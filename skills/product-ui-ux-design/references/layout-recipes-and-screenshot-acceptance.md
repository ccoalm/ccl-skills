# Layout Recipes And Screenshot Acceptance

Use this reference when a design task risks becoming "rule-compliant but plain". It turns the generic design rules into concrete layout recipes, density targets, state templates, and screenshot acceptance checks.

This file is distilled from current Figma rules and frontend implementation evidence. Source product terms are provenance only; do not copy them into new-product UI.

## Adaptation Test Setup

Do this before drawing or coding any nontrivial page:

1. Pick the rendered family and task shape: React or other Web, mobile app/H5, mini-app host/page, ordinary CLI or full-screen terminal/TUI, Electron/desktop/TV shell, dense table/list, structured editor, scan/upload/review, analytics/tracking, or resource/library. For an unlisted client, name its installed owner or fail-closed project convention before choosing adaptation evidence.
2. Derive the primary viewport and stress viewports from the product's supported-device matrix, analytics, host constraints, or existing repository configuration. If no stronger source exists, use these only as provisional test seeds and record that evidence gap:
   - Desktop workbench: one representative desktop frame, then a wider frame and a narrow desktop/tablet width; 1440x810 is a useful seed, not a universal target.
   - Consumer web: content column and optional rail at desktop, then one tablet/narrow width and one mobile width.
   - Mobile app/H5: one representative shipped device, a narrower/shorter stress device, and a larger device; 393x852, 375x812, and 428x926 are useful seeds. If the task supports landscape or review, add a representative landscape frame such as 874x402.
   - Mini-app: use the shipped host/tool and at least one real supported device class; include host chrome, safe area, permission/capability, package/platform, and any embedded web-view constraints.
   - Ordinary CLI or terminal/TUI: cover TTY and non-TTY/plain modes as applicable, representative narrow/default/wide dimensions, color/capability fallback, long/localized output, keyboard/focus/resize/scrollback only where the contract uses them, and the actual command/help/exit/recovery path.
   - Electron/desktop/TV shell or other Web renderer: use the actual content owner plus shell owner/project convention; exercise supported window/display sizes, scaling, focus/input, host bridge, and content-shell integration rather than borrowing the generic browser matrix.
3. Assign fixed or bounded regions before spacing polish: shell/header, context/filter row, primary region, secondary panel, feedback region, and action area.
4. Decide the collapse rule: secondary panel, side rail, preview, filters, and metadata collapse before the primary content becomes unreadable. Do not just shrink everything.
5. Decide the density mode and spacing scale. Productive compact and consumer relaxed use different page padding, control height, row height, and card breathing room.
6. Map long text, no data, partial data, permission blocked, loading, error, and keyboard/safe-area states into the same geometry as the happy path.

If a design or implementation skips these decisions, it is not ready for UI review even if the component choices are correct. Numeric ranges in the recipes below are source-derived starting heuristics; they become acceptance criteria only when the current product source or a recorded decision adopts them and rendered evidence exercises the relevant stress case.

## Quality Lenses For Layout Proof

After choosing the delivery profile in `design-execution-checklist.md`, apply the relevant structure, interaction, behavior, and aesthetic lenses before coding, screenshot review, or acceptance. Translate them into layout proof:

- Aesthetic proof: visible layer model, rhythm, density, alignment, color weight, and one primary focus.
- Interaction proof: visible entry point, current task, next action, progressive disclosure, and return path.
- Behavioral proof: visible protection or recovery for repeat, mistake, wait, cancel, retry, interruption, and undo risks.
- Psychology proof: reduced uncertainty, immediate feedback, perceived control, and deliberate confirmation for high-impact actions.

If one layer is missing, the screen is incomplete even when it passes component and token checks.

## Shared Composition Pass

Before component styling, name the applicable composition roles for a nontrivial screen; mark a role non-applicable with the surface/task reason instead of forcing every product into one shell:

1. Shell: global nav, account/context, route title, and persistent feedback providers.
2. Context row: current scope, mode, filters, selected object, permission or trust state.
3. Primary region: the main content, review object, feed, editor, table, or output.
4. Control region: input, filters, toolbar, settings, or action panel.
5. Feedback region: empty/loading/error/progress/success/partial state in the same geometry as the final content.
6. Return loop: back/close, save draft, retry, undo, next item, or route-preserved selection.
7. Annotation and flow support: for complex tasks, expose the user's current step, decision point, hot zone, affected object, and measurement/status cue through concise labels, markers, progress steps, or tooltips rather than forcing users to infer the workflow from raw layout.

When these roles do not fit, choose a surface-specific structure and record why it supports the representative task. A marketing page can legitimately use a different composition; a raw component dump or unfinished placeholder cannot pass merely by resembling this list. Data-driven empty workbenches are valid when they still expose module structure and next action.

## Productive Web Workbench

Use for creator tools, moderation, analytics, AI review, asset management, and other repeated-use web surfaces.

- Page: light neutral background, 16-24px outer padding, 8-12px panel radius, one primary surface row above the fold.
- Aesthetic logic: use the background as a quiet canvas and let white/elevated work surfaces carry the task. Borders, shadows, and radius should express grouping and depth, not decoration. Repeated work areas need a stable spacing rhythm so the screen feels deliberate at dense information load.
- Interaction logic: keep context, controls, output/review, and final action visible as a connected task path. Complex flows should move into side panels, drawers, setup dialogs, or step regions while preserving the parent workbench context.
- Behavioral psychology: repeated-use users need certainty, recovery, and speed. Show pending jobs, disabled reasons, progress, retry, last-known status, and safe return paths instead of relying on transient toasts.
- Header: compact title/context/action row, usually 48-64px high. Avoid a second oversized title inside the page.
- Control bar: filters, segmented mode, search, upload/generate action, and selected scope in one compact band. Prefer 32-40px controls.
- Status strip: small facts such as scope, source, permission, job state, model/cost, data freshness, or selected count. Keep it one line when possible.
- Desktop seed: many source workspaces use 1440x810 frames with 64px navigation/header bars. Use this only when it represents the current product or as a provisional first screenshot, then check wider desktop and narrow responsive behavior.
- Workbench body: use one of these structures:
  - Library/resource workspace: left tree/source rail around 240px, top filter/search band, sticky filter state, content cards/table in the main region, preview/download/share/edit actions near the object.
  - Split review: left list/source/input 280-360px, center preview/result flexible, right settings/metadata 320-420px.
  - Editor with fixed side panel: primary editor min 900-960px, side panel 360-420px, page min width around 1280-1400px.
  - Table workspace: toolbar above, sticky header, compact rows, fixed action column, detail drawer for inspection.
  - AI workspace: input/source panel, generated output panel, review/metadata panel; output geometry exists in empty and loading states.
- Dialog/setup panels: 560-640px is a useful default for focused settings/download/import dialogs; expand only when comparison, preview, or multi-step validation needs it.
- Collapse rule: hide or dock secondary metadata first, turn right-side settings into a drawer or step panel second, and only then simplify the primary content. If the center work area would fall below about 720px for reading/review or about 900px for structured editing, switch layout rather than squeezing controls.
- Spacing rhythm: outer padding 16/20/24px by density, panel inner padding 12/16px, row/card gaps 8/12/16px. Avoid mixing 10 unrelated spacing values in one page.
- Control alignment: top filters and actions share one baseline, 32-40px height, and consistent label widths. Primary action stays on the far edge or sticky header; destructive actions move into menu/confirm flows.
- Empty/loading/error states stay inside the workbench geometry. Do not replace the whole first viewport with a large illustration unless the whole product area is empty.
- Data-driven workbenches are valid: modules may appear, disappear, reorder, or change status based on permissions, jobs, saved drafts, metrics, or configured workflows. The requirement is that the empty/loading/no-permission shape still exposes the intended module grid, next action, and future data slots instead of collapsing into an unstructured placeholder.
- Table, modal, empty, alert, progress, metric, and chart components must be selected by task role. A table needs stable row/header/action behavior; a modal needs decision and return context; an empty state needs next action; a chart needs drill-down or explanation; an alert needs scope and consequence.

