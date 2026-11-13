# skills/test-artifact-management/references/tc_helpers Agent Contract

Helpers here map automated test results to testcase IDs and report artifacts.

Rules:

- Preserve collection-time testcase mapping so skipped/blocked/fixture-failed
  tests still report to the right case.
- Do not collapse failed, skipped, blocked, unlinked, and deprecated cases into
  one status.
- Keep helpers dependency-light and portable across target repos.
- Add focused tests for marker parsing or report-shape changes.
- Target repos copy `tc.ts` into their own source, so it must pass a strict
  consumer type-check: `strict`, `noUncheckedIndexedAccess`,
  `exactOptionalPropertyTypes`, and both `nodenext` and `bundler` module
  settings (see `typescript-dev`).

Validation:

- `python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py`
- After editing `tc.ts`, in a scratch directory with `typescript`,
  `@types/node`, and `"type": "module"`:
  `npx tsc --noEmit --types node --skipLibCheck --strict --noUncheckedIndexedAccess --exactOptionalPropertyTypes --verbatimModuleSyntax --module nodenext --moduleResolution nodenext tc.ts`,
  then again with `--module esnext --moduleResolution bundler`.
