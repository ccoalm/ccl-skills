# Extraction closeout

## Charter

Recorded after the code, test and register commits, not before them. The
charter-before-editing red line was not met for this round; the cells below
reconstruct what the round actually did and do not claim otherwise.

| Field | Answer |
| --- | --- |
| Purpose | Prevent a pull or merge request from being opened, readied or merged with review findings outstanding while the coverage reminder stays silent. |
| Scope | `hooks/remind-review-covers-head.sh`, `skills/code-review/scripts/review_gate.py`, their suites, one impact-chain row. Out of scope: the post-merge cleanup reminder's quoted-command masking; making any reminder blocking; wording in `code-review/references/development-completion.md`. No `covered-through` watermark applies (single defect, not an iterative program). |
| Depth | Generator/tooling change: a deterministic hook predicate and one controller success path. |
| Result classification | failure/correction. Observation: in a product repository a review chain ended `findings_pending`, the candidate was merged, and the reminder gave no signal that a findings receipt would have been quiet; a paired fixture reproduced silence for `findings` and `passed` alike. |
| Matching analysis | RCA below. |
| Failure mode or success boundary | Weak work would patch only the hook, leaving a correctly disposed chain (closed through `--mode complete`) with a `findings` receipt that reminds forever and trains agents to ignore the reminder. |
| Lifecycle impact | Verification and review/landing readiness. No product intent, design, launch or onboarding change. Use without source access: reminder text now names the receipt path and recorded status. |
| Evidence plan | Produced artifacts first: the candidate diff and `specs/148-review-coverage-findings/`. Then the hook and controller source at `origin/dev`, the existing hook and controller suites, `development-completion.md`, and the hook family (17 hooks surveyed for any disposition check). Correction turns are not used as evidence of what went right. |
| Completion standard | Failing-first regressions on both surfaces, killing mutations applied on copies, full lanes, one independent review and one adversarial challenge through the extraction lane, CI green. |

## RCA

Widened across categories, each tested counterfactually:

| Factor | Category | Would the failure still happen without it? | Weight |
| --- | --- | --- | --- |
| Quiet branches never read `status` | missing mechanical control | No: with a status predicate a findings receipt reminds | primary |
| `--mode complete` never wrote a receipt | latent authored-earlier condition | Yes for this merge; but fixing only the hook turns it into a permanent false reminder | enabling |
| Suite fixture hard-coded `status: findings` and asserted quiet | detection gap | The defect was pinned as expected behavior, so no suite run could turn red | secondary control failed |
| `development-completion.md` states unresolved P0/P1 prevent readiness with no firing point | missing feedback | Rule existed and did not fire; the firing point is the hook | enabling |
| No-receipt reminder did not name the path it checked | missing feedback | An agent holding results elsewhere could read "no record" as a path mismatch; probabilistic, one trace | hypothesis |

Prevention is the firing mechanism on the failure class (status predicate, completion receipt, fixtures that vary status), not agent diligence.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| `code-review` | upstream | updated | `scripts/review_gate.py`, `scripts/test_review_gate.sh`; register row |
| plugin hook surface | shared behavior | updated | `hooks/remind-review-covers-head.sh`, `hooks/test_remind_review_covers_head.sh` |
| `testing-strategy` | downstream | unchanged | Mutation and failing-first rules already require what was done; no gap observed |
| `product-rd-workflow` | coordinator | unchanged | Shared-gate classification applied as written (`plan.md`) |
| `feature-risk-router` | risk | unchanged | `shared-gate` tag applied as written |
| `defect-diagnosis` | executor | unchanged | Paired-control and failing-first rules applied as written |
| `worktree-isolation` | sibling | not-applicable | No isolation behavior involved |
| `skill-extraction-workflow` | this workflow | pending | Two failure-class exposures below owe a prevention point here; the user's request covered only the defect fix, so the edit waits for that authority |

## Gates

| Gate | State | Evidence |
| --- | --- | --- |
| Charter before editing | missed | Recorded after commits (above) |
| Round opened with a workflow invocation | missed | Invoked after the pull request, prompted by the extraction-gate stop backstop |
| Result classification and RCA | met after the fact | Sections above |
| R0 | met | `check-ccl-skills.sh` with base `origin/dev`: `r0_status=private-ok`, `ccl_skill_check_clean_ok` |
| Behavioral evidence | met | `RED-baseline` in the register row; walks in `verification.md` |
| Independent review and challenge | see below | First passes ran through `code-review/scripts/review_gate.sh` as a tracked chain, not the extraction lane's single-shot `scripts/extraction_review_gate.sh`; same controller, candidate and owners, but not the prescribed entry. Extraction-lane passes are recorded separately |
| Impact-chain row | met | Owner-scoped firing path resolved on the committed diff |

## Pending

- Workflow prevention for a gate that declared a block (`completion_gated`, `blocks`) with no mechanism enforcing it, and for a suite fixture that encoded the defect as expected behavior.
- Workflow prevention for this round's under-invocation: the extraction-gate backstop fires at Stop, after commit, push and pull request, which is past the transition where it could change the round.
- Human decision on accepting this round with the charter recorded late.
