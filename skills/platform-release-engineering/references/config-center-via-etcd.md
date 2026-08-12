# Config Center Implementation via etcd

Concrete implementation pattern for the **dynamic config tier** described in `secret-and-config-management.md`. Distilled from production deployments.

## Why etcd

etcd v3 is a mature, widely-deployed key-value store with built-in Watch (push-based change notification) and strong consistency. Using it as the config-center backend means:

- No custom config service to build/maintain.
- Watch semantics are well understood; SDKs exist in every language.
- The k8s cluster already runs etcd (for the cluster state), so the operational expertise is already on-team.
- Atomic single-key updates; multi-key transactions available when needed.

Trade-offs:
- etcd is not optimized for high-rate reads from thousands of subscribers — add a client cache layer.
- etcd cluster size and resource sizing matter; sharing the k8s control plane etcd with config workload is a bad idea — deploy a **separate** etcd cluster for config.
- Not great for large values (>1 MB); keep payloads small or chunk them.

## Deployment

```
Cluster
  observability namespace: <unrelated>
  config (or "infra") namespace:
    etcd cluster:
      3 or 5 replicas, StatefulSet
      PVC-backed
      NOT mesh-injected (mesh depends on dcc bootstrap is OK; mesh on top of dcc is not)
      Service name in-cluster: <config>.<ns>.svc.cluster.local:2379
      Exposed externally (for off-cluster developers/CLI) via SD or LB
```

Use a distinct StatefulSet, not the k8s control plane etcd. Sharing the same etcd cluster invites coupling and a single failure domain.

## Config-center sizing and DR

- Run 3 replicas minimum; use 5 only when the write/read quorum tradeoff is justified.
- Start with roughly 50Gi per member for small-to-medium platforms, then tune by key count, watch history, compaction policy, and snapshot retention.
- Keep config-center member data on per-member PVCs. Store backups/snapshots on a separate backup volume or object store, not only on the member's own PVC.
- Do not mesh-inject config-center pods if the mesh or platform SDK needs config-center during bootstrap.
- Snapshot restore is a whole-cluster DR action. Gate restore behind an explicit operator-set DR marker, require the StatefulSet to be scaled to 0 first, and use the component's native member remove / add path for single-member repair.
- Emit disk usage, leader changes, watch reconnects, compaction errors, and snapshot age metrics. Alert before disk pressure, not after etcd refuses writes.

## Key namespace shape

A three-level key path keeps configs organized:

```
/<service_psm>/<namespace>/<key>
```

- `service_psm` — the owning service (`<owner>.<class>.<env>` style). Per-service ACLs and quotas apply at this level.
- `namespace` — a scope within the service. `default` for general config. Useful examples: `default`, `lane:<lane-name>`, `feature-flags`, `traffic`. Multi-namespace under one service lets a service segment fast-changing flags from rarely-changed deploy parameters.
- `key` — the actual config key.

Example keys:
```
/payments.api.prod/default/feature_v2_enabled         → "true" | "false"
/payments.api.prod/default/rate_limit_per_user         → "100"
/payments.api.prod/default/domains                     → <json array>
/payments.api.prod/default/chat_app_ref                → <secret-store reference, NOT credentials>
/payments.api.prod/default/notice_chat_info            → <chat channel IDs only, NOT tokens>
/payments.api.prod/default/service_resource            → <json map psm → lane → resource>
/payments.api.prod/traffic/<callee_psm>                → <json traffic-config>
```

**What NOT to store** (despite the examples that might tempt you):
- Cluster kubeconfig content (PEM cert + auth token) — use the secret store; etcd reads in the config center are typically broad-readable to developers and CLI tools.
- App credentials (chat platform app secret, OAuth client secret, registry tokens) — same reason.
- Database passwords, API keys.
- Per-tenant secrets.

Store **secret-store references** in etcd (`{"secret_id": "chat-app/prod-v1"}`) and have the consuming service resolve the actual secret from KMS / Vault / equivalent. This way, even broad etcd read access doesn't leak the secret material.

The line "no secret etc." appears in the section below, but it's easy to copy an example. The examples above have been corrected — your platform's reviewers should reject any PR that adds a credential-shaped string to a non-traffic key.

## SDK contract

Minimal SDK API every language must provide:

```
NewDynamicConfig(psm, namespace) → client
client.Get(ctx, key) → []byte, error
client.GetString(ctx, key) → string, error
client.GetJson(ctx, key, &dest) → error
client.Set(ctx, key, value []byte) → error
client.Del(ctx, key) → error
client.AddListener(ctx, key, callback) → ListenerCloser
```

Operations:
- **Get / GetString / GetJson** — read once, return value or `not found`.
- **Set / Del** — typically used by operator/control-plane, not by app code.
- **AddListener** — etcd Watch wrapped in a callback API; cancellation via the returned closer.

Read timeout: 5 seconds is a common default. Longer than typical request budgets but short enough to avoid hanging a service start.

## Endpoint discovery

Where does the SDK find the etcd cluster?

```
In cluster (pod):
  endpoint = "<config>.<ns>.svc.cluster.local:2379"   # k8s DNS, fixed.

Out of cluster (developer laptop, off-cluster CLI):
  endpoint = sd.LookupEndpoints("<config-center-psm>")  # registry-based; refresh periodically.
```

Off-cluster path refreshes endpoints every 10 seconds. The SDK reconnects when endpoints change.

The off-cluster path needs the SD client (registry) which is itself a bootstrap dependency. Document the bootstrap order:

```
1. Resolve SD endpoint (typically a static DNS or env var; cannot depend on dcc).
2. Resolve dcc endpoints via SD.
3. Then everything else can read dcc.
```

## Watch / listener

etcd Watch is push-based; the SDK wraps it:

```
rch := etcd.Watch(ctx, key, clientv3.WithPrevKV())   # PrevKV option required to see ev.PrevKv
go {
  for resp := range rch {
    for ev := range resp.Events {
      callback(ctx, ev)   # ev.IsCreate(), ev.IsModify(), ev.Kv.Value
                          # ev.PrevKv populated only if WithPrevKV was passed and key was modified/deleted
    }
  }
}
```

Event types: Create, Modify, Delete. Each event carries the new Kv. `ev.PrevKv` is populated **only when the Watch was created with the `WithPrevKV` option** AND the event is a Modify or Delete (Create has no previous); always nil-check before use.

For watch resume after a network blip: persist the last seen revision from `resp.Header.Revision` and pass `clientv3.WithRev(<revision+1>)` on reconnect. etcd retains history within compaction limits — events between disconnect and reconnect are recoverable from the saved revision, not lost outright. If reconnect happens after compaction, the watch returns `ErrCompacted` and the SDK must do a full re-read of subscribed keys.

Listener lifetime:
- Created with a parent context; cancelled via `ListenerCloser`.
- One goroutine per listener.
- The SDK MUST recover from panics in the callback; one bad callback should not bring down the goroutine pool.

## Local cache (mature SDK addition)

The reference SDK without cache hits etcd on every Get — bounded latency (one round-trip) but multiplies etcd load with subscriber count. A mature SDK adds:

```
LRU cache with TTL:
  - On Get(key):
      if cache.has(key) && !expired:
          metric: cache_hit_counter ++
          return cache.get(key)
      else:
          val = etcd.Get(key)
          metric: cache_miss_counter ++
          cache.set(key, val, TTL)
          return val
  - On Watch event for key:
          cache.invalidate(key)
  - On etcd error:
          metric: error_counter ++
```

Cache TTL: 30 seconds to a few minutes. Long enough to absorb burst reads; short enough that a writer's value propagates if Watch is missed.

**Split-brain config during partitions**: if some clients reconnect their watch and pull the new value while others remain on the old (stale Watch + still-warm cache), the fleet runs on mixed values. For **dangerous policy values** (retry budgets, circuit-breaker thresholds, kill switches, rate limits), this can produce uneven load amplification. Mitigations:
- **Version every config value**: include a monotonic version field in the JSON payload; client emits a metric `config_version_in_use{key, version}`. Operator can see fleet-wide adoption.
- **Max-staleness enforcement**: if the SDK detects its Watch has been disconnected for longer than `2 × cache_TTL`, treat the cache as expired and force a re-read. If the re-read also fails, fail closed for safety-critical keys (e.g. kill switches default to "off") or warn for non-critical.
- **Fail-closed defaults for dangerous keys**: a key like `payment_double_charge_protection` should default to "on" (safe) if the SDK cannot reach the config center; not "off" (silent-fail). Encode the safe default in code, not in etcd.
- **Per-version adoption gating**: a deploy that flips a policy should query `config_version_in_use` and wait for >95% adoption before proceeding to the next step.

