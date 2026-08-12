# Log / Trace / Metrics Correlation Recipe

Goal: a human (or agent) given one user complaint can find every log line, every trace span, every metric data point produced while that request was in flight — across every service hop.

## The three IDs

| ID | Purpose | Lifetime |
|---|---|---|
| `log-id` | Human-friendly correlation handle; the only id a user reports in a ticket. Generated at the edge if absent. | Per-request, immutable through all hops |
| `trace-id` | OTel-standard 128-bit; joins spans into one trace | Per-request, OTel-managed |
| `span-id` | Identifies one segment of work inside one service | Per-span |

The platform MUST propagate all three through every transport.

## Propagation transports

### HTTP

Inbound (server side):
- Read `<log-id-header>` from request headers; if empty, generate (e.g. `time_ns + random + pod_suffix`).
- Read OTel headers (`traceparent`, `tracestate`) via OTel HTTP instrumentation.
- Inject all three into `context.Context` using platform-defined ctx keys.
- Write `<log-id-header>` back into the response so the client can echo it in error reports.

Outbound (client side):
- Read the three IDs from `context.Context`.
- Set `<log-id-header>` on the outgoing request.
- Let OTel instrumentation set `traceparent`/`tracestate`.

### RPC (Kitex/gRPC/Thrift)

Inbound:
- Same as HTTP, but read from RPC metadata instead of HTTP headers.
- For Kitex specifically: the kitex-contrib OTel package handles trace headers; the platform adds log-id handling in a custom middleware.

Outbound:
- Pull the three IDs from ctx → write into RPC metadata.

### Message Queue (Kafka, RocketMQ, etc.)

Producer:
- Inject the three IDs as message headers/attributes (e.g. Kafka headers, RocketMQ user properties).
- Trace context per OTel messaging spec.

Consumer:
- Extract the three IDs from message attributes → put back into `context.Context` of the consume handler.
- New span: kind=consumer, parent = extracted trace context.

If the queue has no header support, encode as JSON envelope keys: `{ "_log_id": "...", "_traceparent": "...", "payload": {...} }`. Refuse to ship a service that swallows correlation ids at the queue boundary.

### Composite propagator, format interop, and cross-stack key normalization

