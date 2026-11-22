# Hook Turn-Key Fix, Symlink Isolation, Coverage Gate Speedup, and Suite Wiring

Deliver the four-item first batch from the repository quality and efficiency assessment:

1. Fix `hooks/agy-bridge.py` `PreInvocation` turn-key tracking so first-of-turn hooks (`task-entry.sh` and `merge-authorization-prompt.sh`) run once per user turn instead of re-running on every model step and re-arming consumed one-shot merge grants.
2. Fix `hooks/host-input.py` and `hooks/guard-edit-isolation.sh` symlink target handling so mutating, replacing, or deleting a symlink located inside a protected primary checkout is denied even when the symlink points outside the repository or dangles, and creating a file under a dangling parent directory symlink into a protected primary checkout is also denied.
3. Rewrite the per-file scan loop in `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh` in pure Bash 3.2 without per-file `basename`/`dirname` subprocess forks while keeping CLI flags, outputs, and exit codes unchanged.
4. Register `eval/test_owner_role_audit.py` and `skills/code-review/scripts/test_kimi_packet_mcp.py` (plus the new coverage-gate suite) in `Makefile` so both local `make test` and GitHub Actions CI run them.

## Extraction Charter

| Field | Answer |
| --- | --- |
| Purpose | Close two runtime safety/isolation gaps (`agy-bridge.py` per-step re-arming/re-injection and `host-input.py` + `guard-edit-isolation.sh` primary-checkout symlink bypass), eliminate 2×N per-file subprocess forks in `check-agent-contract-coverage.sh`, and close two CI test-registration blind spots (`test_owner_role_audit.py`, `test_kimi_packet_mcp.py`). |
| Scope | In: `hooks/agy-bridge.py`, `hooks/test_agy_bridge.py`, `hooks/host-input.py`, `hooks/test_host_input.py`, `hooks/guard-edit-isolation.sh`, `hooks/test_guard_edit_isolation.sh`, `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh`, `skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh`, `skills/product-rd-workflow/scripts/AGENTS.md`, `Makefile`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `skills/skill-extraction-workflow/references/source-register.md`, and `specs/hook-turn-key-and-gate-speed/plan.md`, and `specs/hook-turn-key-and-gate-speed/evidence/validation.md`. Out: later-batch items (`check-ccl-skills.sh` self-test caching, `test-repo-gates` parallelization, `opencode-plugin` `tsc`, skill entrypoint size reduction, `review_gate.py` split, and `agy-bridge.py` shadow-transcript `tmpfs` inode churn in `skill-loading.py`). No iterative-program watermark applies. |
| Depth | Generator/tooling change: runtime hook scripts/bridge, deterministic coverage gate script, test suites, and `Makefile`/selector registration; no `SKILL.md` prose or routing description changes. |
| Result classification | Failure/correction across all four items, backed by live/sandbox reproductions and repository topology inspection. |
| Matching analysis | Contributing factors: (1) `agy-bridge.py` treated `initialNumSteps` as constant within a user turn, whereas Antigravity's `PreInvocationHookArgs` increments `initialNumSteps` after every tool step and resets `invocationNum` to `0` at each user turn; (2) `host-input.py` `paths()` collapsed leaf symlinks via `os.path.realpath` before policy checks, and `guard-edit-isolation.sh` overwrote `fp` with `realpath "$fp"` before checking `fp`'s own lexical parent directory; (3) `check-agent-contract-coverage.sh` spawned external `basename` and `dirname` processes per tracked file and looped over unquoted space-separated lists per segment/file; (4) two test suites were added without `Makefile` target entries and no registration check pinned them. Prevention: bind `PreInvocation` turn keys to transcript `turn_id` + `invocationNum == 0` boundaries, preserve both directory-entry and resolved-target paths in `host-input.py` and `guard-edit-isolation.sh`, use Bash 3.2 parameter expansion and `/`‑delimited literal sets in `check-agent-contract-coverage.sh` with a zero-fork regression test, and wire the orphaned suites into `Makefile` + `test_select_affected_tests.py`. |
| Failure mode | A flawed turn-key fix could break failed-hook retry within the same turn, drop queued `PreToolUse`/`PostToolUse` notes, or miss a consecutive identical user prompt; a flawed symlink fix could deny edits inside a linked worktree or hang on symlink cycles; a flawed pure-Bash rewrite could alter `--exclude` glob literalness, break on dash-prefixed filenames, or use Bash 4-only features (`declare -A`). |
| Lifecycle impact | Implementation and debugging (accurate per-turn prompt/merge gating and primary-checkout symlink isolation); testing and CI verification (faster contract-coverage gate, 20 previously orphaned assertions active in `make test` and CI); downstream repositories vendoring `check-agent-contract-coverage.sh` via `install-gates.sh`. Product intent and UI/UX: not applicable. |
| Evidence plan | Produced artifacts from the assessment pass; Antigravity primary hook documentation and live `agy -p` / `agy -c -p` `PreInvocation` payload captures in disposable `$TMPDIR` workspaces; `hooks/test_hook_field_reads.py` 576-case baseline `788470c` differential fixture; baseline `0ee3a4a` differential comparison for `check-agent-contract-coverage.sh`; `Makefile` and `.github/workflows/ci.yml` job wiring. |
| Completion standard | RED-before-fix evidence recorded for every behavioral change; killing-mutation walk applied in isolated scratch checkouts; `hooks/test_hook_field_reads.py`, focused suites, `check-ccl-skills.sh`, `check-public-sanitization.py`, `make test`, `--heavy-only` regressions, and npm package tests/pack checks green on the final candidate; independent review and adversarial challenge recorded under `specs/hook-turn-key-and-gate-speed/evidence/`. |

