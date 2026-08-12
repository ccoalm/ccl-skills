# Platform Web Desktop Patterns

Source class: refreshed web/desktop framework Figma file (`class: A2`, surface `shell`). The specific file key and project URL live in the private provenance archive outside this skill tree.

Role: reusable web and desktop platform lens for product development. Use it for desktop tokens, component semantics, web entry/auth surfaces, workspace shells, sidebar mechanics, content cards, login/workbench patterns, AI assistant, spacing, state coverage, workflow density, responsive behavior, upload/import state machines, and component adaptation rules. Do not treat it as a product-flow source for the new domain.

This file merges the former web/desktop overview, desktop design-system, desktop component-practice, and complex-workspace references. Load it when the target surface is web, desktop, admin, analytics, AI workspace, operational workbench, or browser-rendered product UI; do not load separate desktop token/component/workspace files.

## Desktop Token And Component System

Use design-system tokens and component semantics before custom styling:

- Theme modes: Light/Dark color tokens and Default/Compact dimension/typography modes.
- Color system: preserve semantic component tokens first; raw palette families are allowed for charts, tags, badges, and data visualization only when they carry meaning.
- Token provenance: before using this visual system, name the source layer for each token class: Figma component catalog for typography/color/spacing/radius intent, app theme variables for implementation mapping, and page-level code only for local exceptions. Do not treat scattered page CSS hex values as the design system unless they match or intentionally extend the token layer.
- Visual direction: the main web shell is a calm, productive, blue-accented workbench. Neutral surfaces and dark text carry most of the UI; blue accents communicate selection, primary action, AI/help affordance, and active navigation. Soft gradients are reserved for welcome, assistant, or action-card emphasis, not for every card or operational table.
- Density: Default for consumer web readability; Compact for repeated-use operations, analytics, creator tools, moderation, finance/data, and AI workspaces.
- Control heights: small/default/large roles should stay consistent across buttons, inputs, selects, filters, and toolbar controls.
- Radius: prefer 2/4/6/8 for dense controls and cards; reserve 12/16 for higher-level panels or intentionally expressive surfaces.
- Typography: use heading tokens only for real page, modal, section, or dashboard hierarchy; avoid hero-sized type inside dense workbenches.
- Component groups: Layout, Menu, Breadcrumb, Dropdown, Steps, Splitter, Form, Input, Select, Upload, DatePicker, Transfer, TreeSelect, Card, List, Avatar, Tag, Badge, Tooltip, Popover, Statistic, Tree, Alert, Drawer, Message, Notification, Modal, Popconfirm, Progress, Result, Skeleton.

Component practice rules:

- Button: Primary for the main action, Default/Filled for secondary actions, Text/Link for low-emphasis inline actions, Danger only for destructive or externally visible consequences.
- Form/Input: Vertical for focused creation/onboarding/settings; Horizontal or Inline for dense filters, analytics, moderation, and admin-like workflows. Every control needs label, helper/error text, disabled state, required/optional marker, and long-label behavior.
- Cards/Lists: Cards group modules, tasks, suggestions, analytics snapshots, and settings; Lists handle notifications, comments, queues, search results, and activity streams. Avoid grid cards for long feed text.
- Tags/Badges: Use for semantic topics, statuses, filters, trust labels, AI-generated labels, and moderation states. Do not use colorful tags as decoration.
- Tooltip/Popover: Tooltip is for short labels, truncation, disabled reasons, and metric explanations; Popover or Drawer is better for trust, analytics, AI, or moderation detail.
- Feedback: Message for transient results, Notification for background/system events, Alert for scoped inline context, Modal/Popconfirm/Drawer for decisions and focused workflows, Result for terminal state.
- Empty, Skeleton, Progress, Result: empty states name the missing content and next action; skeletons match final density and avoid layout shift; progress covers upload, AI generation, import, publish, review, and long jobs; result pages are reserved for terminal outcomes such as submitted, access denied, removed, completed, or account action done.

Desktop token values from the extracted design-system source:

- Control heights: `controlHeightSM` Default 24 / Compact 21; `controlHeight` 32 / 28; `controlHeightLG` 40 / 36; `controlHeightXL` 44 / 40; `controlHeight2XL` 48 / 44.
- Radius: `borderRadiusXS=2`, `borderRadiusSM=4`, `borderRadius=6`, `borderRadiusLG=8`, `borderRadius2L=12`, `borderRadius3L=16`.
- Typography family: a Chinese UI sans-serif (typically PingFang SC, Noto Sans CJK SC, or an equivalent system font with full Simplified Chinese coverage). Core sizes Default / Compact: `fontSizeSM` 13 / 11, `fontSize` 14 / 12, `fontSizeLG` 16 / 14, `fontSizeXL` 17 / 15, `lineHeight` 21 / 18.
- Heading sizes Default / Compact: H5 20 / 16, H4 22 / 18, H3 24 / 20, H2 30 / 26, H1 38 / 32.
- Main-frame typography evidence: source frames use a Chinese UI sans-serif (PingFang SC / Noto Sans CJK SC / equivalent), 24/22/20/18 semibold heading steps, 17/16/15/14 body steps, and mostly 150% line height with 160%-170% reserved for longer or more expressive copy. In dense workbenches, 14-18px carries most hierarchy; 24px is for task cards or page-level emphasis, not table or toolbar labels.
- Main-frame color provenance: the source frames define semantic color roles — primary action/selection, primary-action text on light fill, light selected/filled surfaces, near-black strong text, strong text, secondary text, muted text, line, and two background tones. Exact hex values are project-specific and live in the team's design-system file and synced token output; never hard-code another team's hex literals into a new product. Keep the semantic role taxonomy, not the literal palette.
- Gradient provenance: source gradients combine cool blue, cyan, violet, and white overlay. Use them as a controlled emphasis language for assistant, welcome, or top action cards. Operational shells, lists, forms, tables, resource managers, and error states should stay neutral-plus-accent unless the new product's brand system deliberately defines a broader expressive layer.
- Use these as source token values for implementation alignment. New products may retheme values, but should preserve semantic roles, density modes, and state coverage.

