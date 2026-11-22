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
import time
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
    "GIT_NO_REPLACE_OBJECTS",
    "GIT_REPLACE_REF_BASE",
    "GIT_PREFIX",
    "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_QUARANTINE_PATH",
    "GIT_GLOB_PATHSPECS",
    "GIT_NOGLOB_PATHSPECS",
    "GIT_LITERAL_PATHSPECS",
    "GIT_ICASE_PATHSPECS",
    "GIT_TEMPLATE_DIR",
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
    "CCL_SKILL_BASE_REF",
    "CCL_SKILL_DEFAULT_BASE_REF",
    "CCL_SKILL_SELECTED_DEFAULT_BASE",
    "AFFECTED_ARGS",
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
    (template_dir / "info").mkdir(parents=True, exist_ok=True)
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


def init_fixture_repo(sandbox: Path, repo_name: str = "repo") -> tuple[Path, Path, dict[str, str]]:
    tpl = sandbox / "empty-git-templates"
    (tpl / "info").mkdir(parents=True, exist_ok=True)
    repo = sandbox / repo_name
    repo.mkdir(parents=True)
    env = isolated_git_env(tpl)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.email", "dev@example.com"], cwd=repo, env=env, check=True)
    subprocess.run(["git", "config", "user.name", "Dev"], cwd=repo, env=env, check=True)
    return repo, tpl, env


