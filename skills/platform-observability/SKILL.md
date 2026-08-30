---
name: platform-observability
description: Use when designing, reviewing, debugging, or shipping observability — service logs, metrics, distributed tracing, log/trace correlation, dashboards, alerts, on-call routing（值班/排班 SOP、P0/P1 打断；发布值班/回滚除外）, SLI/SLO, error budgets — for a backend product. Owns the cross-cutting evidence layer — what signals must exist, what fields must propagate, what middleware must auto-wire, what verification proves a change is observable in production. Hand off mesh/routing/mTLS to `platform-service-connectivity`, release gates and rollback evidence to `platform-release-engineering`, service-internal architecture (HTTP/RPC/DB/queue) to `python-service-architecture` / `go-microservice-architecture`. Product-agnostic; do not depend on specific repository names, service names, hostnames, or business domains.
---

# Platform Observability

This skill owns the **evidence layer**: logs, metrics, traces, log/trace correlation, dashboards, alerts, on-call routing, SLI/SLO/error-budget design, and the framework-level wiring that guarantees a new service is observable on day one.

You do not own:
- Traffic routing, retries, timeouts, mTLS, or service mesh policy — go to `platform-service-connectivity`.
- Deploy pipeline, env matrix, promotion/rollback gates, secret distribution — go to `platform-release-engineering`.
- Service-internal architecture (HTTP handler shape, DB layout, queue topology) — go to language-specific service-architecture skills.
- LLM/RAG/agent inference observability beyond standard trace/metrics — coordinate with `llm-inference-integration`; you still own log_id/trace_id propagation rules.

## Skill Routing

- Use this skill for: instrumenting a new service, reviewing whether a service is observable, designing a dashboard, drafting an alert, sizing an SLO, hunting a missing signal, deciding what log fields propagate, deciding sampling rates, deciding metric label cardinality, judging whether a release has enough observability evidence to be promoted.
- Own on-call SOP design end to end — 值班/排班 SOP、告警统一入口与分级路由、P0/P1 打断策略 MUST be designed here; hand release-period duty and rollback decisions（发布值班/回滚）to `platform-release-engineering`.
- Use `platform-service-connectivity` first when the question is about traffic policy, mesh, routing, retries, or service-to-service identity.
- Use `platform-release-engineering` first when the question is "can this change be promoted?" or "did rollback work?" — those skills consume your SLIs as evidence.
- Use `defect-diagnosis` first when the user reports a specific failure; come back here only to land the missing-signal lesson if observability gaps allowed the bug to escape.
- Use `testing-strategy` when the main question is which test layer should prove the behavior; come back here for the production-evidence layer.

## Core Mental Model

Observability is the chain that turns one user action into searchable, joinable, alert-ready evidence across every service that touched it. The chain has five mandatory links:

1. **Identity** — every request carries a stable `log-id` (correlation id, generated at the edge if absent) and a `trace-id`/`span-id` pair (OTel-spec). These must be in HTTP headers, RPC headers, queue message attributes, and Go/Python `context.Context`. Lose any link and cross-service search dies.
2. **Instrumentation** — every service emits structured logs, metrics, and spans through the **framework default**, not ad-hoc code. A service whose middleware chain does not include `ctx_inject + metrics + recovery + tracing` is unobservable by design.
3. **Transport** — logs go stdout → file collector (DaemonSet) → log pipeline → search index; metrics + traces go SDK → OTLP collector → metric store + trace store. Both transports must survive collector restarts and back-pressure.
4. **Storage + display** — logs in a searchable index keyed by log-id and trace-id; metrics in a long-term store separate from scraper; traces queryable by trace-id; one dashboard tool joins all three.
5. **Evidence consumption** — SLIs are queries against (3) + (4); alerts evaluate SLIs and route to on-call; runbooks live in a wiki that on-call can reach in under one minute.

A new service must satisfy all five before it is allowed in production. A release must produce evidence at all five before it is promoted.

## Non-Negotiable Rules

### R1 — Log/Trace/Metrics correlation is mandatory

