# Make the exited-leader timeout test pass on hosts without /proc

## Change

`skills/skill-extraction-workflow/scripts/test_eval_runtime.py` decides whether a process has stopped with a helper, `running(pid)`, that treats a zombie as stopped. The helper read the state from `/proc/<pid>/stat` and, when that file could not be opened, reported the process as running. macOS and the BSDs have no `/proc`, so an exited group leader that its parent had not reaped yet was reported as running for as long as it stayed a zombie. `test_timeout_stops_descendant_with_inherited_stdout` waits for that leader to stop, never saw it happen, and failed with `group leader never exited`.

The helper now asks `ps` for the process state when `/proc` is not available. When neither source can tell, the process still counts as running, so the test cannot pass by assuming a process is gone. The fixture's descendant process runs the same helper through `inspect.getsource` instead of carrying its own copy.

Only the test file changes. The code under test, `skill-behavior-eval.py`, is unchanged, and so is the behavior on Linux, where `/proc` answers first.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | `make test` is the required local lane and it failed on macOS on an unmodified checkout, so no change could be verified locally there. |
| Scope | The process-state helper in one test file and its copy inside that test's fixture. Not an iterative program; no watermark. |
| Depth | Narrow defect fix. |
| Result classification | Failure/correction: a required check failed. |
| Matching analysis | The helper was added together with the exited-leader fixture and was run on Linux only. Its fallback for an unreadable `/proc` chose "running", which is the safe answer for the final "descendant stopped" assertion and the wrong one for the fixture's own wait on the leader. Nothing ran the test on a host without `/proc` before it merged. |
| Lifecycle impact | Verification only. |
| Evidence plan | The failing assertion, a probe of an unreaped child on the failing host, the test before and after. |
| Completion standard | The test passes on macOS, a regression test fails when the fallback is removed, and the Linux path is unchanged. |

Target-output map: `skill-extraction-workflow` (owner of the script) is updated; no other owner reads this helper.

## Verification

| Check | Observed result |
| --- | --- |
| The test on unmodified `main` (b2a6fa3), macOS | Failed 3 of 3 runs: `group leader never exited` |
| Probe of an exited, unreaped child on that host | The signal probe succeeds, `/proc/<pid>/stat` does not exist, `ps -o stat=` reports `Z` |
| `test_eval_runtime.py` on the final candidate, macOS | Passed 3 of 3 runs, 18 tests |
| `test_eval_runtime.py` on the final candidate, Linux | Passed 3 of 3 runs, 18 tests |
| `make test` on Linux, first candidate (b4dcfcb) | Passed, exit 0 |
| `check-ccl-skills.sh` on the final candidate, macOS | `ccl_skill_check_clean_ok` |
| Code under test changed to kill only the group leader | `test_timeout_stops_descendant_with_inherited_stdout` fails: the surviving descendant is detected |

The changes after b4dcfcb are confined to this one test file, so the suite and `check-ccl-skills.sh` were rerun instead of the full lane.

Each protection in the helper was removed on a copy and `ProcessProbeTests` rerun; every removal failed a test.

| Removal | Failed on |
| --- | --- |
| `ps` fallback removed, so an unreadable `/proc` reports running | macOS, Linux |
| Zombie state from `ps` ignored | macOS, Linux |
| A `ps` error treated as stopped | macOS |
| Empty `ps` output treated as stopped | macOS |
| Only the test's own pid counts as running, through `ps` | macOS |
| Only the test's own pid counts as running, through `/proc` | Linux; not reachable on macOS |
| Zombie state from `/proc` ignored | Linux |
| A missing process reported as running | macOS |

Behavioral evidence: `RED-baseline`. The observed failure is the first row and the passing runs are the third and fourth.

`make test` does not pass on macOS after this change. `skills/code-review/scripts/test_review_diff.sh` fails there on unmodified `main` as well: it narrows `PATH` to `/usr/bin:/bin`, where macOS has no `timeout` or `setsid`, so its runner exits 127. That suite is outside this change.

On the first candidate, two consecutive macOS runs of the test file ended with 9 and then 2 errors while a reviewer process was running on the same host. The error text was not captured, and 11 later runs on macOS, some under the same load, and 3 on Linux all passed. The cause is unknown.

## Review

Results are under `evidence/`. Every pass ran on another model family.

## Review pass
- Reviewed commit: b4dcfcb
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Dispositions: no P0/P1. P2 "the probe tests never reach the `ps` branch on Linux": fixed, the tests now make `/proc` unreadable. P2 "the packet omits the rest of the timeout test": not a defect in the change; that code is unchanged and still fails when the descendant survives (last verification row). P2 "only focused runs are recorded": fixed, the lane result is recorded above.

## Challenge pass
- Reviewed commit: aa7a74a
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- Dispositions: no P0/P1. P2 "live checks probe only the test's own pid": fixed with a long-lived child probed with and without `/proc`. P2 "a reused pid can fail the post-reap assertion": fixed, the missing-process case uses a controlled lookup failure. P2 "the packet omits the rest of the timeout test": same as in the review pass.

## Delta pass
- Reviewed commit: 2c08350, against aa7a74a
- Findings: 1 total (0 P0 / 1 P1 / 0 P2), an evidence gap: the packet held only the changed lines, without `running()` or the validation results.
- Dispositions: P1 fixed by widening the input, not the candidate. The pass was rerun on the same commit with the helper, the probe test class and the validation results appended after the delta (`evidence/delta-widened.json`). It raised nothing about the code and one P1 evidence gap: no `make test` or `check-ccl-skills.sh` result was supplied. Fixed: both are recorded above.

2c08350 and the landed commit hold the same test file; the landed commit also carries this record and the review results.
