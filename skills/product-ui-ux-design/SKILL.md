---
name: product-ui-ux-design
description: "页面怎么设计 / 交互怎么做 / 设计走查 / 设计验收 / 页面别扭 / 空状态 / 错误提示 / UI polish → own product UI/UX decisions: layout, interaction, visual craft, states, accessibility, design-system consistency, and launch acceptance."
---

# Product UI/UX Design Skill

Own product-facing design decisions and acceptance across the full capability surface: user/task fit, information architecture, visual system and layout rhythm, component semantics, interaction flows, behavioral and aesthetic logic, micro-feedback, empty/error/loading states, accessibility, perceived performance, adaptation, launch acceptance, iteration signals, AI-assistant patterns, trust-sensitive data patterns, source-selection guardrails, and evidence-backed design verdicts.

Use this skill for product surfaces across web, app, mini-program, desktop, and terminal/TUI. Product category and source provenance do not define the target design. A component library is rendering vocabulary, not a substitute for deciding hierarchy, state completeness, interaction quality, trust, or visual craft.

## Owner boundary

- This skill owns design intent, design hypotheses, acceptance criteria, and the final design verdict.
- `testing-strategy` owns assertion-layer and rendered-evidence-layer selection, automated proof, and test sufficiency.
- Each changed or claim-bearing backend/config/content/inference owner owns its producer artifact or version identity, execution environment, and API/event/log/output runtime facts.
- The complete affected client-owner set owns implementation and runtime evidence: React web → `web-react-dev`; Vue/Svelte/static/vendor/other web → its installed owner or fail-closed project-convention lookup; native mobile/host → `app-cross-platform-dev`; mini-app → `miniapp-product-dev`; terminal/CLI/TUI → `terminal-cli-dev`; Electron/desktop/TV shell → its installed owner or the same lookup. Composite hosts keep separate content and shell members.
- `feature-risk-router` owns risk grading for destructive, public, financial, permission, privacy, legal/compliance, or other high-impact changes.
- `product-rd-workflow` owns a cross-stage product delivery lifecycle; a narrow UI/UX task can use this skill directly.
- `skill-extraction-workflow` owns changes to this skill, its routing, rules, and references.

Do not use this skill as the implementation owner for client code or as the test-layer owner. Do not let a stack skill decide product hierarchy or mark a triggered redesign accepted by itself.

## Source discipline

Classify design evidence before using it:

- **Current product source**: approved current design, production component/token contract, or current rendered behavior.
- **Candidate source**: a draft, exploration, or proposed design; treat it as a hypothesis until accepted.
- **Historical/reference-only**: copies, archived/deprecated files, reports/slides, or superseded screens; never promote these directly into executable rules.
- **Partial source**: a current file with incomplete or todo areas; use only for the states it actually specifies.

When sources conflict, keep the stronger/current rule, merge compatible variants, and discard stale, duplicated, or product-specific details. Record which source specifies a state and which parts remain design freedom. If source access is unavailable, use the distilled references and state the evidence limit; normal design work need not stop.

For a state or treatment explicitly specified by the current authoritative source, acceptance is conformance rather than author confirmation: record `matches source` or the named divergence. Correct code drift to the source. If the treatment is intentionally changed, update its owning design source and obtain the source's required review before code follows; when that source cannot be edited, create an explicitly authorized replacement decision as the new reviewable source artifact before code. A chat approval, code comment, or silent code divergence is not a replacement design source. What the source leaves unspecified remains design freedom.

Public theory and standards have different authority. Use `references/external-ui-ux-quality-benchmarks.md` to distinguish standards, stable mechanisms, contextual empirical findings, informative guidance, vendor conventions, and local heuristics. Do not turn a named law, vendor recommendation, or remembered number into a cross-platform acceptance rule.

## Core workflow

### 1. Build the context brief

Resolve only what changes the decision:

- target users, representative task, goal, prior knowledge, and use environment;
- product/surface type, platform/runtime, delivery stage, density, and affected consumers;
- current evidence, explicit constraints, behavior that must remain, and risk/consequence;
- one delivery depth—copy-only, narrow visible change, new/reshaped screen, or systemic redesign—and every orthogonal work mode that applies: shared system, source/code evidence, design-to-code, audit/review, naming/version synchronization, same-stack multi-project, and multi-stack.

Do not interrogate the user for facts already available in the task, repository, design source, or current runtime. Treat stakeholder or reviewer preferences that lack user/task evidence as assumptions, not user needs.

### 2. Turn observations into design hypotheses

For each important decision, record:

`observation → user/task risk → design hypothesis → acceptance evidence → boundary/retest condition`

Cover the relevant layers:

