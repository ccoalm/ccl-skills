# Design Closed-Contract Oracles

Mechanics and full rules for the closed-boundary positive-assertion obligation and its oracle-dimension and precision companions referenced from `SKILL.md` (Core Rules).

- Mirror the **documented** contract with an independent oracle; don't snapshot a generated/runtime allowlist (that becomes a change-detector). Negative/adversarial cases stay valid — they prove out-of-contract input is rejected. Acting signal: when an adversarial reviewer keeps surfacing a *new instance of the same bypass class* across rounds, prefer an allowlist/invariant that closes the class over banning one more value, and prove it with a mutation where feasible (a boundary-violating change must make the test fail).
- **A clean oracle is clean only over the DIMENSIONS it crossed, not the cases it ran.** A clean run must be reported with the dimensions it covers, and before trusting it you must enumerate the dimensions themselves and mark each crossed or not: the **shape** of a value; its **provenance**; **cardinality**; **semantics**; and **ordering** where the consumer is order-sensitive.
- **A guard's cases must pin PRECISION as well as recall — the false-positive direction is where hardening turns into an outage.** Keep benign near-miss cases — inputs that share a prefix, substring, or shape with the violating class and must pass — as permanent rows next to the violating ones, so a later tightening that over-fires turns a row RED instead of shipping.

What makes the oracle's own two companions worth a rule rather than a habit: both the uncrossed-dimension gap and the unpinned-precision gap fail silently in the clean direction — the oracle reports green either way, so nothing in the run itself tells you the gap is there.

## Why A Denylist Cannot Prove A Closed Boundary

A denylist of forbidden values is open-ended — variadic, `=`-glued, aliased, and future spellings all slip past a value list — so the gate passes while the boundary is actually violated: a false green. Checking the parsed result or output without the inputs/argv that produced it is the same gap.

If the allowed set is dynamic or not yet codified, record it as accepted/deferred risk and assert the strongest stable invariant until the contract can be closed.

This obligation is distinct from asserting a documented denylist/allowlist *entry* that is itself the contract (the change-detector exception in the entry rule) — that literal stays.

## Per-Dimension Explanations

The entry rule's canonical dimension list — shape, provenance, cardinality, semantics, ordering — is what a clean oracle report must enumerate, because enumerating more values inside a dimension you already thought of buys nothing against the dimension you did not; a matrix can be exhaustive and still blind, and it reports clean either way. What each dimension catches:

- **shape**: the form of a value.
- **provenance**: which of the inputs are attacker- or upstream-controlled — a check that sanitizes one untrusted string and interpolates its neighbour raw is the recurring shape.
- **cardinality**: zero / one / repeated occurrences of the same record, where a per-item rule silently becomes a union rule.
- **semantics**: a token that looks like the thing is not the thing — the one version-shaped number in the output may be a build date.
- **ordering**: where the consumer is order-sensitive.

Failure shape: four consecutive rounds on one gate, each with a clean matrix, each blind to exactly one dimension not yet crossed.

## Precision Near-Miss Rows

The entry rule requires benign near-miss cases kept as permanent rows next to the violating ones. Why hardening drifts the other way: a fix that widens a guard is tested with more violating inputs, so it converges on recall and nothing records what must still be ACCEPTED; the next tightening then rejects legitimate traffic and reads as a stricter, safer check. Relationship to `skill-extraction-workflow`'s dual-track gate: the false-positive sweep the gate requires at fix time is a step someone must remember — the rows are the durable half, visible when missing.

Failure shape: adding short generic stems to a substring denylist, which would have classified benign metadata as a violation and taken every consumer down — introduced by the safety fix itself.
