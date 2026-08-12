# Feishu Comment-Safe Editing

Applicability: the principle is universal: never destroy collaborative comments. The `lark-cli`, `replace_range`, `selection-with-ellipsis`, and `comment_id` mechanics below are Feishu-only. On Google Docs, Notion, Confluence, or git markdown, keep the principle and use that platform's safe-edit primitive.

Before editing any collaborative doc, fetch its real title and count its comments.

- 0 team comments on docs you authored: full overwrite is safe after title/body checks.
- More than 0 team comments: never overwrite the whole doc. Rebuilding blocks orphans every comment; the platform API cannot re-anchor an existing comment, cannot set a comment's original author, and table-cell blocks cannot take API comments. Use paragraph-level `replace_range` on just the target span, return a read-only audit with `原文 -> 改法 + 位置`, or export all comments first.
- Renaming: check the real title first. Usually you only need to fix the link text in your own docs, not touch the commented doc.

## Anchor Preservation

- Feishu re-anchors a comment by matching its quoted text, not by block id.
- A `replace_range` section rebuild does not orphan comments whose exact quoted substring survives byte-identical in the new content.
- Before rebuilding a commented section, list every comment's quoted substring in it and preserve each one byte-identical.
- A comment orphans only when you change the exact string it quotes, typically a reworded heading or exact cell text.
- Your own comment anchored to a string you must change: delete and re-add at the new text. Do not `@mention` unless the user asks. The author field stays bot/you regardless.
- If the quoted string is unchanged, do nothing; it auto-survives.
- Re-fetch ids right before any delete. Never reuse ids from an earlier listing because every rebuild can regenerate them.

## Verification

