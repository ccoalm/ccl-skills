---
name: platform-service-connectivity
description: 服务互通 / service mesh / service discovery / mTLS / retry / timeout / circuit breaker / lane routing → design or debug how one request safely reaches another service across environments, mesh, clients, HTTP/RPC, and queues.
---

# Platform Service Connectivity

This skill owns **how requests move between services**: the transport layer (mesh), service discovery, multi-environment routing, retry/timeout/circuit-breaker policy, and the framework middleware that propagates app-level context across hops.

You do not own:
- Whether the right signals exist or how to alert on them — go to `platform-observability`.
- Whether a change is safe to promote across environments — `platform-release-engineering` consumes connectivity policy as input.
- HTTP handler shape, DB schema, or business contract design — language-specific service-architecture skills.
- Agent/MCP tool exposure, dynamic tool catalog/cache behavior, model-visible schemas, or execution-time tool authorization — route those to `llm-inference-integration`. This skill owns the connector's network path, egress policy, mTLS/TLS boundary, service identity, and transport observability, not whether the agent may call a tool.

## Skill Routing

- Use this skill for: introducing or auditing service mesh, choosing service-discovery mechanism, setting retry/timeout/circuit-breaker defaults, designing lane-based or canary-based traffic shifts, debugging a "service A can't reach service B" failure, writing connectivity middleware, deciding where mTLS lives, propagating tenant/lane/log-id across hops.
- Use `platform-observability` for: anything about whether you can *see* a connectivity failure (envoy access log, kitex/grpc trace, Prom mesh metrics).
- Use `platform-release-engineering` for: shifting traffic during a deploy, promoting a canary, or rolling back via mesh VirtualService.
- Use `llm-inference-integration` for: agent tool catalogs, MCP tool/resource/prompt semantics, prompt-cache or manifest stability, tool-call approval policy, execution-time authorization, and model-visible connector schemas. Return here only for the connector's network reachability, service identity, egress allowlist, TLS/mTLS, timeout/retry transport policy, or mesh/discovery path.
- Use `defect-diagnosis` for: an active connectivity incident — come back here to land the recurring pattern.

## Core Mental Model — Two Layers

A request crossing two services traverses two cooperating layers:

```
Service A app code
   │ writes ctx fields (log_id, lane, business ctx)
   ▼
Framework client middleware (kitex/hertz/equivalent)
   │ packs ctx fields into request headers / RPC base struct
   │ resolves callee via the chosen service-discovery mode
   ▼
A's mesh sidecar (Envoy)         ◄── owns: mTLS, retries, timeouts,
   │ TLS, traffic policy, lane     traffic policy, lane routing,
   │ routing, retry, timeout       circuit breaking, telemetry
   ▼
Network
   ▼
B's mesh sidecar (Envoy)
   │ TLS terminate, authz
   ▼
Framework server middleware
   │ extracts ctx fields from headers / base struct
   │ injects into ctx for handler
   ▼
Service B app code
```

**Layer ownership is non-negotiable:**

| Concern | Owner | Reason |
|---|---|---|
| mTLS | Mesh | Identity is platform-level; apps must not see keys. |
| Connection-level retry | Mesh | Network failures are infrastructure noise. |
| Idempotent retry of business call | App or framework client | App knows idempotency. |
| Per-call timeout (transport) | Mesh + framework client | Mesh sets ceiling; client sets budget. |
| Per-call timeout (business) | App | Mesh cannot know intent. |
| Circuit breaker | Mesh primary, framework fallback | Outlier detection at network. |
| Load balancing across replicas | Mesh | Topology-aware. |
| Service discovery | Framework client + platform resolver | Resolver may use registry, k8s-native discovery, or a mixed mode; mesh consumes the resulting endpoints/subsets. |
| Lane / env / canary routing | Mesh | Single source of traffic truth. |
| Log-id propagation | Framework | Mesh sees but does not mutate. |
| Business context propagation (tenant, user, lane awareness in code) | Framework | Mesh stays oblivious to business. |
| Authz at request level | App (gateway or service) | Business rules. |
| Authz at network level (which service may call which) | Mesh AuthorizationPolicy | Infrastructure rule. |

Confusing these is the source of most "why doesn't this work" connectivity bugs. When in doubt: **mesh is transparent transport; framework is explicit context**.

## Non-Negotiable Rules

### R1 — Mesh is opt-out, not opt-in

