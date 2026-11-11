# Audit And History Architecture

Use this when designing audit logs, resource history, activity records, or change tracking.

## Audit Boundary

- Decide which operations require durable audit and which can use best-effort activity logs.
- Define actor identity, service identity, resource scope, resource id, operation name, result, timestamp, trace id, and canonical error fields.
- Keep end user, client application, service caller, and operator identity separate.
- Use stable operation names rather than function names that change during refactors.
- Define retention, privacy, redaction, query authorization, export, and deletion policy.

## Data Shape

- Store selective before/after summaries or field-level diffs when needed; do not store raw secrets, tokens, passwords, signatures, or unrelated payloads.
- Serialize request parameters and result data through redaction helpers.
- Prefer append-only audit records. Corrections should be new records unless a legal deletion policy requires removal.
- For event-derived history, define lag, rebuild, reconciliation, and source event retention.

## Write Path

- Critical audit should be in the same transaction or outbox as the state change when correctness depends on it.
- Best-effort audit is acceptable only when explicitly non-critical and observable through logs or metrics on write failure.
- Async audit pipelines need bounded queues, retry policy, backpressure or drop policy, and shutdown flush.

## Query Path

- Query APIs need resource-scope authorization, pagination, time range filters, and redaction on read.
- High-volume audit stores need partitioning or retention windows before launch.
