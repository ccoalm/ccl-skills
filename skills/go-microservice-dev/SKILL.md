---
name: go-microservice-dev
description: Use when implementing, modifying, scaffolding, generating, or testing a new product's Go microservice, backend feature, or standalone Go CLI/tooling binary using protobuf IDL, Kitex or similar RPC, Hertz or similar HTTP, Wire/DI, MySQL/GORM-style DAL, Redis, MQ, dynamic config, code generation, and focused tests. For reproduction, isolation, or root-cause debugging, use defect-diagnosis first; this skill owns the Go implementation/fix. Triggers also include "用 Go 写一个服务", "Go 后端怎么搞", "Kitex 接口怎么写", "GORM 加索引", "用 Go 写个命令行工具", "重构 Go 服务里的某文件/某类(局部)", "拆分 Go 服务中的大文件或大类", "refactor a file/class within a Go service".
---

# Go Microservice Dev

Use this for implementation of new backend products and services. It should adapt to the repo in front of you, but the workflow is independent of any prior codebase.

## Skill Routing

- Use this skill for implementation, scaffolding, code generation, handlers, RPC methods, DAL, Redis, MQ, jobs, external clients, DI, and tests.
- Use `product-rd-workflow` first when the request is an end-to-end product delivery workflow, product idea to implementation plan, release workflow, cross-skill coordination, bug postmortem, or durable process improvement.
- Use `defect-diagnosis` first when the task is to reproduce, isolate, instrument, fix, verify, or root-cause a backend defect, regression, repeated failure, review finding, or failing test.
- Use `go-microservice-architecture` when the user asks for system design, service boundaries, contract strategy, storage ownership, reliability design, or architecture review without code changes.
- Use `testing-strategy` when the main question is which unit, integration, contract, or E2E layer should prove behavior; then return here for Go-specific implementation.
- Use `test-artifact-management` when the ask is about generating structured test cases from a Feishu requirements doc or codebase and tracking them in Feishu Bitable before implementation begins.
- Use codebase-specific skills only when the task is explicitly about an existing legacy/workspace repository.
- Development references should turn already-chosen architecture into code, tests, and generated artifacts. If a change requires choosing ownership, security model, source of truth, or release governance, first apply `go-microservice-architecture`.
- For money, billing, quota, permission, tenant/user data isolation, high-impact AI, repeated writes, async finality, or incident-explanation risk, apply `product-rd-workflow` high-risk resilience gates and route test-layer design through `testing-strategy`.
- When a change edits strings, templates, or config values that are returned to, persisted for, emitted to, served to, synchronized with, or configured for client consumption (error copy, labels, notification text, localization payloads, content/CMS/seed rows, message or notification templates, flag-delivered content), classify the consumers with a recorded bounded check (client repo / contract / locale search) before closing on API/log evidence; if any client surface renders the value user-facing, or consumers are unknown, load `product-ui-ux-design` and record its implementation-owner checkpoint — including the consuming client stack owner(s) and `testing-strategy` per that checkpoint's field list — with client-side rendered-evidence routing. Backend-only closure without that recorded consumer check is invalid.

## Generalization Discipline

- Implement the repo in front of you, but do not import product nouns, service names, package paths, provider names, IDs, dashboards, or organization-specific habits from prior codebases.
- Convert domain-specific source patterns into reusable mechanics: handler shape, contract evolution, repository pattern, transaction boundary, cache key strategy, idempotency, job lease, config, observability, or test style.
- If an observed pattern only works for one product domain, discard it instead of turning it into a rule.
- Resolve conflicts by choosing the safer generic default: explicit contracts over hidden conventions, DB constraints over cache-only correctness, typed config over ad hoc strings, idempotent consumers over retry-only consumers, focused unit tests over live-infra tests by default, and fail-closed for auth/permission/data-integrity paths.
- Fuse patterns only when both are product-agnostic and reduce implementation ambiguity; otherwise keep the simpler rule.
- When adding or revising durable Go implementation guidance, check whether the lesson is generic backend service practice that should also update `python-service-dev`, or belongs in a shared workflow skill instead. If the rule depends on Go tooling, protobuf/Kitex/Hertz, Go concurrency, or Go package layout, keep it here and do not force a Python mirror.
- Example: if an existing project uses inline Redis keys but another wraps keys in typed builders, implement typed builders and discard inline string formatting as a reusable pattern.

