# Session cost signals

Status: implemented. Measurements and reproduction are in
[validation evidence](evidence/validation.md); review passes are in
[dispositions](evidence/dispositions.md).

Artifact classification: hook behavior, review-controller output and reference
text. Risk tag: shared-gate (the review controller). The round adds one
user-only notice, trims one redundant injection and adds a counter to an
existing receipt. It adds no gate, block, flag or permission.

## Observed failures

A retrospective over a month of Claude Code and Codex sessions — one product
line's repositories and this one — measured where time and tokens went:

- Long sessions. In the product line's Claude sessions the median request
  carried about 450k tokens of context (p90 about 820k); requests above 300k
  carried about 85% of token cost, and cache reads were about three quarters of
  it. Auto-compaction on 1M-window models waits until about 967k tokens, and
  nothing told the user how large the context had grown.
- Redundant injection. About one third of the task-entry injections fired on
  turns the host starts itself to deliver a background-task completion, where
  the routing list is already in context.
- Review loops. Single changes ran 13 to 49 conclusive review runs, several
  after the five-run continuation checkpoint existed. The controller kept no
  count, so the checkpoint depended on the agent remembering one across hours
  and compactions; and its trigger, "findings recur without progress", did not
  fire while each instance of the same class was being fixed.

## Change

- `hooks/host-input.py` (Stop): when the latest real request's context reaches
  300k or 600k tokens, a `systemMessage` names the size and the two levers
  (`/clear` after a handoff at a delivery boundary, `/autocompact`). It is shown
  to the user only, once per band per transcript, reads only the transcript
  tail, and joins any existing reminder without changing its text.
- `hooks/task-entry.sh`: a prompt that is exactly one host `<task-notification>`
  envelope gets only the skill-loading and unfinished-work boundary, not the
  routing list, which SessionStart keeps in context (also after compaction).
  Every other prompt, and any input the hook cannot parse, keeps the full
  entry. The prompt is still neither classified nor echoed.
- `skills/code-review/scripts/review_gate.py`: the worktree receipt carries
  `conclusive_runs` and `first_recorded_at`; review and challenge runs count,
  completion checkpoints do not. From the sixth conclusive run the output
  carries `continuation_checkpoint` with the count and the checkpoint's steps.
  The read-increment-replace holds a lock on the receipt directory, so
  overlapping runs do not lose increments; a missing, corrupt or linked prior
  receipt restarts the count and never costs the new receipt.
- `skills/code-review/references/development-completion.md`: the checkpoint
  names the counter and adds the same-class decision — narrow or remove the
  capability that keeps producing a class before patching it again.

## Not changed

- No limit on review runs and no block: the checkpoint still waives nothing and
  continues necessary review within task authority.
- No change to auto-compaction or any host setting; the notice only informs.
- Codex: its 258k window compacts automatically; the notice reads Claude usage
  records only and stays quiet for other transcripts.
- Local `make test` parallelism, reviewer-lane health checks and merge-gate
  phrasing were measured in the same retrospective and are left for their own
  rounds. A counting method for session-history retrospectives was drafted and
  withdrawn: its failures were seen once, and a replay without it already
  deduplicated (6/6).
