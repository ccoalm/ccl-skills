#!/usr/bin/env python3
"""Advisory path-based test selector and runner for inner-loop iteration.

Maps changed files (branch diff against merge-base + staged + unstaged + untracked)
to a fast advisory set of repository preflight checks, parallel suites, and serial
commands. Does not replace `make test` or CI lanes before pushing.

Usage:
  python3 scripts/select-affected-tests.py [--repo .] [--base-ref REF] [--dry-run|--json|--run]
"""
from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True

ADVISORY_FOOTER = "advisory: run make test before push"
_JSON_BYTES_PREFIX = "\x00hex:"

GIT_REPOSITORY_ROUTING_ENV = (
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
)
GIT_CONFIG_ROUTING_ENV = (
    "GIT_TEMPLATE_DIR",
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
)
GIT_CONFIG_ROUTING_ENV_PREFIXES = ("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_")

_MAKE_ENV_POLLUTION_KEYS = (
    "MAKEFLAGS",
    "MFLAGS",
    "MAKELEVEL",
    "MAKEOVERRIDES",
    "GNUMAKEFLAGS",
    "-*-command-variables-*-",
    "CCL_SKILL_DEFAULT_BASE_REF",
    "CCL_SKILL_SELECTED_DEFAULT_BASE",
    "AFFECTED_ARGS",
)

# Suites that require dedicated runners, serial isolation, or framework flags and
# therefore must not enter run-parallel-suites.sh via generic self/sibling rules.
DEDICATED_RUNNER_SUITES = frozenset(
    {
        "skills/code-review/scripts/test_review_gate_abort_leak.sh",
        "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh",
        "skills/test-artifact-management/references/test_gen_report.py",
        "scripts/verify-sandbox/test.sh",
    }
)

_DEFAULT_HEAVY_REGRESSION_NAMES = frozenset(
    {
        "test_check_ccl_r0_status.sh",
        "test_entrypoint_domain_scan_terms.sh",
        "test_check_ccl_source_register_lifecycle.sh",
        "test_check_ccl_impact_chain_refscripts.sh",
        "test_register_firing_path_wiring.sh",
        "test_impact_chain_source_refuted.sh",
        "test_impact_chain_gate_verdict_differential.sh",
        "test_impact_chain_self_adjudication.sh",
        "test_pinned_phrase_mutation_walk.sh",
    }
)

_DEFAULT_EVAL_UNITTEST_MODULES = (
    "eval.test_subagent_owner_audit",
    "eval.test_skill_effectiveness_bridge",
    "eval.test_skill_effectiveness_trial",
    "eval.test_reviewer_calibration_protocol",
    "eval.test_design_judge",
)

_MAKEFILE_SUITE_RE = re.compile(
    r"(?<![\w./-])((?:hooks|scripts|skills|eval)/[\w./-]*?(?:test_[\w.-]+|[\w-]+\.test|/test)\.(?:sh|py))(?![\w./-])"
)
_HEX_SHA_RE = re.compile(r"^[0-9a-fA-F]{40,64}$")
_EVAL_MODULE_RE = re.compile(r"^eval\.[A-Za-z_][A-Za-z0-9_]*$")


class SelectorError(Exception):
    """Invalid repository root, base ref, or failed Git discovery."""


class BaseRefError(SelectorError):
    """Base ref could not be resolved or has no usable merge-base with HEAD."""


def _terminal_safe(value: str, *, escape_backslash: bool = False) -> str:
    """Escape surrogates and C0/DEL/C1 terminal controls so output stays single-line and ANSI-free."""
    out: list[str] = []
    for ch in value:
        code = ord(ch)
        if 0xDC80 <= code <= 0xDCFF:
            out.append(f"\\x{code - 0xDC00:02x}")
        elif 0xD800 <= code <= 0xDFFF:
            out.append(f"\\u{code:04x}")
        elif ch == "\\" and escape_backslash:
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or 0x7F <= code <= 0x9F:
            out.append(f"\\x{code:02x}")
        else:
            out.append(ch)
    return "".join(out)


def _comment_line(prefix: str, value: str) -> str:
    return f"# {prefix}{_terminal_safe(value, escape_backslash=True)}"


def _shell_quote(value: str) -> str:
    """Quote an argument for bash replay, preserving arbitrary non-UTF-8 bytes and escaping controls."""
    has_control = any(ord(c) < 0x20 or 0x7F <= ord(c) <= 0x9F for c in value)
    if not has_control:
        try:
            value.encode("utf-8", "strict")
            return shlex.quote(value)
        except UnicodeEncodeError:
            pass
    raw = os.fsencode(value)
    parts = ["$'"]
    for b in raw:
        if b == 0x27:
            parts.append("\\'")
        elif b == 0x5C:
            parts.append("\\\\")
        elif b == 0x0A:
            parts.append("\\n")
        elif b == 0x0D:
            parts.append("\\r")
        elif b == 0x09:
            parts.append("\\t")
        elif 0x20 <= b <= 0x7E:
            parts.append(chr(b))
        else:
            parts.append(f"\\x{b:02x}")
    parts.append("'")
    return "".join(parts)


def encode_json_str(value: str) -> str:
    """Bijectively encode os.fsdecode strings into valid UTF-8 JSON strings."""
    if not value.startswith("\x00"):
        try:
            value.encode("utf-8", "strict")
            return value
        except UnicodeEncodeError:
            pass
    return f"{_JSON_BYTES_PREFIX}{os.fsencode(value).hex()}"


def decode_json_str(value: str) -> str:
    """Inverse of encode_json_str: recover the exact original os.fsdecode string."""
    if value.startswith(_JSON_BYTES_PREFIX):
        return os.fsdecode(bytes.fromhex(value[len(_JSON_BYTES_PREFIX) :]))
    return value


def _json_safe(value):
    if isinstance(value, str):
        return encode_json_str(value)
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, dict):
        return {encode_json_str(str(k)): _json_safe(v) for k, v in value.items()}
    return value


def _clean_git_env(base_env: dict[str, str] | None = None) -> dict[str, str]:
    source = os.environ if base_env is None else base_env
    return {
        k: v
        for k, v in source.items()
        if k not in GIT_REPOSITORY_ROUTING_ENV
        and k not in GIT_CONFIG_ROUTING_ENV
        and not k.startswith(GIT_CONFIG_ROUTING_ENV_PREFIXES)
    }


