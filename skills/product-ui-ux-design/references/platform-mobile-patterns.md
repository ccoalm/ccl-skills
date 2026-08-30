# Platform Mobile Patterns

Use this platform lens for mobile app, mobile H5, and mobile web composition: tokens, component semantics, native shell behavior, mobile interaction states, account flows, AI entry patterns, tab navigation, insight cards, profile/settings, notification patterns, and mobile craft.

Source provenance lives in `source-map.md`. Use this as a distilled mobile interaction reference and do not inherit the original source domain, role model, terminology, or workflow structure.

This file merges the former mobile overview, mobile design-system, and mobile app interaction references. Load it when the target surface is mobile or app-hosted; do not load separate mobile references for token, component, and interaction decisions.

## Mobile Token And Component System

Use mobile semantic tokens before raw values:

- Color roles: primary, success, warning, danger, text levels, background, box, border, fill, badge, and neutral/light/weak surfaces.
- Theme modes: preserve Light/Dark behavior; do not hardcode light-only mobile colors.
- Radius roles: use 4/8/12 as small/medium/large rounding defaults unless the target product defines a stronger token system.
- Mobile layout primitives: SafeArea, Space, Grid, Divider, AutoCenter.
- Navigation primitives: NavBar, TabBar, Tabs, CapsuleTabs, JumboTabs, SideBar, IndexBar.
- Display primitives: Card, List, Avatar, Image, ImageViewer, Tag, Ellipsis, FloatingPanel, InfiniteScroll, Swiper, Steps, Footer.
- Input primitives: Form, Input, TextArea, SearchBar, Picker, Selector, CheckList, Radio, Checkbox, Switch, Stepper, Slider, PasscodeInput, ImageUploader.
- Feedback primitives: Toast, Dialog, Modal/Bottom sheet, Popup, ActionSheet, NoticeBar, ProgressBar, ProgressCircle, ErrorBlock, ResultPage, Skeleton.

Mobile component state rules:

- Buttons require normal, pressed, disabled, loading, and destructive variants where relevant.
- Tabs and tab bars require selected, unselected, badge, long-label, and overflow behavior.
- Lists/cards require loading, empty, long text, media failure, selected/pressed state, and secondary actions.
- Forms/inputs require focus, filled, error, disabled, helper text, password visibility, countdown, paste/autofill, and keyboard-safe layout.
- Image/upload flows require preview, replace/remove, progress, permission denial, retry, and confirm-before-use.
- Feedback strength must match consequence: Toast for lightweight confirmation, NoticeBar for scoped persistent context, Dialog/Modal for decisions, ErrorBlock/ResultPage for section or terminal states.
- Icon-only controls need semantic naming, accessible labels, consistent 24px-style visual weight where the design system supports it, touch target coverage, selected/disabled/loading/error states, and tooltip/sheet titles for unfamiliar actions. Prefer semantic icons for create, comment/reply, like/save/share, report/block/mute, follow/join, search/filter/settings, notification, media upload, AI action, and permission/security.

Mobile token values from the extracted design-system source:

- Radius roles: `radius-s=4`, `radius-m=8`, `radius-l=12`.
- Dark mode primary/status roles: the source defines `color-primary`, `color-success`, `color-warning`, `color-danger`, plus accent roles (`color-yellow`, `color-orange`, and a low-saturation deep-blue accent). Exact hex literals are project-specific and live in the team's design-system file and synced token output; do not import another team's brand hexes into a new product.
- Dark mode text/surface roles: `color-text`, `color-text-secondary`, `color-border`, `color-background`, `color-box`, and a `badge-color` accent. Use the same naming pattern; resolve literals from the new project's design-system source.
- Treat these as source token roles, not mandatory brand colors. For a new product, retheme values only through semantic roles and preserve the component-state coverage.

## Mobile Visual Direction Provenance

Use this when turning mobile Figma or code evidence into a new product screen. The goal is to preserve the visual logic, not copy source colors or domain copy.

Provenance chain:

- Start from the product's semantic tokens: primary/action, success, warning, danger, text levels, weak text, background, card/surface, border/line, badge, radius, and elevation.
- Map design evidence into those semantic roles before writing CSS, Tailwind classes, theme variables, Flutter theme, Android resources, or iOS design tokens.
- Promote repeated local colors, radius, typography, or spacing back into the theme layer. Keep raw values only for one-off illustration, media, chart, or image-treatment exceptions.
- Verify rendered default, pressed/selected, disabled, loading, error, empty, and skeleton states against the token roles; a single happy-path screenshot does not prove visual consistency.

Source-derived mobile direction:

- App foundation surfaces should feel calm, compact, and task/account centered. Prefer pale neutral or lightly tinted backgrounds, white or weak-surface cards, restrained shadows, and primary color only for active actions, selected state, links, and progress.
- Authentication can be sparse and centered; home should be denser and scannable; profile may be warmer through avatar/context treatment but should not become an oversized hero.
- Typical mobile density from the extracted source is a 393-402px portrait frame, 16-24px horizontal page padding, 12-16px card gaps, 56-60px list rows, 48-50px primary buttons, and stable bottom-tab/safe-area geometry. Treat these as starting points and adapt to the target device and design system.
- Typography should separate task title, control label, secondary explanation, and legal/helper copy. Use roughly 22-24px for page/task titles, 16px for primary controls, 14px for secondary labels, and smaller legal/helper text only when it remains readable under text scaling.
- Use gradients, large illustrations, and expressive cards sparingly. They can emphasize a creation shortcut, AI/media entry, or empty state, but should not dominate login, home, profile, privacy, or about surfaces.
- Long names, context labels, legal text, version strings, and metric labels need truncation or wrapping rules at design time; do not rely on the implementation to discover overflow later.

## Source Scope

- Primary active mobile page: use for mobile patterns.
- Support/comparison material and title/cover pages: reference only.
- Documentation, interaction notes, local temporary components, and raw screenshot/image rectangles: use only when the task specifically targets documentation or interaction-note evidence.

## Translation Rules

- Translate login and account flows into consumer onboarding, phone verification, password recovery, agreement consent, and account-security flows.
- Translate homepage/dashboard modules into community home, feed modules, personal activity, creator tasks, AI suggestions, or notification summaries.
- Translate analytics/report pages into creator/community insight cards, content performance, topic health, engagement breakdown, or AI-assisted summaries.
- Translate grading/task-switching settings into creator tool states, moderation task queues, review workspaces, or advanced interaction settings only when relevant.
- Translate AI photo/upload patterns into media upload, AI content parsing, draft extraction, image-to-post, or AI-assisted creation flows.
- For generic/community work, keep source-domain text out of product UI copy.

## Native-Hosted Mobile Shell

Use this when a mobile screen runs inside a native app shell, WebView, or hybrid container. This is a UX contract, not just an engineering wrapper.

Observed patterns:

- The primary mobile UI source uses standard portrait device frames around 393-402px wide, compact landscape review frames, and full-screen mobile surfaces rather than desktop cards in a phone frame.
- Login/account, profile/settings, temporary notices, update prompts, AI media upload, insight/report, review, toast, and modal states are designed as app states, not only page content.
- Corresponding code injects native app information, handles safe area, keyboard, orientation, native storage, network/load failure, camera capture, update, and back behavior through the host shell.

Implementation rules:

- Treat the native shell as visible product experience: splash/launch, consent gate, first load, webview loading, offline/error retry, update prompt, permission denial, and return/back behavior must have deliberate UI.
- The web content should default to full-screen mobile layout. Add max-width device frames only for previews or documentation.
- Safe area, status bar, navigation bar, and keyboard behavior need explicit visual acceptance on iOS, Android, browser fallback, and host container where relevant.
- Orientation changes need their own UX: enter, locked, failed, return to portrait, and cleanup states. Landscape review/edit surfaces should not be a stretched portrait screen.
- Camera/media actions need native permission denial, retake/cancel, upload/generation progress, failure, retry, and confirm-before-use states.
- App update flows need non-forced and forced variants, progress or store handoff, later/update-now actions, install permission failure, and retry.
- Bridge-dependent actions should show a recoverable unavailable state when the native bridge or app info is missing instead of failing silently.

## Login And Onboarding

Observed patterns:

- Launch/splash, one-tap phone login, phone-code login, account-password login, first-login password setup, forgot password, set-new-password, and account-opening or binding states when the product supports them.
- Consent states include checked/unchecked privacy agreement and a system modal explaining user agreement and privacy policy.
- Phone-code states include keyboard-open/keyboard-closed, get-code, countdown, sent-code copy, wrong-code error, and resend.
- Password states include input, show password, invalid account/password, valid new password, invalid new password, and update-success toast.
- Account recovery confirms phone number before setting a new password.
- Splash/launch uses a brief brand frame with a deterministic handoff to consent or login; it is not a marketing page.

Implementation rules:

- For consumer community onboarding, keep phone-code or one-tap login primary and make password or third-party login visible but secondary.
- Treat registration as a state in the login flow unless the product truly needs a separate form. New-number registration, account binding, first-login password setup, and guest-to-account conversion must have explicit copy, validation, and recovery instead of being a hidden backend side effect.
- Agreement consent must block login when unchecked and explain why through a modal or inline prompt.
- Keyboard-open states are first-class mobile states; verify the primary action remains reachable.
- Password recovery must include phone confirmation, code verification, password rules, mismatch/error states, and success feedback.
- Phone and code inputs in a WebView need real device behavior checks, not only visual states. Cover paste, deletion, cursor position, old Android fallback, iOS duplicate-input quirks, clear button debounce, masked formatting, and focus/blur reformatting.
- Code verification should preserve user confidence: mask the destination identifier, auto-focus the first input, support paste/autofill, move focus forward and backward predictably, clear stale errors on edit, show resend countdown, and restore only safe state after app backgrounding or route return.
- Password setup needs two fields, show/hide affordance or an explicit show-password control, the product's current password rule text, mismatch error near the fields, and a disabled or blocked submit state that explains what is missing.
- Splash, consent, login, conditional account-opening or binding, first-login setup, and forgot/reset are one onboarding system. Verify the back paths so users never get trapped between verification and password setup.
- Treat the app entry chain as a foundation system, not a set of independent screens: launch/splash, first-run consent, login mode, registration or binding when supported, verification, first setup, reset, session restore, and first-tab handoff must share one state model.
- Consent and legal access are trust controls. Unchecked consent should block account entry; agreement and privacy links must remain reachable; disagree/close paths must be explicit; the native host should not initialize broad optional capabilities before consent and shell readiness.
- Registration should be visible even when it is implicit. If a new identifier creates or binds an account, the copy must say so and the next required setup, recovery, or guest-to-account step must be visible before the user commits.
- App entry acceptance must include keyboard-open/closed layouts, restore after backgrounding, expired temporary login state, auth failure, resend failure, wrong credential, disabled submit reason, success handoff, and deterministic return to login after session cleanup.
- Treat "register" as a product contract, not a page name. If registration happens through phone-code login, third-party login, invite acceptance, account binding, or guest conversion, surface that consequence before the verification step, then show any required first-password, profile-completion, or recovery state after success. Do not create a standalone registration form unless the product actually owns separate registration data.
- Verification design must include input mechanics as visible UX: masked destination, four-or-N equal cells, numeric keyboard, paste/autofill, wrong-code error location, resend countdown, and return-to-origin behavior. The calm psychological goal is "I know where the code went, what happens if it fails, and how to recover" rather than just "I can type digits."

## Home And Primary Navigation

Observed patterns:

- Bottom tab navigation includes three main tabs in the source pattern: home, insights/tools, and profile.
- Home combines recent summary cards, detail entry points, task cards, empty state, pull-down loading, upward loading, and context selection.
- Selection panels support selected state, long-name handling, max-height internal scrolling, and confirm action.
- Empty and no-recent-task states are distinct.
- Toast feedback appears near interaction completion.

Implementation rules:

- For community products, map bottom tabs to core loops such as feed, create/AI, notifications, and profile.
- Keep the first screen focused on active content and next action rather than a static dashboard.
- Selection panels should support long labels, selected state, internal scrolling, and explicit confirmation.
- Separate true empty feed from temporary no-task/no-update states.
- Loading should cover pull refresh, pagination, and first-load states.
- Dynamic home modules need independent loading/error/retry ownership. A failed summary card, task card, or insight card should not collapse the whole home screen when the rest of the content is usable.
- Bottom sheets that edit filters or context should keep pending state separate from committed state. Open the sheet with the current selection, preserve scroll to the selected option, and apply changes only on explicit confirmation.
- Bottom tabs are part of the app shell contract. Own active-route mapping for nested routes, safe-area bottom padding, fixed or host-relative positioning, disabled/permission states when relevant, and motion that confirms active state without shifting layout.
- Home should be module-owned instead of page-owned: summary, active work, shortcuts, update/version prompts, filters, and notices each need local loading, empty, error, retry, and stale-data behavior so one failed region does not erase the user's next action.
- A mobile home screen should behave as the first useful work/feed surface after login, not as a static landing page. Give it a compact task-and-insight stack: current context, recent summary, 2-4 scannable metrics or activity signals, direct actions, and active work cards. Keep each module recoverable independently so the user can still act when one summary, task list, or shortcut fails.
- Home filter or context selectors need a pending-versus-committed model. Open with the current selection, allow long labels and many options, keep the selected option visible, and commit only through an explicit confirmation; cancel should leave home data unchanged.

## Profile, Settings, And Account

Observed patterns:

- Profile page includes identity card, context line, AI upload entry, account settings, privacy settings, about, feedback, help, update log, app version, and legal/ICP text.
- Account settings include masked phone number, set new password, delete account, and logout.
- Privacy/legal pages include user information collection list, user privacy agreement, and privacy policy.
- Version update states include latest-version, new-version prompt, later, and update now.
- Long organization/community/context names have extreme-character examples.
- Profile lists are compact grouped rows with icon, label, optional right text, chevron, press feedback, and separators; the identity area is visually richer than settings rows but must not become an oversized hero.

Implementation rules:

- Consumer profile should expose identity, relationship/social stats, creation entry, account/security, privacy, help, feedback, and app version.
- Delete account and logout need explicit confirmation and consequence copy.
- High-consequence account actions should add friction that proves intent: read-to-end or equivalent disclosure, cool-down/countdown where appropriate, disabled primary action until acknowledged, second confirmation, and visible session/cache cleanup after success.
- Privacy settings should be a discoverable cluster, not buried legal copy: information collection list, user agreement, privacy policy, privacy preferences, and account deletion path each need a stable row or equivalent entry.
- About/version should handle four states: checking, latest, update available, and update failed. New-version prompts need release notes, later/update actions, and a platform-appropriate handoff.
- Logout is reversible session exit; account deletion is irreversible or high-consequence. Do not reuse the same visual weight, wording, or confirmation depth for both.
- Long display names, bios, affiliations, community names, or badges must truncate predictably.
- Version/update notices should be non-blocking unless the update is mandatory.
- Context switching from profile or settings needs search, selected state, keyboard-safe sheet behavior, and post-switch cleanup. Do not close a context switcher before the switch operation has completed or failed visibly.
- Profile/settings is an account-control workbench, not a miscellaneous menu. Group identity/context, account security, privacy/legal, about/version, help/feedback, creation/tool shortcuts, logout, and deletion by consequence and frequency.
- Guest, public, unbound, or limited-account modes must show what is unavailable and why. Disabled account-security actions need an explanation and a route to bind, sign in, upgrade, or exit instead of a dead row.
- Account exit must coordinate UI state and storage: confirm intent, clear web and native session caches where present, clear temporary auth state, prevent stale WebView sessions, and return deterministically to login or onboarding.
- About/version surfaces reduce uncertainty when they distinguish checking, latest, update available, update failed, forced update, non-forced update, legal footer, and platform handoff states.
- Profile is the account-control hub, not a decorative personal page. Keep identity/context visually warm but compact, then group account security, privacy/legal, about/version, support/feedback, and product shortcuts by consequence and frequency. A shortcut may be visually prominent only when it is capability-gated and gives a clear unavailable reason outside the native host or below the required app version.
- Privacy belongs in two places: entry consent before account use and a later settings cluster for review and control. The later cluster should include collection list or data-use explanation, agreement, privacy policy, preferences where relevant, and account deletion path without forcing users back through the login flow.
- About pages are operational trust surfaces. Include version state, update handoff, legal/compliance footer, support/debug access only when gated, and "latest/checking/update failed" feedback; do not treat about as a static marketing page.

## AI Upload And Creation

Observed patterns:

- AI photo/upload flow includes camera capture, retake, confirm, permission settings, previous/next item navigation, and uploaded-content preview components.
- AI entry appears from profile/home as a prominent shortcut.
- Source examples include multi-image handling and review before confirmation.
- Code-backed flow includes capture return, crop preview, upload, generated extraction, rich content rendering, category metadata selection, disabled-save state, retake, extraction failure, and final save to a chosen destination scope.
- The refreshed native-backed capture flow uses a full-screen capture surface with high-contrast chrome and three clear bottom actions: import from album, primary shutter, and torch/tool. It keeps the capture region visually dominant, reserves bottom safe-area space, and moves processing/upload into visible overlays rather than invisible waits.
- The crop/review state makes "what will be used" visible before commit: image preview, crop handles/grid, processed preview inside the crop region, retake/rotate/done actions, and loading that does not hide the user's last confirmed image.

Implementation rules:

- For community products, use this as reference for AI-assisted creation: image upload, media preview, extraction/generation progress, edit before publish, retry, and permission fallback.
- Camera/media permission denial must lead to settings guidance.
- Multi-image flows need clear current-item position, previous/next controls, retake/remove, and final confirmation.
- AI-generated drafts should remain editable before publishing.
- Native-assisted capture flows are five visible stages, not one picker event: entry/list or shortcut, native capture/import, crop or processed preview, hosted detail/configuration, and saved/detail review. Design each stage with its own loading, cancel, failure, retry, and back behavior.
- AI extraction flows should be staged visibly: capture/import, crop/preview, upload, analyze, review generated content, classify/tag, save/publish, and retake/retry. Disable final commit until required generated content and metadata are valid.
- Rich generated content needs its own rendering and fallback states. Long formulas, markup, tables, or extracted structured text must scroll or wrap safely and should not block the whole screen if one renderer fails.
- The preview must build trust. If the app shows an enhanced or processed image, the saved/uploaded artifact should match that visual intent; otherwise label the preview honestly and give the user a chance to retake or reprocess.
- Capture controls should be large, icon-led, and spatially stable. Keep primary capture centered, secondary import on one side, device tool on the other. Separate icon glyph size from hit area, and apply the current first-party platform rule to the actual hit region: Apple HIG's general rule is at least 44×44pt for buttons (60×60pt on visionOS), while Android guidance recommends at least 48×48dp for touch/focusable targets. Keep both platform-scoped; do not average them into a universal number.
- Upload/analyze waits should preserve context: keep the last image visible, overlay progress near the task, disable only unsafe controls, and provide retry/retake when the failure is recoverable.
- Crop/review screens should expose direct manipulation affordances: a dimmed outside region, visible crop boundary, corner or edge handles, optional grid, retake, rotate, and confirm. While the user is dragging, prefer raw image feedback; after release, show processed preview only when it can represent the committed artifact.
- Handoff from native capture back to hosted content should avoid route flash. Keep a calm transition cover until the destination route is mounted and ready, then remove it deterministically with a timeout fallback.
- Listing captured media should use compact, repeatable cards: date grouping, upload timestamp, thumbnail with fixed preview height, status tag, delete action, no-more state, and a fixed safe-area-aware create button. The floating create control may have visual weight, but it must not cover list recovery, delete confirmation, or no-more text.
- Configuration after capture should be a bottom sheet or equivalent commit surface with pending values separated from committed values, validation near the blocked field, all/select-many support where relevant, and a disabled or blocked confirm reason. Treat native capture success as "asset received", not as final publish/save.

