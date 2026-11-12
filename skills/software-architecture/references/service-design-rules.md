# Service Design Rules (full wording)

The entry `SKILL.md` carries the walk-list: one condensed line per obligation, at the step where it fires. This file carries the full wording of the Go and Python rules, grouped by the same steps: a `Shared` part that both former entries stated, and one part per stack. Node.js/TypeScript has no part here; for a Node.js/TypeScript service the entry's method and its Node.js/TypeScript part are the rule, and nothing under `Shared` transfers to it on its own — in particular not the RPC/gRPC transport default. Read the section for the step you are deciding before giving a conclusion that depends on it; when a condensed line and this file differ, this file is the rule and the entry line is fixed in the same change.

A rule that changes here names its downstream owner before landing: the stack's dev skill for code mechanics, `testing-strategy` for the proof layer, the `platform-*` skills for runtime contracts, and `product-rd-workflow` for cross-stage gates.

## Platform boundary contract

### Go

This skill owns the **service-internal** view: layer separation (transport/application/domain/infra), protobuf IDL design, DAL boundaries, MQ consumer shape, error-code contract, DI/Wire generation. It exposes a fixed contract to the platform layer:

| Service exposes (this skill owns) | Platform owns (route to platform-* skill) |
|---|---|
| `/healthz`, `/readyz`, `/ping` endpoints (via framework default) | Orchestrator probes; registry healthcheck contract |
| Use of framework default server suite + client suite (e.g. Kitex/Hertz `Default*Options`, or equivalent) | What that middleware chain must include — see `platform-observability` and `platform-service-connectivity` |
| Conformance to the platform's request-metadata envelope (request id / correlation id / lane / caller identity), populated by client middleware | Cross-language contract on the envelope shape |
| `context.Context` carrying correlation id, trace context, lane/env, deadline through every hop; helper to clone-without-cancel for spawned goroutines | How those fields propagate across mesh / queue / async boundaries |
| Structured logger interface that emits JSON with the platform field schema (trace context extracted from ctx automatically) | Log shipping pipeline, search index |
| Stable error-code enum + framework error mapping (timeouts, panics, permission errors → typed codes) | Cross-service error contract evolution |
| Graceful shutdown: deregister from SD → drain → close clients → exit | Orchestrator pre-stop hook and termination grace |
| Secret consumption via platform secret-store SDK; never read from committed files | Secret rotation pipeline, secret-store deployment |
| Static config in per-environment files bundled in the image; dynamic config via config-center SDK | Config-center deployment, audit, rollout |
| Service registration metadata: platform service identifier, lane tag, region/cluster tags, version, weight | Registry deployment, federation, healthcheck propagation |
| Metric emission via framework metrics client with baseline labels auto-attached | Metric storage, cardinality budget, SLI definition |

A Go service author works against this contract. Platform-level questions ("which mesh policy?", "which collector?", "which canary weight?") route to the platform skills. Cross-language uniformity is what makes the platform layer reusable.

