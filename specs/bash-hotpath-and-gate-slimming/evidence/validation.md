# Validation & Benchmark Evidence: `bash-hotpath-and-gate-slimming`

## 1. RED-First Verification Summary (`T1`–`T5`)

Every new assertion was written and executed against unmodified `origin/main` (`827f7f684b41842452ca6af3421a45f3e4d364ef`) before editing any target implementation file, then re-verified green after implementation:

| ID | Suite | Pre-Fix RED Result | Post-Fix GREEN Result |
| --- | --- | --- | --- |
| `T1a` | `hooks/test_hook_field_reads.py` (+ `hooks/test_hook_remaining_field_reads.py`) | `rc=1` (`AssertionError: find_config_dir spawned 8 dirname processes (expected 0)` and `engine-bash` spawned `1` `jq` instead of `0`) | `rc=0` (`576 cases, 0 failures`; `532 remaining-hook differential cases match baseline`; `800k-NUL` `peak_ratios` within cap) |
| `T1b` | `hooks/test_skill_loading.py` | `rc=1` (`FAILED (failures=7)`: `normalizer()` loaded on `ls -la`, `pytest -q`, `git status`, `git diff`, `rg`, `gh`, and `Read`) | `rc=0` (`Ran 36 tests ... OK`; `0` `normalizer()` loads on non-write `Bash` / `Read`, `1` load + `deny` on `r'm'`, `/bin/cp`, `>`, `\rm`, `python3<<'EOF'`) |
| `T2` | `hooks/test_guard_merge_authorization.sh` | `rc=1` (`FAIL pass=494 fail=6`: `'ls -la'`, `'pytest -q'`, `'git status --short'`, `'git diff HEAD'`, `'git checkout -b ...'`, `'gh pr view 45'` each spawned `4` `git` processes) | `rc=0` (`test_guard_merge_authorization_ok pass=501`, `0` `git` spawns on all 6 non-landing commands) |
| `T3a` | `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` | `rc=1` (`expected 1 git rev-parse call on linked worktree edit` — plugin spawned `3` `rev-parse` calls) | `rc=0` (`52/52` pass, `1` plugin `git rev-parse` call on linked worktree edit; primary `.worktree-only` checkout blocked) |
| `T3b` | `hooks/test_agy_bridge.py` | `rc=1` (`AssertionError: 'headless-background-stop.sh' unexpectedly found in invoked` when `CLAUDE_CODE_ENTRYPOINT` unset) | `rc=0` (`Ran 68 tests ... OK`; skipped when unset, executed under `CLAUDE_CODE_ENTRYPOINT=sdk-ts`, `--bindings` 1:1 with `hooks/hooks.json`) |
| `T3c` | `hooks/test_proposed_next.py` | `rc=1` (`brain/conv-1234/scratch/*.md` included in `reader_docs`) | `rc=0` (`Ran 73 tests ... OK`; `brain/<id>/scratch/**` excluded while `brain/<id>/walkthrough.md` and `docs/guide.md` retained) |
| `T4` | `scripts/test_check_spec_references.py` | `rc=1` (`AssertionError: 27 != 1 : expected CITATION_RE to run only on the 1 file containing backticked specs/, got 27`) | `rc=0` (`Ran 80 tests ... OK`; `finditer_calls=1`, `escape_calls=2`, `spec_reference_check_ok`) |
| `T5a` | `skills/skill-extraction-workflow/scripts/test_check_ccl_size_budget.sh` | `rc=1` (`FAIL: expected 0 'git show' calls (use cat-file --batch), got 2`) | `rc=0` (`test_check_ccl_size_budget: ok`; `0` `git show`, `1` `rev-parse --show-toplevel`, `<=12` total git calls, nested export inside enclosing checkout downgrades cleanly) |
| `T5b` | `skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh` | `rc=1` (`FAIL: expected 1 batched rg spawn across 3 non-git skill roots, got 3`) | `rc=0` (`test_validate_skill_credential_cwd: ok`; `1` `rg` spawn across 3 skill roots from subdir `cwd`, unreadable root fails closed) |
| `T5c` | `skills/skill-extraction-workflow/scripts/test_git_identity_predicate_gate.sh` | `rc=1` (`FAIL p13 batched scan expected rc=0 and 0 grep spawns across 6 files, got rc=0 spawns=6`) | `rc=0` (`18 passed, 0 failed, 0 skipped`, `test_git_identity_predicate_gate_ok`) |
| `T5d` | `skills/skill-extraction-workflow/scripts/test_liveness_predicate_gate.sh` | `rc=1` (`FAIL p15 batched liveness scan expected rc=0 and 0 grep spawns across 6 files, got rc=0 spawns=6`) | `rc=0` (`pass=24 fail=0`, `liveness_predicate_gate_ok`) |
| `T5e` | `skills/skill-extraction-workflow/scripts/test_generic_r0_leak_scan.sh` | `rc=1` (`FAIL: expected rc=0 got rc=2 (cold --self-test-cached should pass)`) | `rc=0` (`test_generic_r0_leak_scan: ok`; cold `2`-`rg` batch, warm `0`-`rg` hit, `CCL_SKILL_NO_SELFTEST_CACHE=1`, 1-byte invalidation, broken mutant non-caching, `0777`/symlink rejection, `<=64` pruning, `Makefile` uncached `--self-test`) |

