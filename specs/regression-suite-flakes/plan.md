# Regression suite flakes

Two suites in the fast regression lane report failures for checks that hold. This round removes both causes.

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Stop two false failures in the fast lane: the reference-access census suite's checks failing on SIGPIPE, and the body-compliance grading suite's mixed-replica leg failing on runners whose `mkdir` utility does not exclude concurrent callers. A false red costs a rerun and teaches people to rerun reds without reading them. |
| Scope | In: `skills/skill-extraction-workflow/scripts/test_reference_access_census.sh` and `test_body_compliance_grading.sh` (its test-only `claude` stub). Out: the tools under test (`reference-access-census.sh`, `eval/body-compliance-eval.rb`), other suites that share either pattern (listed under Residual risk), the hooks that take a `mkdir` lock. No watermark applies; this is not an iterative-program source. |
| Depth | Targeted check plus test-only change: two named defects, each reproduced and fixed in its suite. No skill text changes. |
| Result classification | Failure. Both are observed false failures: the census pattern reproduces in a fresh bash, and the grading suite failed in CI on a change that did not touch it. Disconfirming observation for each cause is under Diagnosis. |
| Matching analysis | Widen-check plus control per cause (Diagnosis, Prevention). |
| Failure mode | A weak fix would rerun until green, retry the leg, or loosen the expected count (accept 1/3 or 2/3), which hides the defect class and lets a real miscount through. |
| Lifecycle impact | Testing and CI only. Product intent, design, release and onboarding are unaffected: the suites' assertions and the tools' behavior stay the same. |
| Evidence plan | The failing CI log (attempt 1 of the run), both suites and the runner source, a fresh-bash reproduction of the pipe race, a repeated local run of the mixed-replica leg, and a paired run of uutils and GNU `mkdir` in the CI image (`ubuntu:26.04`). |
| Completion standard | Each converted census check turns red on its own mutation in a disposable copy. The grading suite's new guard fails on the old stub and passes on the new one. The repository's local lanes pass on the exact candidate, then extraction review, challenge, and a delta pass for any later change. |

Order note: the census conversion was applied before this charter was written down. Its scope and method were fixed by the task (every pipe-into-`grep -q` check, here-string form as in `test_governing_chain_diff.sh`); nothing else was edited before the charter.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `skill-extraction-workflow` | owner | updated | the two suites and the source-register row |
| `testing-strategy` | sibling | unchanged | Its flake rules already require diagnosis before rerun and deterministic suites; both defects are local test-harness bugs, not a missing rule. Its mutation-walk reference was used as written. |
| `defect-diagnosis` | sibling | unchanged | Used as written; the CI-trace-first and paired-control rules found the cause. |
| `code-review` | sibling | unchanged | Suites of the same shape exist there (Residual risk); not changed in this round. |
| `product-rd-workflow` | upstream | not-applicable | no product, contract or gate semantics change |

## Diagnosis

### Census suite: SIGPIPE under pipefail

The suite runs under `set -euo pipefail` and had 39 checks of the form `printf '%s\n' "$out" | grep -q... PATTERN`. `grep -q` exits on its first match. When the writer still has output to write after that (bash's `printf` evidently writes in more than one call: a single write could not be cut off after a match, yet short outputs fail below), the write reaches a pipe whose reader has exited, the writer dies of SIGPIPE (141), `pipefail` fails the pipeline, and a positive check reports a failure although the text is present. Negative checks (`... && fail`) fail the other way: a leak that matched would kill the writer, the pipeline would report 141, and `&& fail` would not run.

- Reproduced in a fresh bash: `{ printf "a\n[x]\n"; sleep 0.3; printf "b\n"; } | grep -qF "[x]"` under pipefail prints `141 0`.
- Rate with the suite's own shape on this host: a 40-line output gave 82 false failures in 2,000 runs; a 20,000-line output failed 200 of 200.
- Disconfirming observation: if the converted checks still failed intermittently, the cause would be elsewhere. They read from a here-string, so no pipe exists.

The five `[ "$(printf ... | tail -1)" = ... ]` checks are not of this shape: `tail` reads to end of input, so the writer is never cut off. They are unchanged.

### Grading suite: `mkdir` as a lock

The CI failure (regression-fast, attempt 1 of the run) printed `prd-continue-evidenced: 1/3 pass` and two FAIL rows, each with `continuing:` missing and `blocked:` present. The leg runs three replicas concurrently against a stub `claude` that takes a one-shot line when `mkdir "$ONCE_DIR"` succeeds, so exactly one replica should print `blocked:` (2/3). Two did, so `mkdir` succeeded twice.

| Hypothesis | Prediction | Probe | Result |
| --- | --- | --- | --- |
| Runner mixes replica outputs (shared buffer, fd mix-up between concurrent spawns) | duplicated outputs appear on any host under concurrency | the leg 1,200 times on this host (8 parallel loops, load around 60); `ask()` called by 20 threads, 40 rounds | rejected: 0 misses, 0 duplicates |
| The suite or runner changed since the failing commit | a diff between that commit and `main` | `git diff` on both files | rejected: identical |
| The runner image's `mkdir` does not exclude concurrent callers | more than one winner among concurrent `mkdir` of one path on that image, none with GNU `mkdir` | `ubuntu:26.04` (the CI image; `mkdir` is uutils 0.10.0, `gnumkdir` is GNU 9.7), three concurrent callers per round, 500 rounds each | confirmed: uutils 26 rounds with several winners, GNU 0 |

This host runs GNU `mkdir`, which is why the leg never failed locally. The stub's comment ("mkdir is atomic") holds for the `mkdir(2)` system call and for GNU `mkdir`, not for every `mkdir` utility.

## Change

- Census suite: every pipe-into-`grep -q` check reads the output from a here-string, the form `test_governing_chain_diff.sh` already uses.
- Grading suite: the stub takes its one-shot line from `Dir.mkdir`, which is the `mkdir(2)` call itself, through Ruby, which the suite already requires. The mixed-replica leg runs with a `mkdir` on `PATH` that reports success without excluding anyone, so a stub that goes back to the utility fails the leg on every host, not only on uutils runners.

## Test cases

| Case | Layer | Assertion | Before | After |
| --- | --- | --- | --- | --- |
| Each converted census check | suite | a wrong expected value in a disposable copy turns the suite red at that check | n/a | see Validation |
| Census suite passes repeatedly under load | suite | N consecutive green runs | intermittent | see Validation |
| E10 under a non-excluding `mkdir` | suite | `prd-continue-evidenced: 2/3`, mixed summary `{pass 2, fail 1}` | fails (0/3) | passes |
| E10 on the CI image with its own `mkdir` | suite, container | repeated runs, no miss | misses | see Validation |

## Prevention

- The class is "a test helper relies on a property of a host tool that differs across supported hosts". The guard here pins the suite's own stub; the hooks below use the same primitive at runtime and are listed, not changed.
- The pipe race is the second suite fixed in two rounds. Other suites with the same shape are listed below; each is a separate change.

## Residual risk

- `hooks/merge-authorization-prompt.sh` and `hooks/guard-merge-authorization.sh` take a lock with `mkdir "$lock_dir"`, as does `skills/code-review/scripts/test_opencode_review_concurrency.sh`. On a host whose `mkdir` is uutils 0.10.0 that lock may admit two holders. Not exercised against those scripts in this round.
- About 25 other scripts contain `| grep -q` and `pipefail`; not every match is a check under pipefail. Not audited here.

## Validation

Results on the final candidate, the review passes and the commits they reviewed: `evidence/validation.md`.
