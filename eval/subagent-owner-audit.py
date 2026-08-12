#!/usr/bin/env python3
"""Advisory runtime audit for real subagent Skill events and declarations.

WHAT THIS IS. A standing decomposition of the one-off measurement that found the defect
behind the delivery-impact exemption axis: across 73 real subagents, 48 produced
judgments (adversarial review, pre-merge gates, extraction surveys) while invoking
zero owner skills, and all 48 dispatch briefs omitted `required_skills`. This
script tracks those invocation and declaration signals over real host transcripts
so drift can be watched instead of rediscovered. Schema v2 separates actual Skill
events, ccl-scoped Skill events, and the authored brief's declared requirements.

WHAT THIS IS NOT — read before citing it.
  * NOT a merge gate. It classifies free-text briefs with keyword heuristics, and
    heuristics over open semantics do not converge (this repo has the scar tissue:
    see the shell-tokenizer rounds). Exit status is 0 unless the scan itself broke.
  * NOT a quality measure. It counts whether an owner was invoked, never whether
    the resulting verdict was better. A paired probe run while building this found
    the unowned arm reviewing at least as deeply as the owned one, so do not read a
    rising invocation rate as rising review quality.
  * NOT evidence any single dispatch was wrong. `required_skills: []` is legitimate
    for pure source-text / locating retrieval; the classifier cannot always tell.
  * NOT an oracle-owner check. Runtime records do not contain expected owners or
    judge whether an invoked owner was applied to the result.

Read the output as a dashboard: a sharp move in an invocation or declaration
metric is worth investigating; an absolute number is not a verdict.

Usage:
  eval/subagent-owner-audit.py                 # all projects, last 30 days
  eval/subagent-owner-audit.py --days 7
  eval/subagent-owner-audit.py --project sample-product --json
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
from collections import Counter

HOME = os.path.expanduser("~")
ROOT = os.path.join(HOME, ".claude", "projects")

# Judgment markers. Deliberately narrow: a miss (judgment read as retrieval) only
# understates the problem, while a false hit would manufacture alarm. Both English
# and Chinese because real briefs in this org are written in both.
JUDGMENT = re.compile(
    r"对抗评审|独立评审|评审者|评审员|合并前|最后一道闸|根因|方案比选|设计评审|提炼调研"
    r"|adversarial(?:ly)?\s+review|independent\s+review|pre-?merge\s+gate"
    r"|root[- ]cause|design\s+review|critique|assess|judge|verdict",
    re.I,
)
# Retrieval markers only matter when NO judgment marker fired; they are not a veto.
RETRIEVAL = re.compile(
    r"^\s*(locate|find|list|grep|count|搜索|查找|列出|统计)\b", re.I | re.M
)
# NOTE: `[[:space:]]` is a POSIX class, NOT Python — inside a Python character
# class it silently means "the characters :, a, c, e, p, s". An earlier draft of
# this file carried exactly that as dead code and Python warned about the nested
# set; it is spelled with \s here on purpose.
FIELD_VALUE = re.compile(
    r'^\s*(?:[-*]\s+)?"?required_skills"?\s*:\s*(.*?)\s*$', re.M
)
SKILL_ID = re.compile(r"^[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+$")

SCHEMA_VERSION = 2
EVENT_CONTRACT_VERSION = "skill-events-v1"

# Only Skill-detection topology is versioned. Unrelated tool input fields are
# normalized: a Bash or Read schema change must not degrade Skill evidence.
# Relevant Skill/tool_result keys remain exact so host drift stays visible.
SUPPORTED_EVENT_SHAPES = {
    "assistant/skill_tool_use/block:id,input,name,type/input:skill",
    "assistant/skill_tool_use/block:caller,id,input,name,type/input:skill",
    "assistant/skill_tool_use/block:caller,id,input,name,type/input:args,skill",
    "user/tool_result/block:content,tool_use_id,type",
    "user/tool_result/block:content,is_error,tool_use_id,type",
    "assistant/other_tool_use",
    "user/other_tool_use",
    "assistant/text",
    "user/text",
    "assistant/message_string",
    "user/message_string",
}

RECOVERY_RECORD = {
    "add_sanitized_known_answer_fixture": True,
    "rerun_d6": True,
    "manual_recovery_required": True,
}


def dispatch_brief(path):
    """First user text that is not the injected routing block.

    The injection itself contains both `ccl-skills:<name>` strings and the
    literal `required_skills`, so scanning raw transcript text reports fabricated
    numbers — that mistake produced three wrong measurements before this was
    written. Always isolate the brief, and count invocations from tool_use events.
    """
    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                try:
                    ev = json.loads(line)
                except Exception:
                    continue
                if ev.get("type") != "user":
                    continue
                c = (ev.get("message") or {}).get("content")
                if isinstance(c, str) and len(c) > 40 and "ccl-skills-subagent-routing" not in c:
                    return c
    except OSError:
        pass
    return None


def _ordered_unique(values):
    return list(dict.fromkeys(values))


def parse_declared_required_skills(brief):
    """Return (available, field_declared, values) for the authored brief only."""
    if not isinstance(brief, str):
        return False, False, []
    match = FIELD_VALUE.search(brief)
    if match is None:
        return True, False, []

    raw = match.group(1).strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return False, True, []
    body = raw[1:-1].strip()
    if not body:
        return True, True, []

    values = []
    for item in body.split(","):
        token = item.strip()
        if token[:1] in ('"', "'"):
            if len(token) < 2 or token[-1] != token[0]:
                return False, True, []
            value = token[1:-1]
        elif token[-1:] in ('"', "'"):
            return False, True, []
        else:
            value = token
        if not SKILL_ID.fullmatch(value):
            return False, True, []
        values.append(value)
    return True, True, _ordered_unique(values)


def _keys(value):
    return ",".join(sorted(value)) if isinstance(value, dict) else "not-object"


def _shape_id(shapes):
    payload = json.dumps(sorted(set(shapes)), separators=(",", ":"))
    return "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()


def skill_event_record(path):
    """Parse versioned Skill events without inferring owner correctness."""
    shapes = []
    requests = []
    result_success = {}
    seen_message = False
    known_shape = True

    try:
        lines = open(path, errors="ignore")
    except OSError:
        lines = ()
        shapes.append("file_unreadable")
        known_shape = False

    for line in lines:
        try:
            event = json.loads(line)
        except (TypeError, ValueError):
            shapes.append("invalid_json")
            known_shape = False
            continue
        if not isinstance(event, dict):
            shapes.append("event_not_object")
            known_shape = False
            continue

        role = event.get("type")
        if role not in ("assistant", "user"):
            continue
        message = event.get("message")
        if not isinstance(message, dict):
            shapes.append(f"{role}/message_not_object")
            known_shape = False
            continue
        content = message.get("content")
        if isinstance(content, str):
            seen_message = True
            shapes.append(f"{role}/message_string")
            continue
        if not isinstance(content, list):
            shapes.append(f"{role}/content_not_list")
            known_shape = False
            continue

        seen_message = True
        if not content:
            shapes.append(f"{role}/empty_content")
            known_shape = False
            continue
        for block in content:
            if not isinstance(block, dict):
                shapes.append(f"{role}/block_not_object")
                known_shape = False
                continue
            block_type = block.get("type")
            if block_type == "text":
                shapes.append(f"{role}/text")
                continue
            if block_type == "tool_use":
                if role == "assistant" and block.get("name") == "Skill":
                    shape = (
                        "assistant/skill_tool_use/block:"
                        + _keys(block)
                        + "/input:"
                        + _keys(block.get("input"))
                    )
                    shapes.append(shape)
                    tool_use_id = block.get("id")
                    skill = (
                        (block.get("input") or {}).get("skill")
                        if isinstance(block.get("input"), dict)
                        else None
                    )
                    if (
                        shape not in SUPPORTED_EVENT_SHAPES
                        or not isinstance(tool_use_id, str)
                        or not isinstance(skill, str)
                    ):
                        known_shape = False
                        continue
                    requests.append(
                        {
                            "skill": skill,
                            "tool_use_id": tool_use_id,
                            "matching_tool_result": False,
                            "completed": False,
                        }
                    )
                else:
                    shapes.append(f"{role}/other_tool_use")
                continue
            if block_type == "tool_result":
                shape = f"{role}/tool_result/block:" + _keys(block)
                shapes.append(shape)
                tool_use_id = block.get("tool_use_id")
                if (
                    role != "user"
                    or shape not in SUPPORTED_EVENT_SHAPES
                    or not isinstance(tool_use_id, str)
                    or (
                        "is_error" in block
                        and not isinstance(block.get("is_error"), bool)
                    )
                ):
                    known_shape = False
                    continue
                if tool_use_id in result_success:
                    known_shape = False
                    continue
                result_success[tool_use_id] = not block.get("is_error", False)

    close = getattr(lines, "close", None)
    if close is not None:
        close()

    if not seen_message:
        known_shape = False
        if not shapes:
            shapes.append("no_message_events")

    available = bool(seen_message and known_shape)
    if available:
        for request in requests:
            request["matching_tool_result"] = request["tool_use_id"] in result_success
            request["completed"] = result_success.get(request["tool_use_id"], False)
        invocations = requests
    else:
        invocations = []

    status = "stable" if available else "degraded"
    return {
        "event_contract_version": EVENT_CONTRACT_VERSION,
        "skill_events_available": available,
        "skill_invocations": invocations,
        "skills_invoked": _ordered_unique(r["skill"] for r in invocations),
        "transcript_shape_id": _shape_id(shapes),
        "event_contract_status": status,
        "owner_gate_degraded": not available,
        "degraded_reason": None if available else "unknown_transcript_shape",
        "recovery_record": None if available else dict(RECOVERY_RECORD),
    }


def runtime_record(path, brief=None):
    events = skill_event_record(path)
    declaration_available, field_declared, declared = parse_declared_required_skills(brief)
    ccl_invoked = [
        skill for skill in events["skills_invoked"] if skill.startswith("ccl-skills:")
    ]
    completed = {
        invocation["skill"]
        for invocation in events["skill_invocations"]
        if invocation["completed"]
    }
    declared_owner_skills = [
        skill for skill in declared if skill.startswith("ccl-skills:")
    ]
    declared_completed = [skill for skill in declared_owner_skills if skill in completed]

    if not events["skill_events_available"] or not declaration_available:
        owner_status = "unverifiable"
    elif not field_declared:
        owner_status = "not_declared"
    elif not declared_owner_skills:
        owner_status = "not_required"
    elif len(declared_completed) == len(declared_owner_skills):
        owner_status = "complete"
    elif declared_completed:
        owner_status = "partial"
    else:
        owner_status = "missing"

    row = {
        "schema_version": SCHEMA_VERSION,
        **events,
        "declared_required_skills_available": declaration_available,
        "required_skills_declared": field_declared,
        "declared_required_skills": declared,
        "ccl_skills_invoked": ccl_invoked,
        "declared_ccl_skills_completed": declared_completed,
        "declared_owner_match_status": owner_status,
    }
    row["compatibility_v1"] = {
        "no_skill_tool_use": (
            not bool(row["skills_invoked"]) if row["skill_events_available"] else None
        ),
        "required_skills_not_declared": (
            not field_declared if declaration_available else None
        ),
    }
    return row


def invoked_skills(path):
    """Deprecated v1 helper; retained for one schema version."""
    return skill_event_record(path)["skills_invoked"]


def classify_brief(brief):
    if not isinstance(brief, str):
        return "unclassified"
    judgment = bool(JUDGMENT.search(brief))
    if judgment:
        return "judgment"
    if RETRIEVAL.search(brief):
        return "retrieval"
    return "unclassified"


def scan(days, project_filter):
    cutoff = time.time() - days * 86400
    rows = []
    if not os.path.isdir(ROOT):
        return rows
    for proj in sorted(os.listdir(ROOT)):
        if project_filter and project_filter not in proj:
            continue
        pdir = os.path.join(ROOT, proj)
        if not os.path.isdir(pdir):
            continue
        for sess in sorted(os.listdir(pdir)):
            sdir = os.path.join(pdir, sess, "subagents")
            if not os.path.isdir(sdir):
                continue
            for fn in sorted(os.listdir(sdir)):
                if not (fn.startswith("agent-") and fn.endswith(".jsonl")):
                    continue
                fp = os.path.join(sdir, fn)
                try:
                    if os.path.getmtime(fp) < cutoff:
                        continue
                except OSError:
                    continue
                brief = dispatch_brief(fp)
                row = runtime_record(fp, brief=brief)
                row.update(
                    {
                        "project": proj,
                        "agent": fn[6:14],
                        "kind": classify_brief(brief),
                        "brief_head": (
                            brief[:70].replace("\n", " ") if brief is not None else ""
                        ),
                    }
                )
                rows.append(row)
    return rows


def build_report(rows, days, project=None):
    available_rows = [row for row in rows if row["skill_events_available"]]
    declaration_rows = [
        row for row in rows if row["declared_required_skills_available"]
    ]
    judgment_available_rows = [
        row for row in available_rows if row.get("kind") == "judgment"
    ]
    judgment_declaration_rows = [
        row for row in declaration_rows if row.get("kind") == "judgment"
    ]
    declared_ccl_owner_verifiable = [
        row
        for row in rows
        if row["declared_owner_match_status"] in {"complete", "partial", "missing"}
    ]
    unknown_shape_ids = sorted(
        {
            row["transcript_shape_id"]
            for row in rows
            if row["event_contract_status"] == "degraded"
        }
    )
    metrics = {
        "total_subagents": len(rows),
        "skill_events_available": len(available_rows),
        "no_skill_tool_use": sum(not row["skills_invoked"] for row in available_rows),
        "no_ccl_skill_use": sum(
            not row["ccl_skills_invoked"] for row in available_rows
        ),
        "judgment_no_ccl_skill_use": sum(
            not row["ccl_skills_invoked"] for row in judgment_available_rows
        ),
        "required_skills_not_declared": sum(
            not row["required_skills_declared"] for row in declaration_rows
        ),
        "judgment_required_skills_not_declared": sum(
            not row["required_skills_declared"]
            for row in judgment_declaration_rows
        ),
        "declared_owner_complete": sum(
            row["declared_owner_match_status"] == "complete" for row in rows
        ),
        "declared_owner_partial": sum(
            row["declared_owner_match_status"] == "partial" for row in rows
        ),
        "declared_owner_missing": sum(
            row["declared_owner_match_status"] == "missing" for row in rows
        ),
        "declared_owner_not_required": sum(
            row["declared_owner_match_status"] == "not_required" for row in rows
        ),
        "unverifiable": sum(
            row["declared_owner_match_status"] == "unverifiable" for row in rows
        ),
        "owner_gate_degraded": bool(unknown_shape_ids),
        "unknown_transcript_shape_ids": unknown_shape_ids,
        "denominators": {
            "all_subagents": len(rows),
            "skill_events_available": len(available_rows),
            "declaration_available": len(declaration_rows),
            "required_skills_declared": sum(
                row["required_skills_declared"] for row in declaration_rows
            ),
            "judgment_skill_events_available": len(judgment_available_rows),
            "judgment_declaration_available": len(judgment_declaration_rows),
            "declared_ccl_owner_verifiable": len(
                declared_ccl_owner_verifiable
            ),
        },
        "by_kind": dict(
            sorted(Counter(row.get("kind", "unclassified") for row in rows).items())
        ),
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "event_contract_version": EVENT_CONTRACT_VERSION,
        "window_days": days,
        "project_filter": project,
        "metrics": metrics,
        "rows": rows,
    }


def render_report(report):
    metrics = report["metrics"]
    denominators = metrics["denominators"]
    metric_denominators = {
        "no_skill_tool_use": "skill_events_available",
        "no_ccl_skill_use": "skill_events_available",
        "judgment_no_ccl_skill_use": "judgment_skill_events_available",
        "required_skills_not_declared": "declaration_available",
        "judgment_required_skills_not_declared": "judgment_declaration_available",
        "declared_owner_complete": "declared_ccl_owner_verifiable",
        "declared_owner_partial": "declared_ccl_owner_verifiable",
        "declared_owner_missing": "declared_ccl_owner_verifiable",
        "declared_owner_not_required": "required_skills_declared",
        "unverifiable": "all_subagents",
    }
    lines = [
        (
            "subagent_owner_audit"
            f"  schema={report['schema_version']}"
            f"  event_contract={report['event_contract_version']}"
            f"  window={report['window_days']}d"
            f"  subagents={metrics['total_subagents']}"
        )
    ]
    if metrics["by_kind"]:
        lines.append(
            "  by kind: "
            + ", ".join(f"{key}={value}" for key, value in metrics["by_kind"].items())
        )
    for name in (
        "no_skill_tool_use",
        "no_ccl_skill_use",
        "judgment_no_ccl_skill_use",
        "required_skills_not_declared",
        "judgment_required_skills_not_declared",
        "declared_owner_complete",
        "declared_owner_partial",
        "declared_owner_missing",
        "declared_owner_not_required",
        "unverifiable",
    ):
        denominator_name = metric_denominators[name]
        denominator = denominators[denominator_name]
        rate = metrics[name] / denominator if denominator else 0.0
        lines.append(
            f"  {name}: {metrics[name]}/{denominator} ({rate:.1%}; "
            f"denominator={denominator_name})"
        )
    if metrics["owner_gate_degraded"]:
        lines.append(
            "  owner_gate_degraded: true"
            f"  unknown_transcript_shape_ids={','.join(metrics['unknown_transcript_shape_ids'])}"
        )
        lines.append(
            "  recovery: add a sanitized known-answer fixture, rerun D6, then recover manually"
        )
    else:
        lines.append("  owner_gate_degraded: false")
    lines.append(
        "  advisory only — reports invocation and declaration evidence; does not measure outcomes"
    )
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--project", default=None)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    rows = scan(a.days, a.project)
    report = build_report(rows, a.days, a.project)
    if a.json:
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0

    if not rows:
        print(f"subagent_owner_audit: no subagent transcripts in the last {a.days}d")
        return 0
    print(render_report(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
