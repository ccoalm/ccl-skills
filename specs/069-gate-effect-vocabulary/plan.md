# 069 — Gate effect vocabulary and loading-budget margin repair

## Artifact classification

`gate implementation` (two shared deterministic gates, both with rule/completion-semantics
changes). Target branch: `dev` (both gates exist only on dev; this round is a prerequisite
for the pending dev→main promotion). Risk route: `shared-gate` (feature-risk-router);
`security-review: not-applicable — security posture unchanged`; `visible surface: no`.

## Problem

1. **Deletion recorded as "strengthened".** `obligation-ledger.py` restricts `effect` to
   `{preserved, strengthened, unresolved}` and forces `retired-dead` rows (and, via the
   partition rule, every `partial-retirement` row) to close as `strengthened`. In the 065
   ledger this labels 123 carrier-less deletions (98 retired-dead + 25 partial-retirement)
   as `strengthened`; the rendered summary (`Effects: preserved=657, strengthened=583,
   unresolved=0`) reads as zero obligation loss.
2. **Zero-margin budget.** `test_uiux_loading_budget.sh` caps the direct-runtime profile at
   90% of the base mandatory bytes; the measured value is exactly at the cap
   (58860 = 58860, margin 0 bytes). Any future byte added to `SKILL.md` or
   `delivery-contract.md` turns the gate red, converting a migration budget into a de-facto
   document freeze.

## Scope

- `skills/skill-extraction-workflow/scripts/obligation-ledger.py`
  - Add `retired` to `EFFECTS`.
  - `retired-dead` rows: `effect` must be `retired` or `unresolved` (no longer
    `strengthened`).
  - Partition rows: expected effect is `retired` when any part has status `retired`
    (i.e. every `partial-retirement` row); otherwise unchanged
    (`strengthened` if any part strengthened, else `preserved`).
  - `retired` requires `manual_reviewed: true` (same bar as `strengthened`).
  - Rendered summary line gains `retired=<n>`.
- `specs/065-uiux-evidence-delivery/obligation-mapping.jsonl`: relabel the 123 deletion
  rows to `effect: "retired"`; no other field changes.
- `specs/065-uiux-evidence-delivery/obligation-preservation.md`: regenerate via
  `obligation-ledger.py render` (generated file; audit compares byte-identical).
- `skills/skill-extraction-workflow/scripts/test_obligation_ledger.sh`: RED-first cases for
  the new rules; update fixtures that used `strengthened` on deletions.
- `skills/skill-extraction-workflow/scripts/test_uiux_loading_budget.sh`: direct-runtime
  cap 90% → 95% with a recorded rationale; comment states the migration-assertion nature
  and measured values at cap-setting time.

Out of scope: proof-mode vocabulary, part-level effect values, the routing (50%) and
specialized (110%) caps (both have non-zero margins: 3055 and 1285 bytes), any
`skills/**/*.md` content change.

## Decisions (with rejected alternatives)

1. **Forbid `strengthened` on deletions rather than merely allowing `retired`.**
   Rejected: permissive dual vocabulary — it perpetuates the euphemism and there is exactly
   one ledger instance, on dev only, relabeled in this same slice. A breaking rule now has
   zero compatibility cost; after promotion to main it would need a migration.
2. **`partial-retirement` rows close as `retired`, not `strengthened`.** Any retired part
   means part of the obligation was deleted; the surviving parts are already individually
   labeled. Rejected: a fourth "mixed" value — adds vocabulary without adding information.
3. **Budget cap 95% instead of retiring the test.** The three profiles still prove the
   migration claim (split reduced mandatory loading vs the immutable base e322db4); the
   direct profile measured 90.0% when the cap was set, so the cap encoded no headroom.
   95% gives ~3270 bytes for living-document growth while still asserting the direct path
   is cheaper than the pre-split mandatory load. Rejected: full retirement — the other two
   profiles still bind usefully and removal is a larger semantics change than this round
   needs; revisit at dev→main promotion if the migration claim is deemed historical.

## Acceptance decision table (verdict mapping)

### obligation-ledger audit

