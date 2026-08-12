# Online Skill Review

Use this when borrowing methods from public skill repositories, registries, articles, or reports.

## What To Borrow

- Loading and structure methods: trigger-focused frontmatter, progressive disclosure, direct references, minimal root files.
- Validation methods: pressure scenarios, independent review, YAML/schema validation, reference-link checks, trigger-boundary checks.
- Quality methods: concise SKILL.md, lazy-loaded references, deterministic scripts, clear owner/routing boundaries, tiered validation profiles, and doc-contract tests that assert required trigger wording and forbidden leakage.
- Safety methods: inspect before installing, avoid untrusted executable scripts, check for prompt injection, secrets, unexpected root files, and repo-context mismatch.

## What Not To Borrow

- Marketplace claims, install-count rankings, star counts, or marketing copy as quality evidence.
- Tool-specific commands when a portable principle is enough.
- Large copied reference dumps, raw benchmark logs, lockfiles, build artifacts, or root-level clutter.
- Hidden business assumptions, credentials, personal paths, or source-specific role names.
- Persona simulation, voice mimicry, personal-data collection, or identity reconstruction when the target skill is a workflow, design, product, engineering, or review skill.
- Mandatory generated manifests, multi-artifact bundles, or auto-install defaults from generator-style repos unless the local skill is also generator-owned and the user explicitly wants that behavior.

## Review Checklist

- Does the skill description say when to use it, not merely what it does?
- Does the skill entrypoint stay concise while references hold detailed variants?
- Are responsibilities disjoint from sibling skills?
- Are scripts optional, focused, and safe to inspect?
- Would OpenCode, Codex, and Claude Code discover and use the skill from name/description?
- Is the source reputable enough, or should the idea be treated as inspiration only?
- Does the source distinguish real inspected evidence from marketing claims, search results, placeholder links, or fabricated examples?

## Public-Method Triage (Coverage-First + Bounded Change)

Use this when the user asks to "extract / check / borrow industry best practices for X" — a different shape from local-source extraction. The recurring failure is to absorb every named idea found online and bloat the target skill into a literature catalog.

- **Coverage-first grep before reading**: build a candidate-term list for the target domain (frameworks, methodologies, vendors, named patterns) and grep across the target skill + its references. For each candidate, classify as `new gap`, `hidden coverage` (already covered under different wording), `wrong owner` (route to another skill), or `discard` (not in scope). Do not read public sources deeply on hits classified `hidden coverage` / `wrong owner`.
- **Five-bucket triage of remaining candidates**: `mature mainstream` (industry-default, executable, add if missing) / `niche-but-recommendable` (real value in a narrow context, add with adoption condition) / `overhyped` (cite-on-blog ≠ change-execution-judgment, do not add) / `wrong-skill` (real but owned elsewhere, route) / `hidden coverage` (already in target under different wording, do not add). Land only `mature` and qualified `niche` buckets.
- **Adversarial framing for the triage consult**: when consulting a second model for the triage, explicitly ask it to challenge what is hype vs what is industry-standard the target skill is missing — symmetric framing produces back-patting; adversarial framing produces sharper buckets.
- **Diff budget by extraction shape**: a literature-triage update normally lands ≤10–15 executable lines across existing references; a target skill already classified as thick (entrypoint ≥150 lines, refs ≥10) tightens to ≤10 lines and routes overflow to a `prune` task instead of new content. **Track the prune task durably, not in commit-body prose**: record it as a `pending` row in the current commit's target-output map AND append a one-line entry to the per-host scratch backlog (`~/.<host>/skills/.extraction-work/pending-prunes.md` or equivalent) naming the target file, the structural finding (e.g. "SKILL.md entrypoint exceeds its own thinness rule"), and the proposing reviewer. Findings buried in commit-message paragraphs disappear by the next session.
- **Zero new files unless trigger/owner/workflow differs**: per the existing core rule, fold into the smallest existing reference; resist the "new ref per topic" instinct that turns each public-method scan into a parallel knowledge base.
- **Fact-precision adversarial round on landed text**: industry literature carries version numbers, API names, enforcement strength, and dated deprecations — the dual-track adversarial review for a literature-triage commit MUST verify these explicitly (per-platform version cutoffs, exact API surface, "MUST vs SHOULD" enforcement, regulatory effective dates) before convergence; this is a higher bar than internal-evidence extractions, where the source artifact carries the facts. **Primary-source verification is agent-side**: "verify" means the agent runs `WebFetch` / `WebSearch` (or equivalent direct retrieval tool) on the official docs / standards page / API reference URL and reads the actual text — NOT just trusting a consultant model's (codex / external review LLM) URL citation. Consultant-LLM URL citations are second-tier evidence: they may be hallucinated, stale, or paraphrased inaccurately. For load-bearing facts (version cutoffs, current-vs-deprecated status, exact API behavior, regulatory effective dates, MUST/SHOULD enforcement strength, panel / API name spellings), the agent MUST hit the primary source directly during the fact-precision round, even when the consult round provided URLs. Recording "codex cited X" without independent fetch is insufficient — per the attribution-verification rule's source-quality bar, two independent sources are required, and codex + (codex's cited URL unverified) is only ONE source.
- **Skill description / references / scripts / validator output are public API**: changes to trigger semantics, sibling routing, named rules, or validator output break callers in the same way a public API change does — record breaking changes explicitly and verify no sibling skill silently depends on the prior surface.

## Source Handling

Record links in analysis or commit notes when public sources influenced a change. Do not paste long external text into skills. Rephrase into local rules and keep the final skill independent of the source site.

Never invent URLs, quotes, install results, test output, or source coverage just to make a borrowed method look validated. Keep the honest gap visible.
