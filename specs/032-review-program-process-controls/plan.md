# 032 — Review-Program Process Controls (D1+E5 retrospective landing)

The 023 Batch V process-lesson round: the two design+landing rounds recorded in
`specs/030-d1-model-visible-accounting/plan.md` and
`specs/031-e5-controlled-privilege-escalation/plan.md` are the source sessions; the
D1 plan's "Process defect recorded for extraction (pending its own round)" note is
this round's opening obligation. Extraction ran under `skill-extraction-workflow`
(charter + source register + RCA + target-output map in the maintainer's per-host
scratch, `d1e5-process-retro-*`).

## What lands (one squashed landing commit)

Five controls, each merged into an existing canonical rule — no new top-level sections:

1. **Continuation authorization + the binding dead-angle** (`dual-track-review-gate.md`,
   Findings/budget/human-authority): a broken chain content-binding after an owner-file
   fix is by design; recovery = interim checkpoint naming each lane's un-run remainder +
   authenticated `continuation_authorization` (third state beside `review_waiver` /
   `merge_authorization`: extends rounds, waives nothing, decides no merge).
2. **Falsifiable convergence/closure declarations** (`dual-track-review-gate.md`,
   convergence): named candidate identity, per-lane terminal evidence, named crossed
   axes, named open items; axis-free closure claims are inconclusive; "full X" scoped
   to the named axes.
3. **Remediation re-owes pre-cover + third-same-class-round escalation**
   (`dual-track-review-gate.md`, Re-owe after fixes): mid-round remediation text
   re-owes the draft-time axes before returning to the reviewer; a third same-class
   round stops the per-finding loop for one full-matrix implementer self-enumeration.
4. **Ledger append-once** (`source-register.md`, Round-consolidation rule): rows land
   final-form in the same squashed round partition as the changes they declare —
   closes the follow-up recorded in that file's routing-round note.
5. **Artifact→pin reverse coverage + probe classes** (`testing-strategy/SKILL.md` +
   `references/run-killing-mutation-walk.md`): every obligation sentence of a pinned
   artifact must name the pin that reds on its deletion; relocation / reachability /
   tree-isolation / parser-completeness probes. The severe-debt entrypoint is offset
   to net-negative bytes by moving verified reference-duplication into the walk
   reference (zero-loss obligation map in the scratch register).

Pins: family 9 in `test_ai_coding_implementation_gates.sh`, one assertion per
obligation sentence or sub-clause (40, after the round-1, round-2, round-4, and
round-5 re-enumerations): clause pins bind to their owning physical rule-line
(`assert_same_line`), the three rule-line markers are section-anchored, ledger
pins are paragraph-bound. Shown RED under 81 applied mutations in a throwaway
copy — one deletion and one relocation per pin, two cross-moves between the
convergence and continuation rule-lines, one same-bullet pointer removal — with
first-fail-label attribution to the owning assertion and unmutated controls green
before and after; re-run on the final candidate.
Ledger: two rows (process-controls owner, pin-coverage owner), RED-baseline,
firing paths; appended once with this landing.

## Implementer self-review row (persisted before any external round)

- **Acceptance criteria**: the five controls above land as merges into their named
  canonical rules; every new obligation sentence pinned; `check-ccl-skills.sh` ends
  `ccl_skill_check_clean_ok` with the private alias audit run (`r0_status=private-ok`);
  impact-chain gate exit 0 with both rows in this round's partition; testing-strategy
  entrypoint at or below base bytes/words.
