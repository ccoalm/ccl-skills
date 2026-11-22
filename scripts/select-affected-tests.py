#!/usr/bin/env python3
"""Path-based incremental test selector and runner for ccl-skills.

Maps changed files (branch diff against merge-base + staged + unstaged + untracked)
to the minimal sound set of repository preflight gates, parallel isolated suites,
and serial verification commands.

Usage:
  python3 scripts/select-affected-tests.py [--repo .] [--base-ref REF] [--dry-run|--json|--run]
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True

# The Makefile is the one registry of suites `make test` runs. Suite sets that must stay
# complete (the hook fallback) are derived from it instead of being copied here, so a new
# suite added to the Makefile is picked up without editing this file.
_MAKEFILE_SUITE_RE = re.compile(
    r"(?<![\w./-])((?:hooks|scripts|skills|eval)/[\w./-]*?(?:test_[\w.-]+|[\w-]+\.test|/test)\.(?:sh|py))(?![\w./-])"
)


def makefile_suites(repo_root: Path) -> set[str]:
    """Return every suite file path named in the repository Makefile that exists on disk."""
    makefile = repo_root / "Makefile"
    try:
        text = makefile.read_text(encoding="utf-8")
    except OSError:
        return set()
    return {m for m in _MAKEFILE_SUITE_RE.findall(text) if (repo_root / m).is_file()}


def sibling_suites(repo_root: Path, path: str) -> list[str]:
    """Suites that test `path` by naming convention: the file itself if it is a suite,
    else `<dir>/test_<stem>.{py,sh}` with `-` mapped to `_`."""
    rel = Path(path)
    name = rel.name
    if name.startswith("test_") and name.endswith((".py", ".sh")):
        return [path] if (repo_root / path).is_file() else []
    if not name.endswith((".py", ".sh")):
        return []
    stem = rel.stem.replace("-", "_")
    found = []
    for ext in (".py", ".sh"):
        candidate = (rel.parent / f"test_{stem}{ext}").as_posix()
        if (repo_root / candidate).is_file():
            found.append(candidate)
    return found


HOOK_FILE_MAP: dict[str, tuple[str, ...]] = {
    "hooks/host-input.py": (
        "hooks/test_host_input.py",
        "hooks/test_skill_loading.py",
        "hooks/test_task_entry.py",
        "hooks/test_proposed_next.py",
        "hooks/test_headless_background_stop.sh",
    ),
    "hooks/test_host_input.py": ("hooks/test_host_input.py",),
    "hooks/skill-loading.py": (
        "hooks/test_skill_loading.py",
        "hooks/test_guard_delegation_owner.sh",
        "hooks/test_proposed_next.py",
        "hooks/test_headless_background_stop.sh",
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
    "hooks/merge-authorization-prompt.sh": ("hooks/test_merge_authorization_prompt.sh",),
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

CODE_REVIEW_SHARD_SUITES = (
    "skills/code-review/scripts/test_classify_envelope.sh",
    "skills/code-review/scripts/test_concern_excerpt.sh",
    "skills/code-review/scripts/test_parse_opencode_review.sh",
    "skills/code-review/scripts/test_egress_schema.sh",
    "skills/code-review/scripts/test_parse_probe_result.sh",
    "skills/code-review/scripts/test_init_policy_matrix.sh",
    "skills/code-review/scripts/test_parse_review_json.sh",
    "skills/code-review/scripts/test_opencode_review_retry.sh",
    "skills/code-review/scripts/test_abort_leak_state_helpers.sh",
    "skills/code-review/scripts/test_review_diff.sh",
    "skills/code-review/scripts/test_claude_review_probe.sh",
    "skills/code-review/scripts/test_opencode_review_concurrency.sh",
    "skills/code-review/scripts/test_review_gate.sh",
    "skills/code-review/scripts/test_update_review_plan_intent.sh",
    "skills/code-review/scripts/test_review_client_order.sh",
    "skills/code-review/scripts/test_cli_review_wrappers.sh",
    "skills/code-review/scripts/test_review_client_compat.py",
    "skills/code-review/scripts/test_code_review_identity.sh",
)

CODE_REVIEW_LEAF_MAP: dict[str, tuple[str, ...]] = {
    "classify_envelope.py": (
        "skills/code-review/scripts/test_classify_envelope.sh",
        "skills/code-review/scripts/test_claude_review_probe.sh",
        "skills/code-review/scripts/test_review_gate.sh",
    ),
    "concern_excerpt.py": ("skills/code-review/scripts/test_concern_excerpt.sh",),
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
    "parse_cli_review.py": ("skills/code-review/scripts/test_cli_review_wrappers.sh",),
    "classify_timeout_exit.sh": ("skills/code-review/scripts/test_cli_review_wrappers.sh",),
    "normalize_review_timeout.sh": ("skills/code-review/scripts/test_cli_review_wrappers.sh",),
    "test_abort_leak_readiness.py": ("skills/code-review/scripts/test_abort_leak_state_helpers.sh",),
}


def _git_lines(repo_root: Path, *args: str) -> list[str] | None:
    proc = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    return [line.strip() for line in proc.stdout.splitlines() if line.strip()]


class BaseRefError(Exception):
    """An explicitly requested base ref has no merge-base with HEAD."""


def resolve_base_ref(repo_root: Path, explicit_base: str | None = None) -> str | None:
    if explicit_base:
        # An explicit ref must resolve: silently diffing against a different base would
        # select suites for the wrong change set.
        if _git_lines(repo_root, "merge-base", explicit_base, "HEAD"):
            return explicit_base
        raise BaseRefError(f"--base-ref {explicit_base!r} has no merge-base with HEAD")
    for env_key in ("CCL_SKILL_BASE_REF", "CCL_SKILL_DEFAULT_BASE_REF"):
        val = os.environ.get(env_key, "").strip()
        if val and _git_lines(repo_root, "merge-base", val, "HEAD"):
            return val
    # No explicit choice: of the usual integration refs, use the one whose merge-base is
    # nearest HEAD. A stale integration branch (far behind main) would otherwise turn
    # every commit since it into "changed" files.
    best: tuple[int, str] | None = None
    for ref in ("origin/dev", "origin/main", "main"):
        mb = _git_lines(repo_root, "merge-base", ref, "HEAD")
        if not mb:
            continue
        count = _git_lines(repo_root, "rev-list", "--count", f"{mb[0]}..HEAD")
        if not count:
            continue
        distance = int(count[0])
        if best is None or distance < best[0]:
            best = (distance, ref)
    if best is not None:
        return best[1]
    if _git_lines(repo_root, "merge-base", "HEAD~1", "HEAD"):
        return "HEAD~1"
    return None


def normalize_relpath(raw: str) -> str:
    cleaned = raw.strip().replace("\\", "/")
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    return cleaned.strip("/")


def collect_changed_files(
    repo_root: Path,
    base_ref: str | None = None,
) -> tuple[list[str], str | None]:
    resolved = resolve_base_ref(repo_root, base_ref)
    found: set[str] = set()
    if resolved:
        mb = _git_lines(repo_root, "merge-base", resolved, "HEAD")
        if mb:
            # --no-renames: a rename must report the old path too, so suites keyed on it run.
            committed = _git_lines(repo_root, "diff", "--no-renames", "--name-only", f"{mb[0]}...HEAD") or []
            found.update(committed)
    for diff_args in (
        ("diff", "--cached", "--no-renames", "--name-only"),
        ("diff", "--no-renames", "--name-only"),
        ("ls-files", "--others", "--exclude-standard"),
    ):
        lines = _git_lines(repo_root, *diff_args) or []
        found.update(lines)

    normalized = sorted(
        p
        for p in (normalize_relpath(item) for item in found)
        if p and not p.startswith(".work/")
    )
    return normalized, resolved


class _PlanBuilder:
    def __init__(self, repo_root: Path, default_base_ref: str, include_slow: bool, with_npm: bool):
        self.repo_root = repo_root
        self.default_base_ref = default_base_ref
        self.include_slow = include_slow
        self.with_npm = with_npm
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

    def add_suite(self, rel_suite: str) -> None:
        if rel_suite in self._parallel_seen:
            return
        self._parallel_seen.add(rel_suite)
        if (self.repo_root / rel_suite).is_file():
            self.parallel_suites.append(rel_suite)
        else:
            # A mapped suite that no longer exists means this selector's map has drifted;
            # the plan escalates to the full lanes rather than dropping coverage silently.
            self.missing_suites.append(rel_suite)

    def add_changed_suite(self, rel_suite: str) -> None:
        """Add a suite that is itself in the change set; a deleted one is a normal change."""
        if (self.repo_root / rel_suite).is_file():
            self.add_suite(rel_suite)

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
    include_slow: bool = False,
    with_npm: bool = False,
) -> dict:
    cleaned = [
        p
        for p in dict.fromkeys(normalize_relpath(f) for f in changed_files)
        if p and not p.startswith(".work/")
    ]
    builder = _PlanBuilder(
        repo_root=repo_root,
        default_base_ref=default_base_ref,
        include_slow=include_slow,
        with_npm=with_npm,
    )
    if not cleaned:
        return {
            "changed_files": [],
            "preflight_commands": [],
            "parallel_suites": [],
            "serial_commands": [],
            "npm_required": False,
            "notes": [],
            "skipped_lanes": [],
            "missing_suites": [],
        }

    # Always-on fast deterministic preflight (~4-6s).
    builder.preflight_commands.extend(
        [
            ["git", "diff", "--check"],
            ["bash", "skills/skill-extraction-workflow/scripts/check-ccl-skills.sh", "."],
            [
                "python3",
                "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py",
                "--repo",
                ".",
                "--default-base-ref",
                default_base_ref,
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
    need_routing_gates = False
    need_sanitization = False
    need_skill_count = False
    need_release_version = False
    need_eval_unittest = False
    need_pytest_report = False
    need_fast_regressions = False
    fallback_full = False

    hook_suites = sorted(s for s in makefile_suites(repo_root) if s.startswith("hooks/"))

    for path in cleaned:
        lower = path.lower()
        is_md = lower.endswith((".md", ".mdx"))

        # Convention rule, independent of the hand-written maps below: a changed suite runs
        # itself, and a changed `x-y.py` runs its sibling `test_x_y.*`.
        for suite in sibling_suites(repo_root, path):
            builder.add_suite(suite)

        if is_md or path.startswith(("docs/", "specs/", "agent-context/")):
            need_doc_gates = True
            need_sanitization = True

        if path in ("opencode.json", "AGENTS.md") or path.startswith(("skills/", "agent-context/")):
            need_routing_gates = True
            need_skill_count = True
            need_sanitization = True

        if path in (
            "README.md",
            "LICENSE",
            "opencode.json",
            "Makefile",
            "requirements-test.txt",
        ) or path.startswith((".github/", "docs/", "specs/")):
            if path in ("Makefile", "requirements-test.txt") or path.startswith(".github/"):
                builder.add_suite("skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh")
                builder.add_suite("scripts/test_lane_isolation.py")
                builder.add_suite("scripts/test_run_parallel_suites.sh")
                builder.add_suite("scripts/test_select_affected_tests.py")
            if path == "opencode.json":
                builder.npm_required = True
                need_release_version = True
                builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
            continue

        if path.startswith((".claude-plugin/", ".codex-plugin/", ".agents/", "packages/")):
            builder.npm_required = True
            need_release_version = True
            builder.add_suite("scripts/test_check_release_version.py")
            builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
            builder.add_suite("scripts/test_install_status.py")
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
            else:
                # hooks/hooks.json or new/unmapped hook script: run every Makefile hook suite + installer checks.
                for suite in hook_suites:
                    builder.add_suite(suite)
                builder.add_suite("scripts/test_install_opencode_skill_migration.sh")
                builder.npm_required = True
            continue

        if path.startswith("scripts/"):
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
                need_sanitization = True
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
            elif path in ("scripts/install.sh", "scripts/test_install_status.py"):
                builder.add_suite("scripts/test_install_status.py")
            elif path in ("scripts/install-gates.sh", "scripts/test_install_gates_runtime.py"):
                builder.add_suite("scripts/test_install_gates_runtime.py")
            elif path.startswith("scripts/owner-dispatch/"):
                builder.add_suite("scripts/owner-dispatch/test.sh")
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
                if include_slow and shutil.which("docker"):
                    builder.add_serial(["bash", "scripts/verify-sandbox/test.sh"])
                else:
                    builder.add_skip(
                        "verify-sandbox",
                        "verify-sandbox: run 'make test-verify-sandbox' on a machine with Docker enabled."
                    )
            else:
                fallback_full = True
            continue

        if path.startswith("eval/"):
            need_eval_unittest = True
            builder.add_suite("skills/skill-extraction-workflow/scripts/test_body_compliance_grading.sh")
            continue

        if path.startswith("skills/"):
            parts = path.split("/")
            skill_name = parts[1] if len(parts) >= 2 else ""

            if skill_name == "code-review":
                if len(parts) >= 4 and parts[2] == "scripts":
                    fname = parts[3]
                    if fname.endswith(".md"):
                        continue
                    builder.add_suite("scripts/test_lane_isolation.py")
                    if fname in CODE_REVIEW_LEAF_MAP:
                        for suite in CODE_REVIEW_LEAF_MAP[fname]:
                            builder.add_suite(suite)
                    elif fname == "test_review_gate_abort_leak.sh":
                        builder.abort_leak_needed = True
                    elif fname.startswith("test_") and fname.endswith((".sh", ".py")):
                        builder.add_changed_suite(path)
                    else:
                        # review_gate.py, review_gate.sh, or shared/unknown code-review script
                        for suite in CODE_REVIEW_SHARD_SUITES:
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
                    if fname.startswith("test_") and fname.endswith(".py"):
                        builder.add_changed_suite(path)
                    elif fname.startswith("test_") and fname.endswith(".sh") and fname != "test_check_ccl_regressions.sh":
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

            # All other skills under skills/<name>/ (pure SKILL.md / references / scripts):
            if len(parts) >= 3 and parts[2] == "scripts" and not is_md:
                # Any sibling test_* in that skill's scripts dir
                skill_scripts_dir = repo_root / "skills" / skill_name / "scripts"
                if skill_scripts_dir.is_dir():
                    for candidate in sorted(skill_scripts_dir.iterdir()):
                        if candidate.is_file() and (
                            candidate.name.startswith("test_") or candidate.name.endswith((".test.sh", "_test.py"))
                        ):
                            builder.add_suite(candidate.relative_to(repo_root).as_posix())
            continue

        # Unrecognized root path: fail-safe fallback.
        fallback_full = True

    if need_doc_gates:
        builder.add_serial(["python3", "scripts/check-markdown-links.py", "."])
        builder.add_serial(["python3", "scripts/check-spec-references.py", "."])
        builder.add_serial(["python3", "skills/tighten-doc/scripts/doc-lint-repo.py", "."])

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
        builder.add_serial(
            ["python3", "-m", "pytest", "-q", "skills/test-artifact-management/references/test_gen_report.py"]
        )

    if need_eval_unittest:
        builder.add_serial(
            [
                "python3",
                "-m",
                "unittest",
                "eval.test_subagent_owner_audit",
                "eval.test_skill_effectiveness_bridge",
                "eval.test_skill_effectiveness_trial",
                "eval.test_reviewer_calibration_protocol",
                "eval.test_design_judge",
            ]
        )

    if need_fast_regressions:
        builder.add_serial(
            ["bash", "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh", "--fast"]
        )

    if builder.heavy_regressions_needed:
        if include_slow:
            builder.add_serial(
                ["bash", "skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh", "--heavy-only"]
            )
        else:
            builder.add_skip(
                "heavy-regressions",
                "heavy-regressions: skipped clone-heavy suites; pass --include-slow or run 'make test-check-ccl-regressions' before PR."
            )

    if builder.abort_leak_needed:
        if include_slow:
            builder.add_serial(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=1",
                    "ABORT_LEAK_PROBE_CLIENT=claude",
                    "bash",
                    "skills/code-review/scripts/test_review_gate_abort_leak.sh",
                ]
            )
            builder.add_serial(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=2",
                    "ABORT_LEAK_PROBE_CLIENT=fallback",
                    "bash",
                    "skills/code-review/scripts/test_review_gate_abort_leak.sh",
                ]
            )
            builder.add_serial(
                [
                    "env",
                    "ABORT_LEAK_PROBE_LEG=2",
                    "ABORT_LEAK_PROBE_CLIENT=claude",
                    "bash",
                    "skills/code-review/scripts/test_review_gate_abort_leak.sh",
                ]
            )
        else:
            builder.add_skip(
                "abort-leak",
                "abort-leak: skipped slow abort-leak probes (~3 min); pass --include-slow or run 'make test-code-review-abort-leak' before landing."
            )

    if builder.npm_required:
        npm_nm = repo_root / "packages/ccl-skills-npm/node_modules"
        if with_npm or npm_nm.is_dir():
            if not npm_nm.is_dir():
                builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "ci"])
            builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "test"])
            if include_slow:
                builder.add_serial(["npm", "--prefix", "packages/ccl-skills-npm", "run", "test:pack"])
        else:
            builder.add_skip(
                "npm-packages",
                "npm-packages: packages/ccl-skills-npm/node_modules not installed; pass --with-npm or run 'make npm-test npm-pack-verify'."
            )

    if builder.missing_suites:
        builder.add_note(
            "selector-drift: mapped suite(s) missing on disk ("
            + ", ".join(builder.missing_suites)
            + "); update scripts/select-affected-tests.py. Escalating to the full lanes."
        )
        fallback_full = True

    if fallback_full:
        builder.add_note("fallback: unrecognized path or selector drift; escalating to make test-repo-gates + test-regressions-fast.")
        builder.add_serial(["make", "test-repo-gates"])
        builder.add_serial(["make", "test-regressions-fast"])

    return {
        "changed_files": cleaned,
        "preflight_commands": builder.preflight_commands,
        "parallel_suites": builder.parallel_suites,
        "serial_commands": builder.serial_commands,
        "npm_required": builder.npm_required,
        "notes": builder.notes,
        "skipped_lanes": builder.skipped_lanes,
        "missing_suites": builder.missing_suites,
    }


_MAKE_ENV_POLLUTION_KEYS = (
    "MAKEFLAGS",
    "MFLAGS",
    "MAKELEVEL",
    "MAKEOVERRIDES",
    "GNUMAKEFLAGS",
    "-*-command-variables-*-",
    "CCL_SKILL_DEFAULT_BASE_REF",
)


def _clean_child_env(base_env: dict[str, str] | None = None) -> dict[str, str]:
    """Strip outer GNU Make command-line override vars so child suites see clean Makefile defaults."""
    env = dict(os.environ if base_env is None else base_env)
    for key in _MAKE_ENV_POLLUTION_KEYS:
        env.pop(key, None)
    return env


def _run_cmd(cmd: list[str], cwd: Path) -> int:
    print(f"==> {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, cwd=str(cwd), env=_clean_child_env())
    return proc.returncode


def execute_plan(plan: dict, repo_root: Path, jobs: int | None = None) -> int:
    if not plan["changed_files"]:
        print("select_affected_tests_ok: 0 changed files; nothing to run.")
        return 0

    print(
        f"select_affected_tests: {len(plan['changed_files'])} changed file(s) -> "
        f"{len(plan['preflight_commands'])} preflight, "
        f"{len(plan['parallel_suites'])} parallel suite(s), "
        f"{len(plan['serial_commands'])} serial command(s)",
        flush=True,
    )

    for cmd in plan["preflight_commands"]:
        rc = _run_cmd(cmd, repo_root)
        if rc != 0:
            return rc

    suites = plan["parallel_suites"]
    if suites:
        runner = repo_root / "scripts/run-parallel-suites.sh"
        parallel_cmd = ["bash", str(runner), "--label", "affected_suites"]
        if jobs is not None:
            parallel_cmd.extend(["--jobs", str(jobs)])
        parallel_cmd.extend(suites)
        rc = _run_cmd(parallel_cmd, repo_root)
        if rc != 0:
            return rc

    for cmd in plan["serial_commands"]:
        rc = _run_cmd(cmd, repo_root)
        if rc != 0:
            return rc

    for note in plan["notes"]:
        print(f"note: {note}", flush=True)

    skipped = plan.get("skipped_lanes") or []
    if skipped:
        # Everything that ran passed, but selected lanes were skipped: not a full "ok".
        print(f"select_affected_tests_partial: skipped {', '.join(skipped)} (see notes)")
        return 0
    print("select_affected_tests_ok")
    return 0


def print_dry_run(plan: dict, resolved_base: str | None) -> None:
    print(f"# base_ref: {resolved_base or 'none'}")
    print(f"# changed_files ({len(plan['changed_files'])}):")
    for f in plan["changed_files"]:
        print(f"#   - {f}")
    for cmd in plan["preflight_commands"]:
        print(" ".join(cmd))
    if plan["parallel_suites"]:
        print("bash scripts/run-parallel-suites.sh --label affected_suites " + " ".join(plan["parallel_suites"]))
    for cmd in plan["serial_commands"]:
        print(" ".join(cmd))
    for note in plan["notes"]:
        print(f"# note: {note}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select and run affected test suites for changed files in ccl-skills."
    )
    parser.add_argument("--repo", default=".", help="Repository root (default: .)")
    parser.add_argument("--base-ref", default=None, help="Explicit git base ref for branch diff")
    parser.add_argument(
        "--default-base-ref",
        default=os.environ.get("CCL_SKILL_DEFAULT_BASE_REF", "origin/dev"),
        help="Default base ref passed to shared_git_surface_gate.py",
    )
    parser.add_argument(
        "--files",
        nargs="*",
        default=None,
        help="Explicit repo-relative file list (bypasses git status/diff discovery)",
    )
    parser.add_argument("--include-slow", action="store_true", help="Include slow abort-leak / heavy-clone / pack suites")
    parser.add_argument("--with-npm", action="store_true", help="Bootstrap and run npm package tests when packages/ changes")
    parser.add_argument("--jobs", type=int, default=None, help="Max concurrency for run-parallel-suites.sh")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Print selected commands without executing")
    mode.add_argument("--json", action="store_true", help="Print machine-readable selection plan as JSON")
    mode.add_argument("--run", action="store_true", help="Execute selected commands (default)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repo_root = Path(args.repo).resolve()
    if args.files is not None:
        changed = list(args.files)
        resolved_base = args.base_ref
    else:
        try:
            changed, resolved_base = collect_changed_files(repo_root, base_ref=args.base_ref)
        except BaseRefError as exc:
            print(f"select-affected-tests: error: {exc}", file=sys.stderr)
            return 2

    plan = build_test_plan(
        changed,
        repo_root=repo_root,
        default_base_ref=args.default_base_ref,
        include_slow=args.include_slow or os.environ.get("FULL") == "1",
        with_npm=args.with_npm,
    )
    plan["resolved_base_ref"] = resolved_base

    if args.json:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return 0
    if args.dry_run:
        print_dry_run(plan, resolved_base)
        return 0
    return execute_plan(plan, repo_root, jobs=args.jobs)


if __name__ == "__main__":
    sys.exit(main())
