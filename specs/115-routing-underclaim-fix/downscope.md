# Round 115 — declared downscopes

A downscope is a measurement this round decided not to produce. It is recorded here so the decision
is an artifact someone can look up and disagree with, rather than an absence nobody can see.

## `downscoped:R115-TRIGGER-RESTORE-NO-FROZEN-CASE`

Owner: `product-rd-workflow`. Change: the trigger `进入实现阶段` was removed earlier in this round
as a synonym of the surviving `方案评审通过开始实现`, and restored after adversarial review supplied
the counterexample — a request that names the transition without any approval wording.

No bank evidence accompanies the restoration, for a reason that is itself the finding: **no frozen
case exercises that token**, which is exactly why the removal could not be refuted by measurement
when it was made. The two ways to produce a number here are both worse than declaring the gap:

- Adding a case to `eval/routing-tasks.jsonl` voids every baseline comparison in this round — the
  runner treats a bank edit as a different ruler and suppresses the diff — and would also trip its
  co-change warning, which exists to catch exactly the shape of editing the test beside the skill.
- Measuring the restored token against the existing bank produces nothing, because no utterance in
  it contains the token.

An earlier draft of this file argued that the restoration is safe because the description returns to
a **superset** of its base state, so the owner could only claim more than before and no case that
routed to it at the base could route away. Adversarial review refuted that, and it was the same
mistake this round kept making: a superset in TEXT is not a superset in ROUTING. Selection is a
model reading the whole catalog, so adding a token to one description changes the input every case
is judged against and can move any of them, including away from the owner that grew.

So the restoration is unmeasured in both directions, and that is the honest state of it. What
supports accepting it is not a property of the text but the record of how it was removed: the
removal rested on a synonym argument with no case able to refute it, and adversarial review supplied
a request the surviving trigger does not match. The final re-measurement this round owes will show
whether anything else moved; until then this is a declared gap, not a bounded one.

The residual: the token's *value* is unmeasured in both directions. Whether it earns its place is a
question the bank cannot answer until a case exercising it is frozen, and freezing one belongs to a
round that is not also holding a baseline comparison open.

## Restated for the merged form

The restored token now lands merged with its neighbour as `方案评审通过·进入实现阶段` rather than as a
bare `进入实现阶段`: measured on paired probes, the bare form pulled a frozen spec-writing case toward
the requirement family (13/20 against a control of 14/20) while the merged form leaves it at 15/20
and still routes the review counterexample 20/20. The same declaration applies to the merged form
for the same reason — no frozen case exercises the token — so `downscoped:R115-TRIGGER-RESTORE-NO-FROZEN-CASE`
covers this round's wording as well.

## Probe utterances used, verbatim

- `probe-implementation-transition-no-approval` — 「方案已经定了，现在进入实现阶段」, expected `product-rd-workflow`.
  Supplied by adversarial review as the request the removed token had matched; measured on the settled
  tree at 20 replicas (20/20) and never added to `eval/routing-tasks.jsonl`. The old approval wording's
  frozen case is `p3-transition-impl` 「方案评审通过」, 20/20 on the same tree.
