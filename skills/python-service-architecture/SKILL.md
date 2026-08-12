---
name: python-service-architecture
description: Python 后端架构 / FastAPI 项目结构 / Celery worker 拆分 / Python 微服务边界 / 服务分层重构 / Python 服务重构 → design or review Python backend, service, worker, package, API contract, data ownership, reliability, async/job, and runtime boundaries. Prefer this for architecture/boundary decisions; use python-service-dev for implementation work and localized refactor (某文件/某类); multi-stage / cross-module refactor delivery re-enters product-rd-workflow.
---

# Python Service Architecture

Use this for new product/server architecture work in Python. For new backend products, decide the service boundary from ownership, data source of truth, runtime isolation, scaling, release cadence, and rollback needs before choosing microservice, modular monolith, worker, script, or package shape. This skill distills proven Python backend, AI-service hosting, worker, package, and data-access patterns, but must not assume any existing repository, product domain, package path, service identifier, database, or legacy service layout.

## Skill Routing

- Use this skill for Python architecture decisions, microservice decomposition, service decomposition, API contract shape, storage ownership, async execution, worker/job design, observability, reliability, release readiness, and platform boundaries.
- Use `python-service-dev` when the user asks to implement, modify, scaffold, generate Python code, or apply a diagnosis/test strategy in Python code. A localized refactor (某文件/某类) also belongs to `python-service-dev`; only service-wide layering/boundary redesign stays here, and a multi-stage refactor delivery must re-enter `product-rd-workflow`. For root-cause debugging use `defect-diagnosis` first; for test-layer choice use `testing-strategy` first.
- Use `product-rd-workflow` first when the request spans product shaping, architecture, implementation, review, release, and learning loops.
- Use `defect-diagnosis` first when the task is to reproduce, isolate, instrument, fix, verify, or root-cause a backend defect, regression, repeated failure, review finding, or failing test.
- Use `testing-strategy` when the main question is which unit, integration, contract, or E2E layer should prove behavior; then return here for Python architecture impact.
- Use `llm-inference-integration` for inference, RAG, prompt, model-routing, evaluation, replay, token-cost, and batch-inference design. This skill only owns the Python service boundary that hosts or calls those capabilities.
- Use `go-microservice-architecture` for Go services. Do not load Go skill rules for Python work unless the task is explicitly cross-language contract design.
- Use `platform-observability` for logs/metrics/traces/log-id propagation/dashboards/alerts/SLI-SLO design. This skill owns only the service-side observability surface (what fields the handler emits, what middleware the framework attaches, what health endpoints exist); the cross-cutting evidence stack belongs there.
- Use `platform-service-connectivity` for service mesh, service discovery, mTLS, multi-environment lane routing, retry/timeout/circuit-breaker policy, and framework client/server middleware for cross-service hops. This skill defines what the service exposes (health endpoints, ctx propagation, error-code conformance); routing/policy lives there.
- Use `platform-release-engineering` for environment/lane matrix, canary/blue-green, promotion gates, rollback playbook, secret distribution, dynamic-config (config-center) vs static-config split, image build pipeline. This skill owns the service-side contracts (what the service consumes from the secret store and config center); release flow lives there.
- Use codebase-specific skills only when the task is explicitly about an existing repository.
- When changing an architecture rule that implementation must obey, name the downstream execution owner before landing: `python-service-dev` for code mechanics, `testing-strategy` for proof layer, platform skills for runtime contracts, and `product-rd-workflow` for cross-stage gates. If the rule also applies outside Python, route through `skill-extraction-workflow` and mirror or explicitly skip sibling architecture/dev skills.
- For money, billing, quota, permission, tenant/user data isolation, privacy, high-impact AI, repeated writes, async finality, or incident-explanation risk, start from `product-rd-workflow` and its high-risk resilience gate before choosing Python service boundaries or fallback behavior.

## Platform Boundary

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

## Generalization Discipline

