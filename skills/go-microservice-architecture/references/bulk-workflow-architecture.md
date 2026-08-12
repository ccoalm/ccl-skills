# Bulk Workflow Architecture

Use this when designing import, export, backfill, migration, reconciliation, or other large batch workflows.

For durable status, allowed transitions, retry, cancellation, and idempotency rules, use `workflow-state-architecture.md` as the canonical contract. This file covers only the bulk-workflow concerns layered on top of that contract.

## Workflow Model

- Model long-running work as a durable job with actor, resource scope, source artifact, status, progress, total count, success count, failed count, error artifact, idempotency key, and timestamps.
- Separate validation, enrichment, commit, report generation, cleanup, and notification phases.
- Decide whether row-level errors produce partial success or fail the whole job before implementation starts.
- Use async processing when work can exceed request deadlines; synchronous APIs should create, inspect, cancel, or download jobs.
- Define maximum file size, row count, slice count, worker concurrency, and artifact retention before implementation.

## Partitioning And Coordination

- Large jobs should be partitioned by stable slice index, id window, cursor, or object part.
- Each slice needs a stable identity, ownership scope, retry limit, and per-slice progress.
- Finalization should run once after all slices reach terminal state.
- Cross-slice aggregation should use durable counters or transactional finalization, not in-memory state.

## Artifact Policy

- Source files, generated exports, and error reports need ownership, retention, size limit, access control, and cleanup policy.
- Error artifacts should preserve enough context for repair without exposing secrets or unrelated records.
- Store object keys or short-lived signed references; avoid storing large binary artifacts in relational rows.
- Exports must apply the same authorization and resource-scope filters as read APIs.

## Acceptance Checks

- The design states maximum file size, maximum row count, concurrency limit, timeout budget, retry limit, and retention.
- Error report generation failure has a defined terminal outcome.
- Job status is inspectable without reading object storage or worker logs.
