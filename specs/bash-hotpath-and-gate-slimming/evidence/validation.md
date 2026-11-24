# Validation & Benchmark Evidence: `bash-hotpath-and-gate-slimming`

## 1. RED-First Verification Summary (`T1`–`T5`)

Every new assertion was written and executed against unmodified `origin/main` (`827f7f684b41842452ca6af3421a45f3e4d364ef`) before editing any target implementation file, then re-verified green after implementation:

| ID | Suite | Pre-Fix RED Result | Post-Fix GREEN Result |
| --- | --- | --- | --- |
| `T1a` | `hooks/test_hook_field_reads.py` (+ `hooks/test_hook_remaining_field_reads.py`) | `rc=1` (`AssertionError: find_config_dir spawned 8 dirname processes (expected 0)` and `engine-bash` spawned `1` `jq` instead of `0`) | `rc=0` (`576 cases, 0 failures`; `532 remaining-hook differential cases match baseline`; `800k-NUL` `peak_ratios` within cap) |
| `T1b` | `hooks/test_skill_loading.py` | `rc=1` (`FAILED (failures=7)`: `normalizer()` loaded on `ls -la`, `pytest -q`, `git status`, `git diff`, `rg`, `gh`, and `Read`) | `rc=0` (`Ran 36 tests ... OK`; `0` `normalizer()` loads on non-write `Bash` / `Read`, `1` load + `deny` on `r'm'`, `/bin/cp`, `>`, `\rm`, `python3<<'EOF'`, backtick/`{`/`!` boundaries, and all 21 `bash_write_targets` families) |
| `T2` | `hooks/test_guard_merge_authorization.sh` | `rc=1` (`FAIL pass=494 fail=6`: `'ls -la'`, `'pytest -q'`, `'git status --short'`, `'git diff HEAD'`, `'git checkout -b ...'`, `'gh pr view 45'` each spawned `4` `git` processes) | `rc=0` (`test_guard_merge_authorization_ok pass=505`, `0` `git` spawns on all 6 non-landing commands + `origin/HEAD=release` and sub-repo `cd` regression checks) |
| `T3a` | `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` | `rc=1` (`expected 1 git rev-parse call on linked worktree edit` — plugin spawned `3` `rev-parse` calls) | `rc=0` (`52/52` pass, `1` plugin `git rev-parse` call on linked worktree edit; primary `.worktree-only` checkout blocked) |
| `T3b` | `hooks/test_agy_bridge.py` | `rc=1` (`AssertionError: 'headless-background-stop.sh' unexpectedly found in invoked` when `CLAUDE_CODE_ENTRYPOINT` unset) | `rc=0` (`Ran 68 tests ... OK`; skipped when unset, executed under `CLAUDE_CODE_ENTRYPOINT=sdk-ts`, `--bindings` 1:1 with `hooks/hooks.json`) |
| `T3c` | `hooks/test_proposed_next.py` | `rc=1` (`brain/conv-1234/scratch/*.md` included in `reader_docs`) | `rc=0` (`Ran 73 tests ... OK`; `brain/<id>/scratch/**` excluded while `brain/<id>/walkthrough.md` and `docs/guide.md` retained) |
| `T4` | `scripts/test_check_spec_references.py` | `rc=1` (`AssertionError: 27 != 1 : expected CITATION_RE to run only on the 1 file containing backticked specs/, got 27`) | `rc=0` (`Ran 80 tests ... OK`; `finditer_calls=1`, `escape_calls=2`, `spec_reference_check_ok`) |
| `T5a` | `skills/skill-extraction-workflow/scripts/test_check_ccl_size_budget.sh` | `rc=1` (`FAIL: expected 0 'git show' calls (use cat-file --batch), got 2`) | `rc=0` (`test_check_ccl_size_budget: ok`; `0` `git show`, `1` `rev-parse --show-toplevel`, `<=12` total git calls, nested export inside enclosing checkout downgrades cleanly) |
| `T5b` | `skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh` | `rc=1` (`FAIL: expected 1 batched rg spawn across 3 non-git skill roots, got 3`) | `rc=0` (`test_validate_skill_credential_cwd: ok`; `1` `rg` spawn across 3 skill roots from subdir `cwd`, unreadable root fails closed) |
| `T5c` | `skills/skill-extraction-workflow/scripts/test_git_identity_predicate_gate.sh` | `rc=1` (`FAIL p13 batched scan expected rc=0 and 0 grep spawns across 6 files, got rc=0 spawns=6`) | `rc=0` (`19 passed, 0 failed, 0 skipped`, `test_git_identity_predicate_gate_ok`, incl. `p14` non-ASCII root path) |
| `T5d` | `skills/skill-extraction-workflow/scripts/test_liveness_predicate_gate.sh` | `rc=1` (`FAIL p15 batched liveness scan expected rc=0 and 0 grep spawns across 6 files, got rc=0 spawns=6`) | `rc=0` (`pass=25 fail=0`, `liveness_predicate_gate_ok`, incl. `p16` non-ASCII root path) |
| `T5e` | `skills/skill-extraction-workflow/scripts/test_generic_r0_leak_scan.sh` | `rc=1` (`FAIL: expected rc=0 got rc=2 (cold --self-test-cached should pass)`) | `rc=0` (`test_generic_r0_leak_scan: ok`; cold `2`-`rg` batch, warm `0`-`rg` hit, `CCL_SKILL_NO_SELFTEST_CACHE=1`, 1-byte invalidation, `7d2` swapped-`rg` invalidation, broken mutant non-caching, `0777`/symlink rejection, `<=64` pruning, `Makefile` uncached `--self-test`) |

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

