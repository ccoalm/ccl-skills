---
name: platform-release-engineering
description: 发布 / 灰度 / canary / rollback / rollout / 环境泳道 / promotion gate / 发布值班 SOP（P0·P1 打断排班、是否回滚）→ design or review how a change moves from build to traffic and back safely, including rollout strategy, approval, rollback, secrets, config, and deploy control planes. Skip when the ask is the production release lifecycle — 上线范围确认 / 合并 main / 打 tag / 生产构建 / 发布后 reset → release-coordination; release document substance → release-doc-writer.
---

# Platform Release Engineering

This skill owns **how a change reaches users and how it gets recalled**: lane / environment topology, build-to-deploy pipeline, traffic-shifting strategies (canary, blue-green, mirror), promotion gates that consume observability evidence, secret + dynamic-config distribution, and the rollback contract.

You do not own:
- What signals exist to judge a release — see `platform-observability`.
- How a request reaches a service or which subset of pods it lands on — see `platform-service-connectivity` for mesh, registry, and lane-routing primitives. This skill *uses* those primitives.
- Service-internal change shape (handler-level refactor, DB migration mechanics) — language-specific service-architecture skills.
- Language-specific library/module tagging mechanics — the owning stack dev skill. A release task that tags a module in a multi-module repo using local path overrides (e.g. Go `replace`) must run that stack's external-consumer-view verification (see `go-microservice-dev`) before the tag is pushed; this skill owns when a tag may ship and how registry publication is verified, not how the language toolchain validates package internals.

## Skill Routing

- Use this skill for: designing the env/lane matrix, choosing a rollout strategy, defining a promotion gate, writing rollback procedure, designing a secret-distribution model, deciding static-vs-dynamic config split, building the image pipeline, choosing the deploy mechanism (custom control plane / GitOps / pipeline tool), designing approval/review workflow.
- Use `platform-observability` first when the question is "what SLI does the gate consume?" — the gate definition lives here; the SLI lives there.
- Use `platform-service-connectivity` first when the question is purely about VirtualService weights / mesh routing — this skill *invokes* those changes, but the connectivity skill owns the primitives.
- For the production release lifecycle — scope confirmation, merge authorization, tag/pipeline evidence, watchers, and post-release reset — route to `release-coordination`; this skill must not own that coordination lifecycle.
- Use `release-doc-writer` for the release document's substance and evidence discipline.
- Use `references/python-package-registry-release.md` when publishing Python wheel/sdist artifacts to a private PyPI-compatible registry or verifying that a published package resolves from the registry without source/editable mappings.
- Use `defect-diagnosis` for an active incident; come back here to land the recurring rollback gap.

## Core Mental Model

A release moves through three planes:

```
   Source plane         →    Control plane          →    Data plane
   ─────────────             ─────────────────             ─────────────
   code commit               build/deploy API              k8s + mesh
   image build               approval workflow             pods + VirtualService
   config update             traffic-shift orchestration   secret + dcc state
   secret rotation           rollback orchestration        log + metric + trace
```

The control plane is the source of truth for "what is supposed to be running where, in which lane, at what weight." Two healthy patterns exist:

| Pattern | How control plane works | Best for |
|---|---|---|
| **Custom orchestration API** | A platform-team service exposes deploy/canary/review CRUD; CLI and UI clients call it; it generates k8s manifests and applies them. | Heavy customization needs, deep integration with internal RBAC/audit, lane-first models. |
| **GitOps (Argo CD / Flux)** | Desired state lives in a git repo; a controller reconciles cluster to repo. | Standard k8s shape, declarative discipline, off-the-shelf reuse. |
| **Pipeline tool (Spinnaker / Tekton / Jenkins)** | A pipeline runner executes "build → test → deploy → verify" stages with approval gates between. | Long sequenced flows, complex multi-cluster orchestration. |

Pick one as the spine; do not mix. Hybrid patterns (e.g. control plane that writes to a GitOps repo) are workable but require explicit ownership of the boundary.

## Non-Negotiable Rules

### R1 — Lane is the unit of release, not "environment"

