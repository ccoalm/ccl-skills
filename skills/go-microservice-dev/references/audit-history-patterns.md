# Audit And History Patterns

Use this when implementing audit logs, operation records, resource history, or change tracking.

## Audit Record Shape

- Capture actor, service identity, resource scope, resource id, operation name, operation type, request id, trace or log id, timestamp, result, and canonical error code.
- Store safe before/after summaries or field-level diffs when needed.
- Never store raw secrets, tokens, passwords, signatures, or credentials.
- Serialize params and data through redaction helpers; avoid dumping whole request or response objects.
- Use stable operation names rather than function names that change during refactors.

## Write Path

- Audit writes for critical operations should be in the same transaction or outbox as the state change when correctness depends on them.
- Best-effort audit is acceptable only when explicitly non-critical; recover panic and emit failure metrics or logs.
- Async audit writers need bounded queue, retry, backpressure or drop policy, and shutdown flush. For any async side-path (audit, ledger, usage reporting), the working posture is four pieces together: a detached context carrying only whitelisted correlation fields + durable work-item identity (never a wholesale `context.WithoutCancel` copy — it preserves request auth/session/secret values into work that outlives the request; the worker runs under service identity), derived only at the accept boundary for an already-accepted work item, with its own bounded deadline; for records of the service's own rollbackable mutations, the accept boundary is durable commit success — or a same-transaction/outbox row that commits and rolls back atomically with the mutation: before that, caller cancellation suppresses side-path work and nothing detached may be enqueued against an in-flight commit (a `Commit()` that fails, rolls back, or returns unknown after connection loss must never leave a fired detached record — and idempotent reconciliation of an unknown outcome is only possible if a durable intent/reconciliation key was written with or before the mutation, the outbox row being exactly that key; post-commit async capture without such a durable key is a blocked design for audit/billing-relevant records unless unknown commit outcomes are impossible or reconciliation is provable from durable authoritative state); after it, capture is mandatory and not gated on the caller still being connected. Records of NON-rollbackable external side effects (a provider call that already consumed quota/tokens) invert the order: book a per-attempt reservation/outbox row before or independently of the local outcome, with idempotent reconciliation — gating them on local commit drops charges that already happened; a bounded semaphore/queue; shutdown ordering where the accept check + `wg.Add` are serialized under one lock against a `closed` flag that `Close` sets under the same lock — but `Close` releases the lock before calling `wg.Wait`, and worker `Done`/flush paths must not need that lock, or shutdown deadlocks; and a loss policy matched to the data class: an explicitly accepted bounded-loss policy paired with a reconciliation/repair job is valid only when a tested idempotent reconstruction source exists — for billing/ledger/usage data with no such source, use a same-transaction outbox or backpressure instead of drop.
- Audit write errors should be observable even when they do not fail the main request.

## Query Path

- Audit query APIs need resource-scope authorization, pagination, time range filters, and redaction on read.
- Default ordering should be deterministic, usually newest first with a stable tie-breaker.
- Large audit tables need partitioning, retention, or archive strategy before high-volume launch.

## Tests

- Test redaction, critical write rollback behavior, best-effort write failure, panic recovery, pagination, scope filtering, and time range boundaries.