## 3. Applied Differential Killing-Mutation Walk (`26/26` Killed)

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
| `M18_r0_stamp_omit_rg_identity` | `skills/skill-extraction-workflow/scripts/generic-r0-leak-scan.sh` | Drop `rg_bin:rg_hash` from `selftest_stamp_key` | `0` | `1` | `expected swapped rg binary on PATH to miss prior stamp and invoke rg, got 0` |
| `M19_ap27_utf8_prefix_encoding` | `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | Revert `# encoding: BINARY` + `.b` prefix to `# encoding: UTF-8` in Anti-pattern 27 | `0` | `1` | `FAIL p14 non-ASCII root path` (`Encoding::CompatibilityError`) |
| `M20_r0_scan_omit_no_config` | `skills/skill-extraction-workflow/scripts/generic-r0-leak-scan.sh` | Drop `--no-config` from `rg` in `scan_stream()` | `0` | `1` | `FAIL: expected rc=0 got rc=1 (RIPGREP_CONFIG_PATH=--fixed-strings must be ignored (--no-config))` |

Note: `M03b` was observed directly during the initial mutation-walk run before `[ "${#input}" -le 65536 ]` was added (`26/26` distinct mutations verified).

## 4. Contract Sync & `tighten-doc` Closeout Evidence

- **Repo-local contracts updated**:
  - `hooks/AGENTS.md`: documents `agy-bridge.py` `Stop` skip of `headless-background-stop.sh` outside `sdk|sdk-*` entrypoints (while keeping `DISPATCH['Stop']` parity) and the `0`-`jq` non-opt-in `owner-dispatch.sh` `PreToolUse:Bash` fast path.
  - `skills/skill-extraction-workflow/scripts/AGENTS.md`: adds `test_generic_r0_leak_scan.sh` alongside `test_check_evidence_card_leak_cache.sh`.
  - `skills/skill-extraction-workflow/references/source-register.md`: appends six rows (`899–904`: two initial rows for `skill-extraction-workflow` validator/gate batching & caching and `skill-extraction-workflow (plugin runtime surface)` hook/bridge optimizations, plus four append-only remediation rows for `3ca6f633949a19a4ee90ea68313cab79a7d540fb`, `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc`, and `509adc8dbd82bb36a62e06602fef0f98f7df185b`).
  - OpenCode `Stop` boundary note: `packages/opencode-plugin/ccl-skills.ts` continues running `commandHooks(root, "Stop")` because `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` (`L123-145`, `L317`) pins 1:1 execution of every `Stop` command hook in `hooks/hooks.json` with `CLAUDE_CODE_ENTRYPOINT` scrubbed (`headless-background-stop.sh` exits in ~1.5 ms pure shell).
