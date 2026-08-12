# Lane Orchestration Control Plane — Mature Pattern

Concrete implementation of a custom-API control plane (one of the three spines in `deploy-pipeline.md`). Built from observed mature designs; encodes patterns that work at production scale.

## Lane as DB-backed first-class entity

Lane is not just a label; it is a row.

```
table: lanes
  id            int64 PK
  lane_name     varchar  unique
  lane_type     enum     {online, offline}
  description   text
  created_at    timestamp
  updated_at    timestamp
```

Strict naming convention (enforced at API layer):
- `lane_type = online` → name MUST start with a designated online prefix (e.g. `prod-`, `live-`, or any 2-4-character platform-chosen prefix).
- `lane_type = offline` → name MUST start with a designated offline prefix (e.g. `staging-`, `dev-`, or any 2-4-character platform-chosen prefix).
- A few system-reserved lane names exist as enums (e.g. baseline / canary / baseline-offline / canary-offline); the codebase treats them as constants, not free-form strings.

Reasons for strict prefix:
- A glance at the lane name tells operators which environment family it belongs to.
- Routing fallback rules and resource quotas can be applied by prefix.
- Cross-lane data isolation policies can be enforced by prefix at network policy or admission webhook.

After creation, only `description` is mutable. Renaming a lane is forbidden (routing rules, registry tags, k8s labels would all need atomic re-issue).

## Lane-service relation

Many-to-many: a lane has many services, a service can live in many lanes.

```
table: lane_service_rels
  id                int64 PK
  lane_id           int64 FK
  service_id        int64 FK
  cluster           varchar   -- which k8s cluster this lane-service runs in
  cpu_limit         int
  memory_limit      int
  replica_num       int
  protocol          enum {http, grpc, tcp, thrift}
  with_resource     bool       -- requires resource-PVC
  in_vci            bool       -- runs in serverless k8s (VCI) mode
  is_gpu            bool       -- requires GPU
  created_at        timestamp
```

The relation row carries **per-lane deployment config**, allowing the same service to run with different resource shapes in different lanes (e.g. prod=4cpu/8gi, dev=250m/256mi).

Cluster column enables multi-cluster topology without changing the lane model: one lane can span clusters or be cluster-pinned.

## Service catalog

```
table: services
  id            int64 PK
  psm           varchar  unique    -- "owner.class.identifier", validated regex
  owners        []int64 FK         -- via service_owners join table
  protocol      enum
  hosts         []string           -- public hostnames if it's an edge service
  paths         map<match_type, [path]>  -- per-path lane routing config
  with_resource bool
```

PSM regex: `^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$`. Three dot-separated segments; segments allow underscores at the data layer but the gRPC `:authority` constraint may require hyphenation at the wire — see `platform-service-connectivity/references/grpc-authority-workaround.md`.

Service has multiple owners. Change-ownership is a first-class API; orphaned services (zero owners) are blocked from deploy.

## Control-plane API surface

