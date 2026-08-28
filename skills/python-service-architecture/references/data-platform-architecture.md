# Data Platform Architecture (Python)

Use when designing the data-platform substrate of a service or service-fleet: DB engine choice (single-instance OLTP, managed cloud DB, distributed SQL, sharding middleware), HA topology, read scaling and replica routing, sharding and resharding strategy, cross-region replication, backup and restore (with rehearsed recovery), cluster lifecycle (provision / scale / decommission / re-shard), capacity planning, fleet-wide schema-migration coordination, and connection-pool / proxy topology.

This complements `data-modeling-and-migrations.md` (which owns schema, index, transaction, outbox, and per-service migration concerns): this file owns the **substrate** that schema and queries sit on. Load both when designing a new data-bound service or auditing an existing one.

> **Sibling sync.** A parallel `go-microservice-architecture/references/data-platform-architecture.md` mirrors **all non-stack-specific sections** of this file. Only the *Python-specific implementation patterns* section diverges by stack. The mirrored sections stay free of three categories of stack-specific token: DB-engine-specific syntax, runtime/concurrency-mechanic names, and library/framework API names. The concrete token list and grep command live in the *Mirrored-section grep gate* subsection at the end of this file's stack-glue. Routing-reference text (backticked sibling-file links) may differ per tree; cross-file parity is machine-checked by `skill-extraction-workflow/scripts/check-parallel-stack-parity.sh` (wired into `check-ccl-skills.sh`), which normalizes sibling skill names and backticked routing references and blocks on any other divergence.

> **Sanitization boundary.** Vendor names (PostgreSQL, MySQL, Vitess, TiDB, CockroachDB, Aurora, Cloud Spanner, AlloyDB, Cloud SQL, DynamoDB, RDS Proxy, PgBouncer, ProxySQL, S3, Glacier, gp3, io2, etc.) below are illustrative; concrete topology choices, region names, cluster identifiers, and capacity numbers live only in the maintainer's private alias map. The sanitization audience list is positive (external / client / regulator / SOC / procurement / internal-compliance / sales-engineering / partner draft / forwardable-internal); sanitize before any document leaves the implementation team's approved audience.
>
> **Sanitization vs grep gate are separate concerns.** The mirrored-section grep gate at the end of this file's stack-glue forbids *stack-specific implementation syntax* in mirrored content; "zero hits" on the gate is not "safe to forward externally." The illustrative vendor / cloud-service / storage-tier names above are *intentionally* in mirrored content (an architect must reason about engine choice across stacks); they require **manual sanitization review** before this file or excerpts are forwarded to the audiences above. Maintain the vendor-name list above as the canonical set of names that require manual replacement before external publication.

## When this applies / does not apply

Apply when:
- the service owns a durable relational store (its own DB instance, schema, or shared cluster),
- the team owns operations of that store (per the business-team-owns-data-infra ownership model),
- the service or fleet faces a sharding, HA, replication, backup, or capacity decision that goes beyond schema design,
- the team is choosing between standard OLTP + manual sharding, sharding middleware, or a distributed SQL engine.

Skip when:
- the service uses a fully-managed external DB whose lifecycle is owned by the cloud provider (RDS Aurora / Cloud Spanner / DynamoDB), and the team is only choosing schema and queries — route to `data-modeling-and-migrations.md`,
- the service is stateless and only consumes data via the data platform owned by another team — route to that team's contract.

## DB engine choice axis

The choice is not "PostgreSQL or MySQL" — it is the position on this axis:

- **Single-instance OLTP** (PostgreSQL / MySQL on one node, with replicas). Familiar, broad ecosystem, low operational complexity. Sharding becomes a migration project once one instance maxes out.
- **Single-instance OLTP + sharding middleware** (Vitess in front of MySQL, ShardingSphere, application-layer sharding). Keeps the operational model of single-instance OLTP per shard while spreading load across shards. Adds middleware layer to operate; routing complexity moves into the proxy.
- **Distributed SQL engine** (TiDB, CockroachDB, YugabyteDB, Spanner-shape). Native horizontal scale, transactions across shards, native HA. Trades latency (Raft / Paxos quorum write path) and operational model (cluster of stateful nodes with consensus protocols) for transparent scale.
- **Cloud-managed equivalents** (Aurora, Cloud SQL, AlloyDB, DynamoDB, Spanner). The provider owns operations; the team owns schema, queries, and contract. Cost model differs; vendor-specific scaling and pricing characteristics matter.

