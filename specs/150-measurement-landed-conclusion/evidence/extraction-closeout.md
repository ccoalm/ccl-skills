# Closeout — a measurement is a landed conclusion too

**Charter depth:** targeted check, scope explicitly narrowed to one failure class and accepted.
**Result class:** failure/correction — a published finding had to be withdrawn.

## What landed

| surface | change |
|---|---|
| `skill-extraction-workflow/SKILL.md` | third form added to the landed-conclusion enumeration, on both the authoring and the reviewing half; one now-inaccurate count word corrected |
| `references/validation-and-landing.md` | the measurement control leg as three named obligations — power, demonstration, binding |
| `references/source-register.md` | one impact-chain row, `RED-baseline; observed-failure: yes` |

Entrypoint size and word budgets are net-neutral: the diagnosis form's search-hit illustration moved
to the reference alongside the new detail.

## Owner dispositions

| owner | status | reason |
|---|---|---|
| `skill-extraction-workflow` | updated | owns the landed-conclusion rule |
| `testing-strategy` | unchanged — routed | its oracle rules govern a clean run's dimensions, i.e. verdicts from tests the agent owns; this failure was a claim about the subject |
| `defect-diagnosis` | unchanged | the diagnosis form already existed; this round extends the same rule |
| `product-rd-workflow` | unchanged | no delivery-stage gate changes |
| installed external packs | reference-only | none owns "an instrument's output becomes a claim" |

## Second candidate — not landed

Tests naming properties their fixtures could not pin: `unchanged — already-covered`,
`observed-failure: yes`, firing path proven — the killing-mutation walk caught 3 of 3 instances
(a surviving mutation, a case green for an unrelated coupled reason, and sample values that agreed
under both implementations). A gate that demonstrably fires needs no new rule.

## Convergence

Final pair on this candidate: review `passed`, challenge `passed`, no findings. Seven earlier rounds
produced 2 P1 and 5 P2, each fixed, refuted against file evidence, or declined with a recorded
reason. Round 3 was a `replace` decision rather than a third patch: the enumeration of good-arm
properties was replaced by the invariant, because each prior fix had re-instantiated the same
predicate on new inputs.
