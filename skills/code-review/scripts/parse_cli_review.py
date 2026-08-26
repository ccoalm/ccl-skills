#!/usr/bin/env python3
"""Fail-closed parser for dedicated Kimi and Codex CLI review wrappers."""

from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import re
from typing import Any

from concern_excerpt import bounded_reason_detail, concern_fields
from kimi_packet_mcp import MAX_CHUNK_BYTES


FAMILIES = {
    "anthropic": "claude",
    "claude": "claude",
    "codex": "openai",
    "deepseek": "deepseek",
    "gemini": "gemini",
    "google": "gemini",
    "kimi": "moonshot",
    "moonshot": "moonshot",
    "openai": "openai",
    "grok": "grok",
    "xai": "grok",
    "groq": "groq",
    "mistral": "mistral",
}
FINDING_RE = re.compile(r"^(P[0-2])\s+(\S+):(\d+)\s+(.+?)\s+\|\s+(.+)$")
CONCERN_RESULT_RE = re.compile(
    r"^CHECK\s+([a-z][a-z0-9_]*)\s+\|\s+(.+)$", re.IGNORECASE
)
CODEX_STREAM_GAP_RE = re.compile(
    r"^in-process app-server event stream lagged; dropped [1-9]\d* events?$",
    re.IGNORECASE,
)
CODEX_BENIGN_ERROR_ITEMS = {
    "Skill descriptions were shortened to fit the 2% skills context budget. "
    "Codex can still see every skill, but some descriptions are shorter. "
    "Disable unused skills or plugins to leave more room for the rest."
}
# The skills-context-budget notice is advisory, and its wording drifts with the
# CLI: an earlier release said "the 2% skills context budget", a later one dropped
# the number. The exact-sentence set above could not see that, so every Codex
# review lane died on `invalid_model_output` after a routine upstream release —
# with a complete verdict already in hand. Per scripts/AGENTS.md, match the
# invariant claim, not the release's phrasing. The anchor plus the required
# subject keep this from swallowing a real error item.
# Both ends are anchored and the tail is bounded: matching only the prefix would
# let a crafted error item append arbitrary content and still be waved through.
# Only the release-variable numeric slot is optional, so this does not re-pin the
# wording that broke last time.
# A free tail let a real fault ride along behind the benign prefix, so the
# advisory's own continuation is required. That does re-pin some vocabulary — the
# trade is deliberate: an upstream reword now fails LOUDLY as an item-level error
# whose text is carried in `client_diagnostic`, which is exactly the silent
# failure this slice removed. Only the release-variable numeric slot stays free.
CODEX_BENIGN_ERROR_RES = (
    re.compile(
        r"^skill descriptions were shortened to fit the (?:\d{1,3}% )?"
        r"skills context budget\.\s*"
        r"codex can still see every skill, but some descriptions are shorter\.\s*"
        r"disable unused skills or plugins to leave more room for the rest\.?$",
        re.IGNORECASE,
    ),
)


def is_benign_codex_error(message: object) -> bool:
    if not isinstance(message, str):
        return False
    normalized = " ".join(message.split())
    if normalized in CODEX_BENIGN_ERROR_ITEMS:
        return True
    return any(pattern.search(normalized) for pattern in CODEX_BENIGN_ERROR_RES)
CODEX_HOOK_TRUST_WARNING = (
    "`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run "
    "without review for this invocation."
)
TOOL_ACTIVITY_KEYS = {"function_call", "function_calls", "tool_call", "tool_calls"}
TOOL_ACTIVITY_TYPES = {"function_call", "tool_call", "tool_use"}
KIMI_ASSISTANT_KEYS = {"role", "content", "tool_calls"}
KIMI_TOOL_KEYS = {"role", "content", "tool_call_id"}
KIMI_RETRY_KEYS = {
    "role",
    "type",
    "failed_attempt",
    "next_attempt",
    "max_attempts",
    "delay_ms",
    "error_name",
    "error_message",
    "status_code",
}
KIMI_RESUME_KEYS = {"role", "type", "session_id", "command", "content"}
KIMI_HOOK_PREFIX = "UserPromptSubmit hook\n"


