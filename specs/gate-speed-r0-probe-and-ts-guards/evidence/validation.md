# Validation Evidence — Gate Speed, Cross-Host R0 Probe, Parallel Repo Gates, and OpenCode Plugin Type/State Guards

## 1. RED-First Baseline Evidence (Observed Before Production Edits)

All nine registered behavioral scenarios (`T1`–`T9` in `specs/gate-speed-r0-probe-and-ts-guards/plan.md`) were executed against the pre-fix baseline (`origin/main` = `c05fb2868832042efbb183ad2fa13b7e479299d4`) and observed failing for their intended assertions:

| Case | Command | Pre-fix observed outcome |
| --- | --- | --- |
| `T1` | `bash skills/skill-extraction-workflow/scripts/test_check_evidence_card_leak_cache.sh` | `exit 1`: `--self-test-cached` unsupported (`Usage: ... [--self-test | --files <nul-list-file> | <file> ...]`), warm `check-ccl-skills.sh` still spawned `6` `git init` calls (`expected=0`), no `.ok` stamp created in `0700` cache dir, and ambient `CCL_SKILL_BASE_REF=HEAD` broke `self_test()` case `(v)` (`evidence_card_leak_self_test_failed: committed diff leaked path missed`). |
| `T2` | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_r0_status.sh` | `exit 1`: `alias_audit_unavailable` lacked cross-host `~/.<host>/.private-aliases/run-r0-audit.sh` remediation guidance. |
| `T3` | `python3 scripts/test_lane_isolation.py` | `exit 1`: `Makefile` `test-repo-gates` had `0` `run-parallel-suites.sh` suites (`expected >= 30`), and `skills/testing-strategy/scripts/{client-terminal-ansi-check,lang-basics-ast-check,lang-basics-go-check}.test.sh` had `3` unreviewed `fixed-tmp` hits (`base="${TMPDIR:-/tmp}"`). |
| `T4` | `python3 scripts/test_select_affected_tests.py` + `bash skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh` | `exit 1`: `scripts/test_check_public_sanitization.py` missing from `makefile_suites("test-repo-gates")`, `check-public-sanitization.py .` and `CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1` missing from `test-repo-gates`. |
| `T5` | `./packages/ccl-skills-npm/node_modules/.bin/tsc -p packages/opencode-plugin/tsconfig.json` | `exit 2`: `6× error TS18047: 'manifest' is possibly 'null'` at `packages/opencode-plugin/ccl-skills.ts:154-160`. |
| `T6` / `T7` | `node --test packages/ccl-skills-npm/test/opencode-hooks.test.mjs` | `exit 1`: omitted `callID` on `Skill` `before`/`after` failed to record native CCL `multi-agent-delegation` load (`delegation-owner guard blocked this subagent call`), because `before` keyed `pendingSkills` under `call-${Date.now()}` while `after` looked up `"unknown-call"`. |
| `T8` | `node --test packages/ccl-skills-npm/test/basic.test.mjs` + `(cd packages/ccl-skills-npm && rm -rf artifacts && node --test test/*.test.mjs)` | `exit 1`: `packages/ccl-skills-npm/package.json` contained tab indentation and omitted `Antigravity` / `"antigravity"`, and `node --test test/*.test.mjs` swept `test/pack.test.mjs` (`11` failures when `artifacts/` was absent). |
| `T9` | `bash skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh` | `exit 1`: `python3 -W error -m py_compile skills/testing-strategy/scripts/client-terminal-ansi-check.py` raised `SyntaxError: invalid escape sequence '\e'` at line 35. |

## 2. Behavioral Evidence Rows (`skill-extraction-workflow` Dual-Track Gate)

| Owner package | Status | Provenance type | Baseline (without change) vs compliance (with change) |
| --- | --- | --- | --- |
| `skills/skill-extraction-workflow` (`B2-1`, `B2-2`) | `RED-baseline` | Constructed scenario + measured baseline on `c05fb28` | **Without change**: `test_check_evidence_card_leak_cache.sh` exited `1` (`6` `git init` calls on warm `check-ccl-skills.sh`, ambient `CCL_SKILL_BASE_REF=HEAD` broke `self_test()` case `(v)`); `test_check_ccl_r0_status.sh` exited `1` (no sibling-host R0 hint on `alias_audit_unavailable`). **With change**: `test_check_evidence_card_leak_cache.sh` passes `12/12` (`0` warm `git init` calls, 1-byte invalidation, broken/skipped/symlink/`0777` cache bypass, `CCL_SKILL_BASE_REF=HEAD` isolation); `test_check_ccl_r0_status.sh` exits `0` while preserving `r0_status=public-fallback` and `ccl_skill_check_interim_ok`. |
| `skills/testing-strategy` (`B2-3`, `B2-4`) | `RED-baseline` | Constructed scenario + measured baseline on `c05fb28` | **Without change**: `python3 -W error -m py_compile skills/testing-strategy/scripts/client-terminal-ansi-check.py` exited `1` (`SyntaxError: invalid escape sequence '\e'` at line 35), and `test_lane_isolation.py` flagged `base="${TMPDIR:-/tmp}"` across three `testing-strategy` `.test.sh` scripts. **With change**: `client-terminal-ansi-check.test.sh`, `lang-basics-ast-check.test.sh`, `lang-basics-go-check.test.sh`, and `test_lane_isolation.py` exit `0` under `python3 -W error` and parallel `repo_gates`. |

## 3. Contract-Sync and First-Pass Security Triage

- **Contract-sync evidence**:
  - Updated contracts/docs: root `AGENTS.md` (verification section reflecting `check-public-sanitization.py` inside `make test`), `README.md`, `docs/CONTRIBUTING.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md` (`--self-test-cached` + `test_check_evidence_card_leak_cache.sh`), and `packages/opencode-plugin/AGENTS.md` (`tsconfig.json` strict typecheck + synthetic `callID` FIFO/bounds).
  - Coverage verifier: `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce` (`agent_contract_coverage_ok`).
  - Immutable archive exclusion: `eval/evidence/routing-new-tighten-vs-owner-2026-08-15/recompute-aggregates.py` left untouched per its local `AGENTS.md` and `MANIFEST.json` SHA-256 `d02142f53596b7c8ee68602ed32095a62b7410ed184efb11f5ef1455304d9ba9`.
- **Security-review gate (`feature-risk-router`)**:
  - Gate status: `pending-dedicated-review` (`security-first-pass-only` read-only triage completed; no dedicated security firm/owner invoked; sole accountable requester owns final merge decision).
  - First-pass triage checks:
    1. `check-evidence-card-leak.sh` `self_test_cached()` rejects symlinked cache paths (`[ ! -L "$cache_dir" ]`), requires current-UID ownership (`[ -O "$cache_dir" ]`) and exact `0700` permissions before reading or writing `.ok` stamps, writes stamps atomically (`mktemp` + `mv -f`), prunes `.ok` count above `64`, and never caches non-zero or `evidence_card_leak_self_test_skipped` runs.
    2. `check-ccl-skills.sh` and `r0-leakage-audit.md` never auto-execute unconfigured scripts under `$HOME` and expose zero private `.yaml` filenames or contributor paths.
    3. `.github/actions/setup-validation-tools/action.yml` runs `printf '%s  %s\n' "$RIPGREP_SHA256" "$TARBALL" | sha256sum --check -` unconditionally on every run (both cache hit and cache miss) before `tar` extraction and `sudo install`.
    4. `packages/opencode-plugin/ccl-skills.ts` preserves `completedSkill()` realpath + active-file byte verification and bounds both `pendingSkills` and synthetic `callID` queues at `64` entries per session.

## 4. GREEN Verification Matrix by Layer

| Layer | Command | Result |
| --- | --- | --- |
| `unit` | `./packages/ccl-skills-npm/node_modules/.bin/tsc -p packages/opencode-plugin/tsconfig.json`, `python3 scripts/test_lane_isolation.py`, `python3 scripts/test_select_affected_tests.py`, `python3 scripts/test_check_spec_references.py`, `python3 scripts/test_check_public_sanitization.py` | `exit 0` (`test_lane_isolation.py`: `112` lane members, `83` reviewed exceptions, `0` unreviewed; `test_select_affected_tests.py`: `23/23` OK; `test_check_spec_references.py`: `79/79` OK; `test_check_public_sanitization.py`: OK) |
| `integration/contract` | `CCL_BROAD_TEST_REASON=repo-required make test` (with `test-code-review-abort-leak` executed inside `unshare --user --map-root-user --pid --fork --mount-proc` because host `systemd --user` holds `PR_SET_CHILD_SUBREAPER`), `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only`, `npm --prefix packages/ccl-skills-npm test`, `(cd packages/ccl-skills-npm && rm -rf artifacts && node --test test/*.test.mjs)`, `npm --prefix packages/ccl-skills-npm run test:pack` | `exit 0` (`repo_gates_ok: 38 suites, jobs=8`; `pytest`: `188 passed`; `eval` unittest: `173 tests OK`; `test-regressions-fast`: `17/17` OK incl. `test_check_evidence_card_leak_cache.sh` `12/12`; `code_review_shard_1_ok` `10/10`; `code_review_shard_2_ok` `9/9`; `review_gate_abort_leak_ok` `3/3` legs; `regression_heavy_lane_ok: 9 suites` in `185s`; `npm test` & `node --test test/*.test.mjs`: `444 pass, 0 fail, 3 Darwin-only skip`; `test:pack`: `11/11 pass`) |
| `build/static` | `R0_BASE="origin/main" CCL_SKILL_BASE_REF="origin/main" ALIAS_AUDIT_CMD="bash ~/.<host>/.private-aliases/run-r0-audit.sh" bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`, `python3 scripts/check-public-sanitization.py .`, `python3 scripts/check-markdown-links.py .`, `python3 scripts/check-spec-references.py .`, `python3 skills/tighten-doc/scripts/doc-lint-repo.py .`, `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/main` | `exit 0` (`alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok` across `both` `process-retro` and project alias profiles; `register_firing_path_resolution_ok (713 locators resolved)`; zero sanitization, link, spec, doc-lint, or git-surface hits) |
| `E2E/host smoke` | Private R0 maintainer audit (`ALIAS_AUDIT_CMD`) locally + GitHub Actions 8-job PR pipeline (`repository-gates`, `regression-fast`, `regression-heavy`, `code-review-regressions-1/2`, `code-review-abort-leak-1/2`, `npm-packages`) | Local private R0 audit `exit 0`; GitHub Actions 8/8 polled after branch push |
| `manual/exploratory` | — | `not applicable` (all changed surfaces are deterministic CLI, plugin, build, and CI gates) |

## 5. Applied Killing-Mutation Walk and Oracle Dimensions

All 18 mutants were applied in isolated `/tmp` repository copies (never mutating the live worktree) after verifying all 9 control suites exited `0`, and each failed differentially on its owning assertion:

| Mutant | Mutated predicate / file | Owning suite | Differential failure observed |
| --- | --- | --- | --- |
| `M1a` | Disable warm stamp check in `check-evidence-card-leak.sh` | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - warm --self-test-cached missed or failed` |
| `M1b` | Constant SHA-256 stamp key in `check-evidence-card-leak.sh` | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - 1-byte edit did not invalidate cache` |
| `M1c` | Allow caching `evidence_card_leak_self_test_skipped` runs | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - degraded git-skip cached or failed unexpectedly` |
| `M1d` | Drop symlink rejection (`! -L` + `lstat`) on cache dir | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - symlinked cache dir was followed or failed` |
| `M1e` | Drop `0700` mode check on cache dir | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - world-writable cache dir wrote stamps or failed` |
| `M1f` | Ignore `CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST` / `CCL_SKILL_NO_SELFTEST_CACHE=1` | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=2`: `FAIL - strict mode did not bypass warm stamp` + `no-cache` |
| `M1g` | Propagate ambient `CCL_SKILL_BASE_REF` into `self_test()` | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - ambient CCL_SKILL_BASE_REF=HEAD broke --self-test` |
| `M1h` | Disable `>64` stamp pruning in `self_test_cached()` | `test_check_evidence_card_leak_cache.sh` | `rc=1`, `failed=1`: `FAIL - cache stamp count was not bounded` |
| `M2` | Remove sibling-host `run-r0-audit.sh` hint from `check-ccl-skills.sh` | `test_check_ccl_r0_status.sh` | `rc=1`: `FAIL` on cross-host remediation assertion |
| `M3` | Inject unreviewed `/tmp/unreviewed-fixed-tmp-probe` into a `test-repo-gates` suite | `scripts/test_lane_isolation.py` | `rc=1`: flags `client-terminal-ansi-check.test.sh` `fixed-tmp` |
| `M4a` | Drop `test_check_public_sanitization.py` from `Makefile` `test-repo-gates` | `scripts/test_select_affected_tests.py` | `rc=1`: `FAIL` on `test-repo-gates` sanitization membership |
| `M4b` | Drop `CCL_SKILL_BASE_REF` export in `ci.yml` `Repository gate suite` | `test_ci_checkout_ref_binding.sh` | `rc=1`: `FAIL` on `Repository gate suite` base guard |
| `M5` | Remove `if (!manifest) return ""` in `packages/opencode-plugin/ccl-skills.ts` | `tsc -p packages/opencode-plugin/tsconfig.json` | `rc=2`: `TS18047: 'manifest' is possibly 'null'` |
| `M6a` | Drop `dequeueSyntheticCall(...)` in `tool.execute.after` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `delegation-owner guard` blocks omitted-`callID` dispatch |
| `M6b` | Disable `rollbackSyntheticCall(...)` in `tool.execute.before` `catch` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `aborted before without callID must not shift subsequent same-tool callID pairing` |
| `M7` | Raise `MAX_PENDING_CALLS` / disable `pendingSkills` eviction in `ccl-skills.ts` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `oldest explicit-callID pendingSkill beyond 64 must be evicted` |
| `M8` | Remove `"antigravity"` from `packages/ccl-skills-npm/package.json` `keywords` | `basic.test.mjs` | `rc=1`, `fail 1`: `AssertionError` on Antigravity metadata |
| `M9` | Revert `r"""` to `"""` in `client-terminal-ansi-check.py` | `client-terminal-ansi-check.test.sh` | `rc=1`: `SyntaxError: invalid escape sequence '\e'` under `-W error` |

- **Oracle dimensions crossed**: `shape` (64-hex SHA-256 stamp, `tsconfig.json` strict types, 2-space `package.json`, raw docstring), `provenance` (symlink/`0700`/UID checks on cache dir, `completedSkill()` realpath+byte verification, `RIPGREP_SHA256`), `cardinality` (0 vs 1+ `git init` forks, 64-entry stamp/FIFO caps), `semantics` (degraded git-skip non-caching, `r0_status=public-fallback` vs `private-ok`, error rollback), `ordering` (FIFO `before`/`after` pairing across same-tool calls).

## 6. `tighten-doc` Closeout Pass

- Mode: `Tighten` + closeout reread (`tighten-doc/references/closeout-reread.md` and `session-vantage-leakage.md`) across `AGENTS.md`, `README.md`, `docs/CONTRIBUTING.md`, `skills/skill-extraction-workflow/references/r0-leakage-audit.md`, `packages/opencode-plugin/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`, `specs/gate-speed-r0-probe-and-ts-guards/plan.md`, and `specs/gate-speed-r0-probe-and-ts-guards/evidence/validation.md`.
- Applied fixes: reconciled CI-outside-`make test` enumeration across `AGENTS.md`, `README.md`, and `docs/CONTRIBUTING.md` with `.github/workflows/ci.yml` (`regression-heavy`, `repository-gates` `check-skill-count.py` + PR-only `check_review_evidence_present.py`, and `npm-packages`); aligned `node --test test/*.test.mjs` glob wording across `basic.test.mjs`, `plan.md`, and `validation.md`; verified all KEEP/decided points preserved, zero terminology/register drift, and zero session-vantage leakage.

## 7. Dual-Track Independent Review and Adversarial Challenge

- Pending execution on committed candidate checkpoint; receipts and per-finding dispositions recorded here immediately upon completion.
