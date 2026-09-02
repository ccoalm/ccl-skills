---
name: llm-inference-integration
description: Use when designing, implementing, reviewing, debugging, or operating LLM, agent, RAG, prompt, model-routing, streaming, evaluation, replay, shadow, token-cost, or batch inference features across backend products. Product-agnostic; do not depend on prior codebase names, paths, providers, or business domains. Triggers also include "接 LLM", "大模型怎么调", "提示词怎么写", "RAG 怎么实现", "LLM 智能体 / 工具调用怎么搭", "模型评测".
---

# LLM Inference Integration

Use this for product backend work that calls, hosts, evaluates, or operates LLM and inference systems. Keep the skill generic: extract reusable mechanics only, not business-specific prompts, datasets, provider names, repository paths, or domain nouns.

## Skill Routing

- Use this skill for LLM gateway/client design, model registry, prompt versioning, agent/tool orchestration, streaming APIs, fallback, token/cost accounting, evals, replay, shadow comparison, batch inference, and inference observability.
- Use `go-microservice-architecture` or `go-microservice-dev` when the work is mainly a Go service with ordinary storage/RPC/MQ concerns and only minor LLM integration.
- Use `python-service-architecture` or `python-service-dev` when the work is mainly a Python service, AI-service host, worker, SDK/package, or batch job with ordinary API/storage/Redis/queue/pytest/packaging concerns and only minor inference integration.
- Use `nodejs-service-dev` on the same terms when that host is mainly a Node.js service, worker, or CLI/tooling with ordinary API/storage/queue/runner/packaging concerns and only minor inference integration; its architecture decisions must go to `product-rd-workflow`, never to a Node architecture sibling, which does not exist by decision.
- Use `defect-diagnosis` first when a model output, flaky eval, timeout, regression, fallback failure, or prompt/version issue must be reproduced and root-caused.
- Use `product-rd-workflow` first when the request spans product goal, PRD, architecture, implementation plan, release, and learning loop.
- Use `product-rd-workflow` first for AI/algorithm product launch SOPs, business acceptance baselines, build-vs-buy ROI, new-vs-iteration launch gates, or multi-algorithm product quality gates. This skill owns inference implementation/evaluation mechanics after the product gate is defined.
- For high-impact answers or decisions where wrong output can mislead users, affect money/rights/access, or create support/compliance risk, use `product-rd-workflow` high-risk resilience gates before fallback, downgrade, or launch decisions.
- When a change can alter what a client renders or which state, action, or decision path it offers—including strings/templates/config/flags and API/event/schema fields, enums, status/progress, permission/capability signals, defaults, or result shapes—you must load `../product-ui-ux-design/references/delivery-contract.md`, create the applicable full or lightweight record in that contract, and follow its canonical consumer-universe classification, design/test/client handoffs, and terminal-status rules.
- This inference owner returns only its `producer_record` delta: immutable binding, prompt/model/config/artifact identity, exact command/environment, and API/event/log/output observation.

## Generalization Discipline

