# Observability Stack Architecture

Reference topology and component-level rules. Stack-agnostic; specific vendors named only as recurring examples.

## Topology

```
          ┌──────────────────────────────────────────────────────────────┐
          │                      Service Pod                              │
          │  ┌─────────────┐  ┌─────────────────┐  ┌──────────────────┐ │
          │  │ App + OTel  │  │ Mesh sidecar    │  │ Log writer       │ │
          │  │ SDK         │  │ (if mesh used)  │  │ (zap → stdout    │ │
          │  └────┬────────┘  └────┬────────────┘  │  + host file)    │ │
          │       │ OTLP/gRPC      │ (mesh telem)  └────────┬─────────┘ │
          └───────┼────────────────┼─────────────────────────┼───────────┘
                  │                │                         │
                  ▼                ▼                         ▼
          ┌──────────────┐  ┌──────────────────┐    ┌──────────────────┐
          │ OTel         │  │ Mesh control     │    │ File-collector   │
          │ Collector    │  │ plane telemetry  │    │ DaemonSet        │
          │ (Deployment, │  │  (Envoy stats)   │    │ (hostPath access)│
          │  N replicas, │  └────────┬─────────┘    └─────────┬────────┘
          │  NOT in mesh)│           │                        │
          └──┬─────────┬─┘           │                        ▼
             │ metrics │ traces      │              ┌──────────────────┐
             ▼         ▼             ▼              │ Log pipeline     │
        ┌─────────┐ ┌────────┐  ┌──────────┐        │ (logstash/vector,│
        │ Scraper │ │ Trace  │  │ Mesh     │        │ JSON parse,      │
        │ (Prom,  │ │ backend│  │ metrics  │        │ field promotion) │
        │ remote_ │ │ (Jaeger│  │ scrape   │        └─────────┬────────┘
        │ write)  │ │ /Tempo)│  └────┬─────┘                  │
        └────┬────┘ └────┬───┘       │                        ▼
             │           │           │              ┌──────────────────┐
             ▼           │           │              │ Search index     │
       ┌──────────┐      │           │              │ (ES/OpenSearch)  │
       │ Long-term│◄─────┘           │              └─────────┬────────┘
       │ metric   │                  │                        │
       │ store    │◄─────────────────┘                        │
       │ (VM/Mimir│                                           │
       │ /Cortex) │                                           │
       └────┬─────┘                                           │
            │                                                 │
            └────────────────┬────────────────────────────────┘
                             ▼
                  ┌──────────────────────┐
                  │  Dashboard tool      │
                  │  (Grafana/equivalent)│
                  └──────────────────────┘
```

## Component Rules

### OTel Collector
- Deploy as Deployment with ≥ 3 replicas (not DaemonSet — DaemonSet wastes resources for OTLP, and you cannot tail-sample across nodes).
- Pipelines: separate traces, metrics, logs pipelines in the collector config. Shared receivers, separate processors and exporters.
- Processor minimum set: `batch` (always), `memory_limiter` (always), `tail_sampling` (if backend supports it), `resource` (to inject k8s.pod.name etc. when not on SDK).
- Annotate the collector pods to **exclude from mesh** (e.g. `sidecar.istio.io/inject: "false"`). Telemetry must not depend on mesh data plane.
- Resource limits: start at 250m CPU / 512Mi mem requests; 4 CPU / 8Gi limits. Tune from real load.
- Listen on OTLP gRPC (4317) and OTLP HTTP (4318) at minimum.

### Metrics path
- App SDK exports via OTLP → collector → Prometheus exporter scrape OR direct remote_write to long-term store. A process picks ONE egress (OTLP push, or a Prom scrape endpoint), per the SKILL `Decision Points`; collector/scrape/remote_write is a platform back-stage choice.
- Long-term store (VictoriaMetrics, Mimir, Cortex, or managed) MUST receive its samples from the collect/scrape layer (`remote_write` from a scraper, or collector `remote_write`/OTLP) and stay separate from it.
- Dashboards and alerting query the long-term store, NOT the scraper. The scraper is fungible.
- AlertManager is OPTIONAL — see `alerting-and-on-call.md` for the grafana-only pattern.