| # | Input row shape | Verdict |
|---|-----------------|---------|
| A1 | `retired-dead`, `effect: retired`, `manual_reviewed: true`, authority/scope note | `audit_ok` |
| A2 | `retired-dead`, `effect: strengthened` | fail `RETIRED_EFFECT_INVALID` |
| A3 | `retired-dead`, `effect: retired`, `manual_reviewed: false` | fail `MANUAL_REVIEW_REQUIRED` |
| A4 | `partial-retirement` (schema 4), `effect: retired` | `audit_ok` |
| A5 | `partial-retirement`, `effect: strengthened` | fail `PARTITION_EFFECT_MISMATCH` |
| A6 | `partitioned` (no retired part) with a strengthened surviving part, `effect: strengthened` | `audit_ok` (unchanged) |
| A7 | `rehosted`, `effect: retired` | fail (carrier rules unchanged; `retired` valid only on deletion shapes) |
| A8 | real 065 mapping after relabel + re-render | `audit_ok`, summary shows `retired=123`, `strengthened=460`, `preserved=657` |

### loading-budget

| # | Input | Verdict |
|---|-------|---------|
| B1 | current dev docs (58860 bytes direct) | pass, margin ≈ 3270 bytes |
| B2 | direct profile grown past 95% of 65400 (mutation: router-shrink + contract-pad, so only the direct cap trips) | FAIL |
| B3 | existing mutation cases (always-load rewrites etc.) | unchanged FAIL |

## Test/register coverage

- Unit (synthetic fixtures): `test_obligation_ledger.sh` — new cases A1–A7 run RED against
  the unmodified tool first, then GREEN after the change.
- Integration (real repo): `test_obligation_ledger_repo_audit.sh` — covers A8 via the
  pinned-base byte-identical audit.
- Gate self-test: `test_uiux_loading_budget.sh` run; B2 first verified by a one-off local
  mutation (router-shrink + contract-pad, killing the 95% predicate specifically), then —
  after a review finding that a one-off kill cannot catch later silent weakening — encoded
  in-suite: the caps move into pinned variables, the 50/95/110 contract is asserted, and a
  threshold probe walks each predicate at cap and cap+1.
- Full lane: `test_check_ccl_regressions.sh` with `CCL_SKILL_BASE_REF=origin/dev` before
  push; CI green on the PR is the merge gate.
- E2E/runtime/manual: not applicable — no runtime or rendered surface.

## Status sync

No external tracker or status doc owns these gates; this plan file plus the PR description
are the status surface. The dev→main promotion round consumes this plan as the record that
the two pre-promotion debts are repaid.

## Review-round addendum

Dual-track ran with a fixed 1+1 budget (chain 069-gate-vocab-r4; evidence in
`.work/review-evidence/069-gate-vocab/`). Dispositions:

- Review P1 "retired rows escape the manual-review guard": **refuted** empirically —
  flipping one real partial-retirement row's `manual_reviewed` to false fails the
  pinned-base audit (`MANUAL_REVIEW_REQUIRED`, schema4 partition entry check); hardened
  into the suite as the `partition_unreviewed` mutant.
- Review P2 "the 95% predicate's kill was off-suite": **applied** — cap variables, contract
  pin, and the in-suite threshold probe above.
- Challenge P1 "mixed partial retirements lose the strengthened surviving dimension":
  **applied** — 24 of the 25 real rows are mixed; the renderer now emits part-level
  outcome counters, and the fixture pins a mixed row's counts.
- An earlier review lane flagged the packet (checker-summary in place of raw mapping
  edits) as an input defect; the packet was widened with a lossless field-projection diff
  and the generated ledger's word-diff, then rerun.

## Review gate

Independent adversarial review of the final diff (model-family-independent CLI reviewer per
`code-review` routing) recorded before push; findings dispositioned, not waived. Merge of
the PR requires the user's explicit instruction (worktree-isolation).

## Boundary record

- Active baseline: this plan (specs/069-gate-effect-vocabulary/plan.md) on
  `worktree-069-gate-vocabulary` (from origin/dev 5d2b192).
- Implementation-mechanics owner: `skill-extraction-workflow` (shared-skill gate suite),
  loaded in-session; test-layer matrix owner: `testing-strategy`, loaded in-session.
- `multi-agent-delegation`: local — two files with tight data coupling (relabel must match
  the rule change and the re-render), no independent parallel slices.
- Design checkpoint: not applicable (`visible surface: no`).
- Test-case-first: acceptance table above precedes implementation; A2/A3/A5 are the RED
  cases.