- Every service pod runs the mesh sidecar by default (`sidecar.istio.io/inject: "true"` or namespace label).
- Specific workloads MAY opt out via explicit annotation. Documented exceptions:
  - Telemetry collectors (would observe themselves).
  - File-log shippers (DaemonSet with hostPath).
  - Service discovery / registry pods (would bootstrap-cycle).
  - Mesh control plane itself.
- A new service that opts out of mesh without documented reason fails review.

### R2 — Service discovery mode is explicit

- Pick and document the platform's service-discovery mode: registry-based, k8s-native, or mixed. Use `references/service-discovery-choice.md` before mandating a registry.
- App code MUST NOT bypass the chosen lane-routing mechanism with hard-coded cluster URLs or ad hoc hostnames.
- Registry mode carries lane and weight in instance metadata; k8s-native mode carries lane through pod labels, Services, EndpointSlices, and mesh subsets. Both require health to be honored before routing.

### R3 — Lane is the canonical multi-env primitive

- "Lane" = a logical traffic isolation label: `prod`, `test`, `pre`, named per-developer lanes for staging, named per-test-run lanes for integration.
- Lane flows through:
  1. **Request header** (a platform-wide header name; treat the literal value as a constant) at the entry edge.
  2. **`context.Context`** field via framework server middleware.
  3. **Outbound RPC base struct / outbound HTTP header** via framework client middleware.
  4. **Mesh `VirtualService` match rule** that routes lane-tagged traffic to lane-specific endpoints or subsets.
  5. **Discovery metadata** (registry instance tag or k8s pod label) so callees are discoverable under the right lane.
- A service that does not propagate lane through ctx is a multi-env hazard. Lane must traverse every hop, including queue boundaries.

### R4 — Default retry/timeout/circuit-breaker live at mesh, app overrides for business reasons

- Mesh DestinationRule provides default per-callee policy: retries (1-2 attempts on 5xx/connect-fail), connect timeout, request timeout ceiling, outlier detection (5xx-percent → eject).
- Framework client SDK provides per-call override: business timeout (always ≤ mesh ceiling), retry policy for idempotent calls, hedging.
- App code MAY override per-RPC. App code MUST NOT silently disable mesh-level outlier detection.
- Budget rule: total upstream timeout = caller deadline minus a safety margin (e.g. 100ms). Cascading timeouts must shrink down the call chain.

### R5 — mTLS is mesh-default, app cannot disable

- Mesh PeerAuthentication enforces STRICT mTLS namespace-wide.
- App code MUST NOT use plaintext HTTP/gRPC between services. Local dev can use plaintext (no mesh) but the build/staging path always tests with mesh on.

### R6 — Framework client/server middleware chain is mandatory

Every service uses the platform framework client and server suites; ad-hoc construction is reviewed. The default chain (RPC side) MUST include:

| Middleware | Purpose |
|---|---|
| `ctx_inject` | extract log-id from inbound RPC headers/base; generate if missing on client side; write into `context.Context` |
| `base_inject` / request-metadata inject (client side) | populate the outbound request-metadata carrier — the in-message `base` struct where that carrier is standardized, else the R7 owner-recorded metadata/header set (the default for ordinary gRPC) — with `log_id`, lane, idc, cluster, caller identity from ctx (uniform shape regardless of the calling language); the middleware is mandatory, the in-message `base` struct specifically is not (carrier is scenario-driven, see R7) |
| `request_info_log` | log inbound/outbound RPC line with method, duration, error code (gated by env flag for noisy paths) |
| `metrics` | count + histogram with baseline labels + caller/callee identity + method |
| `error_handler` | map framework errors (timeout, panic, ACL, biz) to a stable error-code enum |
| `tracing` (via OTel contrib) | span per RPC, parent-child link across services |

If a developer can build a new client/server without these, the framework is broken.

### R7 — Standard RPC base field contract

For RPC platforms that support a structured request "base" (Kitex `base.Request`, Thrift `Base`, protobuf-backed gRPC request fields, or metadata-only fallbacks), the platform defines a canonical shape:

```
Base {
  UnixTime  int64           // ms since epoch (caller's view)
  LogId     string          // platform log-id
  Caller    string          // PSM-style identity of caller
  Tags      map[string]string {
    "idc":     <region>,
    "cluster": <k8s cluster>,
    "lane":    <env/lane>,
    // optional: "stress_tag", "shadow"
  }
}
```

