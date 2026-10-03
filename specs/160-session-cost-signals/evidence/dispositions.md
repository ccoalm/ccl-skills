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

## Pass 2 — challenge (codex), base `origin/main`, reviewed commit `571cd80`: 6 × P2

Focus: whether the context notice can reach the model, block, repeat or misread
a transcript; whether the task-entry skip can fire on a real user prompt or
lose the entry on bad input; whether the receipt counter can be forged, raced or
reset, or let the checkpoint waive a requirement; anything added beyond the
requester's words. Record: `pass2-challenge.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | A prior receipt nested deeply enough to raise `RecursionError` escapes the corrupt-receipt fallback | fixed: treated as an invalid receipt; the counting unit fails on the previous controller | `review_gate.py`, `test_review_gate.sh` |
| 2 | P2 | Deeply nested hook input raises `RecursionError` and loses the entry | fixed: unreadable input keeps the full entry; a 500,000-deep array fails the previous script with a traceback | `task-entry.sh`, `test_task_entry.py` |
| 3 | P2 | Two envelopes with a user request between them pass the prefix/suffix check | fixed: the envelope must be exactly one; all 567 sampled host notification prompts hold one | `task-entry.sh`, `test_task_entry.py` |
| 4 | P2 | Overlapping completions can both read N and write N + 1 | fixed: the read-increment-replace holds a lock on the receipt directory; without it 24 overlapping writers recorded 4 to 7 runs in three trials | `review_gate.py`, `test_review_gate.sh` |
| 5 | P2 | Once-per-band depends on the state helper; without it the notice would repeat | fixed: the context notice stays quiet when the helper or its state is unavailable; other notices keep showing | `host-input.py`, `test_proposed_next.py` |
| 6 | P2 | The review plan's acceptance still named the withdrawn session-history reference | fixed in the review plan; the reference stays withdrawn | review plan (outside the tree) |

Change made alongside the pass-2 fixes after a requester question about effect:
a notification turn keeps the skill-loading and unfinished-work boundary (it
appears nowhere else after compaction) and drops only the routing list, which
SessionStart keeps in context.

## Pass 3 — delta review (codex), base `571cd80`, reviewed commit `f6dc5ec`: 3 × P2

Record: `pass3-delta.json`.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P2 | The delta packet holds only the follow-up commits, so acceptance about code outside them cannot be checked from it | no change: a delta pass covers the commits after the full passes; the whole change was covered by pass 1 (review) and pass 2 (challenge) | — |
| 2 | P2 | The overlapping-writer check proves the lock only when the writers happen to overlap | fixed in two steps; the second follows pass 4 finding 1 | `test_review_gate.sh` |
| 3 | P2 | The validation notes carry no results for the current candidate | fixed: the validation notes list the commands run on the final candidate, their results and what was not run | `validation.md` |

## Pass 4 — delta review (codex), base `f6dc5ec`, reviewed commit `5c84b38`: 1 × P1, 3 × P2

Record: `pass4-delta.json`. The commits under review added the version for the npm release and the first rewrite of the lock check.

| # | Sev | Finding | Disposition | Where |
| --- | --- | --- | --- | --- |
| 1 | P1 | The writer can be paused after signalling that it started and before it reaches the lock; past the one-second wait both mutants pass | fixed: no wait decides the result. The writer signals from inside its own exclusive lock call on the receipt directory, and the holder rewrites the count only after that signal; a missing lock, a shared lock or a lock on another object never signals, and a read before the lock increments the stale value. Same class as pass 3 finding 2; the timing dependence is removed rather than shortened | `test_review_gate.sh` |
| 2 | P2 | An error while rewriting the receipt skips unlock and cleanup | fixed: unlock and writer cleanup run in `finally` | `test_review_gate.sh` |
| 3 | P2 | The join after kill has no bound | fixed: the writer is a daemon, the join after kill is bounded, and an unreaped writer ends the check with a failure | `test_review_gate.sh` |
| 4 | P2 | No current-candidate results for the full lane, package and shared-skill checks | fixed with pass 3 finding 3 | `validation.md` |
