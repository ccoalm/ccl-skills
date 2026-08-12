# Deploy Pipeline

From source commit to running pod, with audit and rollback.

## Stages

```
commit
   │
   ▼
build:       source @ commit + version → image digest
             record: digest, commit, builder version, build time
   │
   ▼
manifest:    image digest + lane policy → k8s YAML (Deployment, Service, etc.)
             + mesh objects (VirtualService subset, DestinationRule)
             + discovery lane marker (registry tag or k8s label)
   │
   ▼
approve:     review task (for high-risk classes)
             approval recorded with reviewer, change summary, rollback plan
   │
   ▼
apply:       control plane writes desired state
             k8s reconciles
             mesh + discovery updates propagate
   │
   ▼
verify:      readiness probes pass
             smoke tests pass
             SLIs measured during bake window
   │
   ▼
promote OR abort:
             promote: shift traffic forward (canary → stable)
             abort:   rollback to previous known-good
```

Each stage is observable, audit-logged, and re-runnable (or in the case of `apply`, idempotent).

## Three control-plane spines

### A) Custom orchestration API

A platform-team service exposes:

```
POST   /service                                  create or update service definition
POST   /lane                                     create lane
POST   /lane/<lane>/service/<svc>/deploy         deploy a service version into a lane
POST   /lane/<lane>/service/<svc>/traffic        update traffic weight
POST   /canary-check-task                         start a canary check
GET    /canary-check-task/<id>                    status + SLI evidence
POST   /review-task                                request approval
POST   /review-task/<id>/approve                   approve
POST   /service/<svc>/rollback                     rollback to previous
POST   /service/<svc>/reload-mesh-config           push VirtualService update
```

A CLI client wraps these. A web UI provides the same surface for non-CLI users.

**Strengths**: deep integration with internal RBAC, audit, lane-first model, custom approval workflow.

**Weaknesses**: you maintain the API and its tools; off-the-shelf reuse is limited.

### B) GitOps (Argo CD / Flux)

Desired state is a tree of YAML in git. A controller in-cluster watches the repo and reconciles k8s state to match.

- Deploys = git PR + merge. Approval = PR review.
- Rollback = revert the commit.
- Audit = git history.

**Strengths**: declarative, reusable, no custom code to maintain; built-in review via PR.

**Weaknesses**: PR-based approval is coarse; lane-explosion can clutter the repo; secret handling needs an extra tool (Sealed Secrets, External Secrets Operator).

**OpenGitOps conformance gate**: when picking GitOps as the spine, test the implementation against the 4 OpenGitOps principles (CNCF Sandbox v1.0 documents released by the GitOps Working Group, per `opengitops.dev`): (1) **Declarative** — desired state expressed as data, not imperative scripts; if production state lives in `kubectl apply` shell scripts or "Helm render from git tag, runs on master", the spine is not GitOps even if it uses Argo CD as a viewer. (2) **Immutable & Versioned** — desired state stored with full version history; values stored in mutable ConfigMaps that get overwritten outside git, or environment-specific overrides applied at runtime by an operator, fail this. (3) **Pulled Automatically** (canonical OpenGitOps wording) — agents pull from the source of truth, not push from CI; a CI job that runs `argocd app sync --force` on merge defeats the pull model and turns the agent into a push pipeline. (4) **Continuous Reconciliation** — agents continuously observe and re-apply, not "deploy once and forget"; reconciliation interval, drift-detection alert routing, and self-healing toggle are first-class config decisions, not defaults left untouched. **Self-healing scope MUST be bounded explicitly**: legitimate out-of-band controllers (HPA / VPA setting replica counts and resource requests, cert-manager rotating cert Secrets, image-update operators bumping digests, security-patch automation) write fields that GitOps reconciliation would otherwise revert in a fight. Configure the GitOps agent to ignore controller-owned field paths (`spec.replicas` when HPA is in scope, Secrets owned by external-secrets-operator, image digests owned by an image-updater bot) via the agent's diff-ignore mechanism (Argo CD `ignoreDifferences`, Flux `ignore` annotation). Drift outside the ignore set should ALERT before auto-revert on production resources, not silently re-apply — the team needs the chance to intervene if the drift came from an emergency manual fix. Architecture review on a GitOps-spine platform must verify all 4; meeting only 2-3 produces "GitOps-shaped" deployments that lose half the model's benefit (typical failure: declarative + versioned + pulled, but reconciliation disabled because "drift fixes break things" — that platform is one manual `kubectl` away from silent divergence).