In representative tasks, operators should be able to identify the current object, current state, and next relevant action without guessing or opening unrelated regions. Verify that outcome with task-based review, not an arbitrary time threshold.

## Consumer Web Recipe

Use for feed, detail, profile, community/topic, notification, and creator-facing consumer web pages.

- Keep the first viewport content-led: feed/detail/creator identity should appear immediately, not below a decorative hero.
- Use a constrained content column plus optional secondary rail. Keep paragraphs and post bodies readable; do not stretch text full width.
- For desktop, keep the main reading/action column visually dominant. Secondary rails are supporting context and should collapse, stack, or move below content before they force the primary column into cramped line lengths.
- Cards may be expressive, but repeated cards need stable rhythm: avatar/title/body/media/metadata/actions should align across the list.
- Put creation entry, follow/subscribe, reaction, reply, share, save, and moderation/report affordances close to the content they affect.
- Empty states invite a first community action: follow topics, create a post, invite people, upload media, or tune AI suggestions.

## Mobile App Recipe

Use for app/H5 consumer surfaces and focused mobile task flows.

- Mobile seed: when no stronger device matrix exists, start with a 393x852 portrait frame and a narrower/shorter stress frame. For media/review tasks that support landscape, also check a representative landscape frame such as 874x402.
- Aesthetic logic: mobile screens should have one clear focus per viewport. Use compact rhythm for repeated tasks and warmer spacing for discovery or creation, but keep tap targets reliable.
- Interaction logic: design around thumb reach, back/close clarity, bottom-sheet focus, keyboard appearance, and foreground/background recovery. Landscape modes need a new toolbar and preview arrangement, not a rotated portrait layout.
- Behavioral psychology: mobile users are interruption-prone. Preserve draft/input/progress when the app backgrounds, explain disabled actions, and keep the active input/action visible when the keyboard or safe area changes the viewport.
- Shell: safe-area aware app shell, screen NavBar for identity/back/close, durable bottom tabs only for top-level areas.
- Container: full-width by default, optional max width only for desktop preview; avoid ad hoc wrappers that fight scrolling.
- Main loop: one primary action per screen, reachable by thumb or in the active card.
- Lists/cards: compact metadata, clear action row, stable skeleton matching final card shape.
- Bottom sheets: filters, selectors, source settings, and focused confirmation. They must handle keyboard and visual viewport changes.
- Safe-area and keyboard: bottom actions, tabs, floating panels, and text inputs must remain visible with safe-area inset and keyboard open. When the keyboard appears, the active input and submit/retry action must stay reachable without manual page gymnastics.
- Touch sizing: icon-only or compact controls still need reliable tap targets and accessible labels. Use icon-first only for familiar repeated tools; otherwise pair icon with label or tooltip/sheet title.
- Orientation: if landscape is supported for media, review, or editing, toolbar density and preview geometry must be redesigned for landscape, not merely rotated.
- Empty states: illustration max around 120x100 unless onboarding needs more; title + one useful next action beats a large blank decorative panel.
- Errors: section-level retry for local failures; full-page result only when the whole screen cannot proceed.

## Dense Table/List Recipe

Use for analytics, moderation queues, asset libraries, admin settings, and review backlogs.

