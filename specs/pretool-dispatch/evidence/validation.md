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
  - `multi-agent-delegation`, for the delegation decision;
  - `skill-extraction-workflow`, which the edit checkpoint requires for hook files;
  - `code-review`, for review and challenge;
  - `tighten-doc`, for this record.

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

- **Engine, merge guard, broad-test guard.** One `jq -rs` call emits `@sh`-quoted assignments, and the script evaluates them. It emits them only for exactly one JSON document whose fields, after their `// default`, are all strings with:
  - at most 65,536 characters, checked first;
  - no NUL;
  - at most 16 trailing newlines, which are stripped as `$(jq -r ...)` did.

  Any other input prints nothing, and the script runs the original per-field reads unchanged, so those payloads behave as on main by construction.
- **Where the values land.**
  - The assignments go to `hf_*` temporaries. These and the buffer are unset first, so they are never exported.
  - Each hook's own variables (`cmd`, `cwd`, `sid`, `tpath`, `SID`, `AID`, `tool`, `fp`) are assigned from them only where the per-field reads assigned them. The environment the hook's children see is therefore the one main gave them.
  - The engine's agent key is `@base64` of the original value, computed after the bounds and mapped by `tr '+/' '-_'` as `aid_key_from` does.
- **Edit guard.** The plan has it keep its trailing-newline-preserving path read and its malformed flag separate from the `@sh` record.
  - Both stay `jq -j` NUL-terminated records, but from one call on fd 3.
  - The flag record comes first and is always emitted, so a malformed patch with no targets is still flagged. Targets are then checked as they arrive, as on main.
  - The jq-only normalizer emits one object per input document. `$(jq -r .malformed_patch)` printed one line per document, so it read `true` only for a single document flagged true; the flag record reproduces that.
  - Paths keep their exact bytes.
- **Deviation from the plan.** The plan's constraints say NULs are removed in jq, trailing newlines are stripped, and values are evaluated as `@sh` assignments. Measured on jq 1.6 and Bash 5.2 under a UTF-8 locale, those steps cost more than linear time or memory on crafted values:

  | Step | Input | Cost |
  | --- | --- | --- |
  | strip loop `until(endswith("\n") \| not; .[:-1])` (first draft) | 40,000 trailing newlines | 6 s |
  | `split("\u0000") \| join("")` | 400,000 NULs | 3.9 s |
  | `eval` of the `@sh` form | 240,000 apostrophes | 3.0 s; 25.7 s at 900,000 |
  | `split` before any length check | a 2 MiB field | 104 MiB, against 16 MiB for a plain read |

  Each hook has a 10 s timeout in `hooks.json`, and a hook that outlives it does not block. Such a payload could carry an unauthorized merge past the guard, while main reads these values in linear time. Values beyond the bounds therefore take the per-field reads. The result is unchanged, and the work stays linear. Within the bounds, evaluating 65,536 apostrophes takes 137 ms.

## Differential test

`hooks/test_hook_field_reads.py`, registered in `make test-repo-gates`.

- **Cases.** 576, pinned as hashes from baseline `788470c`:
  - 22 value variants per read field, including 16 and 17 trailing newlines, plus 8 whole-payload variants per script;
  - real gated edits followed by `owner-dispatch-stop.sh`;
  - merge grants for two sessions, with a second call after each;
  - edit-guard scenarios with and without `host-input.py`, including several documents;
  - stall payloads for each script, held to 5 s (half the host timeout). Both sides finish each in under 1 s:
    - 200,000 trailing newlines, and 60,000 within the length bound;
    - 800,000 NULs, or 100,000 for the broad guard to stay inside its 1 MiB input head;
    - 900,000 apostrophes;
    - a 700,000-character agent id;
  - a 40,000-apostrophe command with `fields` exported in the hook's environment, with and without an agent id;
  - an `apply_patch` of 160 KB under 65,536 characters with `cmd` exported.
- **Compared.** Each case compares:
  - stdout, exit code and every owner-dispatch state file with its contents;
  - merge grants;
  - stderr, where only the line number in Bash's own `<script>.sh: line N:` prefix is normalized.

  The sandbox path is replaced in its literal and both JSON-escaped forms.
