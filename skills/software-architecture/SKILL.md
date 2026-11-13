---
name: software-architecture
description: 后端架构怎么设计 / 服务边界·微服务怎么拆 / 数据归属 / Go 后端架构怎么设计 / Go 微服务怎么拆 / RPC 接口怎么定义 / Go 服务边界 / Python 后端架构 / FastAPI 项目结构 / Celery worker 拆分 / Python 微服务边界 / Node.js·TypeScript 服务架构与服务边界 / 多租户隔离怎么设计 / 消费 Kafka·消息队列与事件驱动架构 / 数据平台（分库分表·读写分离·备份恢复） / 服务分层重构 / Go 服务重构 / Python 服务重构 / 拆分上帝类·模块边界 (decompose a god class) → design or review service architecture for Go, Python, Node.js/TypeScript or cross-stack backends (boundaries, contracts, data ownership, async/worker model, reliability, runtime) with no code changes; implementation and localized refactor (某文件/某类) go to go-microservice-dev / python-service-dev / nodejs-service-dev; multi-stage / cross-module refactor delivery re-enters product-rd-workflow.
---

# Software Architecture

Design, review, or explain backend and service architecture before code: boundaries, contracts, data ownership, runtime model, and the tradeoffs between them. Product-agnostic — never assume an existing repository, service identifier, package path, database, or legacy layout.

## Routing

- **Use for** architecture decisions on Go, Python, Node.js/TypeScript, or cross-stack backends: service decomposition (microservice, modular monolith, worker, script, package), API/RPC contract shape, storage ownership, async/worker/job design, reliability, service-side observability, release readiness, and platform boundaries. An unqualified whole-service refactor ("重构这个服务") enters here; do not let it fall to an implementation skill.
- **Not for** a local DTO field, component-local state, work inside an already-chosen design, or a localized refactor (某文件/某类). Those, and every request to implement, modify, scaffold, generate, or test code, go to the stack's dev skill: `go-microservice-dev`, `python-service-dev`, `nodejs-service-dev`.
- `product-rd-workflow` goes first when the request spans product shaping, architecture, implementation, review, release, and learning; a multi-stage / cross-module refactor delivery re-enters it. For money, billing, quota, permission, tenant/user data isolation, privacy, high-impact AI, repeated writes, async finality, or incident-explanation risk, start from it and its high-risk resilience gate before choosing service boundaries or fallback behavior.
- `defect-diagnosis` goes first to reproduce, isolate, instrument, or root-cause a defect, regression, review finding, or failing test. `testing-strategy` goes first when the question is which unit, integration, contract, or E2E layer proves behavior; then return here for the architecture impact.
- Load one stack's defaults: the stack the service runs on. Read another stack's defaults only for explicit cross-language contract design. Use codebase-specific skills only when the task is explicitly about an existing legacy/workspace repository.
- This skill owns the **service-internal** view and exposes a fixed contract to the platform layer. When the decision touches another owner's ground, load that owner too:

| The decision involves | Also load | This skill keeps |
|---|---|---|
| Logs, metrics, traces, log-id propagation, dashboards, alerts, SLI/SLO | `platform-observability` | The service-side surface: fields the handler emits, middleware the framework attaches, health endpoints |
| Service mesh, discovery, mTLS, lane routing, retry/timeout/circuit-breaker policy, canonical RPC base struct | `platform-service-connectivity` | What the service exposes: framework default options, request-metadata conformance, graceful shutdown |
| Environment/lane matrix, canary, promotion gates, rollback, secret distribution, dynamic vs static config, image build | `platform-release-engineering` | Service-side contracts: config schema, secret consumption, registration metadata |
| Inference, RAG, prompt, model routing, evaluation, replay, token cost, batch inference | `llm-inference-integration` | The service boundary that hosts or calls those capabilities |
| Web, app, or mini-program client structure | `web-react-dev`, `app-cross-platform-dev`, `miniapp-product-dev` | The server contract those clients consume |
| CLI or terminal command contract | `terminal-cli-dev` | The service the tool talks to |

- The full service-vs-platform contract table for Go and for Python is in `references/service-design-rules.md` ("Platform boundary contract"). Platform-level questions (which mesh policy, which collector, which canary weight) route to the platform skills.
- References here define decision criteria, invariants, ownership boundaries, and acceptance checks; concrete code patterns, helper APIs, and test mechanics belong in the dev skills. When you change a rule that implementation must obey, name the downstream owner before landing — the stack's dev skill for code mechanics, `testing-strategy` for the proof layer, platform skills for runtime contracts, `product-rd-workflow` for cross-stage gates — route the change through `skill-extraction-workflow`, and decide each stack part and each dev skill explicitly (update or skip with a reason).

