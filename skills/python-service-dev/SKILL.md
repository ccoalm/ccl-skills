---
name: python-service-dev
description: 用 Python 写接口 / FastAPI / Django model / Celery 任务 / pytest → implement, modify, scaffold, test, and wire Python backend services, workers, packages, standalone CLI/tooling, migrations, Redis, queues, config, observability, and clients. Triggers also include "用 Python 写个命令行工具", "重构 Python 服务里的某文件/某类(局部)", "refactor a file/class within a Python service". For reproduction, isolation, or root-cause debugging, use defect-diagnosis first; for architecture/layering decisions or a service-wide refactor, use python-service-architecture; for a multi-stage / cross-module refactor delivery, re-enter product-rd-workflow.
---

# Python Service Dev

Use this for implementation of Python backend products, services, microservices, AI-service hosts, workers, packages, and batch tools. For new backend products, implement the smallest deployable or package shape justified by ownership, data boundary, runtime isolation, scaling, release cadence, and rollback needs. It should adapt to the repository in front of you, but the workflow is independent of any prior codebase.

## Skill Routing

- Use this skill for Python implementation, scaffolding, handlers/routes/views, schemas, services, microservices, repositories, migrations, Redis, queues, workers, external/inter-service clients, config, observability, packaging, and tests.
- Use `product-rd-workflow` first when the request is an end-to-end product delivery workflow, product idea to implementation plan, release workflow, cross-skill coordination, bug postmortem, or durable process improvement.
- Use `defect-diagnosis` first when the task is to reproduce, isolate, instrument, fix, verify, or root-cause a backend defect, regression, repeated failure, review finding, or failing test.
- Use `python-service-architecture` when the user asks for system design, service boundaries, contract strategy, storage ownership, reliability design, or architecture review without code changes.
- Use `testing-strategy` when the main question is which unit, integration, contract, or E2E layer should prove behavior; then return here for Python-specific implementation.
- Use `test-artifact-management` when the ask is about generating structured test cases from a Feishu requirements doc or codebase and tracking them in Feishu Bitable before implementation begins.
- Use `llm-inference-integration` for inference, RAG, prompt, model-routing, evaluation, replay, token-cost, and batch-inference design. Return here for Python API, worker, adapter, persistence, and observability implementation.
- Use `go-microservice-dev` for Go services. Do not load Go implementation rules for Python work unless the task is explicitly cross-language contract or generated-client integration.
- Use codebase-specific skills only when the task is explicitly about an existing repository.
- For money, billing, quota, permission, tenant/user data isolation, high-impact AI, repeated writes, async finality, or incident-explanation risk, apply `product-rd-workflow` high-risk resilience gates and route test-layer design through `testing-strategy`.
- When a change can alter what a client renders or which state, action, or decision path it offers—including strings/templates/config/flags and API/event/schema fields, enums, status/progress, permission/capability signals, defaults, or result shapes—load `../product-ui-ux-design/references/delivery-contract.md`, create the applicable full or lightweight record in that contract, and follow its canonical consumer-universe classification, design/test/client handoffs, and terminal-status rules.
- This Python owner returns only its `producer_record` delta: immutable binding, build/schema/config artifact identity, exact command/environment, and API/event/log/output observation.

- For a standalone Python CLI, this skill owns Python parser/library implementation mechanics. Any change to a user-facing command tree, subcommand, flag/default/action path, help/output/exit behavior, confirmation, progress, or recovery path also loads `terminal-cli-dev`, which owns the terminal contract and its UI/UX/testing handoff. Only internal parser refactors proven to preserve all user-visible semantics may skip that owner.

## Generalization Discipline

- Implement the repo in front of you, but do not import product nouns, service names, package paths, provider names, IDs, dashboards, or organization-specific habits from prior codebases.
- Convert domain-specific source patterns into reusable mechanics: route shape, schema validation, repository/unit-of-work boundary, transaction scope, cache key strategy, idempotency, job lease, config object, trace context, fake client, or test style.
- If an observed pattern only works for one product domain, discard it instead of turning it into a rule.
- Resolve conflicts by choosing the safer generic default: explicit schemas over dicts, typed settings over ad hoc environment reads, reviewed migrations over blind autogeneration, bounded async concurrency over unbounded gather, dependency injection over import-time clients, focused pytest tests over live-infra tests by default, and fail-closed for auth/permission/data-integrity paths.
- When adding or revising durable Python implementation guidance, check whether the lesson is generic backend service practice that should also update `go-microservice-dev`, or belongs in a shared workflow skill instead. If the rule depends on Python tooling, FastAPI/Flask/Django, Pydantic, asyncio, pytest, or Python package layout, keep it here and do not force a Go mirror.