Component practice values:

- Button observed dimensions: small 40x28, default 50x36, large 62x40. Preserve focus, pressed, disabled, hover, and loading states.
- Alert observed heights: compact without description 37px, with description 93px.
- Message observed height: 39px.
- Notification observed size: 384x133, with optional button actions only when immediate action is useful.
- Tag color presets observed: Pink, Blue, Cyan, BlueLight, Yellow, Green, GreenLight, Orange, Purple, Red. Use as semantic status/filter colors, not decoration.
- Skeleton variants include button, image, input, avatar, and complex layouts; skeleton shape should match the final component.

## Web Entry, Welcome, And Auth Surfaces

Use this for desktop web welcome, login, account-opening, privacy, and reset-password entry points. Keep the mechanics, not the original product domain.

- On wide desktop, pair a product-preview or value-proof region with a focused auth panel; on constrained widths, collapse or hide the preview before the auth panel becomes cramped.
- Keep the auth panel stable: around a 400px working width, fixed minimum height for mode changes, restrained border/shadow, clear brand header, one primary title, one supporting line, and no marketing-heavy hero treatment.
- Use explicit auth modes when more than one exists: password login, phone/code login, scan or third-party login if actually supported, and reset-password. Mode tabs should preserve the shared account/phone identifier when switching; unsupported modes shown in design but absent from code must be marked as future or hidden rather than shipped as dead tabs.
- Do not invent a standalone registration IA unless the source product or current requirement has one. If registration is only implied, model it as account-opening, invite, binding, waitlist, or account-not-available state with a next step and support path.
- Privacy/user-agreement links belong near the submit/consent area and must remain visible in narrow layouts.
- Legal and about information should be split by user intent. Privacy and user agreement are consent/legal links tied to login or signup; organization filing, copyright, product/version, and "about" information belong in a quiet footer or an account/about route. Do not replace required privacy links with a generic about page, and do not create an about route unless the product needs version, compliance, support, or organization information after login.
- Brand or partner customization should be a skin over the same auth task: logo, slogan, preview image, and product name may vary, but missing or failed brand data must fall back to a complete default login surface instead of blocking entry or shrinking the auth panel.
- Reset-password uses staged states: identify account, send/enter code, countdown/resend, new password, mismatch, rule violation, success, and return-to-login or auto-login fallback.
- Disabled, error, and recovery states are part of the visual design: invalid phone/account, code-send failure, resend countdown, wrong code, password clear/show, reset failure, account not open, auth expiry, and redirect failure need local, readable feedback.
- Responsive acceptance needs a desktop baseline, an around-1000px collapse point, and one narrow/mobile browser width. The preview can disappear; the auth task cannot become visually secondary or lose legal links.

Web entry visual direction provenance:

- Map auth surfaces through the same semantic token chain as the workbench: typography hierarchy, primary/action color, link color, neutral card/surface, border/line, disabled, error, and footer/legal text. Do not copy source hex values into a new product unless they are the product's token values.
- The extracted auth direction is calm and trust-centered: neutral page background, focused card, restrained shadow/border, primary blue for submit/link/active mode, muted text for helper/legal/footer, and local error color near the affected field.
- The product-preview region is proof or context, not a hero. It may show a real product state on wide desktop, but should disappear before it compresses the auth panel or hides privacy/user-agreement links.
- Login typography should keep one clear task title, one helper line, readable input labels/placeholders, and low-emphasis legal/footer copy. Hero-sized slogans, oversized illustrations, or dense marketing paragraphs weaken the auth task.
- Validate token provenance on rendered states: default, mode switch, disabled submit, field error, code countdown, reset-password, footer/legal wrapping, and collapsed preview. A single wide happy-path screenshot is not enough.

## Source Boundary