- **Checks on every case.** Payload text that would run a command if evaluated (`$(touch PWNED)`, backticks, an array element) must leave no `PWNED` file anywhere in the sandbox. A marker in malformed fields must not reach stderr.
- **jq count.** Each script must start at least the merged number of jq processes fewer than baseline. The count runs on one ordinary payload per script, plus a merge command ending in a newline. Each counted run must exit 0 and start at least one jq.
- **Peak memory.** The merge guard and the engine run on an 800,000-NUL field. Their peak memory, as a ratio to one plain jq read of the same payload on the same host, may exceed the baseline's ratio by at most 25% plus 0.1. Splitting before the length check changes no output, because the read falls back, so only this check sees it.
- **Environment.**
  - The hooks run under a UTF-8 locale, as on a host, because under `C` Bash evaluates quoted text much faster and the apostrophe stall disappears. A host without `C.UTF-8` or `en_US.UTF-8` fails the test rather than running a weaker one.
  - Fixture git commands run under a private `HOME` with no global config, and ignore the caller's `GIT_*` variables. Archiving the baseline keeps the caller's global config (for `safe.directory`) but disables replace objects and uses the full commit id.
- **Fixture entries.** The baseline hooks print different results in 5 cases with GNU and with BSD `tr` and `basename`: non-ASCII session ids, the apostrophe-stall edit and the long agent id. Entries are therefore keyed by OS and by the flavour of those two tools on `PATH`:
  - Linux with GNU tools;
  - macOS with BSD tools;
  - macOS with Homebrew's GNU coreutils first.

  A key without an entry fails with the regeneration step. Regeneration refuses a baseline that timed out.
- **RED.** Commit `0b1bc53`, before the scripts changed: all 506 cases of that version matched baseline, and all 5 jq-count assertions failed (engine 5, merge 4, broad 2, edit 2 processes). Each later regression case was either seen failing on the candidate it guards or is killed by the matching mutation below.
- **GREEN on `dcbe712`.** Each jq count is 1, and all 576 cases pass:
  - on Linux (bash 5.2.15, jq 1.6);
  - on macOS (bash 3.2.57, jq 1.7.1) with BSD tools;
  - on macOS with GNU coreutils.

Mutation walk, run on scratch copies with the Linux fixture of the revision named:

| Mutation | Revision | Result |
| --- | --- | --- |
| buffer not unset first (engine, merge or broad) | `dcbe712` | 1–2 failures each (`exported-fields/*`) |
| engine assigns `cmd` for every tool | `dcbe712`, before a redundant `unset` was removed | 1 failure (`exported-cmd/engine-apply-patch`) |
| merge guard splits before the length check | `dcbe712`, before a redundant `unset` was removed | 1 failure (peak memory) |
| merge guard or engine without the length bound | `9cf75b9` | 1–2 failures (apostrophe stalls timed out) |
| merge guard without the NUL fallback | `9cf75b9` | 16 failures |
| merge guard or engine with the unbounded strip loop | `9cf75b9` | 1–2 failures (`newlines-in-bound` stalls timed out) |
| merge guard with a strip bound of 0 | `9cf75b9` | 1 failure (jq count for the newline-ending command) |
| engine session default `""` instead of `nosession` | `9cf75b9` | 9 failures |
| engine agent key without `tr` | `9cf75b9` | 3 failures |
| engine accepts several documents | `9cf75b9` | 2 failures |
| broad guard drops the command | `9cf75b9` | 12 failures |
| edit guard reads a path in place of the flag | `9cf75b9` | 2 failures |
| edit guard strips path newlines | `9cf75b9` | 2 failures |
| edit guard reads only the first document's paths | `9cf75b9` | 4 failures |
| merge guard drops NULs with `split`/`join` | `74b30f4` | 18 failures |
| merge guard reads the session from the transcript field | `74b30f4` | 36 failures |
| engine without the trailing-newline strip | `74b30f4` | 19 failures |
| engine agent key from the newline-stripped value | `74b30f4` | 9 failures |
| engine agent key mapped with `split`/`join` | `74b30f4` | 1 failure (`stall/engine-bash/agent-key` timed out) |
| engine without the string-type test | `74b30f4` | 0 failures. Equivalent mutant: `split` already fails on every non-string, which selects the per-field reads. The explicit test stays, per design review D3. |
| edit guard takes the first document's flag | `74b30f4` | 0 failures. Equivalent on every reachable input: only the Python normalizer emits `true`, and it emits one document. |

## Existing suites

On `dcbe712`, all pass on Linux (bash 5.2.15, jq 1.6):

- `test_guard_merge_authorization.sh`: 493;
- `test_guard_edit_isolation.sh`: 20;
- `test_guard_broad_local_test.sh`: 107;
- `scripts/owner-dispatch/test.sh`: 98;
- `test_agy_bridge.py`, `test_host_input.py`.

The first four also pass on macOS (bash 3.2.57, jq 1.7.1), on `dcbe712` and on the baseline.

