# 018 — A plan's out-of-scope list carries dispositions, or the naming rots

Discharges the open item `specs/015-reviewer-lane-host-vocabulary-class/plan.md`
routed to `product-rd-workflow` plan authoring: "an out-of-scope item named in a
spec needs an owner or it rots", pending its own dual-track round. This slice is
that round.

## Artifact classification

Non-wording shared-skill change: one prose rule (two hunks) in
`skills/product-rd-workflow/references/delivery-lifecycle.md` §Plan Authoring,
plus the append-only ledger row in
`skills/skill-extraction-workflow/references/source-register.md` and this plan.
No scripts, no deterministic gates, no `SKILL.md` frontmatter or description —
the routing surface is untouched. `product-rd-workflow` is on the curated
upstream-owner list, so the impact-chain gate requires the ledger row and a
`RED-baseline` classification; the observed failure is real, so `RED-baseline`
is the only legal class.

## The defect, measured

Pre-change, nothing at plan authoring required a disposition for a named
out-of-scope item. Re-computable RED: against the base commit,
`git show <base>:skills/product-rd-workflow/references/delivery-lifecycle.md`
contains zero matches for "out of scope" — the §Plan Authoring contract has
plan-precision, task-split, and field-list rows, and no row reaches the
out-of-scope list at all.

The observed rot window, first-hand from landed slices:

- `specs/010-review-concern-excerpt/plan.md` named three items "out of scope,
  named rather than silently dropped". Nothing carried any of them forward —
  `specs/014-spec-reference-existence-gate/plan.md` records it as "prose in a
  spec that then landed. Nothing carried it forward, and only one of its two
  copies was ever found".
- All three were eventually closed, each only by a LATER slice's dedicated
  audit, and each closure contradicted the archived wording: the kimi ceiling
  was 16 KB not 47 KB and not a defect; the retention fix was drop-the-field,
  not cap-and-redact; the stale pointer closed by deletion, not by writing the
  missing file. An archived naming decays even when someone eventually reads it.

Naming was visibility, not tracking; the only reason the items closed at all is
that later slices happened to audit the same files.

## The rule landed, and its form

