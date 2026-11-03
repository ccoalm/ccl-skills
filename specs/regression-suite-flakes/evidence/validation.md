# Validation

## Behavioral evidence (RED-baseline, constructed and recorded)

| Case | Before the change | After the change |
| --- | --- | --- |
| Pipe race, fresh bash: `{ printf "a\n[x]\n"; sleep 0.3; printf "b\n"; } \| grep -qF "[x]"` under `pipefail` | `PIPESTATUS` is `141 0`: the pipeline fails although `[x]` is present | the here-string form has no writer to kill |
| The census suite's check shape, 40-line output, 2,000 runs on this host | 82 false failures | not applicable: no pipe remains |
| Census mutation walk: each of the 39 here-string checks mutated alone in a disposable copy (positive checks: an expected value that cannot match; negative checks: an empty pattern, which matches everything) | n/a | control run green; 39 of 39 mutants exit 1 with their own check's message as the first failure; no two checks share a message |
| Parallel-suites runner test alone, repeated | branch: 4 of 10 failed; `origin/main`: 2 of 10; a copy printing `PIPESTATUS` on a marker miss failed 5 of 30, each marker miss `141 0` with the marker present | 0 of 20 failed |
| Parallel-suites mutation walk: each of its 9 here-string checks mutated alone in a disposable copy with the runner | n/a | control green; 9 of 9 exit 1 with their own message first. The marker-loop check was mutated through its marker list (`PY-MARKER-MUTANT`): a mutation inside `"$marker"` names an unset variable and aborts before any check runs |
| Grading suite, mixed-replica leg under the non-excluding `mkdir`, old stub restored in a disposable copy | fails: `prd-continue-evidenced: 0/3`, and the summary check fails; the same two failures the CI run printed | passes: `2/3`, summary `{pass 2, fail 1}` |
| Grading suite, one-shot directory under a missing parent, so `Dir.mkdir` fails with ENOENT for every replica | n/a | E10 fails with `3/3`: a Ruby failure other than EEXIST makes the leg red, not green |
| Mixed-replica leg on the CI image (`ubuntu:26.04`, Ruby 3.3.8, uutils `mkdir` 0.10.0), 200 runs each | 31 misses | 0 misses |
| Same leg on this host (GNU `mkdir`), 1,200 runs | 0 misses (why the failure never reproduced locally) | n/a |
| `mkdir` exclusion on the CI image, three concurrent callers, 500 rounds | uutils: 26 rounds with more than one winner; a second sequential `mkdir` of an existing path fails as it should | GNU `gnumkdir` 9.7 (control): 0 |

## Suites that failed in the lanes and pass alone

| Suite | Lane failure | Alone |
| --- | --- | --- |
| `test_check_ccl_skill_catalog.sh`, `test_check_ccl_route_drift.sh`, `test_check_sync_pointers.sh` | run before the first commit, when the register row cited uncommitted `specs/` files. The catalog log also shows `evidence_card_leak_self_test_failed`, so the citation is not the proven cause of all three | pass alone on the committed branch |
| `test_obligation_ledger.sh` | `stale_locator` printed an absolute path, with five suites running at load near 60 | passes alone on the branch and on `origin/main` |
| `test_eval_runtime.py` | `fixture never reached the descendant path` | 3 of 3 pass alone on the branch and on `origin/main` |

## Local lanes on the candidate

Candidate `b16bb2d`, tree clean, tracked files at 644/755. Not complete: no push.

| Lane | Result on `b16bb2d` |
| --- | --- |
| `make test-repo-gates` | passed once (TMPDIR on tmpfs); other runs failed `test_eval_runtime.py` (a 0.5 s fixture bound at load 24) and, with the disk full, `scripts/owner-dispatch/test.sh` |
| `make test-regressions-fast` | passed once; another run failed `test_check_sync_pointers.sh` and `test_liveness_predicate_gate.sh` |
| `python3 scripts/check-public-sanitization.py .` | passed |
| `make test-code-review-1` | never passed: `test_opencode_review_retry.sh` failed three attempts inside a PID namespace, timeout cases only, 9, 7 and 4 of them. Passed alone on the branch and on `origin/main` outside the namespace |
| `make test-code-review-2` | never passed: `test_cli_review_wrappers.sh` Kimi timeout-signal cases also failed alone on the branch (4) and on `origin/main` (5). Open: cause not diagnosed |
| `make test-code-review-abort-leak` | never passed: leg 1 failed outside a namespace; the namespace run was stopped before finishing |
| Heavy lane | never passed: one run failed `test_check_ccl_r0_status.sh` (passes alone on both trees); one failed `test_register_firing_path_wiring.sh` and `test_pinned_phrase_mutation_walk.sh`, not yet run alone |

`check-evidence-card-leak.sh --self-test`, which `check-ccl-skills.sh` runs, failed 1 of 60 runs on the branch; the script is identical on `origin/main`. It has the pipe-into-`grep -q` shape, but that is a hypothesis: an instrumented copy failed 7 of 60 runs and printed no `PIPESTATUS` line. The `origin/main` figure from that loop is void because the tree was missing.

## Review passes

Base `d0e9b3429357869ceb7415c5f2c7eec0fa7fb31c`, confirmed with `git ls-remote origin refs/heads/main` at 2026-11-03T18:03:34Z. Reviewer: codex (implementer family: claude).

| Pass | Commit reviewed | Result | Disposition |
| --- | --- | --- | --- |
| Review (`review.json`) | `249bf2f` | 1 P2: this file still held placeholders, and `make test-code-review` (part of `make test`) was not on the lane list | Lane list extended to all of `make test`; results in the lanes section above, from the final run |
| Challenge (`challenge.json`), focus: false greens and races | `249bf2f` | 1 P2: the packet did not show that replicas reach the shim or that a non-EEXIST Ruby failure turns E10 red | Evidence, no code change: the runner spawns with `Open3.popen3` and no environment override, so the stub inherits `PATH`; the old stub under the shim took the one-shot line in all three replicas (0/3); the ENOENT row above |
| Review of the increment (`delta-review.json`) | `249bf2f..1011680`, a local commit since rebuilt (see below) | 2 P2: the lanes section was a placeholder; the earlier results were called conclusive although each reports findings | Lanes section filled from the final run. Wording: all four results are conclusive in the repository's sense (status `findings`, client named, as `check_review_evidence_present.py` defines it); none is a clean pass, and every finding is dispositioned in this table |
| Challenge of the increment (`delta-challenge.json`), focus: false greens in the converted runner-test checks | `249bf2f..1011680`, as above | 2 P2: the packet did not show the unconverted `grep -n` / `grep -c` pipelines; the lanes placeholder | The unconverted pipelines are `slow_line="$(printf '%s' "$out" \| grep -n 'SLOW-MARKER' \| cut -d: -f1)"` (likewise FAST and PY), `timings="$(printf '%s' "$out" \| grep -c '^regression_test_timing: test=')"`, and the message-only `grep 'suite(s) failed'`; none takes `-q` or `-m`, and `cut` reads to end of input, so no writer is cut off. Lanes: as above |

The reviewed increment `249bf2f..1011680` also reworded two stub comments in `test_body_compliance_grading.sh` and edited this round's register row. The impact-chain gate scopes register rows per round, and an edited row no longer resolves against the round that added it, so the increment was rebuilt without those two edits. The branch's increment is the runner-test change and these records. Its script change is the one the passes reviewed; only these records changed after them.