- Keep only reusable Python-side mechanics: framework boundaries, typed contracts, dependency assembly, storage ownership, migrations, async/concurrency model, workers, config, reliability, observability, security boundaries, packaging, and delivery workflow.
- Do not copy product nouns, service names, package paths, provider names, environment names, IDs, dashboards, callbacks, or organization-specific operating habits into the architecture.
- Convert domain-specific source patterns into reusable mechanics: router shape, schema evolution, repository/unit-of-work boundary, transaction ownership, cache key strategy, idempotency, job lease, config validation, trace context, or test contract.
- When patterns conflict, choose deliberately:
  - Prefer explicit Pydantic/OpenAPI schemas over untyped dictionaries for public API contracts.
  - Prefer SQLAlchemy 2.x plus Alembic for new Python relational services unless the service records a deliberate alternative data-access choice; use framework ORM ownership when the chosen framework owns that boundary.
  - Prefer relational durable truth over Redis-only truth for auditable state.
  - Prefer explicit dependency assembly over import-time singletons and hidden global clients.
  - Prefer async only when the call chain and libraries are truly non-blocking; isolate blocking CPU/GPU or sync I/O through workers, process pools, or `asyncio.to_thread`.
  - Prefer fail-closed for auth, permission, critical state transitions, and data-integrity paths; fail-open only for non-critical cache/telemetry paths when availability requires it.
  - Fuse patterns only when both are generic and complementary; otherwise keep the simpler product-agnostic rule.

## Core Workflow

Before changing architecture guidance, contracts, service boundaries, diagrams, plans, or implementation-driving recommendations, complete enough analysis and planning for the decision to be reviewable. Scale the plan to risk: a simple low-risk explanation can use a short inline plan; multi-service, contract-visible, data-ownership, release, high-risk, branch/MR, or unclear-risk architecture work needs explicit assumptions, alternatives, tradeoffs, acceptance checks, verification evidence, rollback or migration path, and named handoffs to implementation, testing, platform, or product workflow skills before edits or approval.

1. Define the Python service boundary.
   - Identify whether the product needs an HTTP API, internal API, microservice, worker, scheduled job, batch pipeline, SDK/package, or AI-service host.
   - Classify Python code before reusing a pattern: deployable service, SDK/shared package, application service, experiment/benchmark, generated artifact, model/runtime artifact, or third-party/vendor code. Only deployable/current service code should define service defaults.
   - Internal microservice calls use RPC/gRPC by default and may use HTTP when the service contract chooses it. Internal HTTP must meet the same service discovery, auth, timeout, retry, observability, and contract-test standards as RPC.
   - Use a microservice boundary only when ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify a separate deployable unit; then identify each service's owner, data source of truth, API/OpenAPI or gRPC contract, runtime dependencies, deployment unit, and rollback boundary.
   - Use a modular monolith, script, worker-only service, or package when service boundaries are unclear, the product is too small to justify separate deployable services, the active repository is already that shape and the task is local to it, or the user explicitly requests that shape.
   - Choose FastAPI, Flask, Django, or another framework by request model, admin needs, async needs, ecosystem constraints, and team familiarity.

2. Define contracts before implementation.
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
   - Classify protobuf-backed HTTP using `../platform-service-connectivity/references/protobuf-http-contract-signals.md`; that reference owns the in-scope gate and the routine JSON/OpenAPI carve-out. In Python architecture, once the gate is in scope, record contract source, framework binding, owner, consumers, generated artifact package/version, compatibility policy, migration/deprecation path, and JSON vs binary protobuf wire format. Missing in-scope records block approval; out-of-scope routine Pydantic/OpenAPI changes use the normal contract-definition record.
   - API contracts must define request schemas, the response envelope, and shared public fields in the shared contract source before implementation, per the canonical `code`/`message`/`data` envelope contract in `../platform-service-connectivity/references/http-response-envelope-contract.md` (adoption, migration, non-JSON surfaces, and anti-patterns live there — do not restate them here).
   - Internal RPC contracts carry the platform's shared request/response metadata field when the platform defines one; `platform-service-connectivity` owns the canonical base-struct shape and named-framework examples. Do not inherit a framework's reserved envelope/base field number as a cross-product convention (per `../go-microservice-architecture/references/protobuf-contract-architecture.md`); if a shared metadata field must be part of the protobuf contract (rather than carried via middleware metadata), a new product picks an explicit field and documents it. Within a platform that has already standardized such a field, its field number, name, and message type are compatibility surfaces — do not renumber, rename, or replace them locally.
   - Internal service data models need the same contract discipline: shared cross-service DTOs, enums, status values, metadata fields, and request/response models live in the contract or generated artifact boundary; service-private domain and persistence models stay inside the owning service and convert at route/application boundaries.
   - Prefer additive contract evolution: new fields, new endpoints, new enum values, and stable response semantics.
   - **Inventory the service's exposed surfaces and review new ones at the boundary.** Keep a machine-checkable inventory of every externally reachable surface appropriate to the stack — HTTP routes (FastAPI / Flask / Django), any RPC services and methods, and async subscriptions (Celery / queue / event / webhook consumers); a surface absent from it should not reach production unreviewed. Drive it from a deterministic discovery profile (routes/subscriptions-as-code, or a generated OpenAPI/manifest plus a checked-in snapshot, are two common patterns) with explicit allowlisted carve-outs for framework / health / debug, generated, plugin, and env-conditional surfaces, so the gate flags genuinely new exposure instead of churning on false positives; also flag inventory entries no longer present in code so the snapshot stays trustworthy. Scale enforcement to risk: hard-fail CI for production, externally reachable services; a lighter manifest + review checklist suffices for prototypes, internal scripts, or repos without CI. The inventory proves *every surface was seen and reviewed*, **not** that it is authorized — it is not an authn/authz gate; auth, tenant isolation, and safe exposure remain separate evidence the boundary review must still demand. An unregistered new route or consumer is a *shadow surface* (unreviewed; async consumers are a commonly missed class). Distinct from breaking-change detection (schema / contract diff on *existing* surfaces) and from agent-contract directory coverage (whether a directory carries an `AGENTS.md`); it guards *new runtime exposure*. `product-rd-workflow`'s spec/repo-contract sync gate owns the human discipline; this is its mechanical enforcement. Mirror any change to this rule in `../go-microservice-architecture/SKILL.md`.
   - For finite values that cross service, storage, client, analytics, or generated-code boundaries, architecture must name the canonical owner, shared package or contract location, conversion boundaries, unknown/default behavior, and migration/debt exit path before implementation. If no shared location exists, approve the local-slice fallback and require every `finite-value-debt` marker to carry task reference, owner, deadline, and reason.

