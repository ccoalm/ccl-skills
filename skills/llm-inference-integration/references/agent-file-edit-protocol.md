# Robust Model-Driven File-Edit Protocol

Implementation companion to the Tool Execution rules in `retrieval-agent-safety.md`. When an agent
edits files by emitting an edit instruction the model authored, the *format and matching strategy* of
that edit tool decide whether edits land reliably or corrupt files. This reference is how to design
that tool. Filesystem-safety of the write itself (writable roots, sandbox, hard-link escape) is owned
by `agent-command-sandbox.md`; this is about the edit format and apply algorithm.

Use when designing or reviewing an agent's file-edit / apply-patch tool. Drawn from a production
reference agent.

## 1. Anchor edits on surrounding context, not line numbers

Models cannot reliably count line numbers, but they reproduce *surrounding text* well. A line-number
or offset-based diff breaks the moment the model miscounts or the file drifted by a line; a
context-anchored edit can survive nearby line-count drift *as long as the referenced context is still
present and unique*.

- Use an explicit envelope with per-file operations: add file, delete file, update file, move/rename
  file. Mark file boundaries so one payload can edit several files.
- **Validate the operation graph before matching any hunk.** Normalize and dedupe paths (account for
  case-insensitive/Unicode-normalizing filesystems), and reject conflicting operations on the same
  path: two updates to one file, delete-then-update, update-then-move, move onto an existing path
  without an explicit overwrite, or two operations producing the same target. Define a deterministic
  order for moves/deletes/adds. A payload with a contradictory op-graph is a hard error before any
  matching or writing.
- Within an update, identify each change by a **context window** (a few unchanged lines around the
  edit) plus the `+`/`-` changed lines — not by `(line, column)`. A short `@@`-style locator that
  names the enclosing function/section helps disambiguate repeated context.
- Require enough context to make each hunk's location **unique** in the file; if the same context
  appears in multiple places and the locator does not disambiguate, that is an ambiguity error
  (§3), not a pick-the-first guess.

## 2. Match with graduated strictness, fail when it does not match

When locating a hunk's context in the current file, try progressively more lenient matches and stop
at the first that succeeds:

1. exact line match;
2. ignore trailing whitespace;
3. ignore leading and trailing whitespace.

This absorbs the model's minor whitespace imprecision without silently editing the wrong place. Two
further rules:

- **EOF-anchored hunks**: when a hunk is meant to match the end of the file, match at the end. If you
  allow a forward-search fallback, the fallback match must be *globally unique* and reported as a
  non-EOF location — otherwise an intended append silently overwrites an earlier duplicate-context
  region.
- **Defensive bounds**: a pattern longer than the file is an immediate no-match; never index past the
  buffer. Reject an *empty* context pattern rather than treating it as a universal no-op match
  (an empty pattern matches everywhere and defeats the uniqueness requirement) — the only legitimate
  empty-context cases are explicit file-level add/delete operations.

Do not extend leniency to fuzzy/semantic similarity — that is how an edit lands in the wrong
location. Beyond whitespace tolerance, a non-match is a failure.

**Treat files as encoded text, not raw buffers.** Detect and reject binary content before editing.
Preserve the file's existing line-ending convention (LF vs CRLF), BOM, and final-newline state rather
than normalizing them — a tool that silently rewrites every line ending produces a diff that is all
noise and can break the build. Match against the file in its decoded form so a BOM or CRLF does not
defeat an otherwise-correct context match.

## 3. Resolve everything before writing anything

Apply in two phases so a bad hunk fails *before* the filesystem is touched:

1. **Resolve phase** — parse the whole payload, match every hunk's context in every target file
   against a *single original snapshot* of that file, and compute the full new contents in memory.
   Resolve each file's hunks to **non-overlapping spans of the original**; reject overlapping or
   conflicting hunks rather than double-applying, and materialize the new file from those spans in
   deterministic order. Any parse error, unmatched context, ambiguous match, or overlap aborts here
   with a precise, model-readable error (which file, which hunk, why). Nothing has been written yet.
   Generate the preview/diff here, in the resolve phase — preview after writing is too late to gate
   an approval on.
2. **Write phase** — only after every hunk resolved, write the computed contents.

An unmatched, ambiguous, or overlapping hunk is a hard error the model can correct, never a
best-effort partial edit.

## 4. Multi-file writes are not transactional — report the exact partial state

A real filesystem cannot atomically commit writes to several files. If the write phase fails midway
(permissions, disk, a sandbox denial), some files are already changed and some are not. Do not claim
full success and do not claim a rollback you did not perform:

- **Make each single-file write atomic** — write to a temp file and `rename` over the target so a
  crash mid-write cannot leave a *torn* file (neither old nor new contents). Without this, a failure
  partway through one file corrupts it; with it, each file is all-old or all-new.
- Track which files were committed before the failure and return that exact set with the error. A
  file whose atomic rename had not completed is reported as **unchanged**; only treat a file as
  unknown/torn if you could not use atomic replace for it. Never report a half-written file as
  "committed".
- Distinguish a side-effect-free failure (nothing was written) from a partial-commit failure (some
  files changed). Mark the reported delta as exact or no-longer-exact accordingly.
- An empty patch (no file would change) is an error, not a silent success.
- Return a **bounded** diff for preview/approval (computed in the resolve phase, §3). Return full
  file contents only behind an explicit caller option — echoing whole files by default leaks large or
  sensitive file content into logs and transcripts.

## Non-negotiables

- Edits are located by surrounding context, never by raw line/column offsets.
- Matching leniency stops at whitespace tolerance; anything looser is a non-match, and a non-match,
  ambiguous match, empty-context pattern, or overlapping hunk is a hard, model-correctable error —
  never a silent wrong-location or double-applied edit.
- Validate the multi-file operation graph (unique normalized paths, no conflicting ops, explicit
  overwrite policy) before matching hunks.
- Treat files as decoded text: reject binary, preserve existing line-ending/BOM/final-newline
  conventions, never normalize them silently.
- Resolve and validate all hunks against one original snapshot in memory before writing any file;
  generate the preview diff in that resolve phase, not after writing.
- Write each file atomically (temp + rename) so a failure cannot leave a torn file.
- On partial multi-file failure, report the exact committed set and whether the delta is still exact;
  a not-yet-renamed file is unchanged, never report a half-written file as committed or claim an
  un-performed rollback.
- Return full file contents only behind an explicit option; default to a bounded diff to avoid
  leaking large/sensitive files into logs.
- Route the write itself (writable-root/sandbox/hard-link checks) through `agent-command-sandbox.md`;
  this protocol owns *what to write*, that reference owns *whether the write is allowed*.

## Routing

- The decision to require approval for a file mutation, and the safety classification of the write
  target → `retrieval-agent-safety.md` Tool Execution + `agent-command-sandbox.md`.
- Rendering the before/after diff and approval prompt in a terminal → `terminal-cli-dev`.
- Persisting the edit as a session event for replay → `agent-session-persistence.md`.
- Verifying edit-tool robustness (context drift, ambiguity, partial-failure cases) at the test layer
  → `testing-strategy`.
