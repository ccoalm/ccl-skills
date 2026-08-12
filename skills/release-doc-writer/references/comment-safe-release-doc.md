# Comment-safe Release-doc Editing

For collaborative release documents:

1. Resolve the actual document and target section.
2. Fetch the section with stable block/table/list identifiers when the tooling supports it.
3. List comments or anchors before editing.
4. Edit only target blocks, table cells, rows, or list items.
5. Preserve document structure and heading hierarchy.
6. Re-fetch the edited section and comment state after editing.

Avoid:

- Replacing the whole document body.
- Flattening tables into prose or lists.
- Deleting placeholders that carry comment anchors.
- Claiming a doc was updated without read-back evidence.

Final responses should state the edited section, read-back marker, comment status, and evidence limitations.
