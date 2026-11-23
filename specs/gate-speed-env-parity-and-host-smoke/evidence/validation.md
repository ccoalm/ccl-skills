# Validation Evidence — Gate Speed, Git Env / Repo Hygiene Guards, and Four-Host Smoke

Status: local verification complete; independent review/challenge receipts to be recorded on the landing candidate.

## 1. Behavioral Evidence (`RED-baseline` — Constructed Scenarios Run Before and After Fix)

- **Status**: `RED-baseline`
- **Provenance type**: Constructed scenarios executed against the unpatched `origin/main` (`e8ad14af56c8`) baseline first (observed RED) and re-run after applying `A1`–`A5` (observed GREEN):
  - **`T1` (`skills/skill-extraction-workflow/scripts/test_check_ccl_route_drift.sh`)**:
    - *Without change*: `FAIL: expected output to contain: definitely-missing-first.md` — `md_reference_check` exited `0` on `agent-context/session-start.md` when a line cited `` `requirement-doc-writer/references/definitely-missing-first.md` `` followed by an existing `` `requirement-doc-writer/references/requirement-closure-contract.md` `` token because greedy `sed` `.*` matched only the last citation.
    - *With change*: `test_check_ccl_route_drift: ok` (exit `0`), emitting `md_reference_block:`, `definitely-missing-first.md`, and `sync_reference_blocking_failed` on the broken multi-citation case (`(b2)`), failing closed on missing `ruby` (`rc=2`, `missing_required_command: ruby`) and non-zero `md_reference_check` Ruby scanner exit (`rc=1`, `md_reference_scan_error: ruby exited 127`, `(b3)`), and preserving all 4 historical `source-register.md` SHA-256 waivers and colon-in-`$root` resolution.
  - **`T2` (`scripts/test_check_public_sanitization.py`, `test_check_markdown_links.py`, `test_check_spec_references.py`)**:
    - *Without change*: `FileNotFoundError: _repo_text.py` when importing shared `display()` before `_repo_text.py` landed.
    - *With change*: `public_sanitization_test_ok`, `test_check_markdown_links.py` (`3/3 OK`), `test_check_spec_references.py` (`79/79 OK`, with `WaivedPathPresenceTest.clone_candidate()` copying `_repo_text.py` beside `check-spec-references.py`). Differential check across all tracked files confirmed `identical=True` (`0` finding drift).
  - **`T3` (`scripts/check-repo-hygiene.py` + `scripts/test_check_repo_hygiene.py`)**:
    - *Without change*: `python3 scripts/check-repo-hygiene.py .` exited `1` (`repo_hygiene_failed`) with 12 findings on unpatched `e8ad14af56c8` (`GIT_REPOSITORY_ROUTING_ENV` / `GIT_CONFIG_ROUTING_ENV` divergence across `select-affected-tests.py`, `review_gate.py`, and `shared_git_surface_gate.py`, plus inline `def display` copies).
    - *With change*: `repo_hygiene_ok` (`0.68s`, exit `0`), `test_check_repo_hygiene.py` (`6/6 OK`), `test_select_affected_tests.py` (`24/24 OK`), and `test_lane_isolation.py` (`lane_isolation_ok: 112 lane members, 83 reviewed exception(s), 0 unreviewed`).
  - **`T4` & `T5` (`packages/ccl-skills-npm/test/host-smoke.test.mjs` & `test/basic.test.mjs`)**:
    - *Without change*: `host-smoke.sh` failed to exit `4` when `agy` was absent, leaked caller `XDG_CONFIG_HOME` into `opencode`, copied untracked workspace files via `cp -R`, and omitted `--host antigravity` smoke stages.
    - *With change*: `host-smoke.test.mjs` (`2/2 pass`), full `npm test` (`449` tests: `446 pass`, `0 fail`, `3 skipped` Darwin-only `launchd` cases on Linux), `npm run test:pack` (`11/11 pass`), and live `npm run smoke:host` against real `codex`, `claude`, `opencode`, and `agy` CLIs exited `0` with `{"status":"four-host-smoke-passed","codexHooks":"native-plugin-registered","openCodeHooks":"plugin-registered","openCodeSharedFiles":"retained","antigravityPlugin":"native-plugin-registered"}`.

## 2. Wall-Clock Gate Latency Measurements (`e8ad14af56c8` Baseline vs Candidate)

| Gate | Baseline (`e8ad14af56c8`) | Candidate | Delta |
| --- | --- | --- | --- |
| `md_reference_check` isolated scan (924 lines) | `4.66s` | `<0.10s` | `-4.56s` per invocation |
| Full `check-ccl-skills.sh` (including private R0 audit) | `~9.50s` | `5.11s` | `-4.39s` |
| `python3 scripts/check-public-sanitization.py .` (tracked corpus) | `4.96s` | `0.70s` | `-4.26s` |
| `python3 scripts/check-repo-hygiene.py .` (new 4-check gate) | n/a | `0.68s` | `+0.68s` |

## 3. Applied Differential Killing-Mutation Walk (16/16 Mutants Killed in Isolated Temp Copies)

