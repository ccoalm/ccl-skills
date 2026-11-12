# Error Contract Architecture

Use this when designing service error codes, response envelopes, transport mappings, and cross-service error propagation.

## Contract

- Define one canonical error shape with code, safe message, optional details, retryability, and trace id.
- Keep success separate from failure; success should not be represented by an absent or default error.
- Success and failure envelopes must be explicit and structurally stable; callers should never infer success from a missing error field or missing status field.
- Callers must check the canonical success/failure indicator before reading optional result fields.
- Reserve code ranges for common classes: invalid input, unauthorized, forbidden, not found, conflict, rate limit, timeout, dependency failure, internal error, and panic.
- Response envelopes should be consistent across HTTP, RPC, workers, and callbacks.
- Error messages returned to clients must be safe; logs may contain richer internal context under redaction policy.

## Mapping

- Map transport status to canonical codes at the boundary.
- Preserve error chains internally, but expose only the canonical code and safe message externally. Error mapping is a total function — every error resolves to a canonical code, unknown falls back to the internal-failure class — and before any code is written into a client-facing response body it passes an allow-list separating client-safe codes from internal-only ones: codes that carry no client-actionable contract (raw panic, unclassified internal failure, and any diagnostic-only code) collapse to a generic safe code instead of being emitted, while genuinely client-facing classes (e.g. rate-limited, timeout, dependency-unavailable) stay on the wire only when the public contract declares them, keeping transport status and envelope code distinct.
- Dependency errors should be normalized before leaving the infrastructure adapter.
- Validation errors should identify fields without exposing sensitive values.
- Panics should map to a distinct internal failure class and include trace/log id for support.

## Governance

- Error definitions should live near the owning module while common codes stay shared.
- Codes are API contracts; do not reuse retired codes for different meanings.
- New shared codes need documentation and tests for transport mapping.
- Metrics should group by canonical code and operation, not raw error string.

## Cross-RPC Envelope And Code Range Allocation

- Architecture declares which transport-level slot carries the typed error envelope per protocol: for gRPC, encode structured details via `google.rpc.Status` with `details` (transported via the `grpc-status-details-bin` trailer or the framework's native details mechanism); for header-based RPC protocols, use protocol-native metadata frames; for HTTP, use a response body envelope. Do NOT pack JSON into the gRPC status message field — it is freeform text limited in size, not a structured channel. The serdes contract is symmetric — server writes, client reads — and is part of the platform contract, not per-service.
- Code range allocation is centrally governed. Reserve a numeric range (e.g., `[0, 11999]`) for shared codes and sub-allocate to tiers: platform codes (200/400/401/403/404/500/503/504), gateway/api codes, per-domain biz codes. Architecture owns the allocation table; new code requests route through the table.
- Distinguish system errors from biz errors in the envelope. Middleware decisions — alert vs ignore, retry-safe vs not, fallback path — depend on the class, not the specific code.
- i18n boundary: error message in the envelope is one language (often English). User-facing translations belong to the gateway or front-end, keyed by the code. Do not localize on the producer side.
- HTTP-200-always vs HTTP-status-as-semantic is a portfolio-level decision. The 200-always pattern simplifies SDK error parsing and avoids partial-success ambiguity but loses the ability for intermediate infrastructure (proxies, monitoring) to classify by HTTP status. Architecture documents the choice and applies it consistently.
