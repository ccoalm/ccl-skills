# Engineering Patterns

## Repo Layout

Recommended layout for a new service:

```text
cmd/ or main.go
conf/
idl/ or proto/
handler/
service/ or logic/
domain/
infra/
  dal/
  cache/
  rpc/
  mq/
model/
inject/ or internal/di/
tests/
```

Use the existing repo's layout when one already exists.

When a layering boundary must actually hold — e.g. the core domain must never import infra or heavy SDK dependencies — consider giving that layer its own Go module: a module whose `go.mod` physically lacks the dependency turns a violation into a compile error, which is strictly harder to bypass than import-lint or review convention. Reserve this for boundaries worth the extra module/versioning overhead.

## Code Generation

- IDL/protobuf generates RPC/HTTP contracts and stubs.
- DB DDL can generate model/query/updater/DAL helpers if the project has a generator.
- DI code can be generated from provider declarations.
- Swagger/OpenAPI annotations can be generated from handlers or contracts.

Rules:

- Keep source inputs and generated outputs in the same change.
- Document commands in Makefile, README, or scripts.
- Use repo-relative paths; do not commit generator commands with personal absolute paths.
- Do not patch generated files manually unless the generator is unavailable and the risk is accepted.
- When a repo uses multiple generators, identify the source of truth for IDL/routes, DB models/query helpers, and DI output before editing; update source inputs first, then regenerate outputs.

## DB Pattern

- DAL exposes intent-focused methods, not raw query fragments everywhere.
- Query builder/updater helpers are useful when they prevent unsafe ad hoc SQL.
- Use `R(ctx)` for reads and `W(ctx)` for writes when supported.
- Configure connection pool, read/write resolver, tracing, and query logger at DB proxy initialization.
- Treat sharding as a first-class DB concern: define shard key, shard count, DDL behavior, and bypass rules explicitly.
- Use transactions for multi-step writes and recover/rollback on panic.
- Apply the detailed DAL guardrails in `data-access-patterns.md` for list bounds, update/delete conditions, explicit update columns, and upsert column selection.

## Redis Pattern

- Key format should be deterministic and centralized.
- TTL must be explicit for every cache key.
- Cache miss should be distinguishable from infrastructure failure.
- Locks must use unique values and safe unlock.
- Lua/CAS scripts are appropriate for compound atomic operations.
- Script-backed helpers should handle script-cache misses by reloading or falling back according to the client contract, and tests should cover missing-key, compare-failed, and invalid-return paths.

## MQ Pattern

- Event names should describe domain facts, not implementation steps.
- Producers attach trace/log metadata where the stack supports it.
- Producers should use bounded send context and document sync, async, or one-way semantics.
- Consumers must tolerate duplicate, delayed, and out-of-order messages unless ordering is guaranteed and configured.
- Handler return value should intentionally control retry vs skip.
- Consumer config should make worker count, broadcast vs cluster mode, retry count, ordering, topic, and tag/filter expression explicit.

## Tests

- Table-driven unit tests for domain logic, pure helpers, validation, and DAL query options.
- Component tests for DB/Redis/MQ wrappers when the local environment is available.
- Fake clients for RPC/HTTP integrations, including timeout, dependency error, and non-OK domain status.
- Contract tests for protobuf default values, enum handling, and response error mapping.
- Handler/service scenario tests for request mapping, auth context, resource-scope context, and response codes.
- Consumer tests for duplicate message and retry/skip decisions.
- Scheduled job tests for lock acquisition failure, timeout, retry exhaustion, and panic recovery.
- Build/codegen verification when IDL, generated code, or DI changes.
- Keep infrastructure-dependent tests out of the default fast test path unless the local environment is guaranteed.

## Middleware Pattern

- Inbound middleware should create or accept a trace/log id, attach it to context, and return it to the caller when the protocol supports it.
- Request and response body logging should be gated by config and environment.
- Recovery middleware should log panic stack, return canonical internal/panic error, and increment panic metrics.
- Metrics middleware should record QPS, latency, success, error, and canonical error code for both server and client sides.
- Auth middleware should populate typed context values; application code should not parse tokens or cookies directly.

## Error Handling Pattern

