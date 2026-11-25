# Design, Figma, And Ledger Extraction Methods

Source-coverage matrices, candidate-rule ledgers, UI/UX judgment-delta matrices, decision-persistence rules, Figma node-reading procedures, and execution-completeness checks relocated from `references/source-to-skill-extraction.md`. Load this reference for any source-derived rule extraction (to apply `## Extraction Ledger` during analysis and `## Decision Persistence` before closeout), as well as broad source inventories and design, Figma, frontend, or client extractions.

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