3. Design data ownership.
   - A service owns its write model and migration path.
   - Use SQLAlchemy 2.x plus Alembic by default for new relational services unless the service records a deliberate alternative data-access choice.
   - For new MySQL async services, prefer `asyncmy`; `aiomysql` is allowed when the service deliberately chooses it or already uses it. Do not replace an existing working `aiomysql` driver solely to comply with the default. Do not mix MySQL async drivers inside one service boundary.
   - For MySQL sync services, prefer `mysqlclient`; `PyMySQL` is allowed when portability or existing service convention requires it.
   - Use Django ORM and Django migrations when the service is a Django service. Use SQLModel when the architecture deliberately chooses the Pydantic plus SQLAlchemy model shape or the service already uses SQLModel; do not replace existing SQLModel solely to comply with the default.
   - Another deliberately chosen or existing ORM/query layer is allowed when kept consistent inside the service boundary and recorded as the service data-access choice.
   - Treat Alembic or framework migrations as reviewable source artifacts; autogeneration is a draft, not a substitute for migration design.
   - Use Redis for cache, locks, counters, idempotency windows, rate limits, and ephemeral coordination, not durable truth.

4. Design runtime and dependency contracts.
   - Config should be typed and environment-specific, preferably through Pydantic Settings or framework-equivalent config schemas.
   - High-risk feature flags and runtime config default fail-closed in production. Local stubs, test defaults, and developer-safe switches must be visibly scoped and cannot become implicit production enablement.
   - Secrets must not live in code, config examples, tests, or generated clients.
   - Dependency clients for DB, Redis, MQ, object storage, service discovery, external HTTP, and inference calls must have explicit timeout, credential, observability, and test-substitution contracts.
   - Separate serving-path timeout budgets from admin, migration, bootstrap, repair, and batch-operation timeouts.
   - Service registration or model-serving registration should happen only after readiness checks pass; registered metadata should identify environment, version, routing/lane, and capability. Shutdown, polling, and background registration loops need bounded timeout and explicit exit semantics.
   - Readiness must be externally observable for operations. Internal SDK or serving-framework status is useful, but production services still need a clear health/readiness surface, startup failure behavior, and unregister/shutdown semantics.
   - A capability requirement is not a framework-adoption decision. When a requirement names a capability (service discovery, mTLS, graceful drain), first define its minimal closure — the smallest layer that satisfies it — before adopting a platform framework or runtime component for it, AND name which layer actually closes it: service discovery and mTLS can close at the deployment layer (orchestrator DNS, mesh sidecar), but graceful drain inherently needs runtime behavior (stop accepting, SIGTERM/readiness handling, in-flight completion) — manifests alone leave it explicitly `not closed`, never silently satisfied. Framework adoption is not all-or-nothing: when a framework default conflicts with a service characteristic (e.g. a fixed 30s drain window versus minute-scale streaming requests), split at the boundary — land the part that delivers value on its own (deployment manifests), decide or defer the conflicting part (runtime lifecycle adoption) separately with each deferred capability's closure status recorded, and keep a quotable record of why it was not adopted. Mirror any change to this rule in `../go-microservice-architecture/SKILL.md`.
   - Define error mapping once, then map framework, validation, ORM, worker, HTTP client, and dependency errors into it.
   - When comparing a new product backend against a mature internal reference, convert the comparison into a platform-capability gap list, not a source-code shopping list.
     - The recurring maturity checks are: identity/RBAC subject model, external API signature/replay/allowlist boundary, dynamic config with version/cache/watch/rollback, queue producer/consumer lifecycle with retry/drop/replay visibility, DB transaction and query-safety guardrails, context/error propagation across HTTP/RPC/queue, and resource/search visibility scope.
     - A placeholder or README-only package family is not implementation evidence.
   - Before marking an internal reference package family as placeholder-only, inspect nested git repositories or submodules, non-default local/remote branches, tags, and tree contents with read-only commands. Default-branch scaffolds do not prove the architecture capability is absent.
   - If the comparison uses internal checkouts, private repositories, local paths, or organization projects, route preservation through `skill-extraction-workflow` or apply the same sanitization gate before landing any artifact: keep only mechanisms, boundaries, and acceptance gates; remove source-identifying domains, paths, repository/module names, people, tickets, and business nouns.

