#!/usr/bin/env python3
"""Regression tests for version-neutral review-client compatibility."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
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
                                "name": "Read",
                                "arguments": {
                                    "path": str(packet),
                                    "line_offset": 1,
                                    "n_lines": 1,
                                },
                            },
                        }
                    ],
                },
                {"role": "tool", "tool_call_id": "read-1", "content": "1\tcandidate"},
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
                            {"type": "function", "function": {"name": "Read"}}
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

    def test_kimi_bounds_inline_argv_exposure(self) -> None:
        wrapper = (SCRIPT_DIR / "kimi_review.sh").read_text(encoding="utf-8")

        self.assertIn('[ "$TIMEOUT" -le 120 ] || TIMEOUT=120', wrapper)
        self.assertIn("visible in this process argv", wrapper)
        self.assertIn("MAX_INLINE_PROMPT_BYTES=16000", wrapper)


if __name__ == "__main__":
    unittest.main()
