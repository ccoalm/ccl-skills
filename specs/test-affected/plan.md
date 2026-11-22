# Affected-Test Selector for the Inner Loop

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Provide fast advisory inner-loop feedback (`make test-affected`, `make test-affected-plan`, `scripts/select-affected-tests.py`) over changed repository paths without claiming soundness or weakening `make test` and CI gates, and harden the tool against shell/Make argument injection, Git environment/template/hook leakage, base-resolution and snapshot races, non-reversible raw-byte paths, symlink/loop/TOCTOU escapes, silent discovery errors, uncollected pytest modules, and orphaned child process groups. |
| Scope | In: `Makefile` (`test-affected`, `test-affected-plan`), `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `docs/CONTRIBUTING.md` (one-line pointer), and `specs/test-affected/`. Out: changing `make test`, CI workflows, runtime hooks, distributed npm assets (`packages/ccl-skills-npm`), or any `skills/` text. No iterative-program `covered-through` watermark applies. |
| Depth | Generator/tooling change: deterministic repository developer CLI and its unit/integration test suite; no skill or hook rule changes. |
| Result classification | Failure/correction (`specs/test-affected/evidence/review-R1.json`, `specs/test-affected/evidence/design-review-D1.json`, `specs/test-affected/evidence/design-review-D2.json`, `specs/test-affected/evidence/review-R2.json`). Disconfirming observation: any case where the tool shell-evaluates Make inputs, silently drops failed Git queries or corrupt integration refs, mutates caller Git state or runs user hooks in child fixtures, executes paths outside `--repo`, shadows remote-tracking refs with local branches, loses raw-byte filename fidelity, or emits a gate-passing `ok` token. |
| Matching analysis | Contributing factors: (1) claiming "minimal sound set" required tracking undocumented cross-directory file-to-test reads across the whole repo; (2) Makefile recipes interpolated `AFFECTED_ARGS` and `CCL_SKILL_DEFAULT_BASE_REF` through `/bin/sh`; (3) Git discovery and child execution inherited caller `GIT_*` routing/graph/replace/config variables and user `~/.gitconfig` / template hooks; (4) base lookup used short refs, skipped `--files` env validation, ignored corrupt ref objects when peer refs resolved, and re-read symbolic refs instead of pinned commit SHAs; (5) containment checks missed dedicated serial commands, Make fallback escalation, symlink loops, and dispatch-time TOCTOU swaps; (6) Python entrypoint detection treated module-level setup expressions as test runners. Prevention: position explicitly as advisory inner-loop feedback with a mandatory footer, pass Make variables via target-scoped environment exports, isolate Git config/templates across discovery and child execution, pin commit snapshots fail-closed, enforce containment at planning and dispatch across all command classes, parse Python entrypoints via `ast`, and forward termination signals to active child process groups. |
| Failure mode or success boundary | A weak implementation would let contributors mistake a green inner-loop run for `make test`, execute shell metacharacters in `AFFECTED_ARGS`, corrupt a caller's `GIT_INDEX_FILE` or trigger global Git hooks during suite runs, follow a symlink outside the worktree, break `--json` or `--dry-run` consumers on non-UTF-8 or control-bearing paths, or pass a failing pytest module with exit `0`. |
| Lifecycle impact | Implementation, debugging, and local testing inner loop in this repository; contributor onboarding (`Makefile` help and `docs/CONTRIBUTING.md`). Product intent, design/UX, launch/release, observability, and external source-less npm users: unchanged (`scripts/select-affected-tests.py` is not packaged into npm). |
| Evidence plan | Produced artifacts inspected first: `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `Makefile`, `specs/test-affected/evidence/review-R1.json`, `specs/test-affected/evidence/design-review-D1.json`, `specs/test-affected/evidence/design-review-D2.json`, `specs/test-affected/evidence/review-R2.json`. Repository contracts and peers inspected: `AGENTS.md`, `scripts/AGENTS.md`, `docs/CONTRIBUTING.md`, `scripts/run-parallel-suites.sh`, `scripts/test_lane_isolation.py`, `scripts/test_check_markdown_links.py`, `scripts/test_check_spec_references.py`, `hooks/test_remind_review_covers_head.sh`, `skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py`, `skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh`, `skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh`, `.github/workflows/ci.yml`, `packages/ccl-skills-npm/scripts/build-assets.mjs`. |
| Completion standard | Unit/integration suite fails RED against pre-fix baselines (`b9a3366` and `36fafa6`) and passes `22/22` under `python3 -W error`; 22-mutant killing walk passes in a disposable copy; `make test-affected-plan`, `make test-affected`, `CCL_BROAD_TEST_REASON=repo-required make test`, `check-public-sanitization.py`, and `shared_git_surface_gate.py --base-ref origin/main` pass; independent `code-review` review and adversarial challenge converge before PR and merge to `main`. |