Whether a platform carries this metadata in an **in-message `base` field at all**, versus the **transport metadata / context channel** (gRPC HTTP/2 metadata + interceptors — the industry-standard default for ordinary unary and streaming gRPC), is a scenario decision, not a universal mandate; the propagation obligation (R6) holds on either carrier, but the in-message field-number contract applies only where the in-message `base` carrier is used. See the Carrier decision in `references/rpc-framework-recipe.md`.

For protobuf-backed internal RPC on a platform that has standardized the in-message `base` carrier, the protobuf base-field declarations are owned by `references/rpc-framework-recipe.md`. Field name, type, field number, request/response shape, exception handling, and generated-artifact provenance are fixed by that shared contract source; service repos and language-specific generated packages must consume them as generated, not rename, renumber, retype, or replace them locally.

The client middleware fills this from ctx automatically; the server middleware extracts it back. **App code does not touch the base struct directly.**

For non-protobuf or metadata-only transports, an equivalent header set is compliant only when it cites a resolvable platform owner record, such as a repo/path, document URL, registry id, gateway policy, or owner-suite id. The owner record must enumerate the concrete header names. In diff-only review without resolver tooling, the diff must cite a stable owner-record locator and list the concrete header names inline; with resolver tooling, the reviewer or owner-suite may resolve the locator to those names instead. The enumerated header names must then be checked against the actual propagated and exposed headers: caller-supplied identity headers are absent unless positive authenticated-caller evidence exists. An unresolvable, non-enumerating, uncited, service-local, or unchecked header set is an open gap, not a permitted alternative. For pure HTTP (no RPC base), the equivalent is a stable owner-recorded header set, also filled by middleware.

### R8 — gRPC `:authority` and DNS-label hyphenation

If the platform allows service names with underscores (`<owner>.<class>.<env>` containing `_`), gRPC will reject them in the HTTP/2 `:authority` pseudo-header because it must be a valid DNS label (no `_`). Two acceptable fixes:

1. **Disallow underscores in new service names**; enforce in registry registration and CI.
2. **Mesh-level rewrite**: an EnvoyFilter Lua snippet replaces `_` with `-` in `:authority` for gRPC requests, before routing.

Option 1 is cleaner long-term; option 2 is the live-system workaround. Document which the platform uses; new services should follow option 1.

### R9 — Ingress and egress are explicit, not implicit

- Ingress: traffic from outside the cluster enters via a documented Gateway (Istio Gateway / k8s Ingress). One default gateway per environment is fine; ad-hoc NodePort exposure is not.
- Egress: traffic leaving the cluster goes through an egress gateway OR is explicitly allowed via mesh policy. "Service can reach the internet" is a configuration decision, not a default.
- A service that needs to call an external third-party API declares it; the platform sets up the egress path with mTLS termination, retry, observability.

### R10 — Envoy access log is part of the observability contract

- Mesh access logs MUST include `log-id` and `lane` fields (read from request headers).
- Access logs ship to the same log pipeline as app logs so on-call can join "what mesh saw" with "what app saw" by log-id.
- `enablePrometheusMerge` (Istio) is enabled so Envoy stats appear in the same Prom scrape as the app — one less moving part.

### R11 — Long-lived streaming control channels need transport contracts

- WebSocket, SSE, long-poll, or split read/write transports need explicit connection state: idle, connected, reconnecting, closing, and closed. Permanent auth/not-found/protocol rejections stop retry; retryable network, 429, and 5xx failures use bounded exponential backoff with jitter and a total reconnect horizon.
- Reconnect must refresh credentials, preserve or send a high-water mark that advances only after durable apply or write, replay only unconfirmed outbound messages whose original principal/workspace/session/policy/capability/auth-generation tuple still matches, deduplicate by stable event/request id, and fence callbacks from a previous transport incarnation.
  - If that tuple changed, cancel or fail closed and surface unknown finality instead of replaying under fresh credentials.
  - If multiple sessions run in one process, auth headers and tokens must be per transport instance, not process-global mutable state.
- Liveness is not optional. Define heartbeat or keepalive cadence, liveness timeout, proxy idle-timeout mitigation, sleep/wake behavior, listener/timer cleanup on reconnect and close, and graceful shutdown drain windows. A closed transport must release blocked writers and must not leave orphan listeners, timers, pings, or callbacks.
- Streaming writes need backpressure and queue bounds. Batches are serialized when the downstream store cannot safely handle concurrent writes; retry-after hints are clamped and jittered; permanent failures, max-failure drops, close-time drops, and best-effort flush semantics are surfaced as diagnostics rather than silently treated as delivered.

### R12 — Local egress relays are credentialed transport, not environment sugar

