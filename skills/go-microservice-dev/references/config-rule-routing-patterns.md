# Config Rule Routing Patterns

Use this when implementing dynamic config, rule evaluation, filters, routing, rollout ratios, or controlled execution.

## Config Loading

- Represent config as typed structs with JSON/YAML tags, version, enabled flag, and default values.
- Load config through a provider interface so tests can supply fixed snapshots.
- Parse and validate into a new snapshot before swapping active config.
- Use an `RWMutex`, `atomic.Value`, or equivalent snapshot holder for high-read access.
- On provider or parse failure, keep the last valid snapshot and log/metric the failure.
- Avoid calling `defer cancel()` inside long-running loops; cancel each refresh context before the next iteration.

## Validation

- Validate required fields, enum values, regex syntax, ratio range, total ratio, max body size, timeout, concurrency, and target names.
- Keep validation errors structured with field and message.
- Register custom validators for complex objects instead of embedding ad hoc checks in handlers.
- Unknown rule fields should fail validation unless the schema explicitly supports forward-compatible metadata.

## Rule Evaluation

- Define a field registry that maps rule field names to typed extractors from request/context/metadata.
- Normalize values before comparison; numeric operators should parse both sides as numbers or fail predictably.
- Supported operators should be explicit: `eq`, `ne`, `lt`, `gt`, `le`, `ge`, `contains`, `regex`, `in`.
- Missing fields should have one documented behavior, usually no match.
- Nested condition groups should evaluate deterministically for `AND` and `OR`.
- Priority sorting should be stable and documented.

## Ratio Routing

- Use sticky hashing when route consistency matters for a subject or resource.
- Use random sampling only for stateless sampling where per-request variance is acceptable.
- Clamp ratios to valid bounds and test `0`, `1`, `50`, `99`, and `100`.

## Tests

- Test invalid config fallback, config version swap, concurrent reads during refresh, missing fields, bad regex, numeric parse errors, nested groups, priority ties, disabled rules, unknown target, and ratio boundaries.