## Shared-Gate Classification and Verifier Discovery

- **Artifact classification**: `gate implementation` (`check-agent-contract-coverage.sh`, `guard-edit-isolation.sh`, `host-input.py`, `agy-bridge.py`) + `runtime/code` (`Makefile`, `select-affected-tests.py` test wiring) + `spec/plan` (this file).
- **Authoritative verifiers discovered and run before and after implementation**:
  - `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
  - `bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce`
  - `python3 scripts/check-markdown-links.py .`
  - `python3 scripts/check-spec-references.py .`
  - `python3 scripts/check-public-sanitization.py .`
  - `python3 skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py --repo . --base-ref origin/main`

## Implementation Boundary Record

| Field | Value |
| --- | --- |
| Active baseline | This plan (`specs/hook-turn-key-and-gate-speed/plan.md`) on isolated worktree branch `fix/hook-turn-key-and-gate-speed` forked from `origin/main` (`0ee3a4a89f51098768830fe628bff525a94a3dee`, verified via `git ls-remote origin refs/heads/main`). |
| Scope | Strictly bound to the four items in the accepted first-batch proposal. |
| Implementation owners loaded | `product-rd-workflow`, `skill-extraction-workflow`, `worktree-isolation`, `defect-diagnosis`, `feature-risk-router`, `testing-strategy`, `python-service-dev`, `terminal-cli-dev`, `multi-agent-delegation`, `code-review`, `tighten-doc`, `agents-file-coverage-gate` (all loaded in full in-session). |
| Owner mechanical rules triggered | `worktree-isolation` Step 0 isolated worktree + `git -C` discipline; `python-service-dev` stdlib-only isolation and explicit error handling; `terminal-cli-dev` preservation of all CLI flags, stdout/stderr routing, and exit codes (`0`/`1`/`2`) in `check-agent-contract-coverage.sh` + repo-local `AGENTS.md` sync; `testing-strategy` RED-first register, differential equivalence (`check-agent-contract-coverage.sh`, `test_hook_field_reads.py`), precision/spare rows, real host sample verification, and applied killing-mutation walk; `skill-extraction-workflow` R0 public-fallback honesty (`interim` / `R0 pending maintainer audit` when `ALIAS_AUDIT_CMD` is unset), impact-chain ledger row, and dual-track review + challenge; `tighten-doc` deliverable-doc pass. `owner-dispatch`: `ccl-skills` is exempt (`opted-in: no`, repository is the shared skill source itself). |
| `multi-agent-delegation` decision | `local`: the four items share `Makefile`, `source-register.md`, one candidate diff, and one dual-track review/challenge packet; keeping edits controller-local avoids worktree index contention and split-packet drift. |
| Visible-UI checkpoint | `not-applicable` (`visible surface: no` — non-rendered CLI hook runtime, internal scan loop preserving user-visible CLI contract, and test/CI wiring). |
| `feature-risk-router` inventory | Triggered (`shared-gate`, `permission-access`, `security-review`); see Risk Inventory below. |
| Test-case-first status | Triggered: RED tests written and observed failing before each behavioral code edit (`T1`–`T8`). |

## Risk Inventory (`feature-risk-router`) and Security Four Questions

| Tag | Applies | Required gates and evidence |
| --- | --- | --- |
| `shared-gate` | yes: edits `agy-bridge.py`, `host-input.py`, `guard-edit-isolation.sh`, `check-agent-contract-coverage.sh`, and `Makefile` test lanes | Persistent plan (`plan.md`), RED-baseline + differential tests, `make test`, independent review and adversarial challenge. |
| `permission-access` | yes: fixes one-shot merge-authorization re-arming on Antigravity and primary-checkout symlink edit isolation | Negative (deny) and precision (allow) behavioral matrix, real `agy` payload verification, `test_hook_field_reads.py` 576-case parity. |
| `security-review` | yes (change-triggered hardening / vulnerability-fix on hook guards) | Gate status: `pending-dedicated-review` (`security-first-pass-only` read-only triage recorded in `evidence/validation.md`; sole accountable requester decides merge/launch). |
| `external-integration` | yes: Antigravity `PreInvocation` stdin contract | Verified against primary `agy` binary protobuf descriptors and live `agy -p` / `agy -c -p` runs in disposable `$TMPDIR` workspaces. |
| `release-ops`, `write-finality`, `api-contract`, `money-quota`, `data-migration`, `ai-output`, `ai-action`, `visible-ui`, `docs-only` | no | No version bump, package publish, schema change, or rendered UI change. |

Stop reasons: none for implementation, verification, branch push, or Draft PR creation; merging to `main` requires explicit merge authorization from the sole accountable requester, and clean-landing R0 status requires maintainer `ALIAS_AUDIT_CMD` (`r0_status=public-fallback` locally).

### Security Four Questions

1. **Caller-controllable inputs**: Antigravity `PreInvocation` stdin JSON (`lastUserInput`, `invocationNum`, `initialNumSteps`, `transcriptPath`, `conversationId`), `PreToolUse` edit target paths (`file_path`, `notebook_path`, `path`, `apply_patch` headers) including leaf symlinks, dangling parent symlinks, and symlink cycles, and repository filenames/CLI flags passed to `check-agent-contract-coverage.sh`.
2. **Blast radius if forged or mishandled**: Recomputing a fresh turn key mid-turn re-arms consumed one-shot merge grants; resolving leaf symlinks before checking their directory entry lets edits delete or replace symlinks in `.worktree-only` primary checkouts; unsafe `eval` or unquoted globbing in `check-agent-contract-coverage.sh` could misclassify paths or execute metacharacters.
3. **Trust roots**: Hook scripts remain policy owners; `conversationId` is sanitized/hashed before touching `state_dir()` (`0700`, files `0600`); `guard-edit-isolation.sh` structural worktree detection (`--absolute-git-dir` vs `--git-common-dir`) stays authoritative across both directory-entry and resolved-target paths; `check-agent-contract-coverage.sh` uses quoted `[[ ... ]]` literal matching with `set -f` word-splitting and zero `eval`.
4. **Negative cases**: Multi-step turn after consuming one-shot `merge #123` grant → second merge denied on both step 1 and step 2; symlink and dangling symlink in `.worktree-only` primary checkout → denied; file under dangling parent symlink into `.worktree-only` primary checkout → denied; symlink cycle → bounded `< 16` hops, no hang; `--exclude 'gen*'` metacharacters → literal segment match only.

