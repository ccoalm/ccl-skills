# Batch And Artifact Patterns

Use this for import/export scripts, backfills, reports, generated files, CSV/XLSX/PDF artifacts, and repair tools.

## Implementation

- Add dry-run mode for destructive or broad updates.
- Use chunking, checkpointing, and resume for large jobs.
- Bound concurrency and external dependency rate.
- Write error reports for partial failures.
- For object or artifact migration, record success, error, skipped, and conflict rows in replayable output so reruns can resume or audit decisions without re-discovering every item.
- Make output artifact paths, object storage keys, retention, and download permissions explicit.
- Test parsing, validation, edge rows, and retry/resume behavior.
