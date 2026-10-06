#!/usr/bin/env python3
"""Prove that the abort probe selects a fixture that has entered its hang."""
import contextlib
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPTS = Path(__file__).resolve().parent
CONTROLLER = """import os, subprocess, sys
p = subprocess.Popen(
    ["bash", "-c", 'eval "$SYNTHETIC_STUB_BODY"', os.environ["WRAPPER_ARG"],
     "review", "--diff-file", os.environ["PACKET"],
     "--review-profile-file", os.environ["PROFILE"]],
    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL, start_new_session=True)
print(p.pid, flush=True)
p.stdin.write(sys.stdin.readline().encode())
p.stdin.flush()
p.wait(timeout=30)
"""


class ReadinessTests(unittest.TestCase):
    @contextlib.contextmanager
    def fixture(self, client):
        suite = (SCRIPTS / "test_review_gate.sh").read_text()
        delimiter = "CLAUDE_STUB" if client == "claude" else "CLIENT_STUB"
        body = suite.split(f"<<'{delimiter}'\n", 1)[1].split(
            f"\n{delimiter}\n", 1)[0]
        behavior = (
            'behavior="$(cat "$state/claude_behavior")"'
            if client == "claude"
            else 'behavior="$(cat "$state/${client}_behavior")"'
        )
        self.assertEqual(body.count(behavior), 1)
        # An input barrier fixes the schedule before the real stub reads behavior.
        body = body.replace(behavior, "read -r startup_barrier\n" + behavior, 1)
        with tempfile.TemporaryDirectory(prefix="abort-readiness-") as temporary:
            root = Path(temporary)
            work = root / "review-gate-test.synthetic"
            state = work / "state"
            state.mkdir(parents=True)
            (state / f"{client}_behavior").write_text("hang")
            packet = root / "packet.patch"
            packet.write_text("synthetic packet\n")
            profile = root / "profile.json"
            profile.write_text('{"required_concerns": []}\n')
            environment = {
                "PATH": os.environ["PATH"],
                "REVIEW_GATE_TEST_STATE": str(state),
                "REVIEW_GATE_TEST_HANG_SECONDS": "20",
                "SYNTHETIC_STUB_BODY": body,
                "WRAPPER_ARG": str(work / "harness/scripts" / f"{client}_review.sh"),
                "PACKET": str(packet),
                "PROFILE": str(profile),
            }
            controller = subprocess.Popen(
                ["python3", "-c", CONTROLLER, str(work / "review_gate.py")],
                env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True)
            wrapper = None
            try:
                wrapper = int(controller.stdout.readline())
                self.wait_for(lambda: (state / f"{client}_profile_hash").exists())
                yield root, work, state, controller, wrapper, environment
            finally:
                # This group was created by this test; never scan or signal strangers.
                if wrapper is not None:
                    try:
                        os.killpg(wrapper, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                controller.kill()
                controller.wait(timeout=5)
                controller.stdin.close()
                controller.stdout.close()

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while not predicate():
            self.assertLess(time.monotonic(), deadline, "fixture readiness timed out")
            time.sleep(0.01)  # Bounded process-readiness polling, not a timing assertion.

    def select(self, fixture, client):
        root, work, _, _, _, environment = fixture
        probe = (SCRIPTS / "test_review_gate_abort_leak.sh").read_text()
        start = probe.index("live_wrapper() {")
        function = probe[start:probe.index("\n}\n", start) + 3]
        variables = {
            "PROBE_TMP": str(root),
            "PROBE_TMP_REAL": str(root),
            "PROBE_WRAPPER": f"{client}_review.sh",
            "PROBE_BEHAVIOR_FILE": f"{client}_behavior",
            "PROBE_STARTED_MARKER": f"{client}_hang_started",
        }
        source = "\n".join(f"{key}={shlex.quote(value)}"
                           for key, value in variables.items())
        source += "\nsuite_work_dir() { printf '%s\\n' " + shlex.quote(str(work)) + "; }\n"
        result = subprocess.run(
            ["bash", "-c", source + function + "\nlive_wrapper"],
            env=environment, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_startup_wrapper_is_not_a_hanging_fixture(self):
        for client in ("claude", "kimi"):
            with self.subTest(client=client), self.fixture(client) as fixture:
                self.assertEqual(self.select(fixture, client), "")

    def test_actual_hang_is_selectable(self):
        for client in ("claude", "kimi"):
            with self.subTest(client=client), self.fixture(client) as fixture:
                _, _, state, controller, wrapper, _ = fixture
                controller.stdin.write("start\n")
                controller.stdin.flush()
                self.wait_for(lambda: (state / f"{client}_hang_started").exists())
                self.assertEqual(self.select(fixture, client), str(wrapper))


if __name__ == "__main__":
    unittest.main()