## Role

`make test-affected` (`scripts/select-affected-tests.py`, previewed via `make test-affected-plan`) picks the preflight checks and test suites most likely to catch a regression in the files you changed, and runs them in seconds to a few minutes. It is **advisory feedback during local iteration**, not a gate:

- **Repository and directory gates remain required before push or PR:**
  - `make test` for changes to `AGENTS.md`, `README.md`, `docs/`, `skills/`, `hooks/`, `scripts/`, or plugin manifests (`AGENTS.md`).
  - Focused suites for touched scripts and packages (`npm --prefix packages/ccl-skills-npm test` and `npm --prefix packages/ccl-skills-npm run test:pack`).
  - `python3 scripts/check-public-sanitization.py .` and `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` when touching shared skill text, plus `python3 skills/skill-extraction-workflow/scripts/check_review_evidence_present.py` before opening or updating a PR that touches `skills/` or `hooks/`.
  - `make test-verify-sandbox` when touching `scripts/verify-sandbox/` (local Docker check; neither `make test` nor CI runs it).
- **CI runs every required lane independently and never calls `select-affected-tests.py`.**
- **Output states the boundary explicitly.** `--run` ends with `advisory: run make test before push` after `select_affected_tests_done` or `select_affected_tests_failed: exit=<code>` (never `ok`). `--dry-run` ends with `# advisory: run make test before push`. `--json` remains a single parseable JSON document carrying `"advisory": "advisory: run make test before push"`.

## Why not a sound selector

Two gate-grade designs failed adversarial review:

- **Suite-level claiming "never under-selects" (`specs/test-affected/evidence/review-R1.json`):** 33 findings, 15 of them suites reading inputs not linked in the path map.
- **Lane-level (`specs/test-affected/evidence/design-review-D1.json`):** 21 findings, including cross-directory inputs (`skills/claude-code-review/` checked by `test_code_review_identity.sh`, root `AGENTS.md` read by `test_update_review_plan_intent.sh`), focused tests outside Makefile lanes (`test_kimi_packet_mcp.py`), and checks invoked outside `make test`.

Maintaining a sound whole-repository dependency graph duplicates `make test` and CI at higher maintenance cost. Dropping the soundness claim preserves fast inner-loop signal without weakening any repository gate.

**Mechanism-operability check (claim withdrawal):** Nothing in `.github/workflows/`, `hooks/`, `.githooks/`, `Makefile` `test`, or `AGENTS.md` invokes `select-affected-tests.py` as an enforcement or completion gate. `scripts/test_select_affected_tests.py` stays registered in `make test-repo-gates` to test the tool itself. No downstream control rested on the withdrawn soundness claim.

## Behavior