- "Environment" implies a small fixed set (`prod`/`staging`/`dev`). Real platforms grow many concurrent lanes: per-developer iteration, per-test-run, named canary slices, shadow traffic, stress-test traffic. Treat them all uniformly.
- A lane has: name, parent lane (for fallback), allowed services list, traffic weight (in canary case), expiry (for ephemeral lanes), owner.
- New service deploys MUST declare which lanes they support. A service deployed only to `prod` cannot be tested in `staging` lane — fix by deploying to both.
- Lane primitives are defined by `platform-service-connectivity` (registry tag and/or k8s label plus mesh routing). This skill operates them.

### R2 — Build pipeline is reproducible from source + version tag

- Image build takes (`source@commit`, `version`) → image; same input, same digest.
- No floating tags in prod (`latest`, branch names). Use immutable version tags or digests.
- Build environment is itself pinned: builder image version, base image version, build args. Drift here is invisible until rollback fails.
- Build output is recorded: image digest, source commit, build time, builder version. The release control plane references digest, not tag.
- The version tag must point at a commit whose **committed** tree is the release content. Confirm the **complete** release-identifying set — not just the version string but every deploy-consumed file (version/manifest/lockfile, generated deploy manifests, image-digest/pin files) — with `git show <sha>:<file>` against the committed tree, never a working-tree `grep` (which also shows uncommitted edits and gives false confidence the bump landed). `git commit` records only the **index**: an edit made during a `--no-commit` merge, or any edit after the last `git add`, is NOT in the commit until re-added, so tagging that commit ships the *old* content under the *new* version number. Order is load-bearing and SHA-pinned: stage the **exact** release-identifying paths (not `git add -A`, which can sweep in conflict markers or unrelated local files — follow with `git diff --cached --check`), commit, resolve `sha=$(git rev-parse <ref>^{commit})`, verify `git show $sha:<file>` for the whole set, then tag exactly `$sha` (verifying `<ref>` but tagging later lets a pull/rebase/branch-move retarget the tag onto an unverified commit). A published/prod tag is **immutable**: if the commit was wrong, mint a *new* version — do not force-move the tag (consumers with cached tags would deploy split histories); force-retag is only ever for a tag that was never pushed. Content-correctness of the committed tree is necessary but not sufficient for release provenance: push release tags to a **protected** tag namespace, prefer a signed / CI-attested tag, and re-verify the **remote** tag object points at `$sha` after push — otherwise any tag-push-capable actor can spoof a release at a valid SHA.

### R3 — Deploy is declarative; bash scripts are bootstrap, not lifecycle

- Steady-state deploy and update MUST go through a declarative path (control plane API or GitOps reconciler). Bash scripts (`kubectl apply -f`) are acceptable ONLY for one-time cluster bootstrap (install mesh, install a discovery backend if the chosen mode needs one, install observability stack).
- A service whose deploys live in `deploy.sh` is an audit and rollback hazard. Mark for migration.
- Reason: declarative state is queryable, diffable, and replayable. Imperative scripts are not.

### R4 — Promotion is evidence-driven, not time-driven

A canary or staged rollout is promoted to the next stage ONLY if:
1. The canary's SLI burn rate within the bake window is within budget (query via `platform-observability` SLIs).
2. No P0/P1 alert fired against the canary during the bake window.
3. Manual approval from the documented reviewer (where the workflow requires it).
4. Smoke probes against the canary's endpoints return success.

Time-only promotion ("wait 30 minutes then ramp to 100%") is a guess. Wire the SLI query into the gate; reject the promotion if it fails.

### R5 — Rollback is one command and reaches steady state in < 5 minutes

- Rollback is invoked from the same control plane as forward deploy. A separate rollback tool is a sign the model is broken.
- Rollback target: the previous known-good release (image digest + config snapshot).
- Mechanism choice depends on rollout strategy:
  - Canary: shift VirtualService weight back to 0 for the canary subset.
  - Blue-green: swap which color receives traffic.
  - Plain rolling update: re-deploy the prior image digest.
- Rollback for data migrations is separate and harder; see `references/rollback-playbook.md`.
- Drill: a quarterly rollback exercise on a non-critical service catches drift in the rollback path. If you cannot drill it, you cannot use it.

### R6 — Secrets do not live in source repos

