# Performance And Capacity Patterns

Use this when implementing Go backend capacity controls, batch jobs, replay/shadow workers, or DB performance guards.

## Bounded Concurrency

- Use semaphores, worker pools, or queue consumers to cap concurrent external calls and heavy CPU work.
- Derive default concurrency from config, not only CPU count; CPU-based defaults are a fallback.
- Always release semaphore slots with `defer` or structured scope; structure each successful acquire to have exactly one release, and guard the release (e.g. `sync.Once`) only where it can genuinely race or double-fire — test the double-release path rather than letting a wrapper silently absorb the bug. For a request-admission limiter without a designed bounded queue, prefer a non-blocking acquire that rejects fast under overload and pre-checks `ctx.Done()` before admitting; where a bounded queue is intended, use `Acquire(ctx)` with a defined max wait and cancellation instead.
- Pass `context.Context` through every bounded task and stop dispatching when the context is canceled.

## Batch Jobs

Implement batch jobs with:

- CLI/config options for `batch_size`, `concurrency`, `limit`, `dry_run`, timeout, and report output;
- cursor or checkpoint rather than unbounded scans;
- per-row outcome with success/failure/skipped status;
- bounded error samples;
- final report containing processed count, success count, failure count, duration, and next resume point.

Do not let batch jobs rely on invisible process logs only.

## Replay And Shadow Workers

- Persist replay task status: pending, running, completed, failed, canceled.
- Store total, processed, success, failed, start/end timestamps, and metadata.
- Use a task registry or lock to prevent duplicate in-process execution.
- Scheduled replay needs a distributed lock and explicit timeout.
- Compare candidate and baseline responses with predeclared thresholds and retain diffs for review.

## Database Guards

- Configure DB max open/idle connections and connection lifetime according to service concurrency.
- Add focused tests or non-production hooks that catch missing indexes for known large queries.
- Prefer generated or typed DAL methods with explicit filters, pagination, and ordering.
- Avoid production-only query surprises by checking explain plans during development and staging.

## Timeout And Repair

- Every async task should have a timeout threshold per state.
- Stuck tasks should transition to retryable state until retry budget is exhausted, then terminal failure.
- Repair jobs should log both the stuck duration and retry count.
- Retried jobs must be idempotent or guarded by a domain idempotency key.
