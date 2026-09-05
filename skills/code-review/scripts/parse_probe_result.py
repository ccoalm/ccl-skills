#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

NOT_LOGGED_IN = re.compile(
    r"(^|[^a-z])not logged in([^a-z]|$)|please run /login|invalid api key|"
    r"authentication (failed|required)|session expired|oauth token expired|"
    r"token expired|401 unauthorized|session has ended",
    re.I,
)
QUOTA = re.compile(
    r"rate limit exceeded|quota exceeded|hit your limit|credit balance too low|"
    r"usage limit reached|too_many_requests",
    re.I,
)


def normalize(text: str) -> str:
    return text.replace("\r", "").strip()


def is_ok_token(text: str) -> bool:
    return normalize(text).lower() == "ok"


def last_non_empty_line(text: str) -> str:
    for line in reversed(text.replace("\r", "").splitlines()):
        if line.strip():
            return line.strip()
    return ""


def has_ok_line(text: str) -> bool:
    return any(is_ok_token(line) for line in text.replace("\r", "").splitlines())


def has_tool_available_marker(text: str) -> bool:
    normalized = text.replace("\r", "").lower()
    if re.search(r"\btool_enabled\b", normalized):
        return True
    for match in re.finditer(r"\bavailable\s+tools?\s*:\s*([\s\S]{0,500})", normalized):
        listed = match.group(1).strip()
        if (
            re.match(r"\bnone\b(?:[\s.!,;:()-]|$)", listed)
            and (not re.search(r"\bbash\b", listed) or has_no_tool_refusal_marker(listed))
            and not re.search(r"\bbash(?:\s+tool)?\b.*\b(?:is|are|was|were|be)\s+available\b", listed)
        ):
            continue
        if re.search(r"\bbash\b", listed):
            return True
    for raw_line in text.replace("\r", "").splitlines():
        line = raw_line.strip().lower()
        if not line:
            continue
        if "bash" not in line:
            continue
        bash_unavailable = re.search(
            r"\bbash(?:\s+tool)?\b.*\b(?:(?:is|was)\s+not|isn't|wasn't|not)\s+available\b|\bbash(?:\s+tool)?\b.*\bunavailable\b",
            line,
        )
        if re.search(r"\bbash\s+tool\b.*\benabled\b", line):
            return True
        if re.search(r"\bbash\s+tool\b.*\b(?:is|are|was|were|be|available\s*:)\s+available\b", line):
            return True
        if re.search(r"\bbash\b.*\b(?:is|are|was|were|be)\s+available\b", line):
            return True
        if re.search(r"\bbash\s+tool\b.*\bavailable\b", line) and not bash_unavailable:
            return True
        if re.search(r"\b(?:can|could|will|would|able\s+to)\b.*\b(?:use|run|execute|call)\b.*\bbash\s+tool\b", line):
            return True
        if re.search(r"\bbash\s+tool\b.*\b(?:can|could|will|would|able\s+to)\b.*\b(?:use|run|execute|call)\b", line):
            return True
        if re.search(r"\b(?:can|could|will|would|able\s+to)\b.*\b(?:use|run|execute|call)\b.*\bbash\b", line):
            return True
        if re.search(r"\bbash\b.*\b(?:can|could|will|would|able\s+to)\b.*\b(?:use|run|execute|call)\b", line):
            return True
        if re.search(r"\b(?:use|using|used|run|ran|execute|executed|call|called)\b.*\bbash\b", line):
            return True
        if re.search(r"\bbash\b.*\b(?:using|used|ran|executed|called)\b", line):
            return True
        if re.search(r"\b(?:using|used|ran|executed|called)\b.*\bbash\s+tool\b", line):
            return True
        if re.search(r"\bbash\s+tool\b.*\b(?:using|used|ran|executed|called)\b", line):
            return True
        if has_no_tool_refusal_marker(line):
            continue
        if re.search(r"\b(?:use|using|used|run|ran|execute|executed|call|called)\b.*\bbash\s+tool\b", line):
            return True
        if re.search(r"\bbash\s+tool\b.*\b(?:use|using|used|run|ran|execute|executed|call|called)\b", line):
            return True
    return False


def has_no_tool_refusal_marker(text: str) -> bool:
    normalized = text.replace("\r", "").lower()
    patterns = (
        r"\bbash\b.{0,120}\b(?:is\s+not|isn't|was\s+not|wasn't|not)\s+available\b",
        r"\bbash\b.{0,120}\bunavailable\b",
        r"\bbash\s+tool\b.{0,120}\b(?:is\s+not|isn't|was\s+not|wasn't|not)\s+available\b",
        r"\bbash\s+tool\b.{0,120}\bunavailable\b",
        r"\bbash\s+tool\b.{0,120}\b(?:not\s+allowed|refus(?:ed|al|ing)|denied|disabled|blocked)\b",
        r"\b(?:cannot|can't|can\s+not|unable\s+to)\b.{0,120}\b(?:use|run|execute|call)\b.{0,120}\bbash\s+tool\b",
        r"\bbash\s+tool\b.{0,120}\b(?:cannot|can't|can\s+not|unable\s+to)\b.{0,120}\b(?:use|run|execute|call)\b",
        r"\bbash\s+tool\b.{0,120}\b(?:cannot|can't|can\s+not|unable\s+to)\s+run\s+that\s+command\b",
    )
    return any(re.search(pattern, normalized) for pattern in patterns)


def is_command_output_like_line(text: str) -> bool:
    line = text.strip()
    if not line:
        return False
    if re.search(r"\b[A-Za-z0-9_.-]+\.(?:md|py|sh|go|js|ts|tsx|json|yaml|yml|toml|txt)\b", line):
        return True
    if re.search(r"\b(?:README|scripts|src|bin|lib|dist|node_modules|go\.mod|package\.json)\b", line):
        return True
    if re.match(r"^[A-Za-z0-9_./-]+$", line):
        return True
    if re.match(r"^[-*]\s+[A-Za-z0-9_./-]+$", line):
        return True
    if re.match(r"^(?:total\s+\d+|drwx|[-r][-wxsStT])", line):
        return True
    if line.startswith(("{", "[", "$", ">")):
        return True
    return False


