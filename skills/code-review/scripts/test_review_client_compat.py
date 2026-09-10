#!/usr/bin/env python3
"""Regression tests for version-neutral review-client compatibility."""

from __future__ import annotations

import argparse
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
import review_gate
import kimi_packet_mcp

SPEC = importlib.util.spec_from_file_location(
    "parse_cli_review", SCRIPT_DIR / "parse_cli_review.py"
)
assert SPEC is not None and SPEC.loader is not None
PARSER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PARSER)


class ReviewClientCompatibilityTest(unittest.TestCase):
    def test_gate_attempt_record_preserves_opencode_timeout_receipt(self) -> None:
        result = {"attempts": [], "primary": None, "fallbacks": [], "fallback_attempt_count": 0}
        payload = {
            "status": "inconclusive",
            "reason": "review_native_skill_stream_timeout",
            "reason_code": "timeout",
            "cascade_eligible": True,
            "timeout_diagnostic": {
                "stage": "review",
                "native_owner_skills_requested": True,
                "selected_skill_count": 1,
            },
            "diagnostic_artifacts": {
                "requested": True,
                "retained": True,
                "directory_name": "opencode-review-timeout.fixture",
            },
        }

        attempt = review_gate.record_attempt(result, "opencode", payload)

        self.assertEqual(attempt["reason_code"], "timeout")
        self.assertTrue(attempt["cascade_eligible"])
        self.assertTrue(attempt["timeout_diagnostic"]["native_owner_skills_requested"])
        self.assertTrue(attempt["diagnostic_artifacts"]["retained"])

    def test_opencode_file_option_is_terminated_before_prompt(self) -> None:
        wrapper = (SCRIPT_DIR / "opencode_review.sh").read_text(encoding="utf-8")
        self.assertIn(
            '--format json --file "$prompt_file" \\\n    -- "Review the attached bounded instruction and candidate packet."',
            wrapper,
        )

    def test_kimi_accepts_any_nonempty_version_value(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("candidate\n", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )
            events = [
                {"role": "meta", "type": "system.version", "version": "future"},
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "type": "function",
                            "id": "read-1",
                            "function": {
                                "name": "mcp__code_review_packet__read_packet",
                                "arguments": {
                                    "byte_offset": 0,
                                    "max_bytes": 46_000,
                                },
                            },
                        }
                    ],
                },
                {
                    "role": "tool",
                    "tool_call_id": "read-1",
                    "content": "PACKET_CHUNK 0:10/10\ncandidate\n",
                },
                {"role": "assistant", "content": "NO_BLOCKING_FINDINGS"},
            ]

            text, failure = PARSER.kimi_text(args, events)

            self.assertIsNone(failure)
            self.assertEqual(text, "NO_BLOCKING_FINDINGS")

    def test_kimi_rejects_a_packet_chunk_with_mismatched_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("candidate\n", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )
            events = [
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "type": "function",
                            "id": "read-1",
                            "function": {
                                "name": "mcp__code_review_packet__read_packet",
                                "arguments": {"byte_offset": 0, "max_bytes": 46_000},
                            },
                        }
                    ],
                },
                {
                    "role": "tool",
                    "tool_call_id": "read-1",
                    "content": "PACKET_CHUNK 0:10/10\nCandidate\n",
                },
                {"role": "assistant", "content": "NO_BLOCKING_FINDINGS"},
            ]

            text, failure = PARSER.kimi_text(args, events)

            self.assertIsNone(text)
            self.assertEqual(failure["reason_code"], "invalid_model_output")

    def test_kimi_rejects_noncontiguous_packet_ranges(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("abcdefghij", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )
            events = []
            for index, (start, end) in enumerate(((0, 4), (5, 10)), start=1):
                call_id = f"read-{index}"
                events.extend(
                    [
                        {
                            "role": "assistant",
                            "tool_calls": [
                                {
                                    "type": "function",
                                    "id": call_id,
                                    "function": {
                                        "name": "mcp__code_review_packet__read_packet",
                                        "arguments": {
                                            "byte_offset": start,
                                            "max_bytes": end - start,
                                        },
                                    },
                                }
                            ],
                        },
                        {
                            "role": "tool",
                            "tool_call_id": call_id,
                            "content": f"PACKET_CHUNK {start}:{end}/10\n"
                            + packet.read_text(encoding="utf-8")[start:end],
                        },
                    ]
                )
            events.append({"role": "assistant", "content": "NO_BLOCKING_FINDINGS"})

            text, failure = PARSER.kimi_text(args, events)

            self.assertIsNone(text)
            self.assertEqual(failure["reason_code"], "invalid_model_output")

    def test_kimi_accepts_exact_end_confirmation_after_full_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("candidate\n", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )
            events = [
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "type": "function",
                            "id": "read-1",
                            "function": {
                                "name": "mcp__code_review_packet__read_packet",
                                "arguments": {"byte_offset": 0, "max_bytes": 46_000},
                            },
                        }
                    ],
                },
                {
                    "role": "tool",
                    "tool_call_id": "read-1",
                    "content": "PACKET_CHUNK 0:10/10\ncandidate\n",
                },
                {
                    "role": "assistant",
                    "tool_calls": [
                        {
                            "type": "function",
                            "id": "read-eof",
                            "function": {
                                "name": "mcp__code_review_packet__read_packet",
                                "arguments": {"byte_offset": 10, "max_bytes": 46_000},
                            },
                        }
                    ],
                },
                {
                    "role": "tool",
                    "tool_call_id": "read-eof",
                    "content": "PACKET_CHUNK 10:10/10\n",
                },
                {"role": "assistant", "content": "NO_BLOCKING_FINDINGS"},
            ]

            text, failure = PARSER.kimi_text(args, events)

            self.assertIsNone(failure)
            self.assertEqual(text, "NO_BLOCKING_FINDINGS")

    def test_kimi_rejects_unknown_nonempty_metadata_container(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("candidate\n", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )
            text, failure = PARSER.kimi_text(
                args,
                [
                    {
                        "role": "meta",
                        "type": "future.capabilities",
                        "capabilities": ["shell"],
                    }
                ],
            )

            self.assertIsNone(text)
            self.assertEqual(failure["reason_code"], "tool_boundary_violation")

    def test_kimi_rejects_unknown_scalar_metadata(self) -> None:
        event = {"role": "meta", "type": "future.notice", "value": "text"}

        self.assertFalse(PARSER.is_safe_kimi_metadata_event(event))

    def test_kimi_bounds_version_metadata_size(self) -> None:
        event = {"role": "meta", "type": "system.version", "version": "v" * 257}

        self.assertFalse(PARSER.is_safe_kimi_metadata_event(event))

    def test_kimi_accepts_complete_resume_hint_only(self) -> None:
        event = {
            "role": "meta",
            "type": "session.resume_hint",
            "session_id": "session-1",
            "command": "kimi -r session-1",
            "content": "resume",
        }

        self.assertEqual(PARSER.safe_kimi_metadata_kind(event), "resume")
        del event["session_id"]
        self.assertIsNone(PARSER.safe_kimi_metadata_kind(event))

    def test_kimi_distinguishes_call_container_from_call_boundary_errors(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            packet = Path(temp_dir) / "packet.txt"
            packet.write_text("candidate\n", encoding="utf-8")
            args = argparse.Namespace(
                client="kimi",
                mode="review",
                reviewer_family="moonshot",
                provider="kimi",
                model="configured-model",
                packet=str(packet),
            )

            _, container_failure = PARSER.kimi_text(
                args, [{"role": "assistant", "tool_calls": "invalid"}]
            )
            _, call_failure = PARSER.kimi_text(
                args,
                [
                    {
                        "role": "assistant",
                        "tool_calls": [
                            {
                                "type": "function",
                                "function": {
                                    "name": "mcp__code_review_packet__read_packet"
                                },
                            }
                        ],
                    }
                ],
            )

            self.assertEqual(container_failure["reason_code"], "invalid_model_output")
            self.assertEqual(call_failure["reason_code"], "tool_boundary_violation")

    def test_kimi_inline_delivery_succeeds_without_tools(self) -> None:
        args = argparse.Namespace(
            client="kimi",
            mode="review",
            reviewer_family="moonshot",
            provider="kimi-cli",
            model="",
        )
        events = [
            {"role": "meta", "type": "system.version", "version": "future"},
            {"role": "assistant", "content": "NO_BLOCKING_FINDINGS"},
        ]

        text, failure = PARSER.kimi_inline_text(args, events)

        self.assertIsNone(failure)
        self.assertEqual(text, "NO_BLOCKING_FINDINGS")

    def test_kimi_inline_delivery_rejects_any_tool_call(self) -> None:
        args = argparse.Namespace(
            client="kimi",
            mode="review",
            reviewer_family="moonshot",
            provider="kimi-cli",
            model="",
        )
        events = [
            {
                "role": "assistant",
                "tool_calls": [
                    {
                        "type": "function",
                        "id": "read-1",
                        "function": {"name": "Read", "arguments": {}},
                    }
                ],
            }
        ]

        _, failure = PARSER.kimi_inline_text(args, events)

        self.assertEqual(failure["reason_code"], "tool_boundary_violation")

    def test_kimi_inline_schema_drift_can_cascade(self) -> None:
        args = argparse.Namespace(
            client="kimi",
            mode="review",
            reviewer_family="moonshot",
            provider="kimi-cli",
            model="",
        )
        events = [
            {
                "role": "assistant",
                "content": "NO_BLOCKING_FINDINGS",
                "tool_calls": None,
            }
        ]

        _, failure = PARSER.kimi_inline_text(args, events)

        self.assertEqual(failure["reason_code"], "invalid_model_output")
        self.assertTrue(failure["cascade_eligible"])

    def test_kimi_inline_requires_terminal_packet_receipt(self) -> None:
        args = argparse.Namespace(
            client="kimi",
            mode="review",
            reviewer_family="moonshot",
            provider="kimi-cli",
            model="",
            packet_receipt="KIMI_PACKET_RECEIPT_expected",
        )

        text, failure = PARSER.kimi_inline_text(
            args,
            [
                {
                    "role": "assistant",
                    "content": "KIMI_PACKET_RECEIPT_expected\nNO_BLOCKING_FINDINGS",
                }
            ],
        )

        self.assertIsNone(failure)
        self.assertEqual(text, "NO_BLOCKING_FINDINGS")

    def test_kimi_bounds_inline_argv_exposure_and_file_backs_large_packets(self) -> None:
        wrapper = (SCRIPT_DIR / "kimi_review.sh").read_text(encoding="utf-8")

        self.assertIn('. "$SCRIPT_DIR/normalize_review_timeout.sh"', wrapper)
        self.assertIn('TIMEOUT="$(normalize_review_timeout "$TIMEOUT")"', wrapper)
        self.assertIn("visible in process argv", wrapper)
        self.assertIn("MAX_INLINE_PROMPT_BYTES=16000", wrapper)
        self.assertIn('[ "$FORMAL_TIMEOUT" -le 120 ] || FORMAL_TIMEOUT=120', wrapper)
        self.assertIn("PACKET_DELIVERY=mcp", wrapper)
        self.assertNotIn("PACKET_DELIVERY=agent-file", wrapper)
        self.assertIn('--agent-file "$AGENT_FILE"', wrapper)
        self.assertIn("mcp__code_review_packet__read_packet", wrapper)

    def test_every_wrapper_guards_the_shared_timeout_normalizer(self) -> None:
        for wrapper_name in (
            "claude_review.sh",
            "codex_review.sh",
            "kimi_review.sh",
            "opencode_review.sh",
        ):
            with self.subTest(wrapper=wrapper_name):
                wrapper = (SCRIPT_DIR / wrapper_name).read_text(encoding="utf-8")
                if wrapper_name == "claude_review.sh":
                    guard = '[ -f "$script_dir/normalize_review_timeout.sh" ]'
                    source = '. "$script_dir/normalize_review_timeout.sh"'
                    missing_contract = (
                        'emit_inconclusive_payload "Claude review helper missing: '
                        'normalize_review_timeout.sh" local_tool_failure false '
                        "stop_reviewer_lane"
                    )
                    missing_contracts = (missing_contract,)
                else:
                    guard = '[ -f "$SCRIPT_DIR/normalize_review_timeout.sh" ]'
                    source = '. "$SCRIPT_DIR/normalize_review_timeout.sh"'
                    missing_contracts = (
                        "timeout_normalizer_missing",
                        "local_tool_failure false",
                    )
                self.assertIn(guard, wrapper)
                for missing_contract in missing_contracts:
                    self.assertIn(missing_contract, wrapper)
                self.assertLess(wrapper.index(guard), wrapper.index(source))

    def test_every_wrapper_rejects_below_minimum_timeout_at_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            opencode = Path(temp_dir) / "opencode"
            opencode.write_text("#!/bin/sh\nexit 99\n", encoding="utf-8")
            opencode.chmod(0o755)
            environment = {**os.environ, "PATH": f"{temp_dir}:{os.environ['PATH']}"}
            for wrapper_name in (
                "claude_review.sh",
                "codex_review.sh",
                "kimi_review.sh",
                "opencode_review.sh",
            ):
                with self.subTest(wrapper=wrapper_name):
                    command = ["bash", str(SCRIPT_DIR / wrapper_name)]
                    if wrapper_name == "claude_review.sh":
                        command.append("review")
                    elif wrapper_name == "opencode_review.sh":
                        command.extend(("--implementer-family", "openai"))
                    command.extend(("--timeout", "4"))
                    completed = subprocess.run(
                        command,
                        check=False,
                        capture_output=True,
                        text=True,
                        env=environment,
                    )
                    self.assertEqual(completed.returncode, 2, completed.stderr)
                    payload = json.loads(completed.stdout)
                    self.assertEqual(payload["status"], "inconclusive")
                    self.assertEqual(payload["reason_code"], "invalid_input")
                    expected_reason = (
                        "--timeout must be an integer of at least 5 seconds"
                        if wrapper_name == "claude_review.sh"
                        else "invalid_timeout"
                    )
                    self.assertEqual(payload["reason"], expected_reason)
                    eligibility = payload.get(
                        "fallback_eligible", payload.get("cascade_eligible")
                    )
                    self.assertFalse(eligibility)


class CodexPacketAuditTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.packet = Path(temporary.name) / "packet.txt"
        self.packet.write_text("candidate\n", encoding="utf-8")
        result = Path(temporary.name) / "result.txt"
        result.write_text("NO_BLOCKING_FINDINGS\n", encoding="utf-8")
        self.digest = hashlib.sha256(self.packet.read_bytes()).hexdigest()
        self.args = argparse.Namespace(
            client="codex",
            mode="review",
            reviewer_family="openai",
            provider="codex-cli",
            model="",
            result_file=str(result),
            packet=str(self.packet),
            packet_sha256=self.digest,
        )

    @staticmethod
    def completed_events(*items: dict) -> list[dict]:
        return [
            {"type": "thread.started", "thread_id": "synthetic-review"},
            {"type": "turn.started"},
            *items,
            {
                "type": "item.completed",
                "item": {
                    "id": "verdict",
                    "type": "agent_message",
                    "text": "NO_BLOCKING_FINDINGS",
                },
            },
            {"type": "turn.completed"},
        ]

    @staticmethod
    def read_event() -> dict:
        return {
            "type": "item.completed",
            "item": {
                "id": "read-1",
                "type": "mcp_tool_call",
                "server": "code_review_packet",
                "tool": "read_packet",
                "arguments": {"byte_offset": 0, "max_bytes": 46_000},
                "status": "completed",
                "result": {
                    "content": [
                        {"type": "text", "text": "PACKET_CHUNK 0:10/10\ncandidate\n"}
                    ],
                    "structured_content": None,
                },
                "error": None,
            },
        }

    def assert_inconclusive(self, events: list[dict], reason: str | None = None) -> None:
        failure = PARSER.audit_codex(self.args, events)
        self.assertIsNotNone(failure)
        self.assertEqual(failure["status"], "inconclusive")
        if reason is not None:
            self.assertEqual(failure["reason_code"], reason)

    def test_codex_packet_accepts_verified_read(self) -> None:
        failure = PARSER.audit_codex(
            self.args, self.completed_events(self.read_event())
        )

        self.assertIsNone(failure)

    def test_codex_packet_accepts_verified_search(self) -> None:
        event = self.read_event()
        arguments = {"query": "candidate", "byte_offset": 0, "limit": 2}
        response = kimi_packet_mcp.search_packet(self.packet, self.digest, arguments)
        self.assertFalse(response["isError"])
        event["item"].update(tool="search_packet", arguments=arguments)
        event["item"]["result"]["content"] = response["content"]

        failure = PARSER.audit_codex(self.args, self.completed_events(event))

        self.assertIsNone(failure)

    def test_codex_packet_accepts_started_updated_completed_read(self) -> None:
        completed = self.read_event()
        started = copy.deepcopy(completed)
        started["type"] = "item.started"
        started["item"].update(status="in_progress", result=None)
        updated = copy.deepcopy(started)
        updated["type"] = "item.updated"

        failure = PARSER.audit_codex(
            self.args, self.completed_events(started, updated, completed)
        )

        self.assertIsNone(failure)

    def test_codex_inline_accepts_completion_without_tools(self) -> None:
        self.args.packet = None
        self.args.packet_sha256 = None

        self.assertIsNone(PARSER.audit_codex(self.args, self.completed_events()))

    def test_codex_inline_rejects_packet_tool_without_binding(self) -> None:
        self.args.packet = None
        self.args.packet_sha256 = None

        self.assert_inconclusive(
            self.completed_events(self.read_event()), "tool_boundary_violation"
        )

    def test_codex_packet_rejects_unapproved_tool_surfaces(self) -> None:
        read = self.read_event()["item"]
        items = (
            {**read, "server": "other_packet_server"},
            {**read, "tool": "write_packet"},
            {**read, "tool": "read_file"},
            {
                "id": "shell-1",
                "type": "command_execution",
                "command": "printf synthetic",
                "aggregated_output": "synthetic",
                "status": "completed",
                "exit_code": 0,
            },
        )
        for item in items:
            with self.subTest(item_type=item["type"], tool=item.get("tool")):
                event = {"type": "item.completed", "item": item}
                self.assert_inconclusive(
                    self.completed_events(event), "tool_boundary_violation"
                )

    def test_codex_packet_rejects_forged_read_and_search_results(self) -> None:
        for tool, arguments in (
            ("read_packet", {"byte_offset": 0, "max_bytes": 46_000}),
            ("search_packet", {"query": "candidate", "byte_offset": 0, "limit": 2}),
        ):
            with self.subTest(tool=tool):
                event = self.read_event()
                event["item"].update(tool=tool, arguments=arguments)
                event["item"]["result"]["content"] = [
                    {"type": "text", "text": "forged packet contents"}
                ]
                self.assert_inconclusive(self.completed_events(event))

    def test_codex_packet_rejects_changed_digest_bound_file(self) -> None:
        event = self.read_event()
        self.packet.write_text("Candidate\n", encoding="utf-8")

        self.assert_inconclusive(self.completed_events(event))

    def test_codex_packet_rejects_missing_read_completion(self) -> None:
        event = self.read_event()
        event["type"] = "item.started"
        event["item"].update(status="in_progress", result=None)

        self.assert_inconclusive(self.completed_events(event))

    def test_codex_packet_rejects_malformed_and_extra_arguments(self) -> None:
        cases = (
            ("read_packet", None),
            ("read_packet", []),
            ("read_packet", {"byte_offset": 0}),
            ("read_packet", {"byte_offset": 0, "max_bytes": 46_000, "path": "other"}),
            ("search_packet", {"query": "candidate", "limit": 2}),
            (
                "search_packet",
                {"query": "candidate", "byte_offset": 0, "limit": 2, "path": "other"},
            ),
        )
        for tool, arguments in cases:
            with self.subTest(tool=tool, arguments=arguments):
                event = self.read_event()
                event["item"].update(tool=tool, arguments=arguments)
                self.assert_inconclusive(self.completed_events(event))

    def test_codex_packet_accepts_verified_argument_error_then_retry(self) -> None:
        retry = self.read_event()
        retry["item"]["id"] = "read-retry"
        error = self.read_event()
        error["item"]["arguments"] = {"byte_offset": 11, "max_bytes": 46_000}
        error["item"]["result"]["content"] = [
            {"type": "text", "text": "packet chunk starts beyond end"}
        ]

        failure = PARSER.audit_codex(self.args, self.completed_events(error, retry))

        self.assertIsNone(failure)

    def test_codex_packet_transport_failure_stays_inconclusive_after_retry(self) -> None:
        for status, result, error in (
            ("failed", None, {"message": "transport closed"}),
            ("completed", None, {"message": "transport closed"}),
            ("completed", None, None),
        ):
            with self.subTest(status=status, error=error):
                failed = self.read_event()
                failed["item"].update(status=status, result=result, error=error)
                retry = self.read_event()
                retry["item"]["id"] = "read-retry"
                self.assert_inconclusive(self.completed_events(failed, retry))


class CompletionFindingDispositionTest(unittest.TestCase):
    """Exercise real receipt and completion validation without external models."""

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.packet = self.root / "candidate.patch"
        self.packet.write_text(
            "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n",
            encoding="utf-8",
        )
        self.plan = self.root / "review-plan.json"
        self.write_json(self.plan, {
            "intent": "Preserve bounded completion after source refutation.",
            "acceptance": ["Every finding occurrence is resolved without adding review authority."],
            "self_review": [
                {"concern": concern,
                 "conclusion": f"The synthetic completion fixture preserves {concern} boundaries.",
                 "evidence_refs": ["fixture"]}
                for concern in ("correctness", "safety", "failure_paths", "tests_evidence", "compatibility", "claim_strength")
            ],
            "evidence": [{"id": "fixture", "result": "Synthetic exact-candidate completion and history fixture."}],
        })
        self.dispositions = self.root / "dispositions.json"
        self.record_receipts()

    def record_receipts(self, final_status: str = "findings", *,
                        duplicate_findings: bool = False, distinct_finding: bool = False) -> None:
        self.final_review_status = final_status
        self.duplicate_findings = duplicate_findings
        self.distinct_finding = distinct_finding
        self.provider_calls: list[list[str]] = []
        self.profiles: list[dict] = []
        self.receipt_paths = [self.root / "review.json", self.root / "challenge.json"]
        self.receipts = []
        for index, mode in enumerate(("review", "challenge"), 1):
            extra = ["--review-chain-id", "source-refutation-fixture",
                     "--autonomous-review-index", str(index)]
            if mode == "challenge":
                extra.extend(["--challenge-index", "1", "--focus", "source-boundary",
                              "--prior-review-result-file", str(self.receipt_paths[0])])
            code, result = self.invoke(mode, extra)
            self.assertEqual(code, 0, result)
            self.assertEqual(result["status"], "findings" if mode == "review" else final_status, result)
            self.receipts.append(result)
            self.write_json(self.receipt_paths[index - 1], result)
        self.original_receipt_bytes = [path.read_bytes() for path in self.receipt_paths]
        self.refresh_dispositions()

    @staticmethod
    def write_json(path: Path, value: object) -> None:
        path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True), encoding="utf-8")

    @staticmethod
    def digest(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    @staticmethod
    def finding_digest(finding: dict) -> str:
        canonical = json.dumps(finding, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(canonical.encode("utf-8")).hexdigest()

    def wrapper_result(self, command: list[str], **kwargs: object) -> subprocess.CompletedProcess:
        # Only the provider boundary is replaced. Packet, profile, chain and
        # completion validation execute normally; no subprocess is launched.
        self.assertTrue(command[0].endswith("kimi_review.sh"), command[0])
        self.provider_calls.append(list(command))
        profile_path = Path(command[command.index("--review-profile-file") + 1])
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
        self.profiles.append(profile)
        mode = command[command.index("--mode") + 1]
        payload = {
            "reviewer": "kimi", "reviewer_family": "moonshot", "provider": "kimi-cli",
            "model": "synthetic", "mode": mode, "status": "findings",
            "native_skill_binding": "established",
            "concern_results": [
                {"concern": item["id"], "conclusion": f"Checked {item['id']} against the frozen candidate."}
                for item in profile["required_concerns"]
            ],
            "findings": [{"severity": "P1", "file": "x", "line": 1,
                          "failure_path": "Synthetic missing guard before an action.",
                          "smallest_fix": "Check the guard before the synthetic action."}],
        }
        if mode == "challenge" and self.final_review_status == "passed":
            payload.update(status="passed", findings=[])
        elif self.duplicate_findings:
            payload["findings"].append(dict(reversed(list(payload["findings"][0].items()))))
            if self.distinct_finding:
                payload["findings"].append({**payload["findings"][0],
                                            "failure_path": "A distinct synthetic failure on the same line."})
        return subprocess.CompletedProcess(command, 0, json.dumps(payload).encode("utf-8"), b"")

    def arguments(self, mode: str) -> list[str]:
        return ["--mode", mode, "--cwd", str(self.root), "--diff-file", str(self.packet),
                "--implementer-family", "openai", "--review-plan-file", str(self.plan),
                "--challenge-budget", "1"]

    def invoke(self, mode: str, extra: list[str]) -> tuple[int, dict]:
        output = io.StringIO()
        with (mock.patch.object(review_gate, "run", side_effect=self.wrapper_result),
              mock.patch.object(review_gate, "client_order", return_value=["kimi"]),
              contextlib.redirect_stdout(output)):
            code = review_gate.main(self.arguments(mode) + extra)
        return code, json.loads(output.getvalue())

    def refresh_dispositions(self) -> dict:
        hashes = [self.digest(path) for path in self.receipt_paths]
        receipts = [json.loads(path.read_text(encoding="utf-8")) for path in self.receipt_paths]
        manifest = {
            "schema_version": 1,
            "candidate_sha256": receipts[-1]["candidate_sha256"],
            "review_result_sha256": hashes,
            "dispositions": [
                {"receipt_sha256": receipt_hash,
                 "finding_sha256": self.finding_digest(finding),
                 "disposition": "source_refuted",
                 "evidence": ["Synthetic source x:1 checks the guard before the action; the reported path is unreachable."]}
                for receipt_hash, receipt in zip(hashes, receipts)
                for finding in {self.finding_digest(item): item for item in receipt["findings"]}.values()
            ],
        }
        self.write_json(self.dispositions, manifest)
        return manifest

    def complete(self, *, include_prior: bool = True) -> tuple[int, dict]:
        extra = ["--completion-review-result-file", str(self.receipt_paths[-1]),
                 "--finding-dispositions-file", str(self.dispositions)]
        if include_prior:
            extra.extend(["--prior-review-result-file", str(self.receipt_paths[0])])
        result = self.invoke("complete", extra)
        self.assertEqual(len(self.provider_calls), 2, "completion must never call a reviewer")
        return result

    def assert_rejected(self, *, include_prior: bool = True) -> dict:
        code, result = self.complete(include_prior=include_prior)
        self.assertEqual(code, 2, result)
        self.assertEqual(result["status"], "inconclusive", result)
        self.assertTrue(result["completion_gated"], result)
        return result

    def test_source_refuted_findings_validate_bound_dispositions(self) -> None:
        # Keep the narrower validator exercised independently of CLI parsing.
        args = review_gate.build_parser().parse_args(self.arguments("complete") + [
            "--completion-review-result-file", str(self.receipt_paths[-1])])
        args.finding_dispositions_file = str(self.dispositions)
        args.prior_review_result_file = [str(self.receipt_paths[0])]
        result_hash, prior, metadata = review_gate.validate_finding_dispositions(
            args, self.receipts[-1]["candidate_sha256"], self.profiles[-1])
        self.assertEqual(result_hash, self.digest(self.receipt_paths[-1]))
        self.assertEqual(prior["findings"], self.receipts[-1]["findings"])
        self.assertEqual(metadata["completion_basis"], "source_refuted_findings")

    def test_two_refuted_rounds_complete_without_new_review_or_history_reset(self) -> None:
        code, result = self.complete()
        self.assertEqual(code, 0, result)
        self.assertEqual(result["status"], "passed")
        self.assertFalse(result["completion_gated"])
        self.assertEqual(result["completion_basis"], "source_refuted_findings")
        self.assertEqual(result["finding_dispositions_sha256"], self.digest(self.dispositions))
        manifest = json.loads(self.dispositions.read_text(encoding="utf-8"))
        # A repeated finding in a later round is a separate occurrence even
        # when its canonical finding hash is identical.
        self.assertEqual(len({item["finding_sha256"] for item in manifest["dispositions"]}), 1)
        self.assertEqual(len({item["receipt_sha256"] for item in manifest["dispositions"]}), 2)
        self.assertEqual(result["resolved_finding_occurrences"], [
            {key: item[key] for key in ("receipt_sha256", "finding_sha256")}
            for item in manifest["dispositions"]])
        for field in ("review_chain_id", "review_scope_sha256", "prior_review_result_sha256",
                      "prior_challenge_focuses", "autonomous_review_budget", "autonomous_review_index",
                      "autonomous_reviews_remaining"):
            self.assertEqual(result[field], self.receipts[-1][field], field)
        self.assertEqual(result["autonomous_review_budget"], 2)
        self.assertEqual(result["autonomous_review_index"], 2)
        self.assertEqual(result["autonomous_reviews_remaining"], 0)
        self.assertFalse(result["autonomous_review_allowed"])
        self.assertEqual(result["next_action"], "complete")
        self.assertEqual([path.read_bytes() for path in self.receipt_paths], self.original_receipt_bytes)

    def test_dispositions_file_is_required_and_must_exist(self) -> None:
        code, result = self.invoke("complete", [
            "--completion-review-result-file", str(self.receipt_paths[-1])])
        self.assertEqual(code, 2, result)
        self.assertTrue(result["completion_gated"], result)
        self.dispositions.unlink()
        self.assert_rejected()

    def test_identical_findings_share_identity_without_rewriting_receipts(self) -> None:
        for final_status in ("findings", "passed"):
            with self.subTest(final_status=final_status):
                self.record_receipts(final_status, duplicate_findings=True)
                self.assertEqual(len(self.receipts[0]["findings"]), 2)
                code, result = self.complete()
                self.assertEqual(code, 0, result)
                self.assertEqual(len(result["resolved_finding_occurrences"]),
                                 2 if final_status == "findings" else 1)
                self.assertEqual([path.read_bytes() for path in self.receipt_paths],
                                 self.original_receipt_bytes)

    def test_duplicate_identity_never_hides_a_distinct_finding_or_round(self) -> None:
        self.record_receipts(duplicate_findings=True, distinct_finding=True)
        manifest = self.refresh_dispositions()
        self.assertEqual([len(row["findings"]) for row in self.receipts], [3, 3])
        self.assertEqual(len(manifest["dispositions"]), 4)
        code, result = self.complete()
        self.assertEqual(code, 0, result)
        self.assertEqual(len(result["resolved_finding_occurrences"]), 4)
        for missing in range(4):
            with self.subTest(missing_occurrence=missing):
                incomplete = copy.deepcopy(manifest)
                del incomplete["dispositions"][missing]
                self.write_json(self.dispositions, incomplete)
                self.assert_rejected()

    def test_passed_final_still_requires_valid_historical_finding_dispositions(self) -> None:
        self.record_receipts(final_status="passed")
        code, result = self.complete()
        self.assertEqual(code, 0, result)
        self.assertEqual(result["completion_basis"], "source_refuted_findings")
        self.assertEqual(len(result["resolved_finding_occurrences"]), 1)
        self.assertEqual(result["resolved_finding_occurrences"][0]["receipt_sha256"],
                         self.digest(self.receipt_paths[0]))
        manifest = self.refresh_dispositions()
        manifest["dispositions"][0]["disposition"] = "accepted_risk"
        self.write_json(self.dispositions, manifest)
        rejected = self.assert_rejected()
        self.assertEqual(rejected["next_action"], "resolve_review_findings")
        manifest["dispositions"] = []
        self.write_json(self.dispositions, manifest)
        self.assert_rejected()

    def test_every_historical_finding_occurrence_must_be_covered_once(self) -> None:
        original = self.refresh_dispositions()
        for missing in (0, 1):
            with self.subTest(missing_round=missing):
                manifest = copy.deepcopy(original)
                del manifest["dispositions"][missing]
                self.write_json(self.dispositions, manifest)
                self.assert_rejected()
        manifest = copy.deepcopy(original)
        manifest["dispositions"].append(copy.deepcopy(manifest["dispositions"][0]))
        self.write_json(self.dispositions, manifest)
        self.assert_rejected()

    def test_disposition_candidate_receipt_and_finding_hashes_are_bound(self) -> None:
        original = self.refresh_dispositions()
        for field in ("candidate_sha256", "review_result_sha256", "receipt_sha256", "finding_sha256"):
            with self.subTest(field=field):
                manifest = copy.deepcopy(original)
                if field == "review_result_sha256":
                    manifest[field][0] = "f" * 64
                elif field == "candidate_sha256":
                    manifest[field] = "f" * 64
                else:
                    manifest["dispositions"][0][field] = "f" * 64
                self.write_json(self.dispositions, manifest)
                self.assert_rejected()

    def test_unresolved_or_accepted_risk_cannot_complete(self) -> None:
        original = self.refresh_dispositions()
        for disposition in ("unresolved", "accepted_risk", "accepted_tradeoff", "needs_human_decision"):
            with self.subTest(disposition=disposition):
                manifest = copy.deepcopy(original)
                manifest["dispositions"][0]["disposition"] = disposition
                self.write_json(self.dispositions, manifest)
                self.assert_rejected()

    def test_source_refutation_requires_bounded_nonempty_evidence(self) -> None:
        original = self.refresh_dispositions()
        for evidence in (None, [], [""], ["  \n"], "source x:1", [123], ["x" * 100_000]):
            with self.subTest(evidence_type=type(evidence).__name__, size=len(str(evidence))):
                manifest = copy.deepcopy(original)
                if evidence is None:
                    del manifest["dispositions"][0]["evidence"]
                else:
                    manifest["dispositions"][0]["evidence"] = evidence
                self.write_json(self.dispositions, manifest)
                self.assert_rejected()

    def test_evidence_strings_match_downstream_normalization_and_text_boundary(self) -> None:
        original = self.refresh_dispositions()
        for text in (" leading space", "trailing space ", "line\nbreak", "tab\tinside",
                     "NUL\0inside", "DEL\x7finside", "C1\x85inside", "line\u2028separator",
                     "paragraph\u2029separator", "zero\u200bwidth", "bidi\u202econtrol", "bad\ud800unicode"):
            with self.subTest(text=ascii(text)):
                manifest = copy.deepcopy(original)
                manifest["dispositions"][0]["evidence"] = [text]
                # Escaped JSON can encode an unpaired surrogate even though the
                # decoded string cannot be encoded as valid UTF-8 text.
                self.dispositions.write_text(json.dumps(manifest), encoding="utf-8")
                self.assert_rejected()

    def test_changed_candidate_cannot_use_previous_refutations(self) -> None:
        self.packet.write_text(self.packet.read_text(encoding="utf-8").replace("+b\n", "+c\n"), encoding="utf-8")
        self.assert_rejected()

    def test_stale_historical_candidate_cannot_use_current_refutations(self) -> None:
        historical = copy.deepcopy(self.receipts[0])
        historical["candidate_sha256"] = historical["packet_sha256"] = "f" * 64
        self.write_json(self.receipt_paths[0], historical)
        final = copy.deepcopy(self.receipts[-1])
        final["prior_review_result_sha256"][0] = self.digest(self.receipt_paths[0])
        self.write_json(self.receipt_paths[-1], final)
        # Refresh every outer receipt reference so stale candidate rejection
        # cannot be attributed to an incidental raw-receipt hash mismatch.
        self.refresh_dispositions()
        self.assert_rejected()

    def test_inconclusive_receipt_cannot_be_refuted_into_a_pass(self) -> None:
        for index in (0, 1):
            with self.subTest(round=index):
                for path, raw in zip(self.receipt_paths, self.original_receipt_bytes):
                    path.write_bytes(raw)
                receipt = json.loads(self.receipt_paths[index].read_text(encoding="utf-8"))
                receipt["status"] = "inconclusive"
                self.write_json(self.receipt_paths[index], receipt)
                if index == 0:
                    final = copy.deepcopy(self.receipts[-1])
                    final["prior_review_result_sha256"][0] = self.digest(self.receipt_paths[0])
                    self.write_json(self.receipt_paths[-1], final)
                self.refresh_dispositions()
                self.assert_rejected()

    def test_forged_or_missing_history_cannot_complete(self) -> None:
        self.assert_rejected(include_prior=False)
        receipt = copy.deepcopy(self.receipts[-1])
        receipt["prior_review_result_sha256"][0] = "f" * 64
        self.write_json(self.receipt_paths[-1], receipt)
        self.refresh_dispositions()
        self.assert_rejected()

    def test_original_receipt_metadata_must_match_the_external_round(self) -> None:
        for index in (0, 1):
            for field in ("review_state", "human_decision_required", "gate_required", "gate_triggers"):
                with self.subTest(round=index, field=field):
                    for path, raw in zip(self.receipt_paths, self.original_receipt_bytes):
                        path.write_bytes(raw)
                    receipt = copy.deepcopy(self.receipts[index])
                    if field == "review_state":
                        receipt[field] = "reviewed"
                    elif field == "human_decision_required":
                        receipt[field] = not receipt[field]
                    elif field == "gate_required":
                        receipt["self_review_gate"]["required"] = False
                    else:
                        receipt["self_review_gate"]["required_triggers"] = []
                    self.write_json(self.receipt_paths[index], receipt)
                    if index == 0:
                        final = copy.deepcopy(self.receipts[-1])
                        final["prior_review_result_sha256"][0] = self.digest(self.receipt_paths[0])
                        self.write_json(self.receipt_paths[-1], final)
                    self.refresh_dispositions()
                    self.assert_rejected()

    def test_receipt_order_is_part_of_the_disposition_binding(self) -> None:
        manifest = self.refresh_dispositions()
        manifest["review_result_sha256"].reverse()
        self.write_json(self.dispositions, manifest)
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
