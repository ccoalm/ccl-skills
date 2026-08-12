---
name: release-doc-writer
description: 提测文档 / 上线文档 / 发布文档 / test handoff / release doc / launch notes / 补上线范围 / 发布证据 → write, fill, or review test-handoff and release-document substance from Git/config/deploy/verification evidence without owning release orchestration, merge authorization, or production mutation.
---

# Release Doc Writer（提测 / 上线文档编写）

Use this skill when the task is to write, fill, review, or update test-handoff, release, or launch documentation: delivery scope, config changes, migrations, dependencies, scripts, worker/queue decisions, verification evidence, rollback notes, MR handoff notes, or Feishu/Lark handoff sections.

This skill owns **document substance and evidence discipline**. It does **not** authorize deployment, merge, tag, production mutation, branch reset, or overall release orchestration. For full production release coordination, use `release-coordination`.

## Skip / route

- Full production release lifecycle, MR merge authorization, tag gate, pipeline follow-up, post-release reset → `release-coordination`.
- Rollout/canary/rollback strategy or live deploy/config control plane → `platform-release-engineering`.
- Risk gate decision before release → `feature-risk-router`.
- What tests to run or how to prove behavior → `testing-strategy`.
- Active production error or failed smoke → `defect-diagnosis`.
- Pure wording polish after facts are fixed → `tighten-doc`.
- Actual Feishu/Lark API mechanics → the corresponding document tooling.

## Evidence workflow

1. **Establish source range** — identify repo/service list, base ref, head ref, and whether the evidence is commit log, changed-file summary, line-level diff, CI output, runtime state, or document read-back.
2. **Write scope from evidence** — group by user-visible or operational capability; do not infer scope from branch names, MR titles, memory, or another model's summary alone.
3. **Scope confirmation handoff** — if the actual diff/log scope is broader or narrower than the stated release intent, stop and route the release decision back to `release-coordination` before writing it as settled fact.
4. **Config gate** — before writing “no config change”, check config definitions/defaults, usage sites, deployment/config surfaces, and absent-value behavior enough to justify the claim.
5. **Operational sections** — inspect touched migrations, jobs, dependencies, external services, workers, queues, scripts, and enable/disable flags; record enabled, intentionally disabled, deferred, and not-run decisions.
6. **Testing scope section** — write planned/needed test coverage from confirmed diff; route full matrix or command design to `testing-strategy`.
7. **Verification section** — list only tests, CI, smoke, runtime checks, logs, or metrics actually run or observed. Otherwise say `未验证 / 待验证`.
8. **Rollback notes** — write concrete rollback constraints evidenced by diff/config/data/runtime state; route strategy design to `platform-release-engineering`.
9. **Read back edits** — after editing collaborative docs, re-fetch the edited section and comment state when available.

## Comment-safe document editing

- Inspect the target section and existing comments before editing.
- Avoid full-document replacement when comments or anchors exist.
- Preserve existing structure: table stays table, list stays list, heading hierarchy stays unchanged.
- Replace placeholders or target cells/blocks narrowly; append only when no placeholder exists.
- Do not overwrite unrelated sections.

## MR handoff boundary

If the task includes preparing MR/PR handoff text, the release document should be updated first and the MR description should cite the document and decisions. Creating or updating an MR is not merge authorization; route merge authorization and lifecycle sequencing to `release-coordination`.

## Minimal checklist

- [ ] Repos/services and base/head refs recorded.
- [ ] Scope based on Git diff/log or equivalent first-hand evidence.
- [ ] Scope mismatch, over-broad branches, or target-ref drift routed back to `release-coordination` instead of being written as confirmed.
- [ ] Testing scope section output from diff evidence, or imported from `release-coordination`, and not treated as executed verification.
- [ ] Config/default/usage/deploy surfaces checked.
- [ ] Migrations/jobs/dependencies/scripts/workers/queues checked where touched.
- [ ] Enabled, disabled, deferred, and not-run decisions documented.
- [ ] Verification claims match actual evidence depth.
- [ ] Collaborative doc edits are narrow and comment-safe.
- [ ] Edited section read back.
- [ ] Final response states evidence depth and gaps.

## References

- `references/release-evidence-workflow.md`
- `references/comment-safe-release-doc.md`
- `references/release-testing-scope-section.md`
