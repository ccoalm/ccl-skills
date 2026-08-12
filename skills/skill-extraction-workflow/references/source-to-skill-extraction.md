# Source To Skill Extraction

Use this when mining local repositories, documents, reviews, bugs, or chat history for reusable skill material.

## Domain Method Index

Use the general extraction workflow first, then jump to a domain method only when the source has that technical surface:

Domain methods own extraction procedure and routing only; target architecture, implementation, and testing skills own the reusable rules.

| Method | Use when the source contains |
| --- | --- |
| [Database And DAL Extraction Method](#database-and-dal-extraction-method) | Models, DDL, migrations, generated DAL, repositories, query builders, transactions, data migrations, sharding, or DB/cache consistency code |
| [Redis Extraction Method](#redis-extraction-method) | Cache adapters, key builders, locks, Lua/CAS scripts, counters, rate limiters, idempotency stores, streams, Pub/Sub, queues, or Redis-backed coordination |

Keep this file as the method index while there are one or two domain methods. When a third or later broad domain method is actually needed, such as HTTP/API, queue/MQ, auth, observability, or frontend state extraction, split each domain method into a focused reference file and leave links here.

## Evidence Grades

- Strong: repeated patterns across multiple modules/repos, tests/CI enforcing the behavior, architecture docs that match code, postmortems or review findings with concrete failures.
- Medium: single mature implementation with tests and stable docs, accepted user correction repeated in multiple sessions, production checklist used more than once.
- Weak: one-off code, speculative comments, stale docs, unverified memory, raw generated output, isolated preference.

Promote only strong or medium evidence into skill rules. Keep weak evidence as a question or discard it.

Prefer specific primary or firsthand sources over aggregators, search pages, topic pages, homepages, or placeholder links. A URL proves coverage only when it points to an actual inspected page or artifact that supports the extracted rule.

## Collection Strategy

Pick a strategy before deep analysis:

- Local-first: use the user's provided repository, design file, docs, or session as the authority; use outside sources only to fill gaps or validate format.
- Local-plus-external: combine local evidence with external examples, official docs, or public skill repositories to challenge and strengthen the extraction.
- External-only: use public or provided external material when no local source is available; mark source limits clearly and avoid pretending it reflects local practice.

Before moving from gathering to extraction on broad work, produce a compact coverage checkpoint:

| Dimension | Sources inspected | Key finding or gap | Contradictions | Confidence |
| --- | --- | --- | --- | --- |

Do not wait until landing to discover that a critical source class was never checked.

## Extraction Charter

Use this before reading deeply or editing any skill. The charter is the guardrail against shallow extraction.

| Field | Required answer |
| --- | --- |
| Purpose | What future failure, repeated correction, workflow drift, or quality bar should this extraction prevent? |
| Scope | Which skill(s), source classes, users/tasks, and sibling boundaries are in scope? What is out of scope? For an iterative-program source (multi-round research/writing/delivery), also answer: does a project-local `covered-through` watermark exist, and what does this round cover above it? (see the watermark rule under Task Retrospective Extraction) |
| Depth | Is this wording cleanup/no new source read, targeted check, file-level refresh, node/artifact inventory, full workflow extraction, or generator/tooling change? |
| Root cause | Why does the current skill, workflow, source practice, or prior extraction fail? |
| RCA analysis | The scaled move from observed issue to controllable prevention point(s): wording-only gets one concise ambiguity/typo sentence; small non-wording gets a widen-check plus control; non-trivial failures use Deep RCA. |
| Failure mode analysis | What future bad output, workflow drift, domain leakage, shallow guidance, or missing verification would happen if the extraction is weak? |
| Lifecycle impact | Which stages are affected: product intent, design/UX, implementation, debugging, testing, launch acceptance, iteration feedback, team onboarding, and use without source access? |
| Evidence plan | Which source categories must be inspected, routed, discarded, or marked unavailable? For a task/session retrospective over a session that produced artifacts, the FIRST source class listed MUST be those produced artifacts (deliverables, reports, scripts, datasets — the a0 enumeration, owed at charter time, not only before an exhaustion claim); a session with genuinely no produced artifacts records an explicit `produced artifacts: not-applicable` entry carrying the reason, the minimum checked surfaces (deliverable directories, script/output locations, dataset paths), and a resolvable inventory-check locator — the command or listing that establishes absence — instead of the class. Either way, correction turns and the agent's own summaries are friction-biased digests — they record only what rubbed, so what went RIGHT is structurally invisible in them — and cannot substitute for the artifact class or excuse skipping the check. |
| Completion standard | What pressure scenario, independent review, command, install check, or source-map evidence proves done? |

Depth rules:

- Wording cleanup/no new source read: no new source-derived rule; only clarify trigger, routing, naming, or validation text.
- Targeted check: answer one narrow question with named sources and narrow claims.
- File-level refresh: inspect relevant files/repos/design files at page, module, command, or top-level structure level.
- Node/artifact inventory: inspect concrete nodes, modules, components, states, tests, commands, or artifacts and record exclusions.
- Full workflow extraction: cover purpose, source matrix, conflict decisions, executable recipes, validation, and sibling routing.
- Generator/tooling change: update deterministic scripts or validators when documentation cannot reliably enforce the rule.

Hard stop: record the charter before source reads and before skill edits. Even a trivial wording cleanup records `Depth` explicitly so later review can distinguish wording-only from semantic/routing/validation changes. If the charter identifies affected lifecycle stages, create the target-output map before source-derived editing.

If the user asks for complete, deep, full, or repeat extraction, or challenges shallow extraction, default to full workflow extraction unless the scope is explicitly narrowed.

### Portfolio-stability prefilter

Before a source portfolio can confirm or contradict a reusable rule, classify it as `stable` (in production, not slated for replacement), `evolving` (actively iterating, design not frozen), `legacy-deprecating` (scheduled for retirement), or `mixed`. Only `stable` portfolios can be used as confirmation/contradiction baseline. `Evolving`, `legacy-deprecating`, and `mixed` portfolios are audit/anti-pattern signals unless the extraction is explicitly downscoped to that status; state the long-lived caveat reason instead of implying future verification will upgrade it automatically.

## Baseline RCA For Every Extraction

Use correction RCA after a known failure, but do not wait for a failure to reason about root cause. Every extraction starts with baseline RCA; scale the detail to the task size:

| Question | Required answer |
| --- | --- |
| Future failure | What concrete bad work would a future agent produce without this extraction? |
| Enabling cause | What gap in the current skill/process/source understanding allows that bad work? |
| Prevention mechanism | What rule, recipe, matrix, validation, source register, or routing change would prevent it? |
| Owning layer | Which skill owns the prevention: extraction workflow, product workflow, design, web, app, backend, testing, LLM, or a project artifact? |
| Proof | What source evidence and pressure scenario will show the prevention works? |

Minimum RCA depth:

- Wording cleanup: one sentence future failure and owner.
- Targeted check: future failure, source boundary, and proof.
- File-level or broader extraction: full table above, plus lifecycle impact, run through the Deep RCA five moves below (the table's single "enabling cause" row becomes the *set* of contributing factors).
- Broad or multi-skill extraction: full table above, source register, target-output map, independent review, and the Deep RCA five moves below.

If the RCA reveals the requested work is really a product decision, architecture decision, test strategy, design readiness issue, source-access problem, or sibling-skill update, route it before editing the target skill.

### Deep RCA For Extraction

RCA is the required outcome; 5 Why is only the **entry technique** to get past a visible symptom. Used alone it has a documented failure mode: it traces ONE linear chain to ONE "root cause", is bounded by the investigator's current knowledge, is non-reproducible (different agents reach different ends), and the word "why" drifts toward "who" (blame) and toward hindsight. Most process/agent failures are not single-cause — overt failure requires several contributing causes to coincide — so for any non-trivial extraction run the fuller method below, not just a why-chain. (For pure wording cleanup — the strict wording-only test, no trigger/scope/routing/validation/owner-meaning change — a one-line why is enough.)

Do not force exactly five questions, and do not accept a single straight chain. Ask enough "why" to leave the symptom; ask "how/what conditions" to widen; stop a branch once its next action is concrete and owned.

**The five moves — scale to the failure's size.** A genuine multi-cause failure, an incident, or a file-level/broader extraction uses all five. Any non-trivial RCA must do at least moves 1 (widen), 4 (counterfactual-rank), and 5 (control). A small, single-rule non-wording clarification with no new behavior scales down further — a brief widen-check plus the control, no formal multi-factor table. **Failure shape, not diff size, sets the depth:** a one-line patch that fixes a recurring, under-trigger, or genuinely multi-cause failure is NOT "single-rule" — it still gets the full method. Do not pad rows to look thorough: a smaller honest RCA beats a filled-in template, and relabeling a semantic/routing edit as "wording-only" to escape the method is the dodge the strict wording-only test (`SKILL.md`) forbids.

1. **Widen before you deepen.** Before chasing one chain, enumerate the *multiple* contributing factors in parallel, sorted into categories so you brainstorm across them rather than committing to one line. Categories for extraction / agent-behavior failures:
   - **Trigger / routing** — what should have fired the right skill or gate and didn't?
   - **Process model / knowledge** — what did the agent believe about state (path, branch, prior round, owner) that was wrong or stale?
   - **Missing / inadequate control** — what constraint should have been enforced mechanically but was only advisory or absent?
   - **Missing feedback** — what signal would have told the agent/workflow it was off-track, and was missing?
   - **Latent condition** — what authored-earlier rule, template, default, or budget-dropped description made this failure *available*, waiting to align?
   - **Detection gap** — why did no validator, review, or closeout catch it after the act?
   A straight line of causes with no branches means you stopped early.
2. **Separate active failure from latent conditions.** The visible act (the agent skipped a gate) is the sharp-end *active failure*; the blunt-end *latent conditions* were authored long before (the gate was advisory, the closeout didn't check it, the rule lived only in a dropped description). Deep RCA fixes the latent conditions — you change the conditions agents work under, not their fallibility. This does NOT replace the delivery-chain pass: fixing an upstream latent condition (a trigger/description) and skipping the downstream detection/validation/closeout control is exactly the miss delivery-chain RCA exists to catch — keep both layers (defence-in-depth).
3. **Local rationality, not hindsight.** Knowing the outcome makes the right path look obvious in retrospect — hindsight is the primary obstacle to honest analysis. Do **not** write "the agent should have known / should have run X"; that describes a world that didn't exist and explains nothing. Ask: *given what the agent could see and was optimizing for, why did this action make sense at the time?* The answer points at a missing constraint or feedback, not at diligence. (This is the deep form of the "discipline gap is a non-cause" Core Rule.)
4. **Counterfactually test each candidate cause — to rank causal weight, not to prune defence-in-depth.** A why-chain never tests its links. For each contributing factor run the but-for test: *if this had been removed or changed, would the failure still have happened?* Use it to separate genuine coincidence from causes and to rank levers — never to delete redundant safeguards:
   - Removing it prevents the outcome → **necessary** (a primary lever).
   - It alone would produce the outcome → **sufficient**.
   - Not individually necessary *only because another failed layer would also have allowed the outcome* → this is a **redundant safeguard / secondary control**: KEEP it (its failure is real defence-in-depth erosion — list it as a secondary control exactly as the delivery-chain and incident-postmortem methods require), do not discard it as correlation.
   - Genuinely no causal or detection role (its presence/absence would not change the outcome and it was not a safeguard meant to catch this) → correlation, drop it.
   A factor asserted from a single trace is a hypothesis, not a proven cause — mark it `probabilistic`/`unsupported` and keep it as a candidate until a second observation or a mechanism confirms or refutes it; do not hard-delete a plausible latent or secondary factor on one trace.
5. **Site the fix as a mechanical control on the failure CLASS — provably firing, practically bounded.** The fix is never "remember next time" (sharp-end diligence — the dodge the Core Rules already forbid). Restore or add a *control*: a constraint the workflow enforces mechanically **plus** the *feedback* that confirms it fired. It must pass the **firing-path proof** (name the trigger, validator, closeout row, hook, or merged clause that mechanically catches the case — AND the **reachable surface** where the next agent actually encounters it in time: bootstrap/description/closeout/hook/CI. A clause landed only in a deep reference that nothing routes the agent to read is NOT a firing control — that is the "rule exists but did not trigger" gate. "The final answer mentions it" / "the agent will consider it" is not feedback and is still a diligence patch in disguise). Place it so the whole failure class is caught, not just this instance (defence-in-depth). Where several branches each have a controllable point, prefer the **highest-leverage practical control** (one upstream control often closes several branches) over the first patchable point — but "practical" is bounded exactly as the incident method's *earliest practical prevention point*: a named artifact, an owner who can change it today, and an observable check. Preferring leverage does NOT license deleting a useful narrow gate, removing a wording-only escape hatch, or inflating one miss into an over-broad global hook; keep the failed secondary controls as defence-in-depth. When the same failure class recurs across rounds, question whether the risky capability should exist at all, not just patch it again.

Good stopping points (per branch):

- A missing source row, coverage depth, branch check, Figma node/page register, document register, or evidence grade.
- A missing target-output row or sibling-skill routing decision.
- A missing execution recipe, state matrix, acceptance gate, test scenario, validator, or independent review.
- A missing provenance/naming rule that let source-specific labels enter executable guidance.
- A final-response constraint that prevents overclaiming when evidence is partial.

Bad stopping points (all are symptoms, blame, or hindsight, not causes):

- "The agent was careless." / "Need to be more thorough." / "Need to pay attention."
- "The agent should have known / should have run it." (hindsight counterfactual)
- "The source is complex." / "The user did not remind us."
- A single linear chain ending at one root cause when no branches were enumerated.

Use this compact multi-factor format (one row per surviving contributing factor, not one row total):

| Contributing factor (category) | Active / Latent | Why it made sense (local rationality) | Counterfactual: necessary / sufficient / secondary-control / probabilistic (drop only pure coincidence) | Control to add (constraint + confirming feedback + firing path, failure-class scope) | Owner | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| Which factor, in which category from move 1 | active act or latent condition | what the agent could see that made the action reasonable | per move 4 — keep redundant safeguards as secondary controls; drop only genuine coincidence | the enforced gate/validator/trigger/merged clause + the signal that proves it fired (passes the firing-path proof) | skill/reference/validator/test/doc/final-response rule | diff, command, source row, review, or explicit non-skill reason |

Source-specific prompts (where each branch's RCA should resolve):

| Source type | First symptom to question | RCA should resolve to |
| --- | --- | --- |
| Code | A pattern was missed, overgeneralized, or routed to the wrong skill | Required code inventory depth, branch/module coverage, runtime/test evidence, sibling skill owner, or validator/test gate |
| Figma/design | A visual/interaction/behavior/psychology rule was shallow or unsourced | Required page/node/state-family coverage, Figma-plus-code boundary, judgment layer delta, pressure scenario, or source-neutral design/app/test routing |
| Documents | A workflow rule was copied from wording instead of extracted from durable practice | Document set boundary, source authority, contradiction handling, stale-doc exclusion, owner artifact, or no-skill decision |
| Task/session retrospective | A lesson was summarized but not durably landed | Correction RCA, lesson classification, shared-skill vs memory-only boundary, durable owner, validation command, or final-response limit |

**Method provenance** (the moves are standard root-cause / safety-science practice, checked against primary or authoritative-secondary sources — for audit, not required reading; some origin *dates* are approximate or contested and flagged inline, so do not treat every bundled attribution below as equally primary-verified):

- Single-chain / single-root-cause is the documented failure of 5 Whys (named and operationalized within the Toyota Production System by Taiichi Ohno, 1950s; the earlier "Sakichi Toyoda, 1930s" origin is widely repeated but weakly sourced — do not state it as settled) — the standard 5-Whys critique (named e.g. by ex-Toyota MD Teruyuki Minoura): stops at symptoms, knowledge-bound, non-reproducible, isolates one cause; and John Allspaw, *The Infinite Hows* (2014, kitchensoap.com): ask *how/what conditions*, not *why*, because "why" drifts to "who". Widening across parallel categories = Ishikawa/fishbone (Kaoru Ishikawa, 1960s); combination of causes = Fault Tree Analysis (H.A. Watson / Bell Labs, ~1962); "every effect has ≥2 causes, a straight line means you stopped early" = Apollo RCA (Dean Gano).
- "Overt failure requires multiple faults; post-accident attribution to a single root cause is fundamentally wrong" = Richard Cook, *How Complex Systems Fail* (how.complexsystems.fail). "Root cause is an arbitrary stopping rule; accidents are inadequate enforcement of constraints across a control structure" = Nancy Leveson, STAMP/CAST (*Engineering a Safer World*, MIT, 2011) — the source of the constraint + feedback / control framing in moves 1 and 5.
- Active vs latent conditions and defence-in-depth = James Reason, "Human error: models and management", *BMJ* 2000 (Swiss-cheese model). Local rationality / hindsight & counterfactual trap = Sidney Dekker, *The Field Guide to Understanding Human Error*. "Human error is a symptom, fix systems not people" and "contributing factors, not one root cause" = Google SRE *Postmortem Culture* (Lunney & Lueder) and Etsy blameless-postmortem practice. Necessity / sufficiency counterfactual test = Judea Pearl, *Causality* (probability of necessity / sufficiency).

## Task Retrospective Extraction

Use this when the user asks to summarize this task, summarize lessons learned, review what went wrong, or turn the current session into reusable team practice.

The current task is a source, but it is not automatically a skill rule. Treat task history as evidence and run RCA before writing any durable lesson.

Required flow:

1. Define the task boundary: which user request, implementation slice, review, bug, correction, or validation result is being summarized.
2. Run baseline RCA or correction RCA:
   - What future bad outcome would repeat without a rule?
   - What enabled the issue in this task?
   - Which gate would have caught it earlier?
   - Which skill, validator, shared project doc, memory note, repo doc, or final-response rule owns the prevention?
   - For delivery-chain failures, ask why the requirement/contract was not defined correctly, why implementation could proceed by inference, why unit/contract/integration/E2E tests or review/MR readiness did not block it, and why any earlier retrospective missed the deeper cause; land prevention at every failed owning layer, not only one target skill.
3. Classify each lesson:
   - `skill`: reusable agent behavior that belongs in an existing or new skill.
   - `validator/tooling`: deterministic check that should be scripted.
   - `project artifact`: repo doc, test, CI, or product requirement is the right home.
   - `memory`: user/workspace preference or machine-local context that should be remembered only when explicitly requested, and is not a reusable process, routing, testing, design, review, or teamwide failure.
   - `final response only`: useful task context but not reusable enough to land.
   - Do not classify reusable process defects, repeated user corrections, missed skill triggers, teammate-safety risks, or "others will hit this too" lessons as `memory`. Those require a shared skill/reference/validator/checklist/project-template landing or an explicit `unchanged`/`routed`/`discarded` decision with evidence.
4. Land only reusable, evidenced lessons. Do not turn every inconvenience, preference, or one-off mistake into a skill rule.
5. Verify the landing point. A task retrospective is not complete if the only output is a chat summary and the reusable lesson has no durable owner.

Minimum retrospective table:

| Task event or correction | RCA summary | Lesson classification | Durable owner | Verification |
| --- | --- | --- | --- | --- |
| What happened | Future failure, enabling cause, prevention mechanism | skill / validator / project artifact / memory / final response only | File, skill, script, shared artifact, memory note for local preference only, or no-skill reason | Diff, command, review, or explicit non-skill reason |

### LARGE-Session Lesson Axes And The Delivery-State Axis

A retrospective over a LARGE multi-batch / multi-phase session owes per-axis coverage (the `SKILL.md` Core Rule names the four lesson-TYPE axes — content/craft, program/process, workflow/meta, sustain — and the LARGE trigger; the sustain-entry bar of mechanism + non-luck evidence + owner routing lives there too): each axis is covered or explicitly marked `no-new-lesson`. Sustain and content/craft both read primarily from the produced-artifact source class, not from correction turns — a retro whose only evidence is corrections structurally cannot fill them (the Evidence plan hard-data-first rule). The user **re-asking the same session retrospective after a "done" claim** (especially the SAME wording) is a **same-scope correction signal, not proof an axis was dropped**: first classify it — a plain rerun, a genuinely new scope to honor, or a missed-axis re-ask. Only when it is same-scope AND the prior retro lacks *explicit* per-axis coverage do you owe a full four-axis enumeration (content/craft, program/process, workflow/meta, sustain); if scope actually changed, honor the new scope instead. Either way, never manufacture a lesson to satisfy the re-ask — an evidence-backed `no-new-lesson` mark on an axis is a complete answer for that axis.

For the delivery-state axis (a long operational delivery session's non-lesson axis, additional to the lesson axes): the source register must include a delivery-state row family before "whole-session retro complete" is claimed — changed artifact set, branch/worktree state, remote/MR state, CI or local verification state, cancelled/retried pipeline state, unresolved risks, and the next concrete action. This is still provenance, not shared-skill content: use sanitized labels in the shared landing, but keep the real per-repo evidence in scratch/private archive. Closeout evidence must record either `delivery-state rows: <scratch/private/source-register locator>` or `artifact/status axis: not-applicable, reason=<...>`. Pure doc/skill-text retros with no deployable artifact or remote delivery state record the not-applicable row instead of manufacturing empty rows. If required rows are absent, the retro can be reported only as `interim`, even when the extracted lesson text is correct.

### Pre-Completion DO-CONFIRM Card And The Iterative-Program Watermark

**Pause point: immediately BEFORE claiming "复盘完成 / retro complete / fully summarized" on any LARGE-session retrospective.** Run DO-CONFIRM (do the work from the flow above first, then confirm here); each item is an index into its canonical rule, not a restatement; any unmet item downgrades the claim to `interim`:

1. Produced artifacts enumerated as their own source-register class at charter time (a0)? A `not-applicable` claim MUST carry a resolvable artifact-inventory/search evidence locator plus the minimum checked surfaces, and the locator's evidence must be current and explicitly cover EVERY named surface — this item fails (claim downgrades to `interim`) when the locator is missing, unresolved, contradicted by the inventory, scope-mismatched against the named surfaces, or unable to prove that coverage.
2. All four lesson axes carry landed / routed / `no-new-lesson`+evidence (sustain rows meet the entry bar)?
3. Next-run delta row recorded (a0(ii))?
4. Delivery-state rows present, or `not-applicable`+reason (section above)?
5. Watermark VALIDATED at charter (below) and written/updated at closeout — this item attests the charter-time validation ran, not merely that a record was touched?
6. Every `landed` row names its fetch point (Target-Output Map rules)?
7. Self-adversary pass run before this claim (`SKILL.md` Core Rule)?

**Watermark (`covered-through`).** For an iterative-program source (multi-round research/writing/delivery), extraction completeness is per-round, not per-program: methods keep evolving after the last extraction, so a program whose newest artifacts postdate the last extraction is under-extracted by default — that gap is exactly what a once-at-the-end retro misses (the canonical retro cadence is after each event, not once per program). At charter time, check the PROJECT for an existing watermark record (a project-local note naming: last covered round/commit/artifact date, and where those lessons landed, by sanitized label) — and VALIDATE it before trusting it: reconcile the recorded boundary against the current artifact inventory, and require the watermark to reference the prior round's completed coverage evidence (its source register and per-axis dispositions through the boundary — not just one or two lesson locators); confirm that referenced evidence exists and covers the boundary. A watermark that is missing, inconsistent with the inventory, ahead of verifiable coverage, lacking the prior coverage evidence, or whose references do not resolve is NOT a delta license — a boundary plus a single valid locator proves an extraction happened, not that coverage below the boundary was complete — fall back to bounded/full re-enumeration and keep the retro claim `interim`. Only a validated watermark narrows this round's evidence plan to the delta above it. At closeout, write or update the watermark IN THE PROJECT (project notes/memory) — it is provenance and never enters the shared skill tree. No watermark found = establish one this round (full enumeration, not delta).

## Target-Output Map

Use this before editing any extraction output beyond wording-only cleanup. It prevents the common failure where source evidence updates one obvious skill but misses a sibling skill that owns the implementation, testing, product workflow, or release behavior.

| Target | Owner role | Expected decision | Source mechanism | Actual diff or reason |
| --- | --- | --- | --- | --- |
| Skill/reference/workflow/artifact name | What this target owns, such as design judgment, React implementation, app behavior, testing, product lifecycle, backend, LLM, validator, or source register | `updated`, `unchanged`, `routed`, or `pending` | Which source observation could affect it | File diff, commit, or explicit reason no update is needed |

For any extraction beyond wording-only cleanup, add a provenance-to-target diff beside the map before final validation:

| Source mechanism | Provenance row or source id | Target file | Executable landing | Test or acceptance owner | Status |
| --- | --- | --- | --- | --- | --- |
| Reusable behavior, recipe, state rule, token rule, test gate, or workflow mechanism | Source-register/source-map/evidence-map row that claims the mechanism | Owning skill or reference file, not only a provenance file | Section, line, checklist, recipe, or gate a normal user can apply without source access — PLUS the fetch point that makes it fire: which decision point mechanically reaches it (closeout row, validator, charter field, walked checklist, trigger surface). Text that merely exists in a file with no named fetch point is `downgraded`, not `landed` — captured-but-unretrievable is the canonical lessons-learned failure | Skill, validator, test scenario, product/design/dev/test acceptance owner, or explicit no-test reason | `landed`, `routed`, `downgraded`, or `pending` |

Status mapping: target-output map status says what happened to a target (`updated`, `unchanged`, `routed`, or `pending`); provenance-to-target status says whether a claimed source mechanism actually became usable guidance (`landed`, `routed`, `downgraded`, or `pending`).

Rules:

- Build the map before editing, not as a retrospective summary.
- Derive the initial target list from lifecycle impact. For every affected stage, add every plausible owning target, including sibling skills in the same stage, or an explicit no-output reason before using judgment about specific skills.
- For stack-specific source evidence, include a sibling-generalization mini-map inside or beside the target-output map before editing. The map must name the source stack, immediate sibling stacks, shared owner if any, and one decision per sibling: `update`, `unchanged`, or `route-to-shared`.
- If source evidence spans multiple lifecycle layers, include each owning skill. Figma plus frontend code usually touches at least design and web/app development; complex flows may also touch testing and product workflow.
- `Unchanged` is a decision, not a default. Record why existing guidance already covers the mechanism or why the source evidence is too weak/domain-specific.
- Final verification must compare the real git diff against the map. A target marked `updated` without a diff is a failure; a target absent from the map but discovered later is a routing RCA.
- Final verification must also compare lifecycle impact against the map. If design/UX, implementation, testing, launch, iteration, onboarding, or no-source-access usage is marked affected but a plausible owner or sibling owner in that stage has no target/no-output row, the extraction is incomplete.
- Final verification must include a provenance-to-target diff check. For each mechanism claimed in a source register, source map, evidence map, target-output row, or task-retrospective event, identify the target skill/reference line or section that normal users will read, AND the fetch point that fires it (per the Executable landing column). If no such line exists, add it, route the mechanism, or downgrade the extraction claim to provenance-only; if the line exists but no decision point reaches it, `downgraded` — do not report `landed`.
- `Pending` in the provenance-to-target diff blocks a complete/final claim. `Downgraded` is allowed only when the final/source-map wording says the mechanism is provenance-only or insufficiently evidenced, not extracted guidance.
- When evidence is added after the first pass, update every affected layer of provenance: detailed source row, source-map summary, target-output map, source-evidence map, and executable reference. A detailed row that mentions a mechanism while the generalized extraction summary or executable target omits it is an incomplete extraction.
- Do not count source-register or source-map text as the skill itself. Provenance proves where a rule came from; the owning skill/reference must still tell a future user how to apply, implement, test, or reject the rule without reading the provenance trail.
- **Reconcile the map against every upstream disposition surface before closeout — the map is a transcription, and transcriptions drop rows.** Walk every disposition surface still valid for the current scope — whichever round or session produced it (per-axis lesson tables, candidate ledger, a refined or replay-produced map; a cross-session resume inherits the prior round's surfaces, it does not reset them) — and list the surfaces actually reconciled: every row whose disposition carries a forward obligation — `routed`, `landed`, `updated`, `pending`, or any status naming an owner/output — must resolve to a map row (`updated`/`unchanged`/`routed`/`pending` with owner — a `pending` map row preserves the blocker per the existing pending rule instead of forcing a fake terminal status) or carry a superseded note that names the successor map row covering the same mechanism; derive the surface list from the round's own records (charter, source register, produced-artifact rows), not from memory — a disposition surface named in those records but absent from the reconciled list keeps the claim `interim` (wholesale omission of the records themselves is fabrication, out of scope for this gate and covered by the never-fabricate red line); only evidenced terminal rows (`discarded`/`no-new-lesson`/`not-applicable` with reason) need no map row, and a superseded note with no successor is `downgraded`/`pending`, not closure. A dispositioned row silently absent from the map blocks the complete claim — "diff matches map" then passes while the lesson is lost, which is the exact hole this check closes (observed shape: an axis table routed a craft lesson to two owners; the refined map omitted the row; the landing round verified diff-vs-map clean and shipped without it, caught only by user challenge).

## Capability Naming And Provenance

Use this when naming a new skill, naming a reference file, renaming an extracted artifact, or turning a source-specific pattern into reusable guidance.

Rules:

- Name the durable output by the reusable capability a future teammate needs, not by the source artifact that taught the rule. Prefer names like `complex-workspace-patterns`, `testing-strategy`, or `python-service-architecture`; avoid names that mirror a Figma file, old feature, migration task, internal project, or source page.
- Source names belong in provenance only: source maps, source registers, evidence rows, or a short `Source` field inside a reference. They should not be the trigger, routing label, file name, or normal reading path unless the skill is explicitly about that source.
- For private or domain-sensitive sources, shared provenance must be sanitized too. Replace repo names, product names, source file/page names, and domain-heavy labels with capability-first aliases in shared skills; keep original-to-alias mappings only in local private notes or memory so future duplicate extraction can still be detected.
- Generalization must update semantics, not only paths. After a rename, scan headings, role sentences, rules, source registers, sibling skills, and final summaries for the old source label, old English shorthand, and old capability phrase. Replace them with the new reusable concept, or mark them as provenance.
- If a source-specific name still feels clearer than the generic name, the extraction may not yet have identified the real reusable capability. Pause and restate the capability in one sentence: "A future user can use this to ...". Name from that sentence.
- If the source contains both design and implementation lessons, the generalized name should be broad enough for both, or the target-output map should split the lessons into separate skill/reference owners.

Validation checklist:

| Check | Required evidence |
| --- | --- |
| Capability sentence | A one-sentence statement of what future users can do with the extracted artifact without source access. |
| Source/provenance split | Public/shared skill content uses sanitized capability aliases for private sources; original source names appear only in local private alias maps or explicitly non-shared notes. |
| Residual search | Search old file name, old source label, old shorthand, and old capability phrase; every remaining hit is either removed or justified as provenance. |
| Sibling sync | Any design, web, app, backend, test, or product sibling that used the old label is updated or explicitly marked unchanged. |
| Final wording | Commit message and final response use the reusable capability name, not the source artifact name, except when reporting provenance. |

## Full-Coverage Source Register Protocol

Use this protocol when the user is building or refining reusable skills through broad source extraction, or when the prompt asks for full/deep/complete extraction across a task or workflow, product workflows, codebases, all Figma/design files, document sets, review history, online examples, or multiple target skills.

Do not begin by writing target skills or final rules. Begin with a source register.

Minimum source register columns:

| Column | Meaning |
| --- | --- |
| Source id | Task, workflow, repository, package, design file, document set, meeting/review source, session history, or external source label. Keep private paths only in internal provenance. |
| Source class | Task/workflow, product workflow, Figma/design, frontend, app, backend service, tests, CI/build, docs, existing skills, review/history, online benchmark. |
| Inclusion decision | Include, exclude, route, unavailable, or pending. |
| Minimum read depth | File-level, page-level, node/artifact-level, command/test-level, or workflow-level. |
| Actual read depth | What was actually inspected. |
| Mechanisms extracted | Reusable behaviors, workflows, tests, gates, or recipes. |
| Domain details discarded | Business nouns, legacy IA, stale pages, one-off code, low-quality examples. |
| Target skill/reference | The smallest skill or reference that owns the extracted rule. |
| Completion evidence | File/page/node list, command output, review note, screenshot, source-map row, or reason unavailable. |

Completion rules:

- "All code" does not mean every byte must be memorized, but every effective project/module must be inventoried and assigned a minimum read depth. Generated, vendor, build, archive, and explicitly obsolete areas can be excluded only with a reason.
- Packaged, bundled, minified, source-map-reconstructed, compiled, decompiled, or generated source trees are a source-quality boundary. In private provenance, record the production method, raw artifact names, paths, command output, maps, manifests, hashes, and what cannot be proven from the artifact. Shared skill text and shared registers use only sanitized artifact/module aliases, counts, non-reversible sanitized evidence labels, and sanitized evidence IDs; raw lists, command output, and raw hashes stay private. Do not use full/complete/all claims for these trees unless the claim is explicitly scoped to an inventoried artifact boundary derived from an enumerated artifact source such as a package manifest, archive listing, build output, container layer listing, source-map index, or explicit user scope; arbitrary or manual subsets must be labeled partial or representative. The closure check starts from every member of that boundary, then follows discovered references; every boundary member, package file, chunk, map, manifest, declaration, embedded source reference, lazy/runtime-loaded entry, sidecar, and external asset is inventoried, excluded with reason, or marked unavailable. Such a claim means only "full inventory of the reconstructed artifact boundary", not original-source, runtime-behavior, or product-completeness coverage. Representative architecture extraction is allowed only after a source register exists, excluded areas are named, final wording says representative, and the register states the representative question, sampled artifact strata, observable architecture signals, distorted or unavailable signals, and exact claim boundary.
- "All Figma" requires a file/page register. If the tool cannot enumerate the project, use known file keys, local source maps, user-provided lists, or ask for an export; do not claim full project coverage from a few keys.
- Representative sampling is allowed only after the register exists and only when the final claim says representative. It cannot support "complete", "final", "all", or "full" wording.
- A broad extraction must produce a target-output map: each affected skill, document, workflow, product artifact, or code artifact marked updated, unchanged, routed, or pending.
- A focused extraction beyond wording-only cleanup must also produce a smaller target-output map when source mechanisms cross skill boundaries.
- If the user says the previous extraction was shallow, run correction RCA first and add a prevention rule before continuing. Then reopen the source register and show what changed in the completion standard.

Batch-progress rule: if the source boundary is too large for one pass, split it into named batches and give each batch a status: `pending`, `read`, `deep-read`, `excluded`, `unavailable`, or `routed`. Do not call the whole extraction complete until every required batch is closed or explicitly downscoped.

## Blocked Verification And Source-Read Remediation

Before marking verification or source coverage unavailable, attempt a smaller, alternate, or setup remediation and record it in the blocked row.

- Verification examples: launch the emulator then rerun device discovery, restart the browser/server, start the local dependency container, rerun a readiness probe, or execute the repo setup script.
- Source-read examples: retry a broad failing code scan as narrowed modules/files/branches; for design/Figma-like sources, retry page list -> top-level node list -> single section/frame -> direct children -> selected text/metadata -> screenshot fallback. Also available: a cached or previously-exported copy of the source, and a screenshot-only read — the latter is coverage only when recorded with an explicit weaker-evidence label.
- **Every rung above changes HOW you read. When the source is missing rather than unreadable, change WHERE you enumerate — otherwise a present source gets recorded `unavailable`.** For a **store keyed by something other than the unit you are asking about** — session transcripts, logs, notes, or state filed into a directory derived from the working directory a session ran in (likewise per-host, per-branch, or per-user stores) — "not in this project's directory" is NOT absence: one program routinely spans several working directories (a sibling checkout, a subdirectory, a worktree), so the store's key is not the program's boundary. Re-enumerate by the program's own boundary before recording any absence: scan every **in-scope, already-authorized** store root across the relevant time window and read each record's **own recorded key field** (its logged working directory), rather than trusting the directory the record was filed under. **Re-enumeration widens the search inside the access boundary you already hold — it never licenses reading another user's, another tenant's, or an out-of-scope project's store, and a shared host makes those adjacent by construction**; a root you may not inspect is recorded as an excluded root, never silently walked or silently skipped — and **an exclusion is only valid with support, because "excluded: out of scope" is otherwise the cheapest way to fake a re-enumeration**: the row names the specific root and carries either scope/authority evidence or a recorded failed access probe (the command and its error), not a plausible-sounding reason. An `unavailable` verdict is **blocked** while any exclusion covering a plausible location is unsupported. Failure shape: a retrospective declared its source session's transcript `unavailable` and downgraded that round's lessons to artifact-side reconstruction, while the transcript sat intact under the sibling directory the researched program had actually run in — the remediation attempted was another read strategy, never a re-enumeration.
- No remediation attempt means the extraction or retrospective is incomplete; unavailable is a state after attempted recovery, not a first response.

### Read in chunks: large reads lose the middle

**Large reads can lose the middle with no reliable signal — the trigger is read-OUTPUT size, so chunk proactively** (the always-on form is in `agent-context/session-start.md`; this is the detail; the `SKILL.md` blocked-source-read rule carries the red line). A large read can be head+tail truncated — sometimes with a truncation marker that is easy to miss, sometimes none, so absence of a marker is not proof of completeness; on affected Codex versions/tool paths it keeps only the head + tail of a read whose OUTPUT exceeds 256 lines or 10 KiB and drops the middle ([openai/codex#6426](https://github.com/openai/codex/issues/6426) — version-drift probing detail in the read-coverage check of `dual-track-review-gate.md`; separately, `project_doc_max_bytes` is a host config budget for project-doc ingestion and does NOT affect tool-output truncation), and it is per-read output, not file metadata, so an oversized `sed`/`cat` range re-truncates its *own* middle. So when you need a **complete** view of any source over ~256 lines / ~10 KiB (whole-file coverage, a no-findings/absence claim, or a load-bearing owner-section read — a targeted single-line `sed -n 'Np'` lookup is fine as-is), read it in chunks each kept under **both ~200 lines AND ~8 KiB** (measure each chunk with `sed -n 'a,bp' file | wc -lc`; per-`##` sections or paged reads) and confirm a **mid-file** section was ingested; a single `cat`/whole-file read does not count as coverage even when it returns no error.

Pressure scenario for this protocol:

> A future teammate with no access to the original Figma, code, documents, or source history uses the extracted skill or workflow for a different task. The skill must give reusable decisions, recipes, and validation gates without copying the source domain, and the source register must prove that the rules came from inspected sources rather than post-hoc intuition.

## Evidence-First Rule Changes

Use this when a skill change adds a new rule, conceptual layer, workflow gate, or quality standard.

- Do not write the final rule first and then look for examples that support it. Start with source observations, candidate rules, conflicts, and keep/merge/discard decisions.
- A useful intuition can be kept as a working hypothesis during analysis, but it is not executable skill guidance until evidence confirms it. If evidence is weak, narrow the rule, route it to another skill, or leave it out.
- If the user challenges whether the change was source-backed, treat that as a process failure unless the source ledger already proves the claim.
- Do not turn general expertise into "extracted from source" guidance. General expertise can inform questions, pressure scenarios, and review criteria, but it must not become executable skill guidance for subjective design, UX, frontend/client, product, architecture, or review work unless it is backed by source evidence or an inspected high-quality external source. If it remains unverified, keep it as a low-confidence note, narrow it, or leave it out.
- For UI/UX/client extraction, do a judgment-delta pass before landing design rules. For aesthetics, interaction logic, behavioral logic, and psychology, mark each candidate as `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence`. A pass that adds only layout recipes, state sets, screenshots, or validation gates is useful, but it must be reported as execution hardening rather than new judgment knowledge.

Use honest coverage labels:

| Label | Required evidence |
| --- | --- |
| Wording cleanup/no new source read | Only wording, routing, validation, or organization changed; no source-derived claim should be added. |
| Targeted check | Named source classes or artifacts inspected for a specific question; claim only that narrow question. |
| File-level refresh | Named files/repos/design files inspected at page, module, or top-level structure level; claim coverage of those files, not every node or implementation detail. |
| Node/artifact-level inventory | Concrete node/module/component/state inventory with observations and exclusions; broad "full", "complete", or "all" wording is allowed only at this level and only for the inventoried boundary. |
| Full workflow extraction | Purpose, source matrix, conflict decisions, executable recipes, validation, and sibling routing all covered. |
| Generator/tooling change | Deterministic scripts or validators updated when documentation cannot reliably enforce the rule. |

When writing a source map or final summary, use the weakest true label. If in doubt, downscope the wording.

## Database And DAL Extraction Method

Use this when extracting database experience from repositories with models, DDL, migrations, generated DAL, repositories, query builders, transactions, cache locks, data migrations, or sharding logic. Do not summarize database experience from file counts alone.

Start with a database source register:

| Source class | Minimum evidence to collect | What to extract | Typical owner |
| --- | --- | --- | --- |
| Schema and model definitions | DDL, migrations, model structs/classes, generated schema metadata, comments, unique constraints, soft-delete fields, timestamps | Table ownership, source-of-truth, primary key strategy, required/default fields, enum/state fields, unique constraints, compatibility and rollback needs | Architecture skill |
| Indexes and query paths | Index definitions plus repository/service call sites that use the filter/order/group shape | Composite index order, stable pagination, uniqueness as data invariant, high-cardinality list safety, query-plan risk | Architecture and testing skills |
| Repository and DAL methods | Generated query/update helpers, handwritten repository methods, raw SQL, transaction-bound variants | Intent-focused repository APIs, query-builder safety, bounded lists, explicit update columns, raw SQL containment, read/write routing | Implementation skill |
| Create/upsert/import paths | Service mutation flow, validation, unique-key checks, batch import code, generated IDs, side effects | Idempotency, default state initialization, transaction boundary, partial-failure report, duplicate handling, post-create side effects | Implementation and testing skills |
| Update/delete/state transition paths | Status machine updates, partial updates, locks, compare-and-set, audit/outbox/cache/index updates | Optimistic/pessimistic locking, constrained updates, delete safety, audit/outbox atomicity, repair/replay path | Implementation, architecture, testing skills |
| Transactions and consistency | `Tx` wrappers, transaction-bound repositories, retry/rollback paths, panic recovery, post-commit effects | What must be atomic, what is async/repairable, stale/pending state visibility, compensation and reconciliation | Architecture and implementation skills |
| Sharding and partitioning | Shard key, router function, table suffix, shard-aware DAL, migration/backfill tools, bypass rules | Shard-key choice, query must-carry constraints, cross-shard aggregation policy, migration plan, route tests | Architecture, implementation, testing skills |
| Cache and DB interaction | Redis/cache keys, Lua/CAS helpers, invalidation, counters, locks, DB fallback | Cache-aside/write-through boundaries, stale-read tolerance, lock ownership, counter consistency, miss/rebuild behavior | Implementation and testing skills |
| Tests and CI | Unit/integration tests, live-infra tests, wrappers, migration dry-run, generated drift checks | Which DB behavior is actually asserted, which tests are diagnostic only, what new gates future DB changes need | Testing skill |

Extraction rules:

- Trace each durable rule through `schema/model -> query/mutation call site -> transaction/cache/side effect -> test or missing test`. A schema field or DAL method by itself is evidence of existence, not evidence of a reusable rule.
- Infer index lessons from real query shapes, not from index names alone. Record the filter, sort, pagination, and uniqueness invariant that make the index necessary.
- Separate table design from repository implementation. Architecture owns data ownership, source-of-truth, sharding, migration, and consistency policy; implementation owns generated DAL usage, repository shape, transaction helpers, update builders, and code safety; testing owns proof.
- For create/update/delete rules, identify the failure prevented: duplicate creation, lost update, invalid status transition, partial side effect, stale cache/index, unbounded write, or unrecoverable migration.
- For sharding rules, require a route key, query constraint, migration/backfill story, and test surface before landing a strong rule. If only table suffixes or router names were inspected, record provenance but downgrade the rule.
- For cross-language generalization, route language-agnostic lessons to architecture or testing first. Mirror into Python/Go implementation only when the target stack has enough evidence or the rule is about a shared concept such as repository boundary, transaction scope, migration review, or cache consistency.
- Keep raw SQL snippets, table names, field names, and business-domain labels out of shared guidance. Preserve only sanitized source rows and capability-level observations.

Candidate rule ledger shape:

| Observation | Evidence path | Failure class | Candidate reusable rule | Keep/merge/route/discard | Target owner | Required verification |
| --- | --- | --- | --- | --- | --- | --- |
| Query filters by owner, state, and created time with stable sort | schema/index plus repository list call | slow list or unstable pagination | Composite index and pagination must match real filter/sort path | keep | architecture/testing | repository test, large-fixture test, or explain/dry-run note |

Completion standard:

- The final claim must say whether coverage is topology inventory, targeted DAL extraction, representative workflow extraction, or full database workflow extraction.
- A complete database extraction needs closed rows for schema/model, indexes/query paths, create/update/delete, transactions, cache/side effects, sharding/migration if present, and tests.
- Do not land a final database rule if the only evidence is generated code, file names, or a single isolated DAL helper without a caller.

## Redis Extraction Method

Use this when extracting Redis experience from repositories with cache adapters, distributed locks, Lua scripts, rate limiters, idempotency stores, counters, Redis Streams, Pub/Sub, lightweight task queues, local caches, or Redis-backed coordination. Do not reduce Redis extraction to a list of commands.

Start with a Redis source register:

| Source class | Minimum evidence to collect | What to extract | Typical owner |
| --- | --- | --- | --- |
| Client setup and lifecycle | Config, secret lookup, service discovery, sync/async client choice, pool/timeouts, ping/readiness, close/shutdown paths | Dependency assembly, fail-open/fail-closed behavior, test substitution, resource cleanup | Implementation and architecture skills |
| Key builders and scope | Key functions/constants, prefixes, tenant/user/resource dimensions, environment/lane isolation, pattern-delete use | Key namespace policy, collision prevention, sensitive-value avoidance, key migration/invalidation | Implementation and architecture skills |
| Cache usage | Cache-aside/write-through code, negative cache, JSON/schema decode, malformed payload handling, invalidation/delete paths, DB fallback | Freshness window, stale-read tolerance, cache miss vs Redis failure, value versioning, invalidation ownership | Implementation, architecture, testing skills |
| Locks and leases | `SET NX EX/PX`, Redlock/proven library, unique token, compare-and-delete unlock, renewal, wait/retry loops | Lock scope, lease/max lease, cancellation, renewal failure policy, duplicate-work prevention | Implementation and testing skills |
| Lua/CAS/transactions | Scripts, `EVAL`/`EVALSHA`, `NOSCRIPT` reload, `WATCH`/pipeline, return codes, error mapping | Atomic compound operation, compare-failed/missing-key semantics, fallback and observability | Implementation and testing skills |
| Counters, quotas, rate limits | `INCR/DECR`, positive-only counters, sorted-set sliding windows, retry/conflict behavior, expiry policy | Missing-key semantics, underflow behavior, exact vs approximate truth, user-facing error contract | Implementation, architecture, testing skills |
| Idempotency and dedupe | SETNX claims, pending/complete markers, owner tokens, retry counts, TTLs, persisted DB/outbox fallback | Duplicate handling, claim expiry, durable truth boundary, fail-safe behavior on Redis errors | Architecture, implementation, testing skills |
| Streams, Pub/Sub, queues | `XADD/XREAD`, consumer groups/ack if used, heartbeat, stream TTL, delete/trim, Pub/Sub publish/subscribe | Delivery guarantees, replay/resume point, lost-message tolerance, cleanup, user-visible progress state | Architecture, implementation, testing skills |
| Tests and diagnostics | Unit/integration tests, fake Redis/fakeredis, containers, live Redis tests, logs/metrics, slow/hot key checks | Which Redis behavior is asserted, which tests are diagnostic only, what future Redis changes need as gates | Testing skill |

Extraction rules:

- Classify each Redis use by responsibility first: cache, lock, idempotency, counter/quota, rate limit, stream/queue, session, config, or diagnostic helper. A command name alone is not a reusable pattern.
- For every kept rule, name the failure prevented: stale authorization, duplicate side effect, lock leakage, lost queue item, counter underflow, rate-limit bypass, cache poisoning, hot key, data leak in logs, or unbounded scan/delete.
- Trace correctness through `key scope -> command/script semantics -> failure behavior -> caller decision -> test or missing test`. A Redis helper without caller behavior or test evidence should usually remain provenance-only.
- Separate ephemeral coordination from durable truth. If Redis controls a domain outcome, require a persisted record, idempotency table, outbox/event log, reconciliation path, or explicit risk acceptance.
- For cross-language generalization, route language-agnostic Redis rules to architecture or testing first. Mirror into Python/Go implementation when the target stack has matching client/runtime concepts, and add an evidence caveat when a stack has not been directly inspected.
- Treat broad key deletion, blocking stream reads, Pub/Sub, live Redis tests, and script-cache fallback as risk surfaces that need explicit limits, cleanup, and observability before becoming recommended practice.
- Keep source-specific key names, stream names, tenant labels, business event names, endpoints, and raw payloads out of shared guidance. Preserve sanitized source rows and capability-level observations only.

Candidate rule ledger shape:

| Observation | Evidence path | Redis responsibility | Failure class | Candidate reusable rule | Keep/merge/route/discard | Target owner | Required verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Atomic claim script writes pending marker with TTL and returns explicit statuses | store implementation plus tests | idempotency | duplicate side effect or stuck pending claim | Idempotency claims need pending/complete states, TTLs, explicit return codes, and retry/removal behavior | keep | architecture/implementation/testing | duplicate, pending, expired, Redis-error tests |

Completion standard:

- The final claim must say whether coverage is Redis topology inventory, targeted Redis extraction, representative workflow extraction, or full Redis workflow extraction.
- A complete Redis extraction needs closed rows for client lifecycle, keys/TTL, cache, locks, atomic scripts, counters/rate limits if present, streams/queues if present, idempotency if present, observability, and tests.
- Do not land a final Redis rule if the only evidence is a command wrapper, file name, or one isolated helper without caller semantics or failure handling.

## Correction RCA Protocol

Use this when the user, reviewer, or later evidence shows that a skill extraction was incomplete, overstated, too generic, under-sourced, or landed in the wrong skill.

Automatic trigger:

- Trigger correction RCA without waiting for an explicit "沉淀" request when a user correction or review reveals a reusable extraction failure: missed source class, missed sibling skill, shallow principle without executable recipe, overclaim, domain leakage, missing validation, missing source register row, missing target-output row, or missing automatic trigger.
- The minimum output is not a chat summary. Add or update the smallest owning skill, reference, checklist, validator, or final-response rule so the next agent will encounter the prevention point during normal work.
- If the issue is task-specific and should not become a skill rule, record the explicit non-skill reason in the source/register or final response before resuming.

Record a compact RCA before continuing:

| Previous wrong behavior | Contributing cause(s) | Missed evidence or gate | Corrective rule | Target | Verification |
| --- | --- | --- | --- | --- | --- |

Contributing-cause categories (widen first per the Deep RCA moves, then mark every category that applies — a correction may have more than one; don't force a single pick):

- Source coverage gap: required repositories, Figma files, docs, tests, CI, or external sources were not inspected.
- Post-hoc evidence fitting: rule was written first, then evidence was found or phrased to support it.
- Evidence-depth overstatement: the summary claimed full/complete/all/re-read coverage when only a targeted check was done.
- Source-quality misread: low-quality, stale, diagnostic, generated, or domain-specific material was absorbed as a positive rule.
- Domain leakage: business nouns, legacy product structure, personal paths, or source-specific labels leaked into executable guidance.
- Execution gap: skill had directional principles but lacked recipes, state coverage, commands, acceptance gates, or verification evidence.
- Routing gap: the lesson belonged in a sibling skill, shared workflow skill, validation script, or product/code artifact instead.
- Validation gap: existing static checks or reviews could pass while the same failure mode remained possible.
- Landing/reporting gap: final response, source map, or commit message overstated what was done or failed to preserve durable evidence.

Corrective actions:

- Add or update the smallest owning rule, reference, validation check, or script.
- If no skill change is warranted, record why the issue is task-specific and how the final response should state the limitation.
- Re-run the failed pressure scenario to show the rule now blocks the exact failure mode — this is the behavioral-evidence row (`RED-baseline` for a behavior/routing change). An independent reviewer checking the fix is in addition, not a substitute.
- Commit messages for RCA-driven changes must include the observed wrong behavior, source IDs or session evidence, and the prevention rule landed.

## Repeated Correction Escalation

Use this when the user corrects the same failure class more than once in one extraction effort, or asks why the lesson was not already durably landed. At that point, the problem is no longer only the target skill; it is a workflow-control failure.

Stop normal extraction and record:

| Required item | What to write |
| --- | --- |
| Repeated failure class | The recurring mistake, keyed off the **primary lever** (the necessary / highest-leverage contributing category after counterfactual ranking), not the full multi-label set — recurrence fires when the same primary lever repeats across rounds even if the secondary contributing categories differ. Use the taxonomy above. |
| Prior weak fix | What was previously said or changed that did not prevent recurrence. |
| Missing hard gate | The exact checklist, source register, validation, review, or reporting gate that would have stopped the mistake earlier. |
| Owning artifact | The smallest skill, reference, script, or final-response rule that should own the gate. |
| Prevention update | The concrete rule added now, written as "when X, do Y, verify Z". |
| Proof before resume | The behavioral-evidence row proving the rule now fires (re-run scenario / `RED-baseline` for behavior/routing changes); a bare command or diff suffices only for a non-behavioral mechanical fix. |

Escalation rules:

- Do not answer "已经沉淀" from memory. Open the owning skill or reference and verify the rule exists.
- Do not count a chat summary, apology, or final-response explanation as durable landing. The lesson is durably landed only when a future agent will hit a skill rule, reference checklist, validation script, or required reporting format.
- If the same extraction keeps failing because the source boundary is unclear, freeze target-skill edits until the source register is updated and the completion claim is downgraded or closed.
- If the same extraction keeps failing because rules are too directional, add executable recipes or acceptance checks, not more principles.
- If the same extraction keeps failing because evidence was fitted after the fact, require an observed ledger entry before the next landed rule.
- If the same extraction keeps failing because final answers overclaim, add final-response wording constraints and rerun independent review against that exact failure class.
- If the recurring failure is "we summarized the lesson but did not automatically land it", add an auto-trigger rule to the owning workflow. The proof is a file diff in the workflow/validator/reference, not a promise to remember next time.

Pressure scenario:

> The user asks "这个教训沉淀到技能中了么?" after repeated corrections. A correct response opens the owning skill, points to or adds the prevention rule, validates it, and states the commit or file changed. An incorrect response only says "已沉淀" based on intent or prior chat.

## Thin Evidence Protocol

When evidence is sparse, stale, or one-sided:

- Extract fewer and narrower rules.
- Mark low-confidence assumptions as questions or source gaps instead of executable behavior.
- Expand "do not use when" boundaries so future agents do not over-apply the rule.
- State what evidence would raise confidence: repeated examples, tests, production checklists, review records, source access, or a confirmed user decision.
- Avoid filling gaps with invented links, invented quotes, generic search results, or copied boilerplate from unrelated skills.

## Source Coverage Matrix

Use a coverage matrix for broad extractions. The matrix is a temporary analysis artifact, not a skill file.

| Source category | Check | Useful output |
| --- | --- | --- |
| Root docs | Agent instruction files, README, architecture docs, local conventions | repo intent, commands, ownership, constraints |
| Build and CI | Makefile, package metadata, CI config, scripts | canonical commands, gates, generated artifacts |
| Contracts | protobuf/OpenAPI/RPC/event schemas, migrations, API docs | compatibility rules, contract-first workflow |
| Runtime wiring | config, dependency clients, lifecycle, readiness, observability | platform boundaries, failure behavior |
| Tests | unit, contract, integration, E2E, fixtures, test docs | quality gates, evidence patterns |
| Agent skills | local `.claude`, `.codex`, `.trae`, or other skill folders | workflow habits, review/debug/test automation methods |
| Product/design sources | design systems, Figma-derived notes, UI implementation states | design readiness, interaction states, handoff rules |
| Review/bug history | review notes, postmortems, repeated user corrections | prevention rules, conflict decisions |

Skip or down-rank generated code, vendor trees, third-party assets, static bundles, archived/deprecated systems, and source areas explicitly declared obsolete unless they reveal a contract or migration rule.

## Extraction Ledger

During analysis, track candidate rules in a small table:

| Origin | Source IDs read before drafting | Evidence | Candidate rule | Conflict | Decision | Target | Reason |
| --- | --- | --- | --- | --- | --- | --- | --- |

## Judgment Delta Matrix

Required before landing UI/UX, Figma, frontend, app, or client extraction as design-judgment work. It prevents the common failure where a pass adds layout recipes or validation checks but reports them as newly extracted aesthetics, interaction logic, behavioral logic, or psychology.

| Judgment layer | Delta | Source observations | Candidate rule or decision | Target reference | Verification |
| --- | --- | --- | --- | --- | --- |
| Aesthetics | `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence` | What was observed about hierarchy, density, spacing, rhythm, color weight, material, mood, craft, or visual focus | What rule changes, what is discarded, or why no new rule is landed | Owning design/client reference | Screenshot, node evidence, or review pressure scenario |
| Interaction logic | `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence` | What was observed about entry, inspection, action, confirmation, return, progressive disclosure, or task continuity | What rule changes, what is discarded, or why no new rule is landed | Owning design/client reference | Flow trace or rendered interaction check |
| Behavioral logic | `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence` | What was observed about repeat, mistake, waiting, interruption, disabled states, undo, retry, cancel, or recovery | What rule changes, what is discarded, or why no new rule is landed | Owning design/client reference | State-machine check, scenario test, or code evidence |
| Psychology | `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence` | What was observed about anxiety, uncertainty, perceived control, trust, motivation, consequence, or cognitive load | What rule changes, what is discarded, or why no new rule is landed | Owning design/client reference | Pressure scenario or rendered acceptance check |

Use decisions consistently:

- Keep: promote directly to the owning skill.
- Merge: combine compatible variants into a generalized rule.
- Discard: stale, domain-specific, deprecated, weak, or contradicted.
- Route: useful, but owned by another skill.

The ledger prevents two common failures: silently skipping a source and appending conflicting rules without judgment.

Use `origin` strictly:

- `observed`: the rule came from source observations recorded before drafting the landed rule.
- `hypothesis`: the rule came from intuition, external memory, reviewer suggestion, or a user challenge before the supporting source was inspected.

Do not land a source-derived rule while it is still `hypothesis`. Convert it to `observed` only when the ledger names the source IDs and concrete observations that support it; otherwise narrow, route, discard, or keep it out of the skill.

For high-subjectivity skills such as design, UX, frontend/client, product workflow, architecture, or review, include pressure scenarios in the ledger before editing. A rule is not ready if it cannot explain what future bad output it prevents and how acceptance will notice the difference.

## Decision Persistence

The extraction ledger can stay temporary, but consequential decisions must leave a durable trace:

- For source-heavy skills, keep source status, exclusions, and keep/merge/discard summaries in a source map or evidence map.
- For any landed source-derived rule, the durable trace must retain rule origin, source IDs read before drafting, and concrete observations. This can live in a source map, evidence map, correction log, or concise commit/response summary for very small changes, but it cannot be omitted.
- For small changes, include the decision reason in the final response or commit body without copying private source details.
- For discarded sources, record enough reason to avoid re-litigating them: stale, weak, duplicated, domain-specific, superseded, low quality, or routed elsewhere.
- For skills that evolve through repeated corrections, keep a compact correction log pattern: scene, previous wrong behavior, corrected rule, target file or section, and date/version when relevant.
- Do not preserve raw source dumps, credentials, personal paths, screenshots, or business-specific records just to explain a decision.

## Extraction Questions

- What decision did humans or agents repeatedly get wrong?
- What boundary, command, artifact, or gate prevented the mistake?
- Is the rule task-generic, stack-generic, or stack-specific?
- Which sibling skill owns the next level of detail?
- What evidence proves the rule is useful beyond one codebase?

## Generalization Pass

- Replace business nouns with role-neutral nouns: service, user, caller, workflow, contract, dependency, tenant, artifact.
- Replace concrete repo paths with discovery instructions: read agent instruction files, CI config, package metadata, scripts, and local docs.
- Keep code names only in provenance notes while analyzing; remove them from final executable guidance.
- Translate examples into conditions and checks rather than copying source structure.
- Add negative space: when not to use the skill, when to route elsewhere, and what not to extract.

## Source-Derived Design And Code Skills

When extracting from design tools, product screenshots, frontend code, or interaction-heavy sessions:

- Keep one canonical source repository for the skill, then install it through symlinks or the user's standard skill installation mechanism so every agent reads the same files.
- Separate usable rules from provenance. Normal users should need only the skill entrypoint and focused references; Figma URLs, file keys, local code paths, and source names belong in source maps or evidence maps.
- Make the skill usable without source access. Lack of Figma or repository permission should not block normal design, implementation, review, or launch-check work.
- Treat source names as evidence labels, not product intent. A source domain should not define the new skill's product domain unless the active user context explicitly says that domain is intended.
- Write capability-first rules. If a source has domain-heavy file names, repository paths, or workflow labels, put the generalized capability first and demote source identity to provenance.
- Prefer focused references over one giant extraction file. Add a focused reference when a pattern is strong enough to be loaded independently, such as complex creation, analytics, operational processing, resource management, frontend code evidence, or launch acceptance.
- Code evidence is not design taste. Frontend repositories can provide state handling, permission, upload, task, responsive, build, and observability patterns, but low-quality or domain-specific UI should not become visual guidance.
- If a design skill built from Figma or frontend code still cannot guide attractive, shippable screens, treat the extraction as incomplete. Re-open the design sources and implementation evidence, then add executable layout recipes, component hierarchy, spacing/density rules, state templates, interaction patterns, and rendered acceptance criteria.
- Pair design-source extraction with frontend-code extraction carefully: design tools provide visual intent and interaction models; code provides real states, data density, runtime constraints, component boundaries, and failure handling. Keep both, but do not let weak implementation quality override strong design intent.
- Behavioral, aesthetic, psychology, or interaction-logic guidance must be grounded in source evidence or inspected high-quality external sources. Do not add these layers as generic-sounding polish. If a related point remains external expertise only, keep it outside executable guidance unless it is explicitly scoped as low-confidence review context with pressure scenarios and acceptance checks.

### Figma Reading Method

Use this method when extracting from Figma into reusable skills:

1. Start from a file register, not from a few visible frames.
   - A team/project URL is a scope clue, not proof of full coverage. If the tool cannot enumerate the project, use known file keys, a user-provided export/list, or local source maps, and state that the boundary is known-key coverage.
   - Each row needs file name, file key, source status, inclusion decision, minimum read depth, actual read depth, extracted mechanisms, discarded domain details, and target skill/reference.
2. Classify file and page status before extracting rules.
   - Current/formal files are primary evidence.
   - `补充` and `探索` are not automatic exclusions; inspect them and compare against stronger current sources.
   - Deprecated, copied, old, archive, wrong-version, and explicitly discarded pages are excluded or weak support only unless they reveal a reusable negative pattern.
   - Component libraries and icon libraries provide component capability and handoff practice, not product IA.
3. Read in layers.
   - File key -> page list -> top-level nodes -> key sections/frames -> child nodes and small text -> screenshots for visual verification.
   - Use page/node ids to re-read concrete frames, modals, drawers, hover states, toolbars, empty/error states, and small labels that are easy to miss in a large frame.
   - If large recursive node reads time out or return incomplete text, continue with child indexing and batched child-frame reads before using screenshots. Do not treat screenshots as primary extraction evidence when node metadata/design context can still be read.
   - For large sections, first run a lightweight index pass that returns page/section/frame/component names, ids, dimensions, and coordinates. Then select representative and conflict-prone frames for focused metadata or design-context reads.
   - For component instances or symbol-heavy screens, read the instance/component summary plus selected descendants: text, sizes, fills/strokes, corner radii, main component names, child count, and visible state labels. Do not infer labels or states only from visual memory.
   - Use screenshots only to verify visual composition, density, first viewport, and obvious overlap/cropping. A screenshot can support a rule, but it cannot replace node/text/state inventory for extraction.
   - If only screenshots are available, label the pass as visual inspection or screenshot-backed fallback, not Figma node extraction.
4. Recover from source-read failures before extracting rules.
   - A timeout, partial output, transport failure, or overlarge response is not evidence coverage. It is a signal to switch strategy.
   - Reduce breadth before reducing depth: page list -> top-level nodes -> one section/frame -> direct children -> selected child frames -> targeted text/metadata -> screenshot fallback.
   - Return less data per call: names, ids, dimensions, layout modes, direct children, small text samples, and visible state labels before full recursive descendant dumps.
   - Keep a retry ledger in the source register or source map: failed method, error or timeout, fallback method, recovered evidence, remaining gap, and whether the recovered evidence supports the landed rule.
   - Land only what the recovered evidence supports. If only layout dimensions were recovered, land layout rules and keep text/state extraction pending; if only top-level structure was recovered, label the pass as section-level or shallow node inventory.
   - If no fallback succeeds, mark the source row pending or unavailable with residual risk and the next unblock action.
5. Extract the four judgment layers from actual observations.
   - Aesthetics: hierarchy, density, spacing, rhythm, material, color weight, mood, and visual focus.
   - Interaction logic: entry, inspection, action, confirmation, progressive disclosure, return path, and task continuity.
   - Behavioral logic: repeat, waiting, mistake, disabled state, undo, retry, cancel, interruption, recovery, and queue/task boundary.
   - Psychology: uncertainty, cognitive load, perceived control, anxiety, trust, consequence, and motivation.
6. Pair screenshots with state inventory.
   - Capture or inspect first viewport, long content, empty/loading/error, disabled/no-permission, modal/drawer, narrow desktop, mobile portrait, and landscape when relevant.
   - A screenshot that passes only with ideal data is weak; test long labels, no data, partial data, and failure states.
   - Record which states were read as nodes and which were only visually inspected. If a conflict appears between screenshot and node/text metadata, prefer current node metadata and record the screenshot as visual support only.
7. Cross-check corresponding code when the skill affects implementation, testing, or launch.
   - Figma owns visual intent and interaction model; code owns state machines, data density, persistence, responsive calculations, failure recovery, and runtime constraints.
   - Update design, web/app development, testing, and product workflow targets according to lifecycle impact; do not land a Figma-derived rule only in the design skill when it creates implementation or acceptance obligations.
8. Preserve source access independence.
   - Normal skill users should not need Figma access. Move Figma URLs, file keys, page names, node ids, local code paths, and source-domain labels into provenance only.
   - Executable guidance must be source-neutral: layout recipes, component hierarchy, state templates, interaction patterns, implementation ownership, and screenshot/test acceptance.

9. Name coverage precisely.
   - `Known-key page inventory`: file/page/top-level nodes were read, but project-wide enumeration was not proven.
   - `Section-level index`: sections and direct child frames/components were read, but descendants were not all expanded.
   - `Batched frame extraction`: selected frames were read deeply enough to extract text/layout/state mechanics.
   - `Screenshot-backed fallback`: visual inspection was used because node reads were unavailable or timed out.
   - `Full nested-node extraction`: only use this when every required source row has closed descendant coverage or the user explicitly downscoped remaining rows.

## Execution Completeness Checks

Use these checks before treating a source-derived skill as ready:

- Source coverage is not the same as usable guidance. After reading Figma, code, docs, or online sources, convert the strongest findings into repeatable recipes: layout/state patterns for design skills, analysis/debug/test workflows for development skills, and launch/iteration gates for product workflow skills.
- Directional guardrails are insufficient for visual or interaction-heavy skills. Apply the incomplete-design extraction rule above and include examples of what to reject or merge.
- Development skills need analysis and debugging, not only implementation defaults. Include how to find the owning module, classify failures by layer, inspect runtime evidence, write regression tests, and name the verification surface.
- Treat different execution surfaces as split evidence, not an automatic split decision. Different runtime tooling, platform capabilities, build/release gates, or verification evidence may justify separate skills only when the trigger, owner, and workflow are also clearly different; shared product or lifecycle decisions belong in a routing/workflow skill.
- Keep source-specific labels out of the normal workflow. Put source maps or evidence maps behind references; the entrypoint should speak in capabilities, not in source file names, product names, or legacy domains.
- When a source is useful only as a negative example, extract the rejection rule instead of copying the pattern. Record whether the source was discarded for stale status, weak UI quality, domain specificity, duplication, or conflict.
- Treat "compliant but mediocre" likely output as an extraction defect. Apply the incomplete-design extraction rule above before claiming completion.

## Placement

- Existing skill: add routing, a core rule, or one focused reference when the trigger already matches.
- New skill: create only when the future user would naturally ask for a different task type.
- Reference file: use for detailed checklists, variants, examples, and source-derived heuristics.
- Script: use for repeatable validation, scanning, generation, or formatting that should be deterministic.
