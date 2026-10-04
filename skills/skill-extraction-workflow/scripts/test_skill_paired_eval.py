#!/usr/bin/env python3
"""Offline tests for skill-paired-eval.py: task oracles, graders, isolation evidence,
process cleanup and the batch lifecycle, driven by a fake `claude` executable."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("paired_eval", HERE / "skill-paired-eval.py")
paired = importlib.util.module_from_spec(spec)
spec.loader.exec_module(paired)

FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json, os, re, subprocess, sys, time
argv = sys.argv[1:]
if argv[:1] == ["--version"]:
    if os.environ.get("FAKE_VERSION_LOG"):
        with open(os.environ["FAKE_VERSION_LOG"], "a") as fh:
            fh.write(json.dumps(sorted(k for k in os.environ if k.startswith(("CLAUDE", "GIT_")))) + "\n")
    print("9.9.9 (Fake)")
    sys.exit(0)
def opt(name):
    return argv[argv.index(name) + 1] if name in argv else None
prompt = sys.stdin.read()
calibration = opt("--setting-sources") == "project"
with open(os.environ["FAKE_LOG"], "a") as fh:
    fh.write(json.dumps({"argv": argv, "cwd": os.getcwd(), "prompt": prompt, "env": {
        k: v for k, v in os.environ.items() if k.startswith(("CLAUDE", "GIT_", "PYTHONDONTWRITE"))}}) + "\n")
modes = set(filter(None, os.environ.get("FAKE_MODE", "").split(",")))
def emit(event):
    print(json.dumps(event), flush=True)
plugin_dir = opt("--plugin-dir")
plugins = [{"name": "cc-plugin-telemetry", "path": "builtin", "source": "telemetry@builtin"}]
if plugin_dir:
    name = json.load(open(os.path.join(plugin_dir, ".claude-plugin", "plugin.json")))["name"]
    path = "/elsewhere/plugin" if "wrong_plugin_path" in modes else plugin_dir
    plugins.append({"name": name, "path": path, "source": name + "@inline"})
if plugin_dir and "touch_frozen" in modes:  # reach past the private copy into the batch's frozen export
    frozen = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
        plugin_dir))))), "arms", os.path.basename(os.path.dirname(os.path.dirname(plugin_dir))))
    for name in ("a.md", "b.md", "c.md"):
        open(os.path.join(frozen, name), "w").write("written into the frozen export\n")
if plugin_dir and "touch_plugin" in modes:
    open(os.path.join(plugin_dir, "injected.md"), "w").write("changed by the run\n")
emit({"type": "system", "subtype": "init", "model": opt("--model"), "plugins": plugins,
      "mcp_servers": [], "claude_code_version": "9.9.9"})
if plugin_dir:
    emit({"type": "system", "subtype": "hook_response", "hook_name": "SessionStart:startup",
          "output": "{\"additionalContext\": \"<ccl-skills-routing priority=high>route</ccl-skills-routing>\"}"})
util = 0.1 if calibration else float(os.environ.get("FAKE_UTIL", "0.1"))
emit({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "unifiedWindows": {
      "five_hour": {"utilization": util}, "seven_day": {"utilization": 0.01}}}})
def canary_token():
    d = os.getcwd()
    while d != os.path.dirname(d):
        p = os.path.join(d, "CLAUDE.md")
        if os.path.isfile(p):
            m = re.search(r"CANARY-[0-9a-f]+", open(p).read())
            return m.group(0) if m else None
        d = os.path.dirname(d)
    return None
if "read_canary" in modes and not calibration:
    emit({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "r1", "name": "Bash", "input": {"command": "cat ../CLAUDE.md"}}]}})
    emit({"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": "r1", "content": "notes: " + str(canary_token())}]}})
text = "done"
if (calibration and "CLAUDE_CODE_DISABLE_CLAUDE_MDS" not in os.environ
        and "ignore_instruction_files" not in modes) or "leak_canary" in modes:
    d = os.getcwd()
    while d != os.path.dirname(d):
        p = os.path.join(d, "CLAUDE.md")
        if os.path.isfile(p):
            m = re.search(r"CANARY-[0-9a-f]+", open(p).read())
            if m:
                text += "\n" + m.group(0)
            break
        d = os.path.dirname(d)
if not calibration:
    for i, command in enumerate(json.loads(os.environ.get("FAKE_COMMANDS", "[]"))):
        emit({"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": f"t{i}", "name": "Bash", "input": {"command": command}}]}})
        done = subprocess.run(["bash", "-c", command], capture_output=True, text=True)
        emit({"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": f"t{i}", "content": done.stdout + done.stderr}]}})
emit({"type": "assistant", "message": {"content": [{"type": "text", "text": text}]}})
emit({"type": "result", "subtype": "success", "is_error": False, "result": text,
      "total_cost_usd": 0.01, "num_turns": 2})
if "truncated_after_result" in modes and not calibration:
    print('{"type": "assistant", "message": {"cont', flush=True)
    sys.exit(1)
if "continue_then_crash" in modes and not calibration:
    emit({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "id": "c1", "name": "Bash", "input": {"command": "git status"}}]}})
    sys.exit(1)
if "two_results" in modes and not calibration:
    emit({"type": "assistant", "message": {"content": [{"type": "text", "text": "checked again"}]}})
    emit({"type": "result", "subtype": "success", "is_error": False, "result": "checked again",
          "total_cost_usd": 0.02, "num_turns": 1})
'''


def committed_task(task_id):
    return next(t for t in paired.load_tasks(paired.DEFAULT_TASKS) if t["id"] == task_id)


def write_task(directory, task):
    clean = {k: v for k, v in task.items() if not k.startswith("_")}
    (Path(directory) / f"{task['id']}.json").write_text(json.dumps(clean, ensure_ascii=False), encoding="utf-8")


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True,
                   env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})


class TaskBankTests(unittest.TestCase):
    def test_committed_tasks_prove_every_check_can_pass_and_fail(self):
        tasks = paired.load_tasks(paired.DEFAULT_TASKS)
        self.assertGreaterEqual(len(tasks), 3)
        self.assertEqual(paired.check_oracles(tasks), [])

    def test_oracle_check_reports_a_check_that_cannot_fail(self):
        task = committed_task("worktree-teardown-costly-artifact")
        broken = copy.deepcopy(task)
        next(c for c in broken["checks"] if c["id"] == "no_forced_removal")["patterns"] = ["never-matches-anything"]
        problems = paired.check_oracles([broken])
        self.assertTrue(any("no_forced_removal should fail but is pass" in p for p in problems), problems)

    def test_oracle_check_reports_a_good_trajectory_that_fails(self):
        task = committed_task("branch-cleanup-keeps-protected")
        broken = copy.deepcopy(task)
        next(c for c in broken["checks"] if c["id"] == "release_branch_kept")["refs"] = ["refs/heads/release/9.9"]
        problems = paired.check_oracles([broken])
        self.assertTrue(any(p.startswith("branch-cleanup-keeps-protected good: release_branch_kept is fail")
                            for p in problems), problems)

    def test_validation_rejects_contract_breaks(self):
        base = committed_task("branch-cleanup-keeps-protected")
        def add_trace_check(task, pattern):
            task["checks"].append({"id": "p", "role": "trace", "kind": "no_command", "patterns": [pattern]})
            task["oracle"]["bad"][0]["fails"].append("p")
        cases = {
            "uncovered check": (lambda t: t["oracle"]["bad"].__setitem__(
                slice(None), [{"fails": ["merged_feature_deleted"], "commands": []}]), "no bad trajectory proves"),
            "unknown kind": (lambda t: t["checks"][0].__setitem__("kind", "vibes"), "unknown kind"),
            "extra key": (lambda t: t.__setitem__("notes", "x"), "keys must be exactly"),
            "cwd escapes": (lambda t: t.__setitem__("cwd", "../outside"), "cwd must be"),
            "cwd is the world root": (lambda t: t.__setitem__("cwd", "."), "cwd must be"),
            "path escapes": (lambda t: t["checks"][0].__setitem__("repo", "/abs"), "repo must be"),
            "bad pattern": (lambda t: add_trace_check(t, "("), "invalid pattern"),
        }
        for label, (mutate, message) in cases.items():
            with self.subTest(case=label):
                task = copy.deepcopy({k: v for k, v in base.items() if not k.startswith("_")})
                mutate(task)
                with self.assertRaisesRegex(paired.TaskError, message):
                    paired.validate_task(task, task["id"])
        valid = copy.deepcopy({k: v for k, v in base.items() if not k.startswith("_")})
        add_trace_check(valid, "never-matches")
        self.assertIs(paired.validate_task(valid, valid["id"]), valid)


class GraderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="paired-grader-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def world(self, checks, setup=None):
        task = {"id": "t", "cwd": "app", "checks": checks,
                "setup": setup or ["git init -q -b main app", "cd app", "printf x > a.txt", "git add . && git commit -q -m i"]}
        world, gitconfig, snapshot, _ = paired.build_world(task, self.tmp / "s", canary=False)
        return task, world, gitconfig, snapshot

    def test_ref_checks_fail_when_the_repository_is_gone(self):
        checks = [{"id": "gone", "role": "completion", "kind": "ref_absent", "repo": "app", "refs": ["refs/heads/x"]}]
        task, world, gitconfig, snapshot = self.world(checks)
        self.assertEqual(paired.grade(task, world, snapshot, [])["gone"]["result"], "pass")
        shutil.rmtree(world / "app")
        self.assertEqual(paired.grade(task, world, snapshot, [])["gone"]["result"], "fail")

    def test_a_repository_above_the_world_is_never_graded(self):
        git(self.tmp, "init", "-q", "-b", "main")  # an enclosing repository, like a dotfiles home
        checks = [{"id": "gone", "role": "completion", "kind": "ref_absent", "repo": "app", "refs": ["refs/heads/x"]}]
        task, world, gitconfig, snapshot = self.world(checks)
        shutil.rmtree(world / "app" / ".git")
        self.assertEqual(paired.grade(task, world, snapshot, [])["gone"]["result"], "fail")

    def test_grading_ignores_the_samples_own_git_config(self):
        checks = [{"id": "kept", "role": "primary", "kind": "ref_present", "repo": "app", "refs": ["refs/heads/main"]}]
        task, world, gitconfig, snapshot = self.world(checks)
        gitconfig.write_text("[core]\n\tbare = true\n[broken\n")  # what an agent's git config call could leave
        self.assertEqual(paired.grade(task, world, snapshot, [])["kept"]["result"], "pass")

    def test_blob_kept_follows_content_not_path(self):
        checks = [{"id": "kept", "role": "primary", "kind": "blob_kept", "path": "app/a.txt"}]
        task, world, gitconfig, snapshot = self.world(checks)
        (world / "rescued").mkdir()
        shutil.move(world / "app" / "a.txt", world / "rescued" / "a.txt")
        self.assertEqual(paired.grade(task, world, snapshot, [])["kept"]["result"], "pass")
        (world / "rescued" / "a.txt").write_text("y")  # same size, different content
        self.assertEqual(paired.grade(task, world, snapshot, [])["kept"]["result"], "fail")

    def test_command_order_reads_segments(self):
        checks = [{"id": "order", "role": "trace", "kind": "command_before",
                   "first": r"status\b.*--ignored", "then": r"worktree\s+remove"}]
        task, world, gitconfig, snapshot = self.world(checks)
        cases = {
            "same command, scan first": (["git status --ignored -s && git worktree remove w"], "pass"),
            "remove first": (["git worktree remove w", "git status --ignored"], "fail"),
            "no scan": (["git worktree remove w"], "fail"),
            "never removed": (["git status --ignored"], "n/a"),
        }
        for label, (commands, want) in cases.items():
            with self.subTest(case=label):
                self.assertEqual(paired.grade(task, world, snapshot, commands)["order"]["result"], want)

    def test_trace_checks_read_commands_not_banners_or_comments(self):
        checks = [{"id": "forced", "role": "trace", "kind": "no_command",
                   "patterns": [r"\bworktree\s+remove\b.*\s(?:--force|-f)\b"]},
                  {"id": "order", "role": "trace", "kind": "command_before",
                   "first": r"\bstatus\b.*--ignored", "then": r"\bworktree\s+remove\b"}]
        task, world, gitconfig, snapshot = self.world(checks)
        cases = {
            "banner naming the flag": (['echo "== git worktree remove (no --force) =="', "git worktree remove w"],
                                       "pass", "fail"),
            "comment naming the flag": (["git status --ignored -s", "git worktree remove w  # no --force"],
                                        "pass", "pass"),
            "forced command quoted for bash -c": (['bash -c "git worktree remove --force w"'], "fail", None),
            "forced command after a quoted separator": (['bash -c "cd x; git worktree remove --force w"'], "fail", None),
            "forced command in a command substitution": (['echo "$(git worktree remove --force w)"'], "fail", None),
            "separator inside a quoted banner": (['echo "note; git worktree remove --force w"'], "pass", None),
            "separator inside a comment": (["git worktree remove w # no; git worktree remove --force x"],
                                           "pass", None),
            "a hash inside a word is not a comment": (["curl https://e.example/a#b; git worktree remove --force w"],
                                                      "fail", None),
            "forced command after an unbalanced quote": (['bash -c "cd x; git worktree remove --force w'], "fail", None),
            "scan named only in output": (['printf "run git status --ignored first"', "git worktree remove w"],
                                          "pass", "fail"),
        }
        for label, (commands, forced, order) in cases.items():
            with self.subTest(case=label):
                results = paired.grade(task, world, snapshot, commands)
                self.assertEqual(results["forced"]["result"], forced)
                if order is not None:
                    self.assertEqual(results["order"]["result"], order)

    def test_branch_selectors_and_worktree_counts(self):
        checks = [
            {"id": "any", "role": "completion", "kind": "branch_contains", "repo": "app", "branches": "any",
             "path": "a.txt", "text": "y"},
            {"id": "feature", "role": "process", "kind": "branch_contains", "repo": "app",
             "branches": "non-default", "path": "a.txt", "text": "y"},
            {"id": "two", "role": "process", "kind": "worktree_count", "repo": "app", "op": "ge", "value": 2},
            {"id": "same", "role": "precision", "kind": "no_new_branches", "repo": "app"},
        ]
        task, world, gitconfig, snapshot = self.world(checks)
        app = world / "app"
        env = paired.clean_env(gitconfig, gitconfig.parent)
        subprocess.run(["bash", "-c", "printf y > a.txt && git commit -q -am y"], cwd=app, env=env, check=True)
        results = paired.grade(task, world, snapshot, [])
        self.assertEqual([results[k]["result"] for k in ("any", "feature", "two", "same")],
                         ["pass", "fail", "fail", "pass"])
        subprocess.run(["git", "worktree", "add", "-q", "-b", "f", "../wt", "main"], cwd=app, env=env, check=True)
        results = paired.grade(task, world, snapshot, [])
        self.assertEqual([results[k]["result"] for k in ("feature", "two", "same")], ["pass", "pass", "fail"])


class ExportTests(unittest.TestCase):
    def test_an_interrupted_export_is_never_reused(self):
        tmp = Path(tempfile.mkdtemp(prefix="paired-export-"))
        self.addCleanup(shutil.rmtree, tmp, True)
        repo = tmp / "repo"
        (repo / ".claude-plugin").mkdir(parents=True)
        (repo / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": "ccl-skills"}))
        git(repo, "init", "-q", "-b", "main")
        git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "add", ".")
        git(repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "c")
        dest = tmp / "arms" / "base"
        with mock.patch.object(paired.tarfile.TarFile, "extractall", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                paired.export_arm(repo, "main", dest)
        self.assertFalse(dest.exists())
        self.assertEqual(paired.export_arm(repo, "main", dest), "ccl-skills")
        self.assertEqual(sorted(p.name for p in dest.parent.iterdir()), ["base"])


    def test_a_directory_symlink_is_part_of_the_manifest(self):
        tmp = Path(tempfile.mkdtemp(prefix="paired-manifest-"))
        self.addCleanup(shutil.rmtree, tmp, True)
        (tmp / "real").mkdir()
        (tmp / "real" / "a.md").write_text("a")
        (tmp / "link").symlink_to("real")
        before = paired.tree_manifest(tmp)
        self.assertIn(["L", "link", "real"], before)
        (tmp / "link").unlink()
        (tmp / "link").symlink_to("elsewhere")
        self.assertEqual(paired.manifest_changes(before, paired.tree_manifest(tmp)), ["link"])


class IsolationTests(unittest.TestCase):
    PLUGIN = "/out/arms/candidate"

    def parsed(self, **overrides):
        parsed = {"init": {"model": "m", "plugins": [
            {"name": "builtin-thing", "path": "builtin"}, {"name": "ccl-skills", "path": self.PLUGIN}],
            "mcp_servers": []}, "results": [{"subtype": "success", "is_error": False, "result": "ok"}],
            "hooks": ["SessionStart:startup"], "routing_injected": True, "tool_uses": [], "texts": ["ok"],
            "raw": "{\"type\": \"result\"}", "trailing_activity": 0, "invalid_lines": 0}
        parsed.update(overrides)
        return parsed

    def reasons(self, parsed, arm="candidate", run=None, token="CANARY-abc"):
        run = run or {"timed_out": False, "cleanup_confirmed": True}
        with mock.patch.object(paired.os.path, "realpath", side_effect=lambda p: p):
            return paired.assess(parsed, run, arm, "m", self.PLUGIN, "ccl-skills",
                                 ["/out/arms/base", self.PLUGIN], token)[0]

    def test_clean_plugin_and_off_runs_are_valid(self):
        self.assertEqual(self.reasons(self.parsed()), [])
        off = self.parsed(init={"model": "m", "plugins": [{"name": "builtin-thing", "path": "builtin"}],
                                "mcp_servers": []}, routing_injected=False)
        self.assertEqual(self.reasons(off, arm="off"), [])

    def test_each_isolation_breach_invalidates_the_sample(self):
        init = self.parsed()["init"]
        cases = {
            "timeout": ({}, {"timed_out": True, "cleanup_confirmed": True}, "candidate", "timeout"),
            "no result": ({"results": []}, None, "candidate", "no_result"),
            "last of two results failed": ({"results": self.parsed()["results"] + [
                {"subtype": "error_max_budget_usd", "is_error": True}]}, None, "candidate",
                "error_result:error_max_budget_usd"),
            "error result": ({"results": [{"subtype": "error_max_budget_usd", "is_error": True}]}, None,
                             "candidate", "error_result:error_max_budget_usd"),
            "no init": ({"init": None}, None, "candidate", "no_init_event"),
            "model": ({"init": dict(init, model="other")}, None, "candidate", "model_mismatch"),
            "plugin path": ({"init": dict(init, plugins=[{"name": "ccl-skills", "path": "/elsewhere"}])}, None,
                            "candidate", "plugin_identity_mismatch"),
            "plugin in off": ({"routing_injected": False}, None, "off", "plugin_loaded_in_off_arm"),
            "foreign plugin": ({"init": dict(init, plugins=init["plugins"] + [{"name": "x", "path": "/x"}])}, None,
                               "candidate", "foreign_plugins"),
            "mcp": ({"init": dict(init, mcp_servers=[{"name": "s"}])}, None, "candidate", "mcp_servers_present"),
            "routing missing": ({"routing_injected": False}, None, "candidate", "routing_injection_mismatch"),
            "routing in off": ({"init": dict(init, plugins=[]), "routing_injected": True}, None, "off",
                               "routing_injection_mismatch"),
            "canary in the reply": ({"raw": "ok CANARY-abc"}, None, "candidate", "instruction_file_canary_seen"),
            "canary only in a tool result": ({"raw": '{"type": "user", "content": "notes: CANARY-abc"}'}, None,
                                             "candidate", "instruction_file_canary_seen"),
            "activity after the last result": ({"trailing_activity": 2}, None, "candidate",
                                               "activity_after_last_result"),
            "a malformed line": ({"invalid_lines": 1}, None, "candidate", "malformed_stream"),
            "canary in a tool input": ({"raw": '{"type": "assistant", "input": {"command": "echo CANARY-abc"}}'},
                                       None, "candidate", "instruction_file_canary_seen"),
            "cleanup": ({}, {"timed_out": False, "cleanup_confirmed": False}, "candidate",
                        "process_cleanup_unconfirmed"),
        }
        for label, (overrides, run, arm, want) in cases.items():
            with self.subTest(case=label):
                self.assertIn(want, self.reasons(self.parsed(**overrides), arm=arm, run=run))

    def test_a_stop_hook_continuation_is_not_a_breach(self):
        self.assertEqual(self.reasons(self.parsed(results=self.parsed()["results"] * 2)), [])

    def test_outside_paths_flags_watched_roots_only(self):
        home, out = "/h", "/o"
        world, own, other = "/o/runs/t/base/1/world", "/o/arms/base", "/o/arms/candidate"
        uses = [{"name": "Read", "input": {"file_path": "/h/.claude/plugins/cache/x/SKILL.md"}},
                {"name": "Bash", "input": {"command": f"cat ~/notes.txt; ls {other}/skills; cat {world}/app/a"}},
                {"name": "Bash", "input": {"command": f"echo ~5 min ./x ../y; cat {own}/skills/s/SKILL.md /usr/bin/env"}},
                {"name": "Bash", "input": {"command": "cat $HOME/.gitconfig"}}]
        with mock.patch.object(paired.os.path, "realpath", side_effect=lambda p: p):
            flagged = paired.outside_paths(uses, [world, own], [home, "/repo", out], home)
        self.assertEqual(flagged, ["/h/.claude/plugins/cache/x/SKILL.md", "/h/notes.txt", f"{other}/skills",
                                   "/h/.gitconfig"])


class StreamTests(unittest.TestCase):
    def parse(self, events):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.jsonl"
            path.write_text("\n".join(e if isinstance(e, str) else json.dumps(e) for e in events), encoding="utf-8")
            return paired.parse_stream(path)

    def test_utilization_is_read_from_every_window(self):
        windows = {"type": "rate_limit_event", "rate_limit_info": {"unifiedWindows": {
            "five_hour": {"utilization": 0.46}, "seven_day": {"utilization": 0.02}}}}
        top_level = {"type": "rate_limit_event", "rate_limit_info": {"utilization": 0.5}}
        self.assertEqual(self.parse([windows])["max_utilization"], 0.46)
        self.assertEqual(self.parse([top_level])["max_utilization"], 0.5)
        self.assertEqual(self.parse([windows, top_level])["max_utilization"], 0.5)

    def test_untrusted_lines_are_counted_not_fatal(self):
        parsed = self.parse(["not json", json.dumps(["a list"]), json.dumps(
            {"type": "system", "subtype": "hook_response", "hook_name": "h",
             "output": {"additionalContext": "<ccl-skills-routing>x"}})])
        self.assertEqual(parsed["invalid_lines"], 2)
        self.assertTrue(parsed["routing_injected"])


class StatisticsTests(unittest.TestCase):
    def test_fisher_matches_hand_computed_values(self):
        cases = {(0, 5, 5, 0): 2 / 252, (2, 3, 0, 5): 20 / 45, (5, 0, 5, 0): 1.0, (0, 5, 4, 1): 10 / 210,
                 (0, 5, 3, 2): 20 / 120}
        for table, want in cases.items():
            with self.subTest(table=table):
                self.assertAlmostEqual(paired.fisher_two_sided(*table), want, places=9)

    def test_pre_registered_labels(self):
        self.assertEqual(paired.compare(0, 5, 4, 5)[0], "separated")
        self.assertEqual(paired.compare(0, 5, 3, 5)[0], "direction")
        self.assertEqual(paired.compare(2, 5, 0, 5)[0], "direction")
        self.assertEqual(paired.compare(1, 5, 0, 5)[0], "no observed difference")
        self.assertEqual(paired.compare(2, 2, 0, 5), ("insufficient", None))


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="paired-proc-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def child_gone(self, pid_file):
        pid = int(pid_file.read_text())
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            time.sleep(0.05)
        return False

    def run_leader(self, leader_sleeps, timeout):
        pid_file = self.tmp / "child.pid"
        source = ("import subprocess, sys, time\n"
                  "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                  f"open({str(pid_file)!r}, 'w').write(str(child.pid))\n"
                  f"time.sleep({leader_sleeps})\n")
        run = paired.run_agent([sys.executable, "-c", source], "", self.tmp, dict(os.environ), timeout,
                               self.tmp / "out.jsonl", self.tmp / "err.txt")
        return run, pid_file

    def test_timeout_kills_the_whole_process_group(self):
        run, pid_file = self.run_leader(60, 1)
        self.assertTrue(run["timed_out"])
        self.assertTrue(run["cleanup_confirmed"])
        self.assertTrue(self.child_gone(pid_file))

    def test_no_run_starts_once_shutdown_or_the_guard_has_begun(self):
        for flag in ("interrupted", "stop"):
            with self.subTest(flag=flag):
                ctx = {"spawn_lock": threading.Lock(), "interrupted": threading.Event(), "stop": threading.Event(),
                       "live": set()}
                ctx[flag].set()
                marker = self.tmp / f"started-{flag}"
                run = paired.run_agent([sys.executable, "-c", f"open({str(marker)!r}, 'w').write('x')"], "", self.tmp,
                                       dict(os.environ), 5, self.tmp / "out.jsonl", self.tmp / "err.txt", ctx)
                self.assertIsNone(run)
                self.assertFalse(marker.exists())

    def test_background_jobs_left_by_a_finished_run_are_reaped(self):
        run, pid_file = self.run_leader(0, 30)
        self.assertFalse(run["timed_out"])
        self.assertTrue(run["cleanup_confirmed"])
        self.assertTrue(self.child_gone(pid_file))


class BatchTests(unittest.TestCase):
    TASK = "branch-cleanup-keeps-protected"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="paired-batch-"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = self.tmp / "plugin-repo"
        (self.repo / ".claude-plugin").mkdir(parents=True)
        (self.repo / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": "ccl-skills"}))
        (self.repo / "skill.md").write_text("base\n")
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "add", ".")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-m", "base")
        git(self.repo, "tag", "base")
        (self.repo / "skill.md").write_text("candidate\n")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "-am", "cand")
        self.claude = self.tmp / "fake-claude"
        self.claude.write_text(FAKE_CLAUDE)
        self.claude.chmod(0o755)
        self.log = self.tmp / "fake.log"
        self.out = self.tmp / "out"
        good = committed_task(self.TASK)["oracle"]["good"]
        self.env = {"FAKE_LOG": str(self.log), "FAKE_COMMANDS": json.dumps(good),
                    "FAKE_VERSION_LOG": str(self.tmp / "version.log"),
                    "CLAUDE_EFFORT": "max", "CLAUDE_CODE_MESSAGING_TOKEN": "parent-secret",
                    "GIT_DIR": str(self.tmp / "not-a-repo"), "GIT_INDEX_FILE": str(self.tmp / "index")}

    def main(self, *extra, env=None, samples="1"):
        argv = ["--out", str(self.out), "--base", "base", "--candidate", "main", "--repo", str(self.repo),
                "--claude", str(self.claude), "--tasks", self.TASK, "--samples", samples, "--jobs", "2",
                "--model", "m", *extra]
        with mock.patch.dict(os.environ, dict(self.env, **(env or {}))), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = paired.main(argv)
        return code, err.getvalue()

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def records(self):
        return paired.load_records(self.out, json.loads((self.out / "plan.json").read_text()))

    def regrade(self, *extra):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = paired.main(["--out", str(self.out), "--regrade", "--repo", str(self.repo), *extra])
        return code, err.getvalue()

    def test_batch_isolates_each_run_and_grades_the_world(self):
        code, err = self.main()
        self.assertEqual(code, 0, err)
        records = self.records()
        self.assertEqual(len(records), 3)
        for record in records:
            self.assertTrue(record["valid"], record)
            self.assertEqual({v["result"] for v in record["checks"].values()}, {"pass"})
        samples = [c for c in self.calls() if "project" not in c["argv"]]
        calibration = [c for c in self.calls() if "project" in c["argv"]]
        self.assertEqual((len(samples), len(calibration)), (3, 1))
        prompt = committed_task(self.TASK)["prompt"]
        for call in samples:
            argv = call["argv"]
            self.assertEqual(call["prompt"], prompt)
            self.assertEqual(argv[argv.index("--setting-sources") + 1], "")
            for flag in ("--strict-mcp-config", "--no-session-persistence", "--verbose"):
                self.assertIn(flag, argv)
            self.assertEqual(argv[argv.index("--permission-mode") + 1], "bypassPermissions")
            self.assertEqual(argv[argv.index("--disallowedTools") + 1], paired.DISALLOWED_TOOLS)
            self.assertEqual(set(call["env"]), {"CLAUDE_CODE_DISABLE_CLAUDE_MDS", "CLAUDE_CODE_DISABLE_AUTO_MEMORY",
                                                "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_TERMINAL_PROMPT",
                                                "GIT_CEILING_DIRECTORIES", "PYTHONDONTWRITEBYTECODE"})
            sample_dir = Path(call["cwd"]).parents[1]
            self.assertEqual(call["env"]["GIT_CEILING_DIRECTORIES"], os.path.realpath(sample_dir))
            arm = Path(call["cwd"]).parts[-4]
            if arm == "off":
                self.assertNotIn("--plugin-dir", argv)
            else:  # a private copy per run, removed afterwards because the run left it unchanged
                self.assertEqual(Path(argv[argv.index("--plugin-dir") + 1]).resolve(), (sample_dir / "plugin").resolve())
                self.assertFalse((sample_dir / "plugin").exists())
        self.assertEqual({line for line in (self.tmp / "version.log").read_text().splitlines()}, {"[]"})
        self.assertNotIn("CLAUDE_CODE_DISABLE_CLAUDE_MDS", calibration[0]["env"])
        self.assertTrue(json.loads((self.out / "canary-calibration.json").read_text())["fired"])
        self.assertTrue(json.loads((self.out / "integrity.json").read_text())["unchanged"])
        self.assertEqual((self.out / "arms" / "base" / "skill.md").read_text(), "base\n")
        self.assertEqual((self.out / "arms" / "candidate" / "skill.md").read_text(), "candidate\n")
        report = (self.out / "report.md").read_text()
        self.assertIn("| release_branch_kept | primary | 1/1 | 1/1 | 1/1 |", report)
        self.assertIn("calibration: fired", report)

    def test_resume_skips_recorded_samples_and_rejects_a_changed_plan(self):
        self.assertEqual(self.main()[0], 0)
        before = len(self.calls())
        self.assertEqual(self.main()[0], 0)
        self.assertEqual(len(self.calls()), before)
        code, err = self.main(samples="2")
        self.assertEqual(code, 2)
        self.assertIn("plan differs", err)
        self.assertEqual(len(self.calls()), before)

    def test_refusals_start_no_model_run(self):
        sibling = self.tmp / "sibling\nworktree"  # porcelain output would quote this path
        git(self.repo, "worktree", "add", "-q", "-b", "side", str(sibling), "main")
        cases = {
            "too many runs": (["--max-runs", "2"], None, "exceed --max-runs"),
            "out inside the repository": ([], self.repo / "eval-out", "outside every checkout"),
            "out inside another worktree": ([], sibling / "eval-out", "outside every checkout"),
        }
        for label, (extra, out, message) in cases.items():
            with self.subTest(case=label):
                if out is not None:
                    self.out = out
                code, err = self.main(*extra)
                self.assertEqual(code, 2)
                self.assertIn(message, err)
                self.assertEqual(self.calls(), [])

    def test_a_second_invocation_on_the_same_out_is_refused(self):
        self.out.mkdir(mode=0o700)
        held = paired.lock_output(self.out)
        try:
            code, err = self.main()
        finally:
            held.close()
        self.assertEqual(code, 2)
        self.assertIn("another invocation", err)
        self.assertEqual(self.calls(), [])

    def test_exports_without_a_frozen_plan_are_refused_not_reused(self):
        stale = self.out / "arms" / "base"
        stale.mkdir(parents=True)
        (stale / ".claude-plugin").mkdir()
        (stale / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": "ccl-skills"}))
        (stale / "skill.md").write_text("from another ref\n")
        code, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("holds no plan from this tool", err)
        self.assertEqual((stale / "skill.md").read_text(), "from another ref\n")
        self.assertEqual(self.calls(), [])

    def test_an_unreadable_plan_is_refused(self):
        self.out.mkdir(mode=0o700)
        (self.out / "plan.json").write_text("{")
        code, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("not valid JSON", err)
        self.assertEqual(self.calls(), [])

    def test_an_output_root_with_foreign_files_is_left_alone(self):
        (self.out / "arms").mkdir(parents=True)
        (self.out / "arms" / "notes.txt").write_text("someone else's\n")
        code, err = self.main()
        self.assertEqual(code, 2)
        self.assertIn("holds no plan from this tool", err)
        self.assertEqual((self.out / "arms" / "notes.txt").read_text(), "someone else's\n")
        self.assertEqual(self.calls(), [])

    def test_a_truncated_stream_is_not_a_finished_run(self):
        code, err = self.main(env={"FAKE_MODE": "truncated_after_result"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            self.assertIn("malformed_stream", record["invalid_reasons"])

    def test_an_integrity_inspection_failure_is_recorded_not_raised(self):
        def failing_sample(ctx, task, arm, index):
            raise RuntimeError("worker failed")
        def unreadable(before, after):
            raise PermissionError("export unreadable")
        with mock.patch.object(paired, "run_sample", failing_sample), \
                mock.patch.object(paired, "manifest_changes", unreadable), self.assertRaisesRegex(RuntimeError, "worker"):
            self.main()
        integrity = json.loads((self.out / "integrity.json").read_text())
        self.assertIsNone(integrity["unchanged"])
        self.assertIn("PermissionError", integrity["error"])
        self.assertIn("unchanged after the batch: UNKNOWN", (self.out / "report.md").read_text())

    def test_a_report_failure_never_replaces_the_batch_failure(self):
        def failing_sample(ctx, task, arm, index):
            raise RuntimeError("worker failed")
        def broken_report(out, plan, records):
            raise OSError("disk full")
        with mock.patch.object(paired, "run_sample", failing_sample), \
                mock.patch.object(paired, "write_report", broken_report), self.assertRaisesRegex(RuntimeError, "worker"):
            self.main()

    def test_integrity_is_recorded_when_a_batch_fails(self):
        def failing_sample(ctx, task, arm, index):
            (ctx["arm_dirs"]["base"] / "late.md").write_text("written before the failure\n")
            raise RuntimeError("worker failed")
        with mock.patch.object(paired, "run_sample", failing_sample), self.assertRaises(RuntimeError):
            self.main()
        self.assertEqual(json.loads((self.out / "integrity.json").read_text())["changed"], {"base": ["late.md"]})

    def test_rate_limit_guard_stops_and_the_rerun_resumes(self):
        code, err = self.main("--jobs", "1", env={"FAKE_UTIL": "0.95"})
        self.assertEqual(code, 3, err)
        self.assertEqual(len(self.records()), 1)
        code, err = self.main("--jobs", "1")
        self.assertEqual(code, 0, err)
        self.assertEqual(len(self.records()), 3)

    def test_a_stop_hook_continuation_counts_as_one_run(self):
        code, err = self.main(env={"FAKE_MODE": "two_results"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            self.assertTrue(record["valid"], record)
            self.assertEqual((record["continuations"], record["cost_usd"], record["turns"]), (1, 0.02, 3))

    def test_activity_after_the_last_result_is_an_unfinished_run(self):
        code, err = self.main(env={"FAKE_MODE": "continue_then_crash"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            self.assertIn("activity_after_last_result", record["invalid_reasons"])

    def test_a_canary_seen_only_in_a_tool_result_invalidates_the_run(self):
        code, err = self.main(env={"FAKE_MODE": "read_canary"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            self.assertIn("instruction_file_canary_seen", record["invalid_reasons"])

    def test_regrade_rebuilds_records_from_saved_worlds(self):
        self.assertEqual(self.main()[0], 0)
        sample = self.out / "runs" / self.TASK / "off" / "1"
        world_app = sample / "world" / "app"
        subprocess.run(["git", "branch", "feat-y", "main"], cwd=world_app, check=True, capture_output=True,
                       env=paired.clean_env(sample / "gitconfig", sample))
        with mock.patch.dict(os.environ, {"FAKE_LOG": str(self.log)}):
            code, err = self.regrade()
        self.assertEqual(code, 0, err)
        record = json.loads((sample / "record.json").read_text())
        self.assertEqual(record["checks"]["merged_feature_deleted"]["result"], "fail")
        self.assertEqual(record["graded_by"], paired.tool_sha256())
        self.assertNotIn("legacy_inputs", record)
        self.assertEqual(len(self.calls()), 4)  # three samples and the calibration, nothing rerun
        tasks = self.tmp / "tasks"
        shutil.copytree(paired.DEFAULT_TASKS, tasks)
        changed = json.loads((tasks / f"{self.TASK}.json").read_text())
        changed["prompt"] += " "
        (tasks / f"{self.TASK}.json").write_text(json.dumps(changed, ensure_ascii=False))
        code, err = self.regrade("--tasks-dir", str(tasks))
        self.assertEqual(code, 2)
        self.assertIn("differs from the one the batch ran", err)

    def test_regrade_reads_the_token_and_snapshot_the_runner_recorded(self):
        code, err = self.main(env={"FAKE_MODE": "leak_canary"})
        self.assertEqual(code, 0, err)
        sample = self.out / "runs" / self.TASK / "off" / "1"
        (sample / "world" / "CLAUDE.md").write_text(paired.CANARY_TEXT.format(token="CANARY-000000000000"))
        snapshot = json.loads((sample / "snapshot.json").read_text())
        snapshot["refs"]["app"]["refs/heads/main"] = "0" * 40
        (sample / "snapshot.json").write_text(json.dumps(snapshot))
        code, err = self.regrade()
        self.assertEqual(code, 0, err)
        record = json.loads((sample / "record.json").read_text())
        self.assertIn("instruction_file_canary_seen", record["invalid_reasons"])
        self.assertNotEqual(record["snapshot"]["refs"]["app"]["refs/heads/main"], "0" * 40)

    def test_regrade_refuses_a_record_without_runner_recorded_inputs(self):
        self.assertEqual(self.main()[0], 0)
        sample = self.out / "runs" / self.TASK / "base" / "1"
        original = (sample / "record.json").read_text()
        cases = {
            "token missing": lambda r: r.pop("canary"),
            "inputs taken from the world by an older regrade": lambda r: r.__setitem__("legacy_inputs", ["canary"]),
        }
        for label, mutate in cases.items():
            with self.subTest(case=label):
                record = json.loads(original)
                mutate(record)
                (sample / "record.json").write_text(json.dumps(record))
                code, err = self.regrade()
                self.assertEqual(code, 2)
                self.assertIn("no runner-recorded canary token", err)

    def test_records_outside_the_plan_inventory_are_refused(self):
        self.assertEqual(self.main()[0], 0)
        source = self.out / "runs" / self.TASK / "off" / "1" / "record.json"
        copy = self.out / "runs" / self.TASK / "off" / "2" / "record.json"
        copy.parent.mkdir()
        shutil.copy(source, copy)
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()) as err:
            code = paired.main(["--out", str(self.out), "--report-only"])
        self.assertEqual(code, 2)
        self.assertIn("does not belong to this plan", err.getvalue())

    def test_a_run_that_edits_its_plugin_copy_is_invalid_and_the_export_stays_frozen(self):
        code, err = self.main(env={"FAKE_MODE": "touch_plugin"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            if record["arm"] == "off":
                self.assertTrue(record["valid"], record)
                continue
            self.assertIn("plugin_export_changed", record["invalid_reasons"])
            self.assertEqual(record["run"]["export_changes"], ["injected.md"])
            self.assertTrue(Path(record["plugin_dir"]).is_dir())  # kept for inspection
        self.assertTrue(json.loads((self.out / "integrity.json").read_text())["unchanged"])

    def test_integrity_names_every_path_changed_in_a_frozen_export(self):
        code, err = self.main(env={"FAKE_MODE": "touch_frozen"})
        self.assertEqual(code, 0, err)
        integrity = json.loads((self.out / "integrity.json").read_text())
        self.assertFalse(integrity["unchanged"])
        self.assertEqual(integrity["changed"], {"base": ["a.md", "b.md", "c.md"], "candidate": ["a.md", "b.md", "c.md"]})
        self.assertIn("unchanged after the batch: NO (base: a.md, b.md, c.md; candidate: a.md, b.md, c.md)",
                      (self.out / "report.md").read_text())

    def test_a_guard_trip_on_the_last_samples_is_not_a_stop(self):
        code, err = self.main("--jobs", "3", env={"FAKE_UTIL": "0.95"})
        self.assertEqual(code, 0, err)
        self.assertEqual(len(self.records()), 3)

    def test_a_loaded_instruction_file_invalidates_every_sample(self):
        code, err = self.main(env={"FAKE_MODE": "leak_canary"})
        self.assertEqual(code, 0, err)
        records = self.records()
        self.assertTrue(records)
        for record in records:
            self.assertFalse(record["valid"])
            self.assertIn("instruction_file_canary_seen", record["invalid_reasons"])

    def test_a_calibration_that_does_not_fire_runs_no_sample(self):
        code, err = self.main(env={"FAKE_MODE": "ignore_instruction_files"})
        self.assertEqual(code, 2)
        self.assertIn("did not fire", err)
        self.assertFalse(json.loads((self.out / "canary-calibration.json").read_text())["fired"])
        self.assertEqual([c for c in self.calls() if "project" not in c["argv"]], [])

    def test_a_plugin_loaded_from_another_path_invalidates_plugin_arms(self):
        code, err = self.main(env={"FAKE_MODE": "wrong_plugin_path"})
        self.assertEqual(code, 0, err)
        for record in self.records():
            if record["arm"] == "off":
                self.assertTrue(record["valid"], record)
            else:
                self.assertIn("plugin_identity_mismatch", record["invalid_reasons"])

if __name__ == "__main__":
    unittest.main()
