# Validation: Affected-Test Selector for the Inner Loop

All unit and mutation-walk runs use isolated `tempfile.TemporaryDirectory()` workspaces and scrubbed Git environments (`GIT_CONFIG_NOSYSTEM=1`, isolated `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM=/dev/null`, and isolated `GIT_TEMPLATE_DIR` containing `info/` and no `hooks/`).

## Behavioral evidence (`RED-baseline`, constructed scenarios)

1. **Initial R1/D2 baseline against `b9a3366`:** Running the 19-test suite in `scripts/test_select_affected_tests.py` before editing `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=12, errors=3)`), then passed `19/19`.
2. **Post-review R2 baseline against `36fafa6`:** Expanding `scripts/test_select_affected_tests.py` to 22 tests covering all 33 findings in `specs/test-affected/evidence/review-R2.json` before editing `Makefile` or `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=9, errors=5)`), then passed `22/22`.
3. **Post-challenge C1 baseline against `480095d`:** Expanding `scripts/test_select_affected_tests.py` to cover all 19 findings in `specs/test-affected/evidence/challenge-C1.json` before editing `Makefile` or `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=9, errors=2)`), then passed `22/22` (`python3 -W error scripts/test_select_affected_tests.py`).

| ID | Probe | Pre-fix baselines (`b9a3366` / `36fafa6` / `480095d`) | Candidate |
| --- | --- | --- | --- |
| T1 | Empty-tree commit ahead of base; independent committed whitespace check; pinned `--head-ref` on `shared_git_surface_gate.py` | skipped gate / missed committed whitespace / omitted `--head-ref` | schedules `shared_git_surface_gate.py --repo . --base-ref <base_sha> --head-ref <head_sha>` and `git diff --no-ext-diff --check <mb_sha> <head_sha> --` |
| T2 | Exact `%(refname)` auto-base lookup with descendant ref `origin/ns/topic`, broken loose ref (`"1234\n"`), blob ref, `--base-ref=--independent`, `--files` with `CCL_SKILL_BASE_REF`, nearer merge-base, local shadows | treated `origin/ns/topic` as `origin/ns`, silently ignored broken loose ref warning, or accepted `--independent` | requires exact ref match, fails closed (`exit 2`) on broken loose or blob refs, honors `CCL_SKILL_BASE_REF` in `--files` mode, and picks nearest merge-base |
| T3 | Pinned `resolved_base_sha` + `head_sha` propagation; `_run_cmd` child `safe.directory` trust and override scrubbing | passed symbolic ref or dropped `safe.directory` when setting `GIT_CONFIG_GLOBAL=/dev/null` | forwards pinned SHAs, strips Make/Git overrides, and writes `safe.directory` into isolated child `GIT_CONFIG_GLOBAL` |
| T4 | Discovery `core.fsmonitor` suppression and child template/hook/`GIT_INDEX_FILE` isolation | executed configured `core.fsmonitor` during unstaged `git diff` | runs discovery with `-c core.fsmonitor=false -c core.hooksPath=/dev/null` and isolates child `git init`/`git commit` |
| T5 | `--repo <non-git>`, `--repo <subdir>`, broken `.git` pointer in `--files` mode, missing `git` binary, corrupt `.git/index`, and `\r`-suffixed checkout | allowed broken `.git` in `--files`, raised traceback without `git`, or stripped `\r` | exits `2` cleanly with empty stdout on invalid/broken repos or missing `git`; preserves `\r`-suffixed checkout root |
| T6 | `git diff --cached <head_sha>`, `PYTHONIOENCODING=ascii` `--json`, UTF-8/space/backslash/rename paths, untracked note, and synthetic `0xff` vs `\udcff` round-trip | compared index against live `HEAD`, raised `UnicodeEncodeError` under ASCII stdout, or collided `0xff` with `\udcff` | pins `head_sha` in `diff --cached`, emits `ensure_ascii=True` JSON with `\x00hex:` raw-byte encoding, quotes `$'...'` in Bash, and records `untracked-files:` note |
| T7 | FIFO `Makefile`, `GNUmakefile` symlink, escaping non-test recipe script, queued `--jobs 1` parallel swap, `tests/test_widget.py` pytest swap, and escaping `--dry-run` script | blocked on FIFO `read_text()`, followed `GNUmakefile`/recipe/preview symlinks, or ran swapped queued/pytest targets | opens planner files non-blockingly (`O_NOFOLLOW | O_NONBLOCK`), binds `make -f Makefile`, checks all recipe/command operands at plan and dispatch, and verifies each parallel suite when its worker slot opens |
| T8 | Literal `Makefile` recipes (`$5` base ref), dotted `eval.test_*` drift detection, print-only `__main__` pytest dispatch, path aliases & heavy regressions, stopped Docker | expanded `$5` in Make exports, missed deleted `eval/test_design_judge.py` drift, or exited `0` on print-only `__main__` | deletes `AFFECTED_ARGS`/`CCL_SKILL_SELECTED_DEFAULT_BASE`, tracks `eval.test_*` in `makefile_suites()`, requires a runner call inside `__main__`, and gates slow/Docker suites |
| T9 | `SIGTERM` escalation on TERM-ignoring leader and surviving descendant; `set -euo pipefail` `--dry-run` stop-on-error; ANSI scrubbing; early diagnostics; `BrokenPipeError` | hung in unbounded `proc.wait()` or leaked TERM-ignoring grandchild; continued past failed step in plain `bash` replay | installs handlers pre-`Popen`, polls and escalates to `SIGKILL` across live process groups (`143`), emits `set -euo pipefail` in `--dry-run`, scrubs `ESC`, and exits `141` on closed pipe |

