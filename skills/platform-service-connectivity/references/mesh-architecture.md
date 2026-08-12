# Mesh Architecture

Reference topology and component rules. Istio is the recurring example; rules generalize to Linkerd, Consul Connect, or App Mesh with vendor-specific naming.

## Topology

```
                ┌────────────────────────────────┐
                │  Mesh control plane (pilot/    │
                │  istiod), 1-3 replicas         │
                │  - issues identity / certs     │
                │  - pushes config to sidecars   │
                │  - watches k8s API + registry  │
                └──────┬─────────────────────────┘
                       │ xDS config
        ┌──────────────┼──────────────┬───────────────┐
        ▼              ▼              ▼               ▼
   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌──────────────┐
   │ Pod A   │    │ Pod B   │    │ Pod C   │    │ Ingress      │
   │ ┌─────┐ │    │ ┌─────┐ │    │ ┌─────┐ │    │ Gateway      │
   │ │ app │ │    │ │ app │ │    │ │ app │ │    │ (Envoy)      │
   │ └──┬──┘ │    │ └──┬──┘ │    │ └──┬──┘ │    └──────┬───────┘
   │    │    │    │    │    │    │    │    │           │
   │ ┌──▼──┐ │    │ ┌──▼──┐ │    │ ┌──▼──┐ │           │
   │ │Envoy│◄┼────┼─┤Envoy│◄┼────┼─┤Envoy│ │           │
   │ │side │ │    │ │side │ │    │ │side │ │           │
   │ │car  │ │    │ │car  │ │    │ │car  │ │           │
   │ └─────┘ │    │ └─────┘ │    │ └─────┘ │           │
   └─────────┘    └─────────┘    └─────────┘           │
                                                       │
   Client traffic ─────────────────────────────────────┘
```

## Istio Ambient Mode (GA Nov 2024, v1.24+)

- **Istio Ambient Mode reached General Availability in Istio v1.24 (announced November 2024)** per `istio.io/latest/blog/2024/ambient-reaches-ga/` — `ztunnel` + `waypoint` architecture is the stable sidecar alternative for new production mesh deployments. **Two-layer split**: `ztunnel` (Rust-based DaemonSet, one per node, L4-only — mTLS + simple L4 authz + telemetry) handles every pod's transport-layer mesh participation without per-pod sidecar injection; `waypoint` proxies (Envoy-based, scaled independently from app workloads) handle L7 features when needed (rich authz, traffic routing, resilience). Per Istio's own reported numbers, the architecture can save 90%+ memory/CPU vs the sidecar model in dense-pod-per-node workloads (Istio's claim — re-measure on the team's actual workload before quoting savings). **Architecture choice for new mesh**: (a) **choose ambient** when memory/CPU per pod is the binding constraint, sidecar injection causes restart cycles the team wants to avoid, or a subset of namespaces don't need L7 features at all; (b) **stay on sidecar mode** when the team has deep sidecar-specific tooling (custom `EnvoyFilter`s injected per pod, sidecar-aware debugging recipes, app code that expects `localhost:15001` proxy conventions), or when ambient's narrower L7-feature coverage hits a gap the team relies on. **Mixed-mode in one cluster is officially supported** per the Istio docs: sidecar-mode namespaces and ambient-mode namespaces coexist; migration can be incremental namespace-by-namespace. **CRITICAL migration block: AuthorizationPolicy enforcement loss when flipping a namespace from sidecar to ambient without waypoint** — sidecar mode enforces full L7 `AuthorizationPolicy` rules (HTTP method, path, header, JWT claims) at the per-pod proxy. In ambient mode, ztunnel alone enforces only L4-level policy (workload identity, port); any L7-condition rule (`request.method`, `request.headers[...]`, `request.path`, `request.auth.claims[...]`) silently DOES NOT MATCH on ambient-mode pods until a waypoint proxy is deployed for the namespace/service and the policy is targeted at the waypoint. The failure shape: team flips `istio.io/dataplane-mode=ambient` label, sidecar comes down, ztunnel takes over L4, and every L7 authz policy stops gating traffic — without a visible error, because L4 policy still works. **Pre-flip gate**: inventory every `AuthorizationPolicy` targeting workloads in the namespace, identify the ones using L7 conditions, ensure a waypoint is deployed and the policy `targetRefs` is set to the waypoint (not the workload) BEFORE flipping the namespace label. Validate by re-running the authz integration tests against the ambient-mode namespace before completing the migration. **Observability shift**: ztunnel emits L4 metrics; waypoint emits L7 metrics; existing dashboards keyed on sidecar `istio_requests_total` need a ambient-mode equivalent for the L7-routed traffic — route this update through `platform-observability` rather than redesigning here.

