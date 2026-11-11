# Redis Cache Coordination

Use this for Redis cache, locks, rate limits, counters, idempotency windows, and ephemeral coordination.

## Rules

- Redis is not durable source of truth for auditable state.
- Centralize key names, TTLs, namespaces, lock leases, and rate-limit windows.
- Use unique lock values and compare-and-delete unlock semantics.
- TTL policy is part of architecture, not an implementation afterthought.
- Cache invalidation must have an owner: write-through, event-driven invalidation, explicit delete, or time-bounded staleness.
- If Redis is used for idempotency, separate pending claim, completed marker, duplicate, and retryable-failure states. Pending claims need a lease/TTL and completed markers need a dedupe window that matches the external retry horizon.
- Redis Streams, Pub/Sub, lists, and sorted sets are not interchangeable. Name the delivery guarantee: fire-and-forget notification, replayable stream, deduplicated pending work, delayed scheduling, or durable queue backed by DB/MQ.
- Broad pattern deletion and stream cleanup need a bounded strategy. Architecture should state whether cleanup is batched, TTL-driven, event-driven, or an admin/backfill operation.
- Redis failure policy must be per responsibility: fail open for optional caches, fail closed for authorization/risk controls, return duplicate/pending states for idempotency, and expose repair/retry for workflow coordination.

## Python Notes

- Choose sync or async Redis clients according to the service stack.
- Do not use a sync Redis client directly in async endpoints unless isolated.
- Connection pools, timeouts, and retries should be configured once through dependency assembly.

## Cache Stampede Architecture

- For any cache fronting an expensive source of truth, architecture names the stampede defense: single-flight (one fetcher per key), negative caching with shorter TTL for misses, and randomized TTL jitter. Architecture also names the staleness budget so the team can pick the right combination.
- Multi-tier caches (process-local in front of Redis in front of DB) need a coherent invalidation contract: Pub/Sub fan-out, `CLIENT TRACKING` (RESP3) for short-staleness reads, or explicit delete-on-write. Architecture names the chosen mechanism per cache tier.

## Cluster Topology Boundary

- If Redis is deployed as Cluster (or Cluster-compatible managed service), architecture declares the hash-tag convention and the keys that must share a slot. Cross-slot Lua, `MULTI/EXEC`, and pipeline-with-dependencies are architectural decisions, not coincidence; the key schema is the contract.
- Cluster failover, slot migration, and topology refresh behavior is owned at the platform layer; this skill names the client's expected behavior (refresh on `MOVED`/`ASK`, retry on topology change, idempotency on the retry path).

## Authentication And Encryption Responsibility

- Production Redis must be authenticated and encrypted. TLS is required for any non-loopback traffic; the auth model is whichever the chosen Redis provider supports — ACL user + password, mTLS client certificates, or short-lived IAM/AAD tokens. Architecture names the trust anchor (managed CA, internal PKI) and the credential lifetime, and treats the provider's strongest supported option as the default.
- Redis ACL users follow least-privilege: per-service users with explicit command lists. Cluster-wide admin commands (`FLUSHDB`, `CONFIG`, `DEBUG`) are not part of application user grants.

## Retry And Circuit Breaker Ownership

- Retry policy and circuit breaker for Redis access live at the dependency-assembly layer, not scattered through call sites. Architecture names the transient-error catalog (timeout, connection reset, `LOADING`, `BUSY`) and the breaker scope (per-endpoint, per-shard).
- Breaker-open behavior is a product contract: cache-miss path may return stale-OK, authz path must fail closed, idempotency path returns "duplicate uncertain". Architecture names the per-responsibility breaker semantics; do not let the resilience layer pick silently.
