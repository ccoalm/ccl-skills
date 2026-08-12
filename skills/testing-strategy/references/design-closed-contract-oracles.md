# Design Closed-Contract Oracles

Mechanics for the entry rule's closed-boundary positive-assertion obligation and its oracle-dimension and precision companions in `SKILL.md` (Core Rules). The obligations themselves — assert the boundary positively, report the dimensions an oracle crossed, keep benign near-miss rows — and the canonical dimension list live in the entry; this file owns the failure shapes and per-dimension explanations.

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
