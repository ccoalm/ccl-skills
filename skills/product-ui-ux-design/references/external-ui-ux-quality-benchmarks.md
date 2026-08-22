# External UI/UX Quality Benchmarks

Use this reference when internal Figma/code evidence is not enough to judge UI/UX quality, launch readiness, accessibility, performance, or iteration metrics.

These are external quality benchmarks, not visual style sources. Do not copy another product's brand, layout, or component appearance.

## Source Anchors

- Nielsen Norman Group: usability heuristics such as system status visibility, user control, consistency, error prevention, recognition over recall, and recovery.
- W3C WCAG 2.2: accessibility criteria for keyboard, focus, contrast, labels, target size, error identification, and consistent navigation.
- web.dev Core Web Vitals: Largest Contentful Paint, Cumulative Layout Shift, Interaction to Next Paint, and field/lab measurement.
- Google HEART framework: product-experience metrics across happiness, engagement, adoption, retention, and task success.
- Apple Human Interface Guidelines (developer.apple.com/design/human-interface-guidelines) and Material Design 3 (m3.material.io): first-party platform specifications for feedback, loading, interaction states, accessibility, and platform conventions — distilled into the Platform Convention Walkthrough section below. Each criterion there is labeled (HIG) or (Material); a single-source criterion is that platform's convention, not a cross-platform standard.
- Other design-system guidance such as Atlassian Design System: secondary confirmation for touch targets, empty/error states, progressive disclosure, feedback, and content clarity.

## Heuristic Review Layer

For every important screen, check:

- **Status visibility**: users can see whether the product is loading, generating, saving, uploading, reviewing, failed, complete, or stale.
- **User control**: users can cancel, undo, retry, close, go back, clear, edit, regenerate, or recover when the action has consequence.
- **Consistency**: repeated surfaces use the same action hierarchy, navigation, selected states, empty states, and feedback strength.
- **Error prevention**: destructive, public, irreversible, expensive, or trust-sensitive actions require clear consequence copy and confirmation.
- **Recognition over recall**: current object, active mode, applied filters, selected source/context, and next action stay visible.
- **Recovery**: every recoverable error gives a path forward; unrecoverable errors explain what still works.

## Accessibility Baseline

Before launch or review, verify:

