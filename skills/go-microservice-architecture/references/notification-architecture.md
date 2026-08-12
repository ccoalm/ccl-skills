# Notification Architecture

Use this when designing service notifications, alerts, webhooks, callback delivery, or operator messages.

## Boundary

- Classify notifications as user-facing, operator-facing, integration callbacks, or internal alerts.
- Define whether each notification is critical, retryable, idempotent, and auditable.
- Keep notification templates and delivery endpoints in config or a template store, not inline code.
- Recipient and endpoint selection must be scoped by resource ownership and environment.
- Notification payloads should use safe summaries, not raw request bodies or secrets.

## Delivery Policy

- Critical notifications need durable outbox, retry, idempotency key, and terminal delivery state.
- Best-effort alerts may use async delivery, but failures must be observable.
- Delivery clients need timeout, status-code validation, response body size limit, and rate limit.
- Retries should use bounded backoff and stop on permanent errors.
- Duplicate delivery must be acceptable to receivers or prevented with stable dedupe keys.

## Observability

- Track sent, failed, retried, dropped, and suppressed counts by notification type.
- Include trace/log id and config/template version in delivery logs.
- Alert storms need grouping, throttling, and suppression policy.
