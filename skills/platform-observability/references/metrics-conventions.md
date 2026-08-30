# Metrics Conventions

## Baseline labels (attached automatically by the framework metrics client)

| Label | Source | Notes |
|---|---|---|
| `service` (or `psm`) | env var | Service identity — PSM-style `<owner>.<class>.<env>` or `service.name` OTel attribute. |
| `lane` / `env` | env var | Deployment environment label (`prod`, `test`, `pre`, or named lane). Mesh-routed traffic per lane → labelled lane lets you isolate per-lane regressions. |
| `idc` / `region` | env var | Data center / cloud region. |
| `cluster` | env var | Kubernetes cluster name (or equivalent orchestrator unit). |

The framework metrics client appends these to **every** metric automatically. Service code calls `cli.Counter(ctx, name, value, kvs...)` with only domain-specific labels; baseline is invisible to the caller.

**Instance identity (`pod_name`/`pod_ip`/`node_ip`/`instance`) is NOT a baseline metric label.** Pods churn under autoscaling/rollouts, so as a label they grow unbounded series over the retention window (each labelset = a separate time series). Emit instance identity as **OTel resource attributes** and **log fields**, and reach a specific instance via **exemplars** or a low-churn `*_info` target-metadata metric joined at query time — not by labelling every metric with it.

## Per-metric labels — cardinality discipline

Allowed:
- API path (templated, e.g. `/v1/users/:id`, never raw URL).
- Endpoint / handler name.
- Method (GET/POST/...).
- Error code class (`server_panic`, `validation_error`, `upstream_timeout` — bounded enum).
- Status code class (`2xx`, `4xx`, `5xx`).

Refuse:
- User-id, tenant-id, account-id.
- Raw URL with query string.
- Free-text error message.
- Log-id, trace-id, request-id (these are exemplar attachments, not labels).
- Timestamps as labels.

Cardinality test: `count_distinct(label_value) × count_distinct(other_labels) × series_count`. If projected > 10^6, refuse and route to exemplar traces or to a different signal type.

## Instrument selection

| Use case | Instrument | Notes |
|---|---|---|
| Request rate, error count | Counter (monotonic) | OTel `Counter` increment only — required for request/error totals so backend `rate()`/`increase()` semantics work. **不用 `UpDownCounter`**（那是非 monotonic，用于活跃连接 / 队列深度等 active count）。 |
| Latency | Histogram | Bucket boundaries must be sensible for the SLI (e.g. 1ms, 5ms, 10ms, 50ms, 100ms, 500ms, 1s, 5s). |
| Saturation (queue depth, connection pool) | Gauge (Observable, async) | Read-on-collect, not write-on-event. |
| Cumulative resource | Sum | E.g. bytes transferred. |
| One-shot probe | Histogram with single value | When you need percentile semantics. |

Async observable gauges via OTel SDK reduce noise vs synchronous sets. Pattern: register one callback per metric; reduce buffered samples (avg/max/last) at collection time.

## 业内方法对照（Golden Signals / RED / USE → 本 ref 已有 instruments）

业内不同 framework 讲法不同，下表把外部命名映射回本 ref 已要求的 instrument，避免被术语卡住：

| 外部框架 | 关注什么 | 适用对象 | 映射到本 ref instrument |
|---|---|---|---|
| **Google 4 Golden Signals**（SRE Book）| Latency / Traffic / Errors / Saturation | service-level（user-facing service）| Latency → Histogram；Traffic → Counter (request rate)；Errors → Counter (error count)；Saturation → Gauge (queue / pool / cpu / mem) |
| **RED**（Tom Wilkie；原始 Weaveworks 博客已随公司关停下线，现存最佳出处为 Grafana 官方博文 "The RED Method"）| Rate / Errors / Duration | request-driven service / RPC endpoint | Rate → Counter；Errors → Counter；Duration → Histogram（近似等于 request-side Golden Signals 去 Saturation；非正式 derivation）|
| **USE**（Brendan Gregg）| Utilization / Saturation / Errors | resource（CPU / memory / disk / NIC / connection pool）| Utilization → Gauge (%) ；Saturation → Gauge (queue depth)；Errors → Counter（资源驱动而非请求驱动）|

