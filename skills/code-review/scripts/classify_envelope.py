#!/usr/bin/env python3
"""Classify a non-success Claude JSON or stream-json result envelope.

Reads the captured stdout on stdin. When the captured text is a JSON envelope this
is the primary, structure-based classifier: it reads `is_error`, `subtype`,
`api_error_status`, `permission_denials`, and the `result` error text instead of
grepping raw CLI prose. It prints a single reason token to stdout and exits 0.

Exit 1 means no JSON object/envelope was present (for example a CLI startup auth
failure that only wrote to stderr); the caller may then use a thin stderr/text
fallback. Exit 3 means a JSON object/envelope was present but carried no classified
error; callers must not grep its model-controlled payload as transport diagnostics.

Reason tokens printed on exit 0:
  auth                 -> not logged in / login required
  quota:<text>         -> rate limit / quota / api_error_status 429
  permission_denied    -> tool permission denials present
  error:<subtype>:<text> -> generic errored envelope
"""
from __future__ import annotations

import json
import re
import sys

NOT_LOGGED_IN = re.compile(r"(^|[^a-z])not logged in([^a-z]|$)|please run /login", re.I)
QUOTA = re.compile(r"rate limit exceeded|quota exceeded|hit your limit", re.I)


def result_text(env: dict) -> str:
    result = env.get("result")
    return result if isinstance(result, str) else ""


def classify(env: dict) -> str | None:
    text = result_text(env)
    if env.get("permission_denials"):
        return "permission_denied"
    api_status = env.get("api_error_status")
    if api_status == 429:
        snippet = " ".join(text.split())[:200]
        return f"quota:{snippet}" if snippet else "quota:rate limit or quota exceeded"
    subtype = env.get("subtype")
    errored = env.get("is_error") is True or subtype not in (None, "success")
    if errored and NOT_LOGGED_IN.search(text):
        return "auth"
    if errored and QUOTA.search(text):
        snippet = " ".join(text.split())[:200]
        return f"quota:{snippet}" if snippet else "quota:rate limit or quota exceeded"
    if errored:
        snippet = " ".join(text.split())[:160]
        return f"error:{subtype}:{snippet}"
    return None


def decode_result(raw: str) -> dict | None:
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else None
    except json.JSONDecodeError:
        pass
    events: list[dict] = []
    for raw_line in raw.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            return None
        if not isinstance(event, dict):
            return None
        events.append(event)
    results = [event for event in events if event.get("type") == "result"]
    return results[-1] if results else None


def main() -> int:
    raw = sys.stdin.read().strip()
    if not raw:
        return 1
    env = decode_result(raw)
    if env is None:
        return 1
    reason = classify(env)
    if reason is None:
        return 3
    print(reason)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
