# Service Discovery: Registry vs k8s-Native (Pick One, or Mix)

Service discovery is a platform choice, not a mandate. Both **registry-based** (Nacos / Consul / etcd / managed equivalent) and **k8s-native** (Service + EndpointSlices + pod labels) can support lane-based multi-env routing, canary, A/B, and shadow traffic. Pick by the team's actual needs.

## The two modes side-by-side

| Capability | Registry-based | k8s-native |
|---|---|---|
| In-cluster service lookup | SDK queries registry | k8s DNS resolves `<svc>.<ns>.svc.cluster.local` |
| Lane filter | instance metadata tag | pod label `lane:` + VirtualService subset |
| Per-developer dev lane | new instances registered with lane tag | new Deployment with lane label |
| Canary % | per-instance weight OR VS weight | VS weight + DR subsets |
| Header-match A/B | SDK filter + VS | VS headers.match |
| Shadow / mirror | SDK custom | VS mirror |
| Per-instance custom health (drain, weight-0 without delete) | YES — registry metadata mutable | NO — k8s readiness is binary |
| Out-of-cluster client (laptop) direct lookup | YES — laptop SDK queries registry | NO — must use kubectl port-forward / VPN / Telepresence |
| Multi-cluster federation | registry federation (Nacos / Consul cluster mesh) | Istio multi-cluster |
| Cross-language SDK | requires per-language registry client | k8s client-go in Go; HTTP API in any language |
| Bootstrap order | SD must exist before services (chicken-egg if SD itself needs SD) | k8s API is the bootstrap layer; everything depends on it anyway |
| Operational burden | dedicated cluster (3+ replicas, MySQL backend, log cleanup, snapshot DR) | piggyback on existing k8s control plane |
| Drift between registry truth and k8s truth | possible (registry says healthy, pod actually unscheduled) | impossible by definition |

Both can do **multi-env parallel dev** and **online multi-env experiments**. The choice is about secondary capabilities and operational burden.

## When registry-based is the better fit

Pick registry-based SD when ≥ 2 of these are true:

1. **Per-instance drain / weight tuning** matters operationally — e.g. you want to slowly remove a problematic replica from rotation without scaling down the Deployment.
2. **Out-of-cluster clients are common** — laptop dev SDKs, CI runners, external test harnesses query for instance IPs directly without tooling intermediation.
3. **Cross-cluster federation feels natural** with the registry's federation primitives and you've already invested in operating it.
4. **Polyglot platform with mature registry SDK in each language** — Go, Java, Python all have first-class clients you trust.
5. **Existing platform already runs the registry** — the migration cost outweighs the operational savings.

## When k8s-native is the better fit

Pick k8s-native SD when ≥ 2 of these are true:

1. **Operational simplification** outweighs per-instance tuning needs — one fewer stateful service, no separate SDK to ship in every language.
2. **Single source of truth** matters more than registry-level flexibility — drift between registry state and k8s state has burned the team before.
3. **Laptop dev workflow tolerates** kubectl port-forward / Telepresence / VPN.
4. **Istio multi-cluster** is acceptable for cross-cluster needs (or no multi-cluster need).
5. **Greenfield platform** — no sunk cost in a registry to amortize.

## Mixed / transitional mode

Common pattern: **k8s-native for east-west service-to-service; registry-based for laptop / out-of-cluster access**.

```
In-cluster pod → in-cluster pod
  → k8s Service DNS + VS subset routing
  → fast, no SDK dependency on registry

Laptop SDK → in-cluster pod
  → query small read-only registry (sync'd from k8s)
  → or use kubectl port-forward
```

The registry runs as a thin **k8s → registry sync** sidecar; only laptop/CI clients use it. In-cluster code uses k8s DNS. Reduces registry load drastically.

## Migration paths

### Adding registry (k8s-native → mixed)

If you start k8s-native and later want laptop direct lookup:

1. Deploy a small registry instance (3 replicas, modest sizing).
2. Run a sync controller: watch k8s Service + EndpointSlices, write to registry.
3. Give laptop SDKs the registry endpoint.
4. In-cluster code unchanged — still uses k8s DNS.

### Removing registry (registry-based → k8s-native)

If your platform inherited registry-based SD and you want to drop it:

1. **Inventory**: list every language SDK that uses the registry; every framework `withRegistry` / `WithResolver` configuration; every laptop tool that queries it.
2. **Add k8s-native resolver** as a parallel resolver in the framework client.
3. **Dual-resolve for a deprecation window**: query both, prefer k8s, fall back to registry, log discrepancies. Run for ≥ 1 release cycle.
4. **Migrate laptop tools** to kubectl port-forward / VPN / Telepresence.
5. **Decommission registry pods**, then SDKs, then the sync.

