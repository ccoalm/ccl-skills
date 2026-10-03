# Stop reminders state the blocker test and close the document and Draft gaps

Status: implementation and local verification complete; review and challenge
dispositions are recorded in [validation evidence](evidence/validation.md).

Artifact classification: gate implementation. Risk tag: shared-gate. The change
edits the plugin-shipped Stop reminder text, the continuation gate it mirrors,
the diagnosis owner's fix scope and the always-on session policy, and adds one
Stop-time check: reader-facing documents edited without tighten-doc. It grants
no merge, publication or production authority and keeps every explicit user
limit binding. Security posture: no security-sensitive
input; the hook still reads only the host's final message and the bounded
transcript summary.

## Observed failure

A review of recent interactive Claude Code and Codex sessions found agents
ending turns on work they were already allowed to do, after the decision
recheck added in 152 had fired on the same stop. The recheck named "missing
authority" as a real blocker, and the agents answered it by restating the stop
in terms the text never defined:

- a verified root cause, then "you only asked me to investigate", so the fix,
  its test and its MR waited for a one-word go-ahead;
- "pushing the branch and opening the MR is outward-facing";
- "the approved count is used up", where the count was the agent's own
  estimate that the user had accepted;
- a clarifying question from the user treated as a status-only request;
- the user asked for a fact, log or credential the agent could find or reuse.

Users answered these stops with a bare "ok", "continue", "fix" or "merge", or
corrected them directly ("is there a rule that needs this confirmation?",
"check it yourself"). Detection was not the gap: the hook fired every time.

## Change

- `hooks/host-input.py`: both the decision recheck and the continuation
  reminder carry one shared clause. It opens with the test: a blocker names
  something only the user can supply (a decision the evidence cannot settle, a
  credential or access grant, permission the goal does not cover, a fact absent
  from every readable source), and a step the agent can perform itself is never
  one. The observed restatements follow as examples, and a clarifying question
  is not a status-only request.
- `skills/product-rd-workflow/references/pre-final-continuation-gate.md`: the
  same definitions where intent recovery, inherited authority, count binding and
  the recheck are described; a merge-gate grant request covers the whole
  remaining plan.
- `skills/defect-diagnosis/SKILL.md`: a failure goal carries Phase B through the
  verified fix, test, review, branch push and MR/PR, unless the user limited it
  to diagnosis, the repository marks the area confirm-first, the shared-gate
  route applies, or the step needs merge, deploy or production authority. A
  tradeoff resting on an unverified cause is not yet a user decision. A zero
  failure count says nothing until the path's exposure is confirmed. To stay
  within the entrypoint word budget, the red-CI cause classes moved verbatim to
  `references/diagnosis-playbook.md`; the entrypoint keeps the rule and a
  pointer.
- `agent-context/session-policy.md`: the same non-blockers in the autonomous
  decision paragraph. `session-start.md` and the product-rd entrypoint are
  unchanged: both are at their byte or word ceilings, and the firing-point
  measurement below shows the reminder text carries the change.
- `skills/skill-extraction-workflow/references/resume-paused-delivery.md`: a
  retrospective on a stop that survived its recheck quotes the agent's
  justification and closes that term at the recheck, instead of adding
  detection.
- `hooks/host-input.py` also adds a document closeout reminder at Stop: when the
  session edited reader-facing documents (Markdown/MDX/reST outside skill
  bodies, contracts, memory, scratch and temporary paths) and never loaded
  tighten-doc, the stop gets one reminder to run its closeout readback. In the
  reviewed window 26 of 29 sessions that edited plans, specs, READMEs or handoff
  documents never loaded tighten-doc. The reminder shares the existing
  one-recheck bound and joins any other Stop reminder.
- The self-performable steps in the reminder include marking an MR/PR ready
  once the agent's own checks pass and polling its own CI run; agents left MRs
  in Draft at the end of 21 reviewed sessions and ended on "waiting for CI" 13
  times. The continuation gate and session policy say the same. A count the
  agent proposed binds only when the user adopted it as a limit.
- `eval/body-compliance-eval.rb`: three paired probes (failure goal vs explicit
  diagnosis-only limit, under both owners; clarifying question vs explicit
  hold). They are regression controls; see the measurement section.

## Acceptance decision table

| Input | Expected result | Test |
| --- | --- | --- |
| Blocked handoff after a verified cause, "authorize the code change" | Reminder names the investigation-only, outward-facing and self-proposed-count terms | `hooks/test_proposed_next.py` new case (RED on base) |
| Same three shapes with an actionable marker | Continuation reminder carries the same clause | Same test |
| Replayed stop, base vs new decision-recheck text | New text continues to the fix and MR | Firing-point A/B (evidence) |
| Same replay, user said "investigate only, do not change code" | Both texts keep waiting | Control arm of the A/B |
| Probe pairs on base skill bodies | Continue arms continue, limit arms block | body-compliance runs (controls) |
| Existing Stop cases, quoted text, status-only and one-recheck bound | Unchanged | Full hook suites |
| Reader-facing document edited, tighten-doc never loaded | One closeout reminder naming the files; quiet after tighten-doc or for agent files | `hooks/test_proposed_next.py` doc cases (RED on base) |
| Final message keeps the MR in Draft or waits on CI | Reminder lists marking ready and polling CI as self-performable | Same suite |

## Verification

Run the new hook case on the unchanged hook (RED), then the hook suites,
session-start budget suite, the body-compliance grading walk, check-ccl-skills
against origin/main, make test and the heavy regression lane, public
sanitization and the shared Git surface checker. Evidence and review receipts
live in `evidence/`.
