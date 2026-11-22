# Validation: Hook Turn-Key Fix, Symlink Isolation, Coverage Gate Speedup, and Suite Wiring

All verification runs use synthetic git repositories and isolated `TMPDIR` scratch directories on Linux (`agy` 1.5.14, Python 3.11, Node.js 20, Bash 5.2 with Bash 3.2 syntax constraints).

## Behavioral Evidence (`RED-baseline`, Constructed Scenarios and Live Host Probes)

| Probe | Base tree (`0ee3a4a`) | Candidate (`ccc1000`) |
| --- | --- | --- |
| Antigravity `PreInvocation` across multi-step turns and new user turns (`invocationNum: 0 -> 1`, delayed/stale/oversized transcripts, omitted `initialNumSteps`) | Recomputed a fresh turn key on step 1 because `initialNumSteps` increments after tool execution; re-ran `task-entry.sh` and `merge-authorization-prompt.sh`, re-arming a consumed one-shot `merge #123` grant (`4 failures` in `hooks/test_agy_bridge.py`; stale-transcript + missing-`initialNumSteps` follow-up also failed RED `failures=1` before `seq` replacement) | Increments monotonic `seq` on `invocationNum == 0` and on mid-turn `turn_id` changes while reusing `{ctx['key']}.active.turn` on `invocationNum > 0`; skips first-of-turn hooks mid-turn, delivers queued `notes`, retries failed hooks on synthetic `invocationNum=None` payloads, and fires once on every new user turn (`41 tests OK`) |
| Primary-checkout leaf, dangling-parent, and chained symlinks (`Write`, `Edit`, `apply_patch` `*** Delete File:`) | `host-input.py` `os.path.realpath` and `guard-edit-isolation.sh` `fp=$(realpath "$fp")` resolved leaf symlinks outside the repository before checking their directory entry (`3 failed` in `test_guard_edit_isolation.sh`; chained symlink into dangling parent under `jq`-only mode also failed RED `31 passed, 1 failed` before shared hop budget) | Both `host-input.py` (`candidate_paths`) and `guard-edit-isolation.sh` (`check_one_path` + `check_symlink_targets` sharing a 16-hop `total_sym_hops` budget across `readlink` hops and dangling parent symlinks) deny primary-checkout symlink edits/deletes while allowing linked-worktree and solo-repo symlinks (`32 passed, 0 failed`; `576/576` `test_hook_field_reads.py` cases pass) |
| `check-agent-contract-coverage.sh` per-file scan, `-dash.py` filenames, literal `--exclude 'gen*'`, and `REQUIRE_BASELINE=1` parity | Spawned `5,536` external `basename`/`dirname` processes on this repository (`11,279ms` shimmed / `~7.8s` raw), failed `basename: invalid option -- 'd'` on `-dash.py`, and glob-expanded unquoted `--exclude 'gen*'` against `gen_keep/` (`8 failed` in `test_check_agent_contract_coverage.sh`) | `0` external `basename`/`dirname` processes, `~193ms` full-repo scan (~58× faster shimmed, ~40× raw), handles `-dash.py` and literal `--exclude 'gen*'`, matches `0ee3a4a` byte-for-byte on standard `--check`/`--enforce`/`--fix` inputs, and fails closed under `REQUIRE_BASELINE=1` if `0ee3a4a` is absent (`14 passed, 0 failed, 0 skipped`; `15 passed` with `PERF_BOUND_MS=2000`) |
| Orphaned test suites (`eval/test_owner_role_audit.py`, `skills/code-review/scripts/test_kimi_packet_mcp.py`) | Absent from `Makefile` and `_DEFAULT_EVAL_UNITTEST_MODULES` (`AssertionError` in `test_select_affected_tests.py`) | Registered in `Makefile` (`test-repo-gates` and `test-code-review-2`) and `_DEFAULT_EVAL_UNITTEST_MODULES`; pinned by `SelectAffectedTestsUnit` (`22 tests OK`) |

## Test-Case Register and Full Local Lane Results (Candidate `ccc1000`)