Every named test property across `A1`–`A4` was mutated in disposable `tempfile.TemporaryDirectory()` copies outside the worktree (zero worktree dirtying), confirming the unmutated control passed (or failed closed as expected on negative scanner probes) and each mutated target failed on its exact owning test/assertion:

| Mutant ID | Mutated target & broken invariant | Owning suite | Verbatim differential failure observed |
| --- | --- | --- | --- |
| `M1a_md_ref_last_only` | `check-ccl-skills.sh`: replace `match.scan(ref_re).flatten.uniq` with `[match.scan(ref_re).flatten.last].compact` | `check-ccl-skills.sh` multi-citation probe (`(b2)` fixture) | Control `rc=1` (`definitely-missing-first.md` flagged); mutant `rc=0` (broken first ref missed) |
| `M1b_md_ref_ruby_fail_closed` | `check-ccl-skills.sh`: replace `if [ "$md_ref_scan_rc" -ne 0 ]; then` with `if false; then` | `check-ccl-skills.sh` Ruby `rc=127` probe (`(b3)` fixture) | Control `rc=1` (`md_reference_scan_error: ruby exited 127`); mutant `rc=0` (silent pass) |
| `M2a_inline_display_override` | `check-public-sanitization.py`: replace `from _repo_text import display` with inline `def display` | `test_check_public_sanitization.py` | `AssertionError` on `assert module.display.__code__.co_filename == repo_text_mod.display.__code__.co_filename` |
| `M2b_drop_10_dot_prefilter` | `check-public-sanitization.py`: drop `"10." in line` from `IP_RE` line prefilter | `test_check_public_sanitization.py` | `AssertionError: private-ip unexpectedly passed` |
| `M2c_drop_email_prefilter` | `check-public-sanitization.py`: replace `if "@" in line:` with `if False:` | `test_check_public_sanitization.py` | `AssertionError: private-email unexpectedly passed` |
| `M2d_drop_url_prefilter` | `check-public-sanitization.py`: replace `if "://" in line:` with `if False:` | `test_check_public_sanitization.py` | `AssertionError: nel-before-private-url unexpectedly passed` |
| `M2e_whole_line_git_ssh_bypass` | `check-public-sanitization.py`: replace `if match.span() in git_identities:` with `if git_identities:` | `test_check_public_sanitization.py` | `AssertionError: git-ssh-plus-real-email-same-line unexpectedly passed` |
| `M2f_clone_missing_helper` | `test_check_spec_references.py`: omit `_repo_text.py` copy in `WaivedPathPresenceTest.clone_candidate()` | `test_check_spec_references.WaivedPathPresenceTest.test_control_waived_path_present_still_passes` | `ModuleNotFoundError: No module named '_repo_text'` |
| `M3a_git_env_parity` | `check-repo-hygiene.py`: early `return []` in `check_git_env_parity()` | `test_check_repo_hygiene.py` | Sole failure: `FAIL: test_git_env_parity_catches_missing_extra_and_unscrubbed_constants` |
| `M3b_display_sharing` | `check-repo-hygiene.py`: early `return []` in `check_display_sharing()` | `test_check_repo_hygiene.py` | Sole failure: `FAIL: test_display_sharing_catches_inline_duplicate_and_missing_import` |
| `M3c_test_registration` | `check-repo-hygiene.py`: early `return []` in `check_test_registration()` | `test_check_repo_hygiene.py` | Sole failure: `FAIL: test_registration_catches_orphan_tests_dead_makefile_targets_and_stale_delegates` |
| `M3d_python_warnings` | `check-repo-hygiene.py`: early `return []` in `check_python_warnings()` | `test_check_repo_hygiene.py` | Sole failure: `FAIL: test_python_warnings_catches_invalid_escape_and_tampered_manifest_archive` |
| `M3e_manifest_sha_verification` | `check-repo-hygiene.py`: skip all `eval/evidence/` `.py` without verifying `MANIFEST.json` SHA-256 | `test_check_repo_hygiene.py` | Sole failure: `FAIL: test_python_warnings_catches_invalid_escape_and_tampered_manifest_archive` |
| `M4a_missing_agy_guard` | `host-smoke.sh`: drop `command -v agy >/dev/null || { echo "agy missing" >&2; exit 4; }` | `host-smoke.test.mjs` | Failed test: `host-smoke fails closed with exit 4 when agy CLI is missing` |
| `M4b_xdg_config_home_leak` | `host-smoke.sh`: drop `export XDG_CONFIG_HOME="$tmp/home/.config"` | `host-smoke.test.mjs` | `AssertionError`: `XDG_CONFIG_HOME not isolated under HOME` |
| `M4c_omit_antigravity_lifecycle` | `host-smoke.sh`: exit `0` right before `stage=antigravity-install-v1` | `host-smoke.test.mjs` | `AssertionError`: `agy must be exercised by host-smoke.sh` |

