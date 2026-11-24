# Bash Hot-Path Lazy Evaluation & Inner-Loop Gate Slimming

## Binding Proposal & Scope

Initial repository-wide audit of `<repo-root>` at `827f7f684b41842452ca6af3421a45f3e4d364ef` recommended `方向 1` as the default next slice; affirmative user continuation (`继续优化`) bound scope to that verbatim proposal:

> 下一步建议按以下四个方向推进（默认优先做 **方向 1**）：
> ### 1. 会话 `Bash` 热路径与内环门禁再削峰（推荐首选）
> 1. **`PreToolUse:Bash` 两个最慢钩子按需惰性化（当前 6 钩子串行中位 `331.1 ms`）**
>    - **`owner-dispatch-guard.sh`（每次 `Bash` 占 `117.1 ms`）**：
>      - owner-dispatch.sh 的 `cmd_pretool` 在检查 `.owner-dispatch.json` 是否存在前就先启动 `jq`，未兑现该文件头 L18“未启用仓库先做纯文件探测、零 `git`/`jq` 开销”的设计。
>      - owner-dispatch-guard.sh 每次无条件调用 skill-loading.py，在禁用字节码缓存下每次从源码重编译 1,515 行的 host-input.py（实测仅导入占 `54.2 ms`）。而 `Bash` 分支只对写入 `ccl-skills` 检出内 `skills/|hooks/|scripts/` 的命令生效，普通业务仓或无写操作特征的命令可提前放行。
>    - **`guard-merge-authorization.sh`（每次 `Bash` 占 `75.4 ms`，其余单 `jq` 钩子仅 `~34 ms`）**：
>      - guard-merge-authorization.sh 对任何命令（含 `pytest`、`ls`、`rg`、`git status`）都先无条件跑 **4 次 `git` + 1 次 `sed`** 读取 `origin/HEAD` 与当前分支。这组变量仅在 L976–L987（`git` 段）和 L1284 使用，改为命中对应分支时惰性求值即可省去约 `40 ms`，且无需引入新 shell 词法预筛器（不触碰 `pretool-dispatch` 的 plan.md 已否决的统一调度器或并发竞态方案）。
>    - **宿主桥接冗余与目录边界**：
>      - agy-bridge.py 与 ccl-skills.ts 在 Stop/idle 仍每次 fork 在该宿主恒为空操作的 headless-background-stop.sh；ccl-skills.ts 每次编辑前连跑 3 次 `git rev-parse`，可合并为单次调用。
>      - host-input.py 的 `AGENT_DOC_DIRS` 未排除 Antigravity 会话私有临时目录（`brain/<id>/scratch/*.md`），会把内部草稿误判为面向读者的交付文档并触发 Stop 拦截。
> 2. **内环最慢的两个门禁脚本提速（`7.26s` + `1.95s`）**
>    - check-spec-references.py（实测 **`1.95s`**，当前第二慢门禁）：对全仓约 2,800 个跟踪文件逐行切分并跑正则。配对实测全仓仅 **86 个文件**含反引号加 specs/ 前缀或豁免项，加入字节级 `b"\x60specs/"` 预筛与目标路径 `resolve()` 缓存后仅需 **`0.36s`**（提速 `>5x`，零语义变化）。
>    - check-ccl-skills.sh（实测 **`7.26s`**）：
>      - check-size-budget.sh 占 **`2.03s`**：33 次 `git show` 循环改单次 `git cat-file --batch` 实测 `308.8 ms → 30.0 ms`，另有 20+ 次 `git diff/ls-files` 子进程可合并。
>      - validate-skill.sh 的 33 次逐目录 `rg` 合并为单次调用可省 `0.40s`。
>      - 主脚本内联 Anti-pattern 27/28 逐 `.sh` 文件 `grep` 循环，以及未加 SHA-256 缓存戳的 generic-r0-leak-scan.sh `--self-test`（对齐旁边的 `--self-test-cached`）一并收敛后，可将 `check-ccl-skills.sh` 压至 **`~3s` 以内**。

