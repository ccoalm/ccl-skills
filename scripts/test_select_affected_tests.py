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
import unittest.mock

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

    def test_every_literal_suite_path_in_selector_exists(self):
        # Drift guard: a renamed/removed suite must fail here, not be skipped silently at run time.
        import re

        source = SELECTOR_PATH.read_text(encoding="utf-8")
        literals = set(re.findall(r'"((?:hooks|scripts|skills|eval)/[^"\s]+\.(?:sh|py))"', source))
        self.assertTrue(literals)
        missing = sorted(p for p in literals if not (REPO_ROOT / p).is_file())
        self.assertEqual(missing, [], msg="selector names suites that do not exist")

    def test_hook_fallback_covers_every_makefile_hook_suite(self):
        mod = load_selector()
        universe = mod.makefile_suites(REPO_ROOT)
        hook_suites = {s for s in universe if s.startswith("hooks/")}
        self.assertIn("hooks/test_agy_bridge.py", hook_suites)
        plan = mod.build_test_plan(["hooks/hooks.json"], repo_root=REPO_ROOT)
        self.assertEqual(hook_suites - set(plan["parallel_suites"]), set())

    def test_changed_source_selects_sibling_test_and_changed_suite_selects_itself(self):
        mod = load_selector()
        plan = mod.build_test_plan(["hooks/agy-bridge.py"], repo_root=REPO_ROOT)
        self.assertIn("hooks/test_agy_bridge.py", plan["parallel_suites"])
        plan = mod.build_test_plan(["scripts/test_install_antigravity.sh"], repo_root=REPO_ROOT)
        self.assertIn("scripts/test_install_antigravity.sh", plan["parallel_suites"])

    def test_missing_mapped_suite_is_recorded_and_escalates_to_full(self):
        mod = load_selector()
        builder = mod._PlanBuilder(REPO_ROOT, "origin/dev", False, False)
        builder.add_suite("hooks/test_does_not_exist.sh")
        self.assertEqual(builder.parallel_suites, [])
        self.assertEqual(builder.missing_suites, ["hooks/test_does_not_exist.sh"])

    def test_unresolvable_explicit_base_ref_is_an_error(self):
        proc = subprocess.run(
            [sys.executable, str(SELECTOR_PATH), "--repo", str(REPO_ROOT),
             "--base-ref", "refs/heads/no-such-branch-xyz", "--json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("no-such-branch-xyz", proc.stderr)
        self.assertEqual(proc.stdout, "")

    def test_default_base_prefers_nearest_merge_base_over_stale_branch(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()

            def run(*args):
                subprocess.run(list(args), cwd=repo, check=True, capture_output=True)

            run("git", "init", "-b", "main")
            run("git", "config", "user.email", "dev@example.com")
            run("git", "config", "user.name", "Dev")
            (repo / "base.txt").write_text("base\n", encoding="utf-8")
            run("git", "add", ".")
            run("git", "commit", "-m", "init")
            run("git", "update-ref", "refs/remotes/origin/dev", "HEAD")  # stale integration branch
            for i in range(3):
                (repo / f"main{i}.txt").write_text("x\n", encoding="utf-8")
                run("git", "add", ".")
                run("git", "commit", "-m", f"main {i}")
            run("git", "update-ref", "refs/remotes/origin/main", "HEAD")
            run("git", "checkout", "-b", "feat")
            (repo / "feature.txt").write_text("f\n", encoding="utf-8")
            run("git", "add", ".")
            run("git", "commit", "-m", "feature")
            env = {k: v for k, v in os.environ.items()
                   if k not in ("CCL_SKILL_BASE_REF", "CCL_SKILL_DEFAULT_BASE_REF")}
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, resolved = mod.collect_changed_files(repo)
            self.assertEqual(resolved, "origin/main")
            self.assertEqual(changed, ["feature.txt"])

    def test_rename_reports_both_old_and_new_paths(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"
            repo.mkdir()

            def run(*args):
                subprocess.run(list(args), cwd=repo, check=True, capture_output=True)

            run("git", "init", "-b", "main")
            run("git", "config", "user.email", "dev@example.com")
            run("git", "config", "user.name", "Dev")
            (repo / "old.txt").write_text("same content\n" * 20, encoding="utf-8")
            run("git", "add", ".")
            run("git", "commit", "-m", "init")
            run("git", "checkout", "-b", "feat")
            run("git", "mv", "old.txt", "new.txt")
            run("git", "commit", "-m", "rename")
            changed, _ = mod.collect_changed_files(repo, base_ref="main")
            self.assertEqual(changed, ["new.txt", "old.txt"])

    def test_skipped_lane_reports_partial_not_ok(self):
        import contextlib
        import io

        mod = load_selector()
        plan = {
            "changed_files": ["x"],
            "preflight_commands": [],
            "parallel_suites": [],
            "serial_commands": [],
            "notes": ["npm-packages: skipped"],
            "skipped_lanes": ["npm-packages"],
        }
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = mod.execute_plan(plan, REPO_ROOT)
        self.assertEqual(rc, 0)
        self.assertIn("select_affected_tests_partial", buf.getvalue())
        self.assertNotIn("select_affected_tests_ok", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
