# Promotion Gate and Review

The gate that decides "is this release allowed to keep moving."

## Two kinds of gate

### Automated gate (SLI-driven)

Wired into the canary check task. Queries observability backend; promotes / holds / aborts based on hard thresholds.

```
SLI(canary, bake_window) within budget?
  AND no P0/P1 alert fired on canary subset?
  AND smoke tests pass?
  → promote
otherwise:
  → hold or abort
```

The gate is code. It runs without human intervention for low-risk changes.

### Manual review gate (approval workflow)

For high-risk changes, a human approves before deploy executes.

```yaml
review_task:
  id: <uuid>
  service: <svc>
  change_summary: <one-paragraph>
  risk_class: low | medium | high | critical
  rollback_plan: <one-paragraph>
  observability_evidence: <links to dashboards, SLI checks, recent canary results>
  requester: <user>
  requested_at: <timestamp>
  reviewers_required: [<role-or-user>]
  approvers: [<approver-records>]
  status: pending | approved | rejected | expired
```

The deploy API blocks until `status == approved`. After deploy, the same task is updated with the deploy event for audit.

## Risk class

Each change declares its risk class. The class determines required reviewers and gates:

| Class | Examples | Required gates |
|---|---|---|
| Low | dev-lane updates, config flip in non-prod, doc updates | Automated only |
| Medium | prod canary at < 5%, prod config flip with rollback | Automated + 1 reviewer |
| High | prod canary > 25%, schema-compatible migration, mesh policy change | Automated + 2 reviewers |
| Critical | schema-breaking migration, IAM change, mesh trust domain change | Automated + 2 reviewers + on-call ack + change-mgmt notification |

Mis-declared risk is a review point: a low-risk change that turns out to break prod tells you the classifier needs tuning.

## Approval shape

Each approval record:

```yaml
approval:
  reviewer: <user>
  approved_at: <timestamp>
  observability_evidence_checked: true | false
  rollback_plan_verified: true | false
  comments: <free text>
```

Verification fields force the reviewer to confirm they actually read the SLI dashboards and rollback plan. "Click approve" buttons without these are decorative.

## Multi-approver chain shape

For approval workflows requiring more than one human (typical for high-risk changes touching billing, schema, multi-tenant data, or cross-team boundaries):

- **Approval state is per-requirement satisfaction, not a flat counter threshold**: when the rule is "1 approval from owning-team-leads AND 1 approval from SRE", the workflow stores one immutable vote record per approver (id, role/group claim, timestamp, signature) and evaluates each required requirement-slot independently. A flat `approvals_received >= N` check can be satisfied by `N` approvers from the same role and silently bypass the role-separation guarantee. The transition rule: every required role-slot has at least one positive vote AND zero rejections, AND there exists a one-vote-per-slot assignment (bipartite matching of votes to role-slots, with each vote eligible only for slots it qualifies for) — equivalently, the gate transitions only if a valid injective matching exists, not by greedy assignment. A greedy "each vote claims its highest-priority eligible slot" rule is wrong: with vote A eligible for both `lead` and `SRE` and vote B eligible only for `lead`, greedy can consume `lead` with A and leave `SRE` unsatisfied even though `B→lead, A→SRE` satisfies the policy. A single rejection from any role-slot moves the gate to `rejected` and locks further state changes. A policy may explicitly opt into dual-role self-satisfaction (same person counted in multiple slots); default is forbidden.
- **Approver identity is verified, not just claimed**: every approval mutation requires the approver's authenticated identity (SSO session, OIDC token, signed chat-callback payload) — not just an approver-id field in the request body. The approver's role/group claim is resolved at vote-recording time against the platform's identity provider, not trusted from the request body. Anyone-can-approve-as-anyone is a finding.
- **Approval chain composition is data, not code**: the approver requirement set for a given risk class is loaded from configuration (e.g. "high-risk changes need ≥1 approval from owning-team-leads list AND ≥1 approval from the SRE group"). Hard-coded approver chains rot as teams reorganize. The configuration is itself versioned and reviewed.
- **Per-step handlers chained, not nested if/else**: the approval workflow runs as an ordered set of handlers (validate request → resolve approver identity → check approver eligibility for an open requirement-slot → record immutable vote → recompute per-requirement satisfaction → emit notification → check transition) with each handler returning a typed result the next reads. Pass through; do not branch.
- **External chat callbacks (Lark, Slack, Teams approval cards) follow the platform's full callback verification contract**: signature, timestamp-skew, nonce/event-id replay protection, action binding to the original task+version+reviewer, resolved clicker RBAC, and idempotent state mutation are ALL required and all enforced before any state mutation. The complete inbound-callback rule lives in `lane-orchestration-control-plane.md` (Chat-Card Approval Callback section); apply that contract here too — do not implement a weaker subset just because this is "approval workflow" rather than "lane orchestration". The HMAC shared-secret rotation rules — dual-verifier acceptance during grace, key id where available, constant-time comparison, sender-vs-verifier cutover order, hard reject after revocation, per-verification audit — live in `secret-and-config-management.md` (Webhook / HMAC verifier rotation section); the generic secret rotation pipeline alone is insufficient for callback verifiers.
- **Audit on every transition**: each approval vote records who, when, request id, vote, resolved role-claim, prior per-requirement state, new per-requirement state. The audit log goes to the platform's centralized audit store, not just the workflow's own DB.

