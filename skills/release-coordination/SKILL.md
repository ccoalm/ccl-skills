---
name: release-coordination
description: 发版 / 生产发布 / prod release / 上线范围确认 / 合并 main / 打 tag / 生产构建 / 发布后 reset / 按已确认的上线范围产出测试范围提示（提测范围、这次要回归哪些面）→ coordinate release scope, docs, MR/tag gates, pipeline evidence, rollout handoff, watchers, reset. 从已确认发布范围派生的测试范围提示归本技能——它是发布交接物；完整测试层级/矩阵/CI gate 设计 → testing-strategy。
---

# Release Coordination（生产发版协调）

Use this as the **production release coordinator** for scope confirmation, production MR, merge authorization, tag/build gate, evidence closeout, or reset.

Skip / route directly when the task is narrower:

- Release / launch document substance → `release-doc-writer`.
- Rollout/canary/rollback/control plane → `platform-release-engineering`.
- Risk gates → `feature-risk-router`.
- Verification strategy → `testing-strategy`.
- Active post-release error → `defect-diagnosis`.
- Wording polish → `tighten-doc`.

This skill coordinates gates; it does **not** itself authorize merge, tag push, production mutation, manual job play, force-push reset, or destructive cleanup. Boundary: once the user authorizes a merge, post-merge closeout cleanup of the merged **temporary feature branch created for this delivery** (worktree + local branch + remote branch) is already covered by that merge authorization per `worktree-isolation` 收尾 — do not re-ask (eligibility evidence per the Authorization matrix cleanup row). Permanent/integration source branches (e.g. `dev`) are never cleaned up under this carve-out, and an unclear branch role means preserve and ask; cleanup mechanics and safety rails stay with `worktree-isolation`.

## Owner routing

| Concern | Owner |
| --- | --- |
| Release document evidence | `release-doc-writer` |
| Rollout / rollback / production control plane | `platform-release-engineering` |
| Risk labels and mandatory gates | `feature-risk-router` |
| Verification strategy | `testing-strategy` |
| Active incident / failed smoke | `defect-diagnosis` |
| Release evidence signals | `platform-observability` |
| Local branch/worktree safety | `worktree-isolation` |
| MR/CI/tag commands | repo tooling (`glab`, `gh`, approved API/CLI) |
| Feishu/Lark document operations | Feishu/Lark tooling |
| Wording polish | `tighten-doc` |

## Core lifecycle

