# Scenario Testing

Use this when the user asks for scenario tests, acceptance coverage, user workflow acceptance tests, product-risk tests, or "real user" verification.

## Core Rule

Scenario testing is a coverage model, not a single test runner. Do not automatically turn every scenario into browser E2E. Define the scenario, identify the risk, then place proof at the lowest layer that can assert the behavior.

## Requirement-derived completeness

For behavior-changing product delivery, begin with the active requirement or acceptance source and preserve its stable point IDs and explicit `in` / `out` / `deferred` decisions. Then add code-derived scenarios for boundary conditions, failure paths, permissions, compatibility, and regression risk. Implementation-derived tests alone cannot reveal a required behavior that was never implemented.

| Requirement / acceptance point | Source decision | Implementation surface | Scenario / test | Layer / command | Fresh result / evidence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| stable point ID and observable behavior | in / out / deferred, with source authority | code, API, UI, config, migration, job, or docs | assertion or real-flow proof | lowest sufficient layer and exact command | result, trace, screenshot, or response | satisfied / gap / blocked / unknown / out / deferred |

Every in-scope row needs fresh evidence. `gap`, `blocked`, or `unknown` blocks a complete test verdict; `out` or `deferred` is valid only when the active product or human source made that decision. Keep this closure table beside the risk-oriented scenario matrix below rather than replacing it: the first prevents omitted scope, while the second finds failure modes within that scope.

## Scenario Matrix

Create a compact matrix before writing broad tests:

| Scenario | Risk | Layer | Data/dependency setup | Assertion | Evidence |
| --- | --- | --- | --- | --- | --- |
| Primary success path | user/caller cannot complete the core action | component/API/E2E | minimal valid fixture or test tenant | visible result, response, persisted state, or emitted event | command, trace, screenshot, or API result |
| Permission or role path | unauthorized action succeeds or authorized action is blocked | unit/contract/E2E | role/capability fixture | allowed/denied state and copy/status | focused test plus one real-flow check when UI-visible |
| Empty/partial data path | page or workflow crashes, misleads, or blocks recovery | component/integration | empty, partial, stale, or migrated data | fallback state, disabled action, retry, or guidance | rendered assertion or API invariant |
| Failure/retry path | dependency failure loses work or hides recovery | unit/integration/E2E | timeout, non-2xx, malformed payload, queue retry, offline | error mapping, retry, idempotency, rollback, or compensation | assertion plus logs/trace when relevant |
| Edge-volume path | slow, clipped, paginated, or truncated behavior | unit/component/integration/perf | large but bounded fixture | pagination, virtualization, batching, backpressure, or budget | test output and performance signal |
| Regression path | previously fixed bug returns | lowest sufficient layer | named regression fixture | exact failed behavior stays fixed | failing-before/fixed-after evidence when feasible |

Keep the matrix small. It should cover distinct risks, not every permutation.

### Release/Control-Plane Scenario Matrix

Use this matrix when the changed system deploys, registers, proxies, migrates, or operates other services. Place most assertions at unit, contract, or integration layers; add one controlled release smoke only for cross-boundary behavior that cannot be proven lower.

| Scenario | Risk | Layer | Data/dependency setup | Assertion | Evidence |
| --- | --- | --- | --- | --- | --- |
| Approval and release gate | unauthorized, expired, duplicate, or partial approval changes production state | unit/contract/integration | reviewer roles, expiry window, duplicate request ids, approve/reject threshold | idempotent task creation, reject/approve precedence, lock behavior, transaction status, audit fields | focused service test plus API trace |
| Deploy progress stream | CLI or UI reports success while deployment is still pending or failed | unit/contract/integration/release smoke | fake watch events, timeout, cancellation, final success/failure event | progress events normalize status, timeout is terminal, final result controls exit code or visible state | command output, event log, or controlled smoke |
| Service registration and sidecar health | stale instances stay registered or unhealthy services keep receiving traffic | unit/integration/release smoke | register retry failure, deregister signal, failed health threshold, recent log fetch | register retry bounded, deregister-on-stop, health failure emits metric/log and stops routing | integration test or local sidecar smoke |
| Realtime notification channel | unread state or delivered messages diverge across connect/disconnect/MQ/cache paths | unit/integration/component | connected and offline clients, cache miss, MQ message, ack lock, reconnect | bootstrap count, persist-before-publish, offline no-op, cache increment/expiry, ack idempotency | cache/MQ assertions and rendered state when UI-visible |
| Cursor migration/backfill | data is skipped, duplicated, deleted early, or progress is misleading | unit/integration/drill | bounded source rows, chunk size, worker count, insert failure, restart/resume case | cursor windows cover all rows, target write before source delete, durable final state, restart policy clear | dry-run/integration output with row counts |
| Generated clients and proxy adapters | generated contract drift or missing metadata silently routes to the wrong service | contract/integration | generated client/server pair, missing destination metadata, lane fallback, EOF/error path | generator drift checked, required metadata rejected, context/log fields propagated, EOF handled deterministically | contract test, generator diff, proxy trace |
| Operations console surface | operator cannot inspect long identifiers, stale states, disabled actions, or failure details | component/browser smoke | long names, empty list, loading/error, failed mutation, permission-hidden action, drawer close/reopen | table/detail/drawer preserves identity, reloads after mutation, long values remain inspectable, disabled reasons visible | component assertions plus browser screenshot when layout-sensitive |