## Where the gate runs

The gate runs in the control plane, NOT in the CI pipeline. Reasons:
- Gate decisions need real-time SLI queries (only available post-deploy).
- Approval state changes asynchronously to CI runs.
- Rollback should not require re-running the original CI.

A pipeline can call the gate API; it cannot replace it.

## SLI query wiring

The gate calls into the observability stack (`platform-observability` skill defines the SLI shape):

```
GET /sli/<service>/<subset>?window=30m
→ { burn_rate: <float>, error_budget_remaining: <float>, status: "within_budget" | "breaching" }
```

The query is a contract: observability owns the implementation, release owns the consumption. If observability changes the response shape, the release gate breaks; treat as a contract change.

## Audit log

Every gate decision (auto or manual) writes to an append-only audit log:

```yaml
audit_event:
  type: gate_decision | approval | deploy | rollback | abort
  timestamp: <ISO8601>
  actor: <user-or-system>
  target: <lane>/<service>/<version>
  previous_state: <snapshot>
  new_state: <snapshot>
  evidence_links: [...]
  outcome: success | failure | aborted
```

Retention: ≥ 1 year for high/critical changes, ≥ 90 days otherwise. Audit log is queryable.

## Release-process metrics (DORA)

The audit log above is also the source for measuring the release process itself. DORA's current five-factor model (`dora.dev`):