- Top row: search/filter/segmented mode left, primary action right, selected count/status visible.
- Management seed: when it matches the current product, use a 1440x810 working frame with a compact page header for table/list management pages; derive long-page content width from the product grid and content rather than treating a source frame as a standard.
- Filter stack: cascade selector, tabs, keyword search, status/date/source filters, and bulk action entry should be grouped before the table/list. Avoid scattering filters across unrelated cards.
- Table/list: zebra or subtle row separation is acceptable; hover should preserve row identity and may highlight the hovered column for comparison-heavy data.
- Table header/cell system: define header label, sortable/selected state, row lead action, row secondary actions, cell truncation, status badges, and responsive hidden/wrapped columns before implementation.
- Width handling: choose which columns are fixed, which truncate, which wrap, and which hide at narrow widths. Long names need measured tooltip/title behavior; numeric/status columns stay aligned.
- Row height: compact rows should stay visually stable across loading, hover, selection, error, and disabled states. Do not let badges, tags, or action menus change row height unpredictably.
- Sorting: visible sort state, compact icon, no ambiguous default order.
- Pagination: show total, page controls, page size, and quick jump only when useful; controls should align and use the same radius as other compact controls.
- Row actions: keep primary row action visible; move secondary/destructive actions into menu/popconfirm/drawer.
- Empty: show what filter/scope produced no result and offer reset/create/import where relevant.
- Detail inspection: drawer or side panel keeps the parent table/list available.
- Import/repair: show upload/import, validation, preview, confirm, export/download, and error-repair as a connected sequence. Preview the changed object list before commit.

## Creation And Structured Editor Recipe

Use for upload/import, structured creation, AI draft setup, media editing, rule/configuration, and review-before-publish.

- Phase model: configure -> import/generate -> review/edit -> validate -> publish/export.
- Preview before commit: show the produced object shape before final save/download/publish.
- Validation: put blocking issues near the affected item and summarize them in the side/status panel.
- Long tasks: progress, retry, cancel, background task entry, and terminal success/failure.
- Side settings panel: 320-500px, scrollable, grouped sections, compact labels, validation states, and disabled reasons.
- Header action: save/publish/download button stays visible; disabled state explains what blocks it.
- Editor engine state: initialization, failed initialization with retry, render-complete, validation-blocked, disabled editing, and save-in-progress are first-class screen states.
- Canvas or document preview: include zoom in/out, drag/pan, reset or fit behavior where useful, device-pixel-ratio/image quality checks, and clear distinction between preview, selectable object, and editable object.
- Validation psychology: users should know why save/publish is blocked, which object caused it, and what minimum correction unlocks progress.
- Flow and annotation support: complex creation should show the current phase, decision branch, active hot zone, affected object, measurement or quality cue, and next possible action without turning the page into a tutorial.

## Device Or Native-Capability Task Recipe

Use for printing, scanning, camera/file capture, native bridge operations, device pairing, QR flows, and other flows that depend on hardware or a host app.

- Phase model: configure -> confirm -> wait/processing -> success/continue -> error/retry/report.
- Preflight: expose missing host app, unsupported device, missing permission, unavailable service, no media/paper/resource, or insufficient balance/capacity before the user commits.
- Waiting: keep the modal/screen stable, disable unsafe duplicate actions, show that work is still ongoing, and prevent background interaction when interruption would be confusing.
- Error classification: map raw device/native codes to user-meaningful categories such as missing input, connection failure, host bridge missing, processing failure, unsupported state, or retryable network issue.
- Recovery: offer retry, reselect/reconfigure, report/support, return home, or continue with another item depending on the failure class. Do not collapse all failures into a generic error toast.
- Instrumentation: for support-traceable failures, capture device/status/action context in the workflow and make the user-visible next step clear.

## Scan, Upload, And Review Pipeline Recipe

Use for media ingestion, file parsing, AI extraction, moderation/review queues, and evidence review.

