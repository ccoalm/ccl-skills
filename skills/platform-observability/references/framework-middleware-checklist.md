# Framework Middleware Checklist

The four mandatory middleware that the platform HTTP/RPC framework MUST attach by default. A service constructed via `NewServer()` / `NewClient()` inherits all four; ad-hoc construction is a bug.

## Middleware (order matters)

### 1. Context Inject (`ctx_inject`)

First in the chain. Establishes correlation before anything else runs.

Responsibilities:
- Read `<log-id-header>` from incoming request; if absent, generate (`time_ns + random + pod_suffix` or UUIDv7).
- Read OTel context (`traceparent`, `tracestate`) — typically already handled by OTel HTTP/RPC instrumentation; this middleware just confirms the span is in ctx.
- Read `<lane/env header>` if the platform propagates env as a header.
- Read service identity (PSM-equivalent) for outbound calls.
- Inject all of the above into `context.Context` via platform-defined ctx keys.
- Write the log-id back into the response header so clients can echo it on errors.

Verification: synthetic request with no log-id header → response includes a generated log-id; downstream RPC call observes the same log-id in its inbound headers.

### 2. Tracing (`tracing`)

Hooks OTel instrumentation. Usually from `hertz-contrib/obs-opentelemetry`, `kitex-contrib/obs-opentelemetry`, or language equivalent.

Responsibilities:
- Start a server span on inbound request, with kind=server.
- Propagate trace context to outbound RPC/HTTP/queue calls.
- Record span attributes: `http.method`, `http.route` (templated), `http.status_code`, `error=true` on 5xx.
- Set span status correctly (UNSET / OK / ERROR per OTel spec).

Span-construction correctness (subtle OTel footguns, each a real fix):
- **In-process spans nest via the active span in the context — and you must thread the *returned* child context down.** Start a new span from the parent already in the context, then pass the child context `StartSpan` returns to the code that starts the next span. Two distinct ways to break the tree: (a) with **no** active parent in context and no seeding from the in-process parent, each `StartSpan` is an **independent root trace**; (b) with an active parent present but each span started from the *original* context instead of the previous child's returned context, the spans come out as **siblings** under that parent, not a nested chain. Either way the real parent/child shape is lost.
- **Queue/async boundary: the consumer span LINKS to each message's creation context (the OTel default); parenting is an optional single-message extra.** Per OTel messaging semconv, **span links are the default** producer↔consumer correlation — the consumer "Process"/"Receive" span SHOULD carry a **link** to each message's creation context, because that is the only structure that holds across **batch and fan-in** (one consumer span accounting for N messages from M producers cannot have N parents). For a **single-message "Process" span** you MAY *additionally* set the message's creation context as its parent to keep one joined trace-id — this optional parent is for **"Process" spans only** (not "Receive" spans) and single-message only, never batch/fan-in. Span kind is `CONSUMER` for a "process" span, `CLIENT` for a "receive" span (per the semconv table); verify the current messaging semconv for your instrumentation version, since it is still marked Development.
- **A link / attribute / event is only captured if the span it's added to is *recording* (`IsRecording()` true).** Adding a link to a no-op / non-recording span silently drops it. Gate on `IsRecording()`, **not** the sampled trace-flag: a `RECORD_ONLY` span is recording (attributes/links captured locally) but *not* sampled for export, and backend export is a separate condition again — so don't drop valid links on record-only spans by checking the sampled flag. Attach links to a real recording span; when you seed the context, carry the actual recording/sampled state rather than assuming.

Verification: trace backend shows one server span per inbound request, child spans for outbound calls, same trace-id; a nested in-process call is a child (not a second root); a batch/fan-in consumer shows a link to each message's creation context (no single parent), and a single-message consumer carries the link too (optionally also parented for a joined trace-id); a forced non-recording span still round-trips context without erroring and its link is simply absent, not corrupting the trace.

### 3. Metrics (`metrics`)

Records request count, latency, panic count.

Responsibilities:
- Increment `<framework>_server_request_total` counter on every request (labels: baseline + route + method).
- Record `<framework>_server_request_duration_seconds` histogram (base-unit seconds, per R3; labels: baseline + route + method).
- On 5xx, increment `<framework>_server_request_error_total` with error-class label.

