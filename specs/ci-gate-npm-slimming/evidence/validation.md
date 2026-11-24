# Batch 1 Validation & Evidence Record

## Scope & Candidate Baseline

- **Branch**: `ccoalm/ci-gate-npm-slimming`
- **Target base**: `origin/main` (`fb7874f6b1a8353f969c10596d74178b71453822`)
- **Plan**: `specs/ci-gate-npm-slimming/plan.md` (Batch 1 of the 4-batch repository optimization roadmap)
- **Visible UI surface**: `visible surface: no` (internal CLI/CI validators and npm package asset closure)

## Pre-Implementation RED Baselines (`T1`–`T4`)

All new assertions were authored and executed against the unpatched `fb7874f6b1a8353f969c10596d74178b71453822` implementations before production edits:

| ID | Suite | Pre-Fix RED Result | Post-Fix GREEN Result |
| --- | --- | --- | --- |
| `T1` | `skills/code-review/scripts/test_init_policy_matrix.sh` | `exit 1` — `init_policy_matrix.py spawned 270 child Python processes (expected <= 6 in-process + CLI parity smoke)` | `exit 0` (`init_policy_matrix_ok`; `4` child Python spawns for CLI parity smoke, `__main__` divergence mutant caught, `guard-self-check-broken-mutant` and all `7` policy mutants caught) |
| `T2` | `skills/skill-extraction-workflow/scripts/test_check_evidence_card_leak_cache.sh` | `exit 1` — `FAIL - heading-less --all scan spawned mktemp or failed: rc=0 mktemp_calls=3` | `exit 0` (`passed=15 failed=0`; `0` `mktemp` spawns on heading-less `--all` scan, fenced-heading + unfenced-tier file passes, unfenced card fails) |
| `T3a` | `skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh` | `exit 1` — `expected SKILL.md=1 and demo.rb<=2 File.read calls, got SKILL.md=4 demo.rb=5` | `exit 0` (`register_firing_path_resolution_tests_ok (68 assertions)`; `SKILL.md=1`, `demo.rb=2`) |
| `T3b` | `skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh` | `exit 1` — `expected 0 dirname spawns during root discovery, got 3` (and `3` `ruby` spawns) | `exit 0` (`test_validate_skill_credential_cwd: ok`; `0` `dirname` spawns, `2` `ruby` spawns, exact YAML, missing-reference, and fail-closed `install_visibility_scan_error` tokens preserved) |
| `T3c` | `skills/skill-extraction-workflow/scripts/test_check_contract_anchors.sh` | `exit 1` — `FAIL S1-subproc: unexpected grep/wc/tr spawns` | `exit 0` (`test_check_contract_anchors: ok`; `0` `grep`/`wc`/`tr`/`ruby` spawns, glob-metacharacter fixed-string row `S0-glob-meta` green, `M1`–`M10` / `B1`–`B3` / `D1` / `R1` green) |
| `T4` | `packages/ccl-skills-npm/test/{basic.test.mjs,opencode-hooks.test.mjs}` | `exit 1` — `dist/assets must exclude repo-only test suites, found 107` and `✖ source-extra-repo-test-script` (`delegation-owner guard`) | `exit 0` (`0` leaked repo-only test suites in `release.json`, runtime hooks and contract fixtures retained, `CCL_SKILLS_REPO` override excludes repo-only skill tests, and `sameSkillDirectory` skips one-sided single-link regular repo-test scripts while rejecting tampered shared test scripts, extra runtime scripts, symlinks, and hardlinks) |

## Interleaved Paired Benchmarks & Package Size Deltas

Paired benchmarks interleaved `origin/main` (`fb7874f6b1a8353f969c10596d74178b71453822`) and the candidate worktree (`AB` / `BA` alternating order per round) with pre-warmed self-test caches where applicable:

| Workload | Command | Rounds | Base Median (`s`) | Candidate Median (`s`) | Speedup |
| --- | --- | --- | --- | --- | --- |
| `init_policy_matrix_single` | `python3 skills/code-review/scripts/init_policy_matrix.py` | `5` | `27.7667` | `0.7214` | `38.49x` |
| `test_init_policy_matrix_suite` | `bash skills/code-review/scripts/test_init_policy_matrix.sh` | `3` | `89.5081` | `4.2913` | `20.86x` (`-85.22s`) |
| `evidence_card_leak_strict_selftest` | `CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1 bash skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh --self-test` | `5` | `5.9958` | `1.0346` | `5.80x` (`-4.96s`) |
| `register_firing_path_resolution` | `ruby -Ku skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb .` | `5` | `0.4969` | `0.2516` | `1.97x` |
| `validate_skill_all_roots` | `bash skills/skill-extraction-workflow/scripts/validate-skill.sh .` | `5` | `0.6243` | `0.5435` | `1.15x` |
| `check_contract_anchors` | `bash skills/skill-extraction-workflow/scripts/check-contract-anchors.sh .` | `5` | `0.0519` | `0.0198` | `2.62x` |
| `check_ccl_skills_warm` | `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` | `5` | `4.0570` | `3.0192` | `1.34x` (`-1.04s`) |

> **Falsified intermediate hypothesis recorded**: A pure-Bash `while [[ "$rem" == *"$literal"* ]]` implementation of `check-contract-anchors.sh` regressed from `0.0534s` to `1.2835s` (`0.04x`) due to multibyte glob scanning across large Markdown files; replacing it with a single `python3` byte-count pass (`bytes.count`) eliminated all `grep`/`wc`/`tr`/`ruby` spawns while cutting median latency to `0.0198s` (`2.62x` faster than baseline).

### `@ccoalm/ccl-skills` Asset Closure & Tarball Delta

| Metric | `origin/main` (`fb7874f6b1a8`) | Candidate | Delta |
| --- | --- | --- | --- |
| `dist/assets/release.json` `files` count | `698` | `591` | `-107` files (`-15.3%`) |
| Unpacked `dist/assets` bytes | `12,549,074` B (`11.97 MiB`) | `9,285,431` B (`8.86 MiB`) | `-3,263,643` B (`-3.11 MiB`, `-26.0%`) |
| Packed `.tgz` artifact bytes | `4,032,863` B (`3.85 MiB`) | `3,276,763` B (`3.12 MiB`) | `-756,100` B (`-738.4 KiB`, `-18.7%`) |

## Applied Differential Killing-Mutation Walk (`18/18` + `4/4` Post-Challenge Regressions)

Executed in a disposable clone outside the candidate worktree (`pre_digests == post_digests` verified across all modified files; all target test commands passed GREEN on the unmutated copy first):