## Analysis And Insight Surfaces

Observed patterns:

- Analysis sections include overview reports, single/all-category variants, score/segment distribution, ranking/level distribution, detailed tables, sorting, filtering, expanded fields, comparison selection, and toast feedback.
- Detail analysis examples include vertical analysis, merged state, image preview, annotation, selected/default controls, and multiple toast states.
- Advanced aggregate insight examples include all-category/single-category reports, comprehensive comparison, segment comparison, distribution views, threshold/line settings, context switching, permission variants, and modal confirmations.

Implementation rules:

- For C-end community, translate these into creator analytics, content performance, topic health, user engagement, retention, and AI summary surfaces.
- Keep insight pages card-based and progressively disclosed; avoid large desktop-like tables on mobile.
- Sorting/filtering must expose selected state and preserve context after returning.
- Comparison and threshold settings should be advanced tools, not primary feed interactions.
- Permission-limited analytics should explain what is unavailable and why.
- Insight lists need mobile list mechanics: filter metadata loading, filter-load error, search debounce, pull-to-refresh threshold, infinite scroll trigger, loading-more state, total/no-more handling, and retry that stays inside the failed region.
- Charts and numeric cards need overflow strategy on narrow screens. Use responsive chart containers, auto-fitting numeric text, short labels with full-value access where needed, and avoid forcing desktop tables into a phone viewport.
- If an insight/report can be entered from both the home dashboard and a bottom-tab list, both entries must converge to one report context. The home entry may show a compact latest-summary card with 2x2 metrics and direct actions; the tab entry may show searchable/filterable history. Do not let shortcut entry and list entry fork into different defaults, stale filters, or incompatible return paths.
- Home insight cards should work as a compressed decision surface: show the current scope, four or fewer primary metrics, comparison/baseline hints, and 2-3 direct next actions. Keep the card calm and dense; do not turn a utility dashboard into a marketing hero.
- Mobile insight reports should follow a usable stack: entry list -> report overview -> module drilldown -> dense detail screen. The overview owns scannable cards; the drilldown owns tables, sort, compare, and long labels.
- Keep the active scope visible after every filter change: report/version, segment, group, item category, comparison target, advanced filter, and permission scope where relevant. If the product supports an "all" scope, model it as an explicit selected state instead of a missing value.
- Treat filters as pending until the user confirms a sheet. Open the sheet with current values, scroll selected options into view, show selected counts or chips after commit, and clear stale drilldown or scroll state when scope changes.
- Dense mobile tables need fixed context: sticky header, fixed first column or action column when row identity would be lost, horizontal scroll affordance, stable row height, and a dedicated empty/error/loading region. Do not put a wide table inside a small card and hope horizontal overflow explains itself.
- Dense comparison/detail screens may require landscape. Provide an explicit portrait prompt, a visible orientation affordance, fixed identity columns, sortable metric headers, and cleanup back to the expected orientation on exit.
- Report modules should own their own loading, error, empty, stale, and retry states. Updating a threshold, comparison, or visibility setting should refresh the affected modules instead of blanking the whole report.
- Metric visibility toggles must preserve interpretability. If users can hide series, levels, or score-like metrics, require at least one meaningful metric to remain visible and explain the blocked state locally.
- Advanced setting sheets for thresholds, bands, colors, or indicators need temporary state, explicit scope copy, range validation, monotonic relation checks when levels are ordered, disabled confirm with local error, and a safe-area-aware confirm action.
- Preserve return context from detail pages: scope, sort, selected row, expanded row, scroll position, and comparison target. Restore only after layout is stable; abort restore if the user starts scrolling; clear restore when filters or route context no longer match.
- Analytics should lower uncertainty, not just display numbers. Put definitions, source/scope, timestamp, permission caveats, and benchmark meaning close to the affected chart or table when those details change interpretation.
- When an insight surface runs inside a native shell, the design must include shell-dependent states: first launch and consent gate, web content loading, offline/load failure retry, safe-area and status-bar treatment, native back behavior, orientation enter/exit/failure, bridge unavailable, and native storage/session cleanup after account exit.
- Shell overlays such as update, media capture, permission prompts, transition covers, and network-error views must not feel like foreign app layers. They should preserve the same task context and return visibly to the originating mobile page.

