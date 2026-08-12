# MQ Consumer Patterns

Use this when implementing MQ consumers, producers, event handlers, delayed tasks, or async side effects.

## Constructor And Startup

- Create one small consumer struct per topic/group responsibility; inject service logic, repositories, and dependency clients.
- Load topic, consumer group, credentials, worker count, retry count, filters, and activation gates from typed config.
- If the queue supports vendor-specific features, such as message tags, server-side selectors, table-change filters, ordered or broadcast delivery, delayed delivery, lane metadata, or log/trace properties, model them as typed config or producer/consumer wrapper behavior rather than inline literals.
- Producers should inject trace/log and lane/environment metadata into outgoing messages when the platform supports it; consumers should restore that context before calling application logic.
- Build all consumers through DI and expose an aggregate starter only at the application boundary.
- Startup should return errors to the main runtime; fail fast for required consumers and skip cleanly for disabled optional consumers.
- Do not create consumers with nil handlers or missing group config.
- If a durable outbox relay is needed, implement it as an infrastructure/platform worker with typed config, lifecycle ownership, readiness/metrics, and a repository/publisher boundary. Do not duplicate outbox scan, retry, publish, and status-transition loops in each business feature.

## Handler Flow

- Handler shape should be: create/receive context, decode typed payload, validate, pre-handle/drop, call application logic, map result to ack/retry.
- Do not let raw message bodies leak past the consumer boundary.
- Treat malformed payloads as permanent failures: log safe context, alert if needed, and acknowledge or dead-letter according to policy.
- Return retryable errors for transient dependency failures.
- Return success for irrelevant or intentionally skipped events after logging the reason.
- Add idempotency around every side effect that can be repeated by duplicate delivery.
- If ordering is configured, keep worker count or partitioning consistent with the ordering key; if ordering is not configured, re-read current state before every side effect that depends on sequence.
- Handler return values must intentionally map to queue ack/retry/drop behavior. Do not let an incidental error type decide whether the message is retried.

## Durable Outbox Relay

- Store the event before or in the same transaction as the state change that requires publication.
- Relay workers should claim rows with a bounded batch size, lease timeout, retry threshold, next-attempt timestamp, poll interval, and optional jitter; all knobs belong in typed config.
- Lock ownership must be unique across container replicas and process restarts. Prefer service plus pod or host identity plus process id or random instance id; service plus pid alone is not enough in containerized runtimes.
- Do not assume a relay preserves emit order once retries, batching, or multiple replicas are involved. Consumers must tolerate reordering, or the relay must enforce ordering by an explicit partition or ordering key.
- Publish success should transition the outbox row to a terminal published state. Publish failure should persist a safe truncated error, increment attempts, apply bounded backoff, and move to a terminal failed state after the threshold.
- Expired processing leases should be repaired by a bounded release step before claiming new work.
- Relay publish payloads should preserve the same envelope shape as synchronous publishers so consumers do not need separate handling paths.
- Tests should cover claim ordering, duplicate or missing ownership, success transition, retry transition, terminal failure threshold, expired lease repair, and publisher payload shape.

## Dynamic Activation

- Check environment/lane or feature-gate activation before starting the consumer, not inside every message unless the policy must change live.
- If live activation changes are required, keep the active snapshot atomic and define what happens to in-flight messages.
- Log skipped startup with consumer group, topic, current environment/lane, and selected config version.

## Latency And Alerting

- Measure each message handler duration.
- Emit metrics for received, decoded, dropped, succeeded, retried, failed, and slow messages.
- Slow-message alerts should include event type, event id or safe resource id, consumer group, topic, and trace/log id.
- Redact or truncate payloads in alerts; never send raw secret-bearing bodies.

## Tests

- Unit-test decode failure, validation failure, skip/drop, retryable dependency error, idempotent duplicate, slow handler alert, and disabled startup.
- Use fake queue clients and fake service logic by default.
- Integration tests with real queue infrastructure should be opt-in and isolated from the fast test target.
