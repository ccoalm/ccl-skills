#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys

WRAPPER_PAYLOAD_KEYS = {
    "advisory",
    "consult_scope",
    "gate_eligible",
    "lens_id",
    "reason",
    "status",
    "tool_identity",
    "untrusted_evidence",
}
WRAPPER_FINDING_KEYS = {"source"}
CONCERN_ID_RE = re.compile(r"[a-z][a-z0-9_]*")


def normalize(text: str) -> str:
    stripped = text.strip()
    fence = re.fullmatch(r"```(?:json)?\s*(\{.*\})\s*```", stripped, flags=re.S)
    if fence:
        return fence.group(1).strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        return stripped
    return stripped


def valid(payload: object, mode: str) -> bool:
    if not isinstance(payload, dict) or payload.get("mode") != mode:
        return False
    if "lens_id" in payload or "tool_identity" in payload:
        print(
            f"{mode} payload must not self-report review lens identity", file=sys.stderr
        )
        return False
    if WRAPPER_PAYLOAD_KEYS.intersection(payload):
        return False
    if mode == "consult" and not (
        isinstance(payload.get("answer"), str) and payload["answer"].strip()
    ):
        return False
    if mode == "consult" and payload.get("evidence_sufficient") is not True:
        return False
    findings = payload.get("findings")
    if not isinstance(findings, list):
        return False
    for item in findings:
        if not isinstance(item, dict):
            return False
        if WRAPPER_FINDING_KEYS.intersection(item):
            return False
        if item.get("severity") not in {"P0", "P1", "P2"}:
            return False
        if not isinstance(item.get("file"), str) or not item["file"].strip():
            return False
        if not isinstance(item.get("line"), int) or item["line"] < 1:
            return False
        if (
            not isinstance(item.get("failure_path"), str)
            or not item["failure_path"].strip()
        ):
            return False
        if (
            not isinstance(item.get("smallest_fix"), str)
            or not item["smallest_fix"].strip()
        ):
            return False
    concern_results = payload.get("concern_results", [])
    if not isinstance(concern_results, list):
        return False
    seen_concerns = set()
    for item in concern_results:
        if not isinstance(item, dict) or set(item) != {"concern", "conclusion"}:
            return False
        concern = item.get("concern")
        conclusion = item.get("conclusion")
        if (
            not isinstance(concern, str)
            or CONCERN_ID_RE.fullmatch(concern) is None
            or concern in seen_concerns
            or not isinstance(conclusion, str)
            or not conclusion.strip()
            or len(conclusion.strip()) > 2000
        ):
            return False
        seen_concerns.add(concern)
    return True


def canonical_payload(payload: dict, mode: str) -> dict:
    findings = [
        {
            "severity": finding["severity"],
            "file": finding["file"],
            "line": finding["line"],
            "failure_path": finding["failure_path"],
            "smallest_fix": finding["smallest_fix"],
        }
        for finding in payload["findings"]
    ]
    if mode == "consult":
        return {
            "mode": payload["mode"],
            "answer": payload["answer"],
            "evidence_sufficient": payload["evidence_sufficient"],
            "findings": findings,
        }
    out = {"mode": payload["mode"], "findings": findings}
    if "concern_results" in payload:
        out["concern_results"] = [
            {
                "concern": item["concern"],
                "conclusion": item["conclusion"].strip(),
            }
            for item in payload["concern_results"]
        ]
    return out


def extract_payload(payload: object) -> object:
    if not isinstance(payload, dict):
        return payload
    envelope_like = "structured_output" in payload or "result" in payload
    if envelope_like and payload.get("type") != "result":
        return None
    if envelope_like and not (
        payload.get("subtype") == "success"
        or payload.get("is_error") is False
        or payload.get("terminal_reason") == "completed"
    ):
        return None
    if payload.get("is_error") is True:
        return None
    if payload.get("subtype") not in {None, "success"}:
        return None
    if payload.get("type") == "result" and payload.get("terminal_reason") not in {
        None,
        "completed",
    }:
        return None
    if payload.get("api_error_status") is not None:
        return None
    if payload.get("type") != "result" and payload.get("terminal_reason") not in {
        None,
        "completed",
    }:
        return None
    if payload.get("permission_denials"):
        return None
    structured = payload.get("structured_output")
    if structured is not None:
        return structured
    result = payload.get("result")
    if isinstance(result, str):
        try:
            return json.loads(normalize(result))
        except json.JSONDecodeError:
            return payload
    return payload


def decode_payload(text: str) -> object:
    normalized = normalize(text)
    try:
        return json.loads(normalized)
    except json.JSONDecodeError:
        pass
    events: list[dict] = []
    for raw_line in normalized.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        event = json.loads(line)
        if not isinstance(event, dict):
            raise json.JSONDecodeError("stream event is not an object", line, 0)
        events.append(event)
    results = [event for event in events if event.get("type") == "result"]
    if not results:
        raise json.JSONDecodeError("stream has no result event", normalized, 0)
    return results[-1]


if len(sys.argv) != 2:
    print("usage: parse_review_json.py MODE", file=sys.stderr)
    sys.exit(2)
mode = sys.argv[1]
if mode not in {"review", "challenge", "consult"}:
    print("MODE must be review, challenge, or consult", file=sys.stderr)
    sys.exit(2)
try:
    payload = extract_payload(decode_payload(sys.stdin.read()))
except json.JSONDecodeError:
    sys.exit(1)
if not valid(payload, mode):
    sys.exit(1)
print(json.dumps(canonical_payload(payload, mode), ensure_ascii=False, indent=2))
