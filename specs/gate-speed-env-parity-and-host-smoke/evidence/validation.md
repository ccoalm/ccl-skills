# Validation Evidence — Gate Speed, Git Env / Repo Hygiene Guards, and Four-Host Smoke

Status: local verification complete; independent review/challenge pending execution on committed candidate.

## 1. Behavioral Evidence (`RED-baseline` — Constructed Scenarios Run Before and After Fix)

- **Status**: `RED-baseline`
- **Provenance type**: Constructed scenarios executed against the unpatched `origin/main` (`e8ad14af56c8`) baseline first (observed RED) and re-run after applying `A1`–`A5` (observed GREEN):
  - **`T1` (`skills/skill-extraction-workflow/scripts/test_check_ccl_route_drift.sh`)**:
    - *Without change*: `FAIL: expected output to contain: definitely-missing-first.md` — `md_reference_check` exited `0` on `agent-context/session-start.md` when a line cited `` `skills/product-rd-workflow/references/definitely-missing-first.md` `` followed by an existing `` `skills/product-rd-workflow/references/delivery-lifecycle.md` `` token because greedy `sed` `.*` matched only the last citation.
    - *With change*: `test_check_ccl_route_drift: ok` (exit `0`), emitting `md_reference_block:`, `definitely-missing-first.md`, and `sync_reference_blocking_failed` on the broken multi-citation case while preserving all 4 historical `source-register.md` SHA-256 waivers and colon-in-`$root` resolution.
  - **`T2` (`scripts/test_check_public_sanitization.py`, `test_check_markdown_links.py`, `test_check_spec_references.py`)**:
    - *Without change*: `FileNotFoundError: _repo_text.py` when importing shared `display()` before `_repo_text.py` landed.
    - *With change*: `public_sanitization_test_ok`, `test_check_markdown_links.py` (`3/3 OK`), `test_check_spec_references.py` (`79/79 OK`, with `WaivedPathPresenceTest.clone_candidate()` copying `_repo_text.py` beside `check-spec-references.py`). Differential check across all 2,795 tracked files confirmed `identical=True` (`0` finding drift).
  - **`T3` (`scripts/check-repo-hygiene.py` + `scripts/test_check_repo_hygiene.py`)**:
    - *Without change*: `python3 scripts/check-repo-hygiene.py .` exited `1` (`repo_hygiene_failed`) with 12 findings on unpatched `e8ad14af56c8` (`GIT_REPOSITORY_ROUTING_ENV` / `GIT_CONFIG_ROUTING_ENV` divergence across `select-affected-tests.py`, `review_gate.py`, and `shared_git_surface_gate.py`, plus 3 inline `def display` copies).
    - *With change*: `repo_hygiene_ok` (`0.678s`, exit `0`), `test_check_repo_hygiene.py` (`6/6 OK`), `test_select_affected_tests.py` (`24/24 OK`), and `test_lane_isolation.py` (`lane_isolation_ok: 112 lane members, 83 reviewed exception(s), 0 unreviewed`).
  - **`T4` & `T5` (`packages/ccl-skills-npm/test/host-smoke.test.mjs` & `test/basic.test.mjs`)**:
    - *Without change*: `host-smoke.sh` failed to exit `4` when `agy` was absent, leaked caller `XDG_CONFIG_HOME` into `opencode`, copied untracked workspace files via `cp -R`, and omitted `--host antigravity` smoke stages.
    - *With change*: `host-smoke.test.mjs` (`2/2 pass`), full `npm test` (`449` tests: `446 pass`, `0 fail`, `3 skipped` Darwin-only `launchd` cases on Linux), `npm run test:pack` (`11/11 pass`), and live `npm run smoke:host` against real `codex`, `claude`, `opencode`, and `agy` CLIs exited `0` with `{"status":"four-host-smoke-passed","codexHooks":"native-plugin-registered","openCodeHooks":"plugin-registered","openCodeSharedFiles":"retained","antigravityPlugin":"native-plugin-registered"}`.