def is_allowed_probe_explanation_line(text: str) -> bool:
    normalized = normalize(text)
    if not normalized:
        return True
    if is_ok_token(normalized):
        return True
    if is_command_output_like_line(normalized):
        return False
    if has_no_tool_refusal_marker(normalized):
        return True
    return bool(re.search(r"\b(?:comply|explicit instructions?)\b", normalized, re.I))


def is_safe_ok_tail_value(text: str) -> bool:
    normalized = normalize(text)
    if is_ok_token(normalized):
        return True
    lines = [line.strip() for line in normalized.splitlines() if line.strip()]
    return (
        bool(lines)
        and is_ok_token(lines[-1])
        and any(has_no_tool_refusal_marker(line) for line in lines[:-1])
        and not has_tool_available_marker(normalized)
        and all(is_allowed_probe_explanation_line(line) for line in lines[:-1])
    )


def result_text(env: object) -> str:
    return "\n".join(envelope_text_values(env))


def envelope_text_values(env: object) -> list[str]:
    if not isinstance(env, dict):
        return []
    values: list[str] = []
    structured = env.get("structured_output")
    if isinstance(structured, str):
        values.append(structured)
    result = env.get("result")
    if isinstance(result, str):
        values.append(result)
    return values


def all_string_values(value: object) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        values: list[str] = []
        for key, child in value.items():
            if key in {"type", "subtype", "stop_reason", "terminal_reason", "session_id", "uuid"}:
                continue
            values.extend(all_string_values(child))
        return values
    if isinstance(value, list):
        values: list[str] = []
        for child in value:
            values.extend(all_string_values(child))
        return values
    return []


def envelope_error_values(env: object) -> list[str]:
    if not isinstance(env, dict):
        return []
    values: list[str] = []
    for key in ("error", "message", "errors"):
        value = env.get(key)
        if isinstance(value, str):
            values.append(value)
        elif isinstance(value, (dict, list)) and value:
            values.append(json.dumps(value, ensure_ascii=False))
    return values


def classification_surface(env: object, stdout: str, stderr: str) -> str:
    values: list[str] = []
    if isinstance(env, dict):
        values.extend(envelope_text_values(env))
        values.extend(envelope_error_values(env))
        if env.get("type") != "result":
            values.append(stdout)
    else:
        values.append(stdout)
    values.append(stderr)
    return "\n".join(value for value in values if value)


def has_auth_marker(text: str) -> bool:
    return any(NOT_LOGGED_IN.search(line.strip()) for line in text.splitlines())


def sanitize_snippet(text: str) -> str:
    text = re.sub(r"~[\\/][^\s\"']+", "<path>", text)
    text = re.sub(r"\bUsers[\\/][^\s\"']+", "<path>", text)
    text = re.sub(r"\b[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*/\.[^\s\"']+", "<path>", text)
    text = re.sub(r"/[A-Za-z0-9._-]+(?:/[^\s\"']+)+", "<path>", text)
    text = re.sub(r"(^|[\s:\"'(])/[A-Za-z0-9._-]+(?=$|[\s\"')])", r"\1<path>", text)
    text = re.sub(r"\b[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+){2,}\b", "<path>", text)
    text = re.sub(r"([A-Za-z]:\\[^\s]+|\\\\[^\s]+)", "<path>", text)
    text = re.sub(r"\bsk-[A-Za-z0-9_-]{8,}\b", "<secret>", text)
    text = re.sub(r'"[^"]*(?:oauth|token|key|secret)[^"]*"\s*:\s*"[^"]+"', '"<secret>":"<secret>"', text, flags=re.I)
    text = re.sub(r"\b(?:oauth|token|key|secret)[=:][A-Za-z0-9_./-]{8,}\b", "<secret>", text, flags=re.I)
    text = re.sub(r"\b[A-Fa-f0-9]{32,}\b", "<secret>", text)
    snippet = " ".join(text.split())[:200]
    if snippet == "<path>":
        return "path-only diagnostic redacted; inspect local probe stderr for details"
    return snippet