## Mobile Lifecycle And Dense Data Surfaces

Use this when a mobile app screen can be interrupted, restored, rotated, or used for dense data inspection.

Observed patterns:

- The mobile source includes large landscape tables, compact sort controls, settings sheets, temporary notices, and foreground/background restoration code.
- Corresponding code uses TTL-based state restore, optional sensitive-field transforms, pagehide/pageshow/focus/blur recovery, selected-item auto-centering, overflow-aware notice scrolling, and dynamic table width/height calculation.

Implementation rules:

- App flows that can be interrupted should define restore scope before design: what state is restored, when it expires, which fields are sensitive, what happens when restored context no longer matches the route, and how the user can recover.
- Dense mobile data should not be squeezed into portrait by default. Use a dedicated landscape composition, orientation guidance, fixed context columns where needed, dynamic scroll bounds, visible search/filter/sort state, and a clear return path.
- Long notices should measure overflow before animating. Provide pause behavior on touch/hover and avoid turning short text into motion.
- Horizontal selector strips should keep the active item visible through measured scroll, not by assuming the selected item starts in view.
- Repeated-use preferences should show their scope: local device state, user-level preference, context-level preference, or item-level preference. Validate restored settings against current permissions and available items before applying them.
- Threshold or visual-setting sheets should keep temporary edits separate from committed settings, explain scope, validate ranges, and keep confirmation reachable above the keyboard.

## Mobile Review And Precision Workspaces

Use this when a mobile app includes moderation, review, annotation, approval, scoring, media checking, or other repeated precision work.

Observed patterns:

- The mobile source includes portrait and landscape review frames, task switching, answer/detail drawers, image preview, selection state, and compact scoring controls.
- Corresponding code implements retryable media, zoom/pan image viewing, task-type tabs, progress counters, no-work feedback, custom numeric keypad, left/right handed control placement, unprocessed-item defaults, and persisted review settings.

Implementation rules:

- Separate the media canvas, current item metadata, precision controls, task switcher, and submit/next action. If any one area becomes unavailable, the user should still understand what can be recovered.
- Give precision work an entry surface before the canvas. Home/list cards should show compact metadata, status, progress, filtering scope, and a clear continue action so users know which work is live before entering the heavy workspace.
- Treat precision work as a family of modes, not a single screen. Single item, multiple items, multiple sub-units, review/history mode, exception/problem mode, batch mode, and statistics/settings entry each need visible context, disabled reasons, and a return path to the current item.
- Media must be retryable in place. Keep the last valid artifact visible while the next artifact loads, decode or validate the replacement before swapping, reserve stable skeleton height from prior geometry, and show manual retry inside the media region after automatic retry fails.
- Multi-artifact review needs one shared viewport contract: row-level failure/retry, all-ready detection, consistent zoom/pan behavior across the row, and a reset key when the artifact group or orientation changes.
- Zoom and pan must not fight page gestures. Auto-fit the artifact, persist item-scoped scale when useful, block page swipe only while zoomed, provide a tap fallback for touch environments where `click` is suppressed, and clear stale scale when the item or orientation changes.
- Precision controls need bounded input rules: max value, step size, half-step or decimal constraints when relevant, delete, confirm, full-value shortcut, disabled reason, and visible invalid feedback.
- Repeated-work settings such as handedness, display count, density, unprocessed-item default, input mode, artifact display mode, or media enhancement should be persisted with scope and reset/validated when the task context changes.
- Split repeated-work preferences by scope in the UI and implementation contract: global user preferences, current-workflow preferences, current-task preferences, current-sub-unit preferences, and current-artifact geometry should not overwrite each other. Users should be able to predict whether a setting affects only this item, this run, or future work.
- Task switchers need visible counts, selected state, progress, disabled/no-work feedback, active item preservation, and a compact scrollable layout. Long labels and large counts should truncate predictably without hiding the current task.
- Submission is a finality surface, not only a button. Cover duplicate-submit guard, unprocessed-item confirmation, apply-once versus remember-policy choices, minimum-duration or quality gates when relevant, locked/expired task recovery, and clear finish/no-work outcomes.
- Exception handling belongs in the workspace, not outside it. Permission loss, task locked elsewhere, task source changed, no work, expired work, duplicate submit, too-fast submit, and problem reporting should keep the user's current context visible until the next safe action is chosen.
- Portrait and landscape review are different compositions. Landscape can prioritize canvas width and side controls; portrait needs compact top/bottom sheets and keyboard-safe overlays. Orientation changes should clear measured geometry, preserve recoverable task state, and return to the prior shell orientation on exit when the native host expects it.
- Precision work still needs accessibility and microcopy craft. Touch targets must stay reachable under one-handed and handedness modes, text scaling must not hide current item/progress/action state, and empty/error/disabled/confirmation copy must name the cause, scope, consequence, and next action without exposing raw system details.
- Compact tool rails may use icons to protect density, but every icon-only or icon-dominant control needs a visible label, tooltip, or programmatic accessible name. If portrait mode hides labels, the design must still specify how assistive technology and new users learn the action.
- Aesthetic rule: precision work should feel calm and constrained. Put the artifact and current item at the visual center, use controls as low-noise rails, keep destructive or exception actions visually secondary until invoked, and make progress/status legible without competing with the work surface.
- Behavioral and psychology rule: repeated review creates fatigue and error risk. Reduce cognitive load with consistent item order, immediate local feedback, recoverable retries, explicit consequence copy for bulk/default actions, and progress cues that prove the system has not lost the user's place.