def normalize_family(value: str | None) -> str | None:
    if not value:
        return None
    candidate = value.strip().lower()
    return FAMILIES.get(candidate)


def result(
    args: argparse.Namespace,
    status: str,
    *,
    reason: str | None = None,
    reason_code: str | None = None,
    cascade_eligible: bool = False,
    **extra: Any,
) -> dict[str, Any]:
    if extra.get("concern_results") == []:
        extra.pop("concern_results")
    payload: dict[str, Any] = {
        "reviewer": args.client,
        "mode": args.mode,
        "status": status,
        "reviewer_family": args.reviewer_family or None,
        "provider": args.provider or None,
        "model": args.model or None,
        **extra,
    }
    if reason is not None:
        payload["reason"] = reason
    if reason_code is not None:
        payload["reason_code"] = reason_code
        payload["cascade_eligible"] = cascade_eligible
    return payload


def inconclusive(
    args: argparse.Namespace,
    reason: str,
    reason_code: str,
    cascade_eligible: bool,
    **extra: Any,
) -> dict[str, Any]:
    return result(
        args,
        "inconclusive",
        reason=reason,
        reason_code=reason_code,
        cascade_eligible=cascade_eligible,
        **extra,
    )


def invalid_model_output(
    args: argparse.Namespace, reason: str, raw_verdict: str = ""
) -> dict[str, Any]:
    # Carry the concern-shaped lines with the stop. The lane refuses to cascade
    # precisely because this output may hold a finding; without the excerpt the
    # operator is told a finding exists but not what it says, which leaves
    # reject-and-rerun as the only move and hides a false positive entirely.
    fields = concern_fields(raw_verdict)
    return inconclusive(
        args,
        reason,
        "invalid_model_output",
        not fields["concern_evidence"],
        **fields,
    )


def load_json_lines(
    path: Path,
) -> tuple[list[dict[str, Any]] | None, str | None, str]:
    events: list[dict[str, Any]] = []
    try:
        raw_events = path.read_bytes().decode("utf-8", "replace")
        for raw in raw_events.splitlines():
            if not raw.strip():
                continue
            item = json.loads(raw)
            if not isinstance(item, dict):
                return None, "non_object_event", raw_events
            events.append(item)
    except OSError:
        return None, "invalid_event_stream", ""
    except json.JSONDecodeError:
        return None, "invalid_event_stream", raw_events
    return events, None, raw_events


def tool_name_and_arguments(
    call: dict[str, Any],
) -> tuple[str | None, dict[str, Any] | None]:
    function = call.get("function")
    if isinstance(function, dict):
        name = function.get("name")
        arguments = function.get("arguments")
    else:
        name = call.get("name")
        arguments = call.get("arguments") or call.get("input")
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments)
        except json.JSONDecodeError:
            return name if isinstance(name, str) else None, None
    return name if isinstance(name, str) else None, arguments if isinstance(
        arguments, dict
    ) else None


def has_unrecognized_tool_activity(value: Any) -> bool:
    if isinstance(value, dict):
        event_type = value.get("type")
        if isinstance(event_type, str) and event_type.lower() in TOOL_ACTIVITY_TYPES:
            return True
        for key, child in value.items():
            if isinstance(key, str) and key.lower() in TOOL_ACTIVITY_KEYS:
                return True
            if has_unrecognized_tool_activity(child):
                return True
    elif isinstance(value, list):
        return any(has_unrecognized_tool_activity(item) for item in value)
    return False


def is_safe_kimi_metadata_event(event: dict[str, Any]) -> bool:
    """Accept the version announcement without constraining its version value."""
    version = event.get("version")
    return (
        event.get("role") == "meta"
        and event.get("type") == "system.version"
        and set(event) == {"role", "type", "version"}
        and isinstance(version, str)
        and 0 < len(version) <= 256
    )


