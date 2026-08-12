#!/usr/bin/env bash
# PreToolUse handler — owner-dispatch firing gate (fast path).
# Thin wrapper: delegates to the shared engine and is hard FAIL-OPEN — it always
# exits 0, and only forwards the engine's decision JSON when the engine produced it
# cleanly (rc 0 + non-empty). Any engine error/crash/timeout => no output => allow.
# Enforcement is hard only on Claude Code; Codex runs this hook but ignores the
# decision (advisory). Host-agnostic hard enforcement is the engine's `ci` subcommand.
ENGINE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/owner-dispatch/owner-dispatch.sh"
[ -r "$ENGINE" ] || exit 0
out=$(bash "$ENGINE" pretool 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ -n "$out" ] && printf '%s' "$out"
exit 0
