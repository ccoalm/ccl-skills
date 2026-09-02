# Tag and Production Pipeline Gate

Before creating or pushing a production tag:

1. Resolve the exact target commit after merge.
2. Verify the local and remote tag name does not already exist.
3. Verify the target commit is the intended production target head.
4. State whether the tag is expected to trigger build/deploy automatically, create manual jobs, or do nothing for each repository/service.

Do not assume every repository uses the same tag rules.

After pushing a tag, read back:

- Remote tag target.
- Tag pipeline existence or documented absence.
- Pipeline/job state.
- Manual jobs that require separate authorization.
- Produced image/digest/version evidence when available.

If the tag target is wrong after push, do not force-move a published production tag. Stop and escalate to the release owner for the corrective version/tag path.

## The version pointer is under the same immutability, one step earlier

A published version cannot be changed or reused, so the source tree's version pointer may never sit **below** the highest already-released version. Treat that as a checked invariant, not a convention:

- **Check it at merge time, not only at tag time.** A tag-time check blocks the bad release but leaves the wrong pointer on the integration branch until a person happens to notice, and the next bump then lands on a corrupted base.
- **The commit that lowers it is usually not a release commit.** The version line is a both-sides-changed hunk, so the observed shape is a conflict resolved the wrong way inside a change about something else entirely — the commit subject gives no warning, and reviewers reading it for its stated purpose skip the hunk.
- **Repair every site.** The version is stated in the manifest and again in the lockfile (twice, in current npm lockfile versions); a partial repair leaves the sites disagreeing, which is its own release defect.
- **Compare against the released record, not against a base branch.** "Did this branch lower it" is a different, weaker question than "does the tree point under something already published"; derive the record from release tags or the registry.
