# Inference Capacity Operations

## Source-Backed Runtime Lessons

- Register or advertise an inference service only after readiness is proven. Readiness should cover the actual serving mode, such as model/application loaded, health endpoint passing, or deployment status running; a process start alone is not enough.
- For Ray Serve or similar deployment-graph hosts, treat `serve build`/`serve run` or a bound ingress object as deployment wiring evidence, not readiness evidence by itself. Confirm the deployment status, route availability, and loaded handler/model before registration or traffic shift.
- Service metadata should expose routing and diagnosis fields such as environment, partition, active version, startup timestamp, and build/commit version where available. Keep concrete registry/provider names out of generic code.
- Heartbeat, unregister, shutdown, and polling loops must be bounded or intentionally supervised. Avoid unbounded waits, hidden infinite loops, and process-kill behavior unless the platform contract explicitly owns it.
- Version and traffic routing should be explicit. If a caller requests a version, route deterministically; otherwise route by configured ratios that validate to `1.0` or fail without silently changing traffic.
- Inference handlers should preserve request/log ids through HTTP, gRPC, internal calls, and tests so failed predictions and support reports can be traced.
- Keep service host, SDK/registration, experiment/benchmark, generated artifact, model package, and runtime output folders separate. Do not convert model weights, generated configs, debug output, or benchmark scripts into default product-service architecture rules.
- Streaming responses need terminal state handling: timeout, context cancellation, provider error, EOF/success, partial-content persistence, reader close, and usage/cost availability after the stream is consumed.

## Capacity Controls

- Bound concurrent inference per process, route, model, provider, and tenant or user scope when needed.
- For batch inference, define max batch size, batch wait timeout, max ongoing requests, and backpressure behavior.
- For async jobs, persist task state and include lease, retry count, timeout threshold, terminal failure, and repair path.
- For hosted models, define warmup, health checks, model-load failure behavior, GPU/CPU resource requests, autoscaling target, and max replicas.

## Batch Serving

Batch serving should make latency/throughput tradeoffs explicit:

- `max_batch_size` caps memory and tail latency;
- `batch_wait_timeout` controls how long requests wait for aggregation;
- `max_ongoing_requests` protects the replica;
- per-item output ordering and error mapping must be deterministic.

Keep preprocessing and postprocessing deterministic and cheap. Expensive transformations should be measured separately from model inference.

## Load And Regression Checks

Before rollout, run a bounded capacity check for:

- QPS/concurrency saturation;
- p50/p95/p99 latency;
- timeout and retry rate;
- queue depth or pending job age;
- memory/GPU pressure;
- token cost per successful output;
- streaming first-token latency and final-token latency when applicable.

Use dry-run or report-only modes for migration/backfill/batch jobs whenever possible.

## Fine-Tuning And Local Models

