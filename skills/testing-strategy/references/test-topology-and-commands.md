# Test Topology And Commands

Use this before choosing or running tests in an unfamiliar repository.

## Discovery Order

Read local project guidance before inventing commands:

- Agent/project instructions: `AGENTS.md`, `CLAUDE.md`, `README`, `CONTRIBUTING`, and local agent skill/instruction directories when present.
- Build and test metadata: `go.mod`, `Makefile`, `package.json`, `pyproject.toml`, `pytest.ini`, `tox.ini`, `vitest.config.*`, `playwright.config.*`.
- Automation wrappers: `scripts/run_tests.*`, `scripts/dev.*`, `scripts/check.*`, `magefile.go`, `Taskfile.yml`.
- CI truth: `.github/workflows`, `.gitlab-ci.yml`, buildkite/circle config, release scripts.

Prefer a documented wrapper when present. Wrapper scripts often set env files, codegen, service ports, coverage options, timeout behavior, xdist/parallelism, fixture paths, or CI parity checks that raw runners miss.

## Test-environment hermeticity (local ↔ CI parity)

"Works on my machine, fails in CI" (and the reverse) has several causes — OS/runtime/browser versions, filesystem case-sensitivity, CPU/memory, network/service availability, dependency caches — but a very common and cheap-to-eliminate one is the test reading **ambient environment** that differs between the two machines. The default fast test target must be **hermetic** on that axis — its result must not depend on the developer's machine env. Neutralize the recurring local-vs-CI drift axes:

- **Ambient credentials / API-key env vars** — *unset* them for the default fast target, don't just "not require" them. A developer's shell often has real `*_API_KEY` / `*_TOKEN` / provider creds exported; with them present a test can silently hit a live service, auto-detect a provider, or take a different code path — passing locally and failing in CI where they're absent (or the reverse). Scope the unset to the **hermetic fast-test runtime only**, and target real credential vars — don't blindly nuke every glob match (package-registry tokens, CI job tokens, fixture-only fake tokens). Tests that legitimately need creds are explicitly marked, isolated, and run in a separate live/credentialed gate (or seeded with fake/local creds), never silently broken by the fast gate. This is distinct from the separate rule that the fast gate must not *require* live creds; do both.
- **HOME / state / config dir** — redirect the app/user *state* dirs to a temp location per run/test so the suite reads a clean default config, never the developer's real app-home / auth file, and never writes the real user state dir. But don't hand every spawned tool a blind-empty `HOME`: tools that need real or seeded config (git identity, CA bundles, language/package caches, browser profiles) will throw false failures — use a minimal synthetic HOME with the required tool config seeded, not an empty one.
- **Timezone and locale** — pin (e.g. `TZ=UTC`, `LANG=C.UTF-8`) at the run-environment level for the default deterministic gate; this is the environment-level complement to pinning them at the data/fixture level (see `test-data-and-determinism.md`). Pinning is for determinism, not coverage: when behavior is timezone/DST/locale-visible (dates, billing periods, schedules, "today", number/date formatting), a UTC-only run does NOT prove it — add targeted non-UTC / DST-boundary / non-default-locale cases so the pin doesn't hide a real zone/locale bug.
- **Parallelism / worker count** — fix it or make it irrelevant via per-test isolation (see `test-code-authoring-patterns.md` §7). A suite that passes at one worker count but flakes at another usually has a hidden cross-test dependency — investigate that first rather than pinning workers to hide it; it can occasionally be genuine resource contention (DB pool size, rate limits, CI CPU/memory), which is a capacity fix, not a correctness one. Pinning workers is to make the gate *reproducible*, not to serialize-until-green; if the product itself has suspected concurrency behavior, keep a separate randomized/parallel stress check so pinning the gate doesn't bury a real product concurrency bug.

Enforce hermeticity in **two layers, belt-and-suspenders** — the wrapper alone is not enough because it is easy to bypass (an IDE "run test" button, a raw `pytest` / `go test`, a teammate who does not know the wrapper):
- The **wrapper** (`scripts/run_tests.*`) sets the hermetic env and matches CI exactly; discover and use it, and keep it in lockstep with the CI config — CI is the source of truth, so if they drift the wrapper is wrong.
- An **autouse / always-on fixture** (pytest `conftest.py` autouse fixture, Go `TestMain`, jest `setupFiles`) re-applies the same neutralization so an invocation that skips the wrapper is still hermetic *for ordinary test-body and setup reads*. Caveat: these hooks run after interpreter/package start, so env read at **import / collection / package-`init` / module-level-variable time** is not caught by them — that earliest layer still needs process/runner-level env setup (the wrapper, a CI env block, or a launcher that sets the env before the process starts). So: wrapper = CI parity + the import/init-time layer; autouse hook = the catch-all for everything from setup onward; you generally need both, not either alone.

When there is no wrapper yet, making the default target hermetic against these axes (and adding the autouse hook) is part of the test work, not a separate nicety.

## Inventory Hygiene

When scanning a repository, exclude dependency and generated-test noise unless the task is about those artifacts:

- JavaScript dependencies and outputs: `node_modules`, `dist`, `build`, coverage outputs.
- Python environments and vendored packages: `.venv`, `venv`, `site-packages`, `third_party`, vendored SDK snapshots.
- Generated clients and codegen snapshots unless their drift or compatibility is the test subject.
- Archived worktrees, temporary harnesses, and copied legacy trees unless the active workflow uses them.

Do not count a discovered test file as project coverage until you know which command runs it, whether it is in CI, whether it needs live infrastructure, and what assertion it makes.

## Standard Test Layout

