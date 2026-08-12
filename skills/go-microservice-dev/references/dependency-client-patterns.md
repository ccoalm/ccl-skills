# Dependency Client Patterns

Use this when implementing reusable clients or adapters for dependencies.

## Secret Client

- Hide secret reads behind typed methods such as `GetDatabaseCredential`, `GetQueueCredential`, `GetObjectStorageCredential`, or `GetAppCredential`.
- Apply a request timeout to secret reads and wrap errors with the secret class, not the secret value.
- Decode JSON secret payloads into typed structs and validate required fields.
- Cache temporary credentials under a mutex or singleflight and refresh before expiry.
- For write/admin secret APIs, require explicit call sites and audit logging.
- Redact secrets from logs, test output, panic messages, and generated docs.
- Convenience package-level clients must be replaceable by constructors or DI for tests. If a client can panic during initialization, keep that path in bootstrap code and expose a constructor that returns errors for request-time dependencies.

## Service Discovery Client

- Create discovery clients once in DI and pass them to RPC/HTTP client builders.
- Use healthy-only lookup by default.
- Support metadata filters such as lane/environment through typed tags.
- If lane lookup misses, fall back only to an explicit baseline lane.
- Return a clear dependency error when no instance is available; do not fabricate endpoints.

## Internal RPC Proxy Adapter

- Require an explicit target-service field in trusted metadata or a typed proxy request; reject empty or malformed destinations before opening downstream connections.
- Resolve targets through the runtime discovery policy: in-cluster service DNS when appropriate, otherwise same-lane lookup with explicit baseline fallback.
- Preserve trace/log id, lane/environment, and caller service identity in outgoing metadata; do not forward unreviewed headers or credentials blindly.
- Bound connection pools, return or close connections deterministically, and propagate context cancellation to both upstream and downstream streams.
- Isolate transport-specific reflection or frame-copying code behind a narrow adapter with tests for metadata propagation, connection cleanup, EOF handling, and downstream selection failure. When codegen output shape varies, prefer a documented interface method with a direct-then-unwrap fallback over reflecting into generated structs; reflection here is a smell, and the reflective fallback must emit an observability signal when it fails to find the field, or propagation breaks silently.

## Dynamic Config Client

- When etcd backs dynamic config, prefer a small store adapter or typed client boundary; do not let etcd imports or raw keys leak into domain, application, or transport code.
- For local-first KMS over dynamic config, provide an in-memory store for fast tests and verify encrypted envelopes, missing master key failure, missing secret failure, and readiness behavior.
- Wrap dynamic config keys behind typed methods instead of exposing raw string keys throughout application code.
- Centralize namespace and backend key construction in the client; list/watch APIs should return caller-facing keys or documented resume markers, not raw backend prefixes by accident.
- Use bounded timeouts for get, set, delete, and watch operations.
- Decode JSON config into typed structs and validate required fields before use.
- Cache read-heavy keys with TTL; distinguish not found, decode error, and remote dependency error.
- Listener callbacks should recover panics, update local cache, and stop cleanly when the parent context is canceled.
- Tests should cover default behavior when config is missing or malformed.

## HTTP Client Wrapper

- Provide helpers for constructing requests, attaching discovery options, setting headers, and executing with timeout.
- Use `DoTimeout` or a context deadline for every outbound call.
- **A middleware / client WRAPPER (interceptor, governance layer) owns deadline *propagation*, not a fixed timeout *policy* — but every production call still gets a bounded effective deadline.** Honor the caller's `context` deadline; don't bake an arbitrary fixed default (a hardcoded `30s`) into the wrapper that overrides it. But "no wrapper default" ≠ "unbounded": a `context.Background()` caller plus a hung dependency pins goroutines/connections forever, so the wrapper applies an **env-configured max backstop** as the effective deadline when the caller supplies none, overridable at the call site, with an explicit documented opt-out only for long-lived watch/stream calls **that still bound their own liveness** (idle/read timeout, heartbeat, bounded reconnect, cancel cleanup) — the opt-out is from the single request deadline, not from all bounds, or a half-open stream pins resources forever. Clamp **every untrusted/external inbound deadline** — an inbound gRPC `grpc-timeout` as much as an HTTP deadline header — to platform min/max **before** honoring or propagating it, or an external caller sets a huge deadline to hold resources (slow-DoS). Propagate with the transport's **native** decrementing mechanism where it exists (gRPC `grpc-timeout`, not a reinvented `x-rpc-timeout-ms`); HTTP has **no** native on-wire deadline, so cross-hop propagation over HTTP needs an explicit deadline-header contract — strip any caller-supplied one at ingress and generate the internal header from the server-side (clamped) effective context. Don't add an *independent competing* timer, but a **derived** per-attempt cap is correct — `per-attempt = min(caller-remaining, configured max)`; and before each retry/hedge recompute the remaining budget and **skip** the attempt when it can't cover attempt + backoff + cleanup (doomed retries amplify overload).
- Always close response bodies when using standard HTTP APIs.
- Parse response status and body separately; do not treat a 200 transport status as domain success automatically.
- Keep redirect behavior explicit.
- Include operation name, callee service, status code, duration, and canonical error code in logs/metrics.