- Secrets (DB passwords, API keys, tokens, certs) MUST come from a secret store at deploy time or runtime, not from a committed file.
- Acceptable distribution mechanisms:
  - Cloud-provider KMS / Secrets Manager (AWS, GCP, Azure, or other major-cloud equivalent).
  - Self-hosted secret manager (HashiCorp Vault, internal KMS with audit log).
  - k8s `Secret` objects populated by a controller that pulls from the above.
- Unacceptable patterns: secrets in `values.yaml` in git, secrets in ConfigMap, secrets in any config file checked into source, hardcoded passwords in YAML manifests. Each is a recurring exfiltration pattern in postmortems.
- The platform should run an automated scan (e.g. `gitleaks`, `trufflehog`) on every PR. New secrets MUST go through the secret-store path; CI rejects commits that look like raw credentials.

### R7 — Config has three tiers

| Tier | Mechanism | Update frequency | Example |
|---|---|---|---|
| Static | committed YAML files (`conf/<env>.yml`), bundled in image | Build-time | DB connection pool sizes, feature defaults |
| Dynamic | config center (dcc / Apollo / etcd / Consul KV) | Runtime, no restart | Feature flags, rate limits, A/B variants |
| Secret | secret store | Runtime, masked | Credentials, certs |

A platform that conflates these (e.g. ships feature flags in static YAML, requires redeploy to flip) burns release velocity. Define which lever lives where; new config goes into the right tier from day one.

### R8 — Review/approval is part of the release path, not a step before it

- For high-impact changes (production deploys, schema migrations, mesh policy changes, IAM changes), the deploy API requires an approval record before it executes.
- The approval record lists: reviewer, change summary, risk class, rollback plan, observability evidence the reviewer checked. Stored in the same audit log as the deploy event.
- Lower-risk changes (canary to 1%, dev-lane updates) MAY bypass review. Risk class is declared with the change; mis-declaration is reviewed.
- Approval after deploy is not approval; it is rationalization.

### R9 — Multi-cluster / multi-region is explicit, not emergent

- Single-cluster deploy is acceptable while traffic fits one cluster. Multi-cluster is a deliberate decision with: cluster pairing rule, failover trigger, cross-cluster discovery or mesh federation, and mesh trust domain.
- Cross-cluster service calls go through the platform's chosen discovery/federation path, not direct DNS. Mesh trust must be configured pairwise.
- DR drill: route prod traffic to the secondary cluster for a bounded window every quarter. If you cannot drill it, you cannot use it.

### R10 — Bootstrap state is documented and idempotent

- Cluster bootstrap (install mesh, optional discovery backend, observability stack, control plane) is a documented sequence. Each step is idempotent (re-running it on a healthy cluster produces no change).
- The bootstrap script is committed; partial / commented-out steps are a smell. Either the step is required (uncomment and document) or not (delete).
- A new region / new cluster comes up via the bootstrap script + a region-specific config layer. Manual setup is forbidden.

### R11 — Persisted settings migrations preserve scope and intent

- Treat user-local or workspace-local persisted settings as release state, not throwaway config. A deploy that changes defaults, permission modes, model/runtime choices, tool approvals, update policy, or feature opt-ins must declare the migration plan before release.
- Treat remotely managed runtime policy as release state, not best-effort personalization.
  - Define eligibility, auth source, targeting tuple, schema version, checksum or ETag, maximum stale age, initial-load wait bound, polling cadence, and hot-reload owner before launch.
  - Empty/no-policy responses must explicitly clear stale managed policy instead of falling back to an old cache; malformed responses must not replace the last known-good policy; auth failures must stop retry amplification; and principal, account, tenant, organization, workspace, provider path or source, privacy state, auth source, logout, revocation, trust state, or eligibility drift must purge or re-scope both session and disk cache before any runtime reads policy.
- Stale managed policy may fail open only for advisory defaults whose cached tuple still matches principal, account, tenant, organization, workspace, provider path or source, privacy state, auth source, trust state, eligibility facts, policy version or revocation epoch, and schema version, using explicit none markers for unavailable scopes.
  - Reject old-valid-policy replay, rollback below the accepted policy/revocation epoch floor, or cache replacement that lacks a monotonic freshness signal for the targeted tuple.
  - It must fail closed for permission, credential, destructive-action, sandbox, tool-exposure, privacy, or compliance gates unless there is fresh-enough allow evidence.
  - A newer deny, revocation, opt-out, empty policy, or explicit removal always wins over a stale allow.
  - Dangerous policy additions or widenings need a blocking review path in interactive contexts and a documented non-interactive behavior before rollout.
