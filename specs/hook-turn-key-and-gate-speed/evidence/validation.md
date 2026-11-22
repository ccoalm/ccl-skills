# Validation: Hook Turn-Key Fix, Symlink Isolation, Coverage Gate Speedup, and Suite Wiring

All verification runs use synthetic git repositories and isolated `TMPDIR` scratch directories on Linux (`agy` 1.5.14, Python 3.11, Node.js, Bash 5.2 with Bash 3.2 syntax constraints).

## Behavioral Evidence (`RED-baseline`, Constructed Scenarios and Live Host Probes)

| Probe | Base tree (`0ee3a4a`) | Candidate |
| --- | --- | --- |
| Antigravity `PreInvocation` on multi-step user turn (`invocationNum: 0 -> 1`, `initialNumSteps: 1 -> 5`, `turn-0`) | Recomputes a fresh turn key on step 1 because `initialNumSteps` increments after tool execution; re-runs `task-entry.sh` and `merge-authorization-prompt.sh`, re-arming a consumed one-shot `merge #123` grant (`4 failures` in `hooks/test_agy_bridge.py`) | Reuses `{ctx['key']}.active.turn` / `turn:turn-0` within the user turn (`invocationNum > 0`), skips first-of-turn hooks while still delivering queued `notes`, and mints a fresh key on Turn 2 (`invocationNum: 0`, `turn-7`) even with identical prompt text (`41 tests OK`) |
| Primary-checkout leaf symlink pointing outside repo (`Write`, `Edit`, `apply_patch` `*** Delete File:`) | `host-input.py` `os.path.realpath` and `guard-edit-isolation.sh` `fp=$(realpath "$fp")` resolved the symlink outside the repository before checking its parent directory, returning `allow` (`3 failed` in `test_guard_edit_isolation.sh`; `claude_guard` returned `allow`) | Both `host-input.py` (`candidate_paths`) and `guard-edit-isolation.sh` (`check_one_path` + `check_symlink_targets`, including dangling parent symlinks and `jq`-only fallback) check the symlink's own directory entry and its resolved target; primary-checkout symlink edits/deletes deny while linked-worktree and solo-repo symlinks allow (`30 passed, 0 failed`; `576/576` `test_hook_field_reads.py` cases pass) |
| `check-agent-contract-coverage.sh` per-file scan, `-dash.py` filenames, and `--exclude 'gen*'` | Spawned `5,536` external `basename`/`dirname` processes on this repository (`11,279ms` shimmed / `~7.8s` raw), failed `basename: invalid option -- 'd'` on `-dash.py`, and glob-expanded unquoted `--exclude 'gen*'` against `gen_keep/` (`8 failed` in `test_check_agent_contract_coverage.sh`) | `0` external `basename`/`dirname` processes, `193ms` full-repo scan (~58× faster shimmed, ~40× raw), handles `-dash.py`, literal `--exclude 'gen*'`, and matches `0ee3a4a` byte-for-byte on standard `--check`/`--enforce`/`--fix` inputs (`15 passed, 0 failed`) |
| Orphaned test suites (`eval/test_owner_role_audit.py`, `skills/code-review/scripts/test_kimi_packet_mcp.py`) | Absent from `Makefile` and `_DEFAULT_EVAL_UNITTEST_MODULES` (`AssertionError` in `test_select_affected_tests.py`) | Registered in `Makefile` (`test-repo-gates` and `test-code-review-2`) and `_DEFAULT_EVAL_UNITTEST_MODULES`; pinned by `SelectAffectedTestsUnit` (`22 tests OK`) |

## Test-Case Register Results

| ID | Command | Result |
| --- | --- | --- |
| `T1`, `T2`, `T5` | `python3 hooks/test_agy_bridge.py` | 41 tests OK (observed RED `failures=4` before implementation) |
| `T3`, `T4` | `bash hooks/test_guard_edit_isolation.sh` | 30 passed, 0 failed (observed RED `3 failed` before implementation) |
| `T3` (`apply_patch`) | `python3 hooks/test_host_input.py` | 41 tests OK |
| Baseline hook parity | `python3 hooks/test_hook_field_reads.py` | 576 cases, 0 failures |
| `T6`, `T7` | `bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` | 15 passed, 0 failed, 0 `basename`/`dirname` forks, full-repo scan `193ms` (observed RED `8 failed`, `11,279ms` before implementation) |
| Downstream gate installer | `python3 scripts/test_install_gates_runtime.py` | 8 tests OK |
| `T8` | `python3 scripts/test_select_affected_tests.py`, `python3 -m unittest eval.test_owner_role_audit`, `python3 skills/code-review/scripts/test_kimi_packet_mcp.py` | 22 tests OK, 8 tests OK, 12 tests OK (observed RED `AssertionError` before `Makefile` wiring) |

## Killing-Mutation Walk

All 11 mutations were applied and run inside an isolated temporary checkout outside the worktree (`mktemp -d`, verified disjoint from `$WT` via canonical `pwd -P`), confirming syntax validity, exact owning-assertion failure, and green non-owning control assertions:

| ID | Protected predicate | Mutation | Killing test and control |
| --- | --- | --- | --- |
| `M1a` | `turn_id` + `active.turn` prevent mid-turn merge-grant re-arming | `resolve_turn_key` `inv > 0` reuse and `turn_id` branch disabled (`steps:` fallback) | `test_multi_step_turn_does_not_rearm_consumed_merge_grant` fails; `test_session_start_injects_the_bootstrap` passes |
| `M1b` | `active.turn` preserves turn key when transcript is absent, late, or `>32 MiB` | `if is_int(inv) and inv > 0` → `if False` | `test_task_entry_runs_once_per_user_turn` (`notx`) and `test_mid_turn_missing_or_late_transcript_preserves_turn_key` fail; bootstrap control passes |
| `M2` | Mid-loop absorbed `USER_EXPLICIT` turn mints a new turn key | `if not (prev_turn and turn_id and prev_turn != turn_id)` → `if True` | `test_mid_turn_missing_or_late_transcript_preserves_turn_key` fails; `test_task_entry_runs_once_per_user_turn` passes |
| `M3` | Queued `PreToolUse`/`PostToolUse` notes still deliver when first-of-turn hooks skip | `pop_notes` gated behind `if texts:` | `test_multi_step_turn_does_not_rearm_consumed_merge_grant` fails |
| `M4` | `host-input.py` preserves leaf symlink directory entry alongside `realpath` | `candidate_paths` returns `[resolved]` only | `test_symlink_inside_protected_primary_checkout_is_denied` and `test_patch_targets_receive_isolation_policy` fail; primary-checkout regular-file control passes |
| `M5a` | `guard-edit-isolation.sh` walks dangling parent directory symlinks in `jq`-only mode | `allow_dangling_walk` branch → `if false` | `p6j` fails (`29 passed, 1 failed`) |
| `M5b` | `guard-edit-isolation.sh` resolves symlink targets in `jq`-only mode | `if [ -L "$fp" ]` → `if false` | `p6k` fails (`29 passed, 1 failed`) |
| `M6` | Zero external `basename`/`dirname` forks in coverage scan | Add one `$(basename -- "$file")` inside scan loop | `case 1b`, `case 4a`, and `case 6b` fail; functional cases stay green |
| `M7` | `--exclude` segments split with `set -f` (no pathname globbing) | Remove `set -f` before `for _e in $exclude_segments` | `case 3` fails (`14 passed, 1 failed`) |
| `M8` | `test_kimi_packet_mcp.py` stays wired in `Makefile` | Remove `test_kimi_packet_mcp.py` line from `Makefile` | `SelectAffectedTestsUnit` registration check fails |
| `M9` | `eval.test_owner_role_audit` stays wired in `Makefile` | Remove `eval.test_owner_role_audit` from `Makefile` | `SelectAffectedTestsUnit` registration check fails |

An earlier mutation run revealed `p6i` alone did not kill `M5a` when `python3` was on `PATH` because `host-input.py` already resolved the parent symlink; probes `p6j` and `p6k` (`PATH` without `python3`) were added so `M5a` and `M5b` directly kill `guard-edit-isolation.sh`'s shell fallback too.

## Live Host Smoke (`agy` 1.5.14)

Candidate plugin staged at `<scratch-ws>/.agents/plugins/ccl-skills` inside a synthetic `.worktree-only` git repository on `main` containing `tracked_link.txt -> <scratch>/outside.txt`:

1. `agy plugin validate <scratch-ws>/.agents/plugins/ccl-skills`: `✔ Validation passed with 20 warnings`, 0 errors (`skills 33 · hooks 1`).
2. Multi-step Turn 1 (`agy -p` calling `run_command` then `write_file` on `tracked_link.txt`): `write_file` was denied by the pre-tool hook (`隔离闸：[…] 标记为共享仓库（.worktree-only），禁止直接改主检出… 当前分支:main`), `outside.txt` remained untouched, and `task-entry.sh` fired **1** time across the multi-step turn (`turn1_task_entry_fires=1`).
3. Follow-up Turn 2 (`agy -c -p`): `task-entry.sh` fired **1** additional time (`total_task_entry_fires_after_turn2=2`); bridge state directory mode `0700`, `.active.turn` and `.turn` files mode `0600`, zero leftover `.jsonl` shadow transcripts.

## Repo-Contract Sync and Deliverable-Doc Evidence

- **Repo-contract sync**: Updated `skills/product-rd-workflow/scripts/AGENTS.md` Validation list to include `bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh`. Verified via `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce` (`agent contract coverage ok`, exit `0`).
- **Deliverable-doc pass (`tighten-doc`)**: Ran `tighten-doc` workflow steps 1–4 and standalone-paste readback on `specs/hook-turn-key-and-gate-speed/plan.md` and `specs/hook-turn-key-and-gate-speed/evidence/validation.md` (mode: technical spec/validation; result: preserved all decided points, removed meta phrasing, verified dirty-scan = 0 and `doc-lint-repo.py .` = `doc_lint_repo_ok`).

## Security First Pass (`security-first-pass-only`) and R0 Audit Status

- **Security review gate**: `pending-dedicated-review` (`security-first-pass-only` read-only triage, not a dedicated security audit). Verified: `agy-bridge.py` reads `.active.turn` only from the user-owned `0700` state directory (`0600` files) keyed by SHA-256 of `conversationId`, validates JSON object types (`isinstance(..., bool)` excluded from `is_int`), and never re-arms consumed one-shot merge grants on `invocationNum > 0`; `host-input.py` and `guard-edit-isolation.sh` evaluate both symlink directory-entry and resolved-target paths with a 16-hop loop bound and zero `eval`; `check-agent-contract-coverage.sh` disables globbing (`set -f`) when splitting `--exclude` / `--source-ext` and uses quoted `[[ ... ]]` comparisons.
- **R0 leakage audit**: `ALIAS_AUDIT_CMD` is not configured in this environment; `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` exits `0` with `r0_status=public-fallback` and `ccl_skill_check_interim_ok`, and `python3 scripts/check-public-sanitization.py .` outputs `public_sanitization_ok`. Landing status is therefore `interim` (`R0 pending maintainer audit`).
