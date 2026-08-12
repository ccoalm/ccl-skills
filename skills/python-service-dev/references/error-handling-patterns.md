# Error Handling Patterns

Use this for exceptions, HTTP errors, validation errors, and response envelopes.

> Sibling sync: the Go counterpart `go-microservice-dev/references/error-contract-patterns.md` holds the **canonical** shared error-model invariant list (canonical typed error model; convert only at the transport boundary; no internal/secret leak; structured-details envelope, not a freeform status-message string; closed classification enums with fail-closed defaults, classification correct before retry/fallback policy). This file must stay consistent with that list rather than restating it. Advisory — there is no automated parity gate; keep in sync by hand.

## Rules

- Keep one canonical error mapping per service.
- Convert internal exceptions at transport boundaries.
- Preserve original exceptions in logs where safe, but do not expose stack traces or secrets in API responses.
- Use typed domain exceptions for expected business failures.
- Do not simulate errors at the API/transport boundary with return-value shapes — `(data, err)` tuples, `None` plus a message, or `{"success": false}` / ad-hoc `{code, message}` dicts smuggled into the data payload. Expected failures raise typed exceptions (EAFP). A pure/domain layer MAY use an explicit `Result`/`Either` value internally — but **"boundary" is defined by behavior, not file/module name**: any code whose return value is serialized to an HTTP/RPC/WebSocket/job-terminal response is boundary code and must raise a typed exception or emit the canonical envelope, never return a `Result`/dict as the wire payload. Relabeling a handler as "domain" does not exempt it.
- Treat validation errors as client errors; treat dependency failures according to retry/fallback policy.
- For shipped response envelopes and error payloads, keep client-readable fields, status/code meanings, and business-data locations stable by default. Removing legacy fields or changing where clients read success/error information is a breaking contract change and requires explicit human approval plus a compatibility, rollout, and rollback plan.
- Test edge cases for error envelopes, status codes, and partial failures.

## Cross-RPC Typed Error Envelope (Cross-Stack)

When Python services participate in a portfolio that propagates typed errors across gRPC / Kitex / HTTP boundaries with a shared envelope:

- Server side: convert internal exceptions — validation failures, RPC timeouts, dependency errors, panics — to the canonical typed error class and serialize it into the transport-level error slot per protocol. For gRPC, encode structured details via `google.rpc.Status` with `details` (carried in the `grpc-status-details-bin` trailer or via the framework's documented details mechanism); do NOT pack JSON into the freeform `status.message` string — that loses typed retry/security semantics and risks leaking server-rendered text. For HTTP, use the response body envelope `{code, message, data}`. Never let bare Python exceptions leak across the boundary.
- Client side: extract the canonical structured shape from the protocol-specific channel (gRPC `details` / HTTP body envelope) and reconstruct the typed error so callers can branch on `code` and use `isinstance` / pattern matching on the recovered error class. Parsing the freeform gRPC status text as JSON is fallback-only; wrap unknown wire shapes as a transport/unknown error without dropping the original cause.
- Numeric Code range allocation is portfolio-wide; Python services raising biz codes must use the same allocation table as Go services. Codes outside the allocated range fail at registration, not at runtime.
- i18n boundary: error messages in the envelope are one language (typically English). User-facing translations live in the gateway or front-end keyed by the code; do not localize on the Python producer side.
- Standard library wrap compatibility: prefer raising chained exceptions with `raise NewError(...) from cause` inside one process; when crossing a transport boundary forces JSON serdes, keep a reverse-path that reconstructs the chain on the client side rather than silently dropping it.