何时用哪个：
- **service-level 默认从 Golden Signals / RED 起步**：API endpoint 健康度首选这两套
- **resource-level 默认从 USE 起步**：DB connection pool / CPU / NIC 健康度首选这套；USE 也可用在软件资源（如 thread pool / goroutine queue）不限硬件
- 实际仪表盘常**混用 RED + USE**（Wilkie 自己也推荐）— framework 是脚手架不是教条
- 三套不替代 SLI/SLO 设计（参 `sli-slo-design.md`）— 是 day-to-day 仪表盘 + 报警的 baseline 共同词汇

## Naming

`<domain>_<noun>_<unit>_<aggregation_hint>`

Examples:
- `http_server_request_total` — request count, counter.
- `http_server_request_duration_seconds` — latency, histogram (base-unit seconds in name, per R3; matches the OTel-translated name and the SLI query in `sli-slo-design.md`).
- `rpc_client_call_total` — outbound RPC count.
- `service_panic_total` — recovery counter.
- `queue_pending_messages` — gauge.

Avoid:
- Generic names like `count`, `latency`, `total` without domain.
- Mixed-case names.
- Domain leakage (e.g. `school_login_total` for a non-public service skill; use `auth_login_total` instead).

## SDK initialization

```
MeterProvider:
  - Resource attrs (semconv): service.name, deployment.environment, k8s.pod.name, host.id
  - Reader: PeriodicReader, interval 15s, OTLP gRPC exporter
  - Exporter: insecure inside cluster (TLS at network layer)
View overrides (optional):
  - Custom histogram buckets per metric name.
```

The 15s reader interval matches Prometheus scrape conventions and keeps OTLP push volume sane.

## Prometheus 3.0 Baseline (Nov 2024+)

