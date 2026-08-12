# Sync Spec / Repo Contract

Use this reference for the spec / repo-contract sync gate's detailed mechanics: how the repo-local agent contract stays in sync with the slice, and how to handle value sets owned by an upstream authority the repo does not own. The entrypoint keeps the gate's firing rule and a pointer here; the upstream no-copy rule itself and the handling detail live in this file.

## Repo-local contract sync

- `agents-file-coverage-gate` owns AGENTS.md coverage, nearest-file-wins/source-directory scan semantics, `--check`/`--fix`/`--enforce`, hook/CI wiring, and incremental adoption.
- Lint/build counts as contract evidence only when that target runs the coverage gate.
- Repo-local agent contracts carry version-independent rules plus a version-authority pointer (manifest/lockfile/dependency declaration); never copy the current pin — `platform-release-engineering` owns the layered version model and the audit/snapshot inline-version exception.

## Upstream-authority value sets (no-copy handling)

- Never restate an upstream authority's value sets: **The same no-copy rule governs any UPSTREAM AUTHORITY the repo does not own** — restating its *value sets* creates a second source that drifts silently — keep a pointer plus the revision you read, and make the MR checkable without redistributing the upstream: default to the access-controlled pointer + revision + the reviewer's own comparison result.

Handling mechanics:

- When implementation genuinely needs the values fixed, freeze them in the **contract artifact** (IDL enum, schema, generated code) so the values live in one reviewable place instead of scattered prose.
- The reviewer opens the source and attests the values match; record that comparison result next to the pointer.
- Only quote an excerpt when the upstream's classification and redistribution permissions actually allow it — a partner contract, an access-controlled spec, or anything under NDA must not be pasted into an MR body or review comment, which are durable platform history that outlives the repo (this is the artifact-egress confidentiality gate, applied to the upstream side).

## "The upstream is silent" is a whole-document claim

When you conclude the upstream is SILENT on something, that is a claim about the whole document, not about the sections you happened to open: keyword-hit-and-stop reads the sections that mention your search term, which is exactly the wrong sample for an absence claim. Enumerate the upstream's own section list for the topic and read them, or scope the conclusion to the sections you actually read.

Failure shape: three sections searched, an "upstream never specified this" open-decision registered, downstream work blocked on it — while a fourth section held a titled, closed specification; the same repo had also drifted the upstream's version number and two of its state counts.
