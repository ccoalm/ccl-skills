# Release Evidence Workflow

Release docs must separate evidence depth from conclusions.

Evidence classes:

- `commit-log`: commits in the release range were inspected.
- `changed-file-summary`: file paths/status/stat were inspected.
- `line-level-diff`: relevant hunks were inspected.
- `config-surface`: definitions/defaults/usages/deploy injection were inspected.
- `ci-observed`: CI or test output was read.
- `runtime-observed`: live or staged runtime state was read.
- `doc-readback`: edited document section was fetched after edit.

Rules:

- “No config change” requires config-surface evidence, not memory.
- “Tests passed” requires a specific observed run.
- A testing-scope section is required for release docs with scope/verification/handoff content. It is planned coverage, not verification evidence; only list it as executed verification after a concrete run or observed result exists.
- “Script not needed” must become either “script absent/not touched” or “script exists and is intentionally not run this release”.
- Deferred flags, workers, queues, and scripts still belong in the doc when the diff contains the capability.
- Do not make module-level diff review sound like a full line-level audit.
- If the evidence range is much broader than the intended release, or the target/base ref changed after the document was drafted, stop and route scope confirmation back to `release-coordination`; do not silently rewrite the doc as if the scope were settled.