- **Changed-file scope** (equals the candidate diff, ledger included):
  `skills/skill-extraction-workflow/references/dual-track-review-gate.md`,
  `skills/skill-extraction-workflow/references/source-register.md`,
  `skills/skill-extraction-workflow/scripts/test_ai_coding_implementation_gates.sh`,
  `skills/testing-strategy/SKILL.md`,
  `skills/testing-strategy/references/run-killing-mutation-walk.md`,
  `scripts/check-spec-references.py` (waiver pin line-number follow: the ledger note
  insertion moved the waived row 153→168; row bytes and digest unchanged, per that
  waiver's own recorded precedent for the 152→153 move),
  `specs/032-review-program-process-controls/plan.md` (this file).
- **Edge/failure paths walked**: multi-fragment single-line mutations (three pins share
  the continuation-authorization line — mutations delete fragments, not lines, so
  attribution stays differential); same-bullet pointer removal reds only the
  reachability pin; ledger-row grammar (owner key in evidence cell, owner-scoped
  normative-anchor firing path) verified against the machine gate after two
  re-presses of the unpushed landing commit — both corrections applied per the
  landed append-once rule itself.
- **Deterministic evidence**: gates fixture ok; walk 14/14 red-on-owner twice
  (initial + final candidate); impact-chain exit 0; `ccl_skill_check_clean_ok`;
  testing-strategy delta -6B / +0 words at the pre-anchor-fix candidate, re-checked
  after the normative-verb reword.
- **Known residual risks**: the three dual-track clauses are prose obligations whose
  pins assert presence, not semantics (house precedent for process rules); the
  continuation-authorization state is consumed by `code-review`'s staged gate but not
  machine-encoded there this round (`unchanged` with reason in the target-output map);
  cross-section facet check — the SKILL.md Core Rules entrypoint already routes to the
  edited reference sections via existing pointers, so no entrypoint edit is owed.
- **Cross-rule consistency**: the new continuation-authorization bullet was re-read
  against the budget rule (five-round Agent budget unchanged), the waiver and
  merge-authorization bullets (distinct scopes preserved), and
  `staged-review-contract.md`'s `review_scope_changed` recovery (no contradiction:
  the contract owns chain mechanics, this gate owns the authority states).

## External rounds

Recorded below per round as they run (dual-track: review + adversarial challenge on
the landing diff `dev..HEAD`, reviewer identity and dispositions per round).

### Review round 1 (chain `032-probe-plan2`, codex/OpenAI; claude skipped as implementer family), two P1 + one P2, all accepted

Packet `141f73c6…`, tracked, status `findings`. Two invalid earlier gate attempts
(`032-process-controls`, `032-process-controls-r2`) failed plan validation before any
provider ran (free-form concern ids, then missing controller-derived owner
attributions) and consumed no reviewer round; their evidence rows record the
inconclusive `self_review_incomplete` results.

- **P1 (a), accepted — family 9 claimed section-bound pins but used whole-file
  `assert_contains`**: a relocated or duplicated phrase outside its canonical rule
  stayed green. Fixed: every family-9 pin now binds to its owning section
  (`assert_in_section`) or rule paragraph (`assert_same_paragraph`), and the walk
  gains a relocation mutation per pin (fragment moved to end-of-file must RED).
