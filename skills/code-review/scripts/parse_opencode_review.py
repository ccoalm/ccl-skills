#!/usr/bin/env python3
"""Deterministic parser/judge for the opencode non-Claude reviewer fallback lane.

opencode is only the *transport*; this script is the single judge that turns a
bounded `opencode run` + `opencode export` into a gate-valid result. It is pure
(files in, one JSON line out) so it can be unit-tested with captured fixtures
without invoking opencode.

The lane is a security/governance gate: it decides whether an INDEPENDENT review
or challenge has actually run in a real sandbox. Every ambiguity therefore fails
closed to `inconclusive`. A required lane is closed ONLY by `passed` (reviewer
ran clean, emitted the exact sentinel) or `findings` (reviewer ran clean and
returned schema-shaped findings).

Inputs:
  --events PATH         newline-delimited JSON events from `opencode run --format json` (REQUIRED)
  --export PATH         JSON from `opencode export <sessionID>`
  --agent-boundary PATH resolved JSON from public `opencode debug agent`
  --exit-code N         exit code of the bounded `opencode run` (124 == timeout)
  --mode {review,challenge}
  --implementer-family FAM  canonical family of the code author under review (REQUIRED)

Output: one JSON line. Exit 0 for passed/findings, 2 for inconclusive.
"""

import argparse
import json
import os
from pathlib import PurePosixPath
import re
import sys

# Same-directory import. The lane runs this as a script and the tests load it by
# path, so neither can rely on the package machinery.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from egress_schema import apply as apply_egress_schema  # noqa: E402


# providerID segment (before "/" in an opencode model id) -> canonical reviewer
# family. Same-family reviewer cannot satisfy an independence gate, so the
# Moonshot/Kimi providers collapse to one family.
#
# Heuristic basis (known limitation): the export providerID is the user's own
# opencode provider NAME, so this table assumes a provider name conventionally
# matches its backend (e.g. `kimi` -> Moonshot). A deliberately mis-named custom
# provider (e.g. an OpenAI endpoint labelled `kimi`) would defeat ANY name-based
# entry here -- a limitation shared by every row, not `kimi`-specific. The gate
# guards accidental same-family review, not adversarial self-mislabelling.
PROVIDER_FAMILY = {
    "anthropic": "claude",
    "claude": "claude",
    "openai": "openai",
    "azure": "openai",
    "google": "gemini",
    "google-vertex": "gemini",
    "deepseek": "deepseek",
    "kimi": "moonshot",
    "kimi-for-coding": "moonshot",
    "moonshotai": "moonshot",
    "moonshotai-cn": "moonshot",
    "xai": "grok",
    "groq": "groq",
    "mistral": "mistral",
}

FINDING_RE = re.compile(r"^(P[0-2])\s+(\S+):(\d+)\s+(.+?)\s+\|\s+(.+)$")
CONCERN_EVIDENCE_RE = re.compile(
    r"(?i)(?:^|[^a-z0-9])(p[0-2]|blocker|critical|major|minor|high|medium|low)"
    r"(?:[^a-z0-9]|$)|[a-z0-9_.-]*[./][a-z0-9_./-]*:\d+"
)


def family_for_provider(provider_id):
    if not provider_id:
        return None
    return PROVIDER_FAMILY.get(provider_id.strip().lower())


def normalize_family(value):
    """Accept either a providerID (anthropic) or a family name (claude) and return
    the canonical family, or None if it maps to nothing. Used for the implementer
    family so `--implementer-family anthropic` cannot bypass `claude` independence."""
    if not value:
        return None
    v = value.strip().lower()
    if v in set(PROVIDER_FAMILY.values()):
        return v
    return PROVIDER_FAMILY.get(v)


def _result(status, reason=None, **extra):
    out = {"reviewer": "opencode", "status": status}
    if reason:
        out["reason"] = reason
    if extra.get("concern_results") == []:
        extra.pop("concern_results")
    out.update(extra)
    # Single choke point for the field schema: every verdict this module emits
    # goes through here, so bounding it here bounds the lane. The schema drops
    # malformed values and names them; it never changes `status` or `reason`.
    return apply_egress_schema(out)