```
# Lane CRUD
POST   /lane                              save_lane (create or update description)
DELETE /lane                              delete_lane — see "Lane deletion safety gates" below;
                                          must NOT be a single cascade for online lanes
GET    /lane                              list_lane (filterable, keyset paginated)
GET    /lane/<id>                         get_lane_detail (+services, optional)
POST   /lane/<id>/delete_preview          dry-run delete: returns impact report
                                          (services affected, traffic shifted, k8s resources gone)

# Service CRUD
POST   /service                           save_service
DELETE /service                           delete_service
GET    /service                           list_service
POST   /service/<id>/owners               change_service_owners

# Per-lane service deploy
POST   /lane/<id>/service/<svc>/deploy    deploy_lane_service (image, returns immediately)
WS     /lane/<id>/service/<svc>/deploy_ws deploy_interactive (streams k8s Deployment watch events)
GET    /lane/<id>/service/<svc>           get_lane_service_detail (+pod list)
PUT    /lane/<id>/service/<svc>           update_lane_service (CPU/Mem/replicas/protocol)
DELETE /lane/<id>/service/<svc>           delete_lane_service
GET    /lane/<id>/service/<svc>/config    get_lane_service_deploy_config (returns generated YAML)

# Canary check
POST   /canary_check                      deploy_canary_check (immediate result)
POST   /canary_check_task                 save_canary_check_task (start timer)
GET    /canary_check_task                 get_canary_check_task (poll status)

# Mesh / delegated traffic policy
POST   /service/<svc>/reload_mesh         reload_service_mesh_config (regenerate VS + DR)
GET    /service/<svc>/traffic_config      delegated: get connectivity-owned caller-callee policy
PUT    /service/<svc>/traffic_config      delegated: update connectivity-owned caller-callee policy

# Review / approval
POST   /review_task                       create_review_task
GET    /review_task                       list_review_task
GET    /review_task/<id>                  get_review_task
POST   /review_task/<id>/approve          approve_review_task

# Domain (ingress hostname management)
GET    /domain                            list_domain
PUT    /domain                            modify_domain

# Callbacks (inbound webhooks)
POST   /callback/grafana                  alert → chat platform
POST   /callback/chat_card_action         interactive card click (approve/confirm)
POST   /callback/cloud_provider_pipeline  CI/CD platform notice → chat
POST   /callback/cloud_provider_alert     cloud alert → chat
```

All write APIs are idempotent on `(target, version)`. List APIs are keyset-paginated for stable iteration. Errors return a typed code envelope `{code, message, data}` consistent across the API.

## Deploy flow

`deploy_lane_service(svc, lane, image)`:

1. Look up the service definition.
2. Compute the rendered k8s YAML using:
   - Standard app template (Service + Deployment + optional PVC).
   - Per-lane resource config from the relation row.
   - Image digest.
   - VCI mode flag (serverless k8s) → different sidecar layout.
3. Apply the YAML to the target cluster (k8s dynamic client).
4. Reconcile the service's Istio VirtualService + DestinationRule via `reload_service_mesh_config` (DR first, VS second, with rollback on partial failure — see Reconciled Istio config update section) so the new lane subset is routable.
5. Publish the lane marker through the chosen discovery mode: registry tag, k8s label/EndpointSlice, or mixed adapter.

If any step fails, the caller gets a typed error; the control plane does not auto-rollback partial state — operator confirms then issues delete or re-deploy.

## Deploy interactive (WebSocket stream)

`deploy_interactive` uses k8s Deployment watch + WebSocket to stream live events to the caller. Event types:

```
ADDED / MODIFIED / DELETED / ERROR (k8s watch event types)
+ ADDED-CONDITION / MODIFIED-CONDITION  (synthesized per-condition lines)
```

Each event includes: app name, replicas, ready_replicas, updated_replicas, available_replicas, condition type/status/message.

Termination criterion (avoid early-success on multi-replica rollouts): require all of:
- `status.observedGeneration >= metadata.generation` (controller has seen the latest spec)
- `status.updatedReplicas == spec.replicas` (every replica running new pod template)
- `status.availableReplicas == spec.replicas` (every new replica passed readiness)
- Deployment condition `Progressing` with reason `NewReplicaSetAvailable` (rollout fully complete)
- AND event type not in {Deleted, Error}

→ `IsResultEvent=true, IsSuccess=true`.

The naive check `updated_replicas <= available_replicas` is **wrong** — it fires when only one of N desired replicas is ready (1 updated ≤ 1 available, but other 2 still missing). Always compare against `spec.replicas`, not against the other status field.

Why stream not poll: the deploy CLI's user sees the deploy progress in real time (which pod is ready, which condition is pending). This is markedly better UX than "wait for it" polling.

## Canary check algorithm (log-error-diff variant)

Industry default is SLI burn-rate (see `canary-and-rollout-strategy.md`). A different mature option, suited when the platform already has rich structured logs:

