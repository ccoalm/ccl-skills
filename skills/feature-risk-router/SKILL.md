---
name: feature-risk-router
description: 风险定级 / 要不要灰度 / 需要哪些 gate / 双人 review / 架构评审 / 安全审计 / 安全评审 / 威胁建模 / security audit / threat model / OWASP / pentest review / risky → classify a feature, fix, or change by risk tags (incl. a security-review gate) and name required design, arch, dev, test, review, security, launch, and rollout gates.
---

# Feature Risk Router

Use this lightweight router before or during product delivery when the required rigor is unclear. It classifies risk and names the gates that must run; it does not replace `product-rd-workflow`, `testing-strategy`, `product-ui-ux-design`, stack-specific development skills, review skills, or release workflows.

**Objective high-risk change-shapes force classification even when the change feels trivial — a low-risk intuition is not a substitute for running the tags.** The "when rigor is unclear" entry is not a licence to skip the router because you judged a change low-risk: the tags below classify well *once you are here*; the failure mode is never arriving because you felt sure. So regardless of that intuition, if the change deletes / backfills / migrates data or is otherwise irreversible, touches authentication / authorization / roles / tenant isolation, handles secrets / credentials / tokens, moves money or billing / quota, alters an external-facing or service-client API contract, changes a trust boundary or an untrusted-input sink, drives a production rollout / flag, or changes a shared deterministic gate / validator / CI harness / merge-readiness or completion-status rule (which can look docs/scripts-only yet decide future merge and completion semantics), run the classification FIRST and only then conclude low-risk if the relevant tags (`write-finality`, `data-migration`, `permission-access`, `security-review`, `api-contract`, `money-quota`, `release-ops`, `shared-gate`, `ai-action`) actually clear. Self-de-escalating one of those change-shapes to "not needed" without running its tag is the miss this prevents.

- Tone and diff size are not classification inputs: a reporter's urgent tone or executive pressure must never escalate a change's tags, and a small diff must never de-escalate them — tags run on the change's objective shape (production impact, frequency, money/data finality, workaround availability, rollback difficulty, verification sufficiency). (The always-on routing layer and `product-rd-workflow` owner-dispatch are the backstops for the case where the router is never invoked at all — this clause governs the case where you are deciding whether it applies.)

## Output Contract

Return a compact routing decision:

- `risk tags`: the relevant tags below.
- `required gates`: skills, checks, or evidence that must run before completion.
- `skippable gates`: checks that can be skipped and why.
- `stop reasons`: decisions or blockers that require user/product/architecture/security confirmation.
- `verification evidence`: concrete commands, screenshots, browser/app/device checks, review artifacts, or docs that should prove completion.

## Risk Tags And Gates

- `visible-ui`: Any visible UI change, including layout, copy, state, interaction, navigation, user-facing error/empty/loading feedback, or operation entry. Require `product-ui-ux-design`, the relevant client skill, and rendered inspection evidence.
- `client-plumbing`: Client request headers, telemetry, storage, API adapters, generated clients, or non-rendered behavior. If no visible surface changes, record `visible surface: no`; require focused tests or contract checks for the changed boundary.
- `api-contract`: Backend route, request/response schema, status code, error envelope, auth/session, or service-client contract changes. Require architecture or development skill for the owning stack plus integration/contract verification.
- `permission-access`: Authentication, authorization, roles, admin/internal access, tenant/user isolation, or data visibility. Require architecture review, negative tests, and explicit stop if identity/product boundary is unclear.
- `money-quota`: Billing, points, quota, payment, entitlement, refund, metering, or financial finality. Require high-risk resilience gates, idempotency/replay checks, auditability, and product confirmation for user-facing semantics.
- `write-finality`: Mutations, async jobs, repeated submission, irreversible actions, imports, deletes, or bulk operations. Require duplicate-submit/idempotency checks, pending/final state coverage, retry semantics, and recovery evidence. **Verify the authoritative postcondition, not the call's success/`ok` status** (a 2xx/ok ≠ the effect landed), via a finite ladder — direct read → operation receipt / status / version / ETag / audit-event or effect id (each counts as authoritative only if it actually proves the declared postcondition, not merely "accepted") → bounded eventual-consistency retry (cap attempts/window) → if no authoritative read exists (fire-and-forget / write-only / encrypted), report `accepted-not-applied` / `unverifiable`, never `done` and never loop unbounded; `testing-strategy` owns the side-effect-finality test mechanics.
- `ai-output`: LLM, RAG, model routing, generated content, prompt/eval, high-impact answer, or automation decision. Require `llm-inference-integration`, eval/replay or scenario checks, degradation/refusal behavior, and traceability.
- `ai-action`: An LLM / agent that does not just produce an answer but **takes side-effecting actions** — calls tools that mutate state, send or trigger external effects, access privileged data, or make authorization-sensitive decisions; moves money; changes permissions; or drives irreversible effects from model output (industry framing: OWASP Top 10 for LLM Applications 2025 — LLM06 *Excessive Agency* and LLM01 *Prompt Injection*).
  - Read-only retrieval used only to form an answer stays `ai-output` unless it can expose privileged data or drive a downstream action.
  - Require `llm-inference-integration` for tool-execution validation, fail-closed authorization, human confirmation on destructive / external / financial / permission-changing / irreversible actions, and prompt-injection defense whenever untrusted content (user input, retrieved documents, web pages, tool results) can reach a model able to act or surface privileged data.
  - (This is the product/runtime agent surface; `multi-agent-delegation` is a different axis — it applies only when the *delivery work itself* is delegated to subagents, not to a shipped agent feature.) Also apply `write-finality`, `money-quota`, or `permission-access` when the action actually crosses that boundary — durable-state mutation, money/quota movement, or access change — but do not stack those tags for read-only, reversible, or sandboxed actions whose downstream effect stays in bounds.
  - Where a gate does apply, the action being model-decided does not lower the bar; it raises it, because the model must never infer permission from untrusted content.