def _clean_child_env(
    base_env: dict[str, str] | None = None,
    *,
    resolved_base: str | None = None,
    template_dir: Path | None = None,
) -> dict[str, str]:
    """Scrub inherited Git/Make overrides and isolate child Git init/commit from user hooks/templates."""
    env = _clean_git_env(base_env)
    for key in _MAKE_ENV_POLLUTION_KEYS:
        env.pop(key, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_SYSTEM"] = os.devnull
    env["GIT_TERMINAL_PROMPT"] = "0"
    if template_dir is not None:
        env["GIT_TEMPLATE_DIR"] = str(template_dir)
    if resolved_base:
        env["CCL_SKILL_BASE_REF"] = resolved_base
    else:
        env.pop("CCL_SKILL_BASE_REF", None)
    return env


def normalize_input_relpath(raw: str) -> str:
    """Collapse redundant `/` and `.` segments without stripping spaces, backslashes, or `..`."""
    if not raw or "\x00" in raw:
        return raw
    if raw.startswith("/"):
        return raw
    segments = raw.split("/")
    if ".." in segments:
        return "/".join(p for p in segments if p)
    cleaned = [p for p in segments if p and p != "."]
    return "/".join(cleaned)


def _is_suite_filename(name: str) -> bool:
    return name.endswith((".py", ".sh")) and (
        name.startswith("test_") or name.endswith((".test.sh", "_test.py"))
    )


def _classify_suite_path(repo_root: Path, rel_path: str) -> str:
    """Return 'present', 'missing', or 'unsafe' (symlink/loop/traversal outside repo_root)."""
    if not rel_path or "\x00" in rel_path or rel_path.startswith("/"):
        return "unsafe"
    raw_parts = rel_path.split("/")
    if ".." in raw_parts:
        return "unsafe"
    norm = normalize_input_relpath(rel_path)
    if not norm:
        return "unsafe"
    try:
        root_real = repo_root.resolve(strict=True)
    except (OSError, RuntimeError):
        return "unsafe"
    candidate = repo_root / norm
    if os.path.lexists(candidate):
        try:
            resolved = candidate.resolve(strict=True)
            resolved.relative_to(root_real)
        except (OSError, RuntimeError, ValueError):
            return "unsafe"
        return "present" if resolved.is_file() else "unsafe"
    try:
        parent_real = candidate.parent.resolve(strict=False)
        parent_real.relative_to(root_real)
    except (OSError, RuntimeError, ValueError):
        return "unsafe"
    return "missing"


def _is_dunder_main_guard(node: ast.If) -> bool:
    test = node.test
    if not isinstance(test, ast.Compare) or len(test.ops) != 1 or len(test.comparators) != 1:
        return False
    if not isinstance(test.ops[0], ast.Eq):
        return False
    left, right = test.left, test.comparators[0]
    return (
        isinstance(left, ast.Name)
        and left.id == "__name__"
        and isinstance(right, ast.Constant)
        and right.value == "__main__"
    ) or (
        isinstance(right, ast.Name)
        and right.id == "__name__"
        and isinstance(left, ast.Constant)
        and left.value == "__main__"
    )


def _is_runner_call(call: ast.AST) -> bool:
    if not isinstance(call, ast.Call):
        return False
    func = call.func
    if isinstance(func, ast.Name) and func.id in ("main",):
        return True
    if (
        isinstance(func, ast.Attribute)
        and func.attr in ("main", "exit")
        and isinstance(func.value, ast.Name)
        and func.value.id in ("unittest", "pytest", "sys")
    ):
        return True
    return False


def _python_suite_has_main_entrypoint(suite_file: Path) -> bool:
    """True only when `python3 <suite_file>` invokes a test runner rather than only defining tests."""
    try:
        tree = ast.parse(suite_file.read_bytes(), filename=str(suite_file))
    except (OSError, SyntaxError):
        return True
    for node in tree.body:
        if isinstance(node, ast.If) and _is_dunder_main_guard(node):
            return True
        if isinstance(node, ast.Expr) and _is_runner_call(node.value):
            return True
        if isinstance(node, ast.Raise) and node.exc is not None:
            if _is_runner_call(node.exc):
                return True
            if (
                isinstance(node.exc, ast.Call)
                and isinstance(node.exc.func, ast.Name)
                and node.exc.func.id == "SystemExit"
            ):
                return True
    return False


def _iter_makefile_recipe_lines(text: str) -> list[str]:
    recipes: list[str] = []
    lines = text.splitlines()
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        idx += 1
        if not line.startswith("\t"):
            continue
        buf = [line[1:]]
        while buf[-1].endswith("\\") and idx < len(lines):
            buf[-1] = buf[-1][:-1]
            nxt = lines[idx]
            idx += 1
            buf.append(nxt[1:] if nxt.startswith("\t") else nxt)
        joined = " ".join(buf).lstrip()
        while joined.startswith(("@", "-", "+")):
            joined = joined[1:].lstrip()
        if not joined or joined.startswith("#"):
            continue
        recipes.append(joined)
    return recipes


def makefile_suites(repo_root: Path) -> set[str]:
    """Return every suite path referenced in executable Makefile recipe lines (before disk filtering)."""
    makefile = repo_root / "Makefile"
    try:
        text = makefile.read_text(encoding="utf-8")
    except OSError:
        return set()
    found: set[str] = set()
    for recipe in _iter_makefile_recipe_lines(text):
        try:
            lex = shlex.shlex(recipe, posix=True, punctuation_chars=";&|()")
            lex.whitespace_split = True
            lex.commenters = "#"
            tokens = list(lex)
        except ValueError:
            tokens = _MAKEFILE_SUITE_RE.findall(recipe)
        for tok in tokens:
            norm = normalize_input_relpath(tok)
            if not norm.startswith(("hooks/", "scripts/", "skills/", "eval/")):
                continue
            name = Path(norm).name
            if _is_suite_filename(name) or norm.endswith(("/test.sh", "/test.py")):
                found.add(norm)
    return found


def heavy_regression_suites(repo_root: Path) -> set[str]:
    """Return individual heavy regression suite paths owned by test_check_ccl_regressions.sh."""
    runner = repo_root / "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh"
    names = set(_DEFAULT_HEAVY_REGRESSION_NAMES)
    try:
        text = runner.read_text(encoding="utf-8")
        in_block = False
        parsed: set[str] = set()
        for raw_line in text.splitlines():
            code_part = raw_line.split("#", 1)[0].strip()
            if not in_block:
                if code_part.startswith("heavy_tests=("):
                    in_block = True
                continue
            if code_part.startswith(")"):
                break
            if code_part.endswith(".sh"):
                parsed.add(code_part)
        if parsed:
            names = parsed
    except OSError:
        pass
    base_dir = Path("skills") / "skill-extraction-workflow" / "scripts"
    return {
        normalize_input_relpath((base_dir / name).as_posix())
        for name in names
    }


def _is_dedicated_suite(path: str, heavy_suites: set[str] | None = None) -> bool:
    norm = normalize_input_relpath(path)
    if norm in DEDICATED_RUNNER_SUITES:
        return True
    if heavy_suites and norm in heavy_suites:
        return True
    if norm.startswith("eval/") and Path(norm).name.startswith("test_") and norm.endswith(".py"):
        return True
    return False


def sibling_suites(
    repo_root: Path,
    path: str,
    *,
    heavy_suites: set[str] | None = None,
) -> tuple[list[str], bool]:
    """Return (contained existing suite paths, had_unsafe_candidate) for `path`."""
    if not path or "\x00" in path or path.startswith("/") or ".." in path.split("/"):
        return [], bool(path and (".." in path.split("/") or path.startswith("/")))
    norm = normalize_input_relpath(path)
    if not norm or _is_dedicated_suite(norm, heavy_suites):
        return [], False
    rel = Path(norm)
    name = rel.name
    if _is_suite_filename(name):
        status = _classify_suite_path(repo_root, norm)
        if status == "present":
            return [norm], False
        return [], (status == "unsafe")
    if not name.endswith((".py", ".sh")):
        return [], False
    stem = rel.stem.replace("-", "_")
    found: list[str] = []
    had_unsafe = False
    for ext in (".py", ".sh"):
        candidate = (rel.parent / f"test_{stem}{ext}").as_posix()
        if _is_dedicated_suite(candidate, heavy_suites):
            continue
        status = _classify_suite_path(repo_root, candidate)
        if status == "present":
            found.append(candidate)
        elif status == "unsafe":
            had_unsafe = True
    return found, had_unsafe


HOOK_FILE_MAP: dict[str, tuple[str, ...]] = {
    "hooks/host-input.py": (
        "hooks/test_host_input.py",
        "hooks/test_skill_loading.py",
        "hooks/test_task_entry.py",
        "hooks/test_proposed_next.py",
        "hooks/test_headless_background_stop.sh",
        "hooks/test_guard_edit_isolation.sh",
    ),
    "hooks/test_host_input.py": ("hooks/test_host_input.py",),
    "hooks/skill-loading.py": (
        "hooks/test_skill_loading.py",
        "hooks/test_guard_delegation_owner.sh",
        "hooks/test_proposed_next.py",
        "hooks/test_headless_background_stop.sh",
        "hooks/test_agy_bridge.py",
        "scripts/owner-dispatch/test.sh",
    ),
    "hooks/test_skill_loading.py": ("hooks/test_skill_loading.py",),
    "hooks/task-entry.sh": ("hooks/test_task_entry.py",),
    "hooks/test_task_entry.py": ("hooks/test_task_entry.py",),
    "hooks/proposed-next-stop.sh": ("hooks/test_proposed_next.py",),
    "hooks/test_proposed_next.py": ("hooks/test_proposed_next.py",),
    "hooks/guard-delegation-owner.sh": ("hooks/test_guard_delegation_owner.sh",),
    "hooks/test_guard_delegation_owner.sh": ("hooks/test_guard_delegation_owner.sh",),
    "hooks/guard-edit-isolation.sh": ("hooks/test_guard_edit_isolation.sh",),
    "hooks/test_guard_edit_isolation.sh": ("hooks/test_guard_edit_isolation.sh",),
    "hooks/guard-merge-authorization.sh": ("hooks/test_guard_merge_authorization.sh",),
    "hooks/test_guard_merge_authorization.sh": ("hooks/test_guard_merge_authorization.sh",),
    "hooks/merge-authorization-prompt.sh": (
        "hooks/test_merge_authorization_prompt.sh",
        "hooks/test_guard_merge_authorization.sh",
    ),
    "hooks/test_merge_authorization_prompt.sh": ("hooks/test_merge_authorization_prompt.sh",),
    "hooks/headless-background-stop.sh": ("hooks/test_headless_background_stop.sh",),
    "hooks/test_headless_background_stop.sh": ("hooks/test_headless_background_stop.sh",),
    "hooks/remind-post-merge-cleanup.sh": ("hooks/test_remind_post_merge_cleanup.sh",),
    "hooks/test_remind_post_merge_cleanup.sh": ("hooks/test_remind_post_merge_cleanup.sh",),
    "hooks/remind-review-covers-head.sh": ("hooks/test_remind_review_covers_head.sh",),
    "hooks/test_remind_review_covers_head.sh": ("hooks/test_remind_review_covers_head.sh",),
    "hooks/guard-broad-local-test.sh": ("hooks/test_guard_broad_local_test.sh",),
    "hooks/test_guard_broad_local_test.sh": ("hooks/test_guard_broad_local_test.sh",),
    "hooks/remind-unverified-cli-flag.sh": ("hooks/test_remind_unverified_cli_flag.sh",),
    "hooks/test_remind_unverified_cli_flag.sh": ("hooks/test_remind_unverified_cli_flag.sh",),
    "hooks/remind-untracked-background.sh": ("hooks/test_remind_untracked_background.sh",),
    "hooks/test_remind_untracked_background.sh": ("hooks/test_remind_untracked_background.sh",),
    "hooks/session-start.sh": ("hooks/test_session_start.sh", "hooks/test_skill_loading.py"),
    "hooks/test_session_start.sh": ("hooks/test_session_start.sh",),
}

CODE_REVIEW_LEAF_MAP: dict[str, tuple[str, ...]] = {
    "classify_envelope.py": (
        "skills/code-review/scripts/test_classify_envelope.sh",
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_review_gate.sh",
    ),
    "concern_excerpt.py": (
        "skills/code-review/scripts/test_concern_excerpt.sh",
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_opencode_review_retry.sh",
    ),
    "egress_schema.py": (
        "skills/code-review/scripts/test_egress_schema.sh",
        "skills/code-review/scripts/test_review_gate.sh",
    ),
    "init_policy_matrix.py": ("skills/code-review/scripts/test_init_policy_matrix.sh",),
    "kimi_packet_mcp.py": (
        "skills/code-review/scripts/test_kimi_packet_mcp.py",
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
    ),
    "parse_opencode_review.py": (
        "skills/code-review/scripts/test_parse_opencode_review.sh",
        "skills/code-review/scripts/test_opencode_review_retry.sh",
    ),
    "parse_probe_result.py": (
        "skills/code-review/scripts/test_parse_probe_result.sh",
        "skills/code-review/scripts/test_claude_review_probe.sh",
    ),
    "parse_review_json.py": ("skills/code-review/scripts/test_parse_review_json.sh",),
    "review_diff.py": (
        "skills/code-review/scripts/test_review_diff.sh",
        "skills/code-review/scripts/test_review_client_compat.py",
    ),
    "review_diff_clients.py": (
        "skills/code-review/scripts/test_review_diff.sh",
        "skills/code-review/scripts/test_review_client_compat.py",
    ),
    "update_review_plan_intent.py": ("skills/code-review/scripts/test_update_review_plan_intent.sh",),
    "opencode_review.sh": (
        "skills/code-review/scripts/test_opencode_review_retry.sh",
        "skills/code-review/scripts/test_opencode_review_concurrency.sh",
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
    ),
    "claude_review.sh": (
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
        "skills/code-review/scripts/test_init_policy_matrix.sh",
        "skills/code-review/scripts/test_concern_excerpt.sh",
    ),
    "run_claude_capture.py": (
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
    ),
    "verify_native_skill_binding.py": (
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_init_policy_matrix.sh",
    ),
    "codex_review.sh": (
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
        "skills/code-review/scripts/test_review_client_compat.py",
    ),
    "kimi_review.sh": (
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
        "skills/code-review/scripts/test_review_client_compat.py",
    ),
    "parse_cli_review.py": (
        "skills/code-review/scripts/test_cli_review_wrappers.sh",
        "skills/code-review/scripts/test_concern_excerpt.sh",
    ),
    "classify_timeout_exit.sh": ("skills/code-review/scripts/test_cli_review_wrappers.sh",),
    "normalize_review_timeout.sh": ("skills/code-review/scripts/test_cli_review_wrappers.sh",),
    "test_abort_leak_readiness.py": ("skills/code-review/scripts/test_abort_leak_state_helpers.sh",),
}


def _git_bytes(repo_root: Path, *args: str) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["git", "-C", str(repo_root), *args],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            env=_clean_git_env(),
        )
    except OSError as exc:
        raise SelectorError(f"failed to execute git: {exc}") from exc


