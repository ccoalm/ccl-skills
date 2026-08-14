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
existing downstream instances are pointed to, not restated: the deferred-point
rule in `implementation-completeness-and-minimality.md` (closeout time) and the
accepted-risk/deferred-items row in `code-review-checklist.md` (review time).
This slice adds the missing FIRST firing point — where the naming happens.

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
| enumeration-completeness | Item classes enumerated: defect observed in passing / debt or hardening / follow-up work. Locator forms enumerated open-set, each required to resolve to an item-specific durable entry (tracker row, issue, status doc, item-specific entry in the owning skill or gate, existing successor slice carrying the item as in-scope work, existing owner's item-specific locator) — a bare destination is not a locator (challenge round 2), and a successor slice counts only when it exists and takes the item as in-scope work (challenge round 3). Terminal form: declined, with reason — already-owned is a locator case, not a terminal case, per round 1. |

## Scope

In scope: the two hunks in `delivery-lifecycle.md`, this plan, the appended
ledger rows, and the retroactive sweep of landed specs 010–017 for still-unowned
out-of-scope items — performed this round, not deferred (moved here from the out
list on challenge round 3's finding: "closed this round" is not a disposition
the rule permits for an out-of-scope item, and work actually performed belongs
in scope). Sweep result: 010's three items were closed by later slices
(dispositions recorded in `specs/010-review-concern-excerpt/plan.md`), 014's
routed follow-up was discharged by 016/017, 015's open item is discharged by
this slice, and the remaining out-of-scope entries are scope decisions outside
the predicate. No unowned known-work item remains.

Out of scope, each with its disposition (this rule's own dogfood):

- (a) A mechanical checker over plans' out-of-scope lists — **terminal:
  declined**. Design-time operability legs: author-dogfood fails (out-of-scope
  lists are free prose; a checker needs a structured format, taxing every slice);
  marginal cost per routine slice is high; trust-model adds little (the list is
  author-written either way — same legs on which the lanes-recorded checker was
  declined in `specs/016-spec-citation-template-exemption/plan.md`). A future
  slice may reopen on new evidence; this plan is the record to argue against.
- (b) Standardizing an out-of-scope list format across spec plans — **terminal:
  declined**: plans are freeform prose by design; the slot form lands only in
  the one enumerated field list that exists (assessment-shape plans).

Decision state for both declines (tightened on the h2 challenge finding —
ratification-by-merge names no made decision, and a bare authority name is not
a decision): both are **proposed declines, pending the explicit decision of the
identified decision owner** — the repository risk owner, who was asked directly
in this round's delivery report. Until that decision is recorded here, both
items are OPEN known work whose item-specific entry is this list. When the
decision arrives, this paragraph records it verbatim-adjacent (decision, date,
by whom) as the durable decision record the rule requires.

## Self-review row (persisted before the independent review)

- Acceptance criteria: (1) §Plan Authoring carries the disposition rule keyed to
  the known-work predicate; (2) the assessment-plan field list names the
  unselected-findings disposition slot without restating the rule; (3) both
  downstream instances are pointed to, never restated — no same-facet
  duplication; (4) no file outside the three named surfaces changes; (5)
  `check-ccl-skills.sh` passes including the impact-chain gate over the new
  ledger row and `r0_status=private-ok`.
- Changed-file scope: `skills/product-rd-workflow/references/delivery-lifecycle.md`
  (two regions — the disposition bullet, evolved across rounds 1–5, and the
  field-list slot), `specs/018-plan-oos-item-disposition/plan.md` (new),
  `skills/skill-extraction-workflow/references/source-register.md` (five
  appended rows, one per impact-chain round). Nothing else. (Row refreshed
  before the human-granted extension chain ran; the original row predates the
  first review round, per the ordering rule.)
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

- **Round 3 — challenge, codex, `status=findings`, 4×P1: three accepted, one
  declined with reason.** (chain `oos-owner-018`, index 3, challenge-index 2,
  fresh full pass with reachability/operability/dogfood angles added.)
  (1) Accepted: "a successor slice that names it in scope" admits a
  nonexistent future slice — the ownership-assertion class again; narrowed to
  "an existing successor slice that carries it as in-scope work". (2)
  **Declined, with reason**: the reachability finding asked for
  entrypoint-routing evidence in the packet or an entrypoint edit; the routing
  already exists and is verifiable in-repo — `skills/product-rd-workflow/SKILL.md`
  step 3 routes to §Plan Authoring at three firing moments: plan depth ("model
  in `references/delivery-lifecycle.md` §Plan Authoring", L103), the formal-plan
  upgrade decision ("conditions in ... §Plan Authoring", L106), and the
  assessment-plan fields ("required fields in ... §Plan Authoring", L130) — the
  reviewer's no-tools posture cannot see unchanged lines, and adding entrypoint
  text for a rule already routed three times would violate the
  anti-monotonic-growth discipline; this rule's reachability equals its section
  peers', and that residual is recorded rather than patched. (3) Accepted:
  this plan's own out item (b) was dispositioned "closed this round", which the
  landed rule does not permit for an out-of-scope item — the sweep was actually
  performed, so it moved into in-scope completed work (the finding caught the
  plan violating its own rule; the dogfood held). (4) Accepted: the Landing
  state was stale against the rounds record; rewritten with the transcribed
  gate output.

- **Round 4 — challenge, codex, `status=findings`, 4×P1: one accepted, three
  declined as one already-dispositioned class.** (chain `oos-owner-018`,
  index 4, challenge-index 3, final-angle focus incl. challenging the prior
  declines themselves.)
  (1) Accepted: this plan's own narrative still carried two parenthetical
  restatements of the downstream instances' requirements; trimmed to instance
  names. (2)–(4) **Declined, one class, disposition unchanged and re-verified
  candidate-relative**: all three re-raise the packet-completeness demand —
  controller-captured, digest-bound evidence (base-revision excerpts, gate
  output, entrypoint lines) inside the bounded packet. The class was
  dispositioned in round 2 and again in round 3: the digest-bound evidence
  apparatus was evaluated and REMOVED by the impact-chain gate's own recorded
  design decision, and enforcement lives in the merge-time recomputation on the
  exact candidate, which a no-tools packet reviewer structurally cannot see.
  Candidate-relative re-check: every cited revision (ec8b2a2, e567986, b34fc58)
  is a branch commit any tooled verifier recomputes; the three entrypoint
  routes are quoted verbatim with line numbers in the round-3 record of this
  plan, which is itself inside the packet. Per the repeated-same-class design
  rule, the keep/delete decision is recorded: **keep-absent** — the recurring
  finding pushes against a design boundary the owning gate already decided and
  documented; re-opening it per round would rebuild the removed apparatus.

- **Round 5 — challenge, codex, `status=findings`, 1×P1, accepted; budget
  exhausted.** (chain `oos-owner-018`, index 5, challenge-index 4 — final
  budgeted round.) The finding is a genuinely new class and aligns with the
  sibling instances' existing bar: an ownerless status-document entry is a
  second archive, and a plan author's unilateral "declined, with the reason" is
  termination without authority (the closeout instance already requires the
  active product or human source to make out/deferred decisions; the review
  instance already requires an accepting owner). Fixed: the locator's durable
  entry must name the work and its accepting owner; a terminal decline names
  the deciding authority or its durable decision record. **Because this fix
  lands after the fifth round, the post-fix candidate has had no fresh full
  challenge. The slice is therefore interim at the exhausted-budget checkpoint:
  the parked human decision is to grant a fresh challenge round on the final
  candidate, or to accept it as-is.** Post-budget deep self-review of the fix,
  walked against every prior finding class: no exemption clause added; the
  accepting owner is named inside the durable entry, not asserted in the plan;
  the already-owned and successor-slice forms inherit the head requirement; the
  terminal form now matches the closeout instance's authority bar without
  restating it; the field-list slot is untouched.

- **Extension chain `oos-owner-018-h2`, granted by the human risk owner**
  (in-session instruction, 2026-08-14) after the exhausted-budget checkpoint:
  a fresh tracked review→challenge pair on the exact final candidate.
- **h2 round 1 — review, codex, `status=findings`, 3×P1 + 1×P2: two accepted,
  two declined.** (1) Accepted, and the dogfood bit the author again: this
  plan's two terminal declines named no deciding authority — the exact form
  round 5 prohibited; fixed by the authority paragraph under the out-of-scope
  list (proposed here, decided by the risk owner whose merge is the durable
  decision record). (2) Accepted: the landing gate lacked the human decision
  it was parked on; the grant and this chain's outcomes are now recorded. (3)
  Declined: packet-completeness class, fourth appearance; the keep-absent
  decision stands as recorded in the round-4 entry above. (4) Declined (P2):
  consolidating the five ledger rows into one would break the machine-enforced
  per-round row obligation and the append-only contract (the impact-chain gate
  rejected exactly the edit-in-place shape earlier in this slice); reader
  navigation is carried by each row's explicit supersede-by-pointer clause.

- **h2 round 2 — challenge, codex, `status=findings`, 1×P1, accepted in both
  halves.** Naming is not accepting: (rule half) the locator's durable entry
  must RECORD the accepting owner's acceptance, and a terminal decline must
  CITE the decision's durable record — a bare owner or authority name was one
  more assertion costume, and the sibling closeout instance already carries
  exactly this made-decision bar; (plan half) this plan's own
  ratification-by-merge paragraph named a future merge, not a made decision —
  replaced by proposed-declines-pending-explicit-decision, with the identified
  decision owner asked directly in the delivery report and the answer to be
  recorded here. The items stay open until then, so nothing is terminated by
  the author's assertion.

- **h2 round 3 — challenge, codex, `status=findings`, 1×P1: valid, and
  resolvable only by the risk owner.** The two proposed declines sit in this
  plan's own out-of-scope list with no recorded decision or acceptance; once
  the plan lands it is an archive, so by the letter of the rule this slice
  lands with two unowned known-work items — the exact prohibited path. The
  finding's fix requires the risk owner's explicit durable decisions before
  landing. The decisions were put to the risk owner directly in the delivery
  report of this round; their verbatim-adjacent record (decision, date, by
  whom) lands in the paragraph under the out-of-scope list, resolving this
  finding, before any integration. The dogfood conclusion is itself evidence
  the rule works: the slice cannot land while its own out-of-scope items are
  ownerless.

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

Rounds completed: review (index 1, findings applied), challenge (index 2,
findings applied; one declined with reason), challenge (index 3, findings
applied; one declined with reason), challenge (index 4, one applied; three
declined as one recorded class), challenge (index 5, one applied — the Agent
budget's final round). The parked decision was resolved: the human risk owner
granted a fresh extension chain (`oos-owner-018-h2`, in-session instruction,
2026-08-14). h2 review completed (two accepted fixes above, two recorded
declines); the h2 fresh full challenge of the exact final candidate closes the
gate — its result is recorded here before any merge. Every finding across all
rounds is dispositioned (fixed, or declined with a recorded reason).

Gate output, author-transcribed, from `check-ccl-skills.sh` run against this
candidate tree (rule, ledger rows, and this section's text included; the
merge-time server gate recomputes the same verdicts on the final candidate —
that recomputation, not this transcription, is the enforcement):

```
alias_audit_ok
r0_status=private-ok
ccl_skill_check_ok
ccl_skill_check_clean_ok
```

impact-chain: green (each round's ledger row declared in its own round; the
gate's earlier rejections of the edited-in-place row and of the missing
normative anchor are recorded in the rounds narrative above).