### Dense Analytics / Chart Workbench Matrix

Use this matrix when a web or app surface contains many charts, grouped tables, comparison targets, configurable thresholds, exports, or drill-down detail.

| Scenario | Risk | Layer | Data/dependency setup | Assertion | Evidence |
| --- | --- | --- | --- | --- | --- |
| Chart/table switch | chart and table answer different questions or lose filters/settings | component/browser smoke | same scope with chartable and tabular data | mode switch preserves scope, settings, comparison target, loading state, and export scope | component assertion plus screenshot when layout-sensitive |
| Large category set | labels, legend, or data points clip and users cannot read the chart | component/browser smoke | more categories than the default visible window, long labels, many series | data zoom or horizontal scroll appears, labels rotate/truncate, legend scrolls, tooltip remains readable | rendered assertion or screenshot |
| Benchmark/mark lines | baseline labels overlap or imply wrong comparison | component/browser smoke | one and multiple reference lines near data extremes | mark-line labels are visible, collision handling works, y-axis includes reference values | screenshot plus chart option/unit test when possible |
| Definition/rule popover | users lose metric meaning or stale popovers stay open across modules | component/browser smoke | module definitions, chart/table switch, module anchor switch, comparison target switch | popover opens near the affected module, closes or updates on context change, and does not cover the next action | component assertion plus screenshot |
| Threshold setting | local visual rules affect the wrong user or accept invalid intervals | unit/component | cached user id, valid and invalid min/max intervals, reset/default state | invalid interval disables save and shows inline error; save is user-scoped and refreshes affected module only | component test plus storage/cache assertion |
| Comparison mode | raw threshold colors and higher/lower comparison colors get mixed | component/browser smoke | raw values, target baseline, equal/higher/lower values, missing target | mode switch updates legend/copy, colors, and no-comparison state; color is not the only cue | component assertion plus visual check |
| Dynamic grouped table | exact-value audit becomes unreadable with many groups | component/browser smoke | many metric groups, long row labels, percent values near 100.00%, optional/additional items | fixed identity columns, grouped headers, right-aligned cells, tooltip/ellipsis, horizontal scroll boundary, no clipping, expanded parent context and collapse return position preserved | screenshot and DOM assertions |
| Split comparison fetch | one side fails or caches stale data while the other side succeeds | unit/component/integration | source and target fetched separately, retry one side, changed target id | split loading/error/retry, cache invalidation by scope/type/id, same-entity selection blocked | component/API-client assertion |
| Visual token consistency | chart modules pass logic tests but look inconsistent or inaccessible | component/browser smoke | loading, empty, error, chart, table, threshold, and comparison states | repeated surface, border, text, muted text, primary, semantic, and chart colors follow token/adapter rules and remain readable | visual comparison screenshot plus token/CSS assertion when possible |
| Cross-surface brand color | the same product renders different brand-primary on web vs native vs mini-program with no per-platform role naming in the design source AND no documented migration state | per-surface computed-style/screenshot + design-source role check | the highest-traffic page on each surface (web desktop, web H5, native app, mini-program); the design-source Variables panel (NOT a derivative export — per `multi-project-token-consistency.md` Source vs Export Distinction, exports collapse cross-collection aliases and per-mode bindings, so role-presence verdicts against an export are unsound) | three-layer evidence per surface: (1) design-source brand role + resolved value, (2) code-side theme injection value, (3) rendered computed style or screenshot pixel. Two values across surfaces are NOT automatically a failure — first run Migration-State Classification (`current` / `target` / `in-flight` / `drift`): a documented brand refresh in-flight with named migration signals is a planned-rollout finding, not a per-platform-role failure. After that classification, pass when permanent divergence is expressed with explicit per-platform role naming (`colorPrimary-web` / `colorPrimary-native` etc.) and each surface's three layers resolve to its assigned role; fail when permanent divergence has no per-platform role naming, OR when a single surface's three layers diverge internally. Vendor-default literal (`#1677ff` antd, `#0d6efd` Bootstrap, `#D93025` Google Material, etc.) appearing as the surface's rendered primary against a non-vendor declared brand is a separate per-surface fail. See `product-ui-ux-design/references/multi-project-token-consistency.md` Cross-platform brand divergence sub-case and Vendor-default-literal anti-pattern | per-surface computed-style assertion + design-source role inspection log |
| Export, drill-down, and cleanup | exported data or detail route no longer matches visible scope; chart instances leak after navigation | component/E2E smoke | active filters, selected module, table mode, detail item, export job, route leave | the export job payload (the server-side data request, not just the routed identifier) includes routed identity + filter-set + config-version + sheet/data selection + snapshot/generation token, and the artifact carries timestamp/staleness disclosure; drill-down and back restore module, filters, anchor/scroll when useful; chart instances, resize listeners, timers, and popovers clean up on leave | browser trace or screenshot + export-payload unit assertion |
| Cross-stack metric consistency | same metric renders different numbers on web, mobile-web, and native shell for the same scope/report/level | contract/integration/scenario | fixed report id + scope on all three surfaces; record the rendered top-line metric, at least one chart series, at least one table cell; also exercise pull-to-refresh / desktop hard refresh / native shell relaunch / offline-then-online recovery on each surface | (1) the canonical API contract assertion: the same source endpoint returns the same numeric payload regardless of which surface called it; (2) per-surface presentation assertions: each surface's documented rounding, timezone, privacy-suppression, offline-stale-label, and partial-data behavior is asserted in its own test; (3) per-surface lifecycle freshness assertions: after pull-to-refresh / hard refresh / shell relaunch / online recovery, the rendered value matches the latest API value (modulo the per-surface transform). Do NOT collapse (1)–(3) into a single "all surfaces show identical pixels" test — that drives engineers to remove legitimate per-surface transforms or freshness behavior to pass, which is worse than the original drift the test was meant to catch | numeric assertion against shared API + per-surface transform assertions + per-surface refresh/relaunch/online-recovery assertions |
| Cross-level scope ambiguity | same module key surfaces under multiple hierarchy levels (per-row / per-group / per-tenant / per-federation) with a single user-facing label, AND the same identifier is reused in route / cache / export / persistence keys across levels (analytics event taxonomy is checked separately for low-cardinality discipline, not for routed-tuple coverage) | component/browser smoke + unit | route the user directly into a per-group view of a module that also exists at per-row level; deep-link the same module key into both levels; capture the resulting route keys, data cache keys (including the per-sheetType variant), export filename / job payload, persistence keys, and — separately — analytics event identifiers and their dimensions | the surface visibly identifies the level (breadcrumb, scope chip, header copy) before the chart renders; switching level updates the visible level marker and preserves filter state; each key class composes its correct tuple: (a) routed identity (route key / deep-link / export filename) = `(moduleInstanceId | metricId, level, scope, report, tenant, schema-version)`; (b) export job payload / server-side data request = routed identity + `filter-set` + `config-version` + sheet/data selection + snapshot/generation token; (c) data cache key = `(sheetType | moduleInstanceId | metricId, report, level, scope, filter-set, tenant, schema-version, config-version)`; (d) local persistence key = `(userId, tenant, report, level, scope/resource, schema-version, surface-version)` plus `metricId | moduleInstanceId` when module-specific; (e) analytics event taxonomy stays low-cardinality (`metricId` + small enumerated dimension set), with `tenant`, `report`, `userId` only in first-party hashed/omitted correlation dimensions; deep links to two levels do not collide in any of (a)–(d) storage | component assertion + screenshot + key-shape unit assertion |

