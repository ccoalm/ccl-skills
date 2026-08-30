# Behavioral And Aesthetic Judgment

Use this lens when a design decision depends on attention, perceived control, uncertainty, trust, motivation, fatigue, or visual character. It turns those abstractions into observable hypotheses; it does not replace requirements, interaction mechanics, accessibility, or runtime evidence.

For theory and evidence boundaries, use `external-ui-ux-quality-benchmarks.md`. For concrete state transitions, error/recovery and feedback, use `interaction-design-patterns.md`. For visual craft, use `visual-craft.md`. Use `tokens-and-components.md` for token, component, theme and platform-component mechanics; use this reference for behavioral and aesthetic judgment.

## Judgment method

Write each important judgment in five parts:

1. **Observation**: what the current source, render, task trace, metric, or user behavior shows.
2. **Risk**: the concrete search, recall, switching, error, uncertainty, trust, fatigue, or consequence burden.
3. **Hypothesis**: the layout, state, copy, interaction, or visual change expected to reduce that burden.
4. **Evidence**: the task, state, render, accessibility check, comparison, or metric that can falsify the hypothesis.
5. **Boundary**: target users/tasks/platforms covered, unknowns, and when to retest.

Example:

> Observation: returning operators open three panels to recover the active item after an error. Risk: they lose task context and repeat work. Hypothesis: keep the active item and progress visible while the error is repaired locally. Evidence: in the failed-and-retry task, draft, selection and progress survive without reopening panels. Boundary: verified for keyboard and pointer flows at the tested sizes; mobile remains pending.

Avoid “intuitive,” “clean,” “delightful,” “lower cognitive load,” or “obvious” as standalone criteria. Name what users can find, understand, do, recover, or distinguish.

## Interaction judgment

Use the canonical loop in `interaction-design-patterns.md`: Discover → Inspect → Act → Confirm → Return.

| Stage | Judgment question | Typical evidence |
| --- | --- | --- |
| Discover | Can target users locate the relevant entry from their starting context without irrelevant competition? | Entry task, attention order, navigation/focus path |
| Inspect | Is the context needed for a safe decision visible at the decision point? | State/source/scope/consequence checks, hidden-context errors |
| Act | Does prominence match the user's current intent and consequence rather than business preference alone? | Primary-action selection, misclicks, task completion |
| Confirm | Does feedback/interruption strength match finality, recovery and retry safety? | Event→state→feedback trace, duplicate/retry scenarios |
| Return | Are prior context, progress, draft, selection and next action preserved? | Modal/route/error/reload recovery tasks |

Rules:

- Do not give equal visual weight to actions with different relevance or consequence.
- Reduce active option search for the current decision, while keeping review/edit/recovery controls reachable when needed.
- Preserve current object, mode, filters, progress and return context across drawers, dialogs, routes, uploads and generation when the task depends on them.
- Choose constraint, inline repair, preview, undo, confirmation, retry or restore from consequence and reversibility. Added friction requires a named protective job.
- Give every asynchronous action acknowledged, pending, final and recovery semantics. The exact timing bar comes from the product/runtime need, not a remembered universal number.

## Behavioral variables

Do not assume one universal user behavior. Select variables from current evidence and test the target segment.

| Variable | Risk to inspect | Design response to test |
| --- | --- | --- |
| Scan/search | Users may stop at the first plausible option or miss a low-salience control | Stronger grouping/signifier, reduced competing actions, task-based findability check |
| Recall | Users must remember hidden state, values or prior steps | Keep context visible, provide history/summary, preserve return state |
| Repetition/fatigue | Repeated review or entry increases slips and abandonment | Stable placement/order, compact density, progress, shortcuts, safe batch/recovery behavior |
| Uncertainty | Users cannot tell whether work started, finished, failed or is safe to retry | Explicit state, timestamp/progress, idempotency/retry copy and support path |
| Agency | Users cannot edit, cancel, undo, retry, leave or correct an outcome | Add the consequence-appropriate control and verify it works |
| Trust | Source, permission, automation, review status or consequence is unclear | Put the relevant provenance/status/scope near the decision; avoid unverifiable assurance |
| Motivation | The surface has no meaningful progress, result or return value | Show real progress/outcome and a useful next step; do not manufacture engagement cues |
| Social influence | Counts/badges may distort relevance or create false authority | Explain meaning, prevent fake precision, compare task decisions with/without the cue |

Instructions and help can be necessary. The defect is requiring users to read hidden or lengthy prose to discover a primary operation, not the mere presence of guidance. Prefer concise, contextual instructions and test whether users can complete the task; redesign a control when explanation is compensating for ambiguous semantics.

Consistency is a strong default because it supports transfer and stable expectations. Deviate only when a concrete task/accessibility gain outweighs that transfer cost, and record the reason. A claimed clarity gain never overrides semantic correctness, accessibility, trust/safety, or specified design-system states.

## Aesthetic judgment

Aesthetic choices should reinforce task, hierarchy and product character.

- **Attention order**: name first, second and background elements. Verify the rendered hierarchy with realistic content and relevant states.
- **Density**: choose from task frequency, content volume, error cost and input mode. Consumer breathing room and operational compactness are starting hypotheses, not product-category laws.
- **Rhythm**: repeated spacing, alignment, type roles, state treatment and motion should create a learnable visual grammar.
- **Contrast and material**: color, border, shadow, texture, blur and elevation need a hierarchy, grouping, state or brand job. Decoration cannot repair weak structure.
- **Mood**: describe the intended quality in task terms such as calm review, focused creation, safe consent or lively discovery, then map it to observable visual decisions.
- **Content dignity**: give primary content enough space and legibility for its task; avoid both cramped consumer content and oversized empty operational shells.
- **Delight**: use it for meaningful completion, onboarding or recovery only when it does not obscure status, consequence, accessibility or reduced-motion needs.

If no current product source exists, compare two or three compact visual directions. Hold structure and content constant where possible, state the decision variables, and select against the task/brand criteria rather than personal taste.

## Trust and ethical boundaries

- Do not use urgency, social proof, streaks, notifications, defaults or visual weight to hide cost, permission, risk, alternatives or exit.
- High-impact actions show consequence before execution and actual outcome afterward.
- AI/automation output distinguishes draft/candidate, reviewed, accepted and applied states when users may otherwise over-trust it.
- Popularity, verification, quality and authority are different claims; labels and metrics must not imply one from another.
- Protective friction remains when it prevents irreversible, public, financial, privacy or safety harm. Nuisance friction is removed only after that distinction is made.

## Acceptance

Use realistic content and the representative task from `delivery-contract.md`.

- Target users can state the screen's purpose, current state and relevant next action without guessing from hidden context.
- New and returning users can complete or resume the primary task under the tested conditions.
- Visual prominence matches task relevance and consequence; secondary and exception actions remain findable without competing equally.
- The state-action-feedback mapping remains understandable in loading, failure, permission, offline/degraded, partial and recovery states that apply.
- Layout, copy, motion and feedback preserve agency and trust rather than merely looking polished.
- The chosen visual direction is coherent across representative content, themes, sizes and states, and follows the product/design-system source where specified.
- Findings name verifier, candidate, evidence layer and boundary. A reviewer feeling, single render or heuristic pass remains hypothesis-grade until the required evidence closes it.
