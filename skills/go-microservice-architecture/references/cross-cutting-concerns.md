# Cross-Cutting Concerns

## Error Model

- Define a small canonical error taxonomy: success, invalid input, unauthorized, forbidden, not found, conflict, dependency failure, timeout, panic/internal.
- Keep internal error causes in logs and traces; expose stable code/message pairs to clients.
- Map transport-native failures into the canonical model:
  - HTTP status and response body should agree.
  - RPC domain errors should preserve code/message across client and server middleware.
  - Worker failures should explicitly decide retry, dead-letter, or skip.
- Do not let raw dependency errors become public API contracts.

## Context Propagation

- Every inbound request creates or accepts a trace/log id, then returns it in the response metadata where possible.
- Carry lane/environment, authorization/resource scope, auth subject, and request deadline through HTTP, RPC, DB, Redis, MQ, and external HTTP calls.
- Async producers should put trace/log metadata into the message when the queue supports it; consumers should create a new log id only when none exists.
- Avoid storing context values that are domain inputs better represented as typed request fields.

## Auth And Permission Boundary

- Split authentication from authorization.
- Authentication resolves the subject, token/session state, resource scope, and client application.
- Authorization checks whether that subject can perform the operation on the target resource.
- Public bypass paths such as health/debug/login must be explicit and prefix-safe.
- Permission checks should be injectable so product-specific policy can evolve without rewriting transport middleware.

## Internal Service Trust

- Treat internal RPC and internal HTTP as separate trust boundaries from public API, not as automatically trusted traffic.
- Prefer workload identity, mTLS, signed service tokens, or an equivalent service identity mechanism for service-to-service calls.
- Authorize service callers by operation and resource scope when a service boundary protects sensitive data or side effects.
- Propagate caller service identity separately from end-user subject so audit logs can distinguish user action from service delegation.
- Bypass rules for internal health, readiness, or discovery endpoints must be explicit and narrower than ordinary internal APIs.

## Timeout Budgeting

- Set default timeouts for every transport and dependency.
- Allow method-specific overrides for high-latency operations, but keep an upper bound.
- Honor the caller's context deadline when it is shorter than the local default.
- For RPC clients, separate connection timeout from request timeout.
- For background jobs, set both lock lease and max execution time.

## Observability Contract

- Metrics should cover QPS, latency, success, error by canonical error code, panic count, dependency latency, queue lag, retry count, and job duration.
- Attach low-cardinality tags: service, method/API/job, environment/lane, caller/callee, and canonical error code.
- Logs should include trace/log id and safe domain identifiers, but avoid request/response bodies unless gated by environment/config.
- Long-running requests/jobs should have heartbeat or progress visibility when they can exceed normal latency windows.

## Admission Control And Backpressure

- Define inbound request limits by route/method, caller, authorization scope, or operation cost before traffic grows.
- Use concurrency limits for expensive handlers and worker pools; queue only when bounded wait time and cancellation behavior are defined. Do not share one concurrency/resource budget across workloads with different lifetime profiles (short unary request vs long-lived stream); give each a separate, opt-in budget, and validate the interdependent budget fields as a set rather than individually.
- Load shedding should return a stable canonical error and emit metrics that separate overload from dependency failure.
- Circuit breakers protect dependency calls and high-cost workflows; define open, half-open, and recovery behavior explicitly.
- Backpressure must be visible to upstream callers through retry-after hints, queue depth, or rejection metrics where the protocol supports it.

## Streaming And Large Payloads

- Streaming RPC, server-sent events, WebSocket, upload, and download paths need explicit connection lifetime, idle timeout, max message/body size, and cancellation behavior.
- Validate content type, content length, file extension, and object metadata before expensive processing.
- Outbound file or URL fetches need scheme/host allowlists, redirect policy, size limits, content-type checks, and private-network protection.
- Temporary files and generated artifacts need namespace, quota, cleanup owner, and failure cleanup policy.
- Stream progress, partial failure, and client disconnects should map to stable errors and metrics.

## Context Propagation Boundary

- The set of ctx keys a portfolio relies on is platform contract, not per-service convenience. Architecture defines tiers: global keys carried on every request (trace/log id, PSM/service identity, lane, IDC, cluster, stress tag), API-context keys derived after gateway auth (user, tenant, organization, role), and inbound HTTP header mappings (`X-*` → canonical ctx name).
- Every ctx key has a typed accessor; bare-string `ctx.Value(...)` returning `any` is an architecture finding, not an idiom to spread. Type assertion lives behind helpers, not in domain code.
- For frameworks that propagate metadata over the wire, define which keys travel persistently (every downstream hop forwards them) versus transiently (one hop only). Lane, stress tag, and trace identity are typically persistent; one-off control flags should not be promoted to persistent.
- Dual-injection compatibility: when one binary serves multiple transports (TTHeader Thrift + HTTP/2 gRPC), the propagation layer writes to both the framework's persistent value (`metainfo.WithPersistentValue`) and the transport's outgoing metadata so the framework's meta handler picks the right wire format at send time. Application code stays transport-agnostic.
