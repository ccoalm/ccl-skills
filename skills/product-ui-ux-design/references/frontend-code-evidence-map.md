# Frontend Code Evidence Map

Use this reference when a task needs implementation evidence from frontend code. The rules below describe *how* to classify and use code evidence; specific local repository paths are kept in the private provenance archive outside this skill tree.

Users without code access can still use the distilled patterns in this file and in the platform-specific references. Do not require access to specific local paths unless the task explicitly asks to audit, update, or re-extract implementation evidence.

## Evidence Rules

- Absorb implementation mechanics only: state ownership, async handling, navigation, permissions, upload/progress, preview, review, charts, tables, tooltips, layout recovery, and build scripts.
- Do not copy source product names, business workflows, legacy information architecture, or visual taste into a generic product skill.
- Pin the fetched ref and candidate before comparing sources. “Latest” means the verified development ref after refresh, not the repository's default branch or a remembered path.
- Rank code by demonstrated mechanism and verification, not framework prestige or dependency presence. A component, story, test, or script that exists but was not executed is static-source evidence only.
- Trace at least one complete path from product-visible state or component API through its owner, renderer, test, and CI invocation before promoting a mechanism to a hard rule. Record what the gate scans and what it cannot detect.
- When auditing, updating, or re-extracting from source, treat package scripts and source structure as evidence only after confirming the subproject and invocation exist at the pinned ref. For normal use, rely on the distilled patterns below.

## Source Evidence Classification

For each frontend subproject in scope, classify the code evidence before extracting rules. The shape below is the classification frame; specific paths live in the private archive.

| Evidence level | Required evidence | Permitted use |
| --- | --- | --- |
| **Runtime-verified** | An executed runtime path on the pinned candidate plus bound focused assertions or deterministic gate results | Verified state semantics, component invariants, recovery, preservation, token use, accessibility mechanics, and gate boundaries within the executed scope |
| **Rendered, incomplete** | Current rendered output with traceable owners but incomplete test/CI or runtime coverage | Candidate interaction/state mechanisms and known evidence gaps; do not promote the missing layer by inference |
| **Static-source candidate** | Relevant source, focused test files, scripts, or CI wiring exist at the pinned ref, but execution and rendered/runtime output were not observed | Candidate mechanism and intended check only; never claim execution, runtime behavior, accessibility, visual quality, or completion |
| **Context only** | Dependency lists, examples, stories, screenshots, legacy code, or isolated source fragments without a traced mechanism | Hypothesis or matching-stack context only; never a visual benchmark or completion claim |
| **Backend (out of scope)** | Service-side code | Out of scope for this skill except for product-visible lifecycle consequences; route to the backend skill |

A dependency or directory name can classify likely stack shape; it cannot establish source strength, runtime behavior, accessibility, visual quality, or test execution.

## Static-Source Candidate Patterns

Retained evidence for the source-neutral patterns below is limited to the implementation paths, focused test files, scripts, or CI wiring actually observed for each pattern at the pinned ref; not every pattern has every layer. It contains no executed test/gate result and no rendered/runtime observation. The list therefore records candidate mechanisms and intended checks, not verified behavior or product quality.

