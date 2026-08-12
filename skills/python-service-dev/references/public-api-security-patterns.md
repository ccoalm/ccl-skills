# Public API Security Patterns

Use this for implementing Python public APIs, partner integrations, signed callbacks, app credentials, authorization scope checks, and API security tests.

## Auth Middleware

- Keep bypass path lists explicit and small.
- Preserve raw body bytes when signature verification requires them; otherwise authenticate before parsing domain payloads.
- Extract only the untrusted selector needed to find verification material, such as app id or key id; load auth config; verify token/signature; then resolve app/user identity and authorization/resource scope.
- Return canonical auth errors; log detailed causes with safe identifiers.
- Do not mutate global auth settings per request.

## App Credential Model

- Store app id, secret/public-key reference, allowed source restrictions, allowed resource scopes, integration/source identity, status, and rotation metadata.
- Generate secrets with cryptographic randomness and keep secret values out of logs, tests, docs, generated files, and fixtures.
- Support disabled apps and rotated credentials.
- If auth config is dynamic, cache briefly and fail closed for unknown app ids, disabled apps, expired credentials, or malformed config.

## Safer Composition (Python 3.14+)

- **Python 3.14 (released 7 October 2025) introduced t-strings via PEP 750** — template literals using `t"..."` syntax that evaluate to `string.templatelib.Template` objects rather than `str`, giving a consuming function access to interpolated values BEFORE they are combined into a string. The standard library exposes `string.templatelib.Template`. **t-strings are inert by themselves — they are NOT automatic injection protection by syntax**. A bare t-string only carries the raw values plus their surrounding template; safety arrives only when a trusted consumer library is t-string-aware and validates/escapes each interpolation according to its target language (SQL, shell, HTML). Writing `t"SELECT * FROM users WHERE id = {user_id}"` and passing it to an ORM/driver that has not added Template support gains nothing over an f-string — and passing it to a function expecting `str` triggers `Template.__str__()` which raises by default, surfacing the misuse rather than silently producing the wrong result. As of 2026-Q1: most popular template engines (Jinja2, Django templates) and most DB drivers do NOT yet consume `Template` directly — verify the specific library's Template support before relying on this rule. **PEP 787 (safer subprocess via t-strings) is currently Deferred to Python 3.15** per peps.python.org — PEP authors are pursuing experimental t-string subprocess work outside the stdlib through 3.14 beta before re-proposing for 3.15. Do NOT assume `subprocess.run(t"...")` works safely in 3.14; for shell/subprocess composition on 3.14, keep using `shlex.quote()` + argument-list form (`subprocess.run(["cmd", arg])`) until PEP 787 or its equivalent lands. For Python ≤3.13 targets, t-strings are unavailable — keep `shlex.quote()` / parameterized DB queries / framework-native HTML escaping; t-strings are a 3.14-and-later opt-in, not a backport.

## Signature And Replay Verification

- Canonicalize signed data before verification.
- Include timestamp and nonce or request id in the signed payload.
- Enforce timestamp windows and replay protection for state-changing APIs and callbacks. Allow an exception only for explicitly read-only or already-idempotent calls with documented rationale.
- Use constant-time comparison for MAC/signature checks where applicable.
- Prefer HMAC or asymmetric signatures for new integrations.

## Authorization Scope

- Treat client-supplied tenant, owner, actor, creator, account, permission, and resource fields as claims until resolved from authenticated context or an authoritative service.
- For write paths, use the resolved authenticated identity as source of truth. Reject mismatches or overwrite client-supplied owner fields before domain logic.
- Put resolved scope/source into typed request context and include it in cache keys, idempotency keys, rate limits, logs, and audit records.
- Scope-check bypass must be explicit config with audit logging, not a hidden branch in handler code.

## Callback Handler

- Validate signature/token, timestamp, event type, resource id, and payload shape before side effects.
- Convert provider event codes into internal enums at the boundary.
- Persist a callback receipt or idempotency marker before expensive work when retries are expected.
- Treat empty payloads, unknown event types, and malformed signatures as permanent failures unless provider contract says otherwise.

## Tests

- Unit-test signature canonicalization, timestamp expiry, replay handling, and authorization-scope checks.
- Add spoofing tests for owner, actor, tenant, creator, account, permission, and resource fields in every accepted input surface.
- Add fail-closed tests for auth, permission, profile-resolution, malformed config, and disabled integration errors before downstream side effects.
- Add duplicate-delivery, malformed-payload, and unknown-event callback tests.
- Use fake secrets in fixtures. Keep provider sandbox or live-callback tests behind explicit integration/live markers.
