#!/usr/bin/env python3
"""Unit and integration tests for scripts/select-affected-tests.py."""
from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
import unittest.mock

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parent
SELECTOR_PATH = SCRIPTS_DIR / "select-affected-tests.py"

_SCRUB_GIT_KEYS = (
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
    "GIT_REPLACE_REF_BASE",
    "GIT_PREFIX",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_QUARANTINE_PATH",
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
    "CCL_SKILL_BASE_REF",
    "CCL_SKILL_DEFAULT_BASE_REF",
)


def load_selector():
    if not SELECTOR_PATH.is_file():
        raise FileNotFoundError(f"missing selector script: {SELECTOR_PATH}")
    spec = importlib.util.spec_from_file_location("select_affected_tests", SELECTOR_PATH)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def isolated_git_env(template_dir: Path, extra: dict[str, str] | None = None) -> dict[str, str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in _SCRUB_GIT_KEYS
        and not k.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))
    }
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_SYSTEM"] = os.devnull
    env["GIT_TEMPLATE_DIR"] = str(template_dir)
    if extra:
        env.update(extra)
    return env


def init_fixture_repo(sandbox: Path) -> tuple[Path, Path, dict[str, str]]:
    tpl = sandbox / "empty-git-templates"
    tpl.mkdir(parents=True, exist_ok=True)
    repo = sandbox / "repo"
    repo.mkdir()
    env = isolated_git_env(tpl)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.email", "dev@example.com"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.name", "Dev"], cwd=repo, env=env, check=True)
    return repo, tpl, env


