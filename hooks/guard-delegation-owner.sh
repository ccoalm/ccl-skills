#!/usr/bin/env bash
# PreToolUse hook — delegation-owner invoke gate.
# Asks when the controller dispatches a worker (Task/Agent tool) without having
# visibly invoked ccl-skills:multi-agent-delegation this session.
#
# Why this firing point exists: a controller that only delegates edits nothing, so
# every other owner-dispatch surface (file-edit PreToolUse, Stop-hook dirty-tree
# evidence) stays silent. Substance is produced by the worker, so the "before you
# produce substance" gates never fire controller-side either. Dispatch itself is
# the only observable moment.
#
# State design — cache the SAFE direction only:
#   An earlier version cached "already asked", which adversarial review showed
#   inverted the gate twice over: (a) in a fan-out the first hook created the
#   marker and the nine siblings sailed through before the user could answer one
#   prompt, and (b) the marker recorded that a prompt was EMITTED, not approved,
#   so a denial silenced every later dispatch in the session. So nothing about the
#   ask is cached. Only the verified-loaded state is, because that state never
#   reverts: once the owner is in the transcript it stays there. Cold dispatches
#   therefore keep asking until the owner is actually loaded, which is the only
#   action that makes this gate quiet.
#
# Safety posture:
# - HARD FAIL-OPEN on absent evidence: no jq, no transcript, non-regular
#   transcript => allow silently. The gate is a nudge, never a blocker.
# - Claude: "ask", never "deny". Codex: bounded additionalContext only.
# - Never echoes transcript content anywhere: the transcript may hold prompt
#   payloads or secrets. Nothing is written to stderr.
# - Evidence is the structured Skill tool-use event on a single JSONL line, not
#   free prose, so narrative text mentioning the skill name is not accepted.
#
# Considered and declined: returning `ask` on uncertainty (missing jq, absent or
# unreadable transcript) once we know this is a dispatch. It sounds stricter, but
# on a host that never supplies a transcript path it prompts on every dispatch
# forever with no action that can satisfy it — loading the owner would not help,
# because the hook cannot see that either. A gate with no escape gets approved
# reflexively, which is worse than staying quiet. Fail-open is the deliberate
# choice for unverifiable environments, not an oversight.
#
# Known accepted gaps (advisory local nudge, not an enforcement boundary):
# - Hosts whose dispatch tool is named otherwise.
# - Native skill preloading that emits no Skill event (fails toward asking).
# - A crafted transcript line carrying a real-shaped Skill event; and a local
#   user who can pre-create the verified marker, or edit this file outright. The
#   trust model is a cooperating developer on their own machine.
# - Transcript inspection is bounded to 20,000 JSONL events; later evidence may
#   be missed. Host timeout also bounds slow filesystem reads.
set -u
IN=$(cat 2>/dev/null) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
  Task|Agent|spawn_agent) ;;
  *) exit 0 ;;
esac

# session_id feeds a file path: strip to a safe charset and cap length so a
# hostile/garbled value (e.g. containing ../ or /) cannot traverse out of TMPDIR.
SESSION_RAW=$(printf '%s' "$IN" | jq -r '.session_id // empty' 2>/dev/null)
SESSION=$(printf '%s' "$SESSION_RAW" | tr -cd 'A-Za-z0-9._-' | cut -c1-40)
UID_PART=$(id -u 2>/dev/null || echo u)
TRANSCRIPT=$(printf '%s' "$IN" | jq -r '.transcript_path // empty' 2>/dev/null)
# Sanitizing and truncating the id alone collides: `team/a` and `teama`, or any
# two ids sharing a long prefix, would share one cache entry and one session
# could then vouch for another. Bind a checksum of the RAW id plus the
# transcript path so distinct sessions cannot land on the same marker.
KEYSUM=$(printf '%s|%s' "$SESSION_RAW" "$TRANSCRIPT" | cksum 2>/dev/null | tr -cd '0-9' | cut -c1-20)
# Only set when the owner has been SEEN loaded. A session with no usable id gets
# no cache at all rather than sharing a `nosession` bucket with every other one.
VERIFIED=""
[ -n "$SESSION" ] && [ -n "$KEYSUM" ] \
  && VERIFIED="${TMPDIR:-/tmp}/delegation-owner-loaded-${UID_PART}-${SESSION}-${KEYSUM}"

# Owner already verified loaded this session -> allow without touching the file.
[ -n "$VERIFIED" ] && [ -d "$VERIFIED" ] && exit 0

# Regular files only: a FIFO or device at this path would block the read and
# stall the tool call until the hook timeout.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# Shared boundary parser recognizes Claude Skill request/result pairs and
# successful Codex literal SKILL.md reads. Request-only and failed calls do not
# establish completion. Transcript text is never copied into hook output.
HELPER="$(cd "$(dirname "$0")" && pwd)/host-input.py"
command -v python3 >/dev/null 2>&1 && [ -r "$HELPER" ] || {
  jq -nc '{systemMessage:"Delegation routing reminder unavailable: Python input normalizer missing; skill loading could not be verified."}'
  exit 0
}
SUMMARY=$(python3 "$HELPER" transcript "$TRANSCRIPT" 2>/dev/null) || exit 0
if printf '%s' "$SUMMARY" | jq -e '.completed_skills | index("ccl-skills:multi-agent-delegation") != null' >/dev/null 2>&1; then
  [ -n "$VERIFIED" ] && mkdir "$VERIFIED" 2>/dev/null
  exit 0
fi

# Codex does not support permissionDecision ask. This optional routing reminder
# is context, once per session; its marker records delivery, never approval.
if [ "$TOOL" = spawn_agent ]; then
  REMINDED="${VERIFIED:+$VERIFIED.advisory}"
  [ -n "$REMINDED" ] && [ -d "$REMINDED" ] && exit 0
  [ -n "$REMINDED" ] && mkdir "$REMINDED" 2>/dev/null
  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"Delegation routing reminder (advisory): load ccl-skills:multi-agent-delegation before dispatch and include its required owner, scope, time bound, and parent verification fields. A completed literal cat read of its SKILL.md is recognized; unsupported read formats remain unverifiable. This reminder does not grant authorization."}}'
  exit 0
fi

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Delegation-owner gate: you are dispatching a worker without having invoked ccl-skills:multi-agent-delegation this session. Controller-side delegation edits nothing, so no other owner gate fires here — and recording a delegation decision in a boundary record is not invoking the owner. Loading it supplies the dispatch-blocking fields this dispatch otherwise ships without, among them: required_skills, model_tier, a wall-clock bound, the plan-scan line, the parent verification plan, and — for any worker allowed to delegate onward — an explicit orchestrator promotion carrying a depth cap, child scope, and verbatim transcript return. Without that last one an unbounded leaf silently becomes an orchestrator. Note that read-only investigation is NOT an exemption from the owner: it is a worker class the owner itself scopes, and a delegated design or review can drive delivery just as hard as an edit. Approving proceeds for this one dispatch; loading the owner is what stops the prompting."}}
JSON
exit 0