## Decisions and Mechanism-Operability Check

| Decision | Choice | Rejected alternative and rationale |
| --- | --- | --- |
| `PreInvocation` turn key | Persist `{"seq": seq, "turn_id": effective_turn, "stale_turn_id": new_stale, "key": key}` in `{ctx['key']}.active.turn`. On `invocationNum == 0`, increment monotonic `seq` so every new user turn gets a fresh key regardless of stale transcripts or missing `initialNumSteps` (`replace` decision after two review/challenge rounds surfaced edge cases in `(turn_id, initialNumSteps)` change heuristics), recording `stale_turn_id` when the prior turn's `turn_id` is still on disk. On `invocationNum > 0`, reuse `active["key"]` unless both `active["turn_id"]` and `effective_turn` are non-null and unequal (absorbed mid-run user turn, which increments `seq`); backfill `turn_id` once the current turn's `USER_INPUT` flushes. When `invocationNum` is absent (`None`), derive key from `turn:{effective_turn}`, `steps:{initialNumSteps}`, or `noturn` so synthetic retry payloads keep same-turn retry semantics. | Keying on `initialNumSteps` (increments every tool step), `(turn_id, initialNumSteps)` diffing at `invocationNum == 0` (misses new turns when `initialNumSteps` is omitted), or `turn_id` alone without `active.turn` (fails when transcript is absent, delayed, or scrolls past 32 MiB mid-turn). |
| Symlink isolation check | Preserve both the parent-resolved directory entry path and `os.path.realpath` target in `hooks/host-input.py` (`candidate_paths`), and extract `check_one_path` + `check_symlink_targets` (`realpath` + `readlink` sharing a 16-hop `total_sym_hops` budget across both target hops and dangling parent directory symlinks) in `hooks/guard-edit-isolation.sh` so both the Python normalizer and `jq`-only fallback enforce identical isolation even when `realpath` fails on dangling intermediate directories. | Checking only `realpath` (misses symlinks inside protected primary checkouts pointing outside) or disabling dangling-parent walks inside the `readlink` loop (misses chained symlinks into dangling parent symlinks when `realpath` fails). |
| Pure-Bash coverage scan | Bash 3.2 `${file##*/}` / `${file%/*}`, `/`‑wrapped `exclude_set` and `simple_ext_set` (with `extra_source_suffixes` array fallback for multi-dot/dotless `--source-ext`), `last_checked_dir` cache, and single fd `3>>`/`4>>` redirections. | Associative arrays `declare -A` (breaks macOS `/bin/bash` 3.2) or `eval "case ..."` (metacharacter hazard on `--exclude` / `--source-ext`). |
| Suite registration | Add `eval.test_owner_role_audit` to `Makefile` `test-repo-gates` + `_DEFAULT_EVAL_UNITTEST_MODULES`; add `test_kimi_packet_mcp.py` to `Makefile` `test-code-review-2`; add `REQUIRE_BASELINE=1 bash .../test_check_agent_contract_coverage.sh` to `Makefile` `test-repo-gates` (blocking zero-fork + baseline parity checks; opt-in `PERF_BOUND_MS` timing check). | Adding a separate CI-only step (violates `Makefile:16-20` single-source leaf-target invariant) or an unconditional wall-clock gate in shared CI (flaky under runner contention). |