- **Makefile argument transport:** `test-affected` and `test-affected-plan` pass `CCL_SKILL_SELECTED_DEFAULT_BASE` (target-scoped from `CCL_SKILL_DEFAULT_BASE_REF` so `test-repo-gates` stays unpolluted) and `AFFECTED_ARGS` through the process environment rather than shell command interpolation. Python splits `AFFECTED_ARGS` with `shlex.split(..., posix=True)` and exits `2` on malformed quoting.
- **Selection and runner dispatch:**
  - Unmapped `hooks/` changes run every `hooks/` suite parsed from executable `Makefile` recipes, plus installer and npm checks. Core `skills/code-review/scripts/` changes derive shard membership from `Makefile`.
  - Input paths collapse redundant `/` and `.` segments before dedicated-runner and path-map lookups so aliases such as `skills/code-review/scripts/./test_review_gate_abort_leak.sh` cannot bypass slow-suite exclusions.
  - A changed suite (`.py` or `.sh` only) runs itself, and a changed `<stem>.{py,sh}` runs existing sibling `test_<stem>.{py,sh}` (`-` mapped to `_`), except dedicated suites (`test_review_gate_abort_leak.sh`, `test_check_ccl_regressions.sh`, individual `heavy_tests` parsed comment-safely from `test_check_ccl_regressions.sh`, `test_gen_report.py`, `scripts/verify-sandbox/test.sh`, and `eval/test_*.py`), which stay on their serial/slow/unittest paths. Changing `eval/<mod>.py` or `eval/test_<mod>.py` appends `eval.test_<mod>` to the `python3 -m unittest` command.
  - Selected `.py` suites are parsed with `ast.parse`; any module without a top-level `if __name__ == "__main__":` guard or explicit `unittest.main`/`pytest.main`/`sys.exit`/`raise SystemExit` runner call (even when module-level setup assignments are present) dispatches serially via `python3 -m pytest -q <suite>`.
- **Containment and drift:**
  - Every candidate suite, dedicated serial target (`add_serial_suite`), `eval` unittest module, and `packages/ccl-skills-npm/package.json` check validates containment via `_classify_suite_path` (catching `/`, `..`, NUL bytes, broken symlinks, `RuntimeError` symlink loops, non-regular files, and symlinks resolving outside `repo_root`).
  - If any candidate or registered `Makefile` suite is classified `unsafe`, `unsafe_blocked` is set: `build_test_plan` refuses `make test-*` fallback escalation, `--json` and `--dry-run` exit `2` (with `--dry-run` emitting `(exit 2)` instead of runnable commands), and `execute_plan` exits `2` before running anything. Right before running each preflight, parallel, or serial command, `execute_plan` re-verifies operand and `Makefile` containment to close planning-to-dispatch TOCTOU windows.
  - `makefile_suites()` tokenizes executable tab-indented `Makefile` recipes (ignoring `#` comments and honoring quotes and line continuations) before checking disk presence. Deleted suites still registered in `Makefile` — including a deleted registered suite that is itself the changed file — populate `missing_suites`, emit a `selector-drift` note, and escalate to `make test-repo-gates`, `make test-regressions-fast`, `make test-code-review-1`, and `make test-code-review-2`.
