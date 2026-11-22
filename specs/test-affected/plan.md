# Affected-Test Selector for the Inner Loop

## Charter

| Field | Answer |
| --- | --- |
| Purpose | Provide fast advisory inner-loop feedback (`make test-affected`, `make test-affected-plan`, `scripts/select-affected-tests.py`) over changed repository paths without claiming soundness or weakening `make test` and CI gates, and harden the tool against Git-env leakage, base-resolution pitfalls, symlink/traversal escapes, silent discovery errors, and uncollected pytest modules. |
| Scope | In: `Makefile` (`test-affected`, `test-affected-plan`), `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `docs/CONTRIBUTING.md` (one-line pointer), and `specs/test-affected/`. Out: changing `make test`, CI workflows, runtime hooks, distributed npm assets (`packages/ccl-skills-npm`), or any `skills/` text. No iterative-program `covered-through` watermark applies. |
| Depth | Generator/tooling change: deterministic repository developer CLI and its unit/integration test suite; no skill or hook rule changes. |
| Result classification | Failure/correction (`evidence/review-R1.json`, `evidence/design-review-D1.json`, `evidence/design-review-D2.json`). Disconfirming observation: any case where the tool silently drops failed Git queries, mutates caller Git state, executes paths outside `--repo`, shadows `origin/main` with a local branch, or emits a gate-passing `ok` token. |
| Matching analysis | Contributing factors: (1) claiming "minimal sound set" required tracking undocumented cross-directory file-to-test reads across the whole repo; (2) Git discovery and child execution inherited caller `GIT_*` routing/graph/config variables; (3) base lookup used short refs (`origin/main`) and silent fallbacks (`main`, `HEAD~1`) instead of qualified remote refs and explicit failure; (4) `makefile_suites()` filtered missing files before drift detection could see them; (5) automatic self-selection ran before slow-lane and pytest-runner checks and did not enforce checkout containment. Prevention: reposition explicitly as advisory inner-loop feedback with a mandatory footer, scrub `GIT_*` across discovery, child execution, and test fixtures, validate `--repo` and base refs fail-closed, check containment on all suite paths, retain Makefile entries through drift detection, and dispatch `__main__`-less `.py` suites via `pytest`. |
| Failure mode or success boundary | A weak implementation would let contributors mistake a green inner-loop run for `make test`, corrupt a caller's `GIT_INDEX_FILE` during parallel suite runs, follow a symlink outside the worktree, break `--json` consumers with trailing text, or pass a failing pytest module with exit `0`. |
| Lifecycle impact | Implementation, debugging, and local testing inner loop in this repository; contributor onboarding (`Makefile` help and `docs/CONTRIBUTING.md`). Product intent, design/UX, launch/release, observability, and external source-less npm users: unchanged (`scripts/select-affected-tests.py` is not packaged into npm). |
| Evidence plan | Produced artifacts inspected first: `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `Makefile`, `specs/test-affected/evidence/review-R1.json`, `design-review-D1.json`, `design-review-D2.json`. Repository contracts and peers inspected: `AGENTS.md`, `scripts/AGENTS.md`, `docs/CONTRIBUTING.md`, `scripts/run-parallel-suites.sh`, `scripts/test_lane_isolation.py`, `scripts/check-release-version.py`, `scripts/verify-sandbox/test.sh`, `skills/skill-extraction-workflow/scripts/shared_git_surface_gate.py`, `skills/skill-extraction-workflow/scripts/test_frozen_case_sanctity.sh`, `skills/skill-extraction-workflow/scripts/test_ci_checkout_ref_binding.sh`, `.github/workflows/ci.yml`, `packages/ccl-skills-npm/scripts/build-assets.mjs`. |
| Completion standard | T1–T9 fail RED against `b9a3366` and pass after implementation; killing-mutation walk verified in scratch; `make test-affected-plan`, `make test-affected`, `CCL_BROAD_TEST_REASON=repo-required make test`, `check-public-sanitization.py`, and `shared_git_surface_gate.py --base-ref origin/main` pass; independent `code-review` review and adversarial challenge run and converge before PR and merge to `main`. |

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

- **Suite-level claiming "never under-selects" (`evidence/review-R1.json`):** 33 findings, 15 of them suites reading inputs not linked in the path map.
- **Lane-level (`evidence/design-review-D1.json`):** 21 findings, including cross-directory inputs (`skills/claude-code-review/` checked by `test_code_review_identity.sh`, root `AGENTS.md` read by `test_update_review_plan_intent.sh`), focused tests outside Makefile lanes (`test_kimi_packet_mcp.py`), and checks invoked outside `make test`.

