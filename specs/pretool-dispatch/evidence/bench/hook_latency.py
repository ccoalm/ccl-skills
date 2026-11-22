#!/usr/bin/env python3
"""Compare PreToolUse hook latency of two plugin trees on the same payloads.

Usage: hook_latency.py <baseline-root> <candidate-root> <project-dir>

Each root is an extracted tree containing hooks/, scripts/, agent-context/ and
skills/skill-extraction-workflow/scripts/ (for example `git archive <rev> ...`).
<project-dir> is an ordinary git checkout used as the hook cwd. All three paths
are resolved before any hook runs.

Reported per call class, median of 11 runs in ms:
  parallel - every hook started at once (how Claude Code runs matching hooks)
  serial   - hooks one after another (how the OpenCode plugin and agy-bridge run them)

A hook that exits non-zero, times out or prints a degrade warning stops the
run: its timing would measure the failure, not the hook.
"""
import concurrent.futures as cf
import json
import os
import statistics
import subprocess
import sys
import time

BASH = ['owner-dispatch-guard.sh', 'guard-merge-authorization.sh', 'guard-broad-local-test.sh',
        'remind-unverified-cli-flag.sh', 'remind-untracked-background.sh', 'remind-review-covers-head.sh']
EDIT = ['guard-edit-isolation.sh', 'owner-dispatch-guard.sh']
TIMEOUT = 30


def payload(cwd, tool, tool_input):
    return json.dumps({'session_id': 'bench1', 'transcript_path': '', 'cwd': cwd,
                       'hook_event_name': 'PreToolUse', 'tool_name': tool, 'tool_input': tool_input})


def run(root, script, data, cwd):
    proc = subprocess.run(['bash', f'{root}/hooks/{script}'], input=data, capture_output=True,
                          text=True, cwd=cwd, env=dict(os.environ, CLAUDE_PLUGIN_ROOT=root),
                          timeout=TIMEOUT)
    if proc.returncode != 0 or 'degraded' in proc.stdout:
        sys.exit(f'{root}/hooks/{script}: exit {proc.returncode}: {proc.stdout[:200]}{proc.stderr[:200]}')


def timed(fn):
    start = time.perf_counter()
    fn()
    return (time.perf_counter() - start) * 1000


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    base, cand, cwd = (os.path.realpath(p) for p in sys.argv[1:4])
    for root in (base, cand):
        for script in set(BASH + EDIT):
            if not os.path.isfile(f'{root}/hooks/{script}'):
                sys.exit(f'missing {root}/hooks/{script}')
    cases = {'bash': (BASH, payload(cwd, 'Bash', {'command': 'ls -la'})),
             'edit': (EDIT, payload(cwd, 'Edit', {'file_path': cwd + '/x.txt',
                                                  'old_string': 'a', 'new_string': 'b'}))}
    for name, (scripts, data) in cases.items():
        rows = {k: [] for k in ('base-parallel', 'base-serial', 'cand-parallel', 'cand-serial')}
        for _ in range(11):
            for label, root in (('base', base), ('cand', cand)):
                with cf.ThreadPoolExecutor(len(scripts)) as pool:
                    rows[f'{label}-parallel'].append(
                        timed(lambda: list(pool.map(lambda s: run(root, s, data, cwd), scripts))))
                rows[f'{label}-serial'].append(timed(lambda: [run(root, s, data, cwd) for s in scripts]))
        print(name, ' '.join(f'{k} {statistics.median(v):.0f}' for k, v in rows.items() if v))


if __name__ == '__main__':
    main()