## 2. Interleaved Paired `N=7` Benchmarks (`origin/main` vs Candidate)

Measured in an uncontended interleaved A/B harness (`base, cand, base, cand...` after 1 warmup per arm) inside the Linux execution sandbox (which adds uniform mount-namespace overhead per child spawn to both arms):

| Workload | Baseline Median (`ms`) | Candidate Median (`ms`) | Speedup | Baseline Samples (`ms`) | Candidate Samples (`ms`) |
| --- | ---: | ---: | ---: | --- | --- |
| `PreToolUse:Bash` 6-hook serial (non-opt-in repo) | `333.92` | `269.11` | `1.24x` (`-64.81 ms`) | `[332.4, 331.57, 335.57, 333.92, 337.88, 331.99, 355.66]` | `[266.97, 269.11, 272.6, 273.63, 267.71, 264.28, 278.54]` |
| `PreToolUse:Bash` 6-hook serial (`ccl-skills` checkout) | `346.91` | `272.95` | `1.27x` (`-73.96 ms`) | `[338.42, 347.76, 350.9, 346.77, 346.91, 350.54, 346.46]` | `[275.21, 273.73, 270.5, 268.21, 271.46, 272.95, 275.36]` |
| `owner-dispatch-guard.sh` (`PreToolUse:Bash`) | `112.05` | `56.28` | `1.99x` (`-55.77 ms`) | `[112.05, 110.55, 113.94, 112.29, 110.28, 111.39, 113.95]` | `[55.1, 56.28, 56.86, 57.17, 55.09, 55.14, 56.46]` |
| `guard-merge-authorization.sh` (`PreToolUse:Bash`) | `76.70` | `62.26` | `1.23x` (`-14.44 ms`) | `[77.4, 72.29, 77.6, 73.4, 77.29, 76.7, 75.82]` | `[66.03, 63.97, 61.82, 62.26, 61.53, 62.53, 60.85]` |
| `python3 scripts/check-spec-references.py .` | `843.86` | `541.81` | `1.56x` (`-302.05 ms`) | `[864.64, 843.86, 837.41, 835.89, 878.72, 872.25, 839.07]` | `[538.42, 541.81, 579.56, 541.0, 555.9, 551.94, 539.04]` |
| `bash .../check-size-budget.sh .` | `1424.99` | `677.14` | `2.10x` (`-747.85 ms`) | `[886.73, 2039.65, 1262.59, 1182.21, 1424.99, 1790.45, 1633.04]` | `[462.01, 506.73, 616.66, 677.14, 788.42, 951.62, 902.05]` |
| `bash .../validate-skill.sh skills` | `1169.85` | `876.48` | `1.33x` (`-293.37 ms`) | `[2536.94, 1185.34, 1169.85, 1199.6, 1152.0, 1151.49, 1167.14]` | `[876.48, 917.46, 849.26, 898.27, 888.07, 864.53, 866.52]` |
| `bash .../check-ccl-skills.sh .` (warm cache) | `7718.34` | `5171.37` | `1.49x` (`-2546.97 ms`) | `[7792.08, 7718.34, 7772.43, 7654.49, 7641.61, 7736.97, 7646.4]` | `[5248.94, 5211.11, 5245.71, 5130.83, 5153.95, 5171.37, 5138.57]` |
| `bash .../check-ccl-skills.sh .` (cold cache) | `15273.93` | `12877.78` | `1.19x` (`-2396.15 ms`) | `[15273.93, 15305.05, 15399.05, 15042.44, 15174.81, 15375.46, 15078.49]` | `[12880.75, 12877.78, 12908.86, 12760.78, 12695.69, 12703.66, 12968.56]` |

