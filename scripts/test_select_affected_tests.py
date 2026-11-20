#!/usr/bin/env python3
"""Unit and integration tests for scripts/select-affected-tests.py."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parent
SELECTOR_PATH = SCRIPTS_DIR / "select-affected-tests.py"


def load_selector():
    if not SELECTOR_PATH.is_file():
        raise FileNotFoundError(f"missing selector script: {SELECTOR_PATH}")
    spec = importlib.util.spec_from_file_location("select_affected_tests", SELECTOR_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


class SelectAffectedTestsUnit(unittest.TestCase):
    def test_clean_changeset_selects_nothing(self):
        mod = load_selector()
        plan = mod.build_test_plan([], repo_root=REPO_ROOT)
        self.assertEqual(plan["changed_files"], [])
        self.assertEqual(plan["preflight_commands"], [])
        self.assertEqual(plan["parallel_suites"], [])
        self.assertEqual(plan["serial_commands"], [])

    def test_pure_skill_markdown_skips_heavy_code_review_and_hook_suites(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["skills/typescript-dev/SKILL.md"],
            repo_root=REPO_ROOT,
        )
        all_items = (
            [" ".join(cmd) for cmd in plan["preflight_commands"]]
            + plan["parallel_suites"]
            + [" ".join(cmd) for cmd in plan["serial_commands"]]
        )
        joined = "\n".join(all_items)
        self.assertIn("check-ccl-skills.sh", joined)
        self.assertIn("eval-routing.rb", joined)
        self.assertIn("check-markdown-links.py", joined)
        self.assertIn("check-public-sanitization.py", joined)
        self.assertIn("test_obligation_ledger_repo_audit.sh", joined)
        self.assertNotIn("test_init_policy_matrix.sh", joined)
        self.assertNotIn("test_review_gate_abort_leak.sh", joined)
        self.assertNotIn("test_guard_merge_authorization.sh", joined)

    def test_narrow_hook_change_selects_only_target_hook_suite(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["hooks/remind-untracked-background.sh"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "hooks/test_remind_untracked_background.sh",
            plan["parallel_suites"],
        )
        self.assertNotIn(
            "hooks/test_guard_merge_authorization.sh",
            plan["parallel_suites"],
        )
        self.assertNotIn(
            "skills/code-review/scripts/test_review_gate.sh",
            plan["parallel_suites"],
        )

    def test_shared_hook_helper_fans_out_to_dependent_hook_suites(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["hooks/host-input.py"],
            repo_root=REPO_ROOT,
        )
        for expected in (
            "hooks/test_host_input.py",
            "hooks/test_skill_loading.py",
            "hooks/test_task_entry.py",
            "hooks/test_proposed_next.py",
            "hooks/test_headless_background_stop.sh",
        ):
            self.assertIn(expected, plan["parallel_suites"])

    def test_code_review_leaf_script_vs_core_gate_fanout(self):
        mod = load_selector()
        leaf_plan = mod.build_test_plan(
            ["skills/code-review/scripts/concern_excerpt.py"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "skills/code-review/scripts/test_concern_excerpt.sh",
            leaf_plan["parallel_suites"],
        )
        self.assertIn(
            "scripts/test_lane_isolation.py",
            leaf_plan["parallel_suites"],
        )
        self.assertNotIn(
            "skills/code-review/scripts/test_init_policy_matrix.sh",
            leaf_plan["parallel_suites"],
        )

        core_plan = mod.build_test_plan(
            ["skills/code-review/scripts/review_gate.py"],
            repo_root=REPO_ROOT,
            include_slow=False,
        )
        self.assertIn(
            "skills/code-review/scripts/test_review_gate.sh",
            core_plan["parallel_suites"],
        )
        self.assertIn(
            "skills/code-review/scripts/test_init_policy_matrix.sh",
            core_plan["parallel_suites"],
        )
        self.assertTrue(any("abort-leak" in note for note in core_plan["notes"]))

        slow_plan = mod.build_test_plan(
            ["skills/code-review/scripts/review_gate.py"],
            repo_root=REPO_ROOT,
            include_slow=True,
        )
        serial_joined = "\n".join(" ".join(c) for c in slow_plan["serial_commands"])
        self.assertIn("test_review_gate_abort_leak.sh", serial_joined)

    def test_package_surface_tracks_opencode_and_npm_checks(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["packages/opencode-plugin/ccl-skills.ts"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "scripts/test_install_opencode_skill_migration.sh",
            plan["parallel_suites"],
        )
        self.assertIn(
            "scripts/test_check_release_version.py",
            plan["parallel_suites"],
        )
        self.assertTrue(plan["npm_required"])

    def test_ci_and_makefile_select_binding_and_lane_guards(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["Makefile", ".github/workflows/ci.yml"],
            repo_root=REPO_ROOT,
        )
        for expected in (
            "skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh",
            "scripts/test_lane_isolation.py",
            "scripts/test_run_parallel_suites.sh",
        ):
            self.assertIn(expected, plan["parallel_suites"])

    def test_git_changed_file_discovery_unions_branch_staged_unstaged_and_untracked(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "dev@example.com"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Dev"], cwd=repo, check=True)

            for rel in ("a.txt", "b.txt", "c.txt"):
                (repo / rel).write_text("base\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=repo, check=True, capture_output=True)

            subprocess.run(["git", "checkout", "-b", "feat"], cwd=repo, check=True, capture_output=True)
            (repo / "a.txt").write_text("committed\n", encoding="utf-8")
            subprocess.run(["git", "add", "a.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "feat commit"], cwd=repo, check=True, capture_output=True)

            (repo / "b.txt").write_text("staged\n", encoding="utf-8")
            subprocess.run(["git", "add", "b.txt"], cwd=repo, check=True)
            (repo / "c.txt").write_text("unstaged\n", encoding="utf-8")
            (repo / "d.txt").write_text("untracked\n", encoding="utf-8")

            changed, resolved_base = mod.collect_changed_files(repo, base_ref="main")
            self.assertEqual(resolved_base, "main")
            self.assertEqual(changed, ["a.txt", "b.txt", "c.txt", "d.txt"])

    def test_cli_json_dry_run_and_execution_on_synthetic_suite(self):
        proc = subprocess.run(
            [
                sys.executable,
                str(SELECTOR_PATH),
                "--repo",
                str(REPO_ROOT),
                "--files",
                "scripts/select-affected-tests.py",
                "--json",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, msg=proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertIn("scripts/test_select_affected_tests.py", payload["parallel_suites"])

    def test_child_env_strips_makeflags_overrides(self):
        mod = load_selector()
        dirty = {
            "PATH": os.environ.get("PATH", ""),
            "MAKEFLAGS": " -- CCL_SKILL_DEFAULT_BASE_REF=origin/main",
            "MAKEOVERRIDES": "${-*-command-variables-*-}",
            "-*-command-variables-*-": "CCL_SKILL_DEFAULT_BASE_REF=origin/main",
            "CCL_SKILL_DEFAULT_BASE_REF": "origin/main",
        }
        cleaned = mod._clean_child_env(dirty)
        self.assertNotIn("MAKEFLAGS", cleaned)
        self.assertNotIn("MAKEOVERRIDES", cleaned)
        self.assertNotIn("CCL_SKILL_DEFAULT_BASE_REF", cleaned)
        self.assertIn("PATH", cleaned)


if __name__ == "__main__":
    unittest.main()