## Object Storage Adapter

- Build object storage clients from config plus secret provider credentials.
- Default endpoint selection can depend on runtime environment, but the choice must be explicit and testable.
- Add source service, lane/environment, and trace/log id metadata or tags on writes when supported.
- Wrap provider errors into typed categories: not found, forbidden, retryable server error, client/config error.
- For uploads, validate content size, content type, key namespace, and idempotency before writing.
- For downloads, support `Head` before `Get` when size, range, or existence matters.
- For multipart upload, define part iterator, part numbering, completion, and cleanup-on-error behavior.
- For object copy or migration tools, define overwrite/conflict policy before transfer, tag migrated objects with source identity, emit replayable success/error/conflict records, bound concurrency, and flush/close log writers on shutdown.
- For signed URLs, require explicit expiry and never log the full URL if it contains credentials.

## Search Or Document Store Adapter

- Wrap index or collection access behind repository interfaces; do not let handlers build raw provider queries.
- Build clients with timeout, pool bounds, tracing, health policy, and credentials from the secret provider.
- Keep index names, collection names, mappings, and versioning policy near the adapter or migration package.
- Validate filters through an allowlist and enforce max limit plus stable sorting before executing queries.
- Treat bulk writes as partially successful until per-item results are inspected.
- Tests should cover query construction, pagination, empty result behavior, and retryable write failures.

## ID Generator Client

- Wrap ID allocation behind a small interface such as `Next(ctx)` and `Batch(ctx, n)`.
- Validate namespace and requested count at the boundary.
- Batch prefetch may improve latency, but cache size must be bounded and refill errors must not spin hot.
- `Next` should time out quickly and return an ordinary error.
- If using local fallback, log it as degraded behavior and keep the fallback generator's node/namespace uniqueness explicit.
- Propagate caller identity and trace/log id to central ID services.

### In-process ID generator (snowflake-style)

Applies when the architecture chose a local-only generator OR when the central client falls back to a local one. The architecture-level "in-process vs central vs DB-issued" decision lives in `go-microservice-architecture/references/dependency-platform.md` (ID Generation section); the rules here govern how the local generator must behave once that choice is made.

- **Bit layout is a frozen contract**: document the layout once (e.g., `41-bit timestamp + 8-bit namespace + 4-bit node + 10-bit counter`) and the epoch (`baseTs`) alongside it. Changing widths or order invalidates every previously-issued ID that any consumer parses by position; treat layout changes as a versioned migration with an epoch bump, not an in-place edit.
- **Counter width sizes the per-generator per-millisecond peak**: 10 bits is 1024 IDs/ms per generator, 12 bits is 4096/ms. When the millisecond's counter exhausts, the generator yields (short `Sleep` or runtime yield, not a raw spin) until the next millisecond — never overflow into adjacent bit fields (namespace or node), which silently collides IDs with another logical generator. The wait is bounded by both the caller's context deadline AND a documented per-generator cap (typical: low milliseconds for counter rollover, longer for clock-backward stall); whichever fires first returns an ordinary timeout error rather than block past it. A `context.Background()` caller still hits the per-generator cap — never block indefinitely on a stalled wall clock. The same discipline applies to the clock-backward stall below.
- **Clock-backward protection is mandatory, not advisory**: persist `last_issued_ts` in-memory across a process lifetime. On every issue, refuse or stall when `now < last_issued_ts`. Logging a warning while issuing the ID is not protection — NTP slew, VM pause-replay, container start before time sync, and operator clock reset all produce backward clocks; without refusal, duplicates are issued for the entire backward window. Stalls are bounded by caller deadline AND a per-generator cap as above; on exceed, return an error rather than block.
- **Restart safety when `(namespace, node)` is reused**: persisting in-memory state only is insufficient — a crash-restart cycle inside the same millisecond resets the in-memory counter to zero and re-issues the IDs already emitted that millisecond, without any clock rewind. When `(namespace, node)` is reusable across restarts (the common case for stable-identity replicas), the generator MUST do one of:
  - **(a) Skip-the-partial-millisecond**: persist `last_issued_ts` durably and, on startup, refuse to issue until wall time strictly exceeds the persisted value. Durable write of `last_issued_ts` must occur BEFORE the ID with that timestamp is observable to the caller (write-ahead, not async flush, not shutdown-only flush) — otherwise a crash between "ID returned" and "state persisted" leaves the persisted high-water mark below the issued ts and the next startup re-issues into that millisecond. Per-call durable writes are expensive; the common implementation amortizes by reserving the next millisecond durably (write `last_issued_ts = now_ms + 1` before issuing any ID in `now_ms`).
  - **(b) Resume-the-counter**: persist `(last_issued_ts, last_counter)` durably and resume from `last_counter + 1` within the same millisecond on startup. The same write-ahead durability rule applies as in (a). Option (b) does NOT replace the clock-backward refusal above: when the host clock restarts below the persisted `last_issued_ts` (container before NTP sync, operator reset), the generator MUST still refuse-or-stall until wall time catches up, otherwise it re-issues timestamps from the rewound window.
  - **(c) Incarnation / fencing epoch**: include an incarnation epoch in the bit layout (sub-allocated from the node-id bits) that increments monotonically per process restart and is allocated by an external registry. The epoch field MUST fail closed on exhaustion: when the encoded width has wrapped or the registry refuses, the generator refuses to start and the operator either rotates to a fresh node-id namespace or widens the epoch field with an epoch-bump migration. A rapid crash loop within one millisecond can exhaust a small epoch field; the registry's allocation contract guarantees no epoch reuse within the timestamp collision window (typical: epoch is never reused, period).

  Persisting only across "host clock can rewind across restart" cases is too narrow; same-ms restart re-issuance does not require a clock rewind to occur.
