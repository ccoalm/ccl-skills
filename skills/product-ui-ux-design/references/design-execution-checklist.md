# Design Execution Router

For runtime work, choose one delivery-depth profile, then add every work-mode and risk lens whose trigger is present. Load the union of their references; one lens never cancels another. Delivery depth is ordered `systemic redesign → new/reshaped screen → narrow visible change → copy-only`. Every work mode below is orthogonal to delivery depth and to the other modes: a source-led systemic redesign or a shared-system redesign loads both sets; a narrow implementation review loads design-to-code plus audit/review; a code-evidence audit with naming drift loads source/code evidence plus naming/version synchronization; a same-stack theme audit loads same-stack multi-project even though no stacks differ; a cross-stack redesign loads its delivery profile plus multi-stack. A source-only audit with no requested runtime slice may omit delivery depth and stop at the source-only boundary in `delivery-contract.md`.

The core workflow and state taxonomy are already in the skill entrypoint. This router is conditional context, not an always-loaded prerequisite. A runtime-visible task can enter `delivery-contract.md` directly; an unambiguous common route can enter its named reference directly. Load this router when delivery depth must be composed with specialized work-mode, platform, risk, or evidence lenses. No focused reference is always loaded. Extra context must earn its cost by changing a decision, owner, evidence layer, or acceptance criterion.

## Delivery-depth profiles

| Profile | Use when | Required references | Deliverable |
| --- | --- | --- | --- |
| Copy-only | Same component, rendering slot, or output field and behavior; no hierarchy, layout, state, interaction, navigation, or component-semantics change | `delivery-contract.md` copy-only path | Lightweight owner/evidence record plus extent/localization check |
| Narrow visible change | Local polish, state/copy fix, or bounded review without structural redesign | `delivery-contract.md`; one focused craft/interaction reference | Observation → risk → change → evidence |
| New or reshaped screen | New screen or material change to grouping, hierarchy, navigation, component semantics, or visual direction | `delivery-contract.md`, `design-intake-and-acceptance.md`, `behavioral-aesthetic-logic.md`, `visual-craft.md` | Context brief, state/flow, direction, criteria, owner handoff |
| Systemic redesign | Multiple surfaces, declared redesign/restyle, continuation from a redesigned surface, or a `design-judgment`/`mixed` rejected-surface recovery | New/reshaped set plus `layout-recipes-and-screenshot-acceptance.md`, relevant platform reference, and `ui-ux-audit.md` | Per-surface records following the canonical five-step order, cross-surface consistency, rendered verdict loop |

## Composable work-mode lenses

Select zero or more and union their required references with the delivery-depth set.

| Work mode | Use when | Required references | Deliverable |
| --- | --- | --- | --- |
| Shared system | Tokens, components, themes, state catalogs, or packages consumed by more than one surface/stack | `delivery-contract.md`, `tokens-and-components.md`, `design-system-source-of-truth.md`; compose with same-stack multi-project or multi-stack when their triggers apply | Consumer inventory, semantic contract, migration and evidence matrix |
| Source/code evidence | Auditing, classifying, or refreshing rules from Figma, code, screenshots, or another source corpus; inspecting local frontend implementation evidence, reusable primitives, source boundaries, or build/launch scripts | `source-map.md`, `frontend-code-evidence-map.md`, and [`two-source-extraction-pattern.md`](../../skill-extraction-workflow/references/two-source-extraction-pattern.md) when design+code are paired | Source classification, implementation-evidence map, coverage, contradictions, keep/merge/discard decisions |
| Design-to-code | Applying design decisions to client code, mapping a source/component/token to implementation, or choosing implementation primitives for a visible slice | `ui-ux-design-development.md` plus the affected client owner skill | Source-to-target translation, primitive/component mapping, state/adaptation implementation notes, and owner evidence plan |
| Audit/review | UI/UX audit, design walkthrough or acceptance, implementation review, code/design comparison, or usability, accessibility, responsive QA at any delivery depth | `ui-ux-audit.md`; add the triggered craft, interaction, platform, and external-authority lenses below | Findings ordered by user impact with evidence, correction, strengths, and scope limits |
| Naming/version synchronization | Figma↔code naming drift, deciding which `Foo`/`FooV2` artifact is active, retiring an in-flight version stamp, or maintaining the design-code terminology glossary | `design-impl-naming-and-versioning.md` | Active implementation/source resolution, migration/retirement decision, glossary evidence and recheck trigger |
| Same-stack multi-project | Multiple subprojects on the same end/stack share a brand or theme, need a shared theme module, or may drift to vendor defaults | `multi-project-token-consistency.md`; add multi-stack only if the same framework also spans different ends | Subproject inventory, canonical token/theme source, import/drift audit, migration and evidence matrix |
| Multi-stack | A feature or design system spans multiple client stacks or a composite host; a stack/UI-kit outlier; native-shell↔web-content ownership; or the same framework spans different ends | `multi-stack-strategy.md`; also load `multi-project-token-consistency.md` when the same framework spans different ends and shares brand/theme infrastructure | Per-stack and per-layer owner/consumer map, surface contract, divergence/retirement decision, and evidence matrix |