Pick by:
- **Expected scale** — single-instance maxes out at the box's IOPS / connection ceiling; sharding middleware scales horizontally but each shard is still single-instance ops; distributed SQL scales nodes transparently but at consensus latency cost.
- **Transaction shape** — single-shard transactions are cheap on all engines; multi-shard transactions are expensive on middleware (two-phase commit, distributed coordinator), built-in on distributed SQL, impossible without an outbox/saga on per-shard apps.
- **Operational ownership** — single-instance is straightforward; sharding middleware adds a layer to monitor; distributed SQL needs in-house consensus-protocol experience or vendor support; managed cloud DB outsources ops.
- **Migration path** — choose so the next-tier migration is reachable from this one (start single-instance with a sharding-key contract so a future shard migration does not require schema rewrite).

Document the chosen engine, the next-tier migration trigger, and the operational footprint per cluster.

## HA topology

State the HA model explicitly per cluster:

- **Failover model** — single-primary + synchronous standby with automatic failover (most common); single-primary + async replicas (no automatic failover, RTO = manual promotion time); multi-primary (rare, conflict-resolution required); consensus-based (Raft / Paxos with N replicas, leader election internal to the engine).
- **Synchronous vs asynchronous replication** — sync gives RPO = 0 at the cost of write latency (every write waits for the standby to ack); async writes are faster but the standby lags. Mixed: sync to one standby (RPO = 0) + async to others (read scaling).
- **Failover trigger** — health check threshold, automatic promotion, split-brain protection (fencing of the demoted primary). Define the failover time budget; test it on a real schedule.
- **Quorum semantics** — for consensus engines, the write quorum (e.g., majority of N replicas). Loss of quorum = no writes. The minimum healthy replica count to remain writable is part of the topology contract.
- **Cross-AZ vs single-AZ** — single-AZ failover handles instance failure; cross-AZ handles AZ failure; cross-region handles region failure. Each tier costs more in latency.

Document the failover RTO and RPO targets per cluster, and the last date a failover was tested in production-like conditions (tested vs theoretical).

## Read scaling and replica routing

Once read load exceeds a single primary's capacity, read replicas spread the load:

- **Replica lag** — async replicas lag the primary by milliseconds to seconds; sync replicas lag by zero but slow writes. Define the maximum acceptable lag per use case.
- **Read-your-writes consistency** — a read replica may not yet show a write the same client just made. Either route those reads to the primary (the standard "session pinning" pattern), use a per-tenant or per-session replica with a lag budget, or accept eventual consistency on that path.
- **Replica routing** — at the application layer (the service chooses primary or replica per query), at the proxy layer (the proxy routes by SQL shape), or at the engine layer (the engine routes read-only transactions to replicas). The proxy / engine path is more transparent but moves correctness into infrastructure.
- **Staleness budget** — per query class, declare the maximum acceptable replica lag; monitor and alert when exceeded; fall back to primary when budget is breached.

Replica use is not free: failure modes include lagging replicas serving stale rows, replica connection-pool exhaustion, and replicas falling out of sync after primary failover (must re-attach).

## Sharding and resharding

When a single primary cannot handle write volume or storage, shard:

- **Shard key** — the column or hash that determines which shard a row lives on. Once committed it is hard to change. Choose carefully: tenant_id for SaaS; resource_id for partitioned workloads; time bucket for time-series; composite (tenant_id, year) for both.
- **Shard count and growth** — start with more shards than nodes (each node holds N shards), so adding nodes redistributes existing shards rather than re-keying. Shard count growth requires a re-shard migration.
- **Sharding model** — hash (uniform distribution, no range queries cross-shard), range (range queries cheap, hot range risk), lookup-table / directory (flexible, indirection layer to maintain), composite (tenant + sub-shard).
- **Cross-shard transactions** — expensive (two-phase commit or distributed coordinator) or impossible (no XA support). Design the domain so cross-shard transactions are rare; route those to outbox/saga workflows when needed.
- **Resharding path** — the upgrade from N shards to N+M, or from one engine to another. Define: new-shard provisioning, dual-write window, reconciliation, cutover, decommission. Resharding is a multi-week project; estimate it before starting.

## Cross-region replication

When the service serves users in multiple regions, or compliance requires data residency, replicate across regions:

- **Sync vs async cross-region** — sync gives RPO = 0 but adds inter-region RTT to every write (50–100 ms typical, business-critical or not). Async lets writes complete in the originating region; the secondary region lags.
- **Multi-region writes** — global tables (each region writes locally, conflict resolution per-row), per-region partitions (each tenant pinned to one region, no cross-region writes for that tenant), single-primary-with-read-replicas-elsewhere (writes only in the home region, reads anywhere).
- **Data residency** — when "tenant X's data stays in region Y" is a contractual obligation (see `multi-tenant-isolation.md`), the data plane is region-per-tenant or region-pinned by tenant.
- **Cross-region failure scope** — what happens when a region goes down? Define which clusters fail over to which, which tenants are affected, and the time budget for restore-to-secondary.

## Backup, restore, and tested recovery

Backup strategy is not the backup itself; it is the **tested ability to restore**:

- **Backup types** — full snapshots (consistent point-in-time, large), incremental snapshots (diff from last snapshot), WAL / binlog archive (continuous, supports PITR), logical exports (portable, slower restore).
- **Recovery objectives** — RPO (max data loss in seconds/minutes; depends on backup frequency and WAL archival), RTO (max time to restore; depends on backup size, restore mechanism, and tested practice).
- **Cross-region backup** — store backups in a different region than the primary so a region outage does not also lose the backups.
- **Encryption at rest in backups** — backups carry the same encryption boundary as the primary; key rotation includes backup re-encryption (or accept that old backups remain on old keys).
- **Tested recovery (the rule that distinguishes real from theatre)** — restore from backup on a schedule. Validate the restored state matches expected. Time the restore and compare to RTO. A backup that has never been restored is a backup of unknown quality. Date the last successful restore in the cluster contract.

## Cluster lifecycle

The cluster has a lifecycle as concrete as any service:

- **Provision** — declarative infra (Terraform / equivalent), parameter group, encryption-at-rest configuration, network placement, audit log destination, monitoring scrape config, identity / role setup. Provisioning is reproducible; one-off manual clusters are technical debt.
- **Scale up** — increasing instance class (vertical) without downtime requires planned maintenance windows on most engines; budget for it.
- **Scale out** — adding nodes (replicas, shards) requires re-balancing and may briefly affect write latency. Define the scale-out runbook.
- **Decommission** — taking a cluster out of service: drain traffic, verify zero writes/reads against it for an observation window, snapshot for retention, then destroy. Premature destroy after "looks idle" is a real outage class.
- **Cluster identity** — the cluster has a name, owner, lifecycle stage, and a connection contract documented; services that connect to it are listed.

## Capacity planning

A data cluster has multiple capacity dimensions, each can become the bottleneck:

- **Storage** — current usage, growth rate, headroom; alert at 70% / 80% / 90% with an explicit response. Storage growth past auto-extend limits is a hard outage.
- **IOPS / throughput** — provisioned (e.g., AWS gp3 / io2) or burst-limited; monitor utilization vs limit; right-size before the limit is hit.
- **Connection ceiling** — the engine's max connections; the proxy's connection pool size; the per-service pool. A connection storm at startup (every instance opens 100 connections) can exceed the ceiling instantly.
- **Query latency budget** — p50 / p95 / p99 latency; growth in p99 is a leading indicator before throughput saturates.
- **Replica lag headroom** — lag spikes during heavy writes are normal; sustained lag indicates the replica cannot keep up.

Each dimension has a documented limit, current usage, growth rate, and the action when the threshold trips. Capacity planning is monthly minimum, weekly during growth.

## Fleet-wide schema migration coordination

When the fleet has more than ~20 service DBs and migration tooling is per-DB, fleet-wide coordination becomes its own concern:

- **Migration registry** — a catalog of which service owns which DB, which schema version each is on, and which migrations are pending. Without this, a fleet-wide change (e.g., adding a tenant_id column for compliance) cannot be tracked.
- **Coordinated change rollout** — when the change spans services (a new column in shared semantics, a deprecation of a cross-service contract), define the order: which service migrates first, which dual-reads, when the old shape is retired.
- **Migration tool unification** — fleet-wide migrations work best when every service uses the same migration tool with the same conventions; mixed tooling makes fleet operations brittle.
- **Migration approval gate** — at fleet scale, migrations need pre-merge review (does it break replicas? does it lock tables? does it require downtime?). A "migration approval" workflow + checklist beats heroics.

## Connection pool and proxy topology

The path from app to DB has its own architecture:

- **Per-service pool** — each service instance holds its own connection pool. Simple, but fleet-wide connection count = (services × instances × pool_size). Watch the engine's max-connections ceiling.
- **Proxy layer** (PgBouncer, ProxySQL, Vitess gateway, RDS Proxy) — a proxy multiplexes many service connections into fewer DB connections. Reduces the connection count seen by the engine. Adds a hop (latency) and a layer to operate.
- **Transaction-mode vs session-mode pooling** — transaction-mode is denser (more service connections per DB connection) but breaks features that rely on session state (prepared statements, advisory locks, session variables). Session-mode preserves features at the cost of density.
- **Connection lifecycle** — the pool's idle timeout, max lifetime, and reconnect-on-error policy. A connection storm on app start (every instance opens 50 connections at once) is a common outage trigger.
- **Proxy HA** — the proxy must be HA-paired or per-AZ; a single proxy is a single point of failure for every service behind it.

## Cost and efficiency

Data layer cost grows with scale; explicit cost ownership prevents drift:

- **Right-sizing** — instance class, storage tier (provisioned IOPS vs gp3 vs gp2), backup retention. Over-provisioned clusters are real money.
- **Cold storage and archival** — old rows that are rarely read move to cheaper storage (S3 / Glacier / equivalent); the archival path must preserve tenant scope and support re-hydration (see `multi-tenant-isolation.md`).
- **Read-replica tax** — replicas cost as much as primaries; only run replicas that have a real reader.
- **Cross-region transfer** — egress and inter-region replication traffic costs add up; budget per cluster.

## Anti-patterns

Block these:

- **Sharding decided after a single-instance outage** — emergency sharding under load is a real outage class. Decide shard key and shard count before the migration is forced.
- **Backups that have never been restored** — backups of unknown quality; the first restore is during the incident. Schedule restore drills.
- **Failover that has never been tested in production-like conditions** — RTO is theoretical until proven. Test on a schedule with realistic load.
- **Cross-region sync writes used to hide application bugs** — using cross-region sync replication to mask consistency bugs in the app layer; the latency tax is permanent. Fix the bug.
- **Hot shard** — one shard absorbs the majority of writes (popular tenant, hot resource, time-bucket clustering). Audit shard key cardinality before launch.
- **Long-running transactions on primary** — analytical queries that hold long locks, blocking writes. Route analytical traffic to replicas or a separate warehouse.
- **Connection storm on app start** — every instance opens its full pool at boot, exceeding the engine ceiling. Stagger pool warmup or use a proxy.
- **Proxy as single point of failure** — one PgBouncer instance fronting the whole cluster. Pair or per-AZ.
- **Engine choice driven by hype, not by transaction shape** — picking distributed SQL for a 100-write/sec workload, or single-instance OLTP for a workload that needs distributed transactions. The transaction shape determines the engine, not vice versa.
- **Schema migration that locks the table on a hot path** — a migration that holds a strong lock for minutes; the service is effectively down. Use online-DDL tooling and review migration locking behavior pre-merge.
- **Backup retention shorter than the deletion / regulatory clock** — restoring a 30-day backup to recover yesterday's data only works if the backup is within retention. Coordinate backup retention with data-deletion SLAs (see `multi-tenant-isolation.md` per-store deletion modes).
- **Primary DB as cross-service queue** — using a service's primary OLTP table as the substrate for cross-service async messaging via polling. Adds queue load to the primary's connection pool and IOPS budget; couples the broker semantics to the DB's locking and transaction model; lacks fanout, replay, and lag visibility that a proper broker provides. Route durable cross-service async messaging to `event-driven-architecture.md` (broker + outbox poller); allow only low-volume same-service jobs with an explicit capacity budget against the primary.

## Operations checklist (data platform launch)

Each item is a verifiable action:

- Engine choice declared with the next-tier migration trigger (e.g., "single-instance until 50k QPS sustained; migrate to sharding middleware at that threshold").
- HA topology documented: failover model, sync/async configuration, quorum semantics, cross-AZ placement, failover RTO/RPO targets, last tested-failover date.
- Read-replica routing decision documented per query class with staleness budget and fallback-to-primary path.
- Sharding model declared (shard key, shard count, growth path) before the first shard is provisioned; not retrofitted.
- Cross-region replication mode declared per cluster (sync / async / multi-region / per-region partitioned); residency commitments enforced at the data plane.
- Backup strategy declared: type (snapshot / WAL / logical), frequency, retention, cross-region location, encryption-at-rest, RPO target.
- Restore drill scheduled on a documented cadence; last successful restore dated; restore time vs RTO target measured.
- Cluster lifecycle steps documented: provision (declarative IaC), scale up/out (runbook), decommission (drain + observe + snapshot + destroy); no one-off manual clusters.
- Capacity dimensions monitored (storage, IOPS, connections, latency p99, replica lag) with documented alert thresholds and response runbooks.
- Fleet-wide migration registry exists; per-service migration tool + version recorded; coordinated migrations have an order and approval gate.
- Connection pool sizes documented per service; proxy topology declared (per-service / proxy layer / mixed) with HA pairing where a proxy is used.
- Cost reviewed monthly; right-sizing reviewed quarterly; cold-storage / archival path tested.

## Python-specific implementation patterns

Stack-localized recipes; the sibling Go file localizes the same patterns differently.

- **DB driver and pool** — choose sync or async driver explicitly: `psycopg` (v3, supports both sync and async) or `psycopg2` (legacy sync) or `asyncpg` (async only) for PostgreSQL; for new MySQL async services prefer `asyncmy` and allow `aiomysql`; for MySQL sync prefer `mysqlclient` and allow `PyMySQL`. Do not replace an existing working `aiomysql` driver solely to comply with the default. ORM layer: SQLAlchemy 2.x (async with asyncpg / asyncmy / aiomysql; sync with psycopg / mysqlclient / PyMySQL); Django ORM for Django services; SQLModel when the service deliberately chooses SQLAlchemy + Pydantic or already uses SQLModel. Configure pool size explicitly (`pool_size`, `max_overflow`, `pool_recycle`, `pool_pre_ping`); do not rely on defaults.
- **Sync-vs-async-pool decision** — pick one model per service. An asyncio service that occasionally calls a sync DB driver via `to_thread` works but lose efficiency; a sync service spawning asyncio just for DB is over-engineered. The choice is part of `async-execution-model.md` and should be settled before this file is consulted.
- **Sharding middleware integration** — Vitess via MySQL wire protocol; the Python client (`asyncmy` / `aiomysql` / `mysqlclient` / `PyMySQL`) connects as if to MySQL. Sharding routing is at the gateway; the app's job is to include the shard key in every query.
- **Replica routing** — SQLAlchemy 2.x supports binds (`session.execute(stmt, bind=replica_engine)`) or separate engine instances per replica; route per query at the service layer. Session pinning for read-your-writes: keep a primary engine for the same async session after a write. The Python file's `data-modeling-and-migrations.md` `Read Replica And Routing Boundary` section names the binding mechanics in more detail.
- **Migration tooling** — Alembic for SQLAlchemy; Django migrations for Django ORM. Pick one and stick to it across the fleet for the migration registry to be useful. Alembic + asyncpg works (use the sync driver for Alembic, async for runtime).
- **Outbox poller integration** — the data-platform-architecture decisions (which engine, what HA, replica lag budget) feed into the outbox poller's behavior described in `event-driven-architecture.md` and `data-modeling-and-migrations.md` (Outbox And Dual-Write Consistency).
- **PgBouncer with Python** — `asyncpg` and `psycopg` both prepare statements by default, which can break PgBouncer transaction-mode pooling. Disable prepared statements at the connection level (`prepare_threshold=None` for psycopg; `statement_cache_size=0` for asyncpg) for transaction-mode pools. Session-mode pools work with all features. Choose mode per service's feature usage.
- **Vitess gateway** — looks like MySQL on the wire; the Python MySQL driver (e.g., `asyncmy`) connects normally. Transactions across shards require explicit 2PC or routing to a single shard.
- **Health checks for HA** — a FastAPI dependency or Django readiness view pings the DB; a failed ping → mark un-ready. Distinguish "primary unreachable" (fail) from "replica lagging" (degrade but still ready for non-critical reads).
- **Connection storm mitigation** — staggered pool warmup (sleep N × instance_index ms before opening connections at boot); `pool_pre_ping=True` to handle stale connections; exponential backoff on reconnect. For an asyncio service, use a single `AsyncEngine` per service instance and share via dependency injection — do not create per-request engines.
- **Test substitution** — define a repository protocol; provide a real-DB integration test using `testcontainers-python` for PostgreSQL / MySQL containers. SQLAlchemy's in-memory SQLite is convenient for unit tests but loses many semantics (transactions, locking, FK enforcement); use it cautiously and have integration tests on a real engine.

