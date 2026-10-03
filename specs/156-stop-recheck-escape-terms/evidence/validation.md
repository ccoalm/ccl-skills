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
limits) are out of scope for this change. Merge-grant handling is fixed in
round 157 in the same pull request.

## RED baseline

- `hooks/test_proposed_next.py::test_diagnosis_scope_and_question_turn_are_named_in_both_reminders`
  on the unchanged hook: 6 failures (three observed stop shapes × two event
  sets); the reminder text never mentions the investigation-only, outward-facing
  or self-proposed-count terms.
- Firing-point replay (`claude --print`, tools and hooks disabled, Opus 5.5,
  6 runs per arm, two runs of the experiment; the second used the committed
  `recheck_replay.py`): a stop already restated twice, then the decision
  recheck. Base reminder text: 2/6 and 3/6 proceed to the fix and MR (5/12).
  New text: 6/6 and 6/6 (12/12).
- Control arm, same replay but the user said "investigate only, do not change
  code": base 0/12 and new 0/12 proceed. The new text does not override an
  explicit limit.
- A third observed stop (an inconclusive CI review whose only remedy is a fresh
  full run, stopped as "no resume handle") showed that listing terms is
  open-ended, so the clause now leads with the invariant: a blocker names
  something only the user can supply, and a step the agent can perform itself,
  including a rerun of a failed, timed-out or inconclusive check, is not one.
  Re-measured with that text: diagnosis replay base 2/6, candidate 6/6;
  diagnosis control 0/6 and 0/6. The CI-review replay (`--ci`) proceeded 6/6 on
  both texts and its control held 0/6 on both: the isolated replay does not
  reproduce that stop, so it is a control, not evidence of improvement.

## Additions after review and challenge

- Review (kimi) P2: the moved red-CI section pointed at antecedents absent from
  the playbook; fixed by naming the entrypoint rules.
- Challenge (codex) P1: a typed stop inside a forged notification wrapper
  skipped revocation. The prompt hook now skips only a block whose every line
  is a single-line tag element; free text, nested tags or a multi-line result
  falls back to a user message (revokes). Four new cases fail on the previous
  hook.
- Challenge P1: a budget the user explicitly adopted ("keep that ceiling") was
  classified as the agent's estimate. The rule now binds any count the user
  adopted as a limit; plain assent to the work does not adopt it.
- Challenge P2: the diagnosis probes graded blocked lines by keyword and let a
  blocked fix pass when the line also named the merge; both probes now grade an
  explicit `next:` marker. Re-measured on main skill bodies: 6/6 pass (controls).
- Challenge P2 (evidence gap): guard cases for a help probe compounded with a
  merge, a quoted `--help` message value, and a help probe without a grant.
- Document closeout reminder: five new Stop cases fail on the previous hook
  (`reader_docs` absent) and pass now; tighten-doc already loaded, agent files
  (SKILL.md, AGENTS.md, CLAUDE.md, memory, .claude) and non-doc edits stay quiet.
- Scoped review (codex) P2: Phase B of `defect-diagnosis` listed its stops as
  "stop only for" four cases, so "fix locally, do not push", a cost cap, a
  destructive non-production repair or a purchase matched none of them. Every
  explicit user limit and existing gate now stops the step it covers, and the
  cases are examples; the continuation gate, session policy and both Stop
  reminders say the same. The reminder case asserting "no push" fails 10 times
  on the previous hook and passes now. Two controls show that the old wording
  did not change measured behaviour: `diag-fix-local-no-push` passed 4/4 on the
  previous, main and new bodies, and the replay with "fix locally, do not push"
  (`recheck_replay.py --no-push`) fixed locally 6/6 on both reminder texts.

## Probe controls

Body-compliance runs on the unchanged skill bodies (Opus 5.5):

| Probe | Base result |
| --- | --- |
| `prd-continue-diagnosis-fix` | 3/3 pass (marker grading) |
| `prd-stop-diagnosis-only` | 3/3 pass (marker grading) |
| `prd-continue-question-turn` | 3/3 pass |
| `prd-stop-question-hold` | 3/3 pass |
| `diag-continue-fix-after-handoff` | 4/4 pass |
| `diag-wait-diagnosis-only` | 4/4 pass |
| `diag-fix-local-no-push` | 4/4 pass (also 4/4 on main and on the new body) |

The isolated skill bodies already classify these clean scenarios correctly, so
the probes are regression controls, not RED evidence; the observed failure needs
the accumulated stop context that only the firing-point replay reproduces. The
first grader for `prd-continue-diagnosis-fix` failed three correct answers that
continued the fix and blocked only the merge, and the keyword fix that replaced
it was itself escapable (challenge P2); both product diagnosis probes now grade
an explicit `next:` marker, re-measured 6/6 on main.

## Example-domain preselection

Changed examples: six probe tasks and three hook test messages. Selected domain:
report export with a hard-coded row limit. The source incident's product domain
was rejected; no source identifiers, services or vendors appear.

## Target-output map

| Owner | Direction | Status | Changed file or reason |
| --- | --- | --- | --- |
| Stop hook (`hooks/host-input.py`) | firing point | updated | invariant-led NOT_BLOCKERS clause in both reminders; document closeout reminder |
| tighten-doc | document closeout | routed | the Stop reminder sends sessions to the existing skill; its rules are unchanged |
| product-rd-workflow | upstream gate | updated | `references/pre-final-continuation-gate.md`; entrypoint unchanged (at budget, reference loaded at the gate) |
| defect-diagnosis | owner of failure goals | updated | Phase B scope, decision-on-unverified-cause, zero-exposure count; red-CI classes moved verbatim to the playbook |
| session policy | always-on | updated | `agent-context/session-policy.md`; `session-start.md` unchanged (byte ceiling; recheck carries it) |
| skill-extraction-workflow | this workflow | updated | `references/resume-paused-delivery.md` RCA rule for stops that survive a recheck; grading walk |
| testing-strategy | test layer | unchanged | no new layer rule; probes and hook tests follow existing practice |
| worktree-isolation merge protocol | merge gate | updated | round 157: help probes and task notifications no longer cost a grant; the entrypoint is at its word ceiling, so the Draft rule lives in the continuation gate and the Stop reminder |
| code-review | completion review | unchanged | review still runs before MR; nothing in its contract named push/MR as needing approval |

## Self-review (recorded before external review)

- Acceptance: plan table rows 1–6.
- Changed-file scope: the files in `git diff --stat origin/main` for this branch.
- Edge and failure paths: explicit user limits such as diagnosis only, no push
  or a cost cap (control arms, limit probes); confirm-first repository areas,
  the shared-gate route, destructive actions, purchases and merge/deploy/production
  authority still stop; status-only and explicit stop/hold requests still stop;
  the one-recheck bound and quoted-text exclusion are unchanged (full hook suite).
- Residual risks: the reminder is advisory and bounded to one recheck per stop;
  an agent can still restate a stop with a new term. The replay is one scenario
  shape; other shapes rely on the same definitions.
