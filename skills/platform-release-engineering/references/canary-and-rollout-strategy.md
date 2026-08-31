# Canary and Rollout Strategies

## Canary by traffic-shift (default)

Two parallel deployments of the same service:
- `<svc>` stable: previous known-good version, all subset `lane-prod`.
- `<svc>` canary: new version, subset `lane-prod-canary-<version>`.

Mesh VirtualService routes by weight:

```yaml
http:
  - route:
      - destination: { host: <svc>, subset: lane-prod-canary-<v> }
        weight: 1
      - destination: { host: <svc>, subset: lane-prod }
        weight: 99
```

Rollout = walk the weight from 1 → 5 → 25 → 50 → 100 over hours or days, with a bake window between steps.

## Canary check task

Each step is a canary check task with explicit fields:

```yaml
canary_check_task:
  service: <svc>
  canary_version: <v>
  step: 1                            # 1, 2, 3, ...
  weight: 5                          # at this step
  bake_window: 30m                   # observe this long before promoting
  sli_queries:                       # all must pass within budget
    - name: error_rate
      # Uses request_error_total (5xx counter) per platform-observability
      # framework-middleware-checklist.md contract — request_total has no
      # status_class label; 5xx goes to separate request_error_total.
      # sum() aggregation drops the error_class label from numerator so
      # PromQL vector matching against denominator (no error_class) works.
      # Filter by baseline label `lane` (canonical per metrics-conventions
      # Baseline labels), not raw mesh subset name.
      query: 'sum(rate(http_server_request_error_total{service="<svc>", lane="prod-canary-<v>"}[5m])) / sum(rate(http_server_request_total{service="<svc>", lane="prod-canary-<v>"}[5m]))'
      threshold: < 0.01              # 1% rolling error-rate threshold (5m window; not an SLO error budget) — Flagger's builtin-check example value
    - name: latency_p99
      query: 'histogram_quantile(0.99, sum(rate(http_server_request_duration_seconds_bucket{service="<svc>", lane="prod-canary-<v>"}[5m])) by (le))'
      threshold: < 0.5               # seconds (500 ms) — Flagger's builtin-check example value
      # Threshold provenance: <1% error rate / p99<500ms match Flagger's official
      # builtin metric checks (request-success-rate min 99, request-duration max 500ms).
      # They are NOT a cross-tool default (Argo Rollouts' official example uses 95%
      # success); tune per service SLO — the SLO, not the template, is the authority.
  abort_thresholds:                  # immediate abort if these hit
    - name: error_spike
      query: 'sum(rate(http_server_request_error_total{service="<svc>", lane="prod-canary-<v>"}[1m]))'
      threshold: > 10                # 10 errors/sec in 1 minute → abort
  smoke_tests:                       # synthetic probes
    - endpoint: GET /healthz
      expected_status: 200
    - endpoint: POST /known-known-input
      expected_status: 200
      expected_payload_contains: "ok"
  manual_approval_required: true | false
```

The control plane executes the check, queries the observability backend, and emits a decision: `promote`, `hold`, or `abort`.

## Bake window sizing

| Service criticality | Bake per step | Total rollout |
|---|---|---|
| Critical path (payment, login) | 1-6 hours | 1-3 days |
| Normal user-facing | 30 min - 1 hour | hours to a day |
| Internal | 10-30 min | hours |
| Dev tools | minutes | minutes |

Shorter bake misses slow-burn issues (memory leaks, drift in downstream load). Longer bake costs release velocity. Match to incident history.

## Header-lane canary (high-risk changes)

For changes where you want explicit opt-in rather than percentage exposure:

```yaml
http:
  - match:
      - headers:
          <opt-in-header>: { exact: "canary" }
    route:
      - destination: { host: <svc>, subset: lane-prod-canary-<v> }
  - route:                                       # default: stable
      - destination: { host: <svc>, subset: lane-prod }
```

Internal employees, dogfood users, or a manually-curated test cohort send the header. Far safer for high-risk changes (auth, billing, data migrations).

## Blue-green

Two parallel deployments, all-or-nothing switch:

```
Blue:  <svc>-blue,  currently receives 100% traffic
Green: <svc>-green, receives 0% traffic, runs the new version
```

Switch by editing the Service selector or VirtualService:
```yaml
spec:
  selector:
    app: <svc>
    color: green                                 # was: blue
```

Strengths:
- Instant rollback (flip back).
- Full validation of green before any user sees it.