```
Input:  service_psm, canary_lane, prod_lane, duration (default 5m)
Output: list of suspicious reports

1. List canary lane pods   → canary_pod_names
2. List prod lane pods     → prod_pod_names
3. For each pod set, query ES for ERROR-level logs in the last `duration`:
     filter: _psm=<svc> AND _lane=<lane> AND _level=ERROR AND _timestamp >= now - duration
     OR clauses on _pod for each pod name
4. Group logs by _caller (source file:line where the log was emitted)
5. For each (caller) in canary errors:
     # Normalize by pod count AND traffic share to compare RATES not raw counts.
     canary_rate = canary_count / (canary_pod_count × canary_traffic_share)
     prod_rate   = prod_count   / (prod_pod_count   × prod_traffic_share)
     if prod_rate > 0:
       if canary_rate > 2.0 × prod_rate AND canary_count >= MIN_SAMPLE (e.g. 5):
         report: "same code line, per-unit-traffic error rate anomalously increased"
     else:
       # prod has zero errors at this caller; canary has some.
       # Tolerate if canary_count below a noise floor; report otherwise.
       if canary_count >= MIN_NEW_ERR_THRESHOLD (e.g. 3):
         report: "new error log not seen in prod"
6. IsSuccess := len(reports) == 0
```

Why this works:
- `_caller` (source location) is a stable identity across versions; new code paths produce new callers.
- **Rate normalization is mandatory**: comparing raw counts breaks when canary has different replica count or different traffic weight than prod. Example: prod has 100 pods 100 errors (1/pod), canary has 1 pod 3 errors (3/pod) — raw `3 > 2×100` is false (canary looks fine) but per-pod rate is 3× worse.
- **Minimum sample thresholds** prevent flapping on low-volume callers: a single transient error in canary should not trip the check; require enough samples to be statistically meaningful.
- Bounded by `duration` (default 5m); no long-window risk.

When to use this vs SLI burn-rate:
- Use this when: structured logs are reliable, low-error services where new error patterns are rare, fast iteration cycles where SLO definitions lag.
- Use SLI burn-rate when: latency or success-rate regressions matter as much as error volume, mature SLO discipline exists, observability backend has long retention.

Both are mature; they are complementary, not exclusive. A platform can run both for high-criticality services.

## Canary check task (asynchronous flow)

Triggered by the CLI/CI at the start of a canary rollout:

```
save_canary_check_task(psm, run_id, duration)
  → cache key: (psm, run_id)
  → cache value: { start_at_ms, expire_at_ms }
  → backend: Redis with TTL = duration
```

The CLI polls `get_canary_check_task(psm, run_id)` to know how long until the check window closes, then calls `deploy_canary_check(psm, canary_lane)` to run the log-error-diff and get the report.

**Task state durability**: write the task record to the **same audit DB** as deploy events, not Redis-only. Reasons:
- Redis restart / key expiry can lose a task mid-flight; CI sees missing task and either reruns blind or proceeds without the gate. Both are bad.
- Audit trail: "what canary checks ran and what did they conclude" is incident evidence; needs the same retention as deploys.
- Redis is acceptable ONLY as a write-through cache for fast reads; the DB is source of truth.

Task lifecycle: `Pending` → `Running` → `Completed (success|fail)` with terminal-state markers. TTL on the DB row should be at least `2 × max_bake_duration` to absorb late pollers, plus retention policy for audit (e.g. 90 days).

## Lane deletion safety gates

`DELETE /lane` is the most destructive operation in the control plane. A naive cascade implementation (delete lane-service rows → delete k8s resources → rewrite VS) is a foot-cannon. Required gates:

1. **Protected-lane enforcement**: lanes with `protected: true` (typically online lanes like prod, named canary slices, named long-lived dev shared lanes) cannot be deleted by the regular DELETE call. Operator must first call `PUT /lane/<id>/unprotect` (separately audited) then DELETE — two-step.
2. **Dry-run preview required**: client MUST call `POST /lane/<id>/delete_preview` first; the response includes services affected, current traffic weight on each subset, k8s resources that would be deleted, estimated traffic loss during convergence. DELETE without a matching dry-run token within the last N minutes is rejected.
3. **Two-person approval for online lanes**: online lanes require an approval task analogous to the deploy approval; the chat-card lists the dry-run impact.
4. **Finalizer pattern**: lane row has a finalizer set; controller reconciles k8s deletion before removing the lane row. If k8s deletion fails partway, the row stays in `Deleting` state and the operator gets the failure surfaced; no orphaned state.
5. **Explicit service-count confirmation**: client must pass `expected_service_count` in the DELETE body; mismatch with current count → reject (concurrent service add by another operator).
6. **No cascade for non-empty lanes by default**: if the lane has services, DELETE rejects unless `force: true` is in the body AND approval is recorded. Empty-lane delete is the common safe case.