- Keep only mechanisms that transfer across products:
  - Core: model/version registry, prompt lifecycle, request schema, safety boundaries, streaming protocol, retry/fallback, eval datasets, replay/shadow rollout, token/cost metrics, batch/concurrency control, audit trails.
  - agent-skill-system runtime (progressive-disclosure loading, description-driven skill routing, skill trust/sandbox boundary)
  - MCP integration (server primitives, server-as-untrusted-domain trust boundary, OAuth 2.1 / audience-binding auth)
  - agent capability composition (seam/provider/model-facing-tool decomposition, reversible registration with scope-owned disposal, policy-plugin-vs-enforcement split, sub-agent provider seam with one-shot/continuable separation — see `references/agent-capability-composition.md`)
  - agent command-execution sandbox (OS-sandbox composition, single-owner policy resolution consumed by every enforcement backend, command-policy DSL, approval/escalation state machine, loopback-only egress proxy — see `references/agent-command-sandbox.md`)
  - agent session persistence (append-only event-log source of truth, background-writer flush-before-finality, resume/fork with restored token accounting, context-window compaction — see `references/agent-session-persistence.md`)
  - agent ambient context freshness (diffable world-state sections vs one-shot fragments, comparison-snapshot-vs-rendered-text staleness detection, supersede-stale-in-band-not-retract, self-recognizing injections, derivable baseline + merge-patch re-derive on resume, budget-signaling-vs-compaction-enforcement — see `references/agent-context-freshness.md`)
  - robust model-driven file-edit (context-anchored hunks over line numbers, graduated-strictness matching, resolve-all-before-write, honest partial-failure reporting — see `references/agent-file-edit-protocol.md`)
  - agent turn lifecycle & task supervision (single-active-turn invariant, hierarchical cancellation tree, sample→act loop with deferred-input-drain ordering, mid-turn compaction, loop-level error taxonomy, grace-then-hard interrupt, flush-before-finality ordering, per-turn token-delta accounting, idle/mailbox wake — see `references/agent-turn-lifecycle.md`)
  - agent lifecycle-hooks framework (closed named event set, matcher dispatch with per-handler dedupe, concurrent-run-but-configured-order results, allow/deny/ask/block + additional-context decision model, permission-hook-outranks-built-in-approval, untrusted-command-hook safety — stdin-JSON versioned wire shape, per-handler timeout/kill, capture-don't-panic, bounded output spill, defensive parse — see `references/agent-lifecycle-hooks.md`)
  - agent tool-dispatch framework (uniform tool contract + registry, canonical name flattening, static-vs-dynamic searchable tool discovery for large tool sets, call-id-preserving router with typed dispatch-vs-execution errors, bounded parallel execution with abort-on-drop and shared-diff synchronization, result/post-hook shaping, and the optional code-mode pattern of exposing tools as a typed code/exec runtime with nested calls, yield/wait, and per-exec output budget — see `references/agent-tool-dispatch.md`)
  - automated approval reviewer (LLM-as-reviewer that auto-decides on-request approvals: opt-in gating that never overrides policy/hooks, isolated reviewer session with parent security context + compact bounded transcript + pinned exact action, strict structured allow/deny contract, fail-closed on timeout/error/malformed, and a rejection circuit breaker with consecutive + windowed denial caps that interrupts the turn — see `references/agent-approval-auto-reviewer.md`).
- Discard product-specific prompt content, labels, datasets, provider-specific branding, internal URLs, business metric names, user identifiers, and one-off scripts.
- For composite AI capabilities, validate both the changed sub-capability and the full user-visible chain. A retrieval, ranking, parsing, routing, tool-use, summarization, streaming, or prompt change cannot pass only on its local metric if end-to-end answer quality, latency, safety, citation/grounding, or product acceptance baseline regresses.
- When patterns conflict, choose deliberately:
  - Prefer standard API-compatible payloads behind a provider adapter over mixing incompatible provider formats in one fallback chain.
  - Prefer explicit model and prompt versions over mutable string constants.
  - Prefer recorded request/response metadata with redaction over untraceable calls.
  - Prefer bounded concurrency, timeout budgets, and cancellation over unlimited fan-out.
  - Prefer eval/replay/shadow evidence before traffic rollout over intuition-based prompt or model changes.
  - Prefer refusal or visibly degraded output over silently switching to a weaker or unapproved model for high-impact tasks.
  - Treat user uploads, retrieved documents, web content, tool results, and model outputs as untrusted data until validated.
  - Prefer fail-closed for safety, authorization, data-integrity, and tool-execution boundaries; fail-soft only for non-critical telemetry and best-effort logging.

## Core Workflow

1. Define the inference contract.
   - Identify sync response, streaming response, async job, batch inference, or agent workflow.
   - Define input schema, output schema, error model, timeout budget, idempotency key, and cancellation behavior.
   - Decide whether output must be plain text, JSON, tool calls, citations, embeddings, or files.

2. Define model and prompt control planes.
   - Track model provider, model name, model type, active version, parent version, and activation status.
   - Track prompt key, system/type namespace, version id, status, changelog, variables, defaults, active version, and rollback path.
   - Keep model selection and prompt rendering out of business handlers.
   - For user-impacting generated content, expose candidate, draft, or review-required state plus model, prompt/policy version, status, and cost/usage metadata where useful before final publication or action.

3. Build the gateway/client boundary.
   - Normalize payload shape per provider adapter.
   - Sanitize unsupported parameters per provider/model class.
   - Classify the OUTBOUND payload before it leaves for the provider. A handler must not place sensitive customer data / PII, secrets / tokens / credentials, or regulated content into a prompt or tool-argument sent to a third-party (or cross-residency) model without the operator's data-egress / provider-allowlist / data-residency policy permitting it — minimize or redact those values, or route to an approved-residency / self-hosted provider. This is the same policy the model-question auto-reviewer and any model call reference, applied as a gate on the PRIMARY inference call, not only on logs/fixtures (redacted in step 5) or the reviewer path. It is distinct from the inbound trust-boundary rule below (untrusted content coming IN): this governs sensitive data going OUT.
   - Implement error classification first — a closed failure taxonomy with explicit retryable semantics, locked per provider against real error responses — then build timeout, retry/backoff, fallback order, stream parsing, and usage extraction on top of it.
   - Deep gateway concerns — failure classification, conversation compaction, fallback/cooldown/degraded modes, usage/latency accounting, and prompt cache-miss attribution — gates, assertions, and routing -> `references/llm-client-gateway.md`.
   - Design the rendered prompt for prefix-cache stability (static-first ordering, byte-stable append-only prefix, tool set fixed within a loop) and track cache-read share per route; agent loops are prefill-dominated, so cache hit rate is a first-class cost and latency metric — rules in `references/llm-client-gateway.md` (prompt cache design).
   - Context-window overflow must not retry the same payload unchanged. Compact or truncate only with approved floors for required context, and fail closed if the reduction would drop safety, entitlement, privacy, permission, policy, tool-schema, source ACL/provenance labels, or source-grounding material, or if summarization would merge differently scoped sources.
   - For high-impact routes, fallback requires explicit quality-equivalence evidence or product/compliance approval; otherwise return a clear refusal or degraded state.
   - Enforce trust boundaries before using retrieved content, tool results, or model output in privileged actions; run the lethal-trifecta test (private data + untrusted content + an external channel) on every agent design and break it structurally when it holds — `references/retrieval-agent-safety.md` (Safety And Security, incl. the OWASP LLM Top 10 walk).

4. For tool-using agent runtimes, separate the runtime layers as a design and implementation acceptance gate.
   - Identify the bootstrap/router layer, runtime assembly layer, session lifecycle, per-turn model loop, tool execution path, permission decision path, state/transcript persistence, and recovery/resume path.
   - Trace representative turns through every state transformation: at minimum the normal allow path, deny/ask permission path, resume/recovery path, and dynamic-tool-change path. Each trace must cover user input normalization, context construction, budget or compaction projection, model streaming, tool-call validation, permission decision, tool-result insertion, continuation, terminal stop condition, transcript write, and usage/cost accounting.
   - Each runtime concern below gets layer-separation, and its gate / assertions / routing live in the named reference (read before gating that concern):
     - Runtime startup & config bootstrap -> `references/agent-runtime-bootstrap.md`
     - Capability composition — module/plugin boundaries, registration lifecycle, sub-agent providers -> `references/agent-capability-composition.md`
     - Turn lifecycle — per-turn loop, fg/bg handoff, progress, plan-to-execute, recap -> `references/agent-turn-lifecycle.md`
     - Session & transport — discovery/fork, history sync, workspace scope, protocol/stdout, settings migration -> `references/agent-session-persistence.md`
     - Hooks — hook/classifier output trust, hook config control plane, post-turn hooks -> `references/agent-lifecycle-hooks.md`
     - Command & host — shell, filesystem, sandbox, host-OS/GUI control -> `references/agent-command-sandbox.md`
     - Tools — exposure vs authz, connectors, side-effect authz, search/glob, tool-output artifacts -> `references/agent-tool-dispatch.md`
     - Credentials — secrets/tokens, browser auth flows, remote-session refresh -> `references/agent-credentials-auth.md`
     - Extensions & skills — install/reload, untrusted manifests/bodies -> `references/agent-extensions-skills.md`
     - Instruction composition — instruction-layer assembly, slash/skill invocation -> `references/agent-instruction-composition.md`
     - Input ingestion — typed/paste/media, voice, scheduled prompts -> `references/agent-input-ingestion.md`
     - Editor/IDE integration -> `references/agent-ide-integration.md`
     - Agent-to-agent messaging -> `references/agent-messaging.md`
     - Task orchestration — task control plane, state safety, recovery -> `references/agent-task-orchestration.md`
     - Model-initiated user-question prompts -> `references/agent-approval-auto-reviewer.md`
     - Memory — durable/query-time/shared memory, untrusted recall, fs/sync boundaries -> `references/retrieval-agent-safety.md`
   - For long-running agents, define explicit max iterations, max wall time, max output tokens, max total tokens/cost, max context utilization, per-turn/tool-result insertion caps, context-compaction fidelity and checkpoint invariants, fallback behavior when any budget is exceeded, cancellation, and resumability. A loop that works only while the process and context window stay healthy is not production-ready.

5. Add evaluation and rollout evidence.
   - Create eval datasets with expected output or rubric.
   - Keep the with-key tier first-class: keyless/replay tests prove the plumbing; a run against the real model is what supplies integration, routability, and deployment confidence — the highest-value such check is a smoke that boots the real assembled product, sends one prompt, and verifies the world (files written, tool effects), which catches the "green unit tests, broken product" class that mocks cannot. Because the live model chooses its own tools, that smoke runs only inside an isolated test tenant/workspace with test-owned resources, least-privilege credentials, and an explicit allowlist of reversible tools — production credentials, destructive, or externally-mutating capabilities stay denied unless a separately authorized, bounded test needs them. It is nondeterministic and does not by itself prove correctness: correctness claims still rest on the deterministic, assertion-based eval and regression gates above, consistent with `testing-strategy`'s evidence classes. Suites that need provider credentials may self-skip without them so keyless CI and contributors stay unblocked (a local or self-hosted model that needs none simply runs), but a skipped with-key test is **not run**, never "passed": report skipped separately from passed, and any acceptance/release/completion claim that depends on live-model behavior requires a designated live-model job — credentialed only where the selected provider needs credentials — to have actually executed the assembled-product smoke against the candidate — a non-skipped result bound to the exact candidate tree or built artifact **and** every controllable or observable input it ran under (provider/model identity, dependency, configuration, deployment, and environment generations); where a third-party provider exposes no generation, record the identity plus that limitation and carry the residual drift risk as `weak` evidence rather than pretending to a binding you cannot observe. Any change to a recorded input invalidates the result and the gate reruns (a green keyless lane cannot stand in). Self-skip is a credential guard, not a cost signal — when the team owns the model or inference is cheap, do not ration real-model runs. A run against a third-party model you do not control is confidence/routability evidence, classified `weak` per `testing-strategy`, not proof of correctness.
   - Record raw request/response metadata needed for reproducibility, with redaction.
   - Use replay and shadow comparison for model/prompt changes that can affect user-visible quality. Freeze the comparator, thresholds, sample scope, and stop rules before any replay/shadow/A-B/canary run — never define success criteria after seeing results.
   - Compare accuracy, latency, token cost, success rate, safety failures, and regression examples before rollout.
   - LLM-as-judge scores enter a decision only with the judge's bias controls (position, verbosity, self-preference), human-agreement calibration, and a confidence interval recorded; agent reliability is declared as pass@k or pass^k before measuring — `references/model-prompt-evaluation.md` (Eval Reliability).
   - For multi-stage inference chains, verify the real stage graph from source before per-stage acceptance, enumerate a sub-stage change's impact surface, and report component metrics and end-to-end metrics separately. The launch decision follows the product acceptance baseline, not the best-looking component metric.
   - Deterministic replay fixtures for model or tool outputs are test control planes, not ordinary caches.
     - Normalize volatile paths, timestamps, ids, counts, durations, costs, and platform path separators before computing fixture keys or writing fixture bodies; redact sensitive values before hashing, committing, logging, or comparing; and gate CI so missing fixtures fail unless record mode is explicitly enabled.
     - Replayed streamed or assistant messages must receive unique runtime ids, preserve event order, restore usage/cost only under the same request/model/prompt/tool tuple, and deduplicate replayed accounting so fixtures do not hide duplicate terminal usage, stale transcripts, or live-dependency drift.

6. Operate inference at capacity.
   - Bound concurrent calls and batch size.
   - Declare per-phase latency SLOs for generative routes (TTFT, TPOT/ITL, end-to-end) and gate capacity on goodput (requests meeting every SLO), not raw throughput; route latency-insensitive volume to provider batch endpoints — vocabulary, serving levers, and the batch contract in `references/inference-capacity-operations.md`.
   - Use async queues or job state for long-running inference.
   - For hosted inference, define autoscaling, max ongoing requests, batch wait timeout, health checks, warmup, and model-load failure behavior.
   - Register or expose hosted inference only after readiness is proven for the actual serving mode. Preserve service metadata, request/log ids, version routing, heartbeat/unregister behavior, and bounded shutdown or polling semantics.
   - Streaming inference must define timeout, cancellation, provider error, EOF/success, partial-content persistence, reader close, and usage/cost extraction after stream consumption.
   - Export per-model and per-route metrics; alert on timeout, fallback spike, token-cost anomaly, parse failures, and quality regression.
   - Define a post-launch drift-signal taxonomy (input distribution, no-answer/refusal rate, error-type distribution, latency, cost, timeout/failure, third-party dependency anomaly — applicable signals only) with pre-set, severity-tagged thresholds, response time-limits, and owners before ramp; attribute a shift before gating, and a gate-severity crossing pauses the ramp (with hysteresis/blast-radius limits), not just alerts. See `references/inference-capacity-operations.md`.

## Reference Loading

- For gateway/client, provider adapters, fallback, streaming, usage accounting, prompt cache design and miss attribution, and call records, read `references/llm-client-gateway.md`.
- For RAG retrieval, grounding, agent loops, agent-SDK framework building blocks (agent/loop/sub-agent-handoff/guardrail/session/tracing, vendor-neutral, + the mechanism-not-policy boundary), tool execution, agent-skill systems (progressive-disclosure loading, skill routing, skill trust/sandbox), MCP integration (primitives, server trust, tool-poisoning/rug-pull/confused-deputy failure modes, auth), prompt-injection defenses, and output safety, read `references/retrieval-agent-safety.md`.
- For prompt/model registry, versioning, activation, rollback, eval reports (judge-bias controls, statistical reporting, pass@k vs pass^k), replay, and shadow rollout, read `references/model-prompt-evaluation.md`.
- For hosted inference, batch serving, serving levers and the TTFT/TPOT/goodput vocabulary, provider batch endpoints, concurrency limits, async jobs, capacity tests, and operational controls, read `references/inference-capacity-operations.md`.
- For product launch templates, business acceptance baselines, build-vs-buy ROI, and new-vs-iteration gates, route to `product-rd-workflow`; this skill should not duplicate the product launch template.
