# Multi-Region and Multi-Cluster

When and how to leave a single cluster, and what changes about release flow.

## Why leave a single cluster

Drivers (most common first):
- **Failure-domain isolation**: a single cluster outage takes down everything. DR needs separate failure domains.
- **Geographic latency**: users on another continent see > 200ms RTT.
- **Compliance / data residency**: certain data must stay in a jurisdiction.
- **Resource scale**: control-plane limits, node count, etcd size.
- **Noise isolation**: noisy workloads (heavy batch, stress tests) starve neighbors.

If none of these bite, stay single-cluster. Multi-cluster has real ongoing cost.

## Cluster topology patterns

### Active-passive (DR)

- Primary cluster serves all traffic.
- Secondary cluster runs the same workloads at minimum capacity (or scaled down to 0).
- Failover triggered by a documented condition (primary unreachable, latency > X, manual decision).

Recovery objective:
- RPO (recovery point): how much data loss is acceptable.
- RTO (recovery time): how long until secondary serves.

Test with DR drills (see below).

### Active-active

- Both clusters serve traffic concurrently.
- Geographic routing sends each user to the nearest cluster.
- Cross-cluster traffic happens for stateful services that pin to one region.

Higher complexity, lower RTO. Requires:
- Idempotent writes (or single-writer per record).
- Conflict resolution (CRDT, last-writer-wins, vector clocks — pick one and commit).
- Cross-region observability join.

### Per-purpose isolation

- Cluster A: latency-critical services.
- Cluster B: batch / async / stress.
- Cluster C: external-facing edge.

Routes drawn at ingress / mesh boundary. Easier than multi-region.

## Registry federation

If service A in cluster X needs to call service B in cluster Y:

- Both clusters' registries (Nacos / Consul) federate: writes in one are visible in the other (eventually).
- Mesh trust domain must be configured pairwise: A's identity is recognized in Y.
- VirtualService can target a remote-cluster subset.

Without federation, you fall back to direct hostname routing (k8s DNS doesn't cross clusters) — and lose lane-routing. Federation is the right answer.

## Mesh trust domains

mTLS identity is namespaced by trust domain. Cross-cluster mTLS requires:

- Each cluster has a distinct trust domain (e.g. `cluster-1.local`, `cluster-2.local`).
- Cross-cluster AuthorizationPolicy lists peer trust domains.
- Root CA either shared or bridged.

Misconfigured trust domain = "service A cannot reach service B" for unclear reasons.

## Multi-cluster lane semantics

A lane can live in one cluster or many:

| Scenario | Lane spec |
|---|---|
| `dev-alice` for a developer | one cluster |
| `prod` user traffic | sharded across regions, lane-tagged per region |
| `prod-canary` for global rollout | per-region canary lanes; promote independently |

Track which clusters each lane spans. Cross-cluster lane traffic uses the platform's chosen discovery path (registry federation, k8s-native EndpointSlice export, or mesh federation) plus mesh trust.

## DR drill

Annual minimum; quarterly preferred. Drill scope:

```
1. Pick a non-critical service.
2. Mark its primary cluster "unavailable" (without actually taking it down, if possible).
3. Trigger failover to secondary.
4. Run synthetic user traffic against the failed-over service.
5. Measure: RTO (time to first successful response), RPO (data delta), correctness.
6. Switch back.
7. Document gaps; file remediation tickets.
```

If RTO / RPO is worse than declared, fix the gap before claiming the SLA.

Reality check: most platforms have an undrilled DR plan that doesn't work. The first attempt usually surfaces 3-5 blockers. Plan for that.

## Release flow changes

Multi-cluster makes release harder:

- Image must be available in each region's registry (replicate or use a global registry with regional cache).
- Canary in one region first, then expand. Cross-region promotion is a separate gate.
- Config-center: per-region instance, replicated; or global with regional read replicas.
- Secret store: regional, with cross-region replication where compliant.

A change is "fully deployed" only when it's been canary'd and promoted in every region.

## Cross-region observability

Without it, you cannot reason about a global service.

- Traces stitched across regions (OTel collectors federate or push to a global backend).
- Metrics scraped per region, aggregated globally.
- Logs indexed per region with global search (federated query or central aggregation).

Cross-region trace gaps are common; verify in a drill.

## Cost

Multi-region doubles or triples:
- Compute capacity (idle secondary).
- Network egress (cross-region replication).
- Operational complexity (oncall, runbooks, drills).

If business doesn't need it, don't pay it.

## Verification

- Failover drill executed in the last quarter; gaps documented.
- Cross-region call traced end-to-end; trust domains and mesh policy verified.
- Lane `prod` has instances in expected regions; the chosen discovery view matches deployment.
- Image rollback can pull from the regional registry; not dependent on a single source.
- DR runbook exists, was practiced, and reaches steady state within stated RTO.
