# UI/UX Extraction Routing Map

Use this reference before landing UI/UX, Figma, frontend, app, or client-facing extraction rules. It prevents source evidence from updating only the design skill while missing implementation, testing, product workflow, or extraction-method owners.

## Routing Rules

- Route by lifecycle ownership, not by where the evidence was found.
- A Figma observation can require web/app/test updates when it describes runtime behavior.
- A code observation can require design updates when it reveals a state users must understand visually.
- If a rule is source-derived but an owner is not updated, record the reason in the target-output map.

## Common Routing Map

| Rule type | Design/reference | Web React | App/cross-platform | Testing | Product workflow | Extraction workflow |
| --- | --- | --- | --- | --- | --- | --- |
| Visual direction, typography source, semantic color tokens, neutral/background scale, radius/shadow role, or theme divergence | required | required when implementation/theme/CSS owns it | required when app/native theme owns it | screenshot/contrast/visual acceptance | optional for readiness gate | required when extraction method missed token provenance |
| Visual hierarchy, focal point, density, spacing, mood | required | optional when implementation affects layout | optional when mobile/native layout affected | screenshot/visual acceptance | optional for readiness gate | no |
| Component state semantics such as hover, active, selected, disabled, empty, loading, error | required | required for web implementation | required for app implementation | required | optional | no |
| Entry/current/next/return flow | required | required for route/state ownership | required for navigation/native shell | required | required when it changes delivery scope | no |
| Modal, drawer, overlay, popover, sheet, or stack behavior | required | required when web surface owns it | required when app/native shell owns it | required | optional | no |
| Keyboard, IME, paste, focus, caret, safe area, or viewport behavior | required for UX acceptance | required for web/H5 | required for app/WebView/native | required | optional | no |
| Gesture conflict such as swipe, drag, pinch, zoom, tap fallback | required | required when browser/H5 | required when mobile/native | required | optional | no |
| Media preview, retry, old-content hold, zoom/pan, crop, upload progress | required | required for web/H5 implementation | required for app/native capability | required | required for high-risk media workflows | no |
| Duplicate submit, idempotency, pending/final distinction, rollback | required for visible states | required | required | required | required for high-risk finality | no |
| Bulk/default/destructive/public/costly action consequence | required | required if implemented in web | required if implemented in app | required | required | no |
| Permission/no-access/feature-disabled/no-entitlement state | required | required | required | required | required when product scope changes | no |
| Native shell bridge, WebView/WKWebView, injected app info, native storage, page-ready overlay | required for shell-dependent UX | required for H5 side | required for native side | required | optional | no |
| Orientation, safe area, foreground/background, app restart, return recovery | required for mobile UX | required for app-hosted H5 | required | required | optional | no |
| Automation, generated content, AI suggestion, confidence/caveat, review-before-commit | required | required when web owns generated flow | required when app owns generated flow | required | required for AI/high-impact workflow | optional if extraction method learned |
| Analytics/chart/table dense inspection, drilldown, scroll restore | required | required for web implementation | required for app implementation | required | optional | no |
| Accessibility: contrast, labels, focus order, touch target, text scaling, reduced motion | required | required | required | required | launch readiness when user-facing | no |
| Microcopy: empty, error, disabled, confirmation, consequence, source/caveat | required | required where code maps messages | required where app maps messages | required | required for high-risk actions | no |
| Performance perception: skeleton/spinner, first feedback, long task progress, cancel | required | required | required | required | launch readiness when performance-sensitive | no |
| Domain leakage, source naming, extraction coverage, judgment-delta, evidence depth | no | no | no | no | no | required |

## Default Decisions

- Figma-only extraction can update design references, but must mark implementation/testing behavior as unverified unless code or runtime evidence is inspected.
- Code-only extraction can update development and testing skills, but must not claim a new aesthetic rule unless rendered UI, screenshots, or design source is inspected.
- Figma plus code extraction for a user-facing flow normally updates at least design/reference, the relevant web or app skill, testing strategy, and provenance when it changes visible design, runtime states, or acceptance gates. If it introduces or substantially reshapes a screen, include visual direction/token provenance in the target-output map.
- Product workflow updates are required when the rule changes readiness gates, launch acceptance, high-risk finality, user trust, compliance, money/quota, public posting, destructive actions, or AI/user-decision boundaries.

## Target-Output Prompt

Before editing, fill this compact map:

| Candidate rule | Evidence source | Design | Web | App | Testing | Product workflow | Extraction workflow |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Rule in one sentence | Figma node/code path/review | update/skip reason | update/skip reason | update/skip reason | update/skip reason | update/skip reason | update/skip reason |

If a candidate rule has no owner, it is probably a source note, not a skill rule.
