# Load rules at their firing point

## Intent

Skill entrypoints are loaded whole when a skill activates, and every token
stays in context for the rest of the session. Public evidence on instruction
load points one way: adherence falls as instructions grow longer and denser,
and Skills help most when they are focused (sources and their evidence grades:
`skills/skill-extraction-workflow/references/external-practice-controls.md`,
Instruction-following mechanisms). This round applies that to the most
frequently loaded process skill whose content splits cleanly by lifecycle
point, without changing any rule.

## Scope

- `worktree-isolation`: push, merge and teardown sections move verbatim to two
  package references; the entrypoint keeps Step 0, a firing-point table with
  the load-bearing obligations, and the ledger-anchored shared-branch rule.
- `hooks/remind-post-merge-cleanup.sh`: the post-merge reminder points to the
  canonical teardown section and stops presenting a partial exception list as
  complete; its suite pins the text and the pointer target.
- `check-sync-pointers.sh` and its suites: the three always-on pins resolve to
  the reference that now carries the canonical text.
- `skill-extraction-workflow` references: placement by firing time, the third
  pin class in the trim recipe, and the instruction-load source table.

Out of scope: `code-review` and `product-rd-workflow` get the same treatment
in a later round. A pure relocation of a curated owner has no behavior delta
to show as a RED baseline, so each needs a paired real change or a local
paired evaluation first.

## Decisions

- Exact command conventions and destructive-operation guards stay inline; the
  shared-branch update rule is also the recorded firing path of several
  register rows, so it stays in the entrypoint verbatim.
- No rule is reworded. Relocated lines are byte-identical; the entrypoint's
  firing-point table restates only the obligations that make each moved
  section bite (`rule-consolidation.md` condensing rule).

## Pre-registered checks (frozen before the edits)

| Check | Pass condition |
| --- | --- |
| Entrypoint load | `worktree-isolation/SKILL.md` at or below 14,000 bytes (base 38,112) |
| Zero loss | every non-blank line removed from the entrypoint appears verbatim in the new references; dropping one moved line must be reported |
| Sync gate RED then GREEN | relocated text with the old registry blocks exactly the three worktree pins; the new registry passes; removing the protocol anchor or renaming the teardown heading in the reference blocks the matching pins only |
| Hook RED then GREEN | the new reminder-text assertions fail against the previous hook and pass against the new one; every existing remind/quiet probe still passes |