- Treat fine-tuned models as registry versions with parent base model, training data lineage, training job id, parameter recipe, eval gate, and rollback path.
- Do not promote a fine-tuned model without comparing it against the base model and current production model on the same eval set.
- For local/self-hosted inference, document runtime engine, quantization, context length, batching policy, KV-cache behavior, GPU/CPU memory budget, and warmup path.
- Keep training data governance separate from prompt logs: consent, retention, redaction, deduplication, and evaluation leakage must be explicit.
- **Compressing agent/conversation trajectories into a training or eval dataset must preserve signal and avoid label/leakage bugs — not just fit a token budget.** When a recorded trajectory exceeds target length, do NOT head/tail-truncate or uniformly shrink. Protect the **head** (system prompt + first user turn + first action/tool turn = task setup) and **tail** (final actions + conclusion = outcome). The **middle is the learnable signal** for tool-use imitation / process-supervision / trajectory evals (tool choices, observation handling, correction loops, failed attempts) — compress it only after preserving the salient action/observation spans; never collapse the taught/evaluated behavior into one summary (same destruction as blind truncation). Three invariants make this safe:
  - **Group / split / dedup / leakage-screen by original-trajectory lineage BEFORE compressing, and re-run overlap checks after.** Compress-then-split leaks: a compressed example and its near-raw sibling can straddle the train/eval boundary, or an LLM-written summary can absorb eval content (contamination — see the anti-contamination rule in `model-prompt-evaluation.md`).
  - **An LLM-generated compression/summary note is NOT an original turn.** Keep it in metadata outside the supervised message/action stream, or explicitly mask it from loss / eval scoring; never serialize it as an assistant/tool turn — otherwise you teach the model to emit curator summaries and turn observations into synthetic labels.
  - **Govern "salient" before selecting.** Define salience criteria up front, preserve required negative/failed/correction spans, record selector + version + reason, and audit the slice distribution before/after — post-hoc "keep the interesting parts" cherry-picks a non-representative set (worse for evals, where it inflates or deflates scores).
  This is the offline-dataset counterpart to — and distinct from — runtime context compaction (loop mechanics in `agent-turn-lifecycle.md`, fidelity floors in `agent-session-persistence.md` / `llm-client-gateway.md`), which preserves *current intent / pending tasks* for continuation; here the goal is *training/eval signal*.
- Capacity tests should include cold start, model load failure, concurrent requests, batch saturation, and memory pressure.

## Operational Failure Modes

Plan for:

- provider timeout or rate limit;
- fallback provider incompatibility;
- malformed JSON/tool calls;
- streaming disconnect;
- partial batch failure;
- model load failure;
- prompt activation regression;
- runaway token cost;
- stuck async task.

Each failure mode should map to an owner-visible metric, log, trace, or report entry.

## Post-Launch Drift Monitoring And Ramp Gating

A launch eval proves a version at one point in time; inference quality drifts as input distribution, retrieved context, model behavior, or dependencies change. Define drift monitoring before ramp and wire it to ramp control, not only to a passive alert.

Distinguish two drift types because they are observable at different times. **Data drift** is a shift in the *inputs* (query mix, length, language, retrieved-context distribution, embedding distribution) — it is a *leading* signal, measurable immediately without ground truth, and is an early warning that quality may degrade. **Concept drift** is a change in the right *answer* for the same input (the input→correct-output relationship moved) — it is a *lagging* signal that usually cannot be measured directly in an LLM system with no immediate ground truth; detect it through labels, human-review/feedback, or proxy quality metrics, which arrive later. Do not treat a clean data-drift dashboard as proof quality is fine; concept/quality drift can be real while inputs look stable, and only the lagging signals will show it. "Lagging" is not "wait passively for labels": where the answer depends on fast-changing facts (prices, policy, legal status, knowledge-base content), add leading proxies for concept drift — content/source freshness and version-skew monitors, synthetic recency probes, change hooks on the upstream source of truth, and a high-risk human-review queue — so stale-wrong answers surface before the label/feedback signal arrives.

