#!/usr/bin/env bash
# PreCompact snapshots the old boundary; only PostCompact invalidates context.
# Guidance is deferred to PreToolUse; these callbacks never grant permission.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null 2>&1 && [ -r "$SCRIPT_DIR/skill-loading.py" ] || {
  printf '%s\n' '{"systemMessage":"Skill context reset unavailable: Python checkpoint runtime missing."}'
  exit 0
}
python3 "$SCRIPT_DIR/skill-loading.py" 2>/dev/null || true
exit 0