- A local proxy or relay that injects credentials, rewrites trust roots, or tunnels subprocess traffic must bind only to loopback, fail open only before credentials are accepted or injected when optional setup fails, and fail closed once it has accepted a credentialed tunnel but cannot safely continue. Delete or revoke bootstrap secrets only after the listener, trust bundle, and cleanup path are proven ready, and before launching credentialed children or accepting traffic when possible; keep the secret out of model context, child-visible arguments, logs, dumps, crash reports, and fixture files.
- A local browser authorization callback listener is also credentialed transport.
  - Bind only to loopback, prefer an OS-assigned port unless a caller explicitly owns the port, validate callback path and host/port, accept only the pending flow's state, and reject duplicate or late callbacks after manual fallback, cancellation, timeout, success, or failure.
  - Pending HTTP responses must have exactly one terminal outcome, listeners must remove handlers and close on every exit path, and callback secrets or authorization codes must never be echoed into child process args, model-visible prompts, logs, telemetry, dumps, or fixture files.
- Trust-root and proxy environment changes are scoped runtime state. Publish them only to the intended child process tree, include explicit bypass rules for loopback, metadata, private networks, first-party control channels, package registries, and other direct paths, and never route plain traffic through a credential-injecting tunnel unless the protocol explicitly supports it. Per-runtime proxy support differences need tests; inherited proxy variables must be passed through only when the parent relay is still the intended authority.
- CONNECT-style or byte-tunnel relays need parser and stream contracts: cap header size, reject non-tunnel methods, preserve bytes that arrive before the upstream tunnel is open, chunk large payloads, validate tunnel frame encoding, implement keepalive inside proxy idle windows, handle partial writes and backpressure per runtime, avoid writing plaintext errors after encrypted payloads may have begun, and cleanup listeners, timers, sockets, and upstream sessions on every close path.

## Workflow

### Phase A — Identity and lane chain

1. Confirm lane and log-id propagate through ctx for every hop type (HTTP, RPC, queue). Spot-check by reading framework client/server middleware, not user code.
2. Confirm the RPC base struct (or HTTP header equivalent) carries `log_id` + tags `{idc, cluster, lane}`. A missing tag is a propagation bug.

### Phase B — Mesh policy

1. PeerAuthentication = STRICT (mTLS namespace-wide).
2. DestinationRule per critical callee: retry policy, timeouts, outlier detection.
3. VirtualService rules express lane-based routing: lane header match → lane subset.
4. AuthorizationPolicy expresses which services may call which (zero-trust at network level).

### Phase C — Service discovery

1. Confirm the chosen mode is documented: registry-based, k8s-native, or mixed.
2. Registry mode: registry is multi-replica, explicitly NOT in mesh; SDK resolver uses registry metadata.
3. K8s-native mode: Service / EndpointSlice / pod labels are the discovery source; app code does not bypass mesh/lane routing with raw cluster URLs.
4. Discovery metadata includes `lane` (registry tag or pod label) so VirtualService subsets can target correctly.
5. Healthcheck contract exists: registry heartbeat or k8s readiness removes unhealthy endpoints within the documented window.

### Phase D — Framework middleware

1. Read the framework default client/server options module. Confirm middleware chain matches R6.
2. Confirm dev cannot build a client/server without inheriting these.
3. Test: kill a downstream pod → verify mesh outlier-detection ejects, framework retry kicks in for idempotent calls, error propagates up with stable error-code.

### Phase E — Failure modes

1. Mesh sidecar crash → app pod fails readiness. Configured behavior?
2. Discovery backend unreachable → resolver uses cached endpoints for a bounded TTL, or fails closed by documented policy?
3. Lane label drops mid-chain → service calls wrong env. Detected how?
4. Cascading timeout → caller deadline exceeded but downstream still running. Hedge or cancel?

### Phase F — Evidence

Before marking work done:
- One request traced end-to-end across ≥ 2 services; mesh access log + app log + trace all share the same log-id.
- One synthetic outlier: pod 5xx → mesh ejects → recovers when pod healthy → metrics + access log show the pattern.
- One lane-routing verification: request with lane=test header → arrives only at lane=test instances. Verified via access log `upstream_host`.

## Decision Points

