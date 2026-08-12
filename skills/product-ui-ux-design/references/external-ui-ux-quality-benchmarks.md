# External UI/UX Quality Benchmarks

Use this reference when internal Figma/code evidence is not enough to judge UI/UX quality, launch readiness, accessibility, performance, or iteration metrics.

These are external quality benchmarks, not visual style sources. Do not copy another product's brand, layout, or component appearance.

## Source Anchors

- Nielsen Norman Group: usability heuristics such as system status visibility, user control, consistency, error prevention, recognition over recall, and recovery.
- W3C WCAG 2.2: accessibility criteria for keyboard, focus, contrast, labels, target size, error identification, and consistent navigation.
- web.dev Core Web Vitals: Largest Contentful Paint, Cumulative Layout Shift, Interaction to Next Paint, and field/lab measurement.
- Google HEART framework: product-experience metrics across happiness, engagement, adoption, retention, and task success.
- Platform/design-system guidance such as Material Design and Atlassian Design System: touch targets, empty/error states, progressive disclosure, feedback, and content clarity.

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