Skipping these gates is how production lanes get accidentally torn down. The mature platform builds them in from day one, not after the first incident.

## Reconciled Istio config update (two-resource)

Lane add/remove/update on a service triggers regeneration of the service's VirtualService + DestinationRule. The reconcile is **per-service serialized** to avoid concurrent-operation races.

```
ReconcileServiceIstioConfig(service, operation, isOnline, excludeLanes...):
  1. Acquire per-service distributed lock (e.g. Redis with fencing token, or etcd lease).
     Lock key: "mesh-reconcile/<service-psm>". Hold for full operation.
  2. Read current desired state (lane-service relations + traffic weights) from DB
     under transaction snapshot.
  3. Read current mesh config (VS + DR) from k8s with resourceVersion.
  4. Compute desired YAML; compare with current.
  5. Operation-specific ordering:
       ADD or UPDATE (subset reference appears or weight changes):
         a. Apply DR first (new subset exists before VS references it).
         b. Wait for xDS propagation (poll DR.status or fixed budget).
         c. Apply VS (now references existing subset).
       REMOVE (subset reference disappears):
         a. Apply VS first (drain traffic from subset; reset weight to 0 or remove route).
         b. Wait for xDS propagation + connection drain (configurable, ~30-60s).
         c. Apply DR (remove subset; no in-flight traffic to it).
  6. Server-side dry-run BOTH resources before each apply (admission validation pass).
  7. Use resourceVersion (CAS) on each apply; on conflict, refresh from k8s + DB,
     restart from step 2 (max N retries with backoff).
  8. If any step fails after a successful apply, roll back the applied resource
     to its pre-update state captured in step 3.
  9. Emit reconcile audit event with: lock holder, operation, generation, success/failure,
     duration, retries.
 10. Release lock.
```

**Why per-service serialization is non-negotiable**:
- Concurrent deploy + lane-delete on the same service can read stale DB rows, render conflicting VS/DR, and apply in opposite order — last writer resurrects deleted subsets or drops the canary route.
- The lock + CAS combination ensures the controller always operates on the latest desired state.

**Why operation-specific ordering**:
- Add: DR-first so the VS reference resolves.
- Remove: VS-first so traffic stops flowing to the subset before it disappears, avoiding a traffic blackhole during xDS propagation.
- Naive "always DR first" causes blackholes on delete; always-VS-first leaves orphan references on add. Match ordering to direction of change.

**Not atomic across k8s resources** — k8s provides no cross-resource transaction. The flow above approximates atomicity through: serialization + ordered apply + dry-run validation + rollback. A short window between steps 5a and 5c exists where mesh state is mid-transition; design routing rules so this window is safe (e.g. for ADD, the new subset starts with weight 0 in VS).

This API is called from: deploy, update, delete lane-service, delete lane. Any state change that affects routing reconciles the whole config; no delta-patching.

## Traffic config is owned by connectivity

This reference shows how a mature lane control plane may call into traffic-policy APIs, but retry/timeout/circuit ownership belongs to `platform-service-connectivity`. Keep release orchestration responsible for deploy state, approval, canary, rollback, and mesh reconciliation; route traffic-policy design changes back to connectivity.

The platform separates **routing** (mesh) from **traffic policy** (per-call retry/timeout/circuit):

| Concern | Mechanism | Storage | Update path |
|---|---|---|---|
| Lane → which pods | Istio VirtualService + DestinationRule | k8s API | `reload_service_mesh_config` |
| Per-caller-callee retry/timeout/CB | Application-level config (read by framework client SDK) | dcc / config center | `update_service_traffic_config` |

The traffic config payload (per caller-callee pair):