## Development Workflow

Before editing code, generated files, migrations, configs, or tests, complete enough analysis and planning for the change to be reviewable. Scale the plan to risk: a simple low-risk single-package change can use a short inline plan; multi-file, contract-visible, data/schema, async, release, bug-fix, branch/MR, unclear-risk, or high-risk work needs explicit task split, acceptance checks, verification commands, rollback or stop conditions, and named handoffs to architecture, testing, or diagnosis skills before edits.

Repo-local agent contracts (`AGENTS.md` at the repo root and in source directories) are part of the delivery contract: when a change moves a stable boundary, generated surface, workflow, or directory-local rule, update the nearest contract in the same MR and keep coverage in sync per `product-rd-workflow`'s spec / repo-contract sync gate.

1. Establish the target Python project shape.
   - Find the nearest `pyproject.toml`, lockfile, package root, app entrypoint, framework app, settings, migrations, tests, and documented commands.
   - Identify whether this is an HTTP API microservice, internal microservice, worker service, scheduled job service, SDK/package, CLI, AI-service host, or batch tool.
   - For internal service-to-service calls, use RPC/gRPC by default and HTTP when the service contract chooses it. Do not treat HTTP as a local shortcut: use the repository/platform HTTP client wrappers for discovery, auth, deadlines, retries, logging, metrics, tracing, and contract tests.
   - For new backend products, implement a separate microservice slice only when ownership, scaling, data ownership, runtime isolation, deployment cadence, or rollback needs justify a separate deployable unit. Otherwise keep the slice inside the existing modular monolith, worker, package, or script shape and preserve clean contracts, config, observability, and tests.
   - When mining a local/internal reference tree for Python implementation patterns, first detect nested git repositories, submodules, and implementation-bearing non-default branches or tags before judging the tree empty. Prefer read-only tree inspection over switching branches, and record the reusable mechanism rather than the source branch, module, or path.
   - Check whether tests are split by unit, integration, contract, API, E2E, and live-infra markers.

2. Start from contracts and data.
   - Update Pydantic/OpenAPI, Django serializer/form, or protobuf/gRPC contracts before changing request/response behavior.
   - When protobuf is in scope for gRPC or HTTP contracts, record the source/config/test location for the globally unique service name, IDL source, generation command, generated artifact version, framework binding, and JSON/binary wire-format policy before implementing handlers or service logic; any unconfirmed item is a blocker. Prefer consuming generated contract packages from the contract/generation boundary. When shared IDL and IDLGen repositories exist, Python implementation must use the generated Python artifacts from that shared boundary and keep compatibility with Go and client-side consumers; do not create service-local private IDL copies that drift from the shared contract.
   - Implement JSON-wire business API responses through the contract-recorded envelope per `../platform-service-connectivity/references/http-response-envelope-contract.md`; when the canonical envelope applies, map domain errors to the canonical `code`/`message` model at the framework boundary and do not return ad hoc top-level business fields from routes/views.
   - Select the transport contract first — the carrier is scenario-driven per the Carrier decision in `../platform-service-connectivity/references/rpc-framework-recipe.md`: on a platform that has standardized the in-message `base` carrier (or a contract that declares/publishes `base`), apply the recipe's ordered base-field gate as the single source of truth; on a metadata-carrier service (the default for ordinary gRPC), apply the R7 owner-recorded header-set gate (`../platform-service-connectivity/SKILL.md` R7) instead. Boundary-exposure classification (canonical trigger set, rerun conditions, dispositions) and the implementation population check are canonical in the same recipe; when any canonical boundary trigger fires, run boundary-exposure classification before release per that recipe — missing or contradictory classification evidence is an open release gap, and authz on unauthenticated caller-supplied identity is an immediate blocking implementation finding. Python service diffs cite the recipe evidence for the touched edit kind; service-authored proto snippets, service-local copied descriptors, uncited provenance claims, stale/wrong-version descriptors, or broad tag claims cannot self-certify the shared contract.
   - Route/view/handler, adapter, or DTO diffs that manually construct generated request/response DTOs outside the middleware-filled path, or write/mutate/overwrite `base`, `LogId`, caller, `From`, `To`, `Tags`, or equivalent identity fields on generated DTOs, apply the implementation population check in `../platform-service-connectivity/references/rpc-framework-recipe.md` (carrier-neutral — it runs even when the base-field gate is not applicable); missing evidence is an open implementation gap.
   - Convert generated protobuf types at the transport/application boundary unless a quotable architecture or repo-contract record deliberately treats generated DTOs as the public application contract. Without that record, domain code must not depend on generated transport types.
   - Use generated or schema-owned request/response/common-field types where they exist. If domain or persistence models differ from transport DTOs, map them explicitly at the route/application boundary.
   - Define ORM model and migration changes before repository code. New Python relational services use SQLAlchemy 2.x plus Alembic by default unless the service records a deliberate alternative data-access choice; use framework ORM and migrations when the chosen framework, such as Django, owns that boundary. For new MySQL async services, prefer `asyncmy`; `aiomysql` is allowed when deliberately chosen or already established. Do not replace an existing working `aiomysql` driver solely to comply with the default. Do not mix MySQL async drivers inside one service boundary.
   - Define Redis keys, TTLs, and idempotency/lock semantics before cache code.
   - Define queue payloads, retry behavior, and idempotency before consumers.
   - Define runtime config, health/readiness, entrypoint, and rollback controls before release-facing code.

