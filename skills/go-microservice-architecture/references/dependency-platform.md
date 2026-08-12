# Dependency Platform

Use this when designing reusable dependency access for new Go backend services.

## Secret Provider Contract

- Treat secrets as runtime dependencies, not config literals.
- Repo-committed config may contain secret references, credential names, key ids, roles, service identifiers, and endpoint identities; it must not contain raw app secrets, webhook secrets, passwords, access keys, or private tokens.
- Secret lookups need typed accessors per credential class: database, Redis, MQ, object storage, external API, and application credential.
- The secret provider should expose read paths separately from write/admin paths.
- Startup may fail fast when required credentials are missing; request handling should not panic on missing runtime secrets. More generally, never let a critical invariant ride on a dependency's incidental or undocumented behavior (e.g. it happening to panic on nil wiring); assert and own the invariant locally with a construction-time fail-fast guard, keeping an explicit test opt-out.
- Cache short-lived credentials with a safety buffer before expiry.
- Validate local clock skew when using time-bound credentials.
- Never log secret values, temporary tokens, signatures, raw encrypted payloads, or decrypted config.
- Prefer authenticated encryption or a managed secret store. If local encryption is unavoidable, keep keys outside source/config and rotate deliberately.

## Service Discovery And Lane Routing

- Internal clients should resolve endpoints through a discovery abstraction, not hardcoded host lists.
- Health-filtered instances are the default.
- Lane/environment tags may route traffic, but fallback is operation-specific: read-only requests on idempotent endpoints MAY fall back to a stable baseline lane; writes, tenant-sensitive reads, and any request that mutates state or carries canary/stress assumptions MUST fail closed when the requested lane has no healthy instance. Document the fallback policy per route, default to fail-closed for unmarked routes.
- Keep service identity, lane, and endpoint selection visible in logs and traces.
- Do not let service discovery failure silently fall back to an unrelated public endpoint.
- If external components are registered into service discovery from config, model it as desired-state reconciliation: load desired endpoints, resolve hostnames, compare endpoint plus metadata, register changed instances, and deregister stale instances.
- Registration metadata should be low-cardinality and intentional: source host, lane/environment, protocol, ownership, and routing tags when needed.
- Reconciliation loops need a cancellable ticker, bounded lookup/register/deregister timeouts, and metrics for changed, unchanged, removed, and failed instances.

## Dependency Client Policy

- Define a standard client wrapper for each dependency type with:
  - context propagation.
  - connect timeout and request timeout.
  - credential source.
  - retry budget.
  - low-cardinality metrics.
  - safe structured logs.
  - test fake interface.
- Prefer constructing clients in DI providers; domain logic should receive interfaces.
- Separate internal service clients from external internet clients because timeout, auth, retry, and data-safety rules differ.
- For dependency status responses, validate transport success and domain success separately.

## Dynamic Config

- If etcd is used, state explicitly whether it is a dynamic-config backing store or service discovery. Service mesh based systems may allow etcd for platform-owned dynamic config while still banning in-process etcd registry/resolver clients.
- First-party KMS can be backed by dynamic config for early versions, but secret envelopes must be encrypted, master keys must stay outside repo config, and readiness must fail closed when the KMS store or master key is unavailable.
- Dynamic config keys need typed accessors, namespace ownership, timeout, cache policy, and default behavior.
- Cache hot-path reads briefly and emit cache hit/miss/error metrics when the config system supports it.
- Watch/listener APIs must update local cache and recover panics inside callback handling.
- Keep admin write/delete APIs separate from ordinary runtime read clients.
- For missing or malformed dynamic config, choose fail-closed for safety controls and fail-open only for explicitly non-critical behavior.

## ID Generation

- Decide whether IDs are generated locally, by a central service, or by the database before schema/API design.
- Central ID services need namespace registration, batch allocation, caller identity, timeout, and quota controls.
- Client-side ID caches should have bounded size and timeout on allocation.
- Local fallback generators are acceptable only when their uniqueness domain is explicit and collision risk is understood.
- Do not use timestamp-only fallback IDs for durable cross-service records unless collision handling exists.
- Persist allocator state durably when ID monotonicity or non-reuse matters.

## Object Storage Architecture

- Wrap object storage behind an interface such as `Put`, `Get`, `Head`, `Delete`, `Sign`, and `List`.
- Store object metadata and tags for source service, lane/environment, trace/log id, retention class, and ownership when useful.
- Large uploads require multipart/resumable design, part size, retry policy, and abort/cleanup behavior.
- Range downloads should validate object size with metadata first.
- Signed URLs need explicit expiry, permission scope, and audit visibility.
- Object keys are durable identifiers; define namespace, uniqueness, lifecycle, and cleanup before exposing them in API contracts.
- Object storage is not a relational source of truth. Persist durable resource records in the service database when users or workflows depend on them.

## Projection Stores

- Treat search indexes, document stores, and analytics stores as projections unless the service explicitly defines them as the source of truth.
- Define index/collection ownership, schema or mapping ownership, rebuild path, sync trigger, and eventual-consistency expectations.
- Projection clients need timeout, health policy, pool bounds, tracing, credential source, and endpoint-discovery policy.
- Query APIs need max limit, deterministic sort, filter allowlist, and pagination strategy.
- Bulk writes need chunk size, retry policy, per-item failure inspection, and reconciliation path.
- Avoid coupling domain invariants only to projection-store constraints; enforce durable invariants in the source-of-truth path.

