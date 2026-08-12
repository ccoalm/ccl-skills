#!/usr/bin/env bash
# Stop / SubagentStop handler — owner-dispatch closeout backstop.
# Wired to BOTH the main Stop and SubagentStop (the engine reads agent_id from stdin to
# tell them apart and scope per-subagent). Thin wrapper: delegates to the shared engine
# and is hard FAIL-OPEN — it always exits 0, forwarding the engine's block JSON only when
# produced cleanly (rc 0 + non-empty). Any engine error/crash/timeout => no output => stop
# allowed. Blocks AT MOST ONCE per actor per session (capped + waiver) so it can never
# trap the user. Claude-Code-only hard enforcement; advisory on Codex.
ENGINE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/owner-dispatch/owner-dispatch.sh"
[ -r "$ENGINE" ] || exit 0
out=$(bash "$ENGINE" stop 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] && printf '%s' "$out"
exit 0
