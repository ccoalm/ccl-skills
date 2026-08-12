# Release Operations Patterns

Use this when implementing release-facing code: deploy config, health endpoints, traffic config, canary checks, approval workflows, callbacks, or operations notifications.

## Health And Runtime Introspection

- Add a lightweight liveness endpoint that returns success when the process can serve basic traffic.
- Add readiness when correctness depends on DB, Redis, MQ, service discovery, or a critical remote API.
- Keep debug/profiling endpoints internal-only. Register them under a predictable path and guard by environment, network, or auth.
- Add a ping/introspection endpoint for HTTP services when useful. Include service name, environment/lane, instance id, client address, and status; do not include secrets.
- Middleware should normally bypass auth for liveness and readiness, but not for debug or administrative endpoints.

## Runtime Config Access

- Wrap dynamic config in typed accessors: `GetX(ctx)`, `SetX(ctx, value)`, `ListX(ctx, prefix)`, and listener registration when live reload is needed.
- Return typed empty defaults only when empty config is valid. Otherwise fail fast with a clear startup or request error.
- For list-style config, page through keys with a bounded limit. **Fail the whole snapshot** if any entry is invalid for security/routing/credentials lists — silently skipping one malformed routing rule or credential entry can flip traffic to the wrong upstream or disable a protection without alerting anyone. Partial-skip-with-warning is acceptable ONLY for non-critical inventory lists with an explicit degraded-mode contract.
- Never log secret values. For app credentials, expose only key id, version, or masked identifier.
- Cache mostly-static config with a short TTL and a mutex-protected refresh path; return copies so callers cannot mutate shared state.

## Service Discovery Reconciliation

- Load desired instance config through typed dynamic config or IaC output.
- Resolve hostnames explicitly and fail the single instance, not the whole reconciliation batch, when one host is invalid.
- Compare desired and actual instances by endpoint and metadata before writing to the registry.
- Register missing or changed instances and deregister stale instances; make both operations idempotent.
- Use `time.NewTicker` with `Stop` and context cancellation for periodic reconciliation.
- Log and metric changed, unchanged, removed, skipped, and failed instances with service identifier and lane/environment tags.

## Deployment Implementation

- Build deployment manifests from a typed params struct.
- Validate required inputs before rendering:
  - service identifier and app name.
  - environment/lane.
  - image.
  - CPU, memory, replica count.
  - protocol and ports.
  - optional storage or hardware flags.
- If a redeploy allows empty image, resolve it from the current workload first and fail if no current image exists.
- Apply multi-document manifests through a parser that handles each resource independently and reports the failing kind/name.
- Ensure namespace and service-level resources before deploying lane workloads.
- For deletion, make not-found idempotent and log resource kind/name.

## Interactive Deploy Watch

- For user-visible deploy flow, watch the workload after apply and stream normalized events.
- Mark success only when desired replicas, updated replicas, ready replicas, and available replicas all meet target.
- Include condition messages when the workload is not progressing.
- Use a bounded watch timeout and stop the watcher on completion or context cancellation.
- Keep event payloads stable so CLI, web UI, and automation can consume the same stream.

## Traffic Config Updates

- Model traffic config by caller, callee, method/path, lane, weight, timeout, and enable flag.
- Protect updates with a write lock keyed by caller/callee or the smallest safe route scope.
- Read existing config, apply the minimal patch, validate the full result, then write once.
- Make route removal explicit. Do not silently drop unrelated routes while updating one route.
- Emit audit logs for old value, new value summary, actor, reason, and request id.

## Approval Tasks

- Store approval task by service, lane, run id, status, expiry, required approval count, and pipeline metadata.
- Store reviewer decisions separately from the task row.
- Create or reset a task idempotently for the same run id.
- When approving:
  - acquire the task write lock.
  - verify the reviewer is allowed.
  - count current approved/rejected decisions.
  - update reviewer result and task status in one transaction.
  - reject wins immediately; approve finishes when the threshold is reached.
- Expired tasks should fail closed for production-impacting releases.

## Release CLI And Automation

- Release CLIs should validate pipeline/run identifiers before remote calls and should fail closed when service or lane extraction is ambiguous.
- If a CLI streams deploy progress, consume the same normalized event contract used by API/web clients and treat the final result event as authoritative.
- Apply read deadlines or heartbeat expectations while waiting on WebSocket, SSE, or long polling progress streams.
- Waiting for approval or deploy completion needs a bounded timeout, a bounded consecutive-error budget, and a clear nonzero failure when the result is rejected, expired, or never observed.
- Print stable machine-readable identifiers, such as task id or run id, in addition to human progress text so CI can chain commands.

## Canary Checks

- Persist canary check window by service and run id. Repeated checks should use the same start and expiry timestamps.
- Resolve canary instances and baseline instances from the runtime platform.
- Query logs/metrics within the window using service, lane, instance, and severity dimensions.
- Group errors by stable location such as caller, stack frame, error code, or normalized message.
- Flag:
  - errors present only in canary.
  - canary error count materially higher than baseline.
  - restart/readiness changes.
  - latency or domain metric regression when available.
- Return a structured report with `is_success`, reason, canary count, baseline count, and representative samples.

## Notifications And Callbacks

- Treat CI/CD and alert callbacks as external inputs: validate signature/token, timestamp, event type, and idempotency key before side effects.
- Parse service and lane from explicit fields whenever possible; regex extraction from names is a fallback and must fail closed.
- Send notifications asynchronously only when waiting for upstream state would block a callback. Use bounded retries or timeout.
- Rate-limit notification fanout to avoid alert floods.
- Route messages by environment/lane and severity.
- Include owners/reviewers when available, but do not block the core workflow if owner lookup fails.
- Keep provider-specific SDK and notification rendering behind an interface so release workflow logic is testable.

## Tests

- Unit-test manifest rendering with golden outputs or structured object assertions.
- Test config parsing for missing, empty, malformed, and multi-page list cases.
- Test traffic patch behavior preserves unrelated routes.
- Test approval concurrency with duplicate approve/reject attempts.
- Test canary report classification with baseline-only, canary-only, and count-growth cases.
- Test callback validation and idempotency before any side effect is executed.
