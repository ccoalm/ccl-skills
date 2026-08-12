# Environment and Lane Matrix

## Why "lane" instead of "environment"

"Environment" suggests a small fixed set: `dev`, `staging`, `prod`. Real platforms grow:

- Per-developer lanes (one developer's in-progress version of a couple of services).
- Per-integration-test lanes (ephemeral, deleted after test run).
- Long-lived stages (`dev`, `pre`, `staging`, `prod`).
- Canary subsets within prod (`prod-canary-1pct`).
- Shadow traffic targets (`prod-shadow`).
- Stress-test lanes.

All share routing primitives (registry tag or k8s label plus mesh routing — see `platform-service-connectivity`). The release skill treats them uniformly: each lane is a deploy target.

## Lane object shape

```yaml
lane:
  name: <unique-name>
  parent: <fallback-lane>          # if request lane has no instances, fall to parent
  type: long-lived | ephemeral | canary | shadow | stress
  expires_at: <timestamp>           # required for ephemeral; absent for long-lived
  owner: <team-or-individual>
  services: [<service-names>]       # services deployed in this lane
  traffic_weight: <0-100>            # only for canary/shadow subsets within a parent
  protected: true | false           # protected lanes cannot be deleted without explicit override
```

Long-lived lanes are protected. Ephemeral lanes auto-delete past expiry.

## Standard long-lived lanes

| Lane | Purpose | Traffic source |
|---|---|---|
| `prod` | live user traffic | external clients, ingress |
| `pre` | pre-production validation | internal smoke + load tests |
| `staging` | pre-pre, integration tests | CI |
| `dev` | shared dev environment | engineers, internal tools |

Some platforms add `gray` or `inner-prod` for internal employee dogfooding. Add only when there's a real signal it produces; don't proliferate.

## Per-developer lanes

A developer working on service A wants to test against the real `prod` versions of B, C, D, while running their own A. Lane mechanism:

1. Developer deploys their A under lane `dev-<name>`.
2. Their requests carry `<lane-header>: dev-<name>`.
3. Mesh VirtualService routes:
   - A: to `dev-<name>` subset (their version).
   - B, C, D: no `dev-<name>` subset → fall back to `prod` (or `dev` shared, depending on policy).
4. Developer's `dev-<name>` lane expires after N days (e.g. 7) unless renewed.

This lets one developer iterate without cluster-wide effect. Multiplied by team size, it works only if lane creation is cheap (control-plane API, not manual k8s).

## Ephemeral lanes for CI

Integration tests that need real services (not mocks) create a lane per test run:

```
lane name: it-<test-id>-<commit>
parent: pre
type: ephemeral
expires_at: now + 4h
services: [services-under-test]
```

CI deploys the under-test versions to the lane, runs tests with `<lane-header>: it-...`, then deletes the lane. Lane lifetime is bounded by test duration + grace.

## Canary lanes

A canary is a subset of `prod` with its own subset name:

```
lane name: prod-canary-v2.5.0
parent: prod
type: canary
traffic_weight: 1   # 1% to start
services: [the-one-being-rolled-out]
```

VirtualService weight shifts from canary to stable over the rollout window. See `canary-and-rollout-strategy.md`.

## Shadow lanes

Shadow receives a mirror of prod traffic without affecting user response:

```
lane name: prod-shadow
parent: prod
type: shadow
services: [services-being-shadowed]
```

Shadow target's responses are dropped. Metrics from shadow MUST be tagged so they don't contaminate prod SLIs.

## Cluster / region mapping

Lanes live in clusters. Common topologies:

| Topology | When |
|---|---|
| Single cluster, all lanes | Small platform; everything fits |
| Per-region cluster, lanes mirrored | Geographic latency or compliance |
| Per-lane-type cluster | Heavy stress / shadow isolation |
| Per-team cluster | Late stage; high cost; only when noise isolation is critical |

Document the mapping. Each lane declares its cluster. Cross-cluster lane traffic requires the platform's chosen cross-cluster discovery or mesh federation path (`platform-service-connectivity`).

## Lane policies

Beyond pure routing, lanes carry policy:

- **Resource quotas**: dev / canary lanes get smaller pod counts.
- **Data isolation**: prod and pre have different DB instances; sharing is a leak.
- **Network egress**: dev may have looser external access; prod may have stricter.
- **Observability retention**: prod traces kept 30 days; ephemeral lanes 1 day.

Policies are enforced by namespace labels + admission controllers + mesh AuthorizationPolicy.

## Verification

- `lane list` returns all lanes with type and owner. `lane get <name>` returns services + expiry + traffic weight.
- A new ephemeral lane is reachable end-to-end within minutes of creation.
- A lane deleted leaves no orphaned routing/discovery resources (Deployment, Service, VirtualService subset, registry tag or k8s label selector).
- A request with an unknown lane header falls back to the documented parent lane and logs the fallback (so silent fallback can be detected).