def session_id_from_events(events_text):
    session_id = None
    last_event = None
    for line in events_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            return None, "event_stream_unparseable", False
        if not isinstance(ev, dict):
            return None, "event_stream_unparseable", False
        last_event = ev
        sid = ev.get("sessionID")
        if sid and session_id is None:
            session_id = sid
    terminal_stop = bool(
        isinstance(last_event, dict)
        and last_event.get("sessionID") == session_id
        and last_event.get("type") == "step_finish"
        and isinstance(last_event.get("part"), dict)
        and last_event["part"].get("type") == "step-finish"
        and last_event["part"].get("reason") == "stop"
    )
    return session_id, None, terminal_stop


# Packet-only OpenCode review needs no invocable capability unless the
# controller selected native owner skills. In that case `skill` is required.
# The `invalid` pseudo-tool reports rejected calls and is not an external
# capability. Any other enabled built-in, plugin, or MCP tool widens the packet
# boundary and is terminal.
ALWAYS_ALLOWED_ENABLED_TOOLS = {"invalid"}
REQUIRED_DISABLED_TOOLS = {
    "bash",
    "edit",
    "write",
    "task",
    "webfetch",
    "question",
    "todowrite",
    "read",
    "glob",
    "grep",
}


def validate_agent_boundary(args):
    """Validate the resolved public debug-agent surface without model inference."""
    try:
        with open(args.agent_boundary) as fh:
            agent = json.load(fh)
    except (OSError, json.JSONDecodeError, TypeError):
        return _result("inconclusive", "agent_boundary_unresolved")
    if (
        not isinstance(agent, dict)
        or agent.get("name") != "ccl-review"
        or agent.get("mode") != "primary"
    ):
        return _result("inconclusive", "agent_identity_mismatch")
    tools = agent.get("tools")
    if not isinstance(tools, dict) or any(
        not isinstance(value, bool) for value in tools.values()
    ):
        return _result("inconclusive", "agent_tools_invalid")
    enabled = {name for name, value in tools.items() if value}
    allowed_enabled = set(ALWAYS_ALLOWED_ENABLED_TOOLS)
    if args.require_skill_tool:
        allowed_enabled.add("skill")
    exposed = sorted(enabled - allowed_enabled)
    if exposed:
        return _result(
            "inconclusive", "agent_forbidden_tool_available", exposed_tools=exposed
        )
    disabled_missing = sorted(REQUIRED_DISABLED_TOOLS - set(tools))
    if disabled_missing:
        return _result(
            "inconclusive",
            "agent_disabled_tool_missing",
            missing_disabled_tools=disabled_missing,
        )
    required_review_tools = {"skill"} if args.require_skill_tool else set()
    missing = sorted(required_review_tools - enabled)
    if missing:
        return _result(
            "inconclusive", "agent_required_tool_missing", missing_tools=missing
        )

    model = agent.get("model")
    if model is None:
        return None
    if not isinstance(model, dict):
        return _result("inconclusive", "agent_model_missing")
    actual_provider = model.get("providerID")
    actual_model = model.get("modelID")
    if not actual_provider or not actual_model:
        return _result("inconclusive", "agent_model_missing")
    return None


def parse_export(export_obj):
    """Final assistant text + stop reason + model metadata, bound to the LAST
    assistant message (no cross-message accumulation)."""
    sid = export_obj.get("id") or (export_obj.get("info") or {}).get("id")
    last = None
    assistant_models = []
    for msg in export_obj.get("messages", []):
        msg_info = msg.get("info") or {}
        if msg_info.get("role") != "assistant":
            continue
        msg_model = msg_info.get("model") or {}
        assistant_models.append(
            {
                "model": (msg_model.get("id") if isinstance(msg_model, dict) else None)
                or msg_info.get("modelID"),
                "provider": (
                    msg_model.get("providerID") if isinstance(msg_model, dict) else None
                )
                or msg_info.get("providerID"),
            }
        )
        last = msg
    if last is None:
        return {
            "session_id": sid,
            "model": None,
            "provider": None,
            "version": None,
            "final_text": "",
            "final_reason": "",
            "assistant_models": [],
        }
    info = last.get("info") or {}
    model = info.get("model") or {}
    model_id = (model.get("id") if isinstance(model, dict) else None) or info.get(
        "modelID"
    )
    provider_id = (
        model.get("providerID") if isinstance(model, dict) else None
    ) or info.get("providerID")
    # Join ALL text parts of the final message in order — a message with parts
    # ["P1 ...", "NO_BLOCKING_FINDINGS"] must NOT be read as the bare sentinel.
    texts = []
    final_reason = ""
    for part in last.get("parts", []):
        if part.get("type") == "text" and (part.get("text") or "").strip():
            texts.append(part["text"].strip())
        elif part.get("type") == "step-finish":
            final_reason = part.get("reason") or final_reason
    final_text = "\n".join(texts).strip()
    version = info.get("version") or (export_obj.get("info") or {}).get("version")
    return {
        "session_id": sid,
        "model": model_id,
        "provider": provider_id,
        "version": version,
        "final_text": final_text,
        "final_reason": final_reason,
        "assistant_models": assistant_models,
    }


