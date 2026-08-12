# SQLAlchemy And Migrations Patterns

Use this for SQLAlchemy, SQLModel, Django ORM, Alembic, repository code, and transactions.

## Implementation

- Use repository or data-access modules to keep SQL/ORM details out of routes.
- Use explicit session ownership. The caller should know whether it owns commit/rollback.
- Use `with session.begin()` or repo-standard unit-of-work helpers for multi-step writes.
- New Python relational services use SQLAlchemy 2.x plus Alembic by default unless the service records a deliberate alternative data-access choice; use framework ORM and migrations when the chosen framework, such as Django, owns that boundary. For new MySQL async services, prefer `asyncmy`; `aiomysql` is allowed when deliberately chosen or already established. Do not replace an existing working `aiomysql` driver solely to comply with the default. Do not mix MySQL async drivers inside one service boundary.
- Keep indexes, unique constraints, and query filters aligned with API access patterns.
- If repository filters, query builders, or update builders are mutable or single-use, document that behavior and cover it with tests so callers do not accidentally reuse cleared conditions across reads, updates, or retries.

## Index Safety

Evidence boundary: these rules generalize backend index-risk mechanics to Python ORM and migration tooling. Before treating them as local convention, confirm the active repository's database, migration framework, repository patterns, and query-plan tooling.

- Review SQLAlchemy, SQLModel, Django ORM, and raw SQL repository methods against the migration-defined indexes. For hot paths, compare `.filter()`/`.where()` predicates, joins, soft-delete filters, `order_by`, `limit`/`offset`, and pagination with the left-prefix order of composite indexes in Alembic or Django migrations.
- Do not treat `index=True` on a model field as enough proof. Composite access paths, uniqueness, partial indexes, functional indexes, and sort order must be visible in reviewed migrations or schema metadata.
- For SQLAlchemy, use compiled SQL, query logging, or database-specific `EXPLAIN` in integration tests when SQL shape matters. For Django, inspect `QuerySet.explain()` or the generated SQL for hot repository methods. Assert the expected index/key or a bounded plan/row estimate when the database target makes that stable.
- Leading-wildcard `like`/`ilike`, broad `or_()`/`Q(... | ...)`, tuple or large `in_`, `distinct()` over joins, and offset pagination need a documented cardinality bound, a query-plan test, or a separate search/read-model/keyset path before they are treated as production hot paths.
- If a repository uses dialect-specific index hints or raw SQL to force a plan, keep the hinted index in checked-in migrations and cover the method with an integration test. Hints without migration evidence are review findings.
- Upsert or idempotent write paths that re-query to repair generated IDs or timestamps should re-query by the same unique/conflict key shape used by the write. Extra filters must be redundant, indexed, or explicitly justified as bounded narrowing conditions.

## Migrations

- Generate migrations when the tool supports it, then review and edit them.
- Include indexes, constraints, data migration risks, downgrade/rollback expectations, and lock impact.
- Keep migration files near model/repository changes in the same implementation slice.

## Postgres Driver Choice (psycopg vs asyncpg)

