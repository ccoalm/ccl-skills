# MQ Consumer Architecture

Use this when designing message topics, consumer groups, event contracts, async processors, or producer/consumer ownership.

## Event Contract

- Treat MQ delivery as at-least-once unless the queue contract proves otherwise.
- Every event type needs owner, producer, consumer group, payload schema, version, event id or idempotency key, occurred time, and retry policy.
- Payloads should carry stable resource identifiers and event type, not require consumers to parse free-form text.
- Consumers should tolerate unknown additive fields and reject unknown required semantics at the boundary.
- If ordering matters, define the ordering key and constrain consumer concurrency accordingly.

## Topic And Group Ownership

- Topic names, consumer groups, tags/filters, worker count, retry count, and delay policy belong in typed config.
- Consumer groups should map to one logical processing responsibility.
- Multiple responsibilities may share a topic only when each consumer has explicit event filters and independent idempotency.
- Producer identity, queue selector, trace/log metadata, lane/environment metadata, and ordering key are part of the contract when the queue platform supports them.
- Dynamic activation gates, such as environment/lane allowlists or feature switches, should be config-driven and observable.
- A disabled consumer should skip startup cleanly; a misconfigured required consumer should fail service readiness.

## Processing Semantics

- Decode, validate, and pre-handle payloads before side effects.
- Distinguish permanent drops from retryable failures:
  - malformed payload, unknown event type, or irrelevant event can be logged/alerted and acknowledged.
  - transient dependency failures should return retry.
  - permanent domain conflicts should map to a documented ack or dead-letter policy.
- Re-read current state before acting on delayed, duplicate, or out-of-order messages.
- Side effects must be idempotent by event id, resource id, natural key, or durable task state.

## Operations

- Consumer startup, skip, retry, drop, success, failure, and latency should be logged and metered with low-cardinality tags.
- Slow message processing needs a configurable threshold and alert path.
- Consumer shutdown should stop fetching new messages, wait for in-flight handlers up to a deadline, then close clients.
- Poison messages need a dead-letter, quarantine, or manual replay plan before launch.
- Ordered processing should constrain worker count or partitioning explicitly; unordered processing must tolerate duplicate, delayed, and out-of-order delivery.