def _pid_is_live_non_zombie(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    stat_file = Path(f"/proc/{pid}/stat")
    if stat_file.is_file():
        try:
            raw = stat_file.read_text(encoding="utf-8", errors="replace")
            rparen = raw.rfind(")")
            if rparen != -1 and raw[rparen + 2 : rparen + 3] == "Z":
                return False
        except OSError:
            return False
    return True


class SelectAffectedTestsUnit(unittest.TestCase):
    def test_clean_changeset_selects_nothing_and_empty_commit_runs_metadata_gate(self):
        mod = load_selector()
        plan = mod.build_test_plan([], repo_root=REPO_ROOT)
        self.assertEqual(plan["changed_files"], [])
        self.assertEqual(plan["preflight_commands"], [])
        self.assertEqual(plan["parallel_suites"], [])
        self.assertEqual(plan["serial_commands"], [])

        base_sha = "a" * 40
        head_sha = "b" * 40
        commit_plan = mod.build_test_plan(
            [],
            repo_root=REPO_ROOT,
            resolved_base_ref="refs/remotes/origin/main",
            resolved_base_sha=base_sha,
            merge_base_sha=base_sha,
            head_sha=head_sha,
            has_candidate_commits=True,
        )
        preflight_joined = "\n".join(" ".join(c) for c in commit_plan["preflight_commands"])
        self.assertIn(f"shared_git_surface_gate.py --repo . --base-ref {base_sha}", preflight_joined)

        # Committed whitespace check is independent of staged/worktree repairs when head_sha != merge_base_sha.
        dirty_plan = mod.build_test_plan(
            ["docs/CONTRIBUTING.md"],
            repo_root=REPO_ROOT,
            resolved_base_ref="refs/remotes/origin/main",
            resolved_base_sha=base_sha,
            merge_base_sha=base_sha,
            head_sha=head_sha,
            has_candidate_commits=True,
        )
        self.assertIn(
            ["git", "diff", "--no-ext-diff", "--check", base_sha, head_sha, "--"],
            dirty_plan["preflight_commands"],
        )

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

    def test_code_review_leaf_script_core_fanout_path_aliases_and_heavy_regressions(self):
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

        # Changing the slow abort-leak probe (including via embedded `./` or `//` aliases)
        # must NEVER put it into parallel_suites.
        for alias in (
            "skills/code-review/scripts/test_review_gate_abort_leak.sh",
            "skills/code-review/scripts/./test_review_gate_abort_leak.sh",
            "skills//code-review//scripts//test_review_gate_abort_leak.sh",
        ):
            leak_default = mod.build_test_plan(
                [alias],
                repo_root=REPO_ROOT,
                include_slow=False,
            )
            self.assertNotIn(
                "skills/code-review/scripts/test_review_gate_abort_leak.sh",
                leak_default["parallel_suites"],
                msg=alias,
            )
            self.assertIn("abort-leak", leak_default["skipped_lanes"], msg=alias)

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

        # Individual heavy regressions in skill-extraction-workflow must respect include_slow.
        heavy_rel = "skills/skill-extraction-workflow/scripts/test_impact_chain_gate_verdict_differential.sh"
        heavy_default = mod.build_test_plan([heavy_rel], repo_root=REPO_ROOT, include_slow=False)
        self.assertNotIn(heavy_rel, heavy_default["parallel_suites"])
        self.assertIn("heavy-regressions", heavy_default["skipped_lanes"])
        self.assertIn(
            "skills/skill-extraction-workflow/scripts/test_regression_runner_registration.sh",
            heavy_default["parallel_suites"],
        )
        heavy_slow = mod.build_test_plan([heavy_rel], repo_root=REPO_ROOT, include_slow=True)
        self.assertNotIn(heavy_rel, heavy_slow["parallel_suites"])
        self.assertIn(["bash", heavy_rel], heavy_slow["serial_commands"])

        legacy_plan = mod.build_test_plan(
            ["skills/claude-code-review/README.md"],
            repo_root=REPO_ROOT,
        )
        self.assertIn(
            "skills/code-review/scripts/test_code_review_identity.sh",
            legacy_plan["parallel_suites"],
        )

    def test_eval_changes_include_affected_eval_unittest_module(self):
        mod = load_selector()
        for touched in ("eval/owner-role-audit.py", "eval/test_owner_role_audit.py"):
            plan = mod.build_test_plan([touched], repo_root=REPO_ROOT)
            unittest_cmds = [c for c in plan["serial_commands"] if c[:3] == ["python3", "-m", "unittest"]]
            self.assertEqual(len(unittest_cmds), 1, msg=touched)
            self.assertIn("eval.test_owner_role_audit", unittest_cmds[0], msg=touched)
            self.assertIn("eval.test_design_judge", unittest_cmds[0], msg=touched)

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

    def test_git_changed_file_discovery_special_names_untracked_note_and_reversible_raw_bytes(self):
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
            (repo / "docs").mkdir()
            (repo / "docs/untracked_guide.md").write_text("# Broken [link](missing.md)\n", encoding="utf-8")
            special_names = [
                "hooks/test_路由.py",
                "hooks/test_with space.py",
                r"hooks/test_a\b.py",
            ]
            for rel in special_names:
                (repo / rel).write_text("if __name__ == '__main__':\n    pass\n", encoding="utf-8")

            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, resolved_base, _, _, _, _, untracked = mod._discover_candidate(
                    repo, base_ref="refs/remotes/origin/main"
                )
            self.assertEqual(resolved_base, "refs/remotes/origin/main")
            for expected in ["a.txt", "b.txt", "c.txt", "docs/untracked_guide.md", *special_names]:
                self.assertIn(expected, changed)
            self.assertIn("docs/untracked_guide.md", untracked)

            plan = mod.build_test_plan(
                changed,
                repo_root=repo,
                resolved_base_ref=resolved_base,
                untracked_files=untracked,
            )
            for suite in special_names:
                self.assertIn(suite, plan["parallel_suites"])
            self.assertIn("docs/untracked_guide.md", plan["untracked_files"])
            self.assertTrue(any("untracked-files:" in n for n in plan["notes"]))

        # Portable synthetic Git output for non-UTF-8 byte 0xff (APFS rejects creating 0xff on disk).
        raw_non_utf8 = os.fsdecode(b"hooks/test_raw_\xff.py")
        literal_escaped = r"hooks/test_raw_\udcff.py"

        class FakeCompleted:
            returncode = 0
            stdout = b"hooks/test_raw_\xff.py\x00hooks/test_raw_\\udcff.py\x00"
            stderr = b""

        with unittest.mock.patch.object(mod, "_git_bytes", return_value=FakeCompleted()):
            parsed_paths = mod._git_nul_paths(REPO_ROOT, "ls-files", "-z")
        self.assertEqual([os.fsencode(p) for p in parsed_paths], [b"hooks/test_raw_\xff.py", b"hooks/test_raw_\\udcff.py"])

        # JSON encoding must keep raw 0xff and literal `\udcff` distinct and round-trippable.
        encoded_payload = json.dumps(mod._json_safe({"files": [raw_non_utf8, literal_escaped]}), ensure_ascii=False)
        decoded_items = json.loads(encoded_payload)["files"]
        self.assertNotEqual(decoded_items[0], decoded_items[1])
        self.assertEqual(os.fsencode(mod.decode_json_str(decoded_items[0])), b"hooks/test_raw_\xff.py")
        self.assertEqual(os.fsencode(mod.decode_json_str(decoded_items[1])), b"hooks/test_raw_\\udcff.py")

        # Shell quoting for --dry-run must round-trip exact bytes in bash for both names without raw ESC/FF.
        q_raw = mod._shell_quote(raw_non_utf8)
        q_lit = mod._shell_quote(literal_escaped)
        self.assertNotEqual(q_raw, q_lit)
        out_raw = subprocess.run(["bash", "-c", f"printf '%s' {q_raw}"], capture_output=True, check=True).stdout
        out_lit = subprocess.run(["bash", "-c", f"printf '%s' {q_lit}"], capture_output=True, check=True).stdout
        self.assertEqual(out_raw, b"hooks/test_raw_\xff.py")
        self.assertEqual(out_lit, b"hooks/test_raw_\\udcff.py")

    def test_base_resolution_precedence_shadow_corrupt_ref_unrelated_upstream_and_files_env(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "base.txt").write_text("base\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            # Farther ref origin/dev is 3 commits behind origin/main and placed FIRST via default_base_ref.
            subprocess.run(["git", "update-ref", "refs/remotes/origin/dev", "HEAD"], cwd=repo, env=env, check=True)
            for i in range(3):
                (repo / f"main{i}.txt").write_text("x\n", encoding="utf-8")
                subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
                subprocess.run(["git", "commit", "-q", "-m", f"main {i}"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)
            origin_main_sha = subprocess.run(
                ["git", "rev-parse", "refs/remotes/origin/main"],
                cwd=repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()

            subprocess.run(["git", "checkout", "-q", "-b", "feat"], cwd=repo, env=env, check=True)
            (repo / "feature.txt").write_text("f\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "feature"], cwd=repo, env=env, check=True)

            # Local branch literally named `origin/main` pointing at HEAD must NOT shadow refs/remotes/origin/main,
            # AND passing default_base_ref="origin/dev" first must still pick nearer refs/remotes/origin/main.
            subprocess.run(["git", "branch", "origin/main", "HEAD"], cwd=repo, env=env, check=True)

            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, resolved = mod.collect_changed_files(repo, default_base_ref="origin/dev")
            self.assertEqual(resolved, "refs/remotes/origin/main")
            self.assertEqual(changed, ["feature.txt"])

            with unittest.mock.patch.dict(os.environ, env, clear=True):
                _, resolved_shadow = mod.collect_changed_files(repo, default_base_ref="origin/main")
            self.assertEqual(resolved_shadow, "refs/remotes/origin/main")

            # Option-shaped (--base-ref=--independent reaches validator past argparse!) and missing explicit bases fail closed.
            for bad_arg in ("--base-ref=--independent", "--base-ref=refs/heads/no-such-branch-xyz"):
                proc = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), bad_arg, "--json"],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc.returncode, 2, msg=bad_arg)
                self.assertEqual(proc.stdout, "")

            # CCL_SKILL_BASE_REF must be honored AND fail closed on invalid values even when --files is supplied!
            bad_env = dict(env, CCL_SKILL_BASE_REF="refs/remotes/origin/typo-branch")
            for extra in ([], ["--files", "feature.txt"]):
                proc = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), *extra, "--json"],
                    env=bad_env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc.returncode, 2, msg=extra)
                self.assertEqual(proc.stdout, "")

            good_env = dict(env, CCL_SKILL_BASE_REF="refs/remotes/origin/main")
            proc_files_env = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--files", "feature.txt", "--json"],
                env=good_env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_files_env.returncode, 0, msg=proc_files_env.stderr)
            files_payload = json.loads(proc_files_env.stdout)
            self.assertEqual(files_payload["resolved_base_ref"], "refs/remotes/origin/main")
            self.assertEqual(files_payload["resolved_base_sha"], origin_main_sha)

            # Existing integration ref pointing to a non-commit (blob) or corrupt object must fail closed (exit 2),
            # never silently fall back to a peer ref!
            blob_sha = subprocess.run(
                ["git", "hash-object", "-w", "--stdin"],
                input="not-a-commit\n",
                cwd=repo,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            dev_ref_file = repo / ".git" / "refs" / "remotes" / "origin" / "dev"
            dev_ref_file.parent.mkdir(parents=True, exist_ok=True)
            dev_ref_file.write_text(blob_sha + "\n", encoding="utf-8")
            proc_corrupt_ref = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--json"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_corrupt_ref.returncode, 2)
            self.assertEqual(proc_corrupt_ref.stdout, "")

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

            # Upstream-only repo honors short `upstream/dev` default_base_ref (canonicalized to refs/remotes/upstream/dev)
            # even when a local branch `refs/heads/upstream/dev` points at HEAD!
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/origin/main"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "-d", "refs/remotes/origin/dev"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/upstream/dev", origin_main_sha], cwd=repo, env=env, check=True)
            subprocess.run(["git", "branch", "upstream/dev", "HEAD"], cwd=repo, env=env, check=True)
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed_up, resolved_up = mod.collect_changed_files(
                    repo, default_base_ref="upstream/dev"
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

    def test_resolved_base_snapshot_reaches_child_subprocess_and_strips_overrides(self):
        mod = load_selector()
        pinned_sha = "c" * 40
        plan = mod.build_test_plan(
            ["scripts/select-affected-tests.py"],
            repo_root=REPO_ROOT,
            default_base_ref="origin/dev",
            resolved_base_ref="refs/remotes/origin/main",
            resolved_base_sha=pinned_sha,
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
                pinned_sha,
            ]],
        )

        # Verify through the real execute_plan -> _run_cmd subprocess boundary!
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            env_dump = sandbox / "child_env.json"
            probe_plan = {
                "changed_files": ["x"],
                "resolved_base_ref": "refs/remotes/origin/main",
                "resolved_base_sha": pinned_sha,
                "preflight_commands": [[
                    sys.executable,
                    "-c",
                    "import json, os, pathlib, sys; pathlib.Path(sys.argv[1]).write_text(json.dumps(dict(os.environ)), encoding='utf-8')",
                    str(env_dump),
                ]],
                "parallel_suites": [],
                "serial_commands": [],
                "notes": [],
                "skipped_lanes": [],
            }
            dirty = dict(
                env,
                MAKEFLAGS=" -- CCL_SKILL_DEFAULT_BASE_REF=origin/main",
                MAKEOVERRIDES="${-*-command-variables-*-}",
                AFFECTED_ARGS="--include-slow",
                CCL_SKILL_DEFAULT_BASE_REF="origin/main",
                GIT_DIR="/decoy/git-dir",
                GIT_INDEX_FILE="/decoy/index",
                GIT_SHALLOW_FILE="/decoy/shallow",
                GIT_NO_REPLACE_OBJECTS="1",
                GIT_CONFIG_COUNT="1",
                GIT_CONFIG_KEY_0="core.hooksPath",
                GIT_CONFIG_VALUE_0="/decoy/hooks",
            )
            dirty["-*-command-variables-*-"] = "CCL_SKILL_DEFAULT_BASE_REF=origin/main"
            buf = io.StringIO()
            with unittest.mock.patch.dict(os.environ, dirty, clear=True), contextlib.redirect_stdout(buf):
                rc = mod.execute_plan(probe_plan, repo)
            self.assertEqual(rc, 0)
            observed = json.loads(env_dump.read_text(encoding="utf-8"))
            for forbidden in (
                "MAKEFLAGS",
                "MAKEOVERRIDES",
                "-*-command-variables-*-",
                "AFFECTED_ARGS",
                "CCL_SKILL_DEFAULT_BASE_REF",
                "GIT_DIR",
                "GIT_INDEX_FILE",
                "GIT_SHALLOW_FILE",
                "GIT_NO_REPLACE_OBJECTS",
                "GIT_CONFIG_COUNT",
                "GIT_CONFIG_KEY_0",
                "GIT_CONFIG_VALUE_0",
            ):
                self.assertNotIn(forbidden, observed)
            self.assertEqual(observed["CCL_SKILL_BASE_REF"], pinned_sha)
            self.assertEqual(observed["GIT_CONFIG_NOSYSTEM"], "1")
            self.assertEqual(observed["GIT_CONFIG_GLOBAL"], os.devnull)
            self.assertEqual(observed["GIT_CONFIG_SYSTEM"], os.devnull)

    def test_git_isolation_covers_discovery_child_templates_and_global_hooks(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            poison_tpl = sandbox / "poison-tpl"
            hooks_dir = poison_tpl / "hooks"
            hooks_dir.mkdir(parents=True)
            sentinel = sandbox / "hook-fired"
            for hook_name in ("pre-commit", "post-checkout", "post-index-change"):
                hp = hooks_dir / hook_name
                hp.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
                hp.chmod(0o755)

            fake_home = sandbox / "fake-home"
            global_hooks = fake_home / "global-hooks"
            global_hooks.mkdir(parents=True)
            ghook = global_hooks / "pre-commit"
            ghook.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
            ghook.chmod(0o755)
            (fake_home / ".gitconfig").write_text(
                f"[core]\n\thooksPath = {global_hooks}\n",
                encoding="utf-8",
            )

            target_repo, _, env = init_fixture_repo(sandbox / "target")
            (target_repo / "f.txt").write_text("v1\n", encoding="utf-8")
            subprocess.run(["git", "add", "f.txt"], cwd=target_repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "c1"], cwd=target_repo, env=env, check=True)
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

            caller_repo, _, caller_env = init_fixture_repo(sandbox / "caller")
            (caller_repo / "keep.txt").write_text("caller\n", encoding="utf-8")
            subprocess.run(["git", "add", "keep.txt"], cwd=caller_repo, env=caller_env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "caller init"], cwd=caller_repo, env=caller_env, check=True)
            caller_index = caller_repo / ".git" / "index"
            caller_index_before = hashlib.sha256(caller_index.read_bytes()).hexdigest()

            shallow_file = sandbox / "fake-shallow"
            shallow_file.write_text(tip_sha + "\n", encoding="utf-8")
            polluted_env = {
                "PATH": os.environ.get("PATH", ""),
                "HOME": str(fake_home),
                "GIT_TEMPLATE_DIR": str(poison_tpl),
                "GIT_DIR": str(caller_repo / ".git"),
                "GIT_WORK_TREE": str(caller_repo),
                "GIT_INDEX_FILE": str(caller_index),
                "GIT_SHALLOW_FILE": str(shallow_file),
                "GIT_NO_REPLACE_OBJECTS": "1",
            }
            with unittest.mock.patch.dict(os.environ, polluted_env, clear=True):
                changed, resolved = mod.collect_changed_files(target_repo)
            self.assertEqual(resolved, "refs/remotes/origin/main")
            self.assertEqual(changed, ["f.txt"])

            # Child execution via execute_plan must isolate child `git init` + `git commit` + `.git/info/attributes`
            # from BOTH inherited GIT_TEMPLATE_DIR and $HOME/.gitconfig core.hooksPath!
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
                'printf "* text=auto\\n" >"$d/.git/info/attributes"\n'
                'git -C "$d" config user.email t@example.com\n'
                'git -C "$d" config user.name T\n'
                'echo payload >"$d/staged.txt"\n'
                'git -C "$d" add staged.txt\n'
                'git -C "$d" commit -q -m "child commit"\n',
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
            self.assertFalse(sentinel.exists())
            caller_index_after = hashlib.sha256(caller_index.read_bytes()).hexdigest()
            self.assertEqual(caller_index_before, caller_index_after, "child suite mutated caller GIT_INDEX_FILE")

    def test_repo_root_validation_broken_git_missing_git_binary_and_trailing_cr(self):
        mod = load_selector()
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

            # Broken .git pointer must fail closed even in --files mode!
            broken_wt = sandbox / "broken-wt"
            broken_wt.mkdir()
            (broken_wt / ".git").write_text("gitdir: /nonexistent/worktree/gitdir\n", encoding="utf-8")
            for extra_args in (["--files", "--json"], ["--files", "a.py", "--json"]):
                proc_broken = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(broken_wt), *extra_args],
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc_broken.returncode, 2, msg=extra_args)
                self.assertEqual(proc_broken.stdout, "")

            # Missing `git` binary on PATH must exit 2 cleanly without a Python traceback.
            repo, _, env = init_fixture_repo(sandbox / "w")
            proc_nogit = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--dry-run"],
                env={"PATH": str(sandbox / "empty-path")},
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_nogit.returncode, 2)
            self.assertEqual(proc_nogit.stdout, "")
            self.assertNotIn("Traceback", proc_nogit.stderr)

            # Checkout directory ending in `\r` (valid on POSIX) must pass verify_repo_root.
            try:
                cr_repo, _, cr_env = init_fixture_repo(sandbox / "cr", repo_name="checkout\r")
            except OSError:
                cr_repo = None
            if cr_repo is not None:
                with unittest.mock.patch.dict(os.environ, cr_env, clear=True):
                    verified = mod.verify_repo_root(cr_repo)
                self.assertEqual(verified, cr_repo.resolve())

            sub = repo / "nested" / "dir"
            sub.mkdir(parents=True)
            (sub / "x.txt").write_text("hi\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            for extra_args in (["--json"], ["--files", "nested/dir/x.txt", "--json"]):
                proc_sub = subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), "--repo", str(sub), *extra_args],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc_sub.returncode, 2, msg=extra_args)
                self.assertEqual(proc_sub.stdout, "")

            (repo / ".git" / "index").write_bytes(b"CORRUPT_INDEX_HEADER")
            proc_corrupt = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--repo", str(repo), "--json"],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_corrupt.returncode, 2)
            self.assertEqual(proc_corrupt.stdout, "")

    def test_containment_covers_dedicated_serial_make_fallback_symlink_loops_non_suites_and_toctou(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            outside = sandbox / "test_outside.py"
            sentinel = sandbox / "outside-executed"
            outside.write_text("raise SystemExit(0)\n", encoding="utf-8")
            outside.chmod(0o755)

            repo, _, env = init_fixture_repo(sandbox / "w")
            (repo / "hooks").mkdir()
            escape_link = repo / "hooks" / "test_escape.sh"
            escape_link.symlink_to(outside)

            # Symlink loop must be classified unsafe without raising RuntimeError.
            loop_link = repo / "hooks" / "test_loop.sh"
            loop_link.symlink_to("test_loop.sh")

            # Non-executable fixture `test_payload.json` in generic skill scripts/ must NOT be selected!
            (repo / "skills/demo/scripts").mkdir(parents=True)
            (repo / "skills/demo/scripts/tool.py").write_text("x = 1\n", encoding="utf-8")
            (repo / "skills/demo/scripts/test_payload.json").write_text("{}\n", encoding="utf-8")
            (repo / "skills/demo/scripts/test_tool.py").write_text("if __name__ == '__main__':\n    pass\n", encoding="utf-8")

            # Dedicated suite symlinked outside checkout must NOT be added to serial_commands!
            (repo / "skills/test-artifact-management/references").mkdir(parents=True)
            (repo / "skills/test-artifact-management/references/test_gen_report.py").symlink_to(outside)

            plan = mod.build_test_plan(
                [
                    "hooks/test_escape.sh",
                    "hooks/test_loop.sh",
                    "../test_outside.py",
                    "skills/demo/scripts/tool.py",
                    "skills/test-artifact-management/references/gen_report.py",
                ],
                repo_root=repo,
            )
            self.assertEqual(plan["parallel_suites"], ["skills/demo/scripts/test_tool.py"])
            serial_flat = "\n".join(" ".join(c) for c in plan["serial_commands"])
            self.assertNotIn("test_gen_report.py", serial_flat)
            self.assertTrue(plan["unsafe_blocked"])
            self.assertTrue(any("unsafe" in n for n in plan["notes"]))

            # Registered Makefile suite escaping checkout + unrecognized file must NOT schedule `make test-repo-gates`!
            (repo / "Makefile").write_text(
                "test-repo-gates:\n\tbash hooks/test_escape.sh\n",
                encoding="utf-8",
            )
            esc_plan = mod.build_test_plan(["hooks/test_escape.sh", "unrecognized.foo"], repo_root=repo)
            self.assertTrue(esc_plan["unsafe_blocked"])
            self.assertFalse(any(c[0] == "make" for c in esc_plan["serial_commands"]))
            esc_buf = io.StringIO()
            with unittest.mock.patch.dict(os.environ, env, clear=True), contextlib.redirect_stdout(esc_buf):
                rc_esc = mod.execute_plan(esc_plan, repo)
            self.assertEqual(rc_esc, 2)

            # Dispatch-time TOCTOU: suite is a safe regular file during planning, then replaced by escaping symlink
            # during preflight before parallel runner runs -> execute_plan must block with exit 2!
            safe_suite = repo / "hooks" / "test_toctou.sh"
            safe_suite.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            safe_suite.chmod(0o755)
            (repo / "scripts").mkdir(exist_ok=True)
            (repo / "scripts/run-parallel-suites.sh").write_bytes(
                (REPO_ROOT / "scripts/run-parallel-suites.sh").read_bytes()
            )
            outside_sh = sandbox / "outside_exec.sh"
            outside_sh.write_text(
                "#!/usr/bin/env bash\nprintf 'ran' > \"$OUTSIDE_SENTINEL\"\n",
                encoding="utf-8",
            )
            outside_sh.chmod(0o755)
            toctou_plan = {
                "changed_files": ["hooks/test_toctou.sh"],
                "resolved_base_ref": None,
                "preflight_commands": [[
                    sys.executable,
                    "-c",
                    "import os, sys; os.unlink(sys.argv[1]); os.symlink(sys.argv[2], sys.argv[1])",
                    str(safe_suite),
                    str(outside_sh),
                ]],
                "parallel_suites": ["hooks/test_toctou.sh"],
                "serial_commands": [],
                "notes": [],
                "skipped_lanes": [],
            }
            toctou_out = io.StringIO()
            toctou_err = io.StringIO()
            run_env = dict(env, OUTSIDE_SENTINEL=str(sentinel))
            with (
                unittest.mock.patch.dict(os.environ, run_env, clear=True),
                contextlib.redirect_stdout(toctou_out),
                contextlib.redirect_stderr(toctou_err),
            ):
                rc_toctou = mod.execute_plan(toctou_plan, repo, jobs=1)
            self.assertEqual(rc_toctou, 2)
            self.assertFalse(sentinel.exists(), "TOCTOU symlink replacement was executed")

    def test_every_literal_suite_path_in_selector_exists(self):
        import re

        source = SELECTOR_PATH.read_text(encoding="utf-8")
        literals = set(re.findall(r'"((?:hooks|scripts|skills|eval)/[^"\s]+\.(?:sh|py))"', source))
        self.assertTrue(literals)
        missing = sorted(p for p in literals if not (REPO_ROOT / p).is_file())
        self.assertEqual(missing, [], msg="selector names suites that do not exist")

    def test_makefile_recipe_parser_deleted_registered_suite_and_spaced_tmpdir_fallback(self):
        mod = load_selector()
        universe = mod.makefile_suites(REPO_ROOT)
        hook_suites = {s for s in universe if s.startswith("hooks/")}
        self.assertIn("hooks/test_agy_bridge.py", hook_suites)
        plan = mod.build_test_plan(["hooks/hooks.json"], repo_root=REPO_ROOT)
        dispatched_hooks = set(plan["parallel_suites"]) | {
            cmd[-1]
            for cmd in plan["serial_commands"]
            if len(cmd) >= 5 and cmd[:4] == ["python3", "-m", "pytest", "-q"]
        }
        self.assertEqual(hook_suites - dispatched_hooks, set())

        # Use a sandbox path containing spaces so shell-path regressions fail immediately.
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "space in tmpdir"
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "hooks").mkdir()
            (repo / "hooks/test_quoted space.sh").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            (repo / "Makefile").write_text(
                "# Commented retired suite must NOT count: hooks/test_retired_comment.sh\n"
                "test-repo-gates:\n"
                '\t# Recipe comment: hooks/test_recipe_comment.sh\n'
                '\tbash "hooks/test_quoted space.sh" \\\n'
                "\t  && bash hooks/test_deleted_from_disk.sh\n"
                "test-code-review-2:\n"
                "\tbash scripts/run-parallel-suites.sh skills/code-review/scripts/test_review_client_order.sh\n",
                encoding="utf-8",
            )
            parsed = mod.makefile_suites(repo)
            self.assertIn("hooks/test_quoted space.sh", parsed)
            self.assertIn("hooks/test_deleted_from_disk.sh", parsed)
            self.assertIn("skills/code-review/scripts/test_review_client_order.sh", parsed)
            self.assertNotIn("hooks/test_retired_comment.sh", parsed)
            self.assertNotIn("hooks/test_recipe_comment.sh", parsed)

            # Deleting a directly changed registered suite itself must ALSO trigger selector-drift fallback!
            del_direct = mod.build_test_plan(
                ["skills/code-review/scripts/test_review_client_order.sh"],
                repo_root=repo,
            )
            self.assertIn("skills/code-review/scripts/test_review_client_order.sh", del_direct["missing_suites"])
            self.assertTrue(any("selector-drift" in n for n in del_direct["notes"]))
            self.assertIn(["make", "test-code-review-2"], del_direct["serial_commands"])

            # End-to-end execution of fallback Make targets without interpolating paths into shell source.
            drift_plan = mod.build_test_plan(["hooks/new-unmapped.sh"], repo_root=repo)
            self.assertIn("hooks/test_deleted_from_disk.sh", drift_plan["missing_suites"])
            (repo / "Makefile").write_text(
                "test-repo-gates:\n\t@:\n",
                encoding="utf-8",
            )
            drift_plan["preflight_commands"] = []
            drift_plan["parallel_suites"] = []
            drift_plan["serial_commands"] = [c for c in drift_plan["serial_commands"] if c[0] == "make"]
            ran_log = sandbox / "make calls.log"
            bin_dir = sandbox / "bin"
            bin_dir.mkdir()
            fake_make = bin_dir / "make"
            fake_make.write_text(
                '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$FAKE_MAKE_LOG"\n',
                encoding="utf-8",
            )
            fake_make.chmod(0o755)
            run_env = dict(
                env,
                PATH=f"{bin_dir}:{env.get('PATH', '')}",
                FAKE_MAKE_LOG=str(ran_log),
            )
            buf = io.StringIO()
            with unittest.mock.patch.dict(os.environ, run_env, clear=True), contextlib.redirect_stdout(buf):
                rc = mod.execute_plan(drift_plan, repo)
            self.assertEqual(rc, 0, msg=buf.getvalue())
            recorded_targets = ran_log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(
                recorded_targets,
                ["test-repo-gates", "test-regressions-fast", "test-code-review-1", "test-code-review-2"],
            )

    def test_makefile_passes_inputs_without_shell_interpretation(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "Makefile").write_bytes((REPO_ROOT / "Makefile").read_bytes())
            (repo / "scripts").mkdir()
            (repo / "scripts/select-affected-tests.py").write_bytes(SELECTOR_PATH.read_bytes())
            (repo / "f.txt").write_text("base\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            pwn_file = sandbox / "shell-injected"
            proc = subprocess.run(
                [
                    "make",
                    "--no-print-directory",
                    "-C",
                    str(repo),
                    "test-affected-plan",
                    f"CCL_SKILL_DEFAULT_BASE_REF=origin/main;touch {pwn_file}",
                    f'AFFECTED_ARGS=--files "docs/a`touch {pwn_file}`.md"',
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            self.assertFalse(pwn_file.exists(), "Makefile shell-evaluated metacharacters in variables")
            self.assertIn("docs/a`touch", proc.stdout)

    def test_pytest_style_suite_with_module_setup_dispatches_via_pytest_and_fails_on_red_assertion(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "scripts").mkdir()
            failing_suite = repo / "scripts/test_no_main_red.py"
            failing_suite.write_text(
                "from pathlib import Path\n"
                "ROOT = Path(__file__).resolve().parent\n"
                "ITEMS = sorted([1, 2, 3])\n"
                "def test_deliberate_failure():\n"
                "    assert ROOT.name == 'impossible'\n",
                encoding="utf-8",
            )
            plan = mod.build_test_plan(["scripts/test_no_main_red.py"], repo_root=repo)
            plan["preflight_commands"] = []
            self.assertNotIn("scripts/test_no_main_red.py", plan["parallel_suites"])
            pytest_cmd = ["python3", "-m", "pytest", "-q", "scripts/test_no_main_red.py"]
            self.assertIn(pytest_cmd, plan["serial_commands"])
            plan["serial_commands"] = [pytest_cmd]

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
            self.assertNotEqual(rc_fail, 0, "pytest-style failing suite with module setup exited 0")
            self.assertTrue(buf_fail.getvalue().strip().endswith("advisory: run make test before push"))

            failing_suite.write_text(
                "from pathlib import Path\nROOT = Path(__file__).resolve().parent\ndef test_ok():\n    assert ROOT.is_dir()\n",
                encoding="utf-8",
            )
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
            subprocess.run(["git", "config", "diff.renames", "true"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "mv", "old.txt", "new.txt"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "rename"], cwd=repo, env=env, check=True)
            with unittest.mock.patch.dict(os.environ, env, clear=True):
                changed, _ = mod.collect_changed_files(repo, base_ref="refs/remotes/origin/main")
            self.assertEqual(changed, ["new.txt", "old.txt"])

    def test_sigterm_cancellation_forwards_to_active_runner_child_group(self):
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp)
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "scripts").mkdir()
            (repo / "scripts/run-parallel-suites.sh").write_bytes(
                (REPO_ROOT / "scripts/run-parallel-suites.sh").read_bytes()
            )
            for stub_rel in (
                "skills/skill-extraction-workflow/scripts/check-ccl-skills.sh",
                "skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py",
                "skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh",
            ):
                stub = repo / stub_rel
                stub.parent.mkdir(parents=True, exist_ok=True)
                stub.write_text("#!/usr/bin/env bash\nexit 0\n" if stub_rel.endswith(".sh") else "raise SystemExit(0)\n", encoding="utf-8")
                stub.chmod(0o755)
            pid_file = sandbox / "grandchild.pid"
            term_file = sandbox / "suite.terminated"
            slow_suite = repo / "scripts/test_slow_cancel.sh"
            slow_suite.write_text(
                "#!/usr/bin/env bash\n"
                'trap \'printf "term\\n" > "$TERM_MARKER"; exit 143\' TERM\n'
                "sleep 30 &\n"
                'spid=$!\n'
                'printf "%s\\n" "$spid" > "$PID_MARKER"\n'
                "wait $spid\n",
                encoding="utf-8",
            )
            slow_suite.chmod(0o755)
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            run_env = dict(env, PID_MARKER=str(pid_file), TERM_MARKER=str(term_file))
            proc = subprocess.Popen(
                [
                    sys.executable,
                    str(SELECTOR_PATH),
                    "--repo",
                    str(repo),
                    "--files",
                    "scripts/test_slow_cancel.sh",
                    "--run",
                ],
                env=run_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                deadline = time.monotonic() + 8.0
                while not pid_file.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertTrue(pid_file.exists(), "child suite did not start")
                grandchild_pid = int(pid_file.read_text(encoding="utf-8").strip())
                proc.send_signal(signal.SIGTERM)
                out, err = proc.communicate(timeout=8.0)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()

            self.assertEqual(proc.returncode, 128 + signal.SIGTERM, msg=err)
            self.assertTrue(term_file.exists(), "SIGTERM was not forwarded to active runner")
            # Grandchild sleep must also have been terminated by run-parallel-suites.sh's group kill.
            reap_deadline = time.monotonic() + 3.0
            alive = True
            while time.monotonic() < reap_deadline:
                if not _pid_is_live_non_zombie(grandchild_pid):
                    alive = False
                    break
                time.sleep(0.05)
            self.assertFalse(alive, "grandchild process leaked after SIGTERM")

    def test_json_dry_run_replay_early_diagnostics_ansi_escape_exit_codes_and_broken_pipe(self):
        mod = load_selector()
        with tempfile.TemporaryDirectory() as tmp:
            sandbox = Path(tmp) / "dir with space"
            repo, _, env = init_fixture_repo(sandbox)
            (repo / "scripts").mkdir()
            (repo / "scripts/select-affected-tests.py").write_bytes(SELECTOR_PATH.read_bytes())
            (repo / "scripts/test_select_affected_tests.py").write_text(
                "if __name__ == '__main__':\n    pass\n",
                encoding="utf-8",
            )
            subprocess.run(["git", "add", "."], cwd=repo, env=env, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, env=env, check=True)
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", "HEAD"], cwd=repo, env=env, check=True)

            proc_json = subprocess.run(
                [
                    sys.executable,
                    str(SELECTOR_PATH),
                    "--repo",
                    str(repo),
                    "--files",
                    "scripts/select-affected-tests.py",
                    "--json",
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_json.returncode, 0, msg=proc_json.stderr)
            payload = json.loads(proc_json.stdout)
            self.assertEqual(payload["advisory"], "advisory: run make test before push")
            self.assertIn("scripts/test_select_affected_tests.py", payload["parallel_suites"])

            (repo / "hooks").mkdir()
            spaced = repo / "hooks/test_space name.sh"
            spaced.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            spaced.chmod(stat.S_IRWXU)
            ansi_doc = "docs/\x1b[31mRED\x1b[0m\necho INJECTED.md"
            pinned_sha = "d" * 40
            plan = mod.build_test_plan(
                ["hooks/test_space name.sh", ansi_doc],
                repo_root=repo,
                resolved_base_ref="refs/remotes/origin/main",
                resolved_base_sha=pinned_sha,
            )
            dry_buf = io.StringIO()
            with contextlib.redirect_stdout(dry_buf):
                mod.print_dry_run(plan, repo, "refs/remotes/origin/main", resolved_base_sha=pinned_sha, jobs=3)
            dry_text = dry_buf.getvalue()
            dry_lines = dry_text.splitlines()
            self.assertEqual(dry_lines[-1], "# advisory: run make test before push")
            self.assertNotIn("\x1b", dry_text, "raw ANSI ESC leaked into dry-run output")
            self.assertFalse(any(line == "echo INJECTED.md" for line in dry_lines))
            self.assertTrue(any(line.startswith("cd -- ") for line in dry_lines))
            self.assertTrue(any(f"CCL_SKILL_BASE_REF={pinned_sha}" in line for line in dry_lines))
            parallel_lines = [line for line in dry_lines if "run-parallel-suites.sh" in line]
            self.assertEqual(len(parallel_lines), 1)
            self.assertIn("--jobs 3", parallel_lines[0])
            self.assertIn("'hooks/test_space name.sh'", parallel_lines[0])

            # Unsafe-blocked dry-run refuses to emit runnable suite commands and emits `(exit 2)`.
            blocked_dry = io.StringIO()
            with contextlib.redirect_stdout(blocked_dry):
                mod.print_dry_run(
                    {
                        "changed_files": ["hooks/test_space name.sh"],
                        "preflight_commands": [["echo", "SHOULD_NOT_EMIT"]],
                        "parallel_suites": ["hooks/test_space name.sh"],
                        "serial_commands": [],
                        "notes": ["unsafe-suite-path: skipped"],
                        "skipped_lanes": [],
                        "unsafe_blocked": True,
                    },
                    repo,
                    "refs/remotes/origin/main",
                )
            self.assertNotIn("SHOULD_NOT_EMIT", blocked_dry.getvalue())
            self.assertIn("(exit 2)", blocked_dry.getvalue().splitlines())

            # Replayability from a DIFFERENT working directory: executing a minimal dry-run script runs in `repo`.
            other_cwd = sandbox / "elsewhere"
            other_cwd.mkdir()
            (repo / "scripts").mkdir(exist_ok=True)
            (repo / "scripts/run-parallel-suites.sh").write_bytes(
                (REPO_ROOT / "scripts/run-parallel-suites.sh").read_bytes()
            )
            replay_marker = sandbox / "replayed-pwd.txt"
            spaced.write_text(
                '#!/usr/bin/env bash\nprintf "%s|%s" "$PWD" "${CCL_SKILL_BASE_REF:-}" > "$REPLAY_MARKER"\n',
                encoding="utf-8",
            )
            replay_plan = {
                "changed_files": ["hooks/test_space name.sh"],
                "preflight_commands": [],
                "parallel_suites": ["hooks/test_space name.sh"],
                "serial_commands": [],
                "notes": [],
                "skipped_lanes": [],
            }
            replay_buf = io.StringIO()
            with contextlib.redirect_stdout(replay_buf):
                mod.print_dry_run(
                    replay_plan,
                    repo,
                    "refs/remotes/origin/main",
                    resolved_base_sha=pinned_sha,
                    jobs=1,
                )
            proc_replay = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", replay_buf.getvalue()],
                cwd=other_cwd,
                env=dict(env, REPLAY_MARKER=str(replay_marker)),
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc_replay.returncode, 0, msg=proc_replay.stderr)
            self.assertEqual(replay_marker.read_text(encoding="utf-8"), f"{repo.resolve()}|{pinned_sha}")

            # Early-return diagnostics: `--run --files ../outside.sh` must emit stored unsafe-input note!
            unsafe_only = mod.build_test_plan(["../outside.sh"], repo_root=repo)
            out_unsafe = io.StringIO()
            with contextlib.redirect_stdout(out_unsafe):
                rc_unsafe = mod.execute_plan(unsafe_only, repo)
            self.assertEqual(rc_unsafe, 0)
            self.assertIn("note: unsafe-input-path:", out_unsafe.getvalue())

            # Preflight failure stops before parallel/serial work, emits notes + skipped, and prints advisory.
            marker = sandbox / "should-not-exist"
            fail_preflight = {
                "changed_files": ["x"],
                "resolved_base_ref": "refs/remotes/origin/main",
                "preflight_commands": [[sys.executable, "-c", "raise SystemExit(3)"]],
                "parallel_suites": [],
                "serial_commands": [[sys.executable, "-c", "import pathlib, sys; pathlib.Path(sys.argv[1]).write_text('', encoding='utf-8')", str(marker)]],
                "notes": ["selector-drift: synthetic\x1b[31mNote"],
                "skipped_lanes": ["abort-leak"],
            }
            out_pre = io.StringIO()
            with contextlib.redirect_stdout(out_pre):
                rc_pre = mod.execute_plan(fail_preflight, repo)
            self.assertEqual(rc_pre, 3)
            self.assertFalse(marker.exists())
            pre_text = out_pre.getvalue()
            self.assertNotIn("\x1b", pre_text)
            self.assertIn("note: selector-drift:", pre_text)
            self.assertIn("skipped: abort-leak", pre_text)
            self.assertEqual(pre_text.splitlines()[-1], "advisory: run make test before push")

            # Serial child exit code (7), missing executable (127), signal death (143), and parallel failure (1).
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

            # Closed-pipe test (no shell interpolation): both --dry-run and --json must flush inside the
            # BrokenPipeError handler, exit 141, and emit zero stderr!
            for mode_flag in ("--dry-run", "--json"):
                r_fd, w_fd = os.pipe()
                os.close(r_fd)
                try:
                    proc_pipe = subprocess.run(
                        [
                            sys.executable,
                            str(SELECTOR_PATH),
                            "--repo",
                            str(repo),
                            "--files",
                            "hooks/test_space name.sh",
                            mode_flag,
                        ],
                        env=env,
                        stdout=w_fd,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                finally:
                    os.close(w_fd)
                self.assertEqual(proc_pipe.returncode, 141, msg=f"{mode_flag}: stderr={proc_pipe.stderr!r}")
                self.assertEqual(proc_pipe.stderr, "", msg=mode_flag)


if __name__ == "__main__":
    unittest.main()
