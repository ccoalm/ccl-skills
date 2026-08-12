# External Skill Augmentation — discovery & stage mapping

Use this reference for the operational mechanics of supplementing organization gates with installed external skills.

## Ownership boundary

CCL skills remain primary owners of every stage and every gate. When equivalent external skills are installed locally, they may supplement specific disciplines but must not replace ownership or become required gates: test-first and verification rigor, plan discipline, browser-rendered QA, design review against an approved checkpoint, and ship/land/canary release motions. Discover available external skills through the current session's available-skills list instead of hard-listing external family names here. If an external skill is unavailable, the CCL skill's own gate still stands; never block delivery only because an external skill family is missing.

For multi-step implementation after assessment, map external skills to their narrow role before using them: planning skills may produce the task checklist, debugging skills may enforce root-cause evidence before a fix, TDD skills may enforce failing-test-first for behavior changes, and browser/QA skills may verify a running web/H5 surface. External skills do not decide CCL ownership; they execute or strengthen the gate owned by `product-rd-workflow`, `defect-diagnosis`, `testing-strategy`, `product-ui-ux-design`, or the relevant stack skill.

When an external spec-plan skill is available and the upgrade decision from the entrypoint is positive, run it after the existing-spec review and before implementation. Save or reference the resulting plan according to that external skill's convention, then review/challenge the plan before execution. If the external skill is unavailable, produce the same minimum content in the workflow plan and continue without treating the missing external skill as a blocker.

## Operational discipline

When external skills are discovered in the current session's available-skills list, the rule remains: CCL workflow owns the gate; external skill executes the recipe when present.

- **Do not duplicate inline what an external skill already does as a single command**. If the session has a one-shot ship skill (covers test + diff review + version bump + commit + push + PR), this workflow's "ship" step is "invoke that skill for this slice's tier", not "manually run each sub-step". This skill keeps the rule "what tier of ship for this risk"; the external skill keeps the recipe.
- **Suggest the discovered external skill BY NAME in chat** when about to perform that lifecycle stage manually, using the exact name shown in the session's available-skills list (do not guess a hard-coded family name). The by-name suggestion mechanics and the illustrative stage-to-candidate list live below; discovering the per-session mapping is the agent's responsibility, not this skill's to enumerate.
- **Exemption — multi-step cascades `product-rd-workflow` explicitly owns**: when product-rd-workflow defines a specific cross-skill cascade (notably the Feature Deprecation 7-step sequence in the entrypoint, where the cascade itself is the rule), the "don't duplicate inline" guidance does not apply — the cascade IS the contract and external skills slot into individual steps without replacing the cascade structure.
- **Cross-skill conflict resolution**: if two installed external skills give different guidance for the same lifecycle stage (e.g. a process-discipline skill family vs an operational-tool skill family disagree on plan structure), prefer the more specific operational recipe for the concrete action AND surface the principle-level disagreement to the user. Never silently pick one without naming the conflict in the slice notes.
- **For environments lacking the external skill family entirely**: every principle in the entrypoint stands alone — brainstorm before code, plan before implementation, test before fix, verify before complete, ship with rollback, retro after incident. Do not reference a missing external skill as a blocker.

## Suggest the discovered external skill by name

When about to perform a lifecycle stage manually and an equivalent external skill is present, suggest it **by the exact name shown in the current session's available-skills list** (invocation surface varies: some skills are `family-name`, some are `/short-name`, some are `prefix:name`). Phrase as "About to write a plan — `<exact-discovered-skill>` is available for plan-writing; should I use it?" rather than guessing a hard-coded family name. Do not hard-code external family names in code paths; the canonical owner is whatever the session's available-skills list provides, and discovering the full per-session mapping is the agent's responsibility, not this skill's to enumerate.

## Stage-to-candidate examples

Illustrative only — the actual canonical owner is whatever the current session's available-skills list provides:

- brainstorming / scope-shaping family (intent + requirements + scope challenge)
- plan-writing family
- plan-review family (architecture / design / DevEx perspectives)
- plan-execution / subagent-dispatch family
- branch-worktree-hygiene family
- TDD / test-first family
- debugging-with-RCA family (also covered by `defect-diagnosis`)
- code-review-request and code-review-receive family
- codex-style second-opinion (consult / review / challenge) family
- browser/visual QA family
- completion-verification family
- ship-flow family (basic ship / canary / land-and-deploy variants)
- post-ship doc-update family
- retro family
- repo-health family
- skill-authoring family