### Trace path
- SDK → collector (with batch + tail-sampling processor) → trace backend (Jaeger v2, Tempo, Zipkin, or a vendor).
- Sampling: head-sample 1–10% in SDK; tail-sample errors + slow + named-route at 100% in collector.
- Span attributes mandatory: `service.name`, `deployment.environment`, `k8s.pod.name`, baseline labels matching metrics.
- Trace retention: hot 7 days, warm 30 days, cold optional. Most queries are < 24h old.

### Log path
- App writes JSON to **stdout** (preferred) OR to a known host file path (rotated).
- File-collector DaemonSet reads from hostPath (e.g. `/opt/<org>/app/log` or `/var/log/containers`) → ships to log pipeline.
- Log pipeline (logstash, vector, fluentbit) parses JSON, promotes nested fields to root, adds metadata (k8s namespace, pod, node).
- Index by log-id and trace-id at minimum. Time-based index rollover (daily or larger).
- Daemonset and collector pods MUST be excluded from mesh.

### Dashboard tool
- One tool joins metrics + traces + logs. Grafana is the de facto baseline.
- Service overview dashboard template includes: QPS, latency p50/p90/p99, error rate, saturation (CPU/mem/queue depth), top-N hot endpoints, error budget burn.
- Per-team dashboards inherit from the template; do not let teams rebuild the basics.

## Anti-patterns to refuse

- SDK → backend direct, no collector: loses batching, central sampling, retry buffer.
- DaemonSet collector for OTLP: wastes resources, breaks tail sampling.
- Mesh-injected collector: telemetry depends on the thing it observes.
- Prometheus as long-term store: loses data on restart, hard to scale.
- AlertManager + chat webhook + grafana alerting all running in parallel without ownership: alert duplication.
- Per-pod log volume PVC: high cost, IO contention, fragility.

## Cardinality 分层：alerting 用 bounded metrics，investigation 用 high-cardinality events

业内 high-cardinality observability（Honeycomb 等，Majors / Fong-Jones / Miranda *Observability Engineering* 2022）核心洞察：**metrics 与 events 各管各事，不要混**。本 stack 按下面切分：

- **Metrics（bounded label set）— alerting + 总览仪表盘**：label cardinality 严控（参 `metrics-conventions.md`），可聚合可比较，长期 retention 友好。回答的问题：**"系统现在 / 过去 N 段时间 是否健康"**
- **Traces + structured log events（high-cardinality）— investigation**：可带 user_id / request_id / tenant_id / 任意 business attribute；不预聚合；按 trace_id 关联。回答的问题：**"为什么这一条请求慢 / 错了 / 为什么这个用户的工作流挂了"**
- **Exemplars 桥接两者**：metric 数据点附带代表性 trace_id，看到 latency histogram bucket 异常时，可直接跳到一条对应的 trace 看现场。OTel metrics SDK 规范已稳定支持 exemplar；实际可用性取决于 SDK / exporter / backend 三方都启用 — 落地前确认 stack 链路完整

**操作纪律**：
- 高基数维度（user_id / tenant_id / request_id / order_id 等）**默认拒绝**进 metric label（一般会爆 cardinality）；按 `metrics-conventions.md` cardinality budget threshold 评估，仅 bounded / enumerated 维度（如 ≤ N 个固定 tenant tier）经 budget review 后允许；其余进 trace span attribute / structured log field
- 报警基于 metric（bounded label + 聚合）；on-call 收到 alert 后用 trace / event 下钻
- 不为"以备查问"在 metric 上预聚合每个业务维度 — 那是 trace / log 的职责

参对 SLI/SLO（`sli-slo-design.md`）：SLI 是 metric 层（bounded），SLO/error budget 也是 metric 层；event-first investigation 是 SLI 报警触发后的下一步。
