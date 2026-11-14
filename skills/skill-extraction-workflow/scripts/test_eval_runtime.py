#!/usr/bin/env python3
"""Offline regression cases for evaluator deadlines and terminal evidence."""
import hashlib
import importlib.util
import inspect
import io
import json
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("behavior_eval", HERE / "skill-behavior-eval.py")
behavior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(behavior)


def success(**overrides):
    return {"type": "result", "subtype": "success", "is_error": False,
            "result": "complete", **overrides}


AGENT_TOOLS = ["Read", "Grep", "Glob", "Skill"]


def init(tools):
    """The CLI's init event: the tools the run actually offered the model."""
    return json.dumps({"type": "system", "subtype": "init", "tools": tools}) + "\n"


def running(pid):
    """True while pid is a live process. A zombie counts as terminated: an
    orphan may wait for a reaper that a minimal container never runs. Linux
    reports the state in /proc; where that is absent (macOS, BSD) `ps` does.
    When neither can tell, the process counts as running."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as stat:
            return stat.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        pass
    try:
        done = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return True
    state = done.stdout.strip()
    if done.returncode == 0 and state:
        return not state.startswith("Z")
    try:
        os.kill(pid, 0)  # ps printed nothing: gone since the first probe, or ps cannot tell
    except ProcessLookupError:
        return False
    return True


class ProcessProbeTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "posix", "zombies require POSIX")
    def test_exited_but_unreaped_child_counts_as_stopped(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        try:
            deadline = time.monotonic() + 10.0
            while running(child.pid) and time.monotonic() < deadline:
                time.sleep(0.05)
            # Not reaped yet: the pid still answers a signal probe, so only the state says it stopped.
            os.kill(child.pid, 0)
            self.assertFalse(running(child.pid), "a zombie was reported as running")
        finally:
            child.wait()

    def test_missing_process_counts_as_stopped(self):
        with mock.patch.object(os, "kill", side_effect=ProcessLookupError):
            self.assertFalse(running(12345))

    @unittest.skipUnless(os.name == "posix", "the probe is POSIX-only")
    def test_live_child_counts_as_running_with_and_without_proc(self):
        # Another process, not this one: a probe that only recognises its own pid must fail here.
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        try:
            self.assertTrue(running(child.pid))
            with self.without_proc():
                self.assertTrue(running(child.pid))
        finally:
            child.kill()
            child.wait()

    def without_proc(self):
        """Makes /proc unreadable for the block, as on macOS and the BSDs, so the
        ps branch is exercised on Linux too."""
        real_open = open

        def fake_open(path, *args, **kwargs):
            if str(path).startswith("/proc/"):
                raise FileNotFoundError(path)
            return real_open(path, *args, **kwargs)
        return mock.patch("builtins.open", fake_open)

    @unittest.skipUnless(os.name == "posix", "zombies require POSIX")
    def test_without_proc_ps_tells_a_zombie_from_a_live_process(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        try:
            with self.without_proc():
                deadline = time.monotonic() + 10.0
                while running(child.pid) and time.monotonic() < deadline:
                    time.sleep(0.05)
                os.kill(child.pid, 0)  # still a zombie: the pid answers a signal probe
                self.assertFalse(running(child.pid), "ps did not report the zombie as stopped")
        finally:
            child.wait()

    def test_live_process_counts_as_running_when_nothing_can_tell(self):
        silent = subprocess.CompletedProcess(["ps"], 1, stdout="", stderr="")
        for label, ps in (("ps missing", mock.Mock(side_effect=FileNotFoundError("ps"))),
                          ("ps timed out", mock.Mock(side_effect=subprocess.TimeoutExpired("ps", 5))),
                          ("ps failed without output", mock.Mock(return_value=silent))):
            with self.subTest(label), self.without_proc(), mock.patch.object(subprocess, "run", ps):
                self.assertTrue(running(os.getpid()))
                ps.assert_called_once()


class BehaviorRuntimeTests(unittest.TestCase):
    def fake_process(self, communicate):
        process = mock.Mock(pid=12345, returncode=0)
        process.stdin = io.StringIO()
        process.stdout = io.StringIO()
        process.communicate.side_effect = communicate
        return process

    def invoke(self, source, prompt="x", timeout=0.15):
        started = time.monotonic()
        result = behavior._headless_claude([sys.executable, "-c", source], prompt, timeout)
        return result, time.monotonic() - started

    def test_complete_stream_and_teardown_exit(self):
        for code in (0, 7):
            with self.subTest(code=code):
                result, _ = self.invoke(f"import sys; print({json.dumps(success())!r}); sys.exit({code})", timeout=2)
                self.assertEqual(result[:2], ("complete", None))

    def test_deadline_covers_all_io_and_process_wait(self):
        cases = {
            "stdin_write": ("import time; time.sleep(1.5)", "x" * 1_000_000),
            "stdout_closed_process_live": ("import os,time; os.close(1); time.sleep(1.5)", "x"),
            "stdout_open": ("import time; time.sleep(1.5)", "x"),
            "terminal_before_process_exit": (f"import os,time; print({json.dumps(success())!r}, flush=True); os.close(1); time.sleep(1.5)", "x"),
        }
        for label, (source, prompt) in cases.items():
            with self.subTest(boundary=label):
                result, elapsed = self.invoke(source, prompt)
                self.assertEqual(result[1], "timeout_0.15s")
                self.assertLess(elapsed, 1.2)

    @unittest.skipUnless(os.name == "posix", "process groups require POSIX")
    def test_timeout_stops_descendant_with_inherited_stdout(self):
        # The timeout leaves room for two interpreter start-ups on a loaded host
        # (about 1 s at load 30, longer during spikes); a 0.5 s budget killed the
        # group before the descendant existed and failed the precondition.
        # The parent waits for the descendant to report its pid and then exits,
        # so the group leader is gone while the descendant still holds the
        # inherited stdout — the case the group kill exists for. The check polls
        # that pid instead of sleeping past a fixed marker deadline.
        with tempfile.TemporaryDirectory() as temp:
            marker = Path(temp) / "descendant-finished"
            ready = Path(temp) / "descendant-ready"
            leader_gone = Path(temp) / "leader-gone-at"
            # The descendant itself watches its parent (the group leader) and
            # records, on the shared monotonic clock, when the leader actually
            # stopped running; a zombie counts as stopped.
            # It runs this module's own `running`, so the two never drift apart.
            descendant = (
                "import os, subprocess, time; from pathlib import Path\n"
                f"{inspect.getsource(running)}\n"
                "leader = os.getppid()\n"
                f"Path({str(ready)!r}).write_text(str(os.getpid()))\n"
                "while running(leader):\n"
                "    time.sleep(0.01)\n"
                f"Path({str(leader_gone)!r}).write_text(repr(time.monotonic()))\n"
                "time.sleep(60)\n"
                f"Path({str(marker)!r}).touch()\n")
            source = (f"import subprocess, sys, time; from pathlib import Path; "
                      f"subprocess.Popen([sys.executable, '-c', {descendant!r}]); "
                      f"[time.sleep(0.01) for _ in iter(lambda: Path({str(ready)!r}).exists(), True)]")
            try:
                started = time.monotonic()
                result, elapsed = self.invoke(source, timeout=6.0)
                self.assertEqual(result[1], "timeout_6.0s")
                self.assertLess(elapsed, 7.5)
                self.assertTrue(ready.exists(), "fixture never reached the descendant path")
                # The case is only exercised when the leader was already gone
                # well before the timeout cleanup ran.
                self.assertTrue(leader_gone.exists(), "group leader never exited")
                self.assertLess(float(leader_gone.read_text()), started + 6.0 - 0.5,
                                "group leader exited too close to the timeout to exercise the exited-leader case")
                pid = int(ready.read_text())
                deadline = time.monotonic() + 3.0
                alive = True
                while alive and time.monotonic() < deadline:
                    alive = running(pid)
                    if alive:
                        time.sleep(0.05)
                self.assertFalse(alive, "descendant continued after timeout")
                self.assertFalse(marker.exists(), "descendant continued after timeout")
            finally:
                # A failed assertion must not leave the fixture's descendant
                # running for the rest of its 60 s sleep; this runs while the
                # temporary directory, and so the pid file, still exists.
                try:
                    os.kill(int(ready.read_text()), signal.SIGKILL)
                except (FileNotFoundError, ValueError, ProcessLookupError):
                    pass

    @unittest.skipUnless(os.name == "posix", "terminal process groups require POSIX")
    def test_cli_signals_stop_detached_child(self):
        for cancel in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=cancel), tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                ready, marker, calls = folder / "ready", folder / "late-work", folder / "calls"
                stub = folder / "claude"
                stub.write_text(f"#!{sys.executable}\nimport os,sys,time; from pathlib import Path\n"
                                "sys.stdin.read()\n"
                                f"with Path({str(calls)!r}).open('a') as log: log.write('started\\n')\n"
                                f"Path({str(ready)!r}).write_text(str(os.getpid()))\n"
                                f"time.sleep(1.4); Path({str(marker)!r}).touch()\n")
                stub.chmod(0o700)
                fixtures, output = folder / "fixtures.jsonl", folder / "output"
                fixtures.write_text(json.dumps({"id": "synthetic", "prompt": "x"}) + "\n")
                process = subprocess.Popen(
                    [sys.executable, str(HERE / "skill-behavior-eval.py"), "--fixtures", str(fixtures),
                     "--out", str(output), "--samples", "2", "--timeout", "10", "--no-judge"],
                    env={**os.environ, "HOME": temp, "PATH": temp + os.pathsep + os.environ["PATH"]},
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
                child_pid = None
                try:
                    # Only a precondition wait: it ends as soon as the stub reports,
                    # so a generous bound costs nothing on a quiet host and keeps a
                    # loaded one from failing before the behaviour is exercised.
                    deadline = time.monotonic() + 15
                    while (not ready.exists() or not ready.read_text()) and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue(ready.exists(), "fixture never reached the child")
                    child_pid = int(ready.read_text())
                    os.killpg(process.pid, cancel)
                    _, stderr = process.communicate(timeout=3)
                    self.assertNotEqual(process.returncode, 0)
                    self.assertFalse(marker.exists(), "child performed work after cancellation")
                    with self.assertRaises(ProcessLookupError, msg="child survived evaluator cancellation"):
                        os.kill(child_pid, 0)
                    self.assertEqual(calls.read_text().splitlines(), ["started"])
                    self.assertEqual(list(output.glob("*.s*.txt")), [])
                    if cancel == signal.SIGINT:
                        self.assertIn("KeyboardInterrupt", stderr)
                    else:
                        self.assertEqual(process.returncode, 128 + signal.SIGTERM)
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=2)
                    if child_pid is not None:
                        try:
                            os.kill(child_pid, 0)
                            os.killpg(child_pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    process.stdout.close()
                    process.stderr.close()

    @unittest.skipUnless(os.name == "posix", "process group refusal requires POSIX")
    def test_cancellation_reports_cleanup_refusal_and_reraises(self):
        for interrupted in (KeyboardInterrupt(), SystemExit(128 + signal.SIGTERM),
                            RuntimeError("custom signal handler"), OSError("pipe failure"),
                            BaseException("custom cancellation")):
            with self.subTest(exception=type(interrupted).__name__):
                process = self.fake_process([interrupted, ("", None)])
                with mock.patch.object(behavior.subprocess, "Popen", return_value=process), \
                        mock.patch.object(behavior.os, "killpg", side_effect=PermissionError()) as killpg, \
                        mock.patch.object(sys, "stderr", io.StringIO()) as stderr:
                    with self.assertRaises(type(interrupted)) as raised:
                        behavior._headless_claude(["synthetic"], "x", 1)
                self.assertIs(raised.exception, interrupted)
                self.assertIn("cleanup_unconfirmed:group_kill_permission_denied", stderr.getvalue())
                killpg.assert_called_once_with(process.pid, signal.SIGKILL)
                self.assertEqual(process.communicate.call_args_list,
                                 [mock.call(input="x", timeout=1), mock.call(timeout=1)])

    @unittest.skipUnless(os.name == "posix", "process group cleanup requires POSIX")
    def test_cleanup_io_errors_preserve_original_failure_and_remain_bounded(self):
        for stopped in (subprocess.TimeoutExpired(["synthetic"], 1), OSError("original pipe failure")):
            with self.subTest(exception=type(stopped).__name__):
                process = self.fake_process([stopped, OSError("drain failure")])
                process.wait.side_effect = OSError("reap failure")
                with mock.patch.object(behavior.subprocess, "Popen", return_value=process), \
                        mock.patch.object(behavior.os, "killpg") as killpg, \
                        mock.patch.object(sys, "stderr", io.StringIO()) as stderr:
                    if isinstance(stopped, subprocess.TimeoutExpired):
                        result = behavior._headless_claude(["synthetic"], "x", 1)
                        self.assertEqual(result, (None, "timeout_1s;cleanup_unconfirmed:stdio_error,wait_error", None, []))
                    else:
                        with self.assertRaises(OSError) as raised:
                            behavior._headless_claude(["synthetic"], "x", 1)
                        self.assertIs(raised.exception, stopped)
                        self.assertIn("cleanup_unconfirmed:stdio_error,wait_error", stderr.getvalue())
                killpg.assert_called_once_with(process.pid, signal.SIGKILL)
                process.kill.assert_called_once_with()
                process.wait.assert_called_once_with(timeout=1)
                self.assertEqual(process.communicate.call_args_list,
                                 [mock.call(input="x", timeout=1), mock.call(timeout=1)])
                self.assertTrue(process.stdin.closed)
                self.assertTrue(process.stdout.closed)

    def test_cli_sigterm_handler_is_scoped_and_preserves_existing_handlers(self):
        script = str(HERE / "skill-behavior-eval.py")
        with mock.patch.object(signal, "signal") as install:
            runpy.run_path(script, run_name="imported_fixture")
        install.assert_not_called()
        for previous in (signal.SIG_DFL, signal.SIG_IGN, lambda *_: None):
            with self.subTest(previous=previous), \
                    mock.patch.object(signal, "getsignal", return_value=previous), \
                    mock.patch.object(signal, "signal") as install, \
                    mock.patch.object(sys, "argv", [script, "--help"]), \
                    mock.patch.object(sys, "stdout", io.StringIO()):
                with self.assertRaises(SystemExit) as ended:
                    runpy.run_path(script, run_name="__main__")
                self.assertEqual(ended.exception.code, 0)
            if previous == signal.SIG_DFL:
                self.assertEqual(install.call_count, 2)
                self.assertEqual(install.call_args, mock.call(signal.SIGTERM, previous))
                with self.assertRaises(SystemExit) as ended:
                    install.call_args_list[0].args[1](signal.SIGTERM, None)
                self.assertEqual(ended.exception.code, 128 + signal.SIGTERM)
            else:
                install.assert_not_called()

    def test_invalid_terminal_never_becomes_a_sample(self):
        streams = {
            "missing": [{"type": "assistant", "message": {"content": [{"type": "text", "text": "partial"}]}}],
            "failed": [success(subtype="error_max_turns")],
            "error_flag": [success(is_error=True)],
            "duplicate": [success(), success()],
            "permission_denial": [success(permission_denials=[{"tool": "Read"}])],
            "api_error": [success(api_error_status=429)],
            "malformed_result": [success(result={"invalid": "text"})],
            "empty_result": [success(result="")],
        }
        for label, events in streams.items():
            with self.subTest(stream=label):
                stream = "\n".join(json.dumps(event) for event in events)
                result, _ = self.invoke(f"print({stream!r})", timeout=2)
                self.assertIsNone(result[0])
                self.assertIsNotNone(result[1])

    def test_timeout_cleanup_failures_stay_explicit_and_bounded(self):
        timeout = lambda: subprocess.TimeoutExpired(["synthetic"], 0.15)
        complete = (json.dumps(success()), None)
        cases = (
            ("clean", "posix", None, None, None, False, ""),
            ("already_gone", "posix", ProcessLookupError(), None, None, False, ""),
            ("group_denied", "posix", PermissionError(), None, None, False,
             "group_kill_permission_denied"),
            ("direct_only", "nt", None, None, None, False,
             "descendant_cleanup_unsupported"),
            ("direct_gone", "nt", None, ProcessLookupError(), None, False,
             "descendant_cleanup_unsupported"),
            ("direct_denied", "nt", None, PermissionError(), None, False,
             "descendant_cleanup_unsupported,process_kill_permission_denied"),
            ("pipe_still_open", "posix", None, None, None, True, "stdio_timeout"),
            ("fallback_denied", "posix", None, PermissionError(), None, True,
             "stdio_timeout,process_kill_permission_denied"),
            ("wait_timeout", "posix", None, None, timeout(), True,
             "stdio_timeout,wait_timeout"),
        )
        for label, platform, group_error, kill_error, wait_error, drain_timeout, detail in cases:
            with self.subTest(boundary=label):
                process = self.fake_process([timeout(), timeout() if drain_timeout else complete])
                process.kill.side_effect = kill_error
                process.wait.side_effect = wait_error
                with mock.patch.object(behavior.subprocess, "Popen", return_value=process), \
                        mock.patch.object(behavior.os, "name", platform), \
                        mock.patch.object(behavior.os, "killpg", side_effect=group_error, create=True):
                    result = behavior._headless_claude(["synthetic"], "x", 0.15)
                error = "timeout_0.15s" + (";cleanup_unconfirmed:" + detail if detail else "")
                self.assertEqual(result, (None, error, None, []))
                self.assertEqual(process.communicate.call_args_list,
                                 [mock.call(input="x", timeout=0.15), mock.call(timeout=1)])
                if drain_timeout:
                    process.wait.assert_called_once_with(timeout=1)
                else:
                    process.wait.assert_not_called()
                self.assertTrue(process.stdin.closed)
                self.assertTrue(process.stdout.closed)

    @unittest.skipUnless(os.name == "posix", "group-kill integration requires POSIX")
    def test_cleanup_uncertainty_stops_new_samples_but_preserves_results(self):
        for unconfirmed in (False, True):
            with self.subTest(cleanup_unconfirmed=unconfirmed), tempfile.TemporaryDirectory() as temp:
                timeout = subprocess.TimeoutExpired(["synthetic"], 1)
                stream = (init(AGENT_TOOLS) + json.dumps(success()), None)
                failed = self.fake_process([timeout, timeout if unconfirmed else stream])
                failed.wait.side_effect = timeout if unconfirmed else None
                processes = [self.fake_process([stream]), failed, self.fake_process([stream])]
                argv = ["eval", "--samples", "3", "--timeout", "1", "--out", temp]
                with mock.patch.object(sys, "argv", argv), \
                        mock.patch.object(behavior, "load_fixtures", return_value=[{"id": "synthetic", "prompt": "x"}]), \
                        mock.patch.object(behavior.subprocess, "Popen", side_effect=processes) as spawn, \
                        mock.patch.object(behavior.os, "killpg", side_effect=PermissionError() if unconfirmed else None), \
                        mock.patch.object(sys, "stdout", io.StringIO()) as output:
                    if unconfirmed:
                        with self.assertRaises(SystemExit) as ended:
                            behavior.main()
                        self.assertEqual(ended.exception.code, 1)
                    else:
                        behavior.main()
                rows = [json.loads(line) for line in (Path(temp) / "run-log.jsonl").read_text().splitlines()]
                self.assertEqual(len(rows), 2 if unconfirmed else 3)
                self.assertEqual(spawn.call_count, len(rows))
                expected = "timeout_1s" + (";cleanup_unconfirmed:group_kill_permission_denied,stdio_timeout,wait_timeout"
                                            if unconfirmed else "")
                self.assertEqual(rows[1]["error"], expected)
                self.assertNotIn("error", rows[0])
                self.assertIn("complete", (Path(temp) / "synthetic.current.s1.txt").read_text())
                self.assertFalse((Path(temp) / "synthetic.current.s2.txt").exists())
                self.assertEqual((Path(temp) / "synthetic.current.s3.txt").exists(), not unconfirmed)
                self.assertEqual("ABORT" in output.getvalue(), unconfirmed)

    def test_replacement_invalidates_only_the_sample_actually_started(self):
        cases = ("fresh_failure", "stale_failure", "overwrite", "quota_stop", "cache_resume", "report_only")
        for scenario in cases:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                contract = folder / "contract.md"
                contract.write_text("synthetic contract")
                fx = {"id": "synthetic", "prompt": "x"}
                current = folder / "synthetic.current.s1.txt"
                candidate = folder / "synthetic.candidate.s1.txt"
                previous = folder / "previous.current.s1.txt"
                previous.write_text("earlier completed sample")
                sig = "stale" if scenario == "stale_failure" else behavior.sample_sig(fx, "current", "")
                current.write_text(f"# sig: {sig}\nOLD_CURRENT\n")
                candidate.write_text(f"# sig: {behavior.sample_sig(fx, 'candidate', contract.read_text())}\nOLD_CANDIDATE\n")
                old_current, old_candidate = current.read_bytes(), candidate.read_bytes()
                failed = scenario.endswith("failure")
                stream = init(AGENT_TOOLS) + json.dumps(success(result="NEW_CURRENT"))
                if scenario == "quota_stop":
                    stream += "\n" + json.dumps({"type": "rate_limit_event", "rate_limit_info": {"utilization": 0.99}})
                first = ([subprocess.TimeoutExpired(["synthetic"], 1), ("", None)]
                         if failed else [(stream, None)])
                processes = [self.fake_process(first), self.fake_process([(init(AGENT_TOOLS) + json.dumps(success(result="NEW_CANDIDATE")), None)])]
                argv = ["eval", "--both-arms", "--samples", "1", "--timeout", "1", "--out", temp,
                        "--contract", str(contract), "--no-judge"]
                if scenario not in ("stale_failure", "cache_resume"):
                    argv.append("--fresh")
                if scenario == "report_only":
                    argv.append("--report-only")
                with mock.patch.object(sys, "argv", argv), \
                        mock.patch.object(behavior, "load_fixtures", return_value=[fx]), \
                        mock.patch.object(behavior.subprocess, "Popen", side_effect=processes) as spawn, \
                        mock.patch.object(behavior.os, "killpg", create=True), \
                        mock.patch.object(sys, "stdout", io.StringIO()):
                    behavior.main()
                self.assertEqual(previous.read_text(), "earlier completed sample")
                if failed:
                    self.assertFalse(current.exists(), "failed replacement left the old sample available")
                    logs = [json.loads(line) for line in (folder / "run-log.jsonl").read_text().splitlines()]
                    self.assertEqual(logs[0]["error"], "timeout_1s")
                elif scenario in ("cache_resume", "report_only"):
                    self.assertEqual(current.read_bytes(), old_current)
                    self.assertEqual(candidate.read_bytes(), old_candidate)
                    self.assertEqual(spawn.call_count, 0)
                else:
                    self.assertIn("NEW_CURRENT", current.read_text())
                    self.assertNotIn("OLD_CURRENT", current.read_text())
                if scenario == "quota_stop":
                    self.assertEqual(candidate.read_bytes(), old_candidate)
                    self.assertEqual(spawn.call_count, 1)
                else:
                    rows = [json.loads(line) for line in (folder / "judge-verdicts.jsonl").read_text().splitlines()]
                    self.assertEqual(rows[0]["status"], "missing-arm" if failed else "scaffold")
                    if scenario == "overwrite":
                        self.assertIn("NEW_CANDIDATE", candidate.read_text())

    @unittest.skipUnless(os.name == "posix", "group-kill integration requires POSIX")
    def test_cleanup_uncertainty_stops_judges_and_writes_incomplete_report(self):
        verdict = {"delta": "tie", "reduced_capabilities": [], "added_capabilities": [],
                   "behavior_change": "same", "confidence": "high", "needs_human": False}
        stream = (init([]) + json.dumps(success(result=json.dumps(verdict))), None)
        for unconfirmed in (False, True):
            with self.subTest(cleanup_unconfirmed=unconfirmed), tempfile.TemporaryDirectory() as temp:
                timeout = subprocess.TimeoutExpired(["synthetic"], 1)
                failed = self.fake_process([timeout, timeout if unconfirmed else stream])
                failed.wait.side_effect = timeout if unconfirmed else None
                processes = [self.fake_process([stream]), failed, self.fake_process([stream])]
                fixtures = [{"id": name} for name in ("first", "failed", "last")]
                argv = ["eval", "--report-only", "--timeout", "1", "--out", temp]
                with mock.patch.object(sys, "argv", argv), \
                        mock.patch.object(behavior, "load_fixtures", return_value=fixtures), \
                        mock.patch.object(behavior, "read_saved_response", return_value="complete"), \
                        mock.patch.object(behavior, "sample_sig", return_value="sig"), \
                        mock.patch.object(behavior, "_saved_sig", return_value="sig"), \
                        mock.patch.object(behavior.subprocess, "Popen", side_effect=processes) as spawn, \
                        mock.patch.object(behavior.os, "killpg", side_effect=PermissionError() if unconfirmed else None), \
                        mock.patch.object(sys, "stdout", io.StringIO()):
                    if unconfirmed:
                        with self.assertRaises(SystemExit) as ended:
                            behavior.main()
                        self.assertEqual(ended.exception.code, 1)
                    else:
                        behavior.main()
                rows = [json.loads(line) for line in (Path(temp) / "judge-verdicts.jsonl").read_text().splitlines()]
                self.assertEqual(spawn.call_count, 2 if unconfirmed else 3)
                self.assertEqual(rows[0]["status"], "judged")
                self.assertTrue(rows[1]["status"].startswith("judge-error:timeout_1s"))
                self.assertEqual(rows[2]["status"], "judge-skipped" if unconfirmed else "judged")
                if unconfirmed:
                    self.assertIn("cleanup_unconfirmed", rows[2]["note"])
                self.assertEqual(len(rows), 3)
                self.assertIn("INCOMPLETE", (Path(temp) / "capability-delta-report.md").read_text())


def options(cmd, flag):
    """The values a variadic CLI flag receives: every token after it up to the next option."""
    values = cmd[cmd.index(flag) + 1:]
    stop = next((i for i, token in enumerate(values) if token.startswith("--")), len(values))
    return values[:stop]


class ToolBoundaryTests(unittest.TestCase):
    """The defect: `--allowedTools` only pre-approves, so a host's allow rules or bypass mode let
    the arm agent run Bash and Write; plugin MCP tools stay even under `--tools`; the agent started
    in the caller's directory next to the saved answers. Each case fails on that code."""

    def capture(self, call):
        seen = []

        def fake(cmd, prompt, timeout_s, expected_tools=None, cwd=None):
            seen.append({"cmd": cmd, "expected": expected_tools, "cwd": cwd,
                         "cwd_entries": os.listdir(cwd) if cwd else None})
            return None, "synthetic", None, []

        with mock.patch.object(behavior, "_headless_claude", side_effect=fake):
            call()
        self.assertEqual(len(seen), 1)
        return seen[0]

    def arm_runs(self):
        with tempfile.TemporaryDirectory() as temp:
            contract = Path(temp) / "contract.md"
            contract.write_text("synthetic contract")
            for arm in ("current", "candidate"):
                yield arm, self.capture(lambda: behavior.run_agent("x", 1, arm, str(contract)))

    def test_arms_offer_only_read_tools_and_no_mcp(self):
        for arm, run in self.arm_runs():
            with self.subTest(arm=arm):
                self.assertNotIn("--allowedTools", run["cmd"])
                self.assertIn("--strict-mcp-config", run["cmd"])
                self.assertEqual(sorted(options(run["cmd"], "--tools")), sorted(AGENT_TOOLS))
                self.assertEqual(sorted(run["expected"]), sorted(AGENT_TOOLS))

    def test_judge_is_offered_no_tools(self):
        fx = {"id": "synthetic", "prompt": "x", "rubric": "r"}
        run = self.capture(lambda: behavior.run_judge(fx, "a", "b", 1))
        self.assertIn("--strict-mcp-config", run["cmd"])
        self.assertEqual(options(run["cmd"], "--tools"), [""])
        self.assertEqual(tuple(run["expected"]), ())

    def test_every_run_starts_in_a_fresh_empty_directory(self):
        runs = [run for _, run in self.arm_runs()]
        runs.append(self.capture(lambda: behavior.run_judge({"id": "s", "prompt": "x"}, "a", "b", 1)))
        for run in runs:
            self.assertIsNotNone(run["cwd"])
            self.assertNotEqual(os.path.realpath(run["cwd"]), os.path.realpath(os.getcwd()))
            self.assertEqual(run["cwd_entries"], [])
            self.assertFalse(os.path.exists(run["cwd"]), "the run directory outlived the run")
        self.assertEqual(len({run["cwd"] for run in runs}), len(runs))

    @unittest.skipUnless(os.name == "posix", "the stub claude is a shebang script")
    def test_launched_agent_process_runs_in_the_fresh_directory(self):
        # Through the real launch path: a stub `claude` reports the directory it actually ran in.
        report = ("import json, os, sys; sys.stdin.read(); "
                  f"print(json.dumps({{'type': 'system', 'subtype': 'init', 'tools': {AGENT_TOOLS!r}}})); "
                  "print(json.dumps({'type': 'result', 'subtype': 'success', 'is_error': False, "
                  "'result': json.dumps({'cwd': os.getcwd(), 'entries': os.listdir('.')})}))")
        with tempfile.TemporaryDirectory() as temp:
            stub = Path(temp) / "claude"
            stub.write_text(f"#!{sys.executable}\n{report}\n")
            stub.chmod(0o700)
            contract = Path(temp) / "contract.md"
            contract.write_text("synthetic contract")
            seen = []
            with mock.patch.dict(os.environ, {"PATH": temp + os.pathsep + os.environ["PATH"]}):
                for arm in ("current", "candidate"):
                    text, err, _, _ = behavior.run_agent("x", 5, arm, str(contract))
                    self.assertIsNone(err)
                    seen.append(json.loads(text))
        for ran in seen:
            self.assertNotEqual(os.path.realpath(ran["cwd"]), os.path.realpath(os.getcwd()))
            self.assertEqual(ran["entries"], [])
            self.assertFalse(os.path.exists(ran["cwd"]), "the run directory outlived the run")
        self.assertNotEqual(seen[0]["cwd"], seen[1]["cwd"])

    def test_a_run_directory_that_survives_cleanup_rejects_the_sample(self):
        made = []
        real_mkdtemp = tempfile.mkdtemp

        def mkdtemp(**kwargs):
            made.append(real_mkdtemp(**kwargs))
            return made[-1]

        streams = {"valid": (init(AGENT_TOOLS) + json.dumps(success()), "run_dir_not_removed"),
                   "already_failed": (init(AGENT_TOOLS), "missing_success_result;run_dir_not_removed")}
        try:
            for label, (stream, expected) in streams.items():
                with self.subTest(run=label), \
                        mock.patch.object(behavior.tempfile, "mkdtemp", side_effect=mkdtemp), \
                        mock.patch.object(behavior.shutil, "rmtree"):
                    result = behavior._in_fresh_dir([sys.executable, "-c", f"print({stream!r})"], "x", 5, AGENT_TOOLS)
                    self.assertEqual(result[:2], (None, expected))
                    self.assertTrue(os.path.isdir(made[-1]))
        finally:
            for path in made:
                os.rmdir(path)

    def test_failed_run_keeps_its_own_error_whatever_its_boundary(self):
        failures = {
            "error_flag": (success(is_error=True), "invalid_terminal_result"),
            "permission_denial": (success(permission_denials=[{"tool": "Read"}]), "invalid_terminal_result"),
            "empty_result": (success(result=""), "invalid_terminal_result"),
            "max_turns": (success(subtype="error_max_turns"), "result_error_max_turns"),
        }
        boundaries = {"no_init": "", "widened": init(AGENT_TOOLS + ["Bash"]), "held": init(AGENT_TOOLS)}
        for label, (terminal, expected) in failures.items():
            for shape, prefix in boundaries.items():
                with self.subTest(failure=label, boundary=shape):
                    stream = prefix + json.dumps(terminal)
                    result = behavior._headless_claude([sys.executable, "-c", f"print({stream!r})"], "x", 5,
                                                       expected_tools=AGENT_TOOLS)
                    self.assertEqual(result[:2], (None, expected))

    def test_samples_saved_under_the_old_launch_boundary_are_not_reused(self):
        # Resume skips a saved sample whose `# sig:` matches; the old signature covered only the
        # inputs, so a sample run with the leaky argv would have been banked as current.
        fx = {"prompt": "p", "rubric": "r"}
        for arm, layer in (("current", "tag"), ("candidate", "contract text")):
            old = hashlib.sha1("\x00".join(["p", "r", arm, layer]).encode("utf-8")).hexdigest()[:12]
            self.assertNotEqual(behavior.sample_sig(fx, arm, layer), old)

    def test_init_event_decides_whether_the_boundary_held(self):
        done = json.dumps(success())
        cases = {
            "held": (init(AGENT_TOOLS) + done, None),
            "subset": (init(["Read"]) + done, None),
            "bash_offered": (init(AGENT_TOOLS + ["Bash"]) + done, "tool_boundary_violated"),
            "mcp_offered": (init(AGENT_TOOLS + ["mcp__plugin_x__run"]) + done, "tool_boundary_violated"),
            "second_init_widened": (init(AGENT_TOOLS) + init(["Write"]) + done, "tool_boundary_violated"),
            "first_init_widened": (init(AGENT_TOOLS + ["Bash"]) + init(AGENT_TOOLS) + done, "tool_boundary_violated"),
            # A widened init the parser cannot read must not drop out of the check.
            "undecodable_widened_init": (init(AGENT_TOOLS) + '{"type": "system", "subtype": "init", "tools": ["Bash"]\n' + done,
                                         "missing_tool_boundary"),
            "unreadable_line": (init(AGENT_TOOLS) + "not json\n" + done, "missing_tool_boundary"),
            "blank_lines": (init(AGENT_TOOLS) + "\n\n" + done, None),
            "no_init": (done, "missing_tool_boundary"),
            "tools_not_a_list": (json.dumps({"type": "system", "subtype": "init", "tools": "Read"}) + "\n" + done,
                                 "missing_tool_boundary"),
        }
        for label, (stream, expected) in cases.items():
            with self.subTest(stream=label):
                result = behavior._headless_claude([sys.executable, "-c", f"print({stream!r})"], "x", 5,
                                                   expected_tools=AGENT_TOOLS)
                self.assertEqual(result[1], expected)
                self.assertEqual(result[0] is None, expected is not None)
        result = behavior._headless_claude([sys.executable, "-c", f"print({init(['Bash']) + done!r})"], "x", 5,
                                           expected_tools=())
        self.assertEqual(result[1], "tool_boundary_violated")


