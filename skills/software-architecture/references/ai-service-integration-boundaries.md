# AI Service Integration Boundaries

Use this for Python service architecture around LLM, RAG, model inference, embedding, OCR, vision, or ML calls.

## Scope Boundary

- This skill owns Python service hosting, API boundaries, worker execution, dependency clients, timeouts, streaming endpoints, and persistence around inference.
- `llm-inference-integration` owns prompt design, model routing, retrieval design, evaluation, replay, token/cost policy, batch inference strategy, and agent behavior.

## Service Rules

- Separate request validation, inference orchestration, provider/client adapter, and result persistence.
- Treat model calls as external dependencies with timeout, retry, rate limit, cost, observability, and partial-failure handling.
- Long-running inference belongs in workers or async job APIs when request latency is not bounded.
- Streaming endpoints need cancellation, heartbeat, error event, and cleanup policy.
- Vector stores and embedding tables are data adapters; define ownership, refresh, versioning, and deletion policy.
- GPU/CPU-bound inference must have concurrency controls and memory pressure safeguards.

## Inference Service Runtime Topology

For Python services that host models or wrap model-serving runtimes (Triton, TorchServe, Ray Serve, llama.cpp llama-server):

- **Deployment shape choice** is an architecture decision: FastAPI + Ray Serve for multi-model orchestration with per-model autoscaling and traffic ratio; FastAPI + uvicorn lifespan for single-model CPU services with eager singleton load; llama-server / vLLM / similar for self-contained GGUF / safetensors with OpenAI-compatible HTTP surface. Mixing shapes within one service is a finding.
- **Model load is part of readiness**, not startup side-effect. The readiness probe reflects "model loaded and warm", not "process up". Health stays public early so the orchestrator can place pods; readiness flips only after the model is callable. **FastAPI lifespan loading interaction**: putting a multi-minute model load inside the lifespan startup blocks the whole app from serving any endpoint (including `/health`) until startup completes; Kubernetes can restart the pod before readiness ever flips. Use one of: (1) Kubernetes startup probe with a generous failure budget (cluster waits the model-load time before liveness/readiness fire); (2) a separate lightweight health-only HTTP server on a different port that runs immediately while the main app loads; (3) an async load state machine where the main app starts immediately and `/ready` reads a "loaded" flag the background loader flips. Document which pattern the service uses.
- **GPU memory budget is declared per replica**, not inferred. Document the model's resident memory, KV-cache budget (for LLMs), and headroom required for the largest expected batch; pick `instance count` / `Ray Serve replicas` so the product fits.
- **Three-stage instance lifecycle**: register only after readiness; heartbeat with bounded cadence and explicit failure path; on SIGTERM deregister first, drain in-flight requests with a deadline, then close model handles and exit. Unbounded loops, process-kill exits, and registration-before-load are anti-patterns.
- **Service metadata exposed to discovery** carries lane, environment, partition, active model version, startup timestamp, and commit hash. Discovery can route by lane and surface "which model version is serving this lane" without polling each instance.
- **Per-request log_id and request_id propagation**: middleware reads W3C `traceparent` + `tracestate` (and `baggage` when needed) via OpenTelemetry propagator `extract` so spans continue the parent trace, alongside the platform's `X-Log-Id` / `X-Request-ID` for log correlation. At public trust boundaries, regenerate or validate inbound request ids so callers cannot spoof log correlation; on internal hops, preserve. For `asyncio.create_task` / Ray actors / thread-pool workers, capture the OTel context at task creation via `opentelemetry.context.get_current()` and reattach inside the worker; without this, child-task spans become orphans of the parent trace.

## Internal Inference RPC Authentication And Authorization

"Internal infrastructure" is not a security boundary on its own. Inference endpoints reachable from the service mesh need explicit auth at the architecture layer:

- **Service identity**: every caller has a verified workload identity — mTLS service certificate, SPIFFE / SPIRE ID, signed JWT issued by the platform identity provider, or k8s service account token. The inference service refuses unauthenticated callers; "from inside the cluster" is not authentication.
- **Caller allowlist per model**: each inference endpoint declares which callers (service identities, teams, environments) are allowed to invoke it. The allowlist is enforced by middleware before the model is loaded, not by trust in network reachability.
- **Tenant / resource authorization**: when the call carries a tenant id or resource id, the inference service verifies the caller is permitted to use that tenant's / resource's data. A tenant-id passed in the request body and trusted as truth is a finding.
- **Quota / rate limiting per caller × model × tenant**: a shared GPU model is a shared resource; per-caller quotas prevent one consumer from exhausting capacity for the rest.
- **Signed object-storage URL trust**: a signed URL is a bearer credential plus a server-side fetch target. The inference server enforces (1) allowed bucket/host allowlist (SSRF defense), (2) allowed object namespace / prefix per caller, (3) maximum expiry window (minutes, not hours), (4) HTTP method scope, (5) content-length and content-type caps, (6) checksum / digest validation when the registry supports it, (7) redaction of signed query parameters from logs and trace attributes.

## Discovery Cache Miss Policy

The fallback policy on discovery cache miss is **per-route**, not a portfolio default. The SDK's cache fall-back-to-baseline-lane behavior must be overridable per call:

- Read-only idempotent calls on data that is already public-to-the-tenant (classification, OCR on already-uploaded content) MAY fall back to a documented baseline lane.
- Canary, stress, shadow, tenant-sensitive, or write-with-side-effects routes MUST fail closed when the requested lane has no healthy instance. Silent fallback can leak canary traffic, stress traffic, or one tenant's processing into the wrong lane.
- The default for unmarked routes is fail-closed. Per-route opt-in to baseline fallback is explicit and reviewed.

## Internal Inference SDK Boundary

Portfolios with multiple Python inference services converge on an internal SDK that owns the integration concerns:

- **SDK scope**: service discovery (registry-based or k8s-native, with environment/lane filtering), transport (sync and async paths against the same wire), retry with bounded budget, tracing header injection, contract (de)serialization (protobuf / Pydantic / equivalent), and registry-side lifecycle helpers (`register / heartbeat / shutdown`).
- **Distribution**: package the SDK as a wheel published to a private package index. Pin the version per consumer; SDK upgrades are managed changes with a release note, not ambient editable installs.
- **Service identity format**: SDK validates the platform's chosen identity format (e.g. three-segment `<owner>.<class>.<env>` or equivalent) at client construction; mistyped identities fail at startup, not at first request.
- **Lane derivation**: SDK reads the lane environment variable at startup and tags every outbound discovery query and trace span; in-cluster discovery filters by lane metadata so a canary cannot fall back to production by accident.
- **Discovery cache + failover**: SDK caches the resolved instance list with a short refresh interval (5-15 s), filters to healthy + matching lane, and load-balances over the survivors (round-robin or random). On cache miss, baseline-lane fallback is **per-route, not default-on**: it applies only to routes explicitly opted in per the Discovery Cache Miss Policy above; canary / stress / shadow / tenant-sensitive / write-with-side-effects and all unmarked routes fail closed (never silently fall back) — wiring baseline fallback globally leaks canary/tenant traffic into the wrong lane.
- **Typed exceptions**: SDK raises typed errors (`InferenceTimeout`, `InferenceModelUnavailable`, `InferenceTransport`) rather than `RuntimeError("...")` with a string. Business code catches by class.