| Mutant ID | Target File | Mutated Predicate | Differential RED Attribution (`rc=1`) |
| --- | --- | --- | --- |
| `M01_init_matrix_child_spawns` | `skills/code-review/scripts/init_policy_matrix.py` | Expand CLI smoke to 5 cases (`10` child spawns > `6`) | `init_policy_matrix.py spawned 10 child Python processes` |
| `M02_init_matrix_cli_parity_smoke` | `skills/code-review/scripts/init_policy_matrix.py` | Disable subprocess CLI parity loop (`if False and module is not None`) | `init_policy_matrix.py missed a broken __main__ CLI entrypoint` |
| `M03_init_matrix_broken_mutant_unparseable` | `skills/code-review/scripts/init_policy_matrix.py` | Map module load errors to `TERMINAL` instead of `"unparseable"` | `the walk accepted a BROKEN mutant as sensitivity` |
| `M04_evcard_heading_prefilter` | `skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh` | Remove raw `HEADING_RE` precheck before `sanitized_file` | `FAIL - heading-less --all scan spawned mktemp or failed` (`fenced card` remained `ok`) |
| `M05_evcard_fenced_card_pass` | `skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh` | Skip post-sanitization `HEADING_RE` check on `$san` | `FAIL - fenced card false-triggered --all` (`heading-less` remained `ok`) |
| `M06_evcard_unfenced_card_fail` | `skills/skill-extraction-workflow/scripts/check-evidence-card-leak.sh` | Break `classify_conclusion` `filled` branch | `FAIL - unfenced card missed in mixed tree` (`heading-less` remained `ok`) |
| `M07_register_target_memoization` | `skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb` | Bypass `target_cache[target] ||=` memoization | `expected SKILL.md=1 and demo.rb<=2 File.read calls` |
| `M08_validate_skill_zero_dirname` | `skills/skill-extraction-workflow/scripts/validate-skill.sh` | Revert `${skill_file%/*}` to `$(dirname "$skill_file")` | `expected 0 dirname spawns during root discovery, got 3` |
| `M09_validate_skill_merged_ruby_spawns` | `skills/skill-extraction-workflow/scripts/validate-skill.sh` | Add an extra `ruby` invocation (`3` spawns > `2`) | `expected <= 2 ruby spawns` |
| `M10_validate_skill_yaml_error_token` | `skills/skill-extraction-workflow/scripts/validate-skill.sh` | Alter `missing_frontmatter_` token in merged Ruby pass | `missing_frontmatter_description token missing` |
| `M11_contract_anchors_zero_subproc` | `skills/skill-extraction-workflow/scripts/check-contract-anchors.sh` | Spawn `grep` inside `check-contract-anchors.sh` | `FAIL S1-subproc: unexpected grep/wc/tr/ruby spawns` (`M1` remained `ok`) |
| `M12_npm_release_excludes_repo_tests` | `packages/ccl-skills-npm/scripts/build-assets.mjs` | Disable `REPO_TEST_ASSET_RE` filter | `dist/assets must exclude repo-only test suites, found 107` |
| `M13_npm_release_retains_guard_hook_precision` | `packages/ccl-skills-npm/scripts/build-assets.mjs` | Broaden `hooks/test_[^/]+` to `hooks/.*test[^/]+` | `missing required runtime/contract asset: marketplace/plugins/ccl-skills/hooks/guard-broad-local-test.sh` |
| `M14_opencode_override_excludes_skill_tests` | `packages/ccl-skills-npm/src/opencode-adapter.ts` | Disable `isSkillScriptRepoTest` filter in `walk(skills)` | `✖ OpenCode CCL_SKILLS_REPO override excludes repo-only skill test scripts while keeping runtime scripts` |
| `M15_opencode_sameSkillDirectory_ignores_regular_repo_tests` | `packages/opencode-plugin/ccl-skills.ts` | Disable `scripts/` repo-test filter in `visibleSkillEntries` | `✖ source-extra-repo-test-script` (`source-matching` remained `ok`) |
| `M16_opencode_sameSkillDirectory_rejects_symlink_repo_test` | `packages/opencode-plugin/ccl-skills.ts` | Ignore symlinked `scripts/test_*` entries | `✖ source-symlink-repo-test-script` (`source-extra-repo-test-script` remained `ok`) |
| `M17_opencode_sameSkillDirectory_rejects_hardlink_repo_test` | `packages/opencode-plugin/ccl-skills.ts` | Drop `st.nlink !== 1` check on `scripts/test_*` entries | `✖ source-hardlink-repo-test-script` (`source-symlink-repo-test-script` remained `ok`) |
| `M18_abort_leak_subreaper_reparent` | `skills/code-review/scripts/test_review_gate_abort_leak.sh` | Revert `wrapper_is_reparented` to hardcoded `ppid == 1` | `abort_leak_setup_lost: wrapper ... was never reparented` under synthetic `PR_SET_CHILD_SUBREAPER` (`test_abort_leak_state_helpers.sh`) |

Post-challenge P2 RED-to-GREEN regressions verified on `e5be42f226ef8b7b73bfda924c8afb7dc9a639c5` and `30380275b1386a5bfe4a14180ca85f37b78fe6ac`:

1. `tampered-shared-repo-test-script` (`packages/ccl-skills-npm/test/opencode-hooks.test.mjs`): fails when `sameSkillDirectory` ignores `scripts/test_*` present on both sides with differing bytes; passes when only one-sided single-link regular `scripts/{test_*,*.test.sh}` files are skipped.
2. `M10-abs` & `M10-dotdot` (`skills/skill-extraction-workflow/scripts/test_check_contract_anchors.sh`): fails when `check-contract-anchors.sh` accepts `/etc/...` or `../...` paths; passes (`exit 2`, `contract_anchor_row_malformed`) when path containment inside `root` is enforced.
3. `_SINGLE_USE_GUARD` (`skills/code-review/scripts/test_init_policy_matrix.sh`): fails when `parse_probe_result.py` shares one module dictionary across 270 runs; passes when `_compile_parser_code` executes each `(case, path)` pair in a fresh module namespace.
4. `3d` (`skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh`): fails when `CHECK_INSTALL_VISIBILITY=1` masks a Ruby failure behind process substitution as `install_visibility_not_found`; passes (`exit 2`, `install_visibility_scan_error`, no `install_visibility_not_found`) when Ruby output is captured and checked before the loop.

## Verification By Layer & Sync Gates

- **Unit**: `test_init_policy_matrix.sh`, `test_abort_leak_state_helpers.sh` (including synthetic Linux `PR_SET_CHILD_SUBREAPER` reparenting regression), `test_check_evidence_card_leak_cache.sh`, `test_register_firing_path_resolution.sh`, `test_validate_skill_credential_cwd.sh`, `test_check_contract_anchors.sh`, `test_pinned_phrase_mutation_walk.sh` — all `exit 0`.
- **Inherited Gate-Blocker Repair (`refactoring-discipline.md` §Responding to quality gates)**: On Linux sessions supervised by `systemd --user` (`PR_SET_CHILD_SUBREAPER`), orphaned processes reparent to the subreaper rather than `PID 1`, causing `test_review_gate_abort_leak.sh` (`[ "$(ps -o ppid= ...)" = "1" ]`) to fail `make test` (`abort_leak_setup_lost: wrapper ... was never reparented`). Added pipe-synchronized `orphan_reaper_pid()` + `wrapper_is_reparented()` in `test_review_gate_abort_leak.sh` and pinned both ambient and synthetic `PR_SET_CHILD_SUBREAPER` cases RED→GREEN in `test_abort_leak_state_helpers.sh`.
- **Integration / Contract**: `select-affected-tests.py --run`, `make test` (`test-repo-gates`, `test-regressions-fast`, `test-code-review`), `check-skill-count.py`, `test_check_ccl_regressions.sh --heavy-only`, `npm --prefix packages/ccl-skills-npm test`, `npm --prefix packages/ccl-skills-npm run test:pack` — all `exit 0`.
- **E2E / Host Smoke**: `npm --prefix packages/ccl-skills-npm run smoke:host` — `exit 0` (`{"status":"four-host-smoke-passed","codexHooks":"native-plugin-registered","openCodeHooks":"plugin-registered","openCodeSharedFiles":"retained","antigravityPlugin":"native-plugin-registered"}`).
- **Contract Sync**: Updated `packages/ccl-skills-npm/scripts/AGENTS.md` to record the closed repo-test exclusion boundary; verified via `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh` (`exit 0`) and `scripts/check-spec-references.py .` + `scripts/check-markdown-links.py .` (`exit 0`).
- **R0 Leakage & Shared Git Surface**: Verified via configured private `process-retro` / maintainer audit wrapper (`alias_audit_ok`, `r0_status=private-ok`, terminal token `ccl_skill_check_clean_ok`), `check_review_evidence_present.py` (`review_evidence_present_ok: 3 review, 1 challenge`), and `shared_git_surface_gate.py --repo . --base-ref origin/main --pr-text-file` (`exit 0`).
- **Document Closeout (`tighten-doc`)**: `Tighten` mode closeout readback completed across `specs/ci-gate-npm-slimming/plan.md`, `specs/ci-gate-npm-slimming/evidence/validation.md`, and `packages/ccl-skills-npm/scripts/AGENTS.md` (decided points preserved, zero session-vantage, meta-narration, or cross-section duplication defects).

