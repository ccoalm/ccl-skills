---
description: Check whether current repository is safe for editing under repository worktree rules
---

Check the current repository's worktree isolation state before editing.

Run the repo-local preflight first:

```bash
bash skills/worktree-isolation/scripts/worktree-status.sh --slug <task-slug>
```

If it prints `UNSAFE`, do not edit. Create the feature worktree with the printed
`git worktree add -b ...` command, then continue inside that new path. New lanes
default to (and are recommended to use) the primary checkout root at
`.work/worktrees/<task-slug>`; per-lane local metadata is conventionally
`.work/lanes/<task-slug>.json` and the status script only prints the snippet/path
(it does not write metadata). The `.work/worktrees` location is a convention, not
a hard safety condition: an existing independent feature worktree outside it can
still report `SAFE` when the hard conditions hold (independent worktree, named
feature branch, not a submodule, not detached, clean tree, confirmed base); in
that case the script only emits a non-blocking warning suggesting `.work/worktrees`
for new lanes.

If the script is missing, fallback to:

```bash
git status --short --branch
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git symbolic-ref --quiet --short HEAD || true
test -f .worktree-only && printf '.worktree-only present\n' || printf '.worktree-only absent\n'
```

If `.worktree-only` is present and the current checkout is `main` or `master` with `git-dir == git-common-dir`, stop and create a feature worktree before editing. Manual fallback creation should anchor on the primary checkout root, derived from the parent of `git rev-parse --git-common-dir`, e.g. `git worktree add -b <branch> <primary-root>/.work/worktrees/<slug> <base>`.
