# Attribution Verification

Author-method / project-method pairings drafted from training-data recollection have a high error rate. The SKILL.md entrypoint states the rule and the hard triggers; this file is the operational mechanism: the failure shapes you are watching for, the implicit-attribution surfaces that bypass naive checks, the source-quality bar, and the pending-row workflow when verification cannot complete in this commit.

## Why This Rule Exists

Claims of the form "X is known for Y", "Y was originated by X", "X 提出 Y", "X cheatsheet / heuristic / method", or any other author-method / project-method pairing have a high error rate when drafted from training-data recollection. Independent review (codex / external fact-check) catches this class routinely. The rule below removes the need for adversarial review to find these one by one.

## Common Failure Shapes

- **Famous-adjacent attribution**: attributing a method to the most famous adjacent author rather than the actual originator — e.g., attributing a method to a popular practitioner when the meeting / origin was a different person years earlier.
- **Wrong standard part number**: citing a standard's part / year / clause number incorrectly. The standard exists; the citation does not.
- **Heuristic conflation**: conflating an author's well-known heuristic with unrelated folklore in the same field. Both sources exist; the pairing is invented.

## Attribution-Required Test

### Hard Triggers (Always Required)

Attribution is REQUIRED whenever the claim names any of:

- **Origin** — who first proposed / wrote / invented X
- **Chronology** — when X was first proposed / published / standardized
- **Standard version** — RFC / ISO / IEEE / PEP part / year / clause numbers
- **Authority** — "X is the recommended way to do Y per <named authority>"
- **Named methodology lineage** — X is a variant / derivative / successor of Y

### Secondary Heuristic (Load-Bearing Test)

Apply this ONLY when no hard trigger fires. If removing the named source materially weakens the rule's force, attribution was load-bearing and is still required.

### Generic-Framing Carve-Out

"Generic framing" ("业内常用" / "industry practice" / "commonly recommended") is acceptable ONLY when the executable guidance stands without any authority claim. If the rule needs a name to be believed, you cannot generic-frame it.

## Implicit Attribution Counts

Agents cannot bypass the rule by moving the claim to a header or bibliography line. All of the following count as attribution claims and need the same verification:

- Section placement (a rule under a heading named after an author / framework)
- Header naming (`## The Smith Method`)
- "based on X-style literature" phrasing
- Juxtaposition implying origin (rule followed by a name with no separator)
- `see also: X, Y` suffix lists
- Block quotes without captions
- Reference-file links pointing to a single author's work

If any of these surfaces names a source, the source must satisfy the source-quality bar below.

## Source-Quality Bar

"Verifiable" means one of:

- **Primary source** — official standard / catalog page with correct part / year, original paper / book, publisher page, stable canonical docs.
- **Authoritative secondary source** — an organization or publication recognized as authoritative in the field, citing the primary.
- **OR at least two independent sources that do not cite or copy each other**. Aggregator pages and wikis do NOT count as independent unless they are themselves backed by primary citations.

A single blog post does not satisfy the bar regardless of how well-known the blogger is.

## Pending Blocks Landing

Unverified author-method pairings are recorded as `attribution pending` and tracked in the target-output / provenance-to-target rows. Per the standard pending-row semantics, any pending row blocks a complete / final claim.

Three resolution paths:

1. **Complete the verification** — find the primary / 2-independent source, add it as a footnote / inline citation, mark the row landed.
2. **Downgrade the claim** — remove the authority, restate the rule as generic guidance that stands on its own merits, drop the attribution row.
3. **Finalize as `interim`** — keep the attribution unverified, mark the commit interim, queue the verification for a follow-up commit.

Memory-grade attribution is not evidence. A claim landed on the assumption "I'm pretty sure X said this" without a citation is the failure mode this rule prevents.
