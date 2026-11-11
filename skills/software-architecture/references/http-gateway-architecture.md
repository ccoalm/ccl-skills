# HTTP Gateway Architecture

Use this when designing an HTTP API layer, generated HTTP routes, gateway-to-RPC mapping, or generated HTTP clients.

## Boundary

- Treat the HTTP gateway as a transport boundary, not the owner of core domain behavior.
- Public HTTP contracts and internal RPC contracts may share protobuf inputs only when their stability, trust, and validation needs are the same.
- Generated route files, generated DTOs, and generated clients are output surfaces; hand-written code should live in extension points that generators preserve.
- Generated handlers may be a scaffold, but final handlers should explicitly call application logic, map errors, and return canonical responses.
- Keep custom routes separate from generated routes unless the generator provides a stable insertion point.

## Route And Middleware Design

- Derive method, path, path/query/body/header binding, and docs from IDL annotations or one authoritative route source.
- Route groups should mirror path and trust boundaries, not incidental folder structure.
- Middleware should be ordered deliberately: request context, tracing/log id, authentication, authorization, validation, recovery/error mapping, metrics/logging, then handler logic.
- Bypass middleware should be explicit, reviewed, and small.
- Generated middleware hooks should default to no-op and require intentional implementation.

## Handler Responsibilities

- Handlers bind and validate transport input, resolve caller context, call application logic, and map output to the HTTP contract.
- Do not put transactions, complex queries, fan-out, or long-running work directly in handlers.
- Validation errors, auth failures, dependency failures, and domain failures should map to stable HTTP status and canonical error code/message semantics.
- API docs should describe the public contract, not internal implementation names.

## Generated HTTP Client Policy

- Generated clients should expose typed request/response methods while allowing caller-supplied context, headers, request options, middleware, and response-result policy.
- Service discovery or host selection should be explicit; do not mix relative generated paths with hidden global endpoints.
- Response success must consider both HTTP status and the API envelope when one exists.
- Client wrappers should handle compression, content type, path escaping, repeated query fields, and typed error bodies consistently.
- Generated client code should be reproducible and reviewed separately from handwritten adapter logic.

## IDL-First Three-Tier Layout

- Architecture standardizes a three-tier layout for IDL-driven HTTP gateways: generated router (IDL → URL/verb binding), thin handwritten stubs (request struct + BindAndValidate + dispatch), and business handler (application logic). The three tiers exist so IDL evolution does not force handler rewrites and so handlers do not duplicate validation.
- The stub tier is a stable seam: when initially generated, freeze it with a "do not hand-edit" marker; subsequent regeneration may overwrite. Business logic does not live in the stub tier under any circumstance.
- Generated router files and stubs both carry the generated-file convention; reformatters and linters must skip them.

## Middleware Composition Across Layers

- The middleware contract has two layers: the framework default (recovery, context injection, metrics, tenant/identity propagation, tracing) registered inside the server-construction helper, and the business-level middleware (CORS, auth/login, request logging, custom context) registered in service `main()`.
- Architecture writes down both layers and the resulting effective order so service authors and reviewers can see the full stack. Hidden defaults plus invisible business overrides lead to ordering bugs that surface only under load.
- Recovery middleware sanitizes the response: a stable error code and a generic message reach the client; the panic value, stack trace, and internal error chain stay in the log/trace. Information disclosure through recovery is a security finding.
- An empty middleware stub (declared but not implemented) is dead code and should not ship.

## Long-Lived Connection Handling (WebSocket / SSE / long-poll)

Distinct from request/response handlers: long-lived connections (WebSocket, Server-Sent Events, long-poll) hold one socket per active user for minutes to hours and have a separate failure mode set. The release-side client-of-progress-stream concerns live in `go-microservice-dev/references/release-ops-patterns.md` (Release CLI section); the architecture rules below govern the *server* holding the connections.

- **Origin / handshake check is production-strict**: the WebSocket-upgrade and EventSource-upgrade `Origin` check is the browser-CSRF defense for these protocols (long-poll uses normal HTTP CORS); disabling it ("`CheckOrigin: always true`") is acceptable only for non-production environments and MUST be guarded by an explicit `env.IsProd()`-style condition with the production branch enforcing an allowlist. Origin headers are spoofable from non-browser clients, so the Origin check is the browser-CSRF defense only; cross-origin auth on the connection itself still requires a session cookie / token bound to the user.
- **Handshake / idle / liveness — per-protocol**:
  - *WebSocket*: HandshakeTimeout (typical 5-10s, prevents slow-loris on upgrade); per-connection read deadline refreshed on each ping/pong or business message; server-initiated application-level ping at a documented interval (typical 30s) with close on missed-pong.
  - *SSE*: write deadline on each event; server-emitted heartbeat comment (`: ping\n\n` or named-event no-op) at a documented interval (typical 15-30s); reverse-proxy buffering disabled (`X-Accel-Buffering: no` or framework equivalent) so heartbeats are not held in a buffer.
  - *Long-poll*: bounded request timeout on the server side (typical 30-60s — must be shorter than ingress/LB idle timeout to surface as orderly close, not a TCP reset); reconnect cadence is the client's contract and the server returns an empty-result response immediately on timeout so the client can reconnect.

  Absence of the protocol's liveness contract lets dead connections accumulate until file-descriptor exhaustion.

