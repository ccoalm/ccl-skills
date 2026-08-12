# Redis Cache Lock Patterns

Use this when implementing Redis clients, key builders, local/distributed caches, locks, counters, rate limits, idempotency, or lightweight task queues.

## Client Setup

- Build Redis clients from typed config and a secret provider.
- Resolve endpoints through service discovery or explicit environment config.
- Configure dial timeout, read timeout, write timeout, and pool size.
- Load Lua scripts at startup when using script-based atomic operations.
- On `NOSCRIPT`, reload the script and fall back to direct eval once; emit a metric for script-cache misses.
- Redis command errors should include operation name and key purpose, but not secret payloads.

## Key Builders

- Put all keys in one package or adapter per service domain.
- Use functions such as `KeyForX(id)` rather than inline formatting. When two components share a key namespace, funnel key derivation through one canonicalization function used symmetrically on read and write; mismatched normalization on one side silently splits the namespace.
- Include environment/lane/resource-scope dimensions only when they are necessary for isolation.
- Validate non-empty keys before commands that mutate data.
- Keep key names stable; changing a key format is a migration and invalidation event.
- Keep pattern deletes or key scans behind explicit adapter methods with bounded scan/batch behavior and metrics. Do not scatter raw `KEYS` or broad pattern deletion through service logic.

## Distributed Locks

- Acquire with `SET NX EX/PX` or a proven library.
- Lock value must be unique per attempt: instance id plus random id or operation id.
- Unlock with compare-and-delete, usually via Lua.
- Renew with compare-and-expire when the critical section can exceed one lease.
- Renewal loops must stop on context cancellation and max lease.
- Always `defer unlock` after successful acquire unless the lock is intentionally no-unlock throttling.
- Return a typed lock-failed error when acquire fails; callers must decide skip, retry, or fail.

## CAS And Atomic Scripts

- Use Lua for compound atomic operations such as compare-and-set, compare-and-delete, compare-and-expire, positive-only decrement, increment-only-if-exists, hash get-and-set, and sorted-set pop.
- Define return codes for success, compare failure, and missing key.
- Convert Redis nil/missing-key into explicit domain behavior.
- Keep scripts deterministic and small.
- Test script fallback and invalid return type handling.

## Cache Implementations

- Local cache:
  - protect map/LRU state with locks.
  - enforce capacity and TTL.
  - make cleanup goroutines stoppable or acceptable for process lifetime.
  - deep-copy mutable data when callers might mutate it.
- Distributed cache:
  - serialize through a stable format.
  - set TTL on every write.
  - distinguish miss from Redis failure.
  - handle malformed cache payload by treating it as miss and optionally deleting it.
- Do not let cache failures hide source-of-truth failures unless fallback is explicitly designed.

## Counters And Quotas

- For counters that must not go below zero, use an atomic script rather than read-modify-write.
- Decide whether missing key means zero, nil, or error.
- On increment, decide whether to set, extend, or preserve TTL.
- Batch get/set/delete should validate keys and use pipelines carefully; make sure commands are executed, not only created.
- Return existence along with value when callers must distinguish zero from missing.

## Rate Limiting

- Use a stable scope such as subject, resource scope, IP, app id, operation, or domain object.
- Sliding window implementation should:
  - remove entries older than the window.
  - count current entries.
  - add the current hit atomically or inside a watched transaction.
  - expire the key slightly after the window.
  - retry boundedly on transaction conflict.
- Return both allowed flag and current count when useful for logs or response headers.
- Reset should be explicit and scoped.

## Idempotency

- Idempotency keys should include operation name and stable request/resource id.
- Store status, result reference or summary, last error, created time, and expiry when the workflow is inspectable.
- Separate pending claim, completed marker, duplicate completed event, and retryable failure. Pending claims need a short TTL or owner lease; completed markers need a dedupe window that matches the external retry horizon.
- If Redis is unavailable on a high-risk idempotency path, fail safe according to the product contract rather than silently accepting duplicate side effects.
- For MQ consumers, duplicate messages should normally return success after detecting already-processed state.
- Include retry count in the key only when each retry is intentionally distinct; otherwise it can defeat deduplication.

## Lightweight Task Queues

- Sorted sets are useful for time-ordered pending work and priority.
- Sets are useful for deduplicated pending ids.
- Redis Streams can support replayable progress or event delivery only when the implementation defines starting id, resume behavior, heartbeat/no-message behavior, trimming or TTL cleanup, and malformed-message handling.
- Pop operations should be atomic if losing the popped item is unacceptable.
- For durable work, persist the task in DB or a real queue and use Redis only for scheduling or coordination.
- Expose queue size, pop count, retry count, and stuck-item metrics.

## Tests

- Unit-test key builders and TTL selection.
- Test lock acquire, acquire failure, compare-and-delete unlock, wrong-token unlock, renewal, context cancellation, and max lease.
- Test rate limiter allow/deny at window boundaries and transaction conflicts.
- Test counter missing-key and positive-only behavior.
- Test cache malformed payload, miss, Redis failure, and source fallback.
- Keep live Redis tests out of the default fast test target unless a local isolated Redis is guaranteed.

## Cache Stampede Defense

- Combine single-flight (one fetcher per key while others wait), negative caching for misses with shorter TTL, and randomized TTL jitter (±10-20%) for hot keys whose miss cost is high.
- In-process single-flight uses a per-key mutex or `golang.org/x/sync/singleflight`; cross-process single-flight uses a short Redis lock with compare-and-delete release.
- Apply jitter at write time, not at read time.
- For very hot read-mostly data, layer a short-TTL in-process cache in front of Redis and invalidate through Pub/Sub or topology-change events.

## Cluster Slot And Hash Tag Rules

- Multi-key commands, `MULTI/EXEC`, Lua scripts, and pipelines that depend on key co-location must keep all keys in the same hash slot. Use the `{tag}` hash-tag syntax (`tenant:{tid}:resource`, `tenant:{tid}:counter`) to co-locate keys.
- A Lua script with `KEYS[]` across slots fails with `CROSSSLOT`; review key schemas before writing scripts that take multiple keys.
- `SCAN` walks one cluster node at a time; cluster-aware delete-by-pattern means iterating all primary nodes, not the cluster as one keyspace.
- Pipelines across slots split into per-slot round-trips; do not assume a single network call.
- Cluster clients refresh slot maps on `MOVED`/`ASK`; for latency-sensitive paths cache the slot map and refresh proactively on topology change.

## Retry And Circuit Breaker Coordination

- Retry only for transient errors: connection errors, read/write timeouts on idempotent reads, `LOADING`, `BUSY`. Do not retry write commands when retry could double-apply.
- Bound retries: max attempts, exponential backoff with jitter, total deadline; enforce a per-request retry budget to prevent amplification.
- Pair retry with a circuit breaker per upstream identity (cluster endpoint or sentinel set). Open after consecutive failures, half-open after cool-down, close on success. Do not retry inside an open circuit.
- Coordinate with lock and idempotency: a retry against a lock you already hold uses compare-and-expire, not re-acquire; a retry against an idempotency store distinguishes `pending` (original attempt still in-flight; return in-progress/retry-later to the caller, do NOT execute again) from `completed` (return the recorded success/no-op). Treating duplicate `claimed`/`pending` as success acknowledges work that may still be running and risks double execution if the first attempt later fails or partially succeeds.
- Surface retry count, breaker state, and budget exhaustion as metrics; sustained breaker-open is a paging condition.
