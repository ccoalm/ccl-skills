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
model) with tools and hooks disabled in an empty directory. The scope-anchor
and reviewer-scope counts come from reading every run by hand, against rules
fixed before the reading; their per-run records hold each run's complete
findings, the classification and the index of each finding it rests on. The
runners' regex counts are recall aids only. A first version of this record took
those counts from the regex, which had missed phrasings and counted hardening
options; they were corrected after the delta review.

### Registered forms that did not reproduce (controls)

- `triage_replay.py`: a findings result arrives mid-hotfix with an introduced
  defect, a duplicate-submit risk in an untouched file and a switch suggestion.
  Every arm listed only the introduced defect for this change: clean (Claude 6/6,
  Codex 4/4), with accumulated scope momentum (Claude 6/6), and with the current
  review-reception rules loaded (Claude 6/6, Codex 4/4). The candidate triage
  text changed nothing. The grader reads a `changes:` marker the model emits; an
  earlier grader that offered `record` as an answer was replaced because it
  primed the answer.
- `reviewer_scope_replay.py`: a staged review of an over-grown hotfix diff whose
  intent states the narrow request, rerun with the landed text and raw capture
  (`reviewer_scope_runs.json`). Both texts flagged the retry, manual-review,
  admin and legacy-reader changes as outside the hotfix in 4/4 runs. The
  configuration switch was called unrequested in 0/4 runs with the current text
  and 4/4 with the new text.

### Plan review against the requester's words (RED)

`scope_anchor_replay.py`, neutral domain (report export); per-run record
`scope_anchor_runs.json`. Arms C and D ran the landed wording.

| Arm | Gate questioned against the request | Admin override or staged rollout called unrequested |
| --- | --- | --- |
| A: current concern text, restatement only | Claude 0/6, Codex 0/3 | Claude 0/6, Codex 0/3 |
| B: current text, intent quotes the requester | Claude 6/6 | Claude 0/6 |
| C: new text, intent quotes the requester | Claude 6/6, Codex 3/3 | Claude 6/6, Codex 3/3 |
| D: new text, restatement only | Claude 0/6 | Claude 6/6 |

In arm A every finding that touched the gate hardened it: bound the override
with audit and expiry, gate manual downloads too, add enforcement criteria. In
arm B three runs offered removing the override, but as a way to harden the
gate, not because the request did not ask for it.

### Controls

- Matched plan (`--matched`), a plan that does exactly what the request asks:
  with the new text and the requester's words no run raised a scope finding
  (Claude 0/6, Codex 0/3). One Codex run suggested failing the export when the
  pre-export check cannot fix a mismatch, a blocking step the request leaves
  open: the lens does not stop every hardening suggestion. The plan's first
  version also had a weekly review of the differences, which the request does
  not ask for; reviewers called it unrequested in Claude 5/6 and Codex 3/3
  runs, and it was removed. On that version, one Claude run asked for a subset
  rollout and two Codex runs for failing the export.
- Requested fix (`--requested-fix`), a request to fix duplicate charges caused
  by export retries and a plan that fixes exactly that: no run called the fix
  droppable, under the first wording or the landed one (Claude 0/6 and 0/6,
  Codex 0/3 and 0/3). Every finding was about the fix's own correctness; several
  asked to make the server enforce the key instead of the query-then-resubmit
  step, which strengthens the fix rather than dropping it.

### Controller tests

`test_review_gate.sh` checks that the build profile's `compatibility`
description asks for the scope check against the requester's words with the
pre-existing-risk qualifier. The check fails on the base controller and on the
first-round text, and the concern IDs are unchanged. A derived-default review
with `--focus` carries the words in the reviewer profile; a fallback reviewer
gets the same profile file; a credential-shaped `--focus` value blocks
non-Claude egress without approval. A controller copy that drops the focus
outside challenge mode fails those three checks and no other; a copy that skips
the profile's secret scan fails the focus egress check and the existing
plan-secret check and no other. Full suite: `review_gate_tests_ok`.

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

- Acceptance: plan table rows 1–8.
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
  on a hit unless `--allow-fallback-egress` is passed; the controller tests
  cover both routes. Other confidential detail in a request (people, customers,
  unannounced plans) is not machine-checked: sanitizing the quote is the
  caller's obligation, as for the rest of the packet.
- Delivery to every reviewer: the controller writes one frozen profile file and
  passes it to each client; the Claude, Kimi, Codex and OpenCode wrappers embed
  the whole file in their prompts, and a test shows a fallback reviewer
  receiving the same file.
- Residual risks: the words reach the reviewer only when the implementer quotes
  them, and the controller cannot verify that a quote is verbatim. One
  synthetic plan shape was measured per control. A reviewer can still suggest
  hardening the request leaves open (matched-plan runs above). The agent's own
  design-time additions with no review in the loop are not addressed here.
