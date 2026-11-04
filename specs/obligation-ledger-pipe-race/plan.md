# Obligation-ledger suite pipe race

`skill-extraction-workflow/scripts/test_obligation_ledger.sh` reports failures for checks that hold. Its text checks read the audit output through `printf '%s\n' "$out" | grep -q …` under `set -euo pipefail`. `specs/regression-suite-flakes` removed that race from three other suites and listed the rest under Residual risk. This round converts this suite, which blocked the local fast lane on the 0.18.15 release candidate.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Stop false failures of `test_obligation_ledger.sh` in the regression fast lane. A false red blocks the required local lane (`make test`), costs a rerun, and teaches people to rerun reds without reading them. |
| Scope | In: the ten pipe-into-`grep -q` checks in `skills/skill-extraction-workflow/scripts/test_obligation_ledger.sh` (lines 564, 565, 591, 598, 620, 621, 652, 653, 1234 and 1256 before the change; 1234 also carried the audit's exit status through `pipefail`). Out: the tool under test (`obligation-ledger.py`), other suites with the same shape (Residual risk in `specs/regression-suite-flakes/plan.md`), the package version change that shares this branch. No watermark applies; this is not an iterative-program source. |
| Depth | Targeted check plus test-only change: one named defect, reproduced and fixed in its suite. No skill text changes. |
| Result classification | Failure. The suite failed in the fast lane on a candidate that changed only package version fields, and failed 1 of 3 standalone runs on the same tree; the assertion it printed names text that the printed output contains. |
| Matching analysis | Paired control on the check's own shape (Diagnosis) and a killing-mutation walk over every converted check (`evidence/validation.md`). |
| Failure mode | A weak fix would rerun the lane until green or loosen the check (drop the target match, accept any non-zero exit), which hides the class and lets a real miscount through. |
| Lifecycle impact | Testing and CI only. Product intent, design, implementation, release and onboarding are unaffected: the suite's assertions and the tool's behavior stay the same. |
| Evidence plan | The failing lane log and the suite's own FAIL line, the suite source and the tool's error path, a paired probe of the check shape (pipe vs here-string, 3,000 runs each), repeated standalone runs, and an applied mutation per converted check. |
| Completion standard | Each converted check turns the suite red on its own mutation in a disposable copy, with the unmutated control green. Repeated standalone runs under load pass. The repository's local lanes pass on the exact candidate, then extraction review and challenge, and a delta pass for any later change. |

Order note: the conversion was applied before this charter was written down. Its scope and method were fixed by the diagnosis and by the precedent round (every pipe-into-`grep -q` check, here-string form); nothing else was edited before the charter.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `skill-extraction-workflow` | owner | updated | `scripts/test_obligation_ledger.sh` |
| `testing-strategy` | sibling | unchanged | Its flake rules already require diagnosis before rerun and deterministic suites; this is a local harness bug of a class already recorded, not a missing rule. Its mutation-walk rule was used as written. |
| `defect-diagnosis` | sibling | unchanged | Used as written: the assertion was read first and a paired control settled the cause. |
| `product-rd-workflow` | upstream | not-applicable | no product, contract or gate semantics change |

## Diagnosis

`run_mutant stale_locator` failed with `expected first code STALE_LEDGER at specs/ledger.md, got: ERROR STALE_LEDGER: <tmp>/stale_locator/specs/ledger.md` followed by the tool's `fix:` line. The printed output starts with `ERROR STALE_LEDGER:` and contains `specs/ledger.md`, so `mutation_error_matches` should have matched. That helper ran `printf '%s\n' "$output" | grep -q …` twice under `pipefail`. `grep -q` exits on its first match; when the writer still has output to write, it dies of SIGPIPE, `pipefail` fails the pipeline, and a positive check reports a miss. `stale_locator`'s output carries a long second line (the regenerate command), which leaves the writer more to write after the match; that it is the only case seen failing is consistent with this, not proven by it.

| Hypothesis | Prediction | Probe | Result |
| --- | --- | --- | --- |
| The tool printed the wrong code or a target without `specs/ledger.md` | the printed output lacks one of the two strings | read the FAIL line | rejected: both strings are present |
| The candidate's change caused it | the suite fails only on the branch | the candidate changes only package version fields; the suite and tool are identical to `origin/main` | rejected |
| SIGPIPE under `pipefail` | the check's own shape fails intermittently on a two-line output; the here-string form never does | the helper's two checks on a synthetic two-line output (code line plus a 300-character second line), 3,000 runs each form, on this host under load | confirmed: pipe form 331 false misses, here-string form 0 |
| Intermittent, not deterministic | standalone runs of the stock suite both pass and fail | three runs on the same tree | 1 of 3 failed, at `stale_locator` |

This corrects an earlier reading. `specs/regression-suite-flakes/evidence/validation.md` lists this suite among those that failed in the lanes and passed alone, with "`stale_locator` printed an absolute path" at high load. The absolute path is the tool's normal output and the check matches it by substring; the failure was this race, and load only made it more frequent.

## Change

Every pipe-into-`grep -q` check reads the output from a here-string, the form the precedent round adopted. The stale-fix-hint check (old line 1234) piped the audit straight into `grep`, so `pipefail` also failed it when the audit exited non-zero; it now captures the output and requires both the exit status and the `audit_ok` line (`out="$(audit)" && grep -q '^audit_ok' <<<"$out" || fail`).

| Input to a converted check | Before | After |
| --- | --- | --- |
| Expected text present, writer not cut off | pass | pass |
| Expected text present, writer cut off after the match | false failure | pass |
| Expected text absent | failure | failure |
| Stale-fix-hint audit exits non-zero | failure | failure |

## Test cases

| Case | Layer | Assertion | Before | After |
| --- | --- | --- | --- | --- |
| Each converted check | suite | a mutation that the check alone must catch, in a disposable copy, turns the suite red at that check | n/a | see Validation |
| Stale-fix-hint exit status | suite | an audit that prints `audit_ok` but exits 1 fails the check | n/a | see Validation |
| Suite passes repeatedly under load | suite | consecutive green standalone runs | 1 of 3 failed | see Validation |

## Residual risk

Other suites with the same shape remain, as listed in `specs/regression-suite-flakes/plan.md`; each is a separate change.

One of them has now been seen failing. `test_liveness_predicate_gate.sh` failed 1 of 3 standalone runs at case p10b, which expects a line next to a `ps -o stat=` read to be cleared. The cleared-by-state check is `check-ccl-skills.sh:695`, `if printf '%s' "$liveness_win" | grep -qE …; then continue`, under `pipefail`. When the `stat=` line comes before the end of the window, `grep -q` exits early, the writer dies of SIGPIPE, and the check reads a miss: the gate reports a violation on a line it should clear. On that window's shape the pipe form missed 204 of 3,000 runs and the here-string form none. The gate is shared, so its fix goes through the shared-gate route as its own change.

## Validation

Results on the final candidate, the review passes and the commits they reviewed: `evidence/validation.md`.