5. Define observability, quality, and release readiness.
   - Logs, metrics, traces, health/readiness endpoints, request IDs, and safe debug exposure are architecture surfaces.
   - Package and runtime choices must be reproducible: lockfile, dependency groups, import mode, lint/type/test commands, and container entrypoint.
   - Define deployment resources, process model, worker concurrency, canary/smoke checks, rollback, and migration order before launch.

## Architecture Defaults

- Do not split Python backends into microservices until ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify separate deployable units. When microservices are justified, each service has an owner, API/OpenAPI or gRPC contract, data ownership, inter-service auth, timeout/retry policy, service discovery or routing, observability, deployment unit, and rollback boundary.
- A modular monolith, script, worker-only service, or package is valid when boundaries are unclear, the product is small, the existing repository shape fits, or the user requests simplification. Record the reason when choosing it.
- Keep FastAPI/Flask route handlers thin: auth, validation, request/response mapping, and orchestration handoff.
- In Django, keep framework conventions where they improve clarity, but do not hide domain rules in views, serializers, or settings side effects.
- Use explicit app factories or startup assembly for clients and middleware; avoid doing network I/O at import time.
- Avoid hard-coded registry endpoints, provider URLs, secrets, and fallback domains in code. Route them through typed config and fail closed when required production config is missing.
- Use SQLAlchemy 2.x-style sessions, unit-of-work boundaries, or framework transactions as the data consistency boundary.
- Long-running jobs require idempotency, checkpoint/restart behavior, failure visibility, and a max execution/concurrency model.
- Mature reference code is useful only when it exposes a reusable boundary. Prefer extracting framework wrappers, typed clients, context/error contracts, config schemas, unit-of-work or transaction helpers, queue lifecycle helpers, and query-safety checks; discard business nouns, private module layout, and one-off legacy habits.
- Cross-boundary semantic values are an architecture responsibility even when their local representation is small. Architecture decides where finite values such as status, market, region, channel, source, provider, or permission are canonical, who may expose generated transport enums to domain code, and how duplicate constants are retired.
- High-risk operations require a resilience contract: fail-closed policy, idempotency strategy, durable status, reconciliation or repair path, trace/request id propagation, user/support explanation surface, and proof that fallback/degradation cannot bypass authorization, tenant/user isolation, quota, audit, or data-retention controls.
- High-risk context resolution must reject missing tenant, actor, subject, or resource scope instead of falling back to default identities. Durable side effects need atomic audit/outbox evidence or an explicit reconciliation/repair workflow.
- Python AI/RAG service hosts must separate service wiring from inference design. Model routing, prompt policy, retrieval design, evaluation, and replay belong to `llm-inference-integration`.
- Generated API clients and generated protobuf code are output surfaces; do not hand-edit them. Generated migrations are drafts that require human review before landing.

## Reference Loading