## Method

Scale the plan to risk. A simple low-risk explanation can use a short inline plan. Multi-service, contract-visible, data-ownership, release, high-risk, branch/MR, or unclear-risk work needs the full decision record of step 6 before edits or approval. Walk the steps in order and say which ones do not apply; each step's full wording is in the matching section of `references/service-design-rules.md`.

### 1. Boundary

- Identify user workflows, domain objects, external integrations, and lifecycle events; decide which capabilities are synchronous APIs, internal RPCs, async jobs, scheduled tasks, batch pipelines, or packages.
- Split into a separate deployable service only when ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify it — not by noun count. Otherwise a modular monolith, worker-only service, script, or package is valid; record the reason. A justified service names its owner, data source of truth, contract, runtime dependencies, inter-service auth, timeout/retry policy, deployment unit, and rollback boundary.
- Go and Python internal service calls use RPC/gRPC by default and may use HTTP when the contract chooses it; a Node.js/TypeScript service uses the transport its platform contract names. Internal HTTP meets the same discovery, auth, timeout, retry, observability, and contract-test bar as RPC.
- Layers are transport, application/service logic, domain logic, infrastructure adapters, generated contracts. Transport stays thin: auth, validation, request/response mapping, orchestration handoff. Shared libraries carry infrastructure concerns, never domain rules.
- When the boundary, layering depth, or dependency direction is the decision, read the playbook for the service's stack before concluding: `references/go-architecture-playbook.md` for Go, `references/python-architecture-playbook.md` for Python. Node.js/TypeScript has no playbook: apply the layers above with the inner layers owning the interfaces their adapters implement, plus the Node.js/TypeScript part below; never adopt the Go or Python playbook's stack conventions for it.

### 2. Contracts

- Define the contract before implementation: globally unique service name first, then the contract source, then generated artifacts, then business code. Request shapes, the response envelope (`code`/`message`/`data`, canonical in `platform-service-connectivity/references/http-response-envelope-contract.md`), and shared public fields live in the shared contract source.
- Every consumer — Go, Python, web, mobile, mini-program — derives from the same contract source. Do not fork IDL or generated artifacts per repository or per language, hand-write generated types, or treat generated clients as service-local source, except as a deliberate compatibility branch with owner, version, and deprecation plan.
- Shared cross-service DTOs, enums, status values, and metadata fields live in the contract or generated-artifact boundary; service-private domain and persistence models stay inside the owning service and convert at the transport/application boundary. Separate public API models from internal RPC models when external clients need different stability.
- Evolve additively: new fields, methods, endpoints, enum values; never break field numbers or response semantics. A platform-standardized metadata field's number, name, and type are compatibility surfaces.
- For protobuf-backed HTTP, decide contract source, generated artifacts, and wire format separately, and classify it with the gate in `platform-service-connectivity/references/protobuf-http-contract-signals.md`; do not restate or widen that predicate.
- For each finite value that crosses service, storage, client, analytics, or generated-code boundaries, name the canonical owner, shared location, conversion boundaries, unknown/default behavior, and migration or debt exit before implementation. Without a shared location, approve the local-slice fallback and require every `finite-value-debt` marker to carry task reference, owner, deadline, and reason.
- Keep a machine-checkable inventory of every externally reachable surface — HTTP routes, RPC methods, async subscriptions — and review new ones at the boundary. The inventory proves a surface was seen, **not** that it is authorized; auth, tenant isolation, and safe exposure stay separate evidence. An unregistered route or consumer is a shadow surface.

### 3. Data and state ownership

- Each service owns its write model, schema, and migration path. Cross-service reads go through RPC/API or explicit read models, never shared-table writes.
- The relational database is the source of truth for transactional and auditable state. Redis serves cache, locks, counters, idempotency windows, rate limits, and ephemeral coordination — not durable truth; define key scope, TTL policy, lock lease, rate-limit window, and idempotency lifetime as part of the design.
- Decide schema, indexes, unique constraints, migration path, and sharding keys before data-access code. Queries stay behind a DAL, repository, or unit-of-work boundary; transport and application layers do not build them. Generated migrations are drafts: review them before landing, and get human sign-off only before a destructive one runs on shared data.
- Before concluding on schema or migration design, read the reference for the service's stack: `references/go-data-modeling-and-migrations.md` for Go, `references/python-data-modeling-and-migrations.md` for Python; for Node.js/TypeScript apply the rules in this step and hand the data-access mechanics to `nodejs-service-dev`. When the decision is engine choice, HA, replicas, sharding, backup, or pooling, read `references/data-platform-architecture.md` first. When tenants share the system, read `references/multi-tenant-isolation.md` first.

