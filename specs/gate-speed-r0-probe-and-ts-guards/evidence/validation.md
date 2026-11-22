# Validation Evidence — Gate Speed, Cross-Host R0 Probe, Parallel Repo Gates, and OpenCode Plugin Type/State Guards

## 1. RED-First Baseline Evidence (Observed Before Production Edits)

All twelve registered behavioral scenarios (`T1`–`T12` in `specs/gate-speed-r0-probe-and-ts-guards/plan.md`) were executed against the pre-fix baseline (`origin/main` = `c05fb2868832042efbb183ad2fa13b7e479299d4`) and observed failing for their intended assertions:

| Case | Command | Pre-fix observed outcome |
| --- | --- | --- |
| `T1` | `bash skills/skill-extraction-workflow/scripts/test_check_evidence_card_leak_cache.sh` | `exit 1`: `--self-test-cached` unsupported (`Usage: ... [--self-test | --files <nul-list-file> | <file> ...]`), warm `check-ccl-skills.sh` still spawned `6` `git init` calls (`expected=0`), no `.ok` stamp created in `0700` cache dir, and ambient `CCL_SKILL_BASE_REF=HEAD` broke `self_test()` case `(v)` (`evidence_card_leak_self_test_failed: committed diff leaked path missed`). |
| `T2` | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_r0_status.sh` | `exit 1`: `alias_audit_unavailable` lacked cross-host `~/.<host>/.private-aliases/run-r0-audit.sh` remediation guidance. |
| `T3` | `python3 scripts/test_lane_isolation.py` | `exit 1`: `Makefile` `test-repo-gates` had `0` `run-parallel-suites.sh` suites (`expected >= 30`), and `skills/testing-strategy/scripts/{client-terminal-ansi-check,lang-basics-ast-check,lang-basics-go-check}.test.sh` had `3` unreviewed `fixed-tmp` hits (`base="${TMPDIR:-/tmp}"`). |
| `T4` | `python3 scripts/test_select_affected_tests.py` + `bash skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh` | `exit 1`: `scripts/test_check_public_sanitization.py` missing from `makefile_suites("test-repo-gates")`, `check-public-sanitization.py .` and `CCL_SKILL_EVIDENCE_CARD_STRICT_SELFTEST=1` missing from `test-repo-gates`. |
| `T5` | `./packages/ccl-skills-npm/node_modules/.bin/tsc -p packages/opencode-plugin/tsconfig.json` | `exit 2`: `6× error TS18047: 'manifest' is possibly 'null'` at `packages/opencode-plugin/ccl-skills.ts:241-245`. |
| `T6` / `T7` | `node --test packages/ccl-skills-npm/test/opencode-hooks.test.mjs` | `exit 1`: omitted `callID` on `Skill` `before`/`after` failed to record native CCL `multi-agent-delegation` load (`delegation-owner guard blocked this subagent call`), because `before` keyed `pendingSkills` under `call-${Date.now()}` while `after` looked up `"unknown-call"`. |
| `T8` | `node --test packages/ccl-skills-npm/test/basic.test.mjs` + `(cd packages/ccl-skills-npm && rm -rf artifacts && node --test test/*.test.mjs)` | `exit 1`: `packages/ccl-skills-npm/package.json` contained tab indentation and omitted `Antigravity` / `"antigravity"`, and `node --test test/*.test.mjs` swept `test/pack.test.mjs` (`11` failures when `artifacts/` was absent). |
| `T9` | `bash skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh` | `exit 1`: `python3 -W error -m py_compile skills/testing-strategy/scripts/client-terminal-ansi-check.py` raised `SyntaxError: invalid escape sequence '\e'` at line 35. |
| `T10` | `bash hooks/test_guard_broad_local_test.sh` | `exit 1`: under inherited `SIGPIPE=SIG_IGN`, `awk '{ print } /<</ { exit }'` closed its stdin pipe early on heredocs and `tr` printed `tr: write error: Broken pipe` onto stderr (`heredoc sigign failed: rc=0 out=b'' err=b'tr: write error: Broken pipe\n'`). |
| `T11` | `bash scripts/test_run_parallel_suites.sh` | `exit 1`: when invoked with `SIGPIPE=SIG_IGN` (GitHub Actions Linux `Runner.Worker` default), child suites inherited ignored `SIGPIPE` instead of `SIG_DFL` (`FAIL: suite failed when parent inherited SIGPIPE=SIG_IGN`). |
| `T12` | `python3 scripts/test_select_affected_tests.py` | `exit 1`: `_escalate_and_reap()` returned immediately after `os.killpg(pgid, signal.SIGKILL)` when the group leader had already exited on `SIGTERM` (`AssertionError: 0 not greater than or equal to 3 : post-SIGKILL reap returned while group members were still live`). |

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
    4. `packages/opencode-plugin/ccl-skills.ts` preserves `completedSkill()` realpath + active-file byte verification and bounds both `pendingSkills` and synthetic `callID` queues at `64` entries per session under a `256`-session LRU backstop (`MAX_PENDING_SESSIONS = 256`).

## 4. GREEN Verification Matrix by Layer

| Layer | Command | Result |
| --- | --- | --- |
| `unit` | `./packages/ccl-skills-npm/node_modules/.bin/tsc -p packages/opencode-plugin/tsconfig.json`, `python3 scripts/test_lane_isolation.py`, `python3 scripts/test_select_affected_tests.py`, `python3 scripts/test_check_spec_references.py`, `python3 scripts/test_check_public_sanitization.py`, `bash hooks/test_guard_broad_local_test.sh`, `python3 hooks/test_hook_field_reads.py`, `bash scripts/test_run_parallel_suites.sh` | `exit 0` (`test_lane_isolation.py`: `112` lane members, `83` reviewed exceptions, `0` unreviewed; `test_select_affected_tests.py`: `24/24` OK; `test_check_spec_references.py`: `79/79` OK; `test_check_public_sanitization.py`: OK; `test_guard_broad_local_test.sh`: `108/108` OK; `test_hook_field_reads.py`: `576/576` OK; `test_run_parallel_suites.sh`: `run_parallel_suites_ok`) |
| `integration/contract` | `CCL_BROAD_TEST_REASON=repo-required make test` (including `make test-repo-gates` under inherited `SIGPIPE=SIG_IGN` with `0` `Broken pipe` diagnostics, and `test-code-review-abort-leak` executed inside `unshare --user --map-root-user --pid --fork --mount-proc` because host `systemd --user` holds `PR_SET_CHILD_SUBREAPER`), `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only`, `npm --prefix packages/ccl-skills-npm test`, `(cd packages/ccl-skills-npm && rm -rf artifacts && node --test test/*.test.mjs)`, `npm --prefix packages/ccl-skills-npm run test:pack` | `exit 0` (`repo_gates_ok: 38 suites, jobs=8`; `pytest`: `188 passed`; `eval` unittest: `173 tests OK`; `test-regressions-fast`: `17/17` OK incl. `test_check_evidence_card_leak_cache.sh` `12/12`; `code_review_shard_1_ok` `10/10`; `code_review_shard_2_ok` `9/9`; `review_gate_abort_leak_ok` `3/3` legs; `regression_heavy_lane_ok: 9 suites` in `185s`; `npm test` & `node --test test/*.test.mjs`: `444 pass, 0 fail, 3 Darwin-only skip`; `test:pack`: `11/11 pass`) |
| `build/static` | `R0_BASE="origin/main" CCL_SKILL_BASE_REF="origin/main" ALIAS_AUDIT_CMD="bash ~/.<host>/.private-aliases/run-r0-audit.sh" bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`, `python3 scripts/check-public-sanitization.py .`, `python3 scripts/check-markdown-links.py .`, `python3 scripts/check-spec-references.py .`, `python3 skills/tighten-doc/scripts/doc-lint-repo.py .`, `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/main` | `exit 0` (`alias_audit_ok`, `r0_status=private-ok`, `ccl_skill_check_clean_ok` across `both` `process-retro` and project alias profiles; `register_firing_path_resolution_ok (713 locators resolved)`; zero sanitization, link, spec, doc-lint, or git-surface hits) |
| `E2E/host smoke` | Private R0 maintainer audit (`ALIAS_AUDIT_CMD`) locally; GitHub Actions 8-job PR pipeline (`repository-gates`, `regression-fast`, `regression-heavy`, `code-review-regressions-1/2`, `code-review-abort-leak-1/2`, `npm-packages`) | Local private R0 audit `exit 0`; remote GitHub Actions PR run `pending` until branch push and PR creation |
| `manual/exploratory` | — | `not applicable` (all changed surfaces are deterministic CLI, plugin, build, and CI gates) |

## 5. Applied Killing-Mutation Walk and Oracle Dimensions

All 24 mutants were applied in isolated `/tmp` repository copies (never mutating the live worktree) after verifying all control suites exited `0`, and each failed differentially on its owning assertion:

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
| `M6c` | Discard earlier queued `Skill` entries on out-of-order `skillHint` match in `dequeueSyntheticCall(...)` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `delegation-owner guard` blocks `parallel-omitted-callid` dispatch |
| `M6d` | Fall back to `queue.shift()` on unmatched `skillHint` for `tool === "skill"` in `dequeueSyntheticCall(...)` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `unmatched skillHint in after must not steal another queued skill's synthetic callID` |
| `M7` | Raise `MAX_PENDING_CALLS` / disable `pendingSkills` eviction in `ccl-skills.ts` | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `oldest explicit-callID pendingSkill beyond 64 must be evicted` |
| `M7b` | Collapse session isolation (`MAX_PENDING_SESSIONS = 1`) so cross-session flood evicts active session | `opencode-hooks.test.mjs` | `rc=1`, `fail 1`: `one session flooding >64 pending skills must not evict another session's pending skill` |
| `M8` | Remove `"antigravity"` from `packages/ccl-skills-npm/package.json` `keywords` | `basic.test.mjs` | `rc=1`, `fail 1`: `AssertionError` on Antigravity metadata |
| `M9` | Revert `r"""` to `"""` in `client-terminal-ansi-check.py` | `client-terminal-ansi-check.test.sh` | `rc=1`: `SyntaxError: invalid escape sequence '\e'` under `-W error` |
| `M10` | Revert `awk '!s { print } /<</ { s = 1 }'` to `awk '{ print } /<</ { exit }'` and drop `tr` stderr redirect in `hooks/guard-broad-local-test.sh` | `hooks/test_guard_broad_local_test.sh` | `rc=1`: `FAIL ignored SIGPIPE must stay silent on heredoc and failing tool` |
| `M11` | Remove `python3` `SIGPIPE` `SIG_DFL` reset in `scripts/run-parallel-suites.sh` | `scripts/test_run_parallel_suites.sh` | `rc=1`: `FAIL: suite failed when parent inherited SIGPIPE=SIG_IGN` |
| `M12` | Remove post-`SIGKILL` `_pgid_has_live_non_zombie_members` poll loop in `scripts/select-affected-tests.py` | `scripts/test_select_affected_tests.py` | `rc=1`: `AssertionError: 0 not greater than or equal to 3 : post-SIGKILL reap returned while group members were still live` |

- **Oracle dimensions crossed**: `shape` (64-hex SHA-256 stamp, `tsconfig.json` strict types, 2-space `package.json`, raw docstring), `provenance` (symlink/`0700`/UID checks on cache dir, `completedSkill()` realpath+byte verification, `RIPGREP_SHA256`), `cardinality` (0 vs 1+ `git init` forks, 64-entry per-session caps, 256-session LRU cap), `semantics` (degraded git-skip non-caching, `r0_status=public-fallback` vs `private-ok`, error rollback, unmatched-hint fail-closed `null`), `ordering` (FIFO `before`/`after` pairing plus out-of-order parallel `Skill` completion).

## 6. `tighten-doc` Closeout Pass

- Mode: `Tighten` + final closeout reread (`tighten-doc/references/closeout-reread.md` and `session-vantage-leakage.md`) across `AGENTS.md`, `README.md`, `docs/CONTRIBUTING.md`, `skills/skill-extraction-workflow/references/r0-leakage-audit.md`, `packages/opencode-plugin/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`, `specs/gate-speed-r0-probe-and-ts-guards/plan.md`, and the full `specs/gate-speed-r0-probe-and-ts-guards/evidence/validation.md` after recording review/challenge/delta passes.
- Closeout reread 5-item record (`closeout-reread.md`): (1) surface reread = all 8 modified Markdown docs above, with full-document reread on `plan.md` and `validation.md` after `Delta pass 2`; (2) changed blocks since prior sweep = `plan.md` Scope / Test-Case Register / Target-Output Map and `validation.md` Sections 1, 4, 5, 6, and 7; (3) family/full-card trigger = checked across the 3-doc contributor verification family (`AGENTS.md`, `README.md`, `docs/CONTRIBUTING.md`); (4) defects found and fixed = reconciled CI-outside-`make test` list across `AGENTS.md`/`README.md`/`docs/CONTRIBUTING.md`, aligned `node --test test/*.test.mjs` wording, aligned `256`-session cap note in Section 3, synchronized `T10`–`T12` and `M10`–`M12` across `plan.md` and `validation.md`, verified zero terminology/register drift and zero session-vantage leakage; (5) scope rationale = full read of `plan.md` and `validation.md` plus changed hunks and surrounding sections of repo docs.

## 7. Dual-Track Independent Review and Adversarial Challenge

## Review pass
- Reviewed commit: `58a0cbc1fa40405c40810be0742cc57afd16916f` (base `origin` `refs/heads/main` = `c05fb2868832042efbb183ad2fa13b7e479299d4` confirmed via `git ls-remote origin refs/heads/main` at `2026-11-22T18:10:26Z`; receipt `specs/gate-speed-r0-probe-and-ts-guards/evidence/review-R1.json`, `selected_client: claude`, `candidate_sha256: 1c0e38615565fc01318d9b91b2a5bec346d233994a0c5ebd84298d2a63083053`)
- Findings: `2 total (0 P0 / 0 P1 / 2 P2)`
- R0 evidence: `alias_audit_ok` (`both`: `process-retro` + `project-alias`, `r0_status=private-ok`, `ccl_skill_check_clean_ok`)
- Dispositions:
  - `P2` `packages/opencode-plugin/ccl-skills.ts:405` (out-of-order parallel `Skill` completions without `callID` discarding earlier queued entries): `fixed` in `b9f05b56e94f902f6dfbdeb6131469389c782f87` (`queue.splice(idx, 1)` + `parallel-omitted-callid` test + mutant `M6c`).
  - `P2` `specs/gate-speed-r0-probe-and-ts-guards/evidence/validation.md:56` & `specs/gate-speed-r0-probe-and-ts-guards/plan.md:164` (remote GitHub Actions PR run status before push): `fixed` in `b9f05b56e94f902f6dfbdeb6131469389c782f87` (marked `pending` until branch push and PR execution; also aligned baseline `TS18047` line citation to `ccl-skills.ts:241-245`).

## Challenge pass
- Reviewed commit: `b9f05b56e94f902f6dfbdeb6131469389c782f87` (base `origin` `refs/heads/main` = `c05fb2868832042efbb183ad2fa13b7e479299d4` confirmed via `git ls-remote origin refs/heads/main` at `2026-11-22T18:29:53Z`; receipt `specs/gate-speed-r0-probe-and-ts-guards/evidence/challenge-C1.json`, `selected_client: claude`, `candidate_sha256: 6ae22fb96e3307b7a6861d15bacc00934f7d87f738cd8ab2b3a1f364be44660b`)
- Findings: `2 total (0 P0 / 0 P1 / 2 P2)`
- R0 evidence: `alias_audit_ok` (`both`: `process-retro` + `project-alias`, `r0_status=private-ok`, `ccl_skill_check_clean_ok`)
- Gate-fireability applicability: `yes` — change edits shared deterministic gates, self-test stamp cache, lane-isolation scanner, and OpenCode hook pairing; Item 9 exercised: `specs/gate-speed-r0-probe-and-ts-guards/evidence/challenge-C1.json` (`challenge_focus` item 5 bypass-by-omission probe and `concern_results[0]` evaluation)
- Dispositions:
  - `P2` `packages/opencode-plugin/ccl-skills.ts:365` (`pendingSkills` 64-entry cap shared across sessions rather than scoped per session): `fixed` in `ddbe9da64a25b0a3c7d207f22b7cfd75b6116abb` (`pendingBySession` per-session 64-entry cap under `MAX_PENDING_SESSIONS = 256` + cross-session flood test + mutant `M7b`).
  - `P2` `packages/opencode-plugin/ccl-skills.ts:411` (`dequeueSyntheticCall` falling back to `queue.shift()` on unmatched `skillHint` for `tool === "skill"`): `fixed` in `ddbe9da64a25b0a3c7d207f22b7cfd75b6116abb` (exact normalized-hint match returning `null` on mismatch + `unmatched-hint-session` test + mutant `M6d`).
  - Same-surface design check (`keep / delete / narrow / replace` across `R1` and `C1` on `ccl-skills.ts` omitted-`callID` pairing): `keep` the omitted/empty-`callID` pairing capability required by `B2-4`, and `replace` the flat `${sessionID}\0...` string-prefixed map plus `queue.shift()` fallback with per-session `SessionPending` maps and exact `normalizeSkillName` queue matching (ratified within sole-accountable-requester task scope; verified clean in `Delta pass 1`).

## Delta pass 1
- Reviewed commit: `ddbe9da64a25b0a3c7d207f22b7cfd75b6116abb`; packet: `git diff b9f05b56e94f902f6dfbdeb6131469389c782f87..ddbe9da64a25b0a3c7d207f22b7cfd75b6116abb` (receipt `specs/gate-speed-r0-probe-and-ts-guards/evidence/delta-D1.json`, `selected_client: claude`, `candidate_sha256: 347a147098db2d0dc798bc6215b5816b5cd6a1261c630459f4acc2b6fc3895ac`)
- Findings / Dispositions: `0 total (0 P0 / 0 P1 / 0 P2)` — `status: passed`, none.

## Delta pass 2
- Reviewed commit: `6fed9ee913fd284e147a4f72c677c3cc3f8d1125`; packet: `git diff 060ebc89d2a6796bfb45072a7c32e82aa9f72c34..6fed9ee913fd284e147a4f72c677c3cc3f8d1125` (receipt `specs/gate-speed-r0-probe-and-ts-guards/evidence/delta-D2.json`, `selected_client: claude`, `candidate_sha256: 04afc183141334ffa43b2fb8217c39a18d49fc8ef575231d2d19f77a7f7a3d6b`)
- Findings / Dispositions: `0 total (0 P0 / 0 P1 / 0 P2)` — `status: passed`, none.

## Post-review delta
- `specs/gate-speed-r0-probe-and-ts-guards/evidence/delta-D2.json` — controller receipt for `Delta pass 2` on `6fed9ee913fd284e147a4f72c677c3cc3f8d1125`
- `specs/gate-speed-r0-probe-and-ts-guards/evidence/validation.md` — non-executable disposition and verification record updated for `D2`

## Convergence Declaration
- Covered code/skill candidate commit: `6fed9ee913fd284e147a4f72c677c3cc3f8d1125` (followed only by the non-executable `specs/gate-speed-r0-probe-and-ts-guards/evidence/` commit above).
- Terminal lane receipts: `review-R1.json` (`findings`, 0 P0 / 0 P1 / 2 P2 fixed), `challenge-C1.json` (`findings`, 0 P0 / 0 P1 / 2 P2 fixed), `delta-D1.json` (`passed`, 0 findings), `delta-D2.json` (`passed`, 0 findings).
- Walked self-audit axes: oracle dimensions (`shape`, `provenance`, `cardinality`, `semantics`, `ordering`) + 6 pre-cover blind-spot axes (`security/privacy/authority/data-loss`, `concurrency & lifecycle`, `resource bounds`, `rollout/migration ordering`, `over-broad absolute`, `enumeration-completeness`) + 24 applied killing mutations (`M1a`–`M1h`, `M2`, `M3`, `M4a`, `M4b`, `M5`, `M6a`–`M6d`, `M7`, `M7b`, `M8`, `M9`, `M10`, `M11`, `M12`).
- Standing open items at commit time: (1) remote GitHub Actions 8-job PR pipeline execution (`pending` until branch push, polled to completion before handoff); (2) `security-review` gate at `pending-dedicated-review` (`security-first-pass-only`); (3) PR merge explicitly withheld until user merge instruction.
