# E2E And Real-Flow Testing

Use this for critical user journeys, cross-service flows, release smoke, browser workflows, and runtime integration that lower-level tests cannot prove.

## When E2E Is Worth It

- Login/onboarding/payment/publish/export/import or other primary user flows.
- Permission-sensitive or role-sensitive workflows.
- Cross-service state change where API, UI, worker, and persistence must align.
- Browser-specific interaction such as routing, forms, uploads, keyboard/safe-area behavior, dialogs, or responsive layout.
- Release smoke for the highest-risk changed path.

Before adding a new E2E test, create or update the scenario matrix in `scenario-testing.md`. Keep only the cross-boundary proof in E2E; push deterministic permutations down to unit, contract, component, or integration tests.

## Browser E2E Rules

- Use stable selectors or accessible labels; avoid brittle text-only or CSS-position selectors.
- Prefer accessibility-tree element references or role/name selectors when the browser tool supports them; they survive layout changes better than coordinates or CSS paths.
- Re-read visible state after every action that should change the page.
- Wait for explicit conditions: URL transition, visible text, DOM state, event, network idle, persisted state, or backend signal.
- Avoid fixed sleeps except as a last resort with a clear reason.
- Use isolated browser/session contexts for different users or roles.
- Save authenticated state only when the test is not about login.
- Capture console errors, failed network requests, screenshots/traces/video when useful.
- Use network interception only to control nondeterminism or assert payloads; do not mock away the contract that the E2E test is meant to prove.
- **Playwright 1.5x baseline (Microsoft, ongoing 2024-2026)** is the current default-recommendation browser-E2E framework for new web testing. Key features to use deliberately, per `playwright.dev` docs: (a) **Trace Viewer** is the load-bearing debugging surface — every CI failure should produce a `trace.zip` artifact. Set `trace: 'retain-on-failure'` (not `'on-first-retry'`) when CI runs with `retries: 0` for deterministic gating — `'on-first-retry'` produces no trace unless the test actually retries, leaving teams with zero diagnostics on first-failure-then-fix-the-flake debugging cycles. Reviewers open the artifact locally or via `trace.playwright.dev` to step through actions, screenshots, network, and console without re-running the test. (b) **Soft assertions** via `const softExpect = expect.configure({ soft: true })` let one test report multiple failures rather than stopping at the first — useful for state-snapshot assertions where the team wants the whole-page diff in one run, NOT a substitute for the "one test, one behavior" discipline. (c) `toMatchAriaSnapshot()` (Playwright 1.49+) is the structured accessibility-tree assertion — call it on a locator (`expect(page.locator('main')).toMatchAriaSnapshot(...)` or `await page.locator(...).ariaSnapshot()`), preferred over DOM-string snapshots for resilience to non-semantic markup changes. (d) **Component testing**: Playwright's current component-testing guide replaces the former `@playwright/experimental-ct-{react,vue}` packages (`playwright.dev/docs/test-components`) — that replacement statement is all the source establishes; draw no stability or package-layout inference from it, and follow the pinned Playwright version's own installation instructions before adding or removing any component-testing package. Vitest browser mode remains a valid component-level alternative when the portfolio already standardizes on Vitest. (e) **Projects** in `playwright.config.ts` define run matrices (browser × device emulation × baseURL × config variant) and produce one merged HTML report. Note: Projects ≠ sharding — sharding is a separate `--shard=k/n` mechanism that splits a single project's tests across multiple workers/machines; teams often combine both (projects for the matrix, sharding for parallelism per project). Pin worker count and shard count for CI determinism, do not let auto-detect choose. Routing the per-stack Playwright config implementation goes to `web-react-dev/references/web-quality-release.md`; this skill owns the test-layer policy.

## Runtime QA Sweep

Use this only as bounded runtime acceptance / release-smoke evidence for the scenario-matrix paths whose risk needs runtime proof — it is not exploratory QA and cannot close coverage on its own; push deterministic permutations down to unit/contract/component/integration tests. When smoke-testing a running web surface, sweep these bug categories (not only the one happy path); several are invisible in the rendered UI unless you look:

- **Functional:** dead controls (click does nothing), broken or wrong-destination links, form validation that is missing or bypassable, state not persisting across refresh / back-button, and double-submit or stale-data races.
- **Console / network:** check the console *and* the network panel after interactions, not only on load. Watch uncaught JS exceptions, failed 4xx/5xx user-path requests, and the often UI-silent classes — CORS failures, mixed content (an HTTP resource on an HTTPS page), CSP violations, and deprecation warnings (these surface in the console and frequently as blocked/failed network entries). **Classify before calling any of them a defect** (per the skill's verification-warning rule): product-owned exceptions, failed supported-user-path requests, enforced CSP breaks, blocked mixed content, and unexpected CORS on a supported environment are defects; CSP report-only entries, expected negative/preflight denials, dev-only proxy noise, and third-party deprecations outside the team's control are observations unless they block a supported user path or the current slice caused them — record owner + residual risk rather than failing the sweep blindly.
- **Performance:** cumulative unexpected layout shift across the page lifecycle (CLS — e.g. content jumping after a late-loading image or ad, not only after first paint), and request-pattern smells (unexpected growth versus baseline, duplicate requests, N+1 fan-out, unbounded polling, or unbatched fetches). A high request count alone is not a smell — dashboards, feeds, maps, and streaming surfaces legitimately make many requests with documented pagination or parallel panels.
- **Auth boundary:** what the surface does when logged out and across the relevant user roles, not only the authenticated happy path. **Run these only against staging, synthetic tenants, or read-only / dry-run paths.** Verify privileged or destructive actions by their guardrails — visibility, disabled state, confirmation copy, permission denial, and audit metadata — or via a dry-run / mocked request; do NOT execute the privileged/destructive action itself (irreversible writes, account/session changes, money/quota mutations, deletes, admin repairs) against real data as part of a sweep. A genuine end-to-end test of such an action is a separately-authorized E2E case against synthetic data, never a sweep step.

Capture evidence per the `Browser E2E Rules` above (console/network/screenshot/trace). Preserve every runtime failure or ambiguous red signal as evidence and route it through `defect-diagnosis` (label "confirmed defect" only after triage — never drop or greenwash an unconfirmed failure). Proven categories belong in the `scenario-testing.md` matrix and lower-layer tests, not re-verified by hand every release.

A sweep is **report-and-route, not fix-in-place**: document each finding (severity, category, expected-vs-actual, repro evidence) and route it through `defect-diagnosis` for triage — only confirmed defects proceed to cause + fix + regression evidence; observations (CSP report-only, expected denials, third-party deprecations, ambiguous reds) stay recorded with owner, residual risk, and follow-up path, not treated as defects before triage. During the sweep, treat product/runtime code as read-only (external-state mutation stays governed by the auth-boundary rule above — controlled synthetic/dry-run submits for the functional checks are fine; unrequested or real-data destructive mutation is not): you may write evidence artifacts and scoped QA/test files when they are part of the requested deliverable, but do not make a finding green by patching product code, so a read-only QA / acceptance pass cannot silently become unrequested code changes. If the current-turn request explicitly asks for QA *and* fixing, close the sweep evidence first, then start a separate `defect-diagnosis` phase before any product-code edit.

## Backend/API Real Flows

- Assert response envelope, canonical error code, trace/log id, persisted state, emitted event, and dependency outcome.
- Include setup and teardown or use isolated test tenants/namespaces.
- Make idempotency, retry, and compensation behavior visible.
- Treat live-data scripts, production-like IDs, replay tools, and tests that only log or panic on error as diagnostic until they are isolated, repeatable, and assertion-based.

## Verify The World, Not The Self-Report

When the subject under test is an agent's or automation's own output — a file it says it wrote, a command it says it ran, a state it reports — the assertion re-observes the world independently through **read-only inspection of durable effects**: re-read the file from disk, query the authoritative persisted state, and assert that files the run should not have touched are byte-identical. An audit/log record counts only when it is emitted by an authoritative subsystem **outside the subject's own write/control boundary** and is correlated to the operation and the resulting state — a success record the subject wrote itself is a durable self-report, not evidence; when no independent durable-state observation is safely available, classify the check as incomplete rather than pass it on the record. Re-run a reported command only when it is known read-only or idempotent and confined to a test-owned resource — re-running a deployment, migration, payment, or retry mutates state a second time and still cannot show the original run happened. A keyword probe over the agent's own transcript or summary is not evidence — it lets a cheating or mistaken agent pass. Such tests own their resources: create the harness inside the test and dispose it in a teardown hook that runs on cooperative failure, retry, and in-process timeout — and, because a hard-killed runner never reaches teardown, back durable or external resources with an out-of-process cleanup: tag them with the run id and a TTL and run a bounded janitor/finalizer keyed to that run, so repeated CI runs cannot leak state or retain sensitive test data. Put shared fixtures in a plain helper module rather than importing another spec (re-registering its cases duplicates real runs). The delegation-side rule (do not accept a sub-agent's report as proof) is owned by `multi-agent-delegation`.

## Published Entry Path

When the deliverable ships as a built or installed artifact — a package `bin`, a bundled worker or non-index runtime entry, a plugin loaded by a real loader, a container image — at least one smoke must enter through that published path: the built artifact under the plain runtime, the real loader boot, the installed command. Dev/source-path runners, hot loaders, and hand-mounted test compositions mask module-resolution failures, settle races, and swallowed load errors that only the shipped path exposes; this is the "green unit tests, broken product on start" class. Mock only external services or nondeterministic inputs in that smoke and assert model-visible request/log, durable state, or user-visible output; a genuinely missing config must exit non-zero.

## E2E Scope Control

- Do not reproduce every unit branch through E2E.
- Keep E2E flows few, stable, and tied to user/business risk.
- Prefer one happy path plus high-risk negative paths over many shallow click-throughs.
- A click-through without assertions is not E2E evidence — and weak proxy signals are not business assertions: page loaded, URL changed, non-empty body text, a generic button/canvas/heading visible, or a success toast alone do not prove the business outcome. Anchor the pass condition on objective effects — API response fields, persisted records, balance/count deltas, generated artifact URLs (sufficient alone only when URL issuance is the claimed contract; a generation-success case dereferences the URL and validates artifact status/metadata/content, since a request can issue a valid URL and fail before storing the artifact), or a stable user-visible terminal state (alone only when the visible terminal presentation IS the claimed contract — a rendered "completed" can outrun persistence/billing/artifact creation, so business-outcome cases pair it with the durable effect) — and match assertion strength to what the test title and scenario row claim; a shallow signal is acceptable only when the case explicitly tests just that shallow signal.
- If a scenario can be proven with a stable API/contract/integration test and only needs one browser smoke for confidence, do not duplicate all permutations in the browser.
- External-provider fault/recovery permutations (disconnects, malformed streams, rate limits) belong at the protocol-real fault-server and recorded-replay layers (`ci-fixtures-and-flake-control.md`, Fault-Injection Layers); the live credentialed e2e keeps one wiring sanity path, not the fault matrix.

## Failure Handling

If E2E fails:

- Treat it as a real signal until proven invalid.
- Preserve trace, screenshot, console/network errors, payload, and environment.
- Route through `defect-diagnosis`.
- Do not replace the scenario with a thinner mock-only test unless the E2E scenario was invalid or redundant.