- `genai-compliance`: A surface that **publishes or distributes** generated / synthetic content to end users (synthetic image / audio / video / voice / avatar, user-shareable AI media), or operates a generative-AI service in a covered jurisdiction.
  - This tag only flags that legal/compliance review *may* be needed — it does NOT determine the obligations or satisfy them, and it is distinct from `ai-output` (answer quality).
  - Ordinary ephemeral assistant answers are `ai-output`, not this.
  - Mark it launch-blocking only when legal/compliance ownership is unknown, a target jurisdiction has a covered regime, or the surface distributes synthetic media; route the obligation through `product-rd-workflow`'s compliance/legal stop point and the legal/compliance owner (the Stop Rules below already require stopping for legal/compliance boundaries).
  - Obligations vary by jurisdiction — transparency, labeling, provenance, content filing, safety assessment, or others — and must NOT be inferred from this router.
  - Example: mainland China has AI-generated/synthetic-content labeling rules (explicit user-visible + implicit metadata label concepts, effective 2025-09-01 with a companion mandatory national standard); verify the current requirement for each jurisdiction and content type with legal/compliance.
- `data-migration`: Schema, storage ownership, migration, backfill, indexing, or irreversible data movement. Require architecture review, migration rehearsal or rollback plan, and live-data boundary confirmation.
- `external-integration`: Third-party API, webhook, browser/device, deployment platform, queue, object storage, or credential-dependent path. Require mocked fast tests plus explicit live/integration verification or recorded unavailable evidence.
- `release-ops`: CI, deploy, observability, rollback, feature flags, canary, or platform control-plane changes. Require release/readiness checks and post-change status evidence.
- `shared-gate`: A shared deterministic gate, verifier, conformance script, CI/harness check, status-source validator, agent-contract checker, or review/merge readiness rule that future agents or repositories rely on. This can look like docs/scripts-only work, but the changed artifact decides whether later work is allowed to merge or be called complete. Require the owning workflow skill (usually `product-rd-workflow` for product/spec normalization or `skill-extraction-workflow` for shared-skill gates), `testing-strategy` when the gate has executable or mutation-test behavior, and an explicit independent review/challenge decision before shared branch push or MR merge. Local passing gate output is required evidence, but it does not replace review of the gate's scope, false-positive/false-negative behavior, and completion semantics.
- `security-review`: An explicit security audit / threat-model / OWASP / pentest-review request (over an existing or proposed system/design), OR a change that introduces or materially alters a trust boundary, an untrusted-input surface, a sensitive sink, authentication/authorization semantics, secret/credential handling, or data visibility, or is itself a hardening / vulnerability-fix change. Require a security-review gate before completion; conduct, gate statuses, and safety boundary are in `references/security-review-gate.md`.
  - It **co-applies** with `permission-access`, `external-integration`, `release-ops`, and `ai-action` and **never de-escalates** another tag or a Stop Rule. An explicit security-audit / threat-model / pentest request always sets at least **pending-dedicated-review** and is **never `not-applicable`**. Only the change-triggered arm may be `not-applicable`, and only after recording `security posture unchanged` and ruling out every posture-change blocker (trust boundary, untrusted-input surface, sensitive sink, auth/authorization semantics, data visibility, secret handling, hardening, vulnerability-fix intent).
  - This router owns the gate's **status and safety boundary, not a security-audit method**. With no dedicated security-audit skill/owner available, the most you may run is a **read-only first-pass triage** (`security-first-pass-only`, never a passed gate; never "secure" / "audit passed" / a standalone "no findings" as completeness) — a real audit needs a dedicated security owner or professional firm. Normalize findings per the shared review-finding standard.
- `verification-scope-unclear`: The required test or runtime verification layers are unclear.
  - Must-route only when at least two signals are present: the change spans at least two runtime domains such as browser UI, server process, live infrastructure dependency, or external API; the user mentions complete tests, integration, E2E, live dependency, browser verification, Docker, or equivalent; implementation is underway or complete and the user asks whether a test layer is missing; or the plan/spec does not assign unit, integration, E2E, live dependency, or browser-rendered coverage.
  - Require `testing-strategy` to produce a lightweight test-layer matrix only: each layer applies yes/no, reason, and owner skill.
- `docs-only`: Documentation/status-only change. Require consistency scan; skip code tests unless the doc changes executable instructions, product status, or release readiness claims.

## Stop Rules

Stop and ask before proceeding when a change affects product direction, monetization, legal/compliance boundaries, identity model, public launch scope, security/privacy assumptions, destructive data actions, or external permissions that cannot be exercised locally.

Do not stop for low-risk implied follow-through such as running focused tests, checking diffs, syncing status docs after a merged slice, or recording `visible surface: no` for pure plumbing changes.

## De-Escalation

Keep the route as small as the risk allows:

- If a change is docs-only, do not require runtime tests.
- If a docs/scripts-only change is tagged `shared-gate`, do not de-escalate to ordinary `docs-only`; keep the review/challenge decision and executable verification required unless the owning workflow explicitly classifies the gate as non-blocking and local-only.
- If a client change has no visible surface, do not require a design checkpoint.
- If a backend change is internal and contract-preserving, prefer focused unit/integration tests over full E2E.
- If `verification-scope-unclear` has only one signal, treat it as a hint, not a must-route. Single-file pure refactors, copy-only changes, tiny style tweaks, and docs-only updates do not need test-layer routing unless another risk tag applies.
- If live infrastructure is unavailable after normal remediation, record the blocked gate with command evidence, residual risk, and next unblock action instead of pretending it passed.
