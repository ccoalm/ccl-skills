# Validation

Round: point the testing and architecture entrypoints at `typescript-dev`. Host: Linux, Claude Code 2.1.322. Probes used `claude-haiku-5-5` with `--tools "" --strict-mcp-config` from an empty directory; raw outputs stay in the session scratch area.

## Size cap

`skills/skill-extraction-workflow/scripts/check-size-budget.sh` blocks a changed entrypoint that is already over 50000 bytes from growing in bytes or in body words. `testing-strategy/SKILL.md` was 51412 bytes and 7019 body words on `origin/main`. Adding the pointer alone gave +125 bytes and +18 words, and both blocks fired. After tightening the same pointer list: 51410 bytes, 7019 words, `entrypoint_size_blocking_ok`, `entrypoint_word_budget_blocking_ok`. `software-architecture/SKILL.md` is under every cap (+258 bytes).

The added line shifts later `testing-strategy/SKILL.md` line numbers that the obligation ledger in `specs/065-uiux-evidence-delivery/obligation-preservation.md` cites, so `test_obligation_ledger_repo_audit.sh` reported `STALE_LEDGER`. The ledger was re-rendered with `obligation-ledger.py render` at its pinned base and head; only carrier line numbers moved (21 rows), and the audit passes (`audit_ok ... unresolved=0`).

## Reproduction (RED) and fix (GREEN)

Each probe gives the model one entrypoint's full text and a task, and asks which skill to load next for the implementation. Five runs per arm.

| Entrypoint | Task | Base (`origin/main`) | Head |
| --- | --- | --- | --- |
| `testing-strategy` | Vite browser TypeScript library, no Node.js service: write the `tsc --noEmit` gate and `expectTypeOf` type tests | `typescript-dev` 0/5; `nodejs-service-dev` 5/5 | `typescript-dev` 5/5 |
| `software-architecture` | Node.js TypeScript service: implement the runtime schema and derived types at the webhook boundary | `typescript-dev` 0/5; `nodejs-service-dev` only | `typescript-dev` 5/5, with `nodejs-service-dev` |
| `test-artifact-management` | Approved type-level test cases for a browser TypeScript library: write `expectTypeOf` tests and the `tsc --noEmit` gate; which skills must the implementer load | `typescript-dev` 0/5 (`testing-strategy` 5/5) | `typescript-dev` 5/5 |
| `multi-agent-delegation` | Dispatch one worker for a TypeScript React screen; list its `required_skills` | `typescript-dev` 0/5 (`web-react-dev` only) | `web-react-dev` and `typescript-dev` 5/5 |

## Review gate owner selection

Plan and decision table: `specs/typescript-dev-entry-pointers/plan.md`.

- RED: with the new cases in `skills/code-review/scripts/test_review_gate.sh` and the base `review_gate.py`, the suite fails at the suffix table: `AssertionError: ('service.ts', {'web-react-dev'})`.
- GREEN: `review_gate_tests_ok`, including the full-gate cases "Go, TypeScript, TSX, and Dart candidates route all registered implementation owners" and "a TypeScript candidate whose self-review omits typescript-dev fails before provider execution".

Applied mutations on the fixed `review_gate.py`, each restored from a backup and the tree checked byte-identical afterwards:

| Mutation | First failing assertion |
| --- | --- |
| `.tsx` derives only the React owner | `View.tsx` row: `{'web-react-dev'}` |
| `.ts` keeps the React owner as well | `service.ts` row |
| `.js` adds the language owner | `a.js` row |
| Registry check removed | pre-existing empty-registry row; with that row neutralized, the no-language-owner registry row (`{'web-react-dev', 'typescript-dev'}`); unmutated control passes |
| `.mts` unmapped | `module.mts` row |
| `.cts` unmapped | `module.cts` row |
| Suffix not case-folded | `LEGACY.TS` row |

## Reworded lines: controls

Three runs per arm on the `testing-strategy` entrypoint, one task per reworded line.

| Line | Task | Base | Head |
| --- | --- | --- | --- |
| Python | async pytest fixtures and fake client | `python-service-dev` 3/3 | 3/3 |
| Web | Playwright browser automation flows | `web-react-dev` 3/3 | 3/3 |
| App | Flutter widget tests and device smoke | `app-cross-platform-dev` 3/3 | 3/3 |
| Terminal | PTY rendering tests for a full-screen text UI | `terminal-cli-dev` 3/3 | 3/3 |
| Go | handler unit tests | `go-microservice-dev` 3/3 | 3/3 |