## Dispositions for `specs/test-affected/evidence/review-R2.json` (33 findings: 4 P1, 22 P2, 7 P3)

- **P1 (4/4 fixed):** Dedicated serial suite containment (`add_serial_suite` + `_verify_command_containment`); Make fallback containment (`unsafe_blocked`); APFS-portable synthetic `0xff` filename test; Makefile shell-interpolation removal (superseded in C1 by deleting `AFFECTED_ARGS` and `CCL_SKILL_SELECTED_DEFAULT_BASE` altogether).
- **P2 (22/22 fixed):** AST `_python_suite_has_main_entrypoint`; `CCL_SKILL_BASE_REF` honored in `--files` mode; unconditional `verify_repo_root`; `add_changed_suite` drift detection; `eval.test_<stem>` fanout; `for-each-ref` corrupt-ref check; `GIT_NO_REPLACE_OBJECTS` scrubbing; child Git template/hook isolation; commit-SHA snapshot binding; reversible `encode_json_str`/`decode_json_str` and `_shell_quote`; `.py`/`.sh` `_is_suite_filename`; `normalize_input_relpath` before `DEDICATED_RUNNER_SUITES`; comment-safe `heavy_regression_suites()`; `RuntimeError` symlink-loop handling; dispatch operand recheck; `start_new_session=True` + `os.killpg`; replayable `--dry-run` prelude; shlex `Makefile` recipe parser; `_git_bytes` `OSError` handling; `untracked-files:` note; spaced-`TMPDIR` fallback test; pytest-aware hook dispatch test.
- **P3 (7/7 fixed):** `BrokenPipeError` handler covering `flush()` (`141`); early-return `_emit_diagnostics`; `_strip_single_git_newline` preserving `\r`; independent committed-whitespace `git diff --check`; `_terminal_safe` C0/DEL/C1 escaping; real `_run_cmd` subprocess env test + farther-first base ordering; `--base-ref=--independent` tested past `argparse`.

## Dispositions for `specs/test-affected/evidence/challenge-C1.json` (19 findings: 5 P1, 13 P2, 1 P3)