## Layer Mapping

- Unit: scenario logic, validators, state machines, permission decisions, retry choices, error mapping, data transforms, key builders, and edge cases.
- Contract/API: request/response shape, auth envelope, generated client/server compatibility, idempotency, pagination, error codes, and backward compatibility.
- Integration: DB transaction, cache, queue, file/object storage, real parser, local service adapter, migration, and worker behavior.
- Component/widget: rendered states, form behavior, validation, keyboard/focus, accessibility labels, disabled/retry behavior, and API-client state mapping.
- E2E/device/browser: only the critical cross-boundary flow, login/session behavior, routing/deep-link behavior, uploads/downloads, permission-sensitive visible actions, and release smoke.
- Exploratory/manual: usability, visual polish, awkward copy, performance feel, and surprising combinations that are hard to automate. Record findings as bugs or new automated regression candidates.

## High-Risk Failure Classes

The risk matrix for a high-risk workflow covers the triggered failure classes from this canonical list: duplicate submit/callback/message/job restart, permission service uncertainty, cross-tenant/user/resource mismatch, partial money/quota side effects, AI provider/model failure, unclear final status after refresh/offline, and missing trace/support identifier. Cover each triggered class at the lowest layer that can prove the invariant.

Cross-reference: `non-functional-specialized-scenarios.md` (High-risk resilience boundaries) states the launch-gate counterpart — which classes require scenario tests or drills at release. That is a gate-criteria list; this is the test-matrix failure-class list. The two complement each other and neither replaces the other.