- Domain/application code returns typed or wrapped errors with stable canonical codes.
- Transport code converts canonical errors into HTTP/RPC responses.
- Client middleware converts remote canonical errors back into local errors so callers can branch on code.
- When a dependency or helper returns an explicit status/envelope, callers must branch on success or error before reading optional result fields; never assume success from a nil error alone when the contract carries domain status separately.
- Unknown errors default to internal/dependency failure and must be logged with context.
- Validation errors should be permanent; dependency timeouts and unavailable errors may be retryable depending on operation idempotency.

## Context Key Convention And Metainfo Propagation

The set of ctx keys a service relies on is part of the service's public surface; treat it as deliberately designed, not ad hoc.

- Organize ctx keys in tiers by trust and lifetime: global keys that travel with every request (trace/log id, PSM, lane, IDC, cluster, stress tag); API-context keys derived from the gateway after auth (user id, tenant id, organization id, role); raw header keys mapping inbound `X-*` HTTP headers to their canonical ctx name. Document the tier in code (separate const blocks or files) so reviewers can see which keys are platform-level vs business-level.
- Define a typed accessor per ctx key: a function `LogIDFromCtx(ctx) string` that performs the type assertion is safer than asking callers to remember `ctx.Value("logId").(string)`. Bare string-key access returning `any` is acceptable only for short-lived experiments; production code should hide the assertion behind typed helpers.
- For Kitex-style frameworks that must propagate ctx values both inside the binary and across the wire, dual-inject: write the value to `metainfo.WithPersistentValue(ctx, key)` for cross-hop persistence and to the framework-specific outgoing metadata (HTTP/2 metadata for gRPC, TTHeader for Thrift). The framework's `MetaHandler` chosen at server-build time determines which transport carries it; the application code remains transport-agnostic.
- Distinguish "persistent" metainfo (forwarded on every downstream hop) from "transient" metainfo (one hop only). Lane, stress tag, and trace identity are persistent; one-off control flags should be transient or moved to typed request fields.
- For HTTP gateways, define the mapping between inbound `X-*` headers and ctx keys once, in a binding step at the edge; do not re-read raw headers in domain code.

## Go Language Baseline 2025-2026

Adopt newer Go stdlib idioms when the project targets Go 1.21+ — the older patterns (hand-rolled `sync.Once` value-cache, `for { ... <- ch }` iterators, manual JSON omit-zero handling, ad-hoc context propagation in tests) are now non-idiomatic and produce reviewer questions.