## Implementation review R1

[`review-R1.json`](review-R1.json): Codex, review mode, on `7470868`. It reported 14 findings: 2 P1, 7 P2 and 5 P3. Each was reproduced or checked before acting.

| Finding | Disposition |
| --- | --- |
| P1 fixture git commands inherit `GIT_DIR` and `GIT_INDEX_FILE` | Fixed: the test drops the caller's `GIT_*` variables. |
| P1 `eval` of quote-heavy values exceeds the hook timeout | Reproduced (25.7 s at 900,000 apostrophes, UTF-8 locale). Fixed, first with an apostrophe bound and since C1 by the length bound; pinned by `stall/*/apostrophes`. |
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

## Implementation challenge C1

[`challenge-C1.json`](challenge-C1.json): Codex, challenge mode, on `04637e3`, after the R1 fixes. It reported 8 findings: 5 P2 and 3 P3. Each was reproduced or checked before acting.

| Finding | Disposition |
| --- | --- |
| P2 an inherited exported `fields` passes the buffer to every child | Fixed, and since R2 replaced by the `hf_*` design; pinned by `exported-fields/*`. |
| P2 `split` allocates before the apostrophe bound applies | Reproduced (104 MiB for a 2 MiB field). Fixed with the 65,536-character bound, checked first; the apostrophe bound was removed. Pinned since R2 by the peak-memory check. |
| P2 fixture commits read global git config | Fixed: `GIT_CONFIG_GLOBAL` is null; since R2, also a private `HOME`. |
| P2 benchmark accepts an engine that fails | Fixed: the harness syntax-checks every timed script and runs the engine on the timed payloads, requiring a clean exit. |
| P2 fixture keyed by OS only | Fixed: keyed by OS and by the `tr` and `basename` flavour on `PATH`. |
| P3 regeneration honors replace objects | Fixed: full commit id with `GIT_NO_REPLACE_OBJECTS=1`. |
| P3 a baseline timeout could be saved as expected | Fixed: regeneration refuses a timed-out baseline. |
| P3 JSON-escaped sandbox paths not normalized | Fixed. |

## Incremental review R2 and self-review

[`review-R2.json`](review-R2.json): Codex, review mode, of the C1 fixes only (`04637e3`..`9cf75b9`). It reported 12 findings: 5 P2 and 7 P3. This was the last external pass, so each finding was settled here with a test that failed first or with source evidence.

**Self-review before fixing.** Two findings repeated a C1 class: values reaching the hook's children through an inherited export.
- C1 found the buffer.
- R2 found the agent-key `tr` running before the buffer was cleared, and `cmd` assigned on the `apply_patch` path, where main never assigned it.

The common cause was evaluating into the script's live variable names, which carry any inherited export, and assigning them on paths main did not. Patching each name would leave the class open. The fix changes the shape instead: unexported `hf_*` temporaries, with the real variables assigned only at main's own assignment sites.

| Finding | Disposition |
| --- | --- |
| P2 agent-key `tr` starts before the buffer is cleared | RED: with `fields` exported, the marker key came out empty (`s.S1.a..bashwrite`). Fixed by the `hf_*` design; pinned by `exported-fields/engine-bash-agent`. |
| P2 `cmd` assigned and exported on the `apply_patch` path | RED with a 160 KB patch under 65,536 characters: `jq: Argument list too long`, silent allow, no marker. Fixed by the `hf_*` design; pinned by `exported-cmd/engine-apply-patch`. |
| P2 no fixture for macOS with GNU coreutils | Fixed: entry generated on macOS with Homebrew's `gnubin` first; 576 cases pass there. |
| P2 benchmark accepts an empty engine | Fixed: the engine must answer `status`. A zero-byte engine is now rejected. |
| P2 benchmark does not check the Python helpers | Fixed: the helpers are compiled in memory before timing. A syntax error in `skill-loading.py` is now rejected. |
| P3 jq-style escaping of the sandbox path not normalized | Fixed: the unescaped-non-ASCII JSON form is also replaced. |
| P3 agent key encoded before the length check | Fixed: the key is encoded after the bounds. Source evidence; it changes no output. |
| P3 git before 2.32 ignores `GIT_CONFIG_GLOBAL` | Fixed: fixture git commands also run under a private `HOME` and `XDG_CONFIG_HOME`. |
| P3 null global config breaks `safe.directory` for the baseline archive | Fixed: archiving keeps the caller's global config; only fixture commands drop it. |
| P3 no test that the length check precedes `split` | Fixed: the peak-memory check, which the split-first mutation fails. Measured directly on Linux, the hook's peak was 29.7 MiB as written and 51.5 MiB with `split` first. |
| P3 latency recorded for earlier scripts | Fixed: the Latency section measures `dcbe712`. |
| P3 C1 severity totals wrong | Fixed: 5 P2 and 3 P3. |