def safe_kimi_metadata_kind(event: dict[str, Any]) -> str | None:
    """Classify the bounded metadata envelopes accepted from Kimi."""
    if is_safe_kimi_metadata_event(event):
        return "version"
    event_type = event.get("type")
    if event.get("role") != "meta":
        return None
    if event_type == "turn.step.retrying" and not set(event) - KIMI_RETRY_KEYS:
        return "retry"
    if event_type == "session.resume_hint" and not set(event) - KIMI_RESUME_KEYS:
        metadata = (
            event.get("session_id"),
            event.get("command"),
            event.get("content"),
        )
        if all(isinstance(value, str) and value.strip() for value in metadata):
            return "resume"
    return None


def parse_kimi_tool_calls(
    event: dict[str, Any],
) -> tuple[
    list[tuple[str, str | None, dict[str, Any] | None]] | None,
    str | None,
]:
    """Validate and normalize Kimi's function-call envelope."""
    calls = event["tool_calls"] if "tool_calls" in event else []
    if not isinstance(calls, list):
        return None, "invalid_container"
    parsed = []
    for call in calls:
        if not isinstance(call, dict):
            return None, "invalid_call"
        function = call.get("function")
        if (
            set(call) - {"type", "id", "function"}
            or call.get("type") != "function"
            or not isinstance(call.get("id"), str)
            or not call["id"]
            or not isinstance(function, dict)
            or set(function) - {"name", "arguments"}
        ):
            return None, "invalid_call"
        name, arguments = tool_name_and_arguments(call)
        parsed.append((call["id"], name, arguments))
    return parsed, None


