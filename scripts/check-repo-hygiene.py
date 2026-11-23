#!/usr/bin/env python3
"""Enforce cross-script hygiene invariants across the repository.

Checks four fast, deterministic invariants on tracked repository state:
1. Git environment scrub parity across `scripts/select-affected-tests.py`,
   `skills/code-review/scripts/review_gate.py`, and
   `skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py`.
2. Single-source `display()` usage from `scripts/_repo_text.py` across
   `scripts/check-markdown-links.py`, `scripts/check-public-sanitization.py`,
   `scripts/check-repo-hygiene.py`, and `scripts/check-spec-references.py`.
3. Tracked test-file registration completeness across CI-executed dispatch
   surfaces (`Makefile` `test` closure, `.github/workflows/ci.yml`,
   `test_check_ccl_regressions.sh`, `packages/ccl-skills-npm/package.json`,
   verified parent-suite delegates, and bounded opt-in environment suites).
4. Warning-free compilation (`warnings.simplefilter("error")`) for all tracked
   Python source files outside `specs/` and `MANIFEST.json`-SHA256-sealed
   concluded `eval/evidence/` archives.
"""

from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import warnings
from pathlib import Path

import yaml

sys.dont_write_bytecode = True

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
from _repo_text import display

GIT_ENV_TARGETS = (
    ("scripts/select-affected-tests.py", "_clean_git_env"),
    ("skills/code-review/scripts/review_gate.py", "git_environment"),
    ("skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py", "git_environment"),
)

REQUIRED_GIT_ROUTING_KEYS = frozenset(
    {
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_IMPLICIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_COMMON_DIR",
        "GIT_NAMESPACE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_CEILING_DIRECTORIES",
        "GIT_DISCOVERY_ACROSS_FILESYSTEM",
        "GIT_GRAFT_FILE",
        "GIT_SHALLOW_FILE",
        "GIT_NO_REPLACE_OBJECTS",
        "GIT_REPLACE_REF_BASE",
        "GIT_PREFIX",
        "GIT_INTERNAL_SUPER_PREFIX",
        "GIT_QUARANTINE_PATH",
        "GIT_GLOB_PATHSPECS",
        "GIT_NOGLOB_PATHSPECS",
        "GIT_LITERAL_PATHSPECS",
        "GIT_ICASE_PATHSPECS",
        "GIT_EXTERNAL_DIFF",
        "GIT_DIFF_OPTS",
    }
)
REQUIRED_GIT_CONFIG_KEYS = frozenset(
    {
        "GIT_TEMPLATE_DIR",
        "GIT_CONFIG",
        "GIT_CONFIG_COUNT",
        "GIT_CONFIG_GLOBAL",
        "GIT_CONFIG_SYSTEM",
        "GIT_CONFIG_NOSYSTEM",
        "GIT_CONFIG_PARAMETERS",
    }
)
REQUIRED_GIT_PREFIXES = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")

DISPLAY_HELPER_REL = "scripts/_repo_text.py"
DISPLAY_CALLERS = (
    "scripts/check-markdown-links.py",
    "scripts/check-public-sanitization.py",
    "scripts/check-repo-hygiene.py",
    "scripts/check-spec-references.py",
)

TEST_EXTENSIONS = (".py", ".sh", ".mjs", ".ts", ".js", ".rb")
# Explicit caps prevent allowlists from growing into silent exemptions.
MAX_PARENT_SUITE_DELEGATES = 4
MAX_OPT_IN_ENV_SUITES = 2

PARENT_SUITE_DELEGATES: dict[str, str] = {
    "skills/code-review/scripts/test_abort_leak_readiness.py": (
        "skills/code-review/scripts/test_review_gate_abort_leak.sh"
    ),
}
OPT_IN_ENV_SUITES: dict[str, str] = {
    "scripts/verify-sandbox/test.sh": "test-verify-sandbox",
}

_EVAL_MODULE_RE = re.compile(r"^eval\.test_[A-Za-z0-9_]*$")
_REPO_PATH_TOKEN_RE = re.compile(
    r"^(?:hooks|scripts|skills|eval|packages)/[A-Za-z0-9_./-]+$"
)