Maintaining a sound whole-repository dependency graph duplicates `make test` and CI at higher maintenance cost. Dropping the soundness claim preserves fast inner-loop signal without weakening any repository gate.

**Mechanism-operability check (claim withdrawal):** Nothing in `.github/workflows/`, `hooks/`, `.githooks/`, `Makefile` `test`, or `AGENTS.md` invokes `select-affected-tests.py` as an enforcement or completion gate. `scripts/test_select_affected_tests.py` stays registered in `make test-repo-gates` to test the tool itself. No downstream control rested on the withdrawn soundness claim.

## Behavior

- **Selection:** Path map plus three convention rules:
  - Unmapped `hooks/` changes run every `hooks/` suite named in `Makefile`, plus installer and npm checks. Core `skills/code-review/scripts/` changes derive shard membership from `Makefile`.
  - A changed suite runs itself, and a changed `<stem>.{py,sh}` runs existing sibling `test_<stem>.{py,sh}` (`-` mapped to `_`), except suites requiring dedicated scheduling (`test_review_gate_abort_leak.sh`, `test_check_ccl_regressions.sh`, `test_gen_report.py`, `scripts/verify-sandbox/test.sh`, `eval/test_*.py`), which stay on their dedicated serial/slow/framework paths.
  - Every automatically selected suite must resolve to a regular file contained inside the resolved `--repo` root; symlinks escaping the checkout and `..` paths are skipped with a note and never executed.
  - Selected `.py` suites lacking an `if __name__ == "__main__":` entrypoint run via `python3 -m pytest -q <suite>` in the serial phase instead of bare `python3 <suite>` in `run-parallel-suites.sh`.
- **Drift:** `makefile_suites()` retains all suite paths parsed from `Makefile` before checking disk presence so deleted files still registered in `Makefile` or the static map populate `missing_suites`, emit a `selector-drift` note, and escalate to `make test-repo-gates`, `make test-regressions-fast`, `make test-code-review-1`, and `make test-code-review-2`. A unit test pins that every literal suite path in `select-affected-tests.py` exists.
- **Change discovery:**
  - `--repo` must contain `.git` and match `git rev-parse --show-toplevel` (subdirectories and non-repositories exit `2`).
  - Inputs: committed diff `merge-base...HEAD`, staged diff, unstaged diff, and untracked files (`--others --exclude-standard`), all read as raw NUL-delimited bytes (`-z`, `--no-renames`) and decoded via `os.fsdecode` without stripping whitespace or rewriting backslashes. Any failed Git enumeration exits `2`.
  - When the tree diff is empty but `HEAD` is ahead of the merge-base (for example an empty commit or commit-plus-revert), `shared_git_surface_gate.py` still runs in preflight.