def parse_findings(text):
    """Parse every line into the shared finding schema, or fail closed."""
    findings = []
    for line in text.splitlines():
        match = FINDING_RE.fullmatch(line.strip())
        if not match:
            return None
        severity, file_name, line_number, failure_path, smallest_fix = match.groups()
        path = PurePosixPath(file_name)
        if path.is_absolute() or ".." in path.parts:
            return None
        findings.append(
            {
                "severity": severity,
                "file": file_name,
                "line": int(line_number),
                "failure_path": failure_path,
                "smallest_fix": smallest_fix,
            }
        )
    return findings or None


def parse_review_text(text):
    """Parse optional concern conclusions followed by one verdict contract."""
    concern_results = []
    seen_concerns = set()
    verdict_lines = []
    seen_verdict = False
    for line in text.splitlines():
        normalized = line.strip()
        if not normalized:
            continue
        match = re.fullmatch(
            r"CHECK\s+([a-z][a-z0-9_]*)\s+\|\s+(.+)",
            normalized,
            flags=re.IGNORECASE,
        )
        if match and not seen_verdict:
            concern, conclusion = match.groups()
            concern = concern.lower()
            conclusion = conclusion.strip()
            if concern in seen_concerns or not conclusion or len(conclusion) > 2000:
                return None
            seen_concerns.add(concern)
            concern_results.append({"concern": concern, "conclusion": conclusion})
            continue
        seen_verdict = True
        verdict_lines.append(normalized)
    verdict_text = "\n".join(verdict_lines)
    if verdict_lines == ["NO_BLOCKING_FINDINGS"]:
        return "passed", concern_results, []
    findings = parse_findings(verdict_text)
    if findings is not None:
        return "findings", concern_results, findings
    return None