### 4. Runtime and dependency contracts

- Config is typed and environment/lane-specific. High-risk feature flags and runtime config default fail-closed in production; local stubs and test defaults are visibly scoped and never become implicit production enablement. Secrets never live in code, config files, examples, tests, or generated clients.
- Every dependency client — DB, Redis, MQ, object storage, discovery, secret provider, external HTTP, inference — has explicit timeout, credential, observability, and test-substitution contracts. Serving-path budgets are separate from admin, migration, bootstrap, repair, and batch timeouts.
- Internal trust rests on workload identity, mTLS, signed service tokens, or an equivalent control, not network location. Context — trace/log id, lane, authorization and resource scope, deadline, auth subject — propagates through every sync and async path.
- Define the error contract once, then map transport, framework, worker, and dependency errors into it. Admission control (rate limits, concurrency limits, load shedding, backpressure, circuit breaking) is part of reliability design.
- Register for traffic only after readiness passes; readiness is externally observable; shutdown deregisters, drains, closes clients, and exits within a bounded time.
- A capability requirement is not a framework-adoption decision. Define the capability's minimal closure and name the layer that closes it; when a framework default conflicts with a service characteristic, split at the boundary and record each deferred capability's closure status. Manifests alone leave graceful drain `not closed`.
- External dependency bootstrap needs an operability contract: which resources may be created automatically, which existing ones are only validated, which partial failures are repairable, which failures stop startup, and separate timeouts for administrative work and for serving requests.
- Long-running jobs need a first-class runtime model: lock scope, lease, max execution time, concurrency, retry policy, idempotency key, checkpoint/restart, and failure visibility.
- High-risk operations need a resilience contract: fail-closed policy, idempotency, durable status, reconciliation or repair path, trace propagation, a user/support explanation surface, and proof that fallback cannot bypass authorization, tenant/user isolation, quota, audit, or retention. Context resolution rejects a missing tenant, actor, subject, or resource scope instead of defaulting; durable side effects need atomic audit/outbox evidence or an explicit repair workflow.
- When the design publishes or consumes durable messages, read `references/event-driven-architecture.md` before concluding.

### 5. Generation, quality, and release readiness

- Generated code, generated clients, and generated routes are output surfaces, never hand-edited. Generation commands are documented in the repo, portable, and free of developer-local absolute paths.
- Logs, metrics, traces, health/readiness endpoints, request ids, and safe debug exposure are architecture surfaces. Package and runtime choices are reproducible: lockfile, dependency groups, lint/type/test commands, container entrypoint.
- Define deployment resources, process model, worker concurrency, canary/smoke checks, rollback, and migration order before launch.
- When comparing against a mature internal reference, produce a platform-capability gap list, not a source-code shopping list. A placeholder or README-only package is not implementation evidence; check nested repositories, non-default branches, and tags before calling a capability absent. Anything drawn from internal checkouts passes the `skill-extraction-workflow` sanitization gate before it lands.

### 6. Decision record

For anything beyond a low-risk explanation, the output states: assumptions, alternatives considered, tradeoffs, acceptance checks, verification evidence, rollback or migration path, and named handoffs to the implementation, testing, platform, or product-workflow owners. A new or migrated HTTP gateway/framework additionally needs a quotable record with separately locatable entries for capability justification, contract source, middleware order, generated artifacts, observability, and tests.

A design document also writes down how the service meets its runtime contract. Walk this list and answer each item in the document, or say why it does not apply:

1. Each call to an external dependency: its deadline or timeout, and how that deadline reaches the call (in Go, through `context.Context`).
2. Where each dependency client is constructed and how handlers receive it: built in startup or app-factory code and injected, with no network I/O at import time.
3. Where storage access sits: behind a DAL or repository boundary that handlers and transport code do not bypass.
4. The dependency direction: source dependencies point inward. Inbound adapters (handlers, consumers) call the service or domain layer, outbound adapters implement interfaces that layer owns, and that layer must not import the database driver, the HTTP framework, or a vendor SDK.
5. Where untrusted input is validated at run time, at the boundary that owns it.

