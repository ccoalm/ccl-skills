# UI/UX Audit

Use this reference when the task is to review, QA, compare, or improve UI/UX in a design file or frontend implementation. It turns the extracted design system, Figma screens, and frontend implementation patterns into a concrete audit procedure.

This is not a domain-compliance audit. For finance, healthcare, legal, or regulated products, use this as the UI/UX layer and add the appropriate domain rules separately.

Audit findings are criteria/evidence inputs to `delivery-contract.md`, not an independent acceptance path. A runtime-visible audit names every affected React/other-Web, H5, native, mini-app, terminal/CLI/TUI, Electron/desktop/TV, other-client, and composite-host layer; ready/complete still requires the complete design/test/producer/client binding set, Test Phase 1, and an allowed design verdict.

## Evidence Sources

Use these sources in this order:

1. Current target product code and screenshots.
2. Relevant source Figma file or design-system file.
3. `interaction-design-patterns.md` for flow, feedback, state, gesture, and trust-sensitive behavior.
4. `visual-craft.md` for brand feel, hierarchy, anti-slop, motion, and polish.
5. `tokens-and-components.md`, the applicable platform lens, and every affected client owner's convention for tokens, component/command semantics, host behavior, and adaptation.
6. `frontend-code-evidence-map.md` for local code evidence classification and reusable behavior patterns, never as product-domain requirements.

Reusable Mobile/desktop capability observations already extracted (illustrative, not a closed platform set):

- Mobile design system: Button, List, Card, Image, ImageViewer, NoticeBar, FloatingPanel, Dialog, Empty, ErrorBlock, Modal, Progress, Result, Skeleton, SwipeAction, Toast, NavBar, Popup, TabBar, SafeArea, ImageUploader, PasscodeInput, and Example Pages.
- Desktop design system: Button, Layout, Splitter, Menu, Dropdown, Steps, Form, Input, Select, Upload, Card, Empty, List, Tag, Tooltip, Alert, Drawer, Message, Modal, Notification, Progress, Result, Skeleton, and Table/Tabs marked `【todo】` as weak guidance only.
- Desktop shell/workbench capability class: sidebar, content cards, login states, workbench, AI assistant, responsive panel collapse, empty cards, process entries, Stepper, Alert, Message, Dialog, and upload/import workflow.
- Mobile app interaction source: onboarding/login, agreement consent, keyboard states, task cards, tab navigation, AI upload, multi-item review, Toast, Modal, settings/profile, and interaction-note sections.
- Implementation primitive catalog: see `ui-ux-design-development.md`.

## Audit Severity

Report findings by user impact, not by how easy they are to fix:

- **P0 Blocking**: user cannot complete the primary task, destructive action can happen accidentally, sensitive operation lacks confirmation, auth/permission state is misleading, or mobile layout hides the primary action.
- **P1 High**: key state is missing, flow loses context, feedback is ambiguous, responsive behavior breaks core reading/action, AI/trust output lacks source or failure handling, or design system divergence creates visible inconsistency.
- **P2 Medium**: hierarchy, spacing, copy, hover/focus/disabled, empty state, loading, or component choice harms comprehension but has a workaround.
- **P3 Polish**: microcopy, motion, icon choice, truncation, minor spacing, or visual rhythm issue that does not block the task.

Always include concrete file/line references for code reviews and Figma file/page/section references for design reviews when available.

## Audit Procedure

1. **Classify every rendered layer**: React/other Web, H5, native mobile/host, mini-app, ordinary CLI or terminal/TUI, Electron/desktop/TV, other client, or composite host; then name the consumer/operational/AI/shared/onboarding/settings/trust/analytics task shape.
2. **Name the primary task**: what the user must be able to do in one sentence.
3. **Trace the flow**: entry, context, action, feedback, recovery, return.
4. **Map required states**: happy, first-use, empty, loading, partial, error, retry, permission, disabled, success, undo/cancel, long-content, and responsive states.
5. **Compare UI primitives**: check whether the implementation uses the closest existing component and token semantics instead of one-off UI.
6. **Check UX clarity**: hierarchy, action priority, copy, affordance, consequence, source/provenance, and next action.
7. **Check accessibility basics**: readable contrast, labels, keyboard/focus or touch/input semantics where relevant, reduced-motion/capability fallback, and the affected owner's host-specific accessibility/adaptation behavior.
8. **Check visual craft**: anti-slop, product-level identity, spacing rhythm, typography scale, consistent iconography, appropriate density.
9. **Check serious-domain adaptation** when relevant: source, timestamp, partial data, confirmation, audit labels, and no unsafe optimistic UI.
10. **Check platform-convention conformance** on the named target: use `external-ui-ux-quality-benchmarks.md` to classify authority and boundary, recheck the current first-party platform source, and map applicable criteria into `delivery-contract.md`. Preserve requirement versus recommendation strength and verify on that platform's rendered runtime; do not reuse a combined HIG/Material checklist as a cross-platform standard.

## Diff-Scoped Review

When the audit target is a change (a PR/MR diff), scope the verdict to the change while still scanning mechanically:

- Run a hard-coded visual-value scan over the changed paths covering **every governed visual category** — color, background, border/stroke, shadow/elevation, gradient, spacing/padding/margin, radius, size/layout (width/height/gap), typography (font-size/weight/family/line-height), opacity, and motion (transition/animation/duration/easing/transform) (starter regex: `rg -n '#[0-9a-fA-F]{3}|rgb\(|rgba\(|hsl\(|color:|background:|border:|box-shadow|gradient|padding:|margin:|border-radius|font-size|font-weight|line-height|opacity:|width:|height:|gap:|transition|animation|transform:' <changed-paths>`; extend per stack: inline style props, CSS-in-JS literals, imperative theme config). The regex is a recall aid, not the boundary: any unmatched style declaration in a changed hunk still gets read and classified — prefer a stack-aware style/token lint where one exists. Full-audit sweep obligations stay in `multi-project-token-consistency.md`.
- Classify every hit into exactly one of three buckets: **approved design-system usage** (a token/semantic reference, or an exception that predates this change or carries the design-system owner's recorded approval — approver, scope, and expiry; an exception recorded by the change itself without owner approval is a new violation, not an approval), **pre-existing code outside the requested change**, or **new violation**. Only new violations block the change; pre-existing hits are recorded as debt for the token-consistency audit, never reported as caused by this change.
- Match the fix duty to the bucket: fix new violations in this change; do not silently expand the change to migrate pre-existing debt (route it), and do not let pre-existing debt normalize new violations ("the file already does this" is not approval — the old code is debt, not a license to copy).

## UI Checks

- Typography hierarchy matches the surface: display for brand/product moments, compact headings for dashboards, readable body text for feed/detail/comment/AI output.
- Color and radius come from tokens or a clearly stated product reason.
- Cards, buttons, inputs, tags, tabs, and modals do not all share the same visual weight.
- Empty, loading, and error visuals are sized to context: compact inside cards/drawers, larger for full-page blocks.
- Long labels, names, tags, badges, comments, titles, file names, and generated text truncate or wrap predictably.
- Icons are semantic, not decorative filler. Critical actions use familiar symbols and accessible labels/tooltips.
- Data-heavy screens keep scan lines stable: sticky headers, aligned controls, consistent row/card heights, and visible active filters.
- Mobile screens respect safe area, bottom actions, keyboard visibility, and one-handed reach.
- Web screens collapse secondary panels before damaging primary content readability.
- Mini-app, ordinary CLI or terminal/TUI, other-Web, Electron/desktop/TV, and composite-host screens apply the actual owner-specific host, input, geometry, fallback, bridge, and recovery checks.

## UX Checks

- The user can identify the current location, current object, current mode, and next action without reading documentation.
- Primary and secondary actions are visually distinct; destructive actions are explicit and separated.
- Feedback strength matches consequence: inline < toast < alert < sheet/drawer < modal/dialog < full-page block.
- Selection, filters, tabs, sort, and comparison targets remain visible after they affect content.
- A failed upload, failed image, failed AI generation, failed external link, or failed data fetch has a retry or recovery path.
- Cancel, close, back, clear, remove, retake, replace, undo, or exit behavior is explicit where users can lose work.
- AI output is not treated as final by default. Provide generating, failed, reviewed, editable, regenerate, source/citation, and copy/share states where relevant.
- Trust-sensitive data shows provenance: source, timestamp, data scope, confidence caveat, and partial-result labels.

## Code Review Signals

Look for these implementation signals in frontend code:

- Good: reusable async wrapper, explicit `loading/error/onRetry`, toast queue/dedupe, privacy/consent modal, safe-area/keyboard handling, route-driven selected navigation, permission-gated menu rendering, tooltip on truncation, retryable image/upload components.
- Risk: raw hex colors inside feature components, duplicated local token sets, inline modal styles, `--` values without error/partial labels, console-only failures, silent catch blocks, primary action disabled without reason, layout based only on desktop width, no long-text handling, no retry path.
- Risk in serious products: optimistic success before server confirmation, missing source/timestamp, ambiguous AI result status, destructive action hidden in generic menu, or external link failure only logged.

## Figma Review Signals

Look for these design-file signals:

- Good: named states, component variants, selected/hover/disabled/loading/error states, explicit empty/error pages, mobile keyboard frames, responsive widths, AI open/closed states, upload/progress/retry states, modal and toast examples.
- Risk: only happy-path frames, duplicated components without variants, domain-specific old workflow mixed into generic rules, unchecked `【todo】` components treated as final, no narrow-width frame, no error/permission/empty state, visual styles detached from design-system tokens.

## Output Format

When asked to review or audit UI/UX (in any working language), lead with findings:

- Severity, issue title.
- Evidence: file/line or Figma file/page/section.
- User impact.
- Suggested correction.

Then add a short summary:

- What is already strong.
- What should be fixed first.
- Any scope limitation, such as "this is UI/UX only, not finance compliance".

Keep findings specific. Do not list generic best practices unless tied to an observed issue.

## Review Discipline

- **Debuggable taste — trace every subjective finding to a broken principle.** "This feels off / cluttered / cheap" is not a finding until it names *which* principle it violates: visual hierarchy, scan path, action priority, state coverage, density fit, affordance/clickability, semantic consistency, trust/provenance cue, or accessibility. If you cannot immediately name it, make a targeted articulation attempt before deciding. When observable user impact remains (the user is slower, confused, distrusts, or cannot complete the task) but the principle is still unclear, mark it `needs articulation / second look` **at its impact-based severity** — never downgrade a real P0/P1 to P3 because the reviewer's vocabulary is weak; severity is set by user impact (per Audit Severity), not by how easily a finding is named. Only when no user-impact evidence survives the articulation attempt is it a preference — then drop it or record P3 polish labeled taste. This keeps reviews defensible and actionable and stops "vibes" findings, without suppressing real-but-hard-to-name defects.
