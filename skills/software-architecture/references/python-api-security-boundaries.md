# API Security Boundaries

Use this when a Python service exposes public APIs, partner integrations, callbacks, signed requests, app credentials, or externally reachable admin surfaces.

## Public API Boundary

- Treat public APIs as a separate trust boundary from internal framework routes, workers, and RPC clients.
- Authenticate the calling app or user before resolving authorization scope or running domain validation.
- Keep authentication, authorization, scope resolution, schema validation, and domain validation as separate architecture steps.
- Define auth bypass paths explicitly. Keep them small, reviewed, and limited to health/readiness or documented public metadata.
- Public errors should be stable and non-sensitive; logs should keep the detailed auth failure reason with safe identifiers.

## Partner Application Auth

- A partner app model should include app id, secret/public-key reference, allowed source restrictions when applicable, allowed authorization/resource scope, integration/source identity, status, and rotation metadata.
- Store secrets in a secret provider or encrypted config, not in code, config examples, tests, generated docs, or logs.
- Support disabled apps and rotated credentials. Unknown, disabled, expired, or malformed auth config fails closed.
- Signed requests should include timestamp, nonce or request id, app id, and canonical request data.
- Prefer HMAC or asymmetric signatures for new integrations. Enforce timestamp windows and replay protection for state-changing APIs and callbacks; document explicit read-only or already-idempotent exceptions.

## Authorization Scope Isolation

- Treat tenant, account, owner, actor, resource, and permission fields from request body, query, path, headers, or downstream payloads as claims until resolved from authenticated context.
- Resolve allowed resource scope from the authenticated app/user before domain logic.
- Include resolved scope/source in idempotency keys, cache keys, rate limits, audit records, and downstream context.
- Scope-check bypasses require explicit integration config, narrow reason, and audit trail.

## Callback Boundary

- Callback endpoints must validate signature/token, timestamp window, event type, payload shape, and required resource identifiers before side effects.
- Callback processing should assume duplicate, delayed, and out-of-order delivery.
- Deduplicate by provider event id, request id, or a stable resource-event-time key.
- Return provider success only after durable acceptance, or document why the provider should not retry.

## Audit And Operations

- Log app id, resolved scope id, integration source, event id, endpoint, auth result, canonical error code, and trace/request id.
- Do not log secrets, raw signatures, full tokens, or sensitive payloads.
- Metrics should separate auth failure, permission failure, validation failure, duplicate callback, callback processing failure, and dependency failure.