- **Drift signal taxonomy — monitor every applicable signal; mark the inapplicable ones N/A with a reason.** Input-distribution shift (new query types, length, language mix); empty/no-answer/refusal-rate shift; output-error-type distribution shift (new failure classes, not just total error count); latency (first-token and full-response); token/compute cost per successful output; timeout and failure rate; third-party/provider dependency anomaly (provider latency, error, rate-limit, or a silent default-behavior change). Not every signal applies to every product (an embedding or classifier service has no refusal rate; a batch job has no first-token latency) — record N/A explicitly so a real blind spot is distinguishable from an inapplicable signal.
- **Each signal has a pre-defined threshold, response time-limit, and owner before ramp.** "We monitor X" without a trigger value and an owner is not monitoring. Define the absolute or relative trigger, how long the condition must persist to fire, who is paged, and the target time to a disposition decision.
- **Attribute before you gate — a raw metric shift is not model drift.** A no-answer/refusal/latency/cost shift can come from seasonality, a product campaign, an abuse spike, or an upstream traffic-mix change, not the new version. Use slice-aware baselines, compare against a control / current-prod cohort, require a minimum sample/traffic volume, and exclude known seasonality and classified abuse/incident traffic before attributing a shift to the candidate.
- **Tag each threshold as warning or gate; only a gate-severity crossing pauses the ramp.** Warning thresholds page the owner and inform the disposition decision; gate thresholds halt expansion and, per the rollback contract, can downgrade or roll back. An alert that does not gate ramp lets a regression ride to full traffic — but auto-pausing on every warning causes flapping and, across many co-gated services, a synchronized failover storm. Before any automated pause/rollback require hysteresis, a debounce window, the minimum sample size above, and a per-route blast-radius limit; large or cross-service pauses escalate to a human rather than firing globally at once.
- **Define behavior under stale or missing telemetry separately.** When the gating signals are delayed or absent, do not treat "no breach observed" as healthy: high-risk routes fail closed (hold or roll back); other routes hold the current ramp step and page the owner rather than continuing to expand blind.
- **Keep a live-traffic observation set distinct from the frozen benchmark and the regression bad-case set.** Sample real post-launch traffic to test whether the new version fits the *current* input distribution; the frozen benchmark answers "as good as before" but cannot detect distribution drift. This sampling is subject to the same privacy discipline as eval/replay records (see `retrieval-agent-safety.md` Safety And Security): privacy-approved sampling, redaction/minimization, a retention TTL, and access control; use synthetic or aggregated substitutes where raw traffic capture is prohibited. Confirmed bad cases from this set feed the regression bad-case set (see `model-prompt-evaluation.md`).
- Metric pipeline, alert routing, and dashboard mechanics are owned by `platform-observability`; ramp/pause/rollback authority and time-limits are owned by `platform-release-engineering` and the launch gate in `product-rd-workflow`. This section owns which inference drift signals to watch and the ramp-gating contract.

## Triton-Class Multi-Model Serving

When inference is served through Triton (NVIDIA), Triton-compatible engines (PaddleX HPS, KServe), or any multi-model server with config-driven model loading:

- One server instance can host many models (commonly 10-30+). Each model is a directory under the model repository with a `config.pbtxt` (or equivalent) plus versioned weights. The server is the runtime; the configs are the contract.
- Use **ensemble scheduling** when an inference call needs `preprocess → model infer → postprocess` chained: declare the ensemble as a synthetic model so the client sees one logical call. Intermediate tensor names are part of the contract and must not collide.
- **Backend choice per model**: Python backend for pre/post and custom logic, TensorRT/CUDA for GPU model inference, OpenVINO IR for CPU-optimized inference, framework-specific engines (PaddleX HPS) for vendor stacks. Mixing backends in one server is normal; the server config is where the choice is recorded.
- **Heterogeneous instance scaling**: CPU pre/post stages declare `kind: KIND_CPU` with higher instance count (6-8) because they parallelize cheaply; GPU model stages declare `kind: KIND_GPU` with low instance count (1-2) bound by GPU memory **AND** GPU compute share. The two scale independently.
- **GPU compute oversubscription is a separate failure mode from GPU memory**: when multiple `instance_group { kind: KIND_GPU }` entries (across all models loaded on the same physical device) share one GPU, raising `instance_group.count` does NOT linearly increase throughput — past the point where concurrent kernels fully utilize the GPU's SM / memory-bandwidth capacity, additional instances queue inside the CUDA driver / GPU scheduler. Triton's per-model **queue duration** (`nv_inference_queue_duration_us`) measures only the time spent in Triton's scheduling queue BEFORE dispatch and does NOT include GPU-scheduler contention after dispatch; that contention shows up in **compute duration** (`nv_inference_compute_infer_duration_us`) and in end-to-end latency. Real failure mode: memory fits comfortably, the Triton config validates, the model loads, queue duration looks healthy, end-to-end P50 doubles under load.
  - **Measure don't model**: there is no clean formula to predict the cliff. `instance_group.count` is NOT a static compute-share allocator; MPS limits are process/context-level not per-model-instance; vendor partitioning (MIG) is only meaningful when explicitly configured. Treat capacity as an **empirical profiling** problem: use Triton Model Analyzer or measure end-to-end P50 / P95 / throughput at target concurrency BEFORE and AFTER any count change. Never raise the count on intuition that "more instances = more throughput".
  - **Choose by SLA thresholds at equal offered load, not per-metric dominance**: a higher count can win on P50-of-completed-requests while losing on P95 (long tail under contention), losing on throughput (more queueing externally), or losing on throughput stability (autoscaler thrash). The decision criterion is whether the configuration meets the **declared per-metric SLA thresholds** (P50/P95/P99 budgets, sustained throughput target, tail-variance ceiling) at target concurrency. A config that violates any SLA threshold is unsafe and rolled back, regardless of which alternative is "better on P50"; a config that meets all thresholds wins, regardless of whether the alternative beats it on a non-SLA metric. Document the chosen SLA thresholds next to the config so the next engineer's "which is better" question has a single answer.
  - **When explicit partitioning IS available, sum one partition level at a time, not across nested levels**: each partition mechanism scopes "100%" to its own parent. MIG slices each get a fraction of a physical GPU; their allocations sum to ≤ 100% of that physical GPU and that constraint is enforced by MIG itself. MPS clients each get `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` of their MPS server's view; in the nested case where MPS runs INSIDE a MIG slice (MPS-on-MIG), the MPS server's "100%" IS the MIG slice — not the physical GPU. The sum-check is layered: at each level, the children sum to ≤ that level's budget. Don't flatten the levels — summing every MPS-client percentage across every MIG slice on a physical GPU against a single 100% double-counts and rejects valid nested configurations. Concretely: physical GPU vs MIG slices: MIG-allocator handles the sum. Multiple MPS clients on one MPS server (whether that server is on a bare GPU or inside one MIG slice): sum the clients against the MPS server's parent budget (the bare GPU's 100%, or the MIG slice's 100%). Multiple MPS servers sharing the SAME parent (multiple MPS servers on one bare GPU, or multiple MPS servers inside one MIG slice — uncommon but possible): aggregate ALL clients across ALL sibling MPS servers against the shared parent's budget — two MPS servers each running at "100%" of the same bare GPU is 200% of one GPU and oversubscribes. **MPS limits do NOT scope per-`instance_group` inside one Triton process**: `CUDA_MPS_ACTIVE_THREAD_PERCENTAGE` is per MPS client (the whole Triton process), not per model-instance — claiming you can sum it across N `instance_group` entries inside one Triton server is wrong and either rejects valid configs or grants false isolation confidence. Without partitioning at the right boundary, the rule is empirical profiling above.
