# Validation

## Behavioral evidence (RED-baseline, constructed and recorded)

| Case | Before the change | After the change |
| --- | --- | --- |
| Pipe race, fresh bash: `{ printf "a\n[x]\n"; sleep 0.3; printf "b\n"; } \| grep -qF "[x]"` under `pipefail` | `PIPESTATUS` is `141 0`: the pipeline fails although `[x]` is present | the here-string form has no writer to kill |
| The census suite's check shape, 40-line output, 2,000 runs on this host | 82 false failures | not applicable: no pipe remains |
| Census mutation walk: each of the 39 here-string checks mutated alone in a disposable copy (positive checks: an expected value that cannot match; negative checks: an empty pattern, which matches everything) | n/a | control run green; 39 of 39 mutants exit 1 with their own check's message as the first failure; no two checks share a message |
| Parallel-suites runner test alone, repeated | branch: 4 of 10 failed; `origin/main`: 2 of 10; a copy printing `PIPESTATUS` on a marker miss failed 5 of 30, each marker miss `141 0` with the marker present | 0 of 20 failed |
| Parallel-suites mutation walk: each of its 9 here-string checks mutated alone in a disposable copy with the runner | n/a | control green; 9 of 9 exit 1 with their own message first. The marker-loop check was mutated through its marker list (`PY-MARKER-MUTANT`): a mutation inside `"$marker"` names an unset variable and aborts before any check runs |
| Evidence-card self-test: two-line output through the pipe, `pipefail`, 3,000 runs | 159 false misses; one-line output 0 | here-string form 0 |
| Stock `check-evidence-card-leak.sh --self-test` with `printf` overridden to write line by line, 3 runs | 3 failed: `changed-scope missed a now-modified historical card`; without the override it passes | 3 passed |
| Evidence-card mutation walk: each of the 7 converted self-test checks mutated alone in a disposable copy | n/a | control green; 7 of 7 exit 1 with exactly one failure line, their own |
| Grading suite, mixed-replica leg under the non-excluding `mkdir`, old stub restored in a disposable copy | fails: `prd-continue-evidenced: 0/3`, and the summary check fails; the same two failures the CI run printed | passes: `2/3`, summary `{pass 2, fail 1}` |
| Grading suite, one-shot directory under a missing parent, so `Dir.mkdir` fails with ENOENT for every replica | n/a | E10 fails with `3/3`: a Ruby failure other than EEXIST makes the leg red, not green |
| Mixed-replica leg on the CI image (`ubuntu:26.04`, Ruby 3.3.8, uutils `mkdir` 0.10.0), 200 runs each | 31 misses | 0 misses |
| Same leg on this host (GNU `mkdir`), 1,200 runs | 0 misses (why the failure never reproduced locally) | n/a |
| `mkdir` exclusion on the CI image, three concurrent callers, 500 rounds | uutils: 26 rounds with more than one winner; a second sequential `mkdir` of an existing path fails as it should | GNU `gnumkdir` 9.7 (control): 0 |

## Slow-writer harness for the evidence-card self-test

Run on `e2c9205` (stock) and `111ed9d` (fixed) as `bash slow-writer.sh skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh`.

```bash
#!/usr/bin/env bash
# Runs the given script's --self-test with printf writing multi-line %s output one line at a
# time, pausing between lines, so a reader that exits on its first match always cuts the writer off.
printf() {
  if [ "$1" = "%s" ] && [ "$#" -eq 2 ] && [ "${2#*$'\n'}" != "$2" ]; then
    local rest="$2" head
    while [ "${rest#*$'\n'}" != "$rest" ]; do
      head="${rest%%$'\n'*}"; rest="${rest#*$'\n'}"
      builtin printf '%s\n' "$head" || return $?
      sleep 0.2
    done
    builtin printf '%s' "$rest"
  else
    builtin printf "$@"
  fi
}
export -f printf
exec bash "$1" --self-test
```

| Tree | Result, 3 runs each |
| --- | --- |
| Stock, slow writer | `self-test FAIL: changed-scope missed a now-modified historical card`, then `evidence_card_leak_self_test_failed`; 3 of 3 |
| Stock, no override | `evidence_card_leak_self_test_ok` |
| Fixed, slow writer | `evidence_card_leak_self_test_ok`; 3 of 3 |

A copy of the stock script instrumented with `PIPESTATUS` at the failing check ran 25 times without hitting the race, which a rate near 1 in 60 allows. So on the real path the proof is this deterministic run; the rate comes from the paired control and the 1 failure in 60 stock runs.

Failure path: `self_test` returns `rc`, `main` returns it, and `check-ccl-skills.sh` blocks at `if ! bash "$evidence_card_script" --self-test`. No other script calls it.

## Suites that failed in the lanes and pass alone