Do not downgrade a declared redesign to narrow polish because the code diff is small. Do not upgrade copy-only work because the surrounding screen is complex; use the trigger actually changed.

## Risk lenses

Load a lens only when its trigger is present.

| Trigger | Reference |
| --- | --- |
| Web/desktop layout, workbench/auth/admin surface, responsive container, browser input | `platform-web-desktop-patterns.md` |
| Mobile/native/App/app-hosted/H5/WebView, safe area, keyboard, orientation, text scale, gesture | `platform-mobile-patterns.md` |
| Mini-program host capability or package/platform convention | Keep design acceptance in `delivery-contract.md`; route host mechanics to `miniapp-product-dev` |
| Terminal/TUI grid, ANSI/color fallback, PTY, resize, scrollback, selection | Keep design acceptance in `delivery-contract.md`; route mechanics to `terminal-cli-dev` |
| Operational/admin/moderation/AI-review workspace; capture, upload/import, queue, progress monitoring, assignment/ownership, exception handling, or quality-control workflow | `operational-processing-workflows.md` |
| Trust-sensitive AI, finance/data, permission, provenance/citation, upload, analytics, moderation decision, long-running workflow, or instrumentation | `trust-sensitive-ai-and-data-patterns.md` |
| Analytics, charts, comparison, drill-down, metric explanation, creator/topic health, retention, or AI-quality metric | `analytics-visualization-interactions.md` |
| Complex creation, upload/import, AI draft extraction, structured editing, matching/manual correction, preview/publish/export flow | `complex-creation-interactions.md` |
| Resource/cloud-drive inventory, upload, batch action, media/template/content-pack center, saved prompt, knowledge source, sharing, governance, or lifecycle | `resource-management-interactions.md` |
| Community/social/feed/creator/topic/profile/notification/moderation/AI-social product surface | `scenario-community-patterns.md` or the matching section of `product-surface-patterns.md` |
| Detailed interaction, feedback strength, error/recovery, gesture, generated state, motion, or shortcut behavior | `interaction-design-patterns.md` |
| Attention, motivation, perceived effort, trust psychology, habit loop, or behavioral/aesthetic judgment | `behavioral-aesthetic-logic.md` |
| Visual polish, brand feel, anti-slop, typography/hierarchy, iconography, or material treatment | `visual-craft.md` |
| Layout recipe, component density, workbench structure, empty/loading/error geometry, or screenshot/render acceptance | `layout-recipes-and-screenshot-acceptance.md` |
| Design-system source authority, third-party mirror detection, brand-token ownership, or wrong design-source comments in code/theme files | `design-system-source-of-truth.md` |
| Generic surface/loop taxonomy, account/settings, decision/review, AI-assisted or workflow-extension pattern, or no focused scenario lens fits | `product-surface-patterns.md` |
| External theory, WCAG, platform recommendation, benchmark claim | `external-ui-ux-quality-benchmarks.md` |
| Launch/post-launch measurement and iteration | `product-lifecycle-acceptance-and-iteration.md` |

## Decision pass

Before handing off implementation, confirm that the design record answers these questions:

1. Who is doing which representative task, under what constraints?
2. What observation creates which user/task risk?
3. What information hierarchy, flow, state, and recovery behavior addresses that risk?
4. Which details are specified by a current source, which are design freedom, and which change product behavior?
5. What happens at narrow/large sizes, long content, alternate input, text scaling, and relevant accessibility states?
6. Which criterion is automatic, rendered/device, independent design judgment, user-task evidence, or production evidence?
7. Which producer, test, and client owners must return which evidence before a verdict?

Use `delivery-contract.md` for the field schema and completion states. Do not restate those fields here.

## Design quality checks

Apply the checks relevant to the chosen delivery depth and every triggered lens:

- The most prominent content/action matches the representative task and consequence.
- Required context, current state, available actions, and result/recovery remain visible when needed. For each applicable risk, decide what users may repeat, misclick, wait for, abandon, undo, retry, cancel, or recover after interruption, and provide visible state or control; do not force users to remember hidden state across route or modal transitions.
- States use clear signifiers and event → state → feedback mappings. Animation has a functional purpose and a reduced-motion equivalent.
- Friction follows consequence. Routine work is not interrupted by defensive confirmation; high-consequence action is not hidden behind transient feedback.
- The layout adapts from content/container constraints and survives long text, text scaling, intermediate widths, and relevant input modes.
- Tokens and components express semantic roles and full states. Existing libraries do not excuse weak hierarchy, missing states, or inaccessible behavior.
- Examples, stories, catalogs, and design-system docs used as implementation sources conform to the same token, responsive, state, and accessibility rules.
- Each deterministic gate names its coverage boundary; each conclusion stops at its highest verified evidence rung.

## Closeout

The design owner records criterion results and the verdict defined in `delivery-contract.md`. A source-level review, heuristic pass, automated check, or screenshot cannot silently stand in for a missing rendered, accessibility, independent-design, user-task, or production layer.

Report loaded references with their trigger when the task is large enough to persist a design record. This makes context cost and omitted lenses reviewable without forcing every task to load the corpus.