def _clean_git_env() -> dict[str, str]:
    scrub = REQUIRED_GIT_ROUTING_KEYS | REQUIRED_GIT_CONFIG_KEYS
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in scrub
        and not k.startswith(REQUIRED_GIT_PREFIXES)
        and k != "GIT_TRACE"
        and not k.startswith(("GIT_TRACE_", "GIT_TRACE2"))
    }
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_SYSTEM"] = os.devnull
    return env


def tracked_paths(root: Path) -> list[str]:
    proc = subprocess.run(
        [
            "git",
            "-c",
            "core.fsmonitor=false",
            "-c",
            "core.hooksPath=/dev/null",
            "-C",
            str(root),
            "ls-files",
            "-z",
        ],
        check=True,
        capture_output=True,
        stdin=subprocess.DEVNULL,
        env=_clean_git_env(),
        timeout=30,
    )
    return [os.fsdecode(item) for item in proc.stdout.split(b"\0") if item]


def is_candidate_test_file(rel: str) -> bool:
    if rel.startswith(("specs/", "eval/evidence/")):
        return False
    name = Path(rel).name
    if not name.endswith(TEST_EXTENSIONS):
        return False
    return (
        name.startswith("test_")
        or name.endswith(
            (
                "_test.py",
                "_test.sh",
                ".test.sh",
                ".test.mjs",
                ".test.ts",
                ".test.js",
                "_test.rb",
            )
        )
        or name in ("test.sh", "test.py")
    )


def _extract_string_tuple(tree: ast.Module, const_name: str) -> tuple[str, ...] | None:
    for node in tree.body:
        targets: list[ast.expr] = []
        value: ast.expr | None = None
        if isinstance(node, ast.Assign):
            targets = list(node.targets)
            value = node.value
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            targets = [node.target]
            value = node.value
        if not any(isinstance(t, ast.Name) and t.id == const_name for t in targets):
            continue
        if not isinstance(value, ast.Tuple):
            return None
        items: list[str] = []
        for elt in value.elts:
            if not isinstance(elt, ast.Constant) or not isinstance(elt.value, str):
                return None
            items.append(elt.value)
        return tuple(items)
    return None


def _function_names_used(tree: ast.Module, func_name: str) -> set[str] | None:
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == func_name:
            return {
                sub.id
                for sub in ast.walk(node)
                if isinstance(sub, ast.Name) and isinstance(sub.ctx, ast.Load)
            }
    return None


def check_git_env_parity(root: Path) -> list[str]:
    findings: list[str] = []
    observed: dict[str, tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]] = {}
    const_names = (
        "GIT_REPOSITORY_ROUTING_ENV",
        "GIT_CONFIG_ROUTING_ENV",
        "GIT_CONFIG_ROUTING_ENV_PREFIXES",
    )

    for rel, func_name in GIT_ENV_TARGETS:
        target = root / rel
        if target.is_symlink() or not target.is_file():
            findings.append(f"git-env-missing-target: {rel}")
            continue
        try:
            tree = ast.parse(target.read_bytes(), filename=rel)
        except SyntaxError as exc:
            findings.append(f"git-env-parse-error: {rel}:{exc.lineno}: {exc.msg}")
            continue

        extracted: list[tuple[str, ...]] = []
        missing_const = False
        for cname in const_names:
            val = _extract_string_tuple(tree, cname)
            if val is None:
                findings.append(f"git-env-missing-constant: {rel}: {cname}")
                missing_const = True
            else:
                if len(val) != len(set(val)):
                    findings.append(f"git-env-duplicate-entry: {rel}: {cname}")
                extracted.append(val)
        if missing_const:
            continue

        routing_t, config_t, prefix_t = extracted
        overlap = set(routing_t) & set(config_t)
        if overlap:
            findings.append(
                f"git-env-overlapping-constants: {rel}: {', '.join(sorted(overlap))}"
            )

        missing_routing = sorted(REQUIRED_GIT_ROUTING_ENV_DIFF(set(routing_t)))
        if missing_routing:
            findings.append(
                f"git-env-missing-routing-keys: {rel}: {', '.join(missing_routing)}"
            )
        missing_config = sorted(REQUIRED_GIT_CONFIG_KEYS - set(config_t))
        if missing_config:
            findings.append(
                f"git-env-missing-config-keys: {rel}: {', '.join(missing_config)}"
            )
        if tuple(prefix_t) != REQUIRED_GIT_PREFIXES:
            findings.append(
                f"git-env-prefix-mismatch: {rel}: got {prefix_t!r}, expected {REQUIRED_GIT_PREFIXES!r}"
            )

        used_names = _function_names_used(tree, func_name)
        if used_names is None:
            findings.append(f"git-env-missing-function: {rel}: {func_name}")
        else:
            unscrubbed = [c for c in const_names if c not in used_names]
            if unscrubbed:
                findings.append(
                    f"git-env-unscrubbed-constant: {rel}:{func_name} ignores {', '.join(unscrubbed)}"
                )

        observed[rel] = (routing_t, config_t, prefix_t)

    if len(observed) == len(GIT_ENV_TARGETS):
        baseline_rel = GIT_ENV_TARGETS[0][0]
        base_r, base_c, base_p = observed[baseline_rel]
        for rel, _ in GIT_ENV_TARGETS[1:]:
            cur_r, cur_c, cur_p = observed[rel]
            if set(cur_r) != set(base_r):
                diff = sorted(set(cur_r) ^ set(base_r))
                findings.append(
                    f"git-env-routing-drift: {rel} vs {baseline_rel}: {', '.join(diff)}"
                )
            if set(cur_c) != set(base_c):
                diff = sorted(set(cur_c) ^ set(base_c))
                findings.append(
                    f"git-env-config-drift: {rel} vs {baseline_rel}: {', '.join(diff)}"
                )
            if cur_p != base_p:
                findings.append(f"git-env-prefix-drift: {rel} vs {baseline_rel}")

    return findings