- **Dual config files per model** (`config_min.pbtxt`, `config_max.pbtxt`) plus an env-variable selector at startup is the common pattern for switching between resource profiles (lab vs prod, dev vs canary, CPU-only vs GPU). Document which profile each environment uses.
- **Dynamic batching**: in Triton two settings work together. `max_batch_size > 1` at the model level **permits** batch shapes (the model can receive a tensor whose first dimension is the batch). The `dynamic_batching { ... }` scheduler block selects the dynamic batcher — present and empty means "enable with default knobs". When the block is absent, the effective behavior depends on the backend: some backends (TensorRT, ONNX Runtime in certain configs) and `auto-generated` model configs may enable dynamic batching with defaults when `max_batch_size > 1`; other backends (Python backend, custom backends) do not. **Audit by the effective generated config and observed batching metrics, not by source-`pbtxt` grep alone**: load the model and inspect Triton's `/v2/models/<name>/config` endpoint or the model status logs, then verify with batching metrics under load. `preferred_batch_size` and `max_queue_delay_microseconds` inside the block are tuning knobs that shape latency-throughput trade-off; set them explicitly when latency is sensitive (typical: `preferred_batch_size` close to expected concurrency, `max_queue_delay_microseconds` matching the SLA budget). For variable-length token inputs, add `allow_ragged_batch: true`. A config with `max_batch_size = 1` cannot batch regardless of the block.
- **Model warmup** belongs at startup, not at first-request latency. A warmup sample per model amortizes JIT, kernel selection, and KV-cache allocation cost so the first production request is not a cold call.
- **Version policy**: `model_version: -1` (latest/all) is convenient but loses reproducibility. For services with version-sensitive behavior, pin the version explicitly and rotate through a versioned route or canary policy.
- **Per-model GPU affinity** is necessary when GPU memory or compute is tight. Sharing one GPU device id across all models works only while combined memory and concurrent kernels fit; under contention, declare `instance_group { ... gpus: [n] }` per model.
- Standard ports (HTTP 8000, gRPC 8001, metrics 8002) are conventions; expose them through the platform's discovery layer rather than hard-coding client URLs.

## ML Pipeline Visualization Service

When a multi-stage inference pipeline (detection → classification → matching → structured output) is in production, debugging output drift in any single stage requires a side-by-side comparison of the stage's input, intermediate tensors, and final output. A separate visualization service is the durable answer; ad-hoc Jupyter notebooks per investigation rot fast and silently drift from production code:

- **Per-stage handler classes share the production input contract**: the visualization service declares one handler per pipeline stage (`<stage>_visualize.py`) that consumes the same input shape the production service consumes for that stage. When the production stage changes its input contract, the visualization handler is updated in the same PR — if it is not, the visualization renders stale and silently misleads debug sessions.
- **Common base handler for cross-stage concerns**: a `BaseHandler` owns request id, log context, image / tensor download from object storage, structured logging, and the notification webhook for shareable links. Stage handlers inherit and override only the stage-specific render logic. Without the base, every stage handler re-implements the same boilerplate and drifts.
- **Gradio (or equivalent) is the UI seam, not the inference seam**: the visualization service exposes Gradio components (image viewer, text panel, JSON tree) wired to the stage handlers; inference itself reuses the production stage implementation — NOT a parallel reimplementation. Concretely: (a) when the production caller SDK exposes the per-stage outputs the viz needs (often just the final stage output), the viz tool calls that SDK; (b) when the viz needs raw intermediate tensors that the public SDK does not expose, the viz tool reuses the production *stage modules* directly (the same Python classes / Go packages production runs) rather than re-implementing the stage. Both paths satisfy the rule — what is forbidden is a second copy of the stage logic that drifts from production. If neither path works (production-only Triton ensemble, no Python-level stage entry), add a sanctioned trace/debug interface on the production service (gated by internal auth) and have the viz tool consume that — never resort to a parallel implementation.
- **Ray Serve / equivalent for multi-tenant viz**: when multiple engineers use the tool concurrently and the visualization itself is non-trivial (image processing, large response rendering), deploy the viz service via Ray Serve so concurrent users do not block each other on the Python GIL. For low-volume internal tools, a single-process Gradio is fine; document the scale assumption.
- **Output artifacts go to object storage with a shareable URL — and every access path along the chain has its own controls**: every visualization render writes the rendered image / annotated tensor to object storage with a request-id-prefixed key; the response includes the URL so the engineer can share the result. The artifact path is a separate access surface from the ingress: (a) bucket ACL restricts which identities can read the prefix (internal-employee identity provider, not "anyone with the URL"); (b) signed URLs carry a short TTL (minutes for routine debug, never weeks); (c) webhook payloads / chat previews that auto-expand the URL are themselves access paths — disable link-unfurl in the channel or post hashes-only when the artifact contains sensitive customer data; (d) audit log captures who fetched which artifact, for post-incident review. In-browser rendering only is fine for one-off looks; for any incident-class debug, the artifact persists for post-mortem reference.
- **Internal-only network exposure with auth — ingress is the first gate, not the only one**: the viz tool exposes intermediate model outputs that are normally hidden from end users (raw output strings, confidence scores, intermediate features). Bind the ingress to an internal-only network; gate by SSO / VPN. The ingress alone does NOT cover the artifact-storage path (separate controls above), the webhook / chat surface where URLs land, or developer machines that download and cache artifacts locally — each is its own access path with its own controls. The same redaction rules that apply to logs apply to viz output for any sensitive customer data.
- **Mode / env selector via a single env var**: a flag like `VIZ_MODE=full | extract-only | classifier-only` selects which subset of stage handlers is active for a given deployment. Avoid one deployment trying to be all things; route a slim viz to one URL and the full pipeline viz to another when they have different access policies.

