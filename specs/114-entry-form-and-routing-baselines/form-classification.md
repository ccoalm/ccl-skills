# 114 form classification — the entrypoint's unanchored-prohibition set, walked

Instrument: `skills/skill-extraction-workflow/scripts/entrypoint_form_census.py`, baseline reading recorded
before any edit this round:

`rules=66 prohibitive_tokens=158 rules_naming_baseline_failure=14 unanchored_prohibition_rules=36`

The census flags a rule when it carries imperative-negative vocabulary and does not name its baseline
failure in the phrasings this package uses for that job. That set is the set to classify, not the set to
rewrite: the diagnostic cannot see a rule's structure. Each row below records which form-by-failure row
the rule actually answers and whether its present form is one the table endorses.

Each row is identified by the opening words of the rule as they appear in `SKILL.md`'s `## Core Rules`,
so a reader can find the rule without the census JSON; the ordinal is only the walk order. Regenerate
with `entrypoint_form_census.py --json` and match on the `head` field.

Form classes: `slip` discipline slip; `shape` artifact shape wrong; `slot` required element omitted;
`cond` behavior differs by situation; `pve` aggregate wrong; `tier` latitude vs fragility.

| # | Rule (opening words in Core Rules) | W | P | Form | Verdict | Basis |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | R0 (mandatory clean-landing gate): Before marking any skill or ref… | 409 | 9 | `slip` | `endorsed` | Carries counter-clauses in prose (probe-don't-infer, false-green guard) but no sourced counter table |
| 2 | Pre-draft example domain selection (preempts retroactive R0 cleanu… | 168 | 3 | `slot` | `endorsed` | Names the durable closeout validation row and its fields |
| 3 | Extraction lifecycle handoff: project-specific provenance NEVER en… | 112 | 3 | `slip` | `endorsed` | Phase list is the recipe; the prohibition targets the act of leaking |
| 4 | Charter-before-editing red-line: do not read sources or edit skill… | 53 | 2 | `slip` | `endorsed` | Hard stop aimed at the act of skipping; no counter table |
| 5 | Task-retrospective extraction must inspect the whole delivery chai… | 417 | 5 | `slot` | `endorsed` | Axes must each be covered or explicitly marked no-new-lesson |
| 6 | A blocked source read is not closed by naming the blockage. If Fig… | 156 | 2 | `cond` | `endorsed` | Ladder keyed to the observed read failure |
| 7 | Evidence must come before new rules. Do not add a new conceptual l… | 74 | 2 | `slip` | `endorsed` | Targets the act of backfilling evidence after the rule |
| 8 | For repository evidence, do not conclude a source is empty or unav… | 54 | 1 | `cond` | `endorsed` | Recipe keyed to an observable state (default branch is a scaffold) |
| 9 | When the user asks for full, complete, deep, final, whole-codebase… | 65 | 1 | `slot` | `endorsed` | Source register is the required artifact |
| 10 | Routing-surface change gate: any change touching a routing surface… | 130 | 2 | `slot` | `endorsed` | A validator gate with blocking and advisory classes |
| 11 | A deep review / benchmark of the skill repo is an extraction once … | 177 | 1 | `cond` | `endorsed` | Keyed to an observable: output is meant to change reusable behavior |
| 12 | Treat remembered tool, script, installed-skill, repo-root, validat… | 161 | 2 | `cond` | `endorsed` | Keyed to the observable that a path came from memory |
| 13 | Map every owner/target before the first edit; verify the diff agai… | 242 | 3 | `slot` | `endorsed` | The map is the required artifact, with a stated row format |
| 14 | Classify each candidate target's editability before editing (the u… | 109 | 1 | `slot` | `endorsed` | Each candidate carries an editability label |
| 15 | Impact-chain: a decision-surface edit must map BOTH directions. Wh… | 240 | 5 | `slot` | `endorsed` | Impact-chain row set with named fields |
| 16 | Stack-specific edits need a sibling-generalization mini-map before… | 126 | 1 | `slot` | `endorsed` | Mini-map with per-sibling decision |
| 17 | When a user correction or self-check exposes one missed extraction… | 89 | 1 | `cond` | `endorsed` | Keyed to a discovered miss, explicitly not every extraction |
| 18 | A referenced ccl-owned/vendored skill not installed in a host is i… | 139 | 2 | `cond` | `endorsed` | Keyed to the observable that the skill is repo-present but absent in a host |
| 19 | Extract behavior, decision rules, quality gates, evidence patterns… | 26 | 1 | `shape` | `mixed` | Positive list plus a don't-list about the same shape axis |
| 20 | Keep the skill entrypoint as the trigger and routing surface; move… | 53 | 1 | `shape` | `endorsed` | States what the entrypoint IS and what references own |
| 21 | A skill must be executable, not only directional. For design, clie… | 40 | 2 | `shape` | `endorsed` | States what an executable skill contains |
| 22 | UI/UX, Figma, frontend, app, miniapp, or client sources carry six … | 199 | 3 | `slot` | `endorsed` | Six judgment axes as a walked enumeration |
| 23 | A reported 'recurring cross-project agent failure' plus a question… | 143 | 1 | `cond` | `endorsed` | Keyed to an observable request shape |
| 24 | 复盘 / 纠正 / retro / postmortem / bug-hunt / review-follow-up is an e… | 346 | 1 | `cond` | `endorsed` | Trigger list plus a numbered recipe |
| 25 | Correction-type routing for test / verifier / real-evidence correc… | 179 | 2 | `cond` | `endorsed` | Routing conditional with a stated default and a both-signals case |
| 26 | A reusable lesson must land in a SHARED artifact, and 'skill-extra… | 242 | 3 | `cond` | `endorsed` | Two paths with explicitly different strength |
| 27 | Automatically trigger durable learning when extraction work expose… | 329 | 2 | `cond` | `endorsed` | Keyed to the owner that is already active |
| 28 | Consolidate and retire rules; a skill's rule set must not grow mon… | 329 | 7 | `shape` | `endorsed` | Merge-over-append recipe plus the obligation table requirement |
| 29 | For a whole-session/task-retrospective extraction over operational… | 63 | 2 | `slot` | `endorsed` | Delivery-state rows or an explicit not-applicable |
| 30 | A skill is not done until it is validated for discovery, YAML, gen… | 55 | 1 | `slot` | `endorsed` | Named validation dimensions plus one non-static evidence row |
| 31 | If the primary independent reviewer hangs, returns no output, hits… | 158 | 6 | `cond` | `endorsed` | Ladder keyed to the observed reviewer failure |
| 32 | Independent review is dual-track for any non-wording shared-skill … | 264 | 1 | `cond` | `endorsed` | Keyed to the change class; states what each lens catches |
| 33 | Reference files containing CLI commands, external API calls, or ru… | 115 | 1 | `cond` | `endorsed` | Keyed to what the reference file ships |
| 34 | For reference files or skill examples that include CLI commands or… | 91 | 2 | `cond` | `endorsed` | Keyed to finding type and tool availability |
| 35 | When adding a new section or materially editing any existing secti… | 177 | 3 | `cond` | `endorsed` | Keyed to the edit touching an existing section |
| 36 | Reference example code that performs read-modify-write on external… | 71 | 2 | `slot` | `endorsed` | Five required slots for read, write, uniqueness, lost-update, anti-pattern |

## Result

- `endorsed` 35 of 36; `mixed` 1; wrong-form 0. Every flagged rule has a row: the walk
  order is contiguous 1..36 and the count matches `unanchored_prohibition_rules`.
- No rule in the set is in a form the table calls wrong for the failure it answers. The imperative-negative
  vocabulary sits inside required slots, conditionals and recipes rather than replacing them.
- The single row with a mixed form (19) pairs a positive list with a don't-list on the same shape axis.
  It is left unchanged this round: the exclusions it names are not covered by the positive half, so
  converting it is an obligation-preservation exercise, not a wording change.
- One genuine gap, and it is not authoring: the `slip` rows answer the discipline-slip class, whose
  endorsed form needs rationalization-vs-reality pairs quoted verbatim from baseline or pressure runs.
  That form is prescribed in two places in this package and realized in none, and no channel that
  captures those excuses is operated. The missing input is evidence, so no round can close it by writing.
