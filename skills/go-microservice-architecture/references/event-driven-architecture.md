# Event-Driven Architecture (Go)

Use when designing event-driven systems, async message contracts, producer/consumer ownership, transactional outbox/inbox, sagas, schema evolution, dead-letter and replay strategy, or end-to-end delivery guarantees for a Go service that publishes or consumes messages.

Scope split with the sibling `mq-consumer-architecture.md` (which covers consumer-side processing semantics, topic/group ownership, and consumer operations): this file owns the **broader event-driven architecture concerns** — delivery semantics taxonomy, producer-side patterns, transactional outbox, idempotency design, schema evolution, saga/choreography, fanout, replay, and end-to-end "exactly-once" illusion. Load both when designing a new event-driven boundary.

> **Conforms to the parallel-stack references pattern.** This file follows the layout documented in `skill-extraction-workflow/references/parallel-stack-references-pattern.md`: mirrored stack-agnostic core (when-applies through operations checklist), stack-specific implementation patterns section, and the embedded `### Mirrored-section grep gate` at the end of the stack-glue. The sibling `python-service-architecture/references/event-driven-architecture.md` mirrors the same structure. Either this file or `multi-tenant-isolation.md` may be used as a template for new parallel-stack extractions; multi-tenant additionally demonstrates the `## Topic-extension backlog` H2 for topic-wider-than-loop cases.

> **Sibling sync.** A parallel `python-service-architecture/references/event-driven-architecture.md` mirrors **all non-stack-specific sections** of this file (when-applies/not-applies, delivery semantics, event vs command vs query, idempotency, outbox, ordering, schema evolution, retry/DLQ/replay, backpressure, fanout, saga, end-to-end exactly-once, anti-patterns, operations checklist). Only the *Go-specific implementation patterns* section diverges by stack. Maintainers updating any mirrored section here must update the sibling in the same change to prevent drift. Tree-specific routing references are written inline for both trees so the mirrored bytes stay identical; cross-file parity is machine-checked by `skill-extraction-workflow/scripts/check-parallel-stack-parity.sh` (wired into `check-ccl-skills.sh`), which diffs the mirrored regions byte-for-byte (no normalization) and blocks on any divergence.

> **Sanitization boundary.** The named brokers (Kafka, Pulsar, RabbitMQ, NATS JetStream, Redis Streams) and libraries below are concrete examples for **internal** implementation guidance, scoped to the implementation team's approved audience. Before this file (or excerpts) is copied into any document leaving that audience — external / client-facing materials, customer-specific deliverables, regulator or auditor evidence packages, SOC / compliance reports, procurement responses, or partner architecture appendices — replace the named choices with generic categories (`the broker`, `a partitioned log`, `a confirm-mode AMQP queue`) unless the vendor selection is already approved for disclosure to that specific audience.

## When this applies / does not apply

Apply when the service:
- publishes durable events or commands to a broker (Kafka, Pulsar, RabbitMQ, NATS JetStream, Redis Streams, cloud-managed equivalents),
- consumes from a durable subscription (consumer group, durable subscriber, queue binding),
- needs cross-service atomicity between a DB write and a published message,
- needs a documented replay or backfill story for the event log.

Skip when the service:
- only does in-process pub-sub or fire-and-forget logging,
- uses synchronous HTTP/RPC with no durable async boundary (use `api-contract-and-schema.md` on the Python tree / `protobuf-contract-architecture.md` on the Go tree instead),
- uses a job queue purely for in-tenant background work where loss is acceptable (use `background-jobs-and-scheduling.md` or `batch-and-pipeline-architecture.md` on the Python tree / `notification-architecture.md` or `bulk-workflow-architecture.md` on the Go tree).

## Delivery semantics taxonomy

State the semantics of every event-driven boundary explicitly. Default to **at-least-once** unless the broker contract proves otherwise.