### Mechanism-Operability Check

- **Author dogfood across CI landing faces**: `.github/workflows/ci.yml` runs on `push` to `main` and `dev` and on `pull_request`. Base-relative gates (`check-ccl-skills.sh`, `shared_git_surface_gate.py`, `check_review_evidence_present.py`) are verified against `origin/main` (`0ee3a4a89f51098768830fe628bff525a94a3dee`, the active PR target).
- **Marginal cost**: `PreInvocation` saves 2×(K−1) hook spawns and ~3.2 KB×(K−1) context per K-step Antigravity turn; `guard-edit-isolation.sh` adds 0 forks for non-symlinks; `check-agent-contract-coverage.sh` drops from ~11.3s (with shimmed forks) / ~7.8s raw to ~0.19s on this repo; the 3 wired test suites add ~2.5s total to `make test`.
- **Trust-model fit & premise check**: `host-input.py` and `guard-edit-isolation.sh` tighten only symlink targets touching protected primary checkouts (never linked worktrees or solo plain repos); verified against all 576 baseline cases in `hooks/test_hook_field_reads.py` and 30 `test_guard_edit_isolation.sh` probes.

## Verdict Decision Tables

### 1. `hooks/agy-bridge.py` `PreInvocation` (`resolve_turn_key` + hook dispatch)

| `lastUserInput` | `invocationNum` | `ctx['turn_id']` vs `active.turn` | First-of-turn hooks (`task-entry.sh`, `merge-authorization-prompt.sh`) | Queued `notes` (`pop_notes`) |
| --- | --- | --- | --- | --- |
| empty / missing | any | any | skipped (`key = None`) | delivered once if queued |
| non-empty | `0` | any (fresh, delayed, stale, or absent transcript; with or without `initialNumSteps`) | increment `seq`, record `stale_turn_id` if prior `turn_id` still on disk → run once; write per-script `.turn` marker on `status == 'ok'` | delivered once if queued |
| non-empty | `None` (synthetic payload) | new `turn_id` / `steps`, or same `turn_id` / `steps` on retry | run once per `(turn_id, steps, prompt)`; retry only a script whose prior run failed | delivered once if queued |
| non-empty | int `> 0` | `effective_turn` unchanged, `None` (>32 MiB tail or stale), or `active.turn_id` was `None` | reuse `active.key` → skipped (failed script still retries; succeeded merge arming never re-runs) | delivered once if queued |
| non-empty | int `> 0` | both `active.turn_id` and `effective_turn` non-null and unequal | increment `seq` → new key runs once for absorbed user turn | delivered once if queued |

### 2. `hooks/host-input.py` + `hooks/guard-edit-isolation.sh` (`candidate_paths` + `check_target`)

