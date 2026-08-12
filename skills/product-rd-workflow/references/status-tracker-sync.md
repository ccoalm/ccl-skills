# Status tracker sync

Use this reference when a delivery changes shared product status, roadmap, verification state, cross-repository readiness, or any repo-local status source that a future agent may consume.

## Human-facing status docs

When the delivery changes shared product status, roadmap, verification state, or cross-repository readiness, update the owning product/status document in the same delivery batch after the code MR lands.

Keep it factual and evidence-based:

- Linked review artifact.
- Merged state.
- Pipeline result.
- Verified commands.
- Remaining risk.

Do not let product docs claim stale pending work after implementation has landed.

Implementation-progress fields embedded inside a spec, design doc, or ADR (per-section implemented/pending/done markers) are status surfaces under the same rule: flip them in the same PR/batch that lands the implementation — status drift repaired by after-the-fact "sync status" batches is the failure shape this prevents. Discovery of these surfaces is not optional: a slice delivering against an owning spec/design doc/ADR includes a status-surface inventory in its readiness evidence (grep the owning docs for embedded progress markers and as-built divergence), with `none found` recorded as an explicit checked result — otherwise the same-batch rule never fires because nobody looked. Better still, avoid embedding mutable progress fields in prose docs at all: point the doc at the single owning tracker/ledger so status has one writer. (An ADR's decision `Status` field is decision lifecycle, not delivery progress, and stays in the ADR.)

The "after the code MR lands" rule applies to the human-facing / shared status doc.

## Agent-consumed status-doc rule

A tracker that is **agent-consumed** — an executing agent reads it to orient on current state and next action — is part of the work itself, not a follow-up.

Land it by state:

- **Shared landing**: status is in the same final shared change-set or orchestrated batch. Cross-repo work is cross-linked and not complete until both sides land.
- **Local handback**: status is in the same local diff/patch or reported `pending` with owner.
- **RED/WIP commits**: tracker is not required per commit, but must match the final handed-off, green, or shared state. Never code-first-status-after.

## Final-state gate

Before merge, and after any reviewer edit, squash, rebase, or platform-side merge, re-validate the tracker against the final diff/ref/CI.

A behavior-changing implementation row may become `complete` only when both closure tables are present, the acceptance IDs reconcile to the active source, and no blocking row remains in either table (a concept-delta `simplify`/`remove` decision not reflected in the final diff is blocking); a documentation-only row records the reviewed two-axis `not-applicable`, and a pure-refactor/mechanical-maintenance row records functional-axis `not-applicable` plus its concept-delta table. Record the closeout artifact and reviewed diff identity; missing or stale closure evidence keeps the row pending.

The tracker can be fresh at push and stale at merge. Point status at the final landed ref, not the pre-squash branch commit.

## Live tracker shape

Keep the tracker on the agent's read path: a repo-local file that the agent contract points to.

Keep the live tracker compact:

- Exactly one current state.
- Exactly one next action.
- Only the risks/blockers affecting the next slice or current acceptance.
- Each risk/blocker has owner and stale-after.

Closed, mitigated, and background items move to history, not the live doc.

Do not use a raw append-only checkpoint log as the live tracker. It buries the next action and duplicates VCS history.

## Delivery-status ledger (multi-repo / remote-state delivery)

The entry-precedence rule in `SKILL.md` requires this ledger for multi-repo delivery or any delivery that changes remote branch / MR / pipeline / release / deployable-artifact state. Keep one row per changed unit:

- target branch; local/remote sync state; artifact or commit state; verification state (`not-run`, `running`, `pending`, `success`, `failed`, `blocked`, `inconclusive`, `not-applicable`, or `not-required`); MR/main-dev state; cleanup state; residual risk; next action.
- **Set-completeness reconciliation.** The ledger's rows must equal the *intended* set of changed units, not merely the units the batch happened to touch. Before any "all N / every / done / current" claim over an enumerable set (e.g. repo sweep, multi-file edit, fan-out, per-member bump), re-derive each member's actual post-state from **ground truth** — re-scan the targets themselves (the repos/files/refs) — NOT from the batch loop's own success output: a hand-maintained ledger, or a loop whose item list silently lost an entry, under-counts without erroring, and the drop is often already visible as a count mismatch (a claim of N against N−1 executed rows is the tell). Assert `intended set == covered set` and keep the re-derived coverage table as the evidence the check fired. "The loop ran over the list" is not proof the list was complete; the reconciliation, not the loop, is what licenses the "all N" claim.
- When a final/status response covers remote-state delivery and could be read as completion, split **Agent jobs** from **External async waits**. Agent jobs cover tracked subagents/workers only. External async waits are open-ended — such as MR/PR pipelines, CI jobs, platform reviews, deploys, canaries, release promotions, data migrations/backfills, async callbacks, artifact/package publish propagation, or external tracker waits; a background job board showing no active agent jobs does not prove there is no pending work. For each external wait, record the object/link, branch/ref/head SHA, pipeline/job/deploy/canary/review id, last known state with evidence source/time, and the next gate or owner/unblock action. A pending/running external wait keeps completion and merge recommendation pending unless the owning workflow explicitly records a safe deferral; a failed external wait remains failed until resolved, or until the merge-authorization gate records user acceptance of that non-green state for the specific object and head SHA.

Persistence: for a short batch the ledger may be reported in the final response as closeout evidence; but if it will guide a later slice, persist it in a repo-local/status artifact (or an explicit external tracker) before using it as the continuation baseline — chat (including the prior final response) is not a continuation baseline. The blocking required-gate rule and the merge-authorization boundary (residual-risk acceptance is not merge authorization) stay in the `SKILL.md` entry-precedence bullet.

## Durable decisions

Route must-not-lose decisions to a durable record with path/link and owner:

- ADR.
- Stable-path changelog.
- Spec decision log.
- Policy-durable issue/MR permalink.

A squashable MR comment/log is not durable unless mirrored into one of those records.

Human-facing rollup may live in a tracker or milestone. It is not the agent's continuation truth, and the two do not copy each other.
