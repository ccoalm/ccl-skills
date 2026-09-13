#!/usr/bin/env bash
# Dispatch itself is the firing point, including dispatch-only controllers.
# One agent-facing replan per actor/context; no user approval prompt. A complete
# current-context owner load suppresses the checkpoint. Attempt markers never
# represent approval or verification, and cannot replace the owner contract.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null 2>&1 && [ -r "$SCRIPT_DIR/skill-loading.py" ] || {
  printf '%s\n' '{"systemMessage":"Delegation skill checkpoint unavailable: Python runtime missing; loading is unverified."}'
  exit 0
}
python3 "$SCRIPT_DIR/skill-loading.py" 2>/dev/null || true
exit 0
