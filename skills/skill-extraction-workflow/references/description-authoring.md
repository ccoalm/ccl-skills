# Description Authoring For Auto-Triggering Skills

Use this when writing or rewriting the YAML frontmatter `description` of a skill that AI clients (Claude Code, Codex, opencode, Gemini CLI, and others) match against user requests to decide which skill to auto-invoke. A skill's `description` is its routing surface — it is executable, not documentation. Get this wrong and the skill never fires, or fires for the wrong asks.

## When this reference applies

- Routing / workflow / cross-cutting skills (e.g. `product-rd-workflow`, `feature-risk-router`, `defect-diagnosis`, `testing-strategy`, `skill-extraction-workflow`, `tighten-doc`, `multi-agent-delegation`, `product-ui-ux-design`).
- Any skill where the same user can phrase the trigger many different ways and the skill must catch most of them.

When this reference does NOT apply:

- Stack-specific implementation skills (`web-react-dev`, `go-microservice-dev`, etc.) where the trigger is usually an explicit technology mention. They benefit from some of these rules but the multi-language utterance discipline below is overkill.
- Skills that are only invoked by explicit slash command and never need to auto-trigger.

## The 4-section structure

Block-scalar YAML, ordered:

```yaml
description: |
  <One-line capability statement: what this skill does, what it owns, what it routes out. Product-agnostic; no business nouns.>

  Use when asked to "<CN trigger 1>", "<CN trigger 2>", ..., "<EN trigger 1>", "<EN trigger 2>", ...

  Proactively invoke when <indirect signal A>, <indirect signal B>, ... — even when the literal skill name is absent. Do not invoke just because <common over-fire situation>.

  Skip when <already-scoped-to-other-skill situation> (e.g. "<example phrase>" → <other-skill>; "<example phrase>" → <other-skill>).
```

Four sections. In order. Each does a different job:

### Section 1 — Capability one-liner

- One sentence. Names what the skill OWNS and what it ROUTES OUT.
- Product-agnostic phrasing. Do not import business nouns, project paths, repo names, or tool-specific habits from source projects.
- Do NOT stuff a long list of related implementation skill names here — that dilutes keyword density for matching. Implementation routing belongs in the skill body, not the description.
- **Prompt-engineering discipline for the description text itself**: a `description` is a prompt that selects the skill, so write it simple and direct; reach for few-shot phrasings only when the trigger has genuinely confusing edge cases that one-liners cannot disambiguate. Do NOT bake explicit chain-of-thought directives ("think step by step", "reason carefully then …") into the description — for reasoning-capable models they are usually unnecessary and can degrade behavior (OpenAI reasoning guidance); for Claude, prefer general instructions over prescriptive step lists (Anthropic prompting guidance). If a non-reasoning model genuinely needs stepwise scaffolding for a specific task, put that in the task prompt or examples that the skill triggers, not in the description itself — the description's job is to trigger and route, not to dictate cognition.

Good: `End-to-end product R&D workflow: shapes requirements and routes design / architecture / dev / test / review / release / postmortem stages to the right skill.`

Bad: `Use when turning a product idea, feature request, bug, refactor, or release goal into an end-to-end product R&D workflow. Coordinates product clarification, architecture decisions, design readiness routing, implementation skills such as app-cross-platform-dev, web-react-dev, go-microservice-architecture/go-microservice-dev, and python-service-architecture/python-service-dev, testing, code review, release readiness, and postmortem learning.`
(Too long; implementation skill names are noise for trigger matching.)

### Section 2 — `Use when asked to "<quoted phrases>"`

- Quoted, comma-separated. Real utterances people say. Not abstract capability descriptions.
- Include both Chinese AND English variants if either language could realistically appear. Do not assume English-only or Chinese-only.
- Order: CN phrases first (or whichever language is more common for the team), then EN. Mixing is acceptable; consistency within a skill matters less than coverage.
- Each phrase should pass the 80% precision threshold (see below). Phrases that don't, must either be dropped or anchored with disambiguating context.

### Section 3 — Proactively invoke when

- Covers indirect signals: user described a situation that the skill owns but did not say the skill's name or any of the quoted triggers.
- Be specific about the situation; vague proactive clauses fire constantly.
- Add a "do not invoke when ..." negative clause for the most likely over-fire case. This is in-section guidance, not a separate Skip-when (Skip-when is about already-named-other-skill, not about ambiguous proactive).

Good: `Proactively invoke when the user pastes a stack trace, error message, failed CI output, alert, or describes unexpected behavior — even when they did not ask for "debugging" explicitly. Run before any fix is proposed.`

Bad: `Proactively invoke when the user shares a draft doc / spec / plan and asks for opinion or review.`
(Too broad — competes with every review-type skill on the same phrasing.)

