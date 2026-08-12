# skills/test-artifact-management/references/tc_helpers Agent Contract

Helpers here map automated test results to testcase IDs and report artifacts.

Rules:

- Preserve collection-time testcase mapping so skipped/blocked/fixture-failed
  tests still report to the right case.
- Do not collapse failed, skipped, blocked, unlinked, and deprecated cases into
  one status.
- Keep helpers dependency-light and portable across target repos.
- Add focused tests for marker parsing or report-shape changes.

Validation:

- `python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py`
