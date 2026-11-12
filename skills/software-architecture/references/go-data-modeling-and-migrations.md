# Data Modeling And Migrations

Use this when designing relational data ownership, schema, indexes, migrations, sharding, or generated DAL boundaries for a Go microservice.

## Ownership

- Each service owns its write schema. Other services should not write owned tables directly.
- Cross-service reads should use RPC/API, events, or explicit read models.
- Shared database servers are an infrastructure detail; shared write ownership is an architecture smell.
- A table should have a clear owning service, lifecycle owner, retention policy, and operational contact.

## Schema Design

- Start from domain invariants, not handler DTOs.
- Define primary key, domain unique keys, status/state fields, version fields, timestamps, and soft-delete behavior deliberately.
- Prefer explicit integer or enum-like status fields over free-form strings for state machines.
- Store counters, quotas, mutable quantities, and precise numeric amounts in types that preserve precision and are safe for atomic updates.
- Avoid JSON columns for core queryable truth unless the schema is intentionally extensible and indexed access is not required.
- Include created/updated metadata only when the product can maintain it consistently.

## Index And Query Model

- Every list/query API should name its expected filters, sort order, and pagination strategy before schema is finalized.
- Unique constraints should represent product invariants, not just performance hints.
- Composite indexes should match common equality filters first, then range/order fields.
- Review composite indexes against actual access paths, not table columns in isolation. For each important read, update, delete, and post-upsert re-query path, name the leading equality or `IN` fields, optional range/order fields, join fields, soft-delete predicate, and expected cardinality; then verify the DDL has a matching left-prefix index or a deliberate projection/search alternative.
- When an upsert or de-duplication path later re-queries rows to recover generated fields, the schema must expose a stable unique or conflict key that matches that re-query. Extra predicates in the re-query must be redundant, indexed, or explicitly justified; otherwise the write path can silently miss rows or rely on accidental data shape.
- Add non-production query-plan checks when the stack supports them, but treat them as a safety net rather than a replacement for schema review.
- DAL/query helpers should make unsafe scans difficult: require explicit conditions for updates/deletes, require bounded limits for list reads, cap maximum batch size, and force explicit justification for full-table work.
- Avoid offset pagination for large or operational lists; prefer keyset pagination with a stable order.
- Leading-wildcard `LIKE`, broad `OR`, tuple or large `IN`, and `DISTINCT` over joined tables are schema-design warnings for hot user paths. Either prove bounded cardinality and a plan budget, or split the use case into exact-match filters plus a search/read-model path.
- Full-table reads need an explicit justification, bounded cardinality, or an offline/backfill execution model.
- Search, analytics, and document stores are projections unless explicitly chosen as source of truth.

## Transactions

- A transaction boundary should align with one service-owned relational store.
- Re-read mutable state inside the transaction before applying quantities, quotas, counters, or state transitions.
- Prefer compare-and-update, row lock, optimistic version, or unique-key idempotency for concurrent writes.
- Cross-system writes need outbox/inbox, idempotency, compensation, or a clear reconciliation process.
- Do not rely on Redis locks as the only correctness mechanism for durable relational truth.

## Sharding

- Decide sharding before data volume forces it; retrofitting sharding is a migration project.
- Define shard key, shard count, suffix format, routing function, and whether a main table is retained during migration.
- Shard key must be present in writes and targeted reads.
- Do not allow updates to shard key columns.
- Multi-shard queries should be rare, explicit, bounded, and preferably served by a projection/read model.
- DDL and index changes must apply consistently to every shard.

## Migration Strategy

- Migrations must be compatible with currently deployed code and rollback path.
- Migration design should cover historical data, queued messages, cached values, generated models, and read/write compatibility rather than only the final schema.
- Safe order for most changes:
  - add nullable column or new table.
  - deploy code that dual-reads or writes both shapes when needed.
  - backfill in bounded batches.
  - switch reads.
  - remove old shape only after all code paths are migrated.
- Risky migrations need feature gates, progress metrics, retry/skip behavior, and resume markers.
- Rollback plans should cover schema, data backfill, generated code, dynamic config, and message compatibility.

## Generated DAL Boundary

- DDL can be the source for generated model structs, table constants, query builders, update builders, and baseline DAL interfaces.
- Generated code should protect immutable columns such as primary key, create time, creator, and unique domain keys from generic updates.
- Generated query/update builders should expose typed comparison operators and explicit update-column selection rather than raw string fragments by default.
- Generated query builders are for simple filters; complex query methods still belong in hand-written repositories with tests.
- Generated output is part of the change and should be reviewed for semantic drift.
- Generated repository helpers should encode write-safety invariants, but architecture review still owns the invariant behind them: which columns are immutable, which fields form unique identity, which filters are mandatory for tenant or scope isolation, and which paths are allowed to bypass normal sharding or soft-delete behavior.

## Outbox And Dual-Write Consistency

- DB-plus-Redis or DB-plus-MQ writes that must reflect the same business fact use an outbox table; the outbox row is written in the same transaction as the business write. A relay (worker, sidecar, or CDC consumer) publishes pending rows at-least-once and marks them processed.
- Architecture declares which write paths cross a durability boundary and therefore need outbox; ad hoc dual writes are review findings. The consumer-side idempotency mechanism (unique key, idempotency store, state machine) is named per outbox topic.
- High-throughput paths may use CDC (binlog tail, logical replication) instead of polling; architecture names the chosen strategy and the durability contract it provides.
- Outbox health signals (oldest-pending-age, failed-publish count) belong to the platform observability layer; this skill names the emission contract.