3. Keep layers clean.
   - Transport layer: framework mapping, validation, auth context, response mapping.
   - Application/service layer: use-case orchestration and transactions.
   - Domain layer: rules and invariants.
   - Infrastructure layer: DB, Redis, MQ, HTTP clients, object storage, inference clients.
   - Generated code: never hand-edit generated clients or protobuf output. Migration files are reviewable source.

4. Wire dependencies explicitly.
   - Constructors and dependency providers should declare what they need.
   - Prefer small boundary interfaces or protocols where tests or adapters matter.
   - Keep production and test dependency graphs separate when clients need fakes.
   - Avoid import-time client creation and hidden global mutable state. When a library reads config only from process globals (env vars) and the mutation is unavoidable, confine it to a snapshot/restore context manager scoped to the minimal window — restoring by `pop` when the value was unset versus reassigning when it had a value — under any existing lock.
   - If a mature internal reference has stronger wrappers than the target repo, reuse existing target-repo wrappers first. When no wrapper exists, add the smallest local adapter that the current task justifies, or route platform-wide wrapper extraction to architecture/platform skills before implementation. Do not paste reference business code or private package layout; preserve only the generic contract, such as unit-of-work transaction helper, typed config client, queue producer/consumer wrapper, context injector, error mapper, or query-safety hook. Safety-critical fragments — exception-firewall wrappers, timeout enforcement, untrusted-input parsing — must be a single shared implementation even at a dozen lines; a per-call-site copy that drifts fails as a dead worker or a silent no-op, not as slowness.
   - If the implementation task directly mines an internal checkout, private repository, local path, or organization project, apply the same sanitization gate before landing any artifact: keep only mechanisms and generic contracts; remove source-identifying domains, paths, repository/module names, people, tickets, and business nouns.
   - For service registration, model serving, or worker bootstraps, verify readiness before registration, publish environment/version/routing metadata, and make shutdown/polling loops bounded and testable.
   - For Python-hosted inference or long-running service hosts, separate HTTP ingress, request routing, handler/model execution, SDK registration, and generated deployment config. Treat generated serving configs, model packages, debug downloads, and runtime outputs as artifacts, not source templates.

5. Verify at the right scope.
   - Run focused pytest tests for changed packages.
   - When writing the test code itself (structure, naming, smells, fixtures, behavior-vs-state, coverage, isolation, parameterization), pick the matching § from the decision table in `testing-strategy/references/test-code-authoring-patterns.md`; enable the per-stack lint executors for its machine-decidable smells (conditional logic / sleep / assertion-free tests) per `testing-strategy/references/fitness-functions.md` §4.1.4 (e.g. Ruff `TID251` banning `time.sleep`).
   - Run async tests with the repo's configured `pytest-asyncio` mode.
   - Run integration tests only when required services and credentials are available.
   - **TC traceability and the deprecation cascade** are mandatory when the repo tracks test cases in Bitable: before adding a test, check existing TC coverage; before deleting one, run the caller-liveness sequence. Mechanics (marker registration, coverage grep, the four-step 废弃级联, dynamic-import boundaries) live in `references/testing-and-quality-patterns.md` (TC Traceability And Deprecation Cascade).
   - Run ruff, mypy/pyright, formatting, and codegen/migration checks when the repo uses them.
   - Keep fast tests deterministic; isolate live infrastructure, long sleeps, generated files, and external credentials behind markers.