def _strip_single_git_newline(raw: bytes) -> bytes:
    if raw.endswith(b"\n"):
        raw = raw[:-1]
        if os.name == "nt" and raw.endswith(b"\r"):
            raw = raw[:-1]
    return raw


def verify_repo_root(repo_root: Path) -> Path:
    """Confirm `repo_root` is a usable worktree root rather than a subdirectory or broken repo."""
    try:
        root = repo_root.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise SelectorError(f"--repo {repo_root} is not accessible: {exc}") from exc
    if not root.is_dir():
        raise SelectorError(f"--repo {repo_root} is not a directory")
    if not os.path.lexists(root / ".git"):
        raise SelectorError(f"--repo {repo_root} is not a worktree root (missing .git)")

    proc = _git_bytes(root, "rev-parse", "--show-toplevel")
    if proc.returncode != 0:
        detail = os.fsdecode(proc.stderr).strip() or "git rev-parse --show-toplevel failed"
        raise SelectorError(f"--repo {repo_root} is not a usable git repository: {detail}")
    try:
        toplevel = Path(os.fsdecode(_strip_single_git_newline(proc.stdout))).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise SelectorError(f"--repo {repo_root} resolved to an invalid toplevel: {exc}") from exc
    if toplevel != root:
        raise SelectorError(f"--repo {repo_root} is not the worktree root (resolved to {toplevel})")
    return root


