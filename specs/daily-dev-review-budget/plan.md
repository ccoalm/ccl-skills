# Daily development review budget

Daily development with these skills runs a fresh full review after every change made after the last review, including a test line, a doc line or a resolved conflict. Five reruns were only a progress checkpoint, not a limit, so one change could pass through many review rounds. Local tests already had a narrowest-evidence rule, but the completion walk did not point to it. This round sets the order and budget for daily development. One review comes first. After its fixes, one challenge runs on the fixed candidate. Any change after that is disposed of by the agent with test or source evidence, not sent back for review. High-risk work and the skill-extraction lane keep their existing gates. Design and plan review are unchanged.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Cut review and test toil in daily development without letting an untested or unreviewed P0/P1 reach a ready report. |
| Scope | `code-review/references/development-completion.md` (steps 2–4, invoke paragraph, test-selection pointer, checkpoint scope), `manual-invocation-and-prompts.md` depth rule, `hooks/remind-review-covers-head.sh` reminder text, `agent-context/session-start.md` completion line, the pinning tests. Out of scope: the skill-extraction lane's delta passes, design/plan review, `feature-risk-router` high-risk gates, controller code (`review_gate.py` counting stays as is). No iterative-program watermark applies. |
| Depth | Rule text plus firing-point text (hook, always-on line); no controller change. |
| Result classification | Failure/correction: the user found daily development too slow ("这效率非常低") and said design documents still need review. They also said challenge must stay but may run after the review instead of on the same candidate, and asked how local full tests are decided. |
| Matching analysis | RCA below. The prevention moves both the rule and its two firing points (PR hook reminder, always-on line). Changing either one alone leaves the other firing the old instruction. |
| Failure boundary | A confirmed P0/P1 must not reach a ready report silently. Past the budget, a fix needs a test that fails before and passes after, a source refutation, or a reason. Without one it is reported as blocking. The budget must not turn into a stop-and-ask, which is why a ceiling was retired before. High-risk tagged work keeps the continuation checkpoint. |
| Lifecycle impact | Implementation completion and review (rule, hook), testing (selection pointer; `testing-strategy` text unchanged), always-on routing line. Product intent, design review, release and onboarding: unchanged. |
| Evidence plan | Local Claude/Codex transcripts from the last 30 days, measured by script (review calls per change, wall-time share, full vs focused test runs, what triggered renewed review); the 2026-10-03 cost retro (38% of this repo's session cost on review/test/polling/CI; 13–49 review rounds per change); current rule text. External grounding: not-applicable. This is an internal operating budget with no state-of-the-art claim. |
| Completion standard | RED on base / GREEN on candidate for the rule pins and the hook probes; `make test`; deep self-review; one review and one challenge; PR to main. |

## RCA

1. Rule: step 2 invalidated review on any byte change, and step 3 required "a fresh full run". `manual-invocation-and-prompts.md` repeated it ("any changed candidate takes a fresh full run").
2. No ceiling: five renewed runs triggered only a checkpoint, and the necessary review continued after it.
3. Firing point repeated the rule: the PR hook told the agent that any change, including tests, docs and changelog, must be re-reviewed up to five times.
4. Always-on line: "re-review later changes before PR/completion".
5. Test selection: `testing-strategy` already limits local runs to the narrowest evidence. The completion walk only said "affected verification" and did not link that section.

Counterfactual: changing only the rule leaves the hook and the always-on line issuing the old instruction at every PR and every session, and the reverse leaves the rule. All four surfaces change together.

## Owner map

| Owner | Direction | Status | Reason |
| --- | --- | --- | --- |
| code-review | self | updated | Rule, depth pointer. |
| hooks (plugin) | downstream firing point | updated | Reminder text and probes. |
| agent-context session-start | always-on | updated | Completion line, same byte budget. |
| testing-strategy | sibling | unchanged | Local Evidence Selection already says narrowest checks; now linked from the walk. |
| product-rd-workflow | upstream | unchanged | Design-review gate untouched by request; its verification gate routes to code-review. |
| feature-risk-router | upstream | unchanged | High-risk tags keep the continuation checkpoint. |
| skill-extraction-workflow | sibling lane | unchanged | Its delta passes stay; the pinning test lives in its script and gains the daily-budget pins. |
| user global AGENTS.md (private, outside repo) | always-on | updated | Items 4–5 aligned. |

## Evidence (local sessions, last 30 days)

Measured by script over local Claude and Codex transcripts (private archive, recomputable). "Change" is approximated by session. Review calls starting within 300 s of each other are counted as one pass. Daily development in other repositories:

| Metric | Value |
| --- | --- |
| Interactive dev sessions with an edit / with review | 219 / 180 |
| Review passes per session, median / p90 / max | 3 / 11 / 35 |
| Sessions with 3+ passes | 111 |
| Review wall share of active time, by passes 1 / 2 / 3–5 / 6+ | 1.3% / 2.5% / 6.0% / 11.9% |
| Edits between consecutive passes: code / test-only / doc-only / test+doc | 59% / 17% / 16% / 9% |
| Full local test runs, share of active time | 1.0% (focused 2.4%) |

- **Cost of extra passes:** review time grows with the pass count. The two-pass budget removes the 3+ pass tail.
- **What triggered renewed review:** a third of renewed passes followed test-only or doc-only edits. The exemption in step 2 covers these.
- **Local full test runs in daily development:** a minor cost. The test-selection pointer prevents drift, and no test rule changes.
- **Reruns with no recorded edit:** many passes followed no recorded edit. These are retries, reruns or shell edits. The existing "never rerun an unchanged candidate for zero findings" rule stays.
- **This repository (out of scope here):** `make test` took 28.7% of active time, with a median of 22 minutes per run, and was rerun in each review loop. This is noted as a follow-up for the repository contract.
- **Independent recount:** a separate regex over the same raw records gave higher counts in the same direction, so the figures above are a lower bound.
