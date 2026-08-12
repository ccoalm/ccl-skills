# DB Schema And DAL Patterns

Use this when implementing DDL, generated DB models, DAL methods, transactions, sharding-aware queries, or DB migration tests.

## DDL-First Workflow

- Change DDL before model or repository code.
- Keep DDL, generated model/query/updater/DAL output, and hand-written repository changes in the same change.
- If a generator reads live DB schema, prefer a checked-in DDL file for reviewability when possible.
- Record migration order and rollback notes near the change or in the release plan.
- Run formatting and compile after codegen.

## Generated Model And DAL

- Generated model output should include:
  - table name.
  - column constants.
  - struct fields and tags.
  - query builder helpers.
  - updater helpers.
  - updatable column list.
- Generated DAL output should include a constructor, interface, embedded generic DAL, and `With(tx)` or equivalent transaction binding.
- Do not hand-edit generated model files. Fix generator input/templates or add hand-written repository methods beside generated code.
- Protect immutable columns from generic update helpers: primary key, create time, creator, immutable scope key, and unique domain keys.

## DB Proxy And Connections

- Build DB clients from typed config and secret provider; do not embed usernames/passwords in code or config files.
- Discover DB endpoints through service discovery or explicit environment config.
- Configure read/write separation when supported:
  - reads use read connection.
  - writes use write connection.
  - transaction-bound repositories use the transaction connection.
- Match the reference stack's core DB abstraction shape, not just the concept. If the reference exposes `Tx(ctx, fn)` or repository `With(tx)`, add or reuse that shared helper instead of scattering hand-written transaction templates through business repositories.
- Set connection timeout, read timeout, write timeout, max open, max idle, idle lifetime, and max lifetime.
- Attach tracing and query logging at proxy initialization.

## Repository Methods