def REQUIRED_GIT_ROUTING_ENV_DIFF(actual: set[str]) -> set[str]:
    return set(REQUIRED_GIT_ROUTING_KEYS) - actual


def check_display_sharing(root: Path) -> list[str]:
    findings: list[str] = []
    helper = root / DISPLAY_HELPER_REL
    if helper.is_symlink() or not helper.is_file():
        findings.append(f"display-helper-missing: {DISPLAY_HELPER_REL}")
    else:
        try:
            helper_tree = ast.parse(helper.read_bytes(), filename=DISPLAY_HELPER_REL)
        except SyntaxError as exc:
            findings.append(
                f"display-helper-parse-error: {DISPLAY_HELPER_REL}:{exc.lineno}: {exc.msg}"
            )
        else:
            has_def = any(
                isinstance(n, ast.FunctionDef) and n.name == "display"
                for n in helper_tree.body
            )
            if not has_def:
                findings.append(
                    f"display-helper-missing-def: {DISPLAY_HELPER_REL} must define display()"
                )

    for rel in DISPLAY_CALLERS:
        target = root / rel
        if target.is_symlink() or not target.is_file():
            findings.append(f"display-caller-missing: {rel}")
            continue
        try:
            tree = ast.parse(target.read_bytes(), filename=rel)
        except SyntaxError as exc:
            findings.append(f"display-caller-parse-error: {rel}:{exc.lineno}: {exc.msg}")
            continue

        local_defs = [
            n.lineno
            for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name == "display"
        ]
        if local_defs:
            findings.append(
                f"display-inline-duplicate: {rel}:{local_defs[0]} defines inline display(); import from _repo_text"
            )

        imported = False
        for node in tree.body:
            if isinstance(node, ast.ImportFrom) and node.module in (
                "_repo_text",
                "scripts._repo_text",
            ):
                if any(alias.name == "display" for alias in node.names):
                    imported = True
                    break
        if not imported:
            findings.append(
                f"display-missing-shared-import: {rel} does not import display from _repo_text"
            )

    return findings


