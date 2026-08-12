# Data And Workflow Testing

Use this for batch jobs, ETL/ELT, streaming, scheduled tasks, backfills, replay, and workflow pipelines.

For LLM/model replay, shadow runs, prompt/model regression, or eval datasets, route to `llm-inference-integration`. For stack-specific replay implementation, route to the relevant development skill: `go-microservice-dev` for Go and `python-service-dev` for Python.

## What To Prove

- Idempotent reprocessing: rerunning the same input or window produces the same result without duplicates or double side effects.
- Late, out-of-order, missing, and duplicate events behave according to the stated contract.
- Windowing, partitioning, aggregation, and pagination are correct at boundaries: empty window, single record, window edge, cutoff, watermark, and page boundary.
- Schema evolution handles new, removed, renamed, widened, and nullable fields with forward/backward compatibility where required.
- Backfill and replay produce expected historical results without corrupting downstream state.
- Checkpoint, offset, cursor, and resume logic recovers after interruption without loss or double-count.

## Data-Quality Assertions

- Assert row/record counts, key uniqueness, referential integrity, null/range constraints, reconciliation totals, and output invariants.
- Assert output schema and semantic contract, not only that a job exited successfully or created a file.
- For generated reports or exports, parse the output and assert meaningful fields instead of comparing a large opaque blob.

## Strategy

- Test transformation rules as pure unit tests on small typed records.
- Use integration tests for source/sink contracts, partitioning, storage layout, cursor/checkpoint persistence, and transaction boundaries.
- Reserve E2E for one critical pipeline path plus the highest-risk failure or recovery path.
- Use fixed clocks and scenario-sized fixtures for scheduled or windowed jobs.

## Avoid

- Treating "job ran" or exit code 0 as correctness evidence.
- Wall-clock-dependent windows without an injected clock.
- Whole-dataset golden files when scenario-scoped assertions suffice.
- Shared mutable staging data without namespace, cleanup, or isolation.
