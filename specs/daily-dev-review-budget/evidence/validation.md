# Validation

Candidate: branch `fix/daily-dev-review-budget` from `origin/main` 590eb29.

## RED baseline

- `test_extraction_review_gate.sh` with the base `development-completion.md` fails with `AssertionError: daily review budget lost 'Daily development spends two external passes per change'`. That is the new pin; no other assertion failed.
- `test_remind_review_covers_head.sh` with the base hook fails the two new probes: the budget phrase is missing and the retired five-rerun phrase is present (62 passed, 2 failed).

## GREEN

| Command | Result |
| --- | --- |
| `bash hooks/test_remind_review_covers_head.sh` | `test_remind_review_covers_head_ok` |
| `bash skills/skill-extraction-workflow/scripts/test_extraction_review_gate.sh` | `test_extraction_review_gate: ok` |
| `make -k test` (full lane, before review) | repo gates and code-review lanes passed; the fast lane failed 3 suites on a pinned phrase (`changed named test properties`) that a sentence edit had capitalized. Restored, and the 3 suites passed. |
| `make test-regressions-fast` (after each fix commit) | exit 0 |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `regression_heavy_lane_ok: 9 suites` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_clean_ok` (`r0_status=private-ok`) |

## Passes

| Pass | Base | Result | Dispositions |
| --- | --- | --- | --- |
| review (`evidence/review.json`) | `origin/main` | 4 findings | All applied in b59c6a9. The untracked invocation is now stated. The hook exempts high-risk and extraction work and excludes loosened assertions. The session figures are now described as estimates. |
| challenge (`evidence/challenge.json`) | `origin/main`, candidate with the review fixes | 4 findings | All applied in e088ed9. Deferral no longer clears a confirmed P0/P1. The doc exemption is limited to daily development and excludes behavior-governing text. A findings receipt within the budget is not a stop. The hook sends new scope back to review. |
| delta 1 (`evidence/delta-review-1.json`) | b59c6a9 | 2 findings | D1 applied: the hook's doc exemption now matches step 2, with a new probe. D2 was refuted from execution evidence; see below. |

D2 is the third finding in the same class: evidence that the sequence can run on the controller. This round ran the sequence itself. A review returned findings, and the fixes changed the candidate. A standalone `--mode challenge --challenge-budget 1` pass then ran on the changed candidate without chain options and was not refused. After more fixes, a `--base <commit>` delta pass ran. The controller derives challenge index 1 for an untracked challenge (`review_gate.py` `resolve_challenge_index`). A build-stage review defaults to challenge budget 0 (`review_gate.py:3378`). After findings, the completion gate's allowed actions are `resolve_review_findings` and `deep_self_review`, which are the disposition step. The PR hook never blocks (`hooks/remind-review-covers-head.sh` header). `human_decision_required` is a legacy field, and the staged contract already says budget exhaustion is not a user handoff (`staged-review-contract.md`).

## Behavioral evidence

RED-baseline: the pins and probes above change state between the base text and the candidate. Session evidence for the cost is in `../plan.md` (Evidence).