- Every interactive element has an accessible name or visible label.
- Keyboard/focus behavior works on web for controls, dialogs, menus, popovers, tabs, and drawers.
- Mobile tap targets are large enough for common platform expectations and not crowded near screen edges.
- Text and essential icon states have sufficient contrast in normal, disabled, selected, hover, focus, error, and loading states.
- Error messages identify the field or action and explain the correction.
- Motion, streaming, progress, and loading indicators do not block comprehension or task completion.
- Layout works with longer localized strings, larger text settings, and long generated content.
- **WCAG 2.2 (W3C Recommendation 5 October 2023) added 9 new success criteria; the 6 most product UI surfaces will hit are**: pointer-target ≥24×24 CSS px (AA, SC 2.5.8 — five exceptions per W3C: Spacing where a 24px circle centered on each undersized target does not intersect siblings, Equivalent control elsewhere on the page, Inline-in-text targets, User-agent default controls, Essential when the *presentation* of the target is essential to the information being conveyed and cannot be programmatically determined — narrow scope, e.g. map pins on geographic-density maps or fine-grained selection in a data-viz cluster; this exception is NOT a blanket pass for dense data-table row actions, inline icon buttons in toolbars, or close buttons on cards, which still need 24px geometry or the Spacing/Equivalent exception); focus ring not obscured by sticky bars / cookie banners (AA, SC 2.4.11 Focus Not Obscured Minimum); single-pointer alternative for any *authored* dragging interaction (AA, SC 2.5.7 Dragging Movements — drag-to-reorder, drag-to-resize, draggable map markers, custom-canvas pan; does NOT apply to native browser scroll, OS-level pinch-to-zoom, or assistive-tech gestures, and multipoint gestures like pinch fall under SC 2.5.1 Pointer Gestures, not 2.5.7); accessible authentication without a cognitive-function test like solving puzzles or remembering generated codes (AA, SC 3.3.8 — supporting `autocomplete="username"` and `autocomplete="current-password"` plus allowing paste counts; SMS OTP, email magic link, OAuth, passkeys all satisfy; image-CAPTCHA and "type the code we just showed you" do not); consistent help placement across pages (A, SC 3.2.6); redundant entry — re-using previously entered data unless re-entry is essential (A, SC 3.3.7). The remaining 3 SC (2.4.12 Focus Not Obscured Enhanced AAA, 2.4.13 Focus Appearance AAA, 3.3.9 Accessible Authentication Enhanced AAA) are AAA-only and rarely a launch gate. Treat WCAG 2.2 (not 2.1) as the current acceptance line; 2.1-only audit checklists silently miss the above.
- **Reduced-motion / color-scheme / contrast / transparency design intent must be declared, not auto-derived from `@media` query alone**. For each non-decorative animation, name whether it is *essential* (progress indicator, drag preview, view transition that conveys a state change) or *decorative* (parallax, autoplay carousel, hover bounce); `prefers-reduced-motion: reduce` should remove or replace decorative motion by default and may shorten essential motion but cannot omit feedback. An explicit in-product opt-in (e.g. user setting "Show celebration animation even when system asks for reduced motion") MAY override the default for brand-splash / completion-celebration moments when policy permits, but the override must be opt-in not opt-out and the default behavior must respect the system preference. `prefers-color-scheme` requires the design system to ship Light + Dark token pairs (no missing pair = no dark-mode claim). `prefers-contrast: more` and `prefers-reduced-transparency` are useful supplements where browser support permits but are NOT Baseline yet — do not gate accessibility compliance on them; route them through a separate "increased contrast" theme variant when product needs require it.
- **APCA (Accessible Perceptual Contrast Algorithm) is the WCAG 3 / Silver candidate contrast method, not a WCAG 2.2 replacement**. WCAG 2.2 SC 1.4.3 / 1.4.11 (4.5:1 body / 3:1 large text + UI components) remains the legal/audit baseline. APCA can be used as a *supplementary* perceptual check (per APCA Bronze Simple Mode, Lc 75 minimum / Lc 90 preferred for body text) when WCAG 2.x mathematical contrast passes but the result looks washed-out, or when designing dark mode where WCAG 2.x ratios systematically over-permit low-readability combinations. Decision matrix: WCAG 2.x fail blocks accessibility/legal compliance claims regardless of APCA result; WCAG 2.x pass + APCA fail is NOT a WCAG failure but should be treated as a readability / product-quality defect — either adjust the color tokens to also pass APCA Bronze, or document the acceptance with a rationale (brand constraint, dark-mode literal preserved). Do not ship a design that passes only APCA but fails WCAG 2.2.

## Platform Convention Walkthrough (HIG / Material)

Use this section when reviewing or accepting a mobile-platform surface (iOS/iPadOS or Android/Material-based, including Flutter/React Native apps that adopt a platform design language). Each criterion is a pass/fail walkthrough check distilled from the first-party spec named in its label; verify against the rendered surface, not the design file alone. These complement — never replace — the WCAG 2.2 acceptance line above: where a platform minimum is stricter than WCAG (e.g. target size), the platform minimum is the walkthrough bar for that platform. Criteria mirror each source's own normative strength: where the source states a recommendation ("ideally", "consider", "in general", "in most cases"), a recorded, justified exception passes as an exception — only a silent shortfall fails; where the source states a requirement, the failure is unconditional.

### State completeness against the platform spec