| Suite | Lane failure | Alone |
| --- | --- | --- |
| `test_check_ccl_skill_catalog.sh`, `test_check_ccl_route_drift.sh`, `test_check_sync_pointers.sh` | the evidence-card self-test stopped the full checker they run (plan, Diagnosis). The first occurrence also had an uncommitted citation in the register, which is not the cause: the same three failed again with no such citation | pass alone on the committed branch |
| `test_obligation_ledger.sh` | `stale_locator` printed an absolute path, with five suites running at load near 60 | passes alone on the branch and on `origin/main` |
| `test_eval_runtime.py` | `fixture never reached the descendant path` | 3 of 3 pass alone on the branch and on `origin/main` |

## Local lanes on the candidate

Candidate `261015f`, tree clean, tracked files at 644/755. Later commits add only this record.

| Lane | Result | Failed attempts |
| --- | --- | --- |
| `make test-repo-gates` | passed, load 2 | 3 at load 17 to 57, on wall-clock bounds: `test_eval_runtime.py` (0.5 s for two interpreter starts), and the concurrency check in `test_run_parallel_suites.sh` |
| `make test-regressions-fast` | passed first attempt, load 51 | none |
| `make test-code-review-1` | passed, load 6 | 2 at load 45 and 12, `test_opencode_review_retry.sh` timeout cases |
| `make test-code-review-2` | passed first attempt, load 3 | none |
| `make test-code-review-abort-leak` | passed first attempt in a private PID namespace, load 2 | an earlier run outside the namespace failed leg 1 |
| Heavy lane | passed, load 2 | 1 at load 3: `test_impact_chain_gate_verdict_differential.sh` exited 141. It passed 8 of 8 alone on the branch and on `origin/main`. Likely cause, not proven: its diagnostics use `printf ... \| head -N \| sed` under `set -e` and `pipefail`. Unchanged here |
| `python3 scripts/check-public-sanitization.py .` | passed | none |

## Review passes

Base `d0e9b3429357869ceb7415c5f2c7eec0fa7fb31c`, confirmed with `git ls-remote origin refs/heads/main` at 2026-11-03T18:03:34Z. Reviewer: codex (implementer family: claude).

| Pass | Commit reviewed | Result | Disposition |
| --- | --- | --- | --- |
| Review (`review.json`) | `249bf2f` | 1 P2: this file still held placeholders, and `make test-code-review` (part of `make test`) was not on the lane list | Lane list extended to all of `make test`; results in the lanes section above, from the final run |
| Challenge (`challenge.json`), focus: false greens and races | `249bf2f` | 1 P2: the packet did not show that replicas reach the shim or that a non-EEXIST Ruby failure turns E10 red | Evidence, no code change: the runner spawns with `Open3.popen3` and no environment override, so the stub inherits `PATH`; the old stub under the shim took the one-shot line in all three replicas (0/3); the ENOENT row above |
| Review of the increment (`delta-review.json`) | `249bf2f..1011680`, a local commit since rebuilt (see below) | 2 P2: the lanes section was a placeholder; the earlier results were called conclusive although each reports findings | Lanes section filled from the final run. Wording: all results here are conclusive in the repository's sense (status `findings`, client named, as `check_review_evidence_present.py` defines it); none is a clean pass, and every finding is dispositioned in this table |
| Challenge of the increment (`delta-challenge.json`), focus: false greens in the converted runner-test checks | `249bf2f..1011680`, as above | 2 P2: the packet did not show the unconverted `grep -n` / `grep -c` pipelines; the lanes placeholder | The unconverted pipelines are `slow_line="$(printf '%s' "$out" \| grep -n 'SLOW-MARKER' \| cut -d: -f1)"` (likewise FAST and PY), `timings="$(printf '%s' "$out" \| grep -c '^regression_test_timing: test=')"`, and the message-only `grep 'suite(s) failed'`; none takes `-q` or `-m`, and `cut` reads to end of input, so no writer is cut off. Lanes: as above |
| Review of the evidence-card fix (`gate-review.json`) | `e2c9205..111ed9d` | 2 P2: the slow-writer harness was not replayable from the record; the lane table was tied to `b16bb2d` | Harness and per-tree results recorded above; lane table replaced from the final run |
| Challenge of the evidence-card fix (`gate-challenge.json`), focus: gate false greens | `e2c9205..111ed9d` | 1 P2: the packet did not show the self-test's return path or its caller | Recorded above; nothing depends on the pipe form. No code change |

The reviewed increment `249bf2f..1011680` also reworded two stub comments in `test_body_compliance_grading.sh` and edited this round's register row. The impact-chain gate scopes register rows per round, and an edited row no longer resolves against the round that added it, so the increment was rebuilt without those two edits. The branch's increment is the runner-test change and these records. Its script change is the one the passes reviewed; only these records changed after them.
