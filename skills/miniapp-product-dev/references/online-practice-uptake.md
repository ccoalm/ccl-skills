# Online Practice Uptake

Use this reference when incorporating publicly available best practices into mini-program work — Taro official docs, WeChat/Alipay/Douyin/Baidu developer blogs, top-tier mini-programs observed as a user, OSS UI-kit reference implementations, and conference talks / engineering blogs from large-scale teams.

The aim is to **steal good ideas honestly**: absorb the pattern, do not absorb claims you cannot verify. Online practice has the same maturity gradient as in-codebase practice; not every published pattern deserves to land in this skill.

## Source classes and what they ground

| Source class | What it can ground | What it cannot ground |
|---|---|---|
| Host-platform official docs (WeChat / Alipay / Douyin / Baidu) | API contracts, config shapes, review policy at publication date, capability availability, version constraints | Whether the pattern is appropriate for your product; whether the doc is current (always re-check date and version) |
| Framework official docs (Taro, uni-app, Remax) | Framework facts (lifecycle, build, target resolution, syntax), canonical examples | Whether the canonical example is the best architecture for a specific product; whether the example is current |
| Framework GitHub `examples/` directory + project templates | Default architectural recipes the framework's authors consider idiomatic | Whether the example reflects production-grade concerns (auth epoch, payment finality, observability) |
| Canonical UI-kit source (taroify, NutUI-Taro, tdesign-miniprogram, uni-app uView) | Component-level mechanics: design-token wiring, accessibility defaults, interaction primitives, gesture/animation patterns | Whole-app architecture; cross-page state ownership; backend contract decisions |
| Top-tier mini-program portfolios observed as a user (large-scale finance / e-commerce / education / utility apps) | Pattern / idiom library: how a screen is laid out, what states are shown, what copy is used, what interaction model is chosen | Internal architecture; backend contract; A/B test results; business constraints that drove the visible UX; quality of the underlying code |
| Engineering blogs / conference talks from large-scale teams | Reasoning about tradeoffs; war-story anti-patterns; capacity numbers | Direct applicability without verifying scale / stack / constraint fit |
| OSS demo projects, tutorial blogs, screencasts | Quick orientation; syntax examples | Production-grade patterns; security; finality; observability |
| Weak / abandoned online sources (stale demos, outdated framework versions, low-engagement repos) | Rejection signals only (what NOT to copy) | Positive guidance |

## Uptake discipline

Before landing a pattern from online practice as a rule in this skill:

1. **Classify the source** using the table above. Record the class explicitly when proposing the rule.
2. **Verify the freshness**: what's the publication date? What framework / host version was current then? Has anything material changed (Taro 3 → 4, WeChat capability deprecations, payment policy updates)?
3. **Separate observation from claim**: a top-tier mini-program *showing* a pattern is evidence the pattern exists in the wild, not evidence the pattern is correct. The team may have made the same mistake at scale. Frame as "we observe X; testing whether it generalizes" — not "industry does X, therefore X is right".
4. **Hunt for the failure mode**: every published pattern has a context. What constraint produced it? What does it cost? When does it break? If you cannot describe the cost, you don't understand the pattern well enough to extract it as a rule.
5. **Cross-check at least two independent sources** before landing a rule from observation alone. A single blog / single mini-program is not industry consensus.
6. **Run it through the skill's own gates**: does the proposed rule pass the dual-track review + adversarial challenge in this skill's extraction workflow? A pattern that survives one popular blog but fails the production-safety challenge does not belong here.
7. **Provenance, not claim**: when the rule lands, the **source class + evidence label** (`pattern-observation` / `industry-canonical-with-cross-check`) goes into the shared source-evidence-map row. The **specific URLs, dated screenshots, observed app names, and re-extraction logs** live in the maintainer's private archive (see source-evidence-map.md → "Where The Specific Provenance Lives"), not in the shared skill tree. The rule itself in SKILL.md or reference files stays source-neutral.

## Anti-patterns when borrowing from online practice

- **"Big-name app does X, so X is right."** Big-name apps ship bad UX too. Observed pattern is evidence the pattern exists, not that it works.
- **Copying without context.** A payment flow from a top-tier e-commerce app may rely on backend infrastructure your product does not have. Lifting the UI without the supporting contract creates a half-broken pattern.
- **Stacking idioms from incompatible sources.** Mixing a layout idiom from one mini-program with copy tone from another and a navigation pattern from a third produces a Frankenstein UX that feels wrong even if each piece is individually fine.
- **Treating a tutorial as production guidance.** Tutorials optimize for clarity / shortness. Production code optimizes for failure modes. The two diverge.
- **Quoting a conference talk number as if your team has the same constraints.** A pattern that works at a 100M-DAU scale may not be optimal at 10K-DAU; the inverse is also true.
- **Stale-doc adoption.** Mini-program platform policy changes faster than community blogs. The blog from 18 months ago that solved your problem may now be the reason your release is rejected.

## What to take from online sources, what to leave

| Take | Leave |
|---|---|
| Pattern observation: how a screen handles long content / empty / error / weak network | Specific copy, brand color, brand name |
| Interaction idiom: pull-to-refresh placement, swipe gestures, sticky headers | Pixel-exact layout |
| State enumeration: what states a screen models | The team's chosen visual treatment of those states |
| Anti-patterns the source identifies and avoids | The source's praise of what worked (the team may have moved on) |
| Framework-canonical syntax and architecture from official examples | Whole-app architecture from any single example app |
| Capability contract from host-platform official docs (with date + URL recorded) | Cross-reading the docs from memory |

## Integration with this skill

- New rule candidates from online practice flow through the same dual-track review + adversarial challenge as in-codebase observations (see `skill-extraction-workflow/references/dual-track-review-gate.md`).
- The rule's source provenance is recorded in `source-evidence-map.md` with an explicit evidence label; the rule's wording in SKILL.md / references is source-neutral and capability-named.
- A rule lifted from a single online source without cross-check is recorded as **hypothesis** in the extraction ledger, not as observed evidence. It stays a hypothesis until a real feature delivery cycle or a second independent source confirms it.
