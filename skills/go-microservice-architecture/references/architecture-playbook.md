# Architecture Playbook

## Service Boundary Rules

Create a separate service when at least one is true:

- It owns a distinct transactional data model.
- It has independent scaling or latency requirements.
- It needs independent deployment or failure isolation.
- It is consumed by multiple products or integration surfaces.
- It has a different compliance, security, or operational boundary.

Do not create a service only because:

- A domain noun exists.
- A table exists.
- A team wants a cleaner folder.
- A future scale concern is speculative.

## Recommended Service Types

### API Gateway / HTTP Service

Responsibilities:

- External HTTP contract.
- Authentication, authorization, subject/resource context, request validation.
- DTO mapping between external model and internal commands/queries.
- Swagger/OpenAPI docs if the API is consumed outside the service team.

Avoid:

- Direct complex SQL.
- Long-running jobs.
- Hidden cross-service transactions.

### Internal RPC Service

Responsibilities:

- Core domain operations.
- Internal protobuf contract.
- Data ownership and transaction boundary.
- Calls to other internal services through typed clients.

Avoid:

- Returning raw DB models when the contract should be stable.
- Sharing write access to owned tables.

### Worker / Consumer Service

Responsibilities:

- Async events, scheduled jobs, retryable side effects.
- Idempotency and deduplication.
- Backfill, compensation, repair workflows.
- Outbox/inbox handling when domain consistency matters.

Avoid:

- Assuming exactly-once delivery from MQ.
- Treating retries as safe without idempotency keys.

### Shared Package

Appropriate for:

- Logging, tracing, metrics.
- Config and secret clients.
- DB/Redis/MQ wrappers.
- Codegen helpers.
- Generic data structures and concurrency utilities.

Not appropriate for:

- Product-specific domain rules.
- Cross-service data model coupling.
- Hidden network calls behind generic helpers.

## Contract Design

- Use protobuf for current API/RPC contracts.
- For detailed protobuf package, service, message, enum, annotation, and evolution rules, apply `protobuf-contract-architecture.md`.
- Design pagination, filtering, sorting, and idempotency from v1 for list and write APIs.
- Include request context fields only when they are part of the domain contract; transport context should travel via middleware/metadata.
- Keep transport DTOs, application parameters/results, domain objects, and storage models as separate boundaries when behavior or compatibility is non-trivial.
- Patch/update contracts need presence semantics, not only zero values.
- For finite values used across contracts, domain logic, persistence, clients, analytics, or events, architecture owns the semantic source of truth. Decide the canonical owner, shared contract/package location, allowed representations per boundary, parser/canonicalization owner, unknown/default behavior, and rollout order. If a shared location does not yet exist, the architecture decision must approve a local fallback and a consolidation task with owner and deadline; unowned `finite-value-debt` markers are architecture findings.
- **RPC framework choice: Kitex remains the default; ConnectRPC is the credible 2025-2026 alternative for specific contexts**. Per `connectrpc.com` docs, Connect ships as a single small Go package (single-digit-thousand LOC), built on `net/http` with handlers implementing `http.Handler` and clients wrapping `http.Client` — works with any third-party router, middleware, or server. Supports three protocols (gRPC, gRPC-Web, Connect's own protocol) over both HTTP/1.1 and HTTP/2; any gRPC client in any language can call a Connect server, and Connect clients can call any gRPC server (validated by Google's interop tests). CNCF-incubated as of 2025; production-adopted at CrowdStrike, PlanetScale, Bluesky, Dropbox per `buf.build/blog`. Architecture choice: **choose Connect** when (a) the service hosts a browser-facing API and gRPC-Web is the main use case (Connect collapses gRPC + gRPC-Web + Connect into one server), (b) the service is small and Kitex's framework surface is over-spec'd, (c) the service must interop bidirectionally with multi-language gRPC clients but the team wants to avoid grpc-go's 130k-LOC dependency footprint. **Stay on Kitex** when (a) the team already operates Kitex across many services and the platform observability/middleware/registry contracts are Kitex-native, (b) Thrift IDL (TTHeader / TTHeader Streaming) is in active use alongside protobuf — Connect is protobuf-only, (c) Kitex-specific features (StreamX, FastCodec, generic call) are load-bearing. The two are NOT mutually exclusive: a Connect-based public-edge gateway can fan out to internal Kitex services, but **wire compatibility alone is not interop** — Connect speaks gRPC on the wire when configured for gRPC, and Kitex servers configured with the gRPC meta handler can accept those calls; however, Kitex services in production typically depend on Kitex-specific framework metadata (lane / tenant / caller-identity ctx values propagated via TTHeader or Kitex middleware), and Connect clients do not emit those by default. The fan-out works ONLY when (a) the target Kitex services are configured for the gRPC meta handler (not TTHeader), (b) the Connect-side Go client explicitly attaches the gRPC metadata (`metadata.MD`) that the Kitex service's middleware reads as caller-identity / lane / tenant — typically through a small adapter layer at the Connect-side that pulls fields from the Connect call context and writes them as gRPC headers, (c) any Kitex-specific TTHeader Streaming / generic call / Thrift-only paths stay routed through a Kitex-native edge instead. Plan the adapter layer as a first-class architecture component, not a one-line bridge; otherwise tenant / lane context drops silently at the protocol boundary and downstream services run without isolation.

