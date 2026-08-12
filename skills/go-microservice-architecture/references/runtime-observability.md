# Runtime Observability

Use this when defining runtime identity, service discovery, logging, metrics, tracing, or debug exposure for a Go microservice product.

## Runtime Identity

- Define one service identity used consistently by logs, metrics, traces, service discovery, deployment metadata, and ownership records.
- Runtime identity should include service name, service type, port, environment, lane, cluster, region or data center, instance id, pod or host id, and node address when available.
- Environment/lane is deployment routing metadata, not authorization or resource identity.
- Service tags should be low-cardinality and safe for metric dimensions.
- Local development defaults are useful, but production startup should validate required runtime identity fields.

## Environment And Lane Model

- Keep these concepts separate:
  - environment: local, test, staging, production.
  - lane: baseline, canary, preview, feature lane, or other traffic slice.
  - authorization/resource scope: data access and permission scope.
- Lane should propagate through inbound HTTP, RPC metadata, async messages, and outbound clients.
- Default lane fallback must be explicit. Avoid silently routing production-impacting calls to an unintended baseline.
- Public APIs should not trust client-provided lane headers unless the caller is authorized to route traffic.

## Service Discovery

- Register service instances with service identity and environment/lane tags.
- Internal clients should resolve through a discovery abstraction rather than hard-coded host lists.
- Resolution policy should define:
  - same-lane preference.
  - baseline fallback behavior.
  - healthy-only instance selection.
  - local development proxy or direct-FQDN behavior.
  - failure behavior when no instance remains.
- Discovery tags must avoid high-cardinality values such as request id or user id.

## Logging Contract

- Every log line from request, RPC, worker, and job code should be able to carry trace/log id.
- Context-aware logging is the default; global logging is only for startup/shutdown and process-level events.
- Request and response body logging must be gated by config/environment and disabled by default for sensitive or high-volume paths.
- Logs should include safe domain identifiers only when useful for operations.
- Error logs should retain internal cause, operation name, dependency identity, and canonical error code where available.
- Do not log credentials, tokens, signatures, raw secrets, or full third-party payloads unless redacted and explicitly enabled.

## Metrics Contract

- Use low-cardinality attributes: service, method/API/job, caller, callee, environment, lane, cluster, canonical error code.
- Avoid raw path parameters, subject ids, resource-scope ids, request ids, free-form error strings, and payload values as metric labels.
- Minimum server metrics:
  - request count.
  - latency histogram.
  - success count.
  - error count by canonical code.
  - panic count.
- Minimum dependency metrics:
  - outbound request count.
  - dependency latency.
  - dependency error count.
  - timeout count.
- Minimum async metrics:
  - queue lag.
  - consume count.
  - retry count.
  - dead-letter or skip count.
  - job duration and skipped-lock count.

## Tracing Contract

- Initialize tracing at the server boundary and attach service name, environment/lane, instance id, and host/pod information as resource attributes.
- Propagate trace context through HTTP, RPC, MQ, and detached jobs where the protocol supports it.
- Add logs as span events only when useful and bounded.
- Mark spans as errors when canonical error severity crosses the service-defined threshold.
- Sampling policy should protect hot paths from excessive cost while preserving errors and slow requests.

## Debug And Profiling

- Liveness, readiness, introspection, profiling, and generated documentation endpoints must have separate exposure rules.
- Liveness can be public to the platform; profiling and debug endpoints should be internal-only or auth-gated.
- Public bypass paths must be prefix-safe and reviewed with auth middleware.
- Debug endpoints should identify the current service and runtime context without exposing secrets.

## Metric Naming Convention

- Architecture standardizes a metric name shape across the portfolio so cross-service dashboards and alerts compose without renaming: `{category}_{operation}_{suffix}` snake_case, where category names the surface (`kitex_server`, `kitex_client`, `hertz_server`, `mq_consumer`, `db_dal`), operation names what is happening, suffix names what is measured (`qps`, `latency`, `err_qps`, `success_rate`).
- Names live in a single per-service or per-platform file (e.g., `metrics_name.go`); architecture review treats inline metric name literals scattered through business code as a finding.
- The base label set for RPC metrics is fixed at the platform layer: `caller`, `caller_cluster`, `caller_env`, `caller_method`, `callee`, `callee_cluster`, `callee_env`, `method`, `err_code`. New labels are added only with cardinality review.
- High-cardinality identifiers (user id, tenant id, request id, trace id) are forbidden as metric labels regardless of the apparent business need; they belong in traces and logs.
- Latency bucket boundaries (or summary quantiles) are picked at the platform layer once and reused across services. Per-service bucket choices defeat cross-service comparison and SLO inheritance.

## Logger Adapter And Trace Linkage

- Pick one structured logger family (zap is the common backend choice) and provide per-framework adapters (Kitex `klog.FullLogger`, Hertz logger, GORM logger, MQ logger). The adapter responsibility is to match the framework's interface while emitting the same JSON shape and field names; do not let each framework pick its own log format.
- Every application-facing logger call takes `ctx` and automatically emits a fixed set of trace-identity fields (`_trace_id`, `_span_id`, `_trace_flags`, `_logid` or the project's chosen four). Callers do not pass these manually.
- The logger pairs with the active OTel span: warn/error logs add a `span.AddEvent(...)` so trace backends correlate without manual join; span status flips to error only at logical error boundaries (handler entry/exit, dependency call failure), not on every warn.
- Resource attributes (`service.name`, `service.namespace`, `service.version`, `lane`, `pod.ip`, `pod.name`) are set once at process start through the OTel provider; per-call attributes belong on individual spans, not on the provider.