1. **Intake** — stated scope, production target, release source, tag rule, doc artifact, environments, and user decisions.
2. **Scope-confirmation gate** — compare intended scope with first-hand `base...release-head` diff/log evidence; block on mismatch, over-broad source, target drift, or undocumented operational deltas.
3. **Test-scope prompt** — emit test-scope handoff from confirmed diff; route full design to `testing-strategy`.
4. **Release-doc gate** — invoke `release-doc-writer` to write confirmed scope/evidence depth before MR/merge authorization.
5. **MR/PR gate** — duplicate check; read back URL, source/target, head SHA, CI, mergeability, discussions, auto-merge, and the remove-source-branch flag (the flag may stay set only if the cleanup row's source-eligibility conditions — temp branch created for this delivery, no other open or plan-declared consumer — still hold at merge time; otherwise read the flag back OFF before merging — asking may resolve classification, never waive this invariant).
6. **Merge gate** — re-read immediately; single-form authorization names current object + head SHA, stale state means ask again; batch-form ("批量合并 N") authorization is scoped to the presented release plan — in-plan commits/MRs the agent itself creates while executing the plan stay authorized, out-of-plan objects and third-party changes still require asking again (canonical: `references/mr-merge-authorization.md` + `worktree-isolation` 合并执行协议).
7. **Tag/pipeline gate** — verify tag absence/target; after push read back remote tag and pipeline/job behavior.
8. **Rollout/config handoff** — live mutation goes to `platform-release-engineering`; this skill tracks evidence.
9. **Watchers** — bounded read-only watchers; stop on terminal/manual/timeout and reconcile.
10. **Closeout** — report only read-back facts and explicit gaps/deferred items.
11. **Post-release reset** — remote ref maintenance with dry-run/before-after SHAs, `--force-with-lease`, and SHA equality proof.

## Authorization matrix

| Action | Auth? | Minimum evidence |
| --- | --- | --- |
| Create/update release document | No, if requested | Target section and comment-safe edit plan |
| Create/update MR/PR | Usually no, if requested | Confirmed release scope, source/target, duplicate-check result |
| Merge MR/PR | Yes | Current MR/PR, head SHA, CI/mergeability, discussions, auto-merge flag |
| Create/push production tag | Yes if prod-triggering | Tag name, absence, target commit, expected pipeline behavior |
| Play manual production job | Yes | Specific job id/name, pipeline, status, intended effect |
| Modify production config/resource | Yes | Release-doc decision, read-only current state, planned delta |
| Restart/rollout production workload | Yes | Affected workload, reason, expected state and rollback path |
| Reset dev/test-like branches | Yes | Target/env refs, before SHAs, dry-run/plan, force-with-lease semantics |
| Post-merge cleanup of the merged temp feature branch (worktree/local/remote) | No — covered by the user's merge authorization (`worktree-isolation` 收尾) | The authorized MR/PR read back as merged at the current head SHA and target; the live remote source ref is absent (already cleaned by the platform) or still equals the merged MR source head (moved → preserve and ask, remote path only — eligible local cleanup proceeds per `worktree-isolation`); no other open or plan-declared MR/PR still consumes the source branch; source branch is a temp feature branch (unclear role → preserve and ask); mechanics/safety rails per `worktree-isolation` |

**The matrix is a ceiling, not a floor.** A `Yes` row scopes authorization to that action and to the reversible mechanical prerequisites *inside* it — those are not re-asked. Inheritance stops there: it never covers a retry of a consumed authorization (`worktree-isolation` 合并执行协议), a follow-up action, or a prerequisite that is itself gated — that one keeps its own row, so "X needs Y" cannot launder Y's gate. Post-merge cleanup is not an instance of this inheritance; it is the separate narrow carve-out that the boundary above and its own row define. An action absent from this matrix does not acquire a gate by analogy with a listed one — route it to its owner's rules. **Absence is not permission**: anything irreversible, destructive, production-affecting, or of unclear authority preserves state and asks even with no row of its own. Only a clearly reversible, ungated action is ordinary work.

## Minimal checklist

- [ ] Intended scope, base/head refs, and production target identified.
- [ ] Diff/log scope matches intent; mismatch/broad source/target drift resolved with the user.
- [ ] Operational deltas documented or intentionally deferred.
- [ ] Test-scope prompt emitted or routed to `testing-strategy` for full design.
- [ ] Release doc updated from confirmed first-hand evidence.
- [ ] MR/PR read-back includes head SHA, CI, mergeability, discussions, auto-merge, remove-source-branch flag.
- [ ] Merge authorization is current — for the exact object and head SHA (single form) or for the presented release plan (batch form, in-plan objects only).
- [ ] Merge read-back confirms production target ref.
- [ ] Tag target and remote tag read-back verified.
- [ ] Manual jobs only observed unless explicitly authorized to play.
- [ ] Production config/resource changes delegated and read back.
- [ ] Watchers are bounded and reconciled.
- [ ] Closeout states evidence gaps and deferred items honestly.
- [ ] Post-release reset uses remote refspec + `--force-with-lease` + SHA equality proof.
- [ ] Post-merge closeout cleanup of merged temp feature branches done per `worktree-isolation` 收尾 and the Authorization matrix cleanup row (or a defer/retention reason it sanctions recorded per path — e.g. 让位 pending external-side-effect task or squash non-ancestor retention, both local-path only, remote cleanup still follows the authorized merge when the matrix cleanup row's eligibility holds; never speculative keep-for-later).

## References

- `references/mr-merge-authorization.md`
- `references/release-scope-confirmation.md`
- `references/test-scope-prompt.md`
- `references/tag-and-prod-pipeline-gate.md`
- `references/config-runtime-readback.md`
- `references/post-release-env-reset.md`
- `references/watcher-discipline.md`
- `references/release-closeout-evidence.md`
