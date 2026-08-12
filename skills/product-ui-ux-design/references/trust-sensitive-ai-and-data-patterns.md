# Trust-Sensitive AI And Data Patterns

Use this reference when designing or implementing product surfaces that include AI answers, uploaded files, citations, analytics, financial-like data, moderation decisions, user permissions, or long-running data workflows.

This file extracts reusable behavior and engineering-quality patterns from trust-sensitive AI/data frontends. It does not make the skill a finance-product skill.

Important: these frontends are **not** visual-design sources for this skill. Do not absorb their page composition, visual polish, information architecture, density, copy tone, or interaction taste as positive UI/UX examples. Use them only where the implementation shows reusable mechanics for trust-sensitive AI/data work, instrumentation, recoverability, permissions, upload/task state, and launch checks.

## Source Evidence

Finance frontend sources inspected and classified:

- Trust-sensitive AI frontend source: usable behavior evidence for tests, upload progress, document readers, reference panels, analytics hooks, API request instrumentation, global error handling, and feedback collection. Not a visual/UI benchmark.
- Operations frontend source: usable behavior evidence for permission context, dense data tables, truncated cell portal tooltip, CSV utilities, notifications, and build-mode separation. Not a consumer UI benchmark.
- Typed Vue frontend source: usable engineering evidence for typed build, Element Plus, Pinia, and typed API/client structure. Not a design source.
- Marketing-site frontend source: weak engineering evidence for build/lint/start/push flow and localized pages. Not a visual source.

## Patterns To Absorb

### Evidence And Provenance

- AI answers, data summaries, and document-derived content should expose source, citation, reference item, file, timestamp, or data scope when user trust depends on it.
- Reference panels, drawers, and preview readers are better than hiding sources in a generic tooltip.
- If content is generated from uploaded or selected material, preserve the selected source/context in the UI after generation.
- Community translation: AI-generated post drafts, summaries, recommendations, and moderation explanations should show source/context and editable status.

### AI Chat Trust Patterns

