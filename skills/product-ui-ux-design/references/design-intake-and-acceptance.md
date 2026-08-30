# Design Intake And Acceptance

Use this reference before designing, implementing, or reviewing a concrete product surface. It supplies design-owned intake and criteria to the five top-level stages in `delivery-contract.md`; it does not replace Test Phase 0, producer/client execution, Test Phase 1, immutable binding, or the design verdict. It adapts product-intent and UX-acceptance practices while staying source-agnostic and excluding source-specific visual themes.

## Intake Triage

Clarify these points quickly before making design decisions. Do not over-ask when the answer is obvious from the current task.

| Dimension | Questions |
| --- | --- |
| Product goal | What user behavior should this screen increase: discovery, first participation, creation, retention, trust, or AI-assisted contribution? |
| User segment | Is the user new, returning, creator, moderator, power user, or casual browser? |
| Platform | Which rendered layers are affected: React or other web, H5, native mobile/host, mini-app, ordinary CLI or terminal/TUI, Electron/desktop/TV shell, composite host, or another client? Which installed owner or fail-closed project convention applies to each? |
| Surface | Is it feed, post detail, creation, onboarding, profile, topic/community, notification, AI workspace, trust/safety, analytics, or settings? |
| Primary loop | What is the screen's loop: discover -> interact, create -> publish, AI -> refine -> share, report -> review, or notify -> return? |
| Constraints | Are there known brand, component-library, accessibility, localization, privacy, moderation, or performance constraints? |
| Evidence | Which references apply: Figma-derived patterns, external community benchmarks, existing codebase UI, or explicit user-provided screenshots? |

If the user asks for "all of it" or gives a broad design request, deliver in this order:

1. Product intent and primary loop.
2. UX flow and required states.
3. UI concept and layout.
4. Design-system/tokens/component mapping.
5. Implementation plan or review checklist.

## Evidence Integrity

When applying or refreshing this skill:

- Do not claim a Figma page, code path, screenshot, metric, or review was checked unless it was actually inspected in the current task or already distilled in the references.
- If source access is unavailable, say so briefly and use the distilled rules rather than blocking normal design work.
- If evidence is thin, limit the recommendation to patterns supported by stronger references and state what would improve confidence.
- Keep source names and old product terms out of product-facing UI copy and product structure.
- For conflicting evidence, keep the clearer current reusable pattern, merge compatible variants, and discard stale or overly domain-specific details.

## Deliverable Types

Choose the smallest design-owned deliverable that satisfies the task. Runtime implementation or acceptance still follows the applicable full or lightweight record and complete design/test/producer/client owner set in `delivery-contract.md`.

### UI Concept + Layout

Include:

- Visual direction tied to the product goal.
- Main screen structure, hierarchy, and navigation.
- Key modules, cards, panels, actions, and responsive behavior.
- States that affect layout, such as empty, loading, long content, and collapsed side panels.

### UX Flow

Include:

- Entry point, main path, success state, and return loop.
- Error, empty, permission, moderation, AI failure, and undo paths.
- Cross-surface transitions such as feed -> detail -> comment, AI result -> draft -> publish, notification -> thread.

### Design System Mapping

Include:

- Tokens for color, typography, spacing, radius, shadow, and mode where relevant.
- Component selection and variants.
- Component states: default, hover, active, disabled, selected, loading, error, success, empty, and destructive.
- Per-affected-client differences and shared semantics across React/other web, H5, native, mini-app, terminal/CLI/TUI, Electron/desktop/TV, and composite-host layers.

### Implementation Plan

Include:

- File or component boundaries where known.
- Reusable components and local primitives to use first.
- Data/state requirements for the UI.
- Acceptance checks and visual QA steps.
- The changed producer owners, affected client owners, Test Phase 0 handoff, and complete design/test/producer/client binding/return plan required by `delivery-contract.md`.

### Design Review

Lead with issues, then recommended fixes:

- Functional UX gaps.
- State coverage gaps.
- Visual hierarchy and layout problems.
- Component/token violations.
- Trust, moderation, AI, accessibility, and responsive risks.

## Acceptance Standards

These checks become design criteria in the applicable full or lightweight record. Passing them locally is not completion: only the complete five-stage contract, immutable design/test/producer/client binding set, and allowed verdict/next-state pair can close a runtime-visible slice.

### Product Fit

- The target user and primary loop are clear.
- The main action supports a real target-product behavior, not just navigation.
- The screen gives users a reason to return, continue, or contribute.
- AI entry points support the target product loop instead of becoming isolated chat.

### UX Completeness

- The canonical state taxonomy in `product-surface-patterns.md` is mapped to concrete UI behavior for this surface.
- Long names, long posts, dense metadata, image/video failures, and permissions do not break the layout.
- New-user and returning-user behavior are both considered when relevant.
- Destructive, public, or moderation-related actions have confirmation and consequence copy.

### Visual And Component Quality

- Uses existing design-system tokens and components before inventing new styling.
- Has a coherent visual direction and avoids generic AI-template aesthetics; see `visual-craft.md`.
- Maintains clear hierarchy between content, metadata, actions, and system feedback.
- Mobile/native surfaces respect thumb reach, keyboard, safe area, orientation, text scaling, and bottom-sheet behavior.
- React/other Web surfaces collapse secondary panels before harming core content readability.
- Mini-app, terminal/CLI/TUI, Electron/desktop/TV, composite-host, and other clients apply their owner-specific host, input, geometry, fallback, bridge, and rendered-evidence criteria; absence from the Web/mobile examples is not `not-applicable` proof.
- Text fits in buttons, tabs, cards, sidebars, and compact controls.

### Trust, Safety, And AI

- Report, hide, mute/block, sensitive, under-review, rejected, limited, and appeal/recovery states exist where relevant.
- AI-generated, AI-assisted, human-authored, cited, edited, or community-verified states are distinguishable when trust depends on them.
- AI output can be edited, retried, saved, shared, reported, or discarded as appropriate.
- Moderation status communicates what happened, why it happened, and what the user can do next.

### Accessibility And Responsiveness

- Interactive controls have labels, keyboard/focus states where applicable, and enough hit area.
- Color contrast, disabled state, error state, and loading state remain readable.
- The design works across the supported sizes, host modes, input/capability modes, and adaptation matrix of every affected rendered layer.
- Motion or animation does not block task completion and can degrade gracefully.

## Anti-Patterns

Use `design-execution-checklist.md` for product-density and copy guardrails, and `scenario-community-patterns.md` for per-surface Avoid rules. Do not duplicate those lists here; during review, cite the specific violated rule and the concrete screen evidence.