- State sequence: disconnected/not ready -> empty/no item -> upload/scan/import in progress -> preview on/off -> processing -> partial/unsupported -> ready -> large preview/detail -> completed.
- Interaction logic: split preflight/check, active processing, review/repair, and completion into visible stages. Keep the user in the same task context while moving detailed controls into drawers, toolbars, or side panels.
- Behavioral psychology: users fear losing work during long tasks. Provide a visible count or progress indicator, upload/processing speed or freshness when useful, pause/continue/cancel when supported, before-unload/offline protection, and explicit recovery from partial failure.
- Header: 64px-class factual page header with current object, progress, and next action.
- Preview: keep preview geometry stable when switching between no preview, small preview, large preview, and detail drawer.
- Progress: use inline progress ring/bar plus status text for active processing; do not hide progress behind a generic spinner.
- Review toolbar: show task type/mode, current item, previous/next, mark/confirm, issue/report, and completion progress. Toolbars may be compact icon-first controls, but every unfamiliar icon needs a discoverable label or tooltip.
- Adaptation: support one item vs multiple items, single focus vs side-by-side comparison, and portrait/landscape review where relevant.
- Unsupported input: explain what is unsupported and what the user can still upload, retry, replace, or skip.
- High-throughput evaluation screenshot set: capture at least single-item, multi-item, long-content, empty/delayed artifact, completed item, unsupported automation, and active automation-config states.
- Evaluation header acceptance: queue/progress, display-count controls, view/reference tools, and session actions should read as grouped regions in the product's compact header. The progress count must stay visible at the recorded primary desktop width and its narrow stress width.
- Evaluation canvas acceptance: selected item or sub-unit boundary, current metadata strip, retry/loading shell, and bottom/session tool state must remain visible when switching between one-item, multi-item, and long-artifact layouts.
- Automation-config acceptance: left item list keeps item hierarchy and enable switch state; middle panel shows either an enablement prerequisite or strategy/config controls; right panel keeps required context/reference/rationale fields stable; result-use mode remains visible near final save.
- Long reference/output acceptance: short content still has a readable minimum block, long content caps at a declared height and scrolls inside the panel, and the dialog or workbench does not grow beyond the viewport.

## Analytics And Tracking Recipe

Use for creator insights, topic health, community quality, retention, AI quality, moderation progress, and operational dashboards.

- Start with scope and comparison: selected object/group, time range, baseline/comparison target, and data freshness must be visible near the top.
- Aesthetic logic: analytics should feel calm and exact. Use restrained color, consistent chart rhythm, clear grouping, and strong numeric alignment; avoid decorative chart styling that makes comparison harder.
- Interaction logic: every chart needs a route to exact rows, exceptions, drill-down, or expanded view. Do not leave users with a beautiful summary and no way to inspect the underlying objects.
- Behavioral psychology: users distrust ambiguous metrics. Show freshness, missing/partial data, baseline availability, and whether a zero means zero, unsupported, stale, or still loading.
- Use a chart/table pairing: charts show trend or distribution; tables show exact objects, ranks, exceptions, or drill-down rows.
- Multi-level headers and grouped metrics are valid when they help comparison, but keep the sticky header readable and avoid nested table confusion.
- Maximize/detail states are part of the design, not an afterthought. Large charts, dense tables, and detail drill-down need a focused expanded view.
- Data quality states must be explicit: missing baseline, partial data, stale data, no result, unsupported scope, and loading should not look like normal zero values.
- For monitoring dashboards, expose progress and quality as separate dimensions; do not bury exception review inside the same visual weight as normal summary cards.
- For large report systems, capture at least four screenshot baselines: report list, report detail default module, a long table/chart module with local navigation, and an object-detail or drill-down view. If the surface has a presentation/annotation mode, capture that mode separately at its intended full-viewport size.
- Large report details need fixed context before visual polish: module menu, current scope/filter band, selected module, data freshness, export state, and parent-return path. If any of these disappear while scrolling, add a side rail, sticky header, local anchor, or restored return state instead of relying on page memory.
- Object or user detail pages inside analytics should not feel like separate products. Keep the selected object rail, detail header, comparison cards, trend/knowledge/table sections, and next/previous or search path connected to the parent report.
- Live explanation or annotation modes spawned from analytics need a separate precision-workspace recipe: full-viewport artifact, right-side item navigator, bottom fixed toolbar, mode-specific controls, zoom state, annotation undo/redo/clear, and state reset rules when the current item changes.

## Empty, Loading, Error, Success Templates

Empty:

- Local empty: icon/skeleton/checklist inside the final region, 120px-class illustration max, one title, one short reason, one next action.
- First-use empty: can be warmer, but still shows the first useful action and does not push the product structure below the fold.
- Filtered empty: name the active filter/scope and offer reset.
- Permission empty: say what is blocked and what remains possible.

