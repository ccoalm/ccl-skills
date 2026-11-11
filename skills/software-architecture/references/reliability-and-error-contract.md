# Reliability And Error Contract

Use this for timeout, retry, fallback, exception mapping, and canonical errors.

## Error Contract

- Define canonical error shape once.
- Map Pydantic validation, framework HTTP exceptions, ORM errors, Redis errors, queue errors, HTTP client errors, and inference-client errors into that shape. A pluggable or runtime error classifier's output is untrusted input at the boundary: validate/normalize it and fail closed to a safe generic code; never index the code→status mapping with an unvalidated classifier or external value.
- Keep public error details safe: no secrets, stack traces, raw provider payloads, or internal IDs unless explicitly allowed. Gate every code through an allow-list separating client-safe from internal-only codes before writing it to a client-facing response body.

## Reliability

- Every external call needs timeout, retry/fallback policy, and observability.
- Retries require idempotency or a clear reason the operation is safe.
- Circuit breakers, rate limits, and backpressure belong to architecture when a dependency can overload.
- Fail closed for auth, permissions, money, irreversible actions, and data-integrity checks.
- Use graceful degradation only for non-critical cache, analytics, recommendations, or telemetry paths.
