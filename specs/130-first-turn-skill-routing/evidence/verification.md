# Task-entry and continuation verification

Version candidate: `0.18.3`; base: `688ff9f11871259729fc49a5230106c2f6432539`. Pull-request checks and merge receipts are authoritative for integration state; publication remains a separate operation.

## Scope

- Deliver canonical owner routing before task processing on the supported native hook and OpenCode system-transform paths.
- Recheck a declared next action before Stop, preserving existing authority, explicit user limits and native loop prevention.
- Keep startup text byte-identical, prompt contents out of the new renderer, and npm/plugin distribution aligned.
- Preserve release/shared-gate profiles in the extraction wrapper's separate review and challenge passes, without changing default staged-review requirements.

## Checks completed before independent review

| Check | Observation | Boundary |
| --- | --- | --- |
| `python3 hooks/test_task_entry.py` | 6 passed; registration and followthrough wording each had a failing baseline | Context delivery and failure paths, not universal adherence |
| `python3 hooks/test_proposed_next.py` | 21 passed; action-marker bypass and transcript dependency had failing baselines | Native-shaped Stop payloads, status/quote/artifact/retry boundaries |
| `python3 hooks/test_host_input.py` | 33 passed | Existing input normalization |
| Missing Python and invalid UTF-8 fixtures | Exit 0, empty JSON and bounded diagnostic | New renderer failure paths |
| Native prompt-hook comparison | Initial runs exposed parallel business reads and partial skill coverage. After cue refinement, the same three candidate cases completed successfully: product workflow 233/233 lines and defect owner 166/166 lines returned before business-tool calls; trivial answer used no tools | Public tool-result content matched source lines and event order; small fixed sample, not a population pass rate |
| Native Stop comparison | Baseline declared the pending read and stopped; candidate resumed and performed it. Explicit status-only scope performed no read after the reminder | Synthetic controlled workflow; actual Stop block/continuation events observed; no write/execution tools or MCP |
| `make -j3 test` | Full lane passed with host process visibility; the sandbox run failed the process-state helper, whose host rerun passed 11/11 | Repository, fast regression and review regression lanes; no test assertion was weakened |
| Package and pack refresh | The complete package run passed 356/356 with an isolated temporary npm cache; the refreshed pack suite passed 11/11 and `npm pack --dry-run` passed | Packaged hook presence, artifact integrity and installation recovery; initial default-cache and sandbox failures remain separate diagnostics |
| `npm run smoke:host` | `three-host-smoke-passed` for Claude Code, Codex and OpenCode | Native install/update/uninstall lifecycle and hook registration, not three-host inference compliance |
| Killing-mutation walk | 11 paired controls passed and deliberate regressions failed named assertions; source bytes remained unchanged | Registration, analysis boundary, prompt independence, followthrough, diagnostics, duplicate/oversized context, action recheck, quotes, transcript independence and loop prevention |
| Extraction review-entry regression | Real-controller build, release and shared-gate probes passed; the release review failed before the repair. Five disposable mutations failed their named checks after a passing control | Owner-lane selection, high-risk entry, unchanged staged-risk refusal, chain rejection and scope reconstruction; synthetic same-family client never executes |
| Structure, routing and private leakage checks | `ccl_skill_check_clean_ok`; `public_sanitization_ok`; whitespace check passed | Configured deterministic properties only |

## Integration and publication

Independent review and challenge receipts are required alongside this file before integration. Integration uses protected pull requests through `dev` and `main`, with exact-head CI and platform merge receipts. Tag publication and registry-only consumer verification are outside this merge delivery. The local process-state tests require permission to inspect `ps`; a sandbox refusal is not a passed process-cleanup test.

## Operational boundaries

New context is 2,779 UTF-8 bytes, capped at 4,096. Hooks require the existing Bash/Python runtime and host support. No new credentials, database migrations or package dependencies are introduced. Stop rechecks are bounded by native `stop_hook_active`; malformed/unsupported surfaces remain fail-soft. OpenCode supplies task-entry context but has no native final-message evidence for this Stop check. Prompt-time delivery and a bounded recheck do not guarantee correct owner choice or completion on arbitrary tasks.

Use the existing immutable tag/OIDC release workflow. A bad published version requires a replacement patch; no tag rewrite or unpublish is part of this delivery.
