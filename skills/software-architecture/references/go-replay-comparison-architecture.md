# Replay Comparison Architecture

Use this when designing replay, shadow execution, migration confidence checks, response diffing, or dual-run validation.

## Execution Model

- Separate capture, replay, comparison, storage, and reporting.
- Replays need durable job state, concurrency limit, timeout, delay policy, rate limit, target environment or lane, and cancellation policy.
- Captured input must be redacted and bounded by size before storage.
- Replay requests should preserve only approved headers and metadata; never replay credentials blindly.
- Shadow execution must not commit side effects unless the target is explicitly isolated.

## Comparison Policy

- Define comparator selection by method, content type, schema, or route.
- Generic JSON comparison should support ignored fields, custom field comparators, numeric tolerance, null handling, array handling, and type mismatch reporting.
- Diff output should include field path, original value summary, replay value summary, diff type, score, and ignored status.
- Comparison thresholds should be config driven and versioned.
- Positive, negative, and neutral diffs should be classified only when the product has a defensible definition.

## Retention And Reporting

- Store aggregate job counts and paginated diff details separately.
- Define retention for captured requests, replay responses, and diff artifacts.
- Expose summary metrics: total, processed, success, failed, diff count, similarity, p95 replay latency, and error categories.
- Treat replay as a confidence signal, not an automatic release approval unless acceptance gates are explicit.