## Implementation Rules

- Validate inputs at framework boundaries.
- When ingesting a dynamic set of headers by prefix, whitelist each derived key against a strict token/charset regex and reject empty or malformed keys; do not trust the shape of externally-supplied header names.
- Use typed Pydantic or framework schemas for public APIs.
- For finite domain values such as market, region, status, scene, source, provider, priority, permission, or channel, define a domain-owned `Enum`/`Literal` alias/constant set plus one parser or canonicalization helper before using the value across service, repository, schema, or tests. Transport enums, query/header strings, DB strings, and generated-client values convert at the boundary; business logic and tests reuse the domain symbols.
- Pass request/trace context through external calls where the stack supports it. The carve-out is narrow and behavioral: only a genuinely side-effect-free function — no external calls, task spawning, filesystem/env, clock/random, or logging/trace/tenant/feature lookup across its body and callees — may omit it. A mapper or helper that does, or later gains, any such call takes it. The test is behavior, not the name.
- Set timeouts for HTTP/DB/Redis/MQ/inference calls.
- Honor cancellation and request deadlines in async code.
- Do not block the event loop with sync clients, CPU-heavy processing, large file I/O, or GPU work.
- Use SQLAlchemy/Django transactions for multi-step writes inside one database.
- Keep SQLAlchemy, SQLModel, Django ORM, and raw SQL behind repository or data-access modules; routes/views and business services should not scatter SQL or ORM query construction.
- When a reference stack exposes unit-of-work or session/transaction-bound repositories, reuse or add that shape instead of passing raw sessions through business code. Service logic should enter one transaction boundary, then call repositories bound to that session, transaction, or unit of work.
- For DB-heavy services, prefer shared unit-of-work or transaction helpers that recover/rollback on exception, and add non-production query-safety checks where the repo has ORM hooks, query builders, migration metadata, or test infrastructure to support them. If the repo cannot mechanically check missing indexes or full scans yet, record the platform gap and cover changed high-risk queries with migration/repository review evidence, bounded pagination assertions, or focused tests. These checks should become framework or repository behavior, not reviewer folklore.
- Keep migrations, model changes, repository changes, and rollback notes together.
- For Python microservice work, keep API/OpenAPI or gRPC contract changes, generated clients, service-client adapters, auth headers/tokens, timeout/retry policy, and deployment config in the same implementation slice when they change together.
- Treat queue delivery as at-least-once; consumers must be idempotent.
- Queue producer/consumer wrappers should centralize metadata propagation, topic/routing-key/filter config, worker sizing, retry/drop behavior, exception recovery, close/drain lifecycle, latency/error metrics, and replay or DLQ visibility. Business handlers should implement domain work and idempotency, not recreate consumer scaffolding.
- Treat write retries as unsafe by default. Add automatic retry only when the operation has a durable idempotency key, unique constraint, state machine, dedupe table, or equivalent proof, and test duplicate submit/callback/queue/job-restart behavior.
- For money, quota, entitlement, permission, tenant/user isolation, privacy, and sensitive state changes, fail closed on uncertainty and return the canonical error before side effects.
- Do not default missing tenant, actor, subject, or resource scope on high-risk paths. Reject before side effects unless the code is an explicit bootstrap, seed, or maintenance path with separate approval.
- Do not rely on Redis-only, TTL-only, memory-only, or process-local dedupe for durable side effects. Use persistent idempotency or a state machine when the side effect is auditable, billable, externally acknowledged, or hard to reverse.
- Commit primary mutations with audit/outbox/governance evidence in one transaction when possible. If not possible, create a replayable repair record, surface stale/pending counts, and test the reconciliation gap.
- For high-risk user-visible operations, persist or return a stable request/task/order/support identifier and keep logs, audit records, or metrics sufficient for support explanation and compensation.
- Use Redis locks with unique values and compare-and-delete unlock.
- Centralize Redis keys, TTLs, lock leases, counters, and rate-limit scopes.
- Keep config typed and environment-specific.
- Do not hard-code registry endpoints, provider URLs, secrets, or production fallbacks. Missing production config for high-risk capabilities should keep the capability disabled or fail startup, not silently switch to a local/test default.
- For high-risk config, add typed settings, production-safe defaults, tests for disabled/missing config, and explicit enablement checks before behavior can run.
- Use pytest fakes/mocks for external clients by default; reserve live dependency tests for explicit integration gates.
- High-risk external flows that depend on real credentials, callback delivery, MQ/DB semantics, private-network services, or external model/runtime behavior need an explicit release-blocking integration, sandbox, replay, or manual evidence gate outside the default fast target. If that gate is unavailable, record the blocker, residual risk, and next unblock action instead of claiming fake-only confidence is complete.
- Python AI/service-host tests that require live model servers, real datasets, private-network endpoints, long sleeps, or manual scripts are integration/manual evidence. Keep the default fast gate on deterministic handler, router, config, readiness, metadata, parser, and error-mapping assertions, but do not use the fast gate alone to close high-risk runtime integration.
- Comments state invariants and why, not status snapshots that rot ("X is the only implementation", line counts, "temporary tool"). A comment claiming a guarantee the code does not provide (e.g. a per-attempt timeout that is never actually set) is worse than no comment; in review, treat every guarantee a comment claims as an assertion to verify against the code.
- Code that will live in production must not carry temporariness-implying names (spike/minimal/temp). Transitional scaffolding must state its retirement condition and expected retirement point explicitly, or it is not transitional.
- When bumping a shared dependency's version, change it across **every** consuming package/module, not only the obviously-affected ones — including indirect consumers that reach the dependency through a local/editable path install or that independently pin the same transitive dependency. Keep the version consistent everywhere it is declared (e.g. `pyproject.toml`, lockfile, and package `__version__` when present), then run the **full** test suite (not just the directly-related extra/subset) and update any test that hard-asserts the dependency pin/version. A consumer left on the old pin fails only later, often masked as a CI dependency-resolution error.
- For Python package releases, this skill owns package internals and tests; route registry upload, duplicate-publish recovery, simple-index metadata checks, and registry-only install verification through `platform-release-engineering/references/python-package-registry-release.md`.

