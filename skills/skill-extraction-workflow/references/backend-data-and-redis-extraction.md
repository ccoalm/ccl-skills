# Backend Data And Redis Extraction Methods

Domain-specific extraction procedures relocated from `references/source-to-skill-extraction.md` (`## Domain Method Index`). Load this reference when mining repositories with relational/DAL, migration, sharding, cache, lock, idempotency, rate-limit, or Redis-backed coordination code. These methods own extraction procedure and routing only; target architecture, implementation, and testing skills own the reusable rules.

## Database And DAL Extraction Method

Use this when extracting database experience from repositories with models, DDL, migrations, generated DAL, repositories, query builders, transactions, cache locks, data migrations, or sharding logic. Do not summarize database experience from file counts alone.

Start with a database source register:

| Source class | Minimum evidence to collect | What to extract | Typical owner |
| --- | --- | --- | --- |
| Schema and model definitions | DDL, migrations, model structs/classes, generated schema metadata, comments, unique constraints, soft-delete fields, timestamps | Table ownership, source-of-truth, primary key strategy, required/default fields, enum/state fields, unique constraints, compatibility and rollback needs | Architecture skill |
| Indexes and query paths | Index definitions plus repository/service call sites that use the filter/order/group shape | Composite index order, stable pagination, uniqueness as data invariant, high-cardinality list safety, query-plan risk | Architecture and testing skills |
| Repository and DAL methods | Generated query/update helpers, handwritten repository methods, raw SQL, transaction-bound variants | Intent-focused repository APIs, query-builder safety, bounded lists, explicit update columns, raw SQL containment, read/write routing | Implementation skill |
| Create/upsert/import paths | Service mutation flow, validation, unique-key checks, batch import code, generated IDs, side effects | Idempotency, default state initialization, transaction boundary, partial-failure report, duplicate handling, post-create side effects | Implementation and testing skills |
| Update/delete/state transition paths | Status machine updates, partial updates, locks, compare-and-set, audit/outbox/cache/index updates | Optimistic/pessimistic locking, constrained updates, delete safety, audit/outbox atomicity, repair/replay path | Implementation, architecture, testing skills |
| Transactions and consistency | `Tx` wrappers, transaction-bound repositories, retry/rollback paths, panic recovery, post-commit effects | What must be atomic, what is async/repairable, stale/pending state visibility, compensation and reconciliation | Architecture and implementation skills |
| Sharding and partitioning | Shard key, router function, table suffix, shard-aware DAL, migration/backfill tools, bypass rules | Shard-key choice, query must-carry constraints, cross-shard aggregation policy, migration plan, route tests | Architecture, implementation, testing skills |
| Cache and DB interaction | Redis/cache keys, Lua/CAS helpers, invalidation, counters, locks, DB fallback | Cache-aside/write-through boundaries, stale-read tolerance, lock ownership, counter consistency, miss/rebuild behavior | Implementation and testing skills |
| Tests and CI | Unit/integration tests, live-infra tests, wrappers, migration dry-run, generated drift checks | Which DB behavior is actually asserted, which tests are diagnostic only, what new gates future DB changes need | Testing skill |

Extraction rules:

- Trace each durable rule through `schema/model -> query/mutation call site -> transaction/cache/side effect -> test or missing test`. A schema field or DAL method by itself is evidence of existence, not evidence of a reusable rule.
- Infer index lessons from real query shapes, not from index names alone. Record the filter, sort, pagination, and uniqueness invariant that make the index necessary.
- Separate table design from repository implementation. Architecture owns data ownership, source-of-truth, sharding, migration, and consistency policy; implementation owns generated DAL usage, repository shape, transaction helpers, update builders, and code safety; testing owns proof.
- For create/update/delete rules, identify the failure prevented: duplicate creation, lost update, invalid status transition, partial side effect, stale cache/index, unbounded write, or unrecoverable migration.
- For sharding rules, require a route key, query constraint, migration/backfill story, and test surface before landing a strong rule. If only table suffixes or router names were inspected, record provenance but downgrade the rule.
- For cross-language generalization, route language-agnostic lessons to architecture or testing first. Mirror into Python/Go implementation only when the target stack has enough evidence or the rule is about a shared concept such as repository boundary, transaction scope, migration review, or cache consistency.
- Keep raw SQL snippets, table names, field names, and business-domain labels out of shared guidance. Preserve only sanitized source rows and capability-level observations.

Database/DAL candidate rule ledger shape:

| Observation | Evidence path | Failure class | Candidate reusable rule | Keep/merge/route/discard | Target owner | Required verification |
| --- | --- | --- | --- | --- | --- | --- |
| Query filters by owner, state, and created time with stable sort | schema/index plus repository list call | slow list or unstable pagination | Composite index and pagination must match real filter/sort path | keep | architecture/testing | repository test, large-fixture test, or explain/dry-run note |

Completion standard:

- The final claim must say whether coverage is topology inventory, targeted DAL extraction, representative workflow extraction, or full database workflow extraction.
- A complete database extraction needs closed rows for schema/model, indexes/query paths, create/update/delete, transactions, cache/side effects, sharding/migration if present, and tests.
- Do not land a final database rule if the only evidence is generated code, file names, or a single isolated DAL helper without a caller.

