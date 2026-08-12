# Error Contract Patterns

Use this when implementing canonical errors, response builders, validation errors, dependency error mapping, or transport error conversion.

> Sibling sync (this file holds the canonical list): `python-service-dev/references/error-handling-patterns.md` mirrors these for Python and points back here rather than restating them, so the list lives in one place. Shared error-model invariants both stacks must hold — edit them HERE: canonical typed error model; convert only at the transport boundary; no internal/secret leak in API responses; cross-RPC envelope via structured details, not a freeform status-message string; closed classification enums with fail-closed defaults, and classification correct before retry/fallback policy is built on it. Stack glue (Kitex/gRPC vs FastAPI/gRPC) may differ; the invariants may not. Advisory — there is no automated parity gate; keep the two in sync by hand.

## Error Type

- Implement a typed error with code and safe message, and make it compatible with `errors.As`.
- Keep the internal error chain when adding context; do not replace the cause with a formatted string unless intentionally crossing a trust boundary.
- Do not encode typed errors only as JSON strings; provide methods or fields for code/message access.
- Common constructors should cover known codes and default messages.
- Avoid embedding raw request bodies, secrets, credentials, tokens, or personal data in error messages.

## Definitions

- Group local errors by layer: validation, domain rules, data access, dependency, and system failures.
- Use common codes for common classes and local definitions for local meanings.
- Validation errors should use stable field names and client-safe messages.
- Dependency adapters should translate upstream status/code/message into canonical local errors.
- Timeout, cancellation, and rate-limit errors should remain distinguishable.
- When policy code (retry, fallback, cooldown, alerting) branches on error class, define the classification as a closed enum and make every `switch` over it fail closed in `default` — where "safe direction" is decided per policy domain, not one global answer: for side-effect-bearing actions (retry that can double-execute, billing, writes) unclassified means do-not-act; for availability paths, an unclassified dependency-origin error may still enter bounded, semantics-preserving degradation (count toward circuit-open, take an already-safe fallback) — a provider changing its error wire shape must not turn every response into a hard refusal. The invariant is that a missed mapping never *amplifies* (no blind retry storms) and never silently acts on unknown semantics; pick each default deliberately and record it.
- Get the classification layer right before building retry/fallback/cooldown on top of it — the order cannot be reversed; policy stacked on a wrong or leaky classification hard-codes the wrong failure behavior and is expensive to unwind.

## Response Mapping

- Response builders should map typed errors to code/message and unknown errors to internal failure.
- Success responses should set the canonical success code and include data only when available.
- For shipped response envelopes or error payloads, preserve existing accepted fields and client-readable semantics by default while adding the new canonical shape. Removing legacy fields, changing success/error code meaning, or changing where business data lives is a breaking change and requires explicit human approval with a compatibility and rollback plan.
- When a breaking response-contract change is approved, update server tests, generated or typed clients, web/app parsing tests, smoke/E2E checks, documentation, and residual compatibility scans in the same delivery slice.
- HTTP and RPC handlers should convert errors once at the boundary.
- Worker and async job handlers should persist canonical error code/message on terminal failure.
- Logs should include trace/log id and the wrapped internal error where safe.

## Cross-RPC Envelope Serdes

When typed errors must traverse Kitex/gRPC/HTTP boundaries, both sides participate:

- Server-side ErrorHandler converts internal causes — framework biz error, RPC timeout, ACL denial, panic, validation — into the canonical typed error and serializes it into the transport-level error slot per protocol: for gRPC, use `google.rpc.Status` details (carried via `grpc-status-details-bin` trailer or framework-native details mechanism), not the freeform status message string; for header-based RPC protocols, use protocol-native metadata frames; for HTTP, use a response body envelope. Do not let raw internal errors leak across the boundary.
- Client-side ErrorHandler runs the reverse: extract the canonical structured shape from the protocol-specific channel — for gRPC, parse `google.rpc.Status` details from `grpc-status-details-bin` trailer or framework details mechanism, NOT freeform `rpcErr.Error()` text; for header-based RPC, read protocol-native metadata frames; for HTTP, parse the response body envelope. Reconstruct the typed error and surface it to the caller as a real Go error implementing the project's typed-error interface. If the wire payload is not the canonical shape, wrap it as a transport / unknown error and never drop the original cause silently. Parsing `rpcErr.Error()` as a JSON envelope loses typed-retry / security decisions and risks leaking server-rendered messages that were meant for logs.
- Reserve a numeric code range for the shared envelope (e.g., `[0, 11999]`) inside the shared IDL (`base.proto` or equivalent). Within that range, sub-range allocation per tier (platform / api / domain) prevents collisions when services define their own codes.
- Distinguish "system errors with a structured code" from "biz errors with a structured code" in the envelope so middleware decisions (alert vs ignore, retry-safe vs not) are deterministic.
- Document the i18n boundary: error messages in the envelope are typically a single language (often English). User-facing translations belong to the gateway / front-end based on the code, not the message text.

## Standard Library Wrap Compatibility

- Prefer `fmt.Errorf("...: %w", err)` for non-boundary wrapping inside one process. When crossing a transport boundary forces JSON / string serialization of the typed error, keep the `errors.As`-compatible reconstruction on the client side so consumers can still type-assert. Document any place where `%w` chain is intentionally severed (boundary serdes) and provide a reverse path.
- `%w` makes the wrapped error part of the package's public API — callers can `errors.Is`/`As` it. Inside the process keep `%w`. At an exported / public-contract or transport boundary, **return the typed safe error (or canonical envelope) itself** — do not `%v`-wrap the typed error, or the boundary mapper's `errors.As` stops matching and you emit unknown/500. Use `%v` only to embed a raw internal/driver cause as *text* inside a safe message or log line, never to wrap the canonical typed error. And do not blanket-`%v` errors callers legitimately match on: `context.Canceled` / `context.DeadlineExceeded`, not-found, and documented domain sentinels stay `%w` (test-asserted via `errors.Is`/`As`) — switching them to `%v` breaks cancellation/timeout/not-found mapping and loses the observability chain.

## Tests

- Test typed error matching with `errors.As`, wrapping preservation, unknown error fallback, validation field output, dependency mapping, panic mapping, timeout mapping, and response envelope output.
- For cross-RPC envelope serdes, test a roundtrip: server raises typed error → wire format captured → client reconstruction yields a typed error with the same code/message and matches `errors.As` on the original type. Include the unknown-shape path: a wire-format that does not match the canonical envelope returns a transport/unknown error without silent data loss.
- Test code-range allocation: a service trying to register a code outside its allocated range fails at build/test time, not at runtime.
- For closed error-classification enums, add an exhaustive positive-assertion test: every enum member is explicitly asserted to map to its intended policy outcome, plus at least one unknown/unclassified value asserted to take the fail-closed branch.
