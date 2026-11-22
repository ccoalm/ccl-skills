# Validation: Affected-Test Selector for the Inner Loop

All unit and mutation-walk runs use isolated `tempfile.TemporaryDirectory()` workspaces and scrubbed Git environments (`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, empty `GIT_TEMPLATE_DIR`).

## Behavioral evidence (`RED-baseline`, constructed scenarios against `b9a3366`)

Running the expanded 19-test suite in `scripts/test_select_affected_tests.py` against `b9a3366` before editing `scripts/select-affected-tests.py` exited `1` (`FAILED (failures=12, errors=3)`):

| ID | Probe | Baseline (`b9a3366`) | Candidate |
| --- | --- | --- | --- |
| T1 | Empty-tree commit ahead of base (`has_candidate_commits=True`) | `TypeError` / skipped `shared_git_surface_gate.py` | schedules `shared_git_surface_gate.py --repo . --base-ref refs/remotes/origin/main` |
| T2 | Local `refs/heads/origin/main` shadow, option-shaped `--base-ref=--independent`, typo `CCL_SKILL_BASE_REF`, unrelated `origin/dev`, `upstream/dev`, no-base | resolved local `origin/main` / `main` / `HEAD~1` or accepted flag | resolves `refs/remotes/origin/main` / `refs/remotes/upstream/dev`; rejects invalid/missing bases with exit `2` |
| T3 | Base forwarding to `shared_git_surface_gate.py` and child `CCL_SKILL_BASE_REF` | hardcoded `--default-base-ref origin/dev` | forwards `--base-ref <resolved>` and `CCL_SKILL_BASE_REF=<resolved>`; strips `CCL_SKILL_DEFAULT_BASE_REF` and `MAKEFLAGS` |
| T4 | Inherited `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_SHALLOW_FILE`, `GIT_CONFIG*`, and `GIT_TEMPLATE_DIR` | leaked into discovery and child execution | scrubbed across discovery, `_run_cmd`, and test fixtures |
| T5 | `--repo <non-git>`, `--repo <subdir>`, and corrupt `.git/index` | exited `0` with empty plan | exits `2` with empty stdout |
| T6 | UTF-8, space, literal backslash, raw non-UTF-8 byte filenames, and renames | C-quoted / rewrote `\` to `/` | read via `-z` + `os.fsdecode` and preserved verbatim; JSON-safe encoding verified |
| T7 | Symlinked suite escaping `--repo` and `--files ../test_outside.sh` | followed symlink outside checkout | skipped with `unsafe-suite-path` / `unsafe-input-path` note; never executed |
| T8 | Deleted suite retained in `Makefile`; `test_review_gate_abort_leak.sh` self-edit; pytest-style module without `__main__`; stopped Docker daemon | filtered missing suite before drift check; placed abort-leak and pytest module into `parallel_suites` (exiting `0` on failing test); `which("docker")` ignored stopped daemon | triggers `selector-drift` fallback; keeps abort-leak serial/skipped; dispatches `__main__`-less `.py` via `python3 -m pytest -q` (exits non-zero on failure); marks `verify-sandbox` skipped when `docker info` fails |
| T9 | `--json`, `--dry-run`, preflight abort, exit codes (`7`, `127`, `143`, `1`), advisory footer, `BrokenPipeError` | lacked `advisory` JSON field and footer; unescaped multiline comments; crashed on missing binary / negative signal rc | single-doc JSON; shell-quoted `--dry-run` with escaped comments and `--jobs`; `advisory: run make test before push` on all `--run` exits; `BrokenPipeError` exits `141` cleanly |

## Applied killing-mutation walk

Executed in an isolated copy of the worktree (`19/19` mutants killed by their owning assertions; restored control passed `19/19`):

| Protected property | Applied mutation | Killing test |
| --- | --- | --- |
| Empty-commit metadata preflight | `if has_candidate_commits:` -> `if False:` | `test_clean_changeset_selects_nothing_and_empty_commit_runs_metadata_gate` |
| Pure skill Markdown skips `code-review` shards | `if skill_name == "code-review":` -> `if True:` | `test_pure_skill_markdown_skips_heavy_code_review_and_hook_suites` |
| Narrow hook change selects only target suite | `if path in HOOK_FILE_MAP:` -> `if False:` | `test_narrow_hook_change_selects_only_target_hook_suite` |
| Shared hook helper fanout | remove `test_guard_edit_isolation.sh` from `HOOK_FILE_MAP["hooks/host-input.py"]` | `test_shared_hook_helper_fans_out_to_dependent_hook_suites` |
| Abort-leak excluded from parallel self-selection | remove `test_review_gate_abort_leak.sh` from `DEDICATED_RUNNER_SUITES` | `test_code_review_leaf_script_core_fanout_and_legacy_path` |
| Antigravity manifest tracks `npm_required` | remove `.antigravity-plugin/` from package prefix tuple | `test_package_and_antigravity_surfaces_track_npm_checks` |
| CI/Makefile change selects spec-reference suite | replace `add_suite("scripts/test_check_spec_references.py")` with `pass` | `test_ci_and_makefile_select_binding_and_spec_guards` |
| NUL-delimited discovery preserves literal backslashes | add `.replace("\\", "/")` after `os.fsdecode` | `test_git_changed_file_discovery_unions_branch_staged_unstaged_untracked_and_special_names` |
| Auto-ref canonicalization prevents local `origin/main` shadow | `_canonicalize_auto_ref` returns raw `ref` instead of `refs/remotes/{ref}` | `test_base_resolution_precedence_shadow_unrelated_upstream_and_missing` |
| Resolved base reaches `shared_git_surface_gate.py` | pass `--default-base-ref` instead of `--base-ref` | `test_resolved_base_reaches_gates_and_child_env_strips_overrides` |
| Child execution strips `GIT_INDEX_FILE` | remove `"GIT_INDEX_FILE"` from `GIT_REPOSITORY_ROUTING_ENV` | `test_git_isolation_covers_discovery_child_execution_and_fixture_templates` |
| `--repo` worktree-root validation | bypass `.git` and `toplevel != root` checks | `test_repo_root_validation_and_corrupt_index_fail_closed` |
| Symlink containment check | bypass `resolved.relative_to(root_real)` | `test_containment_blocks_symlinks_and_parent_traversal` |
| Literal suite path existence guard | inject nonexistent suite path literal | `test_every_literal_suite_path_in_selector_exists` |
| Missing Makefile registration triggers drift | replace `self.missing_suites.append(rel_suite)` with `pass` | `test_hook_fallback_covers_makefile_and_missing_makefile_entry_triggers_drift_end_to_end` |
| Pytest-style suite without `__main__` runs via `pytest` | disable `_python_suite_has_main_entrypoint` check | `test_pytest_style_suite_without_main_dispatches_via_pytest_and_fails_on_red_assertion` |
| Stopped Docker daemon marks `verify-sandbox` skipped | `_docker_daemon_ready()` returns `True` unconditionally | `test_stopped_docker_daemon_records_verify_sandbox_skip` |
| Rename reports both old and new paths | drop `--no-renames` from `git diff` | `test_rename_reports_both_old_and_new_paths` |
| Advisory footer on execution and JSON | replace `ADVISORY_FOOTER` with `select_affected_tests_ok` | `test_json_dry_run_execution_phases_exit_codes_and_advisory_footer` |

## Security first pass (`security-first-pass-only`)

Read-only triage of the selector's input and execution boundaries (not a dedicated security audit):

- `--repo` requires `.git` at the root and `git rev-parse --show-toplevel == root.resolve()`.
- All Git discovery and child suite subprocesses strip `GIT_REPOSITORY_ROUTING_ENV`, `GIT_CONFIG_ROUTING_ENV`, `GIT_CONFIG_KEY_*`, and `GIT_CONFIG_VALUE_*`.
- Explicit and default base refs reject leading `-` before reaching Git argv; automatic short `<remote>/<branch>` refs canonicalize to `refs/remotes/<remote>/<branch>`.
- Candidate suite paths reject `/`, `..`, NUL bytes, broken symlinks, and symlinks resolving outside `repo_root.resolve()`.
- `--dry-run` escapes `\`, `\n`, `\r`, and `\0` in `#` comment lines and formats commands with `shlex.join`.

## Document closeout (`tighten-doc`)

Mode: `Tighten` + closeout reread across `specs/test-affected/plan.md`, `specs/test-affected/evidence/validation.md`, `docs/CONTRIBUTING.md`, and `Makefile` help lines. Verified: zero contributor/session provenance tokens, zero unresolved internal links or spec citations, present-tense invariants throughout, and trailing whitespace / EOF blank lines clean.

## Implementer self-review (persisted before independent `code-review`)

- **Acceptance criteria rechecked:** All 6 P1 and 15 P2 items from `specs/test-affected/evidence/design-review-D2.json` plus applicable `specs/test-affected/evidence/review-R1.json` items verified against `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `Makefile`, `docs/CONTRIBUTING.md`, and `specs/test-affected/plan.md`.
- **Changed-file scope vs active plan (`origin/main..HEAD`):** `Makefile`, `docs/CONTRIBUTING.md`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `specs/test-affected/plan.md`, and `specs/test-affected/evidence/` (`review-R1.json`, `design-review-D1.json`, `design-review-D2.json`, `validation.md`). Matches `specs/test-affected/plan.md` Target-output map 1:1.
- **Load-bearing invariants & edge/failure paths checked:**
  1. Advisory-only output invariant: `--run` always terminates with `advisory: run make test before push`, `--dry-run` with `# advisory: run make test before push`, and `--json` with parseable single-object JSON containing `"advisory"`.
  2. Git isolation invariant: no inherited `GIT_*` routing/graph/config env var reaches discovery, child suites, or writable test fixtures.
  3. Checkout containment invariant: no symlink or relative path escaping `repo_root` enters `parallel_suites` or `serial_commands`.
  4. Non-silent discovery & runner invariant: non-zero Git exit codes return exit `2`, `__main__`-less `.py` suites run via `pytest -q` instead of bare `python3`, and Docker daemon probe carries a 5-second timeout.
- **Named regression test (RED before, GREEN after):** `python3 scripts/test_select_affected_tests.py` (`12 failures, 3 errors` on `b9a3366` -> `19/19 OK` on candidate; `19/19` applied mutations killed).
- **Deterministic gates run:** `make test-affected-plan`, `make test-affected` (including `git diff --check`, `check-ccl-skills.sh`, `shared_git_surface_gate.py`, `check-agent-contract-coverage.sh`, `test_check_spec_references.py`, `test_ci_checkout_ref_binding.sh`, `test_lane_isolation.py`, `test_run_parallel_suites.sh`, `test_select_affected_tests.py`, `check-markdown-links.py`, `check-spec-references.py`, `doc-lint-repo.py`, `check-public-sanitization.py`).
- **Known residual risks:** Selection remains heuristic by design (advisory inner-loop aid, not a sound dependency graph); `AGENTS.md` and CI continue to require `make test` and touched focused suites before landing.
