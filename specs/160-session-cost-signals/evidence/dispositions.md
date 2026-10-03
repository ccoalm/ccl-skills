# 160 review dispositions

Passes run through `extraction_review_gate.sh` on the candidate based on
`origin/main`. Each pass names the commit it reviewed; results are kept beside
this file.
## Pass 1 — review (kimi), base `origin/main`, reviewed commit `a8c8c11`: 2 × P2

Record: `pass1-review.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | No adversarial challenge yet over the two hook diffs, which `hooks/AGENTS.md` requires before landing | no change: the challenge is the round's second pass and covers both hook diffs (pass 2 below) | — |
| 2 | P2 | A user prompt that merely starts with the envelope loses the entry | fixed: the skip needs the whole prompt to be one envelope (starts with `<task-notification>` and ends with `</task-notification>`); all 354 host notification prompts in the sampled transcripts have that shape. A test keeps the entry for an envelope followed by a question | `hooks/task-entry.sh`, `hooks/test_task_entry.py` |