- **Disclaimer placement matters more than disclaimer copy** (NN/g research on AI chatbots discouraging error-checking, 2025): generic footer or system-prompt-area disclaimers ("AI can make mistakes, please verify") scroll out of view after a few exchanges and do not measurably change user error-checking behavior. Place the disclaimer adjacent to the input box (visible whenever the user composes a new message) or pinned to the response area, not in chrome that scrolls away. Pair the disclaimer with a specific user action ("Double-check before applying to high-stakes decisions") rather than abstract warning copy. Repeat the disclaimer during onboarding, not only on first message. Audience-scoped exception: in power-user / professional / internal-tool surfaces (engineering Copilot, ops console, analyst workbench) a permanently sticky disclaimer becomes warning fatigue and consumes prime workspace — there, allow a compact / dismissible / org-managed disclaimer state and instead surface risk inline on uncertain or high-stakes outputs. Consumer / first-time-user / high-stakes-decision surfaces remain the default-sticky case.
- **Source citations must be verifiable, not decorative**. Style citations distinctly from main response text (different typographic weight or container), place each citation adjacent to the specific claim it supports rather than only at the end of the answer, use meaningful link labels (page title, section heading) instead of generic "Source" / "[1]", deep-link to the relevant passage when the source supports it, and surface the actual quoted text in a hover/preview/expanded reader instead of forcing the user to leave the chat to verify. Set expectation explicitly that "sources may not always link to accurate information" — citation presence is not citation correctness, and well-formatted citations to fabricated or wrong-passage URLs are a common failure mode.
- **Step-by-step "thinking" or chain-of-thought displays imply certainty the model does not have**. NN/g advises against rendering visible reasoning as a primary trust signal because users read the visible structure as evidence of correctness. If a thinking / expanded-reasoning panel is shown (for transparency or debug), default it collapsed, label it as model self-report not verified reasoning, and do not promote it to the same visual weight as the answer. Confidence scores stated by the model itself are similarly unreliable as trust signals and should not be styled as authoritative percentages.
- **Promote critical-thinking follow-up prompts alongside regenerate/continue, contextually**. After a substantive answer, surface affordances like "How certain are you of this?", "What might be wrong with this answer?", "Show me the sources you used", "What did you not consider?" alongside (not replacing) regenerate / continue. This converts a one-way oracle into a checkable exchange and creates an in-product habit of verification rather than putting all the verification load on disclaimer copy. Trigger them contextually rather than as always-on UI to avoid nagging professional users who already have their own review workflow: surface them when the answer has low confidence / no citations / high-impact domain, during first-run onboarding, or behind an overflow menu / "/" command surface. Default-on critical-thinking prompts on a power-user surface read as the product distrusting the user.
- **Refusal copy needs transitional wording for benign blocked requests; terse final refusal is correct for adversarial / regulated requests**. For benign out-of-scope or policy-missing situations (user asked something the model can't answer, missing permission, surface scope mismatch), avoid a flat "I can't help with that" — provide (a) what specifically is out of scope, (b) what near-by request would be in scope, (c) a non-AI fallback path (human support, documentation link, alternate tool) when the user genuinely needs help with the original ask. For adversarial requests — jailbreak attempts, prompt-injection probes, policy-evasion phrasing, compliance-regulated refusals (export controls, PII extraction, illegal content) — a terse, final refusal is the right pattern; suggesting "near-by" requests leaks workarounds and reads as the refusal being negotiable. Decision: benign blocked → transitional + redirect; adversarial / regulated → terse + final. Recent research on Abrupt Refusal Secondary Harm (ARSH, arXiv 2025) documents user disengagement and trust loss when *emotionally-loaded* conversations terminate with bare safety boilerplate; that finding applies to the benign-blocked case, not the adversarial one.

### Error Boundary And Recovery

- Use page or feature-level error boundaries for complex AI/data/document surfaces.
- Error UI should include a user-facing message, retry, return/home or fallback action, and development-only detail.
- Global error capture should dedupe repeated messages, track source, component, route, and stack where appropriate.
- Community translation: feed/detail should degrade gracefully; composer/AI workspace should preserve drafts and selected context after recoverable failures.

### Request And Operation Instrumentation

- API requests should record request id, path/module, method, duration, status, backend code, upload metadata, and active operation id when available.
- Auth/session invalid states should reset identity and route users to re-authentication without misleading success.
- Upload, AI generation, publishing, report/moderation, and notification actions should have observable start/success/fail events.
- Do not expose raw backend errors to end users in production unless they are intentionally user-facing.

### Upload And Long Task UX

- Global upload/task progress should support pending, uploading, success, error, retry, cancel, dismiss, collapse, view/open result, file size, and progress.
- Long-running operations need stable task ids and visible persistence outside the initiating button.
- Cancelling in-flight upload or generation should use `AbortController` or equivalent cancellation when possible.
- Closing a task panel with active work should confirm consequence.
- Community translation: media upload, AI generation, video processing, moderation review, and export tasks should stay visible and recoverable.

### Feedback Loops

- Like/dislike alone is too weak for AI quality. Ask for structured reasons and optional text when feedback matters.
- Use feedback reasons that map to product improvements: inaccurate, incomplete, unclear, irrelevant, unsafe, repetitive, too slow, or other.
- Submit state, disabled state, outside-click behavior, and max length should be explicit.
- Community translation: collect feedback on AI suggestions, recommendations, moderation decisions, creator tools, and onboarding prompts.

### Dense Data And Operational Tables

- Dense tables should have stable column width roles, persistent row identity, sort/filter state, pagination, and clear empty states.
- Long cells need truncation detection and portal tooltip/popover that avoids viewport clipping.
- Column configuration and filters are first-class controls for repeated operations.
- Community translation: use this for creator dashboards, moderation queues, analytics, notification logs, and AI task histories, not for relaxed consumer feeds.

### Permission And Capability States

- Permission should be centralized where possible and exposed as loading plus explicit capabilities.
- Hidden or disabled actions should not imply the user can complete work they cannot complete.
- Failed permission load should default to least privilege and offer refresh/retry where appropriate.
- Community translation: publish, comment, DM, upload, export, moderate, report, and community-admin actions need visible capability states.

## Build And Launch Signals

Borrow these from finance frontends when a target project supports them:

- Build variants for development/test/production/local modes.
- Type checking before build for typed frontends.
- Lint, format, unit tests, coverage, and bundle analysis where available.
- Preview command for launch smoke testing.
- Bundle/compression/report scripts for performance-sensitive products.
- Tests around upload, session restore, panel width, request failure, error handling, markdown/media rendering, and long-content behavior.

## What Not To Absorb

- Do not absorb visual layout, visual style, interaction taste, information architecture, product copy, or consumer-facing polish from these projects.
- Do not treat these projects as evidence that a UI is good because it exists in production code.
- Do not copy finance terminology, compliance posture, data schemas, or business workflows into non-finance product UI. When the target product is finance/data, keep terminology intentional, user-safe, and tied to evidence, provenance, permission, and risk states.
- Do not make consumer community feeds feel like operational analytics tools.
- Do not overfit to Vue, React, Element Plus, Radix, shadcn, or Next.js; absorb component semantics and quality gates, not framework-specific architecture.
- Do not treat instrumentation as a substitute for good UX. Users still need clear feedback, recovery, and control.