## 2. Wall-Clock Gate Latency Measurements (`e8ad14af56c8` Baseline vs Candidate)

| Gate | Baseline (`e8ad14af56c8`) | Candidate | Delta |
| --- | --- | --- | --- |
| `md_reference_check` isolated scan (924 lines) | `4.66s` | `<0.10s` | `-4.56s` per invocation |
| Full `check-ccl-skills.sh` (including private R0 audit) | `~9.50s` | `5.11s` | `-4.39s` |
| `python3 scripts/check-public-sanitization.py .` (2,795 tracked files) | `4.96s` | `0.70s` | `-4.26s` |
| `python3 scripts/check-repo-hygiene.py .` (new 4-check gate) | n/a | `0.68s` | `+0.68s` |

## 3. Applied Differential Killing-Mutation Walk (14/14 Mutants Killed in Isolated Temp Copies)

Every named test property across `A1`–`A4` was mutated in disposable `tempfile.TemporaryDirectory()` copies outside the worktree (zero worktree dirtying), confirming unmutated control GREEN (`exit 0`) and mutated target RED (`nonzero`) for the exact owning assertion:

| Mutant ID | Mutated target & broken invariant | Owning suite | Differential failure observed |
| --- | --- | --- | --- |
| `M1_md_ref_last_only` | `check-ccl-skills.sh`: check only `matches.last` instead of all `.scan` matches | `test_check_ccl_route_drift.sh` | `exit 1`: `FAIL: expected multi-ref broken first citation to emit md_reference_block` |
| `M2a_splitlines_offset` | `check-public-sanitization.py`: `content.splitlines()` instead of `content.split("\n")` | `test_check_public_sanitization.py` | `exit 1`: `AssertionError` on `\v`/`\f`/`\x85` line-number parity |
| `M2b_drop_git_ssh_exempt` | `check-public-sanitization.py`: skip `GIT_SSH_RE` span exemption | `test_check_public_sanitization.py` | `exit 1`: `AssertionError` (SSH Git transport `git@example.com:org/repo.git` falsely flagged as `email`) |
| `M2c_inline_display` | `check-public-sanitization.py`: re-introduce local `def display` | `test_check_repo_hygiene.py` | `exit 1`: `defines inline display() instead of using scripts/_repo_text.py` |
| `M2d_clone_missing_helper` | `test_check_spec_references.py`: omit `_repo_text.py` in `clone_candidate()` | `test_check_spec_references.py` | `exit 1`: `ModuleNotFoundError: No module named '_repo_text'` |
| `M2e_whole_line_git_ssh` | `check-public-sanitization.py`: `continue` whole line when `GIT_SSH_RE` matches | `test_check_public_sanitization.py` | `exit 1`: `AssertionError` (missed private email sharing a line with valid SSH URL) |
| `M3a_git_env_drift` | `review_gate.py`: drop `"GIT_EXTERNAL_DIFF"` from `GIT_REPOSITORY_ROUTING_ENV` | `check-repo-hygiene.py` | `exit 1`: `missing keys ['GIT_EXTERNAL_DIFF']` |
| `M3b_skip_orphan_test_scan` | `check-repo-hygiene.py`: skip `test_*.py` registration check | `test_check_repo_hygiene.py` | `exit 1`: `AssertionError` in `test_flags_unregistered_test_and_unreachable_makefile_target` |
| `M3c_accept_dead_make_target` | `check-repo-hygiene.py`: scan all `Makefile` lines instead of `test` target closure | `test_check_repo_hygiene.py` | `exit 1`: `AssertionError` (`scripts/test_dead_target.py` not flagged) |
| `M3d_ignore_py_warnings` | `check-repo-hygiene.py`: `"ignore"` instead of `"error"` in `warnings.simplefilter` | `test_check_repo_hygiene.py` | `exit 1`: `AssertionError` in `test_flags_python_escape_warning_and_unsealed_eval_evidence` |
| `M3e_blanket_eval_exempt` | `check-repo-hygiene.py`: spare all `eval/evidence/` `.py` without `MANIFEST.json` SHA-256 check | `test_check_repo_hygiene.py` | `exit 1`: `AssertionError` (tampered `recompute-aggregates.py` not flagged) |
| `M4a_drop_agy_check` | `host-smoke.sh`: omit `agy` from required host loop | `host-smoke.test.mjs` | `exit 1`: `AssertionError [ERR_ASSERTION]: Expected values to be strictly equal: 1 !== 4` |
| `M4b_leak_xdg_config` | `host-smoke.sh`: omit `XDG_CONFIG_HOME` override | `host-smoke.test.mjs` | `exit 1`: `poisoned XDG_CONFIG_HOME was mutated` / `opencode` read caller XDG dir |
| `M4c_copy_untracked` | `host-smoke.sh`: `git ls-files --cached --others` instead of `--stage` tracked-only | `host-smoke.test.mjs` | `exit 1`: `untracked root file leaked into v1 source` |

