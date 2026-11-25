---
name: testing-strategy
description: 怎么测 / 测试方案 / 测试覆盖 / 先写测试用例（可执行测试代码/覆盖） / test cases first for test code / 写测试 / 写测试代码 / 补测试 / 补测试用例（未指向文档/Bitable/source-to-TC 时按可执行测试覆盖处理） / mock / 单元测试 / 集成测试 / E2E / 回归 / CI gate → choose test layers, scenarios, fixtures, mocks, regression coverage, smoke, verification evidence, and runner-config policy. Skip structured test-case documents, Feishu/Bitable TC sync, or source-to-TC generation → test-artifact-management. Skip 具体的 runner 调用（pytest / go test 命令与参数怎么写）→ 该技术栈 dev 技能；覆盖阈值与 CI gate 策略仍归本技能。
---

# Testing Strategy

Owns test scope/design, verification evidence, CI gates and test-layer choices across Go, Python, React web, mobile, mini-program, terminal/CLI/TUI, API, workflow, data/inference and release tasks.

- Code/test changes require self-checks; invoke `code-review` automatically before completion.

## Skill Routing

- Use this skill for test strategy, test pyramid decisions, unit/integration/e2e/scenario boundaries, fixtures, mocks/fakes, regression coverage, and verification evidence. Stack pointers below follow that choice.
- Use `go-microservice-dev` for Go implementation details.
- Use `python-service-dev` for pytest, async, fixture, fake-client, ruff, mypy/pyright, packaging, or migration-test details.
- Node runner, mock/fixture, fake-timer, stream/cancellation assertion, child-process lifecycle, and packaged-artifact verification must use `nodejs-service-dev`.
- TypeScript type checks and type tests (`tsc --noEmit`, `expectTypeOf`/`tsd`) must use `typescript-dev`.
- Use `app-cross-platform-dev` for Flutter unit/widget/integration, Android unit/Compose/instrumented, and iOS unit/UI tests, device smoke, and app release verification.
- Use `miniapp-product-dev` for WeChat/Alipay/Douyin/Baidu mini-program build, developer-tool preview, real-device smoke, host capability verification, review submission, and release checks.
- Use `web-react-dev` for React unit/component/API-client/browser/E2E tests, accessibility checks, and build/deploy smoke.
- Use `terminal-cli-dev` for terminal interface contract, PTY/ANSI/keyboard rendering, and full-screen TUI testing.
- Use `llm-inference-integration` for LLM/agent/RAG evals, replay sets, prompt/model regression checks, shadow runs, and inference-specific observability.
- Use `defect-diagnosis` first when a test is failing, flaky, or used to reproduce a bug.
- Use `product-rd-workflow` first when testing is part of an end-to-end product delivery plan.
- Use `product-ui-ux-design` for visual hierarchy, interaction, state, accessibility, and design acceptance criteria; use this skill for automated proof and test coverage.
- Use `test-artifact-management` when the ask is about generating structured test cases from a Feishu requirements doc or codebase and delivering them to Feishu Bitable; use this skill for scenario selection and risk matrix before `test-artifact-management` writes the cases.
- For ambiguous "写测试用例" / "write test cases" requests, use this skill first when the user is asking to add, modify, run, or verify test code, E2E/browser/device tests, CI coverage, mocks, or regression evidence. Route to `test-artifact-management` only when the deliverable is a structured TC artifact, Feishu/Bitable sync, or source-to-TC generation workflow.
- For team testing standards, QA norms, CI/harness requirements, or a missing "测试规范" in a product/R&D standards family, use `references/rd-testing-standard-template.md` as the source-neutral template, then route stack-specific command mechanics to the relevant dev skill.

## Non-Functional And Specialized Testing

Use this skill to decide whether a specialized or non-functional test belongs in a gate and what evidence is required; the domain owner still owns implementation semantics and detailed method. Keep the entrypoint as the ownership/pointer surface. The full domain index, per-domain gate criteria, scenario/assertion matrices, and routing handoffs live in `references/non-functional-specialized-scenarios.md`.

## Core Rules