## Data Design

- MySQL or compatible relational DB is the default domain truth store.
- Redis is for ephemeral state: cache, lock, counter, limiter, idempotency, job state.
- MQ is for eventual consistency and async workflows; model delivery as at-least-once.
- Dynamic config controls rollout, feature gates, thresholds, and routing, not core domain truth.
- Search stores, document stores, and analytics stores are projections unless explicitly designed as source of truth.

## Dependency Direction

Recommended:

```text
transport -> application/service -> domain -> infrastructure adapters
                         |
                         -> generated clients/contracts
```

Rules:

- Domain logic should not import HTTP or RPC framework packages.
- Infrastructure adapters should be behind interfaces when they are complex or externally visible.
- Generated code may be imported by transport and adapter layers; avoid letting generated DTOs dominate core domain modeling when behavior is complex.
- How a layer boundary is enforced is itself an architecture decision, with a strength ladder: physical module/package boundary (a violation is a compile or import error), import-architecture lint (the tiering CI gate below), then review convention — in decreasing strength; prefer mechanisms where a violation is a CI error, not a review comment. For a core where a frozen contract must coexist with continuous evolution (a gateway data plane, a billing domain), prefer the physical boundary, and add a deterministic digest/conformance anchor as machine proof that evolution has not touched the frozen surface. Record why the chosen strength is enough (cost versus strength); a weaker tier is a documented tradeoff, not a default. Sibling: `python-service-architecture/references/architecture-playbook.md` ("Layering Depth") carries the same rule for Python; keep the two in sync.

### Functional Core, Imperative Shell (Recommended, Not Mandatory)

- Keep calculation, rule, and state-transition logic in pure functions with no I/O or hidden state; let handlers, repositories, clients, and workers be the thin imperative shell that calls them. The payoff is testability — the pure core unit-tests without mocks, and the shell stays small enough for focused integration tests. Conflating them (domain rules inside a repository method or a worker callback) is the recurring cause of "we cannot test this without a real DB / queue / network."
- This pure-core *style* is a recommended outcome for I/O-heavy services, **not a mandatory gate**, and not a license to cargo-cult functional-programming idioms into Go — plain functions and structs, not an abstraction tower. Distinct and **not** optional, though: domain invariants must not be hidden inside handlers, repository methods, IO adapters, framework hooks/middleware, or worker/task callbacks — anywhere outside the domain/service layer. That is the dependency-direction rule above, independent of whether you adopt the pure-core style.
- Sibling: `python-service-architecture/references/architecture-playbook.md` ("Layering Depth — Apply In Moderation") carries the same principle for Python; keep the two in sync.

### Shared Foundation Module Package Tiering

A shared cross-service module (a `common` / foundation / utility library imported by many services) needs stricter internal discipline than a single service: one import cycle or one heavyweight coupling inside it is inherited by every consumer, and a leaf utility cannot be reused once it transitively drags in unrelated packages. Scale the strictness to blast radius — a widely-imported foundation module earns this; a tiny single-consumer helper does not.

