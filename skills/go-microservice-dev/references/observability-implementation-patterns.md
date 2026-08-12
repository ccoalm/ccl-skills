# Observability Implementation Patterns

Use this when implementing middleware, context propagation, service discovery clients, logs, metrics, tracing, or runtime introspection in a Go microservice.

## Context Injection

- At the inbound edge, create or accept a trace/log id and put it into context once.
- Put environment/lane, service name, caller identity, auth subject, and authorization/resource scope into typed context helpers instead of passing ad hoc maps.
- Keep workload/service identity separate from end-user subject and client application identity.
- Return trace/log id in HTTP headers or response metadata when the protocol supports it.
- For RPC clients, write trace/log id and lane into outgoing metadata.
- For RPC servers, read trace/log id and lane from metadata, then normalize into context for application code.
- For async producers, copy trace/log id and lane into message headers or payload metadata.
- For async consumers, restore metadata into context and create a new log id only when none exists.

## Request Logging Middleware

- Log request start and finish in one middleware.
- Include method, route or method name, caller, service, lane, app/client id when safe, trace/log id, status, canonical error code, and latency.
- Request and response bodies must be opt-in by config/environment and size-limited.
- Redact tokens, cookies, signatures, passwords, secrets, and raw authorization headers.
- Do not log request bodies for upload, streaming, large batch, or sensitive callback endpoints by default.
- Recovery middleware should log panic stack with trace/log id and return a canonical internal/panic error.

## Metrics Middleware

- Record request count at entry and latency at exit.
- Record success and error counts after response/error mapping.
- Add canonical error code as a label for failures.
- Use histograms for latency and gauges for current queue lag, active workers, and in-flight requests.
- Heartbeat/progress metrics are useful for long-running requests and jobs, but should have a configurable interval to avoid excessive metric volume.
- Build metrics clients with bounded async buffers. Dropped metrics should not block request handling.

## Tracing Implementation

- Initialize the tracer provider once during server startup and close it during graceful shutdown.
- Add resource attributes for service name, environment/lane, pod/host id, and process metadata.
- Use server-side tracing middleware for inbound HTTP/RPC and client-side tracing middleware for outbound calls.
- Record dependency operation names as spans: DB query, Redis command, RPC method, HTTP endpoint, MQ publish/consume, and scheduled job.
- Add span events for important state transitions, not every log line.
- Set span status and record errors at the boundary where errors are classified.

## Service Discovery Clients

- Construct internal clients with a resolver/discovery abstraction.
- Register server instances with service name, address, weight, and low-cardinality tags.
- Attach workload identity, mTLS config, or signed service-token credentials according to the chosen internal trust model.
- For local development, support an explicit proxy or local resolver path rather than changing production resolution behavior.
- Implement same-lane lookup before baseline fallback when the product uses lane-based routing.
- Fail fast when no healthy instance remains; do not silently call a random host.
- Client timeout, retry, circuit breaker, and error handling should be set alongside the resolver.

## Runtime Endpoints

- Add `/_health` or equivalent for liveness.
- Add readiness if serving correctly depends on external dependencies.
- Add a ping/introspection endpoint only when useful; include service, lane/environment, instance, caller address, and status.
- Register debug/profiling endpoints only on internal listeners or behind environment/auth gates.
- Generated docs endpoints should be disabled or protected in production unless intentionally public.

## Sidecar Health And Registration

- If a sidecar owns service registration, validate service name, port, pod or host IP, and lane/environment before registering; fail fast when identity is missing.
- Register only after the main workload is expected to serve traffic, and deregister during graceful shutdown.
- Bound registration retries and log every failed attempt with service identity, endpoint, and retry count.
- Local health probes should use short timeouts, a failure threshold, and a fixed interval; after threshold failure, emit metrics and capture safe recent logs when available.
- Sidecar stop paths need a bounded timeout, idempotent start/stop state, and tests for duplicate start, stop-before-start, registration failure, health failure, and deregistration failure.

## Shutdown And Closers

- Server constructors should return both the server and a cleanup function or closer list.
- Graceful shutdown should close tracing/metrics providers, log writers, MQ consumers/producers, DB pools, Redis clients, and background workers.
- Cleanup should flush logs and metrics after stopping traffic.
- Use panic-safe cleanup around server exit paths.

## Verification

