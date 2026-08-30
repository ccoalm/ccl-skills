#!/usr/bin/env python3
"""Regression tests for version-neutral review-client compatibility."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
import review_gate

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


if __name__ == "__main__":
    unittest.main()
