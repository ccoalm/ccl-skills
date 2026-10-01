# Stops that hand routine decisions back to the user get one recheck

Agents ended delivery turns on questions they could settle themselves:
security self-checks, which owner skill or module applies, and whether to take
the next in-scope step. The Stop hook let three shapes of that stop through
unchecked, so a progress report could stand in for delivery.

Artifact classification: `gate implementation`. The Stop hook gains one bounded
recheck; no stop is forced and no authority is granted. Risk tags: `shared-gate`
(plugin-shipped hook and always-on session text). Security posture: no
security-sensitive input. The hook reads only the host's final message and the
existing bounded transcript summary, and the recheck text keeps every safety
stop the session policy already requires.

## Baseline

On the base commit, `hooks/host-input.py` returned no decision for:

1. a `proposed-next: blocked: …` handoff;
2. a `proposed-next: none — …` handoff naming an approval, confirmation,
   decision or resource wait;
3. a final prose line asking permission ("Should I proceed?", "是否继续？")
   after edits or delivery evidence, with or without a handoff label.

The base test suite pinned shapes 1 and 2 as quiet. Sixteen new cases in
`hooks/test_proposed_next.py` failed on the base hook before the change.

## Change

- The hook returns one `Decision recheck` block for those three shapes. Its
  text lists the real blockers: missing credentials or authority, a fact
  unavailable from local evidence, an action the safety rules gate, overturning
  an established user direction, or a material product tradeoff the evidence
  cannot settle. Everything else returns to the agent.
- Host `stop_hook_active` bounds the recheck to one attempt per stop. Finished
  `none` states ("PR approved and merged", "PR opened; awaiting review") and
  `none — status only` stay quiet; quoted and fenced text is ignored.
- `agent-context/session-start.md` gains "Decide, don't ask" and a check of
  remaining requested work before the final message, inside its byte budget.
  `agent-context/session-policy.md`, the product-rd pre-final continuation gate,
  README and the source register describe the same behavior.

## Acceptance

- The new hook cases pass, and the three base-quiet shapes now recheck.
- Finished-state, status-only, pleasantry and quoted-question cases stay quiet.
- `make test` lanes pass except suites that fail identically on the base commit
  in this environment; `check-ccl-skills.sh`, public sanitization and the
  shared-Git-surface gate pass.

## Review

See `evidence/review-lane-status.md`.

## Permission matching

Terminal Markdown emphasis around a permission question has the same meaning
as plain prose. The matcher removes one terminal pair of one to three asterisks
or underscores before classification. Quoted text, fenced examples, inline code
and conversations without delivery evidence retain their existing behavior.

Question punctuation is checked once before phrase matching. A repeated
permission prefix without terminal punctuation must finish within the hook's
five-second timeout; a long line ending in a real question must still recheck.
This avoids an unbounded suffix scan for every candidate phrase. No dependency,
stored state, sampling or additional retry is introduced. Reverting the matcher
is the rollback path.

The native-payload suite covers English and Chinese emphasis, status labels,
negative examples and both long-line outcomes. On the unmodified matcher, the
new cases produced 14 assertion failures and one five-second timeout. These are
synthetic hook-contract checks, not evidence of a model completing a real task.
