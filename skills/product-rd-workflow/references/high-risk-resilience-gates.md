# High-Risk Resilience Gates

Use this when product work can cause financial loss, authorization mistakes, tenant/user data exposure, wrong high-impact AI answers, duplicate writes, unclear user finality, or incidents that support cannot explain.

## Trigger

Apply this gate when the feature, workflow, or changed path includes:

- money, billing, quota, credits, refund, entitlement, reconciliation, or audit-affecting state;
- login, permissions, role/capability checks, tenant/user/resource isolation, privacy, or sensitive data;
- write requests, callbacks, MQ consumers, scheduled jobs, imports/exports, long-running tasks, or side effects that may repeat;
- high-impact AI answers, recommendations, summaries, decisions, or generated content that users may trust;
- client submission flows where users can click twice, refresh, go offline, return later, or not know whether the action finished;
- write-finality risk: externally acknowledged, irreversible, repeated-submit, async-final, money/quota, permission, bulk, delete/import, or user-finality-unclear mutations;
- launch, rollback, degradation, customer-support explanation, compensation, or incident traceability.

## Product Decisions

- Define what can degrade, what must fail closed, and what must refuse instead of producing a weak or misleading result.
- Product owns user-visible degradation, refusal, timeout, retry, support, and compensation language. Engineering must not invent these at implementation time.
- High-risk capabilities should default disabled or fail-closed in production until explicitly configured, approved, and verified. Local developer stubs or test defaults must not imply production enablement.
- For high-impact AI, availability cannot silently beat answer quality. Fallback or downgrade requires an explicit quality-equivalence decision; otherwise return a clear refusal/degraded state.
- For money, permissions, privacy, tenant/user isolation, and sensitive writes, uncertainty means reject or stop before side effects.
- Missing tenant, actor, subject, resource scope, entitlement, or authorization context must not fall back to a default identity or default tenant on high-risk paths. Defaults are allowed only for explicit bootstrap, seed, or non-user-facing maintenance flows with separate approval.

## Architecture And Implementation Gates

- Every P0/P1 endpoint or job has an owner, timeout budget, rate/concurrency limit where relevant, canonical error behavior, trace/request id, and observable dependency errors.
- Write requests do not auto-retry unless idempotency is designed with a durable key, unique constraint, state machine, dedupe table, or equivalent proof.
- Redis-only, memory-only, TTL-only, or process-local dedupe is not durable enough for money, quota, entitlement, audit, external acknowledgement, or irreversible side effects. Use durable idempotency or explicitly mark the path as best-effort/non-critical.
- MQ, callbacks, scheduled jobs, imports, and long-running tasks assume duplicate delivery and partial failure. They need idempotency, retry/backoff, terminal failure, repair or compensation, and visible status.
- Degradation must not bypass authorization, tenant/user isolation, quota, audit, or data retention controls.
- Reconciliation is required for money, quota, entitlement, and externally acknowledged side effects. The system needs a way to produce a difference list or equivalent review evidence.
- If the primary mutation and audit/outbox/governance evidence cannot commit atomically, the design needs an outbox, compensating record, replayable repair path, and alertable reconciliation gap. Throwing an error after the mutation commits is not enough.
- Admin repair, replay, quarantine, ignore, requeue, and settlement workflows need explicit claim/complete state, stale counters, oldest-age metrics, idempotency keys, and operator/request/trace evidence.
- AI-generated runtime config for timeout, rate limit, routing, fallback, or circuit behavior needs human approval and recorded rationale before activation.

## Client And Design Gates

- Users must see whether an action is pending, succeeded, failed, partially completed, queued, retryable, cancelled, or blocked. A generic toast is not enough for high-risk flows.
- AI-generated or automation-generated output that can affect users should first appear as draft, candidate, preview, or review-required state with source/status metadata, not as silently published final content.
- Submits must prevent accidental duplicate action through disabled state, idempotency key, optimistic-state discipline, final-status polling, or server-confirmed result display.
- Long-running work needs durable status, recovery after refresh/app restart, timeout/failure UI, and a result or support pointer.
- Failure views should expose a safe tracking identifier such as request id, order id, task id, or support code when the user or support needs follow-up.
- Degraded AI/data output must be visibly marked and should not look equivalent to normal high-confidence output.

## Testing And Launch Evidence

Build a compact scenario matrix before launch. Include only scenarios that match the changed risk surface, but do not skip a triggered class without saying why.

- Duplicate side effect: duplicate HTTP submit, callback replay, MQ redelivery, job restart, refresh/back-button retry.
- Permission uncertainty: auth service timeout, missing capability, stale session, cross-user/tenant/resource mismatch.
- Money/quota/accounting: double charge, partial charge, rollback/refund, quota deduction, reconciliation difference.
- AI failure: provider timeout, rate limit, incompatible fallback, weaker model unavailable or not approved, invalid/unsafe output.
- AI reviewability: generated output exposes status, model/prompt or policy version, cost/usage or execution metadata where useful, and remains candidate/review-required until explicitly accepted.
- User finality: pending longer than expected, network disconnect, app/browser restart, partial success, retry after failure.
- Incident support: trace/request id exists, logs/metrics capture the failed class, customer-support explanation and compensation path are available when required.
- Atomicity/reconciliation: mutation plus audit/outbox either commits together, or a compensating/replayable gap is visible and alertable.
- Missing context: absent tenant/actor/subject/resource scope is rejected; no default identity or default tenant is used on the high-risk path.

Acceptance evidence should name the command, test, replay, browser/device check, trace/log id, screenshot, or runbook step that proves each selected scenario.

Use this matrix before launch for any triggered high-risk class:

| Risk class | Invariant to prove | Owner | Lowest proof layer | Command or drill | Evidence artifact | Skipped reason |
| --- | --- | --- | --- | --- | --- | --- |
| Duplicate side effect | Same intent cannot double-write or double-charge | Backend + client | Unit/contract plus integration | Duplicate submit/callback/retry test | Test name, idempotency key, persisted state | |
| Permission/context | Missing or mismatched actor/scope is rejected before side effect | Backend | Contract/integration | Missing context and cross-scope request test | Response, audit/log trace | |
| Async finality | User/support can tell pending, failed, partial, and final status | Product + backend + client | Integration plus rendered smoke | Job restart/refresh/retry drill | Task id, screenshot, trace/log | |
| AI quality/safety | Weak fallback does not masquerade as trusted output | Product + AI owner | Eval/replay plus UI smoke | Provider failure/fallback/refusal drill | Eval report, refusal/degraded screenshot | |
| Audit/reconciliation | Mutation and evidence commit together or gap is repairable | Backend + operations | Integration/reconciliation drill | Outbox/audit failure or repair replay | Difference list, alert, repair record | |

Every selected row must have an artifact. A blank `Skipped reason` is acceptable only when the risk class is not triggered by the change.
