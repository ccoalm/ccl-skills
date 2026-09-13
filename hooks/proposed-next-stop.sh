#!/usr/bin/env bash
# Optional Stop formatting backstop, once per host user turn via stop_hook_active.
# It neither establishes product intent nor authorizes a next action. Source
# review that exposes the full canonical rule can produce one advisory repair.
# No transcript echo, host configuration reads, or filesystem markers.
set -u
HELPER="$(cd "$(dirname "$0")" && pwd)/host-input.py"
if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$HELPER" ]; then
  printf '%s\n' '{"systemMessage":"Delivery handoff reminder unavailable: Python input normalizer missing."}'
  exit 0
fi
python3 "$HELPER" proposed-next 2>/dev/null ||
  printf '%s\n' '{"systemMessage":"Delivery handoff reminder unavailable: input normalizer failed."}'
exit 0