- **Interaction-state matrix is complete for the component class and input modalities (Material).** Every interactive component accounts for each state its Material component class inherits — enabled, plus disabled/hover/focused/pressed/dragged only where the class takes them (action/selection/input components inherit most; app bars, dialogs, menus, navigation components inherit few) — across the input modalities the surface ships on (hover needs a pointer; focused needs a focus-capable input such as keyboard or voice). States the class does not inherit are marked inapplicable, never styled in. Fail: an action component on a keyboard-capable surface styles only enabled and pressed.
- **Disabled semantics are real, not painted (Material).** A disabled component cannot be focused, dragged, or pressed, and does not change state when tapped or hovered — unrelated explanatory feedback (a tooltip saying why it is disabled) is not prohibited. Components whose class does not take a disabled state in Material — app bars, badges, dialogs, FABs, menus, navigation bar/drawer/rail, sheets, tabs, tooltips — never render a "disabled" look: when a FAB's action is unavailable, remove the FAB rather than disabling it. Fail: a grayed-out FAB or tab sits on screen, or a "disabled" card still accepts a drag.
- **Each state change is signaled by more than one visual cue (Material).** Material's baseline is two visual indicators per state so state remains perceivable under color-vision or contrast loss; opacity-only or color-only state styling fails.
- **Transient input states are singletons (Material).** At most one hover, one focus, one pressed, and one dragged state visible at a time in a layout; persistent states (selected, activated) may combine with them on the same element (e.g. a selected chip showing hover).
- **Feedback reaches people through more than one channel (HIG).** Significant feedback pairs color with text/icon, and sound with haptic where sound is used, so it survives a silenced device, a glance away, or a screen reader. Fail: success/failure conveyed by hue change alone or by sound alone.
- **Interruption level matches significance (HIG).** Passive status renders in-context near the item it describes (badge, inline line); modal alerts are reserved for critical, ideally actionable information. Fail: routine status delivered as a modal, or a data-loss warning delivered as a passive toast.
- **Data-loss warnings fire on the unexpected-and-irreversible boundary, both directions (HIG).** Warn before an action whose data loss is unexpected and irreversible; do NOT interpose confirmation when loss is the expected result of the user's own action (e.g. moving a file to trash). Fail in either direction: silent irreversible loss, or confirmation nagging on expected outcomes.
- **Completion feedback is reserved for significant outcomes; failure feedback is never omitted (HIG).** People expect success, so confirm only payment-grade/significant completions — but every command that cannot be carried out must say so and say why, with the next step. Fail: a no-op button press with no explanation.
- **Content loading shows something immediately and frees the user (HIG).** HIG scopes this to content/asset loading: placeholder/skeleton content appears at once instead of a blank wait, loading continues in the background so unrelated safe actions stay available, a determinate indicator is used when duration is known and indeterminate only when it is not, and an unavoidably long load gets meaningful interim content. This does not apply to in-flight mutations (payment, deletion, submission): while one is pending, its duplicate or conflicting mutation controls are blocked per the high-risk resilience states in `SKILL.md`, not left available.

### Accessibility against the platform spec

