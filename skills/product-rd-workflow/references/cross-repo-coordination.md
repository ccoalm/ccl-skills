# Cross-repo feature coordination

Load this when **one feature spans repos**. These are the gates the
`product-rd-workflow` "Cross-repo feature coordination" pointer routes to; each
section below is an independent gate, not a sequence. The version-coordination
model is the inline component set used throughout this reference (meta-repo
manifest / integration branch + central E2E / linked PRs / versioned artifacts);
`modular-monolith-heuristic.md` holds the related monolith-vs-microservices
decomposition heuristic that informs the monorepo-vs-polyrepo choice (change
frequency is a strong signal, not the only factor).

## Feature authority vs contract artifact

- Keep **one feature-authority surface for the slice** — a per-feature spec, or a slice-section of a program spec; don't concurrently redefine the same feature goals in multiple repos.
- The cross-repo **contract** is a separate concern from the feature spec (the feature spec owns goals/behavior; the contract artifact owns the shared interface + compatibility): keep it in a **stack-neutral independent repo or published artifact** every consumer consumes via an explicit version/compatibility policy, so no implementation repo "owns" it; when the contract has a single authoritative generating source (codegen from one service, gateway-published SDK), an independent **published artifact** substitutes for an independent source repo — but the generating repo still passes contract review before publish (topology doesn't waive governance).

## Consumers, stewardship, and serialization

- **External/un-upgradable consumers** (public SDK, mobile, partners, cached clients, long-lived workers) need an explicit compatibility window + deprecation policy, not assumed same-cadence upgrade.
- Default a **contract steward** (who can block, review turnaround, escalation) for cross-repo contract/data/rollback work unless explicitly waived — neutrality comes from governance, not repo topology alone.
- **Concurrent slices touching the same contract region serialize at the contract** (steward/CI); per-slice feature authority does not protect the shared contract.

## Per-repo coordination status

Its per-repo status must name what actually breaks polyrepo launches, not just which repos changed: **contract/data owner, consumed+produced contract version, compatibility & version-skew policy, rollback/promotion owner, central integration evidence (fresh, bound to the exact manifest version-set — stale E2E from another combination doesn't count)**. The version-coordination model is that inline component set (meta-repo manifest / integration branch + central E2E / linked PRs / versioned artifacts); for the related monolith-vs-microservices decomposition heuristic behind the monorepo-vs-polyrepo choice, see `modular-monolith-heuristic.md` (change frequency is a strong signal, not the only factor).

## Staged "done" and non-atomic rollback

- Cross-stack **"done" is staged** (code landed → contract active → traffic enabled → feature complete; traffic-enabled is not binary — partial/shadow/cohort/regional/store-lag, route rollout staging to `platform-release-engineering`); a single "landed" hides partial adoption.
- **Rollback is not atomic**: reverting the manifest restores only the deployable version combination — stateful/irreversible changes (DB/MQ schema, published app, cache format, external consumers) need expand-contract forward-compat with explicit migration ordering / dual-write windows (route rollout + migration mechanics to `platform-release-engineering`), not a promised atomic rollback.

## Structural vs semantic conformance

Schema/codegen contract-as-code usually covers **structure only**: required files, directories, contracts, version markers, schema/IDL digests, field numbers, and generated enum values must exist and match the declared contract. Cross-stack **semantic** parity (defaults, timezone, idempotency, sampling, redaction, cardinality) needs a semantic conformance suite — route to `testing-strategy`.

## Candidate-until-harness-verified conformance artifacts

**A conformance/contract artifact whose values were *hand-authored / reconstructed from the counterpart's implementation source* (fixtures hand-written from the producer's code, a consumer's expected shapes) — rather than emitted by the authoritative contract generator/IDL — is `candidate`, not authoritative, until a producer-side runtime harness verifies it against the real counterpart** (drive the real handler/serializer; assert envelope/shape/redaction/error-mapping); do not tag / publish / let consumers pin it as the contract before that verification — a released-then-immediately-superseded artifact (the first real check finds the candidate values wrong) means consumers pinned a wrong contract. (Authoritative *generated* artifacts — codegen/IDL/gateway-published SDK — are not `candidate` for this reason, but still pass generator/source review and the normal contract/version gates above.) Sequence the producer-harness verification *before* the immutable version tag; the redaction/visibility set is context-dependent (a field forbidden on one surface can be legitimately public on another), so it is part of what the harness verifies per-surface, not a global constant.

## Vendored-mirror sync

**Vendored-mirror sync** (applies once an authoritative versioned source artifact exists to vendor — the `candidate`-artifact rule above governs the pre-authoritative stage): a consumer's *vendored copy* (fixtures/schema/IDL copied into the consumer repo) is a **read-only mirror of `source@pinned-tag`** — contract changes flow **source-first** (change the source repo, versioned + reviewed, then re-vendor), not hand-edited in the mirror; a hand edit means the consumer has bypassed the source-of-truth flow, and if that edit is the change's only home the **source-of-truth silently falls behind its own consumer** (source older than a downstream copy that advanced under it — the observed failure). A *legitimate* downstream patch is allowed but **must stop calling itself a mirror**: mark it a `local-overlay` with owner / reason / expiry / upstream issue and its own CI. Enforce with a **vendor-sync gate** — each vendored file matches the source's per-tag **manifest** (not necessarily raw bytes: declare any normalization/transform; for *generated* bindings the invariant is "regenerated from `source@pinned-tag` with the pinned generator+options", not byte-equality; subset vendoring verifies its allowlisted files and flags undeclared extras). Divergence is a **blocking signal to classify** (source-first bypass / stale re-vendor / intentional fork / bad normalization / generated drift), never silently merged. Route the version/tag model to `platform-release-engineering`; the drift/conformance **verification mechanic** for this gate (the enumerate→ledger→explicit-verdict procedure, self-contained local-drift default, separate upstream-authenticity gate) is owned by `testing-strategy` (its `testing-strategy/references/vendored-contract-drift-checklist.md`).

## Tooling gaps and the candidate version-set

SDD-style across repos (spec → technical design → implement); **auto repo-discovery and per-repo auto-isolation are target tooling, not assumed** — today there's the spec/ADR/contract sync gate, worktree isolation, and `multi-agent-delegation` dispatch. Caveat on that gap: under a **one-requirement-one-version-boundary** (don't fold another requirement's versions into this integration set; but **merge** into a joint boundary when requirements share a contract / data migration / rollout flag / release-ordering / rollback path), the touched repos + version-set are a **candidate** derived from the per-feature spec — reconcile against actual consumers (spec-unwritten ones = unknown/risk, not "not involved"), so what's missing is discovery *tooling*, not the knowledge. The genuinely un-tooled judgment is the **compatibility baseline + rollback version-set** (incl un-upgradable external consumers). Spec-derivation only scopes the candidate matrix — it does **not** replace central integration / compatibility / rollback validation, which stay independent gates.
