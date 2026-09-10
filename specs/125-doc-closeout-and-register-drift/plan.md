# 125 — Live-document closeout trigger and register drift

## Problem

The document-finalization skill gated its closeout re-read on "before sharing or
publishing". Editing a document in place never reaches that moment: every edit is
already published, so the re-read never fired. In the observed failure a
plain-language collaborative document took ~25 successive single-sentence edits,
each individually correct, and the whole-document defects — a self-introduced
duplication and vocabulary lifted from the editor's own domain rather than the
host document's — surfaced only when its owner rejected the result as unreadable.

## Change

- `tighten-doc/SKILL.md`: the closeout trigger extends to the round's last write
  operation; the term-drift rule gains register drift, stated as a rule ("new
  sentences must not sit above the host document's register") with a check.
- `tighten-doc/references/closeout-reread.md` (new): trigger, the evidence this
  pass owes, the three substitutes that do not count, and the register-drift check.
- Funded by relocation: the closeout-evidence detail moves out of the
  over-budget entrypoint, which shrinks (49905 -> 49454 bytes, 9822 -> 9806 body words).

## Gates

- Five ledger rows, five locators, one guard: `register-firing-path-resolution.rb`
  (whole-ledger locator resolution). They pin, in order, the register-drift rule
  in the entrypoint; the live-document trigger; the obligation to replace or
  gloss a candidate term; the isolation of this round's new sentences; and the
  term-by-term comparison — from the traversal itself through the pre-edit
  target, the prohibition, and the candidate definition. Each was proven by an applied
  differential mutation: the mutant reds and names that locator, control and
  restored are green. The walk is captured verbatim in
  `evidence/mutation-walk.txt` — control, seven mutants, restored, each with the
  guard's own rc and the locator it names, plus the blob hashes of the two
  subject files so a reviewer can confirm the capture describes this tree.
- `check-ccl-skills.sh` with `CCL_SKILL_BASE_REF=origin/main`: `ccl_skill_check_clean_ok`.
- Two cases are added to
  `skills/skill-extraction-workflow/scripts/test_register_firing_path_resolution.sh`:
  deleting an anchored rule must red the gate and name that locator, and gutting
  text outside the anchor must not. State precisely what this buys, because the
  round already overclaimed it once: the packet carries the added call sites,
  their expected exit codes and their expected diagnostic strings, so a reviewer
  can read what is asserted. It does not carry the guard, the fixture builder,
  the assertion helpers or the cleanup trap — all unchanged, therefore outside a
  diff-scoped packet. Whether the assertions hold is checkable by running the
  suite with repository access, not by reading the packet.
- Dual-track review and challenge run against the frozen candidate. Receipts are
  committed only after the binding round passes, because a receipt carries the
  candidate hash and adding it before that round would describe a tree that no
  longer exists; until then this round's chain is recorded in
  `evidence/finding-dispositions.md`.

## Boundary

A prose closeout rule has no executable behavior oracle in this repository. The
five anchors pin the rules' presence and wording; they are not a measured
model-behavior delta, and the rows say so rather than implying otherwise.
Three successive challenge rounds each found a different way to satisfy a
locator while gutting what it pins, which is the class signal rather than three
separate defects: a substring locator binds letters, not meaning. The rows now
state that boundary instead of claiming semantic protection.