One bullet in §Plan Authoring: naming known work (defect observed in passing,
debt/hardening item, follow-up work) out of scope requires a disposition that
outlives the plan — an owner locator, or a declined-with-reason terminal
disposition. The duty attaches only through the known-work predicate: an
explicit "scope decisions and non-goals carry no owner duty" sentence was in the
first draft and was deleted on review round 1's finding — it was the exemption
clause the form table prohibits, a relabeling hole. An item already owned
elsewhere is not terminal by assertion: it takes the existing owner's durable
locator (round 1's second finding). Challenge round 2 tightened the locator
itself: a generic destination ("the owning skill", a team, a gate) is an
ownership assertion wearing a path — every locator form must resolve to an
item-specific durable entry that names the work — and the downstream
cross-references were reduced to pure pointers (name the instance, never its
operative requirement, which would drift). One slot added to the
assessment-plan required-field list: "the disposition of findings named but not
selected".

Form choice per `rule-consolidation.md` form-by-failure: the baseline failure is
an omitted element in an artifact the author already produces → REQUIRED slot,
keyed to an observable predicate (item is known work), not a prohibition. The
predicate scopes the rule so it cannot reach non-goals, instead of an exemption
clause.

Consolidation record: `consolidation: no candidate (new theme)` for §Plan
Authoring — mother-theme grep ("out of scope", "owner", "deferred") over
`delivery-lifecycle.md` at base returns zero rule text. The invariant's two
existing downstream instances are pointed to, not restated:
`implementation-completeness-and-minimality.md` (deferred coverage point needs a
durable follow-up locator, closeout time) and `code-review-checklist.md`
(deferred/accepted-risk items need an accepting owner in the MR description,
review time). This slice adds the missing FIRST firing point — where the naming
happens.

## RCA, widened

- (a) Missing control at the plan-authoring firing point. Counterfactual: with a
  disposition requirement, 010's items carry locators or terminal reasons at
  landing; rot prevented. Necessary and sufficient → primary control, landed.
- (b) False process-model encoded in the plan wording itself: "named rather than
  silently dropped" treats naming as tracking. Counterfactual: weaker alone;
  folded into the rule's rationale sentence ("a landed plan is an archive").
- (c) No detection walks landed plans' out-of-scope lists. A mechanical checker
  was considered and DECLINED — see out-of-scope item (a) below.
- (d) The dangling pointer itself was latent, authored earlier — separate class,
  already owned: retired for `specs/` citations by `scripts/check-spec-references.py`
  (slice `specs/014-spec-reference-existence-gate/plan.md`).
- Hindsight causes rejected: the 010 author followed the then-current convention
  exactly; the convention was the defect.

## Pre-cover axes (before challenge)

| Axis | Negative case or reasoned n/a |
| --- | --- |
| security/privacy/authority/data-loss | An item's description may be confidential; the owner-locator options include in-repo forms (status doc, owning skill/gate, successor slice), so the rule never forces egress to an external tracker; the artifact-egress gate already governs that surface. No new authority or data-loss path — prose rule. |
| concurrency & lifecycle | No runtime. Lifecycle: fires at authoring time; landed plans stay valid archives — no retroactive invalidation duty (the one live backlog was swept this round, see out item (b)). |
| resource bounds | Bounded by predicate: only named known-work items owe a disposition, and a terminal disposition costs one clause. Non-goals owe nothing. |
| rollout/migration ordering | No ordering. The rule is additive prose; no existing artifact breaks. |
| over-broad absolute | The predicate keys to known work and delimits alone. The first draft added an explicit non-goals exemption sentence; review round 1 identified it as the exemption clause the form table prohibits (a deferred item relabeled "non-goal" evades the duty) and it was deleted — the positive predicate cannot reach a non-goal, so nothing is lost. |
| enumeration-completeness | Item classes enumerated: defect observed in passing / debt or hardening / follow-up work. Locator forms enumerated open-set, each required to resolve to an item-specific durable entry (tracker row, issue, status doc, item-specific entry in the owning skill or gate, successor slice, existing owner's item-specific locator) — a bare destination is not a locator, per challenge round 2. Terminal form: declined, with reason — already-owned is a locator case, not a terminal case, per round 1. |

## Scope

In scope: the two hunks in `delivery-lifecycle.md`, this plan, the ledger row.

Out of scope, each with its disposition (this rule's own dogfood):

- (a) A mechanical checker over plans' out-of-scope lists — **terminal:
  declined**. Design-time operability legs: author-dogfood fails (out-of-scope
  lists are free prose; a checker needs a structured format, taxing every slice);
  marginal cost per routine slice is high; trust-model adds little (the list is
  author-written either way — same legs on which the lanes-recorded checker was
  declined in `specs/016-spec-citation-template-exemption/plan.md`). A future
  slice may reopen on new evidence; this plan is the record to argue against.
- (b) Retroactive audit of landed specs 010–017 for still-unowned items —
  **closed this round**: sweep found 010's three items closed by later slices
  (dispositions recorded in `specs/010-review-concern-excerpt/plan.md`), 014's
  routed follow-up discharged by 016/017, 015's open item discharged by this
  slice, and the remaining out-of-scope entries are scope decisions, outside the
  predicate. No unowned known-work item remains.
- (c) Standardizing an out-of-scope list format across spec plans — **terminal:
  declined**: plans are freeform prose by design; the slot form lands only in
  the one enumerated field list that exists (assessment-shape plans).

## Self-review row (persisted before the independent review)

- Acceptance criteria: (1) §Plan Authoring carries the disposition rule keyed to
  the known-work predicate; (2) the assessment-plan field list names the
  unselected-findings disposition slot without restating the rule; (3) both
  downstream instances are pointed to, never restated — no same-facet
  duplication; (4) no file outside the three named surfaces changes; (5)
  `check-ccl-skills.sh` passes including the impact-chain gate over the new
  ledger row and `r0_status=private-ok`.
- Changed-file scope: `skills/product-rd-workflow/references/delivery-lifecycle.md`
  (two hunks), `specs/018-plan-oos-item-disposition/plan.md` (new),
  `skills/skill-extraction-workflow/references/source-register.md` (one appended
  row). Nothing else.
- Edge/failure paths: over-fire on non-goals (bounded by the positive predicate
  alone; the drafted exemption sentence was deleted on review round 1's
  finding); under-fire on items not phrased as defect/debt/follow-up (mitigated
  by the "known work" head noun plus three-class enumeration); drift between the
  bullet and the line-110 slot (the slot names a field only, the bullet owns the
  rule); rot of the two backticked pointers (both targets exist; backticked
  prose paths outside specs/ stay review-caught — the accepted wider class per
  the ledger's 010 row).
- Known residual risks: enforcement is prose + review (checklist row at MR time
  is the detection net); no checker, by the declined-with-legs decision above.

## Review / challenge gate

Non-wording shared-skill change → tracked review→challenge pair, chain opened on
round 1. `review_gate.sh --mode review --stage release`, implementer family
`anthropic` (implementer is Claude; reviewer lanes exclude the family),
`--review-chain-id` fixed for the slice, `--autonomous-review-index` contiguous,
each later round carrying every prior result file. Convergence: no
undispositioned P0/P1 and a fresh full challenge of the exact landing candidate.

Rounds are appended below as they complete.

### Rounds

- **Round 1 — review, codex, `status=findings`, 3×P1, all accepted.** (chain
  `oos-owner-018`, index 1, stage release, base ec8b2a2, plan
  implementer-supplied, native skill binding established, secret scan clean.)
  (1) The "scope decisions and non-goals" sentence was the prohibited exemption
  clause — a deferred item relabeled "non-goal" evades the duty; fixed by
  deletion, the positive predicate delimits alone. (2) "Already-owned, with the
  reason" as terminal recreated the target failure — an unfindable ownership
  assertion; fixed by folding already-owned into the locator branch (cite the
  existing owner's durable locator) and reserving reason-only terminal for
  declined. (3) The plan cited checker success as acceptance without recorded,
  recomputable evidence; fixed by the "The RED, recomputed" section below and
  this rounds record. Fixes landed as a new commit on top of the reviewed
  candidate (201cda9), per the findings-fix commit discipline, with the ledger
  append split into its own commit so each impact-chain round carries its row;
  the round-1 ledger row stays as landed, superseded by pointer from the
  appended round-2 row (append-only, never edited — the first attempt edited it
  and the impact-chain gate rejected the round).

- **Round 2 — challenge, codex, `status=findings`, 3×P1: two accepted, one
  declined with reason.** (chain `oos-owner-018`, index 2, challenge-index 1,
  full adversarial focus over the exact landing candidate.)
  (1) Accepted: "the owning skill or gate" as a locator form admits a generic
  destination holding no item-specific record — an ownership assertion wearing
  a path; fixed by requiring every locator form to resolve to an item-specific
  durable entry that names the work. (2) Accepted: the bullet restated the
  downstream instances' operative requirements (drift risk, and a violation of
  this slice's own acceptance criterion 3); fixed by reducing both to pure
  pointers that name the instance only. (3) **Declined, with reason**: the
  proposed fix — controller-captured checker output bound into the review
  packet — is the digest-bound evidence apparatus the impact-chain gate
  evaluated and removed (recorded in its own ledger row: per-iteration
  regeneration cost), and verification of the checker claims is already
  mechanical outside the packet: `check-ccl-skills.sh` (impact-chain verdict,
  `r0_status`) is recomputed on the exact candidate by the server-side gate at
  merge time, so a false prose claim cannot land — the plan's prose is a
  record, not the enforcement surface. The kernel of the finding (prose is not
  proof) is honored by transcribing the final gate output verbatim into the
  Landing state below, labeled as author-transcribed.

## The RED, recomputed (round-1 finding 3)

Run from the worktree, base pinned at ec8b2a2:

- `git show ec8b2a2:skills/product-rd-workflow/references/delivery-lifecycle.md | grep -c -i "out of scope"`
  → `0` (exit 1, no match): the base plan-authoring contract carries no
  out-of-scope rule text.
- `git show ec8b2a2:specs/010-review-concern-excerpt/plan.md | sed -n '55p'`
  → `Out of scope, named rather than silently dropped:` — the naming, with no
  disposition mechanism.
- `git show ec8b2a2:specs/014-spec-reference-existence-gate/plan.md | sed -n '29p'`
  → `| naming it out-of-scope in \`010\`'s Scope | prose in a spec that then
  landed. Nothing carried it forward, and only one of its two copies was ever
  found |` — the recorded outcome of that naming.
- `git show ec8b2a2:specs/015-reviewer-lane-host-vocabulary-class/plan.md | sed -n '418,419p'`
  → the open item this slice discharges ("…needs an owner or it rots — to
  \`product-rd-workflow\` plan authoring, pending its own dual-track round").
- Sweep (010–017): every named out-of-scope item is either closed by a later
  slice with its disposition recorded in `specs/010-review-concern-excerpt/plan.md`,
  a scope decision outside the predicate, or the 015 open item discharged here.
- `check-ccl-skills.sh` on the candidate: `ccl_skill_check_clean_ok` with
  `r0_status=private-ok` (private alias audit ran to `alias_audit_ok`; range
  origin/dev..HEAD + worktree; profiles process-retro + 10 alias files) and the
  impact-chain gate green over the appended ledger row — rerun after every fix
  commit; the Landing state section records the final run.

## Landing state

Interim: rule drafted, self-review row persisted, ledger row staged; round 1
findings applied; review rerun and challenge lanes pending.