- `title`: cover/title page, not a rule source.
- `component catalog`: primary extracted web component source.
- Login/workbench/list page: extracted only for login, workbench, responsive shell, sidebar states, AI assistant shell, action cards, personal center, and password-change flows.
- Structured creation source: extracted only as a generic upload/import/editing workflow reference: stepper, parsed-empty state, manual correction, semantic tags, and drag-selection mechanics.
- Product-prototype page (in the team's working language): extracted only for generic operational state coverage. Domain-specific workflow, scoring, and legacy microcopy were discarded or merged into `product-surface-patterns.md`.

If this source conflicts with the published desktop design system (`class: A1`), prefer the design-system tokens for base color, typography, spacing, radius, and generic component semantics. If it conflicts with newer product files, prefer the newer product files for product workflow evidence. Keep reusable UI principles and discard old domain requirements.

Detailed refresh logs, source measurement notes, source revision dates, and source-to-code read history live in the private provenance archive. This shared reference keeps only the reusable boundary: use component catalog evidence for component semantics, shell/auth/workbench evidence for reusable desktop composition, structured creation evidence for upload/import/editing mechanics, and prototype evidence only for generic state coverage. Do not infer full product or full route coverage from this file.

## Code Cross-Check Boundary

The corresponding React web implementation confirms which source patterns are implementation-worthy. Use this as a scoped code cross-check, not as a product-domain source and not as a claim that every route or component was audited.

Observed implementation anchors:

- The Figma color system is bound into an Ant Design theme, including primary blue, neutral text, error, menu, table, input, select, tree, segmented, radio, checkbox, and button tokens.
- The web app initializes dynamic user/workspace context, product shape, permission tree, tenant/context identity, request interception, auth expiry handling, and API error mapping before the workbench shell renders.
- Routes carry layout, hidden-menu, permission, nested route, and standalone-page metadata; menu visibility is derived from route permissions instead of static navigation.
- The shell uses a custom layout rather than the default Pro layout: full viewport, fixed sidebar/content boundary, collapsed sidebar state, optional no-sidebar routes, and a globally available AI entry.
- Sidebar state is a model with local restoration for process tabs, download tasks, collapsed mode, and active menu selection. Process tabs can be appended, replaced, selected, deleted, and restored after reload.
- Sidebar labels and process tasks measure actual overflow before showing a tooltip, including delayed recalculation after collapse animation.
- The workbench uses permission-gated modules, skeletons, compact empty states, local data refresh, sticky sections, horizontal fallback, and explicit min-width rules instead of assuming fixed content.
- The AI assistant is both a workbench panel and a draggable/collapsible/fullscreen floating entry, with permission gating, history sessions, infinite scroll recovery, bottom-scroll affordance, loading/empty states, and generated-content caution.
- Upload/import flows model unstarted, uploading, uploaded, parsing, upload failure, parse failure, parsed success, reupload, disabled-while-running, polling, and cleanup on unmount.
- The latest code refresh re-confirmed these anchors in the theme, app/request bootstrap, layout, sidebar menu/model/process tabs, workbench, AI tool/button, upload component, and overflow text component. It also confirmed embedded/hosted shell switching, route-derived hidden-child active states, mutually constrained AI input capabilities, IME-aware send behavior, and upload polling cleanup. It did not change the source boundary or broaden coverage to every route.

Code-backed rules:

- Do not treat the design system as static CSS. Bind tokens into the component library theme and verify key components, including menus, tables, form controls, selected states, hover states, error states, and disabled states.
- A complex workspace shell must start from runtime context: user/session, current product/workspace context, permission tree, route guard, request defaults, auth expiry, and typed error mapping. A visually correct shell without these states is incomplete.
- Route metadata owns navigation. The sidebar should be derived from route/permission state, not duplicated as a static menu that can drift from real access.
- A shell that may run inside a host container needs an explicit hosted-mode contract: allowed entry paths, host/source detection, layout switching, origin-aware messages, persisted host state, and fallback to the normal web shell.
- Auxiliary floating widgets, such as AI, support chat, feedback, or plugin launchers, are part of the shell contract when they can cover the workspace. Give them bounded geometry, drag/click separation, viewport clamping, collision rules with other floating controls, and cleanup on route or host changes instead of treating them as unmanaged third-party overlays.
- Model long-running user work as durable task entries when the user may leave, reload, or switch views. Process/download/task entries need create, replace, select, close, persistence, and fallback navigation.
- Collapsed navigation still needs discoverability. Use icons, hover labels/tooltips, clear selected state, and measured overflow instead of hiding meaning behind clipped text.
- Use measured overflow for long titles, identity names, task names, and dense card labels. Show tooltip/access to full text only when content actually overflows.
- Workbench modules may render dynamically from permissions and data. Preserve the skeleton and empty geometry so modules do not jump, collapse into dead space, or hide the next action.
- Dynamic workbench modules are normal. Design the first viewport as slots with stable geometry: primary actions, pending work, recent/status/insight modules, and optional assistance may appear, disappear, or stack by permission/data, but the remaining modules must still explain what is available and what to do next.
- Secondary panels, including AI, should collapse, float, or enter fullscreen before the primary work region becomes unreadable. Record the collapse rule in the adaptation matrix.
- Assistant inputs with search, reasoning, upload, model choice, or mode toggles need visible dependency rules. When one capability disables or clears another, show the current capability state, block invalid submission, and preserve normal typing behavior including IME composition.
- Long upload/parse/import actions need an explicit state machine, not a single spinner or toast. Show what is happening, whether retry/reupload is safe, whether the current job will be interrupted, and what the next step is.
- Keep implementation evidence separate from visual taste. Code can confirm ownership, state, recovery, persistence, and runtime behavior; Figma remains the primary evidence for visual hierarchy, density, spacing, and component semantics.

## Complex Workspace Execution Pack

Use this pack when designing, implementing, testing, or reviewing a complex desktop/web workspace. It is the concrete output of the refreshed source Figma read plus corresponding React implementation cross-check.

Required composition:

- Shell: account/context area, route-derived navigation, full/collapsed sidebar, active menu/process state, content region, and optional AI/secondary panel.
- Host mode: if the same web surface can be embedded or opened by another client, define the allowed paths, incoming message contract, layout switch, persistence key, and normal-web fallback.
- First viewport: creation/primary action, pending/recent work, status or insight modules, and compact empty/loading geometry. The first viewport should not be mostly banner, blank illustration, or unrelated content.
- Task continuity: active imports, uploads, generation jobs, review tasks, or downloads are visible as durable process entries when the user may switch views, reload, or wait.
- Runtime guardrails: permission-gated modules, auth/expired-session handling, request error mapping, no-permission state, and invalid/restored local task cleanup are part of the UI contract.
- Feedback providers: inline validation, skeletons, compact empties, alerts/messages, long-task progress, measured tooltips, and stronger confirmation for interrupting or destructive actions.

Responsive acceptance:

- Baseline screenshots: 1440x810 first, then 1480-class desktop, 1280 stress width, and one wider desktop such as 1660 or 1920 when the surface has side panels or dense modules.
- Collapse order: AI or secondary panel collapses first; metadata/settings dock or drawer second; primary content should not be squeezed below readable review/edit width.
- Minimum content behavior: define per-region min widths and implementation thresholds. If the primary region cannot stay readable, stack modules or allow controlled horizontal fallback instead of shrinking controls, charts, tables, or card text into unreadability.
- Sticky behavior is conditional. If a row becomes stacked, narrow, or vertically constrained, disable sticky behavior or change its scroll owner so it does not trap content or hide the next action.
- Long-text behavior: identity, title, task, tag, and metadata fields need ellipsis/wrap rules plus full-value access only when actual overflow is measured.
- Scroll ownership: sidebar and active shell remain stable; inner content owns vertical scroll when process tasks, AI panel, sticky modules, or dense workbench sections must stay usable.

State acceptance:

- Workbench state set: first-use, returning-user, partial modules, no permission, loading, empty, long text, error, and narrow-width.
- Process state set: unstarted, active, selected, hover, blocked, retryable failure, completed, closed/deleted, restored-after-reload, and fallback-after-active-close.
- Upload/import/generation state set: not started, validating, uploading, uploaded, processing, parsed/generated success, empty result, partial result, upload failure, processing failure, reupload/reset, retry, disabled while running, and cleanup on exit.
- AI panel state set: closed, collapsed, open, fullscreen, new session, history loading, streaming, loading older content, failed response, empty conversation, generated-output caveat, bottom-scroll affordance, unavailable/no-permission, capability toggle conflict, upload validation failure, cancel/interrupted, and IME-safe keyboard send.

Review questions:

- Aesthetic proof: in the first screenshot, label the shell, sidebar, primary work, secondary panel, and transient feedback by visual weight; no two unrelated regions should compete as the primary focus.
- Interaction proof: trace one real task from entry to return, including the active task marker, detail inspection surface, modal/drawer/upload/AI return point, and next action after completion.
- Behavioral proof: test reload, collapsed navigation, repeated action, processing wait, partial data, active-task deletion, and no-permission with visible UI outcomes.
- Psychology proof: generated or parsed output remains visibly reviewable, risky/disabled actions explain consequence, and every long-running state offers wait, retry, cancel, return, or recovery where applicable.

## Judgment Layer Extraction

This source contributes more than component inventory. Use it to make web workbench screens feel understandable, controllable, and visually intentional.

Source-derived judgment deltas from this file/code pair:

- Density is a trust tool, not only a layout choice. The repeated 1440-class workbench frames, compact module/card rhythm, and implementation min-width rules show that a serious workbench earns confidence by keeping status, next action, and recovery visible above the fold instead of creating a sparse "premium" surface.
- Collapsing is a behavioral contract. Sidebar, AI panel, process entries, and sticky modules are not independent responsive tricks; they preserve the user's sense of location and task continuity when space is constrained.
- Measured overflow is an anti-misunderstanding pattern. The code's actual overflow measurement turns long labels from a visual nuisance into a behavioral risk: clipped identity, task, or item text can cause wrong navigation, wrong review, or duplicate work.
- Long-running work should become place, not just progress. Uploading, parsing, generation, downloads, and active process entries create a durable location the user can return to; a spinner or toast does not preserve confidence during interruption.
- AI assistance should be spatially subordinate but procedurally complete. The assistant can be prominent, collapsed, floating, or fullscreen, but it must not erase the primary work region; its history, caveat, loading, recovery, and return-to-bottom mechanics make it accountable rather than decorative.
- Capability conflicts are part of the interaction model. Search, reasoning, attachment, model, and mode toggles should have explicit enablement, clearing, disabled, and recovery states so users understand why an input changed before submission.
- Empty state size communicates workflow seriousness. Compact empties inside cards/work modules preserve the future work shape; large illustration-led empties are reserved for whole-page first-use moments because oversized emptiness in a workbench weakens perceived readiness.

Judgment delta matrix for this focused pass:

| Layer | Delta | Source-backed decision |
| --- | --- | --- |
| Aesthetics | new | Treat productive density as a trust signal: 1440-class workbench frames, 20/16 spacing rhythm, min/max card states, and compact empty states show that visual calm comes from controlled density, not large blank space. |
| Interaction logic | new | Treat collapse and process entries as task-continuity mechanics: sidebar 184/80 states, AI open/collapsed/fullscreen/floating states, sticky rules, drawers, tooltips, and step flows preserve entry, inspection, action, confirmation, and return. |
| Behavioral logic | new | Treat long labels, hosted entry, capability conflicts, and long jobs as mistake risks: measured overflow, restored process/download tasks, explicit host-mode switching, disabled-while-running upload, polling, reupload interruption copy, stale-entry filtering, AI input dependency clearing, and active-close fallback prevent wrong action and repeated work. |
| Psychology | new | Treat AI/generated/parsed output as provisional until reviewed: AI caveat, subordinate/collapsible assistant geometry, parsing states, compact workbench empties, permission-gated modules, retry/reupload/return paths, and visible progress preserve control and trust. |

Aesthetic logic:

- Layer hierarchy should be quiet and task-led: shell, navigation, active task, primary work modules, secondary AI/metadata, and transient feedback each need distinct visual weight.
- The 20px module rhythm and 16px internal card rhythm create a productive cadence. Keep repeated module spacing stable so dense pages feel organized instead of crowded.
- Primary color should lead actions, selection, AI affordances, and active states; neutral surfaces should carry most of the work area. Do not make every card, tag, and prompt equally colorful.
- Radius, dividers, illustration sizing, and any optional shadow/gradient treatment need a role: grouping, affordance, brand warmth, or completion feedback. In workbench surfaces, restraint is usually better than decorative emphasis.
- Compact empty/loading states should preserve the future content shape. Large illustration-led empties are only appropriate when the whole page is empty or welcoming a first-time user.

Interaction logic:

- Entry should reveal the current context and the next likely action immediately: active workspace, available permissions, pending tasks, recent work, and primary creation/import routes.
- Inspection should happen in-place when possible: sidebar process entries, drawers, cards, tooltips, and AI panel states preserve context better than forcing unrelated page jumps.
- Action flows should expose phase and return path: upload/import, edit, parse, review, publish/export, and AI generation need visible step, previous/next/exit, and saved/unsaved state.
- Confirmation strength should match consequence. Reupload during parsing, deleting/resetting active work, publishing, exporting, or changing downstream-affecting settings need stronger consequence copy than ordinary navigation.
- Return should be explicit: after modal, drawer, upload, AI generation, or process-task completion, users need to land back in the relevant workbench/task context, not a generic home state.

Behavioral logic:

- Users will switch tasks, reload, collapse navigation, wait for long processing, and return later. Persist valid active tasks/downloads and filter stale entries instead of assuming a single uninterrupted session.
- Users will misread clipped text in dense workspaces. Use measured overflow and full-value access for titles, identities, task names, labels, and card metadata.
- Users will repeat actions when feedback is ambiguous. Disable unsafe duplicate actions, show pending/processing state, and distinguish retryable failure from blocked or interrupted work.
- Users will not infer hidden mode dependencies. If choosing search disables upload or reasoning, if a host container changes layout, or if a keyboard shortcut is suppressed during IME composition, make the resulting state deliberate and reversible.
- Users will scan for counts and status before reading details. Counts, date/freshness, status, owner/source, and next action should be placed near the item they explain.
- Users will abandon complex flows if recovery is unclear. Provide reupload, retry, manual correction, previous step, exit, and resume affordances where the source flow shows long or structured work.

Psychology:

- Reduce uncertainty first: users should know where they are, what is available to them, what is currently running, and whether the system is waiting, blocked, failed, or done.
- Preserve perceived control: collapsed navigation, AI panel, sticky modules, upload parsing, and task switching must all offer a visible way to expand, close, retry, return, or recover.
- Lower cognitive load by separating primary work from secondary assistance. AI should help without visually overpowering the main task and should collapse before the primary work becomes unreadable.
- Build trust through accountability: generated content, parsed/imported output, permission-gated modules, and high-impact changes need source/status/caveat/consequence cues.
- Keep serious work calm. Delight, illustrations, and any optional motion are useful for completion or onboarding, but errors, permission denial, destructive actions, and long waits need clarity and control more than decoration.

## Web Component Catalog

Observed reusable component groups:

- Typography: Chinese heading system, including `CN/24_H1_Semibold`; use for web Chinese hierarchy and dense operational headings.
- Colors: primary and base palettes. Observed primary tokens follow a `Primary/Main_*` / `Primary/Text_*` / `Primary/Fill_*` naming pattern with semantic neutral/base color blocks. Specific brand hex literals are project-specific provenance; do not import another team's literals — keep the naming pattern.
- Spacing: different functional modules use 20px spacing; cards inside a module use 16px spacing.
- Text Input: account/input field patterns with icons and typed/default/done/error states.
- Form: number input, radio, tree, transfer, drawer, and transfer usage.
- Sidebar: identity area, first/second-level navigation, process entries, collapsed mode, hover/selected states, and AI-related navigation.
- Content Card: empty and action-oriented cards for creation shortcuts, pending work, recent items, and workbench items.
- Button: normal, hover, click, disabled, and click-disabled states.
- Empty State: small 100x100 illustrations for dialogs/cards/dropdowns; large 140x140 illustrations for full empty pages, welcome pages, and home pages.
- Line: solid dividers for first-level content separation; dashed dividers for lower-level separation.
- Header: page-header patterns and pagination-related header utilities.
- Steps: stepper/page-control and pagination examples.
- Drop-down menu: grouped options and link-style menu actions.
- Label: lightweight label/tag text patterns.
- Alert: info, success, error, loading, and closeable prompt patterns.
- Message: global notification/toast card with title, body, secondary button, and primary button.
- Dialog: modal/table-style dialog examples for metric breakdowns and dense detail inspection.
- Chat Bot / AI Chat Bot: assistant home, conversation list, generated content, attachments, model selector, user bubble, AI response, loading, disabled/hover/active states, and input box.

Implementation rules:

- Use this file to guide reusable web composition, but do not copy raw Figma node names into production code unless they already match the new product naming.
- Preserve 20px module spacing and 16px internal card spacing as the default web workbench rhythm unless a newer product file contradicts it.
- Prefer the extracted blue family for primary actions and AI assistant highlights when it fits the new brand; keep neutral text/background rules aligned with the design system.
- Bind semantic colors into the UI library theme, then test selected/hover/error/disabled states in actual menus, tables, inputs, selects, tree controls, checkboxes, radios, segmented controls, and buttons.
- Use large empty illustrations only for full-page or homepage empty states; use small illustrations inside cards, dialogs, dropdowns, and compact panels.
- Treat AI assistant as a first-class web shell component when present: header/home state, recent conversations, input box, attachments, model selector, function shortcuts, loading/error states, and disabled states should be complete.

## Login And Account

Observed reusable patterns:

- Login card width: 406px in captured frames.
- Short personalized greeting with friendly icon/illustration.
- Login modes: password login, SMS-code login, and QR-code login.
- Password login fields: account, password, forgot password, primary login button, agreement and privacy copy.
- SMS-code states: phone number, verification code, countdown, get-code action, invalid-phone error, sending state.
- QR-code state: scan prompt.
- Forgot-password flow: bound-phone verification, SMS code, next step, new password, confirm password, return to login, confirm action.
- Registration is not observed as a standalone web page in the source. Treat source evidence as registration-adjacent account availability: account not opened, invite or binding required, unsupported account, first-password setup, or contact/support next step.
- Privacy and agreement are observed as repeated legal links in every login mode; the current implementation uses external static-document URLs. About/compliance evidence on web is limited to footer-style copyright/filing information, not an in-product about page.
- Account center and password-change pages reuse the main web shell and sidebar.
- Long role, community, organization, or membership values truncate predictably and expose full text on hover.

Implementation rules:

- Keep password, SMS-code, and QR-code modes in one consistent login card system rather than separate visual treatments.
- Login validation should have explicit error, countdown, disabled, and typing/input states.
- Agreement text belongs below the primary login action and should not compete with the main controls.
- Legal links should open safely, remain reachable after responsive collapse, and have a fallback if a static policy document cannot load. If the new product has account creation, the same legal-link placement and consent semantics apply to signup, invite acceptance, and first-password setup.
- Footer/about compliance should stay visually secondary on the login surface: readable, accessible, and wrap-safe, but never competing with the auth task. If a full about page is required, define product/version/support/legal states separately instead of hiding them in the login card.
- Account-center pages should reuse the main web shell, not introduce a separate layout.
- Password-change states should mirror login/forgot-password validation conventions.

## Workbench Shell

Observed reusable patterns:

- Default landing/workbench frames at 1440x810 and expanded examples at 1480x1080, 1660x1024, 1660x1577, and 1920x1080.
- Browser/header shell shows a product URL area and a stable account context.
- Sidebar identity area supports workspace/community identity, account identity, and context switching.
- Primary navigation translates into workbench, content/activity management, resource library, insights, AI workspace, and member/community management.
- Workbench content includes immediate action cards such as create, import, configure, or start guided workflow.
- To-do cards include pending review, assignment, import, processing, or approval tasks with count, generated date, and completion action.
- Recent item cards include long title, status/action, time, creator/owner, usage count, and next-step actions.
- Insight cards include report/detail/export fields for community health, creator/content performance, campaign state, or AI workflow quality.

Implementation rules:

- Treat workbench as an operational dashboard, not a marketing homepage.
- The first row should prioritize immediate creation actions and currently pending work.
- Long item, community, segment, or role names must be ellipsized with tooltip-style access to the full value.
- Empty, minimal-content, and max-height card states are all first-class states.
- Permission or feature availability may hide modules, but the remaining layout must still explain the current task, next action, and future data slots.
- Use skeletons and partial loading at the same geometry as final content. Do not replace a compact workbench with full-page loading unless the whole shell is unavailable.
- If workbench modules become sticky during scroll, verify both horizontal and vertical layouts; disable sticky behavior when stacked/narrow layouts would trap content.
- Treat module visibility as state. Permission-hidden, no-data, partial-data, loading, and narrow-stacked variants should preserve the same workbench slots and next-action rhythm rather than leaving a blank dashboard.

## Sidebar And Process Entries

Observed reusable patterns:

- Full sidebar width: 184px in captured component frames.
- Collapsed sidebar width: 80px.
- States include default selected menu, hover other menu, clicked other menu, second-level menu, multiple second-level menus expanded, and collapsed hover.
- Scope-specific sidebars differ by product context, such as personal, team, creator, moderator, or admin modes.
- Process/task entries can appear below menu items for active workflows such as imports, reviews, publishing, analytics setup, or moderation tasks.
- Process states include unselected, selected, hover current, hover other, and close affordance.

Implementation rules:

- Sidebar must support full and collapsed modes, first-level and second-level navigation, hover/click/selected states, and process entries.
- Collapsed sidebar still needs discoverability through icon hover and tooltip-style labels.
- Process entries should be treated as first-class task continuity, not as decorative menu items. Support add, replace, select, close, restore, and fallback after deletion of the active task.
- Persist only valid process/download entries. Filter incomplete stale entries on restore so broken local state cannot corrupt navigation.
- When a primary menu item is selected, clear selected process state; when a process task is selected, clear active menu state. Users should always know whether they are in a route or an active task.
- Do not hardcode old source menu labels, but the extracted sidebar mechanics are valid.

## Responsive Shell

Observed reusable patterns:

- Width examples include 1280, 1340, 1440, 1480, 1660, and 1920 layouts.
- The page includes explicit frames for narrower-than-1480 layouts, 1480-width AI-collapsed layouts, and 1920/1340/1280 variants.
- System notification variants include 1280-compatible layouts.
- Layout annotations include min widths such as `min:344`, `min:460`, `min:680`, and notes about behavior when the middle width is below 820.

Implementation rules:

- Treat 1480 as a key desktop shell breakpoint.
- At narrower desktop widths, the AI assistant should collapse or hide before core workbench content becomes unusable.
- Keep card content min widths stable; use ellipsis and vertical scrolling before compressing operational text into unreadable layouts.
- System notifications need a 1280-compatible layout.
- Include 1920, 1480, 1340, 1280, and the product's declared minimum workbench width in screenshot or browser acceptance when the shell or dense modules change; if no minimum is declared, treat 1280 as the default minimum desktop stress width.
- Define which region scrolls. Prefer a stable shell with inner content scroll over whole-page scroll when sidebar, AI panel, or sticky workbench modules must remain usable.
- If a module has a minimum useful width, let the page introduce horizontal fallback or stack the module before shrinking text, buttons, charts, or data cards below readability.
- Match design breakpoints to code thresholds. A design may show 1480/1440/1280/1024 examples, while implementation may use module-specific stack thresholds such as a shell minimum width or a 1200px card-row switch. Record both so review can check the rendered behavior, not only the Figma frame size.

## AI Assistant In Workbench

Observed reusable patterns:

- Full assistant entry in workbench/home state with greeting, prompt suggestions, avatar, regenerate, recent conversation, attachments, model/function shortcuts, and input box.
- AI home examples include prompt suggestions for insight review, workflow operations, OCR/image extraction, AI reasoning, and quick content generation.
- Assistant can be open, closed, collapsed, docked in the workbench, floating as a shortcut, or fullscreen for focused interaction.
- Floating-button variants indicate assistant entry can also be surfaced as a draggable shortcut with title/tooltip discovery.
- Chat response examples include loading, single-line, multi-line, structured long answer, image/file attachment, user send failure, generated-content caution, copy, retry/regenerate, and bottom-scroll recovery.
- Input variants include default, hover, active, typing, photo/attachment, disabled send, upload loading, upload success, upload failure, search toggle, reasoning toggle, and visible hints when capability choices conflict.
- History/session examples include recent conversations, new conversation, delete confirmation, grouped history, pagination/loading-more, empty history, and current-session selection.
- Component-level zoom read confirmed concrete sub-states: assistant shell variants at 380px and 404px width as source evidence only; input box default, hover, active, typing, and attachment states; photo upload loading, success, and failure states; user bubble single-line, default, multi-line, photo, and send-failed variants; AI response loading, single-line, multi-line, and long structured response; function control default and disabled states. Use the specific widths as evidence for banded assistant geometry, not as values to copy into every product.

Implementation rules:

- AI assistant should be part of the shell when present, not a loosely floating afterthought. Decide whether it is docked, floating, fullscreen, route-local, or hidden by permission.
- Must include open, closed/collapsed, fullscreen, loading, attachment, shortcut, response, empty, failed, interrupted, disabled, no-permission, and history states.
- AI assistant should collapse before reducing sidebar or card content below useful widths.
- Provide history/session access, new conversation, close, fullscreen, bottom-scroll recovery, and a visible generated-content caution where generated output may be trusted too quickly.
- A draggable collapsed entry needs viewport boundary checks, collision handling with other floating controls, persisted position, and tooltip/title discoverability.
- If the product also mounts non-React or third-party floating widgets, align their placement and interaction with the same shell rules: drag threshold before movement, pointer/touch support, viewport bounds, no accidental text selection or scroll capture, and deterministic unbind when the widget disappears.
- Streaming or paginated history should preserve the user's scroll position when older content loads and should expose a return-to-bottom affordance only when useful.
- Start states should do real work: greeting, current user/context when safe, preset suggestions, refresh suggestions, and a clear empty conversation state. Do not use the start panel only as branding.
- Separate suggestion shortcuts from compose capability modifiers. Suggestion cards help the user start a task; input modifiers such as upload, search, reasoning, and model choice change how the next prompt is executed. Do not mix these into one visually identical chip set.
- Capability toggles need dependency rules. If web search disables attachments or reasoning, if uploading blocks submit, or if streaming blocks a new send, the UI must show the resulting state and how to recover. Clearing an incompatible attachment or mode should be visible and reversible where practical.
- Compose input should be bounded. Cap the visible row height, keep the send/cancel and model/capability row accessible, and let long prompts scroll inside the input instead of expanding the assistant until conversation history or primary work disappears.
- Attachment support needs validation and local recovery: allowed types, count/size/dimension limits, uploading, uploaded preview, failed upload, remove, and retry or reselect. A failed attachment should not silently disappear from the prompt.
- Streaming output needs lifecycle controls: waiting for first token, streaming, timeout, network failure, user cancel, server interrupt, completed, regenerated, copied, and retryable user-send failure.
- Rich generated content needs a bounded renderer. Markdown, math, tables, media cards, and generated structured objects should scroll/wrap safely; renderer failure should degrade locally rather than blanking the assistant.
- AI-generated structured objects should remain reviewable before commit. If the assistant can turn generated content into a saved item, upload, post, resource, or workflow artifact, show the transformation path, current upload/save state, already-saved state, and failure recovery.
- Assistant geometry must protect the primary work. Declare width bands, min width, fullscreen behavior, and collapse order. If the assistant cannot fit beside the primary region, collapse or route it to fullscreen instead of squeezing the core task.
- The assistant's visual mood should be warm but subordinate: soft background, compact controls, clear avatar/name, and calm loading are useful; oversized hero treatment or decorative gradients should not overpower the workbench.
- Treat every visible assistant subcomponent as a stateful component, not copy inside a chat box: launcher, shell, header controls, suggestion card, function button, input box, attachment chip, user bubble, AI response, structured result, history item, and session delete all need hover/focus/disabled/loading/error where they can be interacted with.
- Generated-content caution should have a stable scope: use a persistent assistant/footer note or per-response label where trust depends on the result; do not rely only on a toast that disappears before the user acts on generated output.

Judgment layers:

- Aesthetics: the assistant is a helpful secondary surface. It may use warmer gradient/brand treatment than the workbench, but its width, contrast, and motion should keep primary work visually dominant.
- Interaction logic: entry, suggestion, compose, attach, toggle capability, send, stream, cancel, inspect history, regenerate, copy, save/commit, and return-to-work are one loop.
- Behavioral logic: users will interrupt streams, scroll back, load older turns, upload invalid files, switch capabilities, delete sessions, and reload. Each branch needs visible state and recovery.
- Psychology: generated output is provisional. Caution, source/status visibility, review-before-commit, and reversible actions preserve trust without making the assistant feel blocked or unsafe by default.

## Structured Upload Workflow

Use only as a generic structured upload/import workflow reference. The reusable value is the visible stepper, parsed-empty states, manual correction, semantic tags, output configuration, and drag-selection mechanics.

Observed reusable patterns:

- Step 1: upload or import a structured file.
- Step 2: confirm parsed information.
- Step 3: configure output or publishable structure.
- Header actions include exit, previous step, next step, saved state, save, and export/download.
- The flow includes a title/context area and usage/count tags.
- Empty states distinguish true empty file from parsed-empty result.
- Recovery actions include re-upload, edit manually, reset, clear divisions, previous step, and next step.
- Structured tables include item number, content, section/group, item type, count, value/status, and batch setting.
- Labels include content, extracted metadata, analysis/summary, unmatched/cancel-match states, and colorful tag variants.
- Output configuration includes grouping/merge mode, spacing, content length, line break, field length, and display options.

Implementation rules:

- Keep upload, confirm, and configuration as an explicit step workflow; users should always know which phase they are in.
- Preserve save-state visibility near top actions.
- Manual correction affordances should be visible when parsing fails or returns no valid items.
- Keep total item count and completion/validity count visible even when they are zero.
- Treat content, extracted metadata, and analysis/summary as distinct selectable/matchable semantic regions.
- Label colors must be semantic and consistent; do not randomly assign colors per item.
- Batch type/status setting should be available at section/group level.
- Settings that affect exported or published output must be distinguished from preview-only indicators.
- Merge/group behavior should not be hidden when it materially affects review, publishing, or downstream processing.
- Upload/import implementation must model at least: unstarted, uploading, uploaded-but-processing, processing, upload failed, processing failed, processed success, reupload/reset, disabled-while-running, and cleanup on exit.
- Reupload during processing needs consequence copy because it may interrupt the current task. Retry after failure should preserve the user's understanding of what failed: transport, file validation, parsing, or downstream processing.
- Long-running parse/import work should poll, subscribe, or restore with a visible task state. A toast alone is insufficient.

## Drag Selection And Edge Snapping

Observed reusable patterns:

- Selection frame has default, active/selected, and hover states.
- Drag handle/interaction hotspot is the bottom area of the input box or selected region.
- When a dragged object approaches the canvas/container edge, the system checks whether the distance is within the snapping threshold.
- Reference snapping threshold: 5px.
- When the object is near the container edge, a reference line appears at the edge.
- If the object moves beyond the container edge, the reference line remains and a tag prompt is displayed.

Implementation rules:

- Dragging should not be triggered by tiny or ambiguous hit areas; preserve a clear drag hotspot.
- Use 5px as the reference snapping threshold unless implementation constraints require a documented adjustment.
- Snapping feedback must be visible before drop through edge line and tag prompt.
- Cross-container or overflow placement should be explicitly indicated, not silently accepted.

## Product Prototype States

Use this page only as broad state coverage. It contains exploratory frames and backups; never preserve old domain microcopy as product copy.

Reusable clusters:

- Dense list management: status filters, category/scope filters, mode/type filters, time range, search, create action, row/card hybrid layout, sticky header, detail drawer, edit, delete, end/reset, and process next actions.
- Metrics and rule settings: weighted metrics, rate groups, distribution ranges, segment comparison, thresholds, benchmark comparison, totals/averages, conversion rules, statistical rules, report parameter configuration, and hierarchy-preserving editing.
- Blank structure creation: title/context, usage count, saved state, preview, save/export, layout mode, identity/metadata fields, QR/barcode, markings, notes, merge/group behavior, display density, grid/count settings, section summaries, setup progress, and add-section dialog with live totals.
- Content completion: upload or direct entry, parsing wait state, parsed file details, re-upload confirmation, manual division, semantic labels, pending-completion markers, shared-context operations, and one-click tagging.
- Third-party source matching: upload image/file, source settings, source-cleanliness guidance, direct region selection, manual item creation, identity information, missing marks, item type setup, totals, and add/modify/delete groups.
- Edit-lock and view-only states: later workflow stages restrict editing; published downstream outputs become view-only; any change that invalidates recognition or structure requires confirmation.
- Item splitting: reset numbering, total count/value, split item, add item, delete group, per-item type controls, hover affordances, selected count, and destination/position before confirmation.

Implementation rules:

- Prefer the generalized workflow rules in `product-surface-patterns.md` when they cover the same behavior.
- Treat dense management as an operational table/card hybrid; prioritize process state and next action over decorative layout.
- Process-state copy should remain explicit; avoid generic status chips that lose workflow meaning.
- Destructive or irreversible operations such as ending, deleting, unpublishing, or resetting need confirmation with consequence copy.
- Processing progress should distinguish missing artifacts from missing records and offer separate repair/download paths.
- Preserve hierarchy when editing rules; section, group, optional, and add-on levels should stay visible.
- Show object-level totals near editing controls so operators can detect inconsistency immediately.
- Use `--` for mixed batch values; do not silently collapse mixed per-item settings.
- Rule UI must be explicit when small wording changes alter downstream behavior.

## Web Animation Baseline 2025-2026

- **View Transitions API (same-document) reached Baseline Newly available in October 2025** when Firefox 144 shipped support, joining Chrome / Edge / Safari. `document.startViewTransition(updateCallback)` + `view-transition-name` CSS property are now usable cross-browser for animating same-document state changes (route swaps in SPA, list reorder, expand-to-detail, modal open). Design implication: hero elements that should appear to morph between states (cover image → detail header, list row → expanded card, avatar → profile header) should be assigned a named `view-transition-name` in the design spec so implementation can opt in deterministically rather than reinvent per-page FLIP animations. `view-transition-name` must be globally unique among elements participating in the same transition — duplicates cause the transition to silently skip the element or animate the wrong source/destination pair. For list items, nested routes, and repeated components in an SPA with route reuse, derive the name from a stable per-record identity (e.g. `view-transition-name: post-${id}`, not the route path or DOM order); shared components used on multiple pages need either a route-scoped name or explicit unset (`view-transition-name: none`) when not participating. Cross-document view transitions (the `@view-transition` at-rule, MPA navigation) are Chrome 126+ / Edge 126+ / Safari 18.2+ — usable progressively for sites that opt in but NOT Baseline yet. All view transitions must respect `prefers-reduced-motion: reduce` by falling back to instant state swap or cross-fade only; the transition's *purpose* (state change feedback) should still be communicated, but the animated geometry should not.