Estimated work for a medium platform (~50 services, 3 languages): 1-2 quarters.

## What this means for the platform skills

The other references in this skill cover both modes:

- `service-discovery-recipe.md` — registry-based concrete recipe (Nacos as the example).
- `mesh-architecture.md` — mesh layer is independent of SD choice; works with either.
- `rpc-framework-recipe.md` — RPC base.Request + ctx propagation work regardless of resolver type.
- `multi-env-routing.md` — lane primitives use pod labels (k8s-native) AND/OR registry tags; the routing rules are the same.

A platform team adopting this skill family picks the SD mode separately and reads the relevant reference accordingly. No skill mandates the registry choice.

## Hard rules that apply to either mode

1. Lane is propagated through every hop regardless of SD mechanism.
2. Mesh handles mTLS / connection retry / transport timeout — SD is not in this path.
3. Health is a real thing: registry heartbeat OR k8s readiness; either is fine, but it MUST exist and be honored at routing time.
4. Bootstrap dependencies are documented: which component depends on which at startup. (k8s API → DNS → mesh control plane → app pods, OR k8s API → SD cluster → mesh control plane → app pods.)
5. Out-of-cluster access has a documented path: registry direct, OR port-forward + VPN, OR ingress + lane header — choose at least one.

## Verification

- A new service registers (registry-mode) or has a k8s Service created (k8s-mode) within seconds of pod ready.
- A lane-tagged request routes to lane-matching pods, and only to lane-matching pods.
- A canary deploy shifts traffic via VS weight; verify access logs show the new ratio.
- Killing one pod removes it from rotation within the health-check propagation window (≤ 15s typical).
- An out-of-cluster client (laptop) can reach a service using the documented path; document the latency and any setup steps required.

## Kubernetes Gateway API Baseline (v1.0 GA Oct 2023 → v1.5 Apr 2026)

- **Gateway API v1.0 (per `kubernetes.io/blog/2023/10/31/gateway-api-ga/`, released Oct 2023) graduated Gateway / GatewayClass / HTTPRoute to v1 GA**, the replacement for the legacy `Ingress` API for new platform deployments. Subsequent releases: **v1.1 (May 2024)** graduated GAMMA (service mesh support) and **GRPCRoute** to Standard channel; **v1.5 (Apr 2026)** moved further experimental features to Stable per `kubernetes.io/blog/2026/04/21/gateway-api-v1-5/`. **Architecture choice for ingress / north-south traffic**: (a) **default to Gateway API HTTPRoute** for new clusters — explicit resource model (Gateway = listener + cert + class, HTTPRoute = routing rules) cleanly separates infrastructure-owner concerns from application-owner concerns; supports cross-namespace routing via `ReferenceGrant` (no more sharing namespaces just to reuse one ingress object); stable schema with GA backward-compat. (b) **keep legacy Ingress** only for clusters where the ingress controller has not yet adopted Gateway API or where downstream tooling (cert-manager Ingress-specific integration, monitoring dashboards keyed on `ingress.kubernetes.io/...` annotations) hasn't migrated; flag those as platform debt. **For service mesh GAMMA (east-west traffic)**: the same HTTPRoute resource configures east-west traffic policies, eliminating mesh-vendor-specific CRDs (Istio `VirtualService` / Linkerd `ServiceProfile`) for new policies — verify the team's mesh implementation supports GAMMA (Istio 1.24+ per ambient-GA cycle, Linkerd 2.16+, Cilium 1.16+) before standardizing on it. **Migration policy**: do not mass-migrate existing Ingress → Gateway API in one slice; convert per ingress as touched for other reasons, run a smoke test against the new HTTPRoute object before deleting the legacy Ingress, and verify cert-manager / monitoring / WAF tooling has Gateway API equivalents wired up. **Split-brain mitigation for clusters running both Ingress and Gateway API**: most modern ingress controllers (Istio Gateway, Envoy Gateway, NGINX, Contour, etc) support BOTH the legacy Ingress object AND Gateway API HTTPRoute. If two route objects (one Ingress, one HTTPRoute) bind to the same host or share an overlapping route, precedence is controller-specific and NOT standardized by Kubernetes — the team gets non-deterministic routing depending on the controller version and config. Required policy: declare **one route-type owner per host** at the platform level (either the host is Ingress-managed OR HTTPRoute-managed, never both), enforce via admission webhook or a CI check that scans for Ingress + HTTPRoute overlap on the same `hostnames`; during the per-ingress migration, delete the legacy Ingress in the same commit/PR that creates the HTTPRoute. Mixed ownership without a precedence rule is a P0 routing-correctness risk for production traffic.
