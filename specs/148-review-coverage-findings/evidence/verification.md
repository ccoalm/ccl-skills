# Verification

Candidate: `63c451f` on `origin/dev` (`d81ea38`).

## Reproduction before the fix

A receipt with `status: findings`, a HEAD match and a clean worktree produced
no reminder; the same fixture with `status: passed` produced the same silence;
a mismatched HEAD produced a reminder. Status was the only varied input.

## Regression walks

| Check | Result |
| --- | --- |
| `hooks/test_remind_review_covers_head.sh` on the unfixed hook | 26 passed, 5 failed (the new cases) |
| Same suite on the fixed hook | 31 passed, 0 failed |
| Status predicate removed on a copy | 27 passed, 4 failed (the status cases) |
| `skills/code-review/scripts/test_review_gate.sh` on the fix | exit 0, three new receipt cases ok |
| Completion write reverted on a copy | exit 1, single failure: the completion-success receipt case |

## Lanes on the final candidate

| Lane | Result |
| --- | --- |
| `CCL_SKILL_BASE_REF=origin/dev check-ccl-skills.sh .` | `ccl_skill_check_clean_ok` |
| `test_check_ccl_regressions.sh --heavy-only` | exit 0 |
| `check-public-sanitization.py .` | exit 0 |
| `git diff --check origin/dev..HEAD` | exit 0 |
| `make test` | exit 2 once: `abort-leak` leg 2, client `claude`, wrapper still alive at 55 s under full-lane load |
| That leg alone, five runs | 5 of 5 exit 0 |
| `make test-code-review-abort-leak-2` | exit 0 |

The first lane run on the fix also failed the impact-chain gate and, through
it, `test_check_ccl_r0_status.sh`; both passed after the register row was
added, with no other change between the runs.

## Review

| Round | Client | Result |
| --- | --- | --- |
| Review, tracked chain index 1 | kimi | passed, 0 findings |
| Challenge, index 2, same candidate hash | kimi | passed, 0 findings |
| `--mode complete` | local | passed; the receipt changed from `challenge` to `complete`, `passed`, HEAD `63c451f`, clean worktree |

An earlier attempt stopped before any provider call because four derived
owners lacked self-review rows. The next attempt selected codex first, which
failed on repeated provider stream disconnects and is not cascade eligible;
the recorded chain reorders the local client list to kimi first.
