# Operations Checklist

## Startup

- Config files have environment-specific defaults.
- Required config is validated before serving traffic.
- Dynamic config access has timeouts and fallback behavior.
- Secret resolution is explicit and never logs secret values.
- Service discovery failure mode is understood.
- Health checks distinguish process liveness from dependency readiness when needed.

## Runtime Context

- Every request has trace/log id.
- Subject/resource-scope/lane/environment context is propagated consistently.
- Outbound RPC, DB, Redis, MQ, and HTTP calls use context deadlines.
- Panic recovery exists at transport and worker boundaries.
- Authentication, authorization, resource-scope resolution, and request context are distinct steps.
- Internal service callers have an explicit service identity and trust model, not only network reachability.
- Public response errors use canonical codes; logs keep the detailed internal cause.
- Public API auth records define app id, secret/key reference, source restrictions, allowed resource scope, and enabled status.
- Third-party callbacks validate signature/token, timestamp, event type, and idempotency key before side effects.

## Reliability

- Writes that cross systems have idempotency keys or compensation.
- MQ consumers are safe under duplicate delivery.
- Redis locks use compare-and-delete unlock semantics.
- Rate limits are scoped by subject/resource/workflow identity.
- Retry policies distinguish transient infrastructure errors from permanent validation errors.
- Scheduled jobs have distributed lock scope, lease, max execution time, retry count, and panic recovery.
- External service clients validate both transport success and domain status code.
- Fallback behavior is documented: when to degrade, when to fail fast, and what metric/log proves it happened.
- Inbound rate limits, concurrency limits, load shedding, and circuit breakers have stable error behavior and metrics.

## Observability

- Logs include service, method/job, safe domain/resource identifiers, trace/log id, and error cause.
- Metrics cover QPS, latency, error rate, dependency latency, queue lag, retry count, and domain counters.
- Traces cover inbound requests, outbound RPC/HTTP, DB, Redis, and MQ handling.
- Debug endpoints such as pprof are gated by environment or internal-only exposure.
- Error metrics include canonical error code and avoid high-cardinality raw messages.
- Long-running handlers and jobs expose heartbeat/progress metrics when operationally useful.

## Release

- IDL/codegen changes are committed with generated output.
- Codegen commands are portable and free of developer-local absolute paths.
- DB migrations are backward compatible with the currently deployed code.
- Feature gates exist for risky behavior changes.
- Deployment metadata, resource profile, replica count, image, protocol, and lane/environment are validated before apply.
- Gateway/mesh route updates are atomic and have a rollback path.
- Canary has an evaluation window, baseline comparison, pass/fail report, and owner for manual confirmation.
- Production-impacting changes have an approval record with reviewers, expiry, status, and decision audit.
- Rollback plan includes schema, config, and message compatibility.
- Integration tests that need real infrastructure are separated from the default fast test target.
- Secret/key rotation and callback verification changes have a rollout and rollback plan.