- **Identity key is the full tuple `(app, tenant, user)` everywhere — never bare `user_id`**: the connection registry, the cap counter, the consistent-hash routing key, the broker channel name, the presence-index ownership key, and the read/write paths all use the same tuple. Bare `user_id` collides across tenants and apps: tenant A user 42 and tenant B user 42 share the same routing slot, the same cap bucket, the same channel, and the same presence owner — silent cross-tenant message delivery and cap-bucket sharing. The tuple is treated as one opaque composite key (e.g. hash of all three) in routing functions; the parts are never recombined downstream by a different rule.
- **Per-user connection cap is enforced through shared state, not per-replica registry alone**: a per-replica registry counts only that replica's connections; with N replicas and naive enforcement, effective cap = `cap × N`. Enforce the cap, keyed by `(app, tenant, user)`, through one of: (a) consistent-hash routing of inbound connections by the `(app, tenant, user)` tuple at the ingress (so per-replica cap *is* the effective cap), (b) a shared lease / counter (Redis `INCR` on the tuple-keyed counter with TTL, refreshed on heartbeat; decrement on disconnect — and a sweep job to release stale leases when a replica dies), or (c) the presence-index service from the fan-out rule below also owning the count. Documented policy on cap-hit (kick oldest, reject new, structured error) AND the policy holds identically across replicas because the counter is shared.
- **Multi-replica fan-out story is explicit AND the send path is consistent with the connection path**: in-process connection registries are ephemeral and per-replica. When the notify-to-user path traverses multiple replicas (the most common case: any replica can receive an incoming "send" while a different replica holds the user's connection), the architecture names ONE of (all keyed by the same `(app, tenant, user)` tuple as the registry):
  - **(a) Consistent send + connection routing**: both the inbound user connection AND the inbound "send to user" RPC are consistent-hash routed by the same `(app, tenant, user)` tuple at the ingress, so they always land on the same replica. Sticky connection routing alone is NOT sufficient — if the send path is normally load-balanced while connections are sticky, sends land on replica A while the connection is on replica B and the user never receives the message.
  - **(b) Broker-mediated fan-out**: the inbound send writes to a channel keyed by `(app, tenant, user)` (Redis Pub/Sub, NATS, internal MQ) and every replica subscribes and delivers to its locally-held connections. The send replica does not need to know which replica holds the connection.
  - **(c) Presence-index service**: a separate service maps `(app, tenant, user) → owning-replica`; the send-receiving replica looks up the owner and RPC-calls that replica. Presence-index needs its own lease / heartbeat so a dead owning-replica's users are remapped.
- **Concurrent writes to one connection MUST hold a per-connection write mutex**: WebSocket / SSE framing corrupts if two goroutines write simultaneously to the same connection. The mutex protects only writes (reads are inherently single-reader). A buffer pool (`sync.Pool` of `bytes.Buffer`) for write payloads reduces allocation but does not substitute for the write mutex.
- **Close handling distinguishes graceful close from network drop**: server reads a `CloseMessage` (graceful) versus the read returning an error (drop); both paths MUST remove the entry from the connection registry, decrement the shared per-user counter (per the cap rule), and release the per-user slot — leaking a registry entry blocks the user from reconnecting.
- **Connection-state vs message-state are different stores**: "is user X currently connected" lives in a shared cache (Redis with short TTL) for cross-replica visibility AND the unread-message-count for offline users; the message inbox itself lives in a durable store (DB) so disconnected users get history on next pull. Conflating "presence cache" with "message store" loses messages on cache eviction.
- **Backpressure: bound by items AND bytes AND aggregate memory**: per-connection outbound queue capped by item count (typical: low double-digits) AND per-connection byte budget (item count alone allows a single large message to OOM the connection) AND per-message size limit (server rejects oversized payloads before they enter the queue). Aggregate process / pod outbound-buffer memory is bounded with shedding — when the global budget is hit, shed lowest-priority deliveries or close slowest connections rather than waiting for OOM-kill. On per-connection overflow, either close the connection (the client will reconnect and pull from the durable inbox) or drop the in-flight delivery and rely on the durable inbox + the client's pull path. Item-count bounds without byte bounds are an OOM-by-large-message vector; per-connection bounds without aggregate bounds are an OOM-by-many-slow-clients vector.

## Framework Version Baseline (CloudWeGo Hertz)

- **Hertz v0.10 (released 2025-05) baseline shifts to track**: (a) **first-class SSE handler integration** — services standing up SSE no longer need a third-party SSE library on top of Hertz; the new built-in SSE helper handles framing, heartbeat emission, and connection close per the SSE rules in the Long-Lived Connection Handling section above (still on the team to implement origin check, per-user cap, multi-replica fan-out — Hertz only owns the per-connection write side). (b) **`http.Handler` adapter** lets a Hertz route delegate to a stdlib `net/http.Handler` — useful when a third-party library (Prometheus exporter, pprof, generic OAuth library) only ships a stdlib handler; before v0.10 those needed custom wrappers. (c) **HTTP/3 + QUIC remain `hertz-contrib/http3` (separate module on `quic-go`), NOT in Hertz core** — the architecture must declare HTTP/3 as a deliberate adoption (extra deployment surface, quic-go upgrade cadence, observability gaps) rather than a Hertz version-bump side effect. ALPN + Alt-Svc + QUIC/TLS parallel-listen support shipped earlier (v0.5+), so the wire side has been stable for a while; the contrib package is the integration point. Pin Hertz minor versions in `go.mod` and re-run smoke tests on any minor bump.