- Throughput: **change lead time** (commit → running in prod), **deployment frequency**, **failed deployment recovery time** (successor to "MTTR"; the clock stops when user impact ends — the *current* SLI healthy again over a short confirmation window, NOT the cumulative error budget replenished — rather than when the rollback or hotfix command completed, so the audit log needs a recovery-confirmed event, not only the remediation event).
- Instability: **change fail rate** (deploys requiring immediate intervention — typically a rollback or hotfix, but any remediation form counts), **deployment rework rate** (unplanned deploys resulting from a production incident — "incident" meaning the production problem itself, not the existence of a formal ticket; missing paperwork doesn't exempt the deploy). Count remediation by what it *is*, not what it is named — a "roll-forward" that exists only to fix a failed deploy is a failed deploy's remediation.

Rules:

- Compute them from the control plane's own audit log (deploy / rollback / abort events with incident links) — never from a hand-maintained spreadsheet.
- Define the counting unit before computing, and keep that definition stable over time (changing artifact topology changes the counts, not the process — trends are only meaningful against a constant unit): for the DORA-comparable metrics, the unit is one *logical artifact deployment* to production — dedupe canary steps, per-region waves, and mechanical retries belonging to the same deployment attempt, but never collapse a *failed* attempt into its later successful retry (an attempt that reached production traffic and needed intervention stays a failed deployment even if the same release ID succeeded afterwards; otherwise change-fail rate is gameable by release-ID reuse). A purely mechanical pre-traffic failure — a control-plane error before any exposure — is pipeline noise, tracked separately, not a change failure.
- Behavior-exposing flag flips, config releases, and traffic shifts stay in the same audit log as release events: they count as the *remediation* (or the cause) of a deployment's failure where causally linked, but they are not deployments — folding them into the deployment-frequency denominator produces a broader custom release metric, which is fine to track but must be labeled as such, not reported as DORA.
- Use them as feedback on the release *process* — gate friction, batch size, rollback health — never as individual or team performance scores; scoring people on them corrupts the signal (deploys get relabeled, rollbacks get renamed "roll-forwards").
- If a metric cannot be computed from the audit log, that is an audit-log gap: fix the event capture, don't estimate the metric.
- Before publishing any of the five, verify the audit-log schema actually carries the correlation keys that metric joins on — at minimum: commit timestamp and production-exposure (traffic-reached) timestamp per deployment (lead time); a stable logical-deployment ID plus a distinct per-attempt ID (deployment frequency, and the failed-attempt/retry separation above); a causal link from each remediation event to the deployment it remediates (change fail rate); an incident link and a recovery-confirmed event (rework rate, recovery time). A metric whose keys are absent is unavailable — an audit-log gap per the rule above — not a license to join on wall-clock proximity or event-name heuristics; proximity joins are exactly how a failed attempt gets deduped into its later retry or a recovery gets inferred from an unrelated healthy reading.

## Merge Topology For Gitflow-Style Release Trains

Applies when a project runs Gitflow-style release branches (the default preference stays short-lived branches / trunk-based per `product-rd-workflow/references/delivery-lifecycle.md`; adopt this section only where release trains are genuinely required). Grounded in AWS Prescriptive Guidance's Gitflow pattern:

- **Squash is direction-sensitive.** feature/bugfix → develop merges use squash (clean linear history). release → main and every back-merge **must not squash** — prefer fast-forward/plain merge. Why (git topology): squashing on higher branches rewrites commit identity, so the back-merge can no longer recognize already-merged changes and produces repeated conflicts or silently dropped work (AWS: "Only use a squash merge when you are merging from a feature branch to a develop branch").
- **Back-merge promptly, both targets.** At release close, merge the release into main AND back into develop as soon as possible ("as soon as possible to consolidate work back into the primary branches") — a skipped back-merge means the next release train overwrites what only main has (the classic lost-hotfix incident).
- **Tag only after the human confirms the main merge.** The production tag is a deploy trigger, not bookkeeping — never tag ahead of the confirmed merge, and stop after MR creation unless asked to proceed (composes with `release-coordination`'s authorization matrix, which owns who may confirm).
- **Hotfix keeps the full environment ladder.** A hotfix branches from main and walks every promotion environment — it compresses cycle time and priority, never skips a gate; and it back-merges like any release, or the next train reverts it.

## Emergency override

For incidents where the gate must be bypassed (e.g. roll out an emergency fix faster than canary allows):

```yaml
emergency_override:
  invoked_by: <user>
  reason: <postmortem-track-id>
  bypassed_gates: [<list>]
  approver: <senior-engineer-or-on-call>     # post-hoc within N hours
```

Override exists but it is logged loudly. A platform that overrides routinely has the gate set too tight.

## Self-service vs centralized

| Approach | When |
|---|---|
| Self-service per team | Teams own their services; central platform sets minimum gate; teams can add stricter |
| Centralized | Small platform / regulated industry / shared infra changes |

Most platforms drift to self-service with central minimums. Document the minimum; let teams exceed it.

## Verification

- Trigger a low-risk change → deploy executes without manual approval.
- Trigger a high-risk change without approval → deploy API rejects.
- Approve a high-risk change → deploy executes; audit log shows approval + deploy events.
- Force an SLI breach during automated gate → gate decision = abort; audit log records the decision and the SLI value that tripped it.
- Emergency override invoked → loud notification fires; post-hoc approval is recorded.
