# Observability Implementation Patterns

Use this for logging, tracing, metrics, health checks, and instrumentation.

## Implementation

- Add request IDs and trace IDs to logs.
- Use structured JSON logs when the service runs in aggregated logging environments.
- Instrument FastAPI/Flask/Django, HTTP clients, DB clients, Redis, queues, and inference calls when supported.
- Add runtime base attributes such as service name, environment, region/lane, process or worker group, pod/host identity, and version once at the recorder/provider layer; feature code should add only operation-specific attributes.
- Keep metric labels low-cardinality and bounded. Do not use raw path parameters, user IDs, request IDs, prompt text, provider payload values, or free-form error strings as labels.
- For HTTP/RPC/worker metrics, combine stable runtime attributes with endpoint, operation, status, canonical error code, and duration; use logs or traces for high-cardinality details.
- Add health and readiness endpoints according to deployment needs.
- Do not log secrets, tokens, raw PII, or full provider payloads unless explicitly safe.
- Add tests for logging, tracing, and metric-label helpers when they are shared packages.

## Metric Naming And Standard Label Set (Cross-Stack)

Match the portfolio's cross-stack metric naming so Python services compose with Go services on the same dashboards.

- Metric name shape: `{category}_{operation}_{suffix}` snake_case. Categories name the surface (`http_server`, `grpc_server`, `grpc_client`, `worker`, `db`, `cache`); operation names what happens (`request`, `invoke`, `task`); suffix names what is measured (`qps`, `latency`, `err_qps`, `success_rate`).
- Define metric names in one central module (e.g., `app/observability/metric_names.py`); inline string literals in handlers are a regression.
- Use the portfolio's base label set for RPC/HTTP metrics so cross-service joins work without renaming: `caller`, `caller_cluster`, `caller_env`, `caller_method`, `callee`, `callee_cluster`, `callee_env`, `method`, `err_code`. New labels go through cardinality review.
- Never use high-cardinality identifiers (user id, tenant id, request id, trace id, prompt text) as metric labels. They belong in traces and logs.

## Ctx-Aware Logger Trace Linkage (Cross-Stack)

- Wrap the chosen logger (structlog, stdlib logging with a formatter, or loguru) so it accepts the active context and automatically emits trace identity: `_trace_id`, `_span_id`, `_trace_flags`, and a request/log id field (`_logid`, `request_id`, etc.). Callers do not pass these manually.
- Pair logs with the active OTel span: at warn/error level, add `span.add_event(message, attributes)` so the trace backend correlates logs without manual join. Flip span status to error only at logical error boundaries (handler entry/exit, dependency call failure), not on every warn.
- For async/await, use `contextvars` to carry the logger context across `await` and `asyncio.create_task` boundaries. When spawning a task that should join the parent trace, capture the current OTel context at task-creation time via `opentelemetry.context.get_current()` (or `contextvars.copy_context()` for the broader ctx) and re-attach inside the spawned coroutine via `context.attach(captured) / context.detach(token)` so spans created in the child task become children of the originating span. Without this snapshot, `asyncio.create_task` inherits the contextvar snapshot at task-creation but subsequent OTel SDK calls in the child can still race with the parent's span lifecycle if the parent ends first.
- Configure the OTel resource (`service.name`, `service.namespace`, `service.version`, `lane`, `pod.ip`, `pod.name`) once at startup; per-call attributes belong on individual spans.