def judge(args):
    # 1. Non-timeout transport failures are fail-closed. A timeout may still
    # leave a public export that proves the assistant turn finished with stop;
    # validate that export through every ordinary binding and schema check
    # before deciding whether the timeout was only a post-completion run tail.
    transport_timed_out = args.exit_code == 124
    if len(set(args.required_concern)) != len(args.required_concern) or any(
        re.fullmatch(r"[a-z][a-z0-9_]*", concern) is None
        for concern in args.required_concern
    ):
        return _result("inconclusive", "invalid_required_concern")
    if args.exit_code not in (0, 124, None):
        return _result("inconclusive", f"reviewer_exit_{args.exit_code}")

    # 2. events are required; capture the run's session id for the binding check.
    if not args.events:
        return _result("inconclusive", "missing_events")
    with open(args.events) as fh:
        ev_sid, event_error, event_terminal_stop = session_id_from_events(fh.read())
    if event_error:
        return _result("inconclusive", event_error)
    if not ev_sid:
        return _result("inconclusive", "missing_session_id")
    if transport_timed_out and not event_terminal_stop:
        return _result("inconclusive", "reviewer_timeout")

    # 3. Validate the resolved debug-agent tool surface without another model call.
    agent_failure = validate_agent_boundary(args)
    if agent_failure:
        return agent_failure

    # 4. need the exported transcript to judge content.
    if not args.export:
        return _result("inconclusive", "missing_export")
    with open(args.export) as fh:
        try:
            export_obj = json.load(fh)
        except json.JSONDecodeError:
            return _result("inconclusive", "export_unparseable")
    meta = parse_export(export_obj)

    base = {
        "session_id": meta["session_id"],
        "model": meta["model"],
        "provider": meta["provider"],
        "version": meta["version"],
        "mode": args.mode,
    }
    if transport_timed_out:
        base["transport_tail_timeout"] = True

    # 5. the exported session must be present AND be the one we actually ran
    #    (a crafted export with no id must not skip the binding check).
    if not meta["session_id"]:
        if transport_timed_out:
            return _result("inconclusive", "reviewer_timeout", **base)
        return _result("inconclusive", "session_id_mismatch", **base)
    if meta["session_id"] != ev_sid:
        return _result("inconclusive", "session_id_mismatch", **base)

    # Attribution is mandatory even when the user leaves ccl-review.model
    # unset and lets OpenCode choose its own default. Every assistant message in
    # the accepted session must stay on the same provider/model as the final one.
    if not meta["provider"] or not meta["model"]:
        return _result("inconclusive", "missing_model_attribution", **base)
    if any(
        item.get("provider") != meta["provider"] or item.get("model") != meta["model"]
        for item in meta["assistant_models"]
    ):
        return _result("inconclusive", "session_model_history_mismatch", **base)

    # If ccl-review.model resolves in the user's config, the public debug
    # agent result becomes the expected binding. A null debug model is valid and
    # means OpenCode will resolve its ordinary default during the run.
    with open(args.agent_boundary) as fh:
        agent_boundary = json.load(fh)
    configured_model = agent_boundary.get("model")
    if isinstance(configured_model, dict):
        configured_provider = configured_model.get("providerID")
        configured_model_id = configured_model.get("modelID")
        if (
            meta["provider"] != configured_provider
            or meta["model"] != configured_model_id
        ):
            return _result("inconclusive", "agent_model_mismatch", **base)

    # 6. model attribution + family independence. Both sides go through the same
    #    table so `--implementer-family anthropic` cannot bypass `claude`, and an
    #    unmapped implementer family fails closed (independence unverifiable).
    reviewer_family = family_for_provider(meta["provider"])
    if not reviewer_family:
        return _result("inconclusive", "missing_or_unmapped_reviewer_family", **base)
    base["reviewer_family"] = reviewer_family
    implementer_family = normalize_family(args.implementer_family)
    if not implementer_family:
        return _result("inconclusive", "unmapped_implementer_family", **base)
    if reviewer_family == implementer_family:
        return _result("inconclusive", "same_family_as_implementer", **base)

    # 7. the run must have finished (stop) with non-empty final text.
    if meta["final_reason"] != "stop" or not meta["final_text"]:
        if transport_timed_out:
            return _result("inconclusive", "reviewer_timeout", **base)
        extra = {"text": meta["final_text"]} if meta["final_text"] else {}
        return _result("inconclusive", "missing_final_text", **extra, **base)

    # 8. content verdict, with schema validation so praise/refusals don't pass.
    if transport_timed_out and not args.required_concern:
        return _result("inconclusive", "reviewer_timeout", **base)
    parsed_review = parse_review_text(meta["final_text"])
    if parsed_review is not None:
        status, concern_results, findings = parsed_review
        if transport_timed_out and args.required_concern:
            observed_concerns = {item["concern"] for item in concern_results}
            if observed_concerns != set(args.required_concern):
                return _result("inconclusive", "reviewer_timeout", **base)
        extra = {"text": meta["final_text"]} if findings else {}
        return _result(
            status,
            concern_results=concern_results,
            findings=findings,
            **extra,
            **base,
        )
    if transport_timed_out and not CONCERN_EVIDENCE_RE.search(meta["final_text"]):
        return _result("inconclusive", "reviewer_timeout", **base)
    return _result(
        "inconclusive", "unparseable_findings", text=meta["final_text"], **base
    )


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--events")
    p.add_argument("--export")
    p.add_argument("--agent-boundary", required=True)
    p.add_argument("--exit-code", type=int, default=0)
    p.add_argument("--mode", choices=["review", "challenge"], default="review")
    p.add_argument("--implementer-family", required=True)
    p.add_argument("--require-skill-tool", action="store_true")
    p.add_argument("--required-concern", action="append", default=[])
    args = p.parse_args(argv)

    result = judge(args)
    print(json.dumps(result))
    return 0 if result["status"] in ("passed", "findings") else 2


if __name__ == "__main__":
    sys.exit(main())
