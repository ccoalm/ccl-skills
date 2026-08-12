# Notification Patterns

Use this when implementing notification clients, webhooks, operator alerts, callbacks, or delivery jobs.

For durable delivery state, retries, and terminal-state behavior, also apply `state-machine-task-patterns.md`.

## Client

- Wrap each delivery provider behind an interface with `Send(ctx, message) error`.
- Build requests with context deadlines, content type, status-code validation, and response body size limits.
- Treat empty message batches as no-op.
- Do not use package-level mutable clients unless construction is deterministic and test substitution is available.
- Parse provider responses into canonical success, retryable error, and permanent error.

## Message Shape

- Include notification type, recipient or endpoint reference, template id/version, actor or service identity, trace/log id, safe summary, and dedupe key.
- Render templates through typed variables, not string concatenation of raw objects.
- Redact secrets, credentials, tokens, signatures, and large payloads.
- Add environment and service metadata from a safe allowlist.

## Async Delivery

- Critical delivery should use an outbox table or durable queue with retry count, next retry time, terminal status, and last error.
- Best-effort alerts may run asynchronously, but must recover panic and emit logs or metrics on failure.
- Use bounded concurrency and backoff.
- Group or throttle repeated alerts by stable fingerprint.
- Flush or drain delivery workers during graceful shutdown when messages are critical.

## Realtime Client Channels

- For WebSocket or similar realtime notification channels, authenticate and resolve app, tenant, and user context before upgrading the connection.
- Keep connection identity in a concurrency-safe registry keyed by the smallest delivery scope, and remove the client in `defer` on disconnect.
- Rebuild initial client state from the durable store when a user connects for the first time or when cache state is absent.
- Maintain cached unread/count state with explicit TTL refresh and atomic increment semantics; do not let a missing realtime cache create a durable-count side effect.
- Queue consumers should treat disconnected clients as a no-op delivery outcome after durable storage succeeds.
- Send a snapshot after connect, then send deltas or latest-message payloads; both payload shapes should be versioned or typed enough for clients to distinguish.

## Tests

- Test empty batch, timeout, non-2xx response, malformed response, retryable vs permanent errors, redaction, template rendering, dedupe key, throttling, and shutdown drain.
- Test realtime connect, duplicate connection, disconnect cleanup, cache-miss bootstrap, unread increment, disconnected delivery no-op, malformed payload, and websocket write failure.
