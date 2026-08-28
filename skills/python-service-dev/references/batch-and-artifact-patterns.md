# Batch And Artifact Patterns

Use this for import/export scripts, backfills, reports, generated files, CSV/XLSX/PDF artifacts, and repair tools. For durable job status transitions, duplicate delivery, retry, and cancellation, `state-machine-task-patterns.md` is the canonical guide; this file covers row/file handling, execution, artifacts, and reports.

## Implementation

- Add dry-run mode for destructive or broad updates.
- Use chunking, checkpointing, and resume for large jobs.
- Bound concurrency and external dependency rate.
- Write error reports for partial failures.
- For object or artifact migration, record success, error, skipped, and conflict rows in replayable output so reruns can resume or audit decisions without re-discovering every item.
- Make output artifact paths, object storage keys, retention, and download permissions explicit.
- Test parsing, validation, edge rows, and retry/resume behavior.

## Import Pipeline

- Represent each input row as a typed row object with row number, source name (sheet/tab/file part), raw values, normalized values, and an error list.
- Validate file type, size, sheet/partition count, header shape, start row, and column-count bounds before row parsing; normalize cells at the boundary (trim, pad missing optional columns, parse accepted list separators, reject unsupported encodings).
- Static row validation accumulates row errors; ordinary row errors do not fail the whole file. Cross-row validation detects duplicates and conflicts, then annotates every affected row.
- Enrichment resolves external names/codes to IDs through typed lookup caches; mapping misses become row errors unless the workflow is explicitly fail-fast.
- Commit only valid rows, chunk large batches, and preserve per-row outcome. Persist the job record (status, progress, counts, error-file pointer, actor, source file, idempotency key) per `state-machine-task-patterns.md`.

## Error Reports And Export

- Error reports preserve original row order with source row, source name, and failure reasons; generate with streaming writers; upload to object storage with bounded retention and store only the object key or signed reference. Represent an empty report explicitly rather than failing generation. No secrets or sensitive raw payloads in reports.
- Exports use cursor or id-window pagination (never offset for large datasets), streaming writers, and the same authorization/resource-scope filters as API reads; long exports run as jobs with progress and a downloadable artifact status.

## Cursor-Based Data Migration

- Read source rows by monotonic cursor or id window; discover min/max before splitting work and persist chunk boundaries so failed chunks are replayable.
- Insert into the target with idempotent create/upsert semantics before deleting from the source; delete only the cursor window that was successfully written, and record a replay/reconciliation path when source and target do not share one transaction boundary.
- Emit per-worker progress (current cursor, chunk range, migrated count, speed, terminal error); progress is best-effort — final migration state must be durable or replayable, and a closed progress channel is not proof all chunks succeeded.

## Tests

- Test empty file, hidden/empty sheets, malformed headers, short/long rows, duplicate rows, mapping misses, partial success, error-report generation, slice idempotency, cancellation, and retry after crash.
- For cursor migrations, test empty range, cursor boundary inclusiveness, idempotent insert, delete-after-insert ordering, worker error propagation, and replaying a partial chunk.