class GoldenRuntimeTests(unittest.TestCase):
    BOUNDARY = {"type": "system", "subtype": "init", "tools": ["Skill", "Read", "Grep", "Glob"]}

    def run_golden(self, events, forbidden=False, argv_out=None):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            stub = folder / "claude"
            record = f"open({str(argv_out)!r}, 'w').write(json.dumps(sys.argv[1:]))\n" if argv_out else ""
            stub.write_text(f"#!{sys.executable}\nimport json, sys\nsys.stdin.read()\n{record}print({events!r})\n")
            stub.chmod(0o700)
            traces = folder / "traces"
            traces.mkdir()
            (traces / "case.json").write_text(json.dumps({
                "id": "synthetic", "hub_skill": "testing-strategy", "frozen_at_sha": "root",
                "trigger_prompt": "synthetic", "assert": {
                    "must_invoke_skill": ["testing-strategy"],
                    "must_not_invoke_skill": ["testing-strategy"] if forbidden else [],
                },
            }))
            report = folder / "report.json"
            proc = subprocess.run(["ruby", str(HERE / "eval-golden-trace.rb"), str(ROOT),
                                   "--traces", str(traces), "--json", str(report)],
                                  env={**os.environ, "PATH": str(folder) + os.pathsep + os.environ["PATH"]},
                                  capture_output=True, text=True, timeout=5)
            self.assertIn(proc.returncode, (0, 3), proc.stderr)
            return json.loads(report.read_text())["results"][0]

    def test_only_complete_valid_stream_can_pass(self):
        skill = {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "Skill", "input": {"skill": "testing-strategy"}},
        ]}}
        boundary = self.BOUNDARY
        widened = {**boundary, "tools": boundary["tools"] + ["Bash"]}
        mcp = {**boundary, "tools": boundary["tools"] + ["mcp__plugin_x__run"]}
        cases = {
            "complete": ([boundary, skill, success()], "PASS"),
            "missing": ([boundary, skill], "INCONCLUSIVE"),
            "failed": ([boundary, skill, success(subtype="error_max_turns")], "INCONCLUSIVE"),
            "error_flag": ([boundary, skill, success(is_error=True)], "INCONCLUSIVE"),
            "duplicate": ([boundary, skill, success(), success()], "INCONCLUSIVE"),
            "malformed_event": ([boundary, skill, [], success()], "INCONCLUSIVE"),
            "malformed_content": ([boundary, skill, {"type": "assistant", "message": {"content": "bad"}}, success()], "INCONCLUSIVE"),
            "permission_denial": ([boundary, skill, success(permission_denials=[{"tool": "Read"}])], "INCONCLUSIVE"),
            "no_boundary": ([skill, success()], "INCONCLUSIVE"),
            "bash_offered": ([widened, skill, success()], "INCONCLUSIVE"),
            "first_init_widened": ([widened, boundary, skill, success()], "INCONCLUSIVE"),
            "second_init_widened": ([boundary, widened, skill, success()], "INCONCLUSIVE"),
            "mcp_offered": ([mcp, skill, success()], "INCONCLUSIVE"),
        }
        for label, (events, expected) in cases.items():
            with self.subTest(stream=label):
                row = self.run_golden("\n".join(json.dumps(event) for event in events))
                self.assertEqual(row["status"], expected)
                if expected == "INCONCLUSIVE":
                    self.assertTrue(row["error"])
        row = self.run_golden("\n".join(json.dumps(event) for event in (boundary, skill, success())), forbidden=True)
        self.assertEqual(row["status"], "FAIL")

    def test_replay_offers_only_read_tools_and_no_mcp(self):
        with tempfile.TemporaryDirectory() as temp:
            argv_out = Path(temp) / "argv.json"
            self.run_golden(json.dumps(success()), argv_out=argv_out)
            cmd = json.loads(argv_out.read_text())
        self.assertNotIn("--allowedTools", cmd)
        self.assertIn("--strict-mcp-config", cmd)
        self.assertEqual(sorted(options(cmd, "--tools")), sorted(AGENT_TOOLS))


if __name__ == "__main__":
    unittest.main()
