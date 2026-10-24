# Validation

Host: git 2.39.5, jq 1.6, Python 3.12 with a virtual environment first on `PATH` for PyYAML and pytest. Comparison host for the probes: git 2.50.1, jq 1.7.1.

## Cause probes

| Probe | git 2.39.5 / jq 1.6 | git 2.50.1 / jq 1.7.1 |
| --- | --- | --- |
| `for-each-ref --points-at <commit>` with tag `t2` annotating tag `t1` | lists the branch and `t1` | lists the branch, `t1` and `t2` |
| `"src/file.py" \| contains("\u0000")` | `true` | `false` |
| `explode \| any(. == 0)` on `"src/file.py"`, `"a\u0000b"`, `""` | `false`, `true`, `false` | `false`, `true`, `false` |
| `printf '' \| jq -e '.a == 1'` exit status | 0 | 4 |

## RED and GREEN on this host

| Suite | `main` at 590eb29 | candidate |
| --- | --- | --- |
| `test_check_ccl_skill_catalog.sh` | fails: `c12-upstream-empty` nested alias survived ref cleanup | ok |
| `hooks/test_host_input.py` | 17 failures: 16 isolation fallback cases returned no decision, 1 helper read failure reported "history is too large" | 41 tests OK |
| `hooks/test_remind_unverified_cli_flag.sh` | pass=100 fail=19, every quiet probe read as a reminder | pass=119 fail=0 |
| `hooks/test_guard_edit_isolation.sh` | not run | 20 passed |
| `scripts/owner-dispatch/test.sh` | not run | PASS=133 FAIL=0 |
| `hooks/test_session_start.sh`, `hooks/test_skill_loading.py` | not run | ok |
| `check-ccl-skills.sh`, `check-public-sanitization.py`, `git diff --check` | not run | `ccl_skill_check_interim_ok` (R0 pending maintainer audit), ok, ok |
| `make -k test` (`SUITE_JOBS=1`) | fails in `test-repo-gates` and `test-regressions-fast` on the three suites above | exit 0, all three lanes green |
| `test_check_ccl_regressions.sh --heavy-only` (`SUITE_JOBS=1`) | not run | `test_check_ccl_regressions_heavy_only_ok`. One earlier run with parallel suites failed W1 of `test_pinned_phrase_mutation_walk.sh` inside the evidence-card self-test; that suite passed twice when run alone and the serial lane passed, so it is recorded as a load-dependent flake, not caused by this change |

## Passes

| Pass | Result | Disposition |
| --- | --- | --- |
| review (`evidence/review.json`) | 2 P2 | Version boundaries stated without a probe: applied, the plan, the test comment and the register row now name only the probed versions. Evidence gap on test results: disposed by the tables above. |
| challenge (`evidence/challenge.json`) | passed | none |

## Not covered

- The suites were not run on a git 2.50 / jq 1.7 host; on such a host the rewritten checks reduce to the old ones (full peel equals `--points-at`, the code-point NUL test equals `contains`, the empty-output guards never fire on non-empty output). CI on a pull request is the authoritative run there.
- Owner-dispatch follow-ups listed in `plan.md`.