- Define and **document** an explicit linear package-tier order in the module's own README/doc. The order `generated value-types -> constants/globals -> generic pure utils -> logging/metrics -> framework/business adapters` is illustrative — each team picks its own — but the written order is the artifact reviewers enforce, and an unwritten "everyone knows the order" rots into cycles. Keep pure helpers in a tier below logging/config so they do not drag observability or runtime config into every consumer.
- **Earlier tiers must never import later tiers** — the tier list is one-directional and acyclic.
- **Default to sibling independence within a tier** so each leaf stays independently importable. When one same-tier package genuinely needs another (a real case: a `retry` helper used by an http client, `backoff` used by a queue), that is the signal to extract the shared piece **down into an earlier tier** so it is no longer a sibling — not to copy-paste it and not to add an artificial micro-tier. Reserve strict "no sibling import" for declared leaf packages.
- **Split generated packages by what they pull in.** Generated pure contract/value types may be imported by any tier; generated clients/server bindings carry transport and runtime deps (gRPC, HTTP) and belong in the adapter tier only — importing them broadly pressures domain code to model around transport shapes, which the Dependency Direction rule above warns against. All generated code is regenerate-only (rebuild via the codegen target, never hand-edit).
- Gate the invariant in CI rather than relying on review memory. Outright cycles already fail `go build` / `go list ./...` (the compiler forbids import cycles), but that does not catch a legal-but-wrong cross-tier or sibling import — for those use a dedicated import-architecture linter: `depguard` (via golangci-lint) to allow/deny imports per package, or a layer/component checker such as `go-arch-lint` or k8s-style `import-boss`. (`internal/` only blocks imports from outside a parent tree; it does not enforce tier order or sibling independence inside the module.) Treat a new cross-tier or sibling import as an architecture-review item, not a silent merge.

### Adapter / Plugin Family — Shared Core + Thin Bridges Across Repos

When one cross-cutting platform concern (observability, auth/governance, a client-SDK wrapper) must bridge into *many* frameworks or drivers — one governance layer wired into gin / hertz / gRPC / Kitex plus a set of DB, cache, and MQ drivers — design **one shared core that owns the invariants + a thin per-framework bridge adapter each**, not a full re-implementation per adapter. Each adapter owns only framework-specific wiring (how *this* framework exposes middleware/hooks/interceptors); the invariants (a **risk-appropriate failure policy** — fail-open for genuinely optional telemetry, fail-closed for auth / governance / data-integrity / audit-and-compliance; classify each concern explicitly, an audit / compliance / security signal is a control, not "observability"; but "fail-closed" for audit/compliance means **durable local capture (outbox) + bounded degraded mode**, hard-blocking only the specific regulated operation (a mutation, sensitive read, export, or privileged access — whatever the compliance scope covers) — not turning the audit exporter into a synchronous production kill switch for unrelated traffic — context binding, lifecycle/cleanup, propagation, canonical schema and error model) live once in the core and are delegated to. This is Ports-and-Adapters applied to a *fleet of transports*, distinct from the intra-module tiering above — here the adapters are typically separate repos.

