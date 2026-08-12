# Behavioral And Aesthetic Logic

Use this reference when a screen needs to feel intuitive, motivating, trustworthy, emotionally appropriate, or visually compelling beyond basic UI correctness.

This file does not replace layout recipes, component rules, accessibility, or product requirements. It adds the why/judgment layer: attention, motivation, perceived effort, confidence, habit loops, visual taste, and emotional fit.

Ownership boundaries:

- Interaction mechanics, the canonical feedback-strength ladder, mobile/web interaction rules, and state-transition detail live in `interaction-design-patterns.md`.
- Concrete visual direction, anti-slop checks, typography, color, motion, and polish rules live in `visual-craft.md`.
- Token, component, theme, and platform component decisions live in `tokens-and-components.md`.
- This file decides why a behavior or aesthetic choice should exist and whether it matches user intent, risk, trust, and product emotion.

## Core Question

Before drawing or coding, answer:

- What does the user want to accomplish or feel in the next 10 seconds?
- What is the user's likely anxiety, doubt, or friction at this moment?
- What should attract attention first, second, and last?
- What action should feel obvious without explanation?
- What should the product make users want to return to?

If these questions cannot be answered, the UI may be well structured but weak.

## Interaction Logic

Use `interaction-design-patterns.md` as the canonical interaction model: Discover -> Inspect -> Act -> Confirm -> Return. This section does not define a second flow. It asks why each stage should exist and whether the chosen mechanics match user intent, risk, trust, and motivation.

Judgment questions for the canonical loop:

- **Discover**: why would the user enter now, and what should catch attention first?
- **Inspect**: what doubt, risk, or curiosity must be resolved before action?
- **Act**: which action should feel primary for this intent and consequence level?
- **Confirm**: does the confirmation or feedback strength match risk? Use the feedback ladder in `interaction-design-patterns.md` for the mechanism.
- **Return**: what context, progress, or motivation helps the user continue or come back?

Rules:

- Do not make all actions equally visible. The primary action should match the user's current intent and risk level.
- Reduce choice when the user is deciding; increase control when the user is reviewing, editing, or correcting.
- For destructive, public, paid, or trust-sensitive actions, judge whether the risk deserves added friction; use `interaction-design-patterns.md` for the concrete confirmation, undo, and feedback mechanism.
- Preserve context after drawers, modals, uploads, generation, and detail views. Losing the user's place creates unnecessary cognitive cost.
- For feedback details and state-transition mechanics, use `interaction-design-patterns.md`; this file only judges whether the chosen feedback matches intent, risk, and trust.

## Behavioral Logic

Design for human behavior, not only information display.

- **Attention**: use hierarchy, grouping, contrast, motion, and whitespace to guide scanning. Do not compete for attention with equal-weight cards.
- **Cognitive load**: show the next meaningful step; progressively reveal advanced controls; avoid dumping all fields before intent is clear.
- **Motivation**: make progress visible. Use draft status, completion, recent activity, reactions, streak-like return cues, or creator feedback only when they match the product's ethics and purpose.
- **Agency**: users should feel they can edit, undo, retry, filter, mute, leave, or correct important outcomes.
- **Trust**: show source, status, timestamp, permission, review state, AI caveat, and consequence where doubt is likely.
- **Habit loop**: entry points, notifications, feed updates, creation prompts, and return states should reinforce a useful loop, not just maximize clicks.
- **Social proof**: counts, badges, replies, followers, and popularity cues should clarify relevance. Do not use them to fake importance or bury new/quiet content.
- **Friction**: remove friction for low-risk repeated actions; add deliberate friction for irreversible, public, sensitive, or costly actions.

## How Users Actually Behave

Design against observed behavior, not the idealized user who reads carefully. These hold across products:

- **Users scan, satisfice, and muddle through.** They skim for the first option that looks reasonable and pick it — not the best one — then keep whatever worked, however badly. Make the *right* choice the most visually prominent one; do not rely on the user comparing options or discovering the "correct" path.
- **Users do not read instructions or prose.** Guidance that must be read to operate the screen has already failed. Make guidance brief, in-context, and unavoidable, and prefer self-evident affordances over explanatory text — if a control needs a sentence to explain it, redesign the control.
- **Goodwill is a depleting reservoir.** Users arrive willing to forgive; every friction point spends that goodwill. It depletes faster when you hide what they came for (price, status, contact), force their input into your format, ask for more than you need, or interrupt with splash/forced-tour/interstitial. It replenishes when you surface what they want up front, save steps, make errors easy to recover from, and own failures plainly. This targets *nuisance* friction only: never strip confirmation, consent, review, recovery, or provenance friction to "save steps" — that protective friction is required by the Friction rule above.
- **Clarity outranks consistency.** Consistency is a default, not a law: when a small inconsistency makes a screen materially clearer, choose clarity, and record the clarity gain. This never overrides the correctness gates — design-system tokens, accessibility, semantic status, trust/safety, high-risk-flow conventions, component semantics, and rendered-evidence — which are correctness, not stylistic consistency.

## Aesthetic Logic

Good visual design is not decoration. It expresses the product's personality and helps the user decide.

- **Mood fit**: choose a tone that supports the surface: lively for discovery, focused for creation, calm for AI assistance, restrained for moderation/settings, serious for trust-sensitive decisions.
- **Rhythm**: repeat spacing, type scale, card treatment, and interaction details so the product feels intentional.
- **Contrast**: create clear focal points. If everything is colorful, raised, bordered, or animated, nothing leads.
- **Material feel**: shadows, borders, glass, texture, blur, and gradients need a role: depth, grouping, brand warmth, or state. Do not add them to compensate for weak structure.
- **Content dignity**: posts, comments, creator identity, media, and AI output should feel cared for. Avoid tiny cramped content in consumer surfaces or oversized empty shells in work surfaces.
- **Delight**: reserve delight for moments that matter: publish success, first useful AI result, meaningful reply, achievement, upload completion, or helpful recovery. Avoid decorative delight during errors, moderation, payment, or permission denial.

## Consumer Community Heuristics

- Discovery surfaces should create curiosity quickly: strong content preview, clear author/topic identity, visible social affordances, and low-friction entry into detail.
- Creation surfaces should reduce blank-page anxiety: prompts, examples, draft recovery, preview, audience visibility, and clear publish consequence.
- Comment/reply surfaces should make conversation feel alive: quoted context, reply target, composer persistence, reactions, and respectful empty states.
- AI surfaces should feel helpful but accountable: visible generation state, editability, source/citation when relevant, retry/regenerate, and clear separation between AI suggestion and user decision.
- Trust/safety surfaces should feel fair and controllable: explain why content is hidden, reported, limited, or under review; provide recovery or appeal where product policy allows.
- Notification surfaces should balance urgency and respect: group related updates, show why the user received it, and make mute/setting controls reachable.

## Design, Development, Test, Acceptance

Use this layer across the whole UI delivery cycle:

- **Design**: state the user's intent, doubt, motivation, trust concern, attention order, and desired mood before choosing layout or components.
- **Frontend development**: preserve the intended judgment in code. Route state, focus, progress, recovery, permission, empty/error, and return-context behavior should match the design checkpoint, not only the component library.
- **Testing**: derive cases from human risk, not just code branches. Test first-use, returning-use, long-content, no-data, partial-data, permission denied, generated/unreviewed, failed/retry, destructive action, and return-from-modal/drawer/upload/generation paths where relevant.
- **Acceptance**: inspect a rendered browser/app surface with realistic content. Verify attention order, obvious next action, risk-matched friction, recovery path, trust cues, mood fit, and whether the screen feels like a product rather than a component demo.

## Acceptance Checks

Before calling a UI good, verify:

- A first-time user can identify the screen's purpose and next action within five seconds.
- A returning user can resume or repeat the main action without re-learning the screen.
- The most visually prominent element matches the user's likely intent and the business priority.
- The screen has one coherent mood; colors, spacing, motion, and copy do not fight each other.
- The interaction adds friction only where risk, trust, or consequence justifies it.
- Empty, loading, error, and success states preserve motivation instead of feeling like dead ends.
- Social, AI, or trust cues are honest and useful, not manipulative decoration.
- The result feels product-specific rather than like a generic component demo.
