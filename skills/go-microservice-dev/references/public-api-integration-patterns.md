# Public API Integration Patterns

## Auth Middleware

- Keep the bypass path list explicit and small.
- Extract application/user identity first, then load auth configuration, then validate signature/token, then resolve authorization/resource scope.
- Do not parse domain request bodies before authentication unless signature verification requires canonical body bytes.
- Return stable canonical auth errors; log detailed causes with safe identifiers.
- Never mutate global auth settings per request.

## App Credential Model

- Store app id, secret/key reference, allowed source restrictions, allowed authorization/resource scopes, integration/source identity, status, and rotation metadata.
- Generate secrets with cryptographic randomness.
- Keep secret values out of logs, code, test fixtures, and generated docs.
- Support disabled apps and rotated credentials.
- If auth config is dynamic, cache briefly and fail closed for unknown app ids or malformed config.

## Signature Verification

- Canonicalize the signed data before verification.
- Include timestamp and nonce/request id.
- Enforce a short timestamp window appropriate to the integration.
- Store nonce/request id for replay protection when the provider can retry.
- Use constant-time comparison for MAC/signature checks where applicable.
- Avoid weak hash-only signing for new integrations; prefer HMAC or asymmetric signatures.

## Authorization And Integration Scope

- Treat request scope id as a claimed scope.
- Confirm the authenticated app/user is allowed to operate on that resource scope.
- Treat identity, ownership, actor, tenant, creator, account, and permission fields in headers, query parameters, request bodies, and downstream RPC requests as claims until resolved from authenticated context or an authoritative service.
- For write paths, use the resolved authenticated identity as the source of truth. Either overwrite client-supplied owner/creator fields or reject mismatches; never use authenticated identity only as a fallback after trusting a client field.
- When fixing an auth or permission bug, search every ingress and propagation point for the same trust class: headers, body fields, query params, path params, generated RPC requests, service defaults, and downstream repository inputs.
- Put resolved authorization scope and integration source into typed request context for downstream logic.
- Include resolved scope/source in cache keys, idempotency keys, rate limits, logs, and audit records.
- Only allow scope-check bypass for specific integrations with explicit config and audit logging.

## Callback Handler

- Validate signature/token, timestamp, event type, resource id, and payload shape before side effects.
- Convert provider event codes into internal event enums at the boundary.
- Deduplicate by provider event id, request id, or stable resource-event-time key.
- Persist a callback receipt before expensive work when retries are expected.
- Treat empty payloads, unknown event types, and malformed signatures as permanent failures.
- Make retry behavior explicit in the response contract expected by the provider.

## Integration Tests

- Unit-test signature canonicalization, timestamp expiry, replay handling, and authorization-scope checks.
- Add spoofing tests for identity/owner/creator fields in every accepted client input surface, and assert the downstream service receives the resolved identity or the request is rejected.
- Add fail-closed tests for auth, permission, capability, and profile-resolution errors before downstream side effects.
- Use fixtures with fake secrets, never production-like secrets.
- Add callback duplicate-delivery tests.
- Add malformed payload and unknown event tests.
- Keep provider sandbox or live-callback tests out of the default fast test target.
