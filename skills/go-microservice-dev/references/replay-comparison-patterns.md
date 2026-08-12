# Replay Comparison Patterns

Use this when implementing replay jobs, shadow execution, response comparison, migration verification, or diff reports.

## Replay Jobs

- Persist replay jobs with status, target, config version, total count, processed count, success count, failed count, diff count, timeout, concurrency, rate limit, and retention.
- Reuse `state-machine-task-patterns.md` for task transitions and terminal-state behavior.
- Use bounded workers and context deadlines for replay execution.
- Preserve only allowlisted headers and metadata.
- Redact captured requests and responses before storage.
- Ensure replay targets cannot commit side effects unless isolated by environment, lane, transaction rollback, or explicit dry-run mode.

## Comparator Design

- Define a comparator interface such as `Compare(ctx, original, replay) Result`.
- Select comparators by method, route, content type, or schema version.
- Generic JSON comparators should normalize strings containing JSON, structs, maps, arrays, and scalar values.
- Support ignored fields by exact path and field name only when documented.
- Support custom field comparators for tolerances, unordered collections, timestamps, generated IDs, and approximate numeric values.
- Avoid hard-coded ignored paths in generic comparators; load them from config or comparator registration.

## Diff Result Shape

- Include field name, field path, original value summary, replay value summary, diff type, diff score, ignored flag, and metadata.
- Use bounded value summaries so diff records do not store huge payloads.
- Record total compared fields, diff count, similarity, threshold, comparator name, and comparator version.
- Distinguish missing value, added value, type mismatch, length mismatch, value mismatch, and custom comparison.

## Tests

- Test nil/nil, nil/value, value/nil, JSON string normalization, struct-to-map conversion, array length mismatch, missing keys, numeric tolerance, ignored fields, custom comparator, threshold behavior, redaction, storage pagination, and replay cancellation.