def _git_rev_parse_commit(repo_root: Path, ref: str) -> tuple[int, str | None]:
    if not ref or ref.startswith("-"):
        return 2, None
    proc = _git_bytes(repo_root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if proc.returncode != 0:
        return proc.returncode, None
    sha = proc.stdout.decode("ascii", "replace").strip()
    return (0, sha) if sha else (2, None)


def _git_merge_base(repo_root: Path, commit_a: str, commit_b: str) -> tuple[int, str | None]:
    proc = _git_bytes(repo_root, "merge-base", "--", commit_a, commit_b)
    if proc.returncode != 0:
        return proc.returncode, None
    sha = proc.stdout.decode("ascii", "replace").strip()
    return (0, sha) if sha else (2, None)


def _canonicalize_auto_ref(ref: str) -> str:
    if ref.startswith("refs/") or _HEX_SHA_RE.match(ref):
        return ref
    if "/" in ref:
        return f"refs/remotes/{ref}"
    return f"refs/heads/{ref}"


def _auto_ref_exists(repo_root: Path, ref: str) -> bool:
    """Return True if `ref` exists in Git refs; raise BaseRefError on corrupt ref/object errors."""
    check_fmt = _git_bytes(repo_root, "check-ref-format", ref)
    if check_fmt.returncode != 0:
        return False
    proc = _git_bytes(repo_root, "for-each-ref", "--format=%(objectname)", "--", ref)
    if proc.returncode != 0:
        detail = os.fsdecode(proc.stderr).strip() or f"exit {proc.returncode}"
        raise BaseRefError(f"git for-each-ref failed for {ref!r}: {detail}")
    return bool(proc.stdout.strip())


def _resolve_base_with_merge_base(
    repo_root: Path,
    explicit_base: str | None = None,
    *,
    default_base_ref: str | None = None,
    allow_missing_auto: bool = False,
) -> tuple[str | None, str | None, str | None, str | None]:
    """Return (resolved_ref, resolved_ref_sha, merge_base_sha, head_sha) or raise BaseRefError."""
    env_explicit = os.environ.get("CCL_SKILL_BASE_REF", "").strip()
    has_explicit = explicit_base is not None or bool(env_explicit)

    rc_head, head_sha = _git_rev_parse_commit(repo_root, "HEAD")
    if rc_head != 0 or not head_sha:
        if allow_missing_auto and not has_explicit:
            return None, None, None, None
        raise BaseRefError("HEAD does not resolve to a commit")

    if explicit_base is not None:
        ref = explicit_base.strip()
        if not ref or ref.startswith("-"):
            raise BaseRefError(f"invalid --base-ref {explicit_base!r}")
        rc_ref, ref_sha = _git_rev_parse_commit(repo_root, ref)
        if rc_ref != 0 or not ref_sha:
            raise BaseRefError(f"--base-ref {ref!r} does not resolve to a commit")
        rc_mb, mb_sha = _git_merge_base(repo_root, ref_sha, head_sha)
        if rc_mb != 0 or not mb_sha:
            raise BaseRefError(f"--base-ref {ref!r} has no merge-base with HEAD")
        return ref, ref_sha, mb_sha, head_sha

    if env_explicit:
        if env_explicit.startswith("-"):
            raise BaseRefError(f"invalid CCL_SKILL_BASE_REF {env_explicit!r}")
        rc_ref, ref_sha = _git_rev_parse_commit(repo_root, env_explicit)
        if rc_ref != 0 or not ref_sha:
            raise BaseRefError(f"CCL_SKILL_BASE_REF {env_explicit!r} does not resolve to a commit")
        rc_mb, mb_sha = _git_merge_base(repo_root, ref_sha, head_sha)
        if rc_mb != 0 or not mb_sha:
            raise BaseRefError(f"CCL_SKILL_BASE_REF {env_explicit!r} has no merge-base with HEAD")
        return env_explicit, ref_sha, mb_sha, head_sha

    raw_default = (
        default_base_ref
        if default_base_ref is not None
        else (
            os.environ.get("CCL_SKILL_DEFAULT_BASE_REF")
            or os.environ.get("CCL_SKILL_SELECTED_DEFAULT_BASE")
            or "origin/dev"
        )
    ).strip()
    if raw_default.startswith("-"):
        raise BaseRefError(f"invalid default base ref {raw_default!r}")
    canon_default = _canonicalize_auto_ref(raw_default) if raw_default else ""
    candidates = list(
        dict.fromkeys(
            c
            for c in (
                canon_default,
                "refs/remotes/origin/main",
                "refs/remotes/origin/dev",
            )
            if c
        )
    )

    best: tuple[int, str, str, str] | None = None
    for ref in candidates:
        if _HEX_SHA_RE.match(ref):
            rc_ref, ref_sha = _git_rev_parse_commit(repo_root, ref)
            if rc_ref != 0 or not ref_sha:
                if allow_missing_auto:
                    continue
                raise BaseRefError(f"default base commit {ref!r} does not resolve to a commit")
        else:
            if not _auto_ref_exists(repo_root, ref):
                continue
            rc_ref, ref_sha = _git_rev_parse_commit(repo_root, ref)
            if rc_ref != 0 or not ref_sha:
                raise BaseRefError(f"integration ref {ref!r} exists but does not resolve to a valid commit")

        rc_mb, mb_sha = _git_merge_base(repo_root, ref_sha, head_sha)
        if rc_mb == 1:
            continue
        if rc_mb != 0 or not mb_sha:
            raise BaseRefError(f"git merge-base failed for existing ref {ref!r} (exit {rc_mb})")
        cnt_proc = _git_bytes(repo_root, "rev-list", "--count", f"{mb_sha}..{head_sha}")
        if cnt_proc.returncode != 0:
            raise BaseRefError(f"git rev-list --count failed for {ref!r}")
        try:
            distance = int(cnt_proc.stdout.decode("ascii", "replace").strip())
        except ValueError as exc:
            raise BaseRefError(f"unexpected rev-list count for {ref!r}") from exc
        if best is None or distance < best[0]:
            best = (distance, ref, ref_sha, mb_sha)

    if best is None:
        if allow_missing_auto:
            return None, None, None, head_sha
        raise BaseRefError(
            "no usable integration base ref found (checked "
            + ", ".join(candidates)
            + "); fetch origin or pass --base-ref <ref>"
        )
    return best[1], best[2], best[3], head_sha


def resolve_base_ref(
    repo_root: Path,
    explicit_base: str | None = None,
    *,
    default_base_ref: str | None = None,
) -> str:
    root = verify_repo_root(repo_root)
    resolved, _, _, _ = _resolve_base_with_merge_base(
        root,
        explicit_base=explicit_base,
        default_base_ref=default_base_ref,
    )
    assert resolved is not None
    return resolved


def _git_nul_paths(repo_root: Path, *args: str) -> list[str]:
    proc = _git_bytes(repo_root, *args)
    if proc.returncode != 0:
        detail = os.fsdecode(proc.stderr).strip() or f"exit {proc.returncode}"
        raise SelectorError(f"git {' '.join(args)} failed: {detail}")
    return [os.fsdecode(entry) for entry in proc.stdout.split(b"\x00") if entry]


def _discover_candidate(
    repo_root: Path,
    base_ref: str | None = None,
    *,
    default_base_ref: str | None = None,
) -> tuple[list[str], str, str, str, str, bool, list[str]]:
    root = verify_repo_root(repo_root)
    resolved, ref_sha, mb_sha, head_sha = _resolve_base_with_merge_base(
        root,
        explicit_base=base_ref,
        default_base_ref=default_base_ref,
    )
    assert resolved is not None and ref_sha is not None and mb_sha is not None and head_sha is not None

    found: set[str] = set()
    found.update(
        _git_nul_paths(root, "diff", "-z", "--no-ext-diff", "--no-renames", "--name-only", mb_sha, head_sha, "--")
    )
    found.update(_git_nul_paths(root, "diff", "--cached", "-z", "--no-ext-diff", "--no-renames", "--name-only", "--"))
    found.update(_git_nul_paths(root, "diff", "-z", "--no-ext-diff", "--no-renames", "--name-only", "--"))
    raw_untracked = _git_nul_paths(root, "ls-files", "-z", "--others", "--exclude-standard")
    found.update(raw_untracked)

    cleaned = sorted(
        (p for p in found if p and not p.startswith(".work/")),
        key=os.fsencode,
    )
    untracked = sorted(
        (p for p in set(raw_untracked) if p and not p.startswith(".work/")),
        key=os.fsencode,
    )
    return cleaned, resolved, ref_sha, mb_sha, head_sha, (head_sha != mb_sha), untracked


def collect_changed_files(
    repo_root: Path,
    base_ref: str | None = None,
    *,
    default_base_ref: str | None = None,
) -> tuple[list[str], str]:
    cleaned, resolved, _, _, _, _, _ = _discover_candidate(
        repo_root,
        base_ref=base_ref,
        default_base_ref=default_base_ref,
    )
    return cleaned, resolved


def _docker_daemon_ready() -> bool:
    if not shutil.which("docker"):
        return False
    try:
        proc = subprocess.run(
            ["docker", "info"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0


class _PlanBuilder:
    def __init__(
        self,
        repo_root: Path,
        include_slow: bool,
        with_npm: bool,
        registered_suites: set[str],
    ):
        self.repo_root = repo_root
        self.include_slow = include_slow
        self.with_npm = with_npm
        self.registered_suites = registered_suites
        self.preflight_commands: list[list[str]] = []
        self.parallel_suites: list[str] = []
        self._parallel_seen: set[str] = set()
        self.serial_commands: list[list[str]] = []
        self._serial_seen: set[tuple[str, ...]] = set()
        self.notes: list[str] = []
        self._notes_seen: set[str] = set()
        self.npm_required = False
        self.abort_leak_needed = False
        self.heavy_regressions_needed = False
        self.missing_suites: list[str] = []
        self.skipped_lanes: list[str] = []
        self.unsafe_blocked = False

    def _record_missing(self, rel_suite: str) -> None:
        if rel_suite not in self.missing_suites:
            self.missing_suites.append(rel_suite)

    def add_suite(self, rel_suite: str) -> None:
        norm = normalize_input_relpath(rel_suite)
        if norm in self._parallel_seen:
            return
        self._parallel_seen.add(norm)
        status = _classify_suite_path(self.repo_root, norm)
        if status == "unsafe":
            self.unsafe_blocked = True
            self.add_note(f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(norm)})")
            return
        if status == "missing":
            self._record_missing(norm)
            return
        if norm.endswith(".py") and not _python_suite_has_main_entrypoint(self.repo_root / norm):
            self.add_serial(["python3", "-m", "pytest", "-q", norm])
            return
        self.parallel_suites.append(norm)

    def add_changed_suite(self, rel_suite: str) -> None:
        """Add a suite that is itself in the change set; if still registered in Makefile when deleted, report drift."""
        norm = normalize_input_relpath(rel_suite)
        status = _classify_suite_path(self.repo_root, norm)
        if status == "present":
            self.add_suite(norm)
        elif status == "unsafe":
            self.unsafe_blocked = True
            self.add_note(f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(norm)})")
        elif status == "missing" and norm in self.registered_suites:
            self._record_missing(norm)

    def add_serial_suite(self, cmd: list[str], rel_suite: str) -> None:
        """Validate containment and existence of a dedicated suite before scheduling a serial command."""
        norm = normalize_input_relpath(rel_suite)
        status = _classify_suite_path(self.repo_root, norm)
        if status == "unsafe":
            self.unsafe_blocked = True
            self.add_note(f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(norm)})")
            return
        if status == "missing":
            self._record_missing(norm)
            return
        self.add_serial(cmd)

    def add_skip(self, lane: str, note: str) -> None:
        if lane not in self.skipped_lanes:
            self.skipped_lanes.append(lane)
        self.add_note(note)

    def add_serial(self, cmd: list[str]) -> None:
        key = tuple(cmd)
        if key not in self._serial_seen:
            self._serial_seen.add(key)
            self.serial_commands.append(cmd)

    def add_note(self, note: str) -> None:
        if note not in self._notes_seen:
            self._notes_seen.add(note)
            self.notes.append(note)