| Layer / Lane | Command | Result |
| --- | --- | --- |
| Focused unit & hook integration (`T1`–`T5`) | `python3 hooks/test_agy_bridge.py`, `python3 hooks/test_host_input.py`, `bash hooks/test_guard_edit_isolation.sh`, `python3 hooks/test_hook_field_reads.py` | `41 OK`, `41 OK`, `32 passed, 0 failed`, `576 cases, 0 failures` |
| Coverage gate & downstream installer (`T6`, `T7`) | `REQUIRE_BASELINE=1 bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh`, `PERF_BOUND_MS=2000 ...`, `python3 scripts/test_install_gates_runtime.py` | `14 passed, 0 failed, 0 skipped` (`~193ms`, `0` forks), `15 passed` with `PERF_BOUND_MS=2000`, `8 OK` |
| Suite wiring (`T8`) | `python3 scripts/test_select_affected_tests.py`, `python3 -m unittest eval.test_owner_role_audit`, `python3 skills/code-review/scripts/test_kimi_packet_mcp.py`, `python3 scripts/test_lane_isolation.py` | `22 OK`, `8 OK`, `12 OK`, `lane_isolation_ok` (`73` members, `0` unreviewed) |
| Repository gates (`repository-gates` CI lane) | `CCL_BROAD_TEST_REASON=repo-required make test-repo-gates` + `python3 scripts/check-public-sanitization.py .` + `python3 scripts/check-skill-count.py .` | `PASS` (`ccl_skill_check_interim_ok`, `r0_status=public-fallback`, `public_sanitization_ok`, `skill_count_ok: 33`) |
| Fast & heavy skill regressions (`regression-fast` + `regression-heavy`) | `CCL_BROAD_TEST_REASON=repo-required make test-regressions-fast` + `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `PASS` |
| Code-review shards (`code-review-regressions-1/2`) | `CCL_BROAD_TEST_REASON=repo-required make test-code-review-1` + `make test-code-review-2` | `PASS` |
| Code-review abort-leak (`code-review-abort-leak-1/2`) | `CCL_BROAD_TEST_REASON=repo-required unshare --user --map-current-user --pid --fork --mount-proc make test-code-review-abort-leak` | `PASS` |
| npm package build, tests & pack (`npm-packages`) | `npm --prefix packages/ccl-skills-npm test` + `npm --prefix packages/ccl-skills-npm run test:pack` (isolated `git archive` snapshot) | `PASS` (`695` packed files verified) |

## Killing-Mutation Walk

All 14 mutations were applied and executed inside isolated temporary directories outside the worktree (`mktemp -d`, verified disjoint via `pwd -P`), confirming valid syntax, failure on the owning assertion, and green non-owning control assertions:

| ID | Protected predicate | Mutation | Killing test and control |
| --- | --- | --- | --- |
| `M1a` | `turn_id` + `active.turn` prevent mid-turn merge-grant re-arming | Disable `inv > 0` reuse and `turn_id` branch (`steps:` fallback) | `test_multi_step_turn_does_not_rearm_consumed_merge_grant` fails; `test_session_start_injects_the_bootstrap` passes |
| `M1b` | `active.turn` preserves turn key when transcript is absent, late, or `>32 MiB` | `if is_int(inv) and inv > 0` → `if False` | `test_task_entry_runs_once_per_user_turn` and `test_mid_turn_missing_or_late_transcript_preserves_turn_key` fail; bootstrap control passes |
| `M1c` | Monotonic `seq` at `invocationNum == 0` fires hooks on new turns with stale/absent transcript and no `initialNumSteps` | `if is_int(inv) and inv == 0:` → `if False:` | `test_mid_turn_missing_or_late_transcript_preserves_turn_key` (`stale-nosteps` / `notx-nosteps`) fails; bootstrap control passes |
| `M2` | Mid-loop absorbed `USER_EXPLICIT` turn mints a new turn key | `if not (prev_turn and effective_turn and prev_turn != effective_turn)` → `if True` | `test_mid_turn_missing_or_late_transcript_preserves_turn_key` fails; `test_task_entry_runs_once_per_user_turn` passes |
| `M3` | Queued `PreToolUse`/`PostToolUse` notes deliver when first-of-turn hooks skip | Gate `pop_notes` behind `if texts:` | `test_multi_step_turn_does_not_rearm_consumed_merge_grant` fails |
| `M4` | `host-input.py` preserves leaf symlink directory entry alongside `realpath` | `candidate_paths` returns `[resolved]` only | `test_symlink_inside_protected_primary_checkout_is_denied` and `test_patch_targets_receive_isolation_policy` fail; regular-file control passes |
| `M5a` | `guard-edit-isolation.sh` walks dangling parent directory symlinks in `jq`-only mode | Disable `[ -L "$dir" ]` walk in `check_one_path` | `p6j` and `p6l` fail; remaining probes pass |
| `M5b` | `guard-edit-isolation.sh` resolves symlink targets in `jq`-only mode | `if [ -L "$fp" ]` → `if false` in `check_target` | `p6k`, `p6l`, and `p6m` fail; remaining probes pass |
| `M5c` | `readlink` hop fallback continues walking dangling parent symlinks under shared hop budget | Pass disabled dangling-walk flag on `readlink` hops (`check_one_path "$cur" 0`) | `p6l` fails (`31 passed, 1 failed`); all other 31 probes pass |
| `M6` | Zero external `basename`/`dirname` forks in coverage scan | Add `$(basename -- "$file")` inside scan loop | `case 1b`, `case 4a`, and `case 6b` fail; functional cases stay green |
| `M7` | `--exclude` segments split with `set -f` (no pathname globbing) | Remove `set -f` before `for _e in $exclude_segments` | `case 3` fails; remaining checks pass |
| `M8` | `test_kimi_packet_mcp.py` stays wired in `Makefile` | Remove `test_kimi_packet_mcp.py` from `Makefile` | `SelectAffectedTestsUnit` registration check fails |
| `M9` | `eval.test_owner_role_audit` stays wired in `Makefile` | Remove `eval.test_owner_role_audit` from `Makefile` | `SelectAffectedTestsUnit` registration check fails |
| `M10` | `REQUIRE_BASELINE=1` fails closed when `0ee3a4a` is absent in a shallow checkout | Shallow clone missing `0ee3a4a` (`--is-shallow-repository == true`) | Control without `REQUIRE_BASELINE=1` exits `0` (`1 skipped`); `REQUIRE_BASELINE=1` exits `1` (`13 passed, 1 failed, 0 skipped`) |

## Live Host Smoke (`agy` 1.5.14)

Candidate plugin staged at `<scratch-ws>/.agents/plugins/ccl-skills` inside a synthetic `.worktree-only` git repository on `main` containing `tracked_link.txt -> <scratch>/outside.txt`:

1. `agy plugin validate <scratch-ws>/.agents/plugins/ccl-skills`: `✔ Validation passed with 20 warnings`, 0 errors (`skills 33 · hooks 1`).
2. Multi-step Turn 1 (`agy -p` calling `run_command` then `write_file` on `tracked_link.txt`): `write_file` was denied by the pre-tool hook (`隔离闸：[…] 标记为共享仓库（.worktree-only），禁止直接改主检出… 当前分支:main`), `outside.txt` remained untouched, and `task-entry.sh` fired **1** time across the multi-step turn (`turn1_task_entry_fires=1`).
3. Follow-up Turn 2 (`agy -c -p`): `task-entry.sh` fired **1** additional time (`total_task_entry_fires_after_turn2=2`); bridge state directory mode `0700`, `.active.turn` and `.turn` files mode `0600`, zero leftover `.jsonl` shadow transcripts.

## Review pass
- Reviewed commit: `82be530c06268b59c60c43fc5967b4dc5d81ece8` (`specs/hook-turn-key-and-gate-speed/evidence/review-R1.json`)
- Findings: 2 total (0 P0 / 0 P1 / 2 P2)
- R0 evidence: `r0_status=public-fallback` (`ccl_skill_check_interim_ok`; `public_sanitization_ok`; `interim: R0 pending maintainer audit`)
- Dispositions: none at P0/P1; both P2s fixed (`hooks/agy-bridge.py` stale-transcript new-turn handling and `test_check_agent_contract_coverage.sh` explicit skip/fail-closed baseline reporting)

## Challenge pass
- Reviewed commit: `c4338996ad66430dd207e476e6b368395817f1b1` (`specs/hook-turn-key-and-gate-speed/evidence/challenge-C1.json`)
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: `r0_status=public-fallback` (`ccl_skill_check_interim_ok`; `public_sanitization_ok`; `interim: R0 pending maintainer audit`)
- Gate-fireability applicability: yes (`guard-edit-isolation.sh`, `agy-bridge.py`, `check-agent-contract-coverage.sh`); Item 9 exercised: live `agy` 1.5.14 `PreInvocation` + `PreToolUse` smoke and `jq`-only/no-`realpath` shell probes (`p6j`–`p6m`)
- Dispositions: none at P0/P1; all 3 P2s fixed in `ccc10004d7d2076c840d910a9be0fb1cb7222e27` (`resolve_turn_key` `replace` simplification to monotonic `seq` at `invocationNum == 0`, shared 16-hop `total_sym_hops` budget in `guard-edit-isolation.sh` + probes `p6l`/`p6m`, and `REQUIRE_BASELINE=1` in `Makefile` + opt-in `PERF_BOUND_MS`)

## Delta pass 1
- Reviewed commit: `ccc10004d7d2076c840d910a9be0fb1cb7222e27`; packet: `git diff c4338996ad66430dd207e476e6b368395817f1b1..ccc10004d7d2076c840d910a9be0fb1cb7222e27` (`specs/hook-turn-key-and-gate-speed/evidence/delta-D1.json`)
- Findings / Dispositions: 1 total (0 P0 / 0 P1 / 1 P2). P0/P1 dispositions: none. P2 disposition (`hooks/guard-edit-isolation.sh:157`, `jq`-only + failing-`realpath` fallback stops at 16 shared symlink hops vs kernel 40): `deferred` — `host-input.py` (`os.path.realpath`) already resolves full OS `MAXSYMLINKS` when `python3` is available; in the `jq`-only + failing-`realpath` fallback, calling `deny` on hop exhaustion would falsely block symlink loops outside protected repositories (violating precision probe `p6h`), while multiplying shell `readlink`/`git` forks risks crossing the 10s `PreToolUse` timeout (`hooks/AGENTS.md:27-28`, where a timed-out hook fails open). Clarified the 16-hop bound scope in this validation record.

## Post-review delta
- `specs/hook-turn-key-and-gate-speed/evidence/review-R1.json`: review controller receipt for `82be530c06268b59c60c43fc5967b4dc5d81ece8`
- `specs/hook-turn-key-and-gate-speed/evidence/challenge-C1.json`: challenge controller receipt for `c4338996ad66430dd207e476e6b368395817f1b1`
- `specs/hook-turn-key-and-gate-speed/evidence/delta-D1.json`: delta review controller receipt for `ccc10004d7d2076c840d910a9be0fb1cb7222e27`
- `specs/hook-turn-key-and-gate-speed/evidence/validation.md`: closeout validation and pass log (non-executable `evidence/` records only)

## Repo-Contract Sync, Deliverable-Doc Evidence, and Gate Status

- **Repo-contract sync**: Updated `skills/product-rd-workflow/scripts/AGENTS.md` Validation list to include `bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh`. Verified via `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce` (`agent contract coverage ok`, exit `0`).
- **Deliverable-doc pass (`tighten-doc`)**: Ran `tighten-doc` workflow steps 1–4 and standalone-paste closeout sweep on `specs/hook-turn-key-and-gate-speed/plan.md` and `specs/hook-turn-key-and-gate-speed/evidence/validation.md` (mode: technical spec/validation; preserved all decided points, dirty-scan = 0, `doc-lint-repo.py .` = `0 ERROR`).
- **Security review gate**: `pending-dedicated-review` (`security-first-pass-only` read-only triage recorded above; not a dedicated security audit).
- **R0 leakage audit**: `ALIAS_AUDIT_CMD` is unset in this environment; `check-ccl-skills.sh .` exits `0` with `r0_status=public-fallback` and `ccl_skill_check_interim_ok`, and `check-public-sanitization.py .` outputs `public_sanitization_ok`. Landing status is `interim` (`R0 pending maintainer audit`).