- structure: information groups, hierarchy, primary/secondary actions, navigation, progressive disclosure, and return context;
- interaction: entry, action, feedback, pending/final state, cancellation, undo/retry, and interruption recovery;
- behavior: duplicate action, optimistic reconciliation, offline/degraded/partial outcomes, permissions, and stale state;
- visual craft: focal point, density, rhythm, typography, color weight, surface hierarchy, component semantics, and coherent direction;
- accessibility/adaptation: semantics, keyboard/focus/touch, target sizes by platform, text scale/localization, motion preference, viewport/container changes, safe area and input mode;
- trust: source, scope, permission, automation status, consequence, review state, and support/audit context where relevant.

Prefer visible signifiers and state-action-feedback mappings over abstract claims such as “intuitive” or “lower cognitive load.” Reduce a concrete recall, search, switching, uncertainty, or error burden and name how it will be observed.

Name controls, states, actions, focus return, failure oracle, scenarios, and
platform exceptions. For an open reversible parameter, choose a testable
provisional value/range/rule; label it a hypothesis with replacement evidence
and fallback. Defer only if irreversible/high-consequence or authority is
missing. Never universalize, omit, leave placeholders, or substitute an owner.

### 3. Run the design-test-producer/client contract

For any runtime-visible change, load and follow `references/delivery-contract.md`. A runtime-visible task enters `references/delivery-contract.md` directly; the specialized router is not a prerequisite to that canonical path. A valid low-risk `copy-only` slice uses that contract's lightweight copy record and lightweight Phase 0; every other visible slice uses the full record. Its canonical execution sequence is:

1. Design brief.
2. Test selection Phase 0.
3. Producer/client execution.
4. Test execution/sufficiency Phase 1.
5. Design verdict.

The legacy **implementation-owner checkpoint** means the applicable brief,
Phase 0, and complete changed-producer/affected-client owner set. The legacy
**cross-stack page-slice gate** means the contract's deeper
new/reshaped/systemic slice. Each redesigned screen remains a full IA/behavior
slice; only a pure token/component sweep may batch. Link the contract instead
of copying its fields.

Before the first implementation edit, the applicable draft must contain the design-owned inputs defined by the contract. `testing-strategy` then selects verifier, assertion/rendered layers and oracles; every changed producer and affected client-owner member confirms its local target and evidence plan. The producer records immutable artifact/config/prompt/model identity and API/event/output facts; each client member records platform facts and which producer version it exercised. Testing Phase 1 cites the complete design/test/producer/client record and candidate-binding sets to decide criterion results and aggregate sufficiency before the design verdict. If the record was missed, stop, record the process defect, reconstruct it from pre-change evidence, and audit the existing diff before further edits or handoff; a retroactive brief cannot bless the implementation. This order is intentional and is not a circular wait.

### 4. Evaluate evidence at its real level

Use `references/delivery-contract.md`'s claim-matched evidence dimensions: no global ladder or cross-dimension substitution; verify each required dimension.

- Static source, a story, a test file, or a token reference proves only that the artifact exists.
- A command pass proves only its declared oracle and target.
- A screenshot proves only the captured state and size.
- Automated accessibility checks do not replace keyboard/assistive-technology checks or standards conformance.
- User evaluation does not replace standards conformance, and one participant does not represent a population.
- Heuristic review produces risks and hypotheses; it is not final acceptance.

Every deterministic design gate states its coverage boundary: what it detects, paths/states scanned, known false negatives, and remaining manual or runtime checks.

### 5. Issue the verdict and next state

Record criterion-level results and bind every changed or claim-bearing design, test, producer, and client member to an immutable commit/tree, artifact digest, or base-plus-dirty-bundle identifier; a branch name is only a mutable planning reference, and a dirty execution cannot be relabeled `commit:HEAD`. Follow the contract's verdict-owner and verdict/next-state matrix. Author acceptance is limited to its deterministic low-risk exception; redesign, shared direction, brand/high-risk work, judgment-bearing criteria, and prior `design-judgment`/`mixed` rejection require the user or a named independent design owner.

Missing evidence or silence is `pending`, never acceptance. Required runtime evidence that is planned or unavailable leaves `pre-runtime-test-ready` or `blocked`. A `deterministic-conformance` rejection may take a criterion-targeted fix with a new binding and rerun; a `design-judgment`/`mixed` rejection stays `design-rejected` until a revised target is rendered and independently accepted. A second design-judgment rejection stops implementation churn and returns direction to the user/design owner.

## Hard design rules

### Preserve behavior unless change is declared

Treat the current implementation as current state, not automatically as the design spec. Classify each independent difference:

- `defect-fix`: incorrect or misleading behavior/rendering; fix it.
- `design-freedom`: visual language, layout grouping, component treatment, and unspecified states; improve without pretending the source required it.
- `behavior-change`: new/removed controls, changed routes, write flows, semantics, or return behavior; declare the product/implementation/test/risk owner and evidence.

Split mixed changes. If one point cannot be split, `behavior-change` outranks `defect-fix`, which outranks `design-freedom`.

### Specify the full interaction state, not only the happy render

