# State Machine And Task Patterns

Use this when implementing durable tasks, async workflows, scheduled jobs, imports, exports, and retryable processors.

For generic async, consumer, scheduled-job, panic recovery, context timeout, and external-call mechanics, also apply `reliability-patterns.md`. This file is the canonical guide for durable state transitions and terminal-state behavior.

## State Model

- Define states as enums or constants with documented terminal states.
- Define allowed transitions in one table or function; do not scatter status checks.
- Terminal states should reject ordinary processing and failure transitions.
- Include retry count, last error, start time, finish time, progress, result pointer, and idempotency key when tasks are inspectable.
- Store progress separately from state; progress is best-effort while state transitions are durable.
- Create the durable task row before launching background work, queueing expensive processing, or generating external artifacts.

## Transition Implementation

- Use compare-and-update, row lock, or distributed lock before processing a task.
- Lease or lock owners must be unique at the runtime-instance level, not only at the service name level. In Kubernetes or similar container platforms, include pod or host identity and process id or a random instance id so replicas cannot claim or complete each other's work.
- Re-read task state under the lock before side effects.
- Make duplicate delivery normal: already successful is success or no-op; already terminal is no-op or typed conflict depending on caller.
- Start transitions should move pending work to processing before expensive work.
- Failure transitions should capture canonical error code, safe message, retryable flag, retry count, and last trace or log id.
- Success transitions should persist result pointer or summary before publishing completion events.
- All timestamps the transition itself stamps come from a single captured `now` (capturing the clock twice inside one transition produces `finished_at < started_at` records or audit rows disagreeing with the state row under load); domain-provided times — an upstream completion time, an event time — are recorded as received, never re-stamped with the local `now`.
- Validate external/dependency response structure before casting or mapping it: an assertion/parse step with a typed error path, never a blind cast — a malformed upstream payload must become a failure transition with the canonical error, not a panic or silently-zeroed field.

## Async Processing

- Prefer queue or task execution for work that must survive process restart.
- Delayed events should re-check task state when consumed.
- Retry thresholds and backoff belong in config or state policy, not inline literals.
- Panic recovery should convert the task to failed or retryable failed state after applying the retry policy.
- Background work that produces a file, report, media object, or other artifact should persist the object key or result pointer before the success transition and expose a retryable failure state when upload/finalization fails.

## Scheduled Repair Jobs

- Scheduled checkers that repair stuck tasks need a job name, interval, distributed lock key, lock lease, per-run max batch size, and max execution time.
- A job-level lock prevents duplicate scans; a task-level lock or compare-and-update prevents duplicate repair of the same record.
- Time-window selection should be explicit, bounded, and based on durable timestamps such as `updated_at`, not process memory.
- Repair actions must re-read current task state before changing status or emitting side effects.
- Emit metrics for scan count, claimed count, repaired count, skipped count, lock conflict, failure, and duration.

## Tests

- Test illegal transition, duplicate event, concurrent processing, already terminal, retry threshold, cancellation, panic-to-failure, and completion event idempotency.
- Test scheduled repair lock conflict, stale-window selection, per-task duplicate prevention, panic recovery, and repeated-run idempotency.
