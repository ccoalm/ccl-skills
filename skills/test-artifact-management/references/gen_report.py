#!/usr/bin/env python3
"""
gen_report.py — run tests, sync results to Bitable, generate Feishu report.

Usage:
  # First-time setup: parse base_token + table_id from Bitable URL, write config
  python gen_report.py --config .report-config.json \
    --init --bitable-url "https://xxx.feishu.cn/base/BASxxx?table=tblxxx"

  # Run tests + update Bitable + generate report — local, zero extra args:
  python gen_report.py --run-tests

  # CI — only --as bot needed (source/author/version auto-detected):
  python gen_report.py --run-tests --as bot

  # Skip running tests; read existing result files → Bitable → report:
  python gen_report.py

  # Preview report Markdown without writing to Feishu:
  python gen_report.py --dry-run

  # Override any default explicitly:
  python gen_report.py --run-tests --author "张三" --version "v1.2.3"

Config file (.report-config.json, committed to repo; no secrets):
  {
    "base_token": "",         ← auto-populated by --init
    "table_id": "",           ← auto-populated by --init
    "folder_token": "",       ← optional: Feishu folder for first doc creation
    "report_doc_url": "",     ← auto-populated after first report run; commit this
    "test_suites": [
      {
        "name": "API tests",
        "command": "pytest tests/api/ --junit-xml=results/api.xml -q",
        "results_file": "results/api.xml"
      },
      {
        "name": "Go service",
        "command": "go test ./... -v 2>&1 | go-junit-report -set-exit-code > results/go.xml",
        "results_file": "results/go.xml"
      }
    ]
  }

TC ID linking: tests register their TC IDs via a small per-stack helper that appends
to test/results/tc-map.jsonl (one JSON line per call):
  Python: from tc import tc;            def test_login(): tc("TC-SY-001"); ...
  Go:     import "yourrepo/testkit/tc"; func TestLogin(t *testing.T) { tc.Mark(t, "TC-SY-001"); ... }
  JS/TS:  import { tc } from './tc';    test('login', () => { tc('TC-SY-001'); ... })
  Dart:   tc(['TC-SY-001'], 'login', () { ... })
gen_report.py joins JUnit <testcase> name → sidecar entry → TC IDs.
See references/tc-marker-conventions.md.

Tests not registered in the sidecar are excluded from Bitable sync — by design.
Unit/boundary/internal tests don't need TC IDs; only TC-linked tests participate
in status aggregation and the Feishu report.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs


DATE_TODAY = datetime.now().strftime("%Y-%m-%d")

_CI_ENV_VARS = ("CI", "GITHUB_ACTIONS", "GITLAB_CI", "CIRCLECI", "JENKINS_URL",
                "BUILDKITE", "TF_BUILD", "CODEBUILD_BUILD_ID")


def _default_config() -> str:
    # Prefer test/.report-config.json (template convention); fall back to root
    if Path("test/.report-config.json").exists():
        return "test/.report-config.json"
    return ".report-config.json"


def _default_source() -> str:
    return "CI" if any(os.environ.get(v) for v in _CI_ENV_VARS) else "本地"


def _default_author() -> str:
    result = subprocess.run(
        ["git", "config", "user.name"], capture_output=True, text=True
    )
    name = result.stdout.strip()
    return name if name else os.environ.get("USER", "CI")


def _default_version() -> str:
    result = subprocess.run(
        ["git", "describe", "--tags", "--always", "--dirty"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def _default_identity() -> str:
    return "bot" if any(os.environ.get(v) for v in _CI_ENV_VARS) else "user"


# ── Test runner ────────────────────────────────────────────────────────────────

def run_suite(suite: dict) -> bool:
    """Run one test suite command. Returns True if exit code == 0."""
    name = suite.get("name", suite["command"])
    print(f"  Running: {name}", file=sys.stderr)
    result = subprocess.run(suite["command"], shell=True)
    if result.returncode != 0:
        print(f"  ⚠ Suite '{name}' exited {result.returncode} (failures recorded in results file)",
              file=sys.stderr)
    return result.returncode == 0


# ── TC ID extraction (sidecar JSONL) ──────────────────────────────────────────

def load_sidecar(sidecar_path: Path) -> dict[str, list[str]]:
    """
    Load test-name → tc_ids mapping from a JSONL sidecar.
    Each line: {"test": "<name>", "tc_ids": ["TC-XX-NNN", ...]}.
    Multiple entries for the same test name are MERGED (union of TC IDs, first-seen
    order preserved). This supports combining marker-form + in-body-form registration
    on the same test without losing IDs from either path.

    Missing/unreadable file → empty mapping (not an error).
    """
    mapping: dict[str, list[str]] = {}
    if not sidecar_path.exists():
        return mapping
    try:
        for raw in sidecar_path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            test = entry.get("test", "")
            ids = entry.get("tc_ids", [])
            if not test or not ids:
                continue
            normalised = [tc_id.replace("_", "-") for tc_id in ids]
            if test not in mapping:
                mapping[test] = list(normalised)
                continue
            existing = mapping[test]
            seen = set(existing)
            for tc_id in normalised:
                if tc_id not in seen:
                    existing.append(tc_id)
                    seen.add(tc_id)
    except OSError:
        pass
    return mapping


def _candidate_keys(classname: str, name: str) -> list[str]:
    """Build possible sidecar lookup keys from a JUnit testcase element."""
    keys = [name]
    if classname:
        keys.extend([
            f"{classname}::{name}",
            f"{classname}.{name}",
            # pytest classname looks like "tests.test_auth"; nodeid uses "tests/test_auth.py"
            f"{classname.replace('.', '/')}.py::{name}",
            f"{classname.replace('.', '/')}::{name}",
        ])
    return keys


def _extract_tc_ids(tc_el: ET.Element, sidecar: dict[str, list[str]]) -> list[str]:
    """
    Return TC IDs for a JUnit testcase, looked up in the sidecar.
    Tries common name forms (name, classname::name, classname.name, pytest nodeid).
    Tests not in the sidecar are silently excluded — by design.
    """
    classname = tc_el.get("classname", "")
    name = tc_el.get("name", "")
    for key in _candidate_keys(classname, name):
        if key in sidecar:
            return sidecar[key]
    return []


def _junit_status(tc_el: ET.Element) -> str:
    """Map JUnit testcase element to Bitable status string."""
    skipped = tc_el.find("skipped")
    if skipped is not None:
        # Pytest @skip with environment reason → 阻塞 (env not ready, restorable).
        # Otherwise (e.g. @skip("deprecated"), manual exclude) → 跳过.
        msg = (skipped.get("message", "") + " " + (skipped.text or "")).lower()
        env_markers = ("environment", "platform", "windows", "linux", "darwin",
                       "ci only", "requires ", "needs ", "no driver", "no device",
                       "service unavailable", "credential", "fixture not ready")
        if any(m in msg for m in env_markers):
            return "阻塞"
        return "跳过"
    if tc_el.find("failure") is not None or tc_el.find("error") is not None:
        return "失败"
    return "通过"


def parse_junit(results_file: str,
                sidecar: dict[str, list[str]] | None = None) -> dict:
    """
    Parse a JUnit XML file.
    Returns:
      {
        "linked":    {tc_id: status, ...},      # tests registered in sidecar
        "untracked": [{"name", "classname", "status"}, ...]  # tests with no sidecar entry
      }
    A TC appearing in multiple linked tests merges pessimistically:
      失败 > 阻塞 > 跳过 > 通过.
    """
    p = Path(results_file)
    if not p.exists():
        print(f"  ⚠ Results file not found: {results_file} — skipping", file=sys.stderr)
        return {"linked": {}, "untracked": []}

    tree = ET.parse(p)
    root = tree.getroot()
    testcases = root.findall(".//testcase")

    sidecar = sidecar or {}
    tc_results: dict[str, list[str]] = defaultdict(list)
    untracked: list[dict] = []
    for tc_el in testcases:
        status = _junit_status(tc_el)
        ids = _extract_tc_ids(tc_el, sidecar)
        if ids:
            for tc_id in ids:
                tc_results[tc_id].append(status)
        else:
            untracked.append({
                "name": tc_el.get("name", ""),
                "classname": tc_el.get("classname", ""),
                "status": status,
            })

    _rank = {"失败": 4, "阻塞": 3, "跳过": 2, "通过": 1}
    linked: dict[str, str] = {}
    for tc_id, statuses in tc_results.items():
        linked[tc_id] = max(statuses, key=lambda s: _rank.get(s, 0))
    return {"linked": linked, "untracked": untracked}


def _sidecar_path() -> Path:
    """Default sidecar location; override via TC_SIDECAR env."""
    return Path(os.environ.get("TC_SIDECAR", "test/results/tc-map.jsonl"))


def _last_run_path() -> Path:
    """Where the previous run's results snapshot lives (for vs-last-run diff)."""
    return Path(os.environ.get("TC_LAST_RUN", "test/results/last-run.json"))


# ── vs-last-run diff (regression delta) ───────────────────────────────────────

def load_last_run(path: Path) -> dict:
    """Load previous run's snapshot. Returns {} on first run or read error.

    Reads `schema_version` if present; treats older bare-key snapshots as
    cold-start (returns {}). This avoids a false `no_longer_seen` storm
    after the snapshot key format changed (e.g. minimal-mode namespacing
    introduced in v2).
    """
    if not path.exists():
        return {}
    try:
        snap = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    if snap.get("schema_version") != LAST_RUN_SCHEMA_VERSION:
        # Old schema → don't diff against it (would noise-flood the report).
        # Treat as cold start; the next save will write the new schema.
        return {}
    return snap


LAST_RUN_SCHEMA_VERSION = 2


def save_last_run(path: Path, linked: dict[str, str]) -> None:
    """Persist this run's linked results for next time's diff."""
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        snapshot = {
            "schema_version": LAST_RUN_SCHEMA_VERSION,
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "linked": linked,
        }
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError:
        pass


def diff_vs_last_run(current: dict[str, str], previous: dict) -> dict:
    """Compare current vs previous {tc_id: status}. Returns:
      {
        "new_failures":  [tc_id, ...],       # was 通过/跳过/missing, now 失败/阻塞
        "fixed":         [tc_id, ...],       # was 失败/阻塞, now 通过
        "flips":         [{tc_id, from, to}],# other status changes
        "newly_seen":    [tc_id, ...],       # not in previous run at all
        "no_longer_seen":[tc_id, ...],       # in previous run, missing now
        "had_previous":  bool                # False on the very first run
      }
    """
    prev_linked = previous.get("linked", {}) if previous else {}
    if not prev_linked:
        return {"had_previous": False, "new_failures": [], "fixed": [],
                "flips": [], "newly_seen": sorted(current.keys()), "no_longer_seen": []}

    failing = {"失败", "阻塞"}
    passing = {"通过"}

    new_failures: list[str] = []
    fixed: list[str] = []
    flips: list[dict] = []
    newly_seen: list[str] = []
    for tc_id, cur in sorted(current.items()):
        prev = prev_linked.get(tc_id)
        if prev is None:
            newly_seen.append(tc_id)
            if cur in failing:
                new_failures.append(tc_id)
            continue
        if prev == cur:
            continue
        if cur in failing and prev not in failing:
            new_failures.append(tc_id)
        elif prev in failing and cur in passing:
            fixed.append(tc_id)
        else:
            flips.append({"tc_id": tc_id, "from": prev, "to": cur})

    no_longer_seen = sorted(set(prev_linked) - set(current))
    return {"had_previous": True, "new_failures": new_failures, "fixed": fixed,
            "flips": flips, "newly_seen": newly_seen, "no_longer_seen": no_longer_seen}


# ── Code coverage (cobertura.xml) ─────────────────────────────────────────────

def parse_coverage(path: str) -> dict | None:
    """Parse a cobertura.xml. Returns {covered, valid, rate} or None.
    Supports: pytest-cov, go-cover-treemap, jest, vitest --coverage.cobertura."""
    p = Path(path)
    if not p.exists():
        return None
    try:
        root = ET.parse(p).getroot()
    except ET.ParseError:
        return None
    covered = root.get("lines-covered")
    valid = root.get("lines-valid")
    rate = root.get("line-rate")
    if covered and valid:
        c = int(covered)
        v = int(valid)
        return {"covered": c, "valid": v, "rate": c / v if v else 0.0}
    if rate:
        try:
            return {"rate": float(rate)}
        except ValueError:
            return None
    return None


def collect_coverage(suites: list[dict]) -> dict | None:
    """Aggregate coverage across suites. Sums lines when available; falls back
    to mean of rates. Returns None when no suite reports coverage."""
    total_covered = 0
    total_valid = 0
    rates: list[float] = []
    found = False
    for suite in suites:
        cov_path = suite.get("coverage_file", "")
        if not cov_path:
            continue
        parsed = parse_coverage(cov_path)
        if not parsed:
            continue
        found = True
        if "covered" in parsed:
            total_covered += parsed["covered"]
            total_valid += parsed["valid"]
        else:
            rates.append(parsed["rate"])
    if not found:
        return None
    if total_valid > 0:
        return {"covered": total_covered, "valid": total_valid,
                "rate": total_covered / total_valid}
    if rates:
        return {"rate": sum(rates) / len(rates)}
    return None


def _matrix_gate_enabled(suite: dict) -> bool:
    value = suite.get("matrix_gate", True)
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip().lower() not in {"", "0", "false", "no", "off"}
    return bool(value)


