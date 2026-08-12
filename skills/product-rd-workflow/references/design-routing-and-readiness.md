# Design Routing And Readiness

Use this reference when product work has a user-facing surface, interaction flow, information architecture, visual system impact, or design-system dependency.

## When Design Is Required Before Implementation

- New screen, navigation path, onboarding, creation flow, dashboard, settings surface, or mobile/web interaction pattern.
- Existing workflow changes that affect user decision-making, empty/loading/error states, permissions, accessibility, or visual hierarchy.
- Product copy, information architecture, component semantics, or design-system tokens/components are ambiguous.
- The implementation could lock in a hard-to-change layout, data model presentation, or interaction contract.
- The product needs a launch/readiness check for UI completeness, visual quality, or interaction polish.

Small backend-only, CLI-only, config-only, or internal refactor tasks can skip design if user-facing behavior and acceptance are already clear.

## Routing

- Use `product-ui-ux-design` for product UI/UX design readiness across community, finance/data, AI workspaces, operational tools, Web, and App surfaces.
- Use scenario references inside that skill only when the target surface matches; community/feed/creator patterns are optional lenses, not the default model for every product.
- Use Figma/design plugin skills when the task explicitly requires Figma file creation, design-system rules, component mapping, or design-to-code implementation.
- Use UI/design review skills for visual QA, accessibility criteria, interaction polish, and launch-readiness review.
- Keep product-rd-workflow responsible for sequencing, acceptance, and handoff evidence; do not duplicate detailed design-system rules here.

## Design Readiness Evidence

Before implementation, capture only the evidence proportional to risk:

- target user/caller and primary workflow;
- approved interaction model or wireflow for new/changed surfaces;
- key states: empty, loading, error, success, permission denied, disabled, offline/timeout where relevant;
- responsive/mobile expectations and accessibility constraints;
- component/design-system reuse decisions and any intentional deviations;
- for a visible-UI design checkpoint, also record: surface type, density mode, layout structure, trust/safety boundary, and visual acceptance criteria;
- acceptance checks that engineering and QA can verify;
- **cross-platform brand decisions when the same product surfaces on multiple stacks**: if the product intentionally renders different brand-primary values per platform (web vs native mobile vs mini-program), the product owner MUST record the decision explicitly — which value applies to which platform, why, and which named role in the design source carries each value (`colorPrimary-web` / `colorPrimary-native` / per-platform variable collection). Implicit "we just always used this color on Android" is the failure mode that downstream design + engineering audits keep re-discovering as drift. If the product owner decides the values should converge, that is also recorded with an owner and a target date. See `product-ui-ux-design/references/multi-project-token-consistency.md` Cross-platform brand divergence sub-case for the design-side check.

For dense web shells, app shells, creator workspaces, or AI/task-heavy surfaces, also capture navigation state ownership, permission-gated actions, active task/process visibility, long-label overflow behavior, global feedback placement, and how users return to their previous context after a modal, drawer, upload, generation, or detail view.

For mobile surfaces, also capture safe-area behavior, keyboard avoidance, bottom navigation or sticky action behavior, update/consent dialogs, and whether errors appear inline, as toast, as a result page, or as a blocking dialog.

## Handoff Rules

- Do not treat a vague mock, screenshot, or verbal idea as implementation-ready when states, copy, permissions, or responsive behavior are missing.
- Do not require full design artifacts for tiny copy/state tweaks when acceptance checks are enough.
- If design and architecture conflict, resolve sequence explicitly: user workflow and IA first, then service/API/data contracts that support it.
- If design feedback reveals reusable rules, update the smallest correct design skill/reference rather than this workflow unless the lesson is about sequencing or handoff.