## Behavioral Evidence

- **Status**: `RED-baseline`
- **Artifact + outcome**: Constructed scenarios (`T1`–`T4` above plus post-challenge P2 regressions, executed before and after implementation edits) and quantitative profiling at `fb7874f6b1a8353f969c10596d74178b71453822` — baseline spawned `270` Python processes (`27.77s`), `3+` `mktemp` calls on heading-less scans (`6.00s` strict self-test), `4–5` repeated `File.read` calls per target, `3` `dirname` + `3` `ruby` calls on 3-skill validation, per-row `grep|wc|tr` subprocesses, and shipped `107` repo-only test files (`3.11 MiB` unpacked) in `dist/assets`; post-fix candidate satisfies all bounds (`4` CLI-parity Python spawns / `0.72s`, `0` `mktemp` spawns on heading-less scans / `1.03s` strict self-test, memoized target reads, `0` `dirname` / `2` `ruby` spawns, `0` `grep`/`wc`/`tr`/`ruby` spawns in `check-contract-anchors.sh` at `0.020s`, and `0` repo-only test files in `dist/assets` with `four-host-smoke-passed`).

## Dual-Track Review & Challenge Passes

- **Landing-target base attestation**: `remote=origin`, `ref=refs/heads/main`, `sha=fb7874f6b1a8353f969c10596d74178b71453822`, `rev-list --count HEAD..fb7874f6b1a8353f969c10596d74178b71453822 = 0`, re-confirmed live via `git ls-remote origin refs/heads/main` at `2026-11-24T20:15:36Z`.

### Review pass

- **Reviewed commit**: `88595604f573a1c09029834498f9a75cc4789013` (`candidate_sha256=c64b08b6c99244967120f87d6a28d5d548540f5fe6f6413bb26763c0a7e4c536`, `packet_sha256=a64549428291a85d99071e4547b7f5e703a3b14ffe691da8e858f2c769c5e1a0`)
- **Controller receipt**: `specs/ci-gate-npm-slimming/evidence/pass1-review.json` (`status=passed`, `native_skill_binding=established`)
- **Findings**: `0 total (0 P0 / 0 P1 / 0 P2)`
- **R0 evidence**: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- **Dispositions**: `none` (`0` findings)

### Challenge pass

- **Reviewed commit**: `88595604f573a1c09029834498f9a75cc4789013` (`candidate_sha256=c64b08b6c99244967120f87d6a28d5d548540f5fe6f6413bb26763c0a7e4c536`, `packet_sha256=c64b08b6c99244967120f87d6a28d5d548540f5fe6f6413bb26763c0a7e4c536`)
- **Controller receipt**: `specs/ci-gate-npm-slimming/evidence/pass2-challenge.json` (`status=findings`, `native_skill_binding=established`)
- **Findings**: `4 total (0 P0 / 0 P1 / 4 P2)`
- **R0 evidence**: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- **Gate-fireability applicability**: `yes — edits shared-gate validators and OpenCode owner-verification predicates`; **Item 9 exercised**: `specs/ci-gate-npm-slimming/evidence/pass2-challenge.json` (`challenge_focus` item `(5)`)
- **Dispositions**: `0` P0/P1; all `4` P2s fixed in `e5be42f226ef8b7b73bfda924c8afb7dc9a639c5`:
  1. `packages/opencode-plugin/ccl-skills.ts:558` (P2): `fixed` — skip single-link regular `scripts/{test_*,*.test.sh}` only when absent from the peer side; compare stat and bytes when present on both sides (`tampered-shared-repo-test-script`).
  2. `skills/skill-extraction-workflow/scripts/check-contract-anchors.sh:124` (P2): `fixed` — reject absolute, `..`, symlinked, and out-of-`root` paths as malformed (`exit 2`, `M10-abs` and `M10-dotdot`).
  3. `skills/code-review/scripts/init_policy_matrix.py:453` (P2): `fixed` — compile `parse_probe_result.py` once to bytecode and execute each `(case, path)` pair in a fresh module namespace (`_SINGLE_USE_GUARD`).
  4. `skills/skill-extraction-workflow/scripts/validate-skill.sh:241` (P2): `fixed` — capture `CHECK_INSTALL_VISIBILITY=1` Ruby output before the loop and exit `2` with `install_visibility_scan_error` on Ruby failure (`3d`).