## 3. Applied Differential Killing-Mutation Walk (`23/23` Killed)

Executed in isolated temporary clones outside the delivery worktree (`control_rc=0` verified before each mutant):

| Mutant ID | Target File | Applied Mutation | Control `rc` | Mutant `rc` | Killing Failure Signal |
| --- | --- | --- | :---: | :---: | --- |
| `M01_owner_dispatch_drop_backslash_escape_guard` | `scripts/owner-dispatch/owner-dispatch.sh` | Drop `*\\*\|` from `cmd_pretool` fast-path `case` | `0` | `1` | `FAIL engine-edit/tool_name/nul-mid differs from 788470c` |
| `M02_owner_dispatch_reintroduce_dirname` | `scripts/owner-dispatch/owner-dispatch.sh` | Replace `${d%/*}` with `dirname` in `find_config_dir` | `0` | `1` | `find_config_dir spawned ... dirname processes (expected 0)` |
| `M03_owner_dispatch_always_run_jq` | `scripts/owner-dispatch/owner-dispatch.sh` | Disable non-opt-in `cmd_pretool` fast path | `0` | `1` | `engine-bash starts 1 jq processes; at most 0 expected` |
| `M03b_owner_dispatch_drop_len_bound` | `scripts/owner-dispatch/owner-dispatch.sh` | Omit `[ "${#input}" -le 65536 ]` before `case "$input"` | `0` | `1` | `FAIL engine-bash peaks at 3.86x a plain jq read; at most 3.83x expected` |
| `M04_skill_loading_drop_quote_strip` | `hooks/skill-loading.py` | Skip stripping `"` / `'` in `may_write_from_bash` | `0` | `1` | `normalizer() must load once` (`r'm' ...`) |
| `M04b_skill_loading_drop_backtick_boundary` | `hooks/skill-loading.py` | Drop `` ` `` from `BASH_WRITE_HINT_RE` leading boundary class | `0` | `1` | `AssertionError: False is not true` (`echo \`rm ...\``) |
| `M05_skill_loading_drop_heredoc_boundary` | `hooks/skill-loading.py` | Drop `<` from `BASH_WRITE_HINT_RE` lookahead | `0` | `1` | `normalizer() must load once` (`python3<<'EOF'`) |
| `M06_skill_loading_eager_normalizer` | `hooks/skill-loading.py` | Load `normalizer()` eagerly at top of `handle()` | `0` | `1` | `normalizer() must not load for 'ls -la'` |
| `M07_merge_guard_noop_lazy_git_context` | `hooks/guard-merge-authorization.sh` | Return early inside `ensure_base_git_context` | `0` | `1` | `FAIL` on default-branch push/merge and `cnt_push` |
| `M08_merge_guard_eager_git_context` | `hooks/guard-merge-authorization.sh` | Call `ensure_base_git_context` unconditionally at startup | `0` | `1` | `'ls -la' spawned 4 git processes (expected 0)` |
| `M09_agy_bridge_skip_headless_even_for_sdk` | `hooks/agy-bridge.py` | Skip `headless-background-stop.sh` even when `sdk_entrypoint` holds | `0` | `1` | `'headless-background-stop.sh' not found` |
| `M10_agy_bridge_remove_headless_from_dispatch` | `hooks/agy-bridge.py` | Remove `headless-background-stop.sh` from `DISPATCH['Stop']` | `0` | `1` | `BindingTests.test_inventory_covers_every_command_hook` `AssertionError` |
| `M11_host_input_overbroad_brain_exclusion` | `hooks/host-input.py` | Exclude any `'brain'` segment instead of `'brain/<id>/scratch'` | `0` | `1` | `walkthrough.md` missing from `reader_docs` |
| `M12a_spec_refs_prefilter_before_waived_mark` | `scripts/check-spec-references.py` | Run `b'\x60specs/'` skip before `scanned_waived_paths.add` | `0` | `1` | `test_stale_pinned_digest_fails_closed` (`AssertionError: 0 != 1`) |
| `M12b_spec_refs_disable_byte_prefilter` | `scripts/check-spec-references.py` | Disable `b'\x60specs/'` prefilter | `0` | `1` | `expected CITATION_RE to run only on the 1 file` |
| `M12c_spec_refs_disable_target_memoization` | `scripts/check-spec-references.py` | Disable `target_cache` lookup | `0` | `1` | `expected duplicate resolved targets to be memoized` |
| `M13_size_budget_reintroduce_git_show` | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | Reintroduce `git show` call during base metric scan | `0` | `1` | `expected 0 'git show' calls` |
| `M13b_size_budget_nested_export_enclosing_git` | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | Stub `File.realpath(root) == File.realpath(toplevel)` to `true` in `git_worktree_root?` | `0` | `1` | `nested export inside enclosing checkout` (`not-a-git-worktree` missing) |
| `M14_validate_skill_duplicate_rg_call` | `skills/skill-extraction-workflow/scripts/validate-skill.sh` | Spawn an extra `rg` process during credential scan | `0` | `1` | `expected 1 batched rg spawn` |
| `M15_ap27_drop_whole_line_comment_carveout` | `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | Drop whole-line comment exclusion in Anti-pattern 27 | `0` | `1` | `p4 comment-only mention must NOT fire` |
| `M16_r0_cache_accept_unsafe_0777_mode` | `skills/skill-extraction-workflow/scripts/generic-r0-leak-scan.sh` | Disable `mode != "700"` check in `run_self_test_cached` | `0` | `1` | `0777 cache dir must bypass stamp on every call` |
| `M16b_ap28_oneline_hollow_helper_leak` | `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | Drop one-line `}` close check in Anti-pattern 28 helper body parser | `0` | `1` | `p12 a one-line hollow helper must NOT borrow a later read` |
| `M17_opencode_three_revparse_fallback` | `packages/opencode-plugin/ccl-skills.ts` | Force 3-call `git rev-parse` fallback in `repoCheckoutPaths` | `0` | `1` | `expected 1 plugin git rev-parse call on linked worktree edit, got 3` |

