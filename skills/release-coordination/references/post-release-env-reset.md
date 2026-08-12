# Post-release Environment Branch Reset

Resetting integration environment branches after release is remote branch pointer maintenance, not local checkout development.

Preflight:

- Confirm the production release closeout is complete enough to use as the baseline.
- Identify the target production ref and every environment branch to reset.
- Fetch target and environment refs.
- Record before SHAs.
- Prefer a dry-run or equivalent before the mutating push.

Safe implementation pattern:

```bash
git fetch origin <target> <env-branch-1> <env-branch-2>
git push --force-with-lease origin \
  origin/<target>:refs/heads/<env-branch-1> \
  origin/<target>:refs/heads/<env-branch-2>
git fetch origin <env-branch-1> <env-branch-2>
```

Completion proof:

```bash
git rev-parse origin/<target>
git rev-parse origin/<env-branch-1>
git rev-parse origin/<env-branch-2>
```

The reset is complete only when every reset environment branch equals the target SHA. Avoid scripts that checkout and hard-reset local branches; they mutate the working checkout and can leave local/remote refs inconsistent if hooks or pushes fail.