- **`tighten-doc` closeout reread**:
  - Surface reread: `specs/bash-hotpath-and-gate-slimming/plan.md` and `specs/bash-hotpath-and-gate-slimming/evidence/validation.md` in full, cross-checked against `hooks/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`, and `skills/skill-extraction-workflow/references/source-register.md` (`L899-904`).
  - Blocks touched since prior reread: `plan.md` opening scope line, `T5c`/`T5d`/`T5e` summary rows, `M18`–`M20` mutation rows (`26/26`), `source-register.md` row count (`899–904`), and the partitioned/full-repo/delta review sections below.
  - Card/family scan trigger: not applicable (round validation record + local `AGENTS.md` contracts, not an execution-card family).
  - Defects found & fixed: sanitized `plan.md` local checkout path and turn-numbered phrasing, synchronized probe/mutation/register counts (`19`, `25`, `26/26`, rows `899–904`), and withheld raw JSON receipts that quote local filesystem paths from tracked `evidence/`.
  - Scope boundary reason: `hooks/AGENTS.md` and `scripts/AGENTS.md` were already reread in full and had no edits after `3ca6f633949a19a4ee90ea68313cab79a7d540fb`.

## Review pass

- Reviewed commit: `f8b0872dc8f77201e3953deb3fc502d5e493dc69` (base `origin/main` `827f7f684b41842452ca6af3421a45f3e4d364ef`; receipt: `specs/bash-hotpath-and-gate-slimming/evidence/pass1-review.json`; client: `claude`)
- Findings: 3 total (0 P0 / 1 P1 / 2 P2)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Dispositions:
  - `P1` (`hooks/guard-merge-authorization.sh:318`): `fixed` (and source-verified) — `gh`/`glab`/`tea`/`hub`/HTTP merge arms at `hooks/guard-merge-authorization.sh:367-998` block platform merges unconditionally without reading `default_branch`, `current_branch`, `origin_flag`, or `is_default_name()`; commit `3ca6f633949a19a4ee90ea68313cab79a7d540fb` also adds per-segment `seg_git_loaded` lazy initialization inside `is_default_name()` plus `origin/HEAD=release` and sub-repo `cd` regression tests in `hooks/test_guard_merge_authorization.sh` (`pass=505`).
  - `P2` (`hooks/skill-loading.py:26`): `fixed` in `3ca6f633949a19a4ee90ea68313cab79a7d540fb` — added backtick, `{`, and `!` leading boundaries to `BASH_WRITE_HINT_RE`, added 21-family `host-input.bash_write_targets` implication tests in `hooks/test_skill_loading.py`, and recorded killing mutant `M04b`.
  - `P2` (`scripts/owner-dispatch/owner-dispatch.sh:703`): `fixed` in `3ca6f633949a19a4ee90ea68313cab79a7d540fb` — broadened fast-path tool-name matching to `*[Ee]dit*|*[Ww]rite*|*apply_patch*`; also included `${roots[*]}` in `validate-skill.sh` non-1 `rg` diagnostics (`test_validate_skill_credential_cwd.sh`).

## Challenge pass

