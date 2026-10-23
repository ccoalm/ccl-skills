# Keep review coverage across a target-only integration

Bringing a branch up to date with its target (a strict default branch makes
every open branch fall behind after each merge) currently invalidates the
last review even when the branch's own change is byte-for-byte the same. The
agent then reruns a full review per update, so N parallel branches cost on
the order of N² reviews. This round keeps coverage when the update only
integrates the target and leaves the candidate's own patch unchanged.

## Charter

| Field | Decision |
| --- | --- |
| Purpose | Stop full re-reviews that a target-only update triggers, without letting any author change escape review. |
| Scope | `hooks/remind-review-covers-head.sh` coverage verdict, its suite, `code-review/references/development-completion.md` step 2, and the npm patch release. The extraction lane's path-disjoint delta rule (`dual-track-review-gate.md`) stays as is; branch protection and merge queues are out of scope. No iterative-program watermark applies. |
| Depth | Generator/tooling change. |
| Result classification | Failure/correction: the user reported that every SHA mismatch forces a rebase and a full re-review. Observed in the hook: coverage is tree equality or ancestry, and both the rebase and the merge-in path report the candidate as unreviewed. |
| Matching analysis | RCA in the section below; prevention is a mechanical coverage predicate at the existing firing point (the PR open/ready/merge hook), not more prose. |
| Failure boundary | A conflict resolution, an amended commit, an extra commit or a dirty review must still remind. Integration correctness stays with CI on the integrated head; this predicate claims nothing about it. |
| Lifecycle impact | Implementation (hook), testing (suite), review policy (code-review completion walk), release (npm patch), maintenance. No product, UI or onboarding change; use without source access is unchanged (reminder text only). |
| Evidence plan | Current hook and `review_gate.py` receipt fields; `development-completion.md` step 2; `dual-track-review-gate.md` path-disjoint rule; external primary source: Gerrit label `copyCondition` change kinds. Produced artifacts: not-applicable (no earlier artifacts; checked `specs/` for a prior round on this topic, none). |
| Completion standard | RED probes before the hook change, GREEN suite, `make test`, deep self-review, independent review and adversarial challenge, PR to main, npm 0.18.14 published and verified. |

Artifact classification: `gate implementation`; risk route: `shared-gate`.
Owners loaded: `skill-extraction-workflow` (shared hook and rule), with
`code-review` owning the completion walk text and `testing-strategy` the
suite. Delegation: not applicable, one dependent slice.

## RCA

- Trigger: strict branch protection marks every open branch BEHIND after each merge.
- Missing control: the hook's only coverage tests are `tree(reviewed) == tree(HEAD)` and "reviewed is an ancestor", which say nothing about whether the author's own patch changed.
- Rule/firing mismatch: step 2 already narrows to "a rebase that changed a file the candidate touches", but the hook, which fires at the decision point, is stricter than the rule, and agents follow the hook.
- Counterfactual: with an integration-only predicate at the hook, a trivial rebase or a clean merge-in no longer prompts a review; removing the BEHIND trigger alone (merge queue) would also help but needs a protection change outside this round.

## External grounding

Gerrit `config-labels` (copyCondition change kinds): `TRIVIAL_REBASE` matches
"the same diff (including context lines) … rebased onto a different parent
and that rebase did not require git to perform any conflict resolution", and
is the default copy condition of the pre-installed Code-Review label.
`MERGE_FIRST_PARENT_UPDATE` keeps approvals when only the target side of a
merge moved. The predicate below implements those two kinds, narrowed to
the case where the target did not touch the reviewed files.

## Design

Coverage additionally holds, for a clean review with `status=passed`, when the
target T is the remote default branch (`refs/remotes/origin/HEAD`) and, with
P the files `diff-tree merge-base(reviewed, T) reviewed` lists:

1. the target changed nothing in P between `merge-base(reviewed, T)` and
   `merge-base(HEAD, T)`;
2. HEAD holds exactly the reviewed version of every file in P;
3. every file outside P in HEAD is exactly the target's at `merge-base(HEAD, T)`.

That is what a clean merge of the target or a conflict-free rebase onto it
produces, and it equals replaying the reviewed diff onto the new base when the
paths are disjoint. Condition 1 is the extraction lane's existing
path-disjoint delta rule; it is stricter than Gerrit, which also copies
approvals when the target changed the same file elsewhere. All three are
`git diff-tree --quiet` comparisons of tree entries: no file content is read,
no index is written, and no diff configuration, hook, driver or helper
program applies. A promisor remote or partial clone, a missing remote default
branch, or any git error means not covered. The reminder stays non-blocking;
integration correctness stays with CI on the new head.

Design history, each replaced rather than patched after review found a
same-class escape: a `merge-tree` walk with a `HEAD~n` rebase base (ran merge
drivers; a commit below the replay escaped), a patch-id comparison (ignores
line numbers; an edit moved to a look-alike block matched), a replay with
`git apply` into a temporary index (porcelain diff config, index hooks and
offset matching each let an unreviewed change through or ran a repository
program). Four rounds of the same classes —
repository-configured programs and config-dependent comparisons — led to
removing every content-level and index-level step.

Security four questions: inputs are the local receipt and repository
history, both writable by the same local user the reminder serves; forging
them silences an advisory reminder only and grants no authority. No
identity, billing, tenant or permission decision. Negative case: a merge
commit carrying an extra edit, and a rebase with an amended patch, must
still remind.

## Target-output map

| owner | direction | status | changed file or reason |
| --- | --- | --- | --- |
| hooks (review coverage reminder) | executor | updated | `hooks/remind-review-covers-head.sh`, `hooks/test_remind_review_covers_head.sh` |
| code-review | upstream rule | updated | `skills/code-review/references/development-completion.md` step 2 |
| skill-extraction-workflow dual-track delta rule | sibling | unchanged | its path-disjoint delta pass is narrower than a full rerun and owned by that lane |
| worktree-isolation | downstream | unchanged | already prefers merging the target into pushed branches |
| npm package | release | updated | version 0.18.14 in package and lock files |
| product-rd-workflow, testing-strategy | coordinator | unchanged | no stage or test-layer policy changes |

## Acceptance

| ID | Scenario | Expected after | Baseline |
| --- | --- | --- | --- |
| A1 | clean merge of the target into the reviewed branch | quiet | remind |
| A2 | merge of the target with an extra edit in the merge commit | remind | remind |
| A3 | rebase onto a moved target, same patch | quiet | remind |
| A4 | rebase with an amended patch | remind | remind |
| A5 | rebase plus an extra commit | remind | remind |
| A6 | clean merge-in but the receipt is `findings` | remind | remind |

Probes added during review (A7–A29) and their results are in
`specs/review-coverage-by-patch/evidence/validation.md`.
