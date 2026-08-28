# Audit And History Patterns

Use this when implementing audit logs, operation records, resource history, or change tracking.

Sibling note: `go-microservice-dev/references/audit-history-patterns.md` carries the Go rendering; adapted per stack, kept in sync by review (not under the parallel-stack parity gate).

## Audit Record Shape

- Capture actor, service identity, resource scope, resource id, operation name, operation type, request id, trace/log id, timestamp, result, and canonical error code.
- Store safe before/after summaries or field-level diffs when needed.
- Never store raw secrets, tokens, passwords, signatures, or credentials.
- Serialize params and data through redaction helpers; do not dump whole request or response objects.
- Use stable operation names, not function names that change during refactors.

## Write Path

- Audit writes for critical operations belong in the same transaction or outbox as the state change when correctness depends on them (`sqlalchemy-and-migrations-patterns.md` Outbox section).
- Best-effort audit is acceptable only when explicitly non-critical; catch and log write failures with a failure metric — audit write errors must be observable even when they do not fail the main request.
- Async audit writers follow the detached side-path posture in `async-and-worker-patterns.md` (whitelisted correlation only, accept boundary at durable commit, per-attempt reservation for non-rollbackable external effects, bounded queue, serialized accept-vs-drain shutdown, loss policy matched to data class). For billing/ledger/usage records with no tested reconstruction source, use a same-transaction outbox or backpressure instead of drop — that posture is canonical there; do not restate it here.

## Query Path

- Audit query APIs need resource-scope authorization, pagination, time-range filters, and redaction on read.
- Default ordering is deterministic — usually newest first with a stable tie-breaker.
- Large audit tables need partitioning, retention, or archive strategy before high-volume launch.

## Tests

- Test redaction, critical-write rollback behavior, best-effort write failure visibility, exception recovery, pagination, scope filtering, and time-range boundaries.