### Mirrored-section grep gate

The sibling-sync header forbids three categories of stack-specific token in mirrored sections (everything from "When this applies" through "Operations checklist"; everything *before* the `## Python-specific implementation patterns` H2). Run this grep against the mirrored region before every commit; zero hits required.

Forbidden tokens for this Python file's mirrored sections:

- **DB-engine syntax** — `SET LOCAL`, `set_config\(`, `current_setting\(`, `pg_try_advisory`, `pg_stat_activity`, `BYPASSRLS`, `FORCE ROW LEVEL SECURITY`, `search_path`, `GET_LOCK\(`.
- **Runtime / concurrency mechanic names** — `context\.Context`, `\bgoroutine\b`, `\bgoroutines\b`, `ctx\.Done`, `database/sql`, `\bsqlx\b`, `contextvars`, `\basyncio\b`, `run_in_executor`, `to_thread`, `ThreadPoolExecutor`, `ProcessPoolExecutor`, `copy_context`, `async with`, `after_commit`, `listens_for`, `asyncio\.Queue`, `asyncio\.Event`, `asyncio\.create_task`, `asyncio\.Task`.
- **Library / framework API names** — `GORM`, `Hertz`, `Kitex`, `golang-migrate`, `\bgoose\b`, `\bAtlas\b`, `pgx`, `lib/pq`, `go-sql-driver/mysql`, `SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`, `SetConnMaxIdleTime`, `PingContext`, `(^|[^[:alnum:]_])\*?sql\.DB\b`, `(^|[^[:alnum:]_])sql\.Tx\b`, `BeginTx`, `QueryContext`, `ExecContext`, `(^|[^[:alnum:]_])sql\.Rows\b`, `(^|[^[:alnum:]_])sql\.NullString\b`, `DB\.Stats`, `PrimaryDB\(`, `ReplicaDB\(`, `testcontainers-go`, `\btestcontainers\b`, `SQLAlchemy`, `FastAPI`, `Starlette`, `Pydantic`, `httpx`, `Alembic`, `asyncpg`, `psycopg`, `aiomysql`, `asyncmy`, `mysqlclient`, `PyMySQL`, `Django`, `databases`, `sqlmodel`, `tortoise`, `pool_pre_ping`.

Run:

```
awk '/^## Python-specific implementation patterns/{exit} 1' data-platform-architecture.md \
  | grep -nE '(SET LOCAL|set_config\(|current_setting\(|pg_try_advisory|pg_stat_activity|BYPASSRLS|FORCE ROW LEVEL SECURITY|search_path|GET_LOCK\(|context\.Context|\bgoroutine\b|\bgoroutines\b|ctx\.Done|database/sql|\bsqlx\b|contextvars|\basyncio\b|run_in_executor|to_thread|ThreadPoolExecutor|ProcessPoolExecutor|copy_context|async with|after_commit|listens_for|asyncio\.Queue|asyncio\.Event|asyncio\.create_task|asyncio\.Task|GORM|Hertz|Kitex|golang-migrate|\bgoose\b|\bAtlas\b|pgx|lib/pq|go-sql-driver/mysql|SetMaxOpenConns|SetMaxIdleConns|SetConnMaxLifetime|SetConnMaxIdleTime|PingContext|(^|[^[:alnum:]_])\*?sql\.DB\b|(^|[^[:alnum:]_])sql\.Tx\b|BeginTx|QueryContext|ExecContext|(^|[^[:alnum:]_])sql\.Rows\b|(^|[^[:alnum:]_])sql\.NullString\b|DB\.Stats|PrimaryDB\(|ReplicaDB\(|testcontainers-go|\btestcontainers\b|SQLAlchemy|FastAPI|Starlette|Pydantic|httpx|Alembic|asyncpg|psycopg|aiomysql|asyncmy|mysqlclient|PyMySQL|Django|databases|sqlmodel|tortoise|pool_pre_ping)'
```

Allowed exception: the *Sibling sync* header itself names the three category classes (without tokens) and references this gate; the *Sanitization boundary* header does not contain any of these tokens. Vendor names in mirrored sections that name a DB engine class (PostgreSQL / MySQL / Vitess / TiDB / CockroachDB / PgBouncer / ProxySQL) are allowed because they are engine choices an architect must reason about across stacks; the gate forbids stack-specific *implementation syntax*, not generic engine names.
