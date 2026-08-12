# Python Architecture Source Evidence Map (Methodology Template)

This file describes the **shape** of source-evidence tracking for Python architecture extraction. Project-specific provenance (real repo names, branch state, dates, module counts, extraction logs) lives in the maintainer's private alias file at `~/.<host>/.private-aliases/<project>.yaml`, never in this shared skill tree — see `skill-extraction-workflow` Core Rule "Extraction lifecycle handoff".

## Scope boundary

This shared template contains reusable methodology only. Do not add concrete repository names, branch state, module counts, package descriptors, or extraction logs.

## Source coverage dimensions (architecture-level)

When extracting Python architecture guidance from a new source set, organize evidence by these dimensions:

| Dimension | What to collect | What to extract at architecture layer |
| --- | --- | --- |
| Service boundary inventory | How services are split (by domain / by traffic class / by data ownership); inter-service contract count | Boundary criteria, when to split vs merge, ownership rules |
| API contract shape | Pydantic / OpenAPI / framework schemas in use, public-vs-internal API split, contract evolution practice | Contract-first discipline, additive evolution rule, public/internal split when stability needs differ |
| Data ownership | Per-service write model, cross-service read patterns, migration discipline (Alembic / framework migrations) | Each service owns its write model; cross-service reads through API; relational source-of-truth |
| Runtime platform | Service discovery integration, framework choice (FastAPI / Flask / Django / equivalent), dynamic config, secret management, observability, mesh integration | Workload identity, registry-based vs DNS-based SD, mesh ownership boundary, dependency client contracts |
| Async / sync model | asyncio call-chain hygiene, blocking work isolation (thread pool / `asyncio.to_thread` / process pool), framework async support | Async only when call chain and libraries are truly non-blocking; isolate blocking I/O / CPU / GPU explicitly |
| Worker / job design | Celery / RQ / arq / framework workers, schedule, retry, idempotency, backfill | Worker design as first-class architecture; idempotency key, lease, max execution |
| Error / context contract | Error code enum, exception → code map, ctx propagation through async paths | Stable enum, framework exception mapping, contextvars-as-source-of-truth for correlation |
| Reliability surfaces | Rate limit, backpressure, circuit breaker, idempotency, durable status | Reliability is architecture, not bolt-on |
| AI / LLM service hosting | Inference adapter shape, streaming protocol, replay, token cost, fallback | Service-side boundary only; inference design routes to `llm-inference-integration` |
| Generated code ownership | OpenAPI client gen, protobuf gen, ORM autogenerate, ownership boundary | Generated code is output; generation commands documented and portable |
| Packaging | Dependency manager (uv / poetry / pip), lockfile, container image, process model | Reproducible builds, pinned dependencies, documented process model |
| Release runtime | Deployment unit, mesh routing, canary, approval, rollback | Architecture surface, not afterthought |

## Sibling-generalization mini-map (template)

For each Python architecture extraction, record decisions across sibling skills:

- `python-service-dev` — does the architectural rule have an implementation pattern? note in dev reference.
- `go-microservice-architecture` — cross-language counterpart? mirror at architecture level.
- `go-microservice-dev` — implementation counterpart?
- `llm-inference-integration` — does the AI/inference-adjacent rule belong there instead?
- `testing-strategy` — what test layer proves the architectural property?
- `platform-observability` / `platform-service-connectivity` / `platform-release-engineering` — does the rule belong at platform layer?

Decisions go in the private alias map alongside the per-batch extraction log.

## Coverage discipline rules

- Architecture extractions describe **decision criteria, invariants, ownership boundaries, and acceptance checks**. Implementation patterns go to `python-service-dev`.
- Mark each dimension `pending` / `read` / `deep-read` / `excluded` / `unavailable` / `routed` with the actual artifacts inspected, in the private alias map.
- Re-read source artifacts when changing rules; use `wording cleanup` / `no new source read` labels honestly.

## Where the live provenance lives

For the maintainer's current Python extraction project, see:
- Private alias map: `~/.<host>/.private-aliases/<project>.yaml`
- Per-batch extraction logs: `~/.<host>/skills/.extraction-work/<batch>-completion.md`

## Audit gate

Before committing a change to this skill, run the private alias map's `audit_cmd` against the changed shared-skill files. Any hit on real repo names, branch states, dates, file counts, or business-domain nouns is either fixed or recorded as `known_debt` (pre-existing hits only — new/modified content must stay zero-hit per the R0 rule).