## Notification And Migration Notices

Observed patterns:

- Temporary notification bar appears on profile-like surfaces.
- Toast and modal components are used for success, errors, update prompts, permission issues, and blocked workflow states.

Implementation rules:

- Community notices should be scoped: global system notice, interaction notice, moderation notice, AI task notice, and account notice should look related but not identical.
- Temporary banners must be dismissible unless they are mandatory.
- Toasts should confirm lightweight actions; modals should be reserved for decisions with consequences.

## Mobile State Checklist From This Source

- Entry/auth: splash timeout/handoff, first-run consent modal, disagree path, unchecked agreement, password login, code login, account-opening or binding state when supported, first-login password setup, forgot/reset, code sent, countdown, resend, wrong code, wrong password, show password, keyboard open/closed, password valid/invalid, success toast, restored verification state.
- Home/feed: first load, refresh, pagination, empty, no recent activity, selected filters, pending-versus-committed filters, long labels, confirm/cancel, nested tab active state, module-level retry, update/version prompt.
- Profile/account: masked identity, long identity text, guest or limited-account variant, compact grouped rows, account-security route, logout, delete account, disclosure load failure, second confirmation, privacy/legal, information collection list, about/legal footer, latest version, checking, update available, update failure, native/web cache cleanup.
- Creation/AI: permission denied, capture, retake, multi-image, preview, previous/next, confirm, generation/edit before publish.
- AI extraction: crop preview, upload failure, analyze failure, renderer failure, metadata missing, disabled save, retake, retry, save success.
- Insights/tools: sorting, filtering, comparison selection, detail drilldown, permission-limited state, modal confirmation, toast feedback.
- Review/precision: entry card, selected item, media loading, old-media hold during swap, media retry, multi-artifact row, zoom/pan, swipe conflict, task switch, no-work, progress count, numeric input, invalid value, handedness, text scaling, touch target, disabled reason, confirmation consequence, landscape/portrait, unprocessed default, duplicate submit, locked/expired work, submit/next recovery.
- Lifecycle/dense data: restore ready, expired restore, sensitive-field restore, foreground/background save, orientation guidance, landscape table, fixed context columns, search/filter/sort, active selector auto-scroll, overflow notice pause, temporary versus committed settings.
- Account risk: disclosure loaded, disclosure load failure, read-to-end, countdown/cool-down, disabled destructive action, second confirm, action failure, session cleanup, return to login/onboarding.

## Mobile Motion Discipline

Motion must have a product purpose — comprehension, orientation, feedback, or deliberate brand/emotional expression. Operational, finance, moderation, dense-data, and destructive flows default to calmer motion (this complements, not contradicts, the expressive-defaults note in the next section). Apply across iOS and Android:

- **Budget attention-grabbing motion.** Avoid more than roughly two *attention-grabbing or decorative* animations competing at once in one view; essential status indicators (a progress spinner, a skeleton shimmer) and a single choreographed timeline are exempt. Layered competing motion reads as jank, not polish.
- **Let platform and design-system motion tokens own duration and curve; only tune micro-feedback.** Micro-feedback (tap, toggle, small in-place state change) defaults to a short band (about 150–350ms), but system navigation, sheet presentation, predictive-back/gesture, hero choreography, and design-system motion tokens (e.g. M3 Expressive) carry their own longer, tuned durations — do not clamp them to the micro band. Reserve custom playful bounce/overshoot for light surfaces; on serious, destructive, financial, or trust-sensitive flows do not add custom overshoot that makes finality feel reversible or celebratory (standard platform component motion, including system spring settling, is fine).
- **Respect the OS reduce-motion setting natively, not only via web `prefers-reduced-motion`.** iOS exposes it directly: `UIAccessibility.isReduceMotionEnabled` / SwiftUI `\.accessibilityReduceMotion`. Android has no single reduce-motion boolean — gate custom animation on `ValueAnimator.areAnimatorsEnabled()` (or the framework duration scale), treating the animation scale as a capability signal rather than a reduce-motion *intent* flag, and fall back to `Settings.Global.*_ANIMATION_SCALE` only when needed. Classify each motion as decorative / spatial-orientation / essential: reduced motion drops decorative movement and shortens or simplifies spatial/essential movement, but must still show required feedback and state changes (progress, a status flip, a gesture preview).
- **Motion must not shift layout or delay the task.** Confirm active state without reflowing surrounding content (per the bottom-tab rule above), and never hold loading/disabled/error feedback behind an entrance animation.