## Development Workflow

Before editing code, generated files, migrations, configs, or tests, complete enough analysis and planning for the change to be reviewable. Scale the plan to risk: a simple low-risk single-package change can use a short inline plan; multi-file, contract-visible, data/schema, async, release, bug-fix, branch/MR, unclear-risk, or high-risk work needs explicit task split, acceptance checks, verification commands, rollback or stop conditions, and named handoffs to architecture, testing, or diagnosis skills before edits.

Repo-local agent contracts (`AGENTS.md` at the repo root and in source directories) are part of the delivery contract: when a change moves a stable boundary, generated surface, workflow, or directory-local rule, update the nearest contract in the same MR and keep coverage in sync per `product-rd-workflow`'s spec / repo-contract sync gate (tooling: `references/developer-tooling-patterns.md`).

1. Establish the target service shape.
   - Is this an HTTP API, internal RPC, worker/consumer, scheduled task, command-line tool, or shared library?
   - For internal service-to-service calls, use RPC/gRPC by default and HTTP when the service contract chooses it. Do not treat HTTP as a local shortcut: use the repository/platform HTTP client wrappers for discovery, auth, deadlines, retries, logging, metrics, tracing, and contract tests.
   - Also classify SDK/tooling, generated-contract packages, and demo/test modules; do not treat every `go.mod`, `cmd/*`, or unfamiliar directory-naming/build-target convention as a deployable RPC service.
   - Identify the nearest `go.mod`, service entrypoint, config files, IDL, generated code, DI setup, and test commands.
   - When mining a local/internal reference tree for Go implementation patterns, first detect nested git repositories, submodules, and implementation-bearing non-default branches or tags before judging the tree empty. Prefer read-only tree inspection over switching branches, and record the reusable mechanism rather than the source branch, module, or path.
   - Check whether tests are split into fast unit tests and infrastructure-dependent integration tests.

2. Start from contracts and data.
   - Update protobuf IDL before changing request/response shape.
   - For new or contract-visible services, confirm the globally unique service name, IDL source location, generation command, and generated artifact version before implementing handlers or service logic. Prefer consuming generated contract packages from the contract/generation boundary. When shared IDL and IDLGen repositories exist, Go implementation must use the generated Go artifacts from that shared boundary and keep compatibility with Python and client-side consumers; do not create service-local private IDL copies that drift from the shared contract.
   - For protobuf-backed HTTP, confirm whether protobuf is only the contract source or also the binary wire format. For a new protobuf-backed HTTP surface, record the source/config/test location for the generator, route annotations, JSON/binary content-type policy, protobuf-generated clients, middleware order, error/envelope mapping, and compatibility tests before writing handlers. For modifications, confirm only the touched items; an additive non-wire claim must cite the out-of-scope evidence required by `../platform-service-connectivity/references/protobuf-http-contract-signals.md`. Without that cited evidence, the touched item is a blocker, not an additive pass.
   - Implement JSON-wire business API responses through the contract-recorded envelope per `../platform-service-connectivity/references/http-response-envelope-contract.md`; when the canonical envelope applies, map domain errors to the canonical `code`/`message` model at the transport boundary and do not return ad hoc top-level business fields from handlers.
   - Select the transport contract first — the carrier is scenario-driven per the Carrier decision in `../platform-service-connectivity/references/rpc-framework-recipe.md`: on a platform that has standardized the in-message `base` carrier (or a contract that declares/publishes `base`), apply the recipe's ordered base-field gate as the single source of truth; on a metadata-carrier service (the default for ordinary gRPC), apply the R7 owner-recorded header-set gate (`../platform-service-connectivity/SKILL.md` R7) instead. Boundary-exposure classification (canonical trigger set, rerun conditions, dispositions) and the implementation population check are canonical in the same recipe; when any canonical boundary trigger fires, run boundary-exposure classification before release per that recipe — missing or contradictory classification evidence is an open release gap, and authz on unauthenticated caller-supplied identity is an immediate blocking implementation finding. Go service diffs cite the recipe evidence for the touched edit kind; service-authored proto snippets, service-local copied descriptors, uncited provenance claims, stale/wrong-version descriptors, or broad tag claims cannot self-certify the shared contract.
   - Handler, adapter, or DTO diffs that manually construct generated request/response DTOs outside the middleware-filled path, or write/mutate/overwrite `base`, `LogId`, caller, `From`, `To`, `Tags`, or equivalent identity fields on generated DTOs, apply the implementation population check in `../platform-service-connectivity/references/rpc-framework-recipe.md` (carrier-neutral — it runs even when the base-field gate is not applicable); missing evidence is an open implementation gap.
   - Use generated request/response/common-field types where they exist. If domain or persistence models differ from transport DTOs, map them explicitly at the transport/application boundary; do not let generated API DTOs leak into domain code unless the architecture record makes them the public application contract.
   - Define DB schema/model changes before DAL code. New Go MySQL services use GORM behind DAL/repository boundaries by default unless the repo already standardizes or conventionally uses another query layer, or the architecture records a deliberate alternative.
   - Define Redis keys, TTLs, and idempotency/lock semantics before cache code.
   - Define MQ topics/events, retry behavior, and idempotency before consumers.
   - Define runtime config, health/readiness behavior, deploy metadata, traffic/canary switches, and rollback controls before release-facing code.