def _clear_suite_result_files(suites: list[dict]) -> dict[str, Path]:
    seen: set[str] = set()
    candidates: list[tuple[str, Path]] = []
    for suite in suites:
        rf = suite.get("results_file", "")
        if not rf:
            continue
        path = Path(rf)
        try:
            real_path = str(path.resolve())
        except OSError as exc:
            raise RuntimeError(f"failed to resolve results_file {rf}: {exc}") from exc
        if real_path in seen:
            continue
        seen.add(real_path)
        if not path.exists():
            continue
        if not path.is_file():
            raise RuntimeError(f"results_file is not a file: {rf}")
        candidates.append((rf, path))

    backups: dict[str, Path] = {}
    for rf, path in candidates:
        stamp = datetime.now().strftime("%Y%m%d%H%M%S%f")
        backup = path.with_name(f"{path.name}.pre-gate-bak-{stamp}")
        try:
            path.replace(backup)
        except OSError as exc:
            try:
                _restore_missing_suite_results(backups)
            except RuntimeError as restore_exc:
                raise RuntimeError(
                    f"failed to back up results_file {rf}: {exc}; "
                    f"also failed to restore earlier backups: {restore_exc}"
                ) from exc
            raise RuntimeError(f"failed to back up results_file {rf}: {exc}") from exc
        backups[rf] = backup
    return backups


def _sweep_pre_gate_backups(suites: list[dict]) -> list[str]:
    restored: list[str] = []
    seen: set[str] = set()
    for suite in suites:
        rf = suite.get("results_file", "")
        if not rf:
            continue
        path = Path(rf)
        try:
            real_path = str(path.resolve())
        except OSError as exc:
            raise RuntimeError(f"failed to resolve results_file {rf}: {exc}") from exc
        if real_path in seen:
            continue
        seen.add(real_path)
        backups = sorted(path.parent.glob(f"{path.name}.pre-gate-bak-*"))
        if not backups:
            continue
        newest = backups[-1]
        if path.exists():
            for backup in backups:
                try:
                    backup.unlink()
                except OSError as exc:
                    raise RuntimeError(f"failed to remove stale results_file backup {backup}: {exc}") from exc
            continue
        try:
            newest.replace(path)
        except OSError as exc:
            raise RuntimeError(f"failed to restore orphaned results_file backup {newest}: {exc}") from exc
        restored.append(rf)
        for backup in backups[:-1]:
            try:
                backup.unlink()
            except OSError as exc:
                raise RuntimeError(f"failed to remove stale results_file backup {backup}: {exc}") from exc
    return restored


def _is_fresh_regenerated_result(path: Path, backup: Path) -> bool:
    return path.exists() and backup.exists()


def _restore_missing_suite_results(backups: dict[str, Path]) -> list[str]:
    restored: list[str] = []
    for rf, backup in backups.items():
        path = Path(rf)
        if path.exists():
            if not path.is_file():
                raise RuntimeError(f"results_file is not a file after test run: {rf}")
            if backup.exists():
                if not _is_fresh_regenerated_result(path, backup):
                    try:
                        path.unlink()
                    except OSError as exc:
                        raise RuntimeError(f"failed to remove stale results_file {rf}: {exc}") from exc
                    try:
                        backup.replace(path)
                    except OSError as exc:
                        raise RuntimeError(f"failed to restore results_file {rf}: {exc}") from exc
                    restored.append(rf)
                    continue
                try:
                    backup.unlink()
                except OSError as exc:
                    raise RuntimeError(f"failed to remove results_file backup {backup}: {exc}") from exc
            continue
        if not backup.exists():
            continue
        try:
            backup.replace(path)
        except OSError as exc:
            raise RuntimeError(f"failed to restore results_file {rf}: {exc}") from exc
        restored.append(rf)
    return restored


def _run_suites_and_restore_backups(suites: list[dict], backups: dict[str, Path]) -> tuple[bool, list[str]]:
    suite_failed = False
    restored: list[str] = []
    try:
        for suite in suites:
            if not run_suite(suite):
                suite_failed = True
    finally:
        if backups:
            restored = _restore_missing_suite_results(backups)
    return suite_failed, restored


def collect_results(suites: list[dict], *, parse_excluded: bool = True,
                    stale_result_files: set[str] | None = None) -> dict:
    """
    Merge results from all suites.
    Returns:
      {
        "linked":    {tc_id: status, ...},       # pessimistic merge across suites
        "linked_test_types": {tc_id: test_type, ...},  # optional suite-declared test type
        "tc_layers": {layer: [tc_id, ...]},       # optional suite layer evidence
        "by_test_type": {test_type: {status counts}},  # minimal-report execution-form grouping
        "configured_layers": [layer, ...],        # layers declared in config
        "unlayered_tcs": [tc_id, ...],            # linked TCs from unlabeled suites
        "untracked": [{"name", "classname", "status", "suite"}, ...],
        "missing_files": [path, ...],            # suites configured but no JUnit XML
        "excluded_missing_files": [path, ...],   # matrix_gate:false suites missing XML
        "missing_layered_files": [path, ...],    # layered suites with no JUnit XML
        "missing_layered_layers": [layer, ...],  # gate-participating missing layers
        "excluded_layered_layers": [layer, ...], # matrix_gate:false layer evidence
        "invalid_layer_suites": [{"suite", "layer"}, ...],
        "parsed_suites": int,                    # suites that produced parseable XML
      }
    missing_files lets the gate distinguish:
      - "infra hard-fail" (suites configured, JUnit XML missing) → exit non-zero
      - "no TC linked" (JUnit XML parsed but no sidecar hits) → exit 0 if no fails
    """
    _rank = {"失败": 4, "阻塞": 3, "跳过": 2, "通过": 1}

    sidecar = load_sidecar(_sidecar_path())
    if sidecar:
        print(f"  Sidecar: {len(sidecar)} test → TC mappings loaded from {_sidecar_path()}",
              file=sys.stderr)

    linked: dict[str, str] = {}
    linked_test_types: dict[str, str] = {}
    test_type_conflicts: set[str] = set()
    tc_layers: dict[str, set[str]] = defaultdict(set)
    by_test_type: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    configured_layers: set[str] = set()
    unlayered_tcs: set[str] = set()
    untracked: list[dict] = []
    missing_files: list[str] = []
    excluded_missing_files: list[str] = []
    missing_layered_files: list[str] = []
    missing_layered_layers: set[str] = set()
    excluded_layered_layers: set[str] = set()
    invalid_layer_suites: list[dict] = []
    parsed_suites = 0
    stale_result_files = stale_result_files or set()
    for suite in suites:
        has_layer_key = "layer" in suite
        raw_layer = str(suite.get("layer", "")).strip()
        if not raw_layer:
            has_layer_key = False
        suite_layer = _normalize_layer(raw_layer)
        suite_test_type = _str(suite.get("test_type", "")).strip()
        participates_in_matrix_gate = _matrix_gate_enabled(suite)
        rf = suite.get("results_file", "")
        if has_layer_key and suite_layer not in _MATRIX_ENFORCED_LAYERS:
            invalid_layer_suites.append({
                "suite": suite.get("name", rf),
                "layer": raw_layer,
            })
        if participates_in_matrix_gate and suite_layer in _MATRIX_ENFORCED_LAYERS:
            configured_layers.add(suite_layer)
        if not rf:
            if has_layer_key and participates_in_matrix_gate:
                missing_label = f"{suite.get('name', '<unnamed>')}: results_file missing"
                if suite_layer in _MATRIX_ENFORCED_LAYERS:
                    missing_files.append(missing_label)
                    missing_layered_files.append(missing_label)
                    missing_layered_layers.add(suite_layer)
                print(f"  ⚠ {suite.get('name', '<unnamed>')}: layered suite has no results_file",
                      file=sys.stderr)
            continue
        if not participates_in_matrix_gate and not parse_excluded:
            if suite_layer in _MATRIX_ENFORCED_LAYERS:
                excluded_layered_layers.add(suite_layer)
            if not Path(rf).exists():
                excluded_missing_files.append(rf)
                print(f"  ⚠ {suite.get('name', rf)}: results file missing outside matrix gate: {rf}",
                      file=sys.stderr)
            else:
                print(f"  {suite.get('name', rf)}: skipped outside matrix gate", file=sys.stderr)
            continue
        if rf in stale_result_files or not Path(rf).exists():
            if participates_in_matrix_gate:
                missing_files.append(rf)
            else:
                excluded_missing_files.append(rf)
            if participates_in_matrix_gate and suite_layer in _MATRIX_ENFORCED_LAYERS:
                missing_layered_files.append(rf)
                missing_layered_layers.add(suite_layer)
            if participates_in_matrix_gate:
                reason = "stale pre-gate XML restored" if rf in stale_result_files else "results file missing"
                print(f"  ⚠ {suite.get('name', rf)}: {reason} → suite presumed failed: {rf}",
                      file=sys.stderr)
            else:
                print(f"  ⚠ {suite.get('name', rf)}: results file missing outside matrix gate: {rf}",
                      file=sys.stderr)
            continue
        parsed_suites += 1
        parsed = parse_junit(rf, sidecar)
        suite_name = suite.get("name", rf)
        print(f"  {suite_name}: {len(parsed['linked'])} linked, "
              f"{len(parsed['untracked'])} untracked", file=sys.stderr)
        for tc_id, status in parsed["linked"].items():
            if tc_id not in linked or _rank.get(status, 0) > _rank.get(linked[tc_id], 0):
                linked[tc_id] = status
            if suite_test_type:
                existing_type = linked_test_types.get(tc_id, "")
                if not existing_type:
                    linked_test_types[tc_id] = suite_test_type
                elif existing_type != suite_test_type:
                    linked_test_types[tc_id] = "（多种测试类型）"
                    test_type_conflicts.add(tc_id)
            if participates_in_matrix_gate and suite_layer in _MATRIX_ENFORCED_LAYERS:
                if status == "通过":
                    tc_layers[suite_layer].add(tc_id)
            elif not participates_in_matrix_gate and suite_layer in _MATRIX_ENFORCED_LAYERS:
                if status == "通过":
                    excluded_layered_layers.add(suite_layer)
            elif participates_in_matrix_gate and not has_layer_key:
                if status == "通过":
                    unlayered_tcs.add(tc_id)
        for u in parsed["untracked"]:
            u["suite"] = suite_name
            if suite_test_type:
                u["test_type"] = suite_test_type
            untracked.append(u)
    for tc_id, status in linked.items():
        test_type = linked_test_types.get(tc_id, "")
        if not test_type or test_type == "（多种测试类型）":
            continue
        by_test_type[test_type][status] += 1
        by_test_type[test_type]["_total"] = by_test_type[test_type].get("_total", 0) + 1
    return {"linked": linked, "untracked": untracked,
            "linked_test_types": linked_test_types,
            "test_type_conflicts": sorted(test_type_conflicts),
            "tc_layers": {layer: sorted(tcs) for layer, tcs in sorted(tc_layers.items())},
            "by_test_type": {name: dict(v) for name, v in sorted(by_test_type.items())},
            "configured_layers": sorted(configured_layers),
            "unlayered_tcs": sorted(unlayered_tcs),
            "missing_files": missing_files,
            "excluded_missing_files": excluded_missing_files,
            "missing_layered_files": missing_layered_files,
            "missing_layered_layers": sorted(missing_layered_layers),
            "excluded_layered_layers": sorted(excluded_layered_layers),
            "invalid_layer_suites": invalid_layer_suites,
            "parsed_suites": parsed_suites}


# ── Bitable helpers ────────────────────────────────────────────────────────────