- **Prometheus 3.0 (released 2024-11-14, per `prometheus.io/blog/2024/11/14/prometheus-3-0/`) lifts the UTF-8 normalization requirement** — metric and label names can contain dots, slashes, colons, and other UTF-8 characters by default. This is the bridge for OpenTelemetry metrics: no more mandatory dots-to-underscores translation on ingest, so `http.server.request.duration` reaches Prometheus and PromQL queries unchanged. **OTLP receiver is native**: Prometheus exposes `/api/v1/otlp/v1/metrics` for direct OTel push; for projects that want the legacy underscore shape, opt-in `otlp.translation_strategy = UnderscoreEscapingWithSuffixes` per the migration guide. **Native histograms are first-class wire support in 3.0** — a native histogram sample is one time series carrying sparse exponential (or custom) buckets, replacing the multi-`_bucket`-series Classic histogram shape; far more efficient on cardinality and quantile accuracy; opt-in per metric via SDK; PromQL `histogram_*` functions handle both representations transparently. (Native histograms remain marked as experimental in early 3.x and stabilize in a later 3.x release per the Prometheus team — verify the specific 3.x version's stability state before production-pinning a metric to native-histogram-only.) **Remote-Write 2.0** carries native histograms + metadata + exemplars + created-timestamp in the wire protocol. **Breaking-change audit before flipping**: `remote-write-receiver` / `promql-at-modifier` / `promql-negative-offset` feature flags removed (apps depending on `--enable-feature=...` for those will fail to start); Remote-Write `enable_http2` default changed to `false`; PromQL syntax tightening for `@` and negative-offset edge cases. Pin Prometheus version in platform manifests, rehearse upgrade on a non-critical scrape target, and verify dashboards / recording rules / alerts still parse before flipping production. **Migration discipline for the UTF-8 names flip on existing deployments** — switching translation off on a running platform silently breaks every PromQL expression that references the underscore-form translated names (`http_server_request_duration_seconds_bucket` no longer exists if the OTel name `http.server.request.duration` now arrives un-normalized). Required pre-flip steps: (a) inventory every PromQL expression referencing OTel-translated metric names across dashboards / recording rules / alert rules; (b) dual-publish both forms during a bake window (Collector emits both transformed and untransformed series via a duplicating processor), or migrate query references first against a staging Prometheus before flipping production; (c) run `promtool check rules` plus a query-result dry-run on critical alerts; (d) flip the translation strategy only after the inventory shows zero unmigrated references. Underestimating this is the typical "silent dashboard outage on Tuesday morning after a platform upgrade" failure.

## OpenTelemetry GenAI Semantic Conventions (Development → opt-in)

- **OTel GenAI conventions (status: Development as of 2026-Q1 per `opentelemetry.io/docs/specs/semconv/gen-ai/`)** standardize LLM observability across providers. Span attributes include `gen_ai.system` (anthropic / openai / google.gemini / etc), `gen_ai.request.model`, `gen_ai.response.model`, `gen_ai.request.temperature`, `gen_ai.usage.input_tokens` (includes cached tokens per spec), `gen_ai.usage.output_tokens`; metric `gen_ai.client.operation.duration` for end-to-end latency. **The OTel GenAI spec says SHOULD NOT capture prompt/tool-argument content by default** — only metadata (model names, token counts, durations). However, **individual instrumentation libraries vary**: some community SDK middleware (LangChain instrumentations, vendor-specific tracing wrappers, OTel-contrib LLM packages) have historically defaulted to capturing prompt text in spans, contrary to the spec's spirit. Required platform-side discipline: **audit each instrumentation's prompt/event capture default before enabling GenAI telemetry on a service** (run a smoke test on a sandbox model call, inspect the emitted span attributes, confirm prompts are absent unless explicitly opted-in via the library's content-capture flag). Opt-in to content capture is a deliberate per-service decision with PII / compliance review; when enabled, capture content via event-based attributes that flow through trace events, NOT metric labels (prompt-content as a metric label would explode cardinality and likely violate the platform's label allowlist). **Stability mechanism**: instrumentations honor `OTEL_SEMCONV_STABILITY_OPT_IN` env (comma-separated; include `gen_ai_latest_experimental` to emit current conventions, else they emit the v1.36.0-frozen version). When platform-observability standardizes label / attribute allowlists across services, include the GenAI attributes alongside HTTP / RPC conventions in the bounded set; route LLM-specific span events (prompt content, tool-call payloads) through the trace backend, not metric labels, to keep metric cardinality bounded.

## Common mistakes

- Treating per-request fields as labels → cardinality explosion → metric backend OOMs.
- Forgetting to add baseline labels manually because the metrics client wasn't used.
- Using gauge for monotonic counters (loses rate semantics on restart).
- Histogram with too few buckets (loses percentile precision) or too many (storage cost).
- Recording metrics inside a tight loop without rate-limiting (collector receives bursts).

## Observation Discipline（查询/看板/新增信号的通用纪律）

- Cross-layer evidence boundary: a client-side event does not prove backend success, and a backend metric does not prove the user saw success — any conclusion crossing the client/backend (or service/service) boundary requires identifiers or time windows aligned across the layers, never a same-shape count on each side.
- Observation code never intrudes on the observed path: instrumentation and evidence collection are best-effort and must not add retries, blocking waits, or business-logic branches to the monitored path — observability that changes the behavior it measures is its own defect class.
- Discover before creating: before proposing a new event, metric, label, panel, or query, enumerate what already exists for that surface and extend/reuse it — parallel near-duplicate signals fragment dashboards and split history.
- Environment-name resolution: a user's explicit component/branch/URL/datasource always wins; never silently substitute a different physical environment for a colloquial environment word — resolve an unqualified name to the recorded default and say which one was used.
