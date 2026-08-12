# Web Client Source Evidence Map

Use this reference when auditing or re-extracting web client guidance. The rules below describe *how* to classify React/Vue/Vite/Umi/Next sources; specific local repository paths and dated cross-check logs live in the private provenance archive outside this skill tree.

Users without code access can still apply the distilled patterns in this file. Do not require access to specific paths unless the task explicitly asks to audit, update, or re-extract implementation evidence.

## Source Coverage

For each web subproject in scope, classify before extracting rules. The shape below is the classification frame; specific entries live in the private archive.

| Dimension | Typical stack signature | Useful extraction | Decision |
| --- | --- | --- | --- |
| Broad web inventory | Batch manifest scan across React/Vue/Vite/Umi/Next/admin/webapp projects | Web skill should cover rendered browser apps, build scripts, API clients, component tests, browser smoke, and generated-client commands | Keep |
| Rich React web source | Umi/React apps with a major component library, charts, DnD, canvas/paper engines, markdown, upload/storage SDKs, process tasks, and route shells | Strong evidence for route/state ownership, complex workbench UI, upload/preview/review, long-task feedback, generated API clients, browser verification | Keep mechanics, discard domain nouns |
| Modern React admin source | Vite React apps with TypeScript, design-system Pro Components, Vitest, Testing Library, Playwright e2e, API generation, check scripts | Strong evidence for layered tests: typecheck/lint/build, component tests, generated API, browser e2e for critical flows | Keep |
| Vue/web sources | Vite Vue apps with Pinia, Element Plus, document/PDF/media viewers, socket/streaming, Vitest, bundle analysis, oxlint/oxfmt | Useful for web-runtime behavior, heavy document/media rendering, streaming, analytics, and performance gates; not React-specific architecture | Merge only generic browser/client rules |
| Infra operations console | React/Umi/Ant Design Pro operations console with generated API client/types, list/detail routes, ProTable, DrawerForm mutations, runtime status tags, copied service identifiers, deploy/runtime metadata display | Confirms operations-console rules for list-detail-drawer route contracts, dense runtime tables, long identifier handling, status severity tags, mutation refresh, generated-client normalization, browser stress checks | Merge into React architecture and UI quality; discard private service/domain labels |
| Weak/negative sources | Low-quality enterprise UI, generated/static bundles, old worktrees, local copies | Useful for rejection rules only: do not absorb visual style or IA when UI quality is weak | Discard as positive design guidance |

## Source Classification Method

Before extracting rules from a subproject:

1. Confirm the stack signature from `package.json` (framework + design-system + test runner + API-client generator). Stack guesses by directory name alone are not evidence.
2. Read at least one entry component to confirm whether the subproject is a workbench/Pro app, an H5 app, an admin console, a marketing site, or a legacy app.
3. Map the subproject into one of the rows above. If it does not fit, classify it as weak/negative and explain why.
4. For default-empty checked-out branches, inspect remote branches before declaring the subproject empty. The active code may live on a feat or release branch, not on `main`.

## Cross-Skill Routing

- Visual/state design judgment → `product-ui-ux-design`.
- React/browser implementation ownership → stays here.
- Flutter/Android/iOS/RN implementation → `app-cross-platform-dev`.
- Mini-program implementation → `miniapp-product-dev`.
- Test-layer planning → `testing-strategy`.
- Backend service implementation → the relevant backend skill.

## Keep / Merge / Discard

