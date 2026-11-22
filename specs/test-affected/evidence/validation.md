# Validation: Affected-Test Selector for the Inner Loop

All unit and mutation-walk runs use isolated `tempfile.TemporaryDirectory()` workspaces and scrubbed Git environments (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, isolated `GIT_TEMPLATE_DIR` containing `info/` and no `hooks/`).

## Behavioral evidence (`RED-baseline`, constructed scenarios)

1. **Initial R1/D2 baseline against `b9a3366`:** Running the 19-test suite in `scripts/test_select_affected_tests.py` before editing `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=12, errors=3)`), then passed `19/19`.
2. **Post-review R2 baseline against `36fafa6`:** Expanding `scripts/test_select_affected_tests.py` to 22 tests covering all 33 findings in `specs/test-affected/evidence/review-R2.json` and running against `36fafa6` before editing `Makefile` or `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=9, errors=5)`), then passed `22/22` (`python3 -W error scripts/test_select_affected_tests.py`).

| ID | Probe | Pre-fix baseline (`b9a3366` / `36fafa6`) | Candidate |
| --- | --- | --- | --- |
| T1 | Empty-tree commit ahead of base; independent committed whitespace check when staged edit repairs trailing space | skipped `shared_git_surface_gate.py` / missed committed whitespace | schedules `shared_git_surface_gate.py --base-ref <sha>` and `git diff --no-ext-diff --check <mb_sha> <head_sha> --` |
| T2 | Local `origin/main` & `upstream/dev` shadows, `--base-ref=--independent`, `--files` with `CCL_SKILL_BASE_REF`, corrupt blob integration ref, nearer merge-base listed second, orphan `origin/dev`, no-base | accepted `--independent` in argparse / dropped `--files` env base / silently skipped corrupt ref | resolves `refs/remotes/*`, pins commit SHAs, honors `CCL_SKILL_BASE_REF` in `--files` mode, and exits `2` on invalid/corrupt/missing bases |
| T3 | Pinned `resolved_base_sha` forwarded to `shared_git_surface_gate.py` and real `_run_cmd` child `CCL_SKILL_BASE_REF` | passed symbolic ref name; tested helper dict instead of subprocess | forwards `resolved_base_sha` across `_run_cmd` subprocess boundary; strips Make and Git overrides |
| T4 | Inherited `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_SHALLOW_FILE`, `GIT_NO_REPLACE_OBJECTS`, `GIT_TEMPLATE_DIR`, and `$HOME/.gitconfig` `core.hooksPath` | leaked `GIT_NO_REPLACE_OBJECTS`, `GIT_TEMPLATE_DIR`, and global `core.hooksPath` into child suites | scrubbed across discovery and child execution; child `git init` + `git commit` + `.git/info/attributes` isolated |
| T5 | `--repo <non-git>`, `--repo <subdir>`, broken `.git` pointer in `--files` mode, missing `git` binary, corrupt `.git/index`, and checkout directory ending in `\r` | allowed broken `.git` in `--files`; raised `FileNotFoundError` traceback without `git`; stripped `\r` from repo name | exits `2` cleanly with empty stdout on invalid/broken repos or missing `git`; preserves `\r`-suffixed checkout root |
| T6 | UTF-8, space, backslash, rename, untracked-file gate note, and portable synthetic `0xff` vs literal `\udcff` round-trip | created non-portable `0xff` file on disk; collided `0xff` with `\udcff` in JSON/dry-run; omitted untracked note | uses synthetic Git bytes (APFS-portable), bijective `\x00hex:` JSON encoding, Bash `$'...'` quoting, and `untracked-files:` note |
| T7 | Escaping symlinks on generic suites, dedicated serial commands (`test_gen_report.py`), Make fallback escalation, symlink loops, non-suite `.json` fixtures, and dispatch TOCTOU swaps | scheduled external pytest / Make targets, crashed on symlink loops, selected `test_payload.json`, and lacked TOCTOU recheck | blocks all uncontained paths (`unsafe_blocked`, exit `2`), ignores `.json` fixtures, and re-verifies containment before dispatch |
| T8 | `Makefile` shell-safe env transport; executable recipe parser; deleted changed registered suite; AST pytest check with module setup; path aliases & individual heavy regressions; `eval` module fanout; stopped Docker daemon | shell-evaluated `AFFECTED_ARGS`; matched `#` comments in `Makefile` and `heavy_tests`; missed module-setup pytest files and `eval/owner-role-audit.py` | passes Make vars via env, parses recipes/heavy lists comment-safely, dispatches module-setup pytest suites via `pytest -q`, includes `eval.test_<stem>`, and skips stopped Docker |
| T9 | `SIGTERM` child-group forwarding; replayable `--dry-run` from another cwd; ANSI `ESC` scrubbing; early-return notes/skips; `BrokenPipeError` flush | left runner running on `SIGTERM`; omitted `cd`/env in `--dry-run`; leaked `ESC`; dropped early notes; exited `120` on closed pipe | forwards `SIGTERM` via `os.killpg` (`143`), emits replayable prelude (or `(exit 2)` when blocked), scrubs `ESC`, prints early diagnostics, and exits `141` cleanly |

