#!/usr/bin/env bash
# Deliver the canonical task entry before sampling, without inspecting the prompt.
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  printf 'ccl-skills task-entry: python3 unavailable; task entry omitted\n' >&2
  printf '{}\n'
  exit 0
fi
python3 - "$SCRIPT_DIR/../agent-context/session-start.md" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], 'rb') as stream:
        raw = stream.read(32769)
    if len(raw) > 32768:
        raise ValueError('oversized source')
    source = raw.decode('utf-8')
    opening = '<ccl-skills-routing priority="high">'
    start = '<!-- ccl:entry-routing:start -->'
    end = '<!-- ccl:entry-routing:end -->'
    if not source.startswith(opening) or source.count(start) != 1 or source.count(end) != 1:
        raise ValueError('invalid routing frame')
    if source.index(start) >= source.index(end):
        raise ValueError('invalid routing order')
    entry = source[len(opening):source.index(end) + len(end)].strip()
    boundary = ('Before task-specific investigation or substantive analysis, load the owning SKILL.md body. '
                'Read long skill bodies in bounded chunks until complete; a partial read is not a load. '
                'Verify the end of SKILL.md before proceeding. '
                'Wait for the skill read results before dependent investigation tools; do not batch these reads together. '
                'Discovery and required contract reads may come first; do not wait for a source edit. '
                'Apply skills already loaded in the current context without redundant reads. '
                'A trivial self-contained answer needs no workflow.\n\n'
                'For an authorized implementation or repair, unrun, failed or inconclusive verification is unfinished work. '
                'Inspect failure evidence, research or change the approach, repair safely and rerun the relevant checks. '
                'A report alone does not complete it. Continue available authorized work; hand back only for a '
                'required user decision or unavailable authority/resource, stating the concrete blocker.\n\n')
    context = '<ccl-task-entry>\n' + boundary + entry + '\n</ccl-task-entry>'
    if len(context.encode('utf-8')) > 4096:
        raise ValueError('oversized entry')
    print(json.dumps({'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit', 'additionalContext': context}}))
except (OSError, UnicodeError, ValueError):
    print('ccl-skills task-entry: canonical entry unavailable or invalid; task entry omitted', file=sys.stderr)
    print('{}')
PY