3. Keep layers clean.
   - Transport layer: protocol mapping, validation, auth context, response mapping.
   - Application/service layer: use-case orchestration and transactions.
   - Domain layer: domain rules and invariants.
   - Infrastructure layer: DB, Redis, MQ, RPC/HTTP clients, object storage, third-party APIs.
   - Generated code: never hand-edit unless explicitly repairing generated output.

4. Wire dependencies explicitly.
   - Constructors should declare what they need.
   - Prefer small interfaces at boundaries where tests or adapters matter.
   - Update DI provider sets and regenerate generated DI output if the repo uses it.
   - Keep production and test dependency graphs separate when infrastructure clients need fakes.
   - Reuse the repository's runtime wrappers for RPC/HTTP servers, clients, DB, Redis, MQ, logs, metrics, tracing, config, and service discovery before adding local one-off clients.
   - If a mature internal reference has stronger wrappers than the target repo, reuse existing target-repo wrappers first. When no wrapper exists, add the smallest local adapter that the current task justifies, or route platform-wide wrapper extraction to architecture/platform skills before implementation. Do not paste reference business code or private package layout; preserve only the generic contract, such as `Tx(ctx, fn)`, typed config client, MQ producer/consumer wrapper, context injector, error mapper, or query-safety hook. Safety-critical fragments — recover wrappers, timeout enforcement, untrusted-input decoding — must be a single shared implementation even at a dozen lines; a per-adapter copy that drifts fails as a process crash or a silent no-op, not as slowness.
   - If the implementation task directly mines an internal checkout, private repository, local path, or organization project, apply the same sanitization gate before landing any artifact: keep only mechanisms and generic contracts; remove source-identifying domains, paths, repository/module names, people, tickets, and business nouns.

5. Verify at the right scope.
   - Run focused unit tests for changed packages.
   - Run integration-ish tests for DB/Redis/MQ wrappers only when environment is available.
   - **TC traceability**: link tests via `tc.Mark(t, "TC-XX-NNN")` (helper from `test-artifact-management/references/tc_helpers/tc.go`, installed under `internal/testkit/tc/`).
     - **`tc.Mark` MUST be the first non-comment line in the test body, BEFORE any `t.Skip` / `t.Skipf` / setup that may call `t.Fatal`** — otherwise the sidecar entry won't be written for skipped tests.
     - See `test-artifact-management/references/tc-marker-conventions.md`.
     - Before adding tests, `grep -rn 'tc\.Mark.*"TC-[A-Z]' .` plus the sidecar `test/results/tc-map.jsonl` to check for existing coverage — extend rather than duplicate.
     - When a TC is marked 废弃, grep both source and sidecar for that TC ID; follow deprecation cascade and orphan rules in `testing-strategy`.
     - Tests without `tc.Mark` calls: prompt user only when the underlying code is also removed.
   - **废弃级联：业务代码是否仍在用** — Go 用 `go list` 拿真实导入图，不依赖手 grep：
     1. 看测试文件导入的产品包：`go list -f '{{join .TestImports "\n"}}{{"\n"}}{{join .XTestImports "\n"}}' ./internal/foo/`
     2. 对每个产品包，查谁还在 import：`go list -f '{{.ImportPath}}: {{join .Imports " "}}' ./... | grep "<pkg-path>"`
     3. 只剩本测试 import → 同 commit 删 pkg + 测试；其他产品代码仍 import → 测试目标在用，不删
     4. 边界：`go:build` tag 受限的 import 默认看不到，用对应 tag 跑 `go list`；反射 / interface 实现注册（`init()` 注册到全局 map）grep 抓不到，得运行时验证或人工确认
   - Run codegen and formatting when generated inputs changed.
   - Keep fast tests deterministic; isolate tests that need live infrastructure, long sleeps, generated files, or external credentials.

