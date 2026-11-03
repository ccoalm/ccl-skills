# Validation

## Behavioral evidence (RED-baseline, constructed and recorded)

| Case | Before the change | After the change |
| --- | --- | --- |
| Pipe race, fresh bash: `{ printf "a\n[x]\n"; sleep 0.3; printf "b\n"; } \| grep -qF "[x]"` under `pipefail` | `PIPESTATUS` is `141 0`: the pipeline fails although `[x]` is present | the here-string form has no writer to kill |
| The census suite's check shape, 40-line output, 2,000 runs on this host | 82 false failures | not applicable: no pipe remains |
| Census mutation walk: each of the 39 here-string checks mutated alone in a disposable copy (positive checks: an expected value that cannot match; negative checks: an empty pattern, which matches everything) | n/a | control run green; 39 of 39 mutants exit 1 with their own check's message as the first failure; no two checks share a message |
| Grading suite, mixed-replica leg under the non-excluding `mkdir`, old stub restored in a disposable copy | fails: `prd-continue-evidenced: 0/3`, and the summary check fails; the same two failures the CI run printed | passes: `2/3`, summary `{pass 2, fail 1}` |
| Mixed-replica leg on the CI image (`ubuntu:26.04`, Ruby 3.3.8, uutils `mkdir` 0.10.0), 200 runs each | 31 misses | 0 misses |
| Same leg on this host (GNU `mkdir`), 1,200 runs | 0 misses (why the failure never reproduced locally) | n/a |
| `mkdir` exclusion on the CI image, three concurrent callers, 500 rounds | uutils: 26 rounds with more than one winner | GNU `gnumkdir` 9.7 (control): 0 |

## Local lanes on the candidate

To be filled.

## Review passes

To be filled.
