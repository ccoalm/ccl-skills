# Custom Control Plane: When and Where

A decision framework for building a self-hosted deploy/ops control plane (API + CLI + Web UI) instead of adopting GitOps / Spinnaker / Tekton. Distilled from real platforms where the custom plane was the right call.

## When custom plane is the right pick

All of the following are usually true:

1. **Lane is a first-class concept**, not a label retrofit. Per-developer lanes, named canary lanes, ephemeral test lanes — and you'll have dozens to hundreds at once.
2. **Approval lives in a chat platform** (Lark / Slack / Teams / WeCom). Operators want to approve from the chat card, not log into a portal.
3. **Multi-language teams** share the deploy tool: backend (Go/Python/...), frontend (React/Flutter/native). One CLI / one UI keeps the workflow uniform.
4. **Domain-specific canary logic** matters — e.g. log-error-diff by source line, custom SLI queries, or business-specific abort criteria — not just CPU/latency thresholds.
5. **Audit and RBAC tie to the organization's identity system** (internal IDP, not GitHub/GitLab user model).
6. **Operations team is non-engineer** — product ops, release manager, on-call — who should not need git PR workflow knowledge.

If 2-3 of these are true, custom plane is competitive. If 5+ are true, custom plane usually wins.

When **not** to build custom plane:
- Pure engineer-driven team, all comfortable with kubectl + git.
- Single environment, few services, no lane explosion.
- No chat-platform approval need.
- Small team (< 10 backend engineers) — maintenance cost outweighs ergonomic gain.

## What the custom plane MUST own

```
1. Service catalog
   - service identity (PSM / service.name)
   - owners (multi-owner; non-empty enforced)
   - protocol, port, mesh-injection flag, VCI/serverless flag
   - hosts (ingress hostnames if any)

2. Lane model
   - lane name, type (online/offline), description
   - immutable after creation; only description mutable
   - strict prefix convention enforced at API
   - lane-service relation table (per-lane resource size, replicas, cluster)
   - lifecycle: protected lanes (long-lived) vs ephemeral (TTL + sweeper)

3. Deploy orchestration
   - render k8s YAML (Deployment + Service + PVC) from templates
   - render Istio resources (VirtualService + DestinationRule) consistently
   - apply via k8s API (direct, or via Argo CD API if hybrid)
   - stream watch events back to caller (WebSocket)
   - record image digest, not tag, in audit

4. Approval workflow
   - create review task (risk class + change summary + rollback plan + obs evidence)
   - send chat-platform card to assigned reviewers
   - receive callback (idempotent — first approver wins)
   - update task state + re-render card
   - block deploy API until approved (for risk class that requires)

5. Canary check task
   - bake window + SLI queries OR log-error-diff configuration
   - start task (record in cache or DB with TTL)
   - poll status + run check at expiry
   - emit promote / abort decision
   - audit the decision with evidence link

6. Rollback
   - one command (CLI) / one button (UI)
   - target = previous known-good image digest
   - mesh weight shift OR re-apply previous Deployment
   - smoke verification post-rollback

7. Traffic-policy delegation hooks
   - MAY expose connectivity-owned per-pair policy APIs through the same auth/audit shell
   - MUST NOT define retry/timeout/circuit semantics here
   - audit every delegated traffic-policy change

8. Mesh config reconciliation
   - regenerate full VS + DR per service on any lane-service change
   - serialized ordered apply with dry-run and rollback capture
   - do not claim k8s cross-resource transactions; full regenerate per change

9. Audit + history
   - every deploy / approval / rollback / traffic-change event recorded
   - queryable by service / lane / time / actor
   - retention >= 90 days (high-risk events 1 year+)

10. Integrations
    - chat-platform card receive + send
    - cloud-provider pipeline notice receive (if applicable)
    - cloud-provider alert receive (if applicable)
    - grafana alert webhook receive
    - emit alerts/notices to chat-platform
```

## What the custom plane MUST NOT own