- **Text scales to 200% without breaking the layout (HIG, stated as "ideally").** Support the platform text-size setting (Dynamic Type on Apple platforms) up to 200% enlargement — HIG's recommended target, so a smaller ceiling passes only as a recorded exception; the walkthrough re-renders key screens at enlarged sizes and checks truncation, overlap, and control reachability. Adoption mechanics (Dynamic Type APIs, per-platform text-scaling behavior) belong to the stack implementation owner, not this walkthrough.
- **iOS hit regions measure at least 44×44pt (HIG, stated as "a general rule").** Every control's hit region is at least 44×44pt (60×60pt on visionOS), and the padded hit area is what must measure up, not the visual glyph; a smaller region passes only as a recorded exception. The ~12pt padding around bezeled elements and ~24pt around bezel-less ones is HIG's "generally works well" guidance, checked the same way. Stricter than WCAG 2.2's 24px floor — the platform benchmark is the walkthrough bar.
- **Android touch targets measure at least 48×48dp with 8dp spacing (Material, stated as "consider" / "in most cases").** Touch targets at least 48×48dp with at least 8dp between targets, pointer targets at least 44×44dp, the padded target extending beyond the visual bounds; a shortfall passes only as a recorded exception. Stricter than WCAG 2.2's 24px floor — the platform benchmark is the walkthrough bar.
- **Contrast meets the W3C-derived platform bar (Material, citing W3C).** Small text at least 4.5:1 against background; large text (14pt bold / 18pt regular and up) and meaningful graphics at least 3:1. Clustered non-text containers (e.g. a button group) need 3:1 container-vs-background. The standalone-prominence exemption (a FAB) applies only to that container-vs-background ratio — the element's own text, icons, focus indicators, and meaningful graphics still need their 3:1/4.5:1 bars; disabled states are the only class exempt from contrast requirements.
- **Reading and focus order follows content hierarchy (Material).** Screen-reader order follows the top-down source/DOM structure, headings do not skip levels, one H1 per web page, repeated landmarks get unique labels. Fail: visual order diverges from traversal order with no remediation.
- **Focus is managed across context changes (Material).** Initial focus is defined per screen; opening a dialog moves focus into it; closing returns focus to the element that opened it; a visible focus ring appears on keyboard traversal. Fail: focus lost to page top after a dialog closes.
- **Labels describe purpose, not appearance, and omit the role (Material).** Icon-only controls, meaningful images, and progress/error cues carry labels naming the action or meaning ("Voice search", not "Microphone"); decorative images are hidden from assistive tech; the role word ("button") never appears inside the label.
- **Core functionality is never gesture-only (HIG).** Any action in the UI's core functionality or supported task flows that a gesture performs (swipe-to-dismiss, swipe-row actions, custom gestures) is also reachable through a visible onscreen control; an optional convenience gesture duplicating an already-visible control needs no second alternative. Frequent actions use the simplest gesture available, no custom multi-finger requirements.
- **Keyboard access is complete and system shortcuts stay untouched (HIG).** Core flows complete with the keyboard alone (Full Keyboard Access on Apple platforms), and system-defined keyboard shortcuts are not overridden.
- **Custom shortcuts default to two-key combinations and are discoverable (Material).** Custom keyboard shortcuts use two or more keys by default — a single-key shortcut needs a remap option, component-focus scoping, or an off switch — and a help surface lists them.
- **Timed UI does not self-dismiss content people must act on (HIG).** Views and controls that auto-dismiss on a timer are minimized; anything carrying a decision or unfinished reading dismisses by explicit action. Fail: an error toast that disappears before its recovery action can be reached.
- **Reduce Motion is honored with concrete substitutions (HIG).** When the OS reduce-motion setting is on, decorative/repetitive animation stops by default — the Accessibility Baseline's narrowly scoped, explicitly opt-in in-product override for brand-splash/celebration moments remains valid and is the only exception. For animations that use these effects: springs tighten (no bounce), x/y/z transitions become fades, z-depth and blur animations are avoided, and gesture-driven animation tracks the gesture. Essential status motion (progress) remains. Declare essential-vs-decorative intent per the reduced-motion rule in the Accessibility Baseline above; native OS setting detection routes to `platform-mobile-patterns.md` Mobile Motion Discipline.

### Platform conventions walkthrough