## Redis Extraction Method

Use this when extracting Redis experience from repositories with cache adapters, distributed locks, Lua scripts, rate limiters, idempotency stores, counters, Redis Streams, Pub/Sub, lightweight task queues, local caches, or Redis-backed coordination. Do not reduce Redis extraction to a list of commands.

Start with a Redis source register:

| Source class | Minimum evidence to collect | What to extract | Typical owner |
| --- | --- | --- | --- |
| Client setup and lifecycle | Config, secret lookup, service discovery, sync/async client choice, pool/timeouts, ping/readiness, close/shutdown paths | Dependency assembly, fail-open/fail-closed behavior, test substitution, resource cleanup | Implementation and architecture skills |
| Key builders and scope | Key functions/constants, prefixes, tenant/user/resource dimensions, environment/lane isolation, pattern-delete use | Key namespace policy, collision prevention, sensitive-value avoidance, key migration/invalidation | Implementation and architecture skills |
| Cache usage | Cache-aside/write-through code, negative cache, JSON/schema decode, malformed payload handling, invalidation/delete paths, DB fallback | Freshness window, stale-read tolerance, cache miss vs Redis failure, value versioning, invalidation ownership | Implementation, architecture, testing skills |
| Locks and leases | `SET NX EX/PX`, Redlock/proven library, unique token, compare-and-delete unlock, renewal, wait/retry loops | Lock scope, lease/max lease, cancellation, renewal failure policy, duplicate-work prevention | Implementation and testing skills |
| Lua/CAS/transactions | Scripts, `EVAL`/`EVALSHA`, `NOSCRIPT` reload, `WATCH`/pipeline, return codes, error mapping | Atomic compound operation, compare-failed/missing-key semantics, fallback and observability | Implementation and testing skills |
| Counters, quotas, rate limits | `INCR/DECR`, positive-only counters, sorted-set sliding windows, retry/conflict behavior, expiry policy | Missing-key semantics, underflow behavior, exact vs approximate truth, user-facing error contract | Implementation, architecture, testing skills |
| Idempotency and dedupe | SETNX claims, pending/complete markers, owner tokens, retry counts, TTLs, persisted DB/outbox fallback | Duplicate handling, claim expiry, durable truth boundary, fail-safe behavior on Redis errors | Architecture, implementation, testing skills |
| Streams, Pub/Sub, queues | `XADD/XREAD`, consumer groups/ack if used, heartbeat, stream TTL, delete/trim, Pub/Sub publish/subscribe | Delivery guarantees, replay/resume point, lost-message tolerance, cleanup, user-visible progress state | Architecture, implementation, testing skills |
| Tests and diagnostics | Unit/integration tests, fake Redis/fakeredis, containers, live Redis tests, logs/metrics, slow/hot key checks | Which Redis behavior is asserted, which tests are diagnostic only, what future Redis changes need as gates | Testing skill |

Extraction rules:

- Classify each Redis use by responsibility first: cache, lock, idempotency, counter/quota, rate limit, stream/queue, session, config, or diagnostic helper. A command name alone is not a reusable pattern.
- For every kept rule, name the failure prevented: stale authorization, duplicate side effect, lock leakage, lost queue item, counter underflow, rate-limit bypass, cache poisoning, hot key, data leak in logs, or unbounded scan/delete.
- Trace correctness through `key scope -> command/script semantics -> failure behavior -> caller decision -> test or missing test`. A Redis helper without caller behavior or test evidence should usually remain provenance-only.
- Separate ephemeral coordination from durable truth. If Redis controls a domain outcome, require a persisted record, idempotency table, outbox/event log, reconciliation path, or explicit risk acceptance.
- For cross-language generalization, route language-agnostic Redis rules to architecture or testing first. Mirror into Python/Go implementation when the target stack has matching client/runtime concepts, and add an evidence caveat when a stack has not been directly inspected.
- Treat broad key deletion, blocking stream reads, Pub/Sub, live Redis tests, and script-cache fallback as risk surfaces that need explicit limits, cleanup, and observability before becoming recommended practice.
- Keep source-specific key names, stream names, tenant labels, business event names, endpoints, and raw payloads out of shared guidance. Preserve sanitized source rows and capability-level observations only.

Redis candidate rule ledger shape:

| Observation | Evidence path | Redis responsibility | Failure class | Candidate reusable rule | Keep/merge/route/discard | Target owner | Required verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Atomic claim script writes pending marker with TTL and returns explicit statuses | store implementation plus tests | idempotency | duplicate side effect or stuck pending claim | Idempotency claims need pending/complete states, TTLs, explicit return codes, and retry/removal behavior | keep | architecture/implementation/testing | duplicate, pending, expired, Redis-error tests |

Completion standard:

- The final claim must say whether coverage is Redis topology inventory, targeted Redis extraction, representative workflow extraction, or full Redis workflow extraction.
- A complete Redis extraction needs closed rows for client lifecycle, keys/TTL, cache, locks, atomic scripts, counters/rate limits if present, streams/queues if present, idempotency if present, observability, and tests.
- Do not land a final Redis rule if the only evidence is a command wrapper, file name, or one isolated helper without caller semantics or failure handling.