def record_list(base_token: str, table_id: str, identity: str) -> list[dict]:
    """Return all records as ``[{"record_id": str, "fields": {name: value}}]``.

    Parses lark-cli's columnar +record-list response: ``data.data`` is a list of
    rows (each a list of cell values), ``data.fields`` gives the column-name
    order, and ``data.record_id_list`` gives the parallel record ids. Paginates
    via ``has_more``. Raises on CLI failure.
    """
    records: list[dict] = []
    offset = 0
    limit = 200
    while True:
        result = subprocess.run(
            ["lark-cli", "base", "+record-list",
             "--base-token", base_token,
             "--table-id", table_id,
             "--as", identity,
             "--limit", str(limit),
             "--offset", str(offset),
             "--format", "json"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"+record-list failed: {result.stderr.strip()}")
        inner = json.loads(result.stdout).get("data", {})
        cols = inner.get("fields", [])
        rows = inner.get("data", [])
        rids = inner.get("record_id_list", [])
        page = []
        for i, row in enumerate(rows):
            fields = {cols[j]: row[j] for j in range(min(len(cols), len(row)))}
            page.append({
                "record_id": rids[i] if i < len(rids) else "",
                "fields": fields,
            })
        records.extend(page)
        if not page or not inner.get("has_more"):
            break
        offset += len(page)
    return records


def _md_cell(s: str) -> str:
    """Escape a string for safe embedding in a Markdown table cell.
    - `|` → `\\|` so the column separator is preserved (parse_md_table reverses this)
    - all line breaks (`\\r\\n`, `\\n`, lone `\\r` from classic-Mac files) → `<br>`
    """
    if not s:
        return ""
    return (
        s.replace("|", "\\|")
        .replace("\r\n", "<br>")
        .replace("\n", "<br>")
        .replace("\r", "<br>")
    )


def _str(val) -> str:
    """Coerce a Bitable field value to a string.

    Bitable text/rich-text fields are returned as a list of segments. Each
    segment is either a plain string or a dict like ``{"type": "text", "text": "..."}``.
    Single-select fields come back as plain strings; user/link fields come
    back as lists of objects with non-text identifiers.
    """
    if val is None or val == "":
        return ""
    if isinstance(val, list):
        parts: list[str] = []
        for seg in val:
            if isinstance(seg, dict):
                # Text segment: prefer "text" key (rich-text segments)
                t = seg.get("text")
                if isinstance(t, str):
                    parts.append(t)
                    continue
                # Single-select option: {"name": "P0"} / {"text": ...} / {"value": ...}
                for k in ("name", "value"):
                    if isinstance(seg.get(k), str):
                        parts.append(seg[k])
                        break
            elif isinstance(seg, str):
                parts.append(seg)
        return "".join(parts)
    if isinstance(val, dict):
        for k in ("text", "name", "value"):
            if isinstance(val.get(k), str):
                return val[k]
        return ""
    return str(val)


def _info_keep_count() -> int:
    """How many 信息流转 entries to retain when writing (ring buffer; oldest
    entries dropped). Default 100. Set TC_INFO_KEEP=0 for unbounded (caps at
    Bitable's per-cell limit ~10万字符 — your problem to manage)."""
    raw = os.environ.get("TC_INFO_KEEP", "100")
    try:
        n = int(raw)
        return n if n >= 0 else 100
    except ValueError:
        return 100


def _truncate_info(info: str) -> str:
    """Keep only the last N entries (one per non-empty line). 0 = unbounded."""
    n = _info_keep_count()
    if n == 0:
        return info.strip()
    lines = [ln for ln in info.split("\n") if ln.strip()]
    if len(lines) <= n:
        return info.strip()
    return "\n".join(lines[-n:])


def build_index(records: list[dict]) -> dict[str, tuple[str, str]]:
    """Return {tc_id: (record_id, current_status)}. Raises on duplicate tc_id."""
    index: dict[str, tuple[str, str]] = {}
    for rec in records:
        tc_id = _str(rec["fields"].get("用例ID", ""))
        if not tc_id:
            continue
        if tc_id in index:
            raise ValueError(f"Duplicate 用例ID '{tc_id}' in Bitable — fix before syncing")
        status = _str(rec["fields"].get("状态", "未测试")) or "未测试"
        index[tc_id] = (rec["record_id"], status)
    return index


def sync_results_with_append(base_token: str, table_id: str, identity: str,
                              records: list[dict],
                              results: dict[str, str], author: str) -> int:
    """
    Update Bitable statuses and append to 信息流转 (read-then-append, never overwrite).
    Returns count of records updated.
    """
    index = build_index(records)
    # Build record_id → fields map from already-fetched records
    rec_map: dict[str, dict] = {r["record_id"]: r["fields"] for r in records}

    updated = 0
    for tc_id, new_status in results.items():
        if tc_id not in index:
            print(f"  ⚠ {tc_id} not found in Bitable — skipping", file=sys.stderr)
            continue
        record_id, current_status = index[tc_id]
        if current_status == "废弃":
            continue  # deprecated TCs are frozen — automation must not change their status
        if current_status == new_status:
            continue

        # Read 信息流转 from in-memory records (no extra API call); truncate to last N
        current_info = _str(rec_map.get(record_id, {}).get("信息流转", ""))
        entry = f"[{author} {DATE_TODAY}] 自动化测试：{new_status}"
        new_info = _truncate_info((current_info + "\n" + entry).strip())

        result = subprocess.run(
            ["lark-cli", "base", "+record-upsert",
             "--base-token", base_token,
             "--table-id", table_id,
             "--as", identity,
             "--record-id", record_id,
             "--json", json.dumps({"状态": new_status, "信息流转": new_info})],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"  ✗ Failed to update {tc_id}: {result.stderr.strip()}", file=sys.stderr)
        else:
            updated += 1
            # Update in-memory so aggregate uses fresh status
            if record_id in rec_map:
                rec_map[record_id]["状态"] = new_status
                rec_map[record_id]["信息流转"] = new_info
                # Propagate back to records list
                for rec in records:
                    if rec["record_id"] == record_id:
                        rec["fields"]["状态"] = new_status
                        rec["fields"]["信息流转"] = new_info
                        break
    return updated


# ── Unfreeze (废弃 → 未测试 recovery) ─────────────────────────────────────────

def unfreeze_tc(base_token: str, table_id: str, identity: str,
                records: list[dict], tc_ids: list[str], author: str,
                reason: str = "") -> int:
    """Recover one or more TCs from 废弃 back to 未测试.
    Appends a 信息流转 entry recording the recovery. Returns count restored."""
    rec_map: dict[str, dict] = {}
    for r in records:
        case_id = _str(r["fields"].get("用例ID", ""))
        if case_id:
            rec_map[case_id] = r

    restored = 0
    for tc_id in tc_ids:
        if tc_id not in rec_map:
            print(f"  ⚠ {tc_id} not found in Bitable — skipping", file=sys.stderr)
            continue
        rec = rec_map[tc_id]
        current_status = _str(rec["fields"].get("状态", "")) or "未测试"
        if current_status != "废弃":
            print(f"  ⓘ {tc_id} is currently {current_status!r}, not 废弃 — skipping",
                  file=sys.stderr)
            continue
        current_info = _str(rec["fields"].get("信息流转", ""))
        msg = f"误标恢复（{reason}）" if reason else "误标恢复"
        entry = f"[{author} {DATE_TODAY}] {msg}：废弃 → 未测试"
        new_info = _truncate_info((current_info + "\n" + entry).strip())
        result = subprocess.run(
            ["lark-cli", "base", "+record-upsert",
             "--base-token", base_token,
             "--table-id", table_id,
             "--as", identity,
             "--record-id", rec["record_id"],
             "--json", json.dumps({"状态": "未测试", "信息流转": new_info})],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"  ✗ Failed to unfreeze {tc_id}: {result.stderr.strip()}", file=sys.stderr)
        else:
            restored += 1
            rec["fields"]["状态"] = "未测试"
            rec["fields"]["信息流转"] = new_info
    return restored


# ── Matrix validation ─────────────────────────────────────────────────────────

_TC_ID_RE = re.compile(r"TC-[A-Z]+-\d+")
_MATRIX_ENFORCED_LAYERS = {"unit", "contract", "integration", "e2e"}
_ALL_MATRIX_LAYERS = _MATRIX_ENFORCED_LAYERS | {"manual", "blocked"}


def _normalize_layer(layer: str) -> str:
    """Normalize suite/matrix layer names used for optional layer enforcement."""
    value = (layer or "").strip().lower()
    aliases = {
        "api": "contract",
        "api-contract": "contract",
        "integration-contract": "integration",
        "browser": "e2e",
        "host": "e2e",
        "host-smoke": "e2e",
        "device": "e2e",
        "smoke": "e2e",
    }
    return aliases.get(value, value)


def _is_matrix_header(cells: list[str]) -> bool:
    lower = [c.strip().lower() for c in cells]
    if any(_TC_ID_RE.findall(c) for c in cells):
        return False
    layer_count = sum(1 for c in lower if c in _ALL_MATRIX_LAYERS)
    return layer_count >= 1


def parse_matrix_tcs(path: str) -> dict[str, list[str]]:
    """Read test/cases/test-matrix.md; return {layer: [tc_ids]}.

    Format expected (loose): a markdown table whose header row contains
    column names matching one of {unit, contract, integration, e2e, manual,
    blocked}. Each cell is scanned for TC-XX-NNN patterns; non-TC content
    (notes, owners, dashes) is ignored.

    The parser is intentionally lenient — the matrix is human-edited and may
    contain notes / formatting variations.
    """
    p = Path(path)
    if not p.exists():
        return {}
    lines = p.read_text(encoding="utf-8").splitlines()
    headers: list[str] | None = None
    by_layer: dict[str, list[str]] = defaultdict(list)
    for idx, raw in enumerate(lines):
        line = raw.strip()
        if not (line.startswith("|") and line.endswith("|")):
            headers = None
            continue
        cells = _split_md_row(line)
        lower = [c.strip().lower() for c in cells]
        next_line = lines[idx + 1].strip() if idx + 1 < len(lines) else ""
        if headers is not None and _is_matrix_header(cells) and _is_md_separator_row(next_line):
            headers = lower
            continue
        if headers is None:
            if _is_matrix_header(cells):
                headers = lower
            continue
        if all(set(c) <= {"-", ":", " "} for c in cells if c):
            continue
        for col, cell in zip(headers, cells):
            if col not in _ALL_MATRIX_LAYERS:
                continue
            for tc_id in _TC_ID_RE.findall(cell):
                by_layer[col].append(tc_id)
    return dict(by_layer)


def parse_matrix_all_tcs(path: str) -> set[str]:
    p = Path(path)
    if not p.exists():
        return set()
    headers: list[str] | None = None
    all_tcs: set[str] = set()
    non_evidence_headers = {
        "模块", "module", "功能", "feature", "owner", "负责人",
        "notes", "note", "备注", "状态", "status",
    }
    lines = p.read_text(encoding="utf-8").splitlines()
    for idx, raw in enumerate(lines):
        line = raw.strip()
        if not (line.startswith("|") and line.endswith("|")):
            headers = None
            continue
        cells = _split_md_row(line)
        lower = [c.strip().lower() for c in cells]
        next_line = lines[idx + 1].strip() if idx + 1 < len(lines) else ""
        if headers is not None and _is_matrix_header(cells) and _is_md_separator_row(next_line):
            headers = lower
            continue
        if headers is None:
            if _is_matrix_header(cells):
                headers = lower
            continue
        if all(set(c) <= {"-", ":", " "} for c in cells if c):
            continue
        for header, cell in zip(headers, cells):
            if header in non_evidence_headers:
                continue
            all_tcs.update(_TC_ID_RE.findall(cell))
    return all_tcs


def _matrix_has_canonical_header(path: str) -> bool:
    p = Path(path)
    if not p.exists():
        return False
    for raw in p.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not (line.startswith("|") and line.endswith("|")):
            continue
        cells = _split_md_row(line)
        lower = [c.strip().lower() for c in cells]
        if _is_matrix_header(cells):
            return True
    return False


def _matrix_row_shape_error(path: str) -> str:
    p = Path(path)
    if not p.exists():
        return ""
    headers: list[str] | None = None
    lines = p.read_text(encoding="utf-8").splitlines()
    for line_no, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not (line.startswith("|") and line.endswith("|")):
            headers = None
            continue
        cells = _split_md_row(line)
        lower = [c.strip().lower() for c in cells]
        next_line = lines[line_no].strip() if line_no < len(lines) else ""
        if headers is not None and _is_matrix_header(cells) and _is_md_separator_row(next_line):
            headers = lower
            continue
        if headers is None:
            if _is_matrix_header(cells):
                headers = lower
            continue
        if all(set(c) <= {"-", ":", " "} for c in cells if c):
            continue
        if len(cells) > len(headers):
            return f"matrix row {line_no} has {len(cells)} cells; header has {len(headers)}"
    return ""


def parse_matrix_declared_layers(path: str) -> set[str]:
    p = Path(path)
    if not p.exists():
        return set()
    declared: set[str] = set()
    for raw in p.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not (line.startswith("|") and line.endswith("|")):
            continue
        cells = _split_md_row(line)
        if _is_matrix_header(cells):
            declared.update(c.strip().lower() for c in cells if c.strip().lower() in _ALL_MATRIX_LAYERS)
    return declared


def validate_matrix(matrix_path: str, records: list[dict],
                    actual_layers: dict[str, list[str]] | None = None,
                    configured_layers: list[str] | None = None,
                    unlayered_tcs: list[str] | None = None) -> dict:
    """Compare matrix TC IDs vs Bitable active records.
    Returns:
      {
        "in_matrix_not_bitable": [tc_id, ...],  # matrix lists, Bitable doesn't have (or has 废弃)
        "in_bitable_not_matrix": [tc_id, ...],  # active Bitable TCs absent from matrix
        "deprecated_in_matrix":  [tc_id, ...],  # matrix lists, Bitable status is 废弃
        "layer_mismatches":      [{"tc_id", "declared", "actual"}],
        "matrix_tcs_by_layer":   {layer: [tc_id]},
        "actual_tcs_by_layer":   {layer: [tc_id]},
        "configured_layers":     [layer, ...],
        "parse_error":           str,
      }
    """
    matrix = parse_matrix_tcs(matrix_path)
    declared_layers = parse_matrix_declared_layers(matrix_path)
    parse_error = ""
    if not Path(matrix_path).exists():
        parse_error = "matrix file not found"
    elif not matrix and not _matrix_has_canonical_header(matrix_path):
        parse_error = "no canonical matrix layer header found"
    else:
        parse_error = _matrix_row_shape_error(matrix_path)
    all_in_matrix = parse_matrix_all_tcs(matrix_path)

    active: set[str] = set()
    deprecated: set[str] = set()
    for rec in records:
        tc_id = _str(rec["fields"].get("用例ID", ""))
        if not tc_id:
            continue
        status = _str(rec["fields"].get("状态", ""))
        if status == "废弃":
            deprecated.add(tc_id)
        else:
            active.add(tc_id)

    in_matrix_not_bitable = sorted(all_in_matrix - active - deprecated)
    deprecated_in_matrix = sorted(all_in_matrix & deprecated)
    in_bitable_not_matrix = [] if parse_error else sorted(active - all_in_matrix)
    normalized_actual: dict[str, set[str]] = defaultdict(set)
    for layer, tcs in (actual_layers or {}).items():
        normalized = _normalize_layer(layer)
        if normalized not in _MATRIX_ENFORCED_LAYERS:
            continue
        normalized_actual[normalized].update(tcs)
    configured_source = normalized_actual.keys() if configured_layers is None else configured_layers
    configured_normalized = {
        _normalize_layer(layer)
        for layer in configured_source
        if _normalize_layer(layer) in _MATRIX_ENFORCED_LAYERS
    }
    unlayered = set(unlayered_tcs or [])
    unverified_layers = sorted(set(matrix) & _MATRIX_ENFORCED_LAYERS - configured_normalized)

    layer_mismatches: list[dict] = []
    if configured_normalized:
        actual_by_tc: dict[str, set[str]] = defaultdict(set)
        for layer, tcs in normalized_actual.items():
            for tc_id in tcs:
                actual_by_tc[tc_id].add(layer)
        for layer, tcs in sorted(matrix.items()):
            if layer not in configured_normalized:
                continue
            for tc_id in sorted(set(tcs)):
                if tc_id in deprecated or tc_id not in active:
                    continue
                actual = actual_by_tc.get(tc_id, set())
                if layer not in actual:
                    actual_list = sorted(actual)
                    if tc_id in unlayered:
                        actual_list.append("unlabeled-suite")
                    layer_mismatches.append({
                        "tc_id": tc_id,
                        "declared": layer,
                        "actual": actual_list,
                    })

    return {
        "in_matrix_not_bitable": in_matrix_not_bitable,
        "in_bitable_not_matrix": in_bitable_not_matrix,
        "deprecated_in_matrix": deprecated_in_matrix,
        "layer_mismatches": layer_mismatches,
        "matrix_tcs_by_layer": matrix,
        "actual_tcs_by_layer": {layer: sorted(tcs) for layer, tcs in sorted(normalized_actual.items())},
        "configured_layers": sorted(configured_normalized),
        "unverified_layers": unverified_layers,
        "parse_error": parse_error,
    }


def print_matrix_validation(report: dict, results: dict | None = None) -> None:
    a = report["in_matrix_not_bitable"]
    b = report["in_bitable_not_matrix"]
    c = report["deprecated_in_matrix"]
    d = report.get("layer_mismatches", [])
    parse_error = report.get("parse_error", "")
    missing_files = (results or {}).get("missing_files", [])
    missing_layered_files = (results or {}).get("missing_layered_files", [])
    invalid_layer_suites = (results or {}).get("invalid_layer_suites", [])
    by_layer = report["matrix_tcs_by_layer"]
    actual_by_layer = report.get("actual_tcs_by_layer", {})
    configured_layers = report.get("configured_layers", [])
    configured_layer_set = set(configured_layers)
    excluded_layered_layers = sorted(
        (
            set((results or {}).get("excluded_layered_layers", []))
            & (set(by_layer) & _MATRIX_ENFORCED_LAYERS)
        ) - configured_layer_set
    )
    unverified_layers = report.get("unverified_layers", [])
    blocking_unverified_layers = unverified_layers if configured_layers else []
    layer_counts = ", ".join(f"{layer}={len(tcs)}" for layer, tcs in sorted(by_layer.items()))
    print(f"Matrix layers: {layer_counts or '(none parsed)'}")
    if parse_error:
        print(f"Matrix parse error: {parse_error}")
    if configured_layers:
        print(f"Configured suite layers: {', '.join(configured_layers)}")
    if unverified_layers:
        print(f"Unverified matrix layers: {', '.join(unverified_layers)} (no matching suite layer configured)")
    if actual_by_layer:
        actual_counts = ", ".join(f"{layer}={len(tcs)}" for layer, tcs in sorted(actual_by_layer.items()))
        print(f"Actual suite layers: {actual_counts}")
    elif configured_layers:
        print("Actual suite layers: (configured, but no linked TC evidence found)")
    else:
        print("Actual suite layers: (not configured; layer enforcement skipped)")
    if missing_files:
        print(f"Missing JUnit XML: {len(missing_files)} file(s)")
    if missing_layered_files:
        print(f"Missing layered JUnit XML: {len(missing_layered_files)} file(s)")
    if invalid_layer_suites:
        print(f"Invalid suite layer config: {len(invalid_layer_suites)} suite(s)")
    if excluded_layered_layers:
        print(f"Excluded matrix-gate layers still claimed in matrix: {', '.join(excluded_layered_layers)}")
    if not (a or b or c or d or parse_error or blocking_unverified_layers or missing_files or missing_layered_files or invalid_layer_suites or excluded_layered_layers):
        if unverified_layers:
            print("\n⚠ test-matrix.md and Bitable TC presence are in sync; layer coverage is unverified.")
            return
        print("\n✅ test-matrix.md and Bitable are in sync.")
        return
    print(f"\nDrift: +{len(a)} matrix-only, -{len(b)} missing from matrix, ~{len(c)} 废弃-in-matrix, !{len(d)} layer-mismatch")
    if parse_error:
        print("\n⚠ Matrix could not be parsed:")
        print("  Use canonical headers: unit, contract, integration, e2e, manual, blocked.")
    if a:
        print(f"\n⚠ In matrix but NOT in Bitable ({len(a)}):")
        print("  These TC IDs are claimed in the matrix but don't exist in Bitable.")
        print("  Either add to Bitable or remove from matrix.")
        for tc_id in a:
            print(f"    {tc_id}")
    if b:
        print(f"\n⚠ Active in Bitable but NOT in matrix ({len(b)}):")
        print("  Pick a layer for each and add to the matrix.")
        for tc_id in b[:30]:
            print(f"    {tc_id}")
        if len(b) > 30:
            print(f"    ... and {len(b) - 30} more")
    if c:
        print(f"\n⚠ Listed in matrix but 废弃 in Bitable ({len(c)}):")
        print("  Remove from matrix (the TC is permanently retired).")
        for tc_id in c:
            print(f"    {tc_id}")
    if d:
        print(f"\n⚠ Matrix layer claim not covered by configured suite layer ({len(d)}):")
        print("  Either move the TC to the actual layer, add suite layer metadata, add matching test coverage, or mark it manual/blocked with owner.")
        for item in d[:30]:
            actual = ", ".join(item["actual"]) if item["actual"] else "none"
            print(f"    {item['tc_id']}: declared={item['declared']} actual={actual}")
        if len(d) > 30:
            print(f"    ... and {len(d) - 30} more")
    if missing_layered_files:
        print(f"\n⚠ Configured layer suites did not produce JUnit XML ({len(missing_layered_files)}):")
        print("  Run suites first in the same CI job, fix the results_file path, or disable matrix fail mode.")
        for path in missing_layered_files[:10]:
            print(f"    {path}")
        if len(missing_layered_files) > 10:
            print(f"    ... and {len(missing_layered_files) - 10} more")
    elif missing_files:
        print(f"\n⚠ Configured suites did not produce JUnit XML ({len(missing_files)}):")
        print("  Run suites first in the same CI job, or fix the results_file path.")
        for path in missing_files[:10]:
            print(f"    {path}")
        if len(missing_files) > 10:
            print(f"    ... and {len(missing_files) - 10} more")
    if invalid_layer_suites:
        print(f"\n⚠ Invalid suite layer config ({len(invalid_layer_suites)}):")
        print("  Use unit, contract, integration, or e2e (suite aliases such as api/browser normalize).")
        for item in invalid_layer_suites[:10]:
            print(f"    {item.get('suite')}: layer={item.get('layer')}")
        if len(invalid_layer_suites) > 10:
            print(f"    ... and {len(invalid_layer_suites) - 10} more")
    if excluded_layered_layers:
        print("\n⚠ Matrix claims automated layers that are excluded from the matrix gate:")
        print("  Move those TCs to manual/blocked owner rows, or include the suite in the fast gate.")
        for layer in excluded_layered_layers:
            print(f"    {layer}")


def _matrix_validation_has_drift(report: dict) -> bool:
    return bool(
        report.get("in_matrix_not_bitable")
        or report.get("in_bitable_not_matrix")
        or report.get("deprecated_in_matrix")
        or report.get("layer_mismatches")
        or report.get("parse_error")
    )


def _matrix_gate_should_fail(report: dict, results: dict) -> bool:
    missing_files = results.get("missing_files", [])
    missing_gate_layers = set(results.get("missing_layered_layers", []))
    invalid_layer_suites = results.get("invalid_layer_suites", [])
    configured_layers = set(report.get("configured_layers", []))
    excluded_claimed_layers = set(results.get("excluded_layered_layers", [])) & (
        set(report.get("matrix_tcs_by_layer", {})) & _MATRIX_ENFORCED_LAYERS
    ) - configured_layers
    return bool(
        _matrix_validation_has_drift(report)
        or missing_files
        or (report.get("configured_layers") and report.get("unverified_layers"))
        or missing_gate_layers
        or invalid_layer_suites
        or excluded_claimed_layers
    )


# ── md ↔ Bitable diff ─────────────────────────────────────────────────────────

# Fields synced between local md mirror and Bitable (definition fields only).
# 状态/跟进人/信息流转 are Bitable-only — never expected in md.
_MD_DEFINITION_FIELDS = ["模块", "功能点", "优先级", "测试层级", "测试类型", "前置条件", "操作步骤", "预期结果"]


class MdTable(dict):
    """Parsed md mirror rows plus the definition columns declared by its header."""

    def __init__(self, *args, definition_fields_present: set[str] | None = None, **kwargs):
        super().__init__(*args, **kwargs)
        self.definition_fields_present = definition_fields_present


def parse_md_table(path: str) -> dict[str, dict[str, str]]:
    """Parse a Markdown table into {tc_id: {field: value}}.

    Recognises the canonical header: | 用例ID | 模块 | 功能点 | 优先级 | 测试层级 | 测试类型 | 前置条件 | 操作步骤 | 预期结果 |
    (extra columns allowed; only present definition fields are kept, so older
    mirrors without 测试层级/测试类型 don't create false drift). Cells may contain
    escaped pipes (`\\|`) — those are unescaped. Multi-line cells use `<br>` or `\\n`
    inside the cell; line breaks across markdown table rows are not supported.

    Returns empty dict and prints a warning when the file is missing or has no
    recognisable table.
    """
    p = Path(path)
    if not p.exists():
        print(f"  ⚠ md file not found: {path}", file=sys.stderr)
        return MdTable()
    text = p.read_text(encoding="utf-8")

    header_cols: list[str] | None = None
    rows: dict[str, dict[str, str]] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line.startswith("|") or not line.endswith("|"):
            continue
        # split cells; respect \| escape
        cells = _split_md_row(line)
        if header_cols is None:
            if "用例ID" in cells or "ID" in cells:
                header_cols = cells
            continue
        # separator row: |---|---|---|
        if all(set(c) <= {"-", ":", " "} for c in cells if c):
            continue
        if len(cells) < 2:
            continue
        row = dict(zip(header_cols, cells))
        tc_id = (row.get("用例ID") or row.get("ID") or "").strip()
        if not tc_id:
            continue
        fields: dict[str, str] = {}
        for field in _MD_DEFINITION_FIELDS:
            if field not in header_cols:
                continue
            v = row.get(field, "").strip()
            # normalise multi-line conventions: <br> / \n in cell → real \n
            v = v.replace("<br>", "\n").replace("\\n", "\n")
            fields[field] = v
        rows[tc_id] = fields
    if header_cols is None:
        print(f"  ⚠ no markdown table header found in {path}", file=sys.stderr)
        return MdTable(rows)
    present = set(header_cols) & set(_MD_DEFINITION_FIELDS)
    return MdTable(rows, definition_fields_present=present)


def _split_md_row(line: str) -> list[str]:
    """Split a markdown table row by `|`, honoring `\\|` escapes."""
    # remove outer pipes
    body = line.strip()
    if body.startswith("|"): body = body[1:]
    if body.endswith("|"):   body = body[:-1]
    # split on un-escaped |
    cells: list[str] = []
    cur = ""
    i = 0
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body) and body[i + 1] == "|":
            cur += "|"
            i += 2
            continue
        if ch == "|":
            cells.append(cur.strip())
            cur = ""
        else:
            cur += ch
        i += 1
    cells.append(cur.strip())
    return cells