- Reviewed commit: `3ca6f633949a19a4ee90ea68313cab79a7d540fb` (base `origin/main` `827f7f684b41842452ca6af3421a45f3e4d364ef`; receipt: `specs/bash-hotpath-and-gate-slimming/evidence/pass2-challenge.json`; client: `claude`)
- Findings: 2 total (0 P0 / 1 P1 / 1 P2)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Gate-fireability applicability: yes; Item 9 exercised: `specs/bash-hotpath-and-gate-slimming/evidence/pass2-challenge.json` (`challenge_focus` + `concern_results`)
- Dispositions:
  - `P1` (`hooks/skill-loading.py:38`): `pre-existing & out-of-scope` (source-refuted as a regression, then confirmed `passed` in widened Partition 1 challenge `part1-challenge.json`) — at base `827f7f684b41842452ca6af3421a45f3e4d364ef`, `hooks/host-input.py:504` (`bash_write_targets`) already enforces `if not isinstance(command, str) or not command or len(command) > 65536: return []`, so `Bash` commands over `65,536` characters already returned `[]` before this change.
  - `P2` (`hooks/guard-merge-authorization.sh:1031`): `pre-existing & out-of-scope` (source-refuted, then confirmed `passed` in widened Partition 1 challenge `part1-challenge.json`) — at base `827f7f684b41842452ca6af3421a45f3e4d364ef`, `hooks/guard-merge-authorization.sh` (`L995-1118`) had only `checkout|switch`, `push`, `merge`, and `pull` arms in `case "$sub"`.

## Partitioned Widened-Context & Full-Repository Read-Only Passes (`claude`)

To eliminate packet-only 3-line diff blindness and >2,000-line single-packet dilution, all 32 changed files at `db5bcebfe1c2fe63bf7fd2f58782efb3d731637f` were split into 3 focused widened-context partitions (`part1` hooks/owner-dispatch, `part2` OpenCode/spec-refs/Makefile/docs, `part3` extraction gates/cache; union = 32/32 files) and paired with full-repository `review_diff.py --client-order claude` (`--tools Read,Grep,Glob`):

- **Partition 1 (`hooks/*`, `scripts/owner-dispatch/owner-dispatch.sh`, `source-register.md` + full surrounding functions)**:
  - `review` (`specs/bash-hotpath-and-gate-slimming/evidence/part1-review.json`, `packet_sha256=b72e0ae910204bcd09b18b36c582f63fa224e9af136a4b5b2d2cb039d4852fb9`): `0 P0 / 0 P1 / 1 P2` (cross-partition note that `part2`/`part3` files are reviewed in their own partitions).
  - `challenge` (`specs/bash-hotpath-and-gate-slimming/evidence/part1-challenge.json`, `packet_sha256=03e64f6748bdf3d84bc376f225fe281d9440c6291152c8379b8f1b6f4304cd81`): `passed` (`0` findings).
- **Partition 2 (`Makefile`, `packages/*`, `scripts/check-spec-references.py`, `scripts/test_check_spec_references.py`, `specs/bash-hotpath-and-gate-slimming/`, `source-register.md` + full surrounding functions)**:
  - `review` (`packet_sha256=6a82ce37032d4399b0e0f3fd5d378fc7f55822cfdc9e85c781a434b8007e40e3`; raw receipt retained in private scratch because reviewer prose quotes a partial backticked `specs` byte prefix): `0 P0 / 0 P1 / 1 P2` (cross-partition note that `part1`/`part3` files are reviewed in their own partitions).
  - `challenge` (`packet_sha256=7d2a0c37c64ef5102757aa319d6b38b88435b7f6ce0a9d9448fa955c59e3ef09`; raw receipt retained in private scratch for the same partial backticked byte-prefix quote): `passed` (`0` findings).
- **Partition 3 (`skills/skill-extraction-workflow/scripts/*`, `source-register.md`, `plan.md` + full surrounding functions)**:
  - `review` (`packet_sha256=d52276f50cf3cfc7953bc7f7150702c079fca3a8f1d03ad10ecf2d13f3079358`; raw receipt retained in private scratch because its finding text quotes the pre-fix local checkout path): `0 P0 / 1 P1 / 0 P2` — `P1` (`specs/bash-hotpath-and-gate-slimming/plan.md:5` local checkout path and turn labels) `fixed` in `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc`.
  - `challenge` (`specs/bash-hotpath-and-gate-slimming/evidence/part3-challenge.json`, `packet_sha256=9a7f3e232cb6b3a15bde36c973fde09770bf92be5b634026e2877be073867033`): `0 P0 / 0 P1 / 1 P2` — `P2` (`generic-r0-leak-scan.sh:319` bind stamp key to `rg` binary) `fixed` in `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc` (`test_generic_r0_leak_scan.sh` `7d2`, `M18`).