Non-goals and preserved rejection boundaries:
- Do not revive any approach rejected in `specs/pretool-dispatch/plan.md`: no user-writable `.pyc` cache, no concurrent `PreToolUse` hook execution, and no unified `PreToolUse` dispatcher.
- Do not modify `hooks/test_hook_field_reads.expected.json` (which holds baseline `788470c` and Darwin calibration entries).
- Do not skip `headless-background-stop.sh` in `packages/opencode-plugin/ccl-skills.ts`: re-deriving against `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` (`L123-145`, `L317`) shows OpenCode `session.idle` explicitly asserts 1:1 execution of every `Stop` command hook in `hooks/hooks.json` with `CLAUDE_CODE_ENTRYPOINT` scrubbed (`headless-background-stop.sh` already exits `0` in ~1.5 ms pure shell when unset). Skip the subprocess only in `hooks/agy-bridge.py:stop()` when `CLAUDE_CODE_ENTRYPOINT` does not match `sdk|sdk-*`, while retaining `headless-background-stop.sh` in `DISPATCH['Stop']` so `--bindings` parity holds.
- Stop after Ready PR creation and green GitHub Actions checks; do not merge to `main` or publish npm packages.

## Extraction Charter

| Field | Decision |
| --- | --- |
| Triggering task / artifact | Repository-wide latency and hygiene audit of `PreToolUse:Bash` hooks, host bridges, and inner-loop deterministic gates at `827f7f684b41842452ca6af3421a45f3e4d364ef` |
| Observed failure or friction | (1) Every `PreToolUse:Bash` call pays ~331 ms serially across 6 hooks because `owner-dispatch.sh` spawns `jq` + `dirname` even in non-opted-in repos, `skill-loading.py` imports and compiles 1,515-line `host-input.py` (`sys.dont_write_bytecode = True`) even on non-write `Bash` commands, and `guard-merge-authorization.sh` spawns 4 `git` + 1 `sed` calls on every non-git/non-landing command; (2) `agy-bridge.py` spawns `headless-background-stop.sh` on every `Stop`, `ccl-skills.ts` spawns 3 `git rev-parse` calls per edit, and `host-input.py:reader_docs` misclassifies Antigravity `brain/<id>/scratch/*.md` notes as reader-facing deliverables; (3) `check-spec-references.py` (`~1.0–1.95s`) splits and regex-scans ~2,800 tracked files without byte prefiltering, and `check-ccl-skills.sh` (`~7.26s`) spawns ~60 `git` calls in `check-size-budget.sh`, 33 `rg` calls in `validate-skill.sh`, 250+ per-file `grep` calls in Anti-pattern 27/28, and an uncached `generic-r0-leak-scan.sh --self-test` on every run |
| Generalizable mechanism | Lazy resource acquisition and byte/tree batching behind sound over-approximating prefilters: defer `jq`/`git`/`host-input.py` loading until opt-in or write/landing predicates hold; batch `git rev-parse`, `git cat-file --batch`, `rg`, and Ruby file scans; cache `generic-r0-leak-scan.sh --self-test` by `0700` per-UID SHA-256 stamp while running uncached `--self-test` in `make test-repo-gates`; exclude `brain/<id>/scratch/` from reader-doc closeout |
| Candidate owner skill(s) | `skill-extraction-workflow` (plugin runtime surface + validator scripts), coordinated with `product-rd-workflow`, `testing-strategy`, `python-service-dev`, `nodejs-service-dev`, `typescript-dev`, `terminal-cli-dev`, `tighten-doc`, `code-review`, `worktree-isolation` |
| Entrypoint capacity | All `skills/*/SKILL.md` and `agent-context/session-start.md` unchanged (`0` byte/word delta); changes land in `hooks/`, `scripts/`, `packages/opencode-plugin/`, `skills/skill-extraction-workflow/scripts/`, `Makefile`, local `AGENTS.md` contracts, and `source-register.md` |
| Why shared-skill / plugin runtime vs memory-only | Hook latency, Antigravity scratch false-blocks, and gate execution times affect every contributor and host session automatically; memory cannot alter runtime hooks or CI/local gate speed |
| Out-of-scope / rejected designs | Rejected in `specs/pretool-dispatch/plan.md`: `.pyc` cache dirs, concurrent `PreToolUse` execution, unified `PreToolUse` dispatcher. Out of scope: OpenCode `Stop` hook skipping (pinned by `opencode-hooks.test.mjs`), `test_hook_field_reads.expected.json` edits, merging PR or npm publish |
| Verification tier | RED-first unit/integration assertions (`T1`–`T5`), paired `N=7` wall-clock benchmarks (`origin/main` vs candidate), applied differential killing-mutation walk outside the worktree, full local `make test` + `--heavy-only` + `npm test` + `test:pack` + private R0 audit, and independent review + adversarial challenge |
| R0 leakage boundary | Public repository: synthetic paths, dummy tokens, and neutral engineering prose only; zero session IDs/links, model names, personal paths, or internal hostnames on shared Git or tracked surfaces |

