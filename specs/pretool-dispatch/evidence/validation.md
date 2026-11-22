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

## How each read is merged

- **Engine, merge guard, broad-test guard.** One `jq -rs` call emits `name='value'` assignments with `@sh`. It does so only for exactly one JSON document whose fields are all strings after their `// default`. Before quoting, it drops NULs and strips trailing newlines, which is what `$(jq -r ...)` did. Any other input prints nothing: a parse error, several documents, or a number, boolean, array or object field. The script then runs the original per-field reads unchanged, so those payloads behave as on main by construction. The engine's agent key is still `@base64` of the original value, with `+/` mapped to `-_`.
- **Edit guard.** The plan has it keep its trailing-newline-preserving path read and its malformed flag separate from the `@sh` record. Both stay `jq -j` NUL-terminated records, but from one call. The flag record comes first and is always emitted, so a malformed patch with no targets is still flagged. Paths keep their exact bytes. The flag gets the same NUL and newline treatment as above.

## Differential test

`hooks/test_hook_field_reads.py`, registered in `make test-repo-gates`.

- **Cases.** 506, pinned as hashes from baseline `788470c`:
  - 20 value variants per read field, plus 8 whole-payload variants per script;
  - real gated edits followed by `owner-dispatch-stop.sh`;
  - merge grants for two sessions, with a second call after each;
  - edit-guard scenarios with and without `host-input.py`.
- **Checks on every case.** Payload text that would run a command if evaluated (`$(touch PWNED)`, backticks, an array element) must leave no `PWNED` file anywhere in the sandbox. A marker in malformed fields must not reach stderr.
- **jq count.** Each script must start at least the merged number of jq processes fewer than baseline, for one ordinary payload.
- **RED.** Commit `0b1bc53`, before the scripts changed: all 506 cases matched baseline, and all 5 jq-count assertions failed (engine 5, merge 4, broad 2, edit 2 processes).
- **GREEN.** Each count is now 1, and 506 cases, 0 failures.
- **Cross-platform.** The Linux-generated fixture also passes on macOS: 506 cases, 0 failures, with bash 3.2.57 and jq 1.7.1. A 1e1000 variant was dropped because jq 1.6 and 1.7 print it differently. Non-string values take the per-field reads anyway.

Mutation walk, run on scratch copies with the same fixture:

| Mutation | Result |
| --- | --- |
| merge guard keeps NULs | 5 failures |
| engine keeps trailing newlines | 13 failures |
| engine session default `""` instead of `nosession` | 9 failures |
| engine agent key from the NUL-stripped value | 9 failures |
| engine agent key without the `+/` mapping | 3 failures, after adding the `base64-specials` variant; it survived before |
| engine accepts several documents | 2 failures |
| broad guard drops the command | 16 failures |
| edit guard reads a path in place of the flag | 2 failures |
| edit guard strips path newlines | 2 failures |
| merge guard reads the session from the transcript field | 43 failures |
| engine without the string-type check | 0 failures. Equivalent mutant: `split` already fails on every non-string, which selects the per-field reads. The explicit check stays, per design review D3. |

## Existing suites

On Linux (bash 5.2.15, jq 1.6), all pass:

- `test_guard_merge_authorization.sh`: 493;
- `test_guard_edit_isolation.sh`: 20;
- `test_guard_broad_local_test.sh`: 107;
- `scripts/owner-dispatch/test.sh`: 98;
- `test_agy_bridge.py`, `test_host_input.py`;
- `test_merge_authorization_prompt.sh`: 119.

On macOS (bash 3.2.57, jq 1.7.1), the first four suites pass on both baseline and candidate.

## Latency

`evidence/bench/hook_latency.py` compares `788470c` with the working tree on top of `0b1bc53` in the same run. Figures are medians of 11 runs in ms.

The harness now resolves its three paths at start-up and stops on a hook that exits non-zero, times out or prints a degrade warning. It also drops the retired `--dispatcher` mode. The output format is unchanged.

**Linux** (32 cores, jq 1.6, bash 5.2.15, load average 8–11 from other sessions):

| Python | Run | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- | --- |
| 3.11.2 (`/usr/bin/python3`, as in the plan) | 1 | 202 → 112 | 482 → 303 | 202 → 113 | 319 → 212 |
| | 2 | 198 → 110 | 466 → 293 | 198 → 111 | 319 → 211 |
| | 3 | 198 → 114 | 478 → 301 | 203 → 115 | 326 → 213 |
| 3.12.13 (`~/.local/bin/python3`, first on `PATH`) | 1 | 299 → 208 | 574 → 392 | 306 → 230 | 566 → 425 |
| | 2 | 313 → 212 | 576 → 412 | 302 → 215 | 521 → 407 |
| | 3 | 298 → 208 | 574 → 402 | 313 → 217 | 523 → 413 |

- **With Python 3.11.2,** parallel Bash and Edit each drop 43–45%, which meets the 40% line. Serial Bash drops 37%.
- **With the 3.12 interpreter,** the drop is 27–33%, because the critical hook is dominated by `skill-loading.py`, which this change does not touch. That interpreter recompiles its standard-library imports on every start: `import json` costs about 55 ms against about 5 ms in 3.11.2. `skill-loading.py` alone takes 160–172 ms there against 57 ms in 3.11.2.
- **Parts,** measured with Python 3.12 by a scratch script (median of 21):
  - one bare `jq -r` costs 21 ms;
  - `owner-dispatch.sh pretool` (Bash) drops from 136 to 46 ms;
  - `guard-merge-authorization.sh` drops from 129 to 64 ms.

**macOS** (18 cores, jq 1.7.1, bash 3.2.57, Python 3.9.6, load average 3–4):

| Run | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- |
| 1 | 95 → 84 | 239 → 217 | 104 → 101 | 183 → 168 |
| 2 | 95 → 84 | 247 → 217 | 104 → 102 | 186 → 172 |
| 3 | 94 → 84 | 245 → 218 | 107 → 107 | 196 → 179 |

Neither call gets slower, which meets the macOS line.