Use the repository's existing layout first. When creating a new layout, keep names conventional:

- `tests/unit`: fast isolated logic.
- `tests/contracts` or `tests/contract`: API, generated client/server, schema, compatibility, and adapter contracts.
- `tests/integration`: DB, Redis, MQ, filesystem/object storage, service-client, transaction, migration, and local container coverage.
- `tests/e2e`: browser, cross-service, release smoke, and real user/caller flows.
- `tests/scenarios` or `tests/acceptance`: optional scenario matrices, acceptance flows, or thin orchestration specs when the repo already separates them. Keep assertions in the owning unit/contract/integration/E2E layer when possible instead of building a second test hierarchy.
- `tests/architecture`: dependency boundary, forbidden import, module layering, generated code cleanliness, and schema drift checks.
- `tests/fixtures`: minimal scenario fixtures, builders, and golden files.

Do not create a parallel convention when the repo already has a clear one.

## Command Tiers

Classify commands before running them:

- Fast default: format, compile/typecheck, lint/static checks, codegen-clean check, unit tests.
- Focused verification: changed package/module tests plus a directly related contract/integration test.
- Opt-in integration: marker/tag/env-gated tests requiring local containers or provisioned services.
- Scenario/acceptance gate: selected risk matrix proving primary, negative, permission, recovery, and regression scenarios at the cheapest sufficient layer.
- E2E/release smoke: browser/API/device real flows in an isolated environment.
- Long gate: compatibility matrix, migration dry-run, load/replay, visual regression, or full-suite release checks.

If the repo separates markers such as `unit`, `integration`, `contract`, `slow`, or `e2e`, preserve that split. Do not move expensive tests into the default PR path unless the local CI contract already expects it.

When existing commands use richer labels such as `contract_fake`, `contract_mysql`, `api`, `e2e_smoke`, `failure_mode`, `drill`, `shadow`, `smoke`, or `replay`, preserve the local meaning instead of flattening everything into unit/integration/E2E. Map them to the scenario matrix and CI gate they actually serve.

## Runner Choice Baseline (2025-2026)

- **`pytest-asyncio` mode choice is a deliberate decision, not a default to leave unset**. Per the project docs at `pytest-asyncio.readthedocs.io`: when no `asyncio_mode` is configured, the mode defaults to `strict`, which means pytest-asyncio runs ONLY tests carrying the `@pytest.mark.asyncio` marker AND fixtures decorated with `@pytest_asyncio.fixture` — async tests/fixtures without those markers silently get skipped or treated as sync. **`auto` mode** (configured via `asyncio_mode = auto` in `pyproject.toml` / `pytest.ini` / `setup.cfg`) auto-marks every async test and takes ownership of every async fixture; this is the recommended setting for projects using only asyncio. **Choose `strict`** when the codebase mixes async libraries (asyncio + trio + anyio) or interoperates with other async test plugins; the marker discipline is the boundary that keeps them from fighting. **Pre-flip audit before flipping a strict-mode project to `auto`**: grep the repo for `import trio` / `import anyio` / `@pytest.fixture` on async functions / `pytest-trio` / `anyio.pytest_plugin` references. Auto mode takes ownership of every async fixture regardless of which library wrote it; flipping without an audit can silently break trio fixtures (auto-marks them as asyncio, runs them in the asyncio event loop, fails or hangs). Stay on strict whenever any async-library coexistence is even possible — the per-test marker cost is small compared to the silent-coexistence failure. Routing the runtime-asyncio mechanic to Python-specific implementation lives in `python-service-dev/references/testing-and-quality-patterns.md`; this skill owns the strict-vs-auto policy choice at portfolio level.
- **`node:test` (Node.js stdlib, stable since Node 20 LTS) is the zero-dep test-runner option for libraries and scripts** that don't need Jest/Vitest's rich-mock / snapshot ecosystem; provides built-in coverage via `--experimental-test-coverage` (the flag remained experimental through Node 22.x at time of writing — verify the exact flag name in the running Node version's `nodejs.org/api/test.html` before pinning CI). **`bun test`** is the analogous runner for Bun-based projects (Jest-compat API, no separate config). Per portfolio: pick ONE primary test runner across services on the same stack (Vitest for most JS/TS web/node projects, Jest where the legacy snapshot ecosystem is load-bearing, `node:test` or `bun test` for small libraries or runtime-native projects); mixing 3-4 runners across a monorepo multiplies CI setup, config drift, and shared-utility coverage gaps. The choice is a portfolio-level architecture decision recorded in the platform docs, not a per-team free choice. **Monorepo with mixed legacy/new runners (Jest-legacy app + Vitest-new app sharing a utility package)** is the recurring failure shape: the shared util may pass tests in caller-A's Jest suite while breaking in caller-B's Vitest suite (subtle API differences in mock injection, `import.meta` handling, module-resolution), and CI may not catch it because the shared util has no test suite of its own. Mitigation: shared utility packages MUST run their own test suite under each runner that production code consumes them with (a `npm test:jest` + `npm test:vitest` matrix on the shared package), OR publish a one-runner contract and migrate stragglers; do not accept "tests pass in caller, no tests on the utility itself" as the steady state.

## Evidence Format

When reporting verification, include:

- command;
- scope;
- result;
- skipped or unavailable suites;
- residual risk.

Example:

| Command | Scope | Result | Notes |
| --- | --- | --- | --- |
| `scripts/run_tests.sh unit` | fast unit gate | pass | repo wrapper used |
| `pytest -m integration tests/contracts` | API and DB contracts | pass | local containers required |
| `npm run e2e:smoke` | release browser smoke | skipped | browser credentials unavailable |
