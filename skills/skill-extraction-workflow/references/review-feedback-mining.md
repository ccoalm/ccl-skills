# Review-feedback mining — turning human review comments into skill candidates

Use this layer when the source corpus is **human review feedback on merged changes** (inline PR/MR comments, review submissions, review-thread replies) and the goal is to find guidance a reviewing skill (`code-review`, `product-rd-workflow`'s review checklist, a stack `*-dev` skill, or a domain reviewer rule) should carry. It complements the incident layer (`incident-postmortem-extraction.md`) and the task-retrospective layer (`source-to-skill-extraction.md`): those mine failures; this mines what reviewers repeatedly had to say. The evidence bar below exists because the naive version — "every comment is a lesson" — produces checklist bloat, and the naive adoption test — "the thread was resolved / the author replied fixed" — promotes guidance the final code may never have implemented.

## What counts as evidence

- **Author filter first.** Only feedback whose author is a human reviewer counts; bot/automation comments, and human comments that merely forward automation output, are excluded before anything else is read. The change author's own comments never count as adoption of themselves.
- **Adoption is a diff fact, not a thread state.** A comment was adopted only if the change landed *after* the comment differs from the change as it stood *when* the comment was made in the way the comment asked. Compare the **feedback-time patch** (the change's diff at the last commit that predates the comment) with the **final landed patch** (the change's diff at the landing merge against its target parent). Merge status, a resolved thread, an author reply saying "fixed", or a same-file edit are context, never proof.
- **Fail closed when the baseline cannot be reconstructed.** After a force-push, when the reviewed commit is no longer part of the change, when the feedback predates every surviving commit, or when the landing shape cannot be reconstructed, classify the item `unclear` and exclude it — do not guess adoption from the final diff alone (that diff also contains unrelated target-branch movement).
- **Timestamps must strictly predate the merge** for both creation and last edit; an item edited at or after merge is post-merge commentary, not pre-merge feedback.

## Classification pipeline

1. **Author + adoption** — classify each eligible item as `human-authored | forwarded-automation | unclear` and `adopted | rejected | unclear`. Only `human-authored ∧ adopted` proceeds.
2. **Against the current skill** — classify each adopted item as `candidate | already-covered | implementation-specific | not-feedback`. `already-covered` is the idempotency guard: rerunning over an overlapping window must not re-propose guidance the skill already states. A **singleton may qualify** — recurrence is a strength signal, not an admission ticket; one adopted, generalizable, non-obvious correction is enough.
3. **Draft from structured agreed guidance, never from raw review text** — the draft input is the classified, generalized statement of what the reviewer asked and why the change adopted it, with the identifying details of the source change already stripped (`r0-leakage-audit.md`, `example-domain-preselect.md`).
4. **Independent review of the same skill diff** — the candidate diff goes through the normal dual-track gate (`dual-track-review-gate.md`); when two model reviewers are used, they must be independently configured (refuse to run when both resolve to the same executable/provider), and disagreement gets one bounded re-evaluation and stays visible in the run record if unresolved.

## Operating stance

- **"No candidate" is the common, correct outcome** of a maintenance pass over a window; days without a skill change are the process working, not stalling. Do not lower the bar to produce output.
- **The operator decides; model output is never committed verbatim.** Read the candidate diff on its own merits — look for checklist bloat, historical prose, extrapolation from a single incident presented as a general rule, and duplication of what the skill or an authoritative doc already says — then discard, batch with a later candidate, or promote with edits. Small edits during promotion (tightening, folding into an existing rule, dropping an example that only made sense with the source change's context) are expected and preserve the reviewer judgment the process depends on.
- **Skill drift stops promotion.** A candidate is drafted against a recorded skill revision; if the skill has changed since, re-run the classification (or manually rebase and re-review) rather than applying a stale complete-file rewrite over newer guidance.
- **Idempotent, cursor-free windows.** Scan a time window with overlap rather than keeping a repository cursor; already-covered guidance classifies out, so overlap is harmless and a missed day is recovered by widening the window.
- **Provenance stays with the promotion, identifying details stay out of the shared tree.** The promoted change records which feedback items (by stable id/URL) and which landed evidence ranges support each rule — in the private alias / provenance archive per `extraction-lifecycle-handoff.md`; the shared skill text carries the generalized rule only.

## Failure shapes this layer prevents

- Promoting a rule from a comment the author argued down and never implemented (thread resolved ≠ adopted).
- Promoting the same guidance twice because the second pass did not classify against the current skill.
- Checklist bloat from treating every nit as a lesson; a reviewer's one-off preference dressed as a standard.
- Committing a model-drafted `SKILL.md` verbatim, including examples that only make sense with the source PR in view.
- Diffing the reviewer's clicked commit against the landing merge and attributing target-branch movement to "adoption".
