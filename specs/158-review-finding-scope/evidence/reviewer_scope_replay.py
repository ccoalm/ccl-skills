"""Replay a staged review of an over-grown hotfix under two concern texts.

Usage: python3 reviewer_scope_replay.py <runs> --candidate-file PATH [--client claude|codex]

The packet is a synthetic hotfix whose stated goal is one path-escaping fix,
while the diff also adds a configuration switch, an idempotency rework of an
untouched retry worker, a manual-review queue and a compatibility shim. The
base arm lists the build-stage concerns as the controller states them today;
the candidate arm replaces the `compatibility` description with the text in
--candidate-file. A run counts as flagging scope when at least one returned
finding names a change the stated goal does not need; the grader prints the
per-run count so the reading can be checked by eye. Advisory measurement only.
"""
import concurrent.futures
import json
import re
import subprocess
import sys
import tempfile

BASE_CONCERNS = [
    ("correctness", "Functional correctness and acceptance coverage."),
    ("safety", "Data-loss, security, privacy, permission, and unsafe-mutation paths."),
    ("failure_paths", "Boundary, error, recovery, concurrency, and partial-failure behavior."),
    ("tests_evidence", "Tests and evidence that would fail when the risky behavior exists."),
    ("compatibility", "Compatibility, maintainability, and unnecessary-complexity regressions."),
    ("claim_strength", "Claims the cited evidence does not carry: absolutes, universals, causal statements, "
                       "exhaustiveness."),
]

INTENT = ("Hotfix: paid report exports fail when the report file name contains a space, because the export "
          "service builds the storage path without escaping. Fix the path escaping and add a regression test. "
          "This ships as a production hotfix today.")

DIFF = r'''diff --git a/export/path_builder.py b/export/path_builder.py
@@ -30,9 +30,14 @@ def build_storage_path(report):
-    return f"{report.tenant}/{report.date}/{report.name}.csv"
+    if not settings.EXPORT_PATH_ESCAPE_ENABLED:
+        return f"{report.tenant}/{report.date}/{report.name}.csv"
+    safe = quote(report.name, safe="")
+    return f"{report.tenant}/{report.date}/{safe}.csv"
diff --git a/export/settings.py b/export/settings.py
@@ -12,3 +12,5 @@
+# Kill switch for the new path escaping; on by default.
+EXPORT_PATH_ESCAPE_ENABLED = env_bool("EXPORT_PATH_ESCAPE_ENABLED", True)
diff --git a/export/retry_worker.py b/export/retry_worker.py
@@ -70,22 +70,41 @@ def resubmit(job):
-    client.submit(job.payload)
+    key = idempotency_key(job)
+    state = client.query(key)
+    if state in ("accepted", "running", "done"):
+        return state
+    if state == "unknown":
+        manual_review.enqueue(job, reason="submission outcome unknown")
+        return "held"
+    client.submit(job.payload, idempotency_key=key)
diff --git a/export/manual_review.py b/export/manual_review.py
new file mode 100644
@@ -0,0 +1,38 @@
+class ManualReviewQueue:
+    """Holds exports whose paid submission outcome is unknown until an operator settles them."""
+    def enqueue(self, job, reason): ...
+    def settle(self, job_id, outcome, operator): ...
diff --git a/admin/routes.py b/admin/routes.py
@@ -101,3 +101,19 @@
+def settle_export(job_id: str, outcome: str, user=Depends(require_admin)):
+    return manual_review.settle(job_id, outcome, operator=user.id)
+router.add_api_route("/admin/exports/{job_id}/settle", settle_export, methods=["POST"])
diff --git a/export/legacy_records.py b/export/legacy_records.py
new file mode 100644
@@ -0,0 +1,25 @@
+def read_job(record):
+    """Compatibility reader for job records written before the idempotency key existed."""
+    ...
diff --git a/tests/test_path_builder.py b/tests/test_path_builder.py
@@ -0,0 +1,12 @@
+def test_space_in_name_is_escaped():
+    assert build_storage_path(Report(name="q3 sales", tenant="t1", date="2026-09-30")).endswith("q3%20sales.csv")
'''

PROMPT = '''Review this diff using the controller-frozen staged review profile below.
Return only JSON: {{"status": "passed" | "findings", "findings": [{{"severity": "P0|P1|P2", "file": "...", "line": 1, "failure_path": "...", "smallest_fix": "..."}}]}}.

Implementer intent:
{intent}

Concerns to review (each finding should map to one):
{concerns}

Candidate diff:
{diff}'''

SCOPE = re.compile(r'(not (?:required|needed) by|beyond|outside|unrelated|scope|split|separate (?:change|pr|mr|work)|'
                   r'stated goal|hotfix (?:does not|doesn\'t) need|not part of the hotfix)', re.I)


def ask(job):
    prompt, client = job
    with tempfile.TemporaryDirectory() as empty:
        if client == 'codex':
            last = empty + '/last.txt'
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
        return 'unparsed'
    scoped = [f for f in findings if SCOPE.search(str(f.get('failure_path', '')) + ' ' + str(f.get('smallest_fix', '')))]
    return f'{len(scoped)}/{len(findings)}'


def main():
    runs = int(sys.argv[1])
    args = sys.argv[2:]
    client = args[args.index('--client') + 1] if '--client' in args else 'claude'
    candidate = open(args[args.index('--candidate-file') + 1], encoding='utf-8').read().strip()
    for label in ('base', 'candidate'):
        concerns = [(cid, candidate if (label == 'candidate' and cid == 'compatibility') else text)
                    for cid, text in BASE_CONCERNS]
        prompt = PROMPT.format(intent=INTENT, diff=DIFF,
                               concerns='\n'.join(f'- {cid}: {text}' for cid, text in concerns))
        with concurrent.futures.ThreadPoolExecutor(runs) as pool:
            results = list(pool.map(ask, [(prompt, client)] * runs))
        print(client, label, json.dumps(results), flush=True)


if __name__ == '__main__':
    main()