## Full local verification

Run on `3eccfb0` with `CCL_BROAD_TEST_REASON=repo-required`, `umask 022`, and pytest and PyYAML from a Python 3.12 virtual environment:

| Check | Result |
| --- | --- |
| `make test-repo-gates` | passed |
| `make test-code-review-1` and `-2` | passed |
| `make test-code-review-abort-leak-1` and `-2` | passed. Run under `unshare`, because the Orca session's subreaper is not PID 1. |
| `make npm-publish-dry`, `npm test` | passed |
| `make test-regressions-fast` | One suite failed: `test_ci_checkout_ref_binding.sh`. The run exported `CCL_SKILL_DEFAULT_BASE_REF=origin/main`, which overrides the Makefile default the suite checks. Without that variable, the suite passes. |
| `npm run smoke:host` | Failed on `3eccfb0` and on a clean `788470c` alike. See below. |

**Host smoke repair.** The smoke failed before this change, for two reasons, each confirmed by rerunning after the previous fix:
- **Synthetic source.** It copied a fixed list of roots that lacks `.antigravity-plugin` and the root `hooks.json`, both of which `build-assets.mjs` builds from since Antigravity host support landed. The build of the synthetic 1.0.0 source then failed with `missing runtime closure: .../.antigravity-plugin/plugin.json`.
- **Claude isolation.** It sets `HOME` but not `CLAUDE_CONFIG_DIR`. On a host that sets that variable, the smoke's `claude` commands read and change the caller's real profile; here the install refused with `double-install` because that profile holds a Git-marketplace install.

`host-smoke.sh` now copies both roots and unsets `CLAUDE_CONFIG_DIR`, and the scripts contract records both rules. The smoke then passes with `three-host-smoke-passed`.

## Latency

`evidence/bench/hook_latency.py` compares `788470c` with a candidate tree extracted by `git archive`, in the same run. Figures are medians of 11 runs in ms.

Harness changes:
- It resolves its three paths at start-up.
- It refuses a tree whose engine or helpers are missing, fail to parse, or whose engine does not answer `status` or fails on the timed payloads.
- It stops on a hook that exits non-zero, times out, or reports a degraded or unavailable component.
- It drops the retired `--dispatcher` mode.

The output format is unchanged.

**Linux** (32 cores, jq 1.6, bash 5.2.15, Python 3.11.2 at `/usr/bin/python3` as in the plan, load average 10–16), candidate `dcbe712`:

| Run | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- |
| 1 | 196 → 108 | 468 → 296 | 200 → 111 | 318 → 209 |
| 2 | 194 → 110 | 465 → 295 | 197 → 111 | 321 → 208 |
| 3 | 194 → 109 | 464 → 292 | 196 → 111 | 317 → 206 |

- Parallel Bash and Edit each drop 43–45%, which meets the 40% line. Serial Bash drops 37%.
- Other sessions load this host unevenly. At load 50–68, an earlier candidate measured 39–44%, because contention inflates both sides.
- **Python 3.12.** The first `python3` on this host's `PATH` is `~/.local/bin/python3` (3.12.13). It recompiles standard-library imports on every start: `import json` costs about 55 ms there, against about 5 ms in 3.11.2.
  - The unchanged `skill-loading.py` then takes 160–172 ms, against 57 ms, and dominates the critical hook.
  - With that interpreter, the first draft (`3484d75`) measured a 27–33% drop. The change saves the same jq time; the larger Python start-up dilutes the share.
- **Parts,** first draft, median of 21 from a scratch script:
  - one bare `jq -r` costs 21 ms;
  - `owner-dispatch.sh pretool` (Bash) drops from 136 to 46 ms;
  - `guard-merge-authorization.sh` drops from 129 to 64 ms.

**macOS** (18 cores, jq 1.7.1, bash 3.2.57, Python 3.9.6, load average 4–7), candidate `dcbe712`:

| Run | Bash parallel | Bash serial | Edit parallel | Edit serial |
| --- | --- | --- | --- | --- |
| 1 | 105 → 94 | 265 → 237 | 111 → 107 | 200 → 183 |
| 2 | 102 → 92 | 261 → 238 | 111 → 108 | 199 → 181 |
| 3 | 104 → 95 | 270 → 242 | 113 → 110 | 200 → 187 |

Neither call gets slower, which meets the macOS line.