- After any comment-affecting edit, re-list all comments and inspect anchors plus reply text.
- Do not assume a target count. A count increase may be a teammate comment that arrived mid-edit; keep it.
- Hunt for stale duplicates still anchored to pre-edit text.
- If deleting a section would leave a numbering gap that cannot be safely renumbered because later heading text is comment-locked, re-add the leading section instead of renumbering.
- Comment count is the authoritative orphan check, not substring presence. Feishu rendered text for a table cell or heading may not reproduce the stored quote verbatim because of wrapping, ordinal prefixes, spacing, or trailing spaces.
- Treat `anchor substring not found` on table/heading content as a render-vs-quote false alarm unless the comments API count dropped or no longer lists the comment with its quote.
- Verify a quote you actually changed by re-reading the cell, not by full-text substring search.
- For these doc edits, a mutating-edit call's success/`ok` status is not proof the edit applied — re-read the target block/content and confirm the new text is present before reporting it done (distinct from the comment re-list above: that proves comments survived; this proves the edit itself landed). Block/anchor ids resolved under one API version, or from an earlier fetch, may silently no-op under another version while still returning success — re-fetch ids in the target version first.
- General principle (beyond doc edits; the broader write-finality version lives with `feature-risk-router`'s `write-finality` tag): verify the authoritative postcondition, not the call's status, via a **finite ladder** — direct read if available → operation receipt / status / version / ETag / audit-event or effect id → bounded eventual-consistency retry (cap attempts/window) → if no authoritative read exists (fire-and-forget, write-only, encrypted), report `accepted-not-applied` / `unverifiable`, never `done` and never loop unbounded. The postcondition may be "durably accepted with an idempotency/effect id," not only "new content present."

## Cross-Doc Rename

A cross-doc term/domain rename is comment-safe work, not find/replace.

1. Enumerate every referencing doc.
2. For each doc, list every comment's quoted substring.
3. Check whether any quote contains the token being renamed. If none does, the rename cannot orphan a comment.
4. On any comment-bearing doc, use per-section `replace_range`; never whole-doc overwrite.
5. Change only the renamed token and keep all other text byte-identical.
6. Re-verify comment count unchanged after each section before moving to the next.
7. Rename the card title with `--new-title`; the body has no H1.
8. For `--selection-by-title`, include the `## ` prefix.
9. Parse `lark-cli` stdout by `raw_decode` from the first `{` because the trailing version banner breaks plain `json.loads`.

## Doc-Mention Cites (引用 chip)

A Feishu doc-mention `<cite type="doc" doc-id="<token>">` renders a chip showing the target doc's title. The chip's `title` is a snapshot captured when that doc-id was first mentioned. It was observed not to refresh when the target was later renamed, and re-inserting an empty cite re-reads the same stale cache.

- Empty cite `<cite type="doc" doc-id="<token>"></cite>` → title comes from the stale mention cache. A doc first cited while still unnamed (placeholder title) keeps showing that placeholder even after the doc is correctly named.
- Inner-text cite `<cite type="doc" doc-id="<token>">目标标题</cite>` → Feishu copies the text into the `title` attribute AND keeps a duplicate plain-text sibling, rendering "chip + 重复标题".
- To force a specific chip label: explicit `title` ATTRIBUTE with empty inner — `<cite type="doc" doc-id="<token>" title="目标标题"></cite>`. Clean chip, no duplicate, still a clickable doc mention.
- An explicit `title` is a PINNED label: if the target is renamed later, the chip silently shows the old hardcoded title. A later rename means finding and rewriting every inbound cite, or chips go stale-wrong.
- One block can hold several cites (e.g. "以 A 和 B 为准"). Fix every cite in the block, not just the first match. `block_replace` rewrites the whole block, so reconstruct the entire block content preserving all surrounding text and inline markup — only mutate the cite elements — or you drop prose like "上线评审用 X 逐项确认。".
- The fix loop must re-fetch ids each iteration (`block_replace` assigns a new block id) and decide "already fixed?" by comparing PARSED semantics (cite `doc-id` + `title` + empty inner + no duplicate label sibling), never by raw serialized-string compare: the API re-normalizes attribute order / escaping, so a string compare never converges and the loop churns forever.
- Verify after: each cite's `title` attribute equals the intended label and no copy of the label follows `</cite>`.

## Docx Title Rename (v2)

To rename a `--api-version v2` docx whose title is its title block:

- `block_replace` on the title block fails; the title block is not block-replaceable.
- `--new-title` returned `result: success` but left the title unchanged (observed no-op in v2). Do not trust it; verify the result.
- Use `docs +update --api-version v2 --command str_replace --pattern '旧标题' --content '新标题'`: the title-block text is inline plain text, so str_replace rewrites it. `drive +inspect` then shows the new title and the wiki node-tree title syncs.
- `str_replace` is full-doc and replaces EVERY occurrence of `--pattern`, not just the title — if the title text recurs in a heading, table, or body line it gets rewritten too. Preflight: fetch and count matches, use a pattern unique to the title, and after the edit verify only the title changed.
- Do not change Cross-Doc Rename step 7: its `--new-title` applies only to the card-title / domain-card rename flow, not to a general v2 docx. For a general docx, verify the title actually changed.
- Renaming the target was observed not to update cite chips pointing to it (stale snapshot, above). After a rename, rewrite each referencing chip with the explicit `title` attribute.

## Range Update Mechanics

- `lark-cli docs +update --mode replace_range/delete_range` locators match the doc's rendered text, not markdown syntax. Drop prefixes such as `### ` and `- `.
- `--selection-with-ellipsis 'X...X'` with identical start and end is unreliable. Use two distinct substrings as `start...end` bounding exactly the target span.
- A non-matching locator is a no-op and is safe to probe.
- By-title section rebuild is more reliable than a single-cell ellipsis locator.
- Batch many small in-section edits into one rebuild instead of one rebuild per tweak.

## Full Overwrite Pitfalls

For `lark-cli docs +update --mode overwrite`:

- The `--markdown` value must be `@./relativefile`. The `@` means read-from-file; without it, the literal argument string is written as the doc body.
- The file must be a relative path inside the current working directory. Write temp markdown into the working directory and reference `@./name`.
- A Feishu docx renders its title block as the H1. If uploaded markdown also starts with `# <title>`, the title doubles. Strip the leading title line from the upload body.
- The CLI prepends a version/update-check banner to stdout. Parse from the first `{`; hard-stop on `ok:false` or validation error.
- Always re-fetch and grep-verify the actual changed line and title-line count.
- Do fetch/strip/replace body surgery in Python instead of `sed`/`awk`; BSD-vs-GNU differences break these one-liners on macOS.

## Renumbering

- After a renumber, locate the target section by heading text, never by section number.
- If a doc was renumbered, splitting on an ordinal prefix can grab the wrong section and silently fail.
- A failed assert before the write means the temp file was not produced. Verify the no-op left the doc and comment count intact instead of assuming the push applied.