- Read and write the same settings scope. Do not read merged effective config and then write a global default; that silently promotes project, policy, or workspace choices into a broader scope.
- Preserve explicit user intent. Migrate only source values that are known legacy forms or known old defaults; do not overwrite an already-set target value. For harmless additive lists, merge with de-duplication instead of replacing. For authorization, tool approval, permission, or policy settings, use policy-aware migration: explicit deny/revocation wins, narrower scope stays narrow, and deprecated broad grants are not carried forward blindly.
- Make the migration idempotent. Use either same-scope source predicates or a completion/version marker when source values disappear after the first run. Keep old readers safe through the rollback window with dual-read/dual-write or legacy-key retention until rollback is no longer supported. A recoverable backup is additional repair evidence, not a substitute for rollback-version readability. Do not delete the old key merely because the new write succeeded.
- Gate migrations by eligibility state when rollout is segmented. A setting migration for one account tier, provider path, workspace class, or feature cohort must no-op outside that segment; completion markers must include the migration version plus eligibility facts, or be written only for permanently ineligible states.
- Startup migrations should log sanitized success/error and continue when the old state can still run safely. Fail closed only when continuing would create an unsafe permission, credential, or destructive-action state.

### R12 — CLI package distribution and self-update are release surfaces

- Treat a command-line product installer or self-updater as a release control path, not a convenience command. Detect the currently running installation owner before mutation: package-manager-managed, bundled/native, local user install, global install, development build, or unknown. Package-manager-owned installs should hand off to the owning manager with a clear no-mutation result; development or unknown installs should fail closed or require explicit user repair rather than guessing a destructive path.
- Bind update decisions to the current installation reality, not only persisted config. If persisted install method and the actual running executable disagree, surface the mismatch, repair only the narrow install-method metadata when safe, and update the installation that is actually executing. Multiple installations, stale aliases, missing PATH entries, orphaned packages, and insufficient permissions are release-readiness findings; the updater must show actionable repair evidence instead of silently proceeding.
- Download and activate through a verifiable staging flow.
  - Version/channel policy, max-version or skip-version gates, authenticated release metadata, platform/architecture matching, bounded stall/timeout behavior, retry only for retryable transfer stalls, and sanitized failure diagnostics are required before publishing a binary.
  - A checksum fetched beside the artifact is not an integrity boundary by itself: require a signed manifest or artifact signature verified against a pinned/trusted key, with the digest bound to version, channel, platform, and architecture before activation.
  - Reject otherwise-valid old metadata through a monotonic release index, channel epoch, freshness window, persisted rollback floor, or equivalent anti-replay policy; document key id, rotation, revocation, and overlapping trust-window handling.
- Materialize packages under containment even after signature verification. Reject or safely handle path traversal, absolute paths, symlinks, hardlinks, device/special files, unsafe ownership, and unsafe mode bits; write with no-follow or descriptor-anchored operations so a signed archive cannot escape staging or overwrite package-manager/user-managed targets.
- Activation must survive process death and power loss between sub-steps.
  - Persist staged-file durability, executable bit/metadata, activation intent/state, and parent-directory durability using fsync or platform-equivalent guarantees before reporting success.
  - Publish by atomic rename, symlink swap, or platform-equivalent copy/restore flow; verify the resolved installed target belongs to the selected installation, still matches the signed manifest digest/version/channel/platform tuple, is present and runnable, and launches the intended binary before reporting success.
  - Run startup recovery/repair when activation intent is incomplete or final validation was not recorded.
- Protect running and previous versions.
  - Use per-version locks or process-lifetime fences so cleanup cannot delete a version still executing in another process; detect stale locks conservatively, handle PID reuse or inconclusive process checks without deleting live versions, retain at least one known-good rollback candidate and any possibly-needed activation-recovery executable until recovery reaches finality, and clean orphaned staging/temp files only after an age threshold that cannot race active installs.
  - Concurrent update attempts should join, wait, or return explicit lock-contended finality, not run duplicate downloads or overlapping activations.