```
1. Pod scheduling, restart, eviction
   → kubernetes does this. Don't reimplement.

2. Service discovery
   → connectivity-owned discovery mode: registry-based, k8s-native,
     or mixed. Custom plane may publish lane/deploy metadata through a
     delegated adapter, but does not own resolver, registry, or
     EndpointSlice semantics.

3. Network-level retry, timeout, mTLS
   → Istio sidecar / Envoy. Custom plane configures DestinationRule
     defaults via the catalog, doesn't enforce at runtime.

4. Metrics collection / storage / query
   → OTel collector + Prometheus + VictoriaMetrics / Mimir.
     Custom plane consumes SLIs via query API, doesn't store metrics.

5. Log collection / parsing / indexing
   → filebeat + logstash + ES. Custom plane queries ES for
     canary log-diff but doesn't ingest.

6. Trace storage / query
   → Jaeger / Tempo / equivalent.

7. Static config bundling
   → image build path (conf/<env>.yml in image). Custom plane
     doesn't manage static config.

8. Dynamic config storage
   → config center (etcd). Custom plane writes via SDK,
     doesn't replace it.

9. Secret storage / rotation
   → secret store (KMS / Vault / cloud-provider equivalent).

10. CI build (compile / test / package)
    → CI runner (GitLab CI / GitHub Actions / Tekton).
      Custom plane triggers image build via control-plane
      API but doesn't run the build itself.

11. Full platform dashboard
    → grafana / kibana / jaeger UI. Custom plane links to them,
      does not duplicate.

12. Identity / SSO
    → organization IDP. Custom plane validates tokens, doesn't issue.

13. Networking policy / firewall
    → k8s NetworkPolicy + cloud provider firewall.

14. Cluster lifecycle (create / upgrade / scale)
    → cloud provider console + ops shell scripts (bootstrap-only).
```

## Recommended minimum API surface

```
# Service catalog
POST   /v1/service                       create/update service definition
GET    /v1/service/<psm>                  get service
DELETE /v1/service/<psm>                  delete service (cascades to k8s + Istio)
GET    /v1/service                         list (filterable)
POST   /v1/service/<psm>/owners            change owners

# Lane
POST   /v1/lane                            create lane
DELETE /v1/lane/<name>                     delete lane (cascades)
GET    /v1/lane                            list lanes
GET    /v1/lane/<name>                     lane detail (+ services optional)

# Per-lane service deploy
POST   /v1/lane/<lane>/service/<psm>/deploy        deploy version into lane
GET    /v1/lane/<lane>/service/<psm>/deploy_ws     WebSocket: stream watch events
GET    /v1/lane/<lane>/service/<psm>               detail + pod list
PUT    /v1/lane/<lane>/service/<psm>               update resource config / replicas / protocol
DELETE /v1/lane/<lane>/service/<psm>               delete from lane
GET    /v1/lane/<lane>/service/<psm>/config        rendered YAML preview

# Canary
POST   /v1/canary_check                            run log-diff or SLI check immediately
POST   /v1/canary_check_task                       start a bake window task
GET    /v1/canary_check_task                       poll task status + result

# Mesh config / delegated traffic policy
POST   /v1/service/<psm>/reload_mesh               regenerate VS + DR for service
GET    /v1/service/<psm>/traffic_config            delegated: list connectivity-owned per-pair traffic policy
PUT    /v1/service/<psm>/traffic_config            delegated: update connectivity-owned per-pair traffic policy

# Review
POST   /v1/review_task                              create review task
GET    /v1/review_task                              list (filterable by status/risk/service)
GET    /v1/review_task/<id>                         detail
POST   /v1/review_task/<id>/approve                 approve (or reject)

# Rollback
POST   /v1/service/<psm>/rollback                   rollback to previous known-good

# Domain (ingress hostname)
GET    /v1/domain                                   list
PUT    /v1/domain                                   modify

# Inbound webhooks
POST   /v1/callback/grafana                         grafana alert → chat
POST   /v1/callback/chat_card_action                chat card click (approve / ack)
POST   /v1/callback/cloud_pipeline_notice           cloud CI/CD notice → chat
POST   /v1/callback/cloud_alert                     cloud alert → chat

# Audit
GET    /v1/audit                                    queryable event log
```

## Recommended CLI surface

```
deploy-cli login                       # SSO → token, cached locally
deploy-cli service ls / get / create
deploy-cli lane ls / get / create / delete
deploy-cli build <psm> <version> [--push]
deploy-cli deploy <psm> <version> <lane> [--wait]   # WebSocket streams events
deploy-cli canary <psm> <version>      # start canary check
deploy-cli review <psm> <version> --risk <class> --reason <text>
deploy-cli rollback <psm> [--to-version <v>]
deploy-cli traffic <psm> <callee> --timeout <ms> --retry <n>  # delegated to connectivity
deploy-cli logs <psm> --log-id <id>    # opens kibana / log search
deploy-cli trace <log-id>              # opens jaeger / trace UI
deploy-cli status <lane>               # lane summary
```

Deploy/update commands call the control-plane API and never directly mutate k8s, service discovery, mesh, or config etcd. Build may push to the image registry through the typed build command. Single endpoint, single auth path for control-plane operations.

## Recommended Web UI surface

Four pages, no more:

1. **Service catalog**: search/filter services, change owners, jump to detail.
2. **Lane overview + management**: list lanes, create/delete (with proper guards), see services per lane.
3. **Deploy console**: select service + lane + version → render YAML preview → confirm → watch live progress via WebSocket → see canary report → approve or rollback.
4. **Audit log query**: filter by actor / service / lane / time / event-type.

Avoid:
- Building a metrics dashboard (grafana already does it; link to grafana).
- Building a log viewer (kibana / equivalent; link).
- Building a trace explorer (jaeger; link).
- Building a "platform health" page (mix of all above; link to each tool).

## Hard rules

1. **No business logic.** Custom plane is platform-only. The day someone adds "feature flag evaluation per user" to it is the day it stops being a deploy tool.
2. **Persistent state in control plane = catalog (services + lanes + lane-service relations) + tasks + audit + approvals.** Pod-level runtime state (which pods are running, ready, where) lives in k8s; control plane reads it. The control plane IS the source of truth for the *intent* of lane and service definitions (which lanes exist, what services they own, what resource sizing each lane-service runs at); k8s is the source of truth for the *observed* state of pods. Never duplicate pod state in the control-plane DB.
3. **Break-glass kubectl path open.** Admins can fix the cluster directly if the control plane is broken or absent.
4. **Chat platform adapter isolated.** Card rendering + callback handler in one module; switching IM platform requires touching only that module.
5. **Don't reimplement k8s primitives.** No custom scheduler, no custom networking, no custom DNS. Generate manifests; apply via k8s API.
6. **No direct etcd writes** (the cluster control-plane etcd). Configuration etcd (dcc) is separate; writes go through control plane API which writes to config etcd, never to cluster etcd.
7. **API is the source of truth, UI/CLI are thin clients.** Everything UI can do, CLI can do, API can do. No UI-only / CLI-only functionality.

## Sizing the maintenance burden

A platform team of 3-5 engineers can sustain a control plane of this scope:
- ~10-15k LOC backend (Go or Python; framework + handlers + logic + service templates)
- ~5-10k LOC frontend (React)
- ~3-5k LOC CLI
- Test suite covering the audit-critical paths (deploy / approve / rollback / mesh reload)
- Monthly: 1-2 feature additions; bugfix turnaround < 1 week
- Quarterly: dependency upgrades; integration test refresh

A team of 1-2 cannot sustain this and should adopt GitOps + Argo Rollouts instead.

## Migration paths

### From ad-hoc kubectl scripts → custom plane

1. **Phase 1**: catalog existing services into the catalog DB. Manual entries.
2. **Phase 2**: implement deploy API for one service group. Migrate that group's scripts to use the API.
3. **Phase 3**: add lane model + render templates from k8s YAML examples.
4. **Phase 4**: add chat-card approval. Migrate review workflow.
5. **Phase 5**: add canary check task. Replace manual "wait and watch" with the task.
6. **Phase 6**: turn off direct kubectl access for non-admins.

Estimated: 2-3 quarters with a 3-engineer team.

### From GitOps → custom plane

Rare; usually the other direction. If you do migrate:
1. Keep Argo CD as the underlying applier; custom plane writes to the Argo CD repo or calls Argo CD API.
2. Custom plane adds the lane / approval / canary-check layer on top.
3. Over time, decide whether to keep Argo or have custom plane apply directly.

### From Spinnaker / Tekton → custom plane

Custom plane subsumes the pipeline stages most teams care about (build, deploy, canary, promote, rollback). Migrate one service group at a time, comparing audit logs before / after.

## Failure modes

- **Custom plane DB / API goes down**: deploys blocked. Mitigation: admins use kubectl directly; CLI surfaces "control plane unavailable" clearly so users don't retry blindly.
- **Chat platform outage**: approvals stuck. Mitigation: emergency override path with explicit audit + post-hoc approval; do not silently bypass.
- **k8s cluster API rate-limited**: control plane retries with backoff; surface "throttled" status.
- **Image registry down**: deploys fail at apply (k8s pull). Control plane can detect and report cleanly; not its job to fix.
- **etcd config center down**: delegated traffic-policy updates blocked. Mesh routing still works (steady state). Old framework SDK cache absorbs the gap.

## Verification

- Single deploy command (CLI or UI) completes a deploy → can roll back → audit log shows both events with operator identity.
- A reviewer's chat-card click triggers approval within ~5 seconds (idempotent).
- Stopping the control-plane backend stops new deploys but leaves running services unaffected (data-plane independence).
- A new engineer can deploy their first service within 1 hour using only the CLI + UI docs.
- Cluster admin can bypass the control plane and fix a k8s resource directly when needed.
