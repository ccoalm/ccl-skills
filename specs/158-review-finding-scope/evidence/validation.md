# Validation evidence

## Source review (sanitized)

The registration came from the retrospective behind round 156: about nine
interactive sessions in a four-day window where users corrected over-grown work,
most of them Codex threads, two Claude Code sessions. The correction turns and
the 10–20 turns before them were re-read from the private per-session tables and
condensed transcripts. Shapes, by what prompted the growth:

| Prompt for the growth | Sessions | Example correction (paraphrased) |
| --- | --- | --- |
| Agent's own defensive design (switches, manual review steps, permissions, staged rollout, wide compatibility layers) | ~7 | "another switch, is it necessary?", "this is getting too heavy" |
| Review output folded into the work (plan review approving an over-design; review questions written as launch preconditions) | 2 | "this cannot ship as a hotfix", "you over-designed it" |

The per-session tables stay in the maintainer's private archive.

## Measurements

All runs use `claude --print` (Opus 5.5) or `codex exec` (the configured Codex
model) with tools and hooks disabled in an empty directory.

### Registered forms that did not reproduce (controls)

- `triage_replay.py`: a findings result arrives mid-hotfix with an introduced
  defect, a duplicate-submit risk in an untouched file and a switch suggestion.
  Every arm listed only the introduced defect for this change: clean (Claude 6/6,
  Codex 4/4), with accumulated scope momentum (Claude 6/6), and with the current
  review-reception rules loaded (Claude 6/6, Codex 4/4). The candidate triage
  text changed nothing. An earlier grader that offered `record` as an answer was
  replaced because it primed the answer.
- `reviewer_scope_replay.py`: a staged review of an over-grown hotfix diff whose
  intent states the narrow request. The current concern text already produced
  scope findings in 4/4 runs; the amended text did too. Re-measured with the
  landed text after one decorator line in the synthetic diff was rewritten for
  the sanitization scanner: base 4/4, new text 4/4.

### Plan review against the requester's words (RED)

`scope_anchor_replay.py`, neutral domain (report export). Counts are runs, read
by eye; the regex in the runner is a recall aid. `scope_anchor_runs.json` holds
every run's findings, its classification and the concern text each arm used;
arms C and D ran the landed wording.

| Arm | Gate questioned against the request | Admin override or staged rollout called unrequested |
| --- | --- | --- |
| A: current concern text, restatement only | Claude 0/6, Codex 0/3 | Claude 0/6, Codex 0/3 |
| B: current text, intent quotes the requester | Claude 6/6 | Claude 3/6 |
| C: new text, intent quotes the requester | Claude 6/6, Codex 3/3 | Claude 6/6, Codex 3/3 |
| D: new text, restatement only | Claude 0/6 | Claude 6/6 |

In arm A every finding that touched the gate hardened it: bound the override
with audit and expiry, gate manual downloads too, add enforcement criteria. An
earlier run in the source domain, kept out of the repository, gave the same
pattern (A 0/6 and 0/3; B 6/6; C 6/6 and 3/3).

### Controls

- Matched plan (`--matched`), a plan that does exactly what the request asks:
  with the new text and the requester's words no run raised a scope finding
  (Claude 0/6, Codex 0/3). One Codex run suggested failing the export when the
  pre-export check cannot fix a mismatch, a blocking step the request leaves
  open: the lens does not stop every hardening suggestion. The plan's first
  version also had a weekly review of the differences, which the request does
  not ask for; Codex flagged it in 2/3 runs, and it was removed.
- Requested fix (`--requested-fix`), a request to fix duplicate charges caused
  by export retries and a plan that fixes exactly that: no run called the fix
  droppable, under the first wording or the landed one (Claude 0/6 and 0/6,
  Codex 0/3 and 0/3). Every finding was about the fix's own correctness.

### Controller tests

`test_review_gate.sh` checks that the build profile's `compatibility`
description asks for the scope check against the requester's words with the
pre-existing-risk qualifier; the base controller's text lacks it (build and
release), and the concern IDs are unchanged. A second check runs a
derived-default review with `--focus` and finds the words in the reviewer
profile; a copy of the controller that drops the focus outside challenge mode
fails that check and no other. Full suite: `review_gate_tests_ok`.

## Example-domain preselection

Changed examples: the scenarios in three replay runners, one test string and
one prompt-template slot. Selected domain: a report-export service. The source
sessions' product domain was rejected; the first draft of
`scope_anchor_replay.py` used it and was rewritten before any commit and
re-measured.

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| code-review (controller) | firing point | updated | `compatibility` concern text in `review_gate.py`; tests in `test_review_gate.sh` |
| code-review (docs) | how the packet is built | updated | `development-completion.md`, `staged-review-contract.md`, `manual-invocation-and-prompts.md` |
| product-rd-workflow | design review packet | updated | `design-review-gate-mechanics.md` |
| product-rd-workflow review reception | finding triage | unchanged | partition-rule replay showed no effect |
| defect-diagnosis | hotfix owner | unchanged | its reviews go through code-review, which now carries the words |
| session policy | always-on | unchanged | "complete what is necessary, do not widen scope" exists; the firing point is the review |
| skill-extraction-workflow | this workflow | updated | register rows only; the RCA rule for this class stays with the review owners |
| testing-strategy | test layer | unchanged | no new layer rule |

## Self-review

- Acceptance: plan table rows 1–7.
- Changed-file scope: `git diff --stat origin/main` for this branch.
- Failure paths: a reviewer could call a needed mechanism unrequested, or a
  requested fix of an older defect droppable. Neither happened in the matched
  and requested-fix controls, and dispositions stay with the implementer under
  the existing reception rules. Without the requester's words the new text
  still flags mechanisms beyond the restatement (arm D) but cannot question the
  restated goal itself.
- Privacy: the quote travels in the plan's intent or in `--focus`, and both
  are in the frozen review profile. Before a non-Claude reviewer sees it, the
  controller scans the profile for credential-shaped secrets and blocks egress
  on a hit unless `--allow-fallback-egress` is passed. Other confidential
  detail in a request (people, customers, unannounced plans) is not
  machine-checked: sanitizing the quote is the caller's obligation, as for the
  rest of the packet.
- Residual risks: the words reach the reviewer only when the implementer quotes
  them, and the controller cannot verify that a quote is verbatim. One
  synthetic plan shape was measured per control. A reviewer can still suggest
  hardening the request leaves open (one matched-plan Codex run). The agent's
  own design-time additions with no review in the loop are not addressed here.