## Implementation Rules

- Pass `context.Context` through all external calls. The carve-out is narrow and behavioral: only a function that is and stays side-effect-free — no external calls, goroutines, filesystem/env, clock/random, or logging/trace/tenant/feature lookup across its body and callees — may omit `ctx`. A mapper or helper that does, or later gains, any such call takes `ctx`. "ctx on external calls" is not "ctx on every function", but the test is behavior, not the name.
- Set timeouts for RPC/HTTP/DB/Redis/MQ operations.
- Honor an existing context deadline when it is shorter than the local default timeout.
- Separate short serving-path request timeouts from longer admin, migration, bootstrap, and repair-operation timeouts. Do not reuse a sub-second request timeout for synchronous dependency setup, index builds, resource activation, schema creation, or other startup administration.
- Use one canonical error model and convert errors at transport boundaries.
- Add or preserve trace/log id in inbound, outbound, and async execution paths.
- MQ producers and consumers should preserve request context where possible, define retry/drop/dead-letter/alert behavior explicitly, and not return success after business failure unless the drop policy is deliberate and observable.
- MQ producer/consumer wrappers should centralize metadata propagation, topic/tag/filter config, worker sizing, retry/drop behavior, panic recovery, close/drain lifecycle, latency/error metrics, and replay or DLQ visibility. Business handlers should implement domain work and idempotency, not recreate consumer scaffolding.
- Use read/write DB separation if the service stack provides it.
- Use transactions for multi-step writes inside one database.
- Keep GORM/sqlx/raw SQL behind DAL or repository modules; handlers and application services should call intent-focused repository methods, not construct queries directly.
- When referencing an existing codebase or platform pattern, match the core abstraction shape, not just the concept. For example, if the reference stack exposes `Tx(ctx, fn)` plus transaction-scoped repository accessors or factories, add or reuse the same kind of platform/DAL helper instead of hand-writing `Begin/Commit/Rollback` or raw `tx.ExecContext` blocks in business code.
- Keep database read/write routing and transaction ownership in the shared DB/platform layer when the repository already has one. Business repositories should call the unified transaction interface and should not duplicate commit/rollback templates unless no shared primitive exists yet.
- For DB-heavy services, prefer shared transaction helpers that recover/rollback on panic or error, and add non-production query-safety checks where the repo has ORM hooks, query builders, migration metadata, or test infrastructure to support them. If the repo cannot mechanically check missing indexes or full scans yet, record the platform gap and cover changed high-risk queries with DDL/DAL review evidence, bounded pagination assertions, or focused tests. These checks should become framework or DAL behavior, not reviewer folklore.
- For DB changes, keep DDL, generated model/query/updater/DAL output, and migration/rollback notes together.
- Before adding a DB index migration, inspect existing and final active migration indexes for the same table/column/order signature, including older migrations and later drops. If the repo has migration metadata or tests, add or extend a deterministic duplicate-index guard so redundant indexes are caught mechanically instead of by review memory.
- Treat MQ delivery as at-least-once; consumers must be idempotent.
- Treat write retries as unsafe by default. Add automatic retry only when the operation has a durable idempotency key, unique constraint, state machine, dedupe table, or equivalent proof, and test duplicate submit/callback/MQ/job-restart behavior.
- For money, quota, entitlement, permission, tenant/user isolation, privacy, and sensitive state changes, fail closed on uncertainty and return the canonical error before side effects.
- Do not default missing tenant, actor, subject, or resource scope on high-risk paths. Reject before side effects unless the code is an explicit bootstrap, seed, or maintenance path with separate approval.
- Do not rely on Redis-only, TTL-only, memory-only, or process-local dedupe for durable side effects. Use persistent idempotency or a state machine when the side effect is auditable, billable, externally acknowledged, or hard to reverse.
- Commit primary mutations with audit/outbox/governance evidence in one transaction when possible. If not possible, create a replayable repair record, surface stale/pending counts, and test the reconciliation gap.
- For high-risk user-visible operations, persist or return a stable request/task/order/support identifier and keep logs, audit records, or metrics sufficient for support explanation and compensation.
- Use Redis locks with unique values and compare-and-delete unlock.
- Centralize Redis keys, TTLs, lock leases, counters, and rate-limit scopes in typed cache/coordination adapters.
- Keep config typed and environment-specific.
- Keep generated code reproducible with documented commands.
- For scheduled jobs, implement distributed lock, max execution time, retry/backoff, panic recovery, and clear retry-vs-skip behavior.
- For streaming or long-running generated-content flows, persist explicit state transitions: waiting/running, partial output when useful, timeout, cancellation, provider error, success/EOF, cost/usage recorded, and repair/alert when persistence fails. Close stream readers and reject conflicting concurrent work when the product state machine requires single-flight behavior.
- For high-risk config, add typed fields, production-safe defaults, tests for disabled/missing config, and explicit enablement checks before behavior can run.
- For external stateful dependency bootstrap, make the operation idempotent and self-healing: validate existing resources, repair missing sub-resources such as indexes or queues when safe, then activate or load the resource. Do not stop at an `exists` check when a prior partial failure could leave the resource unusable.
- Comments state invariants and why, not status snapshots that rot ("X is the only implementation", line counts, "temporary tool"). A comment claiming a guarantee the code does not provide (e.g. a per-attempt timeout that is never actually set) is worse than no comment; in review, treat every guarantee a comment claims as an assertion to verify against the code.
- Code that will live in production must not carry temporariness-implying names (spike/minimal/temp). Transitional scaffolding must state its retirement condition and expected retirement point explicitly, or it is not transitional.
- When bumping a shared dependency's version, change it across **every** consuming module in the repo, not only the obviously-affected ones — including indirect consumers that reach the dependency through a local `replace => ../x` or that independently pin the same transitive dependency. Bump and `go mod tidy` each module to a consistent version, then run the **full** suite (`go test ./...` in every touched module, not just the directly-related one) and update any test that hard-asserts the dependency pin/version. A module left on the old pin makes its module graph inconsistent and typically fails only later — often surfacing as a CI dependency-fetch error that masks the real version mismatch. Separately, a local `replace => ../sibling` makes the stale-`require` failure class invisible to EVERY in-repo build and test (they all resolve through the replace), while external consumers resolve the real pinned version (`replace` is ignored outside the defining module) — so a module whose pinned sibling tag predates symbols it now uses publishes a tag that compiles everywhere internally and fails only for external importers. Before tagging a module in a multi-module repo that uses local `replace`, verify it from the external-consumer view: build from OUTSIDE the repo so the repo's own `replace` directives cannot apply — `replace` only takes effect in the main module being built, and `GOWORK=off` alone does NOT neutralize a replace in the module's own `go.mod` — and the passing gate must cover EVERY package of the candidate module — from a throwaway consumer that means building the candidate's import-path set (`go build <candidate-module>/...`; a bare `go build ./...` there builds only the consumer's own packages), with the consumer binding the unpublished candidate via a single `replace` to the candidate checkout ONLY while sibling deps resolve to published tags (confirm with `go list -m all`); from a verification checkout (local `replace` directives stripped/neutralized) it means `go build ./...` in the candidate — a broken symbol in one subpackage still publishes a broken tag. A checkout that keeps `replace` with the sibling directory present resolves locally and silently passes; one that keeps `replace` with the path absent merely fails on the missing directory even when the pins are correct (a negative control proving the replace would have applied — not a passing gate); the in-repo full suite can never catch this class. When siblings release together and a dependent needs the sibling's NEW tag, release in topological order: tag and push the dependency first, then verify the dependent's candidate the same consumer-view way (checkout outside the sibling layout, replaces stripped, building against the published dependency tag), then tag the dependent (a dependency cycle between modules stops for the release owner to break).

## Reference Loading

- For source provenance, current extraction boundary, and keep/merge/discard decisions, read `references/source-evidence-map.md` when auditing or re-extracting this skill.
- For feature implementation steps, read `references/feature-playbook.md`.
- For generated code, DB, Redis, MQ, and testing patterns, read `references/engineering-patterns.md`.
- For reliability, context, error handling, async jobs, and external calls, read `references/reliability-patterns.md`.
- For service setup, codegen commands, DI wiring, and test-target hygiene, read `references/scaffold-and-codegen.md`.
- For protobuf/IDL implementation, field numbering, enum/message patterns, generation commands, and compatibility tests, read `references/protobuf-contract-patterns.md`.
- For secret clients, service discovery clients, object storage, external HTTP clients, bounded concurrency, and dependency adapters, read `references/dependency-client-patterns.md`.
- For handler/service/DAL feature work, validation, transactions, pagination, and side effects, read `references/domain-feature-patterns.md`.
- For data access, local/Redis cache, locks, idempotency, and query design, read `references/data-access-patterns.md`.
- For public API auth, external app credentials, authorization-scope checks, callback verification, and audit behavior, read `references/public-api-integration-patterns.md`.
- For HTTP gateway handlers, generated route files, middleware hooks, request binding, response mapping, and generated HTTP clients, read `references/http-gateway-client-patterns.md`.
- For release-facing code, deployment config, health endpoints, canary checks, traffic config, approval tasks, and operations notifications, read `references/release-ops-patterns.md`.
- For test strategy, fakes/mocks, traffic replay, generated-output tests, and CI quality gates, read `references/quality-and-testing-patterns.md`.
- For cross-stack unit/integration/E2E test layer selection, fixtures, flake control, and CI gate design, use `testing-strategy`.
- For runtime middleware, context propagation, service discovery clients, logs, metrics, tracing, and request/response logging controls, read `references/observability-implementation-patterns.md`.
- For DDL-first DB implementation, generated models/DAL, sharding-safe queries, migrations, and transaction tests, read `references/db-schema-and-dal-patterns.md`.
- For Redis clients, key builders, local/distributed cache, CAS scripts, locks, rate limiting, counters, and task queues, read `references/redis-cache-lock-patterns.md`.
- For spreadsheet, CSV, file import/export jobs, row validation, slice processing, and error reports, read `references/bulk-import-export-patterns.md`.
- For durable task state machines, allowed transitions, duplicate delivery, retries, and terminal-state behavior, read `references/state-machine-task-patterns.md`.
- For MQ consumers, producers, typed payload decoding, dynamic activation, pre-handling, retry/drop behavior, and latency alerts, read `references/mq-consumer-patterns.md`.
- For audit logs, history records, redaction, async writes, and query APIs, read `references/audit-history-patterns.md`.
- For dynamic config schemas, rule validation, condition evaluation, routing, and rollout ratios, read `references/config-rule-routing-patterns.md`.
- For replay, shadow execution, response comparison, diff scoring, and replay result storage, read `references/replay-comparison-patterns.md`.
- For bounded concurrency, batch jobs, replay/shadow workers, DB performance guards, and stuck-task repair, read `references/performance-capacity-patterns.md`.
- For webhook or notification clients, templates, async delivery, retries, and alert throttling, read `references/notification-patterns.md`.
- For generated spreadsheets, PDFs, CSVs, reports, object upload, and download artifacts, read `references/artifact-generation-patterns.md`.
- For canonical errors, response builders, error wrapping, validation errors, and transport mapping, read `references/error-contract-patterns.md`.
- For developer CLIs, generators, DDL-to-model generation, generated file safety, and command tests, read `references/developer-tooling-patterns.md`.