- Expose intent-focused methods such as `GetByID`, `GetByIDs`, `ListByStatus`, `Create`, `UpdateStatus`, `MarkDeleted`, and `Upsert`.
- Reject empty required conditions for update/delete/query-all helpers.
- Treat empty-condition protection as a hard invariant for generic helpers; callers that truly need full-table scans or bulk updates must use a separate, explicitly named admin/backfill path.
- Put a hard maximum limit on generic list helpers.
- Batch create/upsert helpers should enforce a max batch size and return affected rows when the caller needs retry or stale-write detection.
- When batch upsert must leave caller-owned objects with database-generated IDs or other generated fields, re-query by the exact domain unique key or conflict key after the write, map results back to the input objects, and fail if any non-deleted or non-skipped input row cannot be matched. Do not assume `CreateInBatches` plus `OnConflict` reliably hydrates generated IDs for every dialect or path.
- Prefer keyset pagination for large tables: `id > lastID` or another stable indexed key.
- Return affected row count when callers need to detect stale state, missing rows, or compare-and-update failure.
- Keep raw SQL localized and parameterized.
- If query or update builders are mutable or single-use, document that behavior and cover it with tests so callers do not accidentally reuse cleared conditions across reads, updates, or retries.
- **GORM generics API (gorm.io v1.30+, 2025) for new repository code** — call shape changes from `db.Where("status=?", s).Find(&users)` (uses shared `*gorm.DB` instance that has historically caused SQL-pollution bugs when the same `db` got reused with leftover where-clauses) to `gorm.G[User](db).Where(...).Find(ctx)` (generic typed query bound to `User`, each `gorm.G[T](db)` builds a fresh chain). Per gorm.io docs, the generics API is fully backward-compatible (mix generic + traditional in the same project; existing repositories untouched). **APIs DELIBERATELY REMOVED in the generics path**: `FirstOrCreate` and `Save` are not present in generics because the original semantics are race-prone / ambiguous (`FirstOrCreate` lacks atomicity guarantees on most dialects; `Save`'s "auto INSERT or UPDATE based on primary key presence" is the bug source the team has spent time on historically). **Migration trap for `Save` callers**: the legacy pattern `db.Save(&user)` does INSERT-or-UPDATE based on whether the primary key is zero; rewriting it as `gorm.G[User](db).Create(ctx, &user)` will FAIL with duplicate-key on the second call (no UPDATE fallback), and `gorm.G[User](db).Updates(ctx, &user)` does no INSERT for new rows. The correct generics rewrite is to branch explicitly: check whether the PK is set / fetch-by-PK first, then call `Create` for new rows or `Updates` for existing rows; for true upsert use `gorm.G[User](db).OnConflict(...).Create(ctx, &user)` (verify clause syntax against current docs). Audit each `Save` call site for the team's intended semantics before mechanical replacement — Save covered both "insert this" and "update this" cases under one verb, and they often need different branches in generics. Generics also adds transaction-timeout handling so a leaked transaction does not silently consume a pool slot forever. New repository methods on Go 1.21+ services should default to generics; legacy `db.Where(...).Find(&out)` repositories can stay until touched, then migrate per touch.

## Transactions

- Use `With(tx)` repositories inside a transaction; do not accidentally call the default read/write proxy mid-transaction.
- If the project does not yet expose a shared transaction helper, add it in the DB/platform/DAL layer before implementing business code that needs multi-step atomic writes.
- Roll back on error and panic; log panic stack with trace/log id.
- Keep transaction scope small. Do validation and remote calls outside the transaction when correctness allows.
- Re-read mutable rows inside the transaction before applying counters, quotas, quantities, or state transitions.
- For idempotent writes, use unique keys or persisted idempotency records, not only in-memory checks.
- If upsert falls back to update-all when the model does not declare updatable columns, treat that as a review finding for durable records. Either add an explicit mutable-column list or document why every column is safe to overwrite.

## Sharding-Safe Queries

- Sharded writes must include the shard key and primary/domain key needed by the routing function.
- Targeted reads, updates, and deletes must include shard key or another supported routing key.
- Do not update shard key columns.
- For migrations, generate DDL for every shard and apply consistently.
- For bypass/admin queries, require an explicit no-sharding mode and keep it out of normal request paths.
- Multi-shard fanout should be bounded, observable, and preferably offline or projection-backed.

## Index Safety

- Tests or local checks should catch common missing-index queries before production.
- For hot paths, inspect query plans for expected index use.
- If adding a query-plan checker plugin, guard against recursive checks, metadata/migration queries, and excessive production overhead.
- Query builders should make order, limit, equality filters, range filters, and unscoped soft-delete behavior explicit.
- Avoid `LIKE` prefixes, broad `IN` lists, and unbounded `ORDER BY` unless the index model supports them.
- Do not use production-only query-plan checks as the only guard; review schema and indexes in code.
- Review index safety from the DDL and DAL together. For every repository method that is expected to be hot, compare its equality predicates, `IN` predicates, joins, soft-delete predicate, order, and pagination with the left-prefix order of the table's composite indexes. A single-column index somewhere on the table is not enough evidence.
- If a method needs an index hint to be stable, treat the hint as a compatibility contract: the named index must exist in checked-in DDL, match the method's predicate order, and be covered by an assertion-based query-plan or integration test. Do not leave stale migration comments or hints that disagree with the DDL.
- Re-query-after-upsert paths should use the same unique/conflict key shape that the write uses. If the re-query adds extra filters, those filters must be covered by the same composite index, be redundant with the unique key, or be explicitly documented as a bounded narrowing condition.
- For tuple `IN`, large `IN` lists, offset pagination, `OR`, or leading-wildcard `LIKE`, record why the expected cardinality is bounded or move the path to a search/projection/keyset flow. These shapes require query-plan evidence before they become release-gating hot paths.
- Non-production query-plan checkers should fail or surface missing-index queries in tests or local development, but they are only smoke evidence unless they assert the expected key, row estimate, and representative predicates.

## Migration And Backfill Implementation

- Backfills should run in bounded batches with resume markers.
- Use idempotent batch writes or compare-and-update so retries are safe.
- Emit progress metrics: read, updated, skipped, failed, duration, and last marker.
- Keep sleep/backoff configurable.
- Stop on irreversible data corruption risk; skip and record individual bad rows only when product semantics allow it.
- Never run long backfills inside request handlers.

## Tests

- Unit-test query option builders for equality, range, ordering, limit, soft-delete, and empty-condition behavior.
- Test repository methods with fakes when SQL shape is not important and with integration tests when SQL shape matters.
- Test transactions for rollback on error and panic.
- Test upsert update-column lists protect immutable fields.
- Test sharding route logic for insert, select, update, delete, missing shard key, multi-shard rejection, and shard-key update rejection.
- Test migrations/backfills with small fixtures and repeated runs to prove idempotency.

## Outbox For Cross-Write Consistency

- When a DB write must be reflected in Redis, MQ, or an external system, use an outbox table written in the same transaction as the business row. A relay (sidecar, worker, or CDC consumer) publishes pending rows and marks them processed.
- Do not write to Redis or publish to MQ inside the DB transaction expecting both to succeed; either commit on the DB side and discover the external write failed, or fail the external write and leave the DB committed.
- Outbox publishing is at-least-once; downstream consumers must be idempotent — unique key, idempotency store, or state machine.
- Treat oldest-pending-age and failed-publish count as first-class metrics; both feed paging policy.
- For high-throughput cases, consider CDC (binlog tail or logical replication) instead of polling the outbox table. The choice between polling and CDC is an architecture decision, not an implementation detail.
