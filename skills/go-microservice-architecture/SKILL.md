---
name: go-microservice-architecture
description: Use when designing, reviewing, or explaining a new product's Go backend or microservice architecture using Kitex or similar RPC, Hertz or similar HTTP gateway, protobuf IDL, MySQL/GORM-style relational storage, Redis cache/locks/rate limiting, service discovery, dynamic config, message queues, observability, DI, and code generation. Product-agnostic; do not depend on existing codebase paths, service names, or legacy repositories. Prefer this for architecture, service boundaries, contracts, data ownership, reliability, security, and platform decisions when no code changes are requested; use go-microservice-dev for implementation work. Triggers also include "Go 后端架构怎么设计", "Go 微服务怎么拆", "RPC 接口怎么定义", "Go 服务边界", "Go 服务重构 / 架构分层重构", "拆分 Go 服务的上帝类/模块边界", "decompose a god class in a Go service".
---

# Go Microservice Architecture

Use this for new product/server architecture work. It distills proven backend patterns but must not assume any existing repository, service identifier, package path, database, or legacy service layout.

## Skill Routing

- Use this skill for architecture decisions, service decomposition, API/RPC contract shape, storage ownership, async workflow design, observability, reliability, and launch readiness.
- Use `product-rd-workflow` first when the request spans product shaping, architecture, implementation, review, release, and learning loops rather than architecture alone.
- Use `go-microservice-dev` when the user asks to implement, modify, debug, test, scaffold, or generate code. A localized refactor (某文件/某类) also belongs to `go-microservice-dev`; only service-wide layering/boundary redesign stays here, and a multi-stage / cross-module refactor delivery must re-enter `product-rd-workflow`. An unqualified whole-service "Go 服务重构" enters here by default, mirroring the Python pair — do not let the unqualified form fall to the implementation skill.
- Use `python-service-architecture` for Python services. Do not load Python rules for Go work unless the task is explicitly cross-language contract design.
- Use `platform-observability` for logs/metrics/traces/log-id propagation/dashboards/alerts/SLI-SLO design. This skill owns only the service-side observability surface (Kitex/Hertz middleware that emits structured logs, OTel SDK use, baseline labels attached by metrics client, health endpoints); the cross-cutting evidence stack belongs there.
- Use `platform-service-connectivity` for service mesh, service discovery (Nacos/Consul/equivalent), mTLS, multi-environment lane routing, retry/timeout/circuit-breaker policy, and the canonical RPC base struct shape. This skill defines what the service exposes (framework default options usage, request-metadata propagation conformance via the platform's chosen carrier — in-message `base` or transport metadata, scenario-driven per the connectivity Carrier decision — graceful shutdown); mesh policy and routing rules live there.
- Use `platform-release-engineering` for environment/lane matrix, canary/blue-green, promotion gates, rollback playbook, secret distribution, dynamic-config (config-center) vs static-config split, image build pipeline. This skill owns the service-side contracts (config schema, secret consumption interface, registration metadata); release flow lives there.
- Use codebase-specific skills only when the task is explicitly about an existing legacy/workspace repository.
- Architecture references should define decision criteria, invariants, ownership boundaries, and acceptance checks. Put concrete code patterns, helper APIs, and test mechanics in `go-microservice-dev`.
- When changing an architecture rule that implementation must obey, name the downstream execution owner before landing: `go-microservice-dev` for code mechanics, `testing-strategy` for proof layer, platform skills for runtime contracts, and `product-rd-workflow` for cross-stage gates. If the rule also applies outside Go, route through `skill-extraction-workflow` and mirror or explicitly skip sibling architecture/dev skills.
- For money, billing, quota, permission, tenant/user data isolation, privacy, high-impact AI, repeated writes, async finality, or incident-explanation risk, start from `product-rd-workflow` and its high-risk resilience gate before choosing service boundaries or fallback behavior.

## Platform Boundary

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

## Generalization Discipline

- Keep only reusable server-side mechanics: contracts, layers, storage ownership, config, reliability, observability, security boundaries, code generation, and delivery workflow.
- Do not copy product nouns, service names, package paths, provider names, environment names, IDs, dashboards, callback types, or organization-specific operating habits into the architecture.
- When source code shows a domain-specific concept, generalize it to `domain object`, `resource`, `authorization scope`, `integration scope`, or `workflow` only if the mechanic is reusable; otherwise discard it.
- When patterns conflict, choose deliberately:
  - Prefer current contracts and requirements over historical code habits.
  - Prefer relational durable truth over Redis-only truth for auditable state.
  - Prefer explicit protobuf/config/schema contracts over reflection, hidden globals, or stringly conventions.
  - Prefer idempotency and durable acceptance over retry-only designs.
  - Prefer fail-closed for auth, permission, critical state transitions, and data-integrity paths; fail-open only for non-critical cache/telemetry paths when availability requires it.
  - Fuse patterns only when both are generic and complementary; otherwise keep the simpler product-agnostic rule.
- Example: if one codebase stores workflow state only in Redis and another persists it in a relational table, keep the relational source-of-truth rule and optionally use Redis as cache, lock, rate limit, or scheduling aid.

## Core Workflow

Before changing architecture guidance, contracts, service boundaries, diagrams, plans, or implementation-driving recommendations, complete enough analysis and planning for the decision to be reviewable. Scale the plan to risk: a simple low-risk explanation can use a short inline plan; multi-service, contract-visible, data-ownership, release, high-risk, branch/MR, or unclear-risk architecture work needs explicit assumptions, alternatives, tradeoffs, acceptance checks, verification evidence, rollback or migration path, and named handoffs to implementation, testing, platform, or product workflow skills before edits or approval.

1. Define the product boundary.
   - Identify user workflows, domain objects, external integrations, and lifecycle events.
   - Decide which capabilities must be synchronous APIs, internal RPCs, async jobs, or scheduled tasks.
   - Internal microservice calls use RPC/gRPC by default and may use HTTP when the service contract chooses it. Internal HTTP must meet the same service discovery, auth, timeout, retry, observability, and contract-test standards as RPC.
   - Avoid splitting into microservices until ownership, scaling, data boundary, or deployment cadence justifies it.

2. Define service contracts before implementation.
   - Use protobuf IDL as the default contract format.
   - Service identity is decided before IDL and implementation. For new services, define the globally unique service name first, then IDL, then generated contract artifacts, then business implementation.
   - Treat IDL and idlgen outputs as a stable boundary between service contracts and business repositories. Prefer centralized IDL ownership plus versioned generated artifacts that business services import. When the platform uses shared IDL and IDLGen repositories, Go, Python, web, mobile, and mini-program consumers must derive from the same contract source; do not fork IDL or generated artifacts per service repository or per language unless it is a deliberate compatibility branch with owner, version, and deprecation plan. Service repository layout (single service, multi-service, API/RPC split) does not change contract ownership.
   - Protobuf may be the contract source for HTTP as well as RPC. For protobuf-backed or cross-language HTTP gateways, decide separately: contract source (protobuf/OpenAPI), generated route/client artifacts, and wire format (JSON vs binary protobuf). Classify protobuf-backed HTTP using the canonical wire-format gate in `../platform-service-connectivity/references/protobuf-http-contract-signals.md`; do not restate or widen that predicate locally.
   - API contracts must define request messages, the response envelope, and shared public fields in the shared contract source before implementation, per the canonical `code`/`message`/`data` envelope contract in `../platform-service-connectivity/references/http-response-envelope-contract.md` (adoption, migration, non-JSON surfaces, and anti-patterns live there — do not restate them here).
   - Internal RPC contracts carry the platform's shared request/response metadata field when the platform defines one; `platform-service-connectivity` owns the canonical base-struct shape and named-framework examples. Do not inherit a framework's reserved envelope/base field number as a cross-product convention (per `references/protobuf-contract-architecture.md`); if a shared metadata field must be part of the protobuf contract (rather than carried via middleware metadata), a new product picks an explicit field and documents it. Within a platform that has already standardized such a field, its field number, name, and message type are compatibility surfaces — do not renumber, rename, or replace them locally.
   - Internal service data models need the same contract discipline: shared cross-service DTOs, enums, status values, metadata fields, and request/response models live in the contract or generated artifact boundary; service-private domain and persistence models stay inside the owning service and convert at transport/application boundaries.
   - Separate public HTTP API models from internal RPC models when external clients have different stability needs.
   - Prefer additive contract evolution: new fields, new methods, new enum values; avoid breaking field numbers or response semantics.
   - **Inventory the service's exposed surfaces and review new ones at the boundary.** Keep a machine-checkable inventory of every externally reachable surface appropriate to the stack — HTTP routes, RPC services and methods, and async subscriptions (MQ / event / webhook consumers); a surface absent from it should not reach production unreviewed. Drive it from a deterministic discovery profile (routes/subscriptions-as-code, or a generated manifest plus a checked-in snapshot, are two common patterns) with explicit allowlisted carve-outs for framework / health / debug, generated, plugin, and env-conditional surfaces, so the gate flags genuinely new exposure instead of churning on false positives; also flag inventory entries no longer present in code so the snapshot stays trustworthy. Scale enforcement to risk: hard-fail CI for production, externally reachable services; a lighter manifest + review checklist suffices for prototypes, internal scripts, or repos without CI. The inventory proves *every surface was seen and reviewed*, **not** that it is authorized — it is not an authn/authz gate; auth, tenant isolation, and safe exposure remain separate evidence the boundary review must still demand. An unregistered new route or consumer is a *shadow surface* (unreviewed; async consumers are a commonly missed class). Distinct from breaking-change detection (`buf breaking` / `kitex check`, which guards *changes to existing* surfaces) and from agent-contract directory coverage (whether a directory carries an `AGENTS.md`); it guards *new runtime exposure*. `product-rd-workflow`'s spec/repo-contract sync gate owns the human discipline; this is its mechanical enforcement. Mirror any change to this rule in `../python-service-architecture/SKILL.md`.
   - For finite values that cross service, storage, client, analytics, or generated-code boundaries, architecture must name the canonical owner, shared package or contract location, conversion boundaries, unknown/default behavior, and migration/debt exit path before implementation. If no shared location exists, approve the local-slice fallback and require every `finite-value-debt` marker to carry task reference, owner, deadline, and reason.

3. Design data ownership.
   - Each service owns its write model and schema.
   - Cross-service reads should go through RPC/API or explicit read models, not shared table writes.
   - Use relational DB as source of truth for transactional domain state.
   - Use GORM as the default MySQL DAL choice for new Go services unless the repo already standardizes or conventionally uses another query layer, or the architecture records a deliberate alternative.
   - Decide schema, indexes, unique constraints, migration path, and sharding keys before writing DAL code.
   - Keep GORM, sqlx, and raw SQL behind DAL or repository boundaries; transport and application layers must not build database queries directly.
   - Use Redis for cache, locks, counters, idempotency windows, rate limits, and ephemeral coordination, not durable truth.
   - Define Redis key scope, TTL policy, lock lease, rate-limit window, and idempotency lifetime as part of the architecture.

4. Design runtime platform contracts.
   - Config: local file + dynamic config, with environment/lane separation.
   - High-risk feature flags and runtime config default fail-closed in production. Local stubs, test defaults, and developer-safe switches must be visibly scoped and cannot become implicit production enablement.
   - Secrets: never stored in code or config files; resolve through a secret provider.
   - Service discovery: all internal RPC clients use discovery/resolver abstraction.
   - Service identity: internal RPC/HTTP trust should be based on workload identity, mTLS, signed service tokens, or an equivalent zero-trust control, not only network location.
   - Runtime wrappers should provide service identity, registration/discovery, context propagation, trace/log id, metrics, timeout/circuit behavior, and safe debug exposure consistently across HTTP, RPC, and workers.
   - A capability requirement is not a framework-adoption decision. When a requirement names a capability (service discovery, mTLS, graceful drain), first define its minimal closure — the smallest layer that satisfies it — before adopting a platform framework or runtime component for it, AND name which layer actually closes it: service discovery and mTLS can close at the deployment layer (orchestrator DNS, mesh sidecar), but graceful drain inherently needs runtime behavior (stop accepting, SIGTERM/readiness handling, in-flight completion) — manifests alone leave it explicitly `not closed`, never silently satisfied. Framework adoption is not all-or-nothing: when a framework default conflicts with a service characteristic (e.g. a fixed 30s drain window versus minute-scale streaming requests), split at the boundary — land the part that delivers value on its own (deployment manifests), decide or defer the conflicting part (runtime lifecycle adoption) separately with each deferred capability's closure status recorded, and keep a quotable record of why it was not adopted. Mirror any change to this rule in `../python-service-architecture/SKILL.md`.
   - Dependency clients: DB, Redis, MQ, object storage, service discovery, secret provider, and external HTTP clients must have explicit timeout, credential, observability, and test-substitution contracts.
   - Dependency platform layers own SDK lifecycle, credential resolution, readiness, shared timeout policy, close hooks, and test substitution. Feature infrastructure adapters own feature-specific schemas, indexes, query/ranking contracts, object names, event payload meaning, and repair semantics. Do not place feature contracts in the platform layer just because they use a platform client.
   - Admission control: inbound rate limits, concurrency limits, load shedding, backpressure, and circuit-breaker behavior are part of reliability design.
   - Release runtime: service metadata, deployment resources, mesh/gateway routing, canary traffic, approval, and rollback are first-class architecture surfaces.
   - Error contract: define canonical code/message semantics once, then map HTTP, RPC, worker, and dependency errors into it.
   - Context contract: trace/log id, lane/environment, authorization/resource scope, request deadline, and auth subject must propagate through all sync and async paths.
   - Observability: logs, metrics, traces, health checks, pprof/debug where safe, and structured request context.
   - When comparing a new product backend against a mature internal reference, convert the comparison into a platform-capability gap list, not a source-code shopping list.
     - The recurring maturity checks are: identity/RBAC subject model, external API signature/replay/allowlist boundary, dynamic config with version/cache/watch/rollback, MQ producer/consumer lifecycle with retry/drop/replay visibility, DB transaction and query-safety guardrails, context/error propagation across HTTP/RPC/MQ, and resource/search visibility scope.
     - A placeholder or README-only package family is not implementation evidence.
   - Before marking an internal reference package family as placeholder-only, inspect nested git repositories or submodules, non-default local/remote branches, tags, and tree contents with read-only commands. Default-branch scaffolds do not prove the architecture capability is absent.
   - If the comparison uses internal checkouts, private repositories, local paths, or organization projects, route preservation through `skill-extraction-workflow` or apply the same sanitization gate before landing any artifact: keep only mechanisms, boundaries, and acceptance gates; remove source-identifying domains, paths, repository/module names, people, tickets, and business nouns.

5. Define code generation and ownership boundaries.
   - Generated code is an output surface, not hand-maintained source.
   - Keep IDL, generated contracts, HTTP route generation, DB model generation, and Wire/DI generation explicit.
   - Introducing or migrating any HTTP gateway/framework requires a quotable record in the architecture doc, repo contract, or MR description, with a separately locatable entry for gateway-capability justification, contract source, middleware order, generated artifacts, observability, and tests. Protobuf motivation alone is insufficient evidence unless the same record states a concrete missing capability in the existing framework, why the current extension points cannot satisfy it, and which requirement the new framework satisfies. Adding protobuf-backed HTTP on an unchanged gateway/framework requires the contract-source and wire-format records; expand to generated-artifact, observability, and test records when those surfaces change.
   - Health checks should be able to prove the boundary: IDL source location, generation command, generated package version, service implementation importing generated contracts, and CI/breaking-change checks. Agent review then judges whether the service layer bypasses the contract or hides domain semantics in transport code.
   - Document the generation commands in the repo.
   - Generation commands must be portable and must not contain developer-local absolute paths.

## Architecture Defaults

- One product can start as a modular monolith if service boundaries are unclear; split by data ownership and team/runtime needs, not by noun count.
- Public API layer should be thin: auth, validation, request/response mapping, orchestration handoff.
- RPC services should own domain operations and internal contracts.
- Background workers should own event processing, retries, idempotency, and backfill/repair workflows.
- A mature Go service usually separates transport/handler, application logic, domain/service orchestration, and infrastructure adapters; dependency injection or provider sets should make those seams visible instead of letting handlers construct DB/MQ/RPC clients directly.
- Shared libraries are allowed for infrastructure concerns; do not put domain rules in shared packages.
- Cross-boundary semantic values are an architecture responsibility even when their local representation is small. Architecture decides where finite values such as status, market, region, channel, source, provider, or permission are canonical, who may expose generated transport enums to domain code, and how duplicate constants are retired.
- Mature reference code is useful only when it exposes a reusable boundary. Prefer extracting framework wrappers, typed clients, context/error contracts, config schemas, transaction helpers, MQ lifecycle helpers, and query-safety checks; discard business nouns, private module layout, and one-off legacy habits.
- A service should have clear layers: transport, application/service logic, domain logic, infrastructure adapters, generated contracts.
- Long-running jobs require a first-class runtime model: distributed lock scope, lease time, max execution time, retry policy, idempotency key, and failure visibility.
- External dependencies require explicit timeout budgets, status-code validation, retry/fallback rules, and clear ownership of degraded behavior.
- High-risk operations require a resilience contract: fail-closed policy, idempotency strategy, durable status, reconciliation or repair path, trace/request id propagation, user/support explanation surface, and proof that fallback/degradation cannot bypass authorization, tenant/user isolation, quota, audit, or data-retention controls.
- High-risk context resolution must reject missing tenant, actor, subject, or resource scope instead of falling back to default identities. Durable side effects need atomic audit/outbox evidence or an explicit reconciliation/repair workflow.
- External dependency bootstrap requires a first-class operability contract: which resources may be created automatically, which existing resources must be validated, which partial failures can be repaired, which operations fail startup, and which timeouts apply to administrative work versus serving requests.

## Reference Loading

- For source provenance, current extraction boundary, and keep/merge/discard decisions, read `references/source-evidence-map.md` when auditing or re-extracting this skill.
- For architecture decisions and boundaries, read `references/architecture-playbook.md`.
- For reliability and operability requirements, read `references/ops-checklist.md`.
- For cross-cutting server contracts, read `references/cross-cutting-concerns.md`.
- For service scaffolding, generation, DI, config, and test architecture, read `references/service-scaffold.md`.
- For protobuf/IDL contract design, package boundaries, message/enum/service evolution, and HTTP/RPC mapping, read `references/protobuf-contract-architecture.md`.
- For secret providers, service discovery, dependency clients, object storage, and controlled concurrency, read `references/dependency-platform.md`.
- For public API, third-party callbacks, authorization scope isolation, and external integration boundaries, read `references/api-security-boundaries.md`.
- For HTTP gateway boundaries, generated routes, handler responsibilities, middleware order, and generated HTTP clients, read `references/http-gateway-architecture.md`.
- For deployment, environment/lane runtime, mesh/gateway traffic, canary, approval, rollback, and launch operations, read `references/release-runtime-readiness.md`.
- For runtime identity, environment/lane metadata, service discovery, logs, metrics, tracing, and debug exposure, read `references/runtime-observability.md`.
- For relational data modeling, schema ownership, indexes, sharding, migrations, and generated DAL boundaries, read `references/data-modeling-and-migrations.md`.
- For Redis cache, locks, counters, rate limiting, task coordination, local cache, and idempotency architecture, read `references/redis-cache-coordination.md`.
- For import/export, backfill, migration, partitioning, artifact policy, and batch limits, read `references/bulk-workflow-architecture.md`.
- For durable workflow state, allowed transitions, retry, cancellation, idempotency, and terminal-state policy, read `references/workflow-state-architecture.md`.
- For MQ topics, consumer groups, event contracts, activation gates, retry/drop policy, and async consumer operations, read `references/mq-consumer-architecture.md`.
- For event-driven architecture concerns — delivery semantics taxonomy, producer-side patterns, transactional outbox/inbox, idempotency design, partition-key ordering, schema evolution, retry/DLQ/replay strategy, fanout patterns, saga vs choreography, end-to-end "exactly-once" illusion, and Go-specific implementation glue (consumer goroutine + worker pool, outbox poller with `SKIP LOCKED`, error classification, graceful-shutdown order) — read `references/event-driven-architecture.md`. Stack-agnostic core sections mirror the sibling `python-service-architecture/references/event-driven-architecture.md`; maintainers updating those sections must update both files in the same change.
- For multi-tenant SaaS isolation concerns — isolation-tier decision tree (RLS / schema-per-tenant / DB-per-tenant / region-per-tenant), tenant context as a first-class value, tenant-aware data access with DB-engine enforcement, per-tenant quota and rate limit at every layer, tenant-aware observability with cardinality management, per-tenant lifecycle (provision / suspend / export / delete / retention / archive), per-tenant rollout and feature flags, cross-tenant capability gating, compliance / residency / sovereignty, migration between tiers, and Go-specific implementation glue (tenant on `context.Context`, GORM RLS session variables, connection pool reset, cache key construction, HTTP middleware, message consumer pattern, outbox tenant propagation) — read `references/multi-tenant-isolation.md`. Stack-agnostic core sections mirror the sibling `python-service-architecture/references/multi-tenant-isolation.md`; maintainers updating those sections must update both files in the same change.
- For data-platform architecture concerns — DB engine choice axis (single-instance OLTP / sharding middleware like Vitess / distributed SQL like TiDB / managed cloud DB), HA topology and failover model, read scaling and replica routing with staleness budget, sharding and resharding strategy, cross-region replication and data residency, backup with tested recovery (RPO/RTO + restore drill), cluster lifecycle (provision / scale / decommission), capacity planning (storage / IOPS / connections / latency / replica lag), fleet-wide schema-migration coordination, connection-pool and proxy topology (PgBouncer / ProxySQL / Vitess gateway), cost and efficiency, and Go-specific implementation glue (`database/sql` driver+pool, replica routing via DSN, migration tooling choice, PgBouncer mode decision, health-check shape) — read `references/data-platform-architecture.md`. Stack-agnostic core sections mirror the sibling `python-service-architecture/references/data-platform-architecture.md`; maintainers updating those sections must update both files in the same change.
- For audit logs, history records, retention, redaction, and query authorization, read `references/audit-history-architecture.md`.
- For dynamic config, rules, filters, routing, rollout ratios, and validation policy, read `references/config-rule-routing-architecture.md`.
- For replay, shadow execution, response comparison, diff retention, and rollout confidence checks, read `references/replay-comparison-architecture.md`.
- For performance budgets, capacity controls, DB query safety, batch limits, replay load, and launch readiness, read `references/performance-capacity-architecture.md`.
- For notifications, webhooks, alert delivery, retries, and recipient policy, read `references/notification-architecture.md`.
- For generated files, reports, PDFs, spreadsheets, object storage, and download artifacts, read `references/artifact-generation-architecture.md`.
- For error codes, response envelopes, transport mapping, and cross-service error propagation, read `references/error-contract-architecture.md`.
- For developer CLIs, code generation, generated-file ownership, and reproducible tooling workflows, read `references/developer-tooling-architecture.md`.