Oracle dimensions crossed (`testing-strategy` closed-contract check): **shape** (multi-token backtick lines, control/newline chars, AST tuple literals), **provenance** (`git ls-files --stage` tracked vs untracked, `MANIFEST.json` SHA-256 seal vs tampered file), **cardinality** (1 vs 2+ citations per line; 23+7+2 Git env entries; 4 CLI hosts; capped `<=4` delegate and `<=2` opt-in maps), **semantics** (span-level `GIT_SSH_RE` exemption vs whole-line skip; reachable `Makefile` `test` closure vs dead target), and **ordering** (`v1` install → source switch → `v2` update → `doctor` → `uninstall`).

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
  - First-pass triage summary: verified all 30 Git routing/config/diff/pathspec/replace env keys + 2 `GIT_CONFIG_*` prefixes are scrubbed identically across `select-affected-tests.py`, `review_gate.py`, and `shared_git_surface_gate.py` and guarded by AST parity in `check-repo-hygiene.py`; verified `host-smoke.sh` confines `HOME`, `CODEX_HOME`, and `XDG_*_HOME` under `mktemp -d`, scrubs `OPENCODE_CONFIG*`/`CCL_SKILLS_REPO`/`CLAUDE_*`/`GIT_*`, and stages only `100644`/`100755` tracked git entries; verified `MANIFEST.json` SHA-256 integrity check rejects unsealed or modified `eval/evidence/` `.py` files. Residual risk: `check-repo-hygiene.py` enforces static AST/compile/registration invariants on tracked files and does not replace runtime sandboxing; no professional security audit was performed.
- **`tighten-doc` closeout reread evidence (`references/closeout-reread.md`)**:
  - Surfaces reread: `AGENTS.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/CONTRIBUTING.md`, `packages/ccl-skills-npm/scripts/AGENTS.md`, `packages/ccl-skills-npm/src/AGENTS.md`, `specs/gate-speed-env-parity-and-host-smoke/plan.md`, and this `validation.md`.
  - Scope scanned: every modified/added block plus its enclosing section and cross-doc `三端`/`四端` host references (`packages/ccl-skills-npm/README.md` also checked for consistency); family-wide standards trigger: not triggered (standalone contributor/architecture/contract docs, not an R&D standards card family).
  - Defects found & fixed during reread: removed cross-bullet repetition of "never recursively copying..." between bullets 1 and 5 in `packages/ccl-skills-npm/scripts/AGENTS.md` and compressed duplicated prose tables in `plan.md` while preserving 100% of decided points; zero register drift or meta-narration remaining; `doc-lint-repo.py` (`0 ERROR`) and `check-markdown-links.py` (`markdown_link_check_ok`) passed.

## 5. Dual-Track Independent Review & Adversarial Challenge

Pending execution on committed candidate (to be populated with controller JSON receipts, reviewed commit SHAs, R0 status, item-9 locator, dispositions, and post-review delta).
