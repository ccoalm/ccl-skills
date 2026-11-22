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

- **Engine, merge guard, broad-test guard.** One `jq -rs` call emits `name='value'` assignments with `@sh`, and the script evaluates them. It emits them only for exactly one JSON document whose fields, after their `// default`, are all strings with:
  - no NUL;
  - at most 16 trailing newlines;
  - at most 1000 apostrophes.

  Trailing newlines are stripped, as `$(jq -r ...)` did. Any other input prints nothing, and the script then runs the original per-field reads unchanged, so those payloads behave as on main by construction. The engine's agent key is `@base64` of the original value, mapped by `tr '+/' '-_'` as `aid_key_from` does.
- **Edit guard.** The plan has it keep its trailing-newline-preserving path read and its malformed flag separate from the `@sh` record.
  - Both stay `jq -j` NUL-terminated records, but from one call on fd 3.
  - The flag record comes first and is always emitted, so a malformed patch with no targets is still flagged. Targets are then checked as they arrive, as on main.
  - The jq-only normalizer emits one object per input document. `$(jq -r .malformed_patch)` printed one line per document, so it read `true` only for a single document flagged true; the flag record reproduces that.
  - Paths keep their exact bytes.
- **Deviation from the plan.** The plan's constraints say NULs are removed in jq, trailing newlines are stripped, and values are evaluated as `@sh` assignments. Measured on jq 1.6 and Bash 5.2 under a UTF-8 locale, three of those steps cost more than linear time:

  | Step | Input | Time |
  | --- | --- | --- |
  | strip loop `until(endswith("\n") \| not; .[:-1])` (first draft) | 40,000 trailing newlines | 6 s |
  | `split("\u0000") \| join("")` | 400,000 NULs | 3.9 s |
  | `eval` of the `@sh` form | 240,000 apostrophes | 3.0 s; 25.7 s at 900,000 |

  Each hook has a 10 s timeout in `hooks.json`, and a hook that outlives it does not block. Such a payload could carry an unauthorized merge past the guard, while main reads these values in linear time. Values beyond the bounds above therefore take the per-field reads: the decoded result is unchanged, and the work stays linear.

## Differential test

`hooks/test_hook_field_reads.py`, registered in `make test-repo-gates`.

- **Cases.** 567, pinned as hashes from baseline `788470c`:
  - 22 value variants per read field, including 16 and 17 trailing newlines, plus 8 whole-payload variants per script;
  - real gated edits followed by `owner-dispatch-stop.sh`;
  - merge grants for two sessions, with a second call after each;
  - edit-guard scenarios with and without `host-input.py`, including several documents;
  - stall payloads for each script, held to 5 s, half the host timeout: 200,000 trailing newlines; 800,000 NULs, or 100,000 for the broad guard to stay inside its 1 MiB input head; 900,000 apostrophes; and a 700,000-character agent id. Both sides finish each in under 1 s.
- **Environment.** The hooks run under a UTF-8 locale, as on a host, because under `C` Bash evaluates quoted text much faster and the apostrophe stall disappears. A host without `C.UTF-8` or `en_US.UTF-8` fails the test rather than running a weaker one. Fixture git commands ignore the caller's `GIT_*` variables.
- **Compared.** Each case compares:
  - stdout, exit code and every owner-dispatch state file with its contents;
  - merge grants;
  - stderr, where only the line number in Bash's own `<script>.sh: line N:` prefix is normalized.