- Every service log line MUST carry: `log-id`, `trace-id`, `span-id`, `trace-flags`, `level`, `msg`, `ts`, `service`, `env/lane`, `idc/region`, `pod`.
- `log-id` is generated at the edge (gateway or first service to see the request) and propagated unchanged through every downstream HTTP/RPC/queue hop.
- `trace-id`/`span-id` follow OTel propagation (`traceparent`/`tracestate`).
- **Propagation mechanism**: OTel **Baggage** (W3C `baggage`, composite propagator with `TraceContext`) may carry **non-authoritative correlation/telemetry context** like `log-id` where instrumentation supports it; transport-specific metadata stays allowed where Baggage doesn't reach. Baggage is NOT a trust carrier (it can be tampered/leaked across boundaries) — so `lane`/routing keys are derived by the gateway/mesh from authenticated identity into controlled internal context (allowlisted, boundary-validated), never trusted from inbound Baggage. Keep **one source of truth in context** (not necessarily one wire header); don't maintain redundant parallel carriers of the same value across the same hop.
- **Trust boundary**: the edge does NOT trust externally-supplied routing/correlation headers. A gateway derives `lane`/routing keys from authenticated identity (an external caller could otherwise forge a lane header to route into a canary subset); validate inbound `log-id` shape and regenerate it when absent or malformed. Baggage is an internal-trust carrier — never accept it unvalidated across the external boundary.
- Logger MUST extract trace context from `context.Context` and attach `_trace_id`/`_span_id`/`_trace_flags` to the log record automatically. If a log call requires the developer to manually pass trace fields, the framework is broken.
- Async work that detaches from the request lifecycle (audit, reporting, ledger side-paths) keeps correlation — but only correlation: capture trace/span/log-id fields before the handoff and carry them (plus durable work-item identity) into the detached context; never a bare `context.Background()` that drops linkage, and never a wholesale request-context copy — `context.WithoutCancel` preserves every request value, so a naive derive smuggles request auth/session/secrets/PII into work that outlives the request and can run under stale, revoked authority. Whitelist correlation fields, strip the rest; the worker re-authorizes or runs under service identity (lifecycle/loss-policy detail owned by the stack dev skills' async side-path rules — this bullet owns only the correlation contract).
- Verification: correlation is an acceptance item, not a default — wiring the unified logging component is NOT evidence it works. Assert over the real transport: drive one request through the actual RPC/HTTP server in a test, assert the handler ctx carries a non-empty trace-id/log-id, and that business + access log lines actually contain those fields. Then live: pick any production user action → find one log line → click trace-id → see the full multi-hop trace → all spans share the same log-id.
- Cross-layer evidence boundary: a client-side event does not prove backend success, and a backend metric does not prove the user saw success — any conclusion that crosses the client/backend (or service/service) boundary requires identifiers or time windows aligned across the layers, never a same-shape count on each side.
- Observation code never intrudes on the observed path: instrumentation and evidence collection are best-effort and must not add retries, blocking waits, or business-logic branches to the monitored path — observability that changes the behavior it measures is a defect class of its own.
- Discover before creating: before proposing a new event, metric, label, panel, or query, enumerate what already exists for that surface and extend/reuse it — parallel near-duplicate signals fragment dashboards and split the history.
- Environment-name resolution in queries and dashboards: a user's explicit component/branch/URL/datasource always wins; never silently substitute a different physical environment for a colloquial environment word — when an unqualified name ("测试环境"/"staging") is ambiguous across physical targets, resolve it to the recorded default and say which one was used.

### R2 — Framework default observability, not opt-in

- The platform HTTP/RPC framework MUST attach this middleware chain by default to every service: **(a)** context injection (extract log-id, lane, psm-equivalent service identity from headers; generate log-id if absent; write back to response header), **(b)** metrics (request QPS counter + latency histogram + error counter, labels = baseline + endpoint), **(c)** OTel tracing instrumentation (span per incoming + outgoing request), **(d)** panic recovery (log stack, increment panic counter, return 500 with code).
- A developer adding a new service writes zero observability boilerplate. If they have to, route the gap to the framework, not the service.
- Verification: `grep` the framework default-options source; all four middleware MUST be unconditional. New services start with `NewServer()` (or equivalent) and inherit them.

### R3 — Baseline label set (cardinality-controlled)

Every metric carries a fixed baseline label set, attached automatically by the framework metrics client:

| Label | Source | Cardinality |
|---|---|---|
| `service` (a.k.a. PSM/service.name) | env var injected by orchestrator | hundreds |
| `env`/`lane` | env var (`prod`/`test`/`pre`/named lane) | <20 |
| `idc`/`region` | env var | <10 |
| `cluster` | env var | <20 |
| `pod_name` / `pod_ip` / `node_ip` / `instance` | env var | **HIGH — NOT a default metric label** (see below) |

Per-metric labels are added only for **stable, low-cardinality** dimensions: API path (templated, not raw URL), endpoint name, error code class. Never label by user-id, request-id, log-id, free-text, raw URL, or any field with unbounded value space. A label that grows unbounded is a metric kill switch on the storage tier.

- Encode a status that crosses surfaces — transport status (HTTP/RPC/gRPC) ↔ platform error code ↔ metric `error_code_class` ↔ log field — ONCE as a typed table/enum that every code surface imports and every non-code surface (dashboard, alert config, log pipeline) is generated from or conformance-tested against, never hand-restated `if code == X` per surface. Per-surface literals drift (one surface classes a failure 5xx, another 4xx, a dashboard hard-codes a third), silently mismatching label/alert to reality; the shared table is the single source of the allowed bounded class values, so the cardinality guarantee above holds by construction.

**Instance identity (`pod_name`/`pod_ip`/`node_ip`/`instance`) is NOT a default metric label.** Pods churn under autoscaling and rollouts, so as a metric label they create unbounded series over the retention window (Prometheus: each labelset is a separate time series with RAM/CPU/disk cost — keep cardinality low). Put instance identity in **logs and OTel resource attributes**, and use **exemplars** (or a low-churn `*_info` target-metadata metric joined at query time) for per-instance drill-down. Default metric labels = the baseline set above (`service`/`env`/`lane`/`idc`/`region`/`cluster`) only.

**Instrument discipline**: counters that only accumulate MUST be monotonic Counters (Prometheus: counters only go up / reset) — use UpDownCounter only for genuinely bidirectional values (queue depth, connections, pool size). Histogram bucket boundaries MUST be platform-declared and SLI-threshold-aware (via an OTel View or the SDK's instrument advisory `ExplicitBucketBoundaries`); SDK-default buckets only after review. New instruments SHOULD set a UCUM-compatible unit where meaningful (`1`/dimensionless for counts and ratios); prefer base units (seconds, bytes) for new metrics and preserve legacy units through a migration alias (see R6 retrofit). Counter + Histogram alone are insufficient — the metrics facade must also expose UpDownCounter and (Observable)Gauge so pool stats / saturation can be recorded.

### R4 — Three transports, three guarantees

| Signal | Transport | Failure mode that MUST be tolerated |
|---|---|---|
| Logs | stdout → host file (rotated) → file-collector DaemonSet → log pipeline → search index | collector crash, pipeline back-pressure, ES disk pressure |
| Metrics | one canonical egress per platform (see Decision Points): Prom **scrape** endpoint → scraper → long-term store, OR SDK → **OTLP push** → collector → long-term store; the long-term store stays separate from the collect/scrape layer | collector/scraper restart, network blip |
| Traces | SDK → OTLP gRPC → OTLP collector → trace store | collector restart, sampling-induced gap |

Size SDK queues/timeouts to tolerate a normal ~30s collector outage without expected drops under load test — but the in-memory queue still drops on restart / queue-full / backpressure / export timeout, so expose exporter dropped-count and backpressure metrics, and route audit/security/incident-critical events that cannot tolerate loss through a durable, non-sampled path (not the best-effort SDK queue).

**Head sampling cannot be undone by tail sampling.** Tail sampling runs at the Collector *after* spans arrive (OTel), so a span head-dropped at the SDK never reaches it and cannot be recovered. Head + tail can be combined, but only for a cost model that accepts permanent loss of the head-dropped candidates. If you must retain ALL errors/slow requests, do NOT low-rate head-sample before the tail sampler — export at high/near-full rate to a **tail-sampling collector tier**; if collectors are sharded, route all spans of one trace by trace-id to the same tail-decision point (a node-local collector can only forward or decide single-node traces). A pure head-sampling service (1–10%) accepts permanent loss of unsampled spans.

**In-process log sampling/rate-limit**: the logger MUST support rate-limiting repeated lines (e.g. first N/sec then 1/M) so one hot line cannot flood the pipeline. Bucket by stable low-cardinality keys (`service`, `event/error_class`, `route_template`/dependency, `lane/env`, `severity`) so a localized failure isn't swallowed into one global bucket; expose the dropped count as a counter or structured summary. Never sample away the first occurrence, a state change, or an audit/security event — only repeated bodies. Framework middleware MUST NOT emit per-request lifecycle (start/end) Info logs — that is a built-in log flood.

### R5 — Long-term metrics store is separate from scraper

The scrape layer (e.g. Prometheus) is a relay, not the source of truth. Long-term storage lives in a horizontally scalable store (VictoriaMetrics, Mimir, Cortex, or managed equivalent) reached via `remote_write`. Dashboards and SLI queries hit the long-term store. Never tell on-call "Prom is full, we lost last week's data."

### R6 — Logs schema is contractual

A platform-wide log schema MUST be defined and enforced at the collector parsing layer. Required fields are documented and any service emitting a malformed log line is detected. Reference fields:

```
_ts, _datetime, _level, _msg, _stack,
_logid, _trace_id, _span_id, _trace_flags,
_service (a.k.a. _psm), _idc, _lane, _cluster, _pod
```

Add domain fields with a prefix (e.g. `app_*`, `biz_*`) to avoid colliding with the platform schema. The collector parser maps these to typed fields in the index so kibana/equivalent has them as filters.

**Retrofit / migration contract** (the rules above are otherwise greenfield-framed): when a schema is introduced over EXISTING services, field names, metric label names, and identity env-var names are a **migration contract** — a blind rename breaks every deployed dashboard, alert, and saved query that keys on the old name. Retrofitting MUST alias or dual-write old→new and migrate consumers before retiring the old name; never rename in place. The cheap time to fix a name is before services adopt it.

### R7 — Alerts are SLI-driven and route to a human

- Alerts evaluate against SLIs (query the long-term metric store), not raw metrics.
- Severity levels: P0 (page on-call now), P1 (notify channel, ack within work hours), P2 (digest).
- Every alert MUST link to a runbook entry. If no runbook exists, the alert is not allowed to be P0.
- An alert-backed metric is a coverage contract, and the trigger is mechanical, not prose: any new or changed alert rule, SLO, dashboard alert annotation, or metric referenced by an alert policy fires this check (a written "alert on any increase" note also counts, but its absence is not an exemption). Enumerate every site that should feed the metric and verify each is actually instrumented — derive the site list from a static registry or lint where possible; the easiest site to miss is often the riskiest (e.g. the panic counter in a stream reader parsing untrusted bytes). Ship the site checklist with the alert.
- Alert delivery channels are fixed: P0/P1 → real-time channel that on-call MUST see (chat/IM platform with notification + escalation); P2 → digest. Email-only alerts are forbidden for P0.
- The grafana → webhook → chat-platform pattern is the de-facto standalone case (no Prometheus AlertManager) — see `references/alerting-and-on-call.md` for the trade-offs.

### R8 — SLI/SLO discipline

- Define SLIs from the **user's perspective** (success rate of a request type, latency of a user-visible action), not from internal counters.
- Prefer expressing an SLI as **good events / valid events** (or good windows / valid windows), per Google's Art of SLOs workshop / Google Cloud SLO guidance (the SRE Workbook's own wording is good/total; the valid-events refinement — define valid events/windows first, then the good ratio — comes from the Art of SLOs line). A latency SLI is the **proportion of requests faster than a threshold** (`count(latency ≤ T) / total`, from histogram buckets), NOT a percentile value — P95/P99 are dashboard aids, not the SLI. An error-log counter is a diagnostic signal, not an availability-SLI input (it is skewed by log sampling, dedup, and async/non-request errors).
- Signals you cannot compute are blind spots, not near-coverage: record each one explicitly ("can't measure X because Y" — e.g. a failure counter with no attempt total yields no error *rate*; content not collected means input-semantic drift is unmeasurable) in a blind-spot register instead of pretending coverage, so on-call never leans on a signal that does not exist.
- Each user-visible journey gets at least one availability SLI + one latency SLI.
- Set SLO targets, error budgets, and burn-rate alerts (SRE Workbook multiwindow tiers, derived for a 30d budget window — recompute for other periods: page 14.4× 1h/5m, page 6× 6h/30m, ticket 1× 3d/6h). Each tier MUST evaluate its long AND short window together, firing only when both burn above threshold; the short (~1/12) window makes paging stop soon after the burn stops.
- An SLO without an error-budget-driven release decision is decoration. See `references/sli-slo-design.md`.

### R9 — Local dev parity

- The framework default middleware MUST work locally (logs to stdout, traces optional, metrics optional). A service that only emits signal in prod is a debugging trap.
- Local dev MAY skip the collector and rely on stdout; the rules above apply only to staging/prod transports.

### R10 — Sanitization at log emission

- The logger MUST scrub or hash known secrets (tokens, passwords, full PII like ID numbers, phone numbers) at emit time, not at ingestion. Logs are durable; secrets escape forever once shipped.
- Add a deny-list of header names that must be masked in request logs. Token-style headers default-deny.

### R11 — Client telemetry and remote config respect trust, privacy, and sink boundaries

- For CLIs, agents, desktop clients, SDKs, or other long-lived client runtimes, treat telemetry and remote config as a control plane, not background noise. Before emit or fetch, evaluate privacy mode, workspace/session trust, account/auth freshness, provider path, and user or organization opt-out; nonessential traffic must not run when the local privacy level forbids it.
- Separate general-access telemetry sinks from privileged sinks. PII-tagged fields must be explicitly typed or marked, stripped before fanout to general-access stores, and defensively stripped again before any free-form metadata blob is persisted. A per-sink kill switch must stop new sends and retry/backoff sends, not only future event construction.
- Remote config and experiment caches need staleness semantics by risk class. Startup or hot-path non-critical decisions may read a stale disk cache with safe defaults; security, authorization, entitlement, safety, or policy gates must wait for an in-flight auth refresh or fail closed when no fresh-enough value exists. Never let a stale cached allow override a newer deny, revocation, privacy opt-out, or account switch.
- When auth, account, organization, trust, or privacy state changes, destroy or reinitialize remote-config clients whose headers or targeting attributes are immutable, clear memoized values that were derived under the old principal, and notify long-lived subscribers that baked config values into runtime objects. Persistent telemetry queues and remote-config caches must be scoped by account, organization, workspace, provider path, and privacy state where those facts affect targeting or emission; purge or invalidate them on opt-out, logout, account or organization switch, revocation, or trust downgrade. Ignore late callbacks from replaced clients.
- Remote-config payload processing must validate shape, reject empty or malformed payloads instead of overwriting a known-good cache with a blank answer, replace complete cache snapshots only after a successful full payload, drop removed keys on the next successful refresh, and de-duplicate experiment exposure logging per session.
- Failed telemetry export is best-effort but bounded: queue append-only if needed, chunk sends, short-circuit remaining batches after endpoint failure, back off with a maximum attempt/drop policy, enforce hard max queued events/bytes, TTL, overflow drop policy, and startup compaction/drop behavior, flush on shutdown where possible, and keep failure context sanitized.
- Browser authorization, token refresh, profile fetch, entitlement, and account-cache diagnostics are metadata-only unless an explicit consented support artifact exists. Default logs, metrics, traces, and telemetry may carry categorical state, grant class, storage backend class, retry/lock counters, bounded durations, sanitized error class, and low-cardinality cache outcome. They must not carry authorization codes, PKCE verifiers or challenges, access or refresh tokens, request or response headers, cookies, set-cookie values, device/user codes, full token-endpoint request bodies, raw profile or entitlement payloads, raw token/profile error bodies, account emails, stable user identifiers, organization identifiers, callback URLs containing codes, local callback ports when they identify a live listener, or provider-specific response bodies.

### R12 — Speech input diagnostics are metadata-only

- For microphone, speech-to-text, or prompt-adjacent voice input, raw audio bytes, raw transcripts, interim transcript text, private vocabulary, workspace names, branch names, file names, prompt-adjacent context hints, and context-hint values are not log fields, metric labels, trace attributes, or free-form telemetry metadata.
- Allowed diagnostics are categorical state, bounded sizes and durations, redacted language/config ids, capture or stream attempt counters, consent/privacy-safe reason codes, and finality state names. Keep labels low-cardinality and scoped to the exact privacy/account/workspace context that allowed the feature.
- If support or debugging requires inspecting raw audio or transcript content, use an explicit consented artifact path with short retention, access audit, redaction review, and no default log/metric fanout.

### R13 — Local diagnostic, debug, and error sinks are support artifacts

- For CLIs, agents, desktop clients, and SDKs, treat local diagnostic, debug, and error logs as privileged support artifacts, not ordinary telemetry. Default diagnostic APIs should accept only typed metadata such as event class, level, bounded duration, counts, size buckets, capability state, finality state, and redacted reason code. Raw prompts, tool inputs or outputs, connector payloads, server response bodies, stack traces, local paths, current working directories, repository or project names, account identifiers, session identifiers, credentials, environment names or values, and free-form errors require an explicit support-artifact policy with consent, retention, access audit, and sink separation.
- Bind every local diagnostic sink to privacy state, principal/account scope where available, workspace scope, trust state, debug/support mode, sink identity, storage location policy, retention policy, redaction policy, queue generation, writer generation, and cleanup generation. A caller-provided log path, debug filter, category, event name, or connector label is untrusted input: validate containment or use an approved diagnostic directory, keep categories low-cardinality, escape multiline bodies, and never let filter syntax or category extraction become a privacy boundary.
- Error events queued before a sink attaches must be bounded and rechecked against the current privacy/support policy before drain; idempotent sink attach must not replay or duplicate events. Buffered writers need explicit max-count or max-byte behavior, ordered overflow handling, flush-on-shutdown, dispose idempotency, and visible degraded diagnostics when pending writes cannot be proven durable. Debug filters should fail closed for uncategorized messages when filtering is active; invalid mixed include/exclude filters must not silently widen visibility without a visible warning in privileged support mode.
- **Cap the size of any single logged value/field at emit time — per field, after redaction, on a UTF-8 boundary.** An unbounded logged value — a full request/response body, a large blob, a deeply-nested struct, an unbounded error chain — can OOM the process, exceed the pipeline's per-line limit (silently truncated/dropped *downstream*, where you can't tell it happened), or dominate log cost. Cap **each value/field before serialization** and record that it happened (a truncated-flag + the original byte length) so a reader knows the value was cut, not that it was short — emit that marker via a **canonical-schema field where one is defined**, otherwise an `app_*`-prefixed field; do NOT invent a raw `_`-prefixed name (the platform reserves the `_` namespace and its field-protection path may strip or rename an app-supplied `_` field, silently losing the evidence); **never truncate the finished JSON log line** — that corrupts the JSON and can drop the platform-reserved required fields (correlation and index keys per `references/log-schema-canonical.md`). Two ordering/encoding rules the naive version gets wrong: (a) **redact/scrub secrets & PII first, then cap** — capping before scrubbing can leave the redaction pattern unable to match, or truncate mid-secret and ship a partial token/PII prefix; the redactor itself must be **bounded/streaming** (scan incrementally, don't materialize a whole unbounded attacker-controlled value into a regex) so scrub-before-cap can't be turned into an OOM / CPU-DoS in the hot path; (b) truncate on a **valid UTF-8 codepoint boundary**, not a raw byte offset, or you emit invalid UTF-8 and break JSON/log ingestion. Do the cap **in the hot path** (low-allocation), not at downstream ingestion. Underlying all of the above: enforce the bounds (field count, nesting depth, per-field size, total size) at **ingress** — where the value enters the log event — so redaction, capping, and serialization each operate on already-bounded input, and enforce the total budget **incrementally during serialization** (stop/shed as bytes accrue), never by marshalling the whole event and then measuring. A bound enforced only at a late step (a regex redactor, `json.Marshal`) still lets an unbounded/deep value OOM or CPU-DoS every step before it. Per-field caps bound each value but not the whole event — an event with many bounded fields can still exceed the downstream per-line limit, so also enforce an **event-level serialized-size budget**: on overflow, shed or move non-required fields out-of-line (with a reference) while always preserving every platform-reserved required field **by its canonical name** (the `_`-prefixed required-fields list in `references/log-schema-canonical.md` — don't hardcode a spelling here that could drift from the schema), rather than letting the whole event get dropped or truncated downstream. Scope: applies to unbounded/large values; do **not** silently truncate audit / incident-critical content whose completeness is required — route that through the durable, non-truncated path (per the incident-critical durable-path rule above) or store it out-of-line with a reference.

## Workflow

When you are asked to design, review, debug, or instrument observability, run this checklist:

### Phase A — Identity chain

1. Confirm log-id is generated at the edge and propagated through every hop. Header name is a platform-wide constant; do not invent a new one per service.
2. Confirm OTel trace context propagates through HTTP, RPC, and queue messages. Spot-check by grepping for `traceparent` handling in framework code, not in user code.
3. Confirm logger extracts trace fields from `context.Context` automatically.

### Phase B — Framework wiring

1. Open the platform server-options module. Confirm the middleware chain attaches: ctx_inject, metrics, tracing, recovery.
2. Confirm `NewServer()` (or equivalent) is the only documented entrypoint; ad-hoc server construction is discouraged.
3. Confirm `/ping`, `/healthz`, `/readyz` (or platform-equivalent) are registered automatically.

### Phase C — Transport

1. Collector deployed multi-replica; pods explicitly NOT in mesh (annotation or namespace exclusion). Bypass mesh to avoid telemetry depending on the thing it observes. **mTLS caveat**: a STRICT-mTLS namespace blocks meshed apps from reaching a non-mesh collector. A non-mesh collector has no sidecar, so the fix is NOT a collector-side policy — it's a connectivity-owned decision on the meshed side (caller mTLS mode, mesh-egress config, or admitting the collector into the mesh as an exception). This skill only requires that such an exception is explicitly declared and owned by `platform-service-connectivity`; the policy mechanics (sidecar vs ambient, PeerAuthentication/DestinationRule) live there, not here.
2. Log file collector deployed as DaemonSet with hostPath access to the app log directory; explicitly NOT in mesh.
3. For OTLP-push processes: SDK buffers in memory — verify export queue size + timeout, and that drops are surfaced. For scrape processes: there is no SDK export queue — verify the scrape endpoint, target discovery, and `up`/scrape health instead.

### Phase D — Storage + display

1. Metrics: long-term store separate from scraper (e.g. `remote_write` to VictoriaMetrics or equivalent).
2. Traces: queryable by trace-id; retention configured by signal type, not all-or-nothing.
3. Logs: index by log-id and trace-id at minimum; service + env are required filters.
4. One dashboard tool joins all three. Service overview, latency by endpoint, error budget burn, top-N hot endpoints.

### Phase E — SLI / SLO / Alerts

1. List the top user-visible journeys. For each, write one availability SLI + one latency SLI as concrete PromQL/equivalent queries.
2. Set SLO targets and burn-rate alerts. Each alert links to a runbook entry.
3. Confirm alert delivery reaches an on-call human in < 1 minute for P0.

### Phase F — Evidence

Before marking the work done, produce:
- One end-to-end trace screenshot (or equivalent): user request → all hops → DB → return; log-id and trace-id visible.
- One dashboard screenshot showing the service's QPS + latency + error rate + saturation.
- One alert dry-run: trigger a fake threshold, confirm the chat-platform message arrives and the runbook link works.

If any phase has missing evidence, the work is not done.

## Decision Points

- **"OTel collector vs direct push to backend"** → always go through a collector. SDK → backend skips batching, retry, and central sampling control.
- **"DaemonSet vs sidecar for log collection"** → DaemonSet for file-based logs; sidecar only if a service writes to a custom path you can't standardize. Sidecar increases pod count linearly.
- **"Sample everything vs head-sample 1%"** → head-sample low (1–10%) for cost; retaining errors/slow requests is **tail** sampling at the Collector and requires near-full SDK export to it (head-dropped spans never arrive) — pick one model per service, do not claim both. Sampling-by-route is acceptable for known noisy paths.
- **"Metrics egress: scrape vs push"** → each platform picks ONE canonical egress and every process uses it. A Prometheus-native platform may default to **scrape** (pull, with `up`/target-health + service discovery); an OTel-first platform, or workers/jobs/runtimes that can't be scraped, may default to **OTLP push** to a collector. Neither is universally better — don't overturn a working pull setup just to push. One egress per process for a given metric; a migration window may dual-write only with isolated pipelines / distinct metric names / a dedup plan. Long-term store stays separate from the short-term scrape/collect layer (R5).
- **"Add a new label to a metric"** → answer the cardinality question first. If max distinct values × series count > 1e6, refuse and use an exemplar trace instead.
- **"Alert on this symptom or that cause"** → alert on user-visible symptom; cause-based alerts produce paging spam.

## Sanitization and Provenance

This skill is product-agnostic. It must not contain:
- Repository names, service names, internal hostnames, internal IPs, internal namespaces.
- Business-domain terms (e.g. tenant types, school/campus/bureau, course/exam).
- Concrete env-propagation header names that leak business identity.
- Specific image registry URLs, internal DNS names, or cloud-provider-specific artifact paths.

Reference patterns (PSM-style service identity `<owner>.<class>.<env>`, OTel semconv, baseline label set, log schema field names with `_` prefix) are reused industry conventions and may appear.

## References

- `references/obs-stack-architecture.md` — collector + metrics-store + log-pipeline + dashboard topology, multi-replica + mesh-exclusion rules.
- `references/log-correlation-recipe.md` — end-to-end log_id + trace_id + span_id propagation recipe across HTTP, RPC, queues.
- `references/metrics-conventions.md` — baseline labels, cardinality discipline, naming, instrument selection.
- `references/sli-slo-design.md` — SLI definition from user-visible journeys, SLO targets, error budgets, burn-rate alerts (industry baseline: Google SRE Workbook ch. 2–4).
- `references/alerting-and-on-call.md` — grafana-driven alerting without Prometheus AlertManager, chat-platform webhook delivery, runbook-in-wiki pattern.
- `references/framework-middleware-checklist.md` — the four mandatory middleware, order, and verification commands.
- `references/log-schema-canonical.md` — concrete field set (with types), ILM policy, filebeat config shape, file vs stdout trade-off, DaemonSet vs sidecar collection, online/offline backend split.
- `references/infra-component-deployment.md` — sizing/HA/retention/mesh-inject decisions for observability components; ExternalName + Endpoints binding for external observability services; log-cleaner sidecar pattern for verbose infra; snapshot-DR safety notes for stateful telemetry backends.

## Verification before marking work done

Run this acceptance:

1. **Static**: grep the framework default-options module — all four middleware present, no `if env == "prod"` gating.
2. **Live**: trigger one synthetic request; recover log-id from the response header; search log index by log-id → all hops appear; click trace-id → trace renders with > 1 span; service dashboard shows QPS bump.
3. **Alert dry-run**: fire a fake burn-rate threshold; confirm chat-platform message + runbook link.
4. **Cardinality scan**: list all metric labels and confirm no unbounded fields.
5. **Sanitization audit**: grep this skill's SKILL.md and references — zero hits on real service names, internal hostnames, or business-domain terms.
6. **Client control-plane audit**: for client/agent telemetry or remote config, verify privacy opt-out, trust-before-auth, auth/account refresh, principal-scoped persistent caches/queues, opt-out/logout/account-switch purge or invalidation, per-sink kill switch, stale-cache risk class, payload-shape validation, sink-specific PII stripping, bounded retry/drop with max queued events/bytes and TTL, and subscriber invalidation behavior.

If any check fails, the work is interim, not done.