def build_test_plan(
    changed_files: list[str],
    *,
    repo_root: Path,
    default_base_ref: str = "origin/dev",
    resolved_base_ref: str | None = None,
    resolved_base_sha: str | None = None,
    merge_base_sha: str | None = None,
    head_sha: str | None = None,
    has_candidate_commits: bool = False,
    untracked_files: list[str] | None = None,
    include_slow: bool = False,
    with_npm: bool = False,
) -> dict:
    registered_suites = makefile_suites(repo_root)
    heavy_suites = heavy_regression_suites(repo_root)
    builder = _PlanBuilder(
        repo_root=repo_root,
        include_slow=include_slow,
        with_npm=with_npm,
        registered_suites=registered_suites,
    )
    cleaned: list[str] = []
    seen_inputs: set[str] = set()
    for raw in changed_files:
        if "\x00" in raw or raw.startswith("/") or ".." in raw.split("/"):
            builder.add_note(f"unsafe-input-path: ignored path outside checkout ({_terminal_safe(raw)})")
            continue
        norm = normalize_input_relpath(raw)
        if not norm or norm.startswith(".work/"):
            continue
        if norm not in seen_inputs:
            seen_inputs.add(norm)
            cleaned.append(norm)

    untracked_clean = sorted(
        {
            normalize_input_relpath(u)
            for u in (untracked_files or [])
            if u and "\x00" not in u and not u.startswith("/") and ".." not in u.split("/")
        }
        - {""}
    )

    gate_base_target = resolved_base_sha or resolved_base_ref
    gate_base_args = (
        ["--base-ref", gate_base_target]
        if gate_base_target
        else ["--default-base-ref", default_base_ref]
    )

    if not cleaned:
        if has_candidate_commits:
            builder.preflight_commands.append(
                [
                    "python3",
                    "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py",
                    "--repo",
                    ".",
                    *gate_base_args,
                ]
            )
        return {
            "changed_files": [],
            "untracked_files": untracked_clean,
            "preflight_commands": builder.preflight_commands,
            "parallel_suites": [],
            "serial_commands": [],
            "npm_required": False,
            "notes": builder.notes,
            "skipped_lanes": [],
            "missing_suites": [],
            "unsafe_blocked": builder.unsafe_blocked,
            "advisory": ADVISORY_FOOTER,
        }

    diff_check_cmds: list[list[str]] = []
    if merge_base_sha:
        if head_sha and head_sha != merge_base_sha:
            diff_check_cmds.append(["git", "diff", "--no-ext-diff", "--check", merge_base_sha, head_sha, "--"])
        diff_check_cmds.append(["git", "diff", "--no-ext-diff", "--check", merge_base_sha, "--"])
        diff_check_cmds.append(["git", "diff", "--cached", "--no-ext-diff", "--check", merge_base_sha, "--"])
    else:
        diff_check_cmds.append(["git", "diff", "--no-ext-diff", "--check", "--"])
        diff_check_cmds.append(["git", "diff", "--cached", "--no-ext-diff", "--check", "--"])

    builder.preflight_commands.extend(
        [
            *diff_check_cmds,
            ["bash", "skills/skill-extraction-workflow/scripts/check-ccl-skills.sh", "."],
            [
                "python3",
                "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py",
                "--repo",
                ".",
                *gate_base_args,
            ],
            [
                "bash",
                "skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh",
                "--repo",
                ".",
                "--enforce",
            ],
        ]
    )

    need_doc_gates = False
    need_spec_refs = False
    need_routing_gates = False
    need_sanitization = False
    need_skill_count = False
    need_release_version = False
    need_eval_unittest = False
    eval_extra_modules: list[str] = []
    need_pytest_report = False
    need_fast_regressions = False
    selected_heavy_individuals: list[str] = []
    fallback_full = False

    hook_suites = sorted(s for s in registered_suites if s.startswith("hooks/"))
    code_review_shard_suites = sorted(
        s
        for s in registered_suites
        if s.startswith("skills/code-review/scripts/")
        and s != "skills/code-review/scripts/test_review_gate_abort_leak.sh"
    )

    for path in cleaned:
        lower = path.lower()
        is_md = lower.endswith((".md", ".mdx"))

        sibling_found, had_unsafe = sibling_suites(repo_root, path, heavy_suites=heavy_suites)
        if had_unsafe:
            builder.unsafe_blocked = True
            builder.add_note(f"unsafe-suite-path: skipped uncontained candidate for {_terminal_safe(path)}")
        for suite in sibling_found:
            builder.add_suite(suite)

        if is_md or path.startswith(("docs/", "specs/", "agent-context/")):
            need_doc_gates = True
            need_sanitization = True

        if path in ("README.md", "packages/ccl-skills-npm/README.md"):
            need_skill_count = True

        if path in ("opencode.json", "AGENTS.md") or path.startswith(("skills/", "agent-context/")):
            need_routing_gates = True
            need_skill_count = True
            need_sanitization = True

        if path == "hooks.json":
            builder.npm_required = True
            need_sanitization = True
            builder.add_suite("hooks/test_agy_bridge.py")
            builder.add_suite("scripts/test_install_antigravity.sh")
            continue

        if path in (
            "README.md",
            "LICENSE",
            "opencode.json",
            "Makefile",
            "requirements-test.txt",
        ) or path.startswith((".github/", "docs/", "specs/")):
            if path in ("Makefile", "requirements-test.txt", "docs/CONTRIBUTING.md") or path.startswith(".github/"):
                builder.add_suite("scripts/test_check_spec_references.py")
            if path in ("Makefile", "requirements-test.txt") or path.startswith(".github/"):
                builder.add_suite("skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh")
                builder.add_suite("scripts/test_lane_isolation.py")
                builder.add_suite("scripts/test_run_parallel_suites.sh")
                builder.add_suite("scripts/test_select_affected_tests.py")
            if path == "opencode.json":
                need_release_version = True
                builder.npm_required = True
                builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
            if path.startswith("specs/065-uiux-evidence-delivery/"):
                builder.add_suite("skills/skill-extraction-workflow/scripts/test_obligation_ledger_repo_audit.sh")
            continue

        if path.startswith((".claude-plugin/", ".codex-plugin/", ".antigravity-plugin/", ".agents/", "packages/")):
            builder.npm_required = True
            need_release_version = True
            need_sanitization = True
            builder.add_suite("scripts/test_check_release_version.py")
            builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
            builder.add_suite("scripts/test_install_status.py")
            if path.startswith(".antigravity-plugin/"):
                builder.add_suite("hooks/test_agy_bridge.py")
                builder.add_suite("scripts/test_install_antigravity.sh")
            continue

        if path == "agent-context/session-start.md":
            builder.add_suite("hooks/test_session_start.sh")
            builder.add_suite("hooks/test_skill_loading.py")
            continue

        if path.startswith("agent-context/"):
            continue

        if path.startswith("hooks/"):
            need_sanitization = True
            if path == "hooks/AGENTS.md":
                continue
            if path in HOOK_FILE_MAP:
                for suite in HOOK_FILE_MAP[path]:
                    builder.add_suite(suite)
            elif path in ("hooks/agy-bridge.py", "hooks/test_agy_bridge.py"):
                builder.add_suite("hooks/test_agy_bridge.py")
                builder.add_suite("scripts/test_install_antigravity.sh")
                builder.npm_required = True
            else:
                for suite in hook_suites:
                    builder.add_suite(suite)
                builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
                builder.npm_required = True
            continue

        if path.startswith("scripts/"):
            need_sanitization = True
            need_spec_refs = True
            if path == "scripts/AGENTS.md":
                continue
            if path in ("scripts/check-markdown-links.py", "scripts/test_check_markdown_links.py"):
                builder.add_suite("scripts/test_check_markdown_links.py")
                need_doc_gates = True
            elif path in ("scripts/check-spec-references.py", "scripts/test_check_spec_references.py"):
                builder.add_suite("scripts/test_check_spec_references.py")
                need_doc_gates = True
            elif path in ("scripts/check-release-version.py", "scripts/test_check_release_version.py"):
                builder.add_suite("scripts/test_check_release_version.py")
                need_release_version = True
            elif path in ("scripts/check-public-sanitization.py", "scripts/test_check_public_sanitization.py"):
                builder.add_suite("scripts/test_check_public_sanitization.py")
            elif path in ("scripts/check-skill-count.py", "scripts/test_check_skill_count.py"):
                builder.add_suite("scripts/test_check_skill_count.py")
                need_skill_count = True
            elif path in (
                "scripts/install-opencode.sh",
                "scripts/install-opencode-commands.sh",
                "scripts/test_install_opencode_skill_migration.sh",
            ):
                builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
                builder.add_suite("scripts/test_install_status.py")
            elif path in ("scripts/install-antigravity.sh", "scripts/test_install_antigravity.sh"):
                builder.add_suite("scripts/test_install_antigravity.sh")
                builder.add_suite("hooks/test_agy_bridge.py")
            elif path in ("scripts/install.sh", "scripts/test_install_status.py"):
                builder.add_suite("scripts/test_install_status.py")
            elif path in ("scripts/install-gates.sh", "scripts/test_install_gates_runtime.py"):
                builder.add_suite("scripts/test_install_gates_runtime.py")
            elif path.startswith("scripts/owner-dispatch/"):
                builder.add_suite("scripts/owner-dispatch/test.sh")
                builder.npm_required = True
            elif path.startswith("scripts/control-plane/"):
                builder.add_suite("scripts/control-plane/test.sh")
            elif path in ("scripts/run-parallel-suites.sh", "scripts/test_run_parallel_suites.sh"):
                builder.add_suite("scripts/test_run_parallel_suites.sh")
                builder.add_suite("scripts/test_lane_isolation.py")
            elif path == "scripts/test_lane_isolation.py":
                builder.add_suite("scripts/test_lane_isolation.py")
            elif path in ("scripts/select-affected-tests.py", "scripts/test_select_affected_tests.py"):
                builder.add_suite("scripts/test_select_affected_tests.py")
            elif path.startswith("scripts/verify-sandbox/"):
                if include_slow and _docker_daemon_ready():
                    builder.add_serial_suite(["bash", "scripts/verify-sandbox/test.sh"], "scripts/verify-sandbox/test.sh")
                else:
                    builder.add_skip(
                        "verify-sandbox",
                        "verify-sandbox: Docker daemon unavailable or FULL!=1; run 'make test-verify-sandbox' with Docker running.",
                    )
            elif _is_suite_filename(Path(path).name):
                builder.add_changed_suite(path)
            else:
                fallback_full = True
            continue

        if path.startswith("eval/"):
            need_eval_unittest = True
            need_sanitization = True
            eval_rel = Path(path)
            if len(eval_rel.parts) == 2 and eval_rel.suffix == ".py":
                stem = eval_rel.stem
                cand_name = stem if stem.startswith("test_") else ("test_" + stem.replace("-", "_"))
                cand_rel = (Path("eval") / (cand_name + ".py")).as_posix()
                cand_status = _classify_suite_path(repo_root, cand_rel)
                if cand_status == "present" and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", cand_name):
                    mod_name = f"eval.{cand_name}"
                    if mod_name not in eval_extra_modules:
                        eval_extra_modules.append(mod_name)
                elif cand_status == "unsafe":
                    builder.unsafe_blocked = True
                    builder.add_note(f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(cand_rel)})")
                elif cand_status == "missing" and cand_rel in registered_suites:
                    builder._record_missing(cand_rel)
            builder.add_suite("skills/skill-extraction-workflow/scripts/test_body_compliance_grading.sh")
            builder.add_suite("skills/skill-extraction-workflow/scripts/test_routing_bank_integrity.sh")
            builder.add_suite("skills/skill-extraction-workflow/scripts/test_frozen_case_sanctity.sh")
            builder.add_suite("skills/skill-extraction-workflow/scripts/test_skill_paired_eval.py")
            continue

        if path.startswith("skills/"):
            parts = path.split("/")
            skill_name = parts[1] if len(parts) >= 2 else ""

            if skill_name == "claude-code-review":
                builder.add_suite("skills/code-review/scripts/test_code_review_identity.sh")
                continue

            if skill_name == "code-review":
                if len(parts) >= 4 and parts[2] == "scripts":
                    fname = parts[3]
                    if fname.endswith(".md"):
                        continue
                    builder.add_suite("scripts/test_lane_isolation.py")
                    if fname in CODE_REVIEW_LEAF_MAP:
                        for suite in CODE_REVIEW_LEAF_MAP[fname]:
                            builder.add_suite(suite)
                        if fname == "test_review_gate.sh":
                            builder.abort_leak_needed = True
                    elif fname == "test_review_gate_abort_leak.sh":
                        builder.abort_leak_needed = True
                    elif _is_suite_filename(fname):
                        builder.add_changed_suite(path)
                        if fname == "test_review_gate.sh":
                            builder.abort_leak_needed = True
                    else:
                        for suite in code_review_shard_suites:
                            builder.add_suite(suite)
                        builder.abort_leak_needed = True
                else:
                    builder.add_suite("skills/code-review/scripts/test_code_review_identity.sh")
                continue

            if skill_name == "testing-strategy":
                if len(parts) >= 3 and parts[2] == "scripts":
                    builder.add_suite("skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh")
                    builder.add_suite("skills/testing-strategy/scripts/lang-basics-ast-check.test.sh")
                    builder.add_suite("skills/testing-strategy/scripts/lang-basics-go-check.test.sh")
                    builder.add_suite("skills/testing-strategy/scripts/test_mutation_backup_recipe.sh")
                    builder.add_suite("scripts/test_lane_isolation.py")
                continue

            if skill_name == "tighten-doc":
                builder.add_suite("skills/tighten-doc/scripts/test_doc_lint_repo.py")
                builder.add_suite("skills/tighten-doc/scripts/test_figure_and_doc_lint.sh")
                need_doc_gates = True
                continue

            if skill_name == "worktree-isolation":
                builder.add_suite("skills/worktree-isolation/scripts/test_worktree_status.sh")
                if len(parts) >= 3 and parts[2] == "scripts":
                    builder.add_suite("skills/worktree-isolation/scripts/test_worktree_sweep.sh")
                else:
                    builder.add_suite("skills/skill-extraction-workflow/scripts/test_teardown_guard_pins.sh")
                continue

            if skill_name == "test-artifact-management":
                need_pytest_report = True
                continue

            if skill_name == "product-rd-workflow":
                if len(parts) >= 3 and parts[2] == "scripts":
                    builder.add_suite("skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh")
                continue

            if skill_name == "skill-extraction-workflow":
                if len(parts) >= 4 and parts[2] == "scripts":
                    fname = parts[3]
                    if fname.endswith(".md"):
                        continue
                    builder.add_suite("scripts/test_lane_isolation.py")
                    if fname == "test_check_ccl_regressions.sh":
                        need_fast_regressions = True
                        builder.heavy_regressions_needed = True
                    elif path in heavy_suites:
                        if path not in selected_heavy_individuals:
                            selected_heavy_individuals.append(path)
                        builder.add_suite(
                            "skills/skill-extraction-workflow/scripts/test_regression_runner_registration.sh"
                        )
                    elif _is_suite_filename(fname) and fname.endswith(".py"):
                        builder.add_changed_suite(path)
                    elif _is_suite_filename(fname) and fname.endswith(".sh"):
                        builder.add_changed_suite(path)
                        builder.add_suite(
                            "skills/skill-extraction-workflow/scripts/test_regression_runner_registration.sh"
                        )
                    elif fname in ("eval_runtime.py", "skill-paired-eval.py"):
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_eval_runtime.py")
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_skill_paired_eval.py")
                    elif fname.startswith("eval-routing"):
                        need_routing_gates = True
                        for s in (
                            "skills/skill-extraction-workflow/scripts/test_eval_routing_bank_grader_diagnostics.sh",
                            "skills/skill-extraction-workflow/scripts/test_eval_routing_bank_surface_binding.sh",
                            "skills/skill-extraction-workflow/scripts/test_eval_routing_bank_resolution.sh",
                            "skills/skill-extraction-workflow/scripts/test_eval_routing_prose_target.sh",
                            "skills/skill-extraction-workflow/scripts/test_routing_pointer_integrity.sh",
                            "skills/skill-extraction-workflow/scripts/test_routing_bank_integrity.sh",
                        ):
                            builder.add_suite(s)
                    elif fname == "shared_git_surface_gate.py":
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_shared_git_surface_gate.sh")
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh")
                    elif fname == "check_review_evidence_present.py":
                        builder.add_suite(
                            "skills/skill-extraction-workflow/scripts/test_check_review_evidence_present.sh"
                        )
                    else:
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_eval_runtime.py")
                        builder.add_suite("skills/skill-extraction-workflow/scripts/test_skill_paired_eval.py")
                        need_fast_regressions = True
                        builder.heavy_regressions_needed = True
                elif path == "skills/skill-extraction-workflow/references/source-register.md":
                    builder.add_suite(
                        "skills/skill-extraction-workflow/scripts/test_check_ccl_register_pending_exclusion.sh"
                    )
                    builder.add_suite(
                        "skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh"
                    )
                    builder.add_suite(
                        "skills/skill-extraction-workflow/scripts/test_impact_chain_round_attribution.sh"
                    )
                continue

            if len(parts) >= 3 and parts[2] == "scripts" and not is_md:
                skill_scripts_dir = repo_root / "skills" / skill_name / "scripts"
                if skill_scripts_dir.is_dir():
                    for candidate in sorted(skill_scripts_dir.iterdir()):
                        if _is_suite_filename(candidate.name):
                            rel_cand = (Path("skills") / skill_name / "scripts" / candidate.name).as_posix()
                            cand_status = _classify_suite_path(repo_root, rel_cand)
                            if cand_status == "present":
                                builder.add_suite(rel_cand)
                            elif cand_status == "unsafe":
                                builder.unsafe_blocked = True
                                builder.add_note(
                                    f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(rel_cand)})"
                                )
            continue

        fallback_full = True

    if untracked_clean and (need_doc_gates or need_spec_refs or need_sanitization):
        preview_names = ", ".join(_terminal_safe(p) for p in untracked_clean[:5])
        more = f" (+{len(untracked_clean) - 5} more)" if len(untracked_clean) > 5 else ""
        builder.add_note(
            f"untracked-files: {len(untracked_clean)} untracked path(s) ({preview_names}{more}) "
            "are skipped by git-ls-files gates (markdown-links, spec-references, doc-lint, sanitization) until staged."
        )

    if need_doc_gates:
        builder.add_serial(["python3", "scripts/check-markdown-links.py", "."])
        builder.add_serial(["python3", "scripts/check-spec-references.py", "."])
        builder.add_serial(["python3", "skills/tighten-doc/scripts/doc-lint-repo.py", "."])
    elif need_spec_refs:
        builder.add_serial(["python3", "scripts/check-spec-references.py", "."])

    if need_sanitization:
        builder.add_serial(["python3", "scripts/check-public-sanitization.py", "."])

    if need_skill_count:
        builder.add_serial(["python3", "scripts/check-skill-count.py", "."])

    if need_release_version:
        builder.add_serial(["python3", "scripts/check-release-version.py", "."])

    if need_routing_gates:
        builder.add_serial(["ruby", "-Ku", "skills/skill-extraction-workflow/scripts/eval-routing.rb", "."])
        builder.add_suite("skills/skill-extraction-workflow/scripts/test_obligation_ledger_repo_audit.sh")

    if need_pytest_report:
        builder.add_serial_suite(
            ["python3", "-m", "pytest", "-q", "skills/test-artifact-management/references/test_gen_report.py"],
            "skills/test-artifact-management/references/test_gen_report.py",
        )

    if need_eval_unittest:
        eval_init = (Path("eval") / "__init__.py").as_posix()
        if os.path.lexists(repo_root / eval_init) and _classify_suite_path(repo_root, eval_init) != "present":
            builder.unsafe_blocked = True
            builder.add_note(f"unsafe-suite-path: skipped path outside checkout ({eval_init})")
        eval_modules: list[str] = []
        for mod_name in (*_DEFAULT_EVAL_UNITTEST_MODULES, *eval_extra_modules):
            rel_mod = mod_name.replace(".", "/") + ".py"
            mod_status = _classify_suite_path(repo_root, rel_mod)
            if mod_status == "present":
                if mod_name not in eval_modules:
                    eval_modules.append(mod_name)
            elif mod_status == "unsafe":
                builder.unsafe_blocked = True
                builder.add_note(f"unsafe-suite-path: skipped path outside checkout ({_terminal_safe(rel_mod)})")
            elif mod_status == "missing" and rel_mod in registered_suites:
                builder._record_missing(rel_mod)
        if eval_modules and not builder.unsafe_blocked:
            builder.add_serial(["python3", "-m", "unittest", *eval_modules])

    if need_fast_regressions:
        builder.add_serial_suite(
            ["bash", "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh", "--fast"],
            "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh",
        )

    if builder.heavy_regressions_needed:
        if include_slow:
            builder.add_serial_suite(
                ["bash", "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh", "--heavy-only"],
                "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh",
            )
        else:
            builder.add_skip(
                "heavy-regressions",
                "heavy-regressions: skipped clone-heavy suites; pass --include-slow or run 'make test-check-ccl-regressions' before PR.",
            )
    elif selected_heavy_individuals:
        if include_slow:
            for heavy_path in selected_heavy_individuals:
                builder.add_serial_suite(["bash", heavy_path], heavy_path)
        else:
            builder.add_skip(
                "heavy-regressions",
                "heavy-regressions: skipped clone-heavy suite(s); pass --include-slow or run 'make test-check-ccl-regressions' before PR.",
            )

    if builder.abort_leak_needed:
        abort_suite = "skills/code-review/scripts/test_review_gate_abort_leak.sh"
        if include_slow:
            builder.add_serial_suite(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=1",
                    "ABORT_LEAK_PROBE_CLIENT=claude",
                    "bash",
                    abort_suite,
                ],
                abort_suite,
            )
            builder.add_serial_suite(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=2",
                    "ABORT_LEAK_PROBE_CLIENT=fallback",
                    "bash",
                    abort_suite,
                ],
                abort_suite,
            )
            builder.add_serial_suite(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=2",
                    "ABORT_LEAK_PROBE_CLIENT=claude",
                    "bash",
                    abort_suite,
                ],
                abort_suite,
            )
        else:
            builder.add_skip(
                "abort-leak",
                "abort-leak: skipped slow abort-leak probes (~3 min); pass --include-slow or run 'make test-code-review-abort-leak' before landing.",
            )

    if builder.npm_required:
        pkg_json_rel = "packages/ccl-skills-npm/package.json"
        pkg_status = _classify_suite_path(repo_root, pkg_json_rel)
        npm_nm = repo_root / "packages/ccl-skills-npm/node_modules"
        if pkg_status == "unsafe":
            builder.unsafe_blocked = True
            builder.add_note(f"unsafe-suite-path: skipped path outside checkout ({pkg_json_rel})")
        elif (with_npm or npm_nm.is_dir()) and pkg_status == "present":
            if with_npm:
                builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "ci"])
            builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "test"])
            if include_slow:
                builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "run", "test:pack"])
        else:
            builder.add_skip(
                "npm-packages",
                "npm-packages: packages/ccl-skills-npm/node_modules not installed; pass --with-npm or run 'make npm-test npm-pack-verify'.",
            )

    if builder.missing_suites:
        builder.add_note(
            "selector-drift: mapped suite(s) missing on disk ("
            + ", ".join(_terminal_safe(s) for s in builder.missing_suites)
            + "); update scripts/select-affected-tests.py. Escalating to the full lanes."
        )
        fallback_full = True

    if fallback_full:
        unsafe_registered = sorted(
            s for s in registered_suites if _classify_suite_path(repo_root, s) == "unsafe"
        )
        if os.path.lexists(repo_root / "Makefile") and _classify_suite_path(repo_root, "Makefile") == "unsafe":
            unsafe_registered.append("Makefile")
        if unsafe_registered or builder.unsafe_blocked:
            builder.unsafe_blocked = True
            builder.add_note(
                "unsafe-fallback-blocked: refusing Make target escalation while checkout contains uncontained path(s)"
                + (
                    f" ({', '.join(_terminal_safe(s) for s in unsafe_registered)})"
                    if unsafe_registered
                    else ""
                )
            )
        else:
            builder.add_note(
                "fallback: unrecognized path or selector drift; escalating to make test-repo-gates + test-regressions-fast + test-code-review-1/2."
            )
            builder.add_serial(["make", "test-repo-gates"])
            builder.add_serial(["make", "test-regressions-fast"])
            builder.add_serial(["make", "test-code-review-1"])
            builder.add_serial(["make", "test-code-review-2"])

    return {
        "changed_files": cleaned,
        "untracked_files": untracked_clean,
        "preflight_commands": builder.preflight_commands,
        "parallel_suites": builder.parallel_suites,
        "serial_commands": builder.serial_commands,
        "npm_required": builder.npm_required,
        "notes": builder.notes,
        "skipped_lanes": builder.skipped_lanes,
        "missing_suites": builder.missing_suites,
        "unsafe_blocked": builder.unsafe_blocked,
        "advisory": ADVISORY_FOOTER,
    }