- **Full-Repository Read-Only `Read,Grep,Glob` Passes (`review_diff.py --client-order claude`; raw receipts retained in private scratch because `diagnostics_path` embeds the host gitdir path)**:
  - `review` on `db5bcebfe1c2fe63bf7fd2f58782efb3d731637f` (`candidate_digest=6ccab7d8d7a29f9cd76b37316e5464ad312a08b303907f24d7a486768a64a6aa`, `287.6s`): `0 P0 / 0 P1 / 1 P2 / 2 P3` — `P2` (`rg` stamp key) and `P3` (`check-ccl-skills.sh` non-ASCII root `Encoding::CompatibilityError`) `fixed` in `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc` (`p14`, `p16`, `M19`); `P3` (`hooks/host-input.py` `brain/<id>/scratch` matching across configurable `appDataDir` roots) retained by design to match `AGENT_DOC_DIRS` (`scratchpad`) and `T3c`.
  - `challenge` on `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc` (`candidate_digest=b03c92d9a8dca7c9a326da2114080dfecdf18f482cd97b0b80801878aa456e1d`, `275.5s`): `0 P0 / 0 P1 / 1 P2` — `P2` (`generic-r0-leak-scan.sh` `rg --no-config` against `RIPGREP_CONFIG_PATH` poisoning) `fixed` in `509adc8dbd82bb36a62e06602fef0f98f7df185b` (`7d3`, `M20`).

## Delta pass 1

- Reviewed commit: `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc`; packet: `git diff db5bcebfe1c2fe63bf7fd2f58782efb3d731637f..25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc` (receipt: `specs/bash-hotpath-and-gate-slimming/evidence/delta1-review.json`; client: `claude`)
- Findings: 0 total (`passed`)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Dispositions: none (`0` findings)

## Delta pass 2

- Reviewed commit: `509adc8dbd82bb36a62e06602fef0f98f7df185b`; packet: `git diff 25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc..509adc8dbd82bb36a62e06602fef0f98f7df185b` (receipt: `specs/bash-hotpath-and-gate-slimming/evidence/delta2-review.json`; client: `claude`)
- Findings: 0 total (`passed`)
- R0 evidence: `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- Dispositions: none (`0` findings)

## Post-review delta

- `specs/bash-hotpath-and-gate-slimming/evidence/part1-review.json` — added Partition 1 widened review receipt (`db5bcebfe1c2fe63bf7fd2f58782efb3d731637f`)
- `specs/bash-hotpath-and-gate-slimming/evidence/part1-challenge.json` — added Partition 1 widened challenge receipt (`passed`)
- `specs/bash-hotpath-and-gate-slimming/evidence/part3-challenge.json` — added Partition 3 widened challenge receipt (`db5bcebfe1c2fe63bf7fd2f58782efb3d731637f`)
- `specs/bash-hotpath-and-gate-slimming/evidence/delta1-review.json` — added Delta pass 1 receipt covering `25f2638ff91b2d5f20e96fff3c436bd31cb8f8fc` (`passed`)
- `specs/bash-hotpath-and-gate-slimming/evidence/delta2-review.json` — added Delta pass 2 receipt covering `509adc8dbd82bb36a62e06602fef0f98f7df185b` (`passed`)
- `specs/bash-hotpath-and-gate-slimming/evidence/validation.md` — recorded partitioned, full-repository read-only, and delta review/challenge receipts and dispositions (non-executable `evidence/` records only after `509adc8dbd82bb36a62e06602fef0f98f7df185b`)
