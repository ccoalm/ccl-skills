# Obligation preservation

The comparison domain is the changed tighten-doc entry plus the reference destination. The relocated row set is the card skeleton and four card-specific rules; all other entry text is expected to remain byte-identical.

New governing chain: tighten-doc entry → execution/domain-card generation/edit/review precondition → execution-card reference → the named rule. The entry retains responsibility for loading the reference and the batch-edit, applicability and premise guards; the reference gains the card-specific instructions.

| Before obligation | Old anchor | After anchor | Status | Proof |
| --- | --- | --- | --- | --- |
| Card structure and accountable owner | SKILL.md, execution-card section: For a 域卡/执行卡 | references/execution-card-patterns.md: For a 域卡/执行卡 | rehosted | Verbatim paragraph comparison |
| Remove only the designated card content; respect explicit user retention | SKILL.md: DROP | references/execution-card-patterns.md: DROP | rehosted | Verbatim paragraph comparison |
| Preserve decisions and critical constraints | SKILL.md: KEEP verbatim | references/execution-card-patterns.md: KEEP verbatim | rehosted | Verbatim paragraph comparison |
| Define goal, red line and acceptance once | SKILL.md: 目标/红线/验收 | references/execution-card-patterns.md: 目标/红线/验收 | rehosted | Verbatim paragraph comparison |
| Preserve owner and structure across sibling cards | SKILL.md: Cross-card consistency | references/execution-card-patterns.md: Cross-card consistency | rehosted | Verbatim paragraph comparison |
| Check each document before stripping or retitling; respect do-not-touch exclusions | SKILL.md: Global boilerplate-strip + retitle | SKILL.md: Global boilerplate-strip + retitle | unchanged | Verbatim entry comparison; available to non-card batch edits without loading the card reference |

The reference must match the original block after excluding the unchanged global batch-edit guard and changing the heading level. Restoring the original section prefix must reproduce the original entry byte for byte. Independent review and challenge must verify the governing chain; candidate-bound conclusion evidence is required before a PR. No row is accepted solely on this table's asserted destination. These static checks do not establish runtime reference loading or improved task quality.