- **`psycopg` (v3, formerly psycopg3) is the recommended modern Postgres driver for new SQLAlchemy 2.x services that need both sync and async support** — per psycopg docs, it ships one library with both a PEP-249 sync API and an asyncio-native async API. **Per SQLAlchemy docs**, the `postgresql+psycopg://...` URL is the unified dialect for psycopg v3 and SQLAlchemy auto-selects the sync vs asyncio implementation based on which engine constructor is called (`create_engine()` vs `create_async_engine()`); this is a SQLAlchemy-dialect convenience, not a psycopg-only feature. Built-in support for pipeline mode, server-side parameter binding, and current Postgres features. Migration target for services on psycopg2 (which is in maintenance, not EOL but no new features). Choose psycopg when (a) the service has any sync code path (CLI, scripts, sync framework), (b) the team wants one driver for the whole codebase, (c) modern Postgres features (composite types, JSONB nuances, async pipeline) matter. **PgBouncer transaction-pooling footgun**: psycopg v3 uses server-side prepared statements by default for repeated queries — under PgBouncer in `pool_mode = transaction` (or RDS Proxy / similar transaction-pooled proxy), prepared statements registered on one backend connection will not exist on the next pooled connection and queries fail with `prepared statement "_pg3_N" does not exist`. Mitigations: disable psycopg server-side prepared statements via `prepare_threshold=None` on the connection (or per-cursor), switch PgBouncer to `session` pooling for that service (gives up connection multiplexing), or run psycopg against a direct Postgres connection / session-pooled endpoint. Same caution applies to other session-state operations (server-side cursors, `LISTEN/NOTIFY`, advisory locks held across statements) — these are not psycopg-specific but psycopg's prepared-statement default surfaces the problem faster than psycopg2 did.
- **`asyncpg` is the alternative for pure-async high-throughput Postgres workloads** — independent of psycopg lineage, optimized for the async path; SQLAlchemy supports it as an async dialect. Per official docs, asyncpg often wins synthetic benchmarks vs psycopg async, but the gap has narrowed and the operational cost of "different sync and async drivers in one service" is real. Choose asyncpg only when: (a) the service is 100% async with no sync DB path anywhere, (b) profiled hot-path evidence shows measurable improvement over psycopg async, (c) team accepts that any future sync code (Alembic migration runner, batch script, admin CLI) will use psycopg2/psycopg, creating a two-driver setup. Mixing both is acceptable when migrations + sync admin paths legitimately stay on psycopg and the async serving path is asyncpg, but record the boundary explicitly.

## Async Session Boundaries

`AsyncSession` from SQLAlchemy 2.0 is bound to a single event loop and a single task at a time.

- Do not share one `AsyncSession` across child tasks of `asyncio.gather`, `asyncio.TaskGroup`, or background-task launches. Each concurrent worker needs its own session from the same `async_sessionmaker` or its own `async with session.begin()` scope.
- Do not pass an `AsyncSession` into a background coroutine that outlives the originating request, FastAPI dependency, or async-context block; the connection may already be returned to the pool by the time the background work runs.
- Sync drivers in async paths: do not call `Session` (sync) or sync DB-API code from async handlers — wrap with `asyncio.to_thread` and an isolated sync engine if a sync-only library is unavoidable.
- Use `async_sessionmaker(expire_on_commit=False)` when the request handler will read instance attributes after commit; otherwise expect detached-instance errors.
- For request-scoped sessions in FastAPI, yield from a dependency that opens and closes the session; do not store sessions on `request.state` for later use after the dependency exits.

## Connection Pool Sizing And Proxy Interaction

Pool sizing is a contract between the application, the connection proxy (PgBouncer, RDS Proxy, Azure Database Proxy), and the database server.

- Derive per-process `pool_size + max_overflow` from a global connection budget, not from a per-process demand multiplier. Compute the global budget as the smallest binding constraint among database `max_connections` (minus reserved superuser/admin slots), proxy client-connection limit, and any reserved capacity for other services. Divide that budget across (replicas × processes_per_replica) to get the per-process limit; pick `pool_size` and `max_overflow` so that `pool_size + max_overflow ≤ per-process limit`.
- Async concurrency per worker is a **demand signal**, not the pool size. High in-flight concurrency tells you the pool is undersized for the workload (rising checkout latency, overflow exhaustion); the response is to grow workers/replicas, raise the global budget if the DB and proxy allow it, or shed load — not to set `pool_size = workers × concurrency` literally.
- Under a transaction-pooling proxy (PgBouncer default, RDS Proxy in some modes), session-level state does not survive between transactions: avoid `SET LOCAL` outside an open transaction, server-side cursors that span statements, prepared statements cached client-side, `LISTEN/NOTIFY`, and advisory locks that expect session continuity. Configure SQLAlchemy with `pool_pre_ping=True`, disable statement caching where the proxy mode requires it, and reset session state explicitly when reuse is intentional.
- Set `pool_recycle` shorter than the proxy or load balancer idle timeout to avoid stale connection errors.
- Treat `QueuePool.overflow()` and checkout latency as observable metrics; sustained checkout latency means the pool is undersized for the current concurrency.