- **The core exposes only the seam + invariants; concrete adapters live outside it — dependency-neutral, but NOT semantics-neutral.** The shared core defines the extension interface/seam and owns the invariants — a *concrete* framework/driver adapter (a specific ORM, HTTP framework, or MQ-client binding) must NOT live inside the core package: co-locating it pulls that framework's heavyweight deps into every core consumer and inverts the dependency direction (adapters import the core, never the reverse; the core stays adapter-agnostic). Keep the seam neutral to the concrete *dependency* but **explicit about semantics** — it names the required transaction / commit / ack / retry / cancel / failure guarantees the invariants rely on (an outbox/audit control needs real commit-and-ack semantics, not a seam that hides them) plus an adapter conformance suite; a driver that cannot implement a required guarantee is rejected, not silently flattened to a lowest common denominator. A library swap is a **thin shim only if the replacement preserves that declared capability matrix** (session scoping, driver connection reset, broker nack/backpressure, official middleware ordering); dropping a real semantic is an architecture change, not a shim. And "outside the core" ≠ "ship nothing" — provide at least one official/reference adapter + bootstrap for **every mandatory fail-closed control** (auth / governance / data-integrity / audit / compliance) and for baseline instrumentation, so services don't each hand-roll and diverge from — or bypass — the invariants. Catching a concrete adapter that slipped into the core late means ripping it back out — a costly reversal, not a tidy refactor.
- **Repeated-fix-across-siblings is the extract-the-abstraction trigger — but fix the live bug first.** The same bug fixed in a third sibling adapter, or sustained "harden X" churn across the family, is a missing seam, not N unlucky bugs. Backport/mitigate the incident across the existing adapters **first**; the core extraction is the durable follow-up, not a reason to leave the Nth adapter broken. (An adapter that duplicated the concern and later delegates to a shared helper typically collapses to a fraction of its size — that deleted duplication was the tax on the missing abstraction.)
- **Design a seam early, but keep it minimal — and split the stable API from the core impl.** "Extract down a tier" cannot reach across import-pinned repos, so a *minimal, explicitly-versioned* SPI/compat seam (provider/runtime injection, no core internals or process-global set-once state) should exist before out-of-repo adapters ship — but do NOT freeze a broad abstraction from one adapter; stabilize the wider shared-core shape only after real sibling evidence (rule of three), or you build a version-lock chokepoint. Ship the stable **API/contract as a tiny package separate from the core implementation**, so a core-impl or canonical-schema change does not force-lock every independently-pinned adapter; govern it with semver compatibility windows, an adapter↔core version matrix, and cross-adapter contract tests. Minimal-early, not big-early — a *wrong* shared abstraction couples the whole family to a bad decision and is harder to undo than duplication.
- **Reuse the framework's official instrumentation for wire/transport mechanics — through explicit injection, not its globals.** Official instrumentation often uses process-global providers / auto-registration; wrap it behind an explicitly injected provider/runtime and contract-test that no global set-once state leaks, or you get cross-service exporter/context leakage and double instrumentation. If a framework's official instrumentation *only* exposes a global / set-once API, a documented global-only exception is fine — confined to a single-owner idempotent bootstrap with teardown/test isolation and no custom wire semantics; don't fork or hand-roll transport instrumentation just to avoid the global. Keep platform governance semantics in the shared core so they do not fork per framework.

Sibling: `python-service-architecture/references/architecture-playbook.md` carries the same adapter-family principle; keep the two in sync.

## Cross-Layer Contract Integrity

- For any value that must travel across transport, application, domain, infrastructure, async event, or generated-code boundaries, name its source, destination, allowed transformations, and validation owner.
- Required parameters should be validated at the boundary and re-checked before irreversible side effects when they cross async, retry, or persistence boundaries.
- Do not rely on hidden globals, mutable maps, or stringly payloads for critical parameters; use typed request/result structs or generated contracts.
- Branches behind one public endpoint or command should return the same envelope shape and preserve required workflow steps unless a documented product decision says otherwise.
- Special-case branches need the same acceptance checks as the main path: auth, validation, idempotency, persistence, observability, error mapping, and regression coverage.
- When modifying a cross-layer parameter, update contract docs, generated code, adapters, tests, and observability together.
- When modifying a cross-boundary finite value, update enum/string conversion, storage compatibility, client mappings, analytics dimensions, event payloads, boundary conversion tests, and every tracked `finite-value-debt` marker together or record the remaining owner/deadline explicitly.

## Architecture Change Checklist

- Identify affected contracts, data shapes, state transitions, dependency calls, and generated artifacts before implementation.
- Check backward compatibility for existing clients, stored data, queued messages, cached values, and replay/backfill inputs.
- Define rollout and rollback behavior before migrating data or changing public behavior.
- Add verification for both the new path and historical/compatibility path when old data or old messages may still exist.
- Confirm no branch skips a required step such as validation, authorization, idempotency, persistence, event publication, or audit logging.
