# Product Lifecycle, Acceptance, And Iteration

Use this reference when a product feature moves beyond initial UI/UX design into implementation readiness, product launch acceptance, post-launch observation, or iterative improvement.

This file extracts reusable lifecycle patterns from Figma design coverage and implementation evidence. Treat it as a generic product release process; source-domain release terminology is provenance only.

## Source Evidence

Figma evidence:

- Desktop shell/workbench capability class: login states, global messages, empty cards, responsive widths, AI assistant open/closed states, sidebar collapse, upload/import parsing flows, step/progress/result components.
- Mobile app source: mobile interaction draft, login/update sections, temporary notice bar, Toast, Modal, upload/review flows, settings/profile, and service-migration notice.
- Mobile design system: InfiniteScroll, NoticeBar, Steps, Dialog, Empty, ErrorBlock, Loading, Modal, Progress, Result, Skeleton, Toast, SafeArea, Popup, TabBar, ImageUploader, PasscodeInput.
- Desktop design system: Layout, Menu, Steps, Form, Upload, Empty, Alert, Message, Notification, Progress, Result, Skeleton, plus `【todo】` Table/Tabs/Drawer/Modal as weak guidance only.
- External quality benchmarks: usability heuristics, accessibility, Core Web Vitals, product-experience metrics, and platform interaction guidance.

Code evidence:

- Local frontend package scripts separate build, dev, production preview, formatting, setup, and API generation where relevant. See `frontend-code-evidence-map.md`.
- Mobile app code includes version-check/update confirmation and app-bridge update paths.
- Web code includes reusable polling for long-running download tasks, timeout/failure/success callbacks, and updatable message feedback.
- Existing implementation primitives are cataloged in `ui-ux-design-development.md`.
- Finance frontends add reusable launch signals: type-check-before-build, lint/format/test/coverage, bundle analysis, request instrumentation, upload task persistence, feedback reasons, and global error boundaries.

## Lifecycle Workflow

For every runtime-visible slice, the canonical prerequisite and acceptance path is `delivery-contract.md`: Design brief → Test Phase 0 → producer/client execution → Test Phase 1/sufficiency → design verdict. The lifecycle below annotates that contract with launch and post-launch work; it is not a parallel readiness path. Every runtime-ready or launch-ready claim cites the complete immutable design/test/producer/client binding set and an allowed verdict. A pending, blocked, rejected, stale, or incomplete contract cannot become ready by passing a later checklist.

Use this lifecycle for design, client implementation, release readiness, and iteration:

1. **Intent lock**: state the target product loop, user segment, surface, and success behavior.
2. **Design coverage**: map the screen to component primitives, responsive variants, and required states.
3. **Implementation readiness**: confirm local primitives, tokens, data shape, async ownership, and feature boundaries.
4. **Pre-launch acceptance**: verify UX, visual, responsive, accessibility, failure, and instrumentation readiness.
5. **Launch guardrails**: support version visibility, staged rollout or feature flags, rollback or fallback paths, notices, permissions, and degraded states.
6. **Post-launch observation**: track completion, failure, latency, drop-off, moderation/trust friction, AI failure/retry signals, and event-schema coverage.
7. **Iteration decision**: keep, merge, simplify, expand, or retire patterns based on evidence.

Do not treat a design as ready just because the happy-path frame exists.

When a shipped feature, review, or user correction changes the design rule, update the smallest owning reference and record the correction as: observed scene, previous weak or wrong rule, corrected rule, evidence checked, and whether the change is keep, merge, discard, or route elsewhere.

## Design Acceptance

Record the following as criteria in the applicable full or lightweight Design record before coding or handoff, then let Test Phase 0 choose their oracles:

- The primary loop is visible: discover, inspect, act, confirm, return.
- Every visible action has success, failed, disabled, loading, and cancel/undo behavior where relevant.
- The canonical state taxonomy in `product-surface-patterns.md` is mapped to the surface, including empty, error, skeleton/progress, result, feedback, overlay, and long-content behavior where relevant.
- Mobile designs include safe-area, keyboard, bottom action, popup/bottom-sheet, upload/media, and one-handed reach states.
- Web designs include collapsed navigation, narrow width, secondary-panel collapse, task/progress visibility, truncation tooltip, and active filter/selection persistence.
- AI surfaces include generating, stop, retry, failed, editable draft, source/context, reviewed/unreviewed, copy/share, and escalation/report states where relevant.
- Trust or public-impact actions include consequence copy and recovery paths.
- Handoff artifacts name the core frames, responsive variants, component states, interaction notes, and unresolved questions.

## Frontend Readiness

Record these client implementation-readiness criteria inside the canonical Design/Test records; the list is not a completion decision:

- There is a clear component boundary for shell, navigation, content, action area, feedback, overlay, and terminal result.
- Existing primitives are used before custom UI: async wrapper, error block, toast/message provider, modal/dialog, upload/progress, result, skeleton, empty state, responsive container, route-driven navigation.
- Async actions expose typed states instead of implicit booleans spread through the component.
- Long-running tasks use polling, streaming, websocket, or job status intentionally, with timeout and failure UI.
- Shell-level concerns are mounted once and reused: global toast/notice, app update/consent dialogs, route guard, active task/process store, and route-driven navigation state.
- Mobile forms and bottom-sheet flows have keyboard and visual-viewport behavior checked on both resize and overlay-style browsers.
- Web shells preserve active filters, selected rows, process tabs, and overflow tooltips across collapse/expand, route changes, and narrow-width states.
- User-triggered failures are never console-only; they produce inline feedback, toast/message, alert, or result state.
- Generated API clients or typed service layers are refreshed when backend contracts change.
- Feature-local raw colors, duplicated spacing, and one-off modal/button styles are promoted to tokens or shared primitives when reused.
- Analytics events are named before launch: exposure, primary action, cancel, success, failure reason, retry, drop-off step, feedback reason, report/moderation action, and notification return.

## Product Launch Acceptance

Start these launch gates only after the exact candidate is `accepted + complete` under `delivery-contract.md`, with every required design/test/producer/client record, exercised-version link, and binding member present. These gates can block launch or add release evidence; they cannot replace Phase 1, repair a stale binding, or issue the design verdict.

- **Build gate**: project build or type/lint/format commands pass where available; generated API code is up to date.
- **Cold-start gate**: new communities have seed content, onboarding prompts, recommended topics/users, creator prompts, or first-action defaults; do not launch an empty loop.
- **Visual gate**: compare key screens against Figma or accepted screenshot references at mobile and desktop widths.
- **State gate**: manually exercise the canonical state taxonomy plus retry, disabled, cancel/undo, permission, long-content, and responsive states.
- **Interaction gate**: verify hover/focus/active/selected on web; safe-area, keyboard, scroll, swipe/back, and bottom-sheet behavior on mobile.
- **Feedback gate**: feedback strength follows the ladder in `interaction-design-patterns.md`.
- **Performance gate**: for affected infinite-list, media, streaming, AI-generation, upload, PDF/document-rendering, long-table, chart, and other long-task paths, user input should remain responsive, background work must not block the main action, and progress remains visible in runtime evidence.
- **Localization gate**: long strings, mixed languages, numeric/date formats, and translated action labels fit without breaking hierarchy or controls.
- **Trust gate**: moderation, report/block/mute, public publishing, AI source/citation, privacy/consent, and destructive flows are explicit.
- **Fallback gate**: version/update notices, service migration notices, unavailable features, permissions, stale data, and partial results have understandable UI.
- **Analytics gate**: primary action, drop-off step, error reason, retry, AI failure, report/moderation action, and notification return are instrumented when relevant.
- **Rollout gate**: risky UI/UX changes have a staged rollout, experiment, feature flag, or kill switch where the product stack supports it.
- **External quality gate**: accessibility, performance, and usability heuristics from `external-ui-ux-quality-benchmarks.md` have been checked for the target surface.

## Iteration Signals

Use product evidence to decide what to change:

- High empty-state rate: improve onboarding, defaults, recommendations, seed content, or first-action prompts.
- High retry/failure rate: improve validation, upload/media resilience, AI fallback, network messaging, and timeout copy.
- High creation abandon rate: shorten the creation flow, preserve drafts, add preview, clarify public/private consequences, or improve AI draft handoff.
- Low interaction after exposure: adjust card hierarchy, affordances, reaction/comment entry points, recommendation logic, or notification hooks.
- Low return after notification: refine notification timing, copy, destination context, and digest strategy.
- High report/mute/block rate: strengthen trust cues, content quality filters, moderation surfaces, and user controls.
- High AI regenerate/edit rate: improve prompt context, result structure, source/citation visibility, and editable draft workflow.
- Frequent visual fixes in code: promote the repeated patch into tokens, variants, or shared components.

## Iteration Review Output

When reviewing a shipped or almost-shipped feature, report:

- What evidence was checked: Figma frame/page, code path, screenshot, metrics, or QA scenario.
- Canonical `delivery-contract.md` verdict/next state plus the complete design/test/producer/client binding-set IDs; do not invent a second design-readiness status.
- Separate release/iteration disposition: proceed, conditional, or blocked, with the release-specific reason. This disposition can add a launch block but cannot override the canonical design verdict.
- Top risks by severity and user impact.
- State coverage gaps.
- Component/token drift.
- Instrumentation gaps.
- Any reusable correction to feed back into this skill, with keep/merge/discard judgment.
- Recommended next iteration: keep, merge, simplify, expand, or retire.

Keep recommendations generic to the target product. Do not include source-domain labels in product-facing copy.
