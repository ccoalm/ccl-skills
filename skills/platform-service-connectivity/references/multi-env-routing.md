# Multi-Environment Routing (Lane / Canary / Shadow)

How a request labelled "I belong to env X" reliably reaches X-labelled instances, across every hop including queues.

## Lane is the single primitive

One concept, many uses:

| Use | Lane value example |
|---|---|
| Long-lived environment | `prod`, `staging`, `pre`, `test` |
| Per-developer iteration | `dev-alice`, `dev-bob` |
| Per-integration-test run | `it-<yyyymmdd>-<n>` |
| Canary slice | `prod-canary-1pct` |
| Shadow traffic | `prod-shadow` |
| Stress/load test traffic | `stress` (often via separate `stress_tag` flag, not lane) |

Treat them all as lanes for routing purposes. The mesh and SDK do not need to distinguish "dev" from "canary"; they only match labels.

## End-to-end lane chain

```
Client (browser/app/external caller)
   │ sets <lane-header> in request (or default lane assumed)
   ▼
Ingress gateway
   │ reads <lane-header>; if missing, sets default ("prod")
   │ forwards
   ▼
Service A's mesh sidecar
   │ VirtualService: match <lane-header> → route to subset where instance tag lane=<value>
   ▼
Service A app code
   │ framework server middleware extracts lane → ctx
   │ business logic runs in lane-aware mode if needed (rare; usually transparent)
   ▼
Service A outbound RPC
   │ framework client middleware reads lane from ctx → sets RPC base.Tags.lane
   │ framework client middleware sets <lane-header> on outbound HTTP if used
   ▼
Service B's mesh sidecar
   │ VirtualService routes lane to lane=B-subset
   ▼
... and so on
```

Lose lane anywhere → request leaks to wrong env. The most common leak points:

- **Queue boundary**: producer writes a message without lane attribute; consumer doesn't know which lane to use → defaults to prod and processes test traffic.
- **Async task**: a goroutine / asyncio task spawned without copying lane from parent ctx.
- **Caching layer**: cache keyed without lane → test reads prod cache or vice versa.
- **Cron job**: no inbound request, no lane → defaults to prod (often the right default; document it).

## VirtualService pattern

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: <callee>
spec:
  hosts: ["<callee-service>"]
  http:
    - match:
        - headers:
            <lane-header>:
              exact: test
      route:
        - destination:
            host: <callee-service>
            subset: lane-test
    - match:
        - headers:
            <lane-header>:
              exact: dev-alice
      route:
        - destination:
            host: <callee-service>
            subset: lane-dev-alice
    - route:                                # default: prod
        - destination:
            host: <callee-service>
            subset: lane-prod
```

Pair with `DestinationRule` declaring subsets by tag:

```yaml
kind: DestinationRule
spec:
  host: <callee-service>
  subsets:
    - name: lane-prod
      labels: { lane: prod }
    - name: lane-test
      labels: { lane: test }
    - name: lane-dev-alice
      labels: { lane: dev-alice }
```

Generate VirtualService + DestinationRule programmatically per lane; manual YAML for dozens of lanes is unmaintainable.

## Queue propagation

Producer:
```
msg.headers["<lane-header>"] = appctx.GetLane(ctx)
msg.headers["<log-id-header>"] = appctx.GetLogId(ctx)
msg.headers["traceparent"]    = otel_inject(ctx)
```

Consumer:
```
ctx = appctx.ContextWithLane(ctx, msg.headers["<lane-header>"])
ctx = appctx.ContextWithLogId(ctx, msg.headers["<log-id-header>"])
ctx = otel_extract(ctx, msg.headers["traceparent"])
```

If the queue technology has no headers (rare), use a JSON envelope:
```
{ "_meta": { "lane": "...", "log_id": "...", "traceparent": "..." },
  "payload": {...} }
```

## Async / goroutine propagation

Whenever you fork work from a request:

```go
// Wrong: lane is lost
go doSideEffect()

// Right
go doSideEffect(appctx.Clone(ctx))   // platform helper that copies lane, log-id, trace
```

Provide a platform helper (`appctx.Clone` or equivalent) that copies platform ctx keys but cancels independently. Forbid raw `context.Background()` in handler-spawned goroutines.

## Fallback rules

What happens when a callee has zero instances in the requested lane?

| Strategy | When to use |
|---|---|
| **Strict** (fail with 503) | Lane is mandatory for the use case (canary safety) |
| **Fall back to prod** | Long-running dev lanes that only customize a few services |
| **Fall back to a named default lane** | Pre-prod hierarchies (e.g. `dev → pre → prod`) |
| **Round-robin across all lanes** | Bad idea; don't do this |

Document the fallback per environment. "Silent fall through" creates the worst class of bug: works in dev, breaks in prod.

## Canary as a lane

Canary deploys are just a small-percentage lane:

```yaml
- match:
    - headers:
        <lane-header>:
          exact: prod
  route:
    - destination: { host: <svc>, subset: lane-prod-canary }
      weight: 1
    - destination: { host: <svc>, subset: lane-prod-stable }
      weight: 99
```

This means the release skill (`platform-release-engineering`) shifts traffic by editing VirtualService weights, not by deploying new pods. The connectivity layer provides the primitive; release owns the policy.

## Shadow traffic

Shadow = send a copy of prod traffic to a non-prod target without affecting the user response. Istio supports `mirror`:

```yaml
- route:
    - destination: { host: <svc>, subset: lane-prod }
  mirror:
    host: <svc>
    subset: lane-shadow
  mirrorPercentage:
    value: 10.0
```

Shadow targets MUST tag responses as discarded; metrics from shadow must not contaminate prod SLIs.

## Verification

1. Start a service with `lane=test`. Register to SD with that tag. Verify with `nacos-cli list <svc>` (or registry equivalent) — instance tag includes `lane=test`.
2. Send a request with `<lane-header>: test` from an external client. Inspect mesh access log `upstream_host` — confirm it resolves to a `lane=test` pod IP.
3. Send a request with no lane header. Inspect — confirm it routes to the default lane.
4. Spawn an async task from a handler. Confirm the spawned task's logs carry the same lane as the originating request.
5. Send a message to a queue. Consumer logs should show the same lane in its handler ctx.