def _is_md_separator_row(line: str) -> bool:
    stripped = line.strip()
    if not (stripped.startswith("|") and stripped.endswith("|")):
        return False
    cells = _split_md_row(stripped)
    return bool(cells) and all(set(c) <= {"-", ":", " "} for c in cells if c)


def _record_to_definition(rec: dict) -> dict[str, str]:
    """Extract Bitable record's definition fields (for diff)."""
    f = rec.get("fields", {})
    out: dict[str, str] = {}
    for field in _MD_DEFINITION_FIELDS:
        v = _str(f.get(field, ""))
        # Bitable text fields sometimes return list-of-segment objects; _str flattens
        out[field] = v.strip()
    return out


def diff_md_vs_bitable(md: dict[str, dict[str, str]],
                       records: list[dict]) -> dict:
    """Compute structural diff between local md mirror and Bitable definition fields.

    Returns:
      {
        "added":   [{tc_id, fields}],          # in md, not in Bitable
        "removed": [{tc_id, fields}],          # in Bitable, not in md (active records only)
        "changed": [{tc_id, field, md, bitable}]
      }
    Deprecated (废弃) Bitable records are excluded from "removed" — they intentionally
    stay in Bitable but may not be in md.
    """
    bitable: dict[str, dict[str, str]] = {}
    deprecated_ids: set[str] = set()
    for rec in records:
        tc_id = _str(rec["fields"].get("用例ID", ""))
        if not tc_id:
            continue
        status = _str(rec["fields"].get("状态", ""))
        if status == "废弃":
            deprecated_ids.add(tc_id)
        bitable[tc_id] = _record_to_definition(rec)

    md_ids = set(md.keys())
    bitable_ids = set(bitable.keys())

    added = []
    for tc_id in sorted(md_ids - bitable_ids):
        added.append({"tc_id": tc_id, "fields": md[tc_id]})

    removed = []
    for tc_id in sorted(bitable_ids - md_ids - deprecated_ids):
        removed.append({"tc_id": tc_id, "fields": bitable[tc_id]})

    changed = []
    md_fields_present = getattr(md, "definition_fields_present", None)
    for tc_id in sorted(md_ids & bitable_ids):
        if tc_id in deprecated_ids:
            continue  # 废弃 records: md mirror may legitimately differ
        for field in _MD_DEFINITION_FIELDS:
            if field not in md[tc_id]:
                if md_fields_present is not None and field not in md_fields_present:
                    continue  # older md mirrors have not opted into this definition column yet
            mv = md[tc_id].get(field, "")
            bv = bitable[tc_id].get(field, "")
            if _normalize_cell(mv) != _normalize_cell(bv):
                changed.append({"tc_id": tc_id, "field": field, "md": mv, "bitable": bv})
    return {"added": added, "removed": removed, "changed": changed}