- **P1 (b), accepted — the fixture pinned only selected phrases; unpinned added
  obligations were silently deletable** (the exact failure the landed
  reverse-coverage rule names — caught by the reviewer applying this round's own
  rule to this round's diff). Fixed by re-walking the added text
  sentence-by-sentence: thirteen new pins (escalation trigger and matrix axes,
  declaration components and inconclusive clause, fresh-chain binding,
  Agent-autonomous exclusion, tracker refusal, checkpoint remainder naming,
  risk-acceptance alternative, no-self-authorization, squashed-commit binding,
  post-push supersede, the testing-strategy must-name-its-pin sentence pinned in
  its own file, and the relocation/reachability/tree-isolation probe sentences).
- **P2, accepted — the plan said "Four controls" then enumerated five.** Fixed to
  "Five controls".

All fixes re-pressed into the unpushed landing commit (single-batch program;
finding-derived amend on the just-created unpushed HEAD, provenance recorded here).
The full deletion + relocation walk re-ran on the fixed candidate.

## Zero-loss obligation map (testing-strategy severe-debt offset trims)

Every fragment trimmed from `skills/testing-strategy/SKILL.md` was verified present
in the surviving reference BEFORE dropping (review round 2 P1: the map must be in
the candidate, not only in per-host scratch — the surviving text is pre-existing,
so a bounded range diff cannot show it):

| dropped from SKILL.md | surviving home (pre-existing text, verified) |
| --- | --- |
| "(copy-out/copy-back with fail-fast, canonical-path verification, temp-dir lifecycle)" | `testing-strategy/references/run-killing-mutation-walk.md` §Guarded Backup Recipe — the recipe bullets carry mktemp copy-out/copy-back, per-target fail-fast (`|| exit`), the canonical-path check against the repo root, and the delete-only-after-restore temp-dir lifecycle |
| "the failure must be attributable to the named protected assertion, differential (the owning assertion passes in the unmutated control and fails under the mutant, with no non-owning assertion failing), encoded so a later fixture change cannot silently re-blind it" | same reference, §Encoded Probe For Destructive Artifacts — the attribution bullet, the differential bullet (same three-part definition verbatim), and the re-blinding bullet; the SKILL.md bullet keeps the pointer in the same sentence |
| "not round-trips in general" | same reference, §Round-Trip Nuance (verbatim) |
| "mutation " / "the " qualifiers | wording-only; §Mutation Blast-Radius heading carries the term |

No obligation was dropped without a pointer-reachable surviving home; no trimmed
fragment was pinned by any repo script (grep panel over `skills/*/scripts` before
trimming).

### Review round 2 + challenge round 1 (chain `032-process-controls-r3`, codex/OpenAI), candidate `1607fa66…`

Both lanes tracked on the same candidate; review 4 P1, challenge 5 P1, merging to
six classes:

- **Accepted, fixed — remaining unpinned clauses** ("Name the exact candidate
  identity it covers", "both lanes stay intact and blocking", "or from the
  authorization to continue"): pinned, and the enumeration re-walked at
  sub-clause granularity.
- **Accepted, fixed — section binding too coarse**: convergence and continuation
  pins shared one section, so a clause moved between the two rules stayed green.
  Family 9 now binds each clause pin to its owning physical line
  (`assert_same_line` against the rule's own marker: the falsifiably sentence for
  convergence clauses, the `continuation_authorization` token for continuation
  clauses, the Re-owe marker for escalation clauses), with the marker itself
  section-anchored; the walk adds a cross-move mutation (clause moved from one
  rule-line to the other must RED).
- **Accepted, fixed — stale evidence numbers**: the review-plan evidence rows and
  this spec still said 14/14 deletions while the candidate claimed 29/58; both
  updated to the post-re-enumeration walk and refreshed per candidate.
- **Accepted, fixed — fresh-chain history**: the continuation clause now states
  the fresh chain restarts candidate binding, never history — it carries forward
  the complete review ledger and every prior round's focuses and dispositions
  (aligned with the staged-review-contract chain fields); pinned.
- **Accepted, fixed — zero-loss map not in candidate**: recorded above in this
  spec with per-fragment surviving homes.
- **Declined with precedent — append-once partition not independently checkable
  from a range diff**: the check is mechanical (`impact-chain-gate.rb`, wired into
  `check-ccl-skills.sh`), and the authoritative execution for the frozen candidate
  is the protected CI run on the pushed branch, per the round-029/030 precedent
  that candidate-embedded self-attested execution output is self-attestation one
  indirection deeper. The implementer-run gate result (exit 0, both rows in this
  round's partition) is recorded as implementer-run-plus-reviewable, stated as
  such.

### Review round 3 + challenge round 2 (chain `032-process-controls-r4`, codex/OpenAI), candidate `6d15112e…` — budget checkpoint

Autonomous budget after this pair: five external rounds consumed (invalid plan
probes excluded — no provider ran). Dispositions:

- **Accepted, fixed — "before any further external round" was an unpinned
  sequencing clause** (third instance of the pin-coverage class): pinned.
- **Accepted, fixed — continuation grant replayable across candidates** (challenge:
  one authenticated grant could be reused for unlimited later candidates while
  every round is technically "recorded as human-authorized"): the clause now makes
  the grant scope-bound and non-reusable — it names the granting session and
  either one exact candidate or, explicitly, this program's rounds to convergence
  in that session; outside the named scope a fresh authorization is required. Two
  pins added.
- **Accepted, fixed — staged-contract consistency unverifiable from the bounded
  diff**: the fresh-chain clause now names `code-review`'s staged review contract
  as the owner of the chain fields it defers to, so the claim is bound to its
  primary source instead of floating.
- **Accepted-standing — the reverse-coverage enumeration is hand-maintained** and
  cannot itself detect an omitted obligation: this is exactly what the landed rule
  states ("the walk itself can never detect an unpinned obligation") — the
  recorded enumeration plus adversarial review is the designed mitigation, and it
  demonstrably caught the round-1/2/4 instances. Residual risk stated, not
  patched away.
- **Deferred to the risk owner — encode the family-9 walk in-suite**: the encoded
  in-suite probe is mandatory for DESTRUCTIVE artifacts per `testing-strategy`;
  these are non-destructive prose obligations, where the house precedent (family
  7) is an implementer-run applied walk plus the protected CI run of the presence
  fixture. Encoding a full mutation harness for prose pins is a design decision
  with real maintenance cost — presented for the maintainer's keep/extend
  decision rather than self-decided.
- **Deferred to the risk owner — restore vs trim the testing-strategy guard
  qualifiers**: the bounded packet cannot see the unchanged reference sections the
  zero-loss map points at, so the reviewer cannot confirm survival; the map (above)
  names each surviving home, and restoring the text would re-grow a severe-debt
  entrypoint the size gate blocks. Bounded-review legibility vs entrypoint budget
  is the maintainer's trade to decide.

### Maintainer continuation + merge authorization (2026-08-21) and the user-authorized fresh pair (chain `032-process-controls-r5`, codex/OpenAI)

The maintainer answered the round-4 handoff with a sequenced instruction: (1)
authorize one fresh challenge pass, then (2) accept the landing with the record as
the disposition trail. Recorded per the continuation-authorization rule this round
lands: the grant is scope-bound to this session and this program's rounds to
convergence; both r5 rounds are human-authorized, never Agent-autonomous. The
review round is the chain's mechanical prerequisite for a tracked challenge and
ran under the same grant.

Fresh pair on the frozen candidate (review + full-scope challenge, both tracked,
same candidate hash). Dispositions:

- **P1 (both lanes), accepted, fixed — the grant-scope DEFINITION clause was
  itself unpinned** ("it names the granting session and either one exact candidate
  or, explicitly, this program's rounds to convergence in that session"): deleting
  it left the scope-bound and out-of-scope pins green with the scope undefined —
  the fourth instance of the pin-coverage class, treated identically to its three
  accepted siblings: pinned (`assert_same_line` to the continuation rule-line),
  deletion + relocation mutations red, full walk re-run (40 assertions, 81 applied
  mutations, controls green).
- **P1, re-verified standing — no executable in-suite mutation runner**: the
  already-deferred risk-owner item, re-raised candidate-relative with no delta;
  disposition unchanged (deferred: encode-the-walk-in-suite is a design decision
  with real maintenance cost; house precedent for non-destructive prose is the
  implementer-run applied walk plus the protected CI presence fixture).
- **P1/P2, re-verified standing — testing-strategy trims not visible in the
  bounded packet**: the already-deferred trade (bounded-review legibility vs the
  severe-debt size gate); the in-candidate zero-loss map names each surviving
  home; disposition unchanged.
- **P2, accepted-standing — staged-contract conformance not checkable from the
  bounded diff**: the clause defers to the named contract as its primary source;
  a machine conformance check would live in `code-review`'s gate, outside this
  round's scope; recorded, not patched.

The merge acceptance (step 2 of the instruction) covers this record as the
disposition trail: no undispositioned P0/P1 remains; the r5 scope-definition pin,
like every earlier round's last fix, is pinned and gate-green without a further
external round — that residual is accepted by the maintainer's step-2 instruction,
and the two deferred design decisions remain open items for a future round.

**Honest state at handoff (per the falsifiable-declaration rule this round lands):**
candidate = the frozen landing commit on this branch (exact hash in the MR);
review lane: three rounds run, every P0/P1 dispositioned (fixed, accepted-standing,
deferred-to-owner, or declined-with-precedent) — no undispositioned finding;
challenge lane: two rounds run, same disposition state; axes crossed by the closing
self-audit: obligation→pin coverage, pin binding/relocation/cross-move, ledger
grammar, size budget, leakage, impact-chain partition, spec-reference resolution;
**open items, by name**: (1) the round-4 fixes (sequencing pin, scope-bound grant,
staged-contract pointer) are pinned and gate-green but have NOT themselves been
re-reviewed or re-challenged; (2) two deferred risk-owner decisions above. The
autonomous budget is exhausted; per the continuation-authorization rule this round
lands, the next external round is the maintainer's to authorize — or to accept the
residual with this record as the disposition trail. Merge authorization stays with
the maintainer.