## Platform OS Updates 2025-2026

When the target product ships on iOS 26+ / Android 16+ / Material 3 Expressive defaults, the design baseline shifts. Treat these as platform-default changes that affect token tuning, motion budget, and gesture geometry — not as visual style copies.

- **iOS 26 Liquid Glass (Apple, WWDC 2025; iOS 26 / iPadOS 26 / macOS Tahoe 26 / watchOS 26 / tvOS 26)** introduces a translucent system material that reflects and refracts surrounding content and dynamically transforms across controls, navigation, app icons, and widgets. Apps built with standard SwiftUI / UIKit / AppKit components inherit the new design automatically when rebuilt against the Xcode 26 / iOS 26 SDK; custom-drawn UI (custom CALayers, manual gradients, hand-rolled tab bars) does NOT inherit it and must adopt explicitly. Apple ships a temporary opt-out in Xcode 26 so teams can ramp on their schedule rather than be forced to ship Liquid Glass the day they upgrade SDK. Design impact: (1) custom translucent / blur / glass material tokens MUST be tuned separately for Light, Dark, AND Increased Contrast appearances — Apple's own system colors were re-tuned across all three; (2) typography baseline became bolder and left-aligned, so if the product design uses centered or thinner type to "feel premium" on iOS, re-validate hierarchy on iOS 26; (3) chrome-on-content (tab bars, sidebars) now refract content beneath, so check that overlay surface tokens still keep on-surface text readable when chrome sits over high-contrast or saturated media. Do not adopt Apple's Liquid Glass as a cross-platform default token — it is a system material with system-tuned color/blur/refraction, and cloning it on web / Android as "default brand glass" produces a hard-to-maintain knock-off. Web / Android may use a deliberate glassmorphism treatment when the product needs it, but it must declare its own contrast budget, performance fallback (opaque mode when GPU / battery / low-end device requires), and an opaque-mode trigger that does NOT rely solely on `prefers-reduced-transparency` (the CSS media feature is real but not Baseline — Chrome desktop / Firefox stable lag — so back it up with an in-app "Reduce transparency" setting, platform-equivalent OS preference where available, or a default-opaque variant for non-supporting browsers); cite the explicit rationale in the design spec rather than treating glass as a free aesthetic upgrade.
- **Material 3 Expressive (Google, 2025)** is an opt-in expansion of Material Design 3 with research-backed motion theming tokens, more expressive shape / color / typography, and an explicit emotional-design dimension (research showed expressive variants outperformed baseline on "energetic / emotive / positive / playful / friendly" perception). When the project uses M3 Expressive defaults (Jetpack Compose with M3 expressive themes, libraries pulling expressive motion tokens — note AndroidX `MotionScheme.expressive()` is alpha at the time of writing, not a stable everywhere-default), expect default animation durations and easings to be more energetic than baseline M3. Review whether *operational* / *finance* / *moderation* / *dense-data* surfaces should override motion tokens to a calmer set (`MotionScheme.standard()`) rather than inheriting expressive defaults, because dense workbench surfaces work against the expressive tone and feel jittery under it.
- **Android Predictive Back is default-enforced for apps targeting API 36 (Android 16, 2025)**. Design implication: the back gesture is no longer a single instant action but a *preview-then-commit* gesture — during the swipe the inner area scales down and the destination peeks behind; on commit-threshold crossing the contents fade-through to the destination (Android recommends `STANDARD_DECELERATE` or `PathInterpolator(0f, 0f, 0f, 1f)` for the progress easing). The system handles the previous-destination snapshot automatically for stock navigation; the design only needs to define preview behavior for custom-managed states: modals, bottom sheets, full-screen overlays, in-screen multi-step wizards, and any flow that owns its own back stack. Avoid placing draggable controls or custom horizontal-edge gestures inside the system gesture inset; they fight the OS back gesture and feel broken. For multi-step in-screen flows (form wizards, multi-pane), the design owns the *semantic back contract* (back pops inner step, not the whole screen) — *implementation* should integrate through the owning navigation stack's predictive-back support (Jetpack Navigation predictive-back APIs, `react-native-screens` predictive-back, Flutter `PopScope` / `NavigatorPopHandler`, native Fragment back-stack handlers) rather than wiring an ad-hoc `OnBackPressedCallback` at the screen level. Compose's lower-level `PredictiveBackHandler` is appropriate when the Compose screen owns its own back stack (no navigation library on top); when a navigation library is present, prefer the library's predictive-back hook so the system snapshot and inner-step pop stay in sync. Ad-hoc handlers on top of a navigation library double-pop, desync the system snapshot animation, or bypass the library's intended back stack and the regression is hard to reproduce because the OS-level animation still looks right.
