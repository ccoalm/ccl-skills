# Permission matching validation

Candidate: `f6748369a46cad18bcd58a52c7542cb5c080df80`.
Base: `914653c657ea8ab7a73bc0f1650ff11472ea0c04`.

## Acceptance evidence

| Requirement | Observation |
| --- | --- |
| English and Chinese terminal emphasis triggers one recheck after edits or delivery evidence | Extended native-payload cases pass; each positive also checks `stop_hook_active` stays quiet |
| Repeated permission prefixes cannot exhaust the five-second hook timeout | A 1,080,000-character negative input and its terminal-question control pass in a bounded subprocess |
| Existing eligibility and example exclusions remain intact | No-event unlabelled questions, block quotes, fenced examples, whole-line backticks and completed states pass |
| Original failures are reproducible | The new cases on the original matcher produced 14 assertion failures and one five-second timeout |
| Review and challenge are independent of the repair implementer | Separate controller receipts and source-checked dispositions are in the adjacent review status file |

## Concept changes

| Mechanism | Purpose | Boundary |
| --- | --- | --- |
| One terminal emphasis pair is removed | Recognize formatted permission questions | Fixed marker choices; no Markdown dependency |
| Punctuation check is separated from phrase matching | Prevent repeated unbounded suffix scans | Existing permission vocabulary and punctuation-free request forms retained |

No stored state, schema migration, sampling, extra retry or new authorization.
Rollback is a revert of the matcher correction.

## Commands

Local snapshot at 2026-10-01 22:19 UTC. The source and target remote tips were
rechecked at this point; the target still matched the base above. PR checks
carry the subsequent Linux CI results for the pushed candidate.

- `python3 -B hooks/test_proposed_next.py`: 27 tests passed in a network-denied,
  secret-free sandbox; the full-lane repeat also passed.
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`: passed
  with the configured private audit (`alias_audit_ok`, `r0_status=private-ok`,
  `ccl_skill_check_clean_ok`).
- `python3 scripts/check-public-sanitization.py .`: passed.
- `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/dev`:
  passed before the repair commit.
- `git diff --check`: passed.
- `make -k test`: repository gates and fast regressions passed. Code-review
  shard 1 passed except the process-state helper: the macOS sandbox denies
  execution of setuid `/bin/ps`. The inspected helper passed all 11 assertions
  when rerun with the original system binary in a credential-free native
  environment. Remaining code-review tests were still running at this snapshot;
  no aggregate local pass is claimed.
- `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only`:
  nine suites passed. The historical differential suite could not create its
  worktree inside the shared Git directory under the sandbox. Rerunning that
  unchanged suite in an isolated temporary Git clone passed: 64 integration
  points, 10 named expected divergences and two replay cases, with no unexpected
  verdict change. The initial aggregate failure is retained, not relabelled.

The full lane uses an isolated venv populated from `requirements-test.txt`.
Initial environment failures were a sandbox metadata restriction on Git and
missing PyYAML after hiding user-site packages; both were corrected before the
current run. Its public R0 fallback is supplemented by the separate configured
private-audit run above.

## Evidence limits

These are synthetic hook-contract checks. They do not establish that a model
finishes a real delivery task. Unquoted reported questions can still trigger
one recheck; the disposition records that limitation. Merge and npm publication
are outside this repair's scope.