- **`sync.OnceFunc` / `sync.OnceValue` / `sync.OnceValues` (Go 1.21+) replace the `sync.Once` + closure + cached-result pattern** for lazy singletons. Per Go stdlib docs: `sync.OnceValue(func() *Client { ... }) func() *Client` returns a function that initializes once and returns the cached value on every subsequent call. Use `OnceValues` for `(value, error)` pair. Old pattern (`var once sync.Once; var client *Client; func get() *Client { once.Do(...); return client }`) is verbose and easy to get wrong; `sync.OnceValue` is one-liner. **Panic semantics to know**: if the init function panics, every subsequent call re-panics with the same panic value (literally — same value, not a wrapped error); concurrent callers waiting during init unblock after `Do` completes and also re-panic. This is fail-fast-by-design (the cached value is never partial), but it means a transient init failure that you might want to retry across calls needs explicit retry-or-reset logic outside the OnceValue closure — OnceValue gives no second chance on its own.
- **Range-over-function iterators (`iter.Seq[T]` / `iter.Seq2[K,V]`, Go 1.23+)** are the new idiom for user-defined iteration over arbitrary in-process sequences — paginated API pages held in memory, lazy filter/map/take/zip chains, tree/graph traversal, slice/map iteration via `slices.Values`/`maps.All`. Producers expose `func(yield func(T) bool) {...}`; consumers use `for v := range producer { ... }`. The new `iter` package shipped in 1.23; `slices` and `maps` packages already existed and gained iterator-oriented helpers in 1.23 (`slices.All`, `slices.Values`, `maps.All`, etc). **NOT the right tool for cancellable streaming over a network or long-lived async source** — yield is synchronous and the iterator does not compose with `select { case <-ctx.Done(): ... case v := <-ch: ... }` the way a channel does. Channels + cancellation context remain the right shape for: streaming RPC responses, MQ consumers, long-poll, websocket message loops, anywhere the consumer needs to interleave the data source with deadline / shutdown / multiple sources. The producer-side rule: if the source can block on I/O for an arbitrary duration AND the consumer needs to cancel it, prefer a channel + context; if the source is synchronous (computation, in-memory traversal) or blocks only on cooperative read calls the producer controls, prefer an iterator.
- **`omitzero` struct tag (Go 1.24+)** replaces the `omitempty` foot-gun for non-pointer numeric / time / struct fields. `omitempty` drops `0`, `""`, `false` (often incorrect for fields where zero IS meaningful); `omitzero` drops only the actual Go zero value of the field type, and if the type has `IsZero() bool` (e.g. `time.Time`) it uses that. Migrate `time.Time omitempty` to `omitzero` first — it's the most common bug source. **`omitzero` is recognized only by Go's stdlib `encoding/json` (1.24+). Third-party JSON encoders (`json-iterator/go`, `goccy/go-json`, `easyjson`, `sonic`, etc) ignore unknown tags silently and behave as if no `omitempty` is set — verify the project's actual JSON serializer accepts `omitzero` before migration, or the marshaled output reverts to "always emit" semantics**. Same caveat for any non-stdlib codegen serializer.
- **Per-object / per-request state maps: `delete` on lifecycle; a strong-pointer key leaks, a numeric/id key cross-attributes.** A long-lived map holding per-connection / per-request / per-object state must delete its entry on the object's close / lifecycle end. Two distinct failure modes: a `map[*T]` with a **strong pointer key keeps the object alive**, so a missed delete is a memory leak (the object is never freed); a `map[id]` / `map[uintptr]` keyed by a **numeric id or address does NOT keep the object alive**, so once the original is gone that id/address can be **reused** and silently cross-attributes one object's state to a different, later one. Either way, `delete` deterministically on the close/lifecycle you control — Go does not prune a strong-keyed map for you. Guard the map (a mutex or `sync.Map`) — but a map mutex alone is not enough: on `Close`, under the registry lock mark the object closed (tombstone) and block future lookups; then **release the lock to cancel/drain/wait** for in-flight goroutines (holding the lock through the drain deadlocks if those goroutines need it to finish); then re-acquire and `delete` — otherwise a concurrent goroutine reads or lazily recreates state for a closing object (use-after-delete / resurrected state). Keep the `closed` marker on the **object itself** (an object-owned flag / generation token), not only in the registry entry, or the `delete` erases the tombstone and a later call on the still-referenced object recreates state. (Go 1.24+ `weak` pointers + `runtime.AddCleanup` help for objects with **no** explicit close, but only as a backstop: they fire after the object is unreachable, may be delayed, and are not guaranteed before process exit. Route `Close` and the cleanup through **one idempotent release** (`sync.Once`/atomic) and call the cleanup's `Stop()` on a successful `Close` to avoid a double-free; and the cleanup func must NOT capture the object itself — that keeps it reachable so cleanup never runs — pass only the underlying handle and `runtime.KeepAlive` the object after its last real use.)
- **`testing.TB.Context()` (Go 1.24+) and `t.Chdir(dir)` (Go 1.24+)** clean up two common test patterns. `tb.Context()` is a context auto-cancelled on test cleanup — replace `ctx, cancel := context.WithCancel(...); t.Cleanup(cancel)` with `ctx := t.Context()`. **Scope is the current test/subtest, not the parent**: a goroutine spawned inside `t.Run("sub", func(t *testing.T) { go work(t.Context()) })` sees the context cancel when the subtest ends, NOT when the parent ends — leaking that goroutine past the subtest is the responsibility of the test (use a wait + verify or use the parent's context if cross-subtest scope is intended). `t.Chdir()` changes directory for the test and restores on cleanup — replace manual `os.Chdir + t.Cleanup(os.Chdir(orig))`.
- **`encoding/json/v2` (Go 1.25, experimental behind `GOEXPERIMENT=jsonv2`)** is the upcoming replacement for `encoding/json` — faster, stricter, better error messages, fixes long-standing decoder quirks. NOT production-default yet (experimental flag required). Track for Go 1.26+ stabilization; do not migrate hot paths to it before stable, but new greenfield services may pilot it on opt-in subpackages with the experiment flag set in build config + tests verifying behavior parity with stable v1.