| Symlink location (`dirname -- "$fp"`) | Resolved target (`realpath` / `readlink`) | Verdict |
| --- | --- | --- |
| Protected primary checkout (`.worktree-only` or live worktrees `> 1`) | Outside repo, inside repo, or dangling | `deny` |
| Outside repo or linked worktree | Inside protected primary checkout (existing or uncreated subdir, leaf or parent symlink) | `deny` |
| Linked worktree (`isolated == 1`) | Outside repo or inside linked worktree | quiet `allow` |
| Solo plain primary checkout (no marker, 1 live worktree) | Outside repo or inside solo checkout | quiet `allow` |
| Outside any repo | Symlink loop (`ELOOP`) or outside any repo | quiet `allow` (bounded `< 16` hops) |

### 3. `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh`

| Mode | In-scope source/contract state | Exit code & output |
| --- | --- | --- |
| any | Not inside git work tree and contains nested `.git` repos | exit `2`, stderr group-checkout refusal |
| `--check` / `--enforce` / `--fix` | All in-scope dirs have non-empty real `AGENTS.md`, no empty/symlinked tracked contracts | exit `0`, stdout `agent contract coverage ok` |
| `--check` | Missing, empty, or symlinked contract | exit `0`, stderr lists gaps + guidance note |
| `--enforce` | Missing, empty, or symlinked contract | exit `1`, stderr lists gaps |
| `--fix` | Missing contract in in-scope dir (no empty/symlinked tracked contracts) | exit `0`, scaffolds stub, stdout `agent contract coverage ok` |
| `--fix` + `--enforce` follow-up | Empty or symlinked existing contract | never overwritten/followed; reported on stderr |

## Objective Closure, Functional Completeness, and Structural Minimality

### Objective Closure

- **Objective & member identity**: Deliver the four accepted Batch 1 items from the Turn 1 `proposed-next:` proposal (member unit = each named Batch 1 deliverable item, 4 finite items total, fixed by user Turn 2 `continue` binding to Turn 1 step 228 `proposed-next:`).
- **System of record & enumerator**: Turn 1 final response `proposed-next:` line (4 items, no unenumerated filters); component edge = `hooks/`, `skills/product-rd-workflow/scripts/`, `Makefile`, `scripts/select-affected-tests.py`, `skills/skill-extraction-workflow/references/source-register.md`.
- **Population preflight**: `population: fires` (4 distinct items across runtime events, target paths, and tracked repository files; reconciled 4/4 in Functional Completeness below, difference = 0).
- **Per-operation bounds and no-starvation**: `agy-bridge.py` caps handler budget at `17s` (`PreInvocation`) and transcript tail at `32 MiB` (with `active.turn` preserving turn identity across >32 MiB turns so nothing is deferred); `guard-edit-isolation.sh` caps manual `readlink` fallback at 16 hops (completes every target decision in-call, defers nothing); `check-agent-contract-coverage.sh` processes the entire `files.z` stream to EOF in one pass with no batch cap (0 members deferred).

| Outcome class | Scope | Member scope it holds over | Implementation surface | Fresh evidence | Status |
| --- | --- | --- | --- | --- | --- |
| `positive` | `in` (all 4 Batch 1 items) | First-of-turn injection once per turn + note delivery; linked-worktree & solo-repo symlink edits allowed; clean coverage check in 193ms with 0 `basename`/`dirname` forks; 2 orphaned suites + new coverage suite executed by `make test` | `hooks/agy-bridge.py`, `hooks/host-input.py`, `hooks/guard-edit-isolation.sh`, `check-agent-contract-coverage.sh`, `Makefile`, `scripts/select-affected-tests.py` | `T1`–`T8` + live `agy` smoke (`specs/hook-turn-key-and-gate-speed/evidence/validation.md`) | satisfied |
| `negative` | `in` (all failure/rejection variants) | Consumed merge grant not re-armed on step 2+; primary-checkout symlink, dangling symlink, and dangling-parent symlink edits denied; missing/empty/symlinked `AGENTS.md`, bad `--name`, unknown arg, and parent-of-repos rejected with exact exit codes | Same | `T1`–`T8` negative assertions + `hooks/test_hook_field_reads.py` (576 cases) | satisfied |
| `corrected-recovered` | `in` (retry & fallback paths) | Failed `task-entry.sh` on step 0 retries on step 1 of same turn without re-running succeeded `merge-authorization-prompt.sh`; late/oversized transcript mid-turn recovers key from `active.turn`; `check-agent-contract-coverage.sh --fix` scaffolds missing stubs without touching existing/symlinked files | `hooks/agy-bridge.py`, `check-agent-contract-coverage.sh` | `test_failed_task_entry_is_retried_in_the_same_turn`, `T2`, `T6` | satisfied |
| `ambiguous-or-superficially-successful` | `in` (false-green traps) | Consecutive user turns with identical prompt text still trigger fresh turn key; symlink loop outside repo terminates cleanly without false deny or timeout; `--exclude 'gen*'` metacharacters match literally without globbing neighbor dirs; `test_select_affected_tests.py` pins `Makefile` registration so suites cannot silently drop out | `hooks/agy-bridge.py`, `hooks/guard-edit-isolation.sh`, `check-agent-contract-coverage.sh`, `scripts/test_select_affected_tests.py` | `T1`, `T4`, `T6`, `T8` + 11-mutant walk (`evidence/validation.md`) | satisfied |

