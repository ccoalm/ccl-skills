# Merge grants are spent only by merges and revoked only by the user

Status: implementation and local verification complete; review and challenge
are recorded with round 156, which ships in the same pull request.

Artifact classification: gate implementation. Risk tag: shared-gate. Two
defects in the merge-authorization hooks made users repeat a merge directive
they had already given. Neither change widens what a grant can merge; both stop
a grant from being lost to something that is not a merge or not the user.

## Observed failures

Interactive sessions over four days, first-hand from transcripts and one
host experiment:

1. **A help probe consumed the grant.** The guard classified
   `glab mr merge --help --auto-merge=false` as a merge (the agent had added
   `--auto-merge=false` to pass the spelling check). The CLI printed help, the
   one-shot grant was consumed, and the real merge that followed was denied.
2. **A background-task notification revoked the grant.** The host submits a
   task-completion notification through `UserPromptSubmit` as a whole message
   `<task-notification>…</task-notification>`. The prompt hook treated it as a
   new user message and advanced the epoch, which revokes every grant. A
   controlled check in a live session (a 5-second background task, no user
   message) advanced the epoch at the notification's arrival, and a headless
   capture recorded the payload shape. This is the mechanism behind "a batch
   merge grant covers only the first merge", recorded three times across
   releases: the agent waits on CI between the merges, and the CI completion
   notification revokes the remaining units.

## Change

- `hooks/guard-merge-authorization.sh`: a `-h`/`--help` flag in flag position
  of `glab mr merge` or `gh pr merge` yields `DENY_HELP`, denied before the
  release valve, so no grant is touched; the message names `glab help mr merge`
  and `gh help pr merge`. A help token consumed as a known flag's value stays
  a merge. An unknown value-taking flag can only turn a real merge into this
  deny, never release one.
- `hooks/merge-authorization-prompt.sh`: a prompt that is exactly one task
  notification block, every line of which is a single-line `<tag>value</tag>`
  element, exits before any arming or epoch change. Text before, after or
  between blocks, a free-text or nested line inside, or a multi-line result
  makes it an ordinary message again, so a typed stop always revokes.
- `skills/worktree-isolation/references/hook-authorization.md`: both rules.

## Not changed

Any new user message still revokes single and counted grants; explicit
revocation, target-goal suspension, spelling, target binding and the one-merge
per command rule are unchanged. A failed merge still consumes its grant; a
same-target retry needs repository binding the guard does not extract today,
so it is left for a separate round.

## Acceptance

| Input | Expected | Test |
| --- | --- | --- |
| Grant, then `glab mr merge --help --auto-merge=false` (and `-h`, gh forms) | Deny, grant intact, message names the help form | guard suite (RED on base: 9 failures) |
| Grant, then `glab mr merge 123 -m --help --auto-merge=false --yes` | Allowed and consumed (a real merge) | guard suite control |
| `glab help mr merge`, `gh help pr merge` without a grant | Allowed | guard suite |
| Single, batch, number-bound or goal grant, then one notification block | Grant bytes, mtime and epoch unchanged | prompt suite (RED on base: 4 failures) |
| Notification block alone, or carrying 合并 inside | Not armed | prompt suite |
| Text before, after or between notification blocks | Revokes like any user message | prompt suite |