- Product-visible error semantics: classify errors by affected scope, recovery path, durability/finality, and retry safety. Map each class to one primary carrier and safe action; prove mapping coverage when source error classes are enumerable.
- Component contracts: encode stable visual, state, and accessibility invariants in typed component APIs or semantic primitives, then pin the highest-cost invariants with focused tests. A component library import is not proof that callers preserve those invariants.
- Stateful workspaces: keep the draft/focus/selection/scroll/media core mounted across transient overlays, loading, errors, and mode changes when remounting would lose work. Verify preservation at runtime.
- Deterministic design gates: automate a small set of costly, enumerable failures such as unmapped states, forbidden raw values, missing semantic roles, or invalid component variants. Record scan scope, known false negatives, and the manual/rendered checks that remain.
- Semantic tokens and previews: treat tokens, state catalogs, stories, and examples as implementation sources that need drift checks. Token existence proves reference, not rendered theme quality; story existence proves source, not execution.
- Explicit async and trust states: represent initial/loading/partial/failure/retry/final states and expose source, freshness, permission, or automation status where it changes user decisions.
- Identity-scoped async effects: snapshot enough session identity at request dispatch to distinguish an account switch from same-account credential rotation, compute stale/current ownership once where request-time and current state are both visible, and expose only a non-secret conclusion to consumers. Before destructive cleanup, logout, navigation, or delayed initialization compensation, ignore superseded work and re-check queued work against the current session. Focused tests should cover account switches, credential rotation, anonymous-to-authenticated races, unchanged-session failure, overlapping initialization, legacy or missing metadata, and listener disposal.
- Analytics identity lifecycle: model binding, reset, pending cleanup, and rebinding as an explicit state machine across telemetry providers. On logout or authentication expiry, clear each provider and cached user dimensions; when a provider is unavailable, persist only the minimum scoped pending marker and flush it before binding another identity. Anonymous reset is a no-op, provider/storage failures stay isolated, credentials never enter page-wide events, and cross-tab/runtime limits remain explicit.
- Build scripts: preserve environment-mode, generated-client, preview, test, and build separation when the target codebase supports it; verify the actual script/CI execution and result before citing it as an executed gate.
- Mobile primitives: responsive shell, route guard, bottom navigation, safe-area/keyboard behavior using viewport-aware fallbacks, WebView bridge initialization, development-only debug tooling, touch gestures, portrait/landscape review modes, left/right-handed toolbar adaptation, toast/notice provider with queue/dedupe behavior, consent/update dialogs, image/media preview, document viewer, async loading/error/retry, no-data states, report/chart containers, and mobile feature modularization. These cross-check the mobile design-system primitives for NoticeBar, Dialog, Modal, ErrorBlock, Toast, SafeArea, TabBar, Popup, ImageUploader, and ResultPage.
- Web primitives: central API request wrapper, design-system shell, route-selected sidebar, collapsible navigation, route metadata for layout/menu/permission, process tabs for active jobs, permission-gated menus/actions, drawer/modal/detail inspection, upload and document preview, scan/review progress drawers, rich media viewers, chart/report sections, data tables, event bridge for active workflow tabs, download task entries, and long-label truncation with measured overflow tooltips. These cross-check the web design-system patterns for Sidebar, Content Card, Chat Bot, Empty, Alert, Message, Dialog, Steps, responsive widths, and card min/max height.
- Complex interaction primitives: dnd/drag selection, canvas/image/PDF preview, zoom/pan/crop, source upload, parse/process progress, manual correction, structured editing, split/merge/reorder, preview before commit, and export/download.
- Review and ops primitives: workbench/task queues, content/audit/check pages, search forms, pagination, persisted filters, multi-select, batch operation, operation-after-reload/reset, distribution/download, filters/search, segmented controls, no-data/empty states, direct row actions, and affected-scope summaries.
- Visual/runtime candidates: source paths include chart value-normalization and instance-cleanup logic; canvas/image paths include device-pixel-ratio, zoom/pan, drag, reset, and preview-state handling. Treat visible long-running export/download jobs as a design hypothesis until runtime evidence exists.
- Structured editor primitives: engine initialization, initialization-failure retry, side settings panel, validation-driven disabled save, preview/render callback, zoom/pan canvas controls, object grouping, and editable vs preview object distinction.
- Native/device task primitives: host bridge initialization, old/new bridge fallback, callback id lifecycle and cleanup, device status taxonomy, preflight configuration, wait state, success continuation, retry/reselect/report recovery, and automatic support reporting for classified failures.
- Design-system reference primitives (from refreshed source files): application navigation, modals, table header/cell/row actions, empty states, chart axes/legends/markers, metrics, progress steps, alerts/notifications, icon best practices, flowchart nodes, decision branches, hot zones, annotations, measurement labels, cursor/gesture cues, and UAT/workflow templates. Use these to scope source review, not as proof of product capability, product IA, or brand direction.

## Cross-Skill Routing

- Visual/state acceptance → stays in this skill (`product-ui-ux-design`).
- React browser implementation ownership → `web-react-dev`; Vue/Svelte/static/vendor/other browser implementation → its installed web-content owner or the fail-closed project-convention lookup in `delivery-contract.md`.
- Flutter/Android/iOS/RN implementation ownership → `app-cross-platform-dev`.
- Mini-program implementation ownership → `miniapp-product-dev`.
- Full-screen terminal/TUI implementation ownership → `terminal-cli-dev`.
- Electron/desktop/TV shell or another rendered layer without an installed owner → the fail-closed project-convention lookup in `delivery-contract.md`; use `no-installed-owner` only after that lookup completes.
- Test-layer planning → `testing-strategy`.
- Backend service implementation → the relevant backend skill (e.g. Python service, Go microservice).
- Shared handoff fields, handoff order, evidence semantics, and verdict → `delivery-contract.md`.

## Mechanism Translation

When moving a mechanism into another product or stack, preserve the problem and observable invariant, not source nouns or component shape. Re-derive the target task, state and adaptation matrices, error/recovery semantics, platform convention, and evidence layer through `delivery-contract.md`. A source implementation becomes a candidate mechanism until the target runtime proves it.

Discard the source product's nouns, role labels, and workflow copy from any extracted rule.

## Where The Specific Provenance Lives

Specific subproject paths, real branch names, package.json signatures, and dated implementation cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