- **Recurring-finding design checks (`recurring_findings_design_check`):**
  1. **`delete` `AFFECTED_ARGS` and `CCL_SKILL_SELECTED_DEFAULT_BASE` (`Makefile:12`, recurring across `review-R2.json` P1 #4 and `challenge-C1.json` P1 #1):** Deleted both variables from `Makefile` and `scripts/select-affected-tests.py` so `Makefile` contains only literal zero-expansion recipes (`python3 scripts/select-affected-tests.py --repo . --run` / `--dry-run`); ratified by requester under sole-owner default.
  2. **`replace` partial containment checks with unified regular-file and slot-bound verification (recurring across `review-R2.json` P1 #1/#2, P2 TOCTOU and `challenge-C1.json` P1 #2/#3/#4, P2 #7/#14/#15):** Unified file reading (`_read_contained_regular_bytes` with `O_NOFOLLOW | O_NONBLOCK` + `S_ISREG`), Make fallback (`make -f Makefile` + `makefile_recipe_paths()`), planning/preview/dispatch `_verify_command_containment`, and per-slot `_run_parallel_suites_bounded` verification; ratified by requester under sole-owner default.
- **P1 (5/5 fixed):**
  1. Make `$` expansion (`Makefile:12`) -> deleted `AFFECTED_ARGS` and `CCL_SKILL_SELECTED_DEFAULT_BASE` (`test_makefile_literal_recipes_preserve_dollar_and_avoid_make_arg_expansion`).
  2. Bind Make fallback to `Makefile` (`select-affected-tests.py:1579`) -> emitted `["make", "-f", "Makefile", <target>]` and rejected uncontained/non-regular `Makefile`, `GNUmakefile`, or `makefile`.
  3. Non-test scripts in fallback recipes (`select-affected-tests.py:1614`) -> added `makefile_recipe_paths()` checking all repo-local scripts/modules referenced in `Makefile` recipes.
  4. Queued parallel suite containment (`select-affected-tests.py:1765`) -> replaced upfront batch check with `_run_parallel_suites_bounded`, checking `_verify_contained_regular_file` right when each worker slot opens.
  5. Reachable termination escalation (`select-affected-tests.py:1673`) -> replaced unbounded `proc.wait()` with `0.03s` polling and `_escalate_and_reap` checking both `proc.returncode` and `_pgid_has_live_members(pgid)` before sending `SIGKILL` (`test_sigterm_cancellation_escalates_on_term_ignoring_child_and_descendant`).
- **P2 (13/13 fixed):**
  6. Child-launch signal window (`select-affected-tests.py:1646`) -> installed signal handlers before `subprocess.Popen` and immediately signaled/escalated if a signal arrived during launch.
  7. Planner FIFO/file validation (`select-affected-tests.py:381`) -> added `_read_contained_regular_bytes` (`_classify_suite_path` + `O_RDONLY | O_NOFOLLOW | O_NONBLOCK` + `fstat` `S_ISREG`) for `Makefile`, `test_check_ccl_regressions.sh`, and Python AST inspection.
  8. Disable `core.fsmonitor` in discovery (`select-affected-tests.py:607`) -> passed `-c core.fsmonitor=false -c core.hooksPath=/dev/null` in `_git_bytes`.
  9. Preserve `safe.directory` trust in child env (`select-affected-tests.py:233`) -> wrote isolated `tpl_dir / "gitconfig"` with `safe.directory = <repo_root.resolve()>` for child `GIT_CONFIG_GLOBAL` and `--dry-run`.
  10. Exact auto-base ref match (`select-affected-tests.py:679`) -> checked `line == os.fsencode(ref)` on `git for-each-ref --format=%(refname)` output so descendant refs (`origin/ns/topic`) do not match `origin/ns`.
  11. Broken loose ref hard error (`select-affected-tests.py:683`) -> raised `BaseRefError` (`exit 2`) on `for-each-ref` `stderr` output or when `git rev-parse --git-path <ref>` exists as a non-directory file while `for-each-ref` omits it.
  12. Compare index against captured `head_sha` (`select-affected-tests.py:833`) -> passed `head_sha` to `git diff --cached ... <head_sha> --`.
  13. Pass captured `head_sha` to metadata gate (`select-affected-tests.py:1063`) -> passed `--head-ref <head_sha>` to `shared_git_surface_gate.py`.
  14. Recheck `pytest` operands across all directories (`select-affected-tests.py:1619`) -> generalized `_verify_command_containment` across `pytest`, `unittest`, `python3`, `bash`, `ruby`, `env`, `npm`, and `make`.
  15. Validate executable paths before `--dry-run` (`select-affected-tests.py:1854`) -> ran `_verify_command_containment(..., allow_missing=True)` (plus `run-parallel-suites.sh` check) in `build_test_plan` so escaping gate scripts set `unsafe_blocked = True`.
  16. Stop replayed plans on first failure (`select-affected-tests.py:1836`) -> emitted `set -euo pipefail` as the first executable line in `print_dry_run` and tested with plain `bash -c`.
  17. Verify Python `__main__` guard invokes a runner (`select-affected-tests.py:337`) -> added `_block_invokes_runner` requiring a runner call or `raise` inside `if __name__ == "__main__":`.
  18. Dotted `eval.*` unittest drift detection (`select-affected-tests.py:1461`) -> recorded `eval.test_*` tokens as `eval/test_*.py` in `makefile_suites()`.
- **P3 (1/1 fixed):**
  19. Encoding-independent `--json` (`select-affected-tests.py:1963`) -> switched `json.dumps` to `ensure_ascii=True` and tested under `PYTHONIOENCODING=ascii`.

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
| Bijective raw-byte encoding, cached `head_sha`, & ASCII JSON | replace `_JSON_BYTES_PREFIX` hex encoder with `backslashreplace` | `test_git_changed_file_discovery_special_names_cached_head_ascii_json_and_raw_bytes` |
| Exact auto-ref match, broken loose ref hard error, & `--files` env base | `any(line == ref_bytes ...)` -> `bool(proc.stdout.strip())` | `test_base_resolution_exact_ref_broken_loose_ref_shadow_unrelated_and_files_env` |
| Pinned base/head SHAs & child `safe.directory` trust | `env["CCL_SKILL_BASE_REF"] = resolved_base` -> `pass` | `test_resolved_base_snapshot_reaches_child_subprocess_and_strips_overrides` |
| Discovery `core.fsmonitor=false` & child Git/hook isolation | `"core.fsmonitor=false"` -> `"core.bare=false"` | `test_git_isolation_disables_fsmonitor_and_isolates_child_templates_and_global_hooks` |
| `--repo` validation in `--files` mode, missing `git`, & trailing `\r` | bypass `rev-parse --show-toplevel` non-zero check | `test_repo_root_validation_broken_git_missing_git_binary_and_trailing_cr` |
| FIFO guard, `-f Makefile`, recipe scripts, per-slot parallel, pytest, & preview containment | `if not _verify_contained_regular_file(repo_root, suite):` -> `if False:` | `test_containment_fifo_gnumakefile_recipe_scripts_queued_parallel_pytest_and_dry_run` |
| Literal suite path existence guard | inject nonexistent suite path literal | `test_every_literal_suite_path_in_selector_exists` |
| Executable `Makefile` recipe parser, dotted `eval.*` drift, & `-f Makefile` fallback | remove `_EVAL_MODULE_RE` registration in `makefile_suites` | `test_makefile_recipe_parser_dotted_eval_drift_and_spaced_tmpdir_fallback` |
| `Makefile` literal recipes avoid Make variable/argument expansion | reintroduce `$(AFFECTED_ARGS)` in `Makefile` | `test_makefile_literal_recipes_preserve_dollar_and_avoid_make_arg_expansion` |
| AST pytest check requires runner call inside `__main__` | remove `and _block_invokes_runner(node.body)` | `test_pytest_style_suite_with_module_setup_or_print_only_main_dispatches_via_pytest` |
| Stopped Docker daemon marks `verify-sandbox` skipped | `_docker_daemon_ready()` returns `True` unconditionally | `test_stopped_docker_daemon_records_verify_sandbox_skip` |
| Rename reports both old and new paths | drop `--no-renames` from `git diff` | `test_rename_reports_both_old_and_new_paths` |
| `SIGTERM` escalates to `SIGKILL` on TERM-ignoring leader and descendant | `os.killpg(pgid, signal.SIGKILL)` -> `pass` | `test_sigterm_cancellation_escalates_on_term_ignoring_child_and_descendant` |
| `set -euo pipefail` replay stop-on-error, ANSI scrubbing, & `BrokenPipeError` | `print("set -euo pipefail")` -> `pass` | `test_json_dry_run_replay_stop_on_error_ansi_escape_exit_codes_and_broken_pipe` |

## Security first pass (`security-first-pass-only`)

Read-only triage of the selector's input and execution boundaries (not a dedicated security audit):

- `Makefile` uses literal zero-expansion recipes (`AFFECTED_ARGS` and `CCL_SKILL_SELECTED_DEFAULT_BASE` removed).
- `verify_repo_root` enforces `.git` presence and `git rev-parse --show-toplevel == root.resolve()` across all modes.
- Discovery disables `core.fsmonitor` and `core.hooksPath` while stripping `GIT_REPOSITORY_ROUTING_ENV` and `GIT_CONFIG*`; child execution isolates `GIT_TEMPLATE_DIR` and `GIT_CONFIG_GLOBAL` while preserving `safe.directory = <repo_root.resolve()>`.
- Base refs reject leading `-`, require exact `for-each-ref` matches, fail closed on broken loose or non-commit refs, and bind `diff --cached`, `git diff --check`, `shared_git_surface_gate.py --base-ref ... --head-ref ...`, and child `CCL_SKILL_BASE_REF` to pinned commit SHAs.
- `_read_contained_regular_bytes`, `_verify_contained_regular_file`, `_verify_command_containment`, `makefile_recipe_paths`, and `_run_parallel_suites_bounded` block FIFOs and uncontained symlinks across planning, `--dry-run`, `make -f Makefile`, serial commands, and per-slot parallel suite launch (userspace verification before `execve`, not kernel-race-proof against simultaneous `renameat2`).
- `_terminal_safe`, `_shell_quote`, `set -euo pipefail`, and `ensure_ascii=True` + `encode_json_str` neutralize ANSI/control sequences while keeping JSON and Bash previews reversible and encoding-safe.

## Document closeout (`tighten-doc`)

- **Surface reread:** Full reread of `specs/test-affected/plan.md`, `specs/test-affected/evidence/validation.md`, `docs/CONTRIBUTING.md`, and `Makefile` help lines (`closeout-reread.md`).
- **Touched blocks:** Charter, Behavior, Security four questions, Implementation boundary, Test-case register, Objective closure / Recurring-finding design checks / Structural minimality, C1 behavioral baseline & dispositions, Mutation walk, and Security first pass.
- **Whole-card / family trigger:** Standalone feature spec + validation pair (not a multi-card standards family); both documents reread end-to-end.
- **Defects found & fixed:** Removed stale `AFFECTED_ARGS` and `CCL_SKILL_SELECTED_DEFAULT_BASE` references from present-tense Behavior and Security sections after deleting those variables; verified every technical assertion (`make -f Makefile`, `--head-ref`, `core.fsmonitor=false`, `safe.directory`, `set -euo pipefail`, `ensure_ascii=True`, `\x00hex:`) against `Makefile` and `scripts/select-affected-tests.py`; confirmed zero contributor/path/session tokens and zero unresolved links.
- **Scope note:** `docs/CONTRIBUTING.md` (line 78) and `Makefile` help lines re-checked in context for register consistency and unchanged accuracy.

## Implementer self-review (persisted before delta `code-review --mode review`)

- **Acceptance criteria rechecked:** All findings across `design-review-D2.json`, `review-R1.json`, `review-R2.json` (33 findings), and `challenge-C1.json` (19 findings: 5 P1, 13 P2, 1 P3) verified against `Makefile`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `docs/CONTRIBUTING.md`, and `specs/test-affected/plan.md`.
- **Changed-file scope vs active plan (`origin/main..HEAD`):** `Makefile`, `docs/CONTRIBUTING.md`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `specs/test-affected/plan.md`, and `specs/test-affected/evidence/` (`review-R1.json`, `design-review-D1.json`, `design-review-D2.json`, `review-R2.json`, `challenge-C1.json`, `validation.md`). Matches `specs/test-affected/plan.md` Target-output map 1:1.
- **Load-bearing invariants & edge/failure paths checked:**
  1. Literal `Makefile` recipes with `AFFECTED_ARGS` deleted (`recurring_findings_design_check` `delete`).
  2. Exact auto-base ref matching, broken-loose-ref fail-closed handling, and end-to-end `resolved_base_sha` + `head_sha` pinning.
  3. Discovery `core.fsmonitor=false` isolation + child `GIT_CONFIG_GLOBAL` `safe.directory` preservation.
  4. Non-blocking regular-file containment across planning, `--dry-run` (`set -euo pipefail`), `make -f Makefile` + `makefile_recipe_paths()`, general `pytest`/script operands, and per-slot `_run_parallel_suites_bounded` launch, plus pre-`Popen` signal handling and reachable `SIGKILL` group escalation.
- **Named regression test (RED before, GREEN after):** `python3 -W error scripts/test_select_affected_tests.py` (`9 failures, 2 errors` on `480095d` -> `22/22 OK` on candidate; `22/22` applied mutations killed).
- **Known residual risks:** Selection remains heuristic by design (advisory inner-loop aid, not a sound dependency graph), and userspace regular-file checks before `execve` do not guard against simultaneous kernel-level `renameat2` swaps; `AGENTS.md` and CI continue to require `make test` and touched focused suites before landing.