def kimi_text(
    args: argparse.Namespace, events: list[dict[str, Any]]
) -> tuple[str | None, dict[str, Any] | None]:
    packet_tool = "mcp__code_review_packet__read_packet"
    assistant_texts: list[str] = []
    packet_path = Path(args.packet).resolve()
    try:
        packet_bytes = packet_path.read_bytes()
        packet_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None, inconclusive(
            args, "Kimi packet could not be inspected", "binding_mismatch", False
        )
    packet_byte_count = len(packet_bytes)
    packet_read = False
    packet_read_started = False
    packet_read_ids: dict[str, tuple[int, int]] = {}
    covered_ranges: list[tuple[int, int]] = []
    premature_texts: list[str] = []

    def full_packet_covered() -> bool:
        if packet_byte_count == 0:
            return True
        cursor = 0
        for start, end in sorted(covered_ranges):
            if start > cursor:
                return False
            cursor = max(cursor, end)
            if cursor >= packet_byte_count:
                return True
        return cursor >= packet_byte_count
    for event in events:
        role = event.get("role")
        metadata_kind = safe_kimi_metadata_kind(event)
        is_resume_hint = False
        if role == "assistant":
            allowed_keys = KIMI_ASSISTANT_KEYS
        elif role == "tool":
            allowed_keys = KIMI_TOOL_KEYS
        elif metadata_kind == "retry":
            allowed_keys = KIMI_RETRY_KEYS
        elif metadata_kind == "resume":
            allowed_keys = KIMI_RESUME_KEYS
            is_resume_hint = True
        elif metadata_kind == "version":
            continue
        else:
            return None, inconclusive(
                args,
                "Kimi emitted an event outside the stream allowlist",
                "tool_boundary_violation",
                False,
            )
        if set(event) - allowed_keys:
            return None, inconclusive(
                args,
                "Kimi emitted fields outside the stream allowlist",
                "tool_boundary_violation",
                False,
            )

        if is_resume_hint:
            continue

        parsed_calls, call_error = parse_kimi_tool_calls(event)
        if call_error == "invalid_container":
            return None, inconclusive(
                args, "invalid Kimi tool-call shape", "invalid_model_output", True
            )
        if call_error is not None or parsed_calls is None:
            return None, inconclusive(
                args,
                "Kimi emitted a tool call outside the stream allowlist",
                "tool_boundary_violation",
                False,
            )
        calls = event.get("tool_calls") or []
        content = event.get("content")
        if (
            role == "assistant"
            and not packet_read_started
            and not calls
            and isinstance(content, str)
            and content.startswith(KIMI_HOOK_PREFIX)
        ):
            # Kimi 0.27 emits trusted UserPromptSubmit hook context as an
            # assistant-shaped prelude before the model reads the packet. It is
            # workstation input, not reviewer verdict text. The pre-read/order
            # guard prevents a later model concern from hiding behind the same
            # prefix.
            continue
        for call_id, name, arguments in parsed_calls:
            argument_keys = set(arguments or {})
            page_span: tuple[int, int] | None = None
            if name == packet_tool:
                if argument_keys == {"byte_offset", "max_bytes"}:
                    byte_offset = (arguments or {}).get("byte_offset")
                    max_bytes = (arguments or {}).get("max_bytes")
                    if (
                        isinstance(byte_offset, int)
                        and not isinstance(byte_offset, bool)
                        and byte_offset >= 0
                        and (
                            byte_offset < packet_byte_count
                            or (
                                byte_offset == packet_byte_count
                                and full_packet_covered()
                            )
                        )
                        and isinstance(max_bytes, int)
                        and not isinstance(max_bytes, bool)
                        and 1 <= max_bytes <= MAX_CHUNK_BYTES
                    ):
                        page_span = (byte_offset, max_bytes)
            if page_span is None:
                return None, inconclusive(
                    args,
                    "Kimi attempted a tool outside the exact packet pagination boundary",
                    "tool_boundary_violation",
                    False,
                    attempted_tool=name,
                )
            packet_read_started = True
            packet_read_ids[call_id] = page_span
        if role == "tool":
            tool_call_id = event.get("tool_call_id")
            if not isinstance(tool_call_id, str) or tool_call_id not in packet_read_ids:
                return None, inconclusive(
                    args,
                    "Kimi emitted an unbound tool result",
                    "tool_boundary_violation",
                    False,
                )
            tool_content = event.get("content")
            if not isinstance(tool_content, str):
                return None, inconclusive(
                    args,
                    "Kimi emitted an unreadable packet page",
                    "tool_boundary_violation",
                    False,
                )
            expected_start, requested_bytes = packet_read_ids[tool_call_id]
            header, separator, chunk = tool_content.partition("\n")
            match = re.fullmatch(r"PACKET_CHUNK ([0-9]+):([0-9]+)/([0-9]+)", header)
            if match is not None and separator:
                returned_start, returned_end, returned_total = map(int, match.groups())
                valid_page = (
                    returned_start == expected_start
                    and returned_total == packet_byte_count
                    and returned_start < returned_end <= min(
                        returned_start + requested_bytes, packet_byte_count
                    )
                    and chunk.encode("utf-8") == packet_bytes[returned_start:returned_end]
                )
                valid_eof_confirmation = (
                    returned_start == expected_start == packet_byte_count
                    and returned_end == packet_byte_count
                    and chunk == ""
                    and full_packet_covered()
                )
                if valid_page:
                    covered_ranges.append((returned_start, returned_end))
                    packet_read = full_packet_covered()
                elif valid_eof_confirmation:
                    packet_read = True
        remaining_event = {
            key: value for key, value in event.items() if key != "tool_calls"
        }
        if has_unrecognized_tool_activity(remaining_event):
            return None, inconclusive(
                args,
                "Kimi emitted an unrecognized tool activity shape",
                "tool_boundary_violation",
                False,
            )
        if role != "assistant":
            continue
        if isinstance(content, str) and content.strip():
            if not packet_read:
                premature_texts.append(content.strip())
            else:
                assistant_texts.append(content.strip())
    if not packet_read:
        concern_text = "\n".join(
            line
            for text in premature_texts
            for line in text.splitlines()
            if not CONCERN_RESULT_RE.match(line.strip())
            and line.strip() != "NO_BLOCKING_FINDINGS"
        )
        if premature_texts:
            return None, invalid_model_output(
                args,
                "Kimi produced verdict text before reading the full frozen packet",
                concern_text,
            )
        return None, inconclusive(
            args,
            "Kimi did not read the full frozen packet",
            "invalid_model_output",
            True,
        )
    if premature_texts:
        concern_text = "\n".join(
            line
            for text in premature_texts
            for line in text.splitlines()
            if not CONCERN_RESULT_RE.match(line.strip())
            and line.strip() != "NO_BLOCKING_FINDINGS"
        )
        return None, invalid_model_output(
            args,
            "Kimi produced verdict text before reading the full frozen packet",
            concern_text,
        )
    if not assistant_texts:
        return None, inconclusive(
            args, "Kimi produced no final assistant text", "invalid_model_output", True
        )
    combined_text = "\n".join(assistant_texts)
    expected_receipt = getattr(args, "packet_receipt", "")
    if expected_receipt:
        output_lines = combined_text.splitlines()
        if not output_lines or output_lines[0].strip() != expected_receipt:
            concern_text = "\n".join(
                line
                for line in output_lines
                if not CONCERN_RESULT_RE.match(line.strip())
                and line.strip() != "NO_BLOCKING_FINDINGS"
                and not line.strip().startswith("KIMI_PACKET_RECEIPT_")
            )
            return None, invalid_model_output(
                args,
                "Kimi did not echo the terminal packet receipt first",
                concern_text,
            )
        combined_text = "\n".join(output_lines[1:]).strip()
        if not combined_text:
            return None, inconclusive(
                args,
                "Kimi echoed the packet receipt without a review verdict",
                "invalid_model_output",
                True,
            )
    return combined_text, None