def _normalize_cell(s: str) -> str:
    """Normalize whitespace for diff comparison (ignore trailing/leading; collapse runs)."""
    return " ".join(s.split())


def print_diff_report(diff: dict) -> None:
    a = diff["added"]; r = diff["removed"]; c = diff["changed"]
    if not (a or r or c):
        print("✅ md and Bitable are in sync (definition fields).")
        return
    print(f"md ↔ Bitable diff: +{len(a)} added, -{len(r)} removed, ~{len(c)} changed")
    if a:
        print(f"\n+ ADDED in md, missing in Bitable ({len(a)}):")
        print("  Create these records via lark-cli base +record-upsert / batch-create.")
        for item in a:
            print(f"    {item['tc_id']}  ({item['fields'].get('模块', '')} / {item['fields'].get('功能点', '')})")
    if r:
        print(f"\n- REMOVED from md, still active in Bitable ({len(r)}):")
        print("  Either re-add to md (md drifted), mark Bitable record 废弃, or delete.")
        for item in r:
            print(f"    {item['tc_id']}  ({item['fields'].get('模块', '')} / {item['fields'].get('功能点', '')})")
    if c:
        print(f"\n~ CHANGED field values ({len(c)}):")
        for item in c:
            md_short = _normalize_cell(item['md'])[:60]
            bt_short = _normalize_cell(item['bitable'])[:60]
            print(f"    {item['tc_id']}  [{item['field']}]")
            print(f"      md      : {md_short}")
            print(f"      Bitable : {bt_short}")


# ── Inventory dump (for iteration delta workflow) ─────────────────────────────

def print_inventory(records: list[dict], as_md: bool = False) -> None:
    """Print current Bitable TC inventory grouped by 模块.

    Two formats:
      - default: human-readable list (per module: 用例ID 功能点 [优先级])
      - --inventory-md: full md table (compatible with --diff-md)

    Deprecated records are listed in a separate section so iteration planning
    can see what was retired without conflating with active TCs.
    """
    active: dict[str, list[dict]] = defaultdict(list)
    deprecated: dict[str, list[dict]] = defaultdict(list)
    for rec in records:
        f = rec.get("fields", {})
        case_id = _str(f.get("用例ID", ""))
        if not case_id:
            continue
        module = _str(f.get("模块", "（未分模块）")) or "（未分模块）"
        status = _str(f.get("状态", ""))
        bucket = deprecated if status == "废弃" else active
        bucket[module].append(rec)

    if as_md:
        # md table format (matches parse_md_table expected schema)
        print("| 用例ID | 模块 | 功能点 | 优先级 | 测试层级 | 测试类型 | 前置条件 | 操作步骤 | 预期结果 |")
        print("|---|---|---|---|---|---|---|---|---|")
        rows = []
        for module in sorted(active):
            for rec in active[module]:
                f = rec["fields"]
                row = [
                    _md_cell(_str(f.get("用例ID", ""))),
                    _md_cell(module),
                    _md_cell(_str(f.get("功能点", ""))),
                    _md_cell(_str(f.get("优先级", ""))),
                    _md_cell(_str(f.get("测试层级", ""))),
                    _md_cell(_str(f.get("测试类型", ""))),
                    _md_cell(_str(f.get("前置条件", ""))),
                    _md_cell(_str(f.get("操作步骤", ""))),
                    _md_cell(_str(f.get("预期结果", ""))),
                ]
                rows.append("| " + " | ".join(row) + " |")
        rows.sort()
        for r in rows:
            print(r)
        return

    total = sum(len(v) for v in active.values())
    dep_total = sum(len(v) for v in deprecated.values())
    print(f"# TC Inventory  (active: {total}, 废弃: {dep_total})")
    print()
    for module in sorted(active):
        recs = sorted(active[module], key=lambda r: _str(r["fields"].get("用例ID", "")))
        print(f"## {module}  ({len(recs)} cases)")
        for rec in recs:
            f = rec["fields"]
            case_id = _str(f.get("用例ID", ""))
            feature = _str(f.get("功能点", ""))
            priority = _str(f.get("优先级", ""))
            status = _str(f.get("状态", "")) or "未测试"
            print(f"  {case_id}  [{priority}] [{status}]  {feature}")
        print()
    if deprecated:
        print("## 废弃记录（不参与统计；新迭代规划时排除）")
        for module in sorted(deprecated):
            for rec in deprecated[module]:
                f = rec["fields"]
                print(f"  {_str(f.get('用例ID', ''))}  [{module}]  {_str(f.get('功能点', ''))}")


# ── Next-ID hint (collision avoidance) ───────────────────────────────────────

def print_next_ids(records: list[dict]) -> None:
    """Print next available TC sequence per module, so parallel devs avoid
    picking the same TC-XX-NNN. Format: TC-{module_abbr}-{NNN}."""
    pattern = re.compile(r"^TC-([A-Z]+)-(\d+)$")
    max_seq: dict[str, int] = {}
    bad: list[str] = []
    for rec in records:
        tc_id = _str(rec["fields"].get("用例ID", ""))
        m = pattern.match(tc_id)
        if not m:
            if tc_id:
                bad.append(tc_id)
            continue
        module, seq = m.group(1), int(m.group(2))
        if seq > max_seq.get(module, 0):
            max_seq[module] = seq
    if not max_seq:
        print("No TC IDs found matching TC-{MODULE}-{NNN} format.")
        return
    print("Next available TC ID per module (use these when creating new TCs):")
    for module in sorted(max_seq):
        next_seq = max_seq[module] + 1
        print(f"  TC-{module}-{next_seq:03d}  (current max: TC-{module}-{max_seq[module]:03d})")
    if bad:
        print("\n⚠ TC IDs not matching the canonical TC-{MODULE}-{NNN} format:")
        for tc_id in bad[:10]:
            print(f"  {tc_id}")
        if len(bad) > 10:
            print(f"  ... and {len(bad) - 10} more")


# ── Orphan detection ──────────────────────────────────────────────────────────

def detect_orphans(records: list[dict], results: dict[str, str]) -> dict:
    """
    Compare TC IDs found in test results against Bitable records.
    Returns:
      deprecated_in_tests: TC IDs in test results that are marked 废弃 in Bitable
      missing_in_bitable:  TC IDs in test results not registered in Bitable at all
    Next step is human judgment:
      - Only prompt for deletion when the underlying code/business is also removed.
      - If the code is still active, take no action by default.
    """
    bitable_status: dict[str, str] = {}
    for rec in records:
        tc_id = _str(rec["fields"].get("用例ID", ""))
        if tc_id:
            bitable_status[tc_id] = _str(rec["fields"].get("状态", "未测试")) or "未测试"

    deprecated = sorted(
        tc_id for tc_id in results if bitable_status.get(tc_id) == "废弃"
    )
    missing = sorted(
        tc_id for tc_id in results if tc_id not in bitable_status
    )
    return {"deprecated_in_tests": deprecated, "missing_in_bitable": missing}


def print_orphan_report(orphans: dict) -> None:
    deprecated = orphans["deprecated_in_tests"]
    missing = orphans["missing_in_bitable"]
    if not deprecated and not missing:
        print("✅ No orphan TC IDs found in test results.")
        return
    if deprecated:
        print(f"\n⚠ Tests with DEPRECATED TC IDs ({len(deprecated)}):")
        print("  Check if underlying code is also removed.")
        print("  If code is gone → delete the test in the same commit.")
        print("  If code still exists → no action needed by default.")
        for tc_id in deprecated:
            print(f"    {tc_id}")
    if missing:
        print(f"\n⚠ Tests with TC IDs NOT in Bitable ({len(missing)}):")
        print("  These TC IDs are in test code but not registered in Bitable.")
        print("  Register the TC or remove the ID from the test function name.")
        for tc_id in missing:
            print(f"    {tc_id}")


# ── Aggregation ────────────────────────────────────────────────────────────────

RELEASE_BLOCKING = {"失败", "阻塞"}


def aggregate(records: list[dict]) -> dict:
    # 废弃记录不参与统计 — 计数但不计入分母
    deprecated_count = sum(
        1 for r in records
        if (_str(r.get("fields", {}).get("状态", "")) == "废弃")
    )
    active = [r for r in records if _str(r.get("fields", {}).get("状态", "")) != "废弃"]
    total = len(active)
    by_status: dict[str, int] = defaultdict(int)
    by_module: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    by_layer: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    by_test_type: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    p0_total = 0
    p0_pass = 0
    failures: list[dict] = []
    p0_blocking: list[dict] = []

    for rec in active:
        f = rec.get("fields", {})
        status = _str(f.get("状态", "未测试")) or "未测试"
        module = _str(f.get("模块", "（未分模块）")) or "（未分模块）"
        layer = _str(f.get("测试层级", "")).strip()
        test_type = _str(f.get("测试类型", "")).strip()
        priority = _str(f.get("优先级", ""))
        case_id = _str(f.get("用例ID", ""))
        feature = _str(f.get("功能点", ""))
        info = _str(f.get("信息流转", ""))
        last_info = info.strip().split("\n")[-1] if info.strip() else ""

        by_status[status] += 1
        by_module[module][status] += 1
        by_module[module]["_total"] = by_module[module].get("_total", 0) + 1
        if layer:
            by_layer[layer][status] += 1
            by_layer[layer]["_total"] = by_layer[layer].get("_total", 0) + 1
        if test_type:
            by_test_type[test_type][status] += 1
            by_test_type[test_type]["_total"] = by_test_type[test_type].get("_total", 0) + 1

        if priority == "P0":
            p0_total += 1
            if status == "通过":
                p0_pass += 1

        if status in RELEASE_BLOCKING:
            entry = {"id": case_id, "module": module, "feature": feature,
                     "status": status, "last_info": last_info, "priority": priority}
            failures.append(entry)
            if priority == "P0":
                p0_blocking.append(entry)

    tested = sum(by_status[s] for s in ["通过", "失败", "阻塞"])
    pass_rate = f"{by_status['通过'] / tested * 100:.1f}%" if tested else "N/A"
    p0_pass_rate = f"{p0_pass / p0_total * 100:.1f}%" if p0_total else "N/A"

    return {
        "total": total,
        "deprecated_count": deprecated_count,
        "by_status": dict(by_status),
        "by_module": {m: dict(v) for m, v in by_module.items()},
        "by_layer": {m: dict(v) for m, v in by_layer.items()},
        "by_test_type": {m: dict(v) for m, v in by_test_type.items()},
        "pass_rate": pass_rate,
        "p0_total": p0_total,
        "p0_pass": p0_pass,
        "p0_pass_rate": p0_pass_rate,
        "failures": failures,
        "p0_blocking": p0_blocking,
    }


# ── Markdown generation ────────────────────────────────────────────────────────

def _untracked_section(untracked: list[dict]) -> list[str]:
    """Build a Markdown section summarizing tests that ran but have no TC link.
    Returns an empty list when there are no untracked tests."""
    if not untracked:
        return []
    counts: dict[str, int] = defaultdict(int)
    for u in untracked:
        counts[u["status"]] += 1
    total = len(untracked)
    by_suite: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for u in untracked:
        s = u.get("suite", "（未分套件）")
        by_suite[s][u["status"]] += 1
        by_suite[s]["_total"] += 1

    lines = [
        "## 未链接 TC 的测试",
        "",
        "说明：这些测试运行但未通过 `tc(\"TC-XX-NNN\")` 关联任何 TC，"
        "常见于单元测试、边界检查、内部不变式 — 属于代码层面质量信号，不计入 Bitable 统计。",
        "",
        "| 指标 | 数量 |",
        "|---|---|",
        f"| 总数 | {total} |",
        f"| 通过 | {counts.get('通过', 0)} |",
        f"| 失败 | {counts.get('失败', 0)} |",
        f"| 阻塞 | {counts.get('阻塞', 0)} |",
        f"| 跳过 | {counts.get('跳过', 0)} |",
        "",
    ]
    if any(counts.get(s, 0) for s in ("失败", "阻塞")):
        lines += [
            "### 未链接 TC 的失败 / 阻塞",
            "",
            "| 套件 | 测试 | 状态 |",
            "|---|---|---|",
        ]
        for u in untracked:
            if u["status"] in ("失败", "阻塞"):
                test_id = (u.get("classname", "") + "::" if u.get("classname") else "") + u.get("name", "")
                lines.append(f"| {_md_cell(u.get('suite', ''))} | {_md_cell(test_id)} | {u['status']} |")
        lines.append("")
    return lines


