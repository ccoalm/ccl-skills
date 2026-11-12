# Release Runtime Readiness

Use this when designing launch, deployment, traffic, canary, or operating model for a Go microservice product.

## Runtime Model

- Treat runtime metadata as part of the architecture: service identifier, app name, owners, protocol, environment/lane, image, resource profile, replica count, ports, hosts, paths, storage needs, and whether special hardware is required.
- Keep environment/lane separate from authorization/resource scope. Environment/lane routes traffic and controls deployment; resource scope controls data access and authorization.
- Make local, test, staging, canary, and production behavior explicit. Avoid hidden defaults that make a request unexpectedly cross environments.
- Service registration should include discoverable tags for environment/lane and should not require callers to know deployment internals.
- Health and readiness must be defined before traffic is enabled. A simple process liveness endpoint is not enough when DB, Redis, MQ, or critical remote dependencies gate correctness.
- **Go runtime version baseline (2025-2026)**: track at architecture level which Go version the service is built and deployed against, since 1.23/1.24/1.25 each shipped runtime-behavior changes that affect production. (a) **Go 1.25 (released Aug 2025) container-aware GOMAXPROCS**: on Linux the runtime reads the cgroup CPU **bandwidth limit** (not the request) and defaults `GOMAXPROCS` to `min(logical_cpus, cgroup_limit)`; for k8s pods this means `requests: 500m, limits: 4000m` → `GOMAXPROCS ≈ 4` (driven by the limit), so right-sizing CPU **limits** matters more than requests for goroutine scheduling. On all OSes the runtime periodically updates `GOMAXPROCS` if the limit changes — services that historically hardcoded `runtime.GOMAXPROCS(...)` at startup based on `runtime.NumCPU()` were silently over-scheduling under k8s CPU limits; on 1.25 the runtime fixes this BUT a service that still sets GOMAXPROCS manually defeats the auto-tuning. Upgrade discipline: **remove STALE GOMAXPROCS defaults** (hand-set values that were workarounds for the pre-1.25 behavior); **keep MEASURED overrides** when the team has profiled justification — I/O-heavy services that legitimately oversubscribe (set GOMAXPROCS above CPU limit to absorb async wait time), services that reserve a CPU slot for in-pod sidecars by undersubscribing, and services that intentionally pin GOMAXPROCS for predictable GC behavior all remain valid. Treat the upgrade as "audit each manual call → keep with rationale comment OR remove" rather than blanket removal. (b) **Go 1.25 experimental Green Tea GC** (`GOEXPERIMENT=greenteagc`): per Go release notes, reduces GC overhead by 10-40% on many applications — opt-in flag, NOT production-default yet; pilot on a representative non-critical service before flipping production. (c) **Go 1.25 experimental encoding/json/v2** (`GOEXPERIMENT=jsonv2`): faster, stricter, better errors — opt-in flag, track for likely Go 1.26+ stabilization. (d) **Go 1.24 (Feb 2025)** added FIPS-140 mode, crypto/mlkem post-quantum key exchange (auto-enabled in TLS when `Config.CurvePreferences == nil` via X25519MLKEM768) — services with regulatory FIPS requirements gain a stdlib path; services using non-default `CurvePreferences` need to opt into PQ. (e) Pin the build toolchain in `go.mod` `toolchain` directive so reviewers know which version's runtime behaviors apply. (f) **Verify RPC/HTTP framework support for the target Go version before bumping the toolchain** — a runtime baseline is not a mandate to upgrade: frameworks lag (e.g. Kitex's supported Go range per `go-microservice-dev/references/scaffold-and-codegen.md`), so a Go 1.25 service on a framework that only validates 1.19–1.24 must confirm framework compatibility first.

## Deployment Resources

- Generate deployment manifests from typed inputs rather than hand-edited YAML fragments.
- Validate CPU, memory, replica count, image, protocol, ports, and storage before applying a deployment.
- Use stable naming rules for namespace, workload, service, and routing resources so cleanup and rollback are deterministic.
- Separate service-level resources from lane-level resources:
  - Service-level: namespace, internal service, gateway/mesh route, destination/routing policy.
  - Lane-level: deployment, replica count, resource profile, optional storage, image.
- Delete in safe order: (1) shift traffic weight to zero and deregister from service discovery first, (2) wait for in-flight drain (documented grace window), (3) snapshot or verify retention policy on any storage marked durable, (4) delete lane workloads, (5) delete storage only if explicitly tagged ephemeral, (6) finally remove service-level routing and discovery metadata. Deleting workload storage before draining traffic destroys data while requests are still in flight; the destination order matters more than the source order.

## Gateway And Mesh Routing

- Keep domain, host, path, and TLS configuration in typed dynamic config or IaC, not scattered in handlers.
- Expand wildcard domains through a controlled domain registry and reject hosts not owned by the current environment.
- Model route matches explicitly: prefix, exact, regex, method, header, and rewrite behavior.
- Mesh routing should make lane selection observable through a header, tag, or resolver metadata, and should include a clear default route.
- Canary routing should define both caller-based and percentage-based options when the platform supports them.
- Any traffic config update should be atomic for one caller/callee/method route and protected by a write lock or compare-and-swap.

## Release Governance

- Risky changes should have an approval task that records service, lane, run id, pipeline/workspace, reviewers, required approval count, status, expiry, and decision records.
- Approval must be permissioned: only assigned reviewers or explicitly authorized roles can approve or reject.
- Approval state updates need a concurrency guard and a transaction covering reviewer decision plus task status.
- Rejection should win immediately for production-impacting changes; expired approval tasks should fail closed.
- CI/CD callbacks should be idempotent by run id and stage. Missing out-of-order data should be retried for a bounded time, then surfaced as an operations warning.
- Notifications should include service, lane, stage, task, run id, trigger user, reviewers, status, and direct run URL.

## Canary Verification

- A canary is not only a traffic weight. It needs an evaluation window, target pods/instances, baseline comparison, and pass/fail report.
- Compare canary against production or previous stable lane for:
  - new error locations.
  - abnormal error-count growth.
  - latency or saturation regressions.
  - restart count and readiness failures.
  - domain metric regression when available.
- Canary reports should include sample logs, counts, reason, and whether human confirmation is required.
- Store canary task window by service and run id so repeated checks share one time boundary.
- Default canary duration should be short enough for delivery flow but configurable per risk level.

## Rollback And Launch Checklist

- Rollback must cover image, route weight, dynamic config, DB schema compatibility, async messages, and external callbacks.
- Feature flags should default to off or low-scope exposure for behavior changes that cannot be instantly rolled back.
- Backward compatibility requirements:
  - New code can read old and new data shape.
  - Old code can tolerate new optional fields.
  - Consumers can ignore unknown event fields.
  - Producers keep old required fields until all consumers migrate.
- Launch readiness needs named owners, alert routes, dashboard links, runbook, error budget threshold, and escalation path.
- Debug endpoints and profiling must be internal-only and disabled or gated in public-facing environments.
