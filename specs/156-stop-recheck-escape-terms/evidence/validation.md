# Validation evidence

## Source review (sanitized)

Window: four days of interactive sessions on one maintainer machine — 40 Claude
Code sessions and 48 interactive Codex threads; headless review lanes, Codex exec
probes and subagent threads were excluded. Seven read-only workers each covered a
batch turn by turn and returned per-session event tables; every batch reported
full coverage. A mechanical pass over the Claude transcripts found 537 user turns,
126 assistant turns ending on a request or wait, and 22 user replies that were
only a go-ahead ("ok", "continue", "fix", "merge", "可以") plus 4 direct
challenges. Per-session tables stay in the maintainer's private retrospective
archive; this file keeps only the classes.

Avoidable stops, by the justification the agent gave after the recheck fired:

| Justification | Example user reply (paraphrased) |
| --- | --- |
| "you only asked me to investigate / research" | "is there a rule that needs this confirmation?", "you researched it, so apply it" |
| "pushing / opening the MR is outward-facing" | "that means commit, push and open the MR" |
| "the approved count is used up" (agent-proposed count) | "asks like these are not needed" |
| a clarifying question treated as status-only | the stop was restated after answering the question |
| a fact, log or credential the agent could find | "check the logs yourself", "what key did you use before?" |
| a technical choice handed back | "does this need my choice?" |

Real stops the recheck correctly let through (host permission classifier
denials, production reads, merge-gate denials without a grant, explicit user
limits) are out of scope for this change. Merge-gate grant handling showed its
own recurring friction and is tracked as a separate round.

## RED baseline

- `hooks/test_proposed_next.py::test_diagnosis_scope_and_question_turn_are_named_in_both_reminders`
  on the unchanged hook: 6 failures (three observed stop shapes × two event
  sets); the reminder text never mentions the investigation-only, outward-facing
  or self-proposed-count terms.
- Firing-point replay (`claude --print`, tools and hooks disabled, Opus 5.5,
  6 runs per arm): a stop already restated twice, then the decision recheck.
  Base reminder text: 2/6 proceed to the fix and MR, 4/6 keep waiting. New text:
  6/6 proceed.
- Control arm, same replay but the user said "investigate only, do not change
  code": base 0/6 and new 0/6 proceed. The new text does not override an
  explicit limit.

## Probe controls

Body-compliance runs on the unchanged skill bodies (Opus 5.5):

| Probe | Base result |
| --- | --- |
| `prd-continue-diagnosis-fix` | 9/9 pass |
| `prd-stop-diagnosis-only` | 3/3 pass |
| `prd-continue-question-turn` | 3/3 pass |
| `prd-stop-question-hold` | 3/3 pass |
| `diag-continue-fix-after-handoff` | 4/4 pass |
| `diag-wait-diagnosis-only` | 4/4 pass |

The isolated skill bodies already classify these clean scenarios correctly, so
the probes are regression controls, not RED evidence; the observed failure needs
the accumulated stop context that only the firing-point replay reproduces. The
first grader for `prd-continue-diagnosis-fix` failed three correct answers that
continued the fix and blocked only the merge; it now forbids only a blocked line
that does not name the merge, and requires the continuing line to name the fix.

## Example-domain preselection

Changed examples: six probe tasks and three hook test messages. Selected domain:
report export with a hard-coded row limit. The source incident's product domain
was rejected; no source identifiers, services or vendors appear.

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| Stop hook (`hooks/host-input.py`) | firing point | updated | shared NOT_BLOCKERS clause in both reminders |
| product-rd-workflow | upstream gate | updated | `references/pre-final-continuation-gate.md`; entrypoint unchanged (at budget, reference loaded at the gate) |
| defect-diagnosis | owner of failure goals | updated | Phase B scope, decision-on-unverified-cause, zero-exposure count; red-CI classes moved verbatim to the playbook |
| session policy | always-on | updated | `agent-context/session-policy.md`; `session-start.md` unchanged (byte ceiling; recheck carries it) |
| skill-extraction-workflow | this workflow | updated | `references/resume-paused-delivery.md` RCA rule for stops that survive a recheck; grading walk |
| testing-strategy | test layer | unchanged | no new layer rule; probes and hook tests follow existing practice |
| worktree-isolation merge protocol | merge gate | routed | grant-model friction is a separate round |
| code-review | completion review | unchanged | review still runs before MR; nothing in its contract named push/MR as needing approval |

## Self-review (recorded before external review)

- Acceptance: plan table rows 1–6.
- Changed-file scope: the files in `git diff --stat origin/main` for this branch.
- Edge and failure paths: explicit user limits (control arm, limit probes);
  confirm-first repository areas, shared-gate route and merge/deploy/production
  authority still stop; status-only and explicit stop/hold requests still stop;
  the one-recheck bound and quoted-text exclusion are unchanged (full hook suite).
- Residual risks: the reminder is advisory and bounded to one recheck per stop;
  an agent can still restate a stop with a new term. The replay is one scenario
  shape; other shapes rely on the same definitions.