**ArgoCD OCI source (2024-2025)**: per `argo-cd.readthedocs.io/en/latest/user-guide/oci/`, Argo CD now supports OCI artifacts as a first-class application source — desired-state manifests packaged as OCI artifacts (referenced from a registry) sit alongside the git source. This buys: bundle a versioned manifest set in the same registry as container images (one supply-chain, one access policy); cosign-sign the manifest bundle and verify at sync time; cache via the OCI distribution spec the platform already uses for images. **ApplicationSet OCI generator** is in proposal — until shipped, OCI-driven ApplicationSets need the Plugin Generator with a custom OCI puller. **Version cadence**: ArgoCD's documented support policy is patches for the two most recent minors, so when 3.x is the current line the older minors (e.g. 2.13 until 3.1, 2.14 until 3.2) have time-limited maintenance windows, NOT open-ended LTS — schedule the platform-wide upgrade off the older line before its window closes. Coordinate platform-wide ArgoCD upgrades with the v2.14→3.0 migration notes in `argo-cd.readthedocs.io/en/latest/operator-manual/upgrading/2.14-3.0/` before flipping production clusters; watch the release-cadence page for the current minor before committing a multi-cluster upgrade plan. **Pre-upgrade check**: any ApplicationSet using the Plugin Generator as the OCI workaround needs validation that the proposed native OCI generator (when it ships) matches the plugin's input/output contract — migrating without a contract diff produces silent ApplicationSet behavior change. **Mutable tag footgun (P0 conflict with OpenGitOps "Immutable & Versioned" above)**: OCI artifacts referenced by tag CAN be overwritten in most registries (`docker push` against an existing tag silently replaces the underlying manifest), and an Argo CD sync against a mutable tag will silently pick up the new manifests with no PR / no audit trail / no rollback breadcrumb — defeating the immutability principle this skill demands of the GitOps spine. Required mitigations: (a) reference OCI app sources by digest (`@sha256:...`) or by an immutable-tag policy enforced at the registry (no overwrites on the artifact repo); (b) when tag references are unavoidable, configure Argo CD to require a digest pin via signature verification (cosign-sign + verify-at-sync); (c) treat a tag-only OCI reference on a production app as a platform finding equivalent to a `:latest` image pin — not GitOps-conformant.

### C) Pipeline tool (Spinnaker / Tekton / Jenkins / GitHub Actions)

A pipeline runner executes named stages with gates between.

**Strengths**: long sequenced flows, complex multi-cluster orchestration, broad existing patterns.

**Weaknesses**: pipeline state separate from cluster state; rollback is "run a different pipeline"; less declarative.

## Picking a spine

| Signal | Pick |
|---|---|
| Small team, want off-the-shelf | GitOps |
| Heavy approval / audit / RBAC requirements | Custom API |
| Long pre-deploy sequences (build, scan, test, multiple envs in order) | Pipeline tool |
| Lane explosion (>50 named lanes) | Custom API or GitOps with auto-generation |
| Hybrid budgets | Custom API that emits to GitOps repo; explicit boundary owner |

Do not run two without a documented ownership boundary. The most common production trap is "we have Argo AND a custom deploy API AND a pipeline AND ad-hoc kubectl" — every team picks differently and rollback is undefined.

## CLI shape

A platform CLI is the developer's primary surface regardless of spine. Typical commands:

```
plat build --name=<svc> --version=<v> [--push]
plat compile --name=<svc>                       # local build for testing
plat deploy --lane=<lane> --service=<svc> --version=<v>
plat deploy-config --lane=<lane> --service=<svc>  # update env-specific config
plat review --service=<svc> --change=<summary>  # create review task
plat rollback --service=<svc> [--to-version=<v>]
plat status --lane=<lane>
plat logs --lane=<lane> --service=<svc>          # shortcut to log search
plat trace --log-id=<id>                          # shortcut to trace UI
```

CLI calls the control-plane API (or commits to git for GitOps). It must work from a developer laptop with no extra setup beyond auth.

## Build pipeline specifics

```
source@commit + version
   │
   ▼
builder image (pinned version, golden image)
   │
   ▼
Dockerfile path: per language pattern (e.g. golang-app.dockerfile)
   │
   ▼
Build args:
  - GOPRIVATE / language-private-proxy
  - GOINSECURE / language-insecure-flag (only if necessary)
  - GIT_HOST mapping (only if necessary; consider private registry mirror instead)
   │
   ▼
Image tag: <registry>/<svc>:<version>
   │
   ▼
Push to private registry
   │
   ▼
Record: image digest (SHA), commit, build time, builder version
```

Floating tags (`latest`, branch name) are forbidden in deploys. The control plane references digest, not tag.

Builder image is itself versioned and updated on a schedule. Drift in the builder is invisible until reproduce-from-source fails.

## Idempotency

- `build` with same `(commit, version)` produces the same digest. If it doesn't, the build env is non-deterministic; fix that first.
- `deploy` with the same `(lane, service, digest)` is a no-op.
- `rollback` to a digest already running is a no-op.

Idempotency means CI can retry without side effects.

## Failure modes

- Builder image pulled stale → reproducibility breaks. Mitigation: pin and version.
- Registry credentials expire → CI breaks silently. Mitigation: rotation pipeline.
- k8s apply fails partway → state mismatch. Mitigation: declarative reconciler that retries.
- Approval workflow deadlock (everyone offline) → emergency override path documented.
- Mesh reload non-atomic → some pods serve old VirtualService briefly. Mitigation: connection drain.