def _parse_makefile_targets(makefile_text: str) -> dict[str, tuple[list[str], list[str]]]:
    """Map target name -> (prerequisites, joined_recipe_lines)."""
    targets: dict[str, tuple[list[str], list[str]]] = {}
    lines = makefile_text.splitlines()
    idx = 0
    current_names: list[str] = []
    while idx < len(lines):
        raw = lines[idx]
        idx += 1
        if raw.startswith("\t"):
            buf = [raw[1:]]
            while buf[-1].endswith("\\") and idx < len(lines):
                buf[-1] = buf[-1][:-1]
                nxt = lines[idx]
                idx += 1
                buf.append(nxt[1:] if nxt.startswith("\t") else nxt)
            joined = " ".join(buf).lstrip()
            while joined.startswith(("@", "-", "+")):
                joined = joined[1:].lstrip()
            if joined and not joined.startswith("#"):
                for name in current_names:
                    targets[name][1].append(joined)
            continue

        stripped = raw.strip()
        if not stripped or stripped.startswith(("#", "ifneq", "ifeq", "else", "endif", "export", "unexport")):
            if stripped and not stripped.startswith("#"):
                current_names = []
            continue
        if ":=" in raw or "?=" in raw or "+=" in raw:
            current_names = []
            continue
        if ":" in raw and not raw.startswith("."):
            lhs, rhs = raw.split(":", 1)
            if "=" in lhs:
                current_names = []
                continue
            names = [n.strip() for n in lhs.split() if n.strip()]
            prereq_part = rhs.split("##", 1)[0].strip()
            prereqs = [p for p in prereq_part.split() if p and not p.startswith("$")]
            current_names = names
            for name in names:
                prev_p, prev_r = targets.get(name, ([], []))
                targets[name] = (prev_p + prereqs, prev_r)
        else:
            current_names = []
    return targets


def _extract_paths_from_shell_line(line: str) -> set[str]:
    found: set[str] = set()
    try:
        lex = shlex.shlex(line, posix=True, punctuation_chars=";&|()")
        lex.whitespace_split = True
        lex.commenters = "#"
        tokens = list(lex)
    except ValueError:
        return found
    for tok in tokens:
        if "$" in tok:
            continue
        if _EVAL_MODULE_RE.match(tok):
            found.add(tok.replace(".", "/") + ".py")
            continue
        cleaned = os.path.normpath(tok).replace("\\", "/")
        if _REPO_PATH_TOKEN_RE.match(cleaned):
            found.add(cleaned)
    return found