- **"Add a new retry policy for service X"** → start at mesh DestinationRule. Move to framework client only if the retry depends on business idempotency knowledge.
- **"Service A times out calling Service B"** → check three layers in order: app deadline (ctx timeout) → framework client timeout → mesh request timeout. Whichever is smaller wins; align them.
- **"Switch service discovery mode"** → use `references/service-discovery-choice.md`; do not mandate registry unless the platform needs registry-specific capabilities such as per-instance drain, out-of-cluster lookup, or existing registry federation.
- **"Need mTLS to a non-mesh external service"** → egress gateway with terminating TLS, not app-managed certs.
- **"Multiple registries (legacy + new)"** → run them side-by-side, dual-write during migration, single read source per lane.

## Sanitization and Provenance

This skill is product-agnostic. It must not contain:
- Repository names, service names, internal hostnames, internal IPs, namespaces, cluster names.
- Business-domain header values, tenant types, or vertical terms.
- Specific image registry URLs, ingress hostnames, or cloud-provider artifact paths.
- Concrete credentials or example certificates.

Reused industry patterns (PSM-style identity, `<owner>.<class>.<env>` shape, `traceparent`, `:authority` semantics) are fair game.

## References

- `references/mesh-architecture.md` — Istio (or equivalent) topology, sidecar injection rules, gateway shape, EnvoyFilter use, what mesh owns vs framework owns.
- `references/service-discovery-recipe.md` — Registry-based SD (Nacos as recurring example), instance metadata, lane tag, healthcheck contract, dev-vs-prod differences.
- `references/framework-middleware.md` — Server and client middleware chain (HTTP + RPC); the canonical RPC base struct shape; verification commands.
- `references/multi-env-routing.md` — Lane label end-to-end recipe; VirtualService patterns; queue-boundary propagation; stress/shadow tags.
- `references/retry-timeout-circuit-breaker.md` — Mesh defaults vs SDK overrides; cascading timeout budgets; idempotency awareness; outlier detection tuning.
- `references/grpc-authority-workaround.md` — The `_` → `-` rewrite quirk; when it's needed; the cleaner long-term fix.
- `references/dual-sidecar-and-traffic-config-center.md` — Pod-level dual sidecar (mesh + platform), per-protocol mesh injection policy, per-caller-callee traffic config via config center (separate from mesh routing).
- `references/rpc-framework-recipe.md` — Concrete kitex/hertz default suite: shared RPC base field contract, RPC base.Request full schema (8 fields incl From/To), dual-channel ctx propagation (metainfo + grpc metadata), 9-code error enum + framework error mapping table, three resolver strategies (registry / FQDN fallback / proxy), platform latency histogram buckets, CORS defaults exposing log-id header, server boot sequence with graceful shutdown.
- `references/service-discovery-choice.md` — Decision framework: registry-based vs k8s-native SD; both support lane routing + canary + multi-env; pick by per-instance drain need, laptop access pattern, federation preference, operational burden; mixed mode (k8s east-west + thin registry for laptop) is workable; migration paths in both directions.
- `references/service-discovery-migration-playbook.md` — Step-by-step playbook: 6-phase registry-retirement (inventory / add k8s resolver / dual-resolve burn-in / switch registration off / migrate off-cluster tools / decommission); per-phase risk + rollback path; total ~3 months active work for medium platform; reverse direction (add thin sync-only registry) for off-cluster lookup; 6 anti-patterns to avoid during migration.
- `references/protobuf-http-contract-signals.md` — Cross-stack gate for classifying an HTTP surface as routine JSON/OpenAPI vs protobuf-backed: the in-scope/out-of-scope predicate, protobuf signal list, authoritative wire-format record, and owner-approval decision list. Shared by the Go/Python/web/mini-program/testing skills (each points here; do not redefine per stack).
- `references/http-response-envelope-contract.md` — Cross-stack JSON business-response envelope (`code`/`message`/`data`): canonical shape, new-service vs new-route vs existing-surface adoption/migration, non-JSON surfaces that record their own contract, and the invent/duplicate/hide anti-patterns. The response-side companion to the request-side base struct; shared by the same stack skills (each adds only its define/implement/consume/assert verb).

## Verification before marking work done

1. **Static**: framework default options module includes all R6 middleware; mesh PeerAuthentication is STRICT; DestinationRule and VirtualService exist for every callee that participates in lane routing.
2. **Live, identity**: cross-service trace shows log-id + lane consistent across all hops; mesh access log lines include both.
3. **Live, mesh policy**: kill a callee pod → outlier detection ejects within outlier-detection interval; metrics show client-side error count rise then fall.
4. **Live, lane routing**: send request with non-default lane → confirm only matching-lane instances serve it.
5. **Static, no leakage**: grep this skill's content — zero internal hostnames, repo names, or business terms.

If any check fails, the work is interim, not done.