## Shared-Gate Artifact Classification & Implementation Boundary

- **Artifact class**: `gate implementation` (`scripts/check-spec-references.py`, `skills/skill-extraction-workflow/scripts/{check-ccl-skills.sh,check-size-budget.sh,validate-skill.sh,generic-r0-leak-scan.sh}`, `Makefile`) + `runtime/code` (`scripts/owner-dispatch/owner-dispatch.sh`, `hooks/{skill-loading.py,guard-merge-authorization.sh,agy-bridge.py,host-input.py}`, `packages/opencode-plugin/ccl-skills.ts`) + `contract/ledger` (`hooks/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`, `skills/skill-extraction-workflow/references/source-register.md`).
- **Verifier discovery**: `hooks/test_hook_field_reads.py`, `hooks/test_hook_remaining_field_reads.py`, `hooks/test_skill_loading.py`, `hooks/test_guard_merge_authorization.sh`, `hooks/test_agy_bridge.py`, `hooks/test_proposed_next.py`, `hooks/test_host_input.py`, `packages/ccl-skills-npm/test/opencode-hooks.test.mjs`, `scripts/test_check_spec_references.py`, `scripts/test_lane_isolation.py`, `scripts/check-repo-hygiene.py`, `skills/skill-extraction-workflow/scripts/{test_check_ccl_size_budget.sh,test_validate_skill_credential_cwd.sh,test_validate_skill_root_depth.sh,test_git_identity_predicate_gate.sh,test_liveness_predicate_gate.sh,test_generic_r0_leak_scan.sh,test_check_ccl_r0_status.sh}`.
- **Implementation boundary**: Isolated linked worktree `.work/worktrees/bash-hotpath-and-gate-slimming` on branch `ccoalm/bash-hotpath-and-gate-slimming` from `origin/main` (`827f7f684b41842452ca6af3421a45f3e4d364ef`). Primary checkout stays untouched.

## Risk Classification (`feature-risk-router`)

- Risk tags: `shared-gate`, `permission-access` (pre-tool guards), `client-plumbing` (Antigravity & OpenCode host adapters).
- `security-review: not-applicable — security posture unchanged` (every optimization is a conservative over-approximation preserving existing deny/block/warn/waiver/stale verdicts and fail-closed error handling across tested input classes).
- Required gates: RED-first deterministic tests, paired baseline parity (`788470c` via `test_hook_field_reads.py`), applied killing-mutation walk, private R0 audit (`ccl_skill_check_clean_ok`), full repo gates + heavy regressions + npm package tests, dual-track independent review + adversarial challenge, and green PR CI checks before handoff.

## Pre-Cover, Security Four Questions & Mechanism Operability