class SelectAffectedTestsUnit(unittest.TestCase):
    def test_clean_changeset_selects_nothing_and_empty_commit_runs_metadata_gate(self):
        mod = load_selector()
        plan = mod.build_test_plan([], repo_root=REPO_ROOT)
        self.assertEqual(plan["changed_files"], [])
        self.assertEqual(plan["preflight_commands"], [])
        self.assertEqual(plan["parallel_suites"], [])
        self.assertEqual(plan["serial_commands"], [])

        commit_plan = mod.build_test_plan(
            [],
            repo_root=REPO_ROOT,
            resolved_base_ref="refs/remotes/origin/main",
            has_candidate_commits=True,
        )
        preflight_joined = "\n".join(" ".join(c) for c in commit_plan["preflight_commands"])
        self.assertIn("shared_git_surface_gate.py --repo . --base-ref refs/remotes/origin/main", preflight_joined)

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
        self.assertNotIn("test_code_review_identity.sh", joined)
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
            "hooks/test_guard_edit_isolation.sh",
        ):
            self.assertIn(expected, plan["parallel_suites"])

        sl_plan = mod.build_test_plan(["hooks/skill-loading.py"], repo_root=REPO_ROOT)
        self.assertIn("hooks/test_agy_bridge.py", sl_plan["parallel_suites"])

    def test_code_review_leaf_script_core_fanout_and_legacy_path(self):
        mod = load_selector()
        leaf_plan = mod.build_test_plan(
            ["skills/code-review/scripts/concern_excerpt.py"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "skills/code-review/scripts/test_concern_excerpt.sh",
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
        self.assertIn("abort-leak", core_plan["skipped_lanes"])

        # Changing the slow abort-leak probe itself must NEVER put it into parallel_suites.
        leak_default = mod.build_test_plan(
            ["skills/code-review/scripts/test_review_gate_abort_leak.sh"],
            repo_root=REPO_ROOT,
            include_slow=False,
        )
        self.assertNotIn(
            "skills/code-review/scripts/test_review_gate_abort_leak.sh",
            leak_default["parallel_suites"],
        )
        self.assertIn("abort-leak", leak_default["skipped_lanes"])

        leak_slow = mod.build_test_plan(
            ["skills/code-review/scripts/test_review_gate_abort_leak.sh"],
            repo_root=REPO_ROOT,
            include_slow=True,
        )
        self.assertNotIn(
            "skills/code-review/scripts/test_review_gate_abort_leak.sh",
            leak_slow["parallel_suites"],
        )
        self.assertIn(
            "test_review_gate_abort_leak.sh",
            "\n".join(" ".join(c) for c in leak_slow["serial_commands"]),
        )

        legacy_plan = mod.build_test_plan(
            ["skills/claude-code-review/README.md"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "skills/code-review/scripts/test_code_review_identity.sh",
            legacy_plan["parallel_suites"],
        )

    def test_package_and_antigravity_surfaces_track_npm_checks(self):
        mod = load_selector()
        for changed in (
            "packages/opencode-plugin/ccl-skills.ts",
            ".antigravity-plugin/plugin.json",
            "hooks.json",
        ):
            plan = mod.build_test_plan([changed], repo_root=REPO_ROOT)
            self.assertTrue(plan["npm_required"], msg=changed)

    def test_ci_and_makefile_select_binding_and_spec_guards(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["Makefile", ".github/workflows/ci.yml", "requirements-test.txt"],
            repo_root=REPO_ROOT,
        )
        for expected in (
            "skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh",
            "scripts/test_check_spec_references.py",
            "scripts/test_lane_isolation.py",
            "scripts/test_run_parallel_suites.sh",
        ):
            self.assertIn(expected, plan["parallel_suites"])

    def test_git_changed_file_discovery_unions_branch_staged_unstaged_untracked_and_special_names(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            repo, _, env = init_fixture_repo(Path(tmp))
            for rel in ("a.txt", "b.txt", "c.txt"):
                (repo / rel).write_text("base\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            subprocess.run(["git", "checkout", "-q", "-b", "feat"], cwd=repo, env=env, check=True)
            (repo / "a.txt").write_text("committed\n", encoding="utf-8")
            subprocess.run(["git", "add", "a.txt"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "feat commit"], cwd=repo, env=env, check=True)

            (repo / "b.txt").write_text("staged\n", encoding="utf-8")
            subprocess.run(["git", "add", "b.txt"], cwd=repo, env=env, check=True)
            (repo / "c.txt").write_text("unstaged\n", encoding="utf-8")

            hooks_dir = repo / "hooks"
            hooks_dir.mkdir()
            special_names = [
                "hooks/test_路由.py",
                "hooks/test_with space.py",
                r"hooks/test_a\b.py",
            ]
            for rel in special_names:
                (repo / rel).write_text("if __name__ == '__main__':\n    pass\n", encoding="utf-8")

            raw_non_utf8 = os.fsdecode(b"hooks/test_raw_\xff.py")
            (repo / raw_non_utf8).write_bytes(
                b"if __name__ == '__main__':\n    pass\n"
            )

            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, resolved_base = mod.collect_changed_files(repo, base_ref="refs/remotes/origin/main")
            self.assertEqual(resolved_base, "refs/remotes/origin/main")
            for expected in ["a.txt", "b.txt", "c.txt", *special_names, raw_non_utf8]:
                self.assertIn(expected, changed)
            plan = mod.build_test_plan(changed, repo_root=repo, resolved_base_ref=resolved_base)
            for suite in [*special_names, raw_non_utf8]:
                self.assertIn(suite, plan["parallel_suites"])
            # JSON serialization must remain valid UTF-8 even when surrogate-escaped bytes are present.
            encoded_json = json.dumps(mod._json_safe(plan), ensure_ascii=False)
            self.assertIn("advisory", json.loads(encoded_json))

    def test_base_resolution_precedence_shadow_unrelated_upstream_and_missing(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "base.txt").write_text("base\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            # Stale integration branch far behind origin/main.
            subprocess.run(["git", "update-ref", "refs/remotes/origin/dev", "HEAD"], cwd=repo, env=env, check=True)
            for i in range(3):
                (repo / f"main{i}.txt").write_text("x\n", encoding="utf-8")
                subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
                subprocess.run(["git", "commit", "-q", "-m", f"main {i}"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            subprocess.run(["git", "checkout", "-q", "-b", "feat"], cwd=repo, env=env, check=True)
            (repo / "feature.txt").write_text("f\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "feature"], cwd=repo, env=env, check=True)

            # Local branch literally named `origin/main` pointing at HEAD must NOT shadow refs/remotes/origin/main.
            subprocess.run(["git", "branch", "origin/main", "HEAD"], cwd=repo, env=env, check=True)

            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, resolved = mod.collect_changed_files(repo, default_base_ref="origin/main")
            self.assertEqual(resolved, "refs/remotes/origin/main")
            self.assertEqual(changed, ["feature.txt"])

            # Option-shaped and unresolvable explicit bases fail closed (exit 2, empty stdout).
            for bad_base in ("--independent", "refs/heads/no-such-branch-xyz"):
                proc = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--base-ref", bad_base, "--json"],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc.returncode, 2, msg=bad_base)
                self.assertEqual(proc.stdout, "")

            # Unresolvable CCL_SKILL_BASE_REF must ALSO fail closed, never fall back silently.
            bad_env = dict(env, CCL_SKILL_BASE_REF="refs/remotes/origin/typo-branch")
            proc = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--json"],
                env=bad_env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 2)
            self.assertEqual(proc.stdout, "")

            # Missing origin/dev: single-branch clone with only origin/main still resolves origin/main.
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/origin/dev"], cwd=repo, env=env, check=True)
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed_single, resolved_single = mod.collect_changed_files(repo)
            self.assertEqual(resolved_single, "refs/remotes/origin/main")
            self.assertEqual(changed_single, ["feature.txt"])

            # Unrelated history on origin/dev (orphan commit, merge-base exits 1) is skipped rather than fatal.
            orphan_tree = subprocess.run(
                ["git", "hash-object", "-t", "tree", "/dev/null"],
                cwd=repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            orphan_commit = subprocess.run(
                ["git", "commit-tree", orphan_tree, "-m", "orphan"],
                cwd=repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "update-ref", "refs/remotes/origin/dev", orphan_commit],
                cwd=repo,
                env=env,
                check=True,
            )
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                _, resolved_unrelated = mod.collect_changed_files(repo)
            self.assertEqual(resolved_unrelated, "refs/remotes/origin/main")

            # Upstream-only repo honors CCL_SKILL_DEFAULT_BASE_REF / --default-base-ref.
            main_sha = subprocess.run(
                ["git", "rev-parse", "refs/remotes/origin/main"],
                cwd=repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/origin/main"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/origin/dev"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/upstream/dev", main_sha], cwd=repo, env=env, check=True)
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed_up, resolved_up = mod.collect_changed_files(
                    repo, default_base_ref="refs/remotes/upstream/dev"
                )
            self.assertEqual(resolved_up, "refs/remotes/upstream/dev")
            self.assertEqual(changed_up, ["feature.txt"])

            # No usable integration ref at all -> exits 2 instead of diffing HEAD~1 or local main.
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/upstream/dev"], cwd=repo, env=env, check=True)
            proc_no_base = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--json"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_no_base.returncode, 2)
            self.assertEqual(proc_no_base.stdout, "")

    def test_resolved_base_reaches_gates_and_child_env_strips_overrides(self):
        mod = load_selector()
        plan = mod.build_test_plan(
            ["scripts/select-affected-tests.py"],
            repo_root=REPO_ROOT,
            default_base_ref="origin/dev",
            resolved_base_ref="refs/remotes/origin/main",
        )
        gate_cmds = [c for c in plan["preflight_commands"] if "shared_git_surface_gate.py" in " ".join(c)]
        self.assertEqual(
            gate_cmds,
            [[
                "python3",
                "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py",
                "--repo",
                ".",
                "--base-ref",
                "refs/remotes/origin/main",
            ]],
        )

        dirty = {
            "PATH": os.environ.get("PATH", ""),
            "MAKEFLAGS": " -- CCL_SKILL_DEFAULT_BASE_REF=origin/main",
            "MAKEOVERRIDES": "${-*-command-variables-*-}",
            "-*-command-variables-*-": "CCL_SKILL_DEFAULT_BASE_REF=origin/main",
            "CCL_SKILL_DEFAULT_BASE_REF": "origin/main",
            "GIT_DIR": "/decoy/git-dir",
            "GIT_INDEX_FILE": "/decoy/index",
            "GIT_SHALLOW_FILE": "/decoy/shallow",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.hooksPath",
            "GIT_CONFIG_VALUE_0": "/decoy/hooks",
        }
        cleaned = mod._clean_child_env(dirty, resolved_base="refs/remotes/origin/main")
        for forbidden in (
            "MAKEFLAGS",
            "MAKEOVERRIDES",
            "CCL_SKILL_DEFAULT_BASE_REF",
            "GIT_DIR",
            "GIT_INDEX_FILE",
            "GIT_SHALLOW_FILE",
            "GIT_CONFIG_COUNT",
            "GIT_CONFIG_KEY_0",
            "GIT_CONFIG_VALUE_0",
        ):
            self.assertNotIn(forbidden, cleaned)
        self.assertEqual(cleaned["CCL_SKILL_BASE_REF"], "refs/remotes/origin/main")
        self.assertIn("PATH", cleaned)

    def test_git_isolation_covers_discovery_child_execution_and_fixture_templates(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            # 1. Fixture template hook isolation: a poisonous inherited GIT_TEMPLATE_DIR must never fire.
            poison_tpl = sandbox / "poison-tpl"
            hooks_dir = poison_tpl / "hooks"
            hooks_dir.mkdir(parents=True)
            sentinel = sandbox / "hook-fired"
            pre_commit = hooks_dir / "pre-commit"
            pre_commit.write_text(
                f"#!/usr/bin/env bash\ntouch {sentinel}\nexit 1\n",
                encoding="utf-8",
            )
            pre_commit.chmod(0o755)
            with unittest.mock.patch.dict(os.environ, {"GIT_TEMPLATE_DIR": str(poison_tpl)}):
                target_repo, _, env = init_fixture_repo(sandbox / "target")
                (target_repo / "f.txt").write_text("v1\n", encoding="utf-8")
                subprocess.run(["git", "add", "f.txt"], cwd=target_repo, env=env, check=True)
                subprocess.run(["git", "commit", "-q", "-m", "c1"], cwd=target_repo, env=env, check=True)
            self.assertFalse(sentinel.exists(), "fixture commit executed inherited template hook")

            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=target_repo, env=env, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "feat"], cwd=target_repo, env=env, check=True)
            (target_repo / "f.txt").write_text("v2\n", encoding="utf-8")
            subprocess.run(["git", "add", "f.txt"], cwd=target_repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "c2"], cwd=target_repo, env=env, check=True)
            tip_sha = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=target_repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()

            # 2. Decoy clean repo + shallow file in caller env must NOT redirect or break discovery.
            caller_repo, _, caller_env = init_fixture_repo(sandbox / "caller")
            (caller_repo / "keep.txt").write_text("caller\n", encoding="utf-8")
            subprocess.run(["git", "add", "keep.txt"], cwd=caller_repo, env=caller_env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "caller init"], cwd=caller_repo, env=caller_env, check=True)
            caller_index = caller_repo / ".git" / "index"
            caller_index_before = hashlib.sha256(caller_index.read_bytes()).hexdigest()

            shallow_file = sandbox / "fake-shallow"
            shallow_file.write_text(tip_sha + "\n", encoding="utf-8")
            polluted_env = dict(
                env,
                GIT_DIR=str(caller_repo / ".git"),
                GIT_WORK_TREE=str(caller_repo),
                GIT_INDEX_FILE=str(caller_index),
                GIT_SHALLOW_FILE=str(shallow_file),
            )
            with unittest.mock.patch.dict(os.environ, polluted_env, clear=True):
                changed, resolved = mod.collect_changed_files(target_repo)
            self.assertEqual(resolved, "refs/remotes/origin/main")
            self.assertEqual(changed, ["f.txt"])

            # 3. Child execution via execute_plan must ALSO strip GIT_INDEX_FILE / GIT_DIR so a suite staging
            # files in its own scratch repo cannot corrupt the caller's index.
            scripts_dir = target_repo / "scripts"
            scripts_dir.mkdir()
            (scripts_dir / "run-parallel-suites.sh").write_bytes(
                (REPO_ROOT / "scripts/run-parallel-suites.sh").read_bytes()
            )
            suite_rel = "scripts/test_index_probe.sh"
            suite_file = target_repo / suite_rel
            suite_file.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                'd="$(mktemp -d)"\n'
                'trap \'rm -rf "$d"\' EXIT\n'
                'git -C "$d" init -q -b main\n'
                'echo payload >"$d/staged.txt"\n'
                'git -C "$d" add staged.txt\n',
                encoding="utf-8",
            )
            suite_file.chmod(0o755)
            exec_plan = {
                "changed_files": [suite_rel],
                "resolved_base_ref": "refs/remotes/origin/main",
                "preflight_commands": [],
                "parallel_suites": [suite_rel],
                "serial_commands": [],
                "notes": [],
                "skipped_lanes": [],
            }
            buf = io.StringIO()
            with unittest.mock.patch.dict(os.environ, polluted_env, clear=True), contextlib.redirect_stdout(buf):
                rc = mod.execute_plan(exec_plan, target_repo, jobs=1)
            self.assertEqual(rc, 0, msg=buf.getvalue())
            caller_index_after = hashlib.sha256(caller_index.read_bytes()).hexdigest()
            self.assertEqual(caller_index_before, caller_index_after, "child suite mutated caller GIT_INDEX_FILE")

    def test_repo_root_validation_and_corrupt_index_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            non_git = sandbox / "plain"
            non_git.mkdir()
            proc = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(non_git), "--json"],
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 2)
            self.assertEqual(proc.stdout, "")

            repo, _, env = init_fixture_repo(sandbox / "w")
            sub = repo / "nested" / "dir"
            sub.mkdir(parents=True)
            (sub / "x.txt").write_text("hi\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            # Subdirectory passed to --repo must exit 2 both with and without --files.
            for extra_args in (["--json"], ["--files", "nested/dir/x.txt", "--json"]):
                proc_sub = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(sub), *extra_args],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc_sub.returncode, 2, msg=extra_args)
                self.assertEqual(proc_sub.stdout, "")

            # Corrupt .git/index: merge-base succeeds, but `git diff --cached` fails -> must exit 2, not return [].
            (repo / ".git" / "index").write_bytes(b"CORRUPT_INDEX_HEADER")
            proc_corrupt = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--json"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_corrupt.returncode, 2)
            self.assertEqual(proc_corrupt.stdout, "")

    def test_containment_blocks_symlinks_and_parent_traversal(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            outside = sandbox / "test_outside.sh"
            outside.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            outside.chmod(0o755)

            repo, _, _ = init_fixture_repo(sandbox / "w")
            (repo / "hooks").mkdir()
            escape_link = repo / "hooks" / "test_escape.sh"
            escape_link.symlink_to(outside)

            plan = mod.build_test_plan(
                ["hooks/test_escape.sh", "../test_outside.sh", "hooks/escape.sh"],
                repo_root=repo,
            )
            self.assertEqual(plan["parallel_suites"], [])
            self.assertTrue(any("unsafe" in n or "outside" in n for n in plan["notes"]))

    def test_every_literal_suite_path_in_selector_exists(self):
        import re

        source = SELECTOR_PATH.read_text(encoding="utf-8")
        literals = set(re.findall(r'"((?:hooks|scripts|skills|eval)/[^"\s]+\.(?:sh|py))"', source))
        self.assertTrue(literals)
        missing = sorted(p for p in literals if not (REPO_ROOT / p).is_file())
        self.assertEqual(missing, [], msg="selector names suites that do not exist")

    def test_hook_fallback_covers_makefile_and_missing_makefile_entry_triggers_drift_end_to_end(self):
        mod = load_selector()
        universe = mod.makefile_suites(REPO_ROOT)
        hook_suites = {s for s in universe if s.startswith("hooks/")}
        self.assertIn("hooks/test_agy_bridge.py", hook_suites)
        plan = mod.build_test_plan(["hooks/hooks.json"], repo_root=REPO_ROOT)
        self.assertEqual(hook_suites - set(plan["parallel_suites"]), set())

        # End-to-end drift test: Makefile registers a hook suite missing on disk; unmapped hook change
        # must report drift AND schedule + execute the fallback Make targets.
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "hooks").mkdir()
            (repo / "hooks/test_present.sh").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (repo / "Makefile").write_text(
                "test-repo-gates:\n"
                "\tbash hooks/test_present.sh\n"
                "\tbash hooks/test_deleted_from_disk.sh\n",
                encoding="utf-8",
            )
            drift_plan = mod.build_test_plan(["hooks/new-unmapped.sh"], repo_root=repo)
            self.assertIn("hooks/test_deleted_from_disk.sh", drift_plan["missing_suites"])
            self.assertTrue(any("selector-drift" in n for n in drift_plan["notes"]))
            serial_joined = [" ".join(c) for c in drift_plan["serial_commands"]]
            for expected_cmd in (
                "make test-repo-gates",
                "make test-regressions-fast",
                "make test-code-review-1",
                "make test-code-review-2",
            ):
                self.assertIn(expected_cmd, serial_joined)

            # Verify execute_plan actually runs the fallback serial commands.
            drift_plan["preflight_commands"] = []
            drift_plan["parallel_suites"] = []
            drift_plan["serial_commands"] = [c for c in drift_plan["serial_commands"] if c[0] == "make"]
            ran_log = sandbox / "make-calls.log"
            bin_dir = sandbox / "bin"
            bin_dir.mkdir()
            fake_make = bin_dir / "make"
            fake_make.write_text(
                f"#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> {ran_log}\n",
                encoding="utf-8",
            )
            fake_make.chmod(0o755)
            run_env = dict(env, PATH=f"{bin_dir}:{env.get('PATH', '')}")
            buf = io.StringIO()
            with unittest.mock.patch.dict(os.environ, run_env, clear=True), contextlib.redirect_stdout(buf):
                rc = mod.execute_plan(drift_plan, repo)
            self.assertEqual(rc, 0)
            recorded_targets = ran_log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                recorded_targets,
                ["test-repo-gates", "test-regressions-fast", "test-code-review-1", "test-code-review-2"],
            )

    def test_pytest_style_suite_without_main_dispatches_via_pytest_and_fails_on_red_assertion(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "scripts").mkdir()
            failing_suite = repo / "scripts/test_no_main_red.py"
            failing_suite.write_text(
                "def test_deliberate_failure():\n    assert 1 == 2\n",
                encoding="utf-8",
            )
            plan = mod.build_test_plan(["scripts/test_no_main_red.py"], repo_root=repo)
            plan["preflight_commands"] = []
            self.assertNotIn("scripts/test_no_main_red.py", plan["parallel_suites"])
            pytest_cmd = ["python3", "-m", "pytest", "-q", "scripts/test_no_main_red.py"]
            self.assertIn(pytest_cmd, plan["serial_commands"])
            plan["serial_commands"] = [pytest_cmd]

            # Provide a minimal pytest runner on PYTHONPATH if system python lacks pytest, so
            # both environments exercise real assertion failure vs pass through execute_plan.
            extra_env = dict(env)
            if importlib.util.find_spec("pytest") is None:
                shim_dir = sandbox / "pyshim"
                shim_dir.mkdir()
                (shim_dir / "pytest.py").write_text(
                    "import importlib.util, sys\n"
                    "args = [a for a in sys.argv[1:] if not a.startswith('-')]\n"
                    "spec = importlib.util.spec_from_file_location('m', args[0])\n"
                    "mod = importlib.util.module_from_spec(spec)\n"
                    "spec.loader.exec_module(mod)\n"
                    "ran = 0\n"
                    "for k, v in vars(mod).items():\n"
                    "    if k.startswith('test_') and callable(v):\n"
                    "        v(); ran += 1\n"
                    "sys.exit(0 if ran > 0 else 5)\n",
                    encoding="utf-8",
                )
                extra_env["PYTHONPATH"] = str(shim_dir)

            buf_fail = io.StringIO()
            with unittest.mock.patch.dict(os.environ, extra_env, clear=True), contextlib.redirect_stdout(buf_fail):
                rc_fail = mod.execute_plan(plan, repo)
            self.assertNotEqual(rc_fail, 0, "pytest-style failing suite exited 0")
            self.assertTrue(buf_fail.getvalue().strip().endswith("advisory: run make test before push"))

            failing_suite.write_text("def test_ok():\n    assert 2 == 2\n", encoding="utf-8")
            buf_ok = io.StringIO()
            with unittest.mock.patch.dict(os.environ, extra_env, clear=True), contextlib.redirect_stdout(buf_ok):
                rc_ok = mod.execute_plan(plan, repo)
            self.assertEqual(rc_ok, 0)

    def test_stopped_docker_daemon_records_verify_sandbox_skip(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            bin_dir = sandbox / "bin"
            bin_dir.mkdir()
            fake_docker = bin_dir / "docker"
            fake_docker.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
            fake_docker.chmod(0o755)
            with unittest.mock.patch.dict(os.environ, {"PATH": f"{bin_dir}:{os.environ.get('PATH', '')}"}):
                plan = mod.build_test_plan(
                    ["scripts/verify-sandbox/verify-sandbox.sh"],
                    repo_root=REPO_ROOT,
                    include_slow=True,
                )
            self.assertIn("verify-sandbox", plan["skipped_lanes"])
            self.assertNotIn(["bash", "scripts/verify-sandbox/test.sh"], plan["serial_commands"])

    def test_rename_reports_both_old_and_new_paths(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            repo, _, env = init_fixture_repo(Path(tmp))
            (repo / "old.txt").write_text("same content\n" * 20, encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "feat"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "mv", "old.txt", "new.txt"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "rename"], cwd=repo, env=env, check=True)
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, _ = mod.collect_changed_files(repo, base_ref="refs/remotes/origin/main")
            self.assertEqual(changed, ["new.txt", "old.txt"])

    def test_json_dry_run_execution_phases_exit_codes_and_advisory_footer(self):
        mod = load_selector()
        # 1. --json must be a single valid JSON document carrying the advisory field.
        proc_json = subprocess.run(
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
        self.assertEqual(proc_json.returncode, 0, msg=proc_json.stderr)
        payload = json.loads(proc_json.stdout)
        self.assertEqual(payload["advisory"], "advisory: run make test before push")
        self.assertIn("scripts/test_select_affected_tests.py", payload["parallel_suites"])

        # 2. --dry-run quotes arguments, includes --jobs, escapes multiline filenames, and ends with # advisory.
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, _ = init_fixture_repo(sandbox)
            (repo / "hooks").mkdir()
            spaced = repo / "hooks/test_space name.sh"
            spaced.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            spaced.chmod(stat.S_IRWXU)
            plan = mod.build_test_plan(
                ["hooks/test_space name.sh", "docs/line1\necho INJECTED.md"],
                repo_root=repo,
                resolved_base_ref="refs/remotes/origin/main",
            )
            dry_buf = io.StringIO()
            with contextlib.redirect_stdout(dry_buf):
                mod.print_dry_run(plan, "refs/remotes/origin/main", jobs=3)
            dry_lines = dry_buf.getvalue().splitlines()
            self.assertEqual(dry_lines[-1], "# advisory: run make test before push")
            self.assertFalse(any(line == "echo INJECTED.md" for line in dry_lines))
            parallel_lines = [line for line in dry_lines if "run-parallel-suites.sh" in line]
            self.assertEqual(len(parallel_lines), 1)
            self.assertIn("--jobs 3", parallel_lines[0])
            self.assertIn("'hooks/test_space name.sh'", parallel_lines[0])

            # 3. Preflight failure stops before parallel and serial work, preserves exit code, and prints advisory.
            marker = sandbox / "should-not-exist"
            fail_preflight = {
                "changed_files": ["x"],
                "resolved_base_ref": "refs/remotes/origin/main",
                "preflight_commands": [[sys.executable, "-c", "raise SystemExit(3)"]],
                "parallel_suites": [],
                "serial_commands": [[sys.executable, "-c", f"open({str(marker)!r}, 'w').close()"]],
                "notes": [],
                "skipped_lanes": [],
            }
            out_pre = io.StringIO()
            with contextlib.redirect_stdout(out_pre):
                rc_pre = mod.execute_plan(fail_preflight, repo)
            self.assertEqual(rc_pre, 3)
            self.assertFalse(marker.exists())
            self.assertEqual(out_pre.getvalue().splitlines()[-1], "advisory: run make test before push")

            # 4. Serial child exit code, missing executable (127), and signal death (128 + SIGTERM = 143).
            serial_7 = {
                "changed_files": ["x"],
                "resolved_base_ref": None,
                "preflight_commands": [],
                "parallel_suites": [],
                "serial_commands": [[sys.executable, "-c", "print('select_affected_tests_done'); raise SystemExit(7)"]],
                "notes": [],
                "skipped_lanes": [],
            }
            out_7 = io.StringIO()
            with contextlib.redirect_stdout(out_7):
                rc_7 = mod.execute_plan(serial_7, repo)
            self.assertEqual(rc_7, 7)
            self.assertEqual(out_7.getvalue().splitlines()[-1], "advisory: run make test before push")

            missing_bin = {
                "changed_files": ["x"],
                "resolved_base_ref": None,
                "preflight_commands": [],
                "parallel_suites": [],
                "serial_commands": [["/nonexistent-binary-xyz-999"]],
                "notes": [],
                "skipped_lanes": [],
            }
            out_127 = io.StringIO()
            err_127 = io.StringIO()
            with contextlib.redirect_stdout(out_127), contextlib.redirect_stderr(err_127):
                rc_127 = mod.execute_plan(missing_bin, repo)
            self.assertEqual(rc_127, 127)
            self.assertEqual(out_127.getvalue().splitlines()[-1], "advisory: run make test before push")

            sig_plan = {
                "changed_files": ["x"],
                "resolved_base_ref": None,
                "preflight_commands": [],
                "parallel_suites": [],
                "serial_commands": [[sys.executable, "-c", "import os, signal; os.kill(os.getpid(), signal.SIGTERM)"]],
                "notes": [],
                "skipped_lanes": [],
            }
            out_sig = io.StringIO()
            with contextlib.redirect_stdout(out_sig):
                rc_sig = mod.execute_plan(sig_plan, repo)
            self.assertEqual(rc_sig, 128 + signal.SIGTERM)
            self.assertEqual(out_sig.getvalue().splitlines()[-1], "advisory: run make test before push")

            # 5. Parallel failure through run-parallel-suites.sh returns 1 and ends with advisory.
            (repo / "scripts").mkdir(exist_ok=True)
            (repo / "scripts/run-parallel-suites.sh").write_bytes(
                (REPO_ROOT / "scripts/run-parallel-suites.sh").read_bytes()
            )
            bad_suite = repo / "hooks/test_fail_seven.sh"
            bad_suite.write_text("#!/usr/bin/env bash\nexit 7\n", encoding="utf-8")
            bad_suite.chmod(0o755)
            par_plan = {
                "changed_files": ["hooks/test_fail_seven.sh"],
                "resolved_base_ref": None,
                "preflight_commands": [],
                "parallel_suites": ["hooks/test_fail_seven.sh"],
                "serial_commands": [],
                "notes": [],
                "skipped_lanes": [],
            }
            out_par = io.StringIO()
            with contextlib.redirect_stdout(out_par):
                rc_par = mod.execute_plan(par_plan, repo, jobs=1)
            self.assertEqual(rc_par, 1)
            self.assertEqual(out_par.getvalue().splitlines()[-1], "advisory: run make test before push")

            # 6. Successful run with skipped lanes prints `skipped:`, `select_affected_tests_done`, and advisory (never `_ok`).
            skip_plan = {
                "changed_files": ["x"],
                "resolved_base_ref": "refs/remotes/origin/main",
                "preflight_commands": [],
                "parallel_suites": [],
                "serial_commands": [],
                "notes": ["npm-packages: skipped"],
                "skipped_lanes": ["npm-packages"],
            }
            out_skip = io.StringIO()
            with contextlib.redirect_stdout(out_skip):
                rc_skip = mod.execute_plan(skip_plan, repo)
            self.assertEqual(rc_skip, 0)
            lines = out_skip.getvalue().splitlines()
            self.assertIn("skipped: npm-packages", lines)
            self.assertEqual(lines[-2], "select_affected_tests_done")
            self.assertEqual(lines[-1], "advisory: run make test before push")
            self.assertNotIn("select_affected_tests_ok", out_skip.getvalue())

        # 7. BrokenPipeError / SIGPIPE (e.g. piping --dry-run to `head -n 2`) must not print a traceback.
        proc_pipe = subprocess.run(
            [
                "bash",
                "-c",
                f'set +o pipefail; "{sys.executable}" "{SELECTOR_PATH}" --repo "{REPO_ROOT}" '
                '--files scripts/select-affected-tests.py --dry-run | head -n 2',
            ],
            capture_output=True,
            text=True,
        )
        self.assertNotIn("Traceback", proc_pipe.stderr)
        self.assertNotIn("BrokenPipeError", proc_pipe.stderr)


if __name__ == "__main__":
    unittest.main()