- Test behavior and contracts, not implementation trivia.
- Code analysis may add risk scenarios; it must not define product-delivery completeness. Derive primary coverage from the active requirement/acceptance source with stable IDs.
- Do not write change-detector tests — assertions that snapshot data *expected to change* (vendor/catalog entries, config-version literals, enumeration counts, hardcoded registry lists) instead of behavior; they add no coverage and break CI on routine data updates (`references/test-code-authoring-patterns.md` §3 & §11).
- Every test should pay for itself: prioritize by business risk, defect history, change frequency, and manual-verification cost.
- **Reuse before generating.** Before writing any test, grep existing test files for coverage of the same function, endpoint, class, or scenario; on behavior-correcting fixes, sweep and rewrite pinned old-behavior assertions across every layer (`references/test-code-authoring-patterns.md` §10–§11).
- Keep default tests fast, deterministic, and offline. Select local evidence by touched surface. Leave the matrix to CI only if verified blocking jobs cover it; otherwise run the missing gate or mark incomplete. Report commands run; reuse green only on the same recorded tree (`references/ci-fixtures-and-flake-control.md`, Local Evidence Selection).
- Do not infer coverage from test file count or names. Classify tests by the command that runs them, marker/tag, required dependencies, CI placement, assertion strength, and whether failures block delivery. An uncovered line is first a delete candidate, then a test candidate (`references/test-code-authoring-patterns.md` §6).
- Classify test evidence quality before using it in a completion claim: strong tests are deterministic and assertion-based; medium tests assert behavior but depend on fixed DB/cache/network state; weak tests only log/print, sleep, use random/live data, call live model services, or sit behind non-blocking CI. Weak tests can inform risk but cannot prove correctness. Evidence about an agent's own output observes the world, not its self-report (`references/e2e-real-flow-testing.md`, Verify The World).
- Treat scenario testing as a planning layer, not automatically as E2E: start from user/caller journey, risk, persona/role, data state, environment, and expected evidence, then place assertions at the unit/contract/integration/E2E/exploratory/release-smoke layer.
- Every critical scenario needs at least one automated assertion at the lowest layer that can prove the risk, plus real-flow smoke only when cross-boundary behavior matters; built/installed deliverables need one smoke via the published entry path (`references/e2e-real-flow-testing.md`, Published Entry Path).
- Happy-path tests are insufficient for high-risk workflows. Build a compact risk matrix and cover the triggered failure classes — the canonical failure-class list lives in `references/scenario-testing.md`.
- Composite / multi-stage pipelines (a capability built from several modules, services, or model stages chained together) need acceptance at three layers, not just one: **module-level** (the changed stage's own correctness, errors, latency, fallback), **chain-level** (upstream/downstream input-output contracts, version pass-through, end-to-end recovery and rollback), and **product-level** (the user-visible outcome / acceptance baseline holds); see `references/scenario-testing.md`.
- Maintain a frozen regression set of real past failures (every fixed bug / incident / confirmed bad case becomes a case) and run it on **every release**, not ad hoc (`references/ci-fixtures-and-flake-control.md`).
- Use the repository's own test wrapper when it exists; it encodes env, codegen, fixture, timeout, and CI parity.
- Use the right test double: stub to supply inputs, fake to emulate dependency behavior, and spy/mock to verify interaction only when the interaction is the contract; double the expensive/nondeterministic/unsafe/privileged/unavailable boundary and keep the rest real on isolated test-owned resources (`references/test-code-authoring-patterns.md` §5; external-provider recovery paths: `references/ci-fixtures-and-flake-control.md`, Fault-Injection Layers).
- Use integration tests where mocks would hide contract, transaction, serialization, permission, data-shape, or runtime failures.
- Use E2E only for critical user/caller workflows and release confidence, not every branch through the browser.
- A passing test must assert the outcome. Clicking a button, calling an endpoint, or seeing status 200 is not enough. **Every property a test NAMES — in ANY name a reader or a runner sees: the function name, a docstring or comment, and equally an `it(...)`/`describe(...)` title, a Gherkin scenario name, a pytest parameter id, or a subtest/table-case label (`..._is_bijective`, `..._is_pinned`, "rejects out-of-range input") — is a claim, and each named property owes a killing mutation: the concrete implementation change that would make this test fail.**
  - Drive the walk from the **named properties in every changed test artifact, not from the changed assertions** — renaming a test or adding a docstring line introduces a new claim while touching no assertion at all. For each named property write the mutation: break what the property names → the test must go RED → restore and re-run. Mutate in a **disposable checkout or with the restore guarded** — never by hand-editing a dirty worktree.
  - **Guard it positively rather than resolving to be careful, and keep the guard out of version control** — the executable backup recipe, the git-as-scratch-buffer rebuttal, and the blast-radius discipline live in `references/run-killing-mutation-walk.md`. Verify the tree is back to its pre-mutation state before trusting any later run, since a green result on a still-mutated tree certifies the wrong thing.
  - **When the artifact under test is DESTRUCTIVE or irreversible** (a script/recipe that deletes/overwrites/prunes worktrees, branches, files, records; bulk or `--force`-class mutation), a one-off walk is not enough to discharge this rule: **encode the walk as a probe inside the suite** — a bare non-zero exit does not qualify; right-reason/differential attribution and the probe's anchor/recursion guards live in `references/run-killing-mutation-walk.md`.
  - **The walk proves only the pins that exist — coverage runs in the reverse direction, artifact → pin: an unpinned obligation produces no signal in any walk and is silently deletable.** Every obligation sentence of the pinned artifact must name the pin that reds on its deletion; enumeration method and structural probes live in `references/run-killing-mutation-walk.md`.
  - A property whose killing mutation you cannot name is not asserted — add the assertion, or rename the test to what it checks.
  - Two shapes reading the test cannot catch: a test asserting only that a constant equals its own literal under a behavioral name (a change-detector per the rule above), and — the narrow case — a reverse **expectation** computed from the same source as the forward one, so both drift together and the assertion cannot disagree with itself; the round-trip nuance lives in `references/run-killing-mutation-walk.md`.
- For nondeterministic output, assert structure, invariants, bounds, and required content rather than exact text (`references/integration-contract-testing.md`).
- Assert a security/safety **boundary positively when the contract is closed (only-X-is-allowed)**: prove the observed surface matches the allowed contract, not merely that known-bad values are absent; report oracle dimensions crossed and keep precision near-miss rows per `references/design-closed-contract-oracles.md`.
- For user-visible, contract-visible, bug-fix, or test-harness behavior changes, follow the test-case register and RED-before-implementation rule below; do not downgrade it to a preference.
- Never delete, skip, or weaken a failing test just to pass — route failures through `defect-diagnosis`; removing a redundant/obsolete/duplicate test is valid maintenance, weakening or skipping a failing one is not.
- When a CI step or review claim compares a checked-in copy of a vendored external contract/conformance artifact (vendored API/schema/wire/envelope/validator/fixture content — ambiguous upstream artifacts default in-scope; lockfile/digest-pin checks that vendor no such content are out) against a manifest, digest list, or pinned source, run `references/vendored-contract-drift-checklist.md` as the authoritative gate: enumerate scope → fill the per-row applicability ledger → emit an explicit `pass`/`non-pass`/`inapplicable` verdict (never a bare scope label or a comprehensive green).
- Any claim that the implementation AGREES WITH an external contract you do not own — pinned to, conforms to, compatible with, implements, supports, matches, or interoperates with a peer schema, published wire/file format, or vendor envelope; the trigger is the agreement claim, not one wording of it — requires at least one **real sample produced by that side** to have been exercised; fixtures hand-built from the contract document prove only that the code matches your reading of it (`references/integration-contract-testing.md`).
- Benchmarks, smoke scripts, and manual click-throughs never replace assertion-based unit, contract, integration, or E2E tests; neither do structure scripts, scaffold checks, grep checks, or compile-only gates when a change adds real UI interaction, routing, API clients, permission behavior, failure handling, or user-visible state. If that is the repository's only test layer, add a small deterministic test framework and focused tests in the same delivery slice instead of treating the scaffold check as enough.
- For UI that calls APIs, one test layer is not enough; mocked component tests must not be treated as proof that runtime integration works (`references/integration-contract-testing.md`).
- A test that pins an input the production default leaves unset — or supplies a controlled value for a normally-defaulted condition — can pass while the real default/unset path is broken (`references/test-code-authoring-patterns.md` §11).
- When an enforcement gate, tripwire, or guarantee is re-routed through a new indirection layer (A→B→C instead of A→C) AND that indirection can change which check runs, its execution mode, filtering/suppression, or failure mapping, re-pin the externally-observable contract — not the intermediary's internals: prove the gate still runs in the mode the caller actually uses (not a filtered/quick/subset mode that silently skips it) and that a violation still propagates to a non-zero/blocking outcome (`references/integration-contract-testing.md`).
- Conditional skips (missing-optional-dependency guards such as module-level `importorskip`, platform/env markers) combined with per-job test selection can leave an entire test file executed in NO CI job while every pipeline stays green: the job that selects the file lacks the optional dependency (the skip fires for the whole module), and the job that has the dependency does not select the file (`references/ci-fixtures-and-flake-control.md`).
- A new, ported, or mirrored enforcement mechanism (pre-edit hook, permission guard, write-blocking plugin, validator) is not verified by loading, parsing, or config inspection — those prove installation, not enforcement (`references/verify-enforcement-mechanisms.md`).
- A "skip CI" / "no runner" instruction does not by itself lower verification rigor, only ceremony (`references/ci-fixtures-and-flake-control.md`).
- Browser/E2E smoke must assert visible outcomes, not just click controls; UI tests and screenshots must prove design quality layers, not only DOM existence (`references/e2e-real-flow-testing.md`).
- For every runtime-visible UI/UX slice, load the canonical sequence in `../product-ui-ux-design/references/delivery-contract.md` and `references/client-runtime-test-matrices.md` §UI/UX Delivery Contract before Phase 0 and after producer/client execution. Testing owns layer selection and sufficiency, binds and cites the complete design/test/producer/client record and candidate-binding sets, confirms every affected client wrote its canonical pre-edit `client_entry` and complete client-record member naming the producer version it exercised, fails closed on a missing/incomplete/mismatched/stale/changed-after-run/unexercised member, and never issues the holistic design verdict.
- Authentication and account surfaces need an explicit scenario matrix before they can be called complete (`references/scenario-testing.md`).
- Test cases come before implementation and broad execution for behavior-changing work. Write a compact test-case register first: scenario, layer, assertion, data/dependency, command, expected current result (`fail`, `pass-existing`, `blocked`, `infra-error`, or `gap`), and owner. For bug fixes and user-visible or contract-visible behavior, at least one relevant case must be added or updated and run RED before implementation unless no harness can support it after normal remediation; then record the evidence gap and strongest alternate check. The same RED-first discipline applies to defect records: a reported defect (issue, QA finding) carries the repro command plus the actual failing output, and the fix change references that failing test — a bug "fixed" from its description alone, without a RED reproduction, is unverified.
- Do not answer "tests are complete" from command output alone. Map each important scenario to a written case or an explicit `blocked`, `live-only`, `product gap`, `infra-error`, or `not applicable` row. (verdict definitions and their mutual exclusivity: `references/ci-fixtures-and-flake-control.md`).
- For report-only QA, baseline comparison, or "testing only" branches with no product-code changes, failing tests can be the intended deliverable (`references/ci-fixtures-and-flake-control.md`).
- Generated starter tests are not regression evidence: replace scaffold placeholders in the same delivery slice with assertions for the actual app shell, route, state, or user-visible contract.
- Verification warnings are not automatically follow-up work; do not open, merge, or describe an MR as ready for a contract-visible change until the test matrix is written and executed, or each unavailable layer is explicitly marked unavailable with reason and residual risk (`references/ci-fixtures-and-flake-control.md`).
- A multi-stack development-standard family is incomplete without a testing standard. The testing standard must define test deliverables, layer policy, harness expectations, CI gates, high-risk coverage, evidence format, and stack handoff rules; stack docs may specialize commands but must not redefine the layer policy.
- Do not mark a browser/device/E2E layer unavailable just because discovery returns nothing (`references/e2e-real-flow-testing.md`).
- If a browser/device/E2E or host-smoke layer is classified as blocking, unavailable means the delivery is not complete. Use `pre-runtime-test-ready` only when code, lower-layer tests, and build checks are done and a named human/device owner must finish the runtime gate; a handoff-only label, not merge-ready/release-ready. Otherwise use `blocked`. Do not describe such work as done, fixed, merge-ready, or release-ready.

## Entry Decision: TC Source and Scope

Before any test design or implementation work, resolve two questions: where do the test cases come from, and what is the scope.

### Step A — Resolve acceptance and TC sources

1. **For behavior-changing product delivery, always resolve the acceptance source first.** Record `acceptance-source lookup: found <artifact/section>` or `acceptance-source lookup: absent <locations checked>`. When found, preserve the complete point-ID set and source decisions; TCs may refine but not silently narrow it. When absent, functional completeness is blocked: route to `product-rd-workflow` to establish the acceptance inventory — `test-artifact-management` may only run after an authoritative inventory exists, because it can generate cases from existing code and would reproduce the omission blind spot; code analysis remains supplemental. A delivery carrying an entry-classified functional-axis exemption claim (documentation-only, pure refactor, or mechanical maintenance per `product-rd-workflow`; the reviewer confirms or rejects the claim at closeout) is outside this step — cover it as existing-behavior/refactor coverage per the no-TC fallback in `references/structured-tc-input-translation.md`.
2. Resolve direct TC inputs, `.report-config.json` auto-read, no-TC fallback, and the expected TC-vs-test-code coverage gap per `references/structured-tc-input-translation.md`.

When TCs are available, pass the full list through **When Input Is a Structured TC List** and `references/structured-tc-input-translation.md` before doing anything else.

### Step B — Determine scope (if not already bounded)

A current acceptance source or reviewable task artifact may already confirm scope. In particular, a UI/UX Design brief with a stable slice/surface, authoritative consumer inventory, affected owner(s), and criterion IDs is the confirmed bounded scope for its Phase 0/Phase 1 work; consume it instead of asking the user to restate global/file/function scope.

If neither the request nor a current authoritative artifact bounds the work, inspect the current task, repository contract, diff/target, and available acceptance sources first. Ask only when two or more plausible scopes remain and choosing among them would materially change the test plan. Then ask the smallest concrete question, for example:

> 请确认测试范围：
> 1. 全局 — 整个仓库 / 当前 feature 所有文件
> 2. 文件 — 指定文件（请提供路径）
> 3. 函数 / 接口 — 指定函数或 API endpoint（请提供名称）

Do not infer scope from stale conversation or an unverified guess. A current, resolvable Design brief or accepted scope artifact is evidence, not inference. If the inspection leaves one material scope, proceed and record its source; if ambiguity remains, wait for the user's answer before layer assignment. After confirming scope, apply global/file/function narrowing per `references/structured-tc-input-translation.md`, then proceed to **When Input Is a Structured TC List** (if TCs available) or **Workflow Step 1** (if no TCs).

---

## When Input Is a Structured TC List

When the input is a set of structured test cases from `test-artifact-management` or a Feishu Bitable TC list, use `references/structured-tc-input-translation.md` as the translation guide (status pre-check, priority/layer separation, sidecar metadata, and ownership handoffs), then run the standard workflow from Step 1.

## Workflow

Before editing tests, CI gates, mocks/fakes, fixtures, test scripts, verification docs, or implementation tied to a testing request, complete enough analysis and planning for the testing change to be reviewable. Scale the plan to risk: a simple low-risk single-test addition can use a short inline plan; multi-layer, user-visible, contract-visible, flaky, release-blocking, bug-regression, branch/MR, unclear-risk, or high-risk work needs explicit scenario/risk matrix, test-case register, task split, expected failing test or evidence gap, verification commands, and stop conditions before edits.

1. Discover the repository's test topology (read local guidance, wrappers, markers, noise exclusions, and scaffold checks per `references/test-topology-and-commands.md`).

2. Identify the behavior to prove.
   - User/caller outcome.
   - Contract, state, side effect, emitted event, rendered UI, permission behavior, or operational signal.
   - Risk if wrong.
   - Scenario dimensions when relevant: persona/role, entry path, data state, permission, dependency health, device/browser/platform, locale/timezone, network quality, and recovery path.
   - For API, protobuf-backed HTTP, RPC/base, and boundary-exposure contract changes, record the contract definition first and apply `references/integration-contract-testing.md` (missing or unverified owner/boundary evidence is an `open coverage gap`, not pass).

3. Choose the lowest sufficient test layer.
   - Unit: pure logic, validation, mapping, config, retry decision, state transition, key builder, error translation.
   - Component/API/contract: handler, generated client/server contract, serialization, auth envelope, route mapping, public API compatibility.
   - Architecture/static: dependency direction, module boundary, generated code cleanliness, forbidden import, schema drift, or migration shape.
   - Integration: DB, Redis, MQ, filesystem/object storage, service client, transaction, migration, real parser/generator, dependency adapter.
   - E2E/real flow: critical user journey, cross-service workflow, browser-visible behavior, release smoke, or runtime integration that lower layers cannot prove.
   - Scenario matrix: select a small set of representative happy, negative, edge, recovery, permission, and regression scenarios; map each scenario to the cheapest layer that proves it, then add one real-flow check for the highest-risk cross-boundary journey.
   - **A property about what is NOT emitted can only be proven where the emission happens** (`references/integration-contract-testing.md`).
   - High-risk resilience matrix: for each triggered class, choose the lowest layer that can prove the invariant, then add one release drill or real-flow smoke for the most expensive failure (`references/scenario-testing.md`).

   For client API-backed surfaces, mini-program/mobile/device runtime smoke, runtime-client mechanisms (route guards, permission trees, request interceptors, generated clients, upload wrappers, long-task polling, safe-area/keyboard/orientation handling, foreground/background restore, native bridges, app-hosted H5), terminal/CLI/TUI runtime tests, and streaming/async-finality changes (model streams, queued jobs, MQ consumers, scheduled prompt tasks, cron tasks, persisted tool-output artifacts, long-running exports, long-lived connections), load `references/client-runtime-test-matrices.md` before assigning layers — and again before declaring any runtime/device/browser evidence unavailable, not only at layer assignment.

4. Define data and dependency strategy.
   - Use small fixtures named by scenario. For repeated/complex fixture construction, pick §4 (factory/builder) from the decision table in `references/test-code-authoring-patterns.md`.
   - Use fakes for domain behavior and integration tests for external contracts.
   - Keep real credentials, live services, long sleeps, and network-only dependencies out of default fast tests.
   - Tests that hit live DB, Redis, MQ, RPC, model service, object storage, or real external APIs must be marked or commanded as integration/e2e/drill tests. They are release evidence, not the default fast gate, and they must not replace lower-layer assertions.
   - Before a scripted live runtime turn, invoke the repository's input preflight; reject invalid prepared input before dispatch. If it is absent or unsupported by the send path, record `preflight: unavailable(<reason>)` and implement/connect a supported preflight before dispatch. Load `references/e2e-real-flow-testing.md` (Runtime input preflight).
   - Before tests or verification that write files or seed/mutate tracked files, load `references/test-data-and-determinism.md` (Test-owned files) for temporary evidence and cleanup boundaries.

5. Define assertions and evidence.
   - Assert final user/caller-visible result. Author code per that table — §8: parameterize same-logic inputs instead of copy-pasting — and its closeout checklist walk is required before review.
   - Assert persisted state, emitted event, dependency call, trace/log id, or browser-visible state where relevant.
   - For E2E, capture console errors and failed network requests when tools support it, and collect screenshots/video/traces when useful, but do not rely on artifacts without assertions (`references/e2e-real-flow-testing.md`).

6. Place in CI intentionally.
   - Fast gate: format, compile/typecheck, lint/static checks, focused unit tests, deterministic codegen clean check.
   - Integration gate: runs only when stable infra or containers exist.
   - Scenario gate: small acceptance/risk matrix mapped to unit, contract, integration, component, or E2E commands with clear owners for failures.
   - E2E/release gate: critical smoke and regression flows, isolated environment, explicit owners for failures.

## Reference Loading

- Provenance & extraction boundary: `references/source-evidence-map.md`.
- Topology, wrappers, hermeticity, and runner choice: `references/test-topology-and-commands.md`.
- Scenario matrices, pipeline scope, and high-risk failure classes: `references/scenario-testing.md`.
- Unit tests, fakes, and table tests: `references/unit-testing.md`.
- Fixtures, builders, fuzzing, property tests, and determinism: `references/test-data-and-determinism.md`.
- API, contract, protobuf/RPC, DB, Redis, MQ, and differential tests: `references/integration-contract-testing.md`.
- Client API surfaces, mobile/miniapp runtime smoke, and async finality: `references/client-runtime-test-matrices.md`.
- Batch jobs, streams, scheduled jobs, backfills, and replay: `references/data-and-workflow-testing.md`.
- Browser, real-flow, preflight, and E2E evidence: `references/e2e-real-flow-testing.md`.
- CI gates, external-asset fixtures, flake control, and QA reporting: `references/ci-fixtures-and-flake-control.md`.
- Structured TC translation, scope narrowing, and Bitable handoff: `references/structured-tc-input-translation.md`.
- Test-code authoring patterns (§1–§11) and closeout checklist: `references/test-code-authoring-patterns.md`.
- Architecture fitness functions (Ford et al. 2017): `references/fitness-functions.md`.
- Killing-mutation walk, backup recipe, and destructive-artifact probes: `references/run-killing-mutation-walk.md`.
- Closed-contract oracles, dimensions, and precision near-miss rows: `references/design-closed-contract-oracles.md`.
- Enforcement-mechanism behavioral matrices and port/mirror parity: `references/verify-enforcement-mechanisms.md`.