### Pre-Cover Six Axes
1. **Inputs & adversarial encodings**: JSON escapes (`\u0000`, `\"`, `\u0045dit`), NUL bytes on stdin (`test_hook_field_reads.py` stderr warning), shell quoting/splitting (`r'm'`, `"cp"`, `python3<<EOF`, `\rm`, `(mv ...)`), non-UTF-8 tracked files/filenames (`surrogateescape` / binary `File.binread`), newline-containing `.sh` filenames (`p9`), CR/CRLF reference files (`g10`), directory names with spaces/colons.
2. **State & concurrency**: `skill-loading.py` lazy normalizer stays local to each `handle()` call so `patch.object(module, 'normalizer', ...)` and per-invocation state remain isolated; `generic-r0-leak-scan.sh --self-test-cached` uses atomic `mktemp` + `mv -f` inside a `0700` uid-owned directory.
3. **Failure modes & fail-closed behavior**: Missing/unreadable skill roots in `validate-skill.sh` still exit `1` with `credential_path_scan_error`; unreadable `.sh` files or unwalkable subdirs in Anti-pattern 27/28 still exit `1` with `*_scan_error`; broken `generic-r0-leak-scan.sh` mutants never write a `.ok` stamp; `ccl-skills.ts` falls back to 3-call `rev-parse` if combined output has `!= 3` lines (e.g. newline in repo path).
4. **Compatibility & host contracts**: `agy-bridge.py --bindings` and `OPENCODE_HOOK_BINDINGS` remain 1:1 with `hooks/hooks.json`; `check-spec-references.py` keeps `from _repo_text import display`; all shell test `mktemp` calls use `"${TMPDIR:-/tmp}/...XXXXXX"` (`test_lane_isolation.py`).
5. **Observability & diagnostics**: Existing stdout/stderr diagnostic tokens in `check-size-budget.sh`, `validate-skill.sh`, `check-ccl-skills.sh`, `generic-r0-leak-scan.sh`, `check-spec-references.py`, `owner-dispatch.sh`, and `guard-merge-authorization.sh` are preserved on tested paths.
6. **Rollout & rollback**: Self-contained single-branch change; `CCL_SKILL_NO_SELFTEST_CACHE=1` bypasses self-test stamp caching at runtime.

### Security Four Questions
1. **Trust boundary crossed?** Hook stdin payloads, repository file paths/contents, and `TMPDIR` cache directories.
2. **How could a crafted input bypass a guard via the new fast path?**
   - `owner-dispatch.sh`: JSON `\uXXXX` escape hiding `Edit`/`Write`/`apply_patch` -> blocked by requiring `*\\*` to take the `jq` path.
   - `skill-loading.py`: shell quote splitting (`r'm'`), path prefix (`/bin/cp`), heredoc without space (`python3<<EOF`), or backslash (`\rm`) hiding a write command -> blocked by returning `True` whenever `\` or `>` is present and otherwise matching `BASH_WRITE_HINT_RE` after stripping `'`/`"` with `[\s;&|<>()/]` boundaries.
   - `guard-merge-authorization.sh`: `git -C <bad> push` falling back to `cwd` branch -> `ensure_base_git_context` runs before every `base_*` read in `push|merge|pull` AND before the `L1284` degrade check when `masked` matches `git ... (push|merge)`.
   - `generic-r0-leak-scan.sh --self-test-cached`: shared `/tmp` symlink/permissions -> requires `! -L`, `-d`, `-O`, and mode `700`, else runs uncached `run_self_test`.
3. **Secrets / PII exposure?** None read or persisted; stamp files store only the 64-hex SHA-256 of `generic-r0-leak-scan.sh`.
4. **Blast radius on failure?** Guards fail closed; cache validation failures fall back to uncached `run_self_test`.

### Mechanism-Operability Four Legs (for Fast-Paths & Stamp Cache)
1. **Reachability**: Common non-opted-in `Bash`, non-write `Bash`, non-landing `Bash`, non-citing tracked files, and warm `check-ccl-skills.sh` runs hit the fast path on every invocation.
2. **Discrimination**: Any opt-in marker, write token/escape/redirect, `git push|merge|pull`, `b"\x60specs/"` citation, waived ledger path, or 1-byte detector edit deterministically takes the full verification path.
3. **Non-masking**: Uncached `generic-r0-leak-scan.sh --self-test` runs unconditionally in `Makefile` `test-repo-gates`; opted-in `owner-dispatch.sh` `Bash` still runs the merged payload `jq` read (`>=1` `jq` asserted on `sb.prod`).
4. **Observability**: Subprocess-count shims (`jq`, `dirname`, `git`, `rg`, `grep`) and mock spies (`normalizer`, `CITATION_RE`) directly observe fast-path activation vs full-path execution.

## Verdict Decision Tables

