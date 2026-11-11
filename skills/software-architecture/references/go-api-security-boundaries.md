# API Security Boundaries

## Public API Boundary

- Treat public APIs as a separate trust boundary from internal RPC.
- Authenticate the calling application or user before resolving authorization scope.
- Keep authentication, authorization, scope resolution, and domain validation as separate steps.
- Define which paths bypass auth, and keep bypass lists explicit, reviewed, and minimal.
- Public error responses should be stable; logs should keep the detailed auth failure reason.

## Partner Application Auth

- A partner application model should include:
  - application id.
  - secret or public key reference.
  - allowed source IPs or network policy when applicable.
  - allowed authorization/resource scope.
  - integration/source identity.
  - enable/disable status and rotation metadata.
- Store secrets in a secret provider or encrypted config, not in code.
- Support secret rotation with overlapping validity windows when external partners need rollout time.
- Signatures should include timestamp, nonce or request id, app id, and canonical request data.
- Choose HMAC or asymmetric signatures for new integrations; avoid weak hash-only signing unless compatibility requires it and compensating controls exist.
- Reject expired signatures and replayed nonces/request ids.

## Authorization Scope Isolation

- Scope id from the request is an input, not proof of permission.
- Resolve allowed resource scope from the authenticated app/user.
- Enforce scope permission before domain logic and again at repository boundaries for sensitive writes when feasible.
- Include resolved scope id in idempotency keys, cache keys, rate limits, and audit records.
- Never allow a scope-check bypass flag without a narrow integration reason, explicit config, and audit trail.

## Third-Party Callback Boundary

- Callback endpoints must validate signature/token, timestamp window, event type, payload shape, and required resource identifiers.
- Callback processing should assume duplicate, delayed, and out-of-order delivery.
- Use provider event id or a derived idempotency key to deduplicate.
- Return success only after durable acceptance, or document why the provider should not retry.
- Put provider verification keys in secret/config providers; do not hardcode callback verification keys in source.

## Audit And Operations

- Log app id, resolved scope id, provider, event id, endpoint, auth result, and canonical error code.
- Do not log secrets, raw signatures, full tokens, or sensitive payloads.
- Metrics should separate auth failure, permission failure, validation failure, callback duplicate, callback processing failure, and dependency failure.
- Admin changes to integration auth data should be auditable and optionally notify an operations sink.