- **Field-width masking uses `(1<<bits)-1`, not `1<<bits`**: masking a configured `node_id` or `namespace_id` with `value & (1<<bits)` keeps only the high bit and zeroes the rest, which collapses many distinct IDs into one. The correct mask is `(1<<bits) - 1`. Validate inputs at boundary; clamp documented.
- **Node id and namespace id come from a uniqueness-enforced source**: k8s StatefulSet ordinal, a centralized allocator that registers and revokes on shutdown, or a pinned per-host config with a registry of assignments. "Random in range" is a finding; the bit budget is small (typically 4-10 bits combined) and birthday collisions are easy. Two replicas with the same `(namespace, node)` re-issue duplicates within the same millisecond.
- **Singleton per process AND per (namespace, node)**: multiple generator instances in the same process sharing the same `(namespace, node)` re-issue duplicates because each holds its own counter / `last_issued_ts` state. If sharded generators are needed (per-CPU, per-shard), partition the node-id bits across them; do not partition the counter bits.
- **Concurrent callers serialize through a mutex on (counter, last_issued_ts)**: lock-free atomics are valid only when bit-pack, clock-backward check, and counter-rollover-to-next-millisecond wait fit into a single CAS loop. Default to mutex; only optimize when contention is measured.
- **Wall clock, not monotonic**: IDs encode wall time for cross-process orderability, so `time.Now().UnixMilli()` (or equivalent) is the time source. The clock-backward check on `last_issued_ts` catches wall-time non-monotonicity — that is what protects correctness, not the choice of clock source.
- **Local-fallback discipline**: when the in-process generator is a fallback for a central ID service, the fallback's node-id MUST come from a different pool than the central generators (a reserved high-bit prefix, or a fallback-only namespace) so post-incident reconciliation can distinguish central IDs from fallback IDs. Fallback issuance is a degraded-mode metric; never silent.

## Queue And Task Clients

For full consumer implementation, activation, retry/drop, and observability rules, also apply `mq-consumer-patterns.md`.

- Producers should attach trace/log id and lane/environment metadata to every message when the queue supports properties.
- Consumer constructors should read topic, group, worker count, retry count, filter tags, and mode from typed config.
- Ordered consumers must reduce concurrency to one or otherwise prove ordering is preserved.
- Consumer handlers should decode into typed payloads, validate, then call application logic.
- Return retry for transient dependency errors; return success after logging for permanent malformed payloads.
- For delayed tasks, put delay, queue name, timeout, and max retry in config rather than literals.
- For Redis-backed task queues, create producer, server, and inspector as separate DI dependencies.

## Bounded Fan-Out

- Use a shared helper or local pattern for bounded concurrency instead of open-ended goroutines.
- Configurable knobs should include limit, timeout, retry count, retry interval, and ignore-error behavior.
- Preserve task index or key with each result so callers can reconstruct slices or maps.
- Cancel remaining work on first error only when partial results are not useful.
- Keep retry sleeps bounded by context deadline.

## Dynamic Config Key Convention (Etcd / Config Center)

When the dynamic config backend is etcd or an etcd-style key-value store, the key scheme is part of the cross-service contract.

- Use a structured key pattern such as `/{service}/{namespace}/{key}` where `service` identifies the owning platform service identifier, `namespace` separates logical config domains (e.g. `db_shard`, `rate_limit`, `feature_flag`), and `key` is the leaf. Never let raw etcd keys leak into application code — wrap with typed accessors.
- Periodic endpoint discovery: when the etcd endpoint list itself comes from service discovery (Nacos / Consul / k8s services), refresh the endpoint list on a bounded cadence (10–30 s is typical) in a background goroutine — NOT on the hot request path. Lazy refresh on next operation makes the refresh + reconnect cost (DNS lookup, TLS handshake) land on a user request during endpoint churn, and lets concurrent requests stampede the reconnect. Use singleflight to deduplicate concurrent reconnects and serve last-known-good endpoints with a bounded staleness window while the background refresh runs.
- For dynamic config that backs production-critical data (DB sharding map, rate-limit budget, feature flag), distinguish three failure modes: key not found, decode error, and remote/transient error. The product contract decides which falls back to the cached value, which fails closed, and which fails open.
- Watch callbacks (`AddListener`) must recover from panics, update the local cache atomically, and stop cleanly on parent-ctx cancellation. A watch goroutine that crashes silently is harder to detect than a missing watcher.
