# Background Job Patterns

Use this for Celery, RQ, arq, APScheduler, queue consumers, and scheduled tasks.

## Job Implementation

- Define typed payloads.
- Add idempotency keys.
- Bound retries and backoff.
- Distinguish retryable, drop, quarantine, and terminal failures.
- Store status for user-visible jobs.
- Protect singleton jobs with locks or scheduler guarantees.

## Request Boundary

- Do not hide long work behind a synchronous request unless the timeout budget proves it is safe.
- Return job IDs or status URLs for long-running work.
- Make cancellation and duplicate submissions explicit.
