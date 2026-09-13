#!/usr/bin/env bash
# PreToolUse handler — owner-dispatch firing gate (fast path).
# Existing opt-in policy takes precedence. The default source-edit checkpoint
# creates one model replan opportunity per actor/context; it is not a load-proof
# gate. Failures preserve the engine output and never synthesize an allow.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IN=$(cat 2>/dev/null) || exit 0
ENGINE="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/owner-dispatch/owner-dispatch.sh"
out=""
if [ -r "$ENGINE" ]; then
  out=$(printf '%s' "$IN" | bash "$ENGINE" pretool 2>/dev/null) || out=""
fi
if command -v python3 >/dev/null 2>&1 && [ -r "$SCRIPT_DIR/skill-loading.py" ]; then
  result=$(printf '%s' "$IN" | python3 "$SCRIPT_DIR/skill-loading.py" "$out" 2>/dev/null)
  if [ $? -eq 0 ]; then
    [ -n "$result" ] && printf '%s' "$result"
    exit 0
  fi
fi
[ -n "$out" ] && printf '%s' "$out"
exit 0
