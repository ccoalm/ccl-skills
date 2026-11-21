# Validation: Antigravity host support

All runs use scratch `HOME`/`TMPDIR` directories and synthetic git repositories. Host: Linux, `agy` 1.5.14, Python 3.11, Node.js 26. Paths below are shown relative to the scratch root.

## Behavioral evidence (`RED-baseline`, constructed scenario)

| Probe | Base tree (`3ae87ae`) | Candidate |
| --- | --- | --- |
| `agy plugin validate .` | `✗ plugin.json: no plugin.json found at the plugin root or in .antigravity-plugin or .gemini-plugin`; 1 error | `✔ Validation passed with 21 warnings`, 0 errors |
| `HOME=<scratch> agy plugin install <tree>` | converted as a Claude extension; `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `UserPromptSubmit` skipped; installed copy lacks `hooks/hooks.json` | native install, `source: antigravity`, `diff -rq` between source and installed copy empty |
| Converted `guard-edit-isolation.sh` given an Antigravity `PreToolUse` payload (`write_to_file` into a `.worktree-only` primary checkout) | empty stdout, exit 0: allowed | bridge returns `{"decision":"deny","reason":"隔离闸：…"}` |
| Control: same script, equivalent Claude payload | `permissionDecision: deny` | unchanged |
| Installed shared-skill scope (`/.gemini/config/plugins/…/skills/x/SKILL.md`), `skill-loading.py` and the extraction stop gate | in scope (path returned; gate blocks) | exempt; ordinary-checkout control still in scope and blocks |

The bridge suite was written after the first bridge draft existed; its RED for T1–T11 is the absence of any bridge on the base tree (no Antigravity handler at all). T12 was written and run red before the exemption patch (`2 failures`, then `OK`).

## Test-case register results

| ID | Command | Result |
| --- | --- | --- |
| T1–T11 | `python3 hooks/test_agy_bridge.py` | 38 tests OK |
| T12 | same suite, `ScopeExemptionTests` | RED before patch, OK after |
| T13–T15 | `node --test test/antigravity.test.mjs` (after `npm run build`) | 14 pass |
| T15 | `agy plugin validate dist/assets/marketplace/plugins/ccl-skills` | `✔ Validation passed with 20 warnings` |
| T16 | `bash scripts/test_install_antigravity.sh` | 13 ok |
| T17 | live `agy -p`, below | pass |

## Killing-mutation walk

Each mutation was applied, run and reverted: bridge rows in a scratch copy of `hooks/`, `skills/` and `agent-context/`; npm rows in the compiled `dist/` copy, restored by a rebuild; the installer row inside its own suite.

| Protected predicate | Mutation | Killing test |
| --- | --- | --- |
| unknown edit target denies | `if not targets` → `if False` | `test_unknown_edit_target_fails_closed` |
| guard that cannot run denies | fail-closed branch → `if False` | `test_guard_that_cannot_run_fails_closed` |
| bridge exception on `PreToolUse` denies | fallback → allow | `test_bridge_exception_on_guarded_tool_denies` |
| script `deny` maps to `deny` | `if decision == 'deny'` → `if False` | primary-checkout, symlink and delegation cases |
| skill read lines must match | line comparison → `if False` | `test_forged_or_mismatched_reads_are_not_a_load` |
| skill load needs full coverage | `len(seen) == len(lines)` → `if seen` | `test_partial_read_is_not_a_load` |
| task entry once per turn | turn-claim check → `if False` | `test_task_entry_runs_once_per_user_turn` |
| `continuationActive` stops loops | check → `if False` | `test_stop_maps_a_blocking_hook_to_continue` |
| non-`NO_TOOL_CALL` stop allows | check → `if False` | `test_stop_maps_a_blocking_hook_to_continue` |
| path keys beyond `Path` | `PATH_KEYS` → `Path` only | `test_primary_checkout_edits_are_denied_like_the_claude_path` |
| installer replaces only its own install | ownership `if` → `if false` | encoded inside `scripts/test_install_antigravity.sh` (case 4; it now requires a real fake-host install that replaces the sentinel) |
| npm: compensation removes a plugin this attempt installed | rollback `agy plugin uninstall` removed | `compensates a host install that changed state and then failed` |
| npm: never adopt an unmanaged root | foreign-entry check → `[]` | `never adopts an unmanaged root…` |
| npm: a journal never vouches for a plugin | `state-unknown` branch disabled | `A journal never makes a hand-installed plugin look npm-owned` |
| npm: failed update restores the backup | backup reinstall disabled | update/downgrade/failed-update test |
| npm: shared installer lock | `acquireLock` replaced by a no-op | `install waits for the shared installer lock` |
| bridge: no lexical `..` collapse | `normpath` restored | `test_parent_component_through_a_symlinked_directory…` |
| bridge: workspace root only when unambiguous | first root of any list | `test_relative_target_without_a_known_cwd_is_denied` |
| bridge: a merge guard that cannot run blocks every command | merge guard removed from the fail-closed set | `test_every_command_fails_closed_when_merge_guard_cannot_run` |
| bridge: deny beats ask across patch targets | return on the first ask | `test_a_later_denied_target_beats_an_earlier_ask` |
| bridge: bounded run-lock wait | blocking `flock` | `test_an_event_queued_behind_a_slow_one_still_answers_in_budget` |
| installer: inventory-based ownership | inventory check bypassed (`if false && …`) | installer case 4, which requires a real fake-host install |

The first walk did not apply the `deny` mutation (indentation) and showed the `continuationActive` test was insensitive (both branches allowed with no blocking hook). The test now uses a blocking stop hook; both mutations then turned it red.

## Live host smoke (T17)

The packed plugin was placed at `<workspace>/.agents/plugins/ccl-skills` (workspace plugins override the global one by name, so no user configuration changed). Workspace: a synthetic repository with `.worktree-only` on `main`.

1. `agy -p "<create hello.txt with your file-writing tool; quote any block reason; say whether context contains ccl-skills-routing and ccl-task-entry>" --dangerously-skip-permissions`: `write_file` was rejected with `tool call denied by pre-tool hook: 隔离闸：[…] 标记为共享仓库（.worktree-only），禁止直接改主检出…`; `hello.txt` was not created; the model reported both markers present. Bridge state shows a `.turn` file (candidate bridge ran) and no file of the earlier local prototype.
2. `read_file` of a bundled skill (80 lines, longest 684 characters): results read `Showing lines 1-80 of 80`; `shadow_events` on the real transcript yields `ccl-skills:grill-me`.
3. `read_file` of `product-rd-workflow/SKILL.md` in four chunks (`1-50`, `51-70`, `71-90`, `91-105 of 105`): every shown line matches the bundled bytes; evidence yields `ccl-skills:product-rd-workflow`.

4. After the R1 fixes, rerun with the rebuilt plugin: `run_command` (`git status --short`) allowed; `write_file` to `hello.txt` denied with the same guard reason and not created; both markers in context; the bridge state directory holds only lock and per-hook turn files, no shadow transcript.

5. Host acceptance of `overwrite` and Stop `continue` (scratch workspace plugin with `subagent-start.sh` stubbed to inject `MARKER-SUBAGENT-7Q: begin your answer with the token ZETA-ACK.` and `proposed-next-stop.sh` stubbed to block once): the subagent's reply began with `ZETA-ACK` (it received the prepended context); the blocking Stop produced exactly one continuation (`CONTINUED-ONCE`) and the turn then ended.

npm adapter with the real CLI in a scratch `HOME`: `install` → `installed`, `doctor` → `healthy`, `uninstall --yes` → `uninstalled`, `doctor` → `absent`.

## Security first pass (`security-first-pass-only`)

Read-only triage of the new input surface; not a security audit. Checked: hook stdin parsed as one JSON object, anything else denies on `PreToolUse`; `conversationId` reaches the file system only as a strict token or its SHA-256; `transcriptPath` is opened non-blocking, regular files only, last 32 MiB; skill evidence is checked against bundled bytes; state directory must be owned by the user and is forced to 0700, files 0600; user prompt text and tool output are not copied into the shadow transcript; `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` are stripped so the merge guard never takes its Claude-only `allow` path. Skill-load evidence trusts the integrity of the host transcript: the byte comparison rejects incomplete or mismatched reads, but a process that can write the user's Antigravity transcript can forge any evidence in it. Residual: `send_command_input` is not routed to the merge guard (no host routes it).

## Review R1 (extraction lane, `--mode review`, reviewer: Codex)

Result: `review-R1.json`, 13 P1 and 10 P2. Every finding was checked against the code; all were accepted and fixed, with a regression case each.

| Finding | Fix | Regression proof |
| --- | --- | --- |
| npm downgrade deletes the reactivated snapshot | prune only snapshots the committed manifest no longer references | update/downgrade test asserts both manifest snapshots exist; mutation killed |
| npm crash between host install and manifest commit | operation journal written before each mutation, reconciled by the next run | `reconciles an operation that died…` |
| npm rollback removes or overwrites concurrent changes | exclusive operation lock; compensate only state this attempt produced; verify after | `compensates…`, `update, downgrade and failed update…` |
| npm fresh install ignores an unlisted directory or malformed list | require an absent destination (`lstat`) and a well-formed list | `never adopts…`, `rejects a malformed host list` |
| npm adopts and later deletes an unmanaged root | refuse a root with foreign entries; uninstall deletes only manifest snapshots, keeps drifted ones | `never adopts an unmanaged root` |
| installer: renamed staged manifest replaces another plugin | staged `name` must equal `ccl-skills` before `agy` runs | installer case 6 |
| installer: `tar` follows a tracked path replaced by a directory, or symlinks | stage each tracked path as a verified regular file with no symlink ancestor | installer case 7 |
| bridge: malformed `toolCall` or unreadable command allowed | deny | `test_malformed_tool_call_is_denied`, `test_run_command_without_a_command_is_denied` |
| bridge: landing classifier misses `git -C … push` | git global options accepted before `push`/`merge`; `curl`/`wget` stay conservative, as in the OpenCode adapter | `test_landing_command_fails_closed…` |
| bridge: patch headers read from file contents | patch headers only from `apply_patch` | `test_patch_text_inside_file_contents_is_not_a_target` |
| bridge: relative target checked against the bridge's own directory | relative target without a host cwd denies | `test_relative_target_without_a_known_cwd_is_denied` |
| bridge: shadow keeps commands and prompts after the event | shadow deleted when each event ends | `test_shadow_transcript_is_private_structural_and_removed_after_the_event` |
| bridge: concurrent events replace the shadow mid-read | per-conversation run lock around each event | lock in `handle`; event tests run through it |
| bridge: result pairing by position, non-`ERROR` treated as success | require `DONE` and equal call/result counts | `test_results_pair_only_when_unambiguous_and_done` |
| bridge: turn marker written before hooks run | per-script marker written only after successful delivery | `test_failed_task_entry_is_retried_in_the_same_turn` |
| npm: disabled plugin reported healthy | `doctor` reports `disabled`; install notes it | `reports a disabled plugin` |
| npm: host calls unbounded | 120 s timeout, `SIGKILL`, stdin closed; journal covers uncertain finality | code |
| installer: no-op host reported as installed | installed tree must equal the staged copy | installer case 8 |
| npm rollback test blind, update untested | one-shot fault after a real copy; two-release update/downgrade/failed-update test | npm suite |
| installer mutation probe credits an early exit | requires a fake-host install that replaces the sentinel; portable `sed` | installer case 4 |
| inventory separate from dispatch | handlers dispatch from `DISPATCH`; `--bindings` derives from it | binding tests |
| validation overclaimed forged-transcript resistance | claim limited to incomplete or mismatched reads | this file |
| `hooks/AGENTS.md` "never decides" vs fail-closed | bridge decisions listed explicitly | contract text |

## Challenge C1 (extraction lane, `--mode challenge`, reviewer: Codex)

Result: `challenge-C1.json`, 10 P1 and 4 P2, on the candidate after the R1 fixes (packet without the 56 KB R1 receipt, to stay under the 200 KB cap).

Design decision, `narrow`: R1 and C1 both found data-loss and trust defects in the npm adapter's snapshot, prune and journal machinery (same class, two rounds). Antigravity copies a plugin on install, so npm needs no snapshots: it now installs from the package's bundled plugin, records a receipt (version and file hashes), keeps a verified temporary backup only during an update, and its journal records only that an operation was in flight. Snapshot pruning, root deletion and journal-supplied file lists no longer exist.

| Finding | Disposition | Proof |
| --- | --- | --- |
| npm: install/update cleanup deletes user files under `snapshots/` | removed by the narrowing; a root with any foreign entry, including `snapshots/`, is refused | `never adopts an unmanaged root…` |
| npm: failed-update rollback reinstalls over an unlisted directory | restore only when the tree is ours or provably absent (`ENOENT` only) | code; `failed update…` |
| npm: journal can vouch for a hand-installed plugin | recovery compares only with the current package and the receipt | `A journal never makes…` |
| npm: uninstall recovery drops ownership, previews mutate | previews report `recovery-pending` without mutation; nothing else to clean up after the narrowing | `reconciles an operation that died…` |
| installer: refresh destroys edits in the installed copy | marker records every file's hash; refresh only on an exact match | installer case 2 |
| installer and npm race on a fresh destination | one shared lock file; ownership checked under it | installer case 9; npm lock test |
| bridge: `normpath` defeats symlink resolution | no lexical collapse | symlink-parent test |
| bridge: malformed or multi-root `workspacePaths` | used only as a single absolute directory | relative-target test |
| bridge: quoted subcommand evades the guard-down classifier | superseded by delta D1: no classifier, every command is blocked when the merge guard cannot run | guard-down test |
| bridge: parallel results credited to the wrong call | rejected as stated: evidence keys on the call's own target and the shown lines must equal that file's bytes, so a swapped result yields no evidence (a missed load, never a false one) | `test_swapped_parallel_results_give_no_false_evidence` |
| bridge: unbounded run-lock wait | deadline starts before the lock; bounded non-blocking acquisition | lock test |
| bridge: multi-target ask returned before a later deny | check every target; deny wins | deny-over-ask test |
| validation: no host proof of `overwrite`/`continue` | live run 5 above | this file |
| test: GNU-only `stat -c` | Python `os.stat` | privacy test |

## Delta D1 (extraction lane, `--mode review`)

Codex returned `tool_boundary_violation` twice on the full 141 KB delta packet (no verdict either time). The delta was then split into three packets, each with the source-register row the lane requires, and run on Kimi (`CODE_REVIEW_CLIENT_ORDER=kimi`).

| Partition | Result | Findings and dispositions |
| --- | --- | --- |
| bridge (`delta-D1-bridge.json`) | findings | P1: an encoded or piped command (`echo … \| base64 -d \| sh`) passed the guard-down classifier. Third finding against that classifier (R1 `git -C`, C1 quoting, D1 encoding), so it is `replace`d rather than patched: when the merge guard cannot run, every command is blocked. P2: `AGENTS.md` named a symbol that no longer exists; it now names `DISPATCH`. |
| npm adapter (`delta-D1-npm.json`) | passed | none |
| installer, README, plan (`delta-D1-installer.json`) | passed | none |

## Delta D2 (extraction lane, `--mode review`, Kimi)

Packet: the bridge and its suite, `AGENTS.md`, `hooks/AGENTS.md`, `docs/ARCHITECTURE.md` and the register row, covering the D1 fixes (merge guard fail-closed for every command, `DISPATCH` named as the inventory). Result `delta-D2.json`: passed, no findings.

## Local lanes

Environment: `umask 022`, tracked files `chmod go+rX`, a virtualenv with `requirements-test.txt`, `CCL_BROAD_TEST_REASON=repo-required`, the private alias audit configured (`ALIAS_AUDIT_CMD`, `R0_BASE=origin/main`). The abort-leak shards run under `unshare --user --map-current-user --pid --fork --mount-proc` so that orphaned processes are reparented to PID 1, which those probes require.

Full run on staged tree `110553c` (base `3ae87ae`):

| Lane | Result |
| --- | --- |
| `make test-repo-gates` | exit 0 |
| `make test-regressions-fast` | exit 0 |
| `make test-code-review-1` | exit 0 |
| `make test-code-review-2` | exit 0 |
| `make test-code-review-abort-leak-1` | exit 0 |
| `make test-code-review-abort-leak-2` | exit 0 |
| `npm --prefix packages/ccl-skills-npm test` | exit 0 |
| `npm --prefix packages/ccl-skills-npm run test:pack` | exit 0 |

The D1 fixes then changed `hooks/agy-bridge.py`, its suite and contract text. Rerun of every lane those files reach, on staged tree `eb50986`:

| Check | Result |
| --- | --- |
| `git diff --cached --check` | exit 0 |
| `python3 scripts/check-public-sanitization.py .` | exit 0 |
| `make test-repo-gates` (includes `check-ccl-skills.sh`, which printed `r0_status=private-ok` and `ccl_skill_check_clean_ok`, and `hooks/test_agy_bridge.py`) | exit 0 |
| `npm --prefix packages/ccl-skills-npm test` | exit 0 (453 pass, 0 fail) |
| `npm --prefix packages/ccl-skills-npm run test:pack` | exit 0 |

`test-regressions-fast` and the code-review shards read none of the files changed after tree `110553c`. This record was added after the rerun; it changes only this evidence file.

On the local checkpoint commit: `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` printed `regression_heavy_lane_ok: 9 suites` (exit 0); `shared_git_surface_gate.py --base-ref origin/main` printed `shared_git_surface_gate_ok`; `check_review_evidence_present.py --base "$(git merge-base origin/main HEAD)"` printed `review_evidence_present_ok: 5 review, 1 challenge`.

Not run locally: the real-host npm smoke `scripts/host-smoke.sh` (it installs into the real Claude Code, Codex and OpenCode configuration, which this round does not touch).
