# Merge grants are not spent by help probes; notifications stay user messages

Status: implementation and local verification complete; review, challenge and
delta passes are recorded with round 156, which ships in the same pull request.

Artifact classification: gate implementation. Risk tag: shared-gate. Two
mechanisms made users repeat a merge directive they had already given. This
round fixes the first and, after review, deliberately keeps the second
mechanism's current behaviour and moves its remedy into agent practice.
Nothing here widens what a grant can merge.

## Observed failures

Interactive sessions over four days, first-hand from transcripts and one
host experiment:

1. **A help probe consumed the grant.** The guard classified
   `glab mr merge --help --auto-merge=false` as a merge (the agent had added
   `--auto-merge=false` to pass the spelling check). The CLI printed help, the
   one-shot grant was consumed, and the real merge that followed was denied.
2. **A background-task notification revoked the grant.** The host submits a
   task-completion notification through `UserPromptSubmit` as a whole message
   `<task-notification>…</task-notification>`, with no field that marks its
   origin. The prompt hook treats it as a new user message and advances the
   epoch, which revokes every grant. A controlled check in a live session (a
   5-second background task, no user message) advanced the epoch at the
   notification's arrival, and a headless capture recorded the payload shape.
   This is the mechanism behind "a batch merge grant covers only the first
   merge", recorded three times across releases: the agent waits on CI in the
   background between the merges, and the completion notification revokes the
   remaining units.

## Change

- `hooks/guard-merge-authorization.sh`: a `-h`/`--help` flag in flag position
  of `glab mr merge` or `gh pr merge` yields `DENY_HELP`, denied before the
  release valve, so no grant is touched; the message names `glab help mr merge`
  and `gh help pr merge`. A help token consumed as a known flag's value stays
  a merge. An unknown value-taking flag can only turn a real merge into this
  deny, never release one.
- `hooks/remind-post-merge-cleanup.sh`: the help subcommand form
  (`gh help pr merge`, `glab help mr merge`) is not a merge, so it no longer
  triggers the post-merge cleanup reminder; a real merge in the same command
  still does.
- `hooks/merge-authorization-prompt.sh`: unchanged from main. A notification
  stays a user message: it revokes single and counted grants and never arms
  one. New suite cases pin this.
- `skills/worktree-isolation/references/hook-authorization.md`: the help rule,
  and the remedy for failure 2 — during a granted merge sequence, wait for CI
  in the foreground (for example `gh pr checks <number> --watch`), not with a
  background task or monitor, so no notification arrives between merges.

## Keep or delete: the notification exemption

A first version skipped any prompt that was exactly one notification block.
Two passes broke it in the same way: the challenge showed a typed stop inside
a forged wrapper kept the grant, and the narrowed version (every line a
single-line tag element) still kept it for a stop written as
`<summary>先别合并</summary>`. The predicate "looks like a notification" stands
in for "came from the host", and the payload carries nothing that proves
origin, so every narrowing leaves another typed form. Decision: delete. The
revocation it removed is the safe failure (the user re-authorizes); keeping a
grant through a typed stop is not. The batch-merge cost moves to agent
practice through the foreground-wait rule above, read before every platform
merge.

## Not changed

Any new message still revokes single and counted grants; explicit revocation,
target-goal suspension, spelling, target binding and the one-merge per command
rule are unchanged. A failed merge still consumes its grant; a same-target
retry needs repository binding the guard does not extract today, so it is left
for a separate round.

## Acceptance

| Input | Expected | Test |
| --- | --- | --- |
| Grant, then `glab mr merge --help --auto-merge=false` (and `-h`, gh forms) | Deny, grant intact, message names the help form | guard suite (RED on base: 9 failures) |
| Grant, then `glab mr merge 123 -m --help --auto-merge=false --yes` | Allowed and consumed (a real merge) | guard suite control |
| `glab help mr merge`, `gh help pr merge` without a grant | Allowed | guard suite |
| `gh help pr merge`, `glab help mr merge`, help piped to grep | No cleanup reminder | cleanup suite (RED on base: 3 failures) |
| A help lookup and a real merge in one command | Cleanup reminder | cleanup suite control |
| Counted grant, then a notification block; single grant, then a stop inside notification markup | Grant revoked | prompt suite (fails twice on the exemption version) |
| Notification block carrying 合并 | Not armed | prompt suite |