## Dispositions for `specs/test-affected/evidence/review-R2.json` (33 findings: 4 P1, 22 P2, 7 P3)

- **P1 (4/4 fixed):**
  1. Dedicated serial suite containment (`select-affected-tests.py:1066`) -> routed `test_gen_report.py`, `verify-sandbox/test.sh`, `test_check_ccl_regressions.sh`, and `test_review_gate_abort_leak.sh` through `add_serial_suite` + `_verify_command_containment`.
  2. Make fallback containment (`select-affected-tests.py:1160`) -> added `unsafe_blocked` and registered-suite/Makefile containment checks that refuse `make test-*` escalation and exit `2`.
  3. macOS APFS portability for `0xff` filename test (`test_select_affected_tests.py:284`) -> replaced on-disk `0xff` creation with synthetic `_git_bytes` output + byte-exact JSON/Bash round-trip assertions.
  4. Makefile shell interpretation (`Makefile:24`) -> removed `$(AFFECTED_ARGS)` and `$(CCL_SKILL_DEFAULT_BASE_REF)` from shell recipes; exported `AFFECTED_ARGS` and target-scoped `CCL_SKILL_SELECTED_DEFAULT_BASE` via environment.
- **P2 (22/22 fixed):** AST-based `_python_suite_has_main_entrypoint` for module-setup pytest files; `CCL_SKILL_BASE_REF` honored and validated in `--files` mode; unconditional `verify_repo_root` rejecting broken `.git` pointers in `--files` mode; `add_changed_suite` recording `missing_suites` when a changed registered suite is deleted; `eval` changes appending `eval.test_<stem>` to `python3 -m unittest`; `_auto_ref_exists` via `for-each-ref` so corrupt integration refs fail closed (`exit 2`); `GIT_NO_REPLACE_OBJECTS` added to `GIT_REPOSITORY_ROUTING_ENV`; child Git isolation setting `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and temporary `GIT_TEMPLATE_DIR` with `info/`; commit-SHA snapshot binding across discovery, `git diff --check`, gates, and child env; reversible `encode_json_str`/`decode_json_str` and `_shell_quote`; `_is_suite_filename` requiring `.py`/`.sh`; `normalize_input_relpath` before `DEDICATED_RUNNER_SUITES`; comment-safe `heavy_regression_suites()` gating individual heavy regressions behind `--include-slow`; `RuntimeError` caught for symlink loops; `_verify_command_containment` rechecking operands (`hooks/`, `scripts/`, `skills/`, `eval/`, `eval.*`, `packages/ccl-skills-npm`, `Makefile`) before execution; `start_new_session=True` + `os.killpg` forwarding `SIGINT`/`SIGTERM`/`SIGHUP`; replayable `--dry-run` `cd` + env prelude; shlex-based executable `Makefile` recipe parser; `_git_bytes` catching `OSError` as `SelectorError`; `untracked-files:` note for `git ls-files` gates; quoted env-passed fixture paths tested under spaced `TMPDIR`; hook regression test accepting pytest-dispatched serial hook suites.
- **P3 (7/7 fixed):** `sys.stdout.flush()`/`sys.stderr.flush()` inside `BrokenPipeError` handler (verified exit `141` on `--dry-run` and `--json`); `_emit_diagnostics` called on all early returns; `_strip_single_git_newline` preserving `\r`-suffixed checkout names; independent committed-whitespace `git diff --no-ext-diff --check <mb_sha> <head_sha> --`; `_terminal_safe` escaping C0/DEL/C1 controls including ANSI `ESC`; real `_run_cmd` subprocess env test + farther-first nearest-base ordering; `--base-ref=--independent` tested past `argparse`.

## Applied killing-mutation walk

Executed in an isolated temporary copy of the worktree (`22/22` mutants killed by their owning tests under `python3 -W error`; restored control passed `22/22`):

| Protected property | Applied mutation | Killing test |
| --- | --- | --- |
| Empty-commit metadata preflight & committed whitespace check | `if has_candidate_commits:` -> `if False:` | `test_clean_changeset_selects_nothing_and_empty_commit_runs_metadata_gate` |
| Pure skill Markdown skips `code-review` shards | `if skill_name == "code-review":` -> `if True:` | `test_pure_skill_markdown_skips_heavy_code_review_and_hook_suites` |
| Narrow hook change selects only target suite | `if path in HOOK_FILE_MAP:` -> `if False:` | `test_narrow_hook_change_selects_only_target_hook_suite` |
| Shared hook helper fanout | remove `test_guard_edit_isolation.sh` from `HOOK_FILE_MAP["hooks/host-input.py"]` | `test_shared_hook_helper_fans_out_to_dependent_hook_suites` |
| Abort-leak path aliases & individual heavy regressions | remove `test_review_gate_abort_leak.sh` from `DEDICATED_RUNNER_SUITES` | `test_code_review_leaf_script_core_fanout_path_aliases_and_heavy_regressions` |
| Affected `eval` module included in `unittest` command | `eval_extra_modules.append(mod_name)` -> `pass` | `test_eval_changes_include_affected_eval_unittest_module` |
| Antigravity manifest tracks `npm_required` | remove `.antigravity-plugin/` from package prefix tuple | `test_package_and_antigravity_surfaces_track_npm_checks` |
| CI/Makefile change selects spec-reference suite | `builder.add_suite("scripts/test_check_spec_references.py")` -> `pass` | `test_ci_and_makefile_select_binding_and_spec_guards` |
| Bijective raw-byte JSON/shell encoding & untracked note | replace `_JSON_BYTES_PREFIX` hex encoder with `backslashreplace` | `test_git_changed_file_discovery_special_names_untracked_note_and_reversible_raw_bytes` |
| Auto-ref canonicalization, corrupt ref hard error, & `--files` env base | `_canonicalize_auto_ref` returns raw `ref` instead of `refs/remotes/{ref}` | `test_base_resolution_precedence_shadow_corrupt_ref_unrelated_upstream_and_files_env` |
| Pinned base SHA reaches child subprocess via `_run_cmd` | `env["CCL_SKILL_BASE_REF"] = resolved_base` -> `pass` | `test_resolved_base_snapshot_reaches_child_subprocess_and_strips_overrides` |
| Child Git env/template/hook isolation | remove `"GIT_INDEX_FILE"` from `GIT_REPOSITORY_ROUTING_ENV` | `test_git_isolation_covers_discovery_child_templates_and_global_hooks` |
| `--repo` validation in `--files` mode, missing `git`, & trailing `\r` | bypass `rev-parse --show-toplevel` non-zero check | `test_repo_root_validation_broken_git_missing_git_binary_and_trailing_cr` |
| Dedicated serial, Make fallback, symlink-loop, & TOCTOU containment | bypass `resolved.relative_to(root_real)` | `test_containment_covers_dedicated_serial_make_fallback_symlink_loops_non_suites_and_toctou` |
| Literal suite path existence guard | inject nonexistent suite path literal | `test_every_literal_suite_path_in_selector_exists` |
| Executable `Makefile` recipe parser & deleted changed suite drift | remove `self._record_missing(norm)` in `add_changed_suite` | `test_makefile_recipe_parser_deleted_registered_suite_and_spaced_tmpdir_fallback` |
| `Makefile` passes variables without shell evaluation | reintroduce `$(AFFECTED_ARGS)` shell interpolation in `Makefile` | `test_makefile_passes_inputs_without_shell_interpretation` |
| AST pytest entrypoint check with module-level setup | disable `_python_suite_has_main_entrypoint` check | `test_pytest_style_suite_with_module_setup_dispatches_via_pytest_and_fails_on_red_assertion` |
| Stopped Docker daemon marks `verify-sandbox` skipped | `_docker_daemon_ready()` returns `True` unconditionally | `test_stopped_docker_daemon_records_verify_sandbox_skip` |
| Rename reports both old and new paths | drop `--no-renames` from `git diff` | `test_rename_reports_both_old_and_new_paths` |
| `SIGTERM` cancellation forwarded to child process group | `os.killpg(proc.pid, signum)` -> `pass` | `test_sigterm_cancellation_forwards_to_active_runner_child_group` |
| Advisory footer, ANSI scrubbing, replayable `--dry-run`, & `BrokenPipeError` | replace `ADVISORY_FOOTER` with `select_affected_tests_ok` | `test_json_dry_run_replay_early_diagnostics_ansi_escape_exit_codes_and_broken_pipe` |

## Security first pass (`security-first-pass-only`)

Read-only triage of the selector's input and execution boundaries (not a dedicated security audit):

- `Makefile` exports `AFFECTED_ARGS` and target-scoped `CCL_SKILL_SELECTED_DEFAULT_BASE` via `envp` with zero shell interpolation.
- `verify_repo_root` enforces `.git` presence and `git rev-parse --show-toplevel == root.resolve()` across all modes.
- Discovery and child execution strip `GIT_REPOSITORY_ROUTING_ENV` (including `GIT_NO_REPLACE_OBJECTS`), `GIT_CONFIG_ROUTING_ENV`, `GIT_CONFIG_KEY_*`, and `GIT_CONFIG_VALUE_*`, and isolate child Git config/templates from user hooks.
- Base refs reject leading `-`, verify commit objects, fail closed on corrupt integration refs, and bind execution to pinned commit SHAs.
- `_classify_suite_path`, `unsafe_blocked`, and `_verify_command_containment` block uncontained paths across generic, dedicated serial, `eval`, `npm`, and `Makefile` fallback commands at both planning and dispatch time.
- `_terminal_safe`, `_shell_quote`, and `encode_json_str` neutralize ANSI/control sequences while keeping machine-readable and dry-run paths reversible.

## Document closeout (`tighten-doc`)

- **Surface reread:** Full reread of `specs/test-affected/plan.md`, `specs/test-affected/evidence/validation.md`, `docs/CONTRIBUTING.md`, and `Makefile` help lines (`closeout-reread.md`).
- **Touched blocks:** Charter, Behavior, Security four questions, Test-case register, Objective closure / Structural minimality, R2 dispositions, and Mutation walk tables.
- **Whole-card / family trigger:** Standalone feature spec + validation pair (not a multi-card standards family); both documents reread end-to-end.
- **Defects found & fixed:** Removed historical narrative wording in Behavior bullets in favor of present-tense invariants; verified all technical assertions (`CCL_SKILL_SELECTED_DEFAULT_BASE`, `\x00hex:`, `unsafe_blocked`, `(exit 2)`, `info/` template dir) against `Makefile` and `scripts/select-affected-tests.py`; confirmed zero contributor/path/session tokens and zero unresolved spec links.
- **Scope note:** `docs/CONTRIBUTING.md` (single sentence on line 78) and `Makefile` help lines re-checked in context for register consistency.

## Implementer self-review (persisted before Pass 2 `code-review --mode challenge`)

- **Acceptance criteria rechecked:** All findings from `specs/test-affected/evidence/design-review-D2.json`, `specs/test-affected/evidence/review-R1.json`, and `specs/test-affected/evidence/review-R2.json` (4 P1, 22 P2, 7 P3) verified against `Makefile`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `docs/CONTRIBUTING.md`, and `specs/test-affected/plan.md`.
- **Changed-file scope vs active plan (`origin/main..HEAD`):** `Makefile`, `docs/CONTRIBUTING.md`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `specs/test-affected/plan.md`, and `specs/test-affected/evidence/` (`review-R1.json`, `design-review-D1.json`, `design-review-D2.json`, `review-R2.json`, `validation.md`). Matches `specs/test-affected/plan.md` Target-output map 1:1.
- **Load-bearing invariants & edge/failure paths checked:**
  1. Shell-free Make transport & `test-repo-gates` isolation (`CCL_SKILL_SELECTED_DEFAULT_BASE` target-scoped).
  2. Advisory-only output contract across `--run`, `--dry-run`, and `--json`, including early returns and closed pipes (`141`).
  3. Full Git isolation (`GIT_NO_REPLACE_OBJECTS`, `GIT_CONFIG_GLOBAL=/dev/null`, `info/`-only `GIT_TEMPLATE_DIR`) and SHA-pinned base propagation.
  4. Planning + dispatch-time containment across parallel, dedicated serial, `eval.*`, `npm --prefix`, and `Makefile` fallback commands, plus `SIGTERM` process-group cleanup.
- **Named regression test (RED before, GREEN after):** `python3 -W error scripts/test_select_affected_tests.py` (`9 failures, 5 errors` on `36fafa6` -> `22/22 OK` on candidate; `22/22` applied mutations killed).
- **Known residual risks:** Selection remains heuristic by design (advisory inner-loop aid, not a sound dependency graph); `AGENTS.md` and CI continue to require `make test` and touched focused suites before landing.