def is_truthy_error(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value != 0
    if isinstance(value, str):
        return value.strip().lower() not in {"", "0", "false", "no", "none", "null"}
    if isinstance(value, (dict, list)):
        return bool(value)
    return value is not None


def api_status_int(env: object) -> int | None:
    if not isinstance(env, dict):
        return None
    status = env.get("api_error_status")
    if status is None:
        return None
    try:
        return int(status)
    except (TypeError, ValueError):
        return None


def _strict_object_pairs(pairs: list[tuple[str, object]]) -> dict:
    """Reject duplicate object keys: json.loads silently keeps the LAST value,
    which would let `"capabilities":["bad"],"capabilities":[]` masquerade as
    empty. A duplicate-key record is malformed evidence and must fail closed."""
    obj: dict = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError(f"duplicate JSON object key: {key!r}")
        obj[key] = value
    return obj


def loads_strict(text: str) -> object:
    return json.loads(text, object_pairs_hook=_strict_object_pairs)


def parse_json_object(text: str) -> object | None:
    stripped = normalize(text)
    if not stripped:
        return None
    try:
        return loads_strict(stripped)
    except ValueError:
        pass
    parsed: list[object] = []
    for line in stripped.splitlines():
        candidate = line.strip()
        if not candidate.startswith("{"):
            continue
        try:
            parsed.append(loads_strict(candidate))
        except ValueError:
            pass
    decoder = json.JSONDecoder(object_pairs_hook=_strict_object_pairs)
    start = stripped.find("{")
    while start != -1:
        line_start = stripped.rfind("\n", 0, start) + 1
        if stripped[line_start:start].strip():
            start = stripped.find("{", start + 1)
            continue
        candidate = stripped[start:]
        try:
            value, end = decoder.raw_decode(candidate)
            parsed.append(value)
            start = stripped.find("{", start + end)
            continue
        except ValueError:
            pass
        start = stripped.find("{", start + 1)
    result_values = [value for value in parsed if isinstance(value, dict) and value.get("type") == "result"]
    for value in result_values:
        if (
            is_truthy_error(value.get("is_error"))
            or value.get("api_error_status") is not None
            or value.get("subtype") not in {None, "success"}
            or value.get("permission_denials")
            or envelope_error_values(value)
        ):
            return value
    if result_values:
        return result_values[-1]
    if parsed:
        return parsed[0]
    return None


# The prompt attempts Bash, but the gate is broader: stream-json init data must
# prove that every declared tool/customization surface is empty, and no tool_use
# block may occur. Ground truth comes from the stream, not the model's reply
# token, which can hallucinate TOOL_ENABLED even when no tool exists.
PROBE_TOOL = "bash"
# The only customization surface still required to be EMPTY. An inherited MCP
# server is invocable capability, so it is a breach. Skill, command and plugin
# lists are host/plugin VOCABULARY: nothing in them is invocable while `tools`
# is pinned to the expected set and the tool_use scan is clean, so they are
# recorded metadata and never judged -- see KNOWN_VOCABULARY_INIT_FIELDS.
REQUIRED_EMPTY_INIT_FIELDS = (
    "mcp_servers",
)
# Fields that must be PRESENT (not merely empty). `permissionMode` is the only
# report of the reviewer's authority, and authority is scalar-shaped — which is
# why it is value-pinned rather than drift-tolerated. Without this, a CLI that
# renames the knob makes the old name simply vanish; absence is not "empty", and
# the drift policy below would wave the new scalar through as benign metadata.
# An init that no longer states its authority is unverifiable, not permissive.
REQUIRED_PRESENT_INIT_FIELDS = ("permissionMode",)
# Best-effort, deliberately NOT a boundary: name fragments that mark a scalar as
# authority-widening. The drift policy tolerates unknown scalars because they
# cannot ENUMERATE a surface — but a scalar can still GRANT one, so this catches
# the plausible spellings of a newly-added bypass knob
# (`dangerously_skip_permissions`, `bypass_sandbox`, ...).
#
# Honest limitation: a name-matching denylist over an open vocabulary cannot be
# complete, and this one is not. It is defense in depth on top of the complete
# check above (a renamed knob is caught by absence), chosen over reverting the
# whole relaxation — which would restore the outage this change exists to fix.
# It fails safe: a false positive refuses the lane as fallback-eligible drift,
# which now costs a reviewer-client switch rather than the review.
AUTHORITY_NAME_STEMS = (
    "permission",
    "bypass",
    "dangerous",
    "sandbox",
    "privileg",
    "escalat",
    "elevat",
    "unrestricted",
    "authorit",
    "admin",
    "superuser",
)


def is_authority_name(name: str) -> bool:
    """True when a field NAME reads as an authority knob.

    Segment-wise, not raw substring. A substring test over short generic tokens
    is a false-positive engine pointed straight back at the outage this change
    removes: `auth` hits `author`, `root` hits `workspace_root`, and a benign
    future metadata field would take every lane inconclusive on a perfectly
    isolated run. Names are split on separators and camelCase humps, and a
    segment must START with a stem — so `authorityLevel` matches while `author`
    does not, and `adminMode` matches while `root_dir` does not.
    """
    segments = re.split(r"[_.\-]+|(?<=[a-z0-9])(?=[A-Z])", name)
    return any(
        segment.lower().startswith(stem)
        for segment in segments
        for stem in AUTHORITY_NAME_STEMS
    )
# This list is CLOSED to incremental extension. It is a denylist over an open
# vocabulary, so it can always be extended by one more plausible word, and
# chasing that is a loop with no end state — the completeness argument belongs
# to the required-presence check above, which is complete by construction. The
# remaining exposure is an added authority knob whose name matches none of these
# fragments; it is accepted, recorded, and owned, not patched round by round.


def safe_identifier(name: object) -> str:
    """Render a CLI-supplied init field name safe to embed in a reason string.

    The wrapper routes on the reason TEXT, and JSON object keys are arbitrary
    strings — including ones containing spaces. Interpolating a raw field name
    lets the inspected CLI choose which routing arm matches: a field literally
    named `unrecognized surface-shaped init field` would drag a breach reason
    into the fallback-eligible class. Restricting to an identifier charset makes
    every multi-word routing phrase unrepresentable, and the length cap keeps a
    pathological key from burying the rest of the reason.
    """
    text = name if isinstance(name, str) else repr(name)
    # `:` is kept: namespaced identifiers (`ccl-skills:testing-strategy`)
    # stay readable in diagnostics and, containing no whitespace, still cannot
    # spell a multi-word routing phrase.
    cleaned = "".join(char if char.isalnum() or char in "_.-:" else "_" for char in text)
    return (cleaned[:60] + "...") if len(cleaned) > 60 else (cleaned or "_")
# Explicitly known non-capability metadata from the installed stream-json init
# schema. `agents` is non-empty in safe mode, but cannot be invoked unless a
# corresponding tool appears in the separately checked `tools` allowlist.
#
# Drift policy (deliberate): the CLI adds scalar metadata fields nearly every
# release (`fast_mode_state`, `fast_mode_disabled_reason`, ...). Pinning field
# *names* would make every CLI upgrade a hard lane outage while proving nothing
# — a scalar cannot enumerate an invocable surface. So an unknown field fails
# closed only when its value is a NON-EMPTY list/dict, i.e. the only shape that
# could carry a new tool/skill/plugin/command surface. Invocability itself stays
# proven by the exact `tools` allowlist plus the tool_use scan, which no init
# field can bypass.
KNOWN_SAFE_INIT_METADATA_FIELDS = {
    "type",
    "subtype",
    "cwd",
    "session_id",
    "model",
    "permissionMode",
    "apiKeySource",
    "claude_code_version",
    "output_style",
    "agents",
    "analytics_disabled",
    "product_feedback_disabled",
    "uuid",
    "fast_mode_state",
}
# Host/plugin vocabulary the init event enumerates. Deliberately NOT a
# boundary and never judged by name, shape, or origin: an entry here becomes
# invocable only through a tool, and the exact `tools` allowlist plus the
# tool_use scan already pin that. Judging these lists against a snapshot of the
# host's own built-in names turned every CLI release that shipped a new skill or
# command into a reviewer-lane outage while proving nothing about isolation, and
# it made an uninstalled or older plugin a refusal instead of a review without
# owner skills.
KNOWN_VOCABULARY_INIT_FIELDS = (
    "slash_commands",
    "terminal_slash_commands",
    "skills",
    "plugins",
)
KNOWN_SAFE_PERMISSION_MODES = {"default", "plan"}


def stream_events(text: str) -> list[dict]:
    """Parse newline-delimited JSON (stream-json) into a list of event objects.
    Non-JSON or non-object lines are skipped; a single result envelope still
    parses as a one-element list."""
    events: list[dict] = []
    for line in text.replace("\r", "").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            parsed = loads_strict(line)
        except ValueError:
            continue
        if isinstance(parsed, dict):
            events.append(parsed)
    return events


def stream_has_malformed_record(text: str) -> bool:
    """A line that looks like a stream-json record (starts with '{') but does not
    parse as standalone JSON. In a complete (rc==0) stream-json capture every
    event is one parseable line, so such a record means a tool declaration or
    tool_use may have been silently dropped -> the ground-truth is untrustworthy.
    (Pretty-printed single envelopes are handled by the text fallback, which never
    reaches the stream ground-truth path; see main.)"""
    for line in text.replace("\r", "").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            loads_strict(line)
        except ValueError:
            return True
    return False


# Event types that only appear in a stream-json (--verbose) capture, never in a
# plain single result envelope. Their presence means the parser MUST have the
# init ground-truth; absent init in such a capture = unverifiable -> fail closed.
STREAM_EVENT_TYPES = {"system", "assistant", "user"}


def is_stream_json_capture(events: list[dict]) -> bool:
    return any(ev.get("type") in STREAM_EVENT_TYPES for ev in events)


def stream_has_nonjson_line(text: str) -> bool:
    """Any non-empty line that is not standalone JSON. A confirmed stream-json
    capture is pure JSONL (verified: real captures have zero non-JSON lines), so
    such a line is a corrupt/dropped record — including one that lost its leading
    '{' and so slips past the '{'-prefixed malformed check."""
    for line in text.replace("\r", "").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        try:
            loads_strict(stripped)
        except ValueError:
            return True
    return False


def stream_nonjson_surface(text: str) -> str:
    """Return only non-JSON stream lines for transport/auth classification.

    In runtime-surface mode, model reply prose lives inside JSON records and is
    intentionally ignored. A CLI banner or startup diagnostic outside those
    records is host-controlled evidence and must still classify auth/quota.
    """
    lines: list[str] = []
    for line in text.replace("\r", "").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        try:
            loads_strict(stripped)
        except ValueError:
            lines.append(stripped)
    return "\n".join(lines)


def stream_classification(text: str, events: list[dict]) -> tuple[bool, bool]:
    """Classify a capture as (is_stream, is_corrupt).

    is_stream: a stream-only event type parsed (system/assistant/user), OR a
    standalone record coexists with a '{'-prefixed malformed line (JSONL whose
    init/tool_use line was dropped). A pretty-printed single envelope or plain
    text yields neither.
    is_corrupt: a '{'-prefixed unparseable line, OR — once we know it is a real
    stream — any non-JSON line at all."""
    confirmed = is_stream_json_capture(events)
    brace_malformed = stream_has_malformed_record(text)
    is_stream = confirmed or (bool(events) and brace_malformed)
    is_corrupt = brace_malformed or (confirmed and stream_has_nonjson_line(text))
    return is_stream, is_corrupt


def init_declared_tools(events: list[dict]) -> set[str] | None:
    """Tools the session exposes, aggregated across ALL stream-json system/init
    events (a later init must not be masked by an earlier empty one). Lowercased
    union, or None when no init event with a tools list is present (ground-truth
    unavailable -> caller falls back to text-based parsing)."""
    declared: set[str] | None = None
    for ev in events:
        if ev.get("type") == "system" and ev.get("subtype") == "init":
            tools = ev.get("tools")
            if isinstance(tools, list):
                names = {str(t).strip().lower() for t in tools if isinstance(t, str)}
                declared = names if declared is None else declared | names
    return declared


def init_surface_state(
    events: list[dict],
) -> tuple[set[str], set[str], set[str], set[str], set[str], set[str]] | None:
    """Return init isolation state across all init events.

    Result fields: missing/invalid required fields, non-empty capability
    fields, declared tool names, unrecognized surface-shaped fields, fields
    declaring an unsafe value, and fields whose authority is unverifiable. A
    missing or wrongly typed required field is not treated as empty, because
    that would turn a CLI schema change into a silent gate bypass. Unknown
    *scalar* metadata is tolerated on purpose — see the drift policy on
    KNOWN_SAFE_INIT_METADATA_FIELDS.

    Unsafe *values* are kept apart from unrecognized *shapes* on purpose: an
    unknown schema addition means this lane cannot verify isolation (report it,
    fall back to another reviewer), while a known field carrying an unsafe
    value — `permissionMode: "bypassPermissions"` — is a breached boundary and
    must terminate the lane. Merging them would let a real privilege escalation
    inherit the drift class's softer next_action.

    Skill, command and plugin lists are vocabulary, not capability: they are
    read for nothing and may hold any value. Isolation is proven by the exact
    `tools` allowlist, the tool_use scan, the empty MCP list and the pinned
    `permissionMode` — none of which any vocabulary entry can affect.
    """
    saw_init = False
    missing_or_invalid: set[str] = set()
    nonempty: set[str] = set()
    declared_tools: set[str] = set()
    unknown_fields: set[str] = set()
    unsafe_values: set[str] = set()
    # Unverifiable authority is NOT a proven breach: we cannot show the reviewer
    # was elevated, only that we can no longer show it was not. It therefore
    # reports in the fallback-eligible class like schema drift — routing a
    # renamed knob to the terminal class would reproduce the total outage this
    # change exists to remove. A KNOWN field carrying a KNOWN-unsafe value stays
    # terminal in `unsafe_values`, because that one is proven.
    unverifiable_authority: set[str] = set()
    known_fields = {
        "tools",
        "capabilities",
        *REQUIRED_EMPTY_INIT_FIELDS,
        *KNOWN_VOCABULARY_INIT_FIELDS,
        *KNOWN_SAFE_INIT_METADATA_FIELDS,
    }
    for ev in events:
        if ev.get("type") != "system" or ev.get("subtype") != "init":
            continue
        saw_init = True
        tools = ev.get("tools")
        if not isinstance(tools, list):
            missing_or_invalid.add("tools")
        elif any(not isinstance(tool, str) for tool in tools):
            # Do not turn a future descriptor/object schema into an empty set.
            # The installed stream contract is a list of names; any other
            # element shape is unverifiable and must fail closed.
            missing_or_invalid.add("tools")
        else:
            declared_tools.update(
                tool.strip().lower() for tool in tools
            )
        for field in REQUIRED_EMPTY_INIT_FIELDS:
            value = ev.get(field)
            if not isinstance(value, list):
                missing_or_invalid.add(field)
            elif value:
                nonempty.add(field)
        # Per EVENT, not on the union across events: a later init that drops or
        # renames the authority field must not be masked by an earlier one that
        # stated it. Every other required-field check in this loop is per event;
        # this one was not, which is exactly the masking shape the existing
        # later-init-declares-Bash fixture guards against for tools.
        for required in REQUIRED_PRESENT_INIT_FIELDS:
            if required not in ev:
                unverifiable_authority.add(required)
        for field, value in ev.items():
            if field not in known_fields and is_authority_name(field):
                # Authority is scalar-shaped, so the container test below
                # cannot see it. Flagged regardless of value shape: a
                # newly-added authority knob is unreviewed either way.
                unverifiable_authority.add(field)
            elif field not in known_fields:
                # Version-drift tolerance: only a non-empty container under an
                # unknown name can enumerate a new invocable surface. A scalar
                # (or an empty list/dict) is metadata and stays allowed, so a
                # routine CLI release does not take the reviewer lane down.
                if isinstance(value, (list, dict)) and value:
                    unknown_fields.add(field)
            elif field in ("agents", "capabilities"):
                # Shape-only, no value vocabulary: `agents` needs the Agent tool
                # and `capabilities` announces host stream-protocol features —
                # neither is invocable unless a tool shows up in the separately
                # checked `tools` allowlist, so pinning their member names only
                # buys CLI-version brittleness. A non-string member means an
                # unverifiable descriptor schema and still fails closed.
                if not isinstance(value, list) or any(
                    not isinstance(item, str) for item in value
                ):
                    unknown_fields.add(field)
            elif field == "permissionMode":
                if value not in KNOWN_SAFE_PERMISSION_MODES:
                    unsafe_values.add(field)
            elif field in KNOWN_VOCABULARY_INIT_FIELDS:
                # Vocabulary, not capability: any value, any shape. Whatever a
                # CLI release or an installed plugin lists here cannot be
                # invoked past the pinned `tools` set.
                continue
            elif field in KNOWN_SAFE_INIT_METADATA_FIELDS and isinstance(
                value, (list, dict)
            ):
                unknown_fields.add(field)
    if not saw_init:
        return None
    return (
        missing_or_invalid,
        nonempty,
        declared_tools,
        unknown_fields,
        unsafe_values,
        unverifiable_authority,
    )


def invoked_tool_names(events: list[dict]) -> set[str]:
    """Names of tools the model actually invoked (tool_use blocks). Empty under a
    real no-tool sandbox even when the reply text claims a tool ran."""
    names: set[str] = set()
    for ev in events:
        message = ev.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                name = block.get("name")
                if isinstance(name, str):
                    names.add(name.strip().lower())
                else:
                    # A malformed tool_use still proves that an invocation
                    # record exists. Preserve it as an impossible expected
                    # name so every allowlist comparison rejects the stream.
                    names.add("<invalid-tool-name>")
    return names


def bash_tool_present(events: list[dict]) -> bool:
    """Ground-truth: was the Bash tool available to or used by the session? An
    actual Bash tool_use is a hard fail INDEPENDENT of the init event (a stream
    missing its init must not launder a real Bash call through the text
    fallback)."""
    if PROBE_TOOL in invoked_tool_names(events):
        return True
    declared = init_declared_tools(events)
    return declared is not None and PROBE_TOOL in declared


def envelope_structurally_clean(
    env: object,
    stdout: str = "",
    stderr: str = "",
    *,
    ignore_reply_text: bool = False,
) -> bool:
    """Result envelope carries no error/auth/quota/permission signal. Excludes the
    reply-text checks so a ground-truth caller can ignore a hallucinated reply."""
    if not isinstance(env, dict):
        return False
    if env.get("type") != "result":
        return False
    if is_truthy_error(env.get("is_error")):
        return False
    api_status = api_status_int(env)
    raw_api_status = env.get("api_error_status")
    if raw_api_status not in {None, 0, "0"} and (api_status is None or api_status >= 400):
        return False
    if env.get("permission_denials"):
        return False
    if env.get("subtype") not in {None, "success", "completed", "stop_turn", "end_turn"}:
        return False
    if envelope_error_values(env):
        return False
    if ignore_reply_text:
        # Main runtime attestation validates the result envelope's structural
        # error fields here, while parse_review_json.py owns the model payload.
        # Preserve stderr auth/quota signals without trusting or rejecting
        # model-authored reply prose that can quote those same words.
        surface = stderr
    else:
        surface = "\n".join(
            value
            for value in (classification_surface(env, stdout, stderr), stdout, stderr)
            if value
        )
    if QUOTA.search(surface) or has_auth_marker(surface):
        return False
    return True


def stream_probe_passed(
    events: list[dict],
    env: object,
    stdout: str = "",
    stderr: str = "",
    expected_tools: set[str] | None = None,
    allow_expected_tool_use: bool = False,
    runtime_surface_only: bool = False,
) -> bool:
    """Ground-truth pass: all init capability surfaces are present and empty,
    no tool was invoked, and the result envelope is clean. Reply text is ignored."""
    expected_tools = expected_tools or set()
    state = init_surface_state(events)
    if state is None:
        return False
    (
        missing_or_invalid,
        nonempty,
        declared_tools,
        unknown_fields,
        unsafe_values,
        unverifiable_authority,
    ) = state
    invoked = invoked_tool_names(events)
    # Every state set refuses here: the softer classes change which client
    # serves the review, never whether an unverified isolation surface is
    # ACCEPTED.
    if (
        missing_or_invalid
        or nonempty
        or unknown_fields
        or unsafe_values
        or unverifiable_authority
        or declared_tools != expected_tools
        or invoked - expected_tools
        or (invoked and not allow_expected_tool_use)
    ):
        return False
    if runtime_surface_only:
        if not envelope_structurally_clean(
            env, "", stderr, ignore_reply_text=True
        ):
            return False
    elif not envelope_structurally_clean(env, stdout, stderr):
        return False
    return True


def clean_envelope_value(env: object, stdout: str = "", stderr: str = "") -> str | None:
    if not envelope_structurally_clean(env, stdout, stderr):
        return None
    if has_tool_available_marker("\n".join(all_string_values(env))):
        return None
    values = [normalize(value) for value in envelope_text_values(env)]
    if values and all(is_safe_ok_tail_value(value) for value in values):
        return "ok"
    return None


def classify_failure(
    rc: int,
    stdout: str,
    stderr: str,
    expected_tools: set[str] | None = None,
    allow_expected_tool_use: bool = False,
):
    expected_tools = expected_tools or set()
    check_label = "Claude runtime isolation check" if expected_tools else "Claude no-tool probe"
    combined = f"{stdout}\n{stderr}"
    env = parse_json_object(stdout)
    # run_claude_capture.py owns these reserved statuses. Ordinary Claude exit
    # codes such as 124/143 remain local process failures, not proof that the
    # outer capture timer fired or terminated the child.
    timeout_or_terminated = rc in {198, 199}

    surface = "\n".join(value for value in (classification_surface(env, stdout, stderr), stdout, stderr) if value)
    text = result_text(env) if env is not None else surface
    api_status = api_status_int(env)
    raw_api_status = env.get("api_error_status") if isinstance(env, dict) else None
    # A tool-boundary denial is terminal even when model/CLI prose also quotes
    # auth, quota, or timeout words. Never make this candidate-fallback eligible.
    if isinstance(env, dict) and env.get("permission_denials"):
        if timeout_or_terminated:
            return (
                f"{check_label} timed out or was terminated; "
                "tool permission-denial evidence was also observed",
                False,
            )
        return f"{check_label} reported tool permission denials", False
    if timeout_or_terminated and api_status == 401:
        return ((
            f"{check_label} timed out or was terminated; "
            "auth-path evidence was also observed, so rerun the wrapper from "
            "a host/escalated shell once local Claude auth is logged in"
        ), False)
    if timeout_or_terminated and (
        api_status == 429
        or (isinstance(raw_api_status, str) and QUOTA.search(raw_api_status))
        or QUOTA.search(surface)
    ):
        snippet = sanitize_snippet(surface or combined)
        return (
            f"{check_label} timed out or was terminated; "
            f"quota/rate-limit evidence was also observed: {snippet or 'rate limit or quota exceeded'}",
            False,
        )
    if timeout_or_terminated and isinstance(env, dict) and (
        is_truthy_error(env.get("is_error")) or env.get("subtype") not in {None, "success"}
    ):
        snippet = sanitize_snippet(text)
        return (
            f"{check_label} timed out or was terminated; "
            f"error-envelope evidence was also observed: {snippet or env.get('subtype') or 'unknown error'}",
            False,
        )
    if api_status == 429 or (isinstance(raw_api_status, str) and QUOTA.search(raw_api_status)):
        snippet = sanitize_snippet(surface or combined)
        return (
            f"{check_label} hit quota/rate limit: {snippet or 'rate limit or quota exceeded'}",
            False,
        )
    if not timeout_or_terminated and (api_status == 401 or has_auth_marker(surface)):
        return ((
            f"safe {check_label} hit auth-path false negative; rerun the "
            "wrapper from a host/escalated shell once local Claude auth is logged in"
        ), False)
    if not timeout_or_terminated and QUOTA.search(surface):
        snippet = sanitize_snippet(surface or combined)
        return (
            f"{check_label} hit quota/rate limit: {snippet or 'rate limit or quota exceeded'}",
            False,
        )
    if not timeout_or_terminated and api_status == 403:
        snippet = sanitize_snippet(text or combined)
        return (
            f"{check_label} returned permission/API access status 403: {snippet or 'no error text'}",
            False,
        )
    if raw_api_status is not None and (api_status is None or api_status >= 400) and not (
        timeout_or_terminated and api_status != 429
    ):
        snippet = sanitize_snippet(text or combined)
        return (
            f"{check_label} returned API error status {raw_api_status}: {snippet or 'no error text'}",
            False,
        )
    if isinstance(env, dict) and (
        is_truthy_error(env.get("is_error")) or env.get("subtype") not in {None, "success"}
    ):
        snippet = sanitize_snippet(text)
        return (
            f"{check_label} returned error envelope: {snippet or env.get('subtype') or 'unknown error'}",
            False,
        )
    failure_events = stream_events(stdout)
    if bash_tool_present(failure_events):
        return (
            f"{check_label} detected the Bash tool is available "
            "(declared or invoked in the session); the no-tool sandbox is not enforced",
            False,
        )
    failure_stream, failure_corrupt = stream_classification(stdout, failure_events)
    if failure_stream:
        if failure_corrupt:
            return (
                f"{check_label} produced a malformed stream-json record; "
                "tool-availability ground-truth is unverifiable",
                False,
            )
        state = init_surface_state(failure_events)
        if state is None:
            return (
                f"{check_label} stream-json capture is missing the init event; "
                "tool-availability ground-truth is unverifiable",
                False,
            )
        (
            missing_or_invalid,
            nonempty,
            declared_tools,
            unknown_fields,
            unsafe_values,
            unverifiable_authority,
        ) = state
        if missing_or_invalid:
            return (
                f"{check_label} init event is missing required isolation fields; "
                "runtime capability ground-truth is unverifiable",
                False,
            )
        if unsafe_values:
            # Terminal on purpose, and checked BEFORE the drift class: an unsafe
            # value on a known field is a breached boundary, not an unverifiable
            # schema. The "runtime capability" wording routes it to
            # tool_boundary_violation / stop_reviewer_lane in claude_review.sh.
            return (
                f"{check_label} init event declares an unsafe runtime capability "
                f"value on {', '.join(safe_identifier(f) for f in sorted(unsafe_values))}; "
                "the reviewer sandbox boundary is not enforced",
                False,
            )
        invoked = invoked_tool_names(failure_events)
        surface_breached = bool(
            nonempty
            or declared_tools != expected_tools
            or invoked - expected_tools
            or (invoked and not allow_expected_tool_use)
        )
        if unverifiable_authority and not surface_breached:
            # Fallback-eligible, NOT terminal: a vanished or renamed authority
            # knob means we can no longer prove the reviewer was unelevated —
            # not that it was. Terminalizing it would turn the next CLI rename
            # into the same total outage this landing removes.
            return (
                "Claude reviewer lane found an unrecognized surface-shaped init "
                "field (authority: "
                + ", ".join(safe_identifier(f) for f in sorted(unverifiable_authority))
                + "); the reviewer's authority is no longer verifiable from the "
                "stream-json schema",
                False,
            )
        if unknown_fields and not surface_breached:
            # Drift is reported ONLY when nothing else is wrong — same guard as
            # `runtime_drift_only` on the main-invocation path. A run that both
            # drifts and breaches must report the breach: this branch's phrase
            # routes to the fallback-eligible class, so reaching it first would
            # launder a real breach into "try another reviewer client".
            #
            # Wording is load-bearing: claude_review.sh routes this exact phrase
            # to a fallback-eligible schema-drift class, not to the terminal
            # tool-boundary class — a surface-shaped schema addition means THIS
            # lane cannot verify isolation, not that review must stop. Naming
            # the fields keeps the one-line follow-up obvious.
            #
            # `check_label` is deliberately NOT interpolated here: in consult
            # mode it reads "Claude runtime isolation check", and the routing
            # table's tool-boundary arm matches on "runtime isolation". Emitting
            # it would make correct routing depend on `case`-arm order alone.
            return (
                "Claude reviewer lane found an unrecognized surface-shaped init "
                f"field ({', '.join(safe_identifier(f) for f in sorted(unknown_fields))}); "
                "the stream-json schema must be reviewed before this lane can "
                "verify isolation",
                False,
            )
        if surface_breached or unknown_fields or unverifiable_authority:
            if expected_tools:
                surface_reason = (
                    f"{check_label} runtime capability surface does not match the expected boundary; "
                    "a tool or MCP server is unexpected or unsafe"
                )
            else:
                surface_reason = (
                    "Claude no-tool probe runtime capability surface is not empty; "
                    "a tool or MCP server remains declared or invoked"
                )
            return (
                surface_reason,
                False,
            )
    snippet = sanitize_snippet(combined)
    return f"{check_label} failed: {snippet or 'unexpected probe output'}", True


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "usage: parse_probe_result.py RC STDOUT_FILE STDERR_FILE "
            "[--require-empty-init] [--expected-tools CSV] "
            "[--allow-expected-tool-use] [--runtime-surface-only]",
            file=sys.stderr,
        )
        return 64
    require_empty_init = False
    expected_tools: set[str] = set()
    allow_expected_tool_use = False
    runtime_surface_only = False
    option_index = 4
    while option_index < len(sys.argv):
        option = sys.argv[option_index]
        if option == "--require-empty-init":
            require_empty_init = True
            option_index += 1
        elif option == "--expected-tools" and option_index + 1 < len(sys.argv):
            expected_tools = {
                name.strip().lower()
                for name in sys.argv[option_index + 1].split(",")
                if name.strip()
            }
            option_index += 2
        elif option == "--allow-expected-tool-use":
            allow_expected_tool_use = True
            option_index += 1
        elif option == "--runtime-surface-only":
            runtime_surface_only = True
            option_index += 1
        else:
            print("unknown or incomplete probe parser option", file=sys.stderr)
            return 64

    # Tool-boundary verdicts are meaningful only with stream-json init
    # evidence. Make the stronger requirement intrinsic so a direct caller
    # cannot accidentally re-enable the legacy text fallback.
    if runtime_surface_only or expected_tools or allow_expected_tool_use:
        require_empty_init = True

    try:
        rc = int(sys.argv[1])
    except ValueError:
        print("probe rc must be an integer", file=sys.stderr)
        return 64

    stdout = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
    stderr = Path(sys.argv[3]).read_text(encoding="utf-8", errors="replace")
    normalized_stdout = normalize(stdout)
    stderr_surface = classification_surface(None, "", stderr)
    env = parse_json_object(normalized_stdout)
    events = stream_events(normalized_stdout)
    invoked_tools = invoked_tool_names(events)
    stream_like, stream_corrupt = stream_classification(normalized_stdout, events)
    stdout_clean = not QUOTA.search(normalized_stdout) and not has_auth_marker(normalized_stdout)
    stderr_clean = not QUOTA.search(stderr_surface) and not has_auth_marker(stderr_surface)
    runtime_stdout_surface = ""
    if runtime_surface_only and rc == 0:
        # Only a structurally intact JSONL stream can distinguish host/CLI
        # banners from model reply content. Pretty-printed envelopes and corrupt
        # streams are unverifiable; never classify their stdout prose as auth or
        # quota evidence.
        if stream_like and not stream_corrupt:
            runtime_stdout_surface = stream_nonjson_surface(normalized_stdout)
        stdout_clean = not QUOTA.search(runtime_stdout_surface) and not has_auth_marker(
            runtime_stdout_surface
        )
    if (
        not require_empty_init
        and rc == 0
        and stdout_clean
        and stderr_clean
        and is_ok_token(normalized_stdout)
    ):
        return 0

    if rc == 0 and stdout_clean and stderr_clean:
        unexpected_tool_use = invoked_tools - expected_tools or (
            invoked_tools and not allow_expected_tool_use
        )
        if unexpected_tool_use:
            # Any unexpected tool_use is a hard fail regardless of init/text;
            # fall through to classify_failure (reports sandbox not enforced).
            pass
        elif stream_like:
            # stream-json mode REQUIRES trustworthy ground-truth: a parseable init
            # event, no corruption, Bash neither declared nor invoked. Missing init
            # or a dropped record could hide a real Bash session, so anything less
            # fails closed instead of passing on the reply token.
            if not stream_corrupt and stream_probe_passed(
                events,
                env,
                stdout,
                stderr,
                expected_tools,
                allow_expected_tool_use,
                runtime_surface_only,
            ):
                return 0
        elif not require_empty_init:
            # non-stream output (no standalone JSONL records, e.g. plain single
            # envelope or raw text): legacy text fallback.
            value = clean_envelope_value(env, stdout, stderr)
            if value is not None and is_ok_token(value):
                return 0

    if require_empty_init and rc == 0 and stdout_clean and stderr_clean and not stream_like:
        print(
            json.dumps(
                {
                    "reason": (
                        "Claude no-tool probe is missing the required stream-json init evidence; "
                        "runtime isolation cannot be verified"
                    ),
                    "generic_failure": False,
                }
            )
        )
        return 1

    if runtime_surface_only and rc == 0:
        runtime_diagnostic_surface = "\n".join(
            value for value in (runtime_stdout_surface, stderr_surface) if value
        )
        runtime_api_status = api_status_int(env)
        runtime_raw_api_status = env.get("api_error_status") if isinstance(env, dict) else None
        if isinstance(env, dict) and env.get("permission_denials"):
            runtime_reason = "Claude main invocation reported tool permission denials"
        elif runtime_api_status == 401 or has_auth_marker(runtime_diagnostic_surface):
            runtime_reason = (
                "safe Claude main invocation hit auth-path false negative; rerun the "
                "wrapper from a host/escalated shell once local Claude auth is logged in"
            )
        elif (
            runtime_api_status == 429
            or (
                isinstance(runtime_raw_api_status, str)
                and QUOTA.search(runtime_raw_api_status)
            )
            or QUOTA.search(runtime_diagnostic_surface)
        ):
            snippet = sanitize_snippet(runtime_diagnostic_surface)
            runtime_reason = (
                "Claude main invocation hit quota/rate limit: "
                f"{snippet or 'rate limit or quota exceeded'}"
            )
        else:
            runtime_state = init_surface_state(events)
            runtime_detail = ""
            runtime_drift_only = False
            if runtime_state is not None:
                (
                    missing,
                    nonempty,
                    declared,
                    unknown,
                    unsafe,
                    unverifiable,
                ) = runtime_state
                # Schema drift routes the same way on the main-invocation path as
                # on the probe path. Without this, an unrecognized init container
                # would terminate the lane here while merely falling back there —
                # the same condition, two verdicts, decided by which parse ran.
                runtime_drift_only = bool(unknown or unverifiable) and not (
                    missing
                    or nonempty
                    or unsafe
                    or declared != expected_tools
                    or invoked_tools - expected_tools
                    or (invoked_tools and not allow_expected_tool_use)
                )
                # EVERY interpolated identifier is CLI-supplied, not just the
                # field names: tool names and invoked-tool names come from the
                # inspected stream too, and may contain spaces just as freely.
                # Any one of them left raw lets the inspected CLI pick which
                # routing arm matches — a breach laundered into "try another
                # client".
                def joined(values):
                    return ",".join(safe_identifier(v) for v in sorted(values))

                runtime_detail = (
                    "; missing_or_invalid="
                    + joined(missing)
                    + "; unexpected_customizations="
                    + joined(nonempty)
                    + "; declared_tools="
                    + joined(declared)
                    + "; invoked_tools="
                    + joined(invoked_tools)
                    + "; unknown_fields="
                    + joined(unknown)
                    + "; unsafe_values="
                    + joined(unsafe)
                    + "; unverifiable_authority="
                    + joined(unverifiable)
                )
            if runtime_drift_only:
                runtime_reason = (
                    "Claude main invocation found an unrecognized surface-shaped "
                    "init field; the stream-json schema must be reviewed before "
                    "this reviewer lane can verify isolation" + runtime_detail
                )
            else:
                runtime_reason = (
                    "Claude main invocation runtime isolation surface is invalid or unverifiable"
                    + runtime_detail
                )
        print(
            json.dumps(
                {
                    "reason": runtime_reason,
                    "generic_failure": False,
                }
            )
        )
        return 1

    reason, generic_failure = classify_failure(
        rc,
        stdout,
        stderr,
        expected_tools,
        allow_expected_tool_use,
    )
    print(
        json.dumps(
            {
                "reason": reason,
                "generic_failure": generic_failure,
            },
            ensure_ascii=False,
        )
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
