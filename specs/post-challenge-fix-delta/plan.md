# Post-challenge fix delta

## Problem

The daily review budget sent only a fix for a confirmed P0/P1 to a delta pass after the challenge. Every other post-challenge fix shipped with the agent's own test or source evidence and no external pass.

A tally over local review result files from the last 30 days measured how often later passes still find P0/P1. Results were grouped per change directory (12 passes or fewer), outside this repository, and clean passes were included. Ordering is by file time, so it is approximate.

| Pass | Passes | Passes with a P0/P1 |
| --- | --- | --- |
| 1 | 897 | 20% |
| 2 | 726 | 20% |
| 3 | 131 | 5% |
| 4 | 69 | 6% |
| 5 or later | 185 | 8% |

The 31 P0/P1 findings from pass 3 onward were read one by one:

- Most do not repeat an earlier finding of the same change: text similarity to earlier findings on the same file is low.
- Several are regressions that an earlier fix opened, for example a narrowed error condition that hid other error paths, or a removed assertion.
- About half come from work that carried a high-risk tag. About half come from untagged work, including one data-repair change.
- Severity is the reviewer's claim and was not verified.

## Causes

1. The delta trigger is the severity of the finding a fix addresses. The severity of the regression a fix can open does not follow it.
2. The budget is chosen by a recorded tag. A change of a high-risk shape with no recorded tag takes the daily budget. The router already requires shape-based classification, but nothing fires it where the budget is chosen.
3. The previous round set the budget from non-convergence observations without measuring late-pass yield.

## Change

- `development-completion.md` step 3: a change made after the challenge that step 2 exempts gets no reviewer call. Any other post-challenge change gets one delta pass whatever the severity of the finding it fixes. The fixes are batched into that pass, which is the last call.
- Step 4: before spending the daily budget, check the change against the router's objective high-risk change shapes. A matching change takes the checkpoint even when no tag was recorded.
- The pull-request hook reminder and the session-start line say the same.
- Per change this stays at most three external passes, so the cap from the previous round holds.

## Out of scope

Controller code, the router's tag list, the skill-extraction lane and design review are unchanged.

## Verification

- `test_extraction_review_gate.sh` pins the new obligations and rejects the old P0/P1-only clause. It fails on the base text and passes on the candidate.
- `test_remind_review_covers_head.sh` has two new probes plus a retired-phrase check. Three checks fail on the base hook; all 70 pass on the candidate.
- `make test`, the heavy lane and public sanitization run on the candidate.