## Composite Pipeline Acceptance Scope

The entry rule's three-layer acceptance for composite / multi-stage pipelines (module-level / chain-level / product-level) applies to behavior-affecting stage changes, contract/composition/fallback changes, or product-baseline-sensitive changes — a pure internal refactor with unchanged contracts may rely on existing lower-layer tests plus unchanged-contract evidence (do not force all three layers on every refactor).

## Scenario Selection

Prefer a few high-signal scenarios:

- One primary success path.
- One high-risk negative path.
- One permission or role path when access matters.
- One recovery path for failed dependency, retry, offline, timeout, or malformed response.
- One edge-volume path when lists, charts, files, streams, queues, or long content are involved.
- One regression scenario for each recently fixed defect or review finding.

Do not multiply by every browser, role, locale, data size, and dependency state unless the product risk justifies it. Use pairwise or representative coverage for combinations and push low-level permutations down to unit/contract tests.

## Acceptance And Evidence

Every scenario test needs an assertion that matches the risk:

- User-visible scenario: assert visible outcome, next action, focus/keyboard state, copy/status, or absence of dangerous control.
- API scenario: assert status, error code, response body, idempotency, persisted state, emitted event, and trace/log id when relevant.
- Worker/data scenario: assert terminal state, retry count, dead-letter or compensation behavior, output artifact, and data-quality invariant.
- Release scenario: assert the smoke path in the target environment and record skipped dependencies or unavailable credentials.

Screenshots, videos, traces, logs, coverage reports, and manual notes are evidence only when paired with assertions or a clear observed finding.

## Existing Test Audit

When extracting or reviewing an existing project's scenario coverage:

- Start from the command surface and CI, then map files back to commands. File names alone do not prove coverage.
- Preserve local markers and test lanes such as `integration`, `contract_*`, `api`, `e2e_smoke`, `failure_mode`, `drill`, `shadow`, `smoke`, or `replay`.
- Separate automated gates from diagnostic tools. Traffic replay, benchmark, shadow, drill, manual smoke, and live-debug tests can be valuable, but they need explicit owners, environments, and assertions before they become release gates.
- Mark tests that only log, panic on error, depend on production-like IDs, or require live services as diagnostic/live-infra tests unless they are isolated and assertion-based.
- Convert high-value diagnostic/live-infra scenarios into deterministic unit, contract, integration, or controlled E2E tests when they protect recurring release risk.

## Anti-Patterns

- Calling a long browser script "scenario testing" when it has no assertions.
- Duplicating every unit edge case through E2E.
- Testing only the happy path because it is easiest to automate.
- Treating mocked ideal API responses as proof that a real scenario works.
- Mixing unrelated risks into one scenario so a failure is hard to diagnose.
- Letting scenario fixtures become production data dumps.
- Counting dependency, virtualenv, third-party, generated, archived, or copied tests as proof of the active product's test coverage.

## Source Notes

- The test pyramid (Mike Cohn, *Succeeding with Agile*) supports many fast low-level tests, some service/integration tests, and few high-level E2E tests; practical elaboration by Ham Vocke: https://martinfowler.com/articles/practical-test-pyramid.html
- Playwright guidance supports user-visible locators and assertions against rendered outcomes rather than brittle implementation details: https://playwright.dev/docs/best-practices
- Testing Library guidance supports tests that resemble how users interact with the UI: https://testing-library.com/docs/guiding-principles/
- Pytest guidance supports explicit test discovery, package layout, markers, and reusable fixtures for deterministic tests: https://docs.pytest.org/en/stable/explanation/goodpractices.html