The designer settles what the design can settle, and the document must not hand that work to a reader:

1. The design-time security questions are answered in the document from the requirement and the code. Do not put them to the requester.
2. An open point gets a stated default and the reason for it. List separately only a point the requester alone can answer, with what changes if the answer differs; do not end by waiting for a default to be confirmed.
3. A handoff names the next stage (implementation, testing, release), never a person or a role. Do not invent an approver, a reviewer, or a sign-off for the design that the request did not name. An approval this skill or the repository requires before a runtime action, such as a destructive migration on shared data, is part of the design and stays.

## When patterns conflict

- Prefer current contracts and requirements over historical code habits.
- Prefer relational durable truth over Redis-only truth for auditable state.
- Prefer explicit schema/config contracts over reflection, hidden globals, untyped dictionaries, or stringly conventions.
- Prefer idempotency and durable acceptance over retry-only designs.
- Prefer fail-closed for auth, permission, critical state transitions, and data-integrity paths; fail-open only for non-critical cache/telemetry paths when availability requires it.
- Fuse patterns only when both are generic and complementary; otherwise keep the simpler product-agnostic rule.
- Keep only reusable mechanics. Do not copy product nouns, service names, package paths, provider names, environment names, IDs, dashboards, or organization-specific habits into the architecture.

## Stack defaults

Each part holds only what changes with the stack. The full per-stack wording, including the platform contract tables, is in `references/service-design-rules.md`.

### Go

- Protobuf IDL is the default contract format, for RPC and optionally HTTP; centralized IDL ownership plus versioned generated artifacts that business services import. Repository layout does not change contract ownership.
- GORM is the default MySQL DAL for new services unless the repo already standardizes another query layer or the architecture records a deliberate alternative. GORM, sqlx, and raw SQL stay behind DAL or repository boundaries.
- Seams are made visible with dependency injection or provider sets (Wire); handlers never construct DB/MQ/RPC clients. Keep IDL, generated contracts, HTTP route generation, DB model generation, and DI generation explicit.
- All internal RPC clients go through a discovery/resolver abstraction; runtime wrappers give HTTP, RPC, and workers the same identity, registration, context propagation, metrics, timeout/circuit behavior, and safe debug exposure. `context.Context` carries correlation id, trace context, lane, and deadline through every hop.
- Dependency platform layers own SDK lifecycle, credentials, readiness, shared timeouts, close hooks, and test substitution; feature adapters own feature schemas, indexes, queries, object names, event payload meaning, and repair semantics.
- RPC services own domain operations and internal contracts; background workers own event processing, retries, idempotency, and backfill/repair.
- Health checks can prove the contract boundary: IDL source location, generation command, generated package version, service code importing generated contracts, and CI breaking-change checks.
- Implementation owner: `go-microservice-dev`.

### Python

- Pydantic/OpenAPI is the default HTTP contract surface; framework-native schemas when the repository standard already exists. Protobuf/gRPC for RPC only when the integration requires it; protobuf as an HTTP contract source only for a documented cross-language consumer set, with owner, consumers, generated artifacts, compatibility policy, migration path, framework binding, and wire format recorded first.
- Choose FastAPI, Flask, Django, or another framework by request model, admin needs, async needs, ecosystem constraints, and team familiarity. Classify code before reusing a pattern: only deployable, current service code defines service defaults.
- SQLAlchemy 2.x plus Alembic is the default for new relational services unless a deliberate alternative is recorded; Django ORM and migrations in Django services; SQLModel when chosen or already in use. New MySQL async services prefer `asyncmy`, sync services `mysqlclient`; never mix async drivers inside one service or replace a working driver only to match the default.
- Use async only when the call chain and libraries are truly non-blocking; isolate blocking CPU/GPU or sync I/O through workers, process pools, or `asyncio.to_thread`.
- Assemble clients and middleware in explicit app factories or startup code; no network I/O at import time, no import-time singletons or hidden global clients. Typed settings (Pydantic Settings or equivalent) fail closed when required production config is missing.
- In Django, keep framework conventions where they improve clarity, but do not hide domain rules in views, serializers, or settings side effects.
- AI/RAG service hosts separate service wiring from inference design, which belongs to `llm-inference-integration`.
- Implementation owner: `python-service-dev`.

### Node.js / TypeScript