- **At-most-once** — broker may drop; consumer never sees duplicates. Never acceptable for source-of-truth state changes, money, audit, or non-idempotent external effects. **Is acceptable** for derived or rebuildable state changes (cache-invalidation hints, search-index refresh signals, sampled traces, approximate counters) when each of (a) the downstream state can be repaired by TTL / periodic rebuild / source-of-truth reconciliation, (b) the freshness SLA is documented, and (c) the repair path is itself instrumented and alerted. Otherwise telemetry-only.
- **At-least-once** — broker may redeliver; consumer must be idempotent. The default for durable brokers. Every consumer needs an idempotency key and dedup design.
- **"Exactly-once" illusion** — not a broker property; an *end-to-end* property assembled from (a) transactional or idempotent producer, (b) idempotent consumer with dedup storage, (c) atomic commit-and-publish (outbox + transactional message acknowledgement, or the broker's transactional-producer feature), and **(d) the side effect under the claim must be inside the same atomic domain** (DB + broker via transactional consumer, or a single DB transaction). External side effects — third-party API calls, S3 writes, secondary publishes to a different broker, sent emails — are *outside* the atomic domain and require their own provider-side idempotency keys, an outbox/process-manager step, or honest documentation as at-least-once. Do not claim end-to-end exactly-once for a flow whose externally visible side effect is not in the atomic domain.

Record the chosen semantics in the event contract; downstream consumers reason about retries and dedup against it.

## Event vs command vs query

The semantic shape determines ownership, schema, and retry posture:

- **Event** — a fact about something that happened. Past tense. Owned by the producer. Many consumers may subscribe. Schema evolves with backward-compatible additions; semantic meaning is fixed once published.
- **Command** — a request to do something. Imperative. Owned by the recipient's contract. Typically one consumer (a command handler). May fail validation and be rejected; the sender is told.
- **Query** — a request for state. Synchronous HTTP/RPC or query API, not a durable message. If you find yourself sending a query as a message, you probably want a query API plus an event subscription for change notifications.

Mixing these confuses ownership: a command consumer that drops the message because "it's an event, consumers are best-effort" is a bug; an event producer that retries indefinitely because "it's a command, must deliver" creates head-of-line blocking.

## Idempotency design

Every at-least-once consumer needs idempotency. Decide each axis explicitly:

- **Idempotency key source** — event id from the producer, natural resource key (`order_id` + `state_transition`), or a derived hash. The producer-generated event id is preferred because it survives intermediate retries and is stable across consumer redeploys.
- **Dedup window** — how long the consumer remembers seen keys. Shorter window = cheaper storage, larger duplicate risk if a slow retry arrives after window expiry. The window must exceed the broker's maximum redelivery interval and any expected outage/replay window.
- **Dedup storage** — tier by impact:
  - *Lossy / rebuildable effects* (the same effects allowed under at-most-once above): Redis `SET NX EX` with TTL ≥ window is sufficient. Loss of a dedup key just causes one duplicate side effect, repaired by the same path that handles at-most-once loss.
  - *Source-of-truth state changes, money, audit, regulated, or non-idempotent external effects*: the **authority** is a durable DB row keyed by `event_id` (or natural key). Redis may sit in front, but only as a *negative cache* (a miss does not skip the durable check) or as an *optimization cache for keys known to have been populated only after the durable commit succeeded* (write order: durable insert → commit → cache set; never cache before commit). A positive Redis hit cannot bypass the durable check unless the writer guarantees the cache entry only appears post-commit. If Redis is used at all on this path, configure `maxmemory-policy noeviction`, enable persistence with replication, monitor eviction/replication-lag counters, and alert on loss.
  - Never use Redis as the only dedup for state changes by default.
- **Side-effect ordering** — there are two side-effect classes; treat them separately:
  - *DB-local effects*: write the dedup record in the same DB transaction as the side effect. A consumer that performs the side effect, then writes the dedup record, can lose the dedup on crash and re-process on redelivery.
  - *Cross-system effects (external API call, broker publish to another topic, S3/object-store write, email send)*: the DB transaction cannot include these. Use the **intent-then-execute** pattern: write a durable intent row + dedup key in one DB tx, mark `pending`; the executor (an outbox poller or process manager) calls the external system using a provider-supplied idempotency key; on success it updates the row to `done`. The dedup record and the terminal status are separate columns. The crash window — executor calls the external system, the call succeeds, the executor dies before updating `done` — is the dangerous case: on restart the row is still `pending` and a naive retry duplicates the effect. Handle it explicitly: add an `unknown` / `reconcile` state and require **the external system to support either (a) idempotency-key replay that returns the same outcome for the same key, or (b) status lookup by the idempotency key**. If the external system supports neither, this pattern is not safe; document the boundary as at-least-once with manual reconciliation, alert on rows stuck in `pending` past a deadline, and run a separate reconciliation job. A redelivery sees `pending` / `unknown` / `done` and either looks up status, runs the call with the idempotent key, or skips. Treat any flow that needs cross-system atomicity as a process-manager workflow (see *Saga / process manager* below), not as inline consumer code.

## Transactional outbox / inbox

The outbox pattern makes "write to DB and publish event" atomic without distributed transactions across DB and broker:

- Producer writes the event to an `outbox` table in the **same DB transaction** as the state change.
- A separate poller (a long-running worker in the same service, or a separate worker process) reads the outbox in order, publishes to the broker, and marks the row sent. The poller is at-least-once: idempotent re-publishing is fine because consumers dedup. The stack-glue section names the specific runtime primitive used to host the poller.
- Use a monotonic `outbox_id` for ordering within a partition key; publish in `outbox_id` order **per key** (not globally).
- Poller failure modes: crash mid-publish, broker unavailable, slow broker. Each must leave the outbox in a recoverable state.
- The "never post-commit publish" rule applies to **durable cross-process events**. An after-commit hook or post-commit callback (the ORM's transaction-commit event) that publishes to a remote broker silently drops the event on a crash between commit and publish. *Exception*: in-process, same-instance post-commit notifications that are intentionally best-effort and rebuildable (local cache invalidation, in-process projection refresh, an in-process signal to other workers in the same process) need no outbox, because there is no durable consumer claim — but only when no remote consumer exists on that channel.

### SKIP LOCKED and per-key ordering

`SELECT … FOR UPDATE SKIP LOCKED` lets multiple poller replicas run safely **only when outbox rows are independent or ordering is not required**. `SKIP LOCKED` is *defined* to let later rows overtake a locked earlier row; if poller A locks `outbox_id=100` for key `K` and stalls on broker publish, poller B will skip 100, lock 101 for key `K`, and publish 101 first — consumers see `K`'s events out of order. To preserve per-key ordering across HA pollers, choose one strategy, **and implement the prerequisites that go with it**; the strategies are not safe on their own:

- *Single active publisher per key/partition* — route by `hash(partition_key) MOD N == poller_index` (NOT by `outbox_id`; `outbox_id` is monotonic and would split a key's rows across publishers). Each row's serializer is the publisher that owns its partition key. **Prerequisites:** stable ownership epoch (each publisher knows its index and the current N), drain on rebalance (when N changes, old owners must finish in-flight publishes before new owners take the key), and a fenced epoch token in the publish path so a stale owner cannot publish after its index has been reassigned.
- *Per-key advisory lease* — acquire a short-TTL DB lock or row-lock on the partition key before publishing; release on success or on stall. **Prerequisites:** bounded lease TTL with explicit renewal, fencing token written with the publish so a stuck holder cannot resume after its lease expired, and stale-lock recovery (a stuck holder's lease must expire and another poller must take over without duplicate publish — duplicate publish is acceptable because the consumer dedups, but lock leak that blocks the key forever is not). The DB-specific advisory-lock primitive lives in the stack-glue section below; engines differ in lock lifetime and transaction scope.
- *Dispatcher that refuses to publish `id=N+1` while `id=N` for the same key is unsent* — query `MIN(outbox_id) WHERE key=K AND sent_at IS NULL` and refuse newer ids until that row's `sent_at` is set. **Prerequisites:** an `abandoned` status that the row can move into after K publish failures (otherwise a poisoned unsent row blocks the key forever), an alert on abandonment, and an explicit policy for cross-key dependencies (workflow steps that span keys K1 and K2 can deadlock if K1's next row waits on K2 and vice versa; the dispatcher must not couple keys' progress).

Without one of these (and its prerequisites), `SKIP LOCKED` and per-key ordering are mutually exclusive — pick which property the outbox actually delivers and document it on the event contract.

Inbox (the dual) is rarer: when a consumer must read a message and produce a side effect in a different system atomically, the consumer writes the inbox record + side effect in one DB tx, then acks the broker. On crash before ack, redelivery hits the inbox row and skips the side effect.

## Delivery ordering

Most brokers guarantee per-partition or per-key ordering, not global ordering. Design accordingly:

- **Partition key** — choose a key that aligns with the consistency boundary (per-resource, per-tenant). All events for the same boundary land on the same partition and are processed in order.
- **Hot partition risk** — a key with high cardinality at the head of the distribution (one tenant's traffic, one popular resource) creates a hot partition that blocks the consumer group. Audit key cardinality before launch.
  - *If the ordering boundary can be sharded* (the key is finer than the consistency boundary needs), shard the known hot keys (sub-key suffix, time-windowed re-keying, dedicated topic for the hot tenant).
  - *If the ordering boundary cannot be sharded* (regulated per-tenant audit log, per-resource state machine that must remain serializable), do not shard — sharding destroys the invariant. Mitigate with tenant isolation (dedicated partition or topic for the hot tenant), admission control (per-tenant rate limit at the producer), batching, or a serializing writer; alert on partition-skew metrics so the operator knows when to allocate dedicated capacity.
  - *Throughput ceiling escape hatch* — these mitigations move or throttle the bottleneck; they do not make a non-shardable serial invariant scale beyond a single serializer's physical throughput. If the required write rate genuinely exceeds one serial lane's capacity, no broker tuning fixes it: redesign the invariant (does it really need total ordering, or just per-sub-key ordering?), split the domain (multiple smaller consistency boundaries), pre-aggregate at the producer (one summary event per N), use a stronger consistency model (a write-ordered log service), or reject the SLA. Do not let a fictional broker mitigation hide an unscalable invariant.
- **Cross-partition ordering** — does not exist for free. If a consumer needs to see events from two different keys in a specific order, that ordering must be encoded in the events (causal links, vector clocks, or a serializing component) or relaxed.
- **Scaling and repartition** — broker-specific; document the broker's mechanics on the event contract. Kafka-like partitioned logs are expensive to repartition (changes hash placement and ordering); pre-plan partition count for expected growth. Pulsar topics scale via partition addition with key-shared subscription semantics; NATS JetStream streams reshape via mirroring; RabbitMQ queues and Redis Streams have no partition concept — scale via sharded queues/streams managed by the application. The "plan for years" rule is Kafka-specific; do not apply it to NATS / RabbitMQ / Redis Streams without mapping to their actual scaling story.

## Schema evolution

Events outlive the producer's current code. Schema discipline is non-negotiable:

- **Compatibility mode** — choose `backward` (new producers, old consumers), `forward` (old producers, new consumers), or `full` (both). For multi-team async fanout, full compatibility is the default; pick the others only with explicit consumer coordination.
- **Additive by default** — new fields are optional with safe defaults; do not remove a field or repurpose its meaning **on the existing version**. Deprecate by creating a new event type or version and migrating consumers.
- **Security / compliance exception** — when continuing to emit a field is itself the problem (leaky PII field, secret accidentally embedded, regulator-mandated retraction), additive-only is overruled. The path is: create a new event version that omits the field, inventory active consumers, deploy a coordinated emergency migration plan (consumer flips first, producer flips second, old version retired), and define historical-data handling (purge, redaction in archives, controlled access). Document the security trigger; this path is not the default deprecation flow.
- **Rolling deprecation (the default)** — create a new event type or version, dual-publish or dual-read across a compatibility window, migrate consumers with monitoring and a rollback path, then retire the old version after explicit approval. Do not stop-the-world.
- **Schema discovery model** — choose by audience:
  - *Single-team, single-broker boundary*: in-payload schema or a model-derived schema (from the service's typed model layer) in the envelope header is acceptable.
  - *Multi-team, single-broker fanout*: a schema registry (Confluent-style or self-hosted) validates compatibility at build/deploy time.
  - *Multi-broker, multi-tenant, or external consumers* (webhooks, partner integrations, tenant-private contracts): hybrid — versioned envelope (`event_type`, `event_version`) in payload + per-tenant contract catalog/registry where available + signed schema references for external consumers + broker-specific validation gates. Neither a single registry nor in-payload alone is sufficient.
- **Metadata leakage in cross-trust boundaries** — for external or multi-tenant contracts, the schema discovery layer itself can leak. `event_type` strings, version names, registry paths, enum labels, and catalog visibility can reveal unreleased products, regulated workflows, internal team structure, or tenant-specific capabilities even when payload fields are field-level protected. Before publishing to an external boundary: classify each of (`event_type`, `event_version`, schema-reference path, registry namespace, enum values, error codes, catalog listings) by audience; use opaque public aliases (`event_type=ext.<opaque-name>`, namespace-by-tenant-without-tenant-name) where the internal name is sensitive; never let an internal event type cross the boundary as-is.
- **Breaking change discipline** — a semantic-level breaking change (a field's meaning changes, an enum value is repurposed) is not caught by schema compatibility checks. Document semantic changes; coordinate consumer rollout before publishing the new shape.

For event payloads modelled with the service's typed-model layer, freeze the model at publish time and version the envelope; the producer's evolving model must not reach the wire without a registered new version. The stack-glue section names the specific model library and freezing pattern.

## Retry, dead-letter, replay

Distinguish three failure dispositions explicitly:

- **Retryable** — transient (dependency 5xx, timeout, lock contention). Bounded retries with exponential backoff + jitter, capped attempt count, retry budget.
- **Permanent drop / dead-letter** — malformed payload, unknown event type, expired delivery, domain conflict that will not resolve on retry. Send to DLQ with the original payload + failure metadata; alert. Do not silently ack.
- **Poison** — a message that consistently fails after retries. Quarantine to DLQ; alert with the consumer + payload class. Replay decision is manual.

**Retry budget scope must match the constrained resource:**
- *Isolated handler* (the failure costs only this consumer): per-consumer retry budget.
- *Shared downstream* (multiple consumers call the same payment provider, LLM vendor, third-party API, regulated quota): global or per-provider or per-tenant budget. Three consumers each independently burning their per-consumer budget against the same downstream produces a retry storm at the provider; the budget belongs to the constrained resource, not to the consumer.

**Replay tooling is part of the architecture, not a runbook detail.** Every event-driven boundary needs a documented replay path: read from DLQ or from a checkpointed offset, transform if needed (e.g., bump version), republish or invoke the consumer directly. Without replay, DLQ becomes a graveyard and outages produce permanent data loss.

**Replay fixtures must be representative by event class.** A synthetic poison message exercises parser failures fine, but is insufficient for:
- *Signed callbacks* (vendor webhooks with signature + timestamp + raw-body validation): keep captured sanitized raw-body + signature fixtures, or use the provider's test fixtures.
- *PII or regulated payloads*: privacy-approved fixtures only; the replay tool must accept them without round-tripping through unsanitized logs.
- *Schema-validated payloads*: fixtures must pass the same registry validation as production messages, or the replay tool will diverge from production semantics.
- *Stateful sequences* (create/update/delete chains, reserve/release pairs, workflow timeout sequences, multi-event sagas): fixtures must include the ordered sequence, plus the duplicate, missing-predecessor, out-of-order, and replay-after-terminal-state cases. A single in-sequence event replayed in isolation can pass the consumer while the real production failure is a sequence-level invariant violation.

Document which fixture class is used and which classes are deliberately not covered.

## Backpressure

Consumer lag, broker queue depth, and producer rate are the three backpressure signals. Wire them:

- **Consumer-side** — bound the work-in-flight, but **the shape depends on ordering**:
  - *Unordered consumer*: a bounded work-queue sized to the worker pool, N workers reading from the queue. A shared shutdown signal stops the workers (the stack-glue section names the specific primitive). Order of completion is undefined.
  - *Ordered partitioned log* (Kafka, Pulsar key-shared, NATS JetStream ordered consumer): **one serial work lane per assigned partition/key**. Feed each partition into its own bounded work-queue + single worker, or process messages serially within the partition's poll loop. Feeding multiple ordered partitions into a single shared work-queue + worker pool loses per-partition ordering, and a slow message on one partition can starve cold partitions or let later offsets overtake earlier ones. The bounded-queue-plus-pool shape is correct for unordered work queues; not for ordered partitioned logs.
  - *Rebalance handling for partition-assigned consumers* — when a Kafka / Pulsar key-shared / similar consumer group rebalances and a partition is revoked, "one lane per partition" is unsafe without explicit rebalance discipline. The revoked owner must (1) stop fetching from the partition immediately, (2) drain or cancel its in-flight lane (await handler completion to a bounded deadline, or cancel with an explicit `partial-failure` disposition), (3) commit or abort offsets according to the handler outcome (commit only completed offsets; do not commit `last poll` blindly), and (4) be fenced so it cannot still publish a side effect after the new owner has started — typically by tagging each in-flight message with the assignment epoch and refusing side effects whose epoch is stale. Without fencing, the new owner and the old owner can process the same business key concurrently; per-partition ordering at steady state is meaningless if the rebalance window allows concurrent processing.
  - Avoid unbounded worker-per-message fanout in all cases (the stack-glue section names the specific anti-pattern API).
- **Producer-side** — when the broker buffer fills (Kafka producer queue, RabbitMQ unconfirmed-publishes limit, NATS slow-consumer warning), block the producer's caller with a bounded wait or shed load at the producer entry point. Never block forever; surface a typed error after a bounded wait so upstream can backpressure further.
- **Cross-service** — a slow consumer is an upstream producer's problem to know about. Consumer lag must be exposed as a metric and alerted; producers cannot fix what they cannot see.

## Fanout patterns

- **Pub-sub** — one publish, many independent subscribers. Each subscriber owns its own consumer group/durable subscription, processes at its own pace, has its own DLQ. Add a subscriber by deploying it; no producer change.
- **Work queue** — one publish, exactly one of N workers handles it. All workers share a consumer group. Add capacity by adding workers in the same group.
- **CDC (change-data-capture)** — the DB is the source of truth; a CDC connector (Debezium-style) produces events from the WAL/binlog. Useful when many downstream consumers need to react to a DB-owned domain and the writing service does not own a transactional outbox.
- **Producer-held subscriber list** — generally an anti-pattern (couples producer to consumers; defeats the point of pub-sub). *Legitimate exceptions*: CDC bridges and webhook dispatchers do interact with external targets (a CDC sink config, a per-tenant webhook URL list). The ownership rule for those external lists: the **authoritative list lives in the owning configuration / control-plane system** (the tenant-config service, the connector-config service, the customer-admin app — whichever owns target lifecycle, approval, rotation, and audit). The producer or dispatcher reads a snapshot from that system; it does not own the list unless it *is* the authoritative config owner. Hardcoded subscriber lists in producer code, or producer-owned lists that bypass the tenant-config policy plane, are still the anti-pattern.

## Saga / process manager vs choreography

For multi-step workflows that span services:

- **Choreography** — each service listens for events and emits its own. No central coordinator. Loose coupling; the workflow exists only as the set of subscriptions. Hard to reason about end-to-end; debugging requires tracing across services.
- **Orchestration (process manager / saga)** — a coordinator service drives the workflow: emits commands, listens for responses, compensates on failure. The workflow is explicit in one place.

**Orchestration is required by workflow invariants, not by step count.** Use orchestration when any of these is true, regardless of whether the workflow has two steps or twenty:
- Compensation across services is needed (one step's failure requires undoing another step's effect).
- Audit needs **a single controllable workflow state or a resume/decision point** — not just append-only traceability. Append-only audit (every step emits an immutable audit event tagged with a workflow id) can be served by choreography; a single state view that an operator must inspect or resume requires orchestration.
- An external irreversible effect is involved (see below).
- Timeout handling needs a coordinator with a clock.
- A single business owner needs one place to inspect or resume stuck state.

Choreography is acceptable when none of those hold and the workflow is small and fixed. It is also acceptable for **broadcast fanout** (one event, many independent subscribers, no compensation across subscribers) even when auditability is required — each subscriber owns its own DLQ, immutable audit events carry the shared workflow / trace id, and there is no central state to inspect; the audit story is "did every subscriber see and process this," answered by traces and per-subscriber metrics.

**Compensation, where possible; prevention, where not.** Distributed transactions are not available; design compensation as the default:
- *Compensable steps* — idempotent compensating action (refund, cancel, undo) that is itself at-least-once and idempotent. Document the compensation per step.
- *Irreversible steps* — sent email, filed regulatory report, shipped physical item, called external action with no reversal API. No real compensation exists; at best there is a corrective follow-up (apology email, retraction filing, refund + recovery offer) which is a separate workflow. For these:
  - Add prevention gates before the irreversible step (validation, manual review, approval, dual-confirm, dry-run).
  - Use `pending` / `confirmed` / `committed` state machine so the orchestrator can fail-stop before the irreversible action.
  - Define explicit irreversible-state handling: how the workflow records the irreversible commit, what the corrective workflow looks like, who is paged.
  - Do not design a fictional compensation that "reverses" an irreversible action; document the reality.

If the workflow involves money, audit, or a regulatory requirement, default to orchestration with an explicit state machine.

## End-to-end "exactly-once" illusion

Stack-agnostic recipe; document each clause for every event-driven boundary that claims it:

1. Transactional or outbox-based publish — the message is durable iff the originating state change is durable, atomically.
2. Idempotent consumer with dedup storage that survives consumer restart and broker redelivery.
3. Commit-and-publish ordering — consumer's side effect + dedup record + offset commit are atomic from the consumer's point of view (DB transaction including offset, or broker transactional consumer + producer pairing). Brokers without a transactional offset semantic (NATS JetStream's per-ack model, RabbitMQ classic queues without publisher confirms + tx) cannot satisfy this clause; document the gap.
4. **Side effect under the claim is inside the atomic domain.** "Atomic domain" means the DB transaction that includes the offset commit, or the broker transactional producer/consumer pair. External side effects — third-party API calls, S3/object-store writes, secondary publishes to a different broker, sent emails, SMS, payments — are *outside* the atomic domain. For them you need provider-side idempotency keys, an outbox/process-manager step that records terminal status, or honest documentation as at-least-once. Claiming exactly-once for a flow whose externally visible effect is not in the atomic domain is the most common false claim.
5. Replay path respects idempotency — a manual replay of a DLQ message lands on the consumer's existing dedup and does not double-apply.

If any clause is missing, the boundary is at-least-once with duplicates. Tell consumers honestly.

External grounding (adopted in part): this recipe is an instance of the end-to-end argument — [Saltzer, Reed & Clark, *End-to-End Arguments in System Design*, ACM TOCS 2(4), 1984](https://web.mit.edu/Saltzer/www/publications/endtoend/endtoend.pdf) — a function that "can completely and correctly be implemented only with the knowledge and help of the application standing at the endpoints of the communication system" cannot be delegated to the communication layer, and broker-level transactional features are that paper's "incomplete version … useful as a performance enhancement", never the end-to-end guarantee. Borrowed scope: the placement argument only; the five-clause recipe and the atomic-domain boundary are this skill's own operational criteria.

## Anti-patterns

- **Post-commit publish (durable cross-process)** — publishing the event after the DB transaction commits, without an outbox, when consumers are in another process. A crash between commit and publish silently drops the event. In-process, same-instance, rebuildable post-commit hooks are not this anti-pattern.
- **DB-as-queue** — using a DB table as the message broker via polling without an outbox-style design. Fine for low-volume single-instance background jobs in the same service; breaks under load, lacks fanout, and entangles application reads with queue mechanics when used as a cross-service broker.
- **No idempotency key** — consumer relies on broker's "exactly-once" claim or on hope. Every redelivery becomes a duplicate side effect.
- **Naive retry without dedup** — retry on the producer (republishing the same logical event) without the consumer recognising it as a duplicate. Doubles the side effect.
- **Hot partition / hot key** — one key concentrates traffic, blocking the consumer group. Symptom: consumer lag concentrated on a single partition.
- **Schema drift without registry or envelope** — producer adds a field without coordinating; an older consumer crashes on unknown required field.
- **DLQ as graveyard** — messages land in DLQ, nobody looks, no replay tooling. The DLQ becomes a silent data-loss channel.
- **Exactly-once claimed by broker badge** — broker config has an "exactly-once" mode, but the consumer is not idempotent and the producer is not transactional, OR the side effect is outside the atomic domain. The claim is wrong; record correct end-to-end semantics.
- **Producer-held subscriber list as code** — subscriber list hardcoded at the producer when broker-side subscription is possible. (CDC bridges and webhook dispatchers are exceptions; their lists must live as config with audit and rotation.)
- **Sync HTTP/RPC as command** — a "command" sent via blocking HTTP/RPC with retry and no replay path. If the call needs the durability of a queue, use a queue; if it needs the latency of HTTP/RPC, accept best-effort.

## Operations checklist (event-driven boundary launch)

Before a new event-driven boundary goes live:

- Delivery semantics declared explicitly in the event contract, including which side effects are inside the atomic domain and which require provider idempotency keys.
- Idempotency key, dedup storage tier (lossy/Redis vs source-of-truth/durable), and dedup window documented per consumer; Redis-as-authority disallowed for source-of-truth flows.
- Outbox table + poller in place when atomic publish is required; per-key ordering strategy declared if ordering is part of the contract; no post-commit cross-process publish without outbox.
- Partition key + estimated cardinality; hot-partition mitigation declared (shard if the ordering boundary allows; tenant-isolation/quota/dedicated partition if it does not); broker-specific scaling/repartition path documented.
- Schema compatibility mode declared; schema registered or versioned envelope in payload; multi-broker / multi-tenant / external boundaries documented with the hybrid model; rolling deprecation plan in place for known breaking changes; security/compliance retraction path documented.
- Retry policy (max attempts, base delay, jitter, retry budget) declared per consumer; retry budget scope (per-consumer vs per-provider vs per-tenant) matches the constrained resource.
- DLQ topic + replay tool documented; replay tested with **representative fixtures** for each event class on this boundary (synthetic for parser; raw-body+signature for signed callbacks; privacy-approved for PII flows).
- Consumer lag metric exposed; SLO and alert threshold defined; per-partition lag visible for ordered partitions.
- Backpressure path: bounded work-in-flight in the right shape (per-partition lane for ordered logs; shared pool only for unordered queues); producer behaviour when broker is slow or full is documented and observable.
- End-to-end exactly-once claim, if made, validated against the five-clause recipe above — including the atomic-domain clause — otherwise the boundary is documented as at-least-once.
- Workflow that involves money, audit, regulatory, or external irreversible effects uses orchestration with explicit `pending`/`confirmed`/`committed` state machine and named prevention gates; no fictional compensation for irreversible steps.

## Go-specific implementation patterns

These are stack-localized recipes that implement the stack-agnostic patterns above; the sibling Python file localizes the same patterns differently.

- **Library choice axis** — pick by feature, not popularity. For Kafka in Go: a high-level client (e.g., `segmentio/kafka-go` or `confluent-kafka-go`) for ergonomic ops; a lower-level client when you need precise offset/transaction control. For Pulsar/NATS/RabbitMQ: the vendor's Go client. Standardize within the service; multi-broker services need an abstraction that does not hide delivery semantics.
- **Consumer goroutine shape** — depends on ordering (see *Backpressure* above):
  - *Unordered work queue*: one puller goroutine into a buffered channel; a worker pool of N goroutines reads from the channel.
  - *Ordered partitioned log*: one goroutine per assigned partition that processes serially, or a per-partition bounded channel with a single worker. Use `ctx.Done()` for shutdown; never feed multiple ordered partitions into a shared worker pool.
- **Context propagation** — extract correlation id, trace context, lane/env from the message headers into `context.Context` at the consumer boundary. Use the existing service helper for ctx-clone-without-cancel when spawning workers; do not let a single message's cancellation cancel the whole consumer.
- **Outbox poller with GORM/sqlx** — a goroutine in the same service that runs a **claim → commit → publish → mark-sent** loop, not "publish inside the DB tx" (a broker call inside `BEGIN…COMMIT` holds the tx open for the broker round-trip and violates the short-transaction rule in `data-modeling-and-migrations.md`):
  1. **Claim tx (short)**: `BEGIN; SELECT … FROM outbox WHERE sent_at IS NULL AND (processing_until IS NULL OR processing_until < NOW()) ORDER BY id LIMIT N FOR UPDATE SKIP LOCKED; UPDATE outbox SET processing_until = NOW() + lease, owner = $owner WHERE id IN (…); COMMIT;` — the row is now leased to this poller; tx closes immediately.
  2. **Publish (outside any tx)**: call the broker for each leased row. Duplicate publish on retry is acceptable because the consumer dedups.
  3. **Mark-sent tx (short)**: `BEGIN; UPDATE outbox SET sent_at = NOW(), processing_until = NULL WHERE id = $id AND owner = $owner; COMMIT;` — guarded by `owner` so a re-leased row (after the original lease expired) is not double-marked.
  4. **Abandon tx**: after K publish failures, mark row `abandoned` and alert; do not block the partition key forever on a poison row (see the *Dispatcher that refuses to publish `id=N+1`* strategy).
  For per-key ordering across HA pollers, layer one of the strategies in *SKIP LOCKED and per-key ordering* (hash-routed publisher by `hash(partition_key) MOD N`, per-key advisory lease via the DB's advisory-lock primitive — PostgreSQL `pg_try_advisory_xact_lock(hashtext(partition_key))` for tx-scoped locks bound to the connection's current transaction; MySQL `GET_LOCK(name, timeout)` with explicit session-scoped semantics (release explicitly on success or stall, or rely on session close), and lock names server-wide-scoped so use a fully-bounded namespaced name `lk:<env8>:<svc8>:<purpose8>:<hash16>` (total length = 46 chars including separators, fits inside MySQL's 64-char limit; `<env8>`, `<svc8>`, `<purpose8>` are generated from the canonical environment / service / purpose identities by a **documented deterministic function** (e.g., first-8-of-base32(SHA256(canonical_identity))) or allocated from a **collision-checked registry** — human-readable abbreviations are NOT acceptable unless the registry proves uniqueness in the MySQL server-wide lock namespace; `<hash16>` is the first 16 chars of base32(SHA256(length-prefixed-encoding(canonical_partition_key, versioned_namespace))) — e.g., `SHA256(len(pk) + ':' + pk + len(ns) + ':' + ns)` or canonical JSON/CBOR over `[canonical_partition_key, versioned_namespace]`; raw `pk + ':' + ns` concatenation is **not** acceptable because real partition keys (`acme:prod`, `order:123`, user-supplied ids) can contain `:` and the resulting hash input is not injective. **Namespace-migration safety**: changing `versioned_namespace` requires either a drain / stop-the-world for the poller lane, or a dual-lock period (acquire old + new lock names in canonical order) so that mixed namespace versions across a rolling deploy / rollback cannot acquire different locks for the same partition key and publish concurrently. Without this, a version bump silently splits the per-key serialization lane.), and avoid MySQL NDB / multi-mysqld setups where `GET_LOCK` is not cluster-wide; TiDB supports MySQL-style user-level locks (`GET_LOCK`) cluster-wide in supported versions — verify timeout / deadlock semantics for the deployed TiDB version against a scenario-specific compatibility source: **pinned cluster** → checked-in version pin; **managed channel (TiDB Cloud)** → provider channel/SLA *and* current cluster version (channel alone is insufficient — the version still varies inside the channel); **rolling-upgrade fleet** → min/max active versions across the fleet plus the documented rolling-upgrade policy; **ad-hoc verification** → recorded `tidb_version()` output that includes cluster identity and timestamp. Otherwise fall back to an external coordinator (etcd lease, Redis `SET NX` with TTL) with fencing — with bounded TTL and a fencing token written with each publish; or refuse-newer-id dispatcher with abandoned-row state).
- **Event payload freezing** — the typed-model layer for Go event payloads is protobuf: freezing means serializing the payload to immutable bytes (marshal, or deep-copy then marshal) at the enqueue/publish boundary and binding those bytes to the envelope (`event_type`, `event_version`) — pinning the generated artifact version fixes the schema, not the instance: a queued mutable message object mutated before serialization changes the wire payload despite the pinned schema. See `protobuf-contract-architecture.md` for `message`/`enum`/`oneof` evolution rules.
- **Idempotency storage** — pick by impact (see *Idempotency design*):
  - Lossy/rebuildable: Redis `SET dedup:<key> 1 EX <window> NX`, branch on success/skip.
  - Source-of-truth: insert into a `processed_events` table with `event_id` as primary key inside the side-effect transaction; on duplicate-key error, skip. Optionally cache the recent N keys in Redis as a hot-path filter, but Redis is not the authority.
  - Cross-system effects: intent-then-execute pattern — write `processed_events` row with status `pending` in DB tx, run the external call with a provider idempotency key, update status to `done` on success.
- **Retry policy** — bounded `exponential backoff with jitter`; never retry inside the message handler with an inline `time.Sleep` past tens of seconds — let the broker redeliver after nack, or push to a delay queue/scheduled topic. Scope the retry budget to the actual constrained resource: per-consumer for isolated handlers, **per-provider / per-tenant / per-region / per-API-method / global** for shared downstreams (the budget belongs to whichever resource has the hard quota; "per-provider" alone is insufficient when the real limit is per-region or per-method).
- **Error classification** — wrap errors with `fmt.Errorf("…: %w", err)`; classify via `errors.Is`/`errors.As` at the boundary into `retry` / `drop` / `dlq` dispositions; never return a bare `error` and let the dispatcher guess.
- **Test substitution** — define a `Broker` interface at the service boundary; provide an in-memory implementation for unit tests and an integration test that hits a real broker (Kafka container, RabbitMQ container). Mocking the broker client directly leaks library specifics into tests.
- **Graceful shutdown order** — signal handler → cancel root context → puller stops fetching → workers drain (bounded by `ShutdownGracePeriod`) → outbox poller finishes its in-flight publish → broker client closes → DB connection closes. If the last outbox publish needs an in-flight DB read, hold DB open until the outbox poller acknowledges drain; the rule is "no new work in flight," not "rigid component order."

### Mirrored-section grep gate

The sibling-sync header forbids three categories of stack-specific token in mirrored sections (everything from "When this applies" through "Operations checklist"; everything *before* the `## Go-specific implementation patterns` H2). Run this grep against the mirrored region before every commit; zero hits required.

Forbidden tokens for this Go file's mirrored sections:

- **DB-engine syntax** — `SET LOCAL`, `set_config\(`, `current_setting\(`, `pg_try_advisory`, `pg_stat_activity`, `BYPASSRLS`, `FORCE ROW LEVEL SECURITY`, `search_path`, `GET_LOCK\(`.
- **Runtime / concurrency mechanic names** — `context\.Context`, `\bgoroutine\b`, `\bgoroutines\b`, `ctx\.Done`, `database/sql`, `\bsqlx\b`, `contextvars`, `\basyncio\b`, `run_in_executor`, `to_thread`, `ThreadPoolExecutor`, `ProcessPoolExecutor`, `copy_context`, `async with`, `after_commit`, `listens_for`, `asyncio\.Queue`, `asyncio\.Event`, `asyncio\.create_task`, `asyncio\.Task`, `asyncio\.gather`.
- **Library / framework API names** — `GORM`, `Hertz`, `Kitex`, `golang\.org/x/time/rate`, `SQLAlchemy`, `FastAPI`, `Starlette`, `Pydantic`, `httpx`, `aiokafka`, `\bpika\b`, `aio-pika`, `redis-py`, `tenacity`, `structlog`, `testcontainers`, `Alembic`, `async-lru`, `asyncpg`, `psycopg`.

Run:

```
awk '/^## Go-specific implementation patterns/{exit} 1' event-driven-architecture.md \
  | grep -nE '(SET LOCAL|set_config\(|current_setting\(|pg_try_advisory|pg_stat_activity|BYPASSRLS|FORCE ROW LEVEL SECURITY|search_path|GET_LOCK\(|context\.Context|\bgoroutine\b|\bgoroutines\b|ctx\.Done|database/sql|\bsqlx\b|contextvars|\basyncio\b|run_in_executor|to_thread|ThreadPoolExecutor|ProcessPoolExecutor|copy_context|async with|after_commit|listens_for|asyncio\.Queue|asyncio\.Event|asyncio\.create_task|asyncio\.Task|asyncio\.gather|GORM|Hertz|Kitex|golang\.org/x/time/rate|SQLAlchemy|FastAPI|Starlette|Pydantic|httpx|aiokafka|\bpika\b|aio-pika|redis-py|tenacity|structlog|testcontainers|Alembic|async-lru|asyncpg|psycopg)'
```

Allowed exception: the *Sibling sync* header itself names the three category classes (without tokens) and references this gate; the *Sanitization boundary* header does not contain any of these tokens. The sibling Python file maintains the matching gate for Python-side tokens, so a token forbidden here may legitimately appear in the *Python-specific implementation patterns* section of the sibling, and vice versa.