### Delta pass 1

- **Reviewed commit**: `e5be42f226ef8b7b73bfda924c8afb7dc9a639c5`; **packet**: `git diff 88595604f573a1c09029834498f9a75cc4789013..e5be42f226ef8b7b73bfda924c8afb7dc9a639c5` (`candidate_sha256=9c50cf39cec11f699511cf4ddf65d43690213837987a5366d139daf45a446a3a`, `packet_sha256=43eca7c1028abed5491fe1292fbaad7dfa8ec31228ef0d6d4bee2233a14b362e`)
- **Controller receipt**: `specs/ci-gate-npm-slimming/evidence/pass3-delta-review.json` (`status=findings`, `native_skill_binding=established`)
- **Findings**: `1 total (0 P0 / 0 P1 / 1 P2)`
- **R0 evidence**: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- **Dispositions**: `0` P0/P1; `1` P2 `fixed` in `30380275b1386a5bfe4a14180ca85f37b78fe6ac` (`skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh:158` `3d` matches the visibility Ruby snippet by argument content rather than call index and asserts `rc == 2`, `install_visibility_scan_error` present, and `install_visibility_not_found` absent, alongside Round 2 `source-register.md` Rows `907` & `908`).

### Delta pass 2

- **Reviewed commit**: `30380275b1386a5bfe4a14180ca85f37b78fe6ac`; **packet**: `git diff e5be42f226ef8b7b73bfda924c8afb7dc9a639c5..30380275b1386a5bfe4a14180ca85f37b78fe6ac` (`candidate_sha256=53d8e73a2160f0bfa72b9b357263343909292567b81751ac88741bb6a8264d0a`, `packet_sha256=a2fbfd96b071d263d946b86ee00bcfd9e5de186459067208120b01f7b3ad46eb`)
- **Controller receipt**: `specs/ci-gate-npm-slimming/evidence/pass4-delta2-review.json` (`status=passed`, `native_skill_binding=established`)
- **Findings**: `0 total (0 P0 / 0 P1 / 0 P2)`
- **R0 evidence**: `alias_audit_ok` / `ccl_skill_check_clean_ok` (`r0_status=private-ok`)
- **Dispositions**: `none` (`0` findings; converged across walked axes: correctness, safety, failure paths, tests/evidence, compatibility, rollout/rollback, observability, claim strength, high-risk boundary, repository contract, and Item 9 gate-fireability; standing open items: `none`)

### Post-review delta

- `git diff --stat 30380275b1386a5bfe4a14180ca85f37b78fe6ac..HEAD`:
  - `specs/ci-gate-npm-slimming/evidence/pass1-review.json` (initial review receipt)
  - `specs/ci-gate-npm-slimming/evidence/pass2-challenge.json` (adversarial challenge receipt)
  - `specs/ci-gate-npm-slimming/evidence/pass3-delta-review.json` (delta pass 1 receipt)
  - `specs/ci-gate-npm-slimming/evidence/pass4-delta2-review.json` (delta pass 2 receipt)
  - `specs/ci-gate-npm-slimming/evidence/validation.md` (validation log and pass dispositions)