- Installer cleanup must be scoped and reversible. Removing an old launcher, symlink, alias, package wrapper, or stale version must first prove ownership by this installer and must never delete a package-manager-owned or user-managed target by heuristic alone. On platforms where the executable cannot be replaced while running, use rename/copy/restore semantics so copy failure restores the prior executable; if restore fails, report a critical broken-install result with repair steps.

### R13 — Drain a job-executing worker pool before disruptive reconfig or restart

- **Scope & default.** A pool that runs in-flight work — CI/build runners, queue/stream consumers, long-task workers — must be **drained before** a disruptive change (restart, replacement, scale-down of a busy instance, or any reconfig the tool does not document as in-flight-safe). Disrupting a busy pool **aborts or orphans** the work in flight: aborted units surface as spurious failures; orphaned units wedge in a `running`/locked/leased state until a timeout, blocking everything queued behind them. This is the operator-side companion to a service draining its own requests on shutdown — handler bodies (`preStop` hook contents, in-process signal handling) are owned by the service-architecture skills; here you operate the pool and choose the timeouts.
- **Drain = fence admission, then wait under a bounded deadline, then act** — via the tool's graceful path, not a hard kill, verifying each step:
  - Fence admission and confirm it held: cordon/disable the instance, pause queue assignment / autoscaler / coordinator polling, and verify **no new work is admitted after the fence timestamp**. "Stop accepting new work" that is not verified can wait forever while another controller keeps assigning.
  - Wait for in-flight work under a **bounded deadline** using the tool's graceful signal: gitlab-runner `SIGQUIT` ("stop accepting new builds; exit when running builds finish") versus `SIGTERM`/`SIGINT` or a plain container `stop`/`restart`, which "abort all running builds"; k8s rolling restart with a `preStop` drain hook and `terminationGracePeriodSeconds` ≥ the expected longest unit; a consumer group that finishes in-flight messages before exiting. A unit exceeding the deadline is **stuck → triage it**; do not wait unboundedly, and do not silently kill it. `killall`/`pkill` are not graceful — sub-process signals are mishandled for shell/container executors.
  - Fence old↔new so a replacement cannot double-run a unit whose lease/heartbeat lapsed during shutdown (single-writer: lease+epoch, compare-and-set completion, or idempotent commit).
- **"The tool reloads config live" is a per-option claim to verify against the tool's own docs, not a blanket assumption.** A pool may re-read its config file periodically yet not re-apply a given field to already-running work without disruption, or apply it only to future scheduling (e.g. a concurrency-limit change). Verify the specific field is hot-reload-safe before editing it on a busy pool; otherwise drain first.
- **Reconcile after disruption — but prove orphaned and prove safe-to-retry first** (blanket cancel+retry is data-loss-unsafe):
  - Before cancelling, prove the unit is actually orphaned, not merely slow: last-heartbeat age, lease owner, attempt id, worker liveness, log progress. A slow heartbeat / delayed coordinator / partition can make a live job look stuck — cancelling it loses work.
  - Before retrying, require idempotency or fencing: the old attempt may have committed external side effects (deploy, publish, artifact upload, irreversible message) and only lost its status update — blind retry duplicates them. Use an attempt id / dedup key / durable finality marker; when finality is **unknown**, escalate to an operator decision rather than auto-retry.
  - Recurring orphans of the same shape across changes are a **runbook gap, not bad luck** — add the drain/fence step to the procedure instead of normalizing manual retries.
- **Applicability & break-glass** (drain-first is the default, not a universal):
  - A single shared / non-drainable pool may have no graceful signal, or pausing it would block the whole org. Prefer adding temporary capacity, shifting work to another pool, or scope-disabling only the affected tag/project; otherwise get explicit sign-off that the change accepts in-flight job loss.
  - An emergency hard kill (runner holding leaked credentials, corrupting state, or blocking a P0 fix) is an **explicit, approved, recorded** exception, not the routine path: capture the in-flight inventory, stop admission if at all possible, snapshot logs/state, kill with a named approver, mark affected units **unknown-finality**, and reconcile conservatively per the idempotency rule above.

## Workflow