## Reference Loading

- For source provenance, current extraction boundary, and keep/merge/discard decisions, read `references/source-evidence-map.md` when auditing or re-extracting this skill.
- For feature implementation steps, read `references/feature-playbook.md`.
- For project layout, package roots, uv/poetry/pip, import mode, and tooling, read `references/project-structure-and-tooling.md`.
- For FastAPI, Flask, Django, routes/views, dependencies, and app factories, read `references/web-framework-patterns.md`.
- For Pydantic/OpenAPI/schema validation and generated clients, read `references/schema-and-validation-patterns.md`.
- For public API implementation, partner app auth, signature verification, callback handling, authorization scope, and API security tests, read `references/public-api-security-patterns.md`.
- For SQLAlchemy/Django ORM, Alembic, migrations, repositories, and transactions, read `references/sqlalchemy-and-migrations-patterns.md`.
- For asyncio, blocking work isolation, concurrency limits, and cancellation, read `references/async-and-worker-patterns.md`.
- For Redis, cache, locks, idempotency, counters, and rate limits, read `references/redis-cache-lock-patterns.md`.
- For Celery/RQ/arq, queues, scheduled tasks, and job execution, read `references/background-job-patterns.md`.
- For durable task state machines, status transitions, leases, terminal states, and scheduled repair jobs, read `references/state-machine-task-patterns.md`.
- For audit logs, operation records, resource history, and change tracking, read `references/audit-history-patterns.md`.
- For notification delivery, operator alerts, outbound webhooks, and realtime client channels, read `references/notification-patterns.md`.
- For replay jobs, shadow execution, response comparison, and migration verification, read `references/replay-comparison-patterns.md`.
- For external HTTP clients, SDKs, generated clients, service discovery, and dependency adapters, read `references/dependency-client-patterns.md`.
- For errors, exception mapping, response envelopes, and validation errors, read `references/error-handling-patterns.md`.
- For logs, metrics, traces, health checks, and instrumentation, read `references/observability-implementation-patterns.md`.
- For pytest, async tests, fakes, fixtures, markers, ruff, mypy/pyright, and CI gates, read `references/testing-and-quality-patterns.md`.
- For Python API/worker wiring around LLM/RAG/inference systems, read `references/ai-service-wiring-patterns.md`.
- For import/export, backfill, repair scripts, generated artifacts, and batch reports, read `references/batch-and-artifact-patterns.md`.
