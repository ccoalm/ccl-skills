# Observability And Ops

Use this for logs, metrics, traces, health checks, readiness, and operational controls.

## Required Surfaces

- Structured logs with request ID, trace ID, user/tenant/resource scope where safe, route/job name, dependency target, and outcome.
- Metrics for request latency, error rate, dependency latency, queue depth, retry/drop counts, cache hit/miss, and job duration.
- Traces for inbound requests, outbound HTTP, DB calls, queue work, and inference calls where feasible.
- Health checks distinguish process liveness from dependency readiness.
- Debug endpoints and profilers must be disabled or protected in production.

## Python Notes

- Use OpenTelemetry or framework-supported instrumentation when available.
- Make logging configuration deterministic at startup; avoid libraries configuring global logging unexpectedly.
- Use JSON logs for service environments where log aggregation expects structured fields.

## Cross-Stack Conventions

When the portfolio contains Go services and Python services that share dashboards and alerts, the architecture layer fixes a common shape:

- Metric naming convention: `{category}_{operation}_{suffix}` snake_case, identical across stacks. Base label set for RPC/HTTP metrics is platform-fixed (`caller`, `caller_cluster`, `caller_env`, `caller_method`, `callee`, `callee_cluster`, `callee_env`, `method`, `err_code`); high-cardinality identifiers are forbidden as labels in either stack.
- Logger trace-linkage contract: every service-internal logger accepts `ctx` (Go) or carries `contextvars` (Python), automatically emits the same four trace-identity fields, and adds `span.AddEvent` / `span.add_event` on warn/error. The wire shape is identical; only the call site differs. A shared foundation framework may propagate this cross-cutting context, but it does not own the application's logger API surface or codegen output meant for wire consumers; keep that ownership boundary explicit.
- OTel resource attributes (`service.name`, `service.namespace`, `service.version`, `lane`, `pod.ip`, `pod.name`) are set once per process at startup in both stacks. Per-call attributes belong on spans, not on the provider.
- Context propagation tiers (global trace/log identity, post-auth API context, inbound header mappings) follow the same three-tier shape as the Go side. Typed accessors hide the bare-string assertion in both stacks.