## Inference API Layer Above Triton

When a Python service wraps Triton (or directly hosts models) as the request-facing layer:

- **Three deployment shapes** are common: FastAPI + Ray Serve (multi-model orchestration with `@serve.deployment` and `autoscaling_config`), FastAPI + uvicorn lifespan (single-model CPU service with eager singleton load), and llama.cpp `llama-server` (GGUF self-contained binary for VL / GGUF-quantized LLM). Pick by model and traffic shape; document the choice per service.
- **Ray Serve specifics**: `autoscaling_config(min_replicas, max_replicas)` controls scale. **Backpressure has two distinct knobs**: `max_ongoing_requests` is the per-replica in-flight cap that drives autoscaling and queue-vs-route decisions (it is **not** a rejection threshold); `max_queued_requests` (at the deployment / HTTP proxy layer) is the cap on requests waiting in the router queue and **is** where rejection happens (excess returns 503 / back-pressure). Pick both intentionally — `max_ongoing_requests` follows model-replica capacity (commonly single-digit to low tens for GPU models, higher for I/O-bound work), `max_queued_requests` follows the SLA budget on queue wait. `max_batch_size` lives on the actor / handler, not at Ray level. Build the deployment via `serve build` / `serve run server_config.yaml`.
- **Model load lifecycle**: handlers load models on `initialize()` (Ray Serve) or lifespan startup (FastAPI) as singletons per actor or per worker. Lazy first-request load is acceptable only when readiness reflects the load state.
- **Per-handler timeouts** match each model's measured SLA and queue budget. One global timeout cannot cover models that span two orders of magnitude in latency; record example values only as service-local tuning, not as a generic skill default.
- **Per-model batching**: declare `max_batch_size` per model based on the model's actual memory profile (text embedding 24, orientation 8, layout detection 4 are typical). The orchestrator (Ray Serve actor pool) handles scheduling.
- **Image / large-payload handling**: accept the image as a protobuf message field (e.g. `ImageDetectReq` deserialized from JSON body) rather than a separate multipart upload; for very large payloads, accept a pre-signed object-storage URL and let the server fetch. When the inference output is itself a binary (corrected image, mask, rendered overlay), prefer returning a signed object-storage URL over inline base64 so callers do not pay the wire-cost on every response. If the API contract requires inline bytes, do not strip them from the response (that breaks callers); apply size limits at the logger / persistence layer so log bloat is bounded without changing the response contract.
- **GGUF + llama.cpp serving**: use `-ngl <n>` to push all layers to GPU (`-ngl 99` for full offload), `-b` / `-ub` for batch / micro-batch sizes, `-np` for parallel contexts. For OCR-style use, set `--temp 0` (greedy decode) so output is deterministic. Expose the server's OpenAI-compatible HTTP API; do not invent a new wire format on top.
- **multi-version handler coexistence** (v1 and v4 in the same service) is the pragmatic pattern when a model rolls out incrementally. Route by request field (`version`) or by `handler_flow_ratio` for canary traffic; do not silently swap.

## Model Artifact Integrity