def kimi_inline_text(
    args: argparse.Namespace, events: list[dict[str, Any]]
) -> tuple[str | None, dict[str, Any] | None]:
    """Audit a no-tools Kimi stream with a pre-delivered frozen packet."""
    assistant_texts: list[str] = []
    for event in events:
        role = event.get("role")
        if role == "meta":
            if safe_kimi_metadata_kind(event) is None:
                return None, inconclusive(
                    args,
                    "Kimi emitted metadata outside the no-tools stream allowlist",
                    "tool_boundary_violation",
                    False,
                )
            continue
        if role != "assistant" or set(event) - KIMI_ASSISTANT_KEYS:
            return None, inconclusive(
                args,
                "Kimi emitted an event outside the no-tools packet boundary",
                "tool_boundary_violation",
                False,
            )
        calls, call_error = parse_kimi_tool_calls(event)
        if call_error == "invalid_container":
            return None, inconclusive(
                args,
                "Kimi emitted an invalid tool-call container during no-tools review",
                "invalid_model_output",
                True,
            )
        if call_error is not None:
            return None, inconclusive(
                args,
                "Kimi emitted an invalid tool-call envelope during no-tools review",
                "tool_boundary_violation",
                False,
            )
        if calls:
            return None, inconclusive(
                args,
                "Kimi attempted tool activity during no-tools review",
                "tool_boundary_violation",
                False,
                attempted_tool=calls[0][1],
            )
        remaining_event = {
            key: value for key, value in event.items() if key != "tool_calls"
        }
        if has_unrecognized_tool_activity(remaining_event):
            return None, inconclusive(
                args,
                "Kimi emitted nested tool activity during no-tools review",
                "tool_boundary_violation",
                False,
            )
        content = event.get("content")
        if content is not None and not isinstance(content, str):
            return None, inconclusive(
                args,
                "Kimi emitted non-text no-tools review content",
                "tool_boundary_violation",
                False,
            )
        if isinstance(content, str) and content.strip():
            assistant_texts.append(content.strip())
    if not assistant_texts:
        return None, inconclusive(
            args, "Kimi produced no no-tools review text", "invalid_model_output", True
        )
    combined_text = "\n".join(assistant_texts)
    expected_receipt = getattr(args, "packet_receipt", "")
    if expected_receipt:
        output_lines = combined_text.splitlines()
        if not output_lines or output_lines[0].strip() != expected_receipt:
            concern_text = "\n".join(
                line
                for line in output_lines
                if not CONCERN_RESULT_RE.match(line.strip())
                and line.strip() != "NO_BLOCKING_FINDINGS"
                and not line.strip().startswith("KIMI_PACKET_RECEIPT_")
            )
            return None, invalid_model_output(
                args,
                "Kimi did not echo the terminal packet receipt first",
                concern_text,
            )
        combined_text = "\n".join(output_lines[1:]).strip()
        if not combined_text:
            return None, inconclusive(
                args,
                "Kimi echoed the packet receipt without a review verdict",
                "invalid_model_output",
                True,
            )
    return combined_text, None


