# UI/UX Design And Development

Use this reference when the task is to design a UI/UX surface and implement it in client code. It is a primitive catalog and translation guide; `delivery-contract.md` is authoritative for the design brief, testing selection, producer/client returns, evidence semantics, and design verdict.

This reference is for new-product UI/UX execution. Do not copy education-domain workflows, wording, assets, product assumptions, or information architecture from source artifacts.

## Working Mode

Before coding, define:

- **Surface type**: mobile consumer, web consumer, web operational, AI workspace, onboarding, settings, trust/safety, analytics, or shared component.
- **Primary user job**: one sentence describing what the user must accomplish.
- **Density**: consumer relaxed, productive compact, or hybrid.
- **Source pattern**: which Figma/code pattern is being reused and what domain details are discarded.
- **State set**: use the canonical taxonomy in `product-surface-patterns.md`, then add implementation-specific loading, retry, cancellation, permission, long-content, and responsive behavior.
- **Client owner set**: follow every affected rendered layer in `delivery-contract.md`. React web → `web-react-dev`; Vue/Svelte/static/vendor/other web → its installed web-content owner or fail-closed project-convention lookup; native mobile/host → `app-cross-platform-dev`; mini-app → `miniapp-product-dev`; terminal/CLI/TUI → `terminal-cli-dev`; Electron/desktop/TV shell → its installed owner or the same project-convention lookup. Composite hosts keep separate content and shell members.
- **Producer owner**: every changed or claim-bearing backend, config, content, or inference source that supplies a rendered value or behavior; record its exact artifact/version identity before client execution.

Do not start from a decorative layout. Start from the user job, interaction loop, and required states.

## Design-To-Code Sequence

1. **Map the frame to product primitives**: identify shell, navigation, content area, action area, feedback area, modal/drawer/sheet, and terminal states.
2. **Pick a layout recipe**: use `layout-recipes-and-screenshot-acceptance.md` for workbench, consumer web, mobile, table/list, editor, state, density, and screenshot rules.
3. **Choose existing components first**: use local codebase primitives or the design-system equivalent before creating custom UI.
4. **Define tokens before styles**: color, type, spacing, radius, elevation, and motion should map to existing tokens or a named semantic role.
5. **Implement state model**: represent loading/error/empty/partial/success/permission explicitly in data and UI.
6. **Implement responsive behavior**: mobile safe area and keyboard behavior; web secondary panel collapse and min/max widths.
7. **Implement feedback**: inline validation, toast/message, alert/notice, drawer/sheet, modal/dialog, result page.
8. **Return execution evidence**: have every changed or claim-bearing producer and every affected client return its own immutable record, then have the test owner bind its definition and execution records to the exact producer/client versions exercised. Keep commands, artifacts, criterion results, dimensions, coverage boundary, and gaps in their owning records as required by `delivery-contract.md`; a screenshot proves only its captured state.
9. **Record the design verdict**: run the relevant checks in `ui-ux-audit.md`, evaluate every criterion, and bind the design record plus `candidate`, `accepted`, `rejected`, or `pending` to the complete design/test/producer/client candidate-binding set.

## Mobile Frontend Patterns

Use mobile patterns from the local frontend evidence map:

- Use a page-level responsive container for mobile surfaces; avoid ad hoc full-screen wrappers.
- Put global toast/provider behavior at layout level, not inside individual feature components.
- Wrap async feature sections with a reusable loading/error/retry abstraction rather than branching every page by hand.
- Use safe-area utilities for bottom tabs, sticky actions, and fullscreen task surfaces.
- Use keyboard-aware wrappers for bottom sheets, dialogs, and forms with input fields.
- Keep bottom navigation durable; use screen-level NavBar for back/close/title behavior.
- Keep destructive or consent actions in dialog/alert-dialog patterns with explicit primary and secondary actions.
- For upload/media/review flows, include preview, remove/replace, progress, retry, permission denied, confirm, and completion.

When adapting these patterns, translate the UI copy and information architecture to the new product.

## Web/Desktop Frontend Patterns

Use web patterns from the local frontend evidence map and the desktop design system:

- Use a stable shell: account context, primary navigation, selected state, collapsed state, and content viewport.
- Use Ant Design-style component semantics where the codebase already has Ant Design or similar mature primitives.
- Use route-driven selected menu state; do not rely only on local click state.
- Use permission-gated rendering for menus and actions that users cannot access.
- Use task/process tabs only for active user work such as uploads, generation jobs, imports, reviews, drafts, or downloads.
- Use tooltip/popover for truncated names, disabled reasons, metric definitions, and compact explanations.
- Use drawers for detail inspection or setup when parent list/table context should remain available.
- Use stepper/progress/result patterns for upload/import/configure/review/publish flows.

When adapting these patterns, avoid carrying over old role names, product categories, or workflow-specific labels.

## Implementation Primitive Catalog

Use this as the canonical implementation primitive catalog. Other references should point here instead of re-listing source-code primitives.

Mobile behavior primitives:

- Page shell and responsive container, such as `ResponsiveContainer`.
- Async loading/error/retry wrapper, such as `AsyncContent`.
- Section-level error block with retry action, such as `ErrorBlock`.
- Toast provider with queue, dedupe, type, and position behavior, such as `MiniToastProvider`.
- Consequential decision dialogs for consent, update, discard, and destructive actions, such as `PrivacyModal` and `UpdateConfirmDialog`.
- Keyboard and visual-viewport handling, such as `KeyboardAvoider`; cover iOS visual viewport and Android resize/overlay differences without relying on one browser behavior.
- Route-aware bottom tabs with active state and restrained animation, such as `TabBar`; active state should survive nested routes and programmatic navigation.
- Upload/media preview, remove/replace, progress, retry, permission denied, confirm, and completion patterns.

Web/desktop behavior primitives:

- Central token/theme override surface, such as a shared Less/theme file.
- Route-driven navigation selection and collapsed/expanded shell state, such as `SiderMenus`.
- Permission-gated menu/action rendering.
- Process/task tabs for active user work, such as `SiderProcessTabs`; use an event or state model for append, replace, delete, select, and cleanup when work can start outside the current route.
- Truncation tooltip/popover for long labels and table cells; enable tooltips from measured overflow rather than always showing noisy hover content.
- Explicit collapse affordance and hover state, such as `SiderFoldLine`.
- Reusable compact empty component, such as `Empty`.
- Stepper/progress/result patterns for upload/import/configure/review/publish flows.
- Sticky filter bars, sticky table headers, and fixed action columns for dense analytics or management tables.
- Split workbench geometry for review/editor surfaces: compact top context, primary flexible preview/result area, and fixed 320-500px side settings or metadata panel.

## Component Selection Rules

Prefer the closest existing primitive:

- Feed/list/detail: Card, List, Avatar, Image, Tag, Badge, Skeleton, Empty.
- Creation/AI: Form, TextArea/Input, Upload/ImageUploader, Button, Progress, Toast/Message, Drawer/Sheet, Dialog/Modal, Result.
- Comments/replies: List, Avatar, TextArea, ActionSheet/Popover, SwipeAction where mobile-appropriate.
- Notifications: List, Badge, NoticeBar/Alert, Message/Toast, Empty.
- Creator/moderation/admin tools: Table/List/Card, filters, Tags, Drawer, Modal/Popconfirm, Alert, Result.
- Analytics: Card, Statistic, chart container, Tooltip/Popover, filter toolbar, empty/error/partial labels.
- Settings/account: Form, Input, Select/Picker, Switch, Radio/Checkbox, Alert, Dialog.

Create a new component only when no existing primitive can express the interaction or when duplication is already meaningful.

## Token And Styling Rules

- Mobile implementation should map to CSS variables or design-system utility classes for primary/background/text/border/radius roles.
- Web implementation should map to Less/theme variables or component theme overrides before using raw colors.
- Raw hex values inside feature components are acceptable only for temporary integration or data visualization palettes; otherwise promote them to semantic tokens.
- Use semantic radius roles: compact controls, cards/panels, bottom sheets/dialogs, circular icons/avatars.
- Do not create a second visual system inside one feature.
- Do not introduce page-local gradients, shadows, or oversized radii unless they are part of the product-level visual direction.

## State Implementation Rules

Every implemented feature should map the canonical state taxonomy in `product-surface-patterns.md` to explicit UI and data ownership. Add these implementation rules:

- Loading should use skeleton or progress that matches the final layout.
- Empty should explain the missing content and offer the next useful action.
- Error should provide visible message plus retry or next step when recoverable.
- Partial should show what loaded, what did not, and whether data is stale.
- Disabled controls should have a visible or discoverable reason.
- Success should confirm completion and expose the next action.
- Cancel/undo should exist when users can lose drafts, selections, uploads, or generated output.
- Permission state should say what is blocked and what the user can still do.

Avoid silent catches and console-only errors for user-triggered actions.

## AI UI/UX Development Rules

- AI input surfaces must show attachment state, selected source/context, streaming/loading, stop, retry, and failed states.
- AI output must support copy/share, regenerate, edit or use-as-draft, source/citation where relevant, and reviewed/unreviewed distinction.
- AI actions should not block the primary manual workflow; use side panels or drawers on web and bottom sheets/fullscreen task views on mobile.
- Long-running AI tasks should persist visibly as task/process entries, notifications, or progress cards.
- For serious domains, show source, timestamp, data scope, and caveat near the AI output.

## Responsive Acceptance

Treat the Mobile and Web checks below as stack-specific examples. Build the complete affected client-owner set from `delivery-contract.md`; add mini-app host/device, ordinary CLI or terminal/TUI, Electron/desktop/TV shell, other-Web, and composite-host evidence whenever those layers are affected.

Mobile:

- Safe top/bottom areas are respected.
- Keyboard does not hide the active input or primary action.
- Bottom action bars do not cover content.
- Long labels and generated text wrap or truncate predictably.
- Tap targets are reachable and not crowded.

Web:

- Primary content keeps a usable min width.
- Secondary panels collapse before the main task becomes unreadable.
- Dense toolbars wrap or condense predictably.
- Sidebar collapsed mode remains discoverable.
- Tables/lists preserve row identity and selected/filter state.

Other affected clients:

- Mini-app evidence covers the shipped host/tool, supported device class, safe area, permissions/capabilities, package/platform constraints, and embedded web-view bridge when present.
- Ordinary CLI or terminal/TUI evidence covers command/help/default/exit/recovery semantics, TTY and non-TTY/plain modes as applicable, width/capability/color fallback, and interactive lifecycle only where used.
- Electron/desktop/TV and other-Web evidence comes from the actual content owner plus shell owner or fail-closed project convention, including supported sizes/scaling, input/focus, bridge, and content-shell integration.

Screenshot acceptance:

- First viewport shows the primary workflow, not a decorative banner or empty dead area.
- Empty/loading/error states keep the same geometry as the final content where possible.
- Realistic long labels, long generated text, no data, partial data, and permission-disabled cases do not break spacing or hierarchy.
- Operational workspaces look like focused work surfaces; consumer surfaces look content-led and approachable.

## Development Review Checklist

Use this list as client-side criteria before returning the client record. It cannot by itself finish the slice; completion requires bound design and test records, every changed producer and affected client return, Test Phase 1 sufficiency, and an allowed design verdict under `delivery-contract.md`.

- The code uses local primitives and tokens before custom markup/styles.
- The flow maps to `discover -> inspect -> act -> confirm -> return`.
- Canonical states from `product-surface-patterns.md` are implemented, not just documented.
- Feedback strength follows `interaction-design-patterns.md`.
- Every affected client's adaptation contract is covered; Mobile safe-area/keyboard and Web responsive behavior are examples, not the closed set.
- Global feedback providers, async wrappers, and route/workspace state are mounted at the shell level when multiple feature pages rely on them.
- Long-running uploads, imports, downloads, generation, or review jobs remain visible after route changes and have retry/fail/complete states.
- Designed states have a code owner: shell/provider state, route state, feature state, server task state, or local draft state. Do not leave a designed state as static markup with no data transition.
- AI/trust-sensitive output has source, state, retry, and review affordances where relevant.
- No source-domain terms, assets, or workflow assumptions leaked into the new product.
- Visual polish passes `visual-craft.md`.
- Screenshot acceptance passes `layout-recipes-and-screenshot-acceptance.md`.
- UI/UX review passes `ui-ux-audit.md`.
- The client return names the exact producer member/version exercised and contributes its immutable member to the complete design/test/producer/client binding set.