- **Keep**: inspect package scripts, route owner, state owner, API client, generated clients, and rendered browser surface before claiming completion.
- **Keep**: API-backed UI needs component states, API-client/contract failure parsing, and browser smoke for a visible path.
- **Keep**: for workbench/H5 surfaces, explicitly check startup context, route guard, permission visibility, request interception, long-running job status, upload failure/retry, text overflow, and foreground/background recovery where relevant.
- **Keep**: for complex workspace shells, implement navigation from route/permission metadata, persist only valid active task/download entries, clear route selection versus process-task selection consistently, measure overflow before tooltips, and verify secondary panel collapse before primary content is compressed.
- **Keep**: for complex workspace workbenches, encode these browser-visible contracts: startup context before shell render, token-to-theme component states, route-derived sidebar, durable process/download entries, restored-state validation, measured overflow, sticky/stacked layout fallback, AI panel collapse/fullscreen/floating behavior, upload/parse polling states, and screenshot checks at baseline plus narrow/wide desktop widths.
- **Keep**: for high-throughput evaluation workbenches, encode queue/task ownership, selected record, selected sub-unit, queue switcher density, header action grouping, task-type variants, split layout calculation, current-unit header sync, selected-card boundary state, card default/hover/selected/completed states, empty/delayed artifact shell state, persisted settings, submit modes, precision/table row states, inline numeric edit state, aligned multi-actor comparison, mode-specific batch/default/common-value configuration, incomplete-item confirmation, batch state, media retry, per-item annotation state, long-artifact fit/stitching, option-disablement rules, inline micro-action states, disabled reason tooltips, quality/timing blockers, sticky issue tags, shape-subtool menu state, icon-only/labeled/compact/expanded toolbar variants, settings/history/statistics drawers, full-screen popup containment, AI item-level enable/configuration/strategy state, AI hierarchical item-list state, AI selected-item metadata state, AI empty-config panel state, AI required-context/reference/rationale fields, AI result-use mode, bounded long reference/output panels, inline AI-reviewed tags, AI-review unsupported/rerun states, and queue-end recovery as explicit runtime state.
- **Keep**: for device capture and heavy upload flows, encode readiness, device config cache/re-check, fallback source, active batch/session id, capture/upload counters, speed, preview mode, pause/continue/finish state, stale-session exit, before-unload/offline handling, exception polling, and result-management entry as explicit runtime state.
- **Keep**: for progress/quality monitoring workbenches, encode mode entry, permission-gated tabs, dimension-owned fetches, numerator/denominator calculation, refresh/export jobs, scope-filter resets, expanded detail state, preserved deep-link filters, table resizing, empty-detail disabled reasons, and rework/reset permission as explicit runtime state.
- **Keep**: for structured assignment workbenches, encode unit tree data, row identity, batch-selection state, disabled reasons, split/merge operation state, method/strategy drawers, role-owner drawers, quota/rate validation, permission summary, import/export jobs, save/autosave/finalize state, started-work risk confirmation, owner soft-delete or historical preservation, and post-action scroll/focus as explicit runtime state.
- **Keep**: assignment validation should be a state machine, not a toast list: compute invalid units, scroll/focus the first invalid unit, show row/field-level visual state, clear the state on repair, and keep finalization summaries tied to the exact optional rules and permissions being committed.
- **Keep**: for structured creation/import workspaces, encode source selection, upload validation, process polling, autosave/final-save split, canvas/editor modes, validation blockers, structure DnD, duplicate repair, cleanup of dependent derived data, and downstream lock state as explicit state machines.
- **Keep**: for app-hosted auth/profile surfaces, encode splash handoff, consent modal, login modes, conditional account-opening or binding, verification-code mechanics, first-login password setup, account/privacy/about route clusters, logout/delete cleanup, and post-session navigation as explicit state machines.
- **Merge**: design/layout acceptance belongs in the design skill; web skill owns implementation and browser runtime proof.
- **Route**: mobile/app work to `app-cross-platform-dev`; broad test-layer planning to `testing-strategy`.
- **Discard**: source business vocabulary, old worktree manifests, visual taste from weak UI sources, and component-library naming as a substitute for UX.

Coverage label: broad manifest inventory plus representative file-level refresh, not node-by-node inventory of every web component.

## Where The Specific Provenance Lives

Specific subproject paths, real branches, package.json signatures, and dated cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