## Outbox Pattern For Cross-Write Consistency

Writing to the database and then writing to Redis or a message queue is not atomic. Use an outbox table when both must reflect the same business fact.

- In the same DB transaction as the business write, insert a row into an `outbox` table with the payload, target topic/channel, and a status column.
- A separate relay (sidecar, worker, or CDC consumer) reads pending outbox rows, publishes to MQ/Redis, and marks the row processed. Publishing is at-least-once; consumers must be idempotent.
- Do not write to Redis or publish to MQ inside the DB transaction expecting both to succeed; either commit on the DB side and discover the external write failed, or fail the external write and leave the DB committed.
- Outbox rows that are never published need an alarm path; failed-publish counts and oldest-pending-age are first-class metrics.
- For high-throughput cases, consider logical replication / CDC (e.g., Debezium-style) to read the WAL/binlog instead of polling the outbox table.

## Read Replica Routing

When the deployment includes read replicas, application-layer routing decides which session factory each call uses.

- Maintain a separate `async_sessionmaker` (or session factory) per role: writer (primary), reader (replica). Do not route inside repository methods on a per-statement basis unless the framework already provides safe routing.
- Default writes and read-after-write within the same request to the writer; route only pure reads with no write dependency to the replica.
- Replica lag is non-zero. For "read your own writes" within a session, hold a write-consistency window (request scope, causality token, or master-on-write flag stored on the session/context) and route to writer during that window.
- Forced master read for diagnostics and admin paths should be an explicit option, not a default.
- Never write through a replica session by accident: replica engines should be configured with read-only DB users when the database supports it.

## Long-Running Transaction And Idle-In-Transaction Monitoring

Hot connection on an open transaction blocks vacuum/autovacuum (PostgreSQL) and burns row locks; idle-in-transaction is a common production fire.

- Configure database-side limits: PostgreSQL `statement_timeout` per role (short for OLTP roles, longer for batch roles) and `idle_in_transaction_session_timeout` to cap stuck transactions; MySQL `MAX_EXECUTION_TIME` hint or `max_execution_time` server var.
- Instrument transaction duration as a histogram; alert on p95/p99 above the SLO for the path.
- FastAPI dependency-scoped sessions implicitly tie the transaction to the request lifetime; do not extend the session into background tasks, streaming responses that do not commit promptly, or long-running websocket loops.
- Do not run external HTTP calls, inference calls, or long object-storage uploads inside an open DB transaction; commit first or move the external call outside the transaction boundary.
- Watch for implicit transactions opened by auto-begin behavior on first statement; commit or rollback explicitly at the request boundary.

## Alembic CI Dry-Run And Drift Detection

Migrations are reviewable source artifacts and should fail CI when they drift from models or when production schema cannot replay them.

- Run `alembic upgrade --sql head` in CI against a known starting revision to render the SQL plan; review the rendered SQL in code review when the migration is data-sensitive.
- Run `alembic check` (or `alembic revision --autogenerate --check` style) in CI to detect uncommitted model→schema drift; fail the build when autogenerate produces a non-empty diff and the PR did not include a corresponding revision.
- Maintain a baseline-revision policy: CI applies all migrations against an empty database and a copy of the previous release schema; both must succeed.
- Data migrations and irreversible operations (column drop, type change with implicit cast) must be split from schema migrations and reviewed separately; never let `autogenerate` produce destructive operations silently.
- Do not let `alembic merge` resolve concurrent heads without a human reading the merge; merges hide ordering bugs.

## Tests

- Use fake repositories for pure service tests.
- Use real DB integration tests only when SQL semantics, constraints, transactions, or migrations are under test.
