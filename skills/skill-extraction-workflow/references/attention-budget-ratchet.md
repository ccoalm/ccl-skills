# Attention-budget ratchet — design invariants for size/budget gates

An attention-budget gate limits how much prose an agent must hold to use a surface: the entrypoint body-word/byte gate, the every-session-injection byte gate, the `description` 800-char cap, and the reference-file line gate (all enforced by `scripts/check-size-budget.sh` or the canonical validator). This file owns the design invariants those gates share and the write-side norms for reference files. Companions: `rule-consolidation.md` owns the prose doctrine (merge-into-canonical, why rule sets must not grow monotonically); `skill-listing-budget.md` owns the host's listing-budget mechanism; `description-authoring.md` owns the description surface.

## The five ratchet invariants

Any NEW budget/size gate, and any modification to an existing one, is checked against all five before landing (this is the budget-gate instantiation of the design-time operability check in `dual-track-review-gate.md` — run that check's four legs too). A gate missing one of these fails in a predictable way, named per item:

1. **Stable proxy estimator** — the metric is deterministic and environment-independent: Unicode letter/number word runs with Han counted per ideograph, raw byte size, or physical line count. Never a model/tokenizer-dependent estimate: two environments disagreeing on the measure turns the gate into noise, and a changed estimator silently invalidates every recorded allowance. Deterministic also means encoding-normalized before measuring — a line count taken over raw bytes reads a CR-delimited file as one line, so line endings are folded to LF first.
2. **Anti-false-green sentinel** — a run that could not evaluate says so: base-unresolvable prints an `*_unevaluated` token (never the ok token), probe failures fail closed as partials, and on any block the last token is the failure marker. The ok token must be unearnable by losing the base; a consumer grepping for ok must never read an un-run gate as a pass.
3. **Zero tolerance for new debt** — a NEW surface over budget blocks outright. There is no exempt marker, no waiver flag, and no way for a candidate to nominate its own baseline; structural exclusions live in the gate, owned by the gate.
4. **Legacy may only shrink** — an existing over-budget surface is frozen at its base measure: level or shrinking lands, any growth blocks. Rename credit is path-paired and non-growing (move plus growth blocks as growth). This is what makes a uniform cap deployable over a corpus that already exceeds it, without a rewrite round and without rewarding a rush to pre-shrink.
5. **A missing baseline is never a pass** — the comparison base comes from revision history (`CCL_SKILL_BASE_REF`, upstream, or merge-base), so there is no stored manifest to go stale; when no base resolves, the verdict is unevaluated (invariant 2), and reddening that state is the caller's pipeline decision (CI always exports the base ref).

Two cross-cutting corollaries:

- Average headroom must never fund a single over-budget surface: the ratchet judges each file alone, and corpus-level counters stay visibility-only.
- Debt counters and advisory bands are never a clean-landing waiver nor authorization to keep growing a surface; only the delta verdict blocks.

## Reference-file write-side norms

The read side already defends against oversized files (chunked reads under ~200 lines, references one level deep). These norms are the write side, enforced as a delta ratchet over `skills/*/references/**/*.md`:

- A NEW reference file over 500 physical lines must not land — split it by subtopic before landing (the gate blocks new-or-crossing files; 500 exactly passes).
- An existing over-limit reference is frozen per invariant 4: shrink or stay level; growth blocks. Additions to a frozen reference are funded by consolidating existing text in the same file.
- Append-only ledgers are structurally excluded: `references/source-register.md` grows by contract (append-only, supersede-by-pointer, rows never edited), so a line cap would block the ledger discipline itself; the gate skips it and prints a visibility token when it is over the figure. Residual risk, accepted under the same trusted-contributor model as the entrypoint gate: a prose file named `source-register.md` would dodge the cap — review owns that shape.
- A new reference over 100 lines must be structured with `##` sections so chunked reads and greps can navigate it; a heading-less long file draws an advisory token (never a block). A table-of-contents list is optional — section structure is the invariant, not a TOC block.
- Authoring anti-patterns (verified against the official skill-authoring checklist, see verdicts below): time-sensitive facts outside an explicit old-patterns section; inconsistent terminology for one concept; abstract examples where a concrete input/output pair fits; Windows-style paths; unexplained constants; scripts that defer error handling to the model instead of solving it.

## Official-clause verdicts (provenance)

Registered claims were re-verified against the primary source (Anthropic "Skill authoring best practices", docs.claude.com, read 2026-08-31) before landing; per-clause disposition:

- "Keep SKILL.md body under 500 lines" — present verbatim, but it scopes to SKILL.md, not references. Already covered more strictly here by the 5000-body-word delta ratchet. The 500-LINE reference cap above is a repo-internal norm motivated by the read-side chunking evidence, and is labeled as such — never cite it as an official requirement.
- Table-of-contents mandate for long references — NOT PRESENT in the current official text. The official remedy for `head -100` partial reads is keeping references one level deep (already a Step 6 validation rule). The `##`-section advisory above rests on repo-internal evidence only.
- "Tested with Haiku, Sonnet, and Opus" — present, conditional on the models you plan to ship to. This repo's skills inherit the session model and the eval layer exercises real sessions, so no multi-model matrix is mechanized; the clause fires only if the repo starts shipping model-pinned skills.
- Checklist anti-patterns (time-sensitive info, terminology, concrete examples, forward-slash paths, voodoo constants, scripts-solve-not-defer) — present; landed above as authoring norms. The recurring-anti-patterns grep panel is NOT their landing surface: its admission rule requires a class observed in 2+ skills of this repo.
