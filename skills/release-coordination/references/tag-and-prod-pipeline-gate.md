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