## Obligations kept when rewording

| Before | After | Status |
| --- | --- | --- |
| Go-specific implementation details → `go-microservice-dev` | Go implementation details | kept |
| Python-specific pytest, async test, fixture, fake client, ruff, mypy/pyright, packaging, migration-test implementation details | pytest, async, fixture, fake-client, ruff, mypy/pyright, packaging, migration-test details; the line names `python-service-dev` | kept |
| Node: fake timers, stream and cancellation assertions | fake-timer, stream/cancellation assertion; still "must use" | kept |
| App: Flutter, Android and iOS test kinds, mobile device smoke, app release verification | same test kinds, device smoke (the line is the app owner's), app release verification | kept |
| Web: browser/E2E implementation, browser automation | browser/E2E tests (browser automation is the browser/E2E layer; control row above) | kept |
| Terminal: full-screen text UI testing | full-screen TUI testing | kept |
| Stack pointers below apply after that choice | Stack pointers below follow that choice | kept |

## Local lanes

Candidate `3d16a5a` (rebased onto `origin/main` at `95cb9f7`), with the private alias audit configured:

| Command | Result |
| --- | --- |
| `check-ccl-skills.sh` | `r0_status=private-ok`, `ccl_skill_check_clean_ok` |
| `test_obligation_ledger_repo_audit.sh` | `test_obligation_ledger_repo_audit_ok` |
| `make test-repo-gates` | exit 0 |
| `make test-regressions-fast` | exit 0 |
| `make test-code-review-1`, `make test-code-review-2` | exit 0 |
| `make test-code-review-abort-leak-1`, `-2` (in a PID namespace, so orphans reparent to PID 1) | exit 0 |
| `test_check_ccl_regressions.sh --heavy-only` | `regression_heavy_lane_ok: 9 suites` |
| CI repository-gates extras: `test_check_public_sanitization.py`, `check-public-sanitization.py`, `check-markdown-links.py`, `check-spec-references.py`, `test_check_skill_count.py`, `check-skill-count.py` | exit 0 each |

## Review R1

Reviewer: codex via `extraction_review_gate.sh --mode review --stage build --base origin/main`, on candidate `f0cae19` (before the rebase). Result `review-R1.json`, status `findings`, five P2.

| Finding | Disposition |
| --- | --- |
| `test_review_gate.sh` reverts seven here-string fixes | Stale base: `origin/main` gained PR #228 after this branch was cut, so the diff showed its changes as reverts. Rebased; the candidate keeps every here-string fix |
| Two test scripts lose mode 100755 | Same cause; after the rebase the diff has no mode changes |
| Register rows replace five sweep rows; sweep records deleted | Same cause; after the rebase the five rows are appended after the sweep rows and the sweep directory is untouched |
| Validation record lacks candidate-bound lane results | Fixed: the Local lanes section above |
| Reviewer context lacked eight selected skill bodies and `docs/SKILLS.md` | Packet limit, not a candidate defect. The owner-list edits are checked by the base/head probes above and the gate edit by its tests; both are controller-verified, not reviewer-verified |

## Challenge C1

Challenger: codex via `extraction_review_gate.sh --mode challenge --stage build --base origin/main` on candidate `af1d113`, focused on the suffix owner map (the loosened `.ts` class, over- and under-selection, registry absence, case folding, tests that stay green with a defect) and on routing contradictions and dropped obligations in the edited owner lists. Result `challenge-C1.json`, status `findings`, one P2.

| Finding | Disposition |
| --- | --- |
| Packet lacked `product-rd-workflow` routing, `docs/SKILLS.md` and eight selected skill bodies, so the Node.js CLI versus terminal split and the tightened obligations could not be verified | Packet limit, not a candidate defect; no finding on the gate itself. Controller-verified: `product-rd-workflow/SKILL.md` development routing sends CLI or tooling without terminal-UI concerns to the language owner (`nodejs-service-dev`) and the terminal UI and command/flag/help contract to `terminal-cli-dev`, which is the split the two empty-repo rows state; the tightened lines are covered by the obligation table and per-line controls above |

No change followed the challenge, so no delta pass is owed.
