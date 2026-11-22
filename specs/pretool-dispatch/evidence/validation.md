# Validation: one jq read per hook

Plan: [`../plan.md`](../plan.md) (option A). Baseline: `788470c`.

## Implementation boundary

- **Baseline:** `specs/pretool-dispatch/plan.md` on branch `ccoalm/pretool-jq-reads`, read back in full before editing. Its three design reviews are `design-review-D1/D2/D3.json`.
- **Scope:**
  - payload field reads in `owner-dispatch.sh` (`cmd_pretool`), `guard-merge-authorization.sh`, `guard-broad-local-test.sh` and `guard-edit-isolation.sh`;
  - the differential test `hooks/test_hook_field_reads.py` and its expected-output fixture;
  - the `make test-repo-gates` registration.
- **Owners loaded in this session:**
  - `product-rd-workflow`, for the entry gate;
  - `testing-strategy`, for the differential test design;
  - `python-service-dev`, for the test file;
  - `feature-risk-router`, for risk;
  - `multi-agent-delegation`, for the delegation decision.

  The hook scripts are Bash with no stack owner, so `product-rd-workflow` routes them; their user-visible contract does not change.
- **Delegation:** `local`. The four edits follow one pattern and share one test, so splitting them would mean separate briefs and a merge of one decision.
- **Risk tags:** `shared-gate`, because the hooks are shared enforcement surfaces. Required: a differential test, the existing hook suites, review and challenge. Security posture is unchanged: the same inputs feed the same verdict code. Generated assignments are evaluated only for string values.
- **Visible UI:** none. **Test-case first:** the differential test is written and run RED before the scripts change. Its jq-count assertion fails while each script still reads fields one by one.
- **Artifact class:** `runtime/code` on a shared gate. The verdict, scope and completion semantics do not change, so no gate-design artifact is needed beyond the plan.

## Extraction charter (plugin-behavior surface)

The edit checkpoint routes hook edits through `skill-extraction-workflow`. The skill text does not change.

| Field | Answer |
| --- | --- |
| Purpose | Cut PreToolUse latency without changing any hook verdict. No reusable lesson is extracted. |
| Scope | The four scripts and the differential test. Out of scope: skill text, `hooks.json`, `agy-bridge.py`, the OpenCode plugin and `skill-loading.py`. |
| Depth | Generator/tooling change, meaning hook runtime code. |
| Result classification | Stable success of an evidenced mechanism: the plan's measurements and prototype show jq start-up dominates. |
| Matching analysis | Mechanism: one jq start-up per hook instead of two to five. Evidence: per-hook traces and the prototype table in the plan. Reuse condition: reads whose main form is `$(... \| jq -r ...)`. Owner: the plan. |
| Failure mode | A field decoded differently from main changes a verdict or the recorded state. The differential test guards this. |
| Lifecycle impact | Implementation and testing only. No product intent, design, onboarding or user-visible change. |
| Evidence plan | Baseline `788470c` scripts, the plan, design reviews D1–D3 and benchmark measurements. |
| Completion standard | Differential test green; existing hook suites, the full `make test` and package checks green; latency acceptance met; review and challenge recorded. |

## Test layers

| Layer | Decision | Command |
| --- | --- | --- |
| unit | not applicable | No unit-sized seam; the reads are inline shell. |
| integration/contract | add | `python3 hooks/test_hook_field_reads.py` (differential and jq count) |
| integration/contract | run | the existing suites for each hook, `scripts/owner-dispatch/test.sh`, `hooks/test_agy_bridge.py` |
| E2E/host smoke | run | `npm run smoke:host` in the package directory |
| manual/exploratory | not applicable | Covered by the differential matrix. |