- **Checks on every case.** Payload text that would run a command if evaluated (`$(touch PWNED)`, backticks, an array element) must leave no `PWNED` file anywhere in the sandbox. A marker in malformed fields must not reach stderr.
- **jq count.** Each script must start at least the merged number of jq processes fewer than baseline. The count runs on one ordinary payload per script, plus a merge command ending in a newline. Each counted run must exit 0 and start at least one jq.
- **Per platform.** GNU and BSD `tr` and `basename` make the baseline hooks print different results in 5 cases, so the fixture keeps one entry per platform. The cases are non-ASCII session ids, the apostrophe-stall edit, and the long agent id. A platform without an entry fails with the regeneration step.
- **RED.** Commit `0b1bc53`, before the scripts changed: all 506 cases of that version matched baseline, and all 5 jq-count assertions failed (engine 5, merge 4, broad 2, edit 2 processes).
- **GREEN.** Each count is now 1. On Linux (bash 5.2.15, jq 1.6), all 567 cases pass; on macOS (bash 3.2.57, jq 1.7.1), all 567 pass against that platform's baseline.

Mutation walk on `74b30f4`, run on scratch copies with the Linux fixture:

| Mutation | Result |
| --- | --- |
| merge guard without the NUL fallback | 17 failures |
| merge guard without the apostrophe bound | 1 failure (`stall/merge/apostrophes` timed out) |
| merge guard with the unbounded strip loop | 1 failure (`stall/merge/newlines` timed out) |
| merge guard with a strip bound of 0 | 1 failure (jq count for the newline-ending command) |
| merge guard drops NULs with `split`/`join` | 18 failures |
| merge guard reads the session from the transcript field | 36 failures |
| engine without the trailing-newline strip | 19 failures |
| engine session default `""` instead of `nosession` | 9 failures |
| engine agent key from the newline-stripped value | 9 failures |
| engine agent key without `tr` | 3 failures |
| engine agent key mapped with `split`/`join` | 1 failure (`stall/engine-bash/agent-key` timed out) |
| engine accepts several documents | 2 failures |
| broad guard drops the command | 11 failures |
| edit guard reads a path in place of the flag | 2 failures |
| edit guard strips path newlines | 2 failures |
| edit guard reads only the first document's paths | 4 failures |
| engine without the string-type test | 0 failures. Equivalent mutant: `split` already fails on every non-string, which selects the per-field reads. The explicit test stays, per design review D3. |
| edit guard takes the first document's flag | 0 failures. Equivalent on every reachable input: only the Python normalizer emits `true`, and it emits one document. |

## Existing suites

On Linux (bash 5.2.15, jq 1.6), all pass on `74b30f4`:

- `test_guard_merge_authorization.sh`: 493;
- `test_guard_edit_isolation.sh`: 20;
- `test_guard_broad_local_test.sh`: 107;
- `scripts/owner-dispatch/test.sh`: 98;
- `test_agy_bridge.py`, `test_host_input.py`.

On macOS (bash 3.2.57, jq 1.7.1), the first four pass on `74b30f4` and on the baseline.

## Implementation review R1

[`review-R1.json`](review-R1.json): Codex, review mode, on `7470868`. It reported 14 findings: 2 P1, 7 P2 and 5 P3. Each was reproduced or checked before acting.

| Finding | Disposition |
| --- | --- |
| P1 fixture git commands inherit `GIT_DIR` and `GIT_INDEX_FILE` | Fixed: the test drops the caller's `GIT_*` variables. |
| P1 `eval` of quote-heavy values exceeds the hook timeout | Reproduced (25.7 s at 900,000 apostrophes, UTF-8 locale). Fixed with the 1000-apostrophe bound; pinned by `stall/*/apostrophes`. |
| P2 agent-key `split`/`join` is superlinear | Fixed: `tr`, as on main; pinned by `stall/engine-bash/agent-key`. |
| P2 a second normalized document becomes a target | Reproduced with `{}{}`. Fixed: the flag covers all documents and paths come from each; pinned by `two-empty-docs` and `two-docs-second-protected`. |
| P2 edit guard buffers every target before checking | Fixed: the flag and targets are read and checked as they arrive on fd 3. |
| P2 stall limit looser than the 10 s host timeout | Fixed: 5 s. |
| P2 broad guard's NUL stall payload exceeds its 1 MiB head | Fixed: 100,000 NULs for that guard. |
| P2 benchmark accepts a tree missing the engine | Fixed: the harness requires the engine and helpers and rejects output reporting an unavailable component. |
| P2 stderr normalization hides lines | Fixed: only the line number in Bash's own prefix is normalized. |
| P3 snapshot files compared by presence only | Fixed: contents are compared. |
| P3 jq count accepts a failed run | Fixed: the run must exit 0 and start a jq. |
| P3 timed-out hook descendants survive | Fixed: own process group, killed on timeout. |
| P3 sandbox path not JSON-escaped | Fixed. |
| P3 latency figures not bound to a revision | Fixed: the Latency section names the measured commit. |

