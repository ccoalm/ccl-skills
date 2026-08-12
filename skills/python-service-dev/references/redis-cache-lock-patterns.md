# Redis Cache Lock Patterns

Use this for Redis clients, keys, caches, locks, rate limits, and idempotency.

## Implementation

- Centralize key builders and TTL constants.
- Include tenant/user/resource scope in keys when isolation matters.
- Use unique values for locks and compare-and-delete unlock.
- Renew locks with compare-and-expire when work can exceed one lease, and stop renewal on cancellation, timeout, or max lease.
- Set timeouts on Redis clients.
- Choose sync or async Redis clients to match the call path. Do not call sync Redis clients directly inside async request handlers or long-lived async loops unless the call is isolated through a thread/process boundary.
- Build Redis clients through dependency assembly or app lifespan, and close clients/pools on shutdown. Per-request connect/read/close loops are acceptable only for narrow scripts or tools, not hot service paths.
- Prefix keys through one adapter and keep pattern deletes bounded. If a method deletes by pattern, prefer `SCAN` with a limit/batch policy, observability, and tests for no-match and large-match behavior.
- For JSON cache values, validate decode and schema. Treat malformed cached payloads as explicit cache corruption or miss according to product risk, and avoid letting decode errors bypass source-of-truth checks.
- For compound atomic operations, use Lua scripts, Redis transactions, or a proven library rather than read-modify-write. Examples include compare-and-set, compare-and-delete, compare-and-expire, positive-only decrement, increment-if-exists, and atomic pop.
- Define explicit return meanings for success, compare failure, and missing key; callers should not infer these from raw Redis values.
- If using Lua scripts, load or register scripts during startup when possible; on missing script cache, reload and fall back once while emitting an observable metric or log.
- Idempotency stores need separate pending, completed, duplicate, and retryable-failure meanings. A pending marker should have a short TTL or owner lease; a completed marker should live for the dedupe window; retry counters should fail safe when Redis is unavailable on high-risk paths.
- Redis Streams need an explicit delivery contract: starting message id, heartbeat/no-message behavior, stream TTL/trim/delete policy, reconnect/resume behavior, and whether messages may be replayed or lost.
- Do not let cache misses silently bypass authorization or data-integrity checks.
- Keep cache invalidation close to writes or explicit events.

## Tests

- Use fake Redis for service-level tests when behavior is simple.
- Use real Redis integration tests for locks, scripts, expiration, or cluster-specific behavior.
- Test wrong-token unlock, renewal cancellation, missing-key semantics, malformed JSON payloads, pattern-delete boundaries, script reload/fallback, invalid return type handling, pending-vs-completed idempotency states, stream heartbeat/resume, and positive-only counters when those helpers exist.

## Cache Stampede Defense

Concurrent cache misses on a hot key turn into a thundering herd on the source of truth. Three defenses combine; pick all when miss cost is high.

- Single-flight: when a miss is detected, only one coroutine/process performs the fetch while others wait or read a placeholder. Implement with a per-key `asyncio.Lock` in-process, plus a short-lived Redis lock (`SET NX PX`) for cross-process coordination; followers re-read the cache after the leader publishes the value.
- Negative caching: cache the "not found" outcome with a shorter TTL (a few seconds to a minute) using a distinguishable sentinel value so distinct miss reasons (no row vs auth-denied) do not collapse into one cache entry.
- TTL jitter: add randomized ±10-20% to every TTL so bulk-loaded keys do not expire in lockstep. Apply jitter at write time, not at read time.
- For very hot read-mostly data, layer a short-TTL local cache in front of Redis so even Redis sees a flat load curve; coordinate invalidation through Pub/Sub or `CLIENT TRACKING` (RESP3) when staleness budget is tight.

## Redis Cluster Slot And Hash Tag Rules

When the deployment is Redis Cluster (or Cluster-compatible managed Redis), every multi-key operation must stay within a single hash slot.