### Section 4 — Skip when

- Covers situations where another skill clearly owns the ask, with `→ skill-name` pointers.
- Examples use real user phrasings, not abstract criteria.
- This is a divert, not a trigger. The phrases here should NOT appear in the Use-when list — those are mutually exclusive jobs.
- Use this to resolve known collisions with sibling skills.

Good: `Skip when the ask is already scoped to one stack (e.g. "fix this React render bug" → web-react-dev; "add a GORM index" → go-microservice-dev; "调下这个按钮间距" → product-ui-ux-design), or when the user is reporting a defect / failure / regression → defect-diagnosis owns reproduction and root cause first.`

## Precedence against session-injected process skills

A routing / workflow skill competes not only with sibling skills but also with process-discipline skills that some hosts INJECT at session start with very forceful language (e.g. a brainstorming skill whose description says "MUST use before creating features / adding functionality"). At initial routing time the router primarily sees skill names, descriptions, and host/session rules — the workflow body has not loaded yet, so an "Entry precedence" paragraph in the body does NOT win the routing decision. If your routing skill should own the entry point for a request class that an injected process skill also claims, the description must:

- Carry the high-frequency delivery utterances in the languages users actually type for this skill (include CN + EN only when both are real high-frequency forms), phrased the way they phrase them ("加个功能", "实现/接入某能力", "add a feature"). Each phrase must still pass the 80% precision threshold (above) — anchor a broad delivery phrase to the owned request class rather than dropping it in bare. An injected skill that literally matches "adding functionality" otherwise wins on the unanchored generic phrase.
- State scoped entry ownership for this request class, and describe the process skill as an internal step ONLY when that is actually true under the host's rules — do not teach a blanket priority claim over an injected skill the host may still require. Scope it ("for feature/requirement delivery") so it does not over-claim against pure process-only asks (e.g. retro → skill-extraction-workflow).

For teammates using the shared skill on description-based routing hosts, this is a zero-config fix: it ships in the description and avoids per-project memory or CLAUDE.md overrides. Validate it like any routing-surface change (dual-track challenge below).

## Trigger phrase quality: the 80% precision threshold

A quoted trigger phrase should belong to its skill in at least 80% of real-use contexts. If a phrase would commonly mean something else, it must be DROPPED or ANCHORED.

**Activation is closer to keyword match than semantic match** — two independent public sandbox measurements (2025-2026; sources and locators in the maintainer round evidence and specs ledger) found prompts containing a skill's name or a distinctive description token activate near-100%, while conceptual paraphrases of the same need activate near-0%; one team additionally measured routing accuracy degrading as the installed-skill count approached ~20 similar skills, recovering when consolidated to ~12. Both are host/model/catalog-conditional — treat as directional and reproduce against your own catalog before relying on the numbers. Two consequences for authoring: (a) the description must contain the distinctive tokens users actually type (measure real utterances, don't invent vocabulary — the discovery-vocabulary rule); (b) when routing degrades across the catalog, merging/pruning similar skills beats adding more trigger words to each.

### Drop (too generic, no rescue possible)

- `"改下样式"` — almost always means "change CSS now", which is implementation, not design ownership. Drop.
- `"怎么验证"` — covers release verification / smoke checks / deploy status / test planning — too broad. Drop.
- `"梳理一下"` — could be requirements, architecture, code, or doc — too broad. Drop.
- `"重写下"` — in code-review context, this means rewrite the code, not the doc. Drop.
- `"感觉怎么样"` — open evaluative question for any artifact. Drop.
- `"批量处理这批任务"` / `"parallelize this"` — can mean shell batching, code concurrency, data-pipeline parallelism — not necessarily agent dispatch. Drop.
- `"bug report"` — collides directly with bug-diagnosis territory; do not put in product-workflow proactive. Drop or move to Skip-when as a route pointer.

### Anchor (add disambiguating context)

When the bare phrase is too generic but a slightly longer version is clearly in-scope:

- `"重写下"` → `"重写下这个文档"` (anchored to docs)
- `"错误提示怎么写"` → `"用户看到的错误提示怎么写"` (anchored to user-facing surface, not API/CLI/log)
- `"怎么验证"` → `"测试层面怎么验证"` (anchored to test-layer planning)

The anchor must shift the surface meaning, not just add a noun.

### Keep (already specific enough)

Phrases that are tightly bound to one skill's territory:

- `"这个 bug 怎么修"`, `"为什么挂了"`, `"昨天还好好的"` — clearly defect-diagnosis.
- `"复盘"`, `"沉淀经验"`, `"总结经验教训"` — clearly skill-extraction-workflow.
- `"这个页面怎么设计"`, `"设计走查"`, `"设计验收"` — clearly product-ui-ux-design.
- `"立项"`, `"新项目怎么搞"`, `"让我们做一个 X"` — clearly product-rd-workflow.