- **Change discovery and untracked coverage note:**
  - `verify_repo_root()` runs unconditionally in all modes (including `--files`), requiring `.git` at `--repo` and `git rev-parse --show-toplevel == root` (stripping only Git's single trailing line delimiter so directory names ending in `\r` work), and converting missing-`git` `OSError` failures into exit `2`.
  - Discovery unions `git diff <merge_base_sha> <head_sha> --`, `git diff --cached --`, `git diff --`, and `git ls-files --others --exclude-standard` via `-z` and `os.fsdecode` (`--no-renames`, `--no-ext-diff`). Any non-zero Git exit returns `2`.
  - When untracked files are present alongside `git ls-files`-scoped gates (`check-markdown-links.py`, `check-spec-references.py`, `doc-lint-repo.py`, `check-public-sanitization.py`), the plan records an `untracked-files:` note explaining that those gates skip untracked paths until staged.
  - When candidate commits exist (`head_sha != merge_base_sha`), preflight checks committed whitespace independently (`git diff --no-ext-diff --check <merge_base_sha> <head_sha> --`) in addition to index and worktree diffs, and empty-tree commits still schedule `shared_git_surface_gate.py`.
- **Git isolation and snapshot pinning:**
  - Discovery strips all `GIT_REPOSITORY_ROUTING_ENV` (including `GIT_NO_REPLACE_OBJECTS`), `GIT_CONFIG_ROUTING_ENV`, and `GIT_CONFIG_KEY_*` / `GIT_CONFIG_VALUE_*`. Child execution (`_clean_child_env`) additionally strips Make override variables, sets `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, `GIT_TERMINAL_PROMPT=0`, and points `GIT_TEMPLATE_DIR` at a temporary directory containing only `info/` (no `hooks/`), preventing user `~/.gitconfig` `core.hooksPath` or template hooks from firing inside writable suite fixtures.
  - Explicit `--base-ref` and `CCL_SKILL_BASE_REF` apply in both discovery and `--files` modes; leading `-`, missing commits, or missing merge-bases exit `2`. Automatic resolution canonicalizes `<remote>/<branch>` to `refs/remotes/<remote>/<branch>`, checks existence via `git check-ref-format` + `git for-each-ref` so corrupt or non-commit integration refs fail closed (`exit 2`) rather than silently falling back, skips missing or orphan (`merge-base` exit `1`) refs, picks the candidate with the smallest `rev-list --count <mb>..<head_sha>`, and forwards the pinned `resolved_base_sha` to `shared_git_surface_gate.py --base-ref` and child `CCL_SKILL_BASE_REF`.
- **Execution, cancellation, and output:**
  - `_run_cmd` launches each child with `start_new_session=True` and forwards `SIGINT`, `SIGTERM`, and `SIGHUP` to the child process group (`os.killpg`), escalating to `SIGKILL` if the group does not exit within 5 seconds, and returning `128 + signal` (`127` for missing executable, `126` for launch `OSError`).
  - Early returns (unsafe-blocked, empty changeset, failing preflight/parallel/serial step) emit accumulated `note:` and `skipped:` diagnostics before the terminal status and `advisory: run make test before push` footer.
  - `encode_json_str` / `decode_json_str` bijectively represent non-UTF-8 bytes via `\x00hex:<hex>`; `_shell_quote` emits Bash `$'...'` escapes for non-UTF-8 or control-bearing tokens, and `--dry-run` prepends `cd -- <repo>` plus the isolated Git/base environment prelude so previews replay identically from any directory; `_terminal_safe` escapes surrogates and C0/DEL/C1 controls (including ANSI `ESC`); `stdout`/`stderr` flush inside the `BrokenPipeError` handler to exit `141` cleanly.

## Security four questions

1. **Caller-controllable inputs:** Make/CLI variables and flags (`AFFECTED_ARGS`, `CCL_SKILL_DEFAULT_BASE_REF`, `CCL_SKILL_BASE_REF`, `--repo`, `--base-ref`, `--default-base-ref`, `--files`, `--jobs`), inherited environment variables (`GIT_*`, `MAKEFLAGS`), and worktree paths/symlinks/filenames.
2. **Blast radius if malformed or forged:** Shell metacharacters in Make variables could execute arbitrary commands during `make test-affected-plan`; inherited `GIT_INDEX_FILE`/`GIT_DIR`/`GIT_NO_REPLACE_OBJECTS`/`GIT_TEMPLATE_DIR` or `~/.gitconfig` `core.hooksPath` could redirect discovery, corrupt a caller's index, or run external hooks; `--base-ref=--independent` could inject Git flags; a symlinked suite or TOCTOU swap could execute code outside the worktree; raw ANSI/newline bytes in filenames could spoof terminal lines or inject uncommented commands into `--dry-run`.
3. **Trust roots:** Make variables passed via `envp` without shell expansion; `--repo` verified unconditionally via `.git` + `git rev-parse --show-toplevel`; explicit and automatic base refs verified as commits and pinned by SHA; suite, serial, `eval`, `npm`, and `Makefile` targets checked for regular-file checkout containment at both planning and dispatch time; child processes run in isolated sessions with scrubbed Git config/templates.
4. **Negative cases:** Metacharacters in `CCL_SKILL_DEFAULT_BASE_REF` and `AFFECTED_ARGS` are not shell-evaluated (`test_makefile_passes_inputs_without_shell_interpretation`); inherited `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_NO_REPLACE_OBJECTS`/`GIT_TEMPLATE_DIR` and `$HOME/.gitconfig` `core.hooksPath` are isolated (`test_git_isolation_covers_discovery_child_templates_and_global_hooks`); escaping symlinks across generic, dedicated serial, Make fallback, symlink loops, and TOCTOU swaps are blocked (`test_containment_covers_dedicated_serial_make_fallback_symlink_loops_non_suites_and_toctou`); `--base-ref=--independent`, corrupt integration refs, and broken `.git` pointers in `--files` mode exit `2`; ANSI escapes and multiline filenames are neutralized (`test_json_dry_run_replay_early_diagnostics_ansi_escape_exit_codes_and_broken_pipe`).

## Risk inventory (`feature-risk-router`)

| Tag | Applies | Gate |
| --- | --- | --- |
| `shared-gate` | no: advisory developer CLI only; neither `make test`, CI, `.githooks`, nor runtime hooks gate merges or completion on it | unit/integration tests + `code-review` review and challenge |
| `security-review` | yes, change-triggered: hardens Make/CLI argument, Git env/hook, ref/SHA, path-containment, and terminal/shell-preview boundaries | `security-first-pass-only` triage recorded in `specs/test-affected/evidence/validation.md` |
| `client-plumbing` / CLI surface | one-shot plain-text/JSON developer CLI (`terminal-cli-dev`); no TUI, raw mode, or alternate screen (`visible surface: no` for graphical/TUI; CLI stdout/stderr/signal/pipe contract verified) | CLI contract tests |
| `api-contract`, `permission-access`, `money-quota`, `write-finality`, `data-migration`, `ai-output`, `ai-action`, `external-integration`, `release-ops` | no: `scripts/select-affected-tests.py` is outside `packages/ccl-skills-npm/scripts/build-assets.mjs` `roots` and changes no host plugin or release artifact | — |

## Implementation boundary record

| Field | Value |
| --- | --- |
| Baseline | `specs/test-affected/plan.md` on `worktree-test-affected` (`origin/main` `788470c`), addressing `specs/test-affected/evidence/design-review-D2.json`, `specs/test-affected/evidence/review-R1.json`, and `specs/test-affected/evidence/review-R2.json` |
| Scope | `Makefile`, `docs/CONTRIBUTING.md`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `specs/test-affected/` |
| Implementation owners | `python-service-dev` + `terminal-cli-dev` + `testing-strategy` + `feature-risk-router` + `multi-agent-delegation` + `worktree-isolation` + `code-review` + `tighten-doc` (all loaded in-session; `client_entry`: plain-text/JSON CLI contract preserves `--help`/`--dry-run`/`--json`/`--run`, stdout-vs-stderr separation, POSIX signal/BrokenPipe exits, and `Makefile` `test` lane invariants) |
| Delegation | `local` (`plan-scan: clean`; single tightly coupled Python module, its unit suite, and two-line Makefile/doc entries) |
| Visible UI | `visible surface: no` (non-interactive one-shot developer CLI; no TUI/ANSI/rendered layout) |
| Test-case-first | 19 tests run RED against `b9a3366` before R1/D2 implementation; expanded 22-test suite run RED against `36fafa6` (`9 failures, 5 errors`) before R2 implementation |

## Test-layer decision table and test-case register

| Layer | Decision | Command and reason |
| --- | --- | --- |
| unit | add + run | `python3 -W error scripts/test_select_affected_tests.py` — covers 22 unit/subprocess scenarios in isolated temporary Git fixtures |
| integration / contract | run | `make test-affected-plan`, `make test-affected`, `CCL_BROAD_TEST_REASON=repo-required make test`, and `python3 scripts/check-public-sanitization.py .` |
| E2E / host smoke | run | CLI `--json`, `--dry-run`, `--run`, and closed-pipe smoke on the worktree |
| manual / exploratory | not applicable | deterministic CLI tool fully exercised by automated unit/integration/CLI smoke checks |

| ID | Scenario | Baseline (`b9a3366` / `36fafa6`) | Candidate |
| --- | --- | --- | --- |
| T1 | Empty changeset selects nothing; empty-tree commit schedules `shared_git_surface_gate.py --base-ref <sha>`; committed whitespace checked independently of staged repairs | failed | passes |
| T2 | Base precedence: `--base-ref=--independent` and missing/corrupt refs exit `2`; `--files` honors `CCL_SKILL_BASE_REF`; nearer merge-base wins even when farther ref is listed first; local `origin/main` and `upstream/dev` branches do not shadow `refs/remotes/*` | failed | passes |
| T3 | Pinned `resolved_base_sha` reaches `shared_git_surface_gate.py` and real `_run_cmd` child `CCL_SKILL_BASE_REF`, stripping `MAKEFLAGS`, `AFFECTED_ARGS`, and `CCL_SKILL_DEFAULT_BASE_REF` | failed | passes |
| T4 | Discovery and child execution strip `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_SHALLOW_FILE`, `GIT_NO_REPLACE_OBJECTS`, `GIT_CONFIG*`, and isolate child `git init`/`git commit` from `GIT_TEMPLATE_DIR` and `$HOME/.gitconfig` `core.hooksPath` | failed | passes |
| T5 | `--repo <non-git>`, `--repo <subdir>`, broken `.git` pointer in `--files` mode, missing `git` binary, and corrupt `.git/index` exit `2` cleanly; checkout directory ending in `\r` succeeds | failed | passes |
| T6 | NUL-delimited discovery preserves UTF-8, spaces, backslashes, and renames; portable synthetic raw `0xff` vs literal `\udcff` round-trips bijectively in JSON and Bash `--dry-run`; untracked files emit `untracked-files:` coverage note | failed | passes |
| T7 | Escaping symlinks across generic suites, dedicated serial commands, Make fallback escalation, symlink loops, non-suite `.json` files, and dispatch-time TOCTOU swaps are blocked | failed | passes |
| T8 | `Makefile` recipe parser ignores comments, handles quoted paths and deleted changed suites, and runs safely under spaced `TMPDIR`; Make variables pass without shell evaluation; AST pytest check catches module-setup pytest files; path aliases and individual heavy regressions honor `--include-slow`; `eval` changes include `eval.test_<stem>`; stopped Docker daemon skips `verify-sandbox` | failed | passes |
| T9 | `SIGTERM` cancels active runner process groups (`143`); `--dry-run` replays from another directory with pinned base, scrubs ANSI `ESC`, and blocks unsafe plans with `(exit 2)`; early returns emit notes/skips; `BrokenPipeError` flushes inside handler and exits `141` | failed | passes |

## Objective closure, functional completeness, and structural minimality

- **Objective & member identity:** Deliver `make test-affected` / `scripts/select-affected-tests.py` on `main` as an advisory inner-loop selector over repository-relative changed paths and candidate commits (`population: fires` — evaluates arbitrary changed file sets in a Git worktree; selection enumerates all four Git discovery queries with zero silent drops, notes untracked-file gate limits, and escalates on unknown/drifted paths unless blocked by an unsafe path; no per-operation bound defers any changed path).
- **Outcome classes:**
  - `positive` (`in`): valid repo + resolvable base selects and executes preflight, parallel, and serial suites against pinned commit SHAs, ending with `select_affected_tests_done` + advisory footer -> T1, T2, T3, T6, T8, T9 (`satisfied`).
  - `negative` (`in`): non-root or broken `--repo`, missing `git`, invalid/corrupt base ref, failed Git enumeration, unsafe symlink/traversal/TOCTOU path, failing child, missing binary, `SIGTERM` cancellation -> non-zero exit + diagnostics + advisory footer -> T2, T5, T7, T8, T9 (`satisfied`).
  - `corrected-recovered` (`in`): deleted mapped or registered `Makefile` suite triggers `selector-drift` fallback when all registered paths are contained -> T8 (`satisfied`).
  - `ambiguous-or-superficially-successful` (`in`): skipped slow/Docker/npm lanes print `skipped:` and never `ok`; untracked files emit `untracked-files:` note; pytest file with module setup runs via `pytest` rather than exiting `0` uncollected; empty-tree commit still runs `shared_git_surface_gate.py` -> T1, T6, T8, T9 (`satisfied`).
- **Structural minimality (concept delta):**

| New concept | Current acceptance point or hard constraint | Simpler alternative | Decision |
| --- | --- | --- | --- |
| `encode_json_str` / `decode_json_str` (`\x00hex:` prefix) | T6 (`specs/test-affected/evidence/review-R2.json` P2 reversible machine-readable filenames) | `backslashreplace` display string (rejected: collides raw `0xff` with literal `\udcff`) | keep |
| `_verify_command_containment` + `unsafe_blocked` | T7 (`specs/test-affected/evidence/review-R2.json` P1 Make fallback containment & P2 dispatch TOCTOU) | planning-time check on `parallel_suites` only (rejected: bypassed by Make fallback and preflight-window symlink swaps) | keep |
| Target-scoped `CCL_SKILL_SELECTED_DEFAULT_BASE` + `AFFECTED_ARGS` env export | T8 (`specs/test-affected/evidence/review-R2.json` P1 Make shell injection + `test_ci_checkout_ref_binding.sh` default-base invariant) | recipe shell interpolation (rejected: shell metacharacter injection) or global `export CCL_SKILL_DEFAULT_BASE_REF` (rejected: pollutes `test-repo-gates` child `make -n`) | keep |

## Target-output map

| Owner / target | Direction | Editability | Status | Changed file or reason |
| --- | --- | --- | --- | --- |
| `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py` | repository tooling | editable CCL target | updated | advisory inner-loop selector and 22-test unit/integration suite |
| `Makefile` | repository entrypoint | editable CCL target | updated | `test-affected` and `test-affected-plan` targets with shell-safe env exports |
| `docs/CONTRIBUTING.md` | onboarding doc | editable CCL target | updated | one-line note positioning `make test-affected` as inner-loop advisory tool |
| `specs/test-affected/` | design & evidence | editable CCL target | updated | charter, plan, validation, and independent review/challenge receipts |
| `product-rd-workflow`, `testing-strategy`, `python-service-dev`, `terminal-cli-dev`, `product-ui-ux-design`, `feature-risk-router`, `multi-agent-delegation`, `worktree-isolation`, `code-review`, `tighten-doc`, `skill-extraction-workflow` | process / stack owners | editable CCL target | unchanged | existing rules already cover advisory vs gate separation, CLI contracts, and test isolation; this task implements a repo-local developer script |
| `go-microservice-dev`, `nodejs-service-dev`, `typescript-dev`, `web-react-dev`, `app-cross-platform-dev`, `miniapp-product-dev` | sibling stack owners | editable CCL target | not-applicable | repo-local Python developer script; no reusable stack-skill rule extracted |
| `hooks/*`, `.github/workflows/ci.yml`, `packages/ccl-skills-npm` | runtime / CI / distribution | editable CCL target | unchanged | CI and hooks deliberately do not depend on the advisory selector, and npm does not ship root `scripts/select-affected-tests.py` |
| External skill packages (`run-workflow`, `antigravity-guide`, `agy-customizations`, `swarm_*`) | external / host built-in | reference-only external/system skill | not-applicable | host built-ins unrelated to repository test selection |