def _parallel_runner_command(runner_path: str, suites: list[str], jobs: int | None) -> list[str]:
    cmd = ["bash", runner_path, "--label", "affected_suites"]
    if jobs is not None:
        cmd.extend(["--jobs", str(jobs)])
    cmd.extend(suites)
    return cmd


def _verify_command_containment(repo_root: Path, cmd: list[str]) -> str | None:
    """Recheck repo-local script/suite operands and Make targets right before execution (TOCTOU guard)."""
    if not cmd:
        return "empty command"
    if cmd[0] == "make":
        if os.path.lexists(repo_root / "Makefile") and _classify_suite_path(repo_root, "Makefile") != "present":
            return "Makefile escapes checkout"
        for reg in sorted(makefile_suites(repo_root)):
            if _classify_suite_path(repo_root, reg) == "unsafe":
                return f"Makefile suite escapes checkout ({_terminal_safe(reg)})"
        return None
    for part in cmd[1:]:
        if part.startswith(("hooks/", "scripts/", "skills/", "eval/")):
            if _classify_suite_path(repo_root, part) != "present":
                return f"command operand is missing or outside checkout ({_terminal_safe(part)})"
        elif _EVAL_MODULE_RE.match(part):
            eval_init = (Path("eval") / "__init__.py").as_posix()
            if os.path.lexists(repo_root / eval_init) and _classify_suite_path(repo_root, eval_init) != "present":
                return f"command operand escapes checkout ({eval_init})"
            rel_mod = part.replace(".", "/") + ".py"
            if _classify_suite_path(repo_root, rel_mod) != "present":
                return f"command operand is missing or outside checkout ({_terminal_safe(rel_mod)})"
        elif part == "packages/ccl-skills-npm":
            if _classify_suite_path(repo_root, "packages/ccl-skills-npm/package.json") != "present":
                return "packages/ccl-skills-npm/package.json is missing or outside checkout"
    return None


