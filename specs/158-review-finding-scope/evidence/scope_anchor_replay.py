"""Replay a staged review of an over-designed plan under four packet shapes.

Usage: python3 scope_anchor_replay.py <runs> --candidate-file PATH [--client claude|codex]
                                      [--arms A,B,C,D] [--raw-dir DIR] [--matched | --requested-fix]

The packet has the shape observed in a corrected session, in a neutral domain:
the request asks for an automatic template check before export and only a record
of differences after it, and the plan turns that record into a blocking gate
with credentials, a holding area, a staged enforcement rollout and an admin
override. Arms:

  A  current concern text, intent is the implementer's restatement only
  B  current concern text, intent also quotes the requester's own words
  C  candidate `compatibility` text (--candidate-file), intent quotes the words
  D  candidate `compatibility` text, restatement only

--matched swaps in a plan that does exactly what the request asks (a check and
fix before export, differences recorded after it, nothing blocked): a scope
finding there is a false positive of the lens. (Its first version also added a
weekly review of the differences, which the request does not ask for;
reviewers flagged that step, so it was removed.) --requested-fix swaps in a request
to fix a defect that predates the change and a plan that fixes exactly that: a
finding that calls the fix droppable is the over-correction the lens must avoid.

A run counts as flagging the over-design when one of its findings says a gate,
permission, override, rollout or blocking step is not requested, should be
dropped, or contradicts the request. Raw outputs go to --raw-dir for reading by
hand; the regex is a recall aid, not the verdict. Advisory measurement only.
"""
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import tempfile

CONCERNS = [
    ("correctness", "Functional correctness and acceptance coverage."),
    ("safety", "Data-loss, security, privacy, permission, and unsafe-mutation paths."),
    ("failure_paths", "Boundary, error, recovery, concurrency, and partial-failure behavior."),
    ("tests_evidence", "Tests and evidence that would fail when the risky behavior exists."),
    ("compatibility", "Compatibility, maintainability, and unnecessary-complexity regressions."),
    ("claim_strength", "Claims the cited evidence does not carry: absolutes, universals, causal statements, "
                       "exhaustiveness."),
]

RESTATEMENT = "Add a platform quality gate so exported reports match the confirmed report template."
REQUEST = "Requester's own words: 「导出前自动检查并修正报表模板；导出后的差异只记录下来做观察。」"

DIFF = r'''diff --git a/docs/plans/report-quality.md b/docs/plans/report-quality.md
new file mode 100644
@@ -0,0 +1,14 @@
+# Platform quality gate for exported reports
+1. The user confirms in the template panel whether the export keeps the template layout, adapts it, or uses none;
+   the platform binds the choice to the template version, export job and data snapshot so the export service
+   cannot skip the check by omitting the template.
+2. Report rendering runs as today. Afterwards the platform samples pages, fills a per-field checklist and verifies
+   it; only with a credential matching the template and data snapshot may the export service publish the report
+   to the shared folder or notify subscribers. Unchecked reports stay in a private holding area.
+3. When the check finds a difference, the export service revises the template mapping and waits for the user to
+   reconfirm; no automatic re-render. If the check is unavailable, report a fault, never a pass.
+4. Manual downloads do not wait for the check; the download continues and its check report arrives later.
+5. Rollout: observe on staging first, then enforce the gate for one internal team and one report family at a
+   time; admins get a permission override to bypass the gate.
+
+Status: template confirmation already exists and is fully rolled out; the quality gate is new.
'''

MATCHED_DIFF = r'''diff --git a/docs/plans/report-quality.md b/docs/plans/report-quality.md
new file mode 100644
@@ -0,0 +1,6 @@
+# Template check before export, difference log after it
+1. Before rendering, the export service runs the existing template check on the confirmed template and the data
+   snapshot, and applies its automatic mapping fixes; anything it cannot fix is listed in the export log.
+2. After rendering, the service compares the report with the template and appends the differences to the
+   observation table. Publication, notifications and downloads never wait for or depend on this comparison.
+'''

FIX_RESTATEMENT = "Fix duplicate charges caused by export retries."
FIX_REQUEST = "Requester's own words: 「修复导出重试导致的重复扣费。」"
FIX_DIFF = r'''diff --git a/docs/plans/export-retry-charges.md b/docs/plans/export-retry-charges.md
new file mode 100644
@@ -0,0 +1,6 @@
+# Stop duplicate charges from export retries
+1. The retry worker sends an idempotency key derived from the export job with every submission.
+2. After a read timeout, it queries the job state with that key and resubmits only when no job exists.
+3. A regression test makes a submission time out, retries it, and asserts that one job and one charge exist.
+'''

