# 114 form classification — the entrypoint's unanchored-prohibition set, walked

Instrument: `skills/skill-extraction-workflow/scripts/entrypoint_form_census.py`, baseline reading recorded before any edit this round:
`rules=66 prohibitive_tokens=158 rules_naming_baseline_failure=14 unanchored_prohibition_rules=36`

The census flags a rule when it carries imperative-negative vocabulary and does not name its baseline
failure in the phrasings this package uses for that job. That set is the set to classify, not the set to
rewrite: the diagnostic cannot see a rule's structure. Each row below records which form-by-failure row
the rule actually answers and whether its present form is one the table endorses.

Form classes: `slip` discipline slip; `shape` artifact shape wrong; `slot` required element omitted;
`cond` behavior differs by situation; `pve` aggregate wrong; `tier` latitude vs fragility.

| # | Words | Proh | Group | Form class | Verdict | Basis |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 409 | 9 | Sanitization, provenance & naming | `slip` | `endorsed` | Carries counter-clauses in prose (probe-don't-infer, false-green guard) but no sourced counter table |
| 2 | 168 | 3 | Sanitization, provenance & naming | `slot` | `endorsed` | Names the durable closeout validation row and its fields |
| 3 | 112 | 3 | Sanitization, provenance & naming | `slip` | `endorsed` | Phase list is the recipe; the prohibition targets the act of leaking |
| 4 | 53 | 2 | Evidence, RCA, charter & attribution | `slip` | `endorsed` | Hard stop aimed at the act of skipping; no counter table |
| 5 | 417 | 5 | Evidence, RCA, charter & attribution | `slot` | `endorsed` | Axes must each be covered or explicitly marked no-new-lesson |
| 6 | 156 | 2 | Evidence, RCA, charter & attribution | `cond` | `endorsed` | Ladder keyed to the observed read failure |
| 7 | 74 | 2 | Evidence, RCA, charter & attribution | `slip` | `endorsed` | Targets the act of backfilling evidence after the rule |
| 8 | 54 | 1 | Evidence, RCA, charter & attribution | `cond` | `endorsed` | Recipe keyed to an observable state (default branch is a scaffold) |
| 9 | 65 | 1 | Evidence, RCA, charter & attribution | `slot` | `endorsed` | Source register is the required artifact |
| 10 | 130 | 2 | Triggers, routing surfaces & isolation | `slot` | `endorsed` | A validator gate with blocking and advisory classes |
| 11 | 177 | 1 | Triggers, routing surfaces & isolation | `cond` | `endorsed` | Keyed to an observable: output is meant to change reusable behavior |
| 12 | 161 | 2 | Triggers, routing surfaces & isolation | `cond` | `endorsed` | Keyed to the observable that a path came from memory |
| 13 | 242 | 3 | Owner-generalization, target-output & impact-chain mapping | `slot` | `endorsed` | The map is the required artifact, with a stated row format |
| 14 | 109 | 1 | Owner-generalization, target-output & impact-chain mapping | `slot` | `endorsed` | Each candidate carries an editability label |
| 15 | 240 | 5 | Owner-generalization, target-output & impact-chain mapping | `slot` | `endorsed` | Impact-chain row set with named fields |
| 16 | 126 | 1 | Owner-generalization, target-output & impact-chain mapping | `slot` | `endorsed` | Mini-map with per-sibling decision |
| 17 | 89 | 1 | Owner-generalization, target-output & impact-chain mapping | `cond` | `endorsed` | Keyed to a discovered miss, explicitly not every extraction |
| 18 | 139 | 2 | Owner-generalization, target-output & impact-chain mapping | `cond` | `endorsed` | Keyed to the observable that the skill is repo-present but absent in a host |
| 19 | 26 | 1 | What to extract, content placement & domain (UI/UX) judgment | `shape` | `mixed` | Positive list plus a don't-list about the same shape axis |
| 20 | 53 | 1 | What to extract, content placement & domain (UI/UX) judgment | `shape` | `endorsed` | States what the entrypoint IS and what references own |
| 21 | 40 | 2 | What to extract, content placement & domain (UI/UX) judgment | `shape` | `endorsed` | States what an executable skill contains |
| 22 | 199 | 3 | What to extract, content placement & domain (UI/UX) judgment | `slot` | `endorsed` | Six judgment axes as a walked enumeration |
| 23 | 143 | 1 | Retrospectives, corrections & auto-triggered learning | `cond` | `endorsed` | Keyed to an observable request shape |
| 24 | 346 | 1 | Retrospectives, corrections & auto-triggered learning | `cond` | `endorsed` | Trigger list plus a numbered recipe |
| 25 | 179 | 2 | Retrospectives, corrections & auto-triggered learning | `cond` | `endorsed` | Routing conditional with a stated default and a both-signals case |
| 26 | 242 | 3 | Retrospectives, corrections & auto-triggered learning | `cond` | `endorsed` | Two paths with explicitly different strength |
| 27 | 329 | 2 | Retrospectives, corrections & auto-triggered learning | `cond` | `endorsed` | Keyed to the owner that is already active |
| 28 | 329 | 7 | Retrospectives, corrections & auto-triggered learning | `shape` | `endorsed` | Merge-over-append recipe plus the obligation table requirement |
| 29 | 63 | 2 | Validation & the dual-track gate | `slot` | `endorsed` | Delivery-state rows or an explicit not-applicable |
| 30 | 55 | 1 | Validation & the dual-track gate | `slot` | `endorsed` | Named validation dimensions plus one non-static evidence row |
| 31 | 158 | 6 | Validation & the dual-track gate | `cond` | `endorsed` | Ladder keyed to the observed reviewer failure |
| 32 | 264 | 1 | Validation & the dual-track gate | `cond` | `endorsed` | Keyed to the change class; states what each lens catches |
| 33 | 115 | 1 | Validation & the dual-track gate | `cond` | `endorsed` | Keyed to what the reference file ships |
| 34 | 91 | 2 | Validation & the dual-track gate | `cond` | `endorsed` | Keyed to finding type and tool availability |
| 35 | 177 | 3 | Validation & the dual-track gate | `cond` | `endorsed` | Keyed to the edit touching an existing section |
| 36 | 71 | 2 | Validation & the dual-track gate | `slot` | `endorsed` | Five required slots for read, write, uniqueness, lost-update, anti-pattern |

## Result

- `endorsed` 35 of 36; `mixed` 1; wrong-form 0.
- No rule in the set is in a form the table calls wrong for the failure it answers. The imperative-negative
  vocabulary sits inside required slots, conditionals and recipes rather than replacing them.
- The single row with a mixed form (19) pairs a positive list with a don't-list on the same shape axis.
  It is left unchanged this round: the exclusions it names are not covered by the positive half, so
  converting it is an obligation-preservation exercise, not a wording change.
- One genuine gap, and it is not authoring: the `slip` rows answer the discipline-slip class, whose
  endorsed form needs rationalization-vs-reality pairs quoted verbatim from baseline or pressure runs.
  That form is prescribed in two places in this package and realized in none, and no channel that
  captures those excuses is operated. The missing input is evidence, so no round can close it by writing.
