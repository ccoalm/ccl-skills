# Redis Cache Coordination

Use this when designing Redis usage for a Go microservice product.

## Redis Responsibility

- Redis is appropriate for ephemeral coordination: cache, locks, counters, rate limits, idempotency windows, lightweight task queues, and short-lived workflow state.
- Redis should not be the durable source of truth for domain state that must survive data loss or require auditability.
- If Redis state changes domain outcomes, pair it with a relational record, idempotency table, event log, or reconciliation process.
- Define failure behavior per use case: fail closed for risk controls, fail open for non-critical cache, retry for transient coordination failure.

## Key Space Design

- Keys should be built through typed functions, not inline string formatting across application code.
- Key format should include stable dimensions in a consistent order:
  - product or service namespace.
  - data purpose.
  - environment or lane when needed.
  - authorization/resource/workflow id when needed.
  - entity id or operation id.
- Local development and tests should avoid colliding with shared environments through prefixes, isolated Redis DBs, or fakes.
- Avoid raw user input in keys unless normalized and bounded.

## TTL Policy

- Every cache, lock, idempotency, rate-limit, and task-state key needs an explicit TTL unless intentionally durable.
- TTL should be chosen from domain semantics:
  - cache freshness window.
  - retry/idempotency window.
  - lock critical-section duration plus safety margin.
  - rate-limit window plus cleanup margin.
  - task recovery window.
- No-unlock throttle locks are acceptable only when expiry is the intended release mechanism.
- Durable or no-expiry Redis state needs an owner and cleanup strategy.

## Cache Strategy

- Use local memory cache for small, frequently read, eventually consistent reference data.
- Use distributed cache when multiple instances need shared cache state or invalidation.
- Cache miss, negative cache, and Redis failure must be distinguishable to callers.
- Cache data should be versioned or invalidated when source schema changes.
- Never cache secrets or raw authorization tokens unless encrypted and explicitly justified.

## Locks And Coordination

- Lock values must be unique per attempt and unlock must compare value before deleting.
- Renewable locks need lease, renewal interval, max lease, cancellation behavior, and failure hook.
- Long critical sections need compare-and-renew semantics, not blind expiry extension; renewal failure must stop or safely downgrade the work according to the workflow policy.
- Lock scope should match the domain critical section, not the handler name.
- Redis locks can reduce concurrency but should not replace database constraints for durable correctness.
- Long-running jobs should expose skipped-lock, acquired-lock, renewal-failure, and duration metrics.

## Rate Limits And Counters

- Rate limits need a scope, window, threshold, retry/conflict behavior, and user-facing error contract.
- Sliding-window limits should clean old entries and set expiry longer than the window.
- Counters need explicit semantics:
  - can go negative or cannot.
  - initialize-on-missing or fail-on-missing.
  - expiry reset on increment or fixed expiry.
  - exact truth or approximate throttling signal.

## Task Coordination

- Redis sets, sorted sets, and lists can coordinate lightweight pending work, but durable jobs need a real queue or database-backed state.
- Task entries should carry enough metadata to inspect, retry, or repair stuck work.
- Pop operations should be atomic when losing work is unacceptable.
- Scheduler locks and task queues should include recovery and max lease behavior.
- Script-based coordination should define success, compare-failed, missing-key, and invalid-return semantics so callers can choose retry, skip, fail, or repair deliberately.
- If Redis is used for idempotency, architecture must distinguish pending claim, completed marker, duplicate completed event, and retryable failure. Pending claims need a lease/TTL; completed markers need a dedupe window aligned with external retry behavior.
- Redis Streams, Pub/Sub, lists, and sorted sets should be chosen by delivery semantics, not convenience: fire-and-forget notification, replayable stream, deduplicated pending work, delayed scheduling, or durable work backed by DB/MQ.
- Broad key scans, pattern deletes, stream trimming, and TTL cleanup need an owner and bounded strategy before launch.
- Redis failure policy must be explicit per responsibility: fail open for optional caches, fail closed for authorization or risk controls, return duplicate or pending states for idempotency, and expose retry or repair for workflow coordination.

## Cache Stampede Architecture

- For any cache fronting an expensive source of truth, architecture names the stampede defense: single-flight (one fetcher per key), negative caching with shorter TTL for misses, and randomized TTL jitter. Architecture also names the staleness budget so the team can pick the right combination.
- Multi-tier caches (in-process in front of Redis in front of DB) need a coherent invalidation contract: Pub/Sub fan-out, topology-change events, or explicit delete-on-write. Architecture names the chosen mechanism per cache tier.

## Cluster Topology Boundary

- If Redis is deployed as Cluster, architecture declares the hash-tag convention and which keys must share a slot. Cross-slot Lua, `MULTI/EXEC`, and dependent pipelines are architectural decisions encoded in the key schema, not coincidence.
- Cluster failover, slot migration, and topology refresh are owned at the platform layer; this skill names the client's expected behavior (refresh on `MOVED`/`ASK`, retry on topology change, idempotency on the retry path).

## TLS And Managed-Auth Boundary

- Production Redis traffic must be authenticated and encrypted. For self-hosted Redis this means TLS plus ACL users with least-privilege command grants; for cloud-managed Redis it may additionally mean IAM/AAD short-lived tokens via a per-connection auth callback. Architecture names the trust anchor and credential lifetime.
- Application users get the minimum command set; cluster-wide admin commands (`FLUSHDB`, `CONFIG`, `DEBUG`) are not part of application grants.

## Retry And Circuit Breaker Ownership

- Retry policy and circuit breaker for Redis access live at the dependency-assembly layer, not scattered through call sites. Architecture names the transient-error catalog and the breaker scope.
- Breaker-open behavior is a product contract: cache-miss path may return stale-OK, authz path must fail closed, idempotency path returns "duplicate uncertain". Architecture names the per-responsibility semantics rather than letting the resilience layer pick silently.
