# Run the review_diff test suite on macOS

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | Make the local `make test` lane runnable on macOS again. Since the diff-first runner landed (efa2ada), `test_review_diff.sh` has exited 127 on every macOS run, so local verification was moved to a Linux host for each round. |
| Scope | `skills/code-review/scripts/test_review_diff.sh` only. Out of scope: the runner itself, other tests, CI layout, and `test-public-data-acquisition-recipes.sh` (it fails on macOS for a missing `openpyxl` but is not registered in any lane). |
| Depth | Targeted check: one test harness, one environment difference. |
| Result classification | failure/correction: deterministic failure, reproduced 2026-11-13 on macOS (18 FAIL lines, first case rc 127). |
| Matching analysis | See RCA below. |
| Failure mode or success boundary | A weak fix would put the full user PATH back, which lets tests reach a real reviewer CLI; or drop the setsid fake, which removes the descendant-holds-pipe case on macOS. |
| Lifecycle impact | testing (local lane) and team onboarding (contributors on macOS). Product intent, design, launch and runtime behavior are unaffected: no shipped script changes. |
| Evidence plan | The failing run's own stderr; tool locations on macOS (`command -v timeout gtimeout setsid`); the commit that introduced the narrowed PATH; sibling tests that also narrow PATH, run on macOS. Produced artifacts: not-applicable, this is a repair, not a retrospective. |
| Completion standard | `test_review_diff.sh` passes on macOS; it still passes where `timeout`/`setsid` are native (CI ubuntu); RED before the fix is recorded; independent review. |

## RCA

- Symptom: `findings-rc: expected '1', got '127'` and 17 follow-on FAIL lines.
- Evidence: the runner's stderr reads `line 171: timeout: command not found`. The call is `PATH="$TEST_PATH" ... timeout 60 python3 ...`; bash resolves `timeout` with the prefix-assigned PATH, which is `$work/bin:$work/sysbin:/usr/bin:/bin`. macOS has no `timeout` or `setsid` in `/usr/bin` or `/bin`; `timeout` exists only as Homebrew coreutils under `/opt/homebrew/bin`, and `setsid` does not exist.
- Introduced by: efa2ada (2026-11-02), which narrowed PATH so no test could reach a real reviewer CLI. CI runs ubuntu, where both tools are in `/usr/bin`, so CI never saw it.
- Why it stayed red: each round ran the lane on a Linux host instead, and the fix was noted as open but never made.
- Contributing: no macOS job in CI, so a macOS-only harness break has no mechanical signal.

## Fix

Three macOS differences, each fixed in the test only. The PATH stays narrowed.

1. **Missing tools.** Link `timeout` (or `gtimeout`) into the private `sysbin` the narrowed PATH already carries; fail with an install hint when neither exists. Link the real `setsid` when present, otherwise a small `os.setsid()` + `execvp` stand-in, so the fake still starts a new session.
2. **`/var` is `/private/var`.** `opencode-project-root` compared `git rev-parse --show-toplevel`, which resolves symlinks, with the `--dir` string. The fake now also records the physical `--dir` (`pwd -P`), and the toplevel is compared with that.
   - Review found this let a `--dir` that aliases the candidate (`repo/.` or a symlink) pass. A new check compares the physical `--dir` with the physical candidate. Applied mutation on a scratch copy (the adapter passes `cwd + "/."`): only `opencode-project-alias` fails.
3. **First exec of a new script is slow.** With 1 and 2 fixed, the suite went red again while other sessions loaded the host (load average 12-19): every fake reviewer hit its 2-5 s timeout.
   - Rejected, each measured: CPU load slowing process start (`python3 -c pass` 0.03 s); a slow command inside the fake (0.002-0.03 s each, in or out of a new session); a new session itself (`bash -c` 0.01 s either way).
   - Cause: on this macOS host the first exec of a newly written script takes about 1-4 s, whatever the session, and only an exec warms it (`cat` or `bash -n` does not). The suite calls `make_fakes` twice, and the first timed attempt after each call paid that cost.
   - Fix: each fake exits at once under `FAKE_WARMUP=1`, and `make_fakes` runs each one that way after writing it; the setsid stand-in runs once too.
   - Paired measurement, first case with a 60 s timeout, same host and minute: codex attempt 1 s / 3 s / 1 s without the warm-up, 0 s / 0 s / 0 s with it.

## Heavy lane: GNU-only sed

The heavy lane (`test_check_ccl_regressions.sh --heavy-only`, not part of `make test`) then failed one more macOS-only suite, `test_check_ccl_impact_chain_refscripts.sh`: `mutation did not apply: no doubled successor path in the third owner`.

- Cause: the mutation used `sed '0,/re/s//X/'`, a GNU-only form. BSD sed exits 0 and changes nothing. Unchanged main fails the same way on macOS (137 s).
- Fix: a python3 first-occurrence replace, the same edit GNU sed makes. No other `0,/` sed use in the repo.
- After: the suite passes (95 s), and the doubled-path case behind the guard runs.

## Verification

All on macOS, `bash skills/code-review/scripts/test_review_diff.sh` unless named.

| Candidate | Result |
| --- | --- |
| Before any fix | exit 1, 18 FAIL lines, stderr `timeout: command not found` |
| Fix 1 only | exit 1, `opencode-project-root` `/var` vs `/private/var` |
| Fixes 1-2 | exit 0 at low load (44 s); full `make test` exit 0; then 4 of 4 runs red under load 12-19 |
| Fixes 1-3 | 5 of 5 runs `test_review_diff: ok` (load 12 falling to 5) |
| Final commit | full `make test` with `CCL_SKILL_BASE_REF=origin/main` exit 0; `check-ccl-skills.sh` `ccl_skill_check_clean_ok` |

Review (codex) on fixes 1-2: one P2, fixed as the alias check above. Challenge (codex) on fixes 1-3: no findings. Delta pass (codex) on the sed fix: no findings. Results in `evidence/`.

## Target-output map

| owner | direction | status | changed file or reason |
| --- | --- | --- | --- |
| code-review (test harness) | self | updated | `skills/code-review/scripts/test_review_diff.sh` |
| sibling PATH-narrowing tests | sibling | unchanged | `test_cli_review_wrappers.sh`, `test_claude_review_probe.sh`, `hooks/test_guard_delegation_owner.sh` pass on macOS (run 2026-11-13) |
| testing-strategy | upstream | unchanged | no rule change; a macOS CI job is the mechanical control for this class and is deferred (cost of a macOS runner per PR), recorded here as the open prevention |
| skill-extraction-workflow | self | unchanged | test-only repair; no reusable rule text changes |
