# Artifact Generation Patterns

Use this when implementing generated spreadsheets, PDFs, CSVs, reports, exports, or downloadable files.

## Generator Shape

- Split generators into data query, row/page model, template/style, writer, upload, and artifact record.
- Accept an `io.Writer` for generated output where possible; return bytes only for small artifacts.
- Keep templates, column definitions, fonts, styles, and page dimensions configurable or versioned.
- Avoid reflection-based row extraction unless field ordering and exported-field handling are explicit and tested.
- For spreadsheet columns, prefer typed column definitions over struct field order.

## Spreadsheets And CSV

- Use streaming writers for large spreadsheets.
- Set stable sheet names, header rows, column order, cell formats, and empty-value behavior.
- Validate sheet names and cell values for client compatibility.
- Close files/writers and propagate close errors when the library requires it.
- CSV generation should define delimiter, quoting, newline, encoding, and formula-injection protection.

## PDFs And Rich Reports

- Register fonts/assets before rendering and fail early if missing.
- Keep layout math isolated and covered by tests for pagination, wrapping, alignment, and overflow.
- Treat external images and assets as untrusted: set download timeout, size limit, content type validation, and cache policy.
- Render to a buffer or writer, then upload through the storage adapter.

## Storage And Download

- Upload generated artifacts with content type, size, checksum where available, and retention metadata.
- Store object key, file name, format, size, status, and expiry in the artifact/job record.
- Do not write server runtime outputs only to local disk.
- Signed download URLs should be short-lived and scoped to the requester.

## Tests

- Test empty dataset, large dataset, stable column order, invalid sheet name, formula injection, missing font/asset, pagination, upload failure, close error, content type, and generated file openability.
