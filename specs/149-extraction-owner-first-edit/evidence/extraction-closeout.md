# Extraction closeout

## Charter

Recorded in per-host scratch before any source read or edit for this round.
Summary of its cells:

| Field | Answer |
| --- | --- |
| Purpose | Prevent (1) a shared gate declaring blocking or completion semantics with no enforcing firing point while its fixture pins the defect, and (2) the extraction gate being reached only at Stop, after commit, push and pull request. |
| Scope | The source-edit checkpoint and the extraction stop backstop; `skill-extraction-workflow` references; `testing-strategy` checked for class 1. Out: the coverage reminder (preceding round), making reminders blocking, cleanup-reminder masking. |
| Depth | Targeted check plus tooling change. |
| Result classification | failure/correction; both failures observed in the preceding round. |
| Matching analysis | RCA below. |
| Failure mode or success boundary | Appending duplicate prose; an over-broad hook; claiming the class closed without a RED baseline. |
| Lifecycle impact | Implementation, testing, review/landing readiness, iteration feedback. |
| Evidence plan | Preceding round's artifacts first, then the stop hook, checkpoint, their suites, `firing-point-placement.md`, testing-strategy's assertion rules. No state-of-the-art claim. |
| Completion standard | RED baselines and applied mutations for each new predicate, clean checker with base, full lanes, extraction-lane review and challenge, register row last. |

The repository plan `specs/149-extraction-owner-first-edit/plan.md` was written
after the first hook commit, not before it. The shared-gate classification
requires it before editing; this round missed that step.

## RCA

Class 2, extraction gate reached only at Stop:

| Factor | Category | Weight |
| --- | --- | --- |
| Only the stop backstop knew a target was a ccl-skills shared surface | missing mechanical control at the transition | primary |
| The first source-edit checkpoint gave a generic reason that a debugging owner satisfied | missing feedback (name→invoke) | primary, recognition-dependent |
| Markdown was not a source extension, so skill-text edits never reached the checkpoint | detection gap | enabling |
| Both hooks probed only the first `skills/`, `hooks/` or `scripts/` component (found by review) | latent scope defect | enabling |

Class 1, declared-but-unenforced gate with a fixture pinning the defect:
`testing-strategy` already requires a killing mutation per named property and
a pin per obligation sentence. The rule existed, observed-failure is yes, and
no deterministic firing point with an acceptable false-positive rate was
found. The instance is closed by the preceding round; the class stays pending.

## Target-output map

| Owner | Direction | Status | File or reason |
| --- | --- | --- | --- |
| plugin hook surface | shared behavior | updated | `hooks/skill-loading.py`, `hooks/skill-extraction-gate-stop.sh`, both suites |
| `skill-extraction-workflow` | this workflow | updated | `references/firing-point-placement.md`; register row |
| `testing-strategy` | downstream | pending | Class 1: rule present, no mechanical firing path found |
| `code-review` | upstream | unchanged | Not touched |
| `product-rd-workflow` | coordinator | unchanged | Firing point moved into the hook instead of routing text |
| `feature-risk-router` | risk | unchanged | `shared-gate` tag applied |

## Gates

| Gate | State | Evidence |
| --- | --- | --- |
| Round opened with a workflow invocation | met | Invoked before the charter |
| Charter before source reads and edits | met | Scratch charter written first |
| Repository plan before editing | missed | Written after `5c38ec4` |
| R0 | met | `ccl_skill_check_clean_ok`, `r0_status=private-ok`; one private-alias hit on a test name was renamed before landing |
| Behavioral evidence | met | `RED-baseline` register row; failing-first cases; applied mutations |
| Review | met | First pass on `f76e966`: 2 P2, both reproduced and fixed. Renewed pass on `f3bc394`: passed, 0 findings |
| Challenge | met | Pass on `53d9c50`: 2 P2 wording findings, both fixed in `f3bc394` |
| Impact-chain row | met | Owner-scoped firing path resolved on the committed diff |

## Pending

- Class 1 prevention for `testing-strategy`.
- Bash-written edits still reach only the Stop backstop.