## Controlled Concurrency

- Fan-out work needs an explicit concurrency limit, timeout, retry count, retry interval, and partial-failure policy.
- Preserve output order or stable key mapping when concurrent work returns out of order.
- Recover panics at task boundaries and convert them into ordinary errors.
- Decide whether the first error cancels remaining work or whether all results should be collected.
- Avoid launching background goroutines from hot paths unless lifecycle, shutdown, and test isolation are defined.

## Inference-As-RPC Client (Go Business → Python Inference)

When a Go business service calls a Python inference service (model server, OCR, VL chat, ML pipeline), the call sits between "regular HTTP/RPC client" and a domain-specific inference protocol. The architecture-layer rules:

- **Transport choice**: HTTP POST + JSON body is the common cross-language transport even when the inference server can speak gRPC or Triton-native. The trade-off is broad client support + easy debugging vs binary efficiency. Document the choice per service tier; do not let one service mix transports across methods.
- **URL construction**: derive the inference endpoint from a `method-name → service-identifier` mapping plus a `GeneratePredictPath(method, version)` helper. Hard-coded inference IPs in business code are a finding. Discovery owns the address; the helper owns the path.
- **Method-level timeout per model SLA**: each inference method has its own SLA (image feature extract ~90 s, image match ~120 s, OCR ~90 s, lightweight classifier ~10 s). The client picks the per-request timeout as `min(method-timeout, config-override, ctx-deadline)`. A single global "inference timeout" is wrong for fleets spanning two orders of magnitude in latency.
- **Per-attempt context discipline**: every HTTP attempt uses a sub-context of the request context. When the caller's deadline elapses, the in-flight call is cancelled. Long-running inference holding the socket past cancellation is a leak.
- **Large payload routing**: when the call carries an image, document, or multi-MB binary, the client uploads via signed URL (object storage) and sends URL + metadata, not inline bytes. Inline base64 is acceptable as a fallback with a documented size threshold. When the inference response is itself a binary, the server side should return a signed URL when possible; if the contract requires inline bytes, do not strip them from the response (that breaks callers) — apply size limits or field redaction at the logger / persistence layer so logs and traces are bounded without changing the wire contract.
- **Signed URL trust on the caller side**: a signed URL is a bearer credential plus a server-side fetch target. When the Go business service constructs the URL for the inference service to fetch, scope it strictly: short expiry (minutes), HTTP method GET (or PUT for upload — exclusive), narrow object key (caller-namespaced), content-length cap, and rotate the signing key on schedule. Log the URL with the signature query parameters redacted. The inference service is expected to validate the bucket/host against its allowlist and reject URLs outside it; design the caller's URL accordingly.
- **Inter-service authN/authZ**: the inference service is not behind an implicit trust boundary just because it sits inside the mesh. The Go caller authenticates with a verified workload identity (mTLS service cert, SPIFFE/SPIRE id, JWT issued by the platform IdP, or k8s service-account token) — the inference service refuses unauthenticated callers. The caller's allowlist on the inference side names which Go services are permitted to invoke which models. Tenant id and resource id carried in the request body are inputs to authorization, not statements of truth; the inference side validates the caller is permitted to use that tenant's / resource's data before loading inputs. Quota / rate-limit per caller × model × tenant is part of the contract; a GPU model is a shared resource.
- **Trace propagation**: every outbound inference request injects `X-Request-ID` and `X-Log-Id` (or the project's equivalent) so the Python service correlates. The Python service reads these headers in middleware once and threads them through every internal log line. Without this, the Go-to-Python call chain breaks at the boundary.
- **Cross-stack ctx-key constants**: define context-key constants in one shared package (e.g. request-id key, business-shard key, experiment-router key — name them per the platform's context-keys convention); business code reads through typed accessors, not raw string keys. The set is part of the inference contract.
- **Failure classification**: HTTP 2xx + envelope `code != success` is a domain inference error; HTTP non-2xx is a transport error. Map both to distinguishable Go error types so business retry and circuit-breaker rules can act differently. Generic `ServerError` swallowing both is a finding.
- **Inference-specific error codes**: reserve a numeric range or a typed error class for inference-side failures (model not found, GPU OOM, input shape mismatch, model load failed, version mismatch). Business code should branch on these without parsing free-text error messages.
- **Bounded retry without circuit breaker is incomplete**: short retry loops (2-3 attempts with backoff jitter) handle transient blips; sustained failure needs a circuit breaker per upstream / per model so the service fails fast and sheds load instead of amplifying the upstream incident.
- **Experiment / traffic routing as data**: when the inference fleet runs multiple model variants concurrently, the routing layer is data (rules with traffic ratio + matcher condition + target model/version), not code branches. Strategy types — A/B, canary, orthogonal, shadow — share one engine. Per-request metadata records the experiment id, variant, and served model version so evaluation can join.
- **TrafficLog persistence**: an out-of-band log of every inference call (caller, callee, method, version, latency, code, message, cost) goes to async storage. Failed call-record writes do not fail the inference call. Benchmark and offline lanes can persist locally for replay.