## Latency

`evidence/bench/hook_latency.py` compares `788470c` with a candidate tree extracted by `git archive`, in the same run. Figures are medians of 11 runs in ms. The hook scripts are identical in `74b30f4` and `e2b267b`.

The harness now resolves its three paths at start-up. It refuses a tree missing the engine or its helpers, and stops on a hook that exits non-zero, times out or reports a degraded or unavailable component. It also drops the retired `--dispatcher` mode. The output format is unchanged.

**Linux** (32 cores, jq 1.6, bash 5.2.15, Python 3.11.2 at `/usr/bin/python3` as in the plan). Other sessions load this host heavily and unevenly:

| Candidate | Load average | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- | --- |
| `7470868` | 9–11 | 202 → 112 | 482 → 303 | 202 → 113 | 319 → 212 |
| | | 198 → 110 | 466 → 293 | 198 → 111 | 319 → 211 |
| | | 198 → 114 | 478 → 301 | 203 → 115 | 326 → 213 |
| `74b30f4` | 50–68 | 314 → 182 | 691 → 459 | 287 → 172 | 462 → 314 |
| | | 270 → 166 | 634 → 416 | 265 → 152 | 424 → 284 |
| | | 254 → 154 | 605 → 404 | 259 → 149 | 412 → 286 |
| | | 262 → 150 | 619 → 398 | 255 → 144 | 408 → 265 |

- At load 9–11, parallel Bash and Edit drop 43–45%, which meets the 40% line.
- At load 50–68, `74b30f4` drops 39–43% (Bash) and 40–44% (Edit). Contention inflates both sides. A run at low load on `74b30f4` is still owed before the line is claimed for it.
- `74b30f4` changes only the fallback bounds, the agent-key `tr` and the edit guard's streaming. For ordinary payloads it adds one short `split` per field inside the same jq call.
- **Python 3.12.** The first `python3` on this host's `PATH` is `~/.local/bin/python3` (3.12.13). It recompiles standard-library imports on every start: `import json` costs about 55 ms there, against about 5 ms in 3.11.2.
  - The unchanged `skill-loading.py` takes 160–172 ms under it, against 57 ms under 3.11.2. It then dominates the critical hook.
  - With that interpreter, the first draft (`3484d75`) measured parallel Bash 298–313 → 208–212 and Edit 302–313 → 215–230, a 27–33% drop. The change saves the same jq time; the larger Python start-up dilutes the share.
- **Parts,** first draft, median of 21 from a scratch script:
  - one bare `jq -r` costs 21 ms;
  - `owner-dispatch.sh pretool` (Bash) drops from 136 to 46 ms;
  - `guard-merge-authorization.sh` drops from 129 to 64 ms.

**macOS** (18 cores, jq 1.7.1, bash 3.2.57, Python 3.9.6, load average 3–4), candidate `74b30f4`:

| Run | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- |
| 1 | 94 → 85 | 239 → 216 | 104 → 100 | 183 → 168 |
| 2 | 94 → 84 | 239 → 216 | 104 → 100 | 183 → 168 |
| 3 | 95 → 84 | 242 → 216 | 103 → 100 | 183 → 168 |

Neither call gets slower, which meets the macOS line.