- Multi-key commands, `MULTI/EXEC`, Lua scripts, and pipelines that depend on key co-location must use hash tags: `user:{uid}:profile` and `user:{uid}:settings` share a slot because `{uid}` is the tagged section; `user:uid:profile` and `user:uid:settings` do not.
- A Lua script that touches keys passed via `KEYS[]` will be rejected with `CROSSSLOT` if those keys hash to different slots; design key schemas with the smallest co-location set you need (per-user, per-tenant, per-aggregate) and document the hash-tag convention next to the key builder.
- `SCAN` walks one cluster node at a time; cluster-aware delete-by-pattern means iterating all primary nodes, not the cluster as one space.
- Pipelines across slots split into per-slot batches; do not assume a single round-trip.
- Cluster clients refresh slot maps on `MOVED`/`ASK` responses; for very latency-sensitive paths cache the slot map in the client and refresh proactively on cluster topology change events.

## TLS And IAM Authentication

Production Redis traffic must be authenticated and encrypted; cloud-managed Redis adds IAM/AAD-based auth on top of (or instead of) static passwords.

- Connect with TLS for any non-loopback Redis: pass `ssl=True` and a configured `ssl.SSLContext` to `redis.asyncio.Redis`. Share the `SSLContext` across clients to amortize handshake setup.
- For managed Redis with IAM/AAD auth (AWS ElastiCache IAM, Azure Cache for Redis with AAD), credentials are short-lived tokens fetched per connection: configure the client with an auth callback that retrieves a fresh token (e.g., via boto3/azure-identity) and handle the token's TTL by rotating before expiry.
- Use Redis ACL users for application accounts: grant the minimum command set required (no `FLUSHDB`, `CONFIG`, `DEBUG`, `KEYS`); store credentials through the platform secret provider, never inline in code or config files.
- Do not log connection URLs that contain passwords or tokens; redact at the logger configuration layer.

## Retry And Circuit Breaker Coordination

Transient Redis errors (timeout, connection reset, `LOADING`, `BUSY`) sometimes warrant a retry; sustained failure warrants opening a circuit.

- Retry only for transient errors: connection errors, read/write timeouts on idempotent reads, `LOADING`, and `BUSY` (script in progress). Do not retry application-level errors, wrong-type errors, or write commands when retry could double-apply.
- Bound retries: max attempt count, exponential backoff with jitter, total deadline. A retry budget per request prevents amplification.
- Pair retry with a circuit breaker per upstream identity (Redis cluster endpoint, sentinel set): open after consecutive failures, half-open after a cool-down probe, close on success. Do not retry inside an open circuit — return the fast-fail outcome the product has chosen for that path.
- Coordinate with the lock and idempotency layer: a retry against a lock that you already hold should `COMPARE-AND-EXPIRE` not re-acquire; a retry against an idempotency store should treat duplicate `claimed` as success.
- Surface retry count, breaker state transitions, and budget exhaustion as metrics; sustained breaker-open is a paging condition, not a normal mode.

## OpenTelemetry Instrumentation Across Await

Async Python loses span context easily when tasks are created outside the current `await` chain.

- Use OTel auto-instrumentation for SQLAlchemy and Redis when the package is available (`opentelemetry-instrumentation-sqlalchemy`, `opentelemetry-instrumentation-redis`); enable it once at app startup.
- For `asyncio.create_task`, `asyncio.gather`, and background workers, contextvars snapshot at task creation time — spans created in the parent after the child starts will not be visible to the child. Capture and re-attach context explicitly when launching a task that should join the parent trace (`context.attach(snapshot)` inside the task; `contextvars.copy_context().run(...)` for sync code launched from async).
- Emit DB and Redis attributes per OTel semantic conventions: `db.system`, `db.name`, `db.statement` (sanitized), `db.operation`, `network.peer.address`; for Redis, also `db.redis.database_index` when applicable.
- Do not emit raw SQL or raw key payloads as span attributes when they may contain secrets; use the framework's sanitization hook or a custom span processor.
- Long-running coroutines and SSE/websocket handlers should periodically end the per-message span instead of one giant span per connection; otherwise traces become unusable.

Evidence note: rules above derive from public specifications (SQLAlchemy 2.0 Async docs, Redis Cluster spec, Redis ACL/TLS docs, OpenTelemetry semantic conventions) and documented industry patterns (Cache-Aside variants, Circuit Breaker, Outbox via cross-stack reference). Lua/CAS/script-fallback rules earlier in this file were generalized from external Go evidence; under the portfolio-stability prefilter, the portfolio is not a confirmation baseline, so caveat wording elsewhere should be read as "generic best-practice baseline" rather than "pending verification".