## Length discipline: 800-char cap

The repo validator enforces an 800-character maximum on `description` (parsed as YAML): `check-ccl-skills.sh` fails with `description_too_long_for_opencode` above 800 chars and warns with `description_long_for_opencode` above 600, because longer descriptions dilute the trigger signal and can be truncated in host skill listings. If either threshold changes, update this section in the same diff — this file is the pre-edit reading for description authors and must not drift from the executor again. Practical tips when you exceed:

- Move route-pointers from the Proactively-invoke clause INTO Skip-when. Skip-when's job is to list "go elsewhere" targets, so route pointers fit naturally there and save proactive-clause room.
- Drop redundant proactive triggers (e.g. "right before a doc lands in a shared workspace" was vague and removable in `tighten-doc`).
- Drop weak quoted phrases first, not strong ones. Use the 80% threshold to decide which are weak.
- DO NOT shorten the capability one-liner — that's the routing anchor. Trim the lists instead.

## Don'ts

- Don't stuff implementation skill names in the description. They belong in the body. The description must compete with sibling skills on keyword density.
- Don't list every possible synonym. Pick the realistic ones; over-listing dilutes precision.
- Don't write the Proactively-invoke clause as "...and asks for opinion or review" — that hijacks every review-type sibling.
- Don't use abstract capability words like "comprehensive", "robust", "nuanced" — they don't help routing models match against utterances.
- Don't make the description claim something the skill body contradicts. Cross-check: if description says "X is in scope", the body must not say "for X, route to Y".
- Don't put advisory-only language in Skip-when (e.g. "consider whether..."). Skip-when must name concrete routing targets.
- Don't add new sanitized labels (angle-bracket capability tokens like `<some-capability>`) without registering them in the maintainer's private alias YAML first. See R0 in the parent skill.

## Validation checklist

Before committing a description rewrite:

- [ ] YAML parses with `YAML.safe_load(frontmatter_raw, aliases: false)`. If you use `|` block scalar (recommended for multi-line), validators must rescue `Psych::Exception` (covers `SyntaxError` AND `BadAlias`), not only `Psych::SyntaxError`.
- [ ] `desc.length <= 800` chars after YAML parse.
- [ ] All four sections present in order: capability / Use-when / Proactively-invoke / Skip-when. This applies to routing/workflow/cross-cutting skills; stack-specific implementation skills may keep the shorter capability-plus-quoted-triggers form (see "When this reference applies").
- [ ] Every quoted Use-when phrase passes the 80% precision threshold or is anchored.
- [ ] Proactively-invoke clause has a "do not invoke when ..." negative or a "Skip when ..." reverse-trigger covering the most likely over-fire.
- [ ] Skip-when names concrete `→ skill-name` targets, not abstract criteria.
- [ ] No business nouns, project paths, repo names, or source-team identifiers leaked.
- [ ] Description doesn't contradict the skill body — grep body for the capability words in the description; any "this skill does not own X" lines in body must match Skip-when in description.
- [ ] No new angle-bracket sanitized labels (`<...>`) appear in the description that are not registered in the maintainer's private alias YAML (see R0).
- [ ] If this is a routing/workflow skill, descriptions cover at least 2–3 sibling collision cases in Skip-when (real collisions, observed or likely).
- [ ] If there is an observed or likely routing collision with a named injected process-skill class (e.g. an injected brainstorming/scope-shaping skill) over the same request class, the description carries native-language delivery utterances (80%-precise or anchored) AND a scoped entry-ownership clause (see "Precedence against session-injected process skills"). Do not add this for merely theoretical overlap.
- [ ] Sanity check: read the description as a future AI router would. Would it pick this skill for the intended utterances and reject for the unintended ones? If unclear, the description is too vague.

## Iterative challenge discipline

A description rewrite is a routing-surface change, not a wording-only edit. The wording-only exception in the dual-track-review-gate (`references/dual-track-review-gate.md`) does NOT cover description rewrites. Run an adversarial challenge against the new description that explicitly asks:

- Do any quoted phrases collide with sibling skills?
- Does the Proactively-invoke clause over-fire on common situations?
- Does the description claim anything the body contradicts?
- Are there utterances in the skill's intended territory that none of the triggers would catch?

Re-run the challenge after each fix-up. Multiple rounds are normal: in practice 2–3 iterations land a stable description.

## Iteration after deployment

Even a carefully written description will miss real-user phrasings. Plan to collect actual miss / over-trigger reports for 1–2 weeks after landing, then increment the trigger list and Skip-when based on data. Do not pre-emptively stuff in every imaginable phrase — that fails the 80% threshold and creates new collisions.
