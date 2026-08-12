# Service Discovery Recipe

Registry-based SD. Nacos is the recurring example; rules generalize to Consul, etcd, ZooKeeper, or a managed equivalent.

## Why registry, not k8s Service DNS

k8s Service DNS gives you "an IP for `<service>.<ns>.svc.cluster.local`". Registry gives you:
- Per-instance lane / env / region tags.
- Weighted load balancing.
- Custom health states (e.g. drain mode).
- Cross-cluster federation (one logical service, multiple k8s clusters).
- Lane-based subsetting that the SDK resolver consumes.

If you only have k8s DNS, lane-based routing must live entirely in the mesh, and SDK-level weighting/draining is impossible. For non-trivial multi-env setups, that constraint hurts.

## Topology

```
   ┌──────────────────────────────────────────────┐
   │  Registry cluster (e.g. Nacos), N replicas   │
   │  - StatefulSet, headless service             │
   │  - NOT injected into mesh                    │
   │  - Backing store: MySQL or embedded raft     │
   │  - Anti-affinity, multi-AZ                   │
   └──────┬───────────────────────────────────────┘
          │ register / heartbeat / query
   ┌──────┴───────────────────────────────────────┐
   │                                              │
   ▼                                              ▼
┌──────────────┐                          ┌──────────────┐
│ Server pod   │                          │ Client pod   │
│ - Framework  │  on start: register      │ - Framework  │
│   server     │  service+lane+addr       │   client     │
│   suite      │  on shutdown: deregister │   resolver   │
│ - Heartbeat  │                          │ - Caches      │
│   ttl        │                          │   instances  │
└──────────────┘                          │ - Subsets by │
                                          │   lane tag   │
                                          └──────────────┘
```

## Instance metadata (registration)

When a service registers, it MUST include:

```yaml
service_name: <owner>.<class>.<env>           # PSM-style; or service.name OTel attr
ip: <pod IP>
port: <service port>
tags:
  lane: <lane label>
  idc: <region/data center>
  cluster: <k8s cluster name>
  version: <build/image tag>
  weight: <int, default 100>
ephemeral: true                                # auto-deregister on TTL miss
healthy: true
```

Missing `lane` tag = lane routing broken for callers.

## Healthcheck contract

- Service exposes a `/healthz` or `/ping` endpoint that returns 200 only when ready to serve.
- Registry polls or accepts heartbeat (Nacos uses heartbeat).
- Heartbeat interval: 5s; TTL: 15s. Unhealthy instances drop within 15s.
- During pod terminationGracePeriod: deregister first, then drain in-flight requests, then exit. Pre-stop hook is the standard mechanism.

## Resolver behavior in SDK

The framework client resolver:
1. Calls registry on first connect: `select instances of <callee> with lane=<my-lane>`.
2. If 0 instances for current lane, fall back to a documented lane (e.g. `prod` or `default`). Make the fallback rule explicit; "silently fall through" is a bug breeder.
3. Caches instance list with refresh interval (10–30s).
4. Subscribes to registry change events (push) where the protocol supports it.
5. Filters out unhealthy instances per registry-reported state.
6. Load-balances within filtered list (round-robin, weighted, or P2C).

## Cross-language registration

If services span Go, Python, Java, Node: every language SDK must agree on:
- Service name shape (lowercase, dot-separated, no underscores if gRPC is in scope — see `grpc-authority-workaround.md`).
- Tag key names (`lane`, not `env`; pick one).
- Heartbeat interval and TTL.
- Health state semantics.

Document the cross-language contract; do not let each language SDK reinvent.

## Dev / staging / prod differences

| Env | Registry use | Reason |
|---|---|---|
| Local dev | optional; SDK can fall back to direct address from config | dev shouldn't depend on shared registry |
| Per-developer lane in shared cluster | required | callee's lane tag is how mesh routes |
| Staging / pre-prod | required | parity with prod |
| Prod | required | obvious |

Provide a `LOCAL_HOST=...` env var or equivalent for local dev. The SDK switches resolution mode based on env detection.

## Registry sizing

- 3 replicas minimum for HA.
- StatefulSet with persistent backing (MySQL, raft, or built-in).
- CPU/mem: start with 500m / 1Gi requests and 50Gi PVC per member; tune by instance count, heartbeat volume, and retained audit/history.
- Anti-affinity across nodes and AZs.
- Use a headless Service; set `publishNotReadyAddresses: true` only when the registry needs peer bootstrap before readiness.
- `podManagementPolicy: Parallel` can shorten bootstrap for peer-forming registries, but only if the registry tolerates parallel starts.
- DO NOT mesh-inject. Registry bootstraps the mesh; mesh cannot depend on registry that needs mesh to talk.
- If the registry emits high-volume access / raft / change-history logs, attach a log-cleaner sidecar scoped to the registry log subdirectory. Do not mount shared host log roots; use an allowlist and deletion metric.

## Registry snapshot / DR discipline

- Keep immutable registry metadata exports or snapshots on a separate backup path; incident reconstruction can need historical service registration and federation state.
- Snapshot restore is a whole-cluster DR action, not a single-replica repair. Gate restore behind an explicit operator-set DR marker and require the registry StatefulSet to be scaled to 0 first.
- For a single failed member in a healthy quorum, use the registry's native member remove / add or equivalent replacement flow; do not restore an old snapshot into a live quorum.
- Before decommissioning a registry, run a restore test in a sandbox cluster and verify representative service lookup queries work.

## Failure modes

- **Registry briefly unavailable**: SDK uses cached instances for a bounded TTL (e.g. 5 min). Beyond that, request fails — better than calling a dead pod.
- **Stale instances** (registry crashed without cleanup): readiness probe + heartbeat TTL should converge within minutes. Manual cleanup tool needed for outliers.
- **Split brain across DCs**: registry federation; reads local, writes propagated. Local-first reads avoid cross-DC latency.

## Migration off another SD mechanism

If migrating from k8s DNS or another registry, run both side-by-side for a deprecation window:
- Dual-write: services register to both.
- Dual-read: SDK reads from new registry; falls back to old if new returns empty for a service.
- Burn-in: track which services use which path (per-call metric).
- Cutover: stop dual-write per service group once new is proven.
- Tear-down: remove old SDK paths after one full release cycle clean.