Define the propagator **once** and install the **same** composite propagator across every stack, adapter, and transport (HTTP / RPC / MQ) — not per-adapter. A real fleet is heterogeneously instrumented, so per-adapter divergence in format support, key spelling, or propagator order silently breaks trace-join at the boundary between two services (a Go caller and a Python callee drop each other's context). Footguns, each a repeated fix:

- **CompositePropagator `extract` is LAST-WINS.** When both W3C `traceparent` and `b3` arrive, the propagator listed **last** wins the conflict. The intuitive order `[TraceContext, b3, Baggage]` makes **b3** win — the opposite of "W3C wins". To make W3C win, put TraceContext **last**: `[b3, Baggage, TraceContext]`. Pin it with an explicit W3C-vs-b3 conflict test; never assume the list reads highest-priority-first.
- **Accept every format on extract; inject W3C only — but preserve sampling and sequence the rollout.** *Extract* reads W3C `traceparent`/`tracestate` AND `b3` (single + multi header) for b3-speaking meshes / older services. *Inject* must emit **W3C only** — do NOT leave the `b3` propagator in the inject path, or a single bidirectional composite re-emits both `traceparent` and `b3`. Use an extract-only b3 wrapper (or a composite whose injector is W3C-only); on a b3-only inbound, downstream then carries exactly one canonical `traceparent`, no `b3`. When canonicalizing b3→W3C, **map the sampling/debug bit** (`X-B3-Sampled` / b3 debug flag → W3C `trace-flags` sampled bit) or downstream makes wrong sampling decisions — and handle b3's third state, **absent sampling header = *defer***: do NOT flatten defer to `trace-flags=00` (a `ParentBased` sampler would then drop every span as "remote-not-sampled"); on defer, make a fresh local sampling decision. Also **carry `tracestate`** through every hop — including the headerless-MQ JSON envelope (`_tracestate` alongside `_traceparent`), or vendor sampling/routing state is lost at the queue boundary. Rollout is ordered: deploy W3C+b3 **extraction** (or boundary bridges) everywhere **first**, then flip egress to W3C-only — a service that goes W3C-only before its b3-only consumers upgrade drops the trace for them.
- **Normalize metadata/header keys per transport — don't blindly lowercase, and reject collisions.** Keys must canonicalize the same way across every stack/adapter, or a key set by one is missed by the other — but canonicalize by the **transport's own rule**: HTTP headers / CGI / gRPC metadata are case-insensitive (canonicalize, or a differently-cased key is silently dropped — this bit a gRPC-metainfo bridge and an MQ header dedup path), while some MQ properties are case-**sensitive** (blind lowercasing corrupts them). After normalization, **reject duplicate / colliding propagation keys** rather than last-wins them — a collision otherwise lets a bridge or attacker choose which `traceparent`/`b3` wins. Preserve carrier order where a transport allows multiple carriers.
- **This is non-authoritative correlation, not identity — and untrusted at the external edge.** Accepting inbound trace context does not relax the edge trust boundary: never derive `lane` / routing / authz from inbound propagation, and validate/regenerate `log-id` at the external edge (SKILL trust-boundary rule). At an **untrusted external ingress do not blindly adopt inbound `traceparent`/`b3` as the parent** — an attacker can graft unrelated requests into one trace-id (trace poisoning / mis-join); start a new root span and *link* to the remote context (or gate parenting behind a trusted-peer check), and strip/validate external `tracestate`. b3/W3C trace context is correlation evidence, not a trust carrier.

Verification: (a) send both `traceparent` and a conflicting `b3` → the trace uses the **W3C** id (pinned conflict test); (b) send `b3` only → downstream carries a canonical `traceparent`, no `b3` re-emitted, and `X-B3-Sampled=0/1/debug` maps to the right `trace-flags`; (c) cross-stack — a Go service injects, a Python service extracts, assert the same trace id **and** `tracestate` join (and the reverse), including over an MQ envelope; (d) send a key in non-canonical case → still extracted; send duplicate/colliding keys → rejected, not last-wins; (e) at an untrusted edge, a forged inbound `traceparent` starts a new root (linked), not a child of the attacker's trace.

## Logger field contract

Every log line, regardless of language, MUST include these fields in the structured JSON:

```
_ts          ISO8601 timestamp with timezone
_level       OTel severity text (TRACE/DEBUG/INFO/WARN/ERROR/FATAL)
_msg         Message body
_logid       Log id (above)
_trace_id    OTel trace id (hex)
_span_id     OTel span id (hex)
_trace_flags OTel trace flags
_service     Service identity (PSM-style or service.name)
_lane / _env Environment label
_idc         Region / data center
_cluster     Kubernetes cluster
_pod         Pod name
_stack       Stack trace (ERROR and above only)
```

Domain fields use `app_*` or `biz_*` prefix to avoid collisions.

## Logger extraction recipe

The logger MUST automatically pull `_logid`, `_trace_id`, `_span_id`, `_trace_flags` from `context.Context`. The developer interface looks like:

```go
logs.CtxInfo(ctx, "ordered %d items", n)
```

Internally:
1. Pull `log-id` from ctx via platform ctx-key.
2. Pull current OTel span from ctx; pull trace-id, span-id, trace-flags from span context.
3. Attach all four as structured fields on the log record.
4. Emit JSON.

If a developer can write `logs.Info("ordered %d", n)` (without `ctx`) and the line still ships to prod without trace fields, the framework is broken. Make ctx mandatory or make the no-ctx form a lint failure.

Inject correlation fields at the record factory or on the emitting handler — never via a filter attached to an ancestor/root *logger*: under stdlib logging semantics a record that propagates up from a child logger does NOT run an ancestor logger's own filters, so an ancestor-logger filter silently drops the fields on every propagating child (the common path). A filter on a *handler* is different — propagated records DO reach ancestor/root handlers and run their filters, so a handler-attached filter is a valid seam. Placement trade-off per key: a record-factory injection covers every path but a caller-supplied `extra` of the same key collides (use for ids that must always win); a handler filter/processor runs late, after record creation, so it survives propagation and yields to a caller override (use for overridable defaults) but must be attached to every handler path. Verify with a child logger that propagates to root.

## Trace ↔ Log join

In kibana / OpenSearch / equivalent:
- Saved search: `_trace_id:"<id>"` → all log lines from one trace.
- Saved search: `_logid:"<id>"` → human-friendly alternative.
- Dashboard panel: log volume by service, drill-down to a specific trace.

In Jaeger / Tempo / equivalent:
- Span attribute `log_id` mirrored from the request → click span → see linked log lines in the log tool.

The two tools MUST be cross-linked in the dashboard so on-call can pivot in one click.

## Verification

End-to-end smoke test (run after every major framework change):

1. Inject a synthetic request with no log-id header.
2. Confirm response carries a generated log-id.
3. Search log index by that log-id → expect ≥ 1 hop. For a known multi-hop path, expect all hops.
4. Pick any line's `_trace_id` → search trace tool → expect a trace with > 1 span.
5. Each span's `service.name` should match a `_service` value in the log search.

If any step fails, the correlation chain is broken; do not ship.
