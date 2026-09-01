#!/usr/bin/env python3
"""Require the landing candidate to be the candidate an external round reviewed.

The dual-track ledger is caller-built and caller-run. Nothing at merge time read
it, so which candidate the rounds actually inspected was unchecked: a chain could
close out on the pre-fix candidate while a different tree merged. This gate closes
that gap from the merge side.

The reviewed identity is the packet the controller froze, so this recomputes that
packet with the controller's own `freeze_packet` rather than a second
implementation of the same bytes -- two implementations of one hash drift, and the
drift would read as a forged ledger. Evidence lives outside the reviewed paths
(`--paths skills` by default), so committing the ledger cannot change the hash the
ledger records.

Boundaries this gate does NOT close: it cannot prove the caller retained every
earlier chain, and a caller who never ran the wrapper has no receipt to bind here
-- it proves that what merges was reviewed, not that the review was honest.
"""

from __future__ import annotations

import sys

# Importing the controller must not perturb the tree this gate hashes: a written
# __pycache__ lands as an untracked binary file inside the reviewed paths and the
# packet freeze then fails on it. Set before any import that can write bytecode.
sys.dont_write_bytecode = True

import argparse
import hashlib
import importlib.util
import json
import subprocess
import time
import types
from pathlib import Path

VALIDATOR = "validate_extraction_review_state.py"
CONTROLLER = Path("skills") / "code-review" / "scripts" / "review_gate.py"
DEFAULT_PATHS = ("skills",)


def emit(message: str) -> None:
    print(message, file=sys.stderr)


def load_controller(repo_root: Path) -> types.ModuleType:
    controller_path = repo_root / CONTROLLER
    if not controller_path.is_file():
        raise SystemExit(
            f"review_ledger_binding_error: controller not found at {controller_path}"
        )
    spec = importlib.util.spec_from_file_location(
        "ccl_review_gate_for_binding", controller_path
    )
    if spec is None or spec.loader is None:
        raise SystemExit("review_ledger_binding_error: controller is not importable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def changed_skill_paths(repo_root: Path, base: str, paths: tuple[str, ...]) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "diff", "--name-only", base, "--", *paths],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"review_ledger_binding_error: cannot diff against {base}: {result.stderr.strip()}"
        )
    return [line for line in result.stdout.splitlines() if line]


def candidate_hash(module: types.ModuleType, repo_root: Path, base: str, paths: tuple[str, ...]) -> str:
    args = argparse.Namespace(
        cwd=str(repo_root),
        diff_file=None,
        base=base,
        paths=list(paths),
        wording_only_proof_file=None,
    )
    packet_path, packet_sha256, _paths, _secrets = module.freeze_packet(
        args, time.monotonic() + 120
    )
    try:
        Path(packet_path).unlink(missing_ok=True)
    except OSError:
        pass
    return packet_sha256


def validator_accepts(validator: Path, ledger_path: Path) -> tuple[bool, str]:
    result = subprocess.run(
        [sys.executable, str(validator), str(ledger_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
        timeout=60,
    )
    return result.returncode == 0, result.stdout.strip()


def scan(repo_root: Path, evidence_root: str) -> list[tuple[Path, dict]]:
    found: list[tuple[Path, dict]] = []
    root = repo_root / evidence_root
    if not root.is_dir():
        return found
    for path in sorted(root.rglob("*.json")):
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(payload, dict):
            found.append((path, payload))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--base", default=None)
    parser.add_argument("--evidence-root", default="specs")
    parser.add_argument("--paths", nargs="*", default=list(DEFAULT_PATHS))
    parser.add_argument(
        "--print-candidate",
        action="store_true",
        help="print the candidate hash the evidence must bind, then exit",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    base = args.base or ""
    if not base:
        # The gate is base-relative by construction. A bare run with no base is
        # not a pass: it is an unevaluated gate, and reporting it as ok is how a
        # base-relative check becomes decorative.
        emit(
            "review_ledger_binding_skipped: no base ref supplied "
            "(set --base or CCL_SKILL_BASE_REF); gate not evaluated"
        )
        return 0

    paths = tuple(args.paths)
    changed = changed_skill_paths(repo_root, base, paths)
    if not changed and not args.print_candidate:
        print(f"review_ledger_binding_ok: no reviewed-path change against {base}")
        return 0

    module = load_controller(repo_root)
    try:
        expected = candidate_hash(module, repo_root, base, paths)
    except Exception as exc:  # noqa: BLE001 - surface the controller's own message
        emit(f"review_ledger_binding_error: cannot freeze the candidate packet: {exc}")
        return 1

    if args.print_candidate:
        print(expected)
        return 0

    validator = repo_root / "skills" / "skill-extraction-workflow" / "scripts" / VALIDATOR
    ledgers: list[str] = []
    wording_only: list[str] = []
    for path, payload in scan(repo_root, args.evidence_root):
        if payload.get("candidate_sha256") != expected:
            continue
        relative = str(path.relative_to(repo_root))
        if "closeout_state" in payload and "controller_receipts" in payload:
            accepted, output = validator_accepts(validator, path)
            if accepted:
                print(
                    f"review_ledger_binding_ok: {relative} binds the landing candidate "
                    f"({expected[:12]}...) -- {output}"
                )
                return 0
            ledgers.append(f"{relative}: {output}")
        elif payload.get("wording_only_proof_sha256"):
            wording_only.append(relative)

    if wording_only:
        print(
            "review_ledger_binding_ok: wording-only proof binds the landing candidate "
            f"({expected[:12]}...) -- {wording_only[0]}"
        )
        return 0

    emit(
        "review_ledger_binding_failed: no accepted review evidence binds the landing "
        f"candidate {expected}"
    )
    emit(f"  reviewed paths: {' '.join(paths)} against {base}")
    emit(f"  changed files: {len(changed)}")
    for row in ledgers:
        emit(f"  rejected ledger -> {row}")
    if not ledgers:
        emit(
            "  no committed ledger or wording-only proof records this candidate; run the "
            "extraction review lane against the final, committed tree"
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