Verification: dashboard query confirms QPS bump and latency histogram populated.

### 4. Recovery (`recovery`)

Catches panics so a bad request does not kill the pod.

Responsibilities:
- On panic, capture stack trace, log at ERROR level with `_stack` field.
- Increment `service_panic_total` counter with route label.
- Return 500 with a fixed error code (e.g. `code: SERVER_PANIC`, `message: server panic: <type>`).
- Continue serving (do not propagate the panic up).

Verification: deliberately trigger a panic in a test endpoint; service stays up, log includes stack, panic counter increments.

## Cross-domain (`cross_domain` / CORS)

Optional but standard for public-facing APIs. Configure allow-list per environment; default-deny in prod.

## Order

```
incoming request
    │
    ▼
  ctx_inject     ← must be first; everything else relies on ctx fields
    │
    ▼
  tracing        ← starts span; subsequent log/metrics get trace fields
    │
    ▼
  metrics        ← measures full handler duration including child middleware
    │
    ▼
  recovery       ← wraps everything; catches panics from later middleware + handler
    │
    ▼
  cross_domain   ← may short-circuit OPTIONS before handler; place after recovery so its panic is caught
    │
    ▼
  user handler
```

Order rationale: each later middleware relies on earlier ctx state. Recovery is placed late enough to wrap the handler but early enough that its own log/metric writes have valid ctx.

## Verification commands

Run these on a new or audited service:

```bash
# 1. Static — framework default options include all four
grep -E "ctx_inject|tracing|metrics|recovery" <framework-default-options-file>
# expect 4 hits

# 2. Live — synthetic request shows log-id, trace-id propagation
curl -i -X POST <service-health-url>
# expect response header includes log-id; response body within latency SLO

# 3. Static — service code does NOT manually add the same middleware
grep -rE "Use\(.*(CtxInject|Metrics|Recovery|Tracing)" <service-handler-dir>
# expect zero hits (otherwise: duplicated middleware, may double-count metrics)

# 4. Live — kill switch (panic) does not crash pod
# trigger known panic route, then:
kubectl -n <ns> get pod <pod> -o jsonpath='{.status.containerStatuses[0].restartCount}'
# expect: unchanged
```

## When to NOT use the default chain

- Pure ingress proxy that intentionally bypasses business semantics.
- Health-check-only sidecar.
- Specialized streaming endpoint where metrics middleware would inflate.

In all such cases, the deviation is documented in the service README and reviewed by platform. The default chain is the path of least audit friction.

## Instrumentation registration must be atomic and fail-open (install-time hooks)

Adapters that wire telemetry by registering **multiple** hooks into a host — ORM callbacks (before/after query, create, update, delete, raw, row), DB/driver event listeners, or imperatively-installed middleware — do so once at startup, not per request. The per-request chain above has its own Recovery rule; the install step needs the same discipline:

- **All-or-nothing registration, scoped to hooks you own.** If hook *k* of *n* fails to register, roll back the *k−1* already-registered hooks and surface the error; never leave the host half-instrumented (some query paths traced, some not — invisible gaps that read as "that path isn't hot" when it is merely un-instrumented). Ignoring each registration's error (`_ = register(...)`) is the anti-pattern that silently produces the partial state. Roll back **only your own handles** — remove by the owner token / registration handle / generation id you got back, never by list position or by clearing a shared hook chain, or you disable another adapter's or the host's own hooks. If deregistration itself can throw or partially mutate the host, treat a failed rollback as a separate surfaced error and quarantine/recreate that host object rather than reusing a half-mutated one.
- **Un-removable hooks: disable immediately, bind to owner identity — not "clean up later".** When the host API cannot cleanly deregister a hook mid-rollback, make the hook itself idempotent and generation-checked so a stale closure **no-ops immediately** (don't leave it live until the next install), and bind cleanup to the host's lifecycle + your owner id. A reconnect / re-init must not accumulate duplicate live hooks (double-counted metrics, duplicate spans, memory growth) or remove a newer owner's hook. Serialize install under a host/init lock (or do an atomic chain-swap) and publish the new generation only **after** the full set is registered, so a concurrent reconnect never observes a half-installed set.
- **Fail-open is for OPTIONAL telemetry only — never for policy or a source-of-record.** A pure-telemetry registration failure, or a per-hook *observability* callback error at runtime, must never abort the host's query/request: telemetry that cannot attach degrades to no-telemetry, not a broken business path. This does **not** license fail-open for (a) a security / authorization / audit / tenant-policy hook, or (b) a hook that is the **source of record** for metering / billing / audit — both are control/data-plane, not telemetry: they fail **closed** or enter an explicit degraded-deny mode, or synchronously buffer + replay the record before the host op proceeds (never "alert and continue", which ships unmetered / unaudited actions). Classify each hook mandatory-control-vs-optional-telemetry before applying this rule. And "fail-open" is not "fail-silent": even optional telemetry degrades **visibly** (health signal + alert); a signal that gates an SLO / rollback decision must not vanish silently.
- **The adapter must fail-open on its OWN misconfiguration — construct a pass-through noop, never `panic` / fail-fast at wiring.** A nil / unwired / missing runtime (no emitter, no provider, absent config) must yield a pass-through interceptor/middleware, not a `panic` or fail-fast at construction. Scope the noop precisely: fail-open drops only the **optional telemetry emission/export**; any *mandatory* responsibility co-located in the same interceptor — ctx injection, trust-boundary normalization / spoofed-caller-header stripping, panic recovery, redaction — MUST still run, or that adapter fails closed. A blanket noop that also skips those lets forged context survive (security) or a panic crash the pod (availability). "Fail loud on misconfig" is the right instinct for *business* config but **wrong for a cross-cutting observability layer**: a wiring error in telemetry must never crash or block the host service. This is the trap that repeatedly ships wrong — a service that *looks* wired but emits nothing feels worse than a crash, which tempts fail-fast; resist it and surface the misconfig through a loud startup diagnostic / degraded health signal instead (the "fail-open ≠ fail-silent" line above), not by aborting the host. (Exception, per the classification above: an unwired **mandatory control / source-of-record** adapter — audit / policy / metering — must NOT silently noop-passthrough; it fails closed or blocks startup. Self-misconfig fail-open is for the *optional-telemetry* layer.) **Firing gate — every adapter MUST carry a construct-unwired test**: build the adapter/server with a nil/unwired runtime, drive one request, and assert (a) **no panic** at construction or request time, and (b) the classification-appropriate outcome — an *optional-telemetry* adapter passes the request through **and emits a visible degraded diagnostic / health signal** (not a silent green with telemetry dropped, which masks the wiring error and blinds SLO/rollback), while any co-located mandatory responsibility (ctx inject / spoofed-header strip / recovery) still runs; a *mandatory control/source-of-record* adapter fails closed / blocks startup (never a silent pass-through). The absence of this one test is what repeatedly lets a fail-fast-on-nil-runtime bug ship.
- **Per-host runtime state must be thread-safe and stable-identity-keyed.** State kept per host object (per DB engine / connection / channel — counters, active-span maps, generation ids) is touched concurrently by the host's own threads/goroutines: guard it with a lock / atomic / concurrent registry, never a plain shared map read-modify-written without synchronization, and **not** a thread-local (a span opened on one thread/goroutine and finished on another can't find thread-local state → leaked spans, corrupted metrics; thread-local is only for true per-thread scratch that never crosses the host's lifecycle). Key it by the **live host object in a registry that releases the entry on close/GC** — a synchronized `map[*Host]` with explicit delete, or a weak-keyed registry — NOT by a raw numeric `id()` / address you retain *after* the host is closed/collected: the runtime reuses those values, so a retained stale id attributes one engine's telemetry to a different later engine (silent cross-attribution). Either way, **release the state when the host is closed/collected** (the registry's own release, or an explicit close/dispose hook), or it leaks for the process lifetime.

Verification: fault-inject a failure on the *k*-th hook registration and assert (a) zero of **your** hooks remain installed and no other owner's hooks were touched (no partial or foreign-state corruption); (b) split by classification — for an **optional-telemetry** hook the host operation still succeeds **with a visible degraded-telemetry signal**, while for a **mandatory-control / source-of-record** hook (security / auth / audit / metering) the host operation instead **fails closed / degraded-deny, or buffers + replays the record before proceeding** — asserting "host still succeeds" for those would validate an unmetered / unauthorized action; and (c) run install twice against one host and assert no duplicate hooks accumulate.

## Per-request instrumentation lifecycle (request-scoped, not per-request-leaky)

The install-time rules above wire hooks once; these govern what each instrumented request does. Recurring cross-stack bugs — fixed repeatedly in both Go and Python adapters — cluster here:

- **Bind the boundary span + correlation id INTO the context the handler sees.** Starting a server span / generating a `log_id` at the adapter boundary is not enough — write them into the request `context` the handler and its outbound clients actually read (Go `context.Context`, Python contextvars / ASGI scope), or downstream logs and outbound propagation silently lose correlation (orphan logs, broken trace-id chains). `ctx_inject` first (above) is the seat; the boundary span + log_id must land in that same seat, and the binding is strictly request-scoped (never share one request's ctx values into another's).
- **Reset per-request propagation state between requests — an isolation/correctness bug, not hygiene.** Carry propagation state (lane, caller identity, log_id, baggage) in **concurrency-domain-local** storage — Go `context.Context`, Python `contextvars` with token restore (keep the `set()` token, `reset()` it) — **not** a bare thread-local or process-global: in an async/coroutine or goroutine-pooled server the same OS thread interleaves many requests, so a thread-local lets request B overwrite request A mid-flight (cross-tenant), and sequential tests won't catch it; thread-locals are safe only in a true thread-per-request runtime. Clear the state at request end and clear inbound caller metadata *before* you self-stamp, or a reused worker makes request N+1 inherit request N's lane / caller / trace — **cross-request / cross-tenant leakage** (wrong tenant in logs, a `prod` lane bleeding into a test request, a forged caller surviving). But "request end" is the **real** terminal transition, not merely handler return: when the response is streamed / hijacked / handed off to a writer that outlives the handler, a `defer` reset at handler return clears state **mid-inflight** and the handoff then propagates a wrong/default tenant — snapshot an immutable per-request context into the handoff and reset only after the terminalizer (below) fires. Reset must run on **every** terminal path (success, error, panic, early return).
- **Streaming responses need exactly-once terminal-state instrumentation on EVERY exit path.** When the streaming body is produced **after** the handler/middleware returns — an ASGI middleware returning a streaming response, a connection hijack, or a background/handed-off writer — the response outlives the handler, so a unary-style `defer span.End()` fires too early (or never). (When the send loop stays *inside* the handler, `defer` fires at the real terminal path and is fine — the risk is the deferred/handed-off case.) Route every terminal transition through a **single exactly-once terminalizer** (`sync.Once` / CAS / state machine) that finishes the span, emits completion metrics once, **and releases the per-stream request snapshot / buffers / carrier** (the immutable context handed off above — otherwise it retains caller/tenant/baggage and grows memory for the connection's lifetime); overlapping signals (disconnect + write error + cleanup) must not double-end the span or double-count metrics (record extras as secondary attributes). Classify by cancellation **origin**: only a genuine **client** hangup is a benign non-error disconnect — a **server deadline/timeout**, write failure, or panic is a server-side failure and must count as one, or real timeout/backpressure failures hide as benign disconnects. Streams otherwise also leak spans and goroutines/tasks and skew metrics; bound any per-stream buffering.

Verification: (a) fire two requests on one reused worker — **sequentially and interleaved-concurrently** (async) — where the first sets a lane/caller and the second sets none: assert the second never observes request N's lane/caller/log_id and gets a **fresh** request-scoped log_id (generated if none inbound, per `ctx_inject`); (b) instrument a streaming endpoint and (i) force a **client** disconnect mid-stream → span finished exactly once, classified as client-disconnect (not 5xx), no span/goroutine/task **or retained per-request snapshot/carrier** leak; (ii) force a **server deadline/timeout** → classified as a server-side failure (counts as error), span ended exactly once; (c) assert a handler-emitted log carries the boundary log_id and trace-id.
