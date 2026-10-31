# Validation

Candidate: `c4c7560`, the last commit that changes anything outside this directory. Base `origin/main` at `326374b`. Every command ran with `CCL_SKILL_BASE_REF=origin/main`.

| Command | Result |
| --- | --- |
| `make test` | exit 0: repository gates, `regression_fast_lane_ok: 46 suites`, `code_review_shard_1_ok`, `code_review_shard_2_ok`, abort-leak legs ok |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `regression_heavy_lane_ok: 9 suites` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `ccl_skill_check_clean_ok`, `r0_status=private-ok` (private alias audit ran), `entrypoint_word_budget_blocking_ok` |
| `git diff --check origin/main..HEAD` | clean |

Inside `check-ccl-skills.sh`, the impact-chain gate accepts both rows in `source-register.md`. Each firing-path anchor occurs once in its owner file, inside that round's added lines:

- `one that cannot interpret it reports unknown` in `skills/defect-diagnosis/SKILL.md`
- `declared but not understood` in `skills/product-rd-workflow/references/refactoring-discipline.md`

`defect-diagnosis/SKILL.md` body words: 4940 at base, at most 5000 at head (the budget).

The 065 obligation ledger cites `defect-diagnosis/SKILL.md` by line number. The inserted line shifted that citation, so it was re-rendered with the command the audit printed. The only change is `160-160` to `161-161`.

Not run locally: the pull-request-only `check_review_evidence_present.py`. It runs before pushing (see the pull request).
