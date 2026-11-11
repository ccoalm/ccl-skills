# Background Jobs And Scheduling

Use this for Celery, RQ, arq, APScheduler, cron-like jobs, queue workers, and long-running tasks.

## Job Model

- Define job identity, payload schema, idempotency key, retry policy, timeout, max concurrency, and terminal states.
- Decide whether the job is durable queue work, scheduled work, one-off repair, or batch pipeline before choosing a tool.
- Use Celery/RQ/arq when work must survive process restarts or run outside the request path.
- Use in-process background tasks only for short, non-critical work that can be lost safely.

## Reliability

- Treat queue delivery as at-least-once unless the platform proves otherwise.
- Make consumers idempotent.
- Use leases or locks for singleton jobs.
- Store progress/checkpoints for long jobs.
- Expose failure visibility through logs, metrics, status records, or administrative reports.