def build_pr_summary(results: dict, coverage: dict | None,
                      last_run_diff: dict | None) -> str:
    """Build a short Markdown summary suitable for a PR / MR comment.
    Format: 1-line overview + vs-last-run delta. No Bitable fields needed."""
    linked = results.get("linked", {})
    untracked = results.get("untracked", [])
    missing_files = results.get("missing_files", [])
    counts: dict[str, int] = defaultdict(int)
    for s in linked.values():
        counts[s] += 1
    for u in untracked:
        counts[u["status"]] += 1
    total = sum(counts.values())
    passed = counts.get("通过", 0)
    failed = counts.get("失败", 0)
    blocked = counts.get("阻塞", 0)
    skipped = counts.get("跳过", 0)

    lines = ["### 🧪 自动化测试结果", ""]

    # Infra-failure banner FIRST — otherwise "总 0" misleads on red CI where
    # JUnit XML never got written.
    if missing_files:
        lines += [
            f"**🚨 基础设施失败**：{len(missing_files)} 个测试套件未产出 JUnit XML（编译失败 / runner 异常 / 路径错？）",
            "",
            "未产出 XML 的套件：",
        ]
        for path in missing_files[:5]:
            lines.append(f"- `{path}`")
        if len(missing_files) > 5:
            lines.append(f"- ... 另外 {len(missing_files) - 5} 个")
        lines += ["", "下方计数仅反映 *已产出* XML 的套件，不代表全量。", ""]

    parts = [f"通过 **{passed}** / 总 **{total}**"]
    if failed: parts.append(f"❌ 失败 **{failed}**")
    if blocked: parts.append(f"⚠ 阻塞 **{blocked}**")
    if skipped: parts.append(f"⏭ 跳过 {skipped}")
    if coverage:
        r = coverage.get("rate", 0) * 100
        if "covered" in coverage:
            parts.append(f"📊 覆盖率 {r:.1f}% ({coverage['covered']}/{coverage['valid']})")
        else:
            parts.append(f"📊 覆盖率 {r:.1f}%")
    lines.append(" · ".join(parts))
    lines.append("")

    if last_run_diff and last_run_diff.get("had_previous"):
        nf = last_run_diff["new_failures"]
        fx = last_run_diff["fixed"]
        if nf:
            lines += [f"**🔴 本次新增失败 / 阻塞（{len(nf)}）**：", ""]
            for tc_id in nf[:20]:
                lines.append(f"- `{tc_id}`")
            if len(nf) > 20:
                lines.append(f"- ... 另外 {len(nf) - 20} 个")
            lines.append("")
        if fx:
            lines += [f"**🟢 本次修复（{len(fx)}）**：", ""]
            for tc_id in fx[:10]:
                lines.append(f"- `{tc_id}`")
            if len(fx) > 10:
                lines.append(f"- ... 另外 {len(fx) - 10} 个")
            lines.append("")
        if not (nf or fx):
            lines.append("✅ 相比上次运行，无新增失败或修复。")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def build_minimal_markdown(results: dict, author: str, source: str, version: str,
                            coverage: dict | None = None,
                            last_run_diff: dict | None = None) -> str:
    """Minimal report for projects with no Bitable / no TC management.
    Summarizes JUnit XML directly: per-suite counts, optional test-type counts,
    and failure details."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    linked = results["linked"]
    untracked = results["untracked"]
    # Linked tests are treated as untracked here (no Bitable to look up modules).
    all_tests = list(untracked)
    for tc_id, status in linked.items():
        all_tests.append({"name": tc_id, "classname": "(TC-linked)",
                          "status": status, "suite": "（TC-linked）"})

    counts: dict[str, int] = defaultdict(int)
    by_suite: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for u in all_tests:
        counts[u["status"]] += 1
        s = u.get("suite", "（未分套件）")
        by_suite[s][u["status"]] += 1
        by_suite[s]["_total"] += 1

    total = len(all_tests)
    executed = counts.get("通过", 0) + counts.get("失败", 0) + counts.get("阻塞", 0)
    pass_rate = f"{counts.get('通过', 0) / executed * 100:.1f}%" if executed else "N/A"

    ver_str = f" | 版本: {version}" if version else ""
    lines = [
        "# 自动化测试报告",
        "",
        f"> 执行人: {author} | 来源: {source}{ver_str} | 时间: {now}",
        "",
        "## 总览",
        "",
        "| 指标 | 数量 |",
        "|---|---|",
        f"| 测试总数 | {total} |",
        f"| 通过 | {counts.get('通过', 0)} |",
        f"| 失败 | {counts.get('失败', 0)} |",
        f"| 阻塞 | {counts.get('阻塞', 0)} |",
        f"| 跳过 | {counts.get('跳过', 0)} |",
        f"| **通过率（已执行）** | **{pass_rate}** |",
    ]
    lines += _coverage_row(coverage)
    lines.append("")
    lines += _last_run_section(last_run_diff)
    lines += [
        "## 按套件统计",
        "",
        "| 套件 | 总数 | 通过 | 失败 | 阻塞 | 跳过 | 通过率 |",
        "|---|---|---|---|---|---|---|",
    ]
    for suite, c in sorted(by_suite.items()):
        t = c.get("_total", 0)
        passed = c.get("通过", 0)
        failed = c.get("失败", 0)
        blocked = c.get("阻塞", 0)
        skipped = c.get("跳过", 0)
        ex = passed + failed + blocked
        rate = f"{passed / ex * 100:.0f}%" if ex else "—"
        lines.append(f"| {_md_cell(suite)} | {t} | {passed} | {failed} | {blocked} | {skipped} | {rate} |")
    lines.append("")

    if results.get("by_test_type"):
        lines += _dimension_section("## 按测试类型统计", "测试类型", results["by_test_type"])

    failures = [u for u in all_tests if u["status"] in ("失败", "阻塞")]
    if failures:
        lines += [
            "## 失败 / 阻塞明细",
            "",
            "| 套件 | 测试 | 状态 |",
            "|---|---|---|",
        ]
        for u in failures:
            test_id = (u.get("classname", "") + "::" if u.get("classname") else "") + u.get("name", "")
            lines.append(f"| {_md_cell(u.get('suite', ''))} | {_md_cell(test_id)} | {u['status']} |")
        lines.append("")

    lines += ["## 发布建议", ""]
    if counts.get("失败", 0) or counts.get("阻塞", 0):
        lines.append(f"**⚠️ {counts.get('失败', 0)} 失败 + {counts.get('阻塞', 0)} 阻塞** — 需先解决再发布。")
    elif executed == 0:
        lines.append("**未执行测试** — 无法判断。")
    else:
        lines.append("**✅ 全部通过** — 可发布。")
    lines.append("")
    return "\n".join(lines)


def _residual_risk_section(agg: dict, untracked: list[dict] | None,
                            results: dict | None) -> list[str]:
    """Build the "📋 覆盖与残余风险" section.

    Surfaces what's NOT well-covered: modules with no passing TC, untested P0s,
    blocked items + reasons, skipped items + reasons, infra-failed suites.
    The "all green" report can still ship if this section lists important gaps.
    """
    lines = ["## 📋 覆盖与残余风险", ""]
    risks: list[str] = []

    # 1. Modules with active TCs that have ANY 失败/阻塞/未测试
    weak_modules: list[tuple[str, dict]] = []
    for module, counts in (agg.get("by_module") or {}).items():
        bad = counts.get("失败", 0) + counts.get("阻塞", 0) + counts.get("未测试", 0)
        if bad:
            weak_modules.append((module, counts))
    if weak_modules:
        risks.append("### 模块未达「绿色」标准")
        risks.append("")
        risks.append("| 模块 | 总 | 失败 | 阻塞 | 未测试 |")
        risks.append("|---|---|---|---|---|")
        for m, c in sorted(weak_modules):
            risks.append(f"| {_md_cell(m)} | {c.get('_total', 0)} | "
                          f"{c.get('失败', 0)} | {c.get('阻塞', 0)} | {c.get('未测试', 0)} |")
        risks.append("")

    # 2. Untested P0s
    p0_untested = agg.get("p0_total", 0) - agg.get("p0_pass", 0) - \
                   sum(1 for r in (agg.get("p0_blocking") or []) if r.get("priority") == "P0")
    # simpler: count P0s whose status is neither 通过 nor 阻塞/失败 (already in p0_blocking)
    bs = agg.get("by_status", {})
    if agg.get("p0_total", 0) and (agg.get("p0_pass", 0) < agg["p0_total"]):
        not_passing_p0 = agg["p0_total"] - agg.get("p0_pass", 0)
        risks.append(f"### P0 未通过 / 未测试")
        risks.append("")
        risks.append(f"P0 共 {agg['p0_total']} 条，已通过 {agg.get('p0_pass', 0)} 条，"
                      f"**剩余 {not_passing_p0} 条未达通过状态**。详见上方 P0 明细。")
        risks.append("")

    # 3. Infra-failed suites (JUnit XML missing)
    missing_files = (results or {}).get("missing_files") if isinstance(results, dict) else None
    if missing_files:
        risks.append(f"### 🚨 基础设施失败：{len(missing_files)} 个套件无 JUnit XML")
        risks.append("")
        risks.append("以下套件未产出测试结果（编译失败 / runner 异常 / 路径配置错？）。"
                      "上方所有统计仅覆盖 *已产出* XML 的套件。")
        risks.append("")
        for path in missing_files[:10]:
            risks.append(f"- `{path}`")
        if len(missing_files) > 10:
            risks.append(f"- ... 另外 {len(missing_files) - 10} 个")
        risks.append("")

    # 4. Untracked-test failures (tests that ran but have no TC link)
    if untracked:
        bad_untracked = [u for u in untracked if u.get("status") in ("失败", "阻塞")]
        if bad_untracked:
            risks.append(f"### 未链接 TC 但失败的测试（{len(bad_untracked)} 条）")
            risks.append("")
            risks.append("这些测试运行但没关联到任何 TC，所以不影响 Bitable 通过率 — "
                          "但代码层面是真实失败，需修复或登记为 TC。")
            risks.append("")
            for u in bad_untracked[:10]:
                test_id = (u.get("classname", "") + "::" if u.get("classname") else "") + u.get("name", "")
                lines_status = u.get("status", "")
                risks.append(f"- `{_md_cell(test_id)}` → {lines_status}")
            if len(bad_untracked) > 10:
                risks.append(f"- ... 另外 {len(bad_untracked) - 10} 条")
            risks.append("")

    if not risks:
        lines.append("✅ 所有活跃模块均无失败/阻塞/未测试；P0 全部通过；无 infra 失败；无未链接 TC 的失败测试。")
        lines.append("")
    else:
        lines.extend(risks)
    return lines


def _orphans_section(orphans: dict) -> list[str]:
    """Build a Markdown section for orphan TC IDs (deprecated-in-tests + missing-in-Bitable).
    Returns empty list when both are empty."""
    deprecated = orphans.get("deprecated_in_tests", [])
    missing = orphans.get("missing_in_bitable", [])
    if not deprecated and not missing:
        return []
    lines = ["## 孤儿 TC ID", ""]
    if deprecated:
        lines += [
            f"### 测试关联了 `废弃` TC（{len(deprecated)} 条）",
            "",
            "说明：测试代码里调了 `tc(\"<ID>\")` 但 Bitable 该 TC 已废弃。判断：业务代码已删 → 同 commit 删测试；业务代码仍有效 → 不动（可能 TC 提前标废弃）。",
            "",
        ]
        for tc_id in deprecated:
            lines.append(f"- {tc_id}")
        lines.append("")
    if missing:
        lines += [
            f"### 测试关联的 TC 不在 Bitable（{len(missing)} 条）",
            "",
            "说明：测试代码里调了 `tc(\"<ID>\")` 但 Bitable 没这条记录。要么补登 TC，要么从测试里删掉错误的 ID。",
            "",
        ]
        for tc_id in missing:
            lines.append(f"- {tc_id}")
        lines.append("")
    return lines


def _last_run_section(diff: dict | None) -> list[str]:
    """Markdown section for vs-last-run delta. Returns [] when nothing to show."""
    if not diff or not diff.get("had_previous"):
        return []
    nf = diff["new_failures"]
    fx = diff["fixed"]
    fl = diff["flips"]
    nls = diff["no_longer_seen"]
    if not (nf or fx or fl or nls):
        return ["## vs 上次跑", "", "状态与上次完全一致。", ""]
    lines = ["## vs 上次跑", ""]
    if nf:
        lines += [f"### 🔴 新增失败 / 阻塞（{len(nf)}）", ""]
        for tc_id in nf:
            lines.append(f"- {tc_id}")
        lines.append("")
    if fx:
        lines += [f"### 🟢 修复（{len(fx)}）", ""]
        for tc_id in fx:
            lines.append(f"- {tc_id}")
        lines.append("")
    if fl:
        lines += [f"### 状态翻转（{len(fl)}）", "", "| 用例ID | 上次 | 本次 |", "|---|---|---|"]
        for f in fl:
            lines.append(f"| {_md_cell(f['tc_id'])} | {_md_cell(f['from'])} | {_md_cell(f['to'])} |")
        lines.append("")
    if nls:
        lines += [f"### ⚠ 上次有结果但本次未跑（{len(nls)}）", "",
                  "可能 TC 被删、测试被改名或 sidecar 未覆盖。", ""]
        for tc_id in nls:
            lines.append(f"- {tc_id}")
        lines.append("")
    return lines


def _coverage_row(cov: dict | None) -> list[str]:
    """Return markdown table rows for the coverage signal, or [] if absent."""
    if not cov:
        return []
    if "covered" in cov:
        pct = f"{cov['rate'] * 100:.1f}%"
        return [f"| 代码覆盖率 | {pct}（{cov['covered']} / {cov['valid']} 行）|"]
    return [f"| 代码覆盖率 | {cov['rate'] * 100:.1f}% |"]


def _dimension_section(title: str, key_label: str, rows: dict[str, dict[str, int]]) -> list[str]:
    lines = [title, "", f"| {key_label} | 总数 | 通过 | 失败 | 阻塞 | 跳过 | 未测试 | 通过率 |", "|---|---|---|---|---|---|---|---|"]
    for name, counts in sorted(rows.items()):
        total = counts.get("_total", 0)
        passed = counts.get("通过", 0)
        failed = counts.get("失败", 0)
        blocked = counts.get("阻塞", 0)
        skipped = counts.get("跳过", 0)
        untested = counts.get("未测试", 0)
        executed = passed + failed + blocked
        rate = f"{passed / executed * 100:.0f}%" if executed else "—"
        lines.append(f"| {_md_cell(name)} | {total} | {passed} | {failed} | {blocked} | {skipped} | {untested} | {rate} |")
    lines.append("")
    return lines


def build_markdown(agg: dict, author: str, source: str, version: str,
                   auto_count: int = 0, manual_note: str = "",
                   untracked: list[dict] | None = None,
                   orphans: dict | None = None,
                   coverage: dict | None = None,
                   last_run_diff: dict | None = None,
                   results_for_risk: dict | None = None) -> str:
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    bs = agg["by_status"]
    non_p0_failures = [r for r in agg["failures"] if r["priority"] != "P0"]
    lines = []

    ver_str = f" | 版本: {version}" if version else ""
    lines += [
        "# 自动化测试报告",
        "",
        f"> 执行人: {author} | 来源: {source}{ver_str} | 时间: {now}",
        "",
    ]

    lines += [
        "## 总览",
        "",
        "| 指标 | 数量 |",
        "|---|---|",
        f"| 活跃用例 | {agg['total']} |",
        f"| 通过 | {bs.get('通过', 0)} |",
        f"| 失败 | {bs.get('失败', 0)} |",
        f"| 阻塞 | {bs.get('阻塞', 0)} |",
        f"| 跳过 | {bs.get('跳过', 0)} |",
        f"| 未测试 | {bs.get('未测试', 0)} |",
        f"| 废弃（不计入统计）| {agg['deprecated_count']} |",
        f"| **通过率（已执行）** | **{agg['pass_rate']}** |",
        f"| **P0 通过率** | **{agg['p0_pass_rate']}** |",
    ]
    lines += _coverage_row(coverage)
    if auto_count:
        lines.append(f"| 本次自动化更新 | {auto_count} 条 |")
    lines.append("")

    lines += _last_run_section(last_run_diff)

    lines += [
        "## 按模块统计",
        "",
        "| 模块 | 总数 | 通过 | 失败 | 阻塞 | 跳过 | 未测试 | 通过率 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for module, counts in sorted(agg["by_module"].items()):
        t = counts.get("_total", 0)
        passed = counts.get("通过", 0)
        failed = counts.get("失败", 0)
        blocked = counts.get("阻塞", 0)
        skipped = counts.get("跳过", 0)
        untested = counts.get("未测试", 0)
        executed = passed + failed + blocked
        rate = f"{passed / executed * 100:.0f}%" if executed else "—"
        lines.append(f"| {_md_cell(module)} | {t} | {passed} | {failed} | {blocked} | {skipped} | {untested} | {rate} |")
    lines.append("")

    if agg.get("by_layer"):
        lines += _dimension_section("## 按测试层级统计", "测试层级", agg["by_layer"])

    if agg.get("by_test_type"):
        lines += _dimension_section("## 按测试类型统计", "测试类型", agg["by_test_type"])

    if agg["p0_blocking"]:
        lines += [
            "## P0 未通过明细",
            "",
            "| 用例ID | 模块 | 功能点 | 状态 | 最新信息流转 |",
            "|---|---|---|---|---|",
        ]
        for r in agg["p0_blocking"]:
            lines.append(
                f"| {_md_cell(r['id'])} | {_md_cell(r['module'])} | {_md_cell(r['feature'])} | "
                f"{_md_cell(r['status'])} | {_md_cell(r['last_info'])} |"
            )
        lines.append("")
    else:
        lines += ["## P0 未通过明细", "", "无。", ""]

    if non_p0_failures:
        lines += [
            "## 失败 / 阻塞明细（P1/P2）",
            "",
            "| 用例ID | 模块 | 功能点 | 优先级 | 状态 | 最新信息流转 |",
            "|---|---|---|---|---|---|",
        ]
        for r in non_p0_failures:
            lines.append(
                f"| {_md_cell(r['id'])} | {_md_cell(r['module'])} | {_md_cell(r['feature'])} | "
                f"{_md_cell(r['priority'])} | {_md_cell(r['status'])} | {_md_cell(r['last_info'])} |"
            )
        lines.append("")

    if manual_note:
        lines += ["## 手动测试说明", "", manual_note, ""]

    if untracked:
        lines += _untracked_section(untracked)

    if orphans:
        lines += _orphans_section(orphans)

    # Residual-risk section: what's not green-covered, regardless of overall pass rate.
    lines += _residual_risk_section(agg, untracked, results_for_risk)

    # Untested P0s are NOT in p0_blocking (which only tracks 失败/阻塞),
    # but they DO matter for release. A P0 marked 未测试 means we don't know
    # if it works → cannot recommend release.
    p0_untested = agg["p0_total"] - agg["p0_pass"] - len(agg["p0_blocking"])

    lines += ["## 发布建议", ""]
    if agg["p0_blocking"]:
        lines.append(
            f"**❌ 不建议发布** — {len(agg['p0_blocking'])} 个 P0 用例未通过（失败/阻塞），需先解决后再发布。"
        )
    elif p0_untested > 0:
        lines.append(
            f"**❌ 不建议发布** — {p0_untested} 个 P0 用例尚未测试（状态 `未测试`/`跳过`），"
            "无法判断这部分行为正确性。必须先执行后再考虑发布。"
        )
    else:
        if non_p0_failures:
            lines.append(
                f"**⚠️ 可谨慎发布** — P0 全部通过，{len(non_p0_failures)} 个 P1/P2 用例未通过，需评估影响。"
            )
        else:
            lines.append("**✅ 建议发布** — 所有已执行用例通过，无阻塞项。")
    lines.append("")

    return "\n".join(lines)


# ── Feishu doc ─────────────────────────────────────────────────────────────────

def create_doc(title: str, markdown: str, folder_token: str, identity: str) -> str:
    cmd = ["lark-cli", "docs", "+create",
           "--title", title,
           "--as", identity,
           "--markdown", markdown]
    if folder_token:
        cmd += ["--folder-token", folder_token]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"docs +create failed: {result.stderr.strip()}")
    # Prefer JSON parse first; fall back to plain-URL line for human-readable output
    raw = result.stdout.strip()
    url = ""
    try:
        data = json.loads(raw)
        url = data.get("url") or data.get("obj_url") or data.get("data", {}).get("url", "")
    except (json.JSONDecodeError, AttributeError):
        # Look for a line that IS a URL (not JSON containing a URL)
        for line in raw.splitlines():
            line = line.strip()
            if line.startswith("http"):
                url = line
                break
    if not url:
        raise RuntimeError(f"docs +create succeeded but no URL found in output: {raw!r}")
    return url


def update_doc(doc_url: str, markdown: str, identity: str) -> None:
    result = subprocess.run(
        ["lark-cli", "docs", "+update",
         "--doc", doc_url,
         "--as", identity,
         "--mode", "replace_all",
         "--markdown", markdown],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"docs +update failed: {result.stderr.strip()}")


# ── Config helpers ─────────────────────────────────────────────────────────────

def parse_bitable_url(url: str) -> tuple[str, str]:
    parsed = urlparse(url)
    base_token = parsed.path.rstrip("/").split("/")[-1]
    if not re.match(r"^[A-Za-z0-9]{10,}$", base_token):
        raise ValueError(f"Could not parse base_token from URL: {url}")
    qs = parse_qs(parsed.query)
    table_id = (qs.get("table") or [""])[0]
    return base_token, table_id


def fetch_first_table_id(base_token: str, identity: str) -> str:
    # lark-cli +table-list emits JSON by default (no --format flag) and returns
    # data.tables = [{"id", "name"}, ...].
    result = subprocess.run(
        ["lark-cli", "base", "+table-list",
         "--base-token", base_token, "--as", identity],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"+table-list failed: {result.stderr.strip()}")
    tables = json.loads(result.stdout).get("data", {}).get("tables", [])
    if not tables:
        raise RuntimeError("No tables found in this Bitable app")
    tid = tables[0].get("id", "")
    if not tid:
        raise RuntimeError("Could not read table id from +table-list output")
    return tid


def init_config(config_path: str, bitable_url: str, identity: str) -> None:
    base_token, table_id = parse_bitable_url(bitable_url)
    if not table_id:
        print("table_id not in URL — fetching via +table-list...", file=sys.stderr)
        table_id = fetch_first_table_id(base_token, identity)
    p = Path(config_path)
    cfg: dict = {}
    if p.exists():
        with open(p) as f:
            cfg = json.load(f)
    cfg["base_token"] = base_token
    cfg["table_id"] = table_id
    cfg.setdefault("folder_token", "")
    cfg.setdefault("report_doc_url", "")
    cfg.setdefault("test_suites", [])
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"Config written: {config_path}", file=sys.stderr)
    print(f"  base_token: {base_token}", file=sys.stderr)
    print(f"  table_id:   {table_id}", file=sys.stderr)
    print("  Next: add test_suites entries, then run with --run-tests", file=sys.stderr)


def load_config(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(
            f"Config not found: {path}\n"
            "Run: python gen_report.py --config <path> --init [--bitable-url <url>]"
        )
    with open(p) as f:
        cfg = json.load(f)
    # base_token + table_id MUST be both set (Bitable mode) or both empty
    # (minimal mode). A half-populated config is almost always a typo or
    # interrupted --init; failing loud is better than silently falling into
    # minimal mode and skipping all Bitable sync.
    base = bool(cfg.get("base_token"))
    table = bool(cfg.get("table_id"))
    if base != table:
        raise ValueError(
            f"Config {path}: base_token and table_id must both be set (Bitable mode) "
            f"or both empty (minimal mode); got base_token={'set' if base else 'empty'}, "
            f"table_id={'set' if table else 'empty'}. "
            "Re-run --init or edit the config to fix."
        )
    return cfg


def init_minimal_config(config_path: str) -> None:
    """Create a config skeleton without Bitable. test_suites must be filled in."""
    p = Path(config_path)
    cfg: dict = {}
    if p.exists():
        with open(p) as f:
            cfg = json.load(f)
    cfg.setdefault("base_token", "")
    cfg.setdefault("table_id", "")
    cfg.setdefault("folder_token", "")
    cfg.setdefault("report_doc_url", "")
    cfg.setdefault("test_suites", [])
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    print(f"Minimal config written: {config_path}", file=sys.stderr)
    print("  No Bitable — JUnit-only mode.", file=sys.stderr)
    print("  Add test_suites entries; run with --run-tests; report prints to stdout", file=sys.stderr)
    print("  (or set report_doc_url to publish to a Feishu doc).", file=sys.stderr)


def save_doc_url(config_path: str, url: str) -> None:
    p = Path(config_path)
    with open(p) as f:
        cfg = json.load(f)
    cfg["report_doc_url"] = url
    with open(p, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


# ── CI exit gate ──────────────────────────────────────────────────────────────

def _exit_with_gate(args: argparse.Namespace, suite_failed: bool,
                    results: dict, current_snapshot: dict,
                    *, needs_results: bool = True) -> None:
    """Single exit point. Saves the last-run snapshot (non-dry-run only) and
    exits per --fail-on policy.

    `needs_results=False` is for utility modes (--inventory, --next-id, --diff-md,
    --unfreeze) that don't act on test results — missing JUnit XML is just
    "tests not run yet", NOT an infra failure. With this flag set, the gate
    only fires on suite_failed (when --run-tests was used in the same command).

    Snapshot save policy (independent of `--run-tests`, because report-only
    aggregation may parse existing XML without running suites in this process):
      - dry-run → never save
      - utility mode (needs_results=False) → never save
      - missing_files non-empty AND parsed_suites == 0 → INFRA HARD-FAIL:
        preserve baseline (don't overwrite "nothing ran" on top of a good snapshot)
      - otherwise → save (even an empty `linked` from a project with no markers
        yet is a valid baseline)
    """
    if not args.dry_run and needs_results:
        missing = results.get("missing_files", []) if isinstance(results, dict) else []
        parsed = results.get("parsed_suites", 0) if isinstance(results, dict) else 0
        if missing and parsed == 0:
            print("  ⚠ All configured test suites failed to produce JUnit XML — "
                  "treating as infra failure; preserving previous last-run.json",
                  file=sys.stderr)
        else:
            save_last_run(_last_run_path(), current_snapshot)
    if needs_results:
        rc = _compute_exit_code(args.fail_on, suite_failed, results)
    else:
        # Utility mode: only gate on suite execution failure (--run-tests path),
        # NOT on test-result content (a clean checkout with no prior JUnit XML
        # should still let `make inventory` / `--next-id` succeed).
        rc = 1 if suite_failed and args.fail_on != "never" else 0
    if rc:
        print(f"⚠ Exiting non-zero (--fail-on={args.fail_on}): "
              f"suite_failed={suite_failed}, tc-failures or missing results present.",
              file=sys.stderr)
    sys.exit(rc)


def _compute_exit_code(fail_on: str, suite_failed: bool,
                       results: dict | None) -> int:
    """Return the process exit code per --fail-on policy.
       any: suite_failed OR missing JUnit XML OR any failing/blocked TC/untracked
       tc-failures: failing/blocked TC or untracked test only
       suite-only: only suite_failed OR missing JUnit XML
       never: always 0

    `missing_files` (suites configured but JUnit XML absent) counts as a
    suite-level failure — this is how we catch infra hard-fail when tests run
    outside gen_report.py (the Makefile chain).
    """
    if fail_on == "never":
        return 0
    infra_failed = False
    tc_failed = False
    if results and isinstance(results, dict):
        if results.get("missing_files"):
            infra_failed = True
        linked = results.get("linked", {})
        untracked = results.get("untracked", [])
        bad = {"失败", "阻塞"}
        if any(s in bad for s in linked.values()):
            tc_failed = True
        elif any(u.get("status") in bad for u in untracked):
            tc_failed = True
    suite_or_infra = suite_failed or infra_failed
    if fail_on == "suite-only":
        return 1 if suite_or_infra else 0
    if fail_on == "tc-failures":
        return 1 if tc_failed else 0
    return 1 if (suite_or_infra or tc_failed) else 0


# ── Main ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run tests, sync results to Bitable, generate Feishu report",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Most arguments have smart defaults — minimal invocations:\n"
            "  Local:  python gen_report.py --run-tests\n"
            "  CI:     python gen_report.py --run-tests  (--as bot auto-detected)"
        )
    )
    parser.add_argument("--config", default=_default_config(),
                        help="Path to .report-config.json (default: .report-config.json)")
    parser.add_argument("--init", action="store_true",
                        help="First-time setup: parse Bitable URL → write config")
    parser.add_argument("--bitable-url", default="",
                        help="Feishu Bitable URL (required with --init)")
    parser.add_argument("--run-tests", action="store_true",
                        help="Run test_suites commands before syncing results")
    parser.add_argument("--as", dest="identity", default=None,
                        choices=["user", "bot"],
                        help="lark-cli identity (default: bot in CI env, user locally)")
    parser.add_argument("--author", default=None,
                        help="Author for report and 信息流转 (default: git config user.name)")
    parser.add_argument("--source", default=None,
                        help="CI or 本地 (default: auto-detected from env vars)")
    parser.add_argument("--version", default=None,
                        help="Build/version label (default: git describe --tags --always)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print Markdown only, skip Bitable update and Feishu write")
    parser.add_argument("--detect-orphans", action="store_true",
                        help="Surface tests with deprecated/unregistered TC IDs; no auto-delete")
    parser.add_argument("--unfreeze", default="",
                        help="Comma-separated TC IDs to recover from 废弃 → 未测试 (mis-mark recovery)")
    parser.add_argument("--unfreeze-reason", default="",
                        help="Optional reason recorded in 信息流转 when --unfreeze runs")
    parser.add_argument("--next-id", action="store_true",
                        help="Print next available TC sequence number per module (collision prevention)")
    parser.add_argument("--diff-md", default="",
                        help="Compare a local md TC table against Bitable; print added/removed/changed")
    parser.add_argument("--inventory", action="store_true",
                        help="Print current Bitable TC inventory grouped by 模块 (use before iteration TC writing)")
    parser.add_argument("--inventory-md", action="store_true",
                        help="Same as --inventory but emits a md table (pipe to file then --diff-md it)")
    parser.add_argument("--validate-matrix", default=None,
                        help="Path to test/cases/test-matrix.md. Check that every TC ID in the "
                             "matrix exists in Bitable (not 废弃) and every active Bitable TC appears "
                             "in at least one matrix cell. Reports drift; does not modify either.")
    parser.add_argument("--matrix-drift-gate", choices=["warn", "fail"], default="warn",
                        help="With --validate-matrix, fail process on matrix drift only when set to fail")
    parser.add_argument("--pr-summary", action="store_true",
                        help="Print a short PR-comment summary (overview + vs-last-run) to stdout; "
                             "skip Bitable sync and Feishu publish. For CI 'gh pr comment' / GitLab MR notes.")
    parser.add_argument("--fail-on", default="any",
                        choices=["any", "tc-failures", "suite-only", "never"],
                        help="CI gate: process exit code is non-zero when "
                             "any (default: suite OR TC failure/block) / tc-failures (TC failure/block only) / "
                             "suite-only (suite command non-zero) / never (always exit 0)")
    args = parser.parse_args()

    # Apply smart defaults (evaluated lazily to avoid slow git calls when not needed)
    if args.identity is None:
        args.identity = _default_identity()
    if args.author is None:
        args.author = _default_author()
    if args.source is None:
        args.source = _default_source()
    if args.version is None:
        args.version = _default_version()

    # ── Init mode ──────────────────────────────────────────────────────────────
    if args.init:
        if args.bitable_url:
            init_config(args.config, args.bitable_url, args.identity)
        else:
            init_minimal_config(args.config)
        return

    cfg = load_config(args.config)
    base_token = cfg.get("base_token", "")
    table_id = cfg.get("table_id", "")
    folder_token = cfg.get("folder_token", "")
    doc_url = cfg.get("report_doc_url", "")
    suites: list[dict] = cfg.get("test_suites", [])
    has_bitable = bool(base_token and table_id)

    if (args.validate_matrix is not None
            and not args.validate_matrix.strip()
            and args.matrix_drift_gate == "fail"):
        print("⚠ Exiting non-zero: --validate-matrix requires a non-empty matrix path in fail mode.",
              file=sys.stderr)
        sys.exit(1)
    if (args.validate_matrix is not None
            and args.matrix_drift_gate == "fail"
            and not has_bitable):
        print("⚠ Exiting non-zero: fail-mode matrix validation requires Bitable config.",
              file=sys.stderr)
        sys.exit(1)

    # ── Run tests ──────────────────────────────────────────────────────────────
    suite_failed = False
    stale_result_files: set[str] = set()
    if args.run_tests:
        suites_to_run = suites
        result_backups: dict[str, Path] = {}
        if args.validate_matrix is not None and args.matrix_drift_gate == "fail":
            suites_to_run = [s for s in suites if _matrix_gate_enabled(s)]
            if not suites_to_run:
                print("⚠ Exiting non-zero: fail-mode matrix validation requires at least one fast-gate test suite.",
                      file=sys.stderr)
                sys.exit(1)
            if not args.dry_run:
                try:
                    restored_orphans = _sweep_pre_gate_backups(suites_to_run)
                    if restored_orphans:
                        print("⚠ Restored orphaned pre-gate JUnit XML backup before running suites:",
                              file=sys.stderr)
                        for path in restored_orphans:
                            print(f"  - {path}", file=sys.stderr)
                    result_backups = _clear_suite_result_files(suites_to_run)
                except RuntimeError as exc:
                    print(f"⚠ Exiting non-zero: {exc}", file=sys.stderr)
                    sys.exit(1)
        if not suites_to_run:
            print("⚠ No test_suites defined in config — skipping test run", file=sys.stderr)
        else:
            print(f"Running {len(suites_to_run)} test suite(s)...", file=sys.stderr)
            try:
                run_failed, restored = _run_suites_and_restore_backups(suites_to_run, result_backups)
                suite_failed = suite_failed or run_failed
            except RuntimeError as exc:
                print(f"⚠ Exiting non-zero: {exc}", file=sys.stderr)
                sys.exit(1)
            if restored:
                suite_failed = True
                stale_result_files.update(restored)
                print("⚠ Restored pre-gate JUnit XML because suites did not regenerate configured results_file:",
                      file=sys.stderr)
                for path in restored:
                    print(f"  - {path}", file=sys.stderr)

    # ── Parse results ──────────────────────────────────────────────────────────
    # Always call collect_results so the dict has the full schema (linked,
    # untracked, missing_files, parsed_suites) — keeps downstream consumers
    # from having to .get() with defaults.
    parse_excluded_results = not (
        args.validate_matrix is not None
        and args.matrix_drift_gate == "fail"
    )
    results: dict = collect_results(
        suites,
        parse_excluded=parse_excluded_results,
        stale_result_files=stale_result_files,
    )
    coverage: dict | None = collect_coverage(suites) if suites else None
    if coverage:
        r = coverage.get("rate", 0)
        print(f"  Code coverage: {r * 100:.1f}%", file=sys.stderr)

    # ── vs-last-run diff (also persists this run for next time) ─────────────
    previous = load_last_run(_last_run_path())
    if has_bitable:
        # Bitable mode: keys are TC IDs only (no namespace prefix needed)
        current_snapshot = dict(results["linked"])
    else:
        # Minimal mode: combine linked + untracked but PREFIX each identity
        # with its namespace so the diff doesn't mix TC IDs and test paths
        # (e.g. starting/stopping use of sidecar mappings won't generate
        # phantom newly_seen / no_longer_seen).
        current_snapshot = {f"tc::{tc_id}": status
                             for tc_id, status in results["linked"].items()}
        for u in results["untracked"]:
            ident = (u.get("classname", "") + "::" if u.get("classname") else "") + u.get("name", "")
            if ident:
                current_snapshot[f"test::{ident}"] = u["status"]
    last_run_diff = diff_vs_last_run(current_snapshot, previous) if current_snapshot or previous else None

    # ── PR-summary mode (CI integration) ────────────────────────────────────
    if args.pr_summary:
        print(build_pr_summary(results, coverage, last_run_diff))
        _exit_with_gate(args, suite_failed, results, current_snapshot)

    # ── Minimal mode (no Bitable) ──────────────────────────────────────────────
    if not has_bitable:
        if args.detect_orphans:
            print("--detect-orphans requires Bitable config (base_token + table_id).",
                  file=sys.stderr)
            _exit_with_gate(args, suite_failed, results, current_snapshot)
        markdown = build_minimal_markdown(results, args.author, args.source, args.version,
                                           coverage=coverage, last_run_diff=last_run_diff)
        if args.dry_run or not doc_url:
            print(markdown)
        else:
            print(f"Updating report doc: {doc_url}", file=sys.stderr)
            update_doc(doc_url, markdown, args.identity)
            print(f"Updated: {doc_url}")
        _exit_with_gate(args, suite_failed, results, current_snapshot)

    # ── Bitable mode ──────────────────────────────────────────────────────────
    print("Reading Bitable records...", file=sys.stderr)
    records = record_list(base_token, table_id, args.identity)
    print(f"  {len(records)} records loaded", file=sys.stderr)

    if args.next_id:
        print_next_ids(records)
        _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)

    if args.inventory or args.inventory_md:
        print_inventory(records, as_md=args.inventory_md)
        _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)

    if args.diff_md:
        md = parse_md_table(args.diff_md)
        if not md:
            print("No TCs parsed from md; nothing to diff.", file=sys.stderr)
            _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)
        diff = diff_md_vs_bitable(md, records)
        print_diff_report(diff)
        _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)

    if args.validate_matrix is not None:
        if not args.validate_matrix.strip():
            print("⚠ --validate-matrix is empty; skipping matrix validation.", file=sys.stderr)
            _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)
        if args.matrix_drift_gate == "warn":
            print("⚠ report-only: matrix drift is printed but does not affect exit code.", file=sys.stderr)
        elif not args.run_tests:
            print("⚠ Exiting non-zero: fail-mode matrix validation requires --run-tests "
                  "in the same gen_report.py invocation to prove JUnit freshness.",
                  file=sys.stderr)
            sys.exit(1)
        report = validate_matrix(
            args.validate_matrix,
            records,
            results.get("tc_layers", {}),
            results.get("configured_layers", []),
            results.get("unlayered_tcs", []),
        )
        print_matrix_validation(report, results)
        if args.matrix_drift_gate == "fail" and _matrix_gate_should_fail(report, results):
            print("⚠ Exiting non-zero: test-matrix drift detected.", file=sys.stderr)
            sys.exit(1)
        _exit_with_gate(
            args,
            suite_failed,
            results,
            current_snapshot,
            needs_results=args.matrix_drift_gate == "fail",
        )

    if args.unfreeze:
        if not args.unfreeze_reason.strip():
            parser.error("--unfreeze requires --unfreeze-reason '<why this 废弃 is being reopened>'")
        ids = [s.strip() for s in args.unfreeze.split(",") if s.strip()]
        restored = unfreeze_tc(base_token, table_id, args.identity,
                                records, ids, args.author, args.unfreeze_reason)
        print(f"Unfroze {restored}/{len(ids)} TC(s).", file=sys.stderr)
        _exit_with_gate(args, suite_failed, results, current_snapshot, needs_results=False)

    if args.detect_orphans:
        if not results["linked"]:
            print("No linked test results — run tests first.", file=sys.stderr)
        else:
            orphans = detect_orphans(records, results["linked"])
            print_orphan_report(orphans)
        _exit_with_gate(args, suite_failed, results, current_snapshot)

    auto_count = 0
    if results["linked"] and not args.dry_run:
        print(f"Syncing {len(results['linked'])} TC results to Bitable...", file=sys.stderr)
        auto_count = sync_results_with_append(
            base_token, table_id, args.identity,
            records, results["linked"], args.author
        )
        print(f"  {auto_count} records updated", file=sys.stderr)
    elif results["linked"] and args.dry_run:
        print(f"  [dry-run] would update {len(results['linked'])} TC results", file=sys.stderr)

    # Orphan detection always runs in Bitable mode; surfaces in report + stderr.
    orphans = detect_orphans(records, results["linked"]) if results["linked"] else \
              {"deprecated_in_tests": [], "missing_in_bitable": []}
    if orphans["deprecated_in_tests"] or orphans["missing_in_bitable"]:
        print_orphan_report(orphans)

    agg = aggregate(records)
    markdown = build_markdown(agg, args.author, args.source, args.version,
                              auto_count=auto_count,
                              untracked=results["untracked"],
                              orphans=orphans,
                              coverage=coverage,
                              last_run_diff=last_run_diff,
                              results_for_risk=results)
    if args.dry_run:
        print(markdown)
    else:
        doc_title = "自动化测试报告"
        if doc_url:
            print(f"Updating report doc: {doc_url}", file=sys.stderr)
            update_doc(doc_url, markdown, args.identity)
            print(f"Updated: {doc_url}")
        else:
            print("Creating report doc...", file=sys.stderr)
            doc_url = create_doc(doc_title, markdown, folder_token, args.identity)
            save_doc_url(args.config, doc_url)
            print(f"Created: {doc_url}")
    _exit_with_gate(args, suite_failed, results, current_snapshot)


if __name__ == "__main__":
    main()
