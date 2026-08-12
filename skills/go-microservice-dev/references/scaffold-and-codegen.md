# Scaffold And Codegen

## New Service Checklist

- Create or locate the service module and entrypoint.
- Add `proto/` or `idl/` source contracts before generated stubs.
- Add typed config structs and sample environment config.
- Add production DI providers for config, DB, Redis, MQ, RPC/HTTP clients, service logic, handlers, and workers.
- Add a test DI graph or lightweight constructors for tests.
- Add Makefile or script targets for:
  - protobuf/IDL generation.
  - HTTP route/docs generation when used.
  - DB model/DAL generation when used.
  - DI generation.
  - fast tests.
  - integration tests.

## Entrypoint And Runtime Setup

- Build servers from explicit options plus middleware lists; let caller-provided options override defaults intentionally.
- A common middleware order is context injection, recovery/error mapping, tracing, authentication/authorization, metrics/logging, then domain routes. Recovery MUST wrap auth and validation: a panic in session/token parsing without recovery wrapped around it either drops the connection or crashes the process depending on framework. Adapt only when the framework's wrapper semantics enforce a different order — and verify the panic-catch coverage explicitly.
- Register health/readiness, debug, profiling, and docs routes in one place so exposure rules are reviewable.
- Keep debug/profiling and generated docs behind environment, network, or auth gates when deployed outside local development.
- Return a cleanup function or closer list from server construction and call it from signal/shutdown handling.
- Close resources in shutdown order: stop traffic, wait for in-flight requests up to a deadline, stop consumers/workers/schedulers, close dependency clients, then flush logs/metrics/traces.
- Prefer `time.NewTicker` with `Stop` over `time.Tick` in long-lived runtime code. Stop every timer/ticker you own; when `time.Timer.Stop` returns false and the channel may already hold a tick, drain it with a non-blocking `select`+`default` before reuse so a stale fire cannot trigger later logic — never a bare blocking `<-timer.C` (another goroutine may already have consumed the tick, and a blocking drain then hangs shutdown). This drain applies only to channel timers whose channel this goroutine owns; `time.AfterFunc` has no channel to drain — and a bare atomic flag is not enough (the callback can read the flag before the terminal path sets it and still fire late): the callback must re-check the terminal/generation state under the same lock or CAS that guards its side effect (or use a generation token / done-channel the terminal path waits on) before acting.
- Tests for server setup should assert middleware presence, route exposure rules, and cleanup invocation where practical.

## Portable Commands

- Prefer repo-relative paths.
- If a generator needs a root path, derive it from the current repo or an environment variable.
- Do not commit commands containing a developer's local home directory.
- Do not bake one organization's import root into a reusable generator; pass module path, IDL path, output path, and package mapping as parameters.
- Keep generated inputs and outputs in the same change.
- If a generated file changes unexpectedly, inspect the generator version and input diff before accepting churn.

## Protobuf Contract Rules

- For detailed protobuf definition, generation, and compatibility rules, apply `protobuf-contract-patterns.md`.
- Keep source `.proto`, generated output, handler updates, and contract tests in the same change when the contract changes.
- Keep HTTP mapping annotations and field binding annotations close to the IDL method or field they describe.

## DI Provider Pattern

- Group providers by concern: base, DAL, cache, RPC/HTTP clients, services, tasks, handlers, and test graph.
- Aggregate related dependencies into explicit structs only at module boundaries.
- Avoid global initialization in application code; initialize clients in providers.
- Regenerate DI output after provider-set changes.
- Compile the service after DI generation before moving to behavior tests.
- For non-trivial services, prefer layered DI sets (e.g., `inject/infra` → `inject/service` → `inject/logic` → top-level `inject/`) where each set depends only on lower layers; the aggregate at each layer (`AllInfra`, `AllService`, `AllLogic`) is an embed-friendly struct that the next layer can compose without re-declaring providers.

## Kitex / RPC Client Wrapper