- Test middleware with fake requests and assert context values, response headers, logging controls, and error mapping.
- Test RPC metadata propagation on client and server sides when the transport supports it.
- Test metrics label sets for cardinality regressions.
- Test discovery fallback behavior: same lane, baseline fallback, no healthy instance, and local development mode.
- Test debug endpoint exposure rules by environment/auth state.

## Metric Naming And Standard Label Set

Metric naming is a service-wide contract — once a name pattern is wrong it is expensive to migrate downstream dashboards and alerts.

- Use snake_case with a `{category}_{operation}_{suffix}` shape: category names the surface (`kitex_server`, `kitex_client`, `hertz_server`, `mq_consumer`, `db_dal`), operation names what is happening (`method`, `invoke`, `request`), suffix names what the metric measures (`qps`, `latency`, `err_qps`, `success_rate`).
- Define metric names in a single central file (e.g., `metrics_name.go`) per service or platform package; do not let metric names appear as inline string literals throughout the code.
- Standardize a base label set for every RPC metric so dashboards can join across services without renaming: `caller`, `caller_cluster`, `caller_env`, `caller_method`, `callee`, `callee_cluster`, `callee_env`, `method`, `err_code`. Add domain-specific labels sparingly — every new label multiplies cardinality.
- Refuse to attach user-id, tenant-id, request-id, or any high-cardinality identifier as a metric label. These belong in traces and logs.
- For latency, decide histogram boundaries (or summary quantiles) at the platform layer and reuse across services; ad-hoc per-service buckets defeat cross-service comparison.

## Logger Adapter Surface And Trace Linkage

- Pick one structured logger and wrap it with per-framework adapters: Kitex `klog.FullLogger`, Hertz logger, GORM logger, MQ/RocketMQ logger. The adapter is responsible for matching the framework's interface while emitting the same JSON shape and the same field names.
- **`log/slog` (Go stdlib, stable since Go 1.21) is the current default-recommendation for a new service's primary structured logger** — same `Logger` / `Handler` shape as zap/zerolog, JSON or text handlers built-in, attribute groups, context-aware logging via `slog.Logger.With(...)`, replaceable via `slog.SetDefault()`. Zap remains a valid choice when (a) the team already has zap-based adapters across Kitex/Hertz/GORM and the migration cost is not justified, (b) zap's lower-allocation hot-path matters on a profiled workload (slog has slightly higher allocation in its general case). Zerolog stays the niche choice for "minimal-allocation at all costs" production logging. For new greenfield services on Go 1.21+, prefer slog and wrap it for the framework adapters; for existing zap-based services, schedule the migration only when adapter rewrites are justified — do not mix slog and zap in the same service (two structured-log JSON shapes will fork log parsers and break correlation). **Framework-adapter migration is the load-bearing risk, not the application call sites**: Kitex `klog.FullLogger`, Hertz logger, GORM logger, MQ adapters historically wrap zap and emit zap's JSON field shape (e.g. zap uses `ts`/`level`/`msg`/`caller`; slog defaults differ). If the application code switches to slog while framework adapters still write zap-shape JSON, the service emits two structured-log schemas and downstream log parsers, alerts, SLO queries, and correlation joins fork silently. **Treat the schema-drift risk as P1 when logs feed alerts or SLOs**; the migration plan must include rewriting each framework adapter to a slog-backed implementation in the same slice as the application switch (or using `slog.NewLogLogger` shim + a custom Handler that normalizes field names), with a post-migration log-parser validation step that confirms every framework's output still matches the platform's expected schema.
- The application-facing logger must accept `ctx` and read trace identity from it. Emit `_trace_id`, `_span_id`, `_trace_flags`, and `_logid` (or the project's equivalent four fields) automatically; do not require callers to pass them as args.
- When the OTel SDK is present, the logger should also call `span.AddEvent(message, attributes)` on the active span so logs and traces correlate in the backend without manual join. Set the span status from the log level only at logical error boundaries — do not let every warn-log flip the span to error.
- Use the framework's built-in OTel instrumentation where available: Kitex server suite, Hertz tracing middleware, GORM tracing plugin. Configure the OTel provider with stable resource attributes (`service.name`, `service.namespace`, `service.version`, `lane`, `pod.ip`, `pod.name`) once at process start.
- For long-running coroutines, SSE/websocket handlers, and consumer loops, end the per-message span instead of letting one giant span span the whole connection.