Loading:

- Use skeleton matching the final layout for feed/list/card/table.
- Use progress text for import/upload/generation/long-running tasks.
- Keep the destination geometry stable; avoid replacing a dense page with a centered spinner.

Error:

- Retryable: short message + retry.
- Partial: show loaded content, mark missing/stale content, and keep available actions usable.
- Fatal: use Result/full-page only when the whole surface cannot proceed.

Success:

- Confirm completion and show the next useful action, not just a toast.
- For publish/export/share, make the resulting object or destination visible.

## Density And Component Targets

- Productive compact: 16-24px page padding, 12-16px panel inner padding, 8-12px gaps, 32-40px controls, 13-14px secondary text, restrained shadows.
- Consumer relaxed: 20-32px page rhythm, larger content cards, 15-16px body text, clearer media/avatar affordances, more breathing room around reactions and creation.
- Mobile compact: 12-16px horizontal padding, 8-12px component gaps, 44px-class tap rows/actions where possible, bottom actions aware of safe-area and keyboard. Use smaller visual density only when repeated use needs it and the tap target remains reliable.
- Radius: compact controls 6-8px; cards/panels 8-12px; mobile sheets/dialogs 12-16px. Do not use the same oversized radius everywhere.
- Color: use semantic tokens; primary color leads actions and selection. Accent colors need meaning: status, category, trust, AI, or creation.
- Typography: major screen title 16-22px in product surfaces; compact panel headings 14-16px; body and metadata must not compete with page title.

## Design-To-Code Adaptation Checklist

When implementing from a design or creating a new screen in code, verify these against the rendered surface:

- Layout regions are named in code or component structure, not hidden inside anonymous nested cards.
- CSS/layout uses bounded dimensions, grid/flex rules, sticky regions, overflow handling, and collapse rules; it does not depend on one ideal viewport.
- Visual judgment survives implementation: hierarchy, density, rhythm, material treatment, and mood match the checkpoint instead of degrading into default component-library output.
- Interaction judgment survives implementation: modal/drawer/detail return context, primary/secondary action hierarchy, progressive disclosure, and risk-matched confirmation behave as designed.
- Behavioral judgment survives implementation: pending, disabled, retry, cancel, offline/interrupted, duplicate action, and recovery states are modeled in component state, not only as best-effort toasts.
- Token use is consistent: no feature-local spacing/color/radius scale unless it is promoted or justified.
- Data-driven sections can mount/unmount/reorder without breaking the grid, gaps, sticky header, or primary action placement.
- Upload, preview, review, long-task, and generated-output areas keep stable geometry across empty, loading, partial, success, and error states.
- Screenshot or browser/device evidence covers the primary viewport plus stress viewport(s), long text, empty data, partial data, and an error or permission state.

## Screenshot Acceptance

Before calling a UI done, inspect desktop and mobile/narrow screenshots where relevant:

- First viewport: primary workflow is visible; the screen is not mostly banner, blank illustration, or unrelated dashboard content.
- Hierarchy: the intended object/action leads for the representative task; verify it through task-based review rather than an arbitrary time threshold.
- Geometry: shell, control bar, primary region, secondary panel, and feedback state align to a clear grid.
- Density: no large dead zones; no nested-card clutter; no card-in-card framing unless the inner card is a repeated item or modal content.
- States: happy, empty, loading, error, disabled/permission, long-content, and narrow-width states keep the same layout logic.
- Text: labels fit controls, long names truncate/wrap predictably, no text overlaps, no hero-scale type inside compact panels.
- Actions: primary action is obvious, destructive action is separated, disabled action has a reason.
- Trust: generated/high-impact content shows source/context/status near the output.
- Responsiveness: secondary panels collapse before primary content becomes unreadable; mobile safe area and keyboard do not cover the active input/action.

If a screenshot passes only because the data is ideal, test again with long names, no data, partial data, and an error state.
