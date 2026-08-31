# State Machine And Task Patterns

Use this when implementing durable tasks, async workflows, scheduled jobs, imports, exports, and retryable processors. This is the canonical guide for durable state transitions and terminal-state behavior; generic worker/async mechanics stay in `async-and-worker-patterns.md` and `background-job-patterns.md`.

Sibling note: `go-microservice-dev/references/state-machine-task-patterns.md` carries the Go rendering of the same discipline; content is adapted per stack and kept in sync by review (not under the parallel-stack parity gate).

## State Model

- Define states as a domain-owned `Enum` (per the skill entrypoint's finite-value rule) with documented terminal states.
- Define allowed transitions in one table or policy function; do not scatter status checks across handlers.
- Terminal states reject ordinary processing and failure transitions.
- Include retry count, last error, start time, finish time, progress, result pointer, and idempotency key when tasks are inspectable.
- Store progress separately from state; progress is best-effort while state transitions are durable.
- Create the durable task row before launching background work, queueing expensive processing, or generating external artifacts — a crash must leave an inspectable, repairable record.

## Transition Implementation

- Guard transitions with compare-and-update (`UPDATE … SET status=:new WHERE id=:id AND status=:expected` and check rowcount), `SELECT … FOR UPDATE`, or a Redis lock (`redis-cache-lock-patterns.md`) before processing.
- Lease or lock owners must be unique at the runtime-instance level, not only the service level: include pod/host identity plus process id or a random instance id so replicas cannot claim or complete each other's work.
- A lock alone does not fence: a paused worker whose lease expired can resume and commit after a new owner took over — unique owner names do not prevent this. Every durable write under a lease carries a fencing check at the store it writes to: a monotonic fencing token compared there, or owner/version compare-and-update (`… WHERE id=:id AND owner=:me AND version=:v`), so a stale holder's write fails instead of overwriting the new owner's state.
- A store-side check fences only that store: a stale worker can pass the DB compare-and-update, pause, lose its lease, and then fire a NON-transactional external effect (a charge, a send) after the new owner completed. External side effects under a lease go through intent-then-execute (`sqlalchemy-and-migrations-patterns.md` outbox / the intent pattern in `python-service-architecture/references/event-driven-architecture.md`): the durable intent row is claimed with the fencing check, and the provider call carries an idempotency key bound to that intent. This fully fences **only when the provider actually enforces the key** (rejects or deduplicates a replay). For providers that cannot — SMTP, plain webhooks, any at-least-once send with no key support — no fencing eliminates the stale-execution window: shrink it with a claim re-check immediately before the call, then classify the effect honestly as at-least-once with a duplicate-visible reconciliation path, and record the residual duplicate window instead of claiming exactly-once.
- Re-read task state under the lock before side effects.
- Make duplicate delivery normal: already-successful is success or no-op; already-terminal is no-op or a typed conflict depending on the caller's contract.
- Start transitions move pending work to processing before expensive work begins.
- Failure transitions capture canonical error code, safe message, retryable flag, retry count, and last trace/log id.
- Success transitions persist the result pointer or summary before publishing completion events; completion events are idempotent.
- All timestamps the transition itself stamps come from a single captured `now` (double clock capture inside one transition produces `finished_at < started_at` records or audit/state disagreement under load); domain-provided times — upstream completion time, event time — are recorded as received, never re-stamped with the local `now`.
- Validate external/dependency response structure before mapping it (pydantic/schema parse with a typed error path, never a blind attribute access) — a malformed upstream payload must become a failure transition with the canonical error, not an exception mid-transition or a silently-defaulted field.

## Async Processing

- Prefer queue/worker execution (Celery/RQ/arq per `background-job-patterns.md`) for work that must survive process restart.
- Delayed events and queue messages re-check current task state when consumed.
- Retry thresholds and backoff live in config or state policy, not inline literals.
- A broad `except Exception` at the task boundary converts the task to failed or retryable-failed per the retry policy (never swallow `asyncio.CancelledError` — re-raise it after cleanup, per `async-and-worker-patterns.md`).
- Work that produces a file, report, or media artifact persists the object key or result pointer before the success transition and exposes a retryable failure state when upload/finalization fails.

## Scheduled Repair Jobs

- Scheduled checkers that repair stuck tasks need a job name, interval, distributed lock key, lock lease, per-run max batch size, and max execution time.
- A job-level lock prevents duplicate scans; a task-level lock or compare-and-update prevents duplicate repair of one record.
- Time-window selection is explicit, bounded, and based on durable timestamps (`updated_at`), not process memory.
- Repair actions re-read current task state before changing status or emitting side effects.
- Emit metrics for scan count, claimed count, repaired count, skipped count, lock conflict, failure, and duration.

## Tests

- Test illegal transition, duplicate event, concurrent processing (two claimers, one winner), already-terminal, retry threshold, cancellation, exception-to-failed conversion, and completion-event idempotency.
- Test lease expiry with a stale worker resuming after a new owner claimed the task: the stale worker's durable write and side effect must be rejected by the fencing check.
- Test scheduled repair lock conflict, stale-window selection, per-task duplicate prevention, and repeated-run idempotency.