| Component | Input Condition | Expected Fast/Full Path | Verdict / Side Effect |
| --- | --- | --- | --- |
| `owner-dispatch.sh` `cmd_pretool` | `$# == 0`, `${#input} <= 65536`, no `.owner-dispatch.json` in `$PWD` ancestors, `$input` lacks `\`, `Edit`, `Write`, `apply_patch` | Skip `jq` (`0` `jq`, `0` `dirname`) | `allow_pretool` (`exit 0`, NUL warning on `input=$(cat)` preserved) |
| `owner-dispatch.sh` `cmd_pretool` | Opted-in repo OR `${#input} > 65536` OR `$input` has `\` / `Edit` / `Write` / `apply_patch` | Single merged payload `jq` read (`1` pretool `jq`; `3` total on `sb.prod` with `.owner-dispatch.json` reads) | Parity with `788470c` across all `test_hook_field_reads.py` cases |
| `skill-loading.py` `handle` | `PreToolUse:Bash` with command lacking `\`, `>`, and `BASH_WRITE_HINT_RE` after quote strip | Skip `normalizer()` (`host-input.py` not loaded) | Return `base` unchanged |
| `skill-loading.py` `handle` | `PreToolUse:Bash` with redirect, backslash, or write/interpreter/shell command (incl. `r'm'`, `python3<<EOF`, `/bin/cp`) | Lazy-load `normalizer()` once | Full `bash_write_targets` + `shared_skill_paths` checkpoint |
| `guard-merge-authorization.sh` | Non-landing command (`ls`, `pytest`, `git status`, `git diff`, `git checkout -b`, `gh pr view`) | `ensure_base_git_context` not called (`0` `git` spawns) | Allow (`exit 0`) |
| `guard-merge-authorization.sh` | `git push|merge|pull` or `masked` matches `git ... (push|merge)` | `ensure_base_git_context` loads `base_*` once | Identical allow/deny + unset-`origin/HEAD` `systemMessage` |
| `agy-bridge.py` `stop()` | `CLAUDE_CODE_ENTRYPOINT` unset / not `sdk\|sdk-*` | Skip spawning `headless-background-stop.sh`; keep in `DISPATCH['Stop']` | Identical Stop verdict; `--bindings` unchanged |
| `ccl-skills.ts` `blockReason` | Edit on linked worktree or primary checkout | Combined `git rev-parse --show-toplevel --git-dir --git-common-dir` (`1` call; fallback on `!= 3` lines) | Identical allow on linked worktree / block on protected primary checkout |
| `host-input.py` `reader_docs` | Path contains `.../brain/<id>/scratch/...` | Excluded as agent scratch | Not returned by `reader_docs` |
| `host-input.py` `reader_docs` | `.../brain/<id>/walkthrough.md` or `docs/*.md` | Kept as reader-facing doc | Returned by `reader_docs` |
| `check-spec-references.py` | Tracked regular file with `pins_here is None` and `b"\x60specs/" not in raw_bytes` | Skip UTF-8 decode, `splitlines`, and `CITATION_RE` | `0` findings; `escapes_root` + `.exists()` memoized per target |
| `check-spec-references.py` | Waived file (`pins_here is not None`) or file containing `b"\x60specs/"` | Full line/digest/citation scan | Identical findings, applied waivers, and stale-pin errors |
| `check-size-budget.sh` | Git worktree root (`--show-toplevel` matches `root`) with resolvable `base` | `1` `rev-parse --show-toplevel`, `1` `ls-tree --full-tree -r -z`, `1` `cat-file --batch`, `0` `git show`, consolidated `diff`/`ls-files`; nested exports downgrade to `not-a-git-worktree` | Byte-identical stdout/stderr tokens and exit codes |
| `validate-skill.sh` | Multi-root skill tree | Pre-check each root `cd` + `[ -r . ]`, then `1` `rg` across all roots | Identical offender lines and `credential_path_scan_error` fail-closed exit |
| `check-ccl-skills.sh` AP 27/28 | `hooks/` + `scripts/` / repo `.sh` files | `find -L ... -print0` + `1` binary-safe Ruby pass (`0` per-file `grep` forks) | Identical file:line hits, carve-outs, and `*_scan_error` fail-closed exits |
| `generic-r0-leak-scan.sh` | `--self-test-cached` (`check-ccl-skills.sh`) vs `--self-test` (`Makefile`) | `0700` per-UID SHA-256 stamp cache (batched `run_self_test` on cold/uncached) | Warm hit prints `generic_r0_leak_scan_self_test_ok` with `0` `rg` spawns; `Makefile` runs uncached `--self-test` |

## Objective Closure, Functional Completeness & Structural Minimality

| ID | Criterion | Verification Oracle |
| --- | --- | --- |
| `AC-1` | `owner-dispatch.sh` spawns `0` `jq` and `0` `dirname` on `<= 64 KiB` non-opted-in `Bash` while preserving `788470c` parity and opted-in merged payload `jq` (`>=1` `jq` on `sb.prod`); `skill-loading.py` skips `normalizer()` on non-write `Bash` while catching quoted/escaped/heredoc/path-prefixed writes | `hooks/test_hook_field_reads.py` + `hooks/test_skill_loading.py` + `N=7` paired timing |
| `AC-2` | `guard-merge-authorization.sh` spawns `0` `git` processes on non-landing commands while preserving all merge/push/pull and unset-`origin/HEAD` degrade behavior | `hooks/test_guard_merge_authorization.sh` + `hooks/test_hook_field_reads.py` + `N=7` paired timing |
| `AC-3` | `agy-bridge.py:stop()` skips `headless-background-stop.sh` unless `CLAUDE_CODE_ENTRYPOINT` is `sdk\|sdk-*` (preserving `--bindings`); `ccl-skills.ts` uses 1 `git rev-parse` call per edit; `host-input.py:reader_docs` excludes `brain/<id>/scratch/**` while keeping `brain/<id>/walkthrough.md` | `hooks/test_agy_bridge.py`, `packages/ccl-skills-npm/test/opencode-hooks.test.mjs`, `hooks/test_proposed_next.py` |
| `AC-4` | `check-spec-references.py` prefilters by `b"\x60specs/"` (after registering waived paths) and memoizes target resolution/containment, cutting runtime with zero semantic change | `scripts/test_check_spec_references.py` + `N=7` paired timing |
| `AC-5` | `check-ccl-skills.sh` batches `check-size-budget.sh` (`cat-file --batch`), `validate-skill.sh` (`1` `rg`), Anti-pattern 27/28 (`0` `grep` loops), and `generic-r0-leak-scan.sh --self-test-cached` (+ uncached `--self-test` in `Makefile`), cutting warm runtime substantially | `test_check_ccl_size_budget.sh`, `test_validate_skill_credential_cwd.sh`, `test_git_identity_predicate_gate.sh`, `test_liveness_predicate_gate.sh`, `test_generic_r0_leak_scan.sh` + `N=7` paired timing |
| `AC-6` | Local contracts (`hooks/AGENTS.md`, `skills/skill-extraction-workflow/scripts/AGENTS.md`) and `source-register.md` reflect the landed behavior, all repo/heavy/npm/R0/surface gates pass, and dual-track review + challenge reach clean consensus | Full gate matrix + `ccl_skill_check_clean_ok` + review/challenge receipts |

Structural minimality check: zero new standalone runtime files or unregistered test suites; every change edits the exact existing script and extends its existing CI-registered test suite.

## Test-Layer Decision Table & RED-First Test Register

| ID | Target Suite | Layer | New Assertion | Expected Pre-Fix Status |
| --- | --- | --- | --- | --- |
| `T1a` | `hooks/test_hook_field_reads.py` | Integration / Baseline differential | `JQ_SAVED["engine-bash"] = 5` (`0` `jq` & `0` `dirname` on non-opted-in `Bash`), `>=1` `jq` on opted-in `sb.prod` `Bash` | **RED** (`engine-bash starts 1 jq processes; at most 0 expected`) |
| `T1b` | `hooks/test_skill_loading.py` | Unit + Subprocess | `normalizer()` called `0` times on non-write `Bash` (`ls`, `pytest`, `git status`, `git diff`, `rg`, `gh`), and called `1` time on write-capable `Bash` (`r'm'`, `python3<<EOF`, `/bin/cp`, `>`, `\rm`) | **RED** (`normalizer()` called on `ls`) |
| `T2` | `hooks/test_guard_merge_authorization.sh` | Subprocess shim | `GIT_COUNT_FILE` shim records `0` `git` spawns on `ls -la`, `pytest -q`, `git status`, `git diff`, `git checkout -b feat`, `gh pr view 45`, and `>0` on `git push` | **RED** (`3`–`4` `git` spawns per non-landing command) |
| `T3a` | `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` | Plugin integration | `git` shim records `1` `rev-parse` call per edit on a linked worktree (vs `3`), while primary `.worktree-only` checkout still rejects | **RED** (`3` `rev-parse` calls) |
| `T3b` | `hooks/test_agy_bridge.py` | Bridge unit/subprocess | `Stop` skips `headless-background-stop.sh` when `CLAUDE_CODE_ENTRYPOINT` is unset, runs it when `CLAUDE_CODE_ENTRYPOINT=sdk-ts`, and keeps `--bindings` intact | **RED** (`headless-background-stop.sh` invoked when unset) |
| `T3c` | `hooks/test_proposed_next.py` | Unit | `reader_docs` excludes `<cwd>/brain/<id>/scratch/notes.md` and `/var/lib/agy/brain/<id>/scratch/plan.md`, while keeping `<cwd>/brain/<id>/walkthrough.md` and `docs/guide.md` | **RED** (`scratch/notes.md` included in `reader_docs`) |
| `T4` | `scripts/test_check_spec_references.py` | Unit | Spying `CITATION_RE` confirms `0` line scans on non-waived files without `b"\x60specs/"` while preserving waived-file staleness, invalid-UTF-8 scan, and target memoization | **RED** (`CITATION_RE` called on non-citing files) |
| `T5` | `test_check_ccl_size_budget.sh`, `test_validate_skill_credential_cwd.sh`, `test_git_identity_predicate_gate.sh`, `test_liveness_predicate_gate.sh`, `test_generic_r0_leak_scan.sh` | Subprocess shim + cache matrix | `0` `git show` in size gate; `1` `rg` across 3 skill roots in `validate-skill.sh`; `0` `grep` forks in AP 27/28; 8-case `--self-test-cached` contract + `Makefile` uncached `--self-test` wiring | **RED** across all 5 suites |
| `T6` | Full gate matrix + `N=7` benchmarks + mutation walk | End-to-end verification | `make test`, `check-skill-count.py`, `--heavy-only`, `npm test`, `test:pack`, private R0 `ccl_skill_check_clean_ok`, `shared_git_surface_gate.py`, killing-mutation walk | Post-implementation gate |

## Target-Output & Provenance-to-Target Map

| Finding / Sub-item | Target File(s) | Owning Verifier(s) |
| --- | --- | --- |
| Non-opt-in `owner-dispatch.sh` `Bash` fast-path + pure-Bash `find_config_dir` | `scripts/owner-dispatch/owner-dispatch.sh`, `hooks/AGENTS.md` | `hooks/test_hook_field_reads.py` |
| Lazy `normalizer()` + `may_write_from_bash` prefilter | `hooks/skill-loading.py` | `hooks/test_skill_loading.py` |
| Lazy `ensure_base_git_context` in merge guard | `hooks/guard-merge-authorization.sh` | `hooks/test_guard_merge_authorization.sh`, `hooks/test_hook_field_reads.py` |
| Antigravity `Stop` skip of `headless-background-stop.sh` | `hooks/agy-bridge.py`, `hooks/AGENTS.md` | `hooks/test_agy_bridge.py` |
| Single `git rev-parse` in OpenCode isolation check | `packages/opencode-plugin/ccl-skills.ts` | `packages/ccl-skills-npm/test/opencode-hooks.test.mjs` |
| Exclude `brain/<id>/scratch/` from `reader_docs` | `hooks/host-input.py` | `hooks/test_proposed_next.py` |
| `b"\x60specs/"` byte prefilter + `resolve()` memoization | `scripts/check-spec-references.py` | `scripts/test_check_spec_references.py` |
| `git cat-file --batch` + consolidated diff scans | `skills/skill-extraction-workflow/scripts/check-size-budget.sh` | `skills/skill-extraction-workflow/scripts/test_check_ccl_size_budget.sh` |
| Batched multi-root `rg` credential scan | `skills/skill-extraction-workflow/scripts/validate-skill.sh` | `skills/skill-extraction-workflow/scripts/test_validate_skill_credential_cwd.sh` |
| Single-pass Ruby Anti-pattern 27/28 scans | `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | `test_git_identity_predicate_gate.sh`, `test_liveness_predicate_gate.sh` |
| `generic-r0-leak-scan.sh --self-test-cached` + `Makefile` uncached `--self-test` | `generic-r0-leak-scan.sh`, `check-ccl-skills.sh`, `Makefile`, `scripts/AGENTS.md`, `source-register.md` | `test_generic_r0_leak_scan.sh`, `test_check_ccl_r0_status.sh` |