def audit_codex(
    args: argparse.Namespace, events: list[dict[str, Any]]
) -> dict[str, Any] | None:
    # Codex can emit known non-tool diagnostic items while still completing a
    # valid response. Tool activity is represented by other item types such as
    # command_execution. Unknown error items remain fail-closed even when the
    # last-message file is valid.
    allowed_items = {"agent_message", "reasoning"}
    allowed_item_events = {"item.started", "item.updated", "item.completed"}
    allowed_lifecycle_events = {"thread.started", "turn.started", "turn.completed"}
    failed_lifecycle_events = {"turn.failed", "turn.cancelled", "error"}
    saw_completed_agent_message = False
    saw_completed_turn = False
    concern_fragments: list[str] = []
    try:
        concern_fragments.append(
            Path(args.result_file).read_bytes().decode("utf-8", "replace")
        )
    except OSError:
        pass

    def invalid(reason: str) -> dict[str, Any]:
        return invalid_model_output(args, reason, "\n".join(concern_fragments))

    for event in events:
        event_type = event.get("type")
        if event_type == "turn.completed":
            saw_completed_turn = True
        item = event.get("item")
        if not isinstance(item, dict):
            if event_type in failed_lifecycle_events:
                return invalid("Codex reported a failed review lifecycle")
            if event_type in allowed_lifecycle_events:
                continue
            return inconclusive(
                args,
                "Codex emitted an event outside the packet-only boundary",
                "tool_boundary_violation",
                False,
                attempted_tool=event_type,
            )
        if event_type not in allowed_item_events:
            return inconclusive(
                args,
                "Codex emitted an unrecognized item event",
                "tool_boundary_violation",
                False,
                attempted_tool=event_type,
            )
        item_type = item.get("type")
        if item_type == "agent_message":
            item_text = item.get("text")
            if isinstance(item_text, str) and item_text.strip():
                concern_fragments.append(item_text.strip())
        if item_type == "error":
            message = item.get("message")
            # The hook-trust stop must fire on any allowed item event: gating
            # it on item.completed would let the same warning delivered as
            # item.started/item.updated degrade into cascade-eligible
            # invalid_model_output instead of a terminal boundary stop.
            if message == CODEX_HOOK_TRUST_WARNING:
                return inconclusive(
                    args,
                    "Codex hooks were enabled without persisted trust during packet-only review",
                    "tool_boundary_violation",
                    False,
                    # Same defect class as the malformed-output stop: a boundary
                    # violation that swallowed a concern leaves nothing to triage.
                    **concern_fields("\n".join(concern_fragments)),
                )
            if event_type == "item.completed" and is_benign_codex_error(message):
                continue
            if (
                event_type == "item.completed"
                and isinstance(message, str)
                and CODEX_STREAM_GAP_RE.fullmatch(message.strip())
            ):
                return inconclusive(
                    args,
                    "Codex event stream reported dropped events",
                    "transport_unverifiable",
                    False,
                )
            # Name the error, but not in `reason`. The events file dies with the
            # run dir, so this string is otherwise unrecoverable — yet it is
            # untrusted client text that may quote packet content, and `reason`
            # is a stable field consumers display and compare. Keep `reason`
            # fixed and carry the text in its own labelled field.
            payload = invalid("Codex reported an item-level review error")
            payload["client_diagnostic"] = bounded_reason_detail(message)
            return payload
        if item_type not in allowed_items:
            return inconclusive(
                args,
                "Codex attempted tool activity during packet-only review",
                "tool_boundary_violation",
                False,
                attempted_tool=item_type,
            )
        if event_type == "item.completed" and item_type == "agent_message":
            saw_completed_agent_message = True
    if not saw_completed_agent_message or not saw_completed_turn:
        return inconclusive(
            args,
            "Codex event stream lacked positive completion evidence",
            "transport_unverifiable",
            False,
        )
    return None