PROMPT = '''Review this diff using the controller-frozen staged review profile below.
Return only JSON: {{"status": "passed" | "findings", "findings": [{{"severity": "P0|P1|P2", "file": "...", "line": 1, "failure_path": "...", "smallest_fix": "..."}}]}}.

Profile:
{profile}

Candidate diff:
{diff}'''

UNNEEDED = re.compile(r'(not (?:requested|asked|needed|required)|does not (?:ask|need|require)|unrequested|exceed|'
                      r'beyond (?:the|what)|over-?design|over-?engineer|exist only|only because|drop|remove|'
                      r'observ\w* only|for observation|做观察|contradict)', re.I)
MECHANISM = re.compile(r'(gate|credential|permission|override|rollout|enforce|block)', re.I)


def ask(job):
    prompt, client = job
    with tempfile.TemporaryDirectory() as empty:
        if client == 'codex':
            last = os.path.join(empty, 'last.txt')
            subprocess.run(['codex', 'exec', '--disable', 'hooks', '--disable', 'shell_tool', '--sandbox', 'read-only',
                            '--ephemeral', '--skip-git-repo-check', '-c', 'web_search="disabled"',
                            '-c', 'approval_policy="never"', '--output-last-message', last, '-C', empty, '-'],
                           input=prompt, capture_output=True, text=True, timeout=900)
            try:
                text = open(last, encoding='utf-8').read()
            except OSError:
                text = ''
        else:
            text = subprocess.run(['claude', '--print', '--tools', '', '--settings', '{"disableAllHooks":true}',
                                   '--model', 'claude-opus-5-5'],
                                  input=prompt, capture_output=True, text=True, cwd=empty, timeout=600).stdout
    match = re.search(r'\{.*\}', text, re.S)
    try:
        findings = json.loads(match.group(0)).get('findings', []) if match else None
    except json.JSONDecodeError:
        findings = None
    if findings is None:
        return 'unparsed', text
    hits = [f for f in findings
            if UNNEEDED.search(t := str(f.get('failure_path', '')) + ' ' + str(f.get('smallest_fix', '')))
            and MECHANISM.search(t)]
    return f'{len(hits)}/{len(findings)}', text


def main():
    runs = int(sys.argv[1])
    args = sys.argv[2:]
    client = args[args.index('--client') + 1] if '--client' in args else 'claude'
    candidate = open(args[args.index('--candidate-file') + 1], encoding='utf-8').read().strip()
    arms = args[args.index('--arms') + 1].split(',') if '--arms' in args else ['A', 'B', 'C', 'D']
    raw_dir = args[args.index('--raw-dir') + 1] if '--raw-dir' in args else None
    shapes = {'A': (False, False), 'B': (False, True), 'C': (True, True), 'D': (True, False)}
    for arm in arms:
        amended, quoted = shapes[arm]
        concerns = [(cid, candidate if amended and cid == 'compatibility' else text) for cid, text in CONCERNS]
        fix = '--requested-fix' in args
        restatement, request = (FIX_RESTATEMENT, FIX_REQUEST) if fix else (RESTATEMENT, REQUEST)
        profile = json.dumps({
            'intent': restatement + ('\n' + request if quoted else ''),
            'acceptance': ['The plan can be implemented and rolled out safely.'],
            'required_concerns': [{'id': cid, 'description': text} for cid, text in concerns],
        }, ensure_ascii=False, indent=1)
        diff = FIX_DIFF if fix else (MATCHED_DIFF if '--matched' in args else DIFF)
        prompt = PROMPT.format(profile=profile, diff=diff)
        with concurrent.futures.ThreadPoolExecutor(runs) as pool:
            results = list(pool.map(ask, [(prompt, client)] * runs))
        tag = 'requested-fix-' if fix else ('matched-' if '--matched' in args else '')
        print(client, tag + arm, json.dumps([r for r, _ in results]), flush=True)
        if raw_dir:
            with open(os.path.join(raw_dir, f'scope-anchor-{client}-{tag}{arm}.json'), 'w', encoding='utf-8') as out:
                json.dump([t for _, t in results], out, ensure_ascii=False)


if __name__ == '__main__':
    main()
