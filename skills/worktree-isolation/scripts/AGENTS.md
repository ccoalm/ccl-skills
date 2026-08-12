# skills/worktree-isolation/scripts Agent Contract

Scripts here inspect or clean git worktrees and branches under the worktree
isolation policy.

Rules:

- Destructive cleanup must be conservative: dry-run by default where possible,
  no force deletion, and never delete dirty, detached, default-branch, or
  unmerged worktrees.
- Default-branch/MR branch cleanup requires platform merge evidence, not only
  local ancestry.
- Path handling must be canonical and must not follow unsafe aliases.
- Negative tests are required for protected cases, and they must be **sensitive**:
  a negative probe that would still pass with the protecting predicate removed
  proves nothing. Encode the mutation walk in the suite (see the killing-mutation
  rule in `testing-strategy`); `test_worktree_sweep.sh` probe P7 is the worked
  instance for this directory.

Validation:

- Run the touched script's tests or a synthetic throwaway-repo matrix.
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
