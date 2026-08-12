# Python Dev Source Evidence Map (Methodology Template)

This file describes the **shape** of source-evidence tracking for Python implementation extraction. Project-specific provenance (real repo names, branch state, dates, module counts, extraction logs) lives in the maintainer's private alias file at `~/.<host>/.private-aliases/<project>.yaml`, never in this shared skill tree — see `skill-extraction-workflow` Core Rule "Extraction lifecycle handoff".

## Scope boundary

This shared template contains reusable methodology only. Do not add concrete repository names, branch state, infrastructure details, owner maps, or internal package conventions.

## Source coverage dimensions

When extracting Python implementation guidance from a new source set, organize evidence by these dimensions in the private alias map:

| Dimension | What to collect | What to extract |
| --- | --- | --- |
| Broad Python inventory | Module count by shape (service vs library vs notebook vs tool) | Implementation guidance must classify shape before recommending patterns |
| Web service samples | FastAPI / Flask / Django app factory, routes, dependency injection, middleware order, lifespan handlers | App-factory pattern, thin handlers, explicit dependency assembly, lifespan startup/shutdown |
| Async / sync isolation | Real call chains showing async + blocking I/O / CPU / GPU work | Reject async if blocking work hides inside; isolate via thread/process pool with explicit boundary |
| Pydantic / OpenAPI samples | Schema files, validation rules, error responses | Typed contracts; additive evolution; never use untyped dicts for public API |
| ORM / migrations | SQLAlchemy / Django ORM / SQLModel session, unit-of-work, Alembic migration history | Session-per-request, transaction boundary, reviewed migrations (autogen is draft) |
| Worker samples | Celery / RQ / arq tasks, schedule, retry, idempotency, ack semantics | Tool-specific caveats (Celery ack/retry/visibility, RQ timeout/TTL, arq async retry/defer); transactional enqueue/outbox boundary |
| AI / inference adapter | LLM client, streaming protocol, replay store, token-cost tracker | Reject new turn while prior in-flight; persist partial state on timer; explicit terminal/recoverable states; close stream readers; record cost after completion |
| Redis / cache | Client wrapper, Lua/CAS scripts, lock/renew helpers, idempotency state | Atomic script + fallback, compare-and-delete unlock, compare-and-expire renewal, positive-only counter, pending/completed idempotency |
| Object storage / migrations | Storage client, conflict policy, source tagging, replay logs | Constructor/DI paths, conflict policy, source tagging, bounded concurrency |
| Dynamic config | Config center client (etcd / Apollo / equivalent), key namespace, listener registration | Typed accessors, key namespace, listener registration, fail-mode discipline (last-known-good vs fail-closed vs fail-open) |
| Test layer | unit / integration / live-dependency separation, fixtures, mocks | Focused tests, live-dependency tests outside fast gate |
| Packaging | uv / poetry / pip-tools, lockfile, dependency groups, container | Reproducible builds, pinned, documented entrypoint |
| Official docs | Python language / framework / library official docs | Stable references for primitive behavior |

## Sibling-generalization mini-map (template)

For each Python extraction, record decisions across sibling skills:

- `python-service-architecture` — does the rule belong at architecture level instead?
- `go-microservice-dev` — does the same pattern apply to Go? mirror with evidence caveat.
- `go-microservice-architecture` — cross-language architecture consequence?
- `llm-inference-integration` — does the AI/inference-adjacent rule belong there?
- `testing-strategy` — does this affect test-layer policy?
- `defect-diagnosis` — does this prevent a class of defect?

Decisions go in the private alias map alongside the per-batch extraction log.

## Coverage discipline rules

- Mark each dimension `pending` / `read` / `deep-read` / `excluded` / `unavailable` / `routed` with the actual artifacts inspected.
- Distinguish targeted mechanism extraction from full coverage.
- Re-read source artifacts when changing rules; use `wording cleanup` / `no new source read` labels honestly.

## Where the live provenance lives

For the maintainer's current Python extraction project, see:
- Private alias map: `~/.<host>/.private-aliases/<project>.yaml`
- Per-batch extraction logs: `~/.<host>/skills/.extraction-work/<batch>-completion.md`

## Audit gate

Before committing a change to this skill, run the private alias map's `audit_cmd` against the changed shared-skill files. Any hit on real repo names, branch states, dates, file counts, or business-domain nouns is either fixed or recorded as `known_debt` (pre-existing hits only — new/modified content must stay zero-hit per the R0 rule).