- Use `platform-observability` for logs/metrics/traces/log-id propagation/dashboards/alerts/SLI-SLO design. This skill owns only the service-side observability surface (Kitex/Hertz middleware that emits structured logs, OTel SDK use, baseline labels attached by metrics client, health endpoints); the cross-cutting evidence stack belongs there.
- Use `platform-service-connectivity` for service mesh, service discovery (Nacos/Consul/equivalent), mTLS, multi-environment lane routing, retry/timeout/circuit-breaker policy, and the canonical RPC base struct shape. This skill defines what the service exposes (framework default options usage, request-metadata propagation conformance via the platform's chosen carrier — in-message `base` or transport metadata, scenario-driven per the connectivity Carrier decision — graceful shutdown); mesh policy and routing rules live there.
- Use `platform-release-engineering` for environment/lane matrix, canary/blue-green, promotion gates, rollback playbook, secret distribution, dynamic-config (config-center) vs static-config split, image build pipeline. This skill owns the service-side contracts (config schema, secret consumption interface, registration metadata); release flow lives there.

### Python

This skill owns the **service-internal** view: handler shape, contracts, data ownership, async model, error map, worker design, package layout. It exposes a fixed contract to the platform layer:

| Service exposes (this skill owns) | Platform owns (route to platform-* skill) |
|---|---|
| `/healthz`, `/readyz`, `/ping` endpoints with correct semantics | How orchestrator probes them; registry healthcheck contract |
| Python equivalent of correlation propagation (`contextvars`, FastAPI `Request.state`, Starlette state, framework request scope) carrying request id / correlation id / trace context / lane / deadline | How those fields propagate across mesh / queue boundaries |
| Logger interface that takes ctx and emits structured JSON matching the platform field schema | Log shipping pipeline, search index |
| Use of the framework default app factory with the mandatory middleware chain attached | What that middleware chain must include — see `platform-observability` and `platform-service-connectivity` |
| Stable error-code enum + mapping table (framework error → code → HTTP/RPC status) | Cross-service error contract evolution |
| Graceful shutdown: deregister from SD → drain in-flight → close clients → exit | Orchestrator pre-stop hook and termination grace period |
| Secret consumption via the platform secret-store SDK or injected env at boot | Secret rotation pipeline, distribution mechanism |
| Static config in per-environment files bundled in the image; dynamic config via config-center SDK | Config-center deployment, audit, rollout |
| Trace span creation around handler + outbound calls (auto via OTel instrumentation) | Trace backend, sampling policy, retention |
| Metric emission via framework metrics client (baseline labels attached automatically) | Metric storage, cardinality budget, SLI definition |

A Python service author works against this contract. Platform-level questions ("which collector?", "which mesh weight?", "which canary check?") route to the platform skills. Cross-language uniformity of this contract is what makes the platform layer reusable.

- Use `platform-observability` for logs/metrics/traces/log-id propagation/dashboards/alerts/SLI-SLO design. This skill owns only the service-side observability surface (what fields the handler emits, what middleware the framework attaches, what health endpoints exist); the cross-cutting evidence stack belongs there.
- Use `platform-service-connectivity` for service mesh, service discovery, mTLS, multi-environment lane routing, retry/timeout/circuit-breaker policy, and framework client/server middleware for cross-service hops. This skill defines what the service exposes (health endpoints, ctx propagation, error-code conformance); routing/policy lives there.
- Use `platform-release-engineering` for environment/lane matrix, canary/blue-green, promotion gates, rollback playbook, secret distribution, dynamic-config (config-center) vs static-config split, image build pipeline. This skill owns the service-side contracts (what the service consumes from the secret store and config center); release flow lives there.

## Generalization discipline

### Shared

- Do not copy product nouns, service names, package paths, provider names, environment names, IDs, dashboards, callback types, or organization-specific operating habits into the architecture.

### Go

- Keep only reusable server-side mechanics: contracts, layers, storage ownership, config, reliability, observability, security boundaries, code generation, and delivery workflow.
- When source code shows a domain-specific concept, generalize it to `domain object`, `resource`, `authorization scope`, `integration scope`, or `workflow` only if the mechanic is reusable; otherwise discard it.
- When patterns conflict, choose deliberately:
  - Prefer current contracts and requirements over historical code habits.
  - Prefer relational durable truth over Redis-only truth for auditable state.
  - Prefer explicit protobuf/config/schema contracts over reflection, hidden globals, or stringly conventions.
  - Prefer idempotency and durable acceptance over retry-only designs.
  - Prefer fail-closed for auth, permission, critical state transitions, and data-integrity paths; fail-open only for non-critical cache/telemetry paths when availability requires it.
  - Fuse patterns only when both are generic and complementary; otherwise keep the simpler product-agnostic rule.
- Example: if one codebase stores workflow state only in Redis and another persists it in a relational table, keep the relational source-of-truth rule and optionally use Redis as cache, lock, rate limit, or scheduling aid.

### Python

- Keep only reusable Python-side mechanics: framework boundaries, typed contracts, dependency assembly, storage ownership, migrations, async/concurrency model, workers, config, reliability, observability, security boundaries, packaging, and delivery workflow.
- Convert domain-specific source patterns into reusable mechanics: router shape, schema evolution, repository/unit-of-work boundary, transaction ownership, cache key strategy, idempotency, job lease, config validation, trace context, or test contract.
- When patterns conflict, choose deliberately:
  - Prefer explicit Pydantic/OpenAPI schemas over untyped dictionaries for public API contracts.
  - Prefer SQLAlchemy 2.x plus Alembic for new Python relational services unless the service records a deliberate alternative data-access choice; use framework ORM ownership when the chosen framework owns that boundary.
  - Prefer relational durable truth over Redis-only truth for auditable state.
  - Prefer explicit dependency assembly over import-time singletons and hidden global clients.
  - Prefer async only when the call chain and libraries are truly non-blocking; isolate blocking CPU/GPU or sync I/O through workers, process pools, or `asyncio.to_thread`.
  - Prefer fail-closed for auth, permission, critical state transitions, and data-integrity paths; fail-open only for non-critical cache/telemetry paths when availability requires it.
  - Fuse patterns only when both are generic and complementary; otherwise keep the simpler product-agnostic rule.

## Planning depth

### Shared

Before changing architecture guidance, contracts, service boundaries, diagrams, plans, or implementation-driving recommendations, complete enough analysis and planning for the decision to be reviewable. Scale the plan to risk: a simple low-risk explanation can use a short inline plan; multi-service, contract-visible, data-ownership, release, high-risk, branch/MR, or unclear-risk architecture work needs explicit assumptions, alternatives, tradeoffs, acceptance checks, verification evidence, rollback or migration path, and named handoffs to implementation, testing, platform, or product workflow skills before edits or approval.

## Step 1 — Boundary

### Shared

- Internal microservice calls use RPC/gRPC by default and may use HTTP when the service contract chooses it. Internal HTTP must meet the same service discovery, auth, timeout, retry, observability, and contract-test standards as RPC.

### Go

- Identify user workflows, domain objects, external integrations, and lifecycle events.
- Decide which capabilities must be synchronous APIs, internal RPCs, async jobs, or scheduled tasks.
- Avoid splitting into microservices until ownership, scaling, data boundary, or deployment cadence justifies it.

### Python

- Identify whether the product needs an HTTP API, internal API, microservice, worker, scheduled job, batch pipeline, SDK/package, or AI-service host.
- Classify Python code before reusing a pattern: deployable service, SDK/shared package, application service, experiment/benchmark, generated artifact, model/runtime artifact, or third-party/vendor code. Only deployable/current service code should define service defaults.
- Use a microservice boundary only when ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify a separate deployable unit; then identify each service's owner, data source of truth, API/OpenAPI or gRPC contract, runtime dependencies, deployment unit, and rollback boundary.
- Use a modular monolith, script, worker-only service, or package when service boundaries are unclear, the product is too small to justify separate deployable services, the active repository is already that shape and the task is local to it, or the user explicitly requests that shape.
- Choose FastAPI, Flask, Django, or another framework by request model, admin needs, async needs, ecosystem constraints, and team familiarity.

## Step 2 — Contracts

### Shared

- API contracts must define request messages/schemas, the response envelope, and shared public fields in the shared contract source before implementation, per the canonical `code`/`message`/`data` envelope contract in `platform-service-connectivity/references/http-response-envelope-contract.md` (adoption, migration, non-JSON surfaces, and anti-patterns live there — do not restate them here).
- Internal RPC contracts carry the platform's shared request/response metadata field when the platform defines one; `platform-service-connectivity` owns the canonical base-struct shape and named-framework examples. Do not inherit a framework's reserved envelope/base field number as a cross-product convention (per `protobuf-contract-architecture.md`); if a shared metadata field must be part of the protobuf contract (rather than carried via middleware metadata), a new product picks an explicit field and documents it. Within a platform that has already standardized such a field, its field number, name, and message type are compatibility surfaces — do not renumber, rename, or replace them locally.
- Internal service data models need the same contract discipline: shared cross-service DTOs, enums, status values, metadata fields, and request/response models live in the contract or generated artifact boundary; service-private domain and persistence models stay inside the owning service and convert at transport (route)/application boundaries.
- **Inventory the service's exposed surfaces and review new ones at the boundary.** Keep a machine-checkable inventory of every externally reachable surface appropriate to the stack — HTTP routes (in Python: FastAPI / Flask / Django), RPC services and methods, and async subscriptions (MQ / Celery / queue / event / webhook consumers); a surface absent from it should not reach production unreviewed. Drive it from a deterministic discovery profile (routes/subscriptions-as-code, or a generated OpenAPI/manifest plus a checked-in snapshot, are two common patterns) with explicit allowlisted carve-outs for framework / health / debug, generated, plugin, and env-conditional surfaces, so the gate flags genuinely new exposure instead of churning on false positives; also flag inventory entries no longer present in code so the snapshot stays trustworthy. Scale enforcement to risk: hard-fail CI for production, externally reachable services; a lighter manifest + review checklist suffices for prototypes, internal scripts, or repos without CI. The inventory proves *every surface was seen and reviewed*, **not** that it is authorized — it is not an authn/authz gate; auth, tenant isolation, and safe exposure remain separate evidence the boundary review must still demand. An unregistered new route or consumer is a *shadow surface* (unreviewed; async consumers are a commonly missed class). Distinct from breaking-change detection (`buf breaking` / `kitex check` in Go, schema / contract diff in Python — both guard *changes to existing* surfaces) and from agent-contract directory coverage (whether a directory carries an `AGENTS.md`); it guards *new runtime exposure*. `product-rd-workflow`'s spec/repo-contract sync gate owns the human discipline; this is its mechanical enforcement.
- For finite values that cross service, storage, client, analytics, or generated-code boundaries, architecture must name the canonical owner, shared package or contract location, conversion boundaries, unknown/default behavior, and migration/debt exit path before implementation. If no shared location exists, approve the local-slice fallback and require every `finite-value-debt` marker to carry task reference, owner, deadline, and reason.

### Go

- Use protobuf IDL as the default contract format.
- Service identity is decided before IDL and implementation. For new services, define the globally unique service name first, then IDL, then generated contract artifacts, then business implementation.
- Treat IDL and idlgen outputs as a stable boundary between service contracts and business repositories. Prefer centralized IDL ownership plus versioned generated artifacts that business services import. When the platform uses shared IDL and IDLGen repositories, Go, Python, web, mobile, and mini-program consumers must derive from the same contract source; do not fork IDL or generated artifacts per service repository or per language unless it is a deliberate compatibility branch with owner, version, and deprecation plan. Service repository layout (single service, multi-service, API/RPC split) does not change contract ownership.
- Protobuf may be the contract source for HTTP as well as RPC. For protobuf-backed or cross-language HTTP gateways, decide separately: contract source (protobuf/OpenAPI), generated route/client artifacts, and wire format (JSON vs binary protobuf). Classify protobuf-backed HTTP using the canonical wire-format gate in `platform-service-connectivity/references/protobuf-http-contract-signals.md`; do not restate or widen that predicate locally.
- Separate public HTTP API models from internal RPC models when external clients have different stability needs.
- Prefer additive contract evolution: new fields, new methods, new enum values; avoid breaking field numbers or response semantics.

### Python

- Use Pydantic/OpenAPI as the default HTTP contract surface.
- Use Django forms/serializers or framework-native schemas when the repository standard already exists.
- Use protobuf/gRPC for RPC only when the integration explicitly requires it; protobuf as an HTTP contract source is governed separately by this ordered decision:
  1. Default to Pydantic/OpenAPI as the Python HTTP contract source.
  2. Use protobuf as the HTTP contract source only when that default is not sufficient for a documented cross-language consumer set.
  3. Before approving protobuf HTTP, record owner, consumers, generated artifacts, compatibility policy, and migration or deprecation path.
  4. Record framework binding (FastAPI/Flask/Django) and wire format (JSON vs binary protobuf).
  5. Define the globally unique service name before IDL and implementation, keep IDL ownership separate from business implementation, and consume versioned generated artifacts.
  6. When the platform uses shared IDL and IDLGen repositories, consume the generated Python artifacts from the same contract source as Go and client-side consumers; do not copy IDL into a service repo, handwrite protobuf types, or treat generated clients as service-local source.
  7. Satisfying a protobuf/cross-language trigger does not substitute for the owner, consumer, artifact, compatibility, migration, framework-binding, and wire-format records above; all are required before approval.
- Classify protobuf-backed HTTP using `platform-service-connectivity/references/protobuf-http-contract-signals.md`; that reference owns the in-scope gate and the routine JSON/OpenAPI carve-out. In Python architecture, once the gate is in scope, record contract source, framework binding, owner, consumers, generated artifact package/version, compatibility policy, migration/deprecation path, and JSON vs binary protobuf wire format. Missing in-scope records block approval; out-of-scope routine Pydantic/OpenAPI changes use the normal contract-definition record.
- Prefer additive contract evolution: new fields, new endpoints, new enum values, and stable response semantics.

## Step 3 — Data ownership

### Shared

- Use Redis for cache, locks, counters, idempotency windows, rate limits, and ephemeral coordination, not durable truth.

### Go

- Each service owns its write model and schema.
- Cross-service reads should go through RPC/API or explicit read models, not shared table writes.
- Use relational DB as source of truth for transactional domain state.
- Use GORM as the default MySQL DAL choice for new Go services unless the repo already standardizes or conventionally uses another query layer, or the architecture records a deliberate alternative.
- Decide schema, indexes, unique constraints, migration path, and sharding keys before writing DAL code.
- Keep GORM, sqlx, and raw SQL behind DAL or repository boundaries; transport and application layers must not build database queries directly.
- Define Redis key scope, TTL policy, lock lease, rate-limit window, and idempotency lifetime as part of the architecture.

### Python

- A service owns its write model and migration path.
- Use SQLAlchemy 2.x plus Alembic by default for new relational services unless the service records a deliberate alternative data-access choice.
- For new MySQL async services, prefer `asyncmy`; `aiomysql` is allowed when the service deliberately chooses it or already uses it. Do not replace an existing working `aiomysql` driver solely to comply with the default. Do not mix MySQL async drivers inside one service boundary.
- For MySQL sync services, prefer `mysqlclient`; `PyMySQL` is allowed when portability or existing service convention requires it.
- Use Django ORM and Django migrations when the service is a Django service. Use SQLModel when the architecture deliberately chooses the Pydantic plus SQLAlchemy model shape or the service already uses SQLModel; do not replace existing SQLModel solely to comply with the default.
- Another deliberately chosen or existing ORM/query layer is allowed when kept consistent inside the service boundary and recorded as the service data-access choice.
- Treat Alembic or framework migrations as reviewable source artifacts; autogeneration is a draft, not a substitute for migration design.

## Step 4 — Runtime and dependency contracts

### Shared

- High-risk feature flags and runtime config default fail-closed in production. Local stubs, test defaults, and developer-safe switches must be visibly scoped and cannot become implicit production enablement.
- A capability requirement is not a framework-adoption decision. When a requirement names a capability (service discovery, mTLS, graceful drain), first define its minimal closure — the smallest layer that satisfies it — before adopting a platform framework or runtime component for it, AND name which layer actually closes it: service discovery and mTLS can close at the deployment layer (orchestrator DNS, mesh sidecar), but graceful drain inherently needs runtime behavior (stop accepting, SIGTERM/readiness handling, in-flight completion) — manifests alone leave it explicitly `not closed`, never silently satisfied. Framework adoption is not all-or-nothing: when a framework default conflicts with a service characteristic (e.g. a fixed 30s drain window versus minute-scale streaming requests), split at the boundary — land the part that delivers value on its own (deployment manifests), decide or defer the conflicting part (runtime lifecycle adoption) separately with each deferred capability's closure status recorded, and keep a quotable record of why it was not adopted.
- Dependency clients: DB, Redis, MQ, object storage, service discovery, secret provider, external HTTP, and inference clients must have explicit timeout, credential, observability, and test-substitution contracts.
- When comparing a new product backend against a mature internal reference, convert the comparison into a platform-capability gap list, not a source-code shopping list.
  - The recurring maturity checks are: identity/RBAC subject model, external API signature/replay/allowlist boundary, dynamic config with version/cache/watch/rollback, MQ/queue producer/consumer lifecycle with retry/drop/replay visibility, DB transaction and query-safety guardrails, context/error propagation across HTTP/RPC/MQ (queue), and resource/search visibility scope.
  - A placeholder or README-only package family is not implementation evidence.
- Before marking an internal reference package family as placeholder-only, inspect nested git repositories or submodules, non-default local/remote branches, tags, and tree contents with read-only commands. Default-branch scaffolds do not prove the architecture capability is absent.
- If the comparison uses internal checkouts, private repositories, local paths, or organization projects, route preservation through `skill-extraction-workflow` or apply the same sanitization gate before landing any artifact: keep only mechanisms, boundaries, and acceptance gates; remove source-identifying domains, paths, repository/module names, people, tickets, and business nouns.

### Go

- Config: local file + dynamic config, with environment/lane separation.
- Secrets: never stored in code or config files; resolve through a secret provider.
- Service discovery: all internal RPC clients use discovery/resolver abstraction.
- Service identity: internal RPC/HTTP trust should be based on workload identity, mTLS, signed service tokens, or an equivalent zero-trust control, not only network location.
- Runtime wrappers should provide service identity, registration/discovery, context propagation, trace/log id, metrics, timeout/circuit behavior, and safe debug exposure consistently across HTTP, RPC, and workers.
- Dependency platform layers own SDK lifecycle, credential resolution, readiness, shared timeout policy, close hooks, and test substitution. Feature infrastructure adapters own feature-specific schemas, indexes, query/ranking contracts, object names, event payload meaning, and repair semantics. Do not place feature contracts in the platform layer just because they use a platform client.
- Admission control: inbound rate limits, concurrency limits, load shedding, backpressure, and circuit-breaker behavior are part of reliability design.
- Release runtime: service metadata, deployment resources, mesh/gateway routing, canary traffic, approval, and rollback are first-class architecture surfaces.
- Error contract: define canonical code/message semantics once, then map HTTP, RPC, worker, and dependency errors into it.
- Context contract: trace/log id, lane/environment, authorization/resource scope, request deadline, and auth subject must propagate through all sync and async paths.
- Observability: logs, metrics, traces, health checks, pprof/debug where safe, and structured request context.

### Python

- Config should be typed and environment-specific, preferably through Pydantic Settings or framework-equivalent config schemas.
- Secrets must not live in code, config examples, tests, or generated clients.
- Separate serving-path timeout budgets from admin, migration, bootstrap, repair, and batch-operation timeouts.
- Service registration or model-serving registration should happen only after readiness checks pass; registered metadata should identify environment, version, routing/lane, and capability. Shutdown, polling, and background registration loops need bounded timeout and explicit exit semantics.
- Readiness must be externally observable for operations. Internal SDK or serving-framework status is useful, but production services still need a clear health/readiness surface, startup failure behavior, and unregister/shutdown semantics.
- Define error mapping once, then map framework, validation, ORM, worker, HTTP client, and dependency errors into it.

## Step 5 — Code generation, quality, and release readiness

### Go

- Generated code is an output surface, not hand-maintained source.
- Keep IDL, generated contracts, HTTP route generation, DB model generation, and Wire/DI generation explicit.
- Introducing or migrating any HTTP gateway/framework requires a quotable record in the architecture doc, repo contract, or MR description, with a separately locatable entry for gateway-capability justification, contract source, middleware order, generated artifacts, observability, and tests. Protobuf motivation alone is insufficient evidence unless the same record states a concrete missing capability in the existing framework, why the current extension points cannot satisfy it, and which requirement the new framework satisfies. Adding protobuf-backed HTTP on an unchanged gateway/framework requires the contract-source and wire-format records; expand to generated-artifact, observability, and test records when those surfaces change.
- Health checks should be able to prove the boundary: IDL source location, generation command, generated package version, service implementation importing generated contracts, and CI/breaking-change checks. Agent review then judges whether the service layer bypasses the contract or hides domain semantics in transport code.
- Document the generation commands in the repo.
- Generation commands must be portable and must not contain developer-local absolute paths.

### Python

- Logs, metrics, traces, health/readiness endpoints, request IDs, and safe debug exposure are architecture surfaces.
- Package and runtime choices must be reproducible: lockfile, dependency groups, import mode, lint/type/test commands, and container entrypoint.
- Define deployment resources, process model, worker concurrency, canary/smoke checks, rollback, and migration order before launch.

## Architecture defaults

### Shared

- Cross-boundary semantic values are an architecture responsibility even when their local representation is small. Architecture decides where finite values such as status, market, region, channel, source, provider, or permission are canonical, who may expose generated transport enums to domain code, and how duplicate constants are retired.
- Mature reference code is useful only when it exposes a reusable boundary. Prefer extracting framework wrappers, typed clients, context/error contracts, config schemas, unit-of-work or transaction helpers, MQ/queue lifecycle helpers, and query-safety checks; discard business nouns, private module layout, and one-off legacy habits.
- High-risk operations require a resilience contract: fail-closed policy, idempotency strategy, durable status, reconciliation or repair path, trace/request id propagation, user/support explanation surface, and proof that fallback/degradation cannot bypass authorization, tenant/user isolation, quota, audit, or data-retention controls.
- High-risk context resolution must reject missing tenant, actor, subject, or resource scope instead of falling back to default identities. Durable side effects need atomic audit/outbox evidence or an explicit reconciliation/repair workflow.

### Go

- One product can start as a modular monolith if service boundaries are unclear; split by data ownership and team/runtime needs, not by noun count.
- Public API layer should be thin: auth, validation, request/response mapping, orchestration handoff.
- RPC services should own domain operations and internal contracts.
- Background workers should own event processing, retries, idempotency, and backfill/repair workflows.
- A mature Go service usually separates transport/handler, application logic, domain/service orchestration, and infrastructure adapters; dependency injection or provider sets should make those seams visible instead of letting handlers construct DB/MQ/RPC clients directly.
- Shared libraries are allowed for infrastructure concerns; do not put domain rules in shared packages.
- A service should have clear layers: transport, application/service logic, domain logic, infrastructure adapters, generated contracts.
- Long-running jobs require a first-class runtime model: distributed lock scope, lease time, max execution time, retry policy, idempotency key, and failure visibility.
- External dependencies require explicit timeout budgets, status-code validation, retry/fallback rules, and clear ownership of degraded behavior.
- External dependency bootstrap requires a first-class operability contract: which resources may be created automatically, which existing resources must be validated, which partial failures can be repaired, which operations fail startup, and which timeouts apply to administrative work versus serving requests.

### Python

- Do not split Python backends into microservices until ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify separate deployable units. When microservices are justified, each service has an owner, API/OpenAPI or gRPC contract, data ownership, inter-service auth, timeout/retry policy, service discovery or routing, observability, deployment unit, and rollback boundary.
- A modular monolith, script, worker-only service, or package is valid when boundaries are unclear, the product is small, the existing repository shape fits, or the user requests simplification. Record the reason when choosing it.
- Keep FastAPI/Flask route handlers thin: auth, validation, request/response mapping, and orchestration handoff.
- In Django, keep framework conventions where they improve clarity, but do not hide domain rules in views, serializers, or settings side effects.
- Use explicit app factories or startup assembly for clients and middleware; avoid doing network I/O at import time.
- Avoid hard-coded registry endpoints, provider URLs, secrets, and fallback domains in code. Route them through typed config and fail closed when required production config is missing.
- Use SQLAlchemy 2.x-style sessions, unit-of-work boundaries, or framework transactions as the data consistency boundary.
- Long-running jobs require idempotency, checkpoint/restart behavior, failure visibility, and a max execution/concurrency model.
- Python AI/RAG service hosts must separate service wiring from inference design. Model routing, prompt policy, retrieval design, evaluation, and replay belong to `llm-inference-integration`.
- Generated API clients and generated protobuf code are output surfaces; do not hand-edit them. Generated migrations are drafts: review them before landing, and get human sign-off only before a destructive one runs on shared data.
