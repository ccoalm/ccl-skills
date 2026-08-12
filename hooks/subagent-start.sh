#!/usr/bin/env bash
# SubagentStart hook — injects a slim, self-gating ccl-skills routing pointer into
# every dispatched subagent. WHY: SessionStart's additionalContext is NOT inherited by
# subagents (verified against Claude Code docs), so a cold worker never sees the CCL
# routing and silently skips owning-skill invocation — the recurring "controller had to
# remind it" miss. This raises salience for impl/test/design/doc workers while explicitly
# telling read-only workers (Explore etc.) to ignore it, and it never overrides an
# owner-set the controller already named in the dispatch prompt.
#
# Informational only: SubagentStart cannot block. The blocking backstop for a subagent
# that edits gated product code is owner-dispatch-stop.sh wired to SubagentStop.
#
# Fails soft: any internal error still emits valid JSON so subagent spawn is never broken.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)"
ROUTING="${PLUGIN_ROOT}/agent-context/subagent-start.md"

emit_empty() { printf '{}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || emit_empty
[ -r "$ROUTING" ] || emit_empty

jq -Rs --arg evt "SubagentStart" \
  '{hookSpecificOutput:{hookEventName:$evt, additionalContext:.}}' \
  "$ROUTING" 2>/dev/null || emit_empty