Self-hosted inference depends on weights, configs, and tokenizers loaded into a process with GPU and network access. Treat artifact loading as a supply-chain step, not a file copy.

- **Immutable digests**: every model version is addressed by content digest (sha256 / model registry hash), not by mutable path or "latest" symlink. The runtime resolves digest → object-storage URI at load time and refuses to load if the resolved bytes do not match the expected digest.
- **Signed manifests**: where the registry supports it, sign the model manifest (weights + config + tokenizer + metadata bundle) and verify the signature before load. A model not signed by an approved key path fails closed; do not load with a warning.
- **Config + weight pairing**: refuse to load when `config.json` / `tokenizer.json` / `model.safetensors` come from different versions — pin all artifacts of one model to one digest.
- **Safe deserialization**: prefer `safetensors` (no executable code) over Python `pickle` / `torch.load(..., weights_only=False)` for untrusted-origin models. If a `pickle`-based format is unavoidable, only load from an approved internal registry with manifest signature verification; never load from a user-supplied URL or attachment.
- **Build-time vs runtime**: bake artifact integrity checks into the model-load path so they run in production, not only at build time. A build-time-only check is bypassable by runtime symlink / mount substitution.

## Failure Domain Isolation Across Co-Hosted Models

One Triton or Ray Serve instance commonly hosts 10-30+ models. Without isolation, one bad model (OOM, hang, infinite loop, malformed weights) takes the rest down with it.

- **Separate processes by trust and criticality**: high-trust / high-criticality models (auth-gating classifiers, billing-affecting evaluators) run in their own server process, not co-hosted with experimental / large / unstable models. Don't host an experimental VL model in the same Triton process as the production OCR critical path.
- **GPU isolation**: where the GPU supports it, partition with NVIDIA MIG (Multi-Instance GPU) so one model cannot monopolize compute or memory of another. Where MIG is unavailable, use `CUDA_VISIBLE_DEVICES` to pin per-process GPUs and accept the lower utilization in exchange for isolation.
- **CPU / memory cgroup limits**: containerize each server with explicit CPU and memory limits matched to the model's resident footprint plus headroom; a Python-backend model that leaks memory should hit its container limit and OOM-kill itself, not exhaust the host.
- **Python backend isolation**: when Triton's Python backend hosts user-supplied or experimental logic, run it in a separate Triton instance from compiled backend models so a Python-side crash does not cascade.
- **Blast-radius review**: before adding a new model to an existing multi-model server, audit what else lives there and what fails if the new model OOMs or hangs. If the answer is "the critical path", co-hosting is the wrong decision.

## Inference Service Operational Hygiene

Recurring anti-patterns observed across production inference services:

- **`print` instead of structured logging**: every inference log line should carry `request_id`, `log_id`, model name, model version, and the standard stage timing fields. `print` calls drop on container restart and cannot be aggregated.
- **GPU OOM not caught**: `torch.cuda.OutOfMemoryError` and equivalents must be caught, surfaced as a typed error (not 500 Internal), and surface in metrics so capacity planning can react. Silent OOM crashes look like flaky network errors to the caller.
- **`uvicorn --workers 1`** without justification is a single-worker bottleneck even when the host has many CPUs. Pick the worker count consciously (often 1 when the model holds a single GPU, more when CPU-bound).
- **Disabled framework logging** (`llama-server --log-disable` or equivalent) makes triage impossible. Keep at least warn-level logging in production and redirect to a file or sink the platform aggregates.
- **No `/health` / `/ready` endpoint**: readiness must reflect model-loaded state, not process-running state. Without an explicit endpoint, orchestrators and discovery layers cannot distinguish "process up" from "model ready to serve".
- **Mismatched runtime declarations**: a service whose `config.properties` describes one runtime (e.g. TorchServe) but whose start script launches a different runtime (e.g. Ray Serve) is a maintenance trap. Keep one canonical declaration and delete or clearly mark legacy files.