Map applicable initial, empty, loading/pending, success, failure, retry, disabled, permission, offline/degraded, partial, long-content, and interruption/recovery states. Preserve draft, focus, selection, scroll, and media state when transient overlays can avoid remounting a stateful workspace. Verify preservation at runtime.

An optimistic UI must reconcile to authoritative server state. Distinguish authoritative rejection, confirmed-but-canonicalized result, indeterminate timeout, offline queue, conflict/supersession, and partial success. Never leave a stale optimistic value displayed as success.

### Match friction and feedback to consequence

Prevent invalid states where practical. Prefer constraint, local validation, preview, undo, retry, restore, or reversible action before adding confirmation everywhere. Reserve interruption for consequences that justify it. Choose one primary error/status carrier by scope, recovery path, durability/finality, and retry safety.

High-risk flows name whether an action happened, whether retry is safe, what remains usable, and what support/audit identifier or next action exists. AI/automation surfaces distinguish candidate, draft, reviewed, accepted, rejected, and applied states when trust depends on them.

### Design for actual available space and input

Use content, container/window size, text scale, input capability, and user preferences rather than device-name breakpoints alone. Test between breakpoints, not only at three polished screenshots. Components may adapt to their container even when the global viewport is unchanged.

Platform values remain platform-scoped. Web WCAG criteria, Apple guidance, Android guidance, mini-program host conventions, desktop conventions, and terminal geometry are not interchangeable constants.

### Make design-system claims executable

Use semantic tokens and component APIs for stable decisions, including accessibility obligations and state variants. A token file, component library, story catalog, or design-system README is not proof of visual consistency. Representative components, examples, docs, and stories must pass the same theme, responsive, state, and accessibility checks expected of production.

When one slice reveals a repeatable defect class, inventory sibling consumers/states and sweep detection across them. Text/source classes may use grep or static analysis; render classes such as overflow, clipping, reversed drawing, state geometry, or encoding artifacts require re-rendering the sibling set—grep-only cannot close them. Apply the fix only to in-scope or already-migrated surfaces; record the rest with an owner instead of silently widening scope. Repeated discovery of the same class across review rounds is evidence that the prior sweep was incomplete.

### Keep evidence reviewable and safe

Persist before/after renders, traces, DOM/cell-grid dumps, recordings, or task evidence in review-accessible locations. Bind command, the complete immutable candidate-binding set, target, state, and dimension. Use sanitized/test accounts and redact credentials, tokens, personal data, customer data, and private paths. Build/lint summaries and hand-authored transcripts are not rendered evidence.

## Reference loading

Load `references/design-execution-checklist.md` only when the task needs one or more specialized work-mode, platform, risk, or evidence references whose route is not already unambiguous below. Do not load the router solely to reach `references/delivery-contract.md` or another unambiguous common route. When the router applies, select one delivery-depth profile for runtime work, then add every triggered work-mode and risk lens and load the union of their required references. A source-only audit may enter its named reference directly or use only its work mode. Record why each extra reference is loaded. Do not load the entire reference corpus.

Common routes:

- Runtime handoff or acceptance: `references/delivery-contract.md`.
- Source provenance or Figma/code classification: `references/source-map.md`.
- Theory, standards, vendor conventions, or evidence claims: `references/external-ui-ux-quality-benchmarks.md`.
- Behavioral, aesthetic, trust, and friction judgment: `references/behavioral-aesthetic-logic.md` and `references/interaction-design-patterns.md`.
- Visual hierarchy and craft: `references/visual-craft.md`.
- Responsive layout and rendered acceptance: `references/layout-recipes-and-screenshot-acceptance.md` plus the relevant platform reference.
- Tokens/components or shared design system: `references/tokens-and-components.md`, `references/design-system-source-of-truth.md`, and `references/multi-project-token-consistency.md` only when cross-project consistency is in scope.
- Product lifecycle or post-launch iteration: `references/product-lifecycle-acceptance-and-iteration.md`.

When updating this skill, use `skill-extraction-workflow`, preserve a source register and obligation map, establish a falsifiable baseline before behavior changes, and run the repository's full validation and dual-track review gates.

## Output

Lead with the decision or finding. For a narrow or single-surface task, default
to at most four flat sections: decision; task-specific state/interaction model;
observable acceptance; evidence boundary and next owner. Use a compact table or
bullets. Add nested sections only for another surface or materially different
state.

The shared delivery record is an evidence store, not a response template. Link
or name it instead of repeating its matrices and role fields. State an evidence
limit, source conflict, platform distinction, or owner handoff once, at the
point where it changes a decision. Prefer concrete labels, state names, actions,
failure conditions, and runnable scenarios over process narration. Remove any
paragraph that changes no decision, criterion, owner, evidence level, or risk.
Label proposals, source presence, measured validation, production evidence, and
user/owner authorization separately without restating the same boundary.
