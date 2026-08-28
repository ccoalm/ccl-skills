# Replay Comparison Patterns

Use this when implementing replay jobs, shadow execution, response comparison, migration verification, or diff reports. Reuse `state-machine-task-patterns.md` for job transitions and terminal-state behavior.

Sibling note: `go-microservice-dev/references/replay-comparison-patterns.md` carries the Go rendering; adapted per stack, kept in sync by review (not under the parallel-stack parity gate).

## Replay Jobs

- Persist replay jobs with status, target, config version, total/processed/success/failed/diff counts, timeout, concurrency, rate limit, and retention.
- Use bounded workers with deadlines (`async-and-worker-patterns.md`) for replay execution.
- Preserve only allowlisted headers and metadata; never replay credentials blindly.
- Redact captured requests and responses before storage; bound captured payload size.
- Replay targets must not commit side effects unless isolated by environment, lane, or explicit dry-run mode. Transaction rollback isolates only the local database write — a replayed handler can still send webhooks, publish messages, call payment providers, or write other datastores while its DB transaction rolls back; those adapters need environment/lane isolation or dry-run stubs of their own before rollback counts as isolation.

## Comparator Design

- Define a comparator `typing.Protocol` such as `compare(original, replay) -> Result`; select comparators by method, route, content type, or schema version.
- Generic JSON comparators normalize strings containing JSON, Pydantic models, dicts, lists, and scalars before comparing.
- Support ignored fields by exact path/field name only when documented, loaded from config or comparator registration — never hard-coded in the generic comparator.
- Support custom field comparators for tolerances, unordered collections, timestamps, generated IDs, and approximate numerics.

## Diff Result Shape

- Include field name, field path, original value summary, replay value summary, diff type, diff score, ignored flag, and metadata; bound value summaries so diff records do not store huge payloads.
- Record total compared fields, diff count, similarity, threshold, comparator name, and comparator version.
- Distinguish missing value, added value, type mismatch, length mismatch, value mismatch, and custom comparison.

## Tests

- Test None/None, None/value, value/None, JSON-string normalization, model-to-dict conversion, array length mismatch, missing keys, numeric tolerance, ignored fields, custom comparator, threshold behavior, redaction, storage pagination, and replay cancellation.
