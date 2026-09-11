# 127 review-lane simplification: passes and dispositions

Each pass ran single-shot through `skills/skill-extraction-workflow/scripts/extraction_review_gate.sh`
with an OpenAI-family reviewer (the implementer is Anthropic-family). Controller results sit beside
this file.

## Pass 1 — review (`pass1-review.json`)

Four P2, no P0/P1.

| # | Finding | Disposition |
|---|---|---|
| 1 | The lane required a committed candidate before review while the core rules require passes before commit. | fixed — the lane runs on the candidate; a local unpushed checkpoint commit is now an explicit, narrow exception in `SKILL.md`. |
| 2 | The base-drift paragraph still said any target movement voids the review, contradicting the rebase rule. | fixed — it now defers to the drift handling below it. |
| 3 | The detach hook masked quotes line by line, so a multi-line commit message naming the word fired. | fixed — quotes are masked across lines with escapes honoured; two multi-line negatives and an escaped-quote negative added (both multi-line cases red against the previous hook). |
| 4 | The packet could not carry the historical rows or resolver context to verify the test claims. | accepted — deterministic-gate claims are verified by CI rerunning those gates (dual-track gate, reviewer verification scope). |

## Pass 2 — challenge, documentation partition (`pass2-challenge-docs.json`)

The candidate exceeded one 200,000-byte packet, so the challenge ran per partition (documentation, code).
Four P1.

| # | Finding | Disposition |
|---|---|---|
| 1 | The evidence-directory exemption let an executable probe changed after challenge land unreviewed. | fixed — only non-executable record files are exempt; scripts and register rows changed after a pass owe a delta pass. |
| 2 | The quickstart required committing review fixes before challenge, contradicting the core commit rule. | fixed — the local checkpoint-commit exception is stated once in `SKILL.md` and referenced from the quickstart, the mandatory table note and the R0 interim note. |
| 3 | A conflict-free rebase was exempt although upstream edits to the same file can change meaning. | fixed — a rebase is exempt only when path-disjoint from the candidate; otherwise the shared files get a delta pass. |
| 4 | Nothing mechanical detected a round that never recorded a pass. | fixed — `check_review_evidence_present.py` runs in CI on pull requests and refuses a change under `skills/` or `hooks/` with no conclusive review result (final form after pass 6, below). Presence only; forged results remain out of scope, as for the repository's other author-declared gates. |

## Pass 3 — challenge, code partition (`pass3-challenge-code.json`)

Three P1, one P2.

| # | Finding | Disposition |
|---|---|---|
| 1 | A file replaced by a symlink is a type change the gate's diff filter omitted. | fixed — no diff filter; symlink regression added (red against the filtered gate). |
| 2 | One passed wording-only review exempted the whole pull request from challenge. | fixed, then superseded by the deletion after pass 6. |
| 3 | The packet could not carry the ledger rows, resolver, controller and OpenCode context. | accepted — reviewer verification scope; CI reruns the deterministic gates. Third appearance of this class, all the same boundary. |
| 4 (P2) | `/usr/bin/nohup` and `nohup>log` launched without the advisory. | fixed — both forms fire; tests added. |

## Pass 4 — delta, documentation (`pass4-delta-docs.json`)

Two P1.

| # | Finding | Disposition |
|---|---|---|
| 1 | `SKILL.md` and the quickstart still exempted evidence files and register rows wholesale. | fixed — both now exempt only non-executable record files. |
| 2 | The documentation packet could not show the checker or its CI wiring. | covered — the checker was reviewed in the code partition (pass 3 found items 1 and 2 in it). |

## Pass 5 — delta over both partitions (`pass5-delta.json`)

One P1: after a passed wording-only review, a later edit of the same `SKILL.md` kept the waiver.
Fixed by re-verifying the recorded proof against the whole pull request (same-file and frontmatter regressions, red against the previous rule).

## Pass 6 — delta, presence gate (`pass6-delta-code.json`)

Two P1: rewriting the frontmatter delimiter defeated the re-verification, and the packet lacked the proof producer's contract.
This was the second delta pass on the code partition with a P0/P1 still open, and the fourth distinct break of the same wording-only waiver.
Disposition: **deleted** — the gate no longer waives or requires a challenge; it requires at least one conclusive review result, and the challenge obligation stays in the review-lane rule. The challenge-presence requirement and its waiver were both introduced in this round, so removing them is an exact rollback of that feature to the base state; the remaining review-presence check is the part reviewed since pass 3.

## Pass 7 — delta, documentation (`pass7-delta-docs.json`)

Two P1.

| # | Finding | Disposition |
|---|---|---|
| 1 | "A pure removal owes no further pass" let an agent delete a safety condition after two delta passes with no review. | fixed — only an exact rollback of the change to a previously accepted state, with its dependent changes, owes no further pass; any other deletion leaves the pull request blocked. |
| 2 | The documentation packet could not show the checker, its CI call or its tests. | accepted — reviewer verification scope; the checker was reviewed in the code partition. Fourth appearance of this boundary class. |

## Pass 8 — delta, the rollback sentence (`pass8-delta-docs.json`)

One P1, evidence class: the packet carries no regression distinguishing an exact rollback from a guard-only deletion.
Disposition: accepted — the reviewer did not report the original item open; the sentence is a procedural rule with no executable part, so there is nothing to regress beyond the rule text (reviewer verification scope). This was the second delta pass on that fix; the review sequence ends here.

## Pass 9 — delta, docstring (`pass9-delta-code.json`)

Two backticks removed around a path template in the presence gate's docstring so the spec-citation check does not read it as a real path. Passed, no findings.

## Summary

Nine external passes: one review, a challenge per partition (the candidate exceeded one packet), and six delta passes over post-review changes.
No P0 was raised. Every P1 is fixed, deleted by exact rollback, or accepted as the packet-verifiability boundary with its reason above.