- **One-handed reachability shapes iPhone layouts (HIG).** Primary and frequent controls live in the middle or bottom of the screen; back-swipe from the edge and list-row swipe actions are preserved, not hijacked by custom edge gestures (Android's equivalent predictive-back geometry routes to `platform-mobile-patterns.md`).
- **The surface adapts to user-chosen appearance settings (HIG).** A screen passes walkthrough only after being checked under orientation change, Dark Mode, and enlarged Dynamic Type — the platform treats these as user choices the app must follow, not edge cases.
- **Standard platform components are the default for standard tasks (Material).** Standard platform controls and semantic elements inherit assistive-technology support for free; a custom replacement for a standard task (e.g. a non-standard dialog) carries the burden of extra AT verification before it passes walkthrough.
- **Contrast and appearance adaptation is verified on the rendered surface (HIG).** Beyond the orientation/Dark Mode/Dynamic Type checks above, the walkthrough gate is observable: the surface renders correctly with the Increase Contrast setting on — text, icons, and state indicators keep sufficient contrast and their meaning. Preferring system-defined colors (whose accessible variants adapt automatically) and familiar system behaviors is non-blocking implementation guidance verified in code review, because two token implementations can render identically.

### Deliberately not absorbed from the platform specs

Recorded so future rounds do not re-import them; each was read and rejected for walkthrough use:

- HIG media-accessibility taxonomy (captions vs subtitles vs audio descriptions vs transcripts) — media-content-type guidance, not a screen-walkthrough criterion; consult the HIG Hearing section directly when shipping media surfaces.
- HIG platform-capability integrations (Siri/Shortcuts, Switch Control, Voice Control setup, Assistive Access optimization) and watchOS/visionOS-specific rules — implementation- or platform-mode-specific; route to the stack implementation skill if those surfaces enter scope. One exception is retained: the visionOS 60×60pt hit-region figure stays inside the iOS hit-region criterion as informational context only — this walkthrough's scope remains iOS/Android mobile surfaces and does not govern visionOS.
- Material state-layer token mechanics (fixed opacity percentages, on-color derivation) — design-kit implementation detail owned by token/component references, not an acceptance criterion.
- Material web-landmark role enumeration (the eight ARIA roles) — imported only as the "landmarks get unique labels" criterion; the full role catalog is reference material, not a checklist.
- Visual-style content from either spec (Liquid Glass materials, M3 Expressive shapes/motion values) — style adoption is a product decision covered by `platform-mobile-patterns.md` Platform OS Updates; copying platform visual language is already ruled out by "What Not To Absorb" below.

## Performance And Perceived Speed

Use these checks for AI, feed, media, upload, and document-heavy surfaces:

- LCP-critical content should appear quickly or use a meaningful skeleton that matches final layout.
- Avoid layout shifts when cards, media, citations, ads/promotions, AI output, or toolbars load.
- User input should remain responsive during streaming, upload, PDF/document rendering, long tables, and chart rendering.
- Heavy panels should lazy-load without hiding the primary task.
- Progress should be visible for long-running operations; if duration is uncertain, show staged progress and recovery options.
- Repeated rerenders, oversized bundles, unbounded lists, and hidden but mounted expensive viewers should be treated as launch risks.

## Product Metrics For Iteration

Use HEART-style metrics as a product-iteration lens:

- **Happiness**: satisfaction feedback, qualitative complaints, rating/reaction reasons, AI answer helpfulness.
- **Engagement**: feed depth, comments/replies, reactions, follows, topic joins, creation attempts, AI draft usage.
- **Adoption**: first successful action, first follow, first post/comment, first AI-assisted contribution, onboarding completion.
- **Retention**: return from notification, repeat visits, recurring creation, saved topics, creator return.
- **Task success**: completion rate, time to complete, error rate, retry rate, abandon step, moderation appeal success.

Do not optimize a visual change without a corresponding behavior or quality hypothesis.

## Launch Review Additions

Add these to product launch acceptance:

- Accessibility smoke test: keyboard, focus, contrast, labels, target size, long text.
- Web performance smoke test: key page load, no major layout shift, responsive input during interaction.
- Error-prevention smoke test: destructive/public/trust-sensitive actions have confirmation and recovery.
- Metrics smoke test: primary action, failure, retry, drop-off, and satisfaction events are observable.
- Content clarity smoke test: empty/error/success states say what happened and what to do next.

## What Not To Absorb

- Do not turn external benchmark articles into a generic checklist dump.
- Do not force enterprise dashboard density onto consumer discovery surfaces.
- Do not import another design system's exact visual language when local tokens/components exist.
- Do not cite performance or accessibility as "done" without running a product-specific check when implementation exists.
