# Data Modeling And Migrations

Use this for SQLAlchemy, SQLModel, Django ORM, Alembic, transactions, and storage ownership.

## Ownership

- A Python service owns its write schema and migration history.
- Shared databases require explicit ownership rules. Do not let two services write the same tables without a designed contract.
- Keep ORM models, repository interfaces, transactions, and migration scripts aligned.

## Migration Policy

- Treat Alembic autogenerate output as a draft. Review table names, indexes, constraints, data migrations, downgrade/rollback expectations, and lock impact.
- Keep generated migrations in source control, with human-edited intent where needed.
- For Django, treat migrations as source artifacts too; review data migrations and irreversible operations.
- Define deploy order for schema changes that require application compatibility.

## Index And Query Model

Evidence boundary: these rules are cross-stack backend guidance expressed for Python ORM and migration tooling. Confirm the active repository's migrations, ORM conventions, database dialect, and observed repository methods before claiming local completeness.

- Define expected query filters, joins, sort order, and pagination strategy before finalizing ORM models or migrations.
- Composite indexes should match actual access paths: leading equality or `IN` predicates first, then range/order fields. Single-column `index=True` fields do not replace a reviewed composite index when the repository method filters by multiple columns.
- Unique constraints should represent product/data invariants, not only performance. Upsert or de-duplication paths that re-query rows to recover generated fields need a stable unique/conflict key that matches the re-query shape.
- Treat leading-wildcard search, broad `OR`, tuple or large `IN`, `DISTINCT` over joins, and offset pagination as warnings for hot user paths. Either prove bounded cardinality and a query-plan budget, or move the use case to exact-match filters, keyset pagination, or a search/read-model projection.
- Query-plan tooling such as SQLAlchemy compiled SQL plus database `EXPLAIN`, or Django `QuerySet.explain()`, is a safety net. It does not replace reviewing migrations, access paths, and production cardinality assumptions.

## Transactions

- Use explicit unit-of-work/session boundaries for multi-step writes.
- Avoid opening sessions deep inside domain functions when the caller owns the transaction.
- Keep DB read/write routing and transaction ownership in a shared infrastructure layer when one exists.
- Redis, queues, and external calls inside DB transactions require careful outbox, idempotency, or compensation design.

## Postgres Driver Choice (Architecture Axis)

- **Driver choice is an architecture decision, not a developer preference** — it constrains sync/async coexistence, ecosystem maturity, and operational tooling (psql tools, observability libraries, ORM dialect availability). Decide at service-shape time, not when the first repository method is written.
- **`psycopg` v3 is the default for new services that need both sync and async** — per psycopg docs, one library, one DBAPI, both `create_engine()` and `create_async_engine()` consume the same URL with SQLAlchemy auto-selecting sync vs asyncio dialect. Supports modern Postgres features (composite types, JSONB, pipeline mode, server-side parameter binding). Migration target for psycopg2 (maintenance mode, no new features). Architecture impact: one driver across web handlers, Alembic migration runner, batch scripts, CLI tools, admin paths — no driver-boundary cognitive overhead.
- **`asyncpg` is the alternative for pure-async high-throughput services** — independent driver, optimized for the async path; SQLAlchemy supports it as an async dialect. Architecture cost: any sync code path (Alembic, batch scripts, sync admin) will pull in psycopg2/psycopg anyway, producing a two-driver service. Choose asyncpg only when (a) the service is genuinely 100% async, (b) profiled benchmarks show measurable improvement over psycopg async on the actual workload (the gap has narrowed in psycopg v3), (c) the team accepts the cost of two-driver maintenance. The "asyncpg is faster" claim is generic; verify against the workload before letting it drive a driver split.
- **For non-Postgres dialects, the same architectural question applies but with different defaults**: MySQL async → prefer `asyncmy` for new services; `aiomysql` is allowed when deliberately chosen or already established in the service, and should not be replaced solely to comply with the default. MySQL sync → prefer `mysqlclient`; `PyMySQL` is allowed for portability or existing convention. SQLite → built-in `sqlite3` (sync) + `aiosqlite` for async. Document the chosen driver per dialect at architecture level and do not mix two MySQL async drivers inside one service boundary.

## Connection Pool And Proxy Topology

- Pool sizing is a contract between the service, the connection proxy (PgBouncer, RDS Proxy), and the database server. Architecture must name the binding constraint and document how worker count, async concurrency, and replica count combine into the global connection budget.
- Decide proxy mode (session vs transaction pooling) at the architecture level; transaction pooling forces the service to give up session-level state (server-side cursors, `LISTEN/NOTIFY`, prepared-statement caches, advisory locks held across statements). Code patterns that depend on session continuity must be redesigned or routed to a session-pooling pool.
- Recycle intervals (`pool_recycle`, proxy idle timeout, load balancer idle timeout) must satisfy `recycle < idle_timeout` at every hop; architecture documents the tightest hop and the resulting client setting.

## Read Replica And Routing Boundary

- If the deployment includes read replicas, architecture declares which read paths can tolerate replica lag and which must read through the primary. Replica reads are a feature with a consistency contract, not a transparent optimization.
- Read-after-write within a request window routes to primary until the consistency window closes; the window length and the carrier (request scope, causality token, session flag) are architecture decisions.
- Replica engines should use read-only DB credentials so write attempts fail loudly at the database, not silently against the wrong endpoint.

## Outbox And Dual-Write Consistency

- DB-plus-Redis or DB-plus-MQ writes must use an outbox table when both must reflect the same business fact. Architecture declares which write paths cross a durability boundary and need outbox; ad hoc dual writes are review findings.
- Outbox publishing is at-least-once; downstream consumers carry the idempotency burden. Architecture names the consumer-side idempotency mechanism (unique key, idempotency store, state machine) per outbox topic.
- High-throughput outbox paths may use CDC (logical replication, binlog tail) instead of polling; architecture names the chosen strategy and the durability contract it provides.

## Long-Running Transaction Budget

- Architecture sets per-role transaction time budgets and chooses the enforcement layer: database `statement_timeout` / `idle_in_transaction_session_timeout`, framework-level transaction wrapper with timeout, or both.
- External calls (HTTP, inference, object storage) inside DB transactions are an architectural error unless explicitly documented with a compensation plan. Streaming responses and websocket handlers must commit before entering the long phase.
- Transaction-duration histograms and idle-in-transaction counts are first-class SLI/SLO signals owned at the platform observability layer; this skill names the emission contract.
