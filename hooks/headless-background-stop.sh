#!/usr/bin/env bash
# Stop guard for sessions nothing re-invokes (claude -p, the SDKs): one block per background
# task still running at the stop, because the host stops those tasks when the session ends and
# work waiting on them is lost. Interactive sessions exit here untouched. Reads only the hook
# input, never the transcript or host configuration.
set -u
case "${CLAUDE_CODE_ENTRYPOINT:-}" in
  sdk|sdk-*) ;;
  *) exit 0 ;;
esac
HELPER="$(cd "$(dirname "$0")" && pwd)/host-input.py"
if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$HELPER" ]; then
  printf '%s\n' '{"systemMessage":"Background task check unavailable: Python input normalizer missing."}'
  exit 0
fi
python3 "$HELPER" headless-background 2>/dev/null ||
  printf '%s\n' '{"systemMessage":"Background task check unavailable: input normalizer failed."}'
exit 0