### Phase A — Topology

1. Map the env/lane matrix: long-lived envs, named canary lanes, per-developer lanes, ephemeral test lanes.
2. Map clusters and regions; document which lanes live in which cluster.
3. Confirm the chosen cross-cluster discovery or mesh federation path if multi-cluster.

### Phase B — Source to image

1. Image build is reproducible from `(commit, version)`. Builder image pinned.
2. Image registry is private; access controlled.
3. Image digest is the deploy identifier, not tag.

### Phase C — Control plane

1. Pick one spine: custom API / GitOps / pipeline tool. Document the choice.
2. CRUD operations: service, lane, lane-service-deploy, review-task, canary-check-task, rollback, and optional delegated traffic-policy hooks when the platform exposes connectivity-owned policy through the release shell. Each is callable from CLI and UI where applicable.
3. Audit log captures every deploy event with: actor, target, previous state, new state, approval link.

### Phase D — Rollout strategy

1. Default: canary via mesh VirtualService weight shift.
2. Alternatives: blue-green (two parallel deployments, swap router), mirror/shadow (copy traffic to non-prod target without affecting users).
3. Canary check task definition: bake duration, SLI queries, smoke tests, promotion threshold, abort threshold.

### Phase E — Promotion gate

1. SLI burn-rate during bake window within budget (call into `platform-observability`).
2. No P0/P1 alerts on the canary subset.
3. Smoke probe success.
4. Manual approval (where the risk class requires).
5. If any fails: abort, rollback, log the abort cause.

### Phase F — Rollback contract

1. One command from the control plane.
2. Reaches steady state within 5 minutes (target; measure it).
3. Data migration rollbacks declared in advance (forward-compatible migrations preferred; see `references/rollback-playbook.md`).
4. Drill quarterly.

### Phase G — Secret + config

1. Static config: YAML in image, env-suffix split (e.g. `conf/<env>.yml`).
2. Dynamic config: config center; client SDK with cache + push-update.
3. Secret: secret store; injected via init container or sidecar; never in image, never in git.
4. Rotation: secrets have an expiry; pipeline rotates before expiry; rotation is observable.
5. Persisted settings migration: define source scope, target scope, eligibility gate, idempotency marker, rollback-read compatibility, legacy-key retention/deletion timing, recovery backup, and user notification/audit event before the release ships.

### Phase H — Evidence

Before marking the release done:
- Deploy event in audit log with approval link.
- Canary traced end-to-end; SLI burn-rate query result attached.
- Rollback command exists and has been tested in the same environment within the quarter.
- No secret-in-git scanner hits on the change.
- For CLI installers/updaters: diagnostic evidence shows installation owner, sanitized or path-classified current executable identity, persisted install method, multiple-installation warnings, package-manager handoff or selected mutation path, verified signed release metadata with freshness and key policy, durable activation and recovery result, lock/fencing result, retained rollback candidate, and user-facing repair path for every terminal failure class. Keep raw executable paths local or user-visible only when needed for repair.
- For Python package registry releases: published package evidence shows the built artifact metadata, registry package/version listing, simple-index metadata, target-distribution download+hash proof from the intended private registry, the dependency install index used, and a fresh-environment import/version check; see `references/python-package-registry-release.md`.
- For a disruptive change to a job-executing worker pool (R13): evidence that admission was fenced (no new work admitted after the fence timestamp), that in-flight work reached zero within the drain deadline (or that the break-glass exception was approved and recorded with affected units marked unknown-finality), that stuck units were triaged, and that any retry of orphaned units passed the freshness + idempotency check.

## Decision Points

