# Declared but unenforced: no mechanical trigger lands

The class: a gate's text declares that it blocks, reminds or refuses under a
condition, the code has no branch that does so, and the fixture records the
defective outcome as the expected one. `testing-strategy` already owns the
rule (each named property owes a killing mutation; each obligation sentence
names the pin that reds on its deletion). This record answers whether a
deterministic trigger with a controllable false-positive rate exists.

Verdict: **no mechanism lands.** The class stays owned by the existing
`testing-strategy` rule and the review/challenge lanes. Evidence follows.

## Samples

| Sample | Where the declaration lived | Where the gap lived | What found it |
| --- | --- | --- | --- |
| Coverage reminder stayed quiet on a receipt with findings (`specs/148-review-coverage-findings/plan.md`) | hook header: reminds unless a conclusive review covers HEAD | quiet branch never read `status`; fixtures used receipts whose status the branch ignored | independent review |
| Abort-leak leg asserted liveness samples rather than the invariant (`specs/046-abort-leak-baseline-invariants/`) | suite name and comments | assertion on an output present with or without the defect | recorded in that round's spec |
| Two further rounds in the private archive: a "no threshold" declaration with a numeric trigger and a non-zero warning exit; a check whose fixture never produced the condition it claimed to test | reference prose and test names | branch condition or fixture input, in another file | review, challenge and an applied mutation |

The 148 instance is fixed on the baseline: its cases in
`hooks/test_remind_review_covers_head.sh` pass on 095941a. The other samples
were closed in their own rounds and were not re-run here; they serve only to
show where declaration and gap sat.

## Candidate triggers

**T1. Static: the file's header declares blocking, the body never emits a
block.** Prototype over every tracked non-test script under `hooks/`,
`scripts/` and `skills/*/scripts/` (`.sh`, `.py`, `.rb`). A header (first 40
lines) matching `block|deny|fail-closed|reject|gate` counts as declaring; a
body with no `exit N`, `return N`, `deny`, `"block"`, `decision`, `abort` or
`die` counts as a hit.

- 54 files declare; 9 hits.
- All 9 are false positives: three advisory reports that say so in the header
  (`remind-untracked-background.sh`, `remind-unverified-cli-flag.sh`,
  `source-register-lifecycle.rb`), three wrappers that delegate the decision to
  an engine (`owner-dispatch-guard.sh`, `owner-dispatch-stop.sh`,
  `headless-background-stop.sh`), two context injectors (`session-start.sh`,
  `subagent-start.sh`), and one helper that reports through `warn` by design
  (`source-register-pending-status.rb`).
- Recall on the samples, by inspection: 0 of 4. Every sample's gate has a
  path that emits its outcome; the defect is a missing or wrong condition on
  that path, which a header-versus-exit scan cannot see.

**T2. Mutation coverage: require a killing mutation per declared blocking
branch.** A mutation can only remove code that exists. In the 148 sample the
missing piece was the `status` condition on the quiet path, so no mutant of
the shipped code turns any test RED. The existing walk already catches the cases where a branch exists and a
test fails to pin it (the 046 sample). Mechanising it adds nothing for the
absent-condition half of the class.

**T3. Traceability: every row of a plan's acceptance decision table maps to a
named test.** Decidable only with a row-to-test ID convention that no current
plan carries. In the 148 sample the original declaration was a hook header
comment, not a table row, so the gate would not have fired either. Author
cost: every plan in `specs/` would need retrofitting or an exemption.

**T4. Fixture text says the outcome the declaration forbids.** Requires
reading the declaration's meaning; no syntactic predicate separates "expected
quiet because covered" from "expected quiet because the defect hides it".

## Decision

| Option | Recall on samples | False positives | Decision |
| --- | --- | --- | --- |
| T1 static header/exit scan | 0/4 | 9/9 hits false | reject |
| T2 mechanical mutation coverage | absent-condition half: 0 | n/a | reject; the existing walk keeps the present-code half |
| T3 decision-table traceability | 0/1 (declaration not in a table) | high author cost | reject |
| T4 fixture-vs-declaration text | not decidable | — | reject |

What finds this class today is a reader comparing a declaration with the
branch that should implement it, in another file. That is what the review and
challenge lanes do, and in each sample whose finder is recorded, one of them
found it. The class remains
`testing-strategy`-owned, with no new rule text: the existing reverse-direction
pin rule (artifact → pin) already states the obligation. The trigger to
reopen: a sample where the declaration is machine-readable (a decision table
with stable row IDs, or a declared exit-code contract) and the gap escaped
both lanes.
