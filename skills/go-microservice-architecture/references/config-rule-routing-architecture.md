# Config Rule Routing Architecture

Use this when designing dynamic config, rule evaluation, request routing, rollout ratios, filters, or controlled execution.

## Contract

- Define a typed config schema with version, enabled flag, include/exclude scopes, rules, priority, ratio, target, and metadata.
- Validate config before activation: required fields, enum values, regex syntax, ratio bounds, total ratio limits, timeout limits, and unknown target behavior.
- Keep rule input fields explicit. Avoid reading arbitrary context keys without a documented field registry.
- Support nested condition groups only when the product needs them; otherwise prefer a flat rule list.
- Define operator semantics once: equality, inequality, numeric comparison, containment, regex, set membership, and missing-field behavior.

## Activation

- Config refresh should be atomic: load, parse, validate, then swap the active snapshot.
- On config load or parse failure, use the last valid snapshot or a documented safe default.
- Version changes should be observable through logs and metrics.
- Concurrency must be safe for high-read, low-write access patterns.

## Routing Policy

- Priority ordering must be deterministic, including tie-break behavior.
- Ratio rollout should be stable when users or resources need sticky assignment; random sampling is acceptable only for stateless sampling.
- Disabled rules should be skipped without side effects.
- Unknown targets should fail closed or route to an explicitly approved default.
- Every route decision should expose rule id, config version, selected target, and skip reason where useful.

## Dynamic Config Key Namespace

- For etcd-backed or config-center dynamic config, architecture declares the key namespace shape: `/{service}/{namespace}/{key}` is the common pattern, with `service` identifying the owning platform service identifier, `namespace` separating logical config domains (e.g. `db_shard`, `rate_limit`, `feature_flag`), and the leaf naming the entity. Raw etcd keys never leak into application code.
- Endpoint discovery for the config backend itself: when etcd endpoints come from another service-discovery system, architecture sets the refresh cadence (10-30 s is typical) so endpoint churn does not amplify into config hot-path latency. Refresh happens lazily on the next operation, not on a tight loop.
- Failure-mode allocation per responsibility: key-not-found, decode error, and remote/transient error each route to a different product behavior. Architecture documents which keys fall back to last-known-good cache (feature flags, rate budget), which fail closed (auth policy, billing rules), and which fail open (telemetry knobs).
- Watch callbacks run in their own goroutines and must recover from panic, update local cache atomically, and shut down cleanly on parent-ctx cancellation. A silently-dead watcher is harder to detect than a missing one; surface watcher health as a metric.
- Watch reconnect must preserve monotonicity: persist the last-observed revision/version, resume from `last_revision + 1` after disconnect, and trigger a full resync (re-read all subscribed keys) on `ErrCompacted` or other history-loss errors. Use jittered exponential backoff on reconnect to avoid stampede. Track watcher staleness as a metric and fail readiness probes when a critical-config watcher has been stale beyond a documented threshold.
