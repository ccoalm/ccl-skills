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

What can be said without a measurement, and is the whole basis for accepting the restoration: it
returns the description to a **superset** of its base state. The trigger existed at `1506dcf`, was
removed by this round, and is now back; the owner can only claim more than it did before, never
less, so no case that routed to it at the base can route away from it now.

The residual: the token's *value* is unmeasured in both directions. Whether it earns its place is a
question the bank cannot answer until a case exercising it is frozen, and freezing one belongs to a
round that is not also holding a baseline comparison open.
