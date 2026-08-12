# Reliability Patterns

## Context And Log Id

- Start every inbound request with a trace/log id. If the caller provides one, validate and reuse it; otherwise generate one.
- Put trace/log id, lane/environment, authorization/resource scope, and auth subject into context once at the edge.
- Return trace/log id in HTTP headers or response metadata when supported.
- Do not create `context.Background()` inside request handling unless starting a deliberately detached task; pass the parent context down.
- At the outermost boundary the framework invokes on your behalf — a documented entrypoint with no parent-context source, where a nil `ctx` means no caller context could exist (e.g. a direct or background caller), not a dropped one — normalize it (`if ctx == nil { ctx = context.Background() }`) with a diagnostic rather than relying on the framework's always-non-nil guarantee; anywhere a caller context was expected, treat nil as a bug and fail/log explicitly instead of masking a lost cancellation/deadline. Test the nil path.
- For detached async work, create a new context with inherited metadata and a fresh bounded deadline — but separate the two lifetimes: the setup/registration call itself still honors the caller's cancellation (do not strip it with `context.WithoutCancel`; cancelling setup must still abort setup), and only the spawned worker runs on the detached context, so cancelling the caller after setup succeeds does not kill the worker and cancelling setup does not orphan a worker already spawned. Test cancellation with an explicit `cancel()`, not a race-prone tiny timeout+sleep.

## Detached Goroutines And Panic Firewall

- A panic inside a detached goroutine is unreachable by any framework or RPC middleware recover — it crashes the whole process. Route every production goroutine spawn through one shared safe-spawn wrapper that recovers, logs the stack with trace/log id, and increments a panic metric; no bare `go func()` on production paths. Recovery policy follows isolation level: recover-and-continue is for per-request/per-item work whose state dies with it (plus its cleanup); a supervisor or global-invariant goroutine (scheduler, registry owner, singleton reader) that panics mid-mutation must not silently keep serving on recovered-but-corrupted state — recover to log/metric, then actually stop serving: flipping readiness alone leaves existing connections and un-propagated routing serving corrupt state, so also stop accepting, cancel/drain the serving loops, and exit nonzero (or hard-drain with serving disabled).
- Enforce firewall coverage with a checklist or lint, not memory. Failure shape: the sites most often missed are exactly the largest-blast-radius ones — top-level server goroutines and stream readers decoding untrusted bytes. Verify the panic metric is actually wired per spawn site instead of assuming the wrapper implies it.
- The only rigorous regression proof for "process survives this panic" is a subprocess exit code: the test runs a child process that triggers the panic inside the detached goroutine and asserts the fixed binary exits 0. An in-process recover assertion cannot prove process survival. Scope this proof to per-request/per-item work where recover-and-continue is the policy; for a supervisor/global-invariant goroutine the assertion is the opposite — the child process must go unready/non-serving or exit nonzero on purpose, and an exit-0-and-still-serving result is the failure being prevented, not the pass.

## Timeout And Deadline

- Pick local defaults per dependency type: connection timeout, RPC/HTTP request timeout, DB query timeout, Redis timeout, MQ publish timeout.
- If `ctx.Deadline()` exists and is shorter than the configured timeout, use the remaining deadline.
- Always call `cancel()` for contexts created with timeout.
- Avoid unbounded retries inside a context that is already near its deadline.

## External RPC/HTTP Clients

- Build clients around a single method that accepts context, request, and operation name.
- Validate transport errors, HTTP status, and domain status code separately.
- Wrap errors with operation name and endpoint/service identity, but keep secrets and payloads out of error text.
- Use retry only for idempotent operations or operations with an idempotency key.
- Define fallback explicitly: alternate endpoint, cached response, degraded result, or hard failure.
- For outbound URL or file fetches, validate scheme and host before request, set redirect policy, cap response size, verify content type, and always close the response body.

## Admission Control And Circuit Breakers

- Add inbound rate limit, concurrency limit, or cost-based guard middleware before expensive handlers.
- Return a canonical overload error and optional retry-after hint when rejecting work; do not let overload surface as panic or random timeout.
- Use bounded queues only when callers have a defined wait deadline and cancellation path.
- Circuit breakers should wrap dependency calls or expensive workflows with explicit open, half-open, and close conditions.
- Emit metrics for admitted, rejected, queued, shed, circuit-open, and circuit-half-open outcomes.
- Tests should cover limit reached, context canceled while queued, breaker open, half-open success, and half-open failure.

## Streams, Uploads, And Downloads

- Streaming handlers should check context cancellation or send errors on every loop iteration and close upstream streams in `defer`.
- For long-lived stream state machines, prefer a single owner goroutine keeping state in closure-local variables: "local variables have no data race" is an argument a reviewer can verify at a glance, while shared mutable state behind locks needs a proof per field.
- Set max request body size, max file count, max object size, and allowed content types before parsing uploads.
- For compressed uploads or archives, enforce compressed size, expanded size, file count, path traversal checks, and expansion-ratio limits.
- Download handlers should support bounded range reads only when object metadata confirms size and range validity.
- Temporary files and directories should be created under a controlled base path and removed on both success and failure.
- For generated or transformed files, write to a temp path first, then atomically publish or upload when complete.
- Tests should cover client disconnect, oversized body, invalid content type, partial stream error, and cleanup after failure.

## Async Consumers

- Decode payload into a typed struct and validate required fields before side effects.
- Treat duplicate delivery as normal. Use idempotency keys or persisted processing state for non-repeatable writes.
- Decide return behavior intentionally:
  - return error for retryable infrastructure failure.
  - return nil after logging for permanent bad payload or already-processed work.
  - dead-letter when the queue supports it and the payload needs later inspection.
- Attach trace/log metadata to logs and downstream calls.
- Recover panic at the consumer boundary and convert it into retry/dead-letter behavior according to queue policy.

## Scheduled Jobs

- Define job name, schedule, lock key, lock lease, max execution time, retry count, and backoff.
- Acquire a distributed lock before work starts; failure to acquire should normally skip, not fail the process.
- For jobs whose max execution time can exceed one lease window (GC pause, slow dependency, large backfill), require **renewable leases with fencing tokens**: the job renews the lease via heartbeat at < ½ the lease TTL, and every write/external-call carries the current fencing token so a second pod that acquires the lock after the first's lease expires cannot overwrite work from the original holder. Stop work immediately on a failed renewal. Fixed-lease + max-execution alone is not enough — if execution exceeds lease, two pods run simultaneously and can both write non-idempotent backfill/repair side effects.
- Use a job-scoped context with timeout and pass it to all downstream operations.
- Recover panic and release locks in `defer`.
- Emit metrics for start, success, failure, timeout, retry, skipped-lock, and duration.
- Support both fixed interval and cron-style schedules only through validated config; reject empty or malformed schedules at startup.
- Job managers should be closable: stop tickers, prevent new executions, and let in-flight jobs finish or cancel by policy.
- Immediate-run behavior should be explicit and normally disabled for jobs with external side effects.
- Retry sleep must be bounded by the job context deadline.

## Redis Locks And Idempotency

- Lock values must be unique per attempt and unlock must compare value before delete.
- Lock lease must exceed expected critical section time but remain bounded.
- Idempotency records should include operation key, status, result pointer or summary, expiry, and last error if useful.
- Choose TTL based on domain retry window, not arbitrary cache duration.