### Functional Completeness Matrix (Generated Trace IDs from Accepted Proposal)

| ID (`generated`) | Requirement / acceptance point | Source decision | Implementation surface | Verification | Status |
| --- | --- | --- | --- | --- | --- |
| `AC-1` | `PreInvocation` runs `task-entry.sh` and `merge-authorization-prompt.sh` once per user turn across multi-step model calls (`invocationNum: 0, 1, ...`, incrementing `initialNumSteps`), while still running on a new user turn even with identical prompt text | `in` (Turn 1 `proposed-next`) | `hooks/agy-bridge.py` (`resolve_turn_key`, `pre_invocation`) | `python3 hooks/test_agy_bridge.py` (41 OK) + live `agy` smoke (`T1`) | satisfied |
| `AC-2` | A one-shot merge grant armed on step 0 and consumed by `gh pr merge` is NOT re-armed on step 1+ of the same user turn; failed `task-entry.sh` still retries; queued notes still deliver on step 1+ | `in` (Turn 1 `proposed-next`) | `hooks/agy-bridge.py` | `python3 hooks/test_agy_bridge.py` (`T2`) | satisfied |
| `AC-3` | Editing, replacing, or `apply_patch`-deleting a symlink (target outside repo or dangling) inside a protected primary checkout (`.worktree-only` or live sibling worktree) is denied; symlink or dangling-parent symlink (including chained symlinks when `realpath` fails) into protected primary checkout is denied; symlinks in linked worktrees / solo plain repos and symlink loops outside repos stay allowed; 576 `test_hook_field_reads.py` cases stay green | `in` (Turn 1 `proposed-next`) | `hooks/host-input.py`, `hooks/guard-edit-isolation.sh` | `bash hooks/test_guard_edit_isolation.sh` (32 passed), `python3 hooks/test_host_input.py` (41 OK), `python3 hooks/test_agy_bridge.py` (41 OK), `python3 hooks/test_hook_field_reads.py` (576 OK) (`T3`–`T5`) | satisfied |
| `AC-4` | `check-agent-contract-coverage.sh` eliminates per-file `basename`/`dirname` forks (0 calls during scan, ~193ms on this repo), remains Bash 3.2 compatible, and preserves byte-identical stdout/stderr/exit codes across all modes and edge cases (`REQUIRE_BASELINE=1` in `Makefile`) | `in` (Turn 1 `proposed-next`) | `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh` | `REQUIRE_BASELINE=1 bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` (14 deterministic checks passed; 15 passed with `PERF_BOUND_MS=2000`) (`T6`, `T7`) | satisfied |
| `AC-5` | `eval/test_owner_role_audit.py`, `skills/code-review/scripts/test_kimi_packet_mcp.py`, and `skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` are wired into `Makefile` (and `_DEFAULT_EVAL_UNITTEST_MODULES`) and verified by `test_select_affected_tests.py` | `in` (Turn 1 `proposed-next`) | `Makefile`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py` | `python3 scripts/test_select_affected_tests.py` (22 OK), `python3 -m unittest eval.test_owner_role_audit` (8 OK), `python3 skills/code-review/scripts/test_kimi_packet_mcp.py` (12 OK) (`T8`) | satisfied |

### Structural Minimality Table

| New concept | Current acceptance point or hard constraint | Simpler alternative | Decision |
| --- | --- | --- | --- |
| `{ctx['key']}.active.turn` JSON state file in `hooks/agy-bridge.py` | `AC-1`, `AC-2` (`hooks/agy-bridge.py:514-546`): preserves turn key when `invocationNum > 0` and transcript is absent in tests, flushes after step 0, or exceeds `MAX_TRANSCRIPT_BYTES` (`32 MiB`) | Using `ctx['turn_id']` alone without state: fails unit tests without `transcriptPath` and re-arms grants if `USER_INPUT` scrolls past 32 MiB | `keep` |
| `candidate_paths` in `hooks/host-input.py` + `check_one_path` / `check_symlink_targets` in `hooks/guard-edit-isolation.sh` | `AC-3` (`hooks/host-input.py:206-214`, `hooks/guard-edit-isolation.sh:81-172`): preserves leaf symlink directory entry alongside resolved target across both Python normalizer and `jq`-only fallback without duplicating the 65-line structural git/worktree check | `os.path.realpath` alone (drops primary-checkout symlink location) or copy-pasting the git/worktree block twice | `keep` |
| `/`‑delimited `exclude_set` and `simple_ext_set` strings + `last_checked_dir` scalar cache in `check-agent-contract-coverage.sh` | `AC-4` (`check-agent-contract-coverage.sh:103-197` + macOS Bash 3.2 portability): O(1) literal lookup without Bash 4 `declare -A` or `eval` | Keeping nested `for` loops (still ~30× slower per segment/file) or `declare -A` (fails under Bash 3.2) | `keep` |

## Test-Layer Decision Table and Test-Case Register

| Layer | Decision | Command | Reason |
| --- | --- | --- | --- |
| `unit` | `add` + `run` | `python3 hooks/test_agy_bridge.py`, `python3 hooks/test_host_input.py`, `python3 -m unittest eval.test_owner_role_audit`, `python3 skills/code-review/scripts/test_kimi_packet_mcp.py`, `python3 scripts/test_select_affected_tests.py` | Covers `resolve_turn_key` state transitions, `candidate_paths` leaf symlink preservation, MCP packet framing, owner-role counters, and `Makefile` suite registration. |
| `integration/contract` | `add` + `run` | `bash hooks/test_guard_edit_isolation.sh`, `python3 hooks/test_hook_field_reads.py`, `bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh`, `python3 scripts/test_install_gates_runtime.py`, `npm --prefix packages/ccl-skills-npm test`, `npm --prefix packages/ccl-skills-npm run test:pack`, `CCL_BROAD_TEST_REASON=repo-required make test` | Exercises real hook scripts, synthetic git worktrees/symlinks, baseline `788470c` & `0ee3a4a` differential parity, and npm asset packaging. |
| `E2E/host smoke` | `run` | Scratch-workspace `agy -p` / `agy -c -p` multi-turn `PreInvocation` and symlink-isolation verification (`specs/hook-turn-key-and-gate-speed/evidence/validation.md`) | Proves real `agy` 1.5.14 emits `invocationNum: 0 -> 1` and `USER_EXPLICIT` `USER_INPUT` matching bridge expectations and denies primary-checkout symlink edits. |
| `manual/exploratory` | `not applicable` | — | Deterministic CLI/hook surfaces fully covered by automated unit, differential, and live `agy -p` smoke checks. |

### Test-Case Register (Run RED Before Implementation)

| ID | Scenario | Layer | Command | Pre-fix RED → Post-fix GREEN |
| --- | --- | --- | --- | --- |
| `T1` | Multi-step turn (`invocationNum: 0 -> 1`, `initialNumSteps: 1 -> 5`, `turn-0`) injects `<ccl-task-entry>` once; Turn 2 (`invocationNum: 0`, `initialNumSteps: 8`, `turn-7`) with identical prompt injects again | unit/integration | `python3 hooks/test_agy_bridge.py` | `FAIL` → `OK` |
| `T2` | One-shot `merge #123` grant consumed on step 0 is NOT re-armed when step 1 `PreInvocation` (`invocationNum: 1`, `initialNumSteps: 5`) runs; queued notes still deliver on step 1; mid-turn `turn_id=None` (`>32 MiB`) preserves key | integration | `python3 hooks/test_agy_bridge.py` | `FAIL` → `OK` |
| `T3` | `guard-edit-isolation.sh` denies editing/replacing a symlink or dangling symlink in `.worktree-only` or multi-worktree primary checkout pointing outside repo, and denies dangling leaf/parent/chained symlink outside repo pointing into `.worktree-only` uncreated subdir (both Python normalizer and `jq`-only/no-`realpath` fallback) | integration | `bash hooks/test_guard_edit_isolation.sh`, `python3 hooks/test_host_input.py` | `FAIL` (`3 failed` initial + `1 failed` chained `p6l`) → `PASS` (`32 passed, 0 failed`; `41 OK`) |
| `T4` | Precision/spare probes: symlink in linked worktree pointing outside repo → quiet `allow`; symlink in solo plain primary checkout pointing outside repo → quiet `allow`; symlink cycle outside repo → quiet `allow` | integration | `bash hooks/test_guard_edit_isolation.sh` | `PASS` → `PASS` |
| `T5` | `agy-bridge.py` `apply_patch` `*** Delete File:` on a tracked symlink in `.worktree-only` primary checkout pointing outside repo → `deny` | integration | `python3 hooks/test_agy_bridge.py` | `FAIL` → `OK` |
| `T6` | `check-agent-contract-coverage.sh` spawns 0 external `basename`/`dirname` calls while matching baseline `0ee3a4a` stdout/stderr/exit codes (`REQUIRE_BASELINE=1`) across `--check`, `--enforce`, `--fix`, `--source-ext` (`.tf`, `.d.ts`, `Dockerfile`), `--exclude` (`gen*` literal), dotfiles, spaces, dash-prefixed files, symlinks, non-git, and group-parent exit `2` | integration/differential | `REQUIRE_BASELINE=1 bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` | `FAIL` (`8 failed`, 5,536 forks) → `PASS` (`14 passed`, 0 forks, 0 skipped) |
| `T7` | Full-repo `check-agent-contract-coverage.sh --repo . --enforce` completes in `< 2.0s` (`PERF_BOUND_MS=2000` opt-in check) with `agent contract coverage ok` | integration | `PERF_BOUND_MS=2000 REQUIRE_BASELINE=1 bash skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` | `FAIL` (`11,279ms` shimmed / ~7.8s raw) → `PASS` (`15 passed`, `~193ms`) |
| `T8` | `makefile_suites(REPO_ROOT)` contains `eval/test_owner_role_audit.py`, `skills/code-review/scripts/test_kimi_packet_mcp.py`, and `skills/product-rd-workflow/scripts/test_check_agent_contract_coverage.sh` | unit/contract | `python3 scripts/test_select_affected_tests.py` | `FAIL` → `OK` |

