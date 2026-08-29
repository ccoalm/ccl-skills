# Background Job Patterns

Use this for Celery, RQ, arq, APScheduler, queue consumers, and scheduled tasks.

## Job Implementation

- Define typed payloads.
- Add idempotency keys.
- Bound retries and backoff.
- Distinguish retryable, drop, quarantine, and terminal failures.
- Store status for user-visible jobs.
- Protect singleton jobs with locks or scheduler guarantees.

## Tool-Specific Caveats

Defaults shift across major versions; verify against the installed tool version's docs before relying on any default named here.

- Celery ack semantics: the default early ack loses a task on worker crash; `acks_late=True` moves the ack to after completion, so a crash mid-task causes redelivery — pair it with idempotent task bodies, and decide `task_reject_on_worker_lost` deliberately rather than by default.
- Celery visibility timeout (Redis/SQS-style brokers): must exceed the longest task runtime plus retry backoff, or the broker redelivers a still-running task and it executes concurrently with itself.
- Celery prefetch and worker lifecycle: set `worker_prefetch_multiplier=1` for long tasks (default prefetch head-of-line blocks the queue behind one slow task); use `worker_max_tasks_per_child` to recycle leaky workers.
- Celery beat is a single point of scheduling: run exactly one beat instance, or guard schedule dispatch with a distributed lock; two beats double-fire every schedule.
- RQ: a queued job silently expires when its `ttl` passes before a worker picks it up, and `job_timeout` kills execution past the budget; failed jobs land in the failed registry and requeueing is an explicit operation, not automatic.
- arq: async-native — `max_tries` bounds retries, `job_timeout` bounds execution, `defer_by`/`defer_until` schedule, and results live in Redis only for the `keep_result` TTL; treat result reads after that window as misses, not errors.

## Transactional Enqueue Boundary

- Enqueueing from inside an open DB transaction is a dual write: the broker publish does not roll back with the transaction. Either enqueue through an outbox row committed with the business write (see `python-service-architecture/references/event-driven-architecture.md` and the outbox section of `sqlalchemy-and-migrations-patterns.md`), or enqueue after commit and accept the crash window between commit and enqueue with a documented reconciliation path.
- The inverse ordering — enqueue first, then commit — hands the worker a job for state that may never commit; workers must re-read durable state, not trust the enqueue payload as proof the write happened.

## Request Boundary

- Do not hide long work behind a synchronous request unless the timeout budget proves it is safe.
- Return job IDs or status URLs for long-running work.
- Make cancellation and duplicate submissions explicit.
