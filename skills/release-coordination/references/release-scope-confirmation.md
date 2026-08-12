# Release Scope Confirmation Gate

Before creating a production MR, asking for merge authorization, pushing a production tag, or playing a production deploy job, confirm the **actual release scope** against first-hand source-control evidence.

Minimum evidence:

1. Resolve the exact production target ref and release source ref.
2. Fetch/re-read refs immediately before scope confirmation.
3. Compare `base...release-head` using commit log, changed-file/status/stat, and line-level diff for high-risk or unclear areas.
4. Classify user-visible capability changes and operational changes: config/defaults, migrations, scripts, jobs, workers, queues, dependencies, external integrations, feature flags, and manual steps.
5. Compare the actual scope to the user's intended scope and the release document.

Block and ask the user to re-confirm when:

- The release source contains unrelated capabilities or a much broader commit/file set than intended.
- The wrong source or target branch/ref appears to be selected.
- The production target advanced after the scope was documented, changing the diff base.
- Config, migration, script, worker, queue, dependency, or manual-job deltas are present but absent from the release document.
- Evidence depth is only commit/file-level but the conclusion claims line-level or runtime verification.

Do not infer scope from branch names, MR titles, prior memory, release notes, or another model's summary without checking source-control evidence. Once confirmed, route document substance to `release-doc-writer` and carry the exact scope evidence into MR/tag authorization prompts.