def _run_cmd(
    cmd: list[str],
    cwd: Path,
    *,
    resolved_base: str | None = None,
    template_dir: Path | None = None,
) -> int:
    rendered = " ".join(_terminal_safe(part) for part in cmd)
    print(f"==> {rendered}", flush=True)
    env = _clean_child_env(resolved_base=resolved_base, template_dir=template_dir)
    try:
        proc = subprocess.Popen(cmd, cwd=str(cwd), env=env, start_new_session=True)
    except FileNotFoundError as exc:
        print(f"select-affected-tests: error: executable not found ({_terminal_safe(cmd[0])}): {exc}", file=sys.stderr)
        return 127
    except OSError as exc:
        print(f"select-affected-tests: error: failed to launch {_terminal_safe(cmd[0])}: {exc}", file=sys.stderr)
        return 126

    received_sig: list[int] = []

    def _forward_signal(signum: int, _frame) -> None:
        if not received_sig:
            received_sig.append(signum)
        try:
            os.killpg(proc.pid, signum)
        except ProcessLookupError:
            pass

    watched_signals = [signal.SIGINT, signal.SIGTERM]
    if hasattr(signal, "SIGHUP"):
        watched_signals.append(signal.SIGHUP)
    previous_handlers = {sig: signal.getsignal(sig) for sig in watched_signals}
    try:
        for sig in watched_signals:
            signal.signal(sig, _forward_signal)
        while True:
            try:
                rc = proc.wait()
                break
            except KeyboardInterrupt:
                _forward_signal(signal.SIGINT, None)
                break
        if received_sig and proc.poll() is None:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
    finally:
        for sig, prev in previous_handlers.items():
            signal.signal(sig, prev)

    if received_sig:
        return 128 + received_sig[0]
    if proc.returncode is not None and proc.returncode < 0:
        return 128 + (-proc.returncode)
    return proc.returncode if proc.returncode is not None else 1


def _emit_diagnostics(plan: dict) -> None:
    for note in plan.get("notes") or []:
        print(f"note: {_terminal_safe(note)}", flush=True)
    skipped = plan.get("skipped_lanes") or []
    if skipped:
        print(f"skipped: {', '.join(_terminal_safe(s) for s in skipped)}", flush=True)


