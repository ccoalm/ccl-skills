# Frontend Code Evidence Map

Use this reference when a task needs implementation evidence from frontend code. The rules below describe *how* to classify and use code evidence; specific local repository paths are kept in the private provenance archive outside this skill tree.

Users without code access can still use the distilled patterns in this file and in the platform-specific references. Do not require access to specific local paths unless the task explicitly asks to audit, update, or re-extract implementation evidence.

## Evidence Rules

- Absorb implementation mechanics only: state ownership, async handling, navigation, permissions, upload/progress, preview, review, charts, tables, tooltips, layout recovery, and build scripts.
- Do not copy source product names, business workflows, legacy information architecture, or visual taste into a generic product skill.
- Prefer newer React + design-system + typed-build subprojects over older Vue 2 / Element UI projects or server-rendered legacy folders.
- When auditing, updating, or re-extracting from source, treat package scripts and source structure as evidence only after confirming the subproject exists locally. For normal use, rely on the distilled patterns below.

## Source Strength Classification

For each frontend subproject in scope, classify the code evidence before extracting rules. The shape below is the classification frame; specific paths live in the private archive.

| Strength | Typical stack signature | Useful extraction |
| --- | --- | --- |
| **Strong** | Modern React + Ant Design (Pro Components) workbench, or React + antd-mobile H5, with typed build (TS + Vite/Umi), generated API client, and Less/CSS-module token files | State ownership, route/permission metadata, sidebar/process tabs, upload/preview/review drawers, long-task polling, dense tables, measured overflow, AI/assistant surfaces |
| **Medium** | React + design-system but smaller scope: admin/workbench, structured creator, content-center, consumer-mobile, H5 device/resource | Sidebar tabs, permission separation, structured DnD, canvas mechanics, list/detail flows, QR/device states |
| **Weak / excluded** | Legacy Vue 2 + Element UI, rich-text-only packages, render/export pipelines, deploy-only servers, third-party utility apps that happen to share a stack | Use only for legacy stack reference (print/QR/canvas behavior) or matching-stack implementation evidence; never as visual or interaction benchmark |
| **Backend (out of scope)** | Service-side code | Out of scope for this skill except for product-visible lifecycle consequences; route to the backend skill |

A subproject's strength can be confirmed from its `package.json` deps (e.g. `antd@5 + @ant-design/pro-components` indicates Pro workbench; `antd-mobile@5` indicates H5; absence of either with `vue@2` indicates legacy) plus a quick read of one entry component. Stack guesses based on directory name alone are not evidence.

## Extracted Implementation Patterns

These are the source-neutral patterns confirmed across the strong/medium subprojects:

- Build scripts: most modern web/H5 subprojects separate `build`, `dev`, `prod`, `preview`, `format`, `setup`, and sometimes `gen:api`. Non-framework packages may add independent test/build/lint gates. Preserve environment-mode and generated-API separation in new projects.
- Mobile primitives: responsive shell, route guard, bottom navigation, safe-area/keyboard behavior using viewport-aware fallbacks, WebView bridge initialization, development-only debug tooling, touch gestures, portrait/landscape review modes, left/right-handed toolbar adaptation, toast/notice provider with queue/dedupe behavior, consent/update dialogs, image/media preview, document viewer, async loading/error/retry, no-data states, report/chart containers, and mobile feature modularization. These cross-check the mobile design-system primitives for NoticeBar, Dialog, Modal, ErrorBlock, Toast, SafeArea, TabBar, Popup, ImageUploader, and ResultPage.
- Web primitives: central API request wrapper, design-system shell, route-selected sidebar, collapsible navigation, route metadata for layout/menu/permission, process tabs for active jobs, permission-gated menus/actions, drawer/modal/detail inspection, upload and document preview, scan/review progress drawers, rich media viewers, chart/report sections, data tables, event bridge for active workflow tabs, download task entries, and long-label truncation with measured overflow tooltips. These cross-check the web design-system patterns for Sidebar, Content Card, Chat Bot, Empty, Alert, Message, Dialog, Steps, responsive widths, and card min/max height.
- Complex interaction primitives: dnd/drag selection, canvas/image/PDF preview, zoom/pan/crop, source upload, parse/process progress, manual correction, structured editing, split/merge/reorder, preview before commit, and export/download.
- Review and ops primitives: workbench/task queues, content/audit/check pages, search forms, pagination, persisted filters, multi-select, batch operation, operation-after-reload/reset, distribution/download, filters/search, segmented controls, no-data/empty states, direct row actions, and affected-scope summaries.
- Visual/runtime primitives: chart components normalize values and clean up instances; canvas/image flows account for device pixel ratio, zoom/pan, drag, reset, and preview state; long-running export/download flows should be visible as jobs rather than hidden behind one toast.
- Structured editor primitives: engine initialization, initialization-failure retry, side settings panel, validation-driven disabled save, preview/render callback, zoom/pan canvas controls, object grouping, and editable vs preview object distinction.
- Native/device task primitives: host bridge initialization, old/new bridge fallback, callback id lifecycle and cleanup, device status taxonomy, preflight configuration, wait state, success continuation, retry/reselect/report recovery, and automatic support reporting for classified failures.
- Design-system reference primitives (from refreshed published-system files): application navigation, modals, table header/cell/row actions, empty states, chart axes/legends/markers, metrics, progress steps, alerts/notifications, icon best practices, flowchart nodes, decision branches, hot zones, annotations, measurement labels, cursor/gesture cues, and UAT/workflow templates. Use these as capability and review coverage, not as product IA or brand direction.

## Cross-Skill Routing

- Visual/state acceptance → stays in this skill (`product-ui-ux-design`).
- React/browser implementation ownership → `web-react-dev`.
- Flutter/Android/iOS/RN implementation ownership → `app-cross-platform-dev`.
- Mini-program implementation ownership → `miniapp-product-dev`.
- Test-layer planning → `testing-strategy`.
- Backend service implementation → the relevant backend skill (e.g. Python service, Go microservice).

## Product Translation

When mapping these implementation patterns to a new product domain:

- Mobile app implementation → community mobile shell, onboarding, profile/settings, AI creation, notification, feed/detail, and insight surfaces.
- Web shell implementation → creator center, moderation/trust workspace, AI workspace, asset/resource governance, analytics, and settings.
- Creation/editing implementation → AI draft creation, media/content import, structured post/event/content-pack setup, and review-before-publish.
- Scan/print/canvas implementation → media ingestion, document preview, QR/device flows, evidence capture, and export/share flows.

Discard the source product's nouns, role labels, and workflow copy from any extracted rule.

## Where The Specific Provenance Lives

Specific subproject paths, real branch names, package.json signatures, and dated implementation cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