def parse_text_contract(args: argparse.Namespace, text: str) -> dict[str, Any]:
    concern_results: list[dict[str, str]] = []
    verdict_lines: list[str] = []
    seen_verdict = False
    seen_concerns: set[str] = set()
    for line in text.splitlines():
        normalized = line.strip()
        if not normalized:
            continue
        concern_match = CONCERN_RESULT_RE.fullmatch(normalized)
        if concern_match and not seen_verdict:
            concern, conclusion = concern_match.groups()
            concern = concern.lower()
            conclusion = conclusion.strip()
            if concern in seen_concerns or not conclusion or len(conclusion) > 2000:
                return invalid_model_output(
                    args, "review concern result used invalid values", text
                )
            seen_concerns.add(concern)
            concern_results.append({"concern": concern, "conclusion": conclusion})
            continue
        seen_verdict = True
        verdict_lines.append(normalized)
    if verdict_lines == ["NO_BLOCKING_FINDINGS"]:
        return result(args, "passed", concern_results=concern_results, findings=[])
    findings: list[dict[str, Any]] = []
    for line in verdict_lines:
        match = FINDING_RE.fullmatch(line)
        if not match:
            return invalid_model_output(
                args, "review verdict violated the output contract", text
            )
        severity, file_name, line_number, failure_path, smallest_fix = match.groups()
        path = PurePosixPath(file_name)
        if path.is_absolute() or ".." in path.parts:
            return invalid_model_output(
                args, "review finding used an unsafe file path", text
            )
        findings.append(
            {
                "severity": severity,
                "file": file_name,
                "line": int(line_number),
                "failure_path": failure_path,
                "smallest_fix": smallest_fix,
            }
        )
    if not findings:
        return invalid_model_output(args, "review verdict was empty", text)
    return result(args, "findings", concern_results=concern_results, findings=findings)


