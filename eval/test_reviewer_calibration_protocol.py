import importlib.util
import errno
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest import mock


EVAL_DIR = Path(__file__).resolve().parent / "skill-effectiveness"
PROTOCOL_PATH = EVAL_DIR / "reviewer_calibration_protocol.py"
REQUEST_SCHEMA = "skill-effectiveness.reviewer-calibration.request.v1"
RESPONSE_SCHEMA = "skill-effectiveness.reviewer-calibration.response.v1"


class ReviewerCalibrationProtocolTests(unittest.TestCase):
    def _load_protocol_module(self):
        module_name = "reviewer_calibration_protocol_under_test"
        spec = importlib.util.spec_from_file_location(module_name, PROTOCOL_PATH)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        sys.path.insert(0, str(EVAL_DIR))
        try:
            spec.loader.exec_module(module)
        finally:
            sys.path.pop(0)
        return module

    def _write_fake_codex(self, root: Path) -> tuple[Path, Path]:
        log_path = root / "model-calls.jsonl"
        malformed_path = root / "malformed-response"
        executable = root / "codex"
        executable.write_text(
            """#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

log_path = Path(__FAKE_LOG_PATH__)
if sys.argv[1:] == ["--version"]:
    print("codex-cli protocol-test-1.0")
    raise SystemExit(0)
if not sys.argv[1:] or sys.argv[1] != "exec":
    raise SystemExit(64)
prompt = sys.stdin.read()
with log_path.open("a", encoding="utf-8") as stream:
    stream.write(json.dumps({"argv": sys.argv[1:], "prompt": prompt}) + "\\n")
request = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
verdicts = {
    "k1": "A win",
    "k2": "B win",
    "k3": "tie",
    "k4": "A win",
    "k5": "B win",
}
payload = {
    "protocol_version": 1,
    "judgments": [
        {"case_id": row["case_id"], "verdict": verdicts[row["case_id"]]}
        for row in request["cases"]
    ],
}
if Path(__MALFORMED_PATH__).exists():
    payload = {"protocol_version": 1, "judgments": []}
print(json.dumps({"type": "thread.started", "thread_id": "opaque"}))
print(json.dumps({"type": "turn.started"}))
print(json.dumps({
    "type": "item.completed",
    "item": {"type": "agent_message", "text": json.dumps(payload)},
}))
print(json.dumps({"type": "turn.completed"}))
""".replace("__FAKE_LOG_PATH__", repr(str(log_path))).replace(
                "__MALFORMED_PATH__", repr(str(malformed_path))
            ),
            encoding="utf-8",
        )
        executable.chmod(0o700)
        return executable, log_path

    def _invoke(
        self,
        request: dict,
        *,
        environment: dict[str, str] | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], dict]:
        result = subprocess.run(
            [sys.executable, str(PROTOCOL_PATH)],
            input=json.dumps(request),
            text=True,
            capture_output=True,
            check=False,
            env=environment,
        )
        self.assertNotIn("\x1b", result.stdout)
        self.assertNotIn("\x1b", result.stderr)
        # Diagnostics are emitted on the blocked and internal paths, so the leak
        # invariant is asserted for every request rather than the happy path.
        artifact_root = request.get("artifact_root")
        if isinstance(artifact_root, str) and artifact_root:
            self.assertNotIn(artifact_root, result.stdout)
            self.assertNotIn(artifact_root, result.stderr)
        self.assertNotIn("CALIBRATION_INPUT", result.stdout)
        self.assertNotIn("CALIBRATION_INPUT", result.stderr)
        response = json.loads(result.stdout)
        self.assertEqual(response["schema"], RESPONSE_SCHEMA)
        self.assertEqual(response["request_id"], request["request_id"])
        return result, response

    def _probe(self) -> dict:
        result, response = self._invoke(
            {
                "schema": REQUEST_SCHEMA,
                "request_id": "probe-1",
                "action": "probe",
                "payload": {},
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(response["status"], "ok")
        self.assertEqual(response["result"]["supported_providers"], ["codex"])
        self.assertEqual(
            set(response["result"]["runtime_manifest"]["interpreter"]),
            {"implementation", "version", "executable_hash"},
        )
        self.assertNotIn(sys.executable, result.stdout)
        return response["result"]

    def _sample_request(
        self,
        *,
        request_id: str,
        sample_id: str,
        artifact_root: Path,
        executable: Path,
        manifest_hash: str,
    ) -> dict:
        return {
            "schema": REQUEST_SCHEMA,
            "request_id": request_id,
            "action": "sample",
            "artifact_root": str(artifact_root),
            "payload": {
                "sample_id": sample_id,
                "provider": "codex",
                "executable": str(executable),
                "model": "gpt-test-exact",
                "reviewer_family": "codex-test",
                "timeout_seconds": 5,
                "max_model_calls": 1,
                "runtime_manifest_hash": manifest_hash,
            },
        }

    def test_invalid_provider_or_relative_binary_fails_before_model_start(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            environment = os.environ.copy()
            environment["FAKE_CODEX_LOG"] = str(log_path)
            request = self._sample_request(
                request_id="sample-invalid-provider",
                sample_id="sample-001",
                artifact_root=root / "artifacts",
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            request["payload"]["provider"] = "claude"
            result, response = self._invoke(request, environment=environment)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(response["status"], "invalid")
            self.assertFalse(log_path.exists())

            request = self._sample_request(
                request_id="sample-relative-binary",
                sample_id="sample-001",
                artifact_root=root / "artifacts",
                executable=Path("codex"),
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request, environment=environment)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(response["status"], "invalid")
            self.assertFalse(log_path.exists())

            invalid_cases = (
                ("model", "", 2, "invalid"),
                ("reviewer_family", "bad family", 2, "invalid"),
                ("timeout_seconds", 0, 2, "invalid"),
                ("max_model_calls", 2, 2, "invalid"),
                (
                    "runtime_manifest_hash",
                    "sha256:" + "0" * 64,
                    3,
                    "blocked",
                ),
            )
            for index, (field, value, exit_code, status) in enumerate(
                invalid_cases, start=1
            ):
                request = self._sample_request(
                    request_id=f"sample-invalid-{index}",
                    sample_id="sample-001",
                    artifact_root=root / "artifacts",
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                request["payload"][field] = value
                result, response = self._invoke(request, environment=environment)
                self.assertEqual(result.returncode, exit_code)
                self.assertEqual(response["status"], status)
                self.assertFalse(log_path.exists())

    def test_sample_calls_model_once_withholds_truth_and_blocks_replay(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            environment = os.environ.copy()
            environment.update(
                {
                    "FAKE_CODEX_LOG": str(log_path),
                    "HTTP_PROXY": "http://environment-marker.invalid",
                }
            )
            request = self._sample_request(
                request_id="sample-1",
                sample_id="sample-001",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request, environment=environment)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(response["status"], "ok")
            self.assertEqual(response["result"]["model_call_count"], 1)
            self.assertEqual(response["result"]["sample_id"], "sample-001")
            self.assertNotIn(str(root), result.stdout)
            calls = [
                json.loads(line)
                for line in log_path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(len(calls), 1)
            prompt = calls[0]["prompt"]
            self.assertNotIn("environment-marker.invalid", prompt)
            self.assertNotIn(str(root), prompt)
            # Substring absence cannot prove truth withholding: it only rules out
            # the key names it happens to name. Bind the outbound structure.
            calibration_input = json.loads(prompt.split("CALIBRATION_INPUT=", 1)[1])
            self.assertEqual(
                {"protocol_version", "instructions", "cases"},
                set(calibration_input),
            )
            self.assertTrue(calibration_input["cases"])
            for case in calibration_input["cases"]:
                self.assertEqual(
                    {"case_id", "task", "rubric", "candidate_a", "candidate_b"},
                    set(case),
                )
            self.assertEqual(stat.S_IMODE(artifact_root.stat().st_mode), 0o700)
            sample_path = artifact_root / "samples" / "sample-001.json"
            self.assertEqual(stat.S_IMODE(sample_path.stat().st_mode), 0o600)
            sample = json.loads(sample_path.read_text(encoding="utf-8"))
            self.assertEqual("ephemeral", sample["requested_session_mode"])
            self.assertEqual("read-only-observed-none", sample["tool_access"])
            ledger_path = artifact_root / "sample-ledger" / "sample-001.json"
            self.assertEqual(stat.S_IMODE(ledger_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(ledger_path.parent.stat().st_mode), 0o700)

            replay = dict(request)
            replay["request_id"] = "sample-1-replay"
            result, response = self._invoke(replay, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["status"], "blocked")
            self.assertEqual(response["reason_code"], "sample_already_exists")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_finalize_requires_exact_set_and_publishes_pair_without_model(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            environment = os.environ.copy()
            environment["FAKE_CODEX_LOG"] = str(log_path)
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request, environment=environment)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 2)

            incomplete = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-incomplete",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-003"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            result, response = self._invoke(incomplete, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "sample_set_mismatch")
            self.assertFalse(
                (artifact_root / "calibration" / "reviewer-calibration.json").exists()
            )

            finalize = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-exact",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            intent_path = artifact_root / "samples" / ".sample-002.intent.json"
            completed_intent = json.loads(intent_path.read_text(encoding="utf-8"))
            self.assertEqual(completed_intent["state"], "completed")
            unresolved_intent = dict(completed_intent)
            unresolved_intent["state"] = "model_call_started"
            unresolved_intent.pop("sample_hash")
            intent_path.write_text(json.dumps(unresolved_intent), encoding="utf-8")
            intent_path.chmod(0o600)
            unresolved_finalize = dict(finalize)
            unresolved_finalize["request_id"] = "finalize-unresolved"
            result, response = self._invoke(
                unresolved_finalize, environment=environment
            )
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "sample_finality_unknown")
            self.assertFalse(
                (artifact_root / "calibration" / "reviewer-calibration.json").exists()
            )
            intent_path.write_text(json.dumps(completed_intent), encoding="utf-8")
            intent_path.chmod(0o600)
            mismatched_intent = dict(completed_intent)
            mismatched_intent["model"] = "gpt-tampered"
            intent_path.write_text(json.dumps(mismatched_intent), encoding="utf-8")
            intent_path.chmod(0o600)
            mismatched_finalize = dict(finalize)
            mismatched_finalize["request_id"] = "finalize-intent-mismatch"
            result, response = self._invoke(
                mismatched_finalize, environment=environment
            )
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "sample_intent_mismatch")
            intent_path.write_text(json.dumps(completed_intent), encoding="utf-8")
            intent_path.chmod(0o600)

            result, response = self._invoke(finalize, environment=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(response["status"], "ok")
            self.assertEqual(response["result"]["model_call_count"], 0)
            self.assertEqual(response["result"]["calibration_status"], "pass")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 2)
            calibration_root = artifact_root / "calibration"
            self.assertEqual(
                stat.S_IMODE(calibration_root.stat().st_mode),
                0o700,
            )
            report = json.loads(
                (calibration_root / "reviewer-calibration-result.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual("read-only-observed-none", report["tool_access"])
            for name in (
                "reviewer-calibration.json",
                "reviewer-calibration-result.json",
            ):
                self.assertEqual(
                    stat.S_IMODE((calibration_root / name).stat().st_mode), 0o600
                )
            finalization_path = artifact_root / ".finalization.intent.json"
            finalization = json.loads(finalization_path.read_text(encoding="utf-8"))
            self.assertEqual(finalization["state"], "completed")
            self.assertRegex(finalization["claim_token"], r"^[0-9a-f]{64}$")
            self.assertRegex(
                finalization["published_pair_hash"], r"^sha256:[0-9a-f]{64}$"
            )
            self.assertEqual(stat.S_IMODE(finalization_path.stat().st_mode), 0o600)
            published = {
                name: (calibration_root / name).read_bytes()
                for name in (
                    "reviewer-calibration.json",
                    "reviewer-calibration-result.json",
                )
            }
            repeated_finalize = dict(finalize)
            repeated_finalize["request_id"] = "finalize-repeated"
            result, response = self._invoke(repeated_finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "finalize_already_started")
            self.assertEqual(
                published,
                {name: (calibration_root / name).read_bytes() for name in published},
            )
            moved_calibration_root = artifact_root / "published-calibration"
            calibration_root.rename(moved_calibration_root)
            repeated_finalize["request_id"] = "finalize-after-move"
            result, response = self._invoke(repeated_finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "finalize_already_started")
            self.assertEqual(
                published,
                {
                    name: (moved_calibration_root / name).read_bytes()
                    for name in published
                },
            )

            copied_root = root / "copied-artifacts"
            copied_root.mkdir(mode=0o700)
            shutil.copytree(artifact_root / "samples", copied_root / "samples")
            shutil.copytree(
                artifact_root / "sample-ledger",
                copied_root / "sample-ledger",
            )
            copied_finalize = dict(finalize)
            copied_finalize["request_id"] = "finalize-copied-root"
            copied_finalize["artifact_root"] = str(copied_root)
            result, response = self._invoke(copied_finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_mismatch")
            self.assertFalse((copied_root / "calibration").exists())

    def test_finalize_rejects_stateless_v1_ledgers(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = (root / "artifacts").resolve()
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)
            protocol = self._load_protocol_module()
            for index in (1, 2):
                ledger_path = (
                    artifact_root / "sample-ledger" / f"sample-{index:03d}.json"
                )
                ledger = protocol.trial.load_private_json(ledger_path)
                ledger["artifact_contract"] = (
                    "skill-effectiveness-reviewer-calibration-sample-ledger-entry-v1"
                )
                ledger.pop("state")
                protocol.trial.write_json_atomic(ledger_path, ledger)

            finalize = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-legacy-ledgers",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            result, response = self._invoke(finalize)
            # A v1 ledger carries no state, so it cannot evidence that the model
            # call started. No v1 ledger has ever been written by this protocol.
            self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
            self.assertEqual(response["reason_code"], "sample_invalid")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 2)

    def test_finalize_rejects_orphaned_intent_from_deleted_sample(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            environment = os.environ.copy()
            environment["FAKE_CODEX_LOG"] = str(log_path)
            for index in (1, 2, 3):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request, environment=environment)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            deleted_sample = artifact_root / "samples" / "sample-003.json"
            deleted_sample.unlink()
            self.assertTrue(
                (artifact_root / "samples" / ".sample-003.intent.json").exists()
            )

            finalize = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-cherry-picked",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            result, response = self._invoke(finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            (artifact_root / "samples" / ".sample-003.intent.json").unlink()
            finalize["request_id"] = "finalize-pair-deleted"
            result, response = self._invoke(finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 3)
            self.assertFalse((artifact_root / "calibration").exists())

    def test_finalize_retries_after_pre_publication_failure(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            environment = os.environ.copy()
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request, environment=environment)
                self.assertEqual(result.returncode, 0)

            protocol = self._load_protocol_module()
            finalization_path = (artifact_root / ".finalization.intent.json").resolve()
            original_write_json_atomic = protocol.trial.write_json_atomic

            def crash_after_output_claim(path, value):
                if (
                    path.resolve() == finalization_path
                    and isinstance(value, dict)
                    and value.get("state") == "output_claimed"
                ):
                    raise SystemExit(137)
                original_write_json_atomic(path, value)

            with mock.patch.object(
                protocol.trial,
                "write_json_atomic",
                side_effect=crash_after_output_claim,
            ):
                with self.assertRaises(SystemExit):
                    protocol._finalize(
                        {
                            "sample_ids": ["sample-001", "sample-002"],
                            "runtime_manifest_hash": probe["runtime_manifest_hash"],
                        },
                        str(artifact_root),
                    )

            finalization = protocol.trial.load_private_json(finalization_path)
            self.assertEqual(finalization["state"], "publication_started")
            lock = protocol.trial.load_private_json(
                artifact_root / "calibration" / ".reviewer-calibration.lock"
            )
            self.assertEqual(lock["claim_token"], finalization["claim_token"])
            tokenless = dict(finalization)
            tokenless.pop("claim_token")
            protocol.trial.write_json_atomic(finalization_path, tokenless)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalize_already_started",
            )
            protocol.trial.write_json_atomic(finalization_path, finalization)

            response = protocol._finalize(
                {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
                str(artifact_root),
            )
            self.assertEqual(response["model_call_count"], 0)
            calibration_root = artifact_root / "calibration"
            self.assertTrue(
                (calibration_root / "reviewer-calibration-result.json").exists()
            )
            self.assertTrue(
                (calibration_root / "reviewer-calibration.json").exists()
            )
            finalization = protocol.trial.load_private_json(finalization_path)
            self.assertEqual(finalization["state"], "completed")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 2)

    def test_finalize_retry_refuses_partial_publication(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)
            calibration_root = artifact_root / "calibration"
            calibration_root.mkdir(mode=0o755)
            calibration_root.chmod(0o755)
            finalize = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-partial-first",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            result, response = self._invoke(finalize)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "finalization_recovery_required")
            self.assertFalse((artifact_root / ".finalization.intent.json").exists())
            self.assertEqual(stat.S_IMODE(calibration_root.stat().st_mode), 0o755)

            calibration_root.chmod(0o700)
            lock_path = calibration_root / ".reviewer-calibration.lock"
            lock_path.write_text("", encoding="utf-8")
            lock_path.chmod(0o600)
            result, response = self._invoke(finalize)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "finalization_recovery_required")
            self.assertNotIn(str(artifact_root), result.stdout)
            lock_path.unlink()
            partial_path = calibration_root / "reviewer-calibration.json"
            partial_path.write_text("{}\n", encoding="utf-8")
            partial_path.chmod(0o600)

            finalize["request_id"] = "finalize-partial-retry"
            result, response = self._invoke(finalize)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "finalization_recovery_required")
            self.assertNotIn(str(artifact_root), result.stdout)
            self.assertTrue(partial_path.exists())
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 2)

    def test_finalize_retry_recovers_owned_partial_publication_without_model(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)

            protocol = self._load_protocol_module()
            partial_path = (
                artifact_root / "calibration" / "reviewer-calibration.json"
            )

            def leave_owned_partial(**_kwargs):
                partial_path.write_text("{}\n", encoding="utf-8")
                partial_path.chmod(0o600)
                raise SystemExit(137)

            with mock.patch.object(
                protocol.reviewer_calibration,
                "_persist_calibration",
                side_effect=leave_owned_partial,
            ):
                with self.assertRaises(SystemExit):
                    protocol._finalize(
                        {
                            "sample_ids": ["sample-001", "sample-002"],
                            "runtime_manifest_hash": probe["runtime_manifest_hash"],
                        },
                        str(artifact_root),
                    )

            finalization_path = artifact_root / ".finalization.intent.json"
            finalization = protocol.trial.load_private_json(finalization_path)
            self.assertEqual(finalization["state"], "output_claimed")
            self.assertEqual(
                len(log_path.read_text(encoding="utf-8").splitlines()), 2
            )

            calibration_root = partial_path.parent
            lock_path = calibration_root / ".reviewer-calibration.lock"
            claimed_lock_bytes = lock_path.read_bytes()
            outside_root = root / "outside-calibration"
            outside_root.mkdir(mode=0o700)
            outside_partial = outside_root / partial_path.name
            outside_partial.write_text("{}\n", encoding="utf-8")
            outside_partial.chmod(0o600)
            owned_calibration = root / "owned-calibration"
            calibration_root.rename(owned_calibration)
            calibration_root.symlink_to(outside_root, target_is_directory=True)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertEqual(outside_partial.read_text(encoding="utf-8"), "{}\n")
            calibration_root.unlink()
            owned_calibration.rename(calibration_root)

            calibration_root.chmod(0o755)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            self.assertEqual(lock_path.read_bytes(), claimed_lock_bytes)
            self.assertEqual(
                stat.S_IMODE(calibration_root.stat().st_mode),
                0o755,
            )
            self.assertEqual(
                protocol.trial.load_private_json(finalization_path)["state"],
                "output_claimed",
            )
            calibration_root.chmod(0o700)

            original_lock = protocol.trial.load_private_json(lock_path)
            protocol.trial.write_json_atomic(
                lock_path,
                {"claim_token": "0" * 64},
            )
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            protocol.trial.write_json_atomic(lock_path, original_lock)

            symlink_target = root / "outside.json"
            symlink_target.write_text("{}\n", encoding="utf-8")
            symlink_target.chmod(0o600)
            partial_path.unlink()
            partial_path.symlink_to(symlink_target)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertTrue(partial_path.is_symlink())
            self.assertEqual(symlink_target.read_text(encoding="utf-8"), "{}\n")
            partial_path.unlink()
            partial_path.write_text("{}\n", encoding="utf-8")

            partial_path.chmod(0o644)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            partial_path.chmod(0o600)
            result_path = (
                artifact_root
                / "calibration"
                / "reviewer-calibration-result.json"
            )
            result_path.write_text("{}\n", encoding="utf-8")
            result_path.chmod(0o600)
            terminal_request = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-complete-mismatch",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            lock_path.unlink()
            result, response = self._invoke(terminal_request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(
                response["reason_code"],
                "finalize_already_started",
            )
            self.assertNotIn(str(artifact_root), result.stdout)
            self.assertFalse(lock_path.exists())
            self.assertEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            self.assertEqual(result_path.read_text(encoding="utf-8"), "{}\n")
            result_path.unlink()
            recovery_request = dict(terminal_request)
            recovery_request["request_id"] = "finalize-missing-lock-recovery"
            partial_path.chmod(0o644)
            result, response = self._invoke(recovery_request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(
                response["reason_code"],
                "finalization_recovery_required",
            )
            self.assertEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            self.assertFalse(lock_path.exists())
            self.assertNotIn(str(artifact_root), result.stdout)
            partial_path.chmod(0o600)
            recovery_request["request_id"] = "finalize-missing-lock-recovered"
            result, response = self._invoke(recovery_request)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(response["result"]["model_call_count"], 0)
            self.assertNotIn(str(artifact_root), result.stdout)
            self.assertEqual(
                len(log_path.read_text(encoding="utf-8").splitlines()), 2
            )
            self.assertNotEqual(partial_path.read_text(encoding="utf-8"), "{}\n")
            self.assertTrue(result_path.exists())
            finalization = protocol.trial.load_private_json(
                artifact_root / ".finalization.intent.json"
            )
            self.assertEqual(finalization["state"], "completed")
            self.assertEqual(lock_path.read_bytes(), claimed_lock_bytes)

    def test_finalize_retry_confirms_published_pair_without_republishing(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)

            protocol = self._load_protocol_module()
            finalization_path = artifact_root / ".finalization.intent.json"
            original_write_json_atomic = protocol.trial.write_json_atomic

            def crash_before_confirmation(path, value):
                if (
                    path.resolve() == finalization_path.resolve()
                    and isinstance(value, dict)
                    and value.get("state") == "completed"
                ):
                    raise SystemExit(137)
                original_write_json_atomic(path, value)

            with mock.patch.object(
                protocol.trial,
                "write_json_atomic",
                side_effect=crash_before_confirmation,
            ):
                with self.assertRaises(SystemExit):
                    protocol._finalize(
                        {
                            "sample_ids": ["sample-001", "sample-002"],
                            "runtime_manifest_hash": probe["runtime_manifest_hash"],
                        },
                        str(artifact_root),
                    )

            calibration_root = artifact_root / "calibration"
            report_path = calibration_root / "reviewer-calibration-result.json"
            evidence_path = calibration_root / "reviewer-calibration.json"
            published = {
                report_path: report_path.read_bytes(),
                evidence_path: evidence_path.read_bytes(),
            }
            self.assertEqual(
                protocol.trial.load_private_json(finalization_path)["state"],
                "output_claimed",
            )
            staged_report_path = (
                calibration_root / ".reviewer-calibration-result.pending.json"
            )
            lock_path = calibration_root / ".reviewer-calibration.lock"
            lock_path.unlink()
            staged_report_path.write_text("{}\n", encoding="utf-8")
            staged_report_path.chmod(0o600)
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertFalse(lock_path.exists())
            self.assertTrue(staged_report_path.exists())
            staged_report_path.write_bytes(report_path.read_bytes())
            staged_report_path.chmod(0o600)
            staged_path = (
                calibration_root / ".reviewer-calibration.pending.json"
            )
            outside_staged = root / "outside-staged.json"
            outside_staged.write_text("{}\n", encoding="utf-8")
            outside_staged.chmod(0o600)
            staged_path.symlink_to(outside_staged)
            with (
                mock.patch.object(
                    protocol.reviewer_calibration,
                    "_persist_calibration",
                    side_effect=AssertionError(
                        "published pair must not be rebuilt"
                    ),
                ) as persist_calibration,
                self.assertRaises(protocol.Blocked) as caught,
            ):
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            persist_calibration.assert_not_called()
            self.assertFalse(lock_path.exists())
            self.assertTrue(staged_report_path.exists())
            self.assertTrue(staged_path.is_symlink())
            self.assertEqual(
                protocol.trial.load_private_json(finalization_path)["state"],
                "output_claimed",
            )
            staged_path.unlink()
            staged_path.write_bytes(evidence_path.read_bytes())
            staged_path.chmod(0o600)
            staged_report_path.write_text("{}\n", encoding="utf-8")
            with self.assertRaises(protocol.Blocked) as caught:
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertTrue(staged_report_path.exists())
            self.assertTrue(staged_path.exists())
            staged_report_path.write_bytes(report_path.read_bytes())
            staged_report_path.chmod(0o600)
            with mock.patch.object(
                protocol.reviewer_calibration,
                "_persist_calibration",
                side_effect=AssertionError("published pair must not be rebuilt"),
            ) as persist_calibration:
                recovered = protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            persist_calibration.assert_not_called()
            self.assertEqual(recovered["model_call_count"], 0)
            self.assertFalse(staged_report_path.exists())
            self.assertFalse(staged_path.exists())
            self.assertEqual(report_path.read_bytes(), published[report_path])
            self.assertEqual(evidence_path.read_bytes(), published[evidence_path])
            self.assertEqual(
                protocol.trial.load_private_json(finalization_path)["state"],
                "completed",
            )
            self.assertEqual(
                len(log_path.read_text(encoding="utf-8").splitlines()),
                2,
            )

    def test_non_oserror_finalize_failure_requires_recovery(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, _ = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)

            protocol = self._load_protocol_module()
            with mock.patch.object(
                protocol.reviewer_calibration,
                "_build_calibration_documents",
                side_effect=RuntimeError("synthetic document failure"),
            ):
                with self.assertRaises(protocol.Blocked) as caught:
                    protocol._finalize(
                        {
                            "sample_ids": ["sample-001", "sample-002"],
                            "runtime_manifest_hash": probe["runtime_manifest_hash"],
                        },
                        str(artifact_root),
                    )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            self.assertEqual(
                protocol.trial.load_private_json(
                    artifact_root / ".finalization.intent.json"
                )["state"],
                "publication_started",
            )

            with mock.patch.object(
                protocol.reviewer_calibration,
                "_persist_calibration",
                side_effect=RuntimeError("synthetic publication failure"),
            ):
                with self.assertRaises(protocol.Blocked) as caught:
                    protocol._finalize(
                        {
                            "sample_ids": ["sample-001", "sample-002"],
                            "runtime_manifest_hash": probe["runtime_manifest_hash"],
                        },
                        str(artifact_root),
                    )
            self.assertEqual(
                caught.exception.reason_code,
                "finalization_recovery_required",
            )
            recovered = protocol._finalize(
                {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
                str(artifact_root),
            )
            self.assertEqual(recovered["model_call_count"], 0)
            finalization = protocol.trial.load_private_json(
                artifact_root / ".finalization.intent.json"
            )
            self.assertEqual(finalization["state"], "completed")

    def test_orphan_ledger_quarantines_before_model_call(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            first = self._sample_request(
                request_id="sample-1",
                sample_id="sample-001",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, _ = self._invoke(first)
            self.assertEqual(result.returncode, 0)
            ledger_root = artifact_root / "sample-ledger"
            orphan = json.loads(
                (ledger_root / "sample-001.json").read_text(encoding="utf-8")
            )
            orphan["sample_id"] = "sample-002"
            (ledger_root / "sample-002.json").write_text(
                json.dumps(orphan), encoding="utf-8"
            )
            (ledger_root / "sample-002.json").chmod(0o600)

            request = self._sample_request(
                request_id="sample-after-orphan-ledger",
                sample_id="sample-003",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_same_sample_orphan_ledger_resumes_before_model_call(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = (root / "artifacts").resolve()
            protocol = self._load_protocol_module()
            protocol.trial.ensure_private_directory(artifact_root)
            ledger_root = artifact_root / "sample-ledger"
            protocol.trial.ensure_private_directory(ledger_root, artifact_root)
            protocol.trial.write_json_atomic(
                ledger_root / "sample-001.json",
                {
                    "schema_version": 1,
                    "artifact_contract": protocol.SAMPLE_LEDGER_CONTRACT,
                    "sample_id": "sample-001",
                    "artifact_root_hash": protocol._artifact_root_hash(artifact_root),
                    "state": "reserved",
                },
            )

            request = self._sample_request(
                request_id="sample-resume-orphan-ledger",
                sample_id="sample-001",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(response["result"]["model_call_count"], 1)
            self.assertTrue(
                (artifact_root / "samples" / "sample-001.json").exists()
            )
            intent = json.loads(
                (
                    artifact_root / "samples" / ".sample-001.intent.json"
                ).read_text(encoding="utf-8")
            )
            self.assertEqual(intent["state"], "completed")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_started_ledger_without_intent_never_retries_model(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            malformed_path = root / "malformed-response"
            malformed_path.write_text("", encoding="utf-8")
            request = self._sample_request(
                request_id="sample-unresolved-before-intent-loss",
                sample_id="sample-001",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "model_call_unresolved")
            intent_path = artifact_root / "samples" / ".sample-001.intent.json"
            intent_path.unlink()
            malformed_path.unlink()

            request["request_id"] = "sample-retry-after-intent-loss"
            result, response = self._invoke(request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_concurrent_samples_do_not_observe_transient_ledger_state(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            protocol = self._load_protocol_module()
            first_ledger_written = threading.Event()
            release_first = threading.Event()
            original_write = protocol._write_exclusive_json

            def pause_after_first_ledger(path, payload, **kwargs):
                original_write(path, payload, **kwargs)
                if (
                    path.name == "sample-001.json"
                    and path.parent.name == "sample-ledger"
                ):
                    first_ledger_written.set()
                    self.assertTrue(release_first.wait(timeout=5))

            requests = [
                self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                for index in (1, 2)
            ]
            with (
                mock.patch.object(
                    protocol,
                    "_write_exclusive_json",
                    side_effect=pause_after_first_ledger,
                ),
                ThreadPoolExecutor(max_workers=2) as pool,
            ):
                first = pool.submit(
                    protocol._sample,
                    requests[0]["payload"],
                    str(artifact_root),
                )
                self.assertTrue(first_ledger_written.wait(timeout=5))
                second = pool.submit(
                    protocol._sample,
                    requests[1]["payload"],
                    str(artifact_root),
                )
                release_first.set()
                results = [first.result(timeout=10), second.result(timeout=10)]

            self.assertEqual(
                ["sample-001", "sample-002"],
                sorted(result["sample_id"] for result in results),
            )
            self.assertEqual(2, len(log_path.read_text(encoding="utf-8").splitlines()))

    def test_finalize_waits_for_inflight_sample_and_closes_the_root(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            protocol = self._load_protocol_module()
            requests = [
                self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                for index in (1, 2, 3, 4)
            ]
            for request in requests[:2]:
                protocol._sample(request["payload"], str(artifact_root))

            third_ledger_written = threading.Event()
            release_third = threading.Event()
            original_write = protocol._write_exclusive_json

            def pause_after_third_ledger(path, payload, **kwargs):
                original_write(path, payload, **kwargs)
                if (
                    path.name == "sample-003.json"
                    and path.parent.name == "sample-ledger"
                ):
                    third_ledger_written.set()
                    self.assertTrue(release_third.wait(timeout=5))

            finalize_payload = {
                "sample_ids": ["sample-001", "sample-002", "sample-003"],
                "runtime_manifest_hash": probe["runtime_manifest_hash"],
            }
            with (
                mock.patch.object(
                    protocol,
                    "_write_exclusive_json",
                    side_effect=pause_after_third_ledger,
                ),
                ThreadPoolExecutor(max_workers=2) as pool,
            ):
                sample = pool.submit(
                    protocol._sample,
                    requests[2]["payload"],
                    str(artifact_root),
                )
                self.assertTrue(third_ledger_written.wait(timeout=5))
                finalize = pool.submit(
                    protocol._finalize,
                    finalize_payload,
                    str(artifact_root),
                )
                release_third.set()
                self.assertEqual("sample-003", sample.result(timeout=10)["sample_id"])
                self.assertEqual(0, finalize.result(timeout=10)["model_call_count"])

            with self.assertRaises(protocol.Blocked) as caught:
                protocol._sample(requests[3]["payload"], str(artifact_root))
            self.assertEqual("finalize_already_started", caught.exception.reason_code)
            self.assertEqual(3, len(log_path.read_text(encoding="utf-8").splitlines()))

    def test_transient_sample_lock_failure_does_not_quarantine_root(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact_root = Path(directory) / "artifacts"
            artifact_root.mkdir(mode=0o700)
            protocol = self._load_protocol_module()
            lock_path = str(artifact_root / ".sample.lock")
            real_open = os.open

            def only_the_lock_fails(path, *args, **kwargs):
                # A process-global open failure cannot distinguish a lock
                # acquisition failure from any other open mapped to the same
                # reason code, so fail exactly the lock path and delegate the rest.
                if str(path) == lock_path:
                    raise OSError(errno.ENOSPC, "synthetic full volume")
                return real_open(path, *args, **kwargs)

            with (
                mock.patch.object(
                    protocol.os,
                    "open",
                    side_effect=only_the_lock_fails,
                ),
                self.assertRaises(protocol.Blocked) as caught,
            ):
                with protocol._sample_root_lock(artifact_root):
                    self.fail("lock acquisition should have failed")
            self.assertEqual("sample_lock_unavailable", caught.exception.reason_code)

    def test_published_schemas_match_the_implemented_contract(self):
        protocol = self._load_protocol_module()
        request_schema = json.loads(
            (EVAL_DIR / "protocol/reviewer-calibration-request-v1.schema.json").read_text(
                encoding="utf-8"
            )
        )
        response_schema = json.loads(
            (
                EVAL_DIR / "protocol/reviewer-calibration-response-v1.schema.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(
            REQUEST_SCHEMA, request_schema["properties"]["schema"]["const"]
        )
        self.assertEqual(
            RESPONSE_SCHEMA, response_schema["properties"]["schema"]["const"]
        )
        self.assertFalse(request_schema["additionalProperties"])
        self.assertFalse(response_schema["additionalProperties"])

        probe = self._probe()
        self.assertEqual(
            sorted(request_schema["properties"]["action"]["enum"]),
            sorted(probe["supported_actions"]),
        )
        self.assertEqual(
            sorted(response_schema["properties"]["action"]["enum"]),
            sorted(probe["supported_actions"]),
        )
        self.assertEqual(
            ["blocked", "error", "invalid", "ok"],
            sorted(response_schema["properties"]["status"]["enum"]),
        )
        # A consumer pins this set, so the schema, the probe output and the
        # raise sites must agree. A pattern-only reason_code would let any new
        # code ship unannounced.
        declared = sorted(protocol.REASON_CODES)
        self.assertEqual(
            declared, sorted(response_schema["properties"]["reason_code"]["enum"])
        )
        self.assertEqual(declared, sorted(probe["reason_codes"]))
        self.assertEqual(len(declared), len(set(declared)))

        source = (EVAL_DIR / "reviewer_calibration_protocol.py").read_text(
            encoding="utf-8"
        )
        raised = set(
            re.findall(
                r'(?:InvalidRequest|Blocked|InternalFailure)\(\s*"([a-z][a-z0-9_]*)"',
                source,
            )
        )
        raised |= set(re.findall(r'reason_code="([a-z][a-z0-9_]*)"', source))
        undeclared = sorted(raised - set(declared))
        self.assertEqual([], undeclared, f"undeclared reason codes: {undeclared}")

    def test_publication_failure_leaves_no_half_published_pair(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = (root / "artifacts").resolve()
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request)
                self.assertEqual(result.returncode, 0)
            protocol = self._load_protocol_module()
            real_replace = os.replace
            replacements: list[str] = []

            def fail_result_publication(src, dst):
                # Fail the second half of the pair publication, after the first
                # canonical file has already landed.
                replacements.append(str(dst))
                if str(dst).endswith("reviewer-calibration-result.json"):
                    raise OSError(errno.EIO, "synthetic publication failure")
                return real_replace(src, dst)

            with (
                mock.patch.object(
                    protocol.reviewer_calibration.os,
                    "replace",
                    side_effect=fail_result_publication,
                ),
                self.assertRaises(protocol.Blocked) as caught,
            ):
                protocol._finalize(
                    {
                        "sample_ids": ["sample-001", "sample-002"],
                        "runtime_manifest_hash": probe["runtime_manifest_hash"],
                    },
                    str(artifact_root),
                )
            self.assertEqual(
                "finalization_recovery_required", caught.exception.reason_code
            )
            self.assertTrue(
                any(
                    name.endswith("reviewer-calibration-result.json")
                    for name in replacements
                )
            )
            calibration_root = artifact_root / "calibration"
            for name in (
                "reviewer-calibration.json",
                "reviewer-calibration-result.json",
                ".reviewer-calibration.pending.json",
                ".reviewer-calibration-result.pending.json",
            ):
                self.assertFalse((calibration_root / name).exists(), name)
            self.assertEqual(2, len(log_path.read_text(encoding="utf-8").splitlines()))

    def test_malformed_intent_quarantines_before_model_call(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            first = self._sample_request(
                request_id="sample-1",
                sample_id="sample-001",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, _ = self._invoke(first)
            self.assertEqual(result.returncode, 0)
            intent_path = artifact_root / "samples" / ".sample-001.intent.json"
            intent_path.write_text("{", encoding="utf-8")
            intent_path.chmod(0o600)

            request = self._sample_request(
                request_id="sample-after-malformed-intent",
                sample_id="sample-002",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(request)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 1)

    def test_unresolved_model_call_quarantines_artifact_root(self):
        probe = self._probe()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable, log_path = self._write_fake_codex(root)
            artifact_root = root / "artifacts"
            environment = os.environ.copy()
            environment["FAKE_CODEX_LOG"] = str(log_path)
            for index in (1, 2):
                request = self._sample_request(
                    request_id=f"sample-{index}",
                    sample_id=f"sample-{index:03d}",
                    artifact_root=artifact_root,
                    executable=executable,
                    manifest_hash=probe["runtime_manifest_hash"],
                )
                result, _ = self._invoke(request, environment=environment)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

            (root / "malformed-response").write_text("", encoding="utf-8")
            failed_request = self._sample_request(
                request_id="sample-unresolved",
                sample_id="sample-003",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(failed_request, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "model_call_unresolved")
            self.assertTrue(
                (artifact_root / "sample-ledger" / "sample-003.json").exists()
            )
            unresolved_intent = json.loads(
                (artifact_root / "samples" / ".sample-003.intent.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(unresolved_intent["state"], "model_call_started")
            self.assertFalse((artifact_root / "samples" / "sample-003.json").exists())
            (root / "malformed-response").unlink()
            retry = self._sample_request(
                request_id="sample-after-quarantine",
                sample_id="sample-004",
                artifact_root=artifact_root,
                executable=executable,
                manifest_hash=probe["runtime_manifest_hash"],
            )
            result, response = self._invoke(retry, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")

            finalize = {
                "schema": REQUEST_SCHEMA,
                "request_id": "finalize-quarantined",
                "action": "finalize",
                "artifact_root": str(artifact_root),
                "payload": {
                    "sample_ids": ["sample-001", "sample-002"],
                    "runtime_manifest_hash": probe["runtime_manifest_hash"],
                },
            }
            result, response = self._invoke(finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            finalize["request_id"] = "finalize-quarantined-explicit"
            finalize["payload"]["sample_ids"] = [
                "sample-001",
                "sample-002",
                "sample-003",
            ]
            result, response = self._invoke(finalize, environment=environment)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(response["reason_code"], "artifact_root_quarantined")
            self.assertEqual(len(log_path.read_text(encoding="utf-8").splitlines()), 3)
            self.assertFalse((artifact_root / "calibration").exists())


if __name__ == "__main__":
    unittest.main()
