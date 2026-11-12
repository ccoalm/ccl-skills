# Service Scaffold

## Required Surfaces

A new service should make these surfaces explicit from the first useful version:

- `go.mod` and module ownership.
- Entrypoints for API, RPC, worker, and scheduled jobs as applicable.
- `proto/` or `idl/` source contracts.
- Generated contract output directory.
- `config/` with typed structs and environment overlays.
- `handler/`, `service/` or `logic/`, `domain/`, and `infra/` boundaries.
- `infra/dal`, `infra/cache`, `infra/rpc`, `infra/mq`, and external clients as needed.
- DI setup for production and tests.
- Makefile or scripts for code generation, tests, lint/format, and local run.

## Runtime Lifecycle

- Entrypoints should return or register a cleanup function for servers, tracer providers, metrics exporters, log writers, DB pools, Redis clients, MQ clients, and background workers.
- Startup should install middleware in a deterministic order, with context/identity established before authorization and recovery/error mapping wrapping domain handlers.
- Shutdown should stop accepting traffic before closing dependency clients and should flush logs/metrics after worker shutdown.
- Graceful shutdown needs an in-flight draining deadline and a forced-close policy after that deadline.
- Health endpoints should be available early, but readiness should only pass after required config, secrets, service discovery, and critical clients are initialized.
- Debug, profiling, and generated-doc endpoints must be internal-only, auth-gated, or disabled in production-facing environments.
- Avoid background loops that cannot be stopped; every ticker, watcher, scheduler, and worker pool needs an owner and close path.

## Code Generation Contract

- Treat IDL, DB DDL, route docs, and DI provider declarations as source inputs.
- Treat generated stubs, route files, model helpers, query builders, and DI output as generated outputs.
- Every generator should have one documented command.
- Commands must use repo-relative paths or environment variables, not personal absolute paths.
- Generated files should carry a clear generated-file convention and should not be hand-edited during feature work.
- When a generator is unavailable, record the exception in the change and keep the manual patch minimal.

## Dependency Injection

Organize providers by concern:

- base: config, logger, metrics, secret clients, object storage, generic clients.
- dal: DB proxy and table-specific repositories.
- cache: Redis client, key builders, locks, rate limiters.
- rpc/http clients: internal service clients and external API clients.
- service/application: use-case services and orchestrators.
- task/worker: async task handlers, scheduled jobs, backfill jobs.
- transport: HTTP handlers or RPC service implementation.
- test: a test application graph with fakes or local adapters.

Keep DI output reproducible. Do not construct hidden global dependencies inside domain logic when a provider can declare them.

## Config Shape

- Use typed config structs for service-specific settings.
- Separate static defaults from dynamic config.
- Include timeout, retry, worker count, lock lease, object storage, DB, Redis, MQ, and external client settings where relevant.
- Validate required config at startup.
- Never put credentials directly into config; resolve via a secret provider.

## Test Architecture

- Fast tests should not require live DB, Redis, MQ, service discovery, or cloud credentials.
- Integration tests that require live dependencies should be opt-in with tags, environment variables, or separate make targets.
- Provide fakes for external RPC/HTTP clients and repositories where domain behavior can be tested without infrastructure.
- Include at least one smoke test for DI wiring when the graph is non-trivial.

## Option Precedence And Protocol Selection

- Server and client constructors should expose default-options helpers and accept caller overrides that win on conflict. Document the precedence (caller appended after defaults wins) so framework defaults can be tightened over time without surprise breakage in services that have already chosen a different setting.
- Pick the meta handler (or equivalent transport-attached metadata propagator) by transport protocol exclusively — gRPC and Thrift do not share one handler, even when the framework allows registering both. Architecture chooses the protocol per service; the binary should not switch at request time.
- Conditional registry registration is an architecture decision, not a default: register at startup only when running in an environment the platform layer is meant to discover (online / canary / lane environments). Local-dev, short-lived test, and migration binaries must not register, or the directory pollutes.

## Layered Aggregates And DI Composition

- For non-trivial services, model the layered surface as embedded aggregates: `AllInfra` (config + DAL + cache + RPC/HTTP clients + MQ + external SDKs), `AllService` (use-case services that depend only on `AllInfra`), `AllLogic` (orchestrators that depend on `AllService` + may reach `AllInfra` for low-level access), and a top-level `Application` (handlers + workers + consumers).
- Wire-style DI maps cleanly: one `inject/infra` provider set, one `inject/service`, one `inject/logic`, and a top-level `inject` that composes them. Dependencies always point downward; never let `inject/infra` import from `inject/service`.
- Embedded aggregates are a convenience for composition, not for hiding dependencies. A service that needs DAL access should still depend on the specific repository interface, not on `AllInfra` directly, except at the composition root.
