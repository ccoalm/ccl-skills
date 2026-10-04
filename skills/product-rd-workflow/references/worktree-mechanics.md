# Worktree Mechanics

Use this reference for the concrete mechanics behind product R&D worktree isolation and cleanup.

## Create A Dedicated Worktree

Use a unique per-line branch so it never collides with a branch already checked out elsewhere:

```bash
git worktree list
git worktree add -b <line-branch> <path> <base>
```

## Shared Git State

A worktree isolates only the working directory and index. Sibling worktrees of the same repository still share git objects, refs, hooks, config, and remotes.

Coordinate repo-global mutation such as:

- Hook or config edits.
- Remote changes.
- Global cleanup.
- `git gc`.

## Concurrent-Session Hazards

A branch alone is not concurrent isolation. `git checkout` moves the single shared working tree and index under every other line in that checkout, so branch-with-committed-WIP is safe only for serialized handoff (commit, then switch away), not for simultaneous edits.

Never `git stash` another line's uncommitted changes to clear your own view. `git stash` / `refs/stash` is shared mutable state a concurrent session can overwrite or drop. A dropped stash is only sometimes recoverable before garbage collection by locating its unreachable commit and inspecting or applying it; treat that as emergency recovery, not a workflow.

Host-install symlinks are shared-tree edits too: editing `~/.<host>/skills/<skill>/…` or any path that symlinks into a shared repository working tree edits that shared tree, even when it looks like a local file. Isolate it the same way.

If isolation was skipped and a concurrent session may act, do not commit unreviewed or work-in-progress shared changes merely to dodge a clobber. Move the patch into a dedicated worktree or private scratch, then land it through the normal review and release gates.

## Branch Sharing Boundary

A per-line WIP branch stays local/private until the normal shared-branch-push and MR gates pass. Never force-push a shared branch to "isolate" it.

## Closeout Cleanup

At closeout, after the work lands or is abandoned, clean up the worktree and private branch. `worktree-isolation` owns this teardown in its teardown section (`## 收尾` in `worktree-isolation/references/merge-and-teardown.md`), which also holds the integration evidence and the remote-branch rules. Its guards apply to every removal:

- Before removing the worktree directory, you must run `git -C <path> status --ignored -s` from the primary checkout. It must exit 0; a failed scan counts as no scan, so stop and find the cause instead of reading empty output as nothing to keep. `git worktree remove` without `--force` still deletes gitignored files.
- Judge each listed entry by what it costs to recreate: drop regenerable outputs (dependency directories, build and test outputs, caches, logs) and copy costly ones (long-running results, collected data, trained artifacts) back to the primary checkout before removal. When unsure, treat an entry as costly.
- If a task with unfinished external side effects, such as a migration or a deployment, still runs from the worktree, wait for it to finish; never kill it to clean up.
- Never pass `--force` to `git worktree remove` or use `git branch -D`: a refusal means unmerged or uncommitted work. An abandoned line's branch usually fails `-d`; keep it and report it.
- Never delete a permanent or integration branch, or any branch whose name contains `release`, as part of this cleanup.

```bash
git -C <path> status --ignored -s   # must exit 0; copy costly ignored outputs out first
git worktree remove <path>          # no --force
git worktree prune
git branch -d <line-branch>         # -d, not -D
```

## Owner Routing

Route the concrete worktree recipe to the organization `worktree-isolation` skill, especially its Step 0 isolation self-check and integration cleanup. If the session has an installed branch/worktree-hygiene skill, such as `superpowers:using-git-worktrees`, it may supplement the mechanics. Otherwise apply these steps directly.

## Pre-Merge Freshness

Before merging a branch back, especially via squash, check whether it is behind the target. If it is stale, follow `worktree-isolation`'s pre-merge freshness gate: update onto the target and verify the collision set so the stale branch does not silently revert recent target fixes.