```
ServiceTrafficConfig {
  CallerPSM: <psm>
  CalleePSM: <psm>
  Content: {
    Timeout: <duration>
    RetryAttempts: <int>
    CircuitBreakerThreshold: <float>
    // ... other framework-client tunables
  }
}
```

Updates go through a Redis write lock per caller-callee pair (prevents concurrent diverging writes), then to dcc. Framework client SDK in each service subscribes to dcc updates and applies new values without restart.

Why this split:
- Mesh routing changes affect topology — slower, requires control-plane reload across nodes.
- Traffic policy changes are per-call — needs to apply instantly, with full caller-callee granularity (mesh DR is per-callee only).
- Many companies pick one (all-mesh or all-app); the dual pattern is more work but more flexible.

When NOT to do this:
- Small platform — pick mesh-only, simpler.
- No internal dcc/config-center — adopting dcc just for this is overengineering.
- Strict zero-trust where all policy MUST be enforced at network — mesh-only mandatory.

## Review / approval via chat platform cards

Mature pattern for fast approval workflow without a separate UI:

```
1. Operator calls create_review_task(lane, service, run_id, ...)
2. Control plane creates DB row {status: Pending, expires_in: 24h default}
3. Control plane sends a chat-platform card to the approver(s):
     Card content: change summary, risk class, lane, service, version, rollback plan, approve/reject buttons.
4. Approver clicks button → chat platform fires callback to /callback/chat_card_action
5. Callback handler — **MUST verify before mutating state**:
     a. Verify platform signature (HMAC/RSA per chat platform's webhook spec).
     b. Check timestamp skew: reject if > 5 min old (replay protection).
     c. Check nonce/event-id against recently-seen set (replay protection).
     d. Verify action binding: the click's task_id + version + reviewer matches
        what was originally sent — prevents reusing one valid signed payload
        against a different task.
     e. Resolve clicker's identity via chat platform user id → internal user;
        check RBAC: this user is an authorized reviewer for this service/lane.
     f. Look up the task by (lane, psm, run_id).
     g. Idempotency: if already approved/rejected, return current state, do NOT
        re-trigger downstream effects.
     h. Update task status; emit audit event with full callback payload preserved.
     i. Re-render card to show "approved by X" + timestamp.
6. CI/CD polls task status; on approved, proceeds with deploy.

**Without signature + timestamp + nonce verification**, an attacker who captures a single valid callback payload (e.g. via log scraping or MITM) can replay it to approve arbitrary deploys. This is a credential-grade vulnerability; all five checks (a-d, e) are required, not optional.
```

This compresses approval latency from "open the portal, find the task, click approve" (~minutes) to "see the card, click button" (~seconds). The chat platform is the single approval surface.

Failure modes:
- Approver clicks but callback fails to reach — chat platform retries the webhook; idempotency check prevents double-approve.
- Multiple approvers click simultaneously — first wins via DB row-level lock; others see "already approved".
- Task expires before approval — control plane marks expired, CI gets rejected status, operator must re-submit.

## Alert flow through the same callback API

The same `/callback/chat_card_action` handles multiple action types:

```
case "cp_review":          # promotion approval
case "alert_confirm":      # acknowledge alert (silences for 30min)
case "cloud_alert_confirm":# acknowledge cloud-provider alert
```

Routing by `Action.Value.source` field. Each source has its own data shape and handler. New action types are added without changing the callback URL.

This means the chat platform is the **single interaction surface** for both releases (approve/reject) and incidents (acknowledge). Operators don't switch tools.

## What this pattern is good for

- Teams that want strong audit + integration with internal user/RBAC system without building a full deploy UI.
- Companies where the chat platform (Lark/Slack/Teams equivalent) is already the primary work surface.
- Heavy multi-lane usage where commodity GitOps would clutter the manifest repo.

## What it costs

- The control plane is a real backend service you maintain (DB schema, API stability, audit, RBAC).
- Tight coupling to one chat platform — switching chat platforms means rebuilding interaction cards.
- Two control levers (mesh + dcc traffic config) require operators to know which lever to pull.