Metrics emitted (all with baseline labels):
- `dcc_client_operations_counter` — labelled by op (get/set/del/watch).
- `dcc_client_cache_hit_counter` / `dcc_client_cache_miss_counter` — by key.
- `dcc_client_error_counter` — by op + error class.

Without these metrics you cannot tell whether the cache is doing its job.

## Common stored payload types

Real deployments store a mix of non-secret payloads:

| Payload | Type | Update cadence | Read cadence |
|---|---|---|---|
| Domain / hostname list | JSON array | weekly | per-service-startup |
| Secret-store references for external services | JSON reference id | rare (rotation) | per-service-startup |
| Chat group routing config (notice channel IDs) | JSON | monthly | per-alert |
| Per-service per-lane resource sizing | JSON map (psm → lane → {cpu, memory, replicas, size}) | per deploy | per-deploy |
| Per-caller-callee traffic policy | JSON (timeout, retry, CB) | daily | per-RPC-call (cached) |
| Feature flags | string / JSON | hourly | per-request (cached) |

**Different payloads need different cache TTLs**. Feature flags MUST update fast; stable domain lists can be cached longer.

## What NOT to put in etcd

- Secrets (use the secret store).
- Per-request state (use Redis / DB).
- Audit logs (use audit log infra).
- Large blobs (> 1 MB).
- Anything that needs ACID across multiple keys (etcd supports transactions but the SDK rarely exposes them; use a relational DB for transactional needs).

## Operator interface

Operators write to etcd via the control-plane API, not via raw etcd commands:

```
PUT /v1/config/{service}/{namespace}/{key}     body: value, audit_reason
GET /v1/config/{service}/{namespace}/{key}     → value, version, last_modified, modified_by
GET /v1/config/{service}/{namespace}           → list keys
DEL /v1/config/{service}/{namespace}/{key}     body: audit_reason
```

The control plane:
- Authenticates the operator.
- Validates the value (JSON shape, range, allowed enum).
- Acquires a per-key write lock (Redis lock for ~10s) to prevent racing writers.
- Writes to etcd.
- Emits audit event (who changed what to what, when, why).

Direct `etcdctl put` access should be limited to platform admins for break-glass; routine changes go through the control plane.

## Off-cluster developer access

Developers and CLIs that run outside the cluster reach dcc via:
- The same control-plane API (read-only for most developers; write requires role).
- OR a direct etcd connection if their role permits — usually for SDK debugging only.

Do not give every developer raw etcd write access; one mis-keyed `put` corrupts config for a whole service.

## Failure modes

- **etcd cluster split (minority partition)**: by default etcd uses linearizable reads which require quorum/leader contact — clients on the minority side typically fail reads, not return stale data. If your SDK explicitly enables serializable reads (`clientv3.WithSerializable()`), reads can succeed locally but may be stale; document the choice. Writes always fail on the minority side.
- **Watch stream drops** (network blip): SDK reconnects from the last observed revision (saved from `resp.Header.Revision`) — events within the compaction window are recoverable. Beyond compaction, the SDK gets `ErrCompacted` and must do a full re-read of subscribed keys. Best practice: track last revision per watch + periodic full re-read (e.g. every 5 min) as belt-and-suspenders.
- **Cache stale**: If the Watch reconnect didn't recover all events (compaction window exceeded) and cache TTL is long, readers see stale values. Tune TTL by payload sensitivity; on watch reconnect failure, invalidate the cache for the affected keys.
- **etcd cluster full**: rare but real. Monitor etcd disk usage; alert at 60% / 80%.

## Verification

- Read a value via SDK, change it via control plane, expect SDK listener fires within 1 second.
- Read same key 1000 times in 30s, expect cache hit metric > 99%.
- Set a too-large value (>1 MB), expect SDK rejects or etcd rejects with clear error.
- Kill one etcd replica (in a 3-replica cluster), expect reads continue, writes continue, SDK reconnects within seconds.
- Read `<service>/non-default-namespace/<key>` for a key that exists only in `default`, expect not-found (not a fallback to default — keep namespaces explicit).
