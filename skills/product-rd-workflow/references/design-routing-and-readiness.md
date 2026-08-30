# Design Routing And Readiness

Use this reference when product work has a user-facing surface, interaction flow, information architecture, visual system impact, or design-system dependency.

## When Design Is Required Before Implementation

- New screen, navigation path, onboarding, creation flow, dashboard, settings surface, or mobile/web interaction pattern.
- Existing workflow changes that affect user decision-making, empty/loading/error states, permissions, accessibility, or visual hierarchy.
- Product copy, information architecture, component semantics, or design-system tokens/components are ambiguous.
- The implementation could lock in a hard-to-change layout, data model presentation, or interaction contract.
- The product needs a launch/readiness check for UI completeness, visual quality, or interaction polish.

Small backend-only, parser/library-only CLI, config-only, or internal refactor tasks can skip design only when evidence proves they preserve every user-facing behavior and acceptance contract. Any changed command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, recovery, full-screen TUI, interactive terminal layout, ANSI state, or keyboard/focus flow is a user-facing terminal surface and does not qualify for that shortcut.

## Routing

- Use `product-ui-ux-design` for product UI/UX design readiness across Web, App, mini-program, desktop/native, terminal/TUI, and other user-facing surfaces.
- Use scenario references inside that skill only when the target surface matches; community/feed/creator patterns are optional lenses, not the default model for every product.
- Use Figma/design plugin skills when the task explicitly requires Figma file creation, design-system rules, component mapping, or design-to-code implementation.
- Use UI/design review skills for visual QA, accessibility criteria, interaction polish, and launch-readiness review.
- Keep product-rd-workflow responsible for sequencing, acceptance, and handoff evidence; do not duplicate detailed design-system rules here.
- Use `../../product-ui-ux-design/references/delivery-contract.md` as the canonical design brief → test Phase 0 → producer/client execution → test Phase 1/sufficiency → design verdict record. Product R&D records the slice and sequencing decision; every changed producer and affected client writes its own runtime facts once, each client names the producer member/version it exercised, testing cites both record sets for sufficiency, and each owner fills only its part instead of restating a separate checkpoint.

## Design Readiness Evidence

Before implementation, link one canonical delivery record, complete the applicable full Design brief or valid low-risk copy-only record, and obtain its Test selection Phase 0. This reference does not restate or partially fork the contract's schema. Record unresolved product decisions and their owner instead of filling a design gap with implementation convention.

Product-stage additions remain narrow:

- **Cross-platform brand decisions**: when the same product intentionally renders different brand-primary values per platform, the product owner records which value and named semantic role applies to each platform, why they differ, and the convergence owner/date when convergence is chosen. See `../../product-ui-ux-design/references/multi-project-token-consistency.md` for the design-side check.
- **Dense workspaces**: select the operational/web risk lenses in `../../product-ui-ux-design/references/design-execution-checklist.md`; navigation ownership, permission-gated actions, active work, overflow, feedback placement, and return context belong in that design record rather than a second Product R&D checklist.
- **Mobile surfaces**: select the mobile risk lens in the same router; safe area, keyboard, bottom actions/navigation, consent/update dialogs, feedback carrier, lifecycle, and recovery belong in its adaptation/state/evidence fields.

## Handoff Rules

- Do not treat a vague mock, screenshot, or verbal idea as implementation-ready when states, copy, permissions, or responsive behavior are missing.
- Do not require full design artifacts for tiny copy/state tweaks when acceptance checks are enough.
- A visible slice may form a clearly labeled handoff commit or draft MR at `pre-runtime-test-ready` only when lower layers pass and the contract names the runtime owner and command. It is not MR-ready, merge-ready, complete, or accepted. Those stronger states require target-runtime inspection against the criteria, a complete design/test/producer/client candidate-binding set with the actually exercised versions, and an allowed verdict; builds, DOM existence, snapshots, and unreviewed screenshots prove only their stated oracle.
- A `rejected` slice preserves its negative evidence and `rejection_basis`. A deterministic rejection permits only a failed-criterion-targeted fix, new binding, and invalidated-criterion rerun. A design-judgment or mixed rejection requires a revised target, fresh baseline/runtime evidence, and user or named independent verdict; isolated polish cannot clear it. Both paths block complete, MR-ready, merge-ready, and normal MR. A clearly labeled review-only draft MR may carry the revised bound candidate to the named independent design owner, but remains `candidate + blocked` and cannot merge until that owner records `accepted + complete`.
- If design and architecture conflict, resolve sequence explicitly: user workflow and IA first, then service/API/data contracts that support it.
- If design feedback reveals reusable rules, update the smallest correct design skill/reference rather than this workflow unless the lesson is about sequencing or handoff.
