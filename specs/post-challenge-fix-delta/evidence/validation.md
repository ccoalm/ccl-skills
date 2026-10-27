# Validation

## Red baseline

- `test_extraction_review_gate.sh` against the base `development-completion.md` fails with `AssertionError: daily review budget lost 'Any other change made after the challenge gets one delta pass'`.
- `test_remind_review_covers_head.sh` against the base hook fails 3 checks: the every-fix delta phrase and the untagged high-risk phrase are missing, and the retired P0/P1-only phrase is present.

## Commands on the candidate

Run on e5c290d..232d795 (rule, waiver, review fixes, register):

| Command | Result |
| --- | --- |
| `make test` | `make_exit=0` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `test_check_ccl_regressions_heavy_only_ok` |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_clean_ok` (`r0_status=private-ok`) |

After the challenge fix (hook text and one probe), rerun:

| Command | Result |
| --- | --- |
| `bash hooks/test_remind_review_covers_head.sh` | `72 passed, 0 failed` |
| `bash skills/skill-extraction-workflow/scripts/test_extraction_review_gate.sh` | `test_extraction_review_gate: ok` |
| `CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | see below |

## Reviews

| Pass | File | Result | Disposition |
| --- | --- | --- | --- |
| Review (base `origin/main`) | `review.json` | 3 × P2 | R1 applied: the reminder sends every non-exempt post-challenge change, including behavior-governing docs, to the delta, with a probe. R2 applied: this file. R3 applied: the plan marks the fix-induced-regression reading as unverified. |
| Challenge (base `origin/main`, on 232d795) | `challenge.json` | 2 × P2 | C1 applied: the findings branch of the reminder says findings from the final delta go to test or source disposition, with a probe. C2 refuted by an applied probe, below. |

## Waiver abuse probe (C2)

`register-firing-path-resolution.rb` run on three exported copies of 232d795:

| Copy | Change | Result |
| --- | --- | --- |
| base | none | exit 0 |
| reuse | a new row citing the waived locator appended | exit 1: `EXEMPT locator cited by 2 rows (allowance 1)` |
| altered | one word of the historical row changed | exit 1: `EXEMPT citing row does not match the waived row (digest ... not recorded)` |