Weaknesses:
- Double the resource cost during switch window.
- Schema/data changes complicate it (both colors share the DB).

Use for: stateless services with strict zero-downtime requirements.

## Mirror / shadow

Send a copy of prod traffic to a non-prod target, drop the response:

```yaml
- route:
    - destination: { host: <svc>, subset: lane-prod }
  mirror:
    host: <svc>
    subset: lane-shadow
  mirrorPercentage:
    value: 10.0                                  # mirror 10% of traffic
```

Use to:
- Validate a new version under real traffic shape before any user exposure.
- Test infrastructure changes (DB migration, mesh upgrade) under real load.

Critical rule: mirror writes are dangerous. Either the shadow target writes to a separate data store, or the writes are intercepted and dropped. If the shadow writes to the prod store, you've doubled the write load AND created phantom data.

## Progressive delivery tooling

Off-the-shelf options:
- **Argo Rollouts** — k8s-native, integrates with Argo CD, exposes Canary / BlueGreen CRDs.
- **Flagger** — operator-driven, integrates with Istio / Linkerd / App Mesh, supports metric-driven promotion natively.

If your platform has a custom canary check workflow, the trade-off is: build it yourself (more control, more maintenance) or adopt Flagger/Argo Rollouts (less control, more reuse). Hybrid is rare and creates ambiguous ownership.

## Abort and rollback

Abort path during canary:
1. Set canary weight to 0 (mesh VirtualService update).
2. Drain in-flight requests on canary pods.
3. Log abort event with cause (which SLI tripped, who triggered).
4. Optionally: keep canary pods running for post-mortem inspection (don't terminate immediately).

Rollback path post-promotion:
1. Re-deploy the previous known-good digest as the new "canary".
2. Walk the same rollout flow.
3. Or, in extreme cases, immediately set the new bad version's weight to 0 and old version's to 100.

## Ramp/Rollback Data Literacy (user-level experiments and flags)

When the rollout is user-bucketed (A/B, percentage flag, allowlist) rather than pod-weighted, the decision data has its own failure modes; a ramp/rollback/graduate decision that ignores them reads a lying funnel:

- **Exposure without a bake point lies.** Count a user as "on treatment" only from an exposure event emitted at the moment the treatment actually took effect for them — an assignment record without exposure means the funnel includes users who never saw the change.
- **Funnel invariant:** for any feature, outcome unique-users ≤ exposure unique-users — a necessary sanity check, never attribution proof (disjoint sets can satisfy it): attribution requires joining outcome events to the same users' exposure with outcome.time > exposure.time. A dashboard violating the invariant has a data-pipeline defect, not a product effect.
- **Analytics profile attributes are current state, not post-assignment behavior.** A profile-filtered dashboard cannot express `event.time > assigned_at`; ramp/rollback/graduate decisions must not rely on profile-filtered boards alone — use exposure/outcome event joins, and pair them with failure logs and cost data.
- **Control-plane query ≠ execution fact.** Reading the flag service proves only what policy is *stored* at query time. Policy, assignment, exposure, actual execution path, and outcome are five separate evidence layers — never infer a user's actual arm from the configured weights.
- **Bucketing salt is immutable mid-flight.** Changing the salt re-buckets every user (treatment users silently swap arms), destroying the experiment; weight and target changes have defined semantics for existing vs new users — write down which one the platform gives before ramping.

## Verification

- Trigger a synthetic SLI breach during canary → control plane logs detection within bake window → automatic abort fires.
- Force a canary abort → traffic returns to stable within seconds (mesh weight propagation time).
- Trigger header-lane canary with the opt-in header → request lands on canary subset; without header → lands on stable.
- Mirror enabled → mirror target sees traffic; primary handler is unaffected; metrics tagged distinctly.

## Topic-extension backlog

Entries here are registered candidates, not adopted guidance. Each names the candidate, its evidence status, and the condition that unblocks adoption; the round that evaluates one records keep/narrow/discard against its entry.

- **Application-layer rolling provider transition (deferred candidate).** Observed form, from one agent-native product repository (evolving portfolio): a new backend provider registers with an in-process broker as an additional route, traffic shifts to it by weight, and the old provider unloads once it has no in-flight work — demoting blue-green from an infrastructure operation to an in-process composition pattern. Evidence status: hypothesis-grade — single source, and the source itself labels the account observational. Do not land this as executable rollout guidance until at least two independent external sources corroborate the pattern in production use; re-evaluate at the next design round touching provider transition, blue-green, or in-process traffic shifting.