- **"Custom control plane vs GitOps"** → custom buys deep integration with internal RBAC and audit; GitOps buys reuse and declarative discipline. Pick by team size and customization need, not fashion.
- **"Canary by percentage vs canary by header lane"** → header-lane canary is safer (you control who sees it); percentage canary is simpler. Use header for high-risk changes, percentage for general rollout.
- **"Roll back vs roll forward"** → roll back if (a) the issue is severe and (b) rollback target is known good. Roll forward if (a) the issue is minor and (b) the fix is small and tested.
- **"Single shared cluster vs per-team cluster"** → per-team is operationally expensive; share until you can't. The cliff is usually noise isolation, not capacity.
- **"Mesh-managed canary vs SDK-managed canary"** → mesh; the SDK doesn't know about deployed pods.
- **"Cross-repo integration layer: deploy repo vs dedicated integration repo"** → keep ONE authoritative source of version combinations per system (it may encode scoped combinations — per env/region/channel/ring, e.g. during canary/blue-green/staged rollback — but not duplicated per-env/region/branch manifest copies), and a cross-stack e2e gate that **resolves versions from that manifest** (hand-written or CI-overridden test versions make the manifest's authority fake). Default home: co-locate both with the rollout owner — usually the deploy repo; the contract/spec repo stays free of manifest churn (a read-only contract→combination pointer is fine). Roll the manifest back **in lockstep** with deploy config, or later e2e/audit validates a phantom combination. Split out a dedicated integration/meta repo when ANY trigger fires: the e2e combination matrix (old↔new, N-1) gets heavy, integration cadence diverges from deploy, the manifest needs independent versioning, co-location would force cross-stack contributors into the deploy repo's sensitive access scope, external consumers (SDK / downstream / customer deploys / audit) must read the combination authority, or audit / cross-org / supply-chain governance needs an isolated owner. Even co-located, keep version-manifest and env/deploy config in separate areas — different truths.
- **"Where the version number lives across repos" (version-authority layering)** → version management is layered (contract tag → combination manifest → consumer pin → repo-local `AGENTS.md` *pointer* to the authority); never copy the authoritative current pin into a doc (it drifts on the next bump). See `references/version-authority-and-deprecation.md` for the per-layer owner/change-mode table, the narrow audit/generated-artifact inline-version exception, the freshness gate, and the standing current-state drift check (the manifest/status doc needs a mechanical drift gate, not same-batch sync discipline — keeping it fresh by memory silently rots across sessions). `product-rd-workflow`'s spec/repo-contract sync gate cross-refs this.
- **"When can the producer drop an old contract version?" (deprecation timing for consumers you don't control)** → for store apps / distributed SDKs / customer-deployed services, key the backward-compat hold off a **real adoption/telemetry signal, not a calendar date** (`stale-after` is a revisit placeholder, not authorization to drop); but no signal is not a license for an unowned indefinite hold either — sunset then proceeds via an explicit owned EOL decision. See `references/version-authority-and-deprecation.md` for the signal types, the EOL-decision fields, and the testing-strategy compatibility-window split.

## Common Pitfalls (observed, not blanket-prescribed)

These are signs the platform has rough edges; not all are "fix immediately" — but seeing them should trigger a deeper look:

- Secret files in a source repo (even one), or DB passwords in a ConfigMap. Pitfall is data exfiltration on next leak.
- Bootstrap scripts with commented-out steps. Pitfall is divergence between documented and actual cluster state.
- Hardcoded IPs / hostnames in build scripts. Pitfall is non-portable image build.
- Service deploys driven by ad-hoc `kubectl apply` in a shell script. Pitfall is no audit trail, no rollback.
- Approval workflow that fires AFTER the deploy. Pitfall is rationalization, not approval.
- Time-only canary promotion ("wait 30 min then 100%"). Pitfall is shipping past silent breakage.
- Multiple parallel orchestration patterns (custom API + Argo + Spinnaker) without clear ownership of the boundary. Pitfall is ambiguous source of truth.
- Single-region production with no DR drill. Pitfall is unbounded RPO/RTO when the region fails.
- CI bootstrap steps fetching external artifacts with no connect/total timeout and no per-step logging. Pitfall is a silent multi-minute hang indistinguishable from progress — bound every fetch, log each step, and pin what you fetch; prefer an internal registry/mirror where the repository controls one (required for production-critical pipelines); for any executable or build/release-influencing artifact (tooling binaries included, not only artifacts labeled release-critical) verify a pinned digest/signature regardless of which source served it, and treat external fallback as an explicit, logged break-glass path rather than an automatic one (a silent automatic fallback re-opens the supply-chain exposure the mirror exists to close, and an internal mirror without pinning merely relocates it).
- A pipeline job perpetually pending/queued on a self-hosted runner fleet, then stuck-failed. Pitfall is misreading it as a content failure — check runner scheduling/capability/availability first from job and runner metadata (job tags vs runner tag/run_untagged policy, executor type, arch, runner online/paused, project assignment, concurrency saturation); note a shell executor ignores `image:` and runs as the runner's service account on the host, whose privileges vary (root/sudo/docker access is neither guaranteed nor excluded — verify, don't assume).

## Sanitization and Provenance

This skill is product-agnostic. It must not contain:
- Repository names, control-plane service names, internal hostnames, internal IPs, cluster names.
- Image registry URLs, cloud-provider artifact paths, region codes that identify the platform.
- Business-domain terms, tenant types, vertical names.
- Specific credentials or example secrets, even fake ones.

Reused industry patterns (canary, blue-green, GitOps, control plane, lane, dcc, config center, secret manager) are fair game.

## References

- `references/env-and-lane-matrix.md` — Lane as first-class entity; long-lived envs, ephemeral lanes, canary slices, shadow traffic; cluster/region topology.
- `references/deploy-pipeline.md` — Build → image → manifest → apply; three control-plane patterns; CLI / UI / API surface.
- `references/canary-and-rollout-strategy.md` — Canary check task shape; bake window; abort thresholds; blue-green and mirror alternatives.
- `references/promotion-gate-and-review.md` — Evidence-driven gate; SLI wiring; approval workflow; audit-log; DORA release-process metrics.
- `references/rollback-playbook.md` — Rollback by strategy; data-migration rollback discipline; forward-compatible migration patterns; drill schedule.
- `references/secret-and-config-management.md` — Static / dynamic / secret tier; rotation; injection paths; scanning.
- `references/multi-region-and-cluster.md` — Cluster pairing; failover trigger; cross-cluster discovery/federation; DR drill.
- `references/lane-orchestration-control-plane.md` — Concrete mature pattern: lane as DB entity with strict naming, per-lane resource config, custom-API surface, deploy-interactive via WebSocket, log-error-diff canary alternative, and serialized mesh reconciliation with ordered apply, rollback, and drain handling.
- `references/config-center-via-etcd.md` — etcd v3 as config-center backend; key shape `/<psm>/<namespace>/<key>`; in-cluster + SD endpoint discovery; Watch listener; mature SDK with LRU cache + hit/miss/error metrics; payload-by-cadence cache TTL; operator interface via control plane.
- `references/custom-control-plane-boundary.md` — When custom plane vs GitOps / Spinnaker is right; 10 things it MUST own (catalog / lane / deploy orchestration / approval / canary task / rollback / delegated traffic-policy hooks / mesh reconcile / audit / integrations); 14 things it MUST NOT own (k8s scheduling / SD / mTLS / metrics / logs / traces / secrets / CI build / IDP / etc); recommended API + CLI + Web surface; hard rules (no business logic, chat-platform adapter isolated, break-glass kubectl open); migration paths from kubectl-scripts / GitOps / Spinnaker.
- `references/deploy-cli-concrete-recipe.md` — Concrete deploy CLI recipe with compile/build/deploy-config/review/deploy commands, pipeline metadata parsing, image namespacing, control-plane API calls, streamed deploy status, review-task wait loop, and self-bootstrap notes.
- `references/version-authority-and-deprecation.md` — Cross-repo version-authority layering (per-layer owner/change-mode; never copy the current pin; the audit/generated-artifact inline exception + freshness gate) and deprecation timing for un-upgradable consumers (signal-not-calendar hold; the owned EOL-decision fallback).
- `references/python-package-registry-release.md` — Private PyPI-compatible wheel/sdist upload, duplicate recovery, simple-index metadata checks, and registry-only install verification.

## Verification before marking work done

1. **Static**: deploy pipeline path is declarative; bash scripts are clearly bootstrap-only; secrets scanner integrated into CI.
2. **Live**: trigger a canary; verify SLI gate queries fire; verify abort path works (force a fake SLI breach).
3. **Live, rollback**: execute rollback in a non-critical service; reach steady state and verify within 5 min.
4. **Audit**: every deploy in the last 30 days has an approval record before the deploy event.
5. **Static, no leakage**: grep this skill — zero internal hostnames, repo names, or business terms.

If any check fails, the work is interim, not done.