- Recover the runtime contract first and preserve it unless migration is explicit: supported and deployed Node.js line, package manager and authoritative lockfile, ESM or CommonJS, and the JS/TS execution and type-check path. A move to another runtime (Bun, Deno) is a `product-rd-workflow` decision, not a drop-in swap.
- TypeScript types are erased at run time. Validate untrusted data with a runtime schema at the owning boundary, and keep a real type-check gate separate from execution.
- One event loop serves every request: keep callbacks short, bound fan-out, queues, retries, payloads, and buffering, and use streams with backpressure for large or unbounded data. Measured CPU-intensive work goes to a bounded `worker_threads` pool or a separate worker boundary, never the request path.
- Cancellation and deadlines propagate to the underlying work; a wrapper timeout that leaves work running is not cancellation. Request context (correlation, tenant, deadline) rides `AsyncLocalStorage` established at the owning boundary; a security-bearing value with no context fails closed.
- Treat the outbound HTTP client as a bounded resource: pool size, layered timeouts, and response-body consumption are part of the dependency contract.
- Prefer explicit dependencies and startup wiring over mutable process-wide singletons. Do not add blanket retries, speculative caches, generic base layers, or process-level exception recovery without observed need and an owning contract.
- The Go and Python defaults above do not transfer: their RPC, storage, and code-generation contracts are stack-specific. Use the method and this part only.
- Implementation owner: `nodejs-service-dev`, which carries the mechanics (`nodejs-service-dev/references/runtime-and-project-contract.md`, `nodejs-service-dev/references/async-lifecycle-and-performance.md`).

## Reference index

Files without a prefix are either shared or belong to the stack named in the row. Everything is one level under `references/`.

| Topic | Shared | Go | Python |
|---|---|---|---|
| Full rule wording, platform contract | `service-design-rules.md` | | |
| Boundaries, layering, dependency direction | | `go-architecture-playbook.md` | `python-architecture-playbook.md` |
| Frameworks, scaffolding, DI | | `service-scaffold.md`, `developer-tooling-architecture.md` | `web-framework-boundaries.md`, `packaging-runtime-readiness.md` |
| Contracts and schema evolution | | `protobuf-contract-architecture.md`, `http-gateway-architecture.md` | `api-contract-and-schema.md` |
| Public API, callbacks, authorization scope | | `go-api-security-boundaries.md` | `python-api-security-boundaries.md` |
| Errors, timeouts, retries | | `error-contract-architecture.md` | `reliability-and-error-contract.md` |
| Data modeling and migrations | | `go-data-modeling-and-migrations.md` | `python-data-modeling-and-migrations.md` |
| Data platform: engines, HA, replicas, sharding, backup | `data-platform-architecture.md` | | |
| Multi-tenant isolation | `multi-tenant-isolation.md` | | |
| Event-driven boundaries, outbox, sagas, replay | `event-driven-architecture.md` | `mq-consumer-architecture.md` | |
| Redis cache, locks, limits, idempotency | | `go-redis-cache-coordination.md` | `python-redis-cache-coordination.md` |
| Workflow and task state | | `go-workflow-state-architecture.md` | `python-workflow-state-architecture.md` |
| Concurrency, jobs, batch, bulk | | `bulk-workflow-architecture.md` | `async-execution-model.md`, `background-jobs-and-scheduling.md`, `batch-and-pipeline-architecture.md` |
| Config, secrets, dependency clients | | `dependency-platform.md`, `config-rule-routing-architecture.md` | `config-secrets-runtime.md` |
| Observability and operations | | `runtime-observability.md`, `ops-checklist.md`, `cross-cutting-concerns.md` | `observability-and-ops.md` |
| Release, capacity, launch readiness | | `release-runtime-readiness.md`, `performance-capacity-architecture.md` | `packaging-runtime-readiness.md` |
| Audit and history | | `go-audit-history-architecture.md` | `python-audit-history-architecture.md` |
| Notifications and webhooks | | `go-notification-architecture.md` | `python-notification-architecture.md` |
| Replay, shadow, comparison | | `go-replay-comparison-architecture.md` | `python-replay-comparison-architecture.md` |
| Generated files and artifacts | | `artifact-generation-architecture.md` | |
| LLM/RAG service boundaries | | | `ai-service-integration-boundaries.md` |
| Provenance and re-extraction | `method-grounding.md` | `go-source-evidence-map.md` | `python-source-evidence-map.md` |