## Target-Output and Owner-Generalization Map

| Owner / target | Editability | Direction | Status | Changed file or reason |
| --- | --- | --- | --- | --- |
| `hooks/agy-bridge.py`, `hooks/test_agy_bridge.py` | editable CCL target | runtime / test | `updated` | `PreInvocation` `resolve_turn_key` fix + multi-step merge-rearm and symlink-delete tests |
| `hooks/host-input.py`, `hooks/test_host_input.py`, `hooks/guard-edit-isolation.sh`, `hooks/test_guard_edit_isolation.sh` | editable CCL target | runtime / test | `updated` | Preserve leaf symlink directory entry + check resolved/dangling leaf and parent symlink targets + recall/precision/`jq`-only probes |
| `skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh`, `test_check_agent_contract_coverage.sh`, `AGENTS.md` | editable CCL target | upstream owner script / test / contract | `updated` | Pure-Bash 3.2 scan loop, differential + zero-fork suite, validation command in directory `AGENTS.md` |
| `Makefile`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py` | editable CCL target | CI / test harness | `updated` | Wire `eval.test_owner_role_audit`, `test_kimi_packet_mcp.py`, and `test_check_agent_contract_coverage.sh` |
| `skills/skill-extraction-workflow/references/source-register.md` | editable CCL target | provenance / impact-chain | `updated` | Impact-chain `RED-baseline` row for `product-rd-workflow` script change |
| `skills/agents-file-coverage-gate` | editable CCL target | downstream runner skill | `unchanged` | Invokes `product-rd-workflow/scripts/check-agent-contract-coverage.sh` with unchanged CLI flags and exit codes |
| `scripts/install-gates.sh` | editable CCL target | downstream installer | `unchanged` | Vendors `check-agent-contract-coverage.sh` by source path at install time; tested via `test_install_gates_runtime.py` |
| `packages/opencode-plugin`, `hooks/hooks.json` | editable CCL target | sibling host adapters | `unchanged` | Claude/Codex `UserPromptSubmit` already fires once per user prompt; OpenCode uses `chat.message` / system transform; all four hosts share `host-input.py` and `guard-edit-isolation.sh` |
| `hooks/AGENTS.md` | editable CCL target | directory contract | `unchanged` | Existing contract already specifies `agy-bridge.py` protocol role and `test_hook_field_reads.py` `788470c` baseline |
| `product-rd-workflow`, `testing-strategy`, `defect-diagnosis`, `feature-risk-router`, `python-service-dev`, `terminal-cli-dev`, `code-review`, `tighten-doc` | editable CCL target | process / stack / review owners | `unchanged` | Existing rules governed this slice directly; no missing skill-level rule identified |
| Built-in Antigravity host skills (`agy-customizations`, `antigravity-guide`, `run-workflow`, `swarm_*`) | reference-only external/system skill | host docs | `unchanged` | Used read-only as primary host specification (`docs/hooks.md`) |
