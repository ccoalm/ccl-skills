# Go Architecture Source Evidence Map (Methodology Template)

This file describes the **shape** of source-evidence tracking for Go architecture extraction. Project-specific provenance (real repo names, branch state, dates, module counts, extraction logs) lives in the maintainer's private alias file at `~/.<host>/.private-aliases/<project>.yaml`, never in this shared skill tree — see `skill-extraction-workflow` Core Rule "Extraction lifecycle handoff".

## Scope boundary

This shared template contains reusable methodology only. Do not add concrete repository names, branch state, module counts, package descriptors, or extraction logs.

## Source coverage dimensions (architecture-level)

When extracting Go architecture guidance from a new source set, organize evidence by these dimensions:

| Dimension | What to collect | What to extract at architecture layer |
| --- | --- | --- |
| Service boundary inventory | How services are split (by domain / by traffic class / by data ownership); inter-service contract count | Boundary criteria, when to split vs merge, ownership rules |
| API/RPC contract shape | IDL formats in use, public-vs-internal API split, contract evolution practice | Contract-first discipline, additive evolution rule, public/internal split when stability needs differ |
| Data ownership | Per-service write model, cross-service read patterns, migration discipline | Each service owns its write model; cross-service reads through API/RPC; relational source-of-truth for durable state |
| Runtime platform | Service discovery, framework, dynamic config, secret management, observability, mesh | Workload identity, registry-based vs DNS-based SD, mesh ownership boundary, dependency client contracts |
| Error / context contract | Error code enum, error mapping table, ctx propagation through all sync/async paths | Stable enum, framework error mapping, ctx-as-source-of-truth for correlation |
| Reliability surfaces | Admission control, rate limit, backpressure, circuit breaker, idempotency, durable status | Reliability is architecture, not bolt-on; idempotency strategy; durable acceptance |
| Background workers | Long-running job model, lease scope, retry policy, idempotency key, failure visibility | Worker design as first-class architecture; not "happens to run async" |
| Generated code ownership | Generators in use, generation commands, ownership boundary between generated and hand-edited | Generated code is output, not source; generation commands documented and portable |
| High-risk operations | Tenant/user data isolation, money/billing, write atomicity, audit/outbox | Fail-closed default for high-risk paths; durable status + reconciliation; audit/outbox atomicity |
| External integrations | Third-party callbacks, public APIs, authorization scope isolation | Boundary rules: idempotent receivers, signature verification, scope isolation |
| Release runtime | Deployment unit, mesh routing, canary, approval, rollback | Architecture surface, not afterthought; per-service rollback boundary |

## Sibling-generalization mini-map (template)

For each Go architecture extraction, record decisions across sibling skills:

- `go-microservice-dev` — does the architectural rule have an implementation pattern? note in dev reference.
- `python-service-architecture` — cross-language counterpart? mirror at architecture level.
- `python-service-dev` — implementation counterpart?
- `testing-strategy` — what test layer proves the architectural property?
- `platform-observability` / `platform-service-connectivity` / `platform-release-engineering` — does the rule belong at platform layer instead?

Decisions go in the private alias map alongside the per-batch extraction log.

## Coverage discipline rules

- Architecture extractions describe **decision criteria, invariants, ownership boundaries, and acceptance checks**. Implementation patterns go to `go-microservice-dev`.
- Mark each dimension `pending` / `read` / `deep-read` / `excluded` / `unavailable` / `routed` with the actual artifacts inspected, in the private alias map.
- Re-read source artifacts when changing rules; use `wording cleanup` / `no new source read` labels honestly.
- For full-coverage claims, the private source register must be closed (every dimension has a status) before any "complete" claim is made.

## Where the live provenance lives

For the maintainer's current Go extraction project, see:
- Private alias map: `~/.<host>/.private-aliases/<project>.yaml`
- Per-batch extraction logs: `~/.<host>/skills/.extraction-work/<batch>-completion.md`
- These files are never pushed to the shared skill tree.

## Audit gate

Before committing a change to this skill, run the private alias map's `audit_cmd` against the changed shared-skill files. Any hit on real repo names, branch states, dates, file counts, or business-domain nouns is either fixed or recorded as `known_debt` in the alias map. Pre-existing leakage may be grandfathered; new or modified content must remain zero-hit.