- **Git isolation:** Both discovery and child execution (`_run_cmd`) strip all repository-routing, commit-graph, and config override variables (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_IMPLICIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_NAMESPACE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_CEILING_DIRECTORIES`, `GIT_DISCOVERY_ACROSS_FILESYSTEM`, `GIT_GRAFT_FILE`, `GIT_SHALLOW_FILE`, `GIT_REPLACE_REF_BASE`, `GIT_PREFIX`, `GIT_INTERNAL_SUPER_PREFIX`, `GIT_QUARANTINE_PATH`, `GIT_CONFIG*`), plus outer GNU Make overrides (`MAKEFLAGS`, `MFLAGS`, `MAKELEVEL`, `MAKEOVERRIDES`, `GNUMAKEFLAGS`, `-*-command-variables-*-`, `CCL_SKILL_DEFAULT_BASE_REF`).
- **Base resolution and propagation:**
  - Explicit `--base-ref` (or non-empty `CCL_SKILL_BASE_REF`) wins. Option-shaped values (leading `-`), empty values, unresolvable refs, or refs with no merge-base with `HEAD` exit `2`.
  - Otherwise, automatic candidates combine the canonicalized `--default-base-ref` (`<remote>/<branch>` normalized to `refs/remotes/<remote>/<branch>` so local branches named `origin/main` cannot shadow remote-tracking refs), `refs/remotes/origin/main`, and `refs/remotes/origin/dev`, choosing the candidate whose merge-base is nearest `HEAD`. Missing refs and refs with unrelated history (`git merge-base` exit `1`) are skipped; corrupt-repo Git errors (`exit >= 2`) and having no usable candidate exit `2`.
  - For promotions between integration branches (`dev` into `main`), pass `--base-ref refs/remotes/origin/main`.
  - When a base resolves, `shared_git_surface_gate.py` receives `--base-ref <resolved_base>` and child processes receive `CCL_SKILL_BASE_REF=<resolved_base>` while `CCL_SKILL_DEFAULT_BASE_REF` remains unset so `test_ci_checkout_ref_binding.sh` observes the `Makefile` default.
- **Execution and exit codes:**
  1. Preflight commands (`git diff --check` across candidate and index, `check-ccl-skills.sh`, `shared_git_surface_gate.py`, `check-agent-contract-coverage.sh`).
  2. Parallel suites via `scripts/run-parallel-suites.sh` (returns `1` when any parallel suite fails).
  3. Serial commands.
  - Execution stops at the first non-zero status and returns it (`127` if an executable is missing, `126` on other `OSError` launch failures, `128 + signal` when a child dies from a signal).
  - Planned slow skips and runtime-unavailable skips (`verify-sandbox` when `docker info` fails) are listed in `skipped: <lanes>`.
  - `BrokenPipeError` exits `141` quietly without a Python traceback.
- **Output:**
  - `--run`: prints `select_affected_tests: base_ref=<ref>`, runs the three phases, prints `skipped:` when non-empty, prints `select_affected_tests_done` or `select_affected_tests_failed: exit=<code>`, and finishes with `advisory: run make test before push`.
  - `--dry-run`: escapes control characters in `#` comment lines so multiline filenames stay commented, shell-quotes all command tokens including `--jobs`, and ends with `# advisory: run make test before push`.
  - `--json`: prints one JSON object to stdout (`advisory` field included) and nothing else.
- **Fixture safety:** Writable Git fixtures in `scripts/test_select_affected_tests.py` scrub all `GIT_*` routing/config variables and set `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and an empty `GIT_TEMPLATE_DIR` inside `tempfile.TemporaryDirectory()`.

## Security four questions

1. **Caller-controllable inputs:** CLI flags (`--repo`, `--base-ref`, `--default-base-ref`, `--files`, `--jobs`), inherited environment variables (`GIT_*`, `CCL_SKILL_BASE_REF`, `CCL_SKILL_DEFAULT_BASE_REF`, `MAKEFLAGS`), and worktree paths/symlinks.
2. **Blast radius if malformed or forged:** Inherited `GIT_INDEX_FILE`/`GIT_DIR`/`GIT_COMMON_DIR`/`GIT_SHALLOW_FILE`/`GIT_CONFIG*` could redirect discovery or corrupt another checkout's index/refs during child or fixture execution; `--base-ref=--independent` could inject Git flags; a symlinked `test_*.sh` or `--files ../outside.sh` could execute code outside the worktree; a newline in a filename could inject an uncommented command line into `--dry-run` output.
3. **Trust roots:** `--repo` verified against `.git` presence and `git rev-parse --show-toplevel` under a scrubbed Git environment; explicit bases checked against leading `-` and `rev-parse --verify <ref>^{commit}`; executable suite paths resolved and checked for containment under `repo_root`; writable fixtures isolated from system/global Git config and templates.
4. **Negative cases:** Inherited `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_SHALLOW_FILE` ignored in discovery and child execution (T4); fixture `git commit` ignores a failing hook in inherited `GIT_TEMPLATE_DIR` (T4); symlinked suite outside `repo_root` and `--files ../outside.sh` excluded (T7); `--base-ref=--independent` and `--repo <subdir>` exit `2` (T2, T5); multiline filename stays commented in `--dry-run` (T9).

## Risk inventory (`feature-risk-router`)

| Tag | Applies | Gate |
| --- | --- | --- |
| `shared-gate` | no: advisory developer CLI only; neither `make test`, CI, `.githooks`, nor runtime hooks gate merges or completion on it | unit/integration tests + `code-review` review and challenge |
| `security-review` | yes, change-triggered: scrubs untrusted env, ref, path-containment, and shell-preview boundaries | `security-first-pass-only` triage recorded in `evidence/validation.md` |
| `client-plumbing` / CLI surface | one-shot plain-text/JSON developer CLI (`terminal-cli-dev`); no TUI, ANSI escapes, raw mode, or alternate screen (`visible surface: no` for graphical/TUI; CLI stdout/stderr contract verified by T9) | CLI contract tests (T9) |
| `api-contract`, `permission-access`, `money-quota`, `write-finality`, `data-migration`, `ai-output`, `ai-action`, `external-integration`, `release-ops` | no: `scripts/select-affected-tests.py` is outside `packages/ccl-skills-npm/scripts/build-assets.mjs` `roots` and changes no host plugin or release artifact | — |

## Implementation boundary record

| Field | Value |
| --- | --- |
| Baseline | `specs/test-affected/plan.md` on `worktree-test-affected` (`origin/main` `788470c`), addressing `evidence/design-review-D2.json` and `evidence/review-R1.json` |
| Scope | `Makefile`, `docs/CONTRIBUTING.md`, `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py`, `specs/test-affected/` |
| Implementation owners | `python-service-dev` + `terminal-cli-dev` + `testing-strategy` + `feature-risk-router` + `multi-agent-delegation` + `worktree-isolation` + `code-review` + `tighten-doc` (all loaded in-session; `client_entry`: plain-text/JSON CLI contract preserves `--help`/`--dry-run`/`--json`/`--run`, stdout-vs-stderr separation, POSIX signal/BrokenPipe exits, and `Makefile` `test` lane invariants) |
| Delegation | `local` (`plan-scan: clean`; single tightly coupled Python module, its unit suite, and two-line Makefile/doc entries) |
| Visible UI | `visible surface: no` (non-interactive one-shot developer CLI; no TUI/ANSI/rendered layout) |
| Test-case-first | T1–T9 written in `scripts/test_select_affected_tests.py` and run RED against `b9a3366` before editing `scripts/select-affected-tests.py` |

## Test-layer decision table and test-case register

| Layer | Decision | Command and reason |
| --- | --- | --- |
| unit | add + run | `python3 scripts/test_select_affected_tests.py` — covers T1–T9 with isolated temporary Git fixtures |
| integration / contract | run | `make test-affected-plan`, `make test-affected`, and `CCL_BROAD_TEST_REASON=repo-required make test` |
| E2E / host smoke | run | CLI `--json`, `--dry-run`, `--run`, and piped `head -n 3` smoke on the worktree |
| manual / exploratory | not applicable | deterministic CLI tool fully exercised by automated unit/integration/CLI smoke checks |

| ID | Scenario | Expected before (`b9a3366`) | Expected after |
| --- | --- | --- | --- |
| T1 | Empty changeset (`has_candidate_commits=False`) selects nothing; empty-tree commit ahead of base schedules `shared_git_surface_gate.py` | fails empty-commit check | passes |
| T2 | Base precedence: explicit `--base-ref` / `CCL_SKILL_BASE_REF` rejects `--independent` and missing refs (`exit 2`); auto base prefers nearest merge-base, ignores local `refs/heads/origin/main` shadow, skips missing or unrelated-history `origin/dev`, honors `CCL_SKILL_DEFAULT_BASE_REF=refs/remotes/upstream/dev`, and exits `2` when no integration ref resolves | fails option/shadow/unrelated/no-base cases | passes |
| T3 | Resolved base reaches `shared_git_surface_gate.py --base-ref` and child `CCL_SKILL_BASE_REF` while `CCL_SKILL_DEFAULT_BASE_REF` and `MAKEFLAGS` are stripped | fails (`--default-base-ref origin/dev` hardcoded) | passes |
| T4 | Discovery and `_run_cmd` strip `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_SHALLOW_FILE`, `GIT_GRAFT_FILE`, `GIT_REPLACE_REF_BASE`, `GIT_CONFIG*`; writable fixtures ignore inherited `GIT_TEMPLATE_DIR` hooks | fails | passes |
| T5 | `--repo <subdir>` and `--repo <non-git>` exit `2`; corrupt `.git/index` causing `git diff --cached` failure exits `2` | fails (silent `[]` / parent walk) | passes |
| T6 | NUL-delimited discovery preserves UTF-8, spaces, literal backslashes, and `--no-renames` old+new paths | fails backslash/quoting cases | passes |
| T7 | Symlinked suite escaping `--repo` and `--files ../outside.sh` are excluded and never executed | fails (symlink followed) | passes |
| T8 | `makefile_suites` retains deleted Makefile entries for drift fallback end-to-end; `test_review_gate_abort_leak.sh` never enters `parallel_suites`; pytest-style suite without `__main__` runs via `python3 -m pytest -q` and fails on failing assertion; stopped Docker daemon marks `verify-sandbox` skipped | fails | passes |
| T9 | `--json` stays single-document JSON with `advisory`; `--dry-run` quotes args, includes `--jobs`, escapes multiline filenames, ends with `# advisory: ...`; `--run` stops on preflight failure, preserves serial/launch (`127`)/signal (`143`)/parallel (`1`) failure codes, prints `skipped:` and `select_affected_tests_done`, always ends with `advisory: run make test before push`, and exits `141` cleanly on `BrokenPipeError` | fails | passes |

## Objective closure, functional completeness, and structural minimality

- **Objective & member identity:** Deliver `make test-affected` / `scripts/select-affected-tests.py` on `main` as an advisory inner-loop selector over repository-relative changed paths and candidate commits (`population: fires` — evaluates arbitrary changed file sets in a Git worktree; selection enumerates all four Git discovery queries with zero silent drops and falls back on unknown/drifted paths; no per-operation bound defers any changed path).
- **Outcome classes:**
  - `positive` (`in`): valid repo + resolvable base selects and executes preflight, parallel, and serial suites, ending with `select_affected_tests_done` + advisory footer -> T1, T2, T3, T6, T8, T9 (`satisfied`).
  - `negative` (`in`): non-root `--repo`, unresolvable/option-shaped explicit base, missing all bases, failed Git enumeration, failing preflight/parallel/serial child, missing binary, signal exit -> exit `2` / child status + advisory footer -> T2, T5, T8, T9 (`satisfied`).
  - `corrected-recovered` (`in`): deleted mapped/Makefile suite triggers `selector-drift` fallback to full lanes; escaping symlink/`..` skipped safely -> T7, T8 (`satisfied`).
  - `ambiguous-or-superficially-successful` (`in`): skipped slow/Docker lanes print `skipped: <lanes>` and never print `ok`; pytest file without `__main__` runs via `pytest` rather than exiting `0` uncollected; empty-tree commit still runs `shared_git_surface_gate.py` -> T1, T8, T9 (`satisfied`).
- **Structural minimality (concept delta):** Single standalone stdlib Python CLI `scripts/select-affected-tests.py` + `Makefile` targets (`test-affected`, `test-affected-plan`); `CODE_REVIEW_SHARD_SUITES` duplicate tuple removed in favor of `makefile_suites()` (`simplify`); no daemon, cache file, or hook added (`keep`).

## Target-output map

| Owner / target | Direction | Editability | Status | Changed file or reason |
| --- | --- | --- | --- | --- |
| `scripts/select-affected-tests.py`, `scripts/test_select_affected_tests.py` | repository tooling | editable CCL target | updated | advisory inner-loop selector and unit/integration suite |
| `Makefile` | repository entrypoint | editable CCL target | updated | `test-affected` and `test-affected-plan` targets and advisory help text |
| `docs/CONTRIBUTING.md` | onboarding doc | editable CCL target | updated | one-line note positioning `make test-affected` as inner-loop advisory tool |
| `specs/test-affected/` | design & evidence | editable CCL target | updated | charter, plan, validation, and independent review/challenge receipts |
| `product-rd-workflow`, `testing-strategy`, `python-service-dev`, `terminal-cli-dev`, `product-ui-ux-design`, `feature-risk-router`, `multi-agent-delegation`, `worktree-isolation`, `code-review`, `tighten-doc`, `skill-extraction-workflow` | process / stack owners | editable CCL target | unchanged | existing rules already cover advisory vs gate separation, CLI contracts, and test isolation; this task implements a repo-local developer script |
| `go-microservice-dev`, `nodejs-service-dev`, `typescript-dev`, `web-react-dev`, `app-cross-platform-dev`, `miniapp-product-dev` | sibling stack owners | editable CCL target | not-applicable | repo-local Python developer script; no reusable stack-skill rule extracted |
| `hooks/*`, `.github/workflows/ci.yml`, `packages/ccl-skills-npm` | runtime / CI / distribution | editable CCL target | unchanged | CI and hooks deliberately do not depend on the advisory selector, and npm does not ship root `scripts/select-affected-tests.py` |
| External skill packages (`run-workflow`, `antigravity-guide`, `agy-customizations`, `swarm_*`) | external / host built-in | reference-only external/system skill | not-applicable | host built-ins unrelated to repository test selection |