Oracle dimensions crossed (`testing-strategy` closed-contract check): **shape** (multi-token backtick lines, `\v`/`\f`/`\x85` non-LF whitespace spans, AST tuple literals), **provenance** (`git ls-files --stage` tracked vs untracked, `MANIFEST.json` SHA-256 seal vs tampered file), **cardinality** (1 vs 2+ citations per line; 23+7+2 Git env entries; 4 shared-`display()` callers; 4 CLI hosts; capped `<=4` delegate and `<=2` opt-in maps), **semantics** (fail-closed `md_ref_scan_rc` check; span-level `GIT_SSH_RE` exemption vs whole-line skip; reachable `Makefile` `test` closure vs dead target), and **ordering** (`v1` install → source switch → `v2` update → `doctor` → `uninstall`).

## 4. Verification by Layer, Contract Sync, Security First-Pass, and `tighten-doc` Closeout

- **Verification by layer**:
  - `unit`: PASS (`test_check_public_sanitization.py`, `test_check_markdown_links.py` 3/3, `test_check_spec_references.py` 79/79, `test_check_repo_hygiene.py` 6/6, `test_select_affected_tests.py` 24/24, `basic.test.mjs`).
  - `integration/contract`: PASS (`test_check_ccl_route_drift.sh`, `host-smoke.test.mjs` 2/2, `npm test` 446 pass / 0 fail / 3 Darwin-only skipped, `npm run test:pack` 11/11, `select-affected-tests.py --run`, `CCL_BROAD_TEST_REASON=repo-required make test`, `test_check_ccl_regressions.sh --heavy-only`).
  - `E2E/host smoke`: PASS (`npm run smoke:host` exit `0` across real `codex`, `claude`, `opencode`, `agy` CLIs).
  - `manual/exploratory`: `not applicable` (deterministic CLI validators, non-interactive installer smoke script, and Markdown docs).
  - `build/static & R0`: PASS (`check-ccl-skills.sh` with private R0 audit → `r0_status=private-ok`, `ccl_skill_check_clean_ok`; `check-public-sanitization.py` → `public_sanitization_ok`; `check-repo-hygiene.py` → `repo_hygiene_ok`; `check-skill-count.py` → `skill_count_ok: 33`; `doc-lint-repo.py` → `0 ERROR`; `shared_git_surface_gate.py --base-ref origin/main` → `shared_git_surface_gate_ok`; `git diff --check` → exit `0`).
- **Spec / repo-contract sync evidence**:
  - Updated contract layer: root `AGENTS.md`, `packages/ccl-skills-npm/scripts/AGENTS.md`, `packages/ccl-skills-npm/src/AGENTS.md`, and `docs/CONTRIBUTING.md`.
  - Executable proof: `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce` → `agent contract coverage ok` (exit `0`); deferred adoption boundaries: none.
- **`security-review` gate record (`feature-risk-router`)**:
  - Gate status: `pending-dedicated-review` (`security-first-pass-only` inline read-only triage; sole accountable requester owns final merge decision).
  - First-pass triage summary: verified all 30 Git routing/config/diff/pathspec/replace env keys + 2 `GIT_CONFIG_*` prefixes are scrubbed identically across `select-affected-tests.py`, `review_gate.py`, and `shared_git_surface_gate.py` and guarded by AST parity in `check-repo-hygiene.py`; verified `md_reference_check` checks `md_ref_scan_rc` fail-closed; verified `host-smoke.sh` confines `HOME`, `CODEX_HOME`, and `XDG_*_HOME` under `mktemp -d`, scrubs `OPENCODE_CONFIG*`/`CCL_SKILLS_REPO`/`CLAUDE_*`/`GIT_*`, and stages only `100644`/`100755` tracked git entries; verified `MANIFEST.json` SHA-256 integrity check rejects unsealed or modified `eval/evidence/` `.py` files. Residual risk: `check-repo-hygiene.py` enforces static AST/compile/registration invariants on tracked files and does not replace runtime sandboxing; no professional security audit was performed.
- **`tighten-doc` closeout reread evidence (`references/closeout-reread.md`)**:
  - Surfaces reread: `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `packages/ccl-skills-npm/scripts/AGENTS.md`, `packages/ccl-skills-npm/src/AGENTS.md`, `specs/gate-speed-env-parity-and-host-smoke/plan.md`, and this `validation.md`.
  - Scope scanned: every modified/added block plus its enclosing section and cross-doc `三端`/`四端` host references (`packages/ccl-skills-npm/README.md` also checked for consistency); family-wide standards trigger: not triggered (standalone contributor/architecture/contract docs, not an R&D standards card family).
  - Defects found & fixed during reread: removed cross-bullet repetition in `packages/ccl-skills-npm/scripts/AGENTS.md`, compressed duplicated tables in `plan.md`, and aligned `0.70s` sanitization timing, 4-caller `_repo_text.display` coverage, and verbatim `run_mutation_walk.py` entries across `plan.md`, `source-register.md`, and `validation.md`; zero register drift or meta-narration remaining; `doc-lint-repo.py` (`0 ERROR`) and `check-markdown-links.py` (`markdown_link_check_ok`) passed.

## 5. Dual-Track Independent Review & Adversarial Challenge

Pending execution on committed candidate (to be populated with controller JSON receipts, reviewed commit SHAs, R0 status, item-9 locator, dispositions, and post-review delta).
