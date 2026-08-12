# Go Dev Source Evidence Map (Methodology Template)

This file describes the **shape** of source-evidence tracking for Go implementation extraction. Project-specific provenance (real repo names, branch state, dates, file counts, extraction logs) lives in the maintainer's private alias file at `~/.<host>/.private-aliases/<project>.yaml`, never in this shared skill tree — see `skill-extraction-workflow` Core Rule "Extraction lifecycle handoff".

## Scope boundary

This shared template contains reusable methodology only. Do not add concrete repository names, branch state, module counts, feature findings, or extraction logs.

## Source coverage dimensions to track

When extracting Go implementation guidance from a new source set, organize evidence by these dimensions in the private alias map:

| Dimension | What to collect | What to extract |
| --- | --- | --- |
| Broad Go inventory | Module count by shape (service vs library vs tool vs generated), without exposing real module names | Implementation guidance must classify shape before recommending patterns |
| New-product Go service | Build files, IDL tree, dependency container, observability wiring, generated code, unit/integration tests | Contract-first implementation, documented generators, explicit dependency lifecycle, generated-file discipline |
| Legacy Go services | Representative generated surfaces, config files, handlers, logic, DAL tests | Handler/logic split, env config, generated transport files, test utilities |
| Search / AI-adjacent service | HTTP/RPC clients, store clients (Redis, search index, queue), probe/debug/load assets | Dependency adapters, probe/debug tests, performance/replay as opt-in evidence |
| Mature multi-service workspace | Handler/logic/service/infra modules, DI wiring, codegen Makefile, shared runtime wrappers, DB/MQ adapters, config, live-dependency tests | Thin handlers, generated code through reproducible commands, ctx/log/trace through clients, visible DB/MQ retries + transaction boundaries, live-dependency tests outside fast gate |
| High-risk service samples | Targeted context / idempotency / audit / repair samples | Missing-context rejection, durable idempotency, mutation-plus-audit atomicity or repair, visible admin repair states |
| Shared platform packages | Discovery-backed HTTP clients, secret accessors, dynamic config, ID allocation, DB proxy/DAL generation, object storage, migration tooling | Constructor/DI paths beside convenience globals; dynamic-config backend abstraction; generated DAL builder mutability; object migration conflict policy + replay logs |
| Shared cache/lock packages | Cache client with Lua/CAS helpers, lock/renew/unlock, missing-script fallback, result codes | Atomic script + fallback, compare-and-delete unlock, compare-and-expire renewal, positive-only counter, pending/completed idempotency |
| Infra control-plane services | Release-facing CLI, internal RPC proxy, generator image, dynamic service registration, KMS, ID service, tracker, RPC proxy | Executable rules for CLI progress/wait, approval/deploy/canary boundaries, generator cleanup guards, RPC proxy metadata/connection handling |
| Database / DAL layer | DB wrapper, sharding plugin, DDL/index samples, repository query/update methods, DAL tests | Batch-upsert generated-field repair, explicit updatable-column lists, schema/query conflict-key alignment, DB/sharding assertions |
| Official docs | Language test/subtest guidance, code-review comments | Focused tests, context/error hygiene, useful failure messages |

## Sibling-generalization mini-map (template)

For each Go extraction, record decisions across sibling skills:

- `python-service-dev` — does the same pattern apply to Python? mirror with evidence caveat.
- `go-microservice-architecture` — does the rule belong at architecture level instead?
- `python-service-architecture` — cross-language architecture consequence?
- `testing-strategy` — does this affect test-layer policy?
- `defect-diagnosis` — does this prevent a class of defect?

Decisions go in the private alias map alongside the per-batch extraction log.

## Coverage discipline rules

- Mark each dimension `pending` / `read` / `deep-read` / `excluded` / `unavailable` / `routed` with the actual artifacts inspected.
- Distinguish targeted mechanism extraction from full coverage; never claim "complete" for representative-sample work.
- Re-read source artifacts when changing rules; use `wording cleanup` / `no new source read` labels honestly.

## Where the live provenance lives

For the maintainer's current Go extraction project, see:
- Private alias map: `~/.<host>/.private-aliases/<project>.yaml`
- Per-batch extraction logs: `~/.<host>/skills/.extraction-work/<batch>-completion.md`
- These files are never pushed to the shared skill tree.

## Audit gate

Before committing a change to this skill, run the private alias map's `audit_cmd` against the changed shared-skill files. Any hit on real repo names, branch states, dates, file counts, or business-domain nouns is either fixed or recorded as `known_debt` in the alias map. Pre-existing leakage may be grandfathered; new or modified content must remain zero-hit.