## Sidecar injection rules

- **Default** (sidecar mode): every workload namespace labelled `istio-injection=enabled` (or pod-level `sidecar.istio.io/inject: "true"`). For ambient-mode namespaces, sidecar injection is OFF; the ambient-mode label and ztunnel DaemonSet handle participation instead.
- **Opt-out cases** (each must be documented):
  - Telemetry collectors (would loop).
  - Log-shipping DaemonSets (hostPath access, no app traffic).
  - Service registry pods (mesh would bootstrap-cycle).
  - Mesh control plane itself.
  - Pure batch jobs that don't communicate with services.
- **Verification**: `kubectl get pods -A -o jsonpath='{.items[?(@.spec.containers[*].name=="istio-proxy")].metadata.name}'` should cover ~all app pods.

## Mesh config minimums

```yaml
meshConfig:
  accessLogFile: "/dev/stdout"       # log to stdout, captured by file-collector daemonset
  accessLogFormat: |
    { "start_time": "%START_TIME%",
      "method":     "%REQ(:METHOD)%",
      "path":       "%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%",
      "protocol":   "%PROTOCOL%",
      "host":       "%REQ(HOST)%",
      "log_id":     "%REQ(<log-id-header>)%",
      "lane":       "%REQ(<lane-header>)%",
      "response_code":     "%RESPONSE_CODE%",
      "x_forwarded_for":   "%REQ(X-FORWARDED-FOR)%",
      "upstream_host":     "%UPSTREAM_HOST%",
      "upstream_cluster":  "%UPSTREAM_CLUSTER%" }
  enablePrometheusMerge: true        # Envoy stats merged into app's Prom scrape
```

The access log JSON shape MUST include `log_id` and `lane`. These are the join keys between mesh logs and app logs.

`enablePrometheusMerge` saves an entire scrape target per pod; Envoy stats appear in the same `/metrics` endpoint as the app.

## Gateway

One default ingress gateway per environment is the baseline. The gateway terminates TLS, applies WAF/rate-limit if needed, and routes to mesh-internal services.

```yaml
kind: Gateway
spec:
  selector:
    istio: ingressgateway
  servers:
    - port: { number: 80, name: http, protocol: HTTP }
      hosts: ["<public-host-pattern>"]
    - port: { number: 443, name: https, protocol: HTTPS }
      hosts: ["<public-host-pattern>"]
      tls: { mode: SIMPLE, credentialName: <tls-secret> }
```

Egress gateway is OFF by default. Turn ON only when a workload needs controlled external access (compliance, audit, retry).

## EnvoyFilter usage

EnvoyFilter is the escape hatch. Use sparingly; each filter is hard to test and easy to break across Envoy upgrades.

Acceptable uses:
- Header rewrite for protocol quirks (e.g. gRPC `:authority` hyphenation — see `grpc-authority-workaround.md`).
- Adding a Lua filter for one-off business handling that doesn't yet have a first-class WASM filter.
- Custom rate-limit before the canonical RLS is rolled out.

Unacceptable uses:
- Disabling mTLS for a specific service to "fix" a connectivity issue (root-cause it).
- Removing access log fields per service (breaks log-join).
- Inline business logic (mesh is not a runtime — push to a sidecar service if you really need it).

## What mesh owns vs framework owns

| Concern | Mesh | Framework client/server middleware |
|---|---|---|
| TLS / identity | YES (mTLS) | NO |
| Connection retry (network errors) | YES | NO (don't double-retry) |
| Per-call business retry (idempotent op) | NO | YES, with idempotency awareness |
| Transport timeout | YES (ceiling) | YES (per-call budget, ≤ ceiling) |
| Business deadline | NO | YES (ctx.Deadline) |
| Circuit breaker / outlier detection | YES | (fallback if mesh absent) |
| Load balancing | YES (topology-aware) | YES (resolver level) |
| Lane routing | YES (VirtualService) | Sets the lane label; doesn't pick routes |
| Authn/authz at network | YES (AuthorizationPolicy) | NO |
| Authn/authz at request | NO | YES (or in service handler) |
| Log-id propagation | Passes through; logs it | Sets it, extracts it |

## Failure modes to test

- **Sidecar crashed**: pod fails readiness; mesh control plane re-pushes config; rolling restart needed?
- **Mesh control plane unreachable**: existing sidecars keep last config (sidecars are stateless data-plane proxies); new pods can't start.
- **mTLS cert expiry**: control plane rotates; verify rotation works under load.
- **Mesh upgrade**: data plane behind control plane is allowed; control plane behind data plane is not.