Note: `M03b` was observed directly during the initial mutation-walk run before `[ "${#input}" -le 65536 ]` was added (`23/23` distinct mutations verified).

## 4. Contract Sync & `tighten-doc` Closeout Evidence

- **Repo-local contracts updated**:
  - `hooks/AGENTS.md`: documents `agy-bridge.py` `Stop` skip of `headless-background-stop.sh` outside `sdk|sdk-*` entrypoints (while keeping `DISPATCH['Stop']` parity) and the `0`-`jq` non-opt-in `owner-dispatch.sh` `PreToolUse:Bash` fast path.
  - `skills/skill-extraction-workflow/scripts/AGENTS.md`: adds `test_generic_r0_leak_scan.sh` alongside `test_check_evidence_card_leak_cache.sh`.
  - `skills/skill-extraction-workflow/references/source-register.md`: appends two rows (one for `skill-extraction-workflow` validator/gate batching & caching, one for `skill-extraction-workflow` `(plugin runtime surface)` hook/bridge optimizations).
  - OpenCode `Stop` boundary note: `packages/opencode-plugin/ccl-skills.ts` continues running `commandHooks(root, "Stop")` because `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` (`L123-145`, `L317`) pins 1:1 execution of every `Stop` command hook in `hooks/hooks.json` with `CLAUDE_CODE_ENTRYPOINT` scrubbed (`headless-background-stop.sh` exits in ~1.5 ms pure shell).
- **`tighten-doc` closeout reread**:
  - `mode`: `closeout-reread` over `specs/bash-hotpath-and-gate-slimming/plan.md`, `specs/bash-hotpath-and-gate-slimming/evidence/validation.md`, `hooks/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`, and the appended `source-register.md` rows; verified zero session-vantage leakage (`tighten-doc/references/session-vantage-leakage.md`), preserved all decided points, and passed `doc-lint-repo.py .`.