- Wrap framework-native client constructors behind a generic helper such as `NewClient[T](psm, ctor, opts...)` so callers cannot accidentally instantiate per-request or with inconsistent option sets. The helper composes a shared default option set (resolver, meta handler, tracing suite, middleware chain) with caller-supplied overrides.
- Caller-supplied options must override the helper's defaults, not the other way around — append them after the defaults in the option slice. Document this precedence so reviewers can verify which side wins.
- Construct each RPC client exactly once per process and inject via DI. `sync.Once` plus a package-level container or a Wire-generated provider both work; avoid plain package-level vars initialized from `init()` because they hide error handling.
- The wrapper assembles the client middleware chain in a fixed order so observability and error handling cannot be silently reordered. A common order: error handler → metrics → caller-identity injection → context/log-id injection → request/response logging.
- For Kitex specifically, pick the meta handler by transport protocol exclusively: HTTP/2 meta handler for gRPC, TTHeader meta handler for Thrift. Do not register both; do not switch at request time.
- **Kitex v0.13 (released 2025-04-07) baseline shifts to track**: (a) `StreamX` now supports gRPC alongside the existing TTHeader Streaming, so a server can be compatible with both streaming protocols simultaneously — pick StreamX for new streaming code and let the server keep multi-protocol compatibility during migration; (b) **default Thrift transport protocol changed from `Buffered` to `Framed` to leverage FastCodec — this is a wire-format change, NOT a negotiation**: a v0.13 client built with default options sending Framed frames to an older Kitex server still on Buffered (PurePayload) will fail before useful RPC traffic, not gracefully downgrade. Upgrade discipline: either upgrade ALL participating services in one rollout window, OR explicitly pin the new client back to `PurePayload` (transport.PurePayload) via client option during the rolling-upgrade interval until every callee is on v0.13. Verify the same on `Framed` server returning to a `Buffered` client. Treat the transport-default flip as a wire-compat break that needs a versioned-upgrade plan, not a default-flag bump; (c) Kitex Tool by default stopped generating repeated `Set` validation code and `DeepEqual` functions (smaller generated output) and disabled Apache Codec generation by default — if any business code depended on those generator outputs, the upgrade will fail to compile until those usages are removed or the generator flags are re-enabled; (d) Go version support is 1.19–1.24, so Kitex services on Go 1.25 should validate framework compatibility before upgrading toolchain. Treat any Kitex minor-version bump as an architecture change: read CloudWeGo release notes, run the protocol-default check + the wire-compat fan-in/fan-out matrix, and rerun integration tests against any sibling service still on the prior version.

## Server Wrapper And Option Precedence

- Server constructors should expose a default-options helper and accept caller-supplied options that override defaults. Common defaults: server basic info, service address, meta handler, registry, tracing suite, error handler, the standard middleware chain.
- Registry registration is environment-conditional, not unconditional. Register only when running in an environment that the platform layer expects to discover this instance (typically online / canary / lane environments), not in local-dev or short-lived test environments.
- Return both the cleanup function (`func()`) and the closer list (`[]io.Closer`) from server construction so signal handlers can drive deterministic shutdown.

## Generated DB Model Pattern

- Generate table constants, struct fields, `TableName`, updatable column lists, query helpers, and update helpers from DDL when available.
- Keep unique/primary/index constraints represented in query helpers where the generator supports it.
- Exclude immutable columns such as create-time, creator, primary key, and unique key columns from generic update helpers.
- Do not hide unsafe raw SQL behind generated helpers; add explicit DAL methods for complex queries.
- Parse DDL with a real SQL parser instead of regular expressions.
- Refuse to overwrite hand-maintained DAL files unless the caller explicitly asks for regeneration.
- Format generated Go files and fail the command if formatting or import resolution fails.
- Keep sharding keys and read/write routing explicit in generated query helpers when the stack supports them.

## HTTP Docs And Route Generation

- For detailed HTTP gateway, generated route, handler, middleware, and generated client rules, apply `http-gateway-client-patterns.md`.
- Route generation and API docs should derive from source contracts or handler annotations, not duplicated hand-written tables.
- Remove stale generated comments before writing new generated comments.
- Keep route method/path annotations close to the handler or IDL method they describe.
- Run formatter and docs generator after patching annotations.
- If a handler signature does not match the generator pattern, fail visibly rather than generating partial docs.