def parse_json_contract(args: argparse.Namespace) -> dict[str, Any]:
    try:
        raw_verdict = Path(args.result_file).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return invalid_model_output(args, "review verdict was not readable")
    try:
        payload = json.loads(raw_verdict)
    except json.JSONDecodeError:
        return invalid_model_output(
            args, "review verdict was not valid JSON", raw_verdict
        )
    allowed = {"status", "findings", "concern_results"}
    if (
        not isinstance(payload, dict)
        or not {"status", "findings"}.issubset(payload)
        or set(payload) - allowed
    ):
        return invalid_model_output(
            args, "review verdict used an invalid schema", raw_verdict
        )
    status = payload.get("status")
    findings = payload.get("findings")
    if status not in {"passed", "findings"} or not isinstance(findings, list):
        return invalid_model_output(
            args, "review verdict used an invalid schema", raw_verdict
        )
    if (status == "passed" and findings) or (status == "findings" and not findings):
        return invalid_model_output(
            args, "review status did not match findings", raw_verdict
        )
    required = {"severity", "file", "line", "failure_path", "smallest_fix"}
    for finding in findings:
        if not isinstance(finding, dict) or set(finding) != required:
            return invalid_model_output(
                args, "review finding used an invalid schema", raw_verdict
            )
        path = PurePosixPath(str(finding.get("file", "")))
        if (
            finding.get("severity") not in {"P0", "P1", "P2"}
            or not isinstance(finding.get("line"), int)
            or finding["line"] < 1
            or not isinstance(finding.get("failure_path"), str)
            or not finding["failure_path"].strip()
            or not isinstance(finding.get("smallest_fix"), str)
            or not finding["smallest_fix"].strip()
            or path.is_absolute()
            or ".." in path.parts
        ):
            return invalid_model_output(
                args, "review finding used invalid values", raw_verdict
            )
    concern_results = payload.get("concern_results", [])
    if not isinstance(concern_results, list):
        return invalid_model_output(
            args, "review concern results used an invalid schema", raw_verdict
        )
    seen_concerns: set[str] = set()
    normalized_concerns: list[dict[str, str]] = []
    for item in concern_results:
        if not isinstance(item, dict) or set(item) != {"concern", "conclusion"}:
            return invalid_model_output(
                args, "review concern result used an invalid schema", raw_verdict
            )
        concern = item.get("concern")
        conclusion = item.get("conclusion")
        if (
            not isinstance(concern, str)
            or not re.fullmatch(r"[a-z][a-z0-9_]*", concern)
            or concern in seen_concerns
            or not isinstance(conclusion, str)
            or not conclusion.strip()
            or len(conclusion.strip()) > 2000
        ):
            return invalid_model_output(
                args, "review concern result used invalid values", raw_verdict
            )
        seen_concerns.add(concern)
        normalized_concerns.append(
            {"concern": concern, "conclusion": conclusion.strip()}
        )
    return result(args, status, concern_results=normalized_concerns, findings=findings)


def judge(args: argparse.Namespace) -> dict[str, Any]:
    reviewer_family = normalize_family(args.reviewer_family)
    implementer_family = normalize_family(args.implementer_family)
    args.reviewer_family = reviewer_family or ""
    if not reviewer_family:
        payload = inconclusive(
            args,
            "reviewer family could not be attributed",
            "missing_or_unmapped_reviewer_family",
            True,
        )
        payload["candidate_ineligible"] = True
        return payload
    if not implementer_family:
        return inconclusive(
            args, "implementer family is unmapped", "unmapped_implementer_family", False
        )
    events, event_error, raw_events = load_json_lines(Path(args.events))
    if event_error is not None or events is None:
        return invalid_model_output(
            args, event_error or "invalid_event_stream", raw_events
        )
    if args.client == "kimi":
        if args.packet_delivery == "mcp":
            text, failure = kimi_text(args, events)
        else:
            text, failure = kimi_inline_text(args, events)
        return failure or parse_text_contract(args, text or "")
    failure = audit_codex(args, events)
    return failure or parse_json_contract(args)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", required=True, choices=("kimi", "codex"))
    parser.add_argument("--mode", required=True, choices=("review", "challenge"))
    parser.add_argument("--implementer-family", required=True)
    parser.add_argument("--reviewer-family", required=True)
    parser.add_argument("--provider", default="")
    parser.add_argument("--model", default="")
    parser.add_argument("--events", required=True)
    parser.add_argument("--packet")
    parser.add_argument("--packet-delivery", choices=("mcp", "inline"), default="mcp")
    parser.add_argument("--packet-receipt", default="")
    parser.add_argument("--result-file")
    args = parser.parse_args()
    if args.client == "kimi" and not args.packet:
        parser.error("--packet is required for Kimi")
    if args.client == "kimi" and not args.packet_receipt:
        parser.error("--packet-receipt is required for Kimi delivery")
    if args.client == "codex" and not args.result_file:
        parser.error("--result-file is required for Codex")

    payload = judge(args)
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return 0 if payload["status"] in {"passed", "findings"} else 2


if __name__ == "__main__":
    raise SystemExit(main())
