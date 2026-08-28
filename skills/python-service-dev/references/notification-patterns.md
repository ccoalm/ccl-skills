# Notification Patterns

Use this when implementing notification clients, webhooks, operator alerts, outbound callbacks, or delivery jobs. For durable delivery state, retries, and terminal-state behavior, also apply `state-machine-task-patterns.md`. (Inbound callback *verification* is `public-api-security-patterns.md`; this file owns the outbound side.)

Sibling note: `go-microservice-dev/references/notification-patterns.md` carries the Go rendering; adapted per stack, kept in sync by review (not under the parallel-stack parity gate).

## Client

- Wrap each delivery provider behind a `typing.Protocol` with a `send(message) -> Result` surface (`dependency-client-patterns.md` owns the Protocol-vs-ABC rule).
- Build requests with deadlines, content type, status-code validation, and response body size limits.
- Treat empty message batches as no-op.
- Parse provider responses into canonical success, retryable error, and permanent error.
- **Outbound URLs are an SSRF surface** when endpoints are tenant- or operator-configurable: enforce approved schemes/ports; resolve the hostname once, validate the resolved IP against private/link-local/loopback/cloud-metadata ranges, and **connect to that same validated IP** (connect-by-IP with Host/SNI set from the hostname, or a resolver-pinning client hook) — validate-then-let-the-client-re-resolve is bypassed by DNS rebinding returning a public IP to the validator and a private one to the connection; re-run the resolve-validate-pin cycle on every redirect hop, or disable redirects; prefer routing deliveries through a constrained egress proxy.

## Message Shape

- Include notification type, recipient or endpoint reference, template id/version, actor or service identity, trace/log id, safe summary, and dedupe key.
- Render templates through typed variables, not string concatenation of raw objects.
- Redact secrets, credentials, tokens, signatures, and large payloads.

## Async Delivery

- Critical delivery uses an outbox table or durable queue with retry count, next retry time, terminal status, and last error.
- Best-effort alerts may run asynchronously but must recover exceptions and emit logs/metrics on failure (detached-spawn firewall per `async-and-worker-patterns.md`).
- Use bounded concurrency and backoff; group or throttle repeated alerts by stable fingerprint.
- Flush or drain delivery workers during graceful shutdown when messages are critical.

## Realtime Client Channels

- For WebSocket/SSE realtime channels, authenticate and resolve app, tenant, and user context before accepting the connection.
- Keep connection identity in a concurrency-safe registry keyed by the smallest delivery scope, and remove the client on disconnect via `finally`/context-manager cleanup.
- Rebuild initial client state from the durable store on first connect or cache miss; send a snapshot after connect, then typed/versioned deltas.
- Maintain cached unread/count state with explicit TTL refresh and atomic increments; a missing realtime cache must not create a durable-count side effect.
- Queue consumers treat disconnected clients as a no-op delivery outcome after durable storage succeeds.

## Tests

- Test empty batch, timeout, non-2xx response, malformed response, retryable vs permanent classification, redaction, template rendering, dedupe key, throttling, and shutdown drain.
- Test the SSRF boundary: loopback/private/link-local/metadata-range targets rejected, disallowed scheme/port rejected, redirect to a blocked range rejected, and the pin exercised — assert the connection is made to the validated IP (fake resolver returning different answers on first and second resolution must not reach the second answer).
- Test realtime connect, duplicate connection, disconnect cleanup, cache-miss bootstrap, disconnected-delivery no-op, and write failure on a closed socket.