def execute_plan(plan: dict, repo_root: Path, jobs: int | None = None) -> int:
    resolved_base_ref = plan.get("resolved_base_ref")
    resolved_base_sha = plan.get("resolved_base_sha") or resolved_base_ref
    print(
        f"select_affected_tests: base_ref={_terminal_safe(resolved_base_ref) if resolved_base_ref else 'none'}",
        flush=True,
    )

    if plan.get("unsafe_blocked"):
        _emit_diagnostics(plan)
        print("select_affected_tests_failed: exit=2", flush=True)
        print(ADVISORY_FOOTER, flush=True)
        return 2

    changed = plan.get("changed_files") or []
    preflights = plan.get("preflight_commands") or []
    suites = plan.get("parallel_suites") or []
    serials = plan.get("serial_commands") or []

    if not changed and not preflights and not suites and not serials:
        _emit_diagnostics(plan)
        print("select_affected_tests_done: 0 changed files; nothing to run.")
        print(ADVISORY_FOOTER, flush=True)
        return 0

    print(
        f"select_affected_tests: {len(changed)} changed file(s) -> "
        f"{len(preflights)} preflight, "
        f"{len(suites)} parallel suite(s), "
        f"{len(serials)} serial command(s)",
        flush=True,
    )

    with tempfile.TemporaryDirectory() as tpl_tmp:
        tpl_dir = Path(tpl_tmp)
        (tpl_dir / "info").mkdir(parents=True, exist_ok=True)

        for cmd in preflights:
            violation = _verify_command_containment(repo_root, cmd)
            if violation:
                print(f"select-affected-tests: error: {violation}", file=sys.stderr)
                _emit_diagnostics(plan)
                print("select_affected_tests_failed: exit=2", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return 2
            rc = _run_cmd(cmd, repo_root, resolved_base=resolved_base_sha, template_dir=tpl_dir)
            if rc != 0:
                _emit_diagnostics(plan)
                print(f"select_affected_tests_failed: exit={rc}", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return rc

        if suites:
            if _classify_suite_path(repo_root, "scripts/run-parallel-suites.sh") != "present":
                print("select-affected-tests: error: scripts/run-parallel-suites.sh missing or uncontained", file=sys.stderr)
                _emit_diagnostics(plan)
                print("select_affected_tests_failed: exit=2", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return 2
            for suite in suites:
                if _classify_suite_path(repo_root, suite) != "present":
                    print(
                        f"select-affected-tests: error: suite missing or outside checkout at dispatch ({_terminal_safe(suite)})",
                        file=sys.stderr,
                    )
                    _emit_diagnostics(plan)
                    print("select_affected_tests_failed: exit=2", flush=True)
                    print(ADVISORY_FOOTER, flush=True)
                    return 2
            runner = str(repo_root / "scripts/run-parallel-suites.sh")
            parallel_cmd = _parallel_runner_command(runner, suites, jobs)
            rc = _run_cmd(parallel_cmd, repo_root, resolved_base=resolved_base_sha, template_dir=tpl_dir)
            if rc != 0:
                _emit_diagnostics(plan)
                print(f"select_affected_tests_failed: exit={rc}", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return rc

        for cmd in serials:
            violation = _verify_command_containment(repo_root, cmd)
            if violation:
                print(f"select-affected-tests: error: {violation}", file=sys.stderr)
                _emit_diagnostics(plan)
                print("select_affected_tests_failed: exit=2", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return 2
            rc = _run_cmd(cmd, repo_root, resolved_base=resolved_base_sha, template_dir=tpl_dir)
            if rc != 0:
                _emit_diagnostics(plan)
                print(f"select_affected_tests_failed: exit={rc}", flush=True)
                print(ADVISORY_FOOTER, flush=True)
                return rc

    _emit_diagnostics(plan)
    print("select_affected_tests_done", flush=True)
    print(ADVISORY_FOOTER, flush=True)
    return 0


def print_dry_run(
    plan: dict,
    repo_root: Path,
    resolved_base: str | None,
    *,
    resolved_base_sha: str | None = None,
    jobs: int | None = None,
) -> None:
    print(_comment_line("base_ref: ", resolved_base or "none"))
    changed = plan.get("changed_files") or []
    print(f"# changed_files ({len(changed)}):")
    for f in changed:
        print(_comment_line("  - ", f))

    if plan.get("unsafe_blocked"):
        skipped = plan.get("skipped_lanes") or []
        if skipped:
            print(_comment_line("skipped: ", ", ".join(skipped)))
        for note in plan.get("notes") or [] :
            print(_comment_line("note: ", note))
        print("# blocked: unsafe path detected; refusing to emit runnable commands")
        print("(exit 2)")
        print(f"# {ADVISORY_FOOTER}")
        return

    has_commands = bool(
        (plan.get("preflight_commands") or [])
        or (plan.get("parallel_suites") or [])
        or (plan.get("serial_commands") or [])
    )
    if has_commands:
        print(f"cd -- {_shell_quote(str(repo_root.resolve()))}")
        unset_keys = " ".join(
            k
            for k in (*GIT_REPOSITORY_ROUTING_ENV, *GIT_CONFIG_ROUTING_ENV, *_MAKE_ENV_POLLUTION_KEYS)
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k)
        )
        print(f"unset {unset_keys}")
        print('_affected_tpl="$(mktemp -d)" && mkdir -p "$_affected_tpl/info" && trap \'rm -rf "$_affected_tpl"\' EXIT')
        print(
            f'export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL={_shell_quote(os.devnull)} '
            f'GIT_CONFIG_SYSTEM={_shell_quote(os.devnull)} GIT_TERMINAL_PROMPT=0 GIT_TEMPLATE_DIR="$_affected_tpl"'
        )
        base_val = resolved_base_sha or resolved_base
        if base_val:
            print(f"export CCL_SKILL_BASE_REF={_shell_quote(base_val)}")
        else:
            print("unset CCL_SKILL_BASE_REF")

    for cmd in plan.get("preflight_commands") or []:
        print(" ".join(_shell_quote(part) for part in cmd))
    suites = plan.get("parallel_suites") or []
    if suites:
        parallel_cmd = _parallel_runner_command("scripts/run-parallel-suites.sh", suites, jobs)
        print(" ".join(_shell_quote(part) for part in parallel_cmd))
    for cmd in plan.get("serial_commands") or []:
        print(" ".join(_shell_quote(part) for part in cmd))
    skipped = plan.get("skipped_lanes") or []
    if skipped:
        print(_comment_line("skipped: ", ", ".join(skipped)))
    for note in plan.get("notes") or []:
        print(_comment_line("note: ", note))
    print(f"# {ADVISORY_FOOTER}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Advisory path-based test selector and runner for ccl-skills inner-loop iteration."
    )
    parser.add_argument("--repo", default=".", help="Repository worktree root (default: .)")
    parser.add_argument("--base-ref", default=None, help="Explicit git base ref for branch diff")
    parser.add_argument(
        "--default-base-ref",
        default=(
            os.environ.get("CCL_SKILL_DEFAULT_BASE_REF")
            or os.environ.get("CCL_SKILL_SELECTED_DEFAULT_BASE")
            or "origin/dev"
        ),
        help="Default integration base ref candidate (default: CCL_SKILL_DEFAULT_BASE_REF or origin/dev)",
    )
    parser.add_argument(
        "--files",
        nargs="*",
        default=None,
        help="Explicit repo-relative file list (bypasses git status/diff discovery)",
    )
    parser.add_argument("--include-slow", action="store_true", help="Include slow abort-leak / heavy-clone / pack suites")
    parser.add_argument("--with-npm", action="store_true", help="Run npm ci + tests when packaged paths change")
    parser.add_argument("--jobs", type=int, default=None, help="Max concurrency for run-parallel-suites.sh")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Print shell-quoted selected commands without executing")
    mode.add_argument("--json", action="store_true", help="Print machine-readable selection plan as JSON")
    mode.add_argument("--run", action="store_true", help="Execute selected commands (default)")

    if argv is None:
        raw_extra = os.environ.get("AFFECTED_ARGS", "").strip()
        extra_tokens: list[str] = []
        if raw_extra:
            try:
                extra_tokens = shlex.split(raw_extra, posix=True)
            except ValueError as exc:
                raise SelectorError(f"invalid AFFECTED_ARGS: {exc}") from exc
        argv = [*sys.argv[1:], *extra_tokens]
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
    except SelectorError as exc:
        print(f"select-affected-tests: error: {exc}", file=sys.stderr)
        return 2

    if args.jobs is not None and args.jobs < 1:
        print("select-affected-tests: error: --jobs must be >= 1", file=sys.stderr)
        return 2

    raw_repo = Path(args.repo)
    try:
        repo_root = verify_repo_root(raw_repo)
        if args.files is not None:
            changed = list(args.files)
            resolved_base, resolved_sha, mb_sha, head_sha = _resolve_base_with_merge_base(
                repo_root,
                explicit_base=args.base_ref,
                default_base_ref=args.default_base_ref,
                allow_missing_auto=True,
            )
            has_commits = bool(mb_sha and head_sha and head_sha != mb_sha)
            untracked: list[str] = []
        else:
            changed, resolved_base, resolved_sha, mb_sha, head_sha, has_commits, untracked = _discover_candidate(
                repo_root,
                base_ref=args.base_ref,
                default_base_ref=args.default_base_ref,
            )
    except SelectorError as exc:
        print(f"select-affected-tests: error: {exc}", file=sys.stderr)
        return 2

    plan = build_test_plan(
        changed,
        repo_root=repo_root,
        default_base_ref=args.default_base_ref,
        resolved_base_ref=resolved_base,
        resolved_base_sha=resolved_sha,
        merge_base_sha=mb_sha,
        head_sha=head_sha,
        has_candidate_commits=has_commits,
        untracked_files=untracked,
        include_slow=args.include_slow or os.environ.get("FULL") == "1",
        with_npm=args.with_npm,
    )
    plan["resolved_base_ref"] = resolved_base
    plan["resolved_base_sha"] = resolved_sha
    plan["advisory"] = ADVISORY_FOOTER

    if args.json:
        print(json.dumps(_json_safe(plan), ensure_ascii=False, indent=2))
        return 2 if plan.get("unsafe_blocked") else 0
    if args.dry_run:
        print_dry_run(
            plan,
            repo_root,
            resolved_base,
            resolved_base_sha=resolved_sha,
            jobs=args.jobs,
        )
        return 2 if plan.get("unsafe_blocked") else 0
    return execute_plan(plan, repo_root, jobs=args.jobs)


if __name__ == "__main__":
    try:
        rc = main()
        sys.stdout.flush()
        sys.stderr.flush()
        raise SystemExit(rc)
    except BrokenPipeError:
        try:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, sys.stdout.fileno())
            os.close(devnull)
        except OSError:
            pass
        raise SystemExit(141)
