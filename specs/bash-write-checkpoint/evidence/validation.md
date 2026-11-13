# Validation

Commands run locally on macOS. Base `origin/main` at `6f71016`. Final
candidate `ba2f7ac`.

## Final candidate

| Command | Result |
| --- | --- |
| `CCL_BROAD_TEST_REASON=repo-required make test` | exit 0 |
| `test_check_ccl_regressions.sh --heavy-only` | `regression_heavy_lane_ok: 9 suites` |
| `python3 scripts/check-public-sanitization.py .` | `public_sanitization_ok` |
| `CCL_SKILL_BASE_REF=origin/main check-ccl-skills.sh .` | `ccl_skill_check_clean_ok`, `r0_status=private-ok` |
| `git diff --check origin/main` | clean |
| `shared_git_surface_gate.py --base-ref origin/main --pr-text-file <PR text>` | `shared_git_surface_gate_ok: commits=5` |
| `python3 hooks/test_skill_loading.py` | 35 tests OK |
| `python3 hooks/test_host_input.py` | 41 tests OK |

## Failing first and mutations

| Run | Candidate | Result |
| --- | --- | --- |
| current tests on the base hook code (scratch copy) | `095941a` hook files | every shared-surface write case fails; every control row passes (`red-baseline.txt`) |
| review-fix rows | `7af702b` | 12 new rows fail, earlier rows pass (`red-review-fixes.txt`) |
| challenge-fix rows | `b3053e9` | 9 new rows fail, earlier rows pass (`red-challenge-fixes.txt`) |
| delta-fix rows | `04901ac` | 4 new rows fail, earlier rows pass (`red-delta-fixes.txt`) |
| 28 mutants on scratch copies | per fix round | each fails only its owning case (`mutation-walk.md`) |

## Hook runtime at the input cap

Each input is close to the 64 KiB limit. Each run uses a fresh actor, so a
command that reaches the checkpoint runs the full deny path. The hook timeout
is 10 s.

| Input | Bytes | Slowest of 3 | Decision |
| --- | --- | --- | --- |
| `touch` with deep shared-surface operands | 64,966 | 0.161 s | deny |
| one command with many redirections to the shared surface | 64,976 | 0.158 s | deny |
| heredoc of 3,500 lines with quotes and `<<` text | 64,986 | 0.095 s | none |
| quote-heavy `echo` | 65,000 | 0.113 s | none |
| inline Python with repeated write calls | 64,987 | 0.217 s | deny |