def check_test_registration(
    root: Path,
    tracked_set: set[str],
    *,
    parent_delegates: dict[str, str] | None = None,
    opt_in_suites: dict[str, str] | None = None,
) -> list[str]:
    findings: list[str] = []
    delegates = PARENT_SUITE_DELEGATES if parent_delegates is None else parent_delegates
    opt_ins = OPT_IN_ENV_SUITES if opt_in_suites is None else opt_in_suites

    if len(delegates) > MAX_PARENT_SUITE_DELEGATES:
        findings.append(
            f"test-registration-cap-exceeded: PARENT_SUITE_DELEGATES has {len(delegates)} > {MAX_PARENT_SUITE_DELEGATES}"
        )
    if len(opt_ins) > MAX_OPT_IN_ENV_SUITES:
        findings.append(
            f"test-registration-cap-exceeded: OPT_IN_ENV_SUITES has {len(opt_ins)} > {MAX_OPT_IN_ENV_SUITES}"
        )

    candidates = sorted(p for p in tracked_set if is_candidate_test_file(p))
    registered: set[str] = set()

    # 1. Makefile `test` target closure
    makefile_path = root / "Makefile"
    make_targets: dict[str, tuple[list[str], list[str]]] = {}
    if makefile_path.is_file() and not makefile_path.is_symlink():
        make_targets = _parse_makefile_targets(
            makefile_path.read_text(encoding="utf-8", errors="replace")
        )
        visited: set[str] = set()
        stack = ["test"] if "test" in make_targets else []
        while stack:
            cur = stack.pop()
            if cur in visited or cur not in make_targets:
                continue
            visited.add(cur)
            prereqs, recipes = make_targets[cur]
            stack.extend(prereqs)
            for recipe in recipes:
                registered.update(_extract_paths_from_shell_line(recipe))

    # 2. .github/workflows/ci.yml active run steps
    ci_path = root / ".github/workflows/ci.yml"
    ci_runs_npm_test = False
    ci_runs_npm_pack = False
    if ci_path.is_file() and not ci_path.is_symlink():
        try:
            ci_doc = yaml.safe_load(ci_path.read_text(encoding="utf-8"))
        except yaml.YAMLError as exc:
            findings.append(f"test-registration-ci-yaml-error: {exc}")
            ci_doc = None
        if isinstance(ci_doc, dict) and isinstance(ci_doc.get("jobs"), dict):
            for job in ci_doc["jobs"].values():
                if not isinstance(job, dict):
                    continue
                if job.get("if") is False or str(job.get("if", "")).strip() == "false":
                    continue
                if job.get("continue-on-error") is True:
                    continue
                steps = job.get("steps")
                if not isinstance(steps, list):
                    continue
                for step in steps:
                    if not isinstance(step, dict) or step.get("continue-on-error") is True:
                        continue
                    if step.get("if") is False or str(step.get("if", "")).strip() == "false":
                        continue
                    run_cmd = step.get("run")
                    if not isinstance(run_cmd, str):
                        continue
                    workdir = str(step.get("working-directory", "")).strip().strip("/")
                    for raw_line in run_cmd.splitlines():
                        stripped = raw_line.strip()
                        if workdir == "packages/ccl-skills-npm":
                            if stripped == "npm test":
                                ci_runs_npm_test = True
                            elif stripped == "npm run test:pack":
                                ci_runs_npm_pack = True
                        registered.update(_extract_paths_from_shell_line(stripped))

    # 3. Regression runner arrays (only when the runner itself is CI/Makefile-dispatched)
    runner_rel = "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh"
    runner_path = root / runner_rel
    if runner_rel in registered and runner_path.is_file() and not runner_path.is_symlink():
        runner_text = runner_path.read_text(encoding="utf-8", errors="replace")
        for arr_name in ("fast_tests", "heavy_tests"):
            match = re.search(rf"^{arr_name}=\((.*?)^\)", runner_text, re.S | re.M)
            if not match:
                findings.append(
                    f"test-registration-runner-parse-error: missing {arr_name} in {runner_rel}"
                )
                continue
            for raw_line in match.group(1).splitlines():
                entry = raw_line.split("#", 1)[0].strip()
                if not entry:
                    continue
                norm = os.path.normpath(
                    f"skills/skill-extraction-workflow/scripts/{entry}"
                ).replace("\\", "/")
                if norm not in tracked_set:
                    findings.append(
                        f"test-registration-missing-runner-entry: {runner_rel} lists untracked {norm}"
                    )
                registered.add(norm)

    # 4. packages/ccl-skills-npm/package.json test & test:pack scripts
    pkg_rel = "packages/ccl-skills-npm/package.json"
    pkg_path = root / pkg_rel
    if pkg_path.is_file() and not pkg_path.is_symlink():
        try:
            pkg_doc = json.loads(pkg_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            findings.append(f"test-registration-package-json-error: {pkg_rel}: {exc}")
            pkg_doc = {}
        scripts_map = pkg_doc.get("scripts") if isinstance(pkg_doc, dict) else {}
        if isinstance(scripts_map, dict):
            active_script_keys: list[str] = []
            if ci_runs_npm_test:
                active_script_keys.append("test")
            if ci_runs_npm_pack:
                active_script_keys.append("test:pack")
            for skey in active_script_keys:
                sval = scripts_map.get(skey)
                if not isinstance(sval, str):
                    continue
                if "test/*.test.mjs" in sval:
                    for cand in candidates:
                        if re.fullmatch(
                            r"packages/ccl-skills-npm/test/[^/]+\.test\.mjs", cand
                        ):
                            registered.add(cand)
                for m in re.finditer(r"(?:scripts|test)/[A-Za-z0-9_.-]+\.mjs", sval):
                    registered.add(f"packages/ccl-skills-npm/{m.group(0)}")

    # 5. Verified parent-suite delegates
    for child, parent in sorted(delegates.items()):
        child_path = root / child
        parent_path = root / parent
        if child not in tracked_set or not child_path.is_file():
            findings.append(f"test-registration-stale-delegate: {child} is not tracked")
            continue
        if parent not in tracked_set or not parent_path.is_file():
            findings.append(
                f"test-registration-stale-delegate: parent {parent} for {child} is not tracked"
            )
            continue
        if parent not in registered:
            findings.append(
                f"test-registration-unregistered-parent: parent {parent} for {child} is not CI-registered"
            )
            continue
        parent_text = parent_path.read_text(encoding="utf-8", errors="replace")
        if Path(child).name not in parent_text:
            findings.append(
                f"test-registration-unreferenced-delegate: {parent} no longer invokes {Path(child).name}"
            )
            continue
        registered.add(child)

    # 6. Bounded opt-in environment-gated suites (e.g. Docker-only target in Makefile)
    for suite, make_target in sorted(opt_ins.items()):
        if suite not in tracked_set or not (root / suite).is_file():
            findings.append(f"test-registration-stale-opt-in: {suite} is not tracked")
            continue
        if make_target not in make_targets:
            findings.append(
                f"test-registration-missing-opt-in-target: Makefile lacks {make_target} for {suite}"
            )
            continue
        _, target_recipes = make_targets[make_target]
        target_paths: set[str] = set()
        for rline in target_recipes:
            target_paths.update(_extract_paths_from_shell_line(rline))
        if suite not in target_paths:
            findings.append(
                f"test-registration-unreferenced-opt-in: Makefile target {make_target} does not run {suite}"
            )
            continue
        registered.add(suite)

    for cand in candidates:
        if cand not in registered:
            findings.append(f"unregistered-test-file: {display(cand)}")

    return findings


def _load_sealed_manifest_hashes(
    root: Path, tracked_set: set[str]
) -> dict[str, str]:
    """Return repo-relative path -> pinned sha256 from tracked eval/evidence/*/MANIFEST.json."""
    sealed: dict[str, str] = {}
    for rel in sorted(tracked_set):
        if not (rel.startswith("eval/evidence/") and rel.endswith("/MANIFEST.json")):
            continue
        mpath = root / rel
        if mpath.is_symlink() or not mpath.is_file():
            continue
        try:
            doc = json.loads(mpath.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(doc, dict):
            continue
        files_sha = doc.get("files_sha256")
        if not isinstance(files_sha, dict):
            continue
        prefix = rel[: -len("MANIFEST.json")]
        for sub_rel, digest in files_sha.items():
            if isinstance(sub_rel, str) and isinstance(digest, str):
                norm = os.path.normpath(prefix + sub_rel).replace("\\", "/")
                if norm.startswith(prefix):
                    sealed[norm] = digest
    return sealed


def check_python_warnings(root: Path, tracked_set: set[str]) -> list[str]:
    findings: list[str] = []
    sealed_hashes = _load_sealed_manifest_hashes(root, tracked_set)

    for rel in sorted(p for p in tracked_set if p.endswith(".py")):
        if rel.startswith("specs/"):
            continue
        target = root / rel
        if target.is_symlink() or not target.is_file():
            continue
        try:
            raw = target.read_bytes()
        except OSError as exc:
            findings.append(f"python-unreadable: {display(rel)}: {display(str(exc))}")
            continue

        expected_sha = sealed_hashes.get(rel)
        if expected_sha is not None:
            actual_sha = hashlib.sha256(raw).hexdigest()
            if actual_sha == expected_sha:
                continue

        with warnings.catch_warnings():
            warnings.simplefilter("error")
            try:
                compile(raw, rel, "exec", dont_inherit=True)
            except (SyntaxError, Warning, ValueError, UnicodeDecodeError) as exc:
                lineno = getattr(exc, "lineno", None)
                loc = f"{display(rel)}:{lineno}" if lineno else display(rel)
                findings.append(
                    f"python-compile-error: {loc}: {type(exc).__name__}: {display(str(exc))}"
                )

    return findings


def run_all_checks(root: Path) -> list[str]:
    root = root.resolve()
    tracked = set(tracked_paths(root))
    findings: list[str] = []
    findings.extend(check_git_env_parity(root))
    findings.extend(check_display_sharing(root))
    findings.extend(check_test_registration(root, tracked))
    findings.extend(check_python_warnings(root, tracked))
    return findings


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    root = Path(args[0] if args else ".").resolve()
    findings = run_all_checks(root)
    if findings:
        for item in findings:
            print(f"repo_hygiene_block: {item}", file=sys.stderr)
        print(f"repo_hygiene_failed: findings={len(findings)}", file=sys.stderr)
        return 1
    print("repo_hygiene_ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
