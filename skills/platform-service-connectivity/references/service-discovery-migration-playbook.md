# Service Discovery Migration Playbook

Step-by-step playbook for migrating service discovery between modes (registry-based ↔ k8s-native). For the strategic decision — when to migrate vs stay — see `service-discovery-choice.md`. This reference is the **how**.

## Direction A: Registry-based → k8s-native (retiring the registry)

When you've decided the registry's value no longer justifies its operational cost. Typical signals: operational burden (registry cluster + per-language SDKs + log cleanup), drift between registry truth and k8s truth, low usage of registry-only features (per-instance drain, off-cluster direct lookup).

### Phase 0 — Inventory (1-2 weeks)

Before touching code, build a complete dependency map.

```
1. List every framework client/server that uses the registry:
     grep -rE "WithRegistry|WithResolver|nacos|consul|<registry-sdk-import>" <all-service-repos>
2. List every laptop / CI tool that queries the registry directly:
     ops team interview + grep CLI configs
3. List every k8s cluster that runs registry pods:
     kubectl get sts -A | grep <registry>
4. List every cross-cluster federation config / SDK config:
     check registry cluster config for federation peers
5. Identify "registry-only" features in use:
     per-instance drain — search for "weight: 0" set calls
     per-instance metadata reads — search for instance.metadata access
     off-cluster lookup — search laptop tools
```

Output: a checklist with one row per item, status `discovered / mapped / planned / migrated`.

### Phase 1 — Add k8s-native resolver alongside (2-3 weeks)

Make the framework client able to resolve via k8s without removing the registry path.

```
1. Implement k8s-native resolver (per language):
     - Go: use kitex-contrib/registry-kubernetes OR custom k8s-client-based resolver
     - Python: use kubernetes Python client to list Endpoints
     - Other: equivalent k8s client
2. Add as a SECOND resolver, not replacing the first.
3. Make resolver choice a per-service-startup flag or env var:
     RESOLVER_MODE = registry | k8s | dual
   Default: registry (no behavior change yet).
4. Test the k8s resolver against a non-prod lane; verify lane-tag routing works
   via pod labels.
5. Roll the new framework version to all services (no behavior change since
   default mode is registry).
```

Risk: framework version bump must not break anyone. Make sure the new resolver code is exercised in tests but unreachable in default config until Phase 2.

### Phase 2 — Dual-resolve for one release cycle (3-4 weeks)

Run both resolvers in parallel, prefer k8s, fall back to registry, log discrepancies.

```
1. Flip RESOLVER_MODE to "dual" for one non-critical service group.
2. Resolver behavior in dual mode:
     a. Query k8s → result_k8s
     b. Query registry → result_reg
     c. Compare set-equal; if different, log warning with both sides.
     d. Use result_k8s for actual routing.
3. Watch metrics:
     resolver_discrepancy_total{service=X}
   Discrepancies are the gap — services in registry not in k8s, or vice versa.
4. Investigate each discrepancy:
     stale registry instances (registry doesn't know pod is gone) → registry health issue
     missing k8s service/endpoints → service not registering correctly in k8s
     timing skew during deploy → expected; should self-heal
5. Once the discrepancy rate is < 0.1% sustained for 2 weeks, promote the
   service group to k8s-only.
6. Repeat per service group, criticality ascending: dev tools → batch → mid-tier → critical.
```

Risk: silent fallback to registry hides k8s misconfiguration. Make dual-mode discrepancies LOUD — page if discrepancy rate > 1%.

### Phase 3 — Switch service registration off (per group, 2-4 weeks)

When dual mode confirms parity, stop new services from registering to the registry.

```
1. Per service group, flip RESOLVER_MODE to "k8s" only.
2. Remove server.WithRegistry(...) from framework default options for this group.
3. Service no longer writes to registry; relies solely on k8s Service + EndpointSlices.
4. Verify:
     - cross-service calls still work (mesh + VS routing intact).
     - off-cluster laptop tooling works via documented alternative
       (kubectl port-forward / VPN / Telepresence / ingress + lane header).
5. Keep registry cluster running; no clients write anymore, some may still read.
```

After all service groups migrated, no service writes to the registry. The registry still serves reads (for laptop / off-cluster tools using the old path).

### Phase 4 — Migrate off-cluster tools (2-3 weeks)

```
1. Identify every off-cluster tool that queries the registry:
     CLIs, IDE plugins, monitoring scripts, CI runners.
2. For each tool, pick the replacement:
     - Static config tools (point to one prod service) → use ingress + DNS
     - Dev IDE / debug → kubectl port-forward instruction in docs
     - Pipeline runners → control-plane API for any deploy ops; k8s API for lookups
     - Internal monitoring → query k8s API or scrape via Prometheus
3. Update tool docs; remove registry endpoint from tool configs.
4. Ship updated tool versions; deprecate old versions over 1 release cycle.
```

Risk: a forgotten tool still queries the now-empty registry. Mitigation: keep registry running read-only for one extra cycle, monitor read traffic, alert on any source.

### Phase 5 — Decommission registry (1 week)

When registry read traffic from non-platform tools is zero for 2 weeks:

```
1. Audit-retention export: full immutable export of registry metadata + audit log
   to long-term storage (object store with WORM lock, or equivalent).
   Retention policy: 1 year minimum, OR longer if compliance / legal requires.
   Owner: security + platform; signoff required before any deletion proceeds.
2. Restore test: in a sandbox cluster, restore the export and verify queries
   work. If restore is broken, fix it before proceeding.
3. Scale registry StatefulSet to 0.
4. Wait 1 week (real users surface gaps).
5. Delete the StatefulSet + PVCs.
6. Remove the registry MySQL backend (separate task; backup the DB first to the
   same audit-retention storage).
7. Remove infra-namespace YAML manifests for the registry.
8. Archive registry-related code repositories (service_register, component_register,
   etc.) — keep readable but archived; do not delete repos.
9. Update platform onboarding docs: "Service discovery is k8s + Istio; no registry."
10. Run a tabletop drill: simulate a new service deploy from scratch with no
    registry knowledge required.
```

**Do NOT delete a registry without immutable audit export + restore test + security signoff.** Incident investigations 6+ months later may need historical service registration / federation state to reconstruct who-called-what. Once the registry is gone with no export, that evidence is unrecoverable.

### Phase 6 — Reclaim resources

- 3+ registry pods × N replicas (~6-9 GiB memory, 1.5-3 CPU)
- MySQL backend (~10-50 GiB storage)
- NAS storage for registry data + snapshots (~150 GiB across 3 replicas)
- Cross-language SDK build + maintenance time (~1-2 engineer-weeks/quarter)
- Daily log cleanup CI (~1.9 GB/day if naive — now zero)

### Total timeline

For a medium platform (~50 services, 3 languages, 1 cluster):

| Phase | Duration | Risk |
|---|---|---|
| 0. Inventory | 1-2 weeks | low |
| 1. Add k8s resolver | 2-3 weeks | medium (framework change) |
| 2. Dual-resolve burn-in | 3-4 weeks | medium (discrepancies surface) |
| 3. Switch registration off | 2-4 weeks | low-medium (per group, gradual) |
| 4. Off-cluster tool migration | 2-3 weeks | low (tools updated incrementally) |
| 5. Decommission | 1 week | low |
| **Total** | **~3 months active work + 1 month observation** | |

For a large platform (~500 services, polyglot, multi-cluster), budget 2x.

### Rollback path (within migration)

If discrepancies in Phase 2 are too high to clear, OR off-cluster tools cannot be migrated in time:

```
1. Flip RESOLVER_MODE back to "registry" (default in Phase 1).
2. Re-enable server.WithRegistry(...) if it was removed.
3. Keep registry pods running; do not decommission.
4. Document the cause; address in a follow-up cycle.
```

Rollback is cheap if you stop before Phase 5 (decommission). After Phase 5, restoring is a fresh registry install.

## Direction B: k8s-native → Add a thin registry (mixed mode)

For platforms that started k8s-native and now want off-cluster direct lookup without the operational cost of a full registry-of-record.

```
1. Deploy a small registry (e.g. 3 replicas, low resource ask).
2. Run a sync controller (typically ~200 LOC) that watches k8s
   Service + EndpointSlices and writes corresponding entries to the registry.
3. The registry is NOT the source of truth; k8s is. The registry is a
   read-only mirror.
4. Off-cluster tools query the registry; no in-cluster code reads it.
5. Service registration: services do NOT explicitly register; the sync
   controller picks them up from k8s.
```

Pros: in-cluster routing unchanged (k8s + Istio); off-cluster tools get easy lookups.
Cons: an additional system to operate, even if thin.

Skip this entirely if off-cluster lookups can be satisfied by kubectl port-forward / VPN / Telepresence.

## Verification rituals (both directions)

After each phase, run:

```
1. Synthetic deploy: deploy a new dev-lane service; verify it's reachable
   end-to-end from at least one client in each migrated mode.
2. Pod kill: kill one pod of a multi-replica service; verify routing skips
   it within the health check propagation window.
3. Lane routing: send requests with lane header; verify they land on
   lane-matching pods only.
4. Off-cluster reach: from a laptop with the documented path, reach an
   in-cluster service; verify latency is acceptable.
5. Discrepancy scan (dual mode only): resolver_discrepancy_total{} = 0
   or below tolerance threshold for the past 24h.
```

## Anti-patterns during migration

- **Removing the registry path before dual-resolve burn-in clears**: causes silent breakage when k8s and registry disagree.
- **Migrating critical services first**: any framework bug surfaces in the riskiest place. Migrate dev tools and batch first.
- **Skipping the discrepancy investigation**: warnings get ignored, you don't actually achieve parity, then production breaks.
- **Decommissioning registry too eagerly**: a forgotten off-cluster tool fails silently. Keep registry running read-only for at least one full release cycle past Phase 3.
- **Trying to migrate in one big-bang release**: there is no big-bang here. Per-service-group gradual rollout is the only safe path.
- **Mixing migration with framework refactoring**: each is risky on its own. Don't bundle.

## Outcome

After Direction A:
- Single source of truth (k8s API).
- One fewer stateful service to operate.
- Per-language SDKs slim down (drop registry client dependency).
- Bootstrap order simplifies (no SD chicken-egg).
- Off-cluster access goes through documented tooling, not direct lookup.
- Per-instance custom health states (drain, weight-0-without-delete) are lost — accept or design alternatives (e.g. labeled "drain" pod with NetworkPolicy excluding it from traffic).

After Direction B:
- In-cluster routing unchanged.
- Off-cluster lookup becomes easy.
- Thin sync controller adds one moving part; keep it simple.
