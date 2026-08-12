# Bulk Import And Export Patterns

Use this when implementing spreadsheet, CSV, file import, export, or other large batch jobs.

For status transitions, duplicate delivery, retry, and cancellation mechanics, use `state-machine-task-patterns.md` as the canonical implementation guide. This file covers row/file handling, slice execution, artifacts, and reports.

## Import Pipeline

- Represent each input row as a typed row object with row number, source name, raw values, normalized values, and `Errors []string`.
- Define source name as the sheet, tab, file part, or partition name from the input format.
- Validate file type, size, sheet/tab/partition count, visible sheets or partitions, header shape, start row, and min/max column count before row parsing.
- Normalize cells at the boundary: trim whitespace, pad missing optional columns, parse accepted list separators, and reject unsupported encodings or formats.
- Static row validation accumulates row errors; ordinary row errors should not fail the whole file.
- Cross-row validation detects duplicates and conflicts, then annotates every affected row.
- Enrichment and mapping resolve external names or codes to IDs through typed lookup caches.
- Mapping misses become row errors unless the workflow is explicitly fail-fast.
- Commit only valid rows, chunk large batches, and preserve per-row outcome.

## Job And Slice Processing

- Persist a job record with status, progress, total count, success count, failed count, error file pointer, actor, source file, and idempotency key.
- Split large jobs into slices or messages with stable slice index and job token.
- Use distributed locks or compare-and-update from the state-machine guide to claim each slice.
- Progress updates are best-effort; final status and counts must be durable.
- When all slices finish, generate a consolidated error report and transition the job to a terminal state.

## Error Reports

- Preserve original row order and include source row, source name, and failure reasons.
- Generate reports with streaming writers for large files.
- Upload reports to object storage with bounded expiry or retention and store only the object key or signed reference in the job record.
- Do not include secrets, tokens, credentials, or sensitive raw payloads in error reports.
- Empty error reports should be represented explicitly rather than failing report generation.

## Export Pipeline

- Use cursor or id-window pagination instead of offset for large datasets.
- Use streaming writers and chunked reads; avoid loading all rows into memory.
- Include stable column definitions, version, generated time, actor, and filter summary where useful.
- Apply the same authorization and resource-scope filters to export queries as API reads.
- Long exports should run as jobs with progress and downloadable artifact status.

## Cursor-Based Data Migration

- For large table migrations, read source rows by monotonic cursor or id window, not offset.
- Discover min/max cursor before splitting work, and persist or print chunk boundaries so failed chunks are replayable.
- Make worker count and chunk size explicit config with conservative defaults and validation.
- Insert into the target with idempotent create/upsert semantics before deleting from the source.
- Delete source rows only for the cursor window that was successfully written; prefer one transaction when source and target share a database boundary, otherwise record a replay or reconciliation path.
- Emit per-worker progress with current cursor, chunk range, migrated count, speed, and terminal error.
- Treat progress as best-effort and final migration state as durable or replayable; a closed progress channel is not proof that all chunks succeeded.

## Tests

- Test empty file, hidden or empty sheets/partitions, malformed headers, short rows, long rows, duplicate rows, mapping misses, partial success, error report generation, slice idempotency, cancellation, and retry after crash.
- For cursor migrations, test empty range, cursor boundary inclusiveness, idempotent insert, delete-after-insert ordering, worker error propagation, replaying a partial chunk, and progress reporting.