- For source provenance, current extraction boundary, and keep/merge/discard decisions, read `references/source-evidence-map.md` when auditing or re-extracting this skill.
- For architecture decisions and boundaries, read `references/architecture-playbook.md`.
- For framework choice, app boundaries, ASGI/WSGI, and route ownership, read `references/web-framework-boundaries.md`.
- For Pydantic, OpenAPI, schema evolution, and protobuf/gRPC exceptions, read `references/api-contract-and-schema.md`.
- For public API, partner app auth, signature verification, callback trust boundaries, authorization scope, and audit/operations security, read `references/api-security-boundaries.md`.
- For SQLAlchemy/Django ORM, migrations, transactions, and data ownership, read `references/data-modeling-and-migrations.md`.
- For asyncio, blocking work, GIL, and concurrency design, read `references/async-execution-model.md`.
- For Celery/RQ/arq, scheduled jobs, worker leases, and batch/restart policy, read `references/background-jobs-and-scheduling.md`.
- For event-driven architecture concerns — delivery semantics taxonomy, producer-side patterns, transactional outbox/inbox, idempotency design, partition-key ordering, schema evolution, retry/DLQ/replay strategy, fanout patterns, saga vs choreography, end-to-end "exactly-once" illusion, and Python-specific implementation glue (asyncio consumer + bounded queue, SQLAlchemy outbox poller with `SKIP LOCKED`, exception hierarchy, sync-vs-async consumer choice, graceful-shutdown order) — read `references/event-driven-architecture.md`. Stack-agnostic core sections mirror the sibling `go-microservice-architecture/references/event-driven-architecture.md`; maintainers updating those sections must update both files in the same change.
- For multi-tenant SaaS isolation concerns — isolation-tier decision tree (RLS / schema-per-tenant / DB-per-tenant / region-per-tenant), tenant context as a first-class value, tenant-aware data access with DB-engine enforcement, per-tenant quota and rate limit at every layer, tenant-aware observability with cardinality management, per-tenant lifecycle (provision / suspend / export / delete / retention / archive), per-tenant rollout and feature flags, cross-tenant capability gating, compliance / residency / sovereignty, migration between tiers, and Python-specific implementation glue (tenant on `contextvars.ContextVar`, FastAPI dependency + Starlette middleware, SQLAlchemy RLS session variables, connection pool reset via pool reset event, cache key helper, async task spawning with `copy_context`, async message consumer pattern, outbox tenant propagation) — read `references/multi-tenant-isolation.md`. Stack-agnostic core sections mirror the sibling `go-microservice-architecture/references/multi-tenant-isolation.md`; maintainers updating those sections must update both files in the same change.
- For data-platform architecture concerns — DB engine choice axis (single-instance OLTP / sharding middleware like Vitess / distributed SQL like TiDB / managed cloud DB), HA topology and failover model, read scaling and replica routing with staleness budget, sharding and resharding strategy, cross-region replication and data residency, backup with tested recovery (RPO/RTO + restore drill), cluster lifecycle (provision / scale / decommission), capacity planning (storage / IOPS / connections / latency / replica lag), fleet-wide schema-migration coordination, connection-pool and proxy topology (PgBouncer / ProxySQL / Vitess gateway), cost and efficiency, and Python-specific implementation glue (sync-vs-async driver choice, SQLAlchemy 2.x async with asyncpg/asyncmy, Alembic migrations, PgBouncer prepared-statement caveat, health-check FastAPI dependency, connection-storm mitigation) — read `references/data-platform-architecture.md`. Stack-agnostic core sections mirror the sibling `go-microservice-architecture/references/data-platform-architecture.md`; maintainers updating those sections must update both files in the same change.
- For Redis cache, locks, counters, rate limiting, and idempotency architecture, read `references/redis-cache-coordination.md`.
- For typed settings, secrets, dependency clients, and runtime config, read `references/config-secrets-runtime.md`.
- For logs, metrics, traces, health checks, and debug exposure, read `references/observability-and-ops.md`.
- For timeouts, retries, canonical errors, validation, and failure policy, read `references/reliability-and-error-contract.md`.
- For Python service boundaries around LLM/RAG/inference systems, read `references/ai-service-integration-boundaries.md`.
- For uv/poetry/pip, lockfiles, dependency groups, containers, process model, and launch checks, read `references/packaging-runtime-readiness.md`.
- For import/export, backfill, data repair, batch jobs, and pipeline boundaries, read `references/batch-and-pipeline-architecture.md`.
