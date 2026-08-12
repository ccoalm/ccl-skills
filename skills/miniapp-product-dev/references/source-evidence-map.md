# Miniapp Source Evidence Map

Use this reference when auditing or re-extracting mini-program guidance. The rules below describe *how* to classify mini-program sources by maturity and trust; specific local repository paths, branches, project provenance, and dated cross-check logs live in the private provenance archive outside this skill tree.

Users without code access can still apply the distilled patterns in this file. Do not require access to specific paths unless the task explicitly asks to audit, update, or re-extract implementation evidence.

## Current Maturity Baseline

The mini-program skill's current rule set is **vendor-spec + framework-canonical**, not `mature confirmed`. It is grounded in:

- Host-platform official guidelines (WeChat, Alipay, Douyin/TikTok, Baidu developer documentation and review policy).
- Taro official documentation and reference examples.
- Canonical Taro-ecosystem UI component libraries (taroify, NutUI-Taro, tdesign-miniprogram React mapping).
- Cross-stack design rules already extracted in `product-ui-ux-design/references/multi-stack-strategy.md` and `multi-project-token-consistency.md`.

It is not yet confirmed against a production-quality mini-program portfolio observed end-to-end. Upgrade to `mature confirmed` requires at least one real feature delivery cycle passing without correction, and at least one real review/release passing platform audit.

## Source Coverage

For each candidate mini-program source in scope, classify before extracting rules. The shape below is the classification frame; specific entries live in the private archive.

| Dimension | Typical source signature | Useful extraction | Decision |
| --- | --- | --- | --- |
| Host-platform official spec | WeChat / Alipay / Douyin / Baidu developer documentation, review policy pages, capability reference | Authoritative for config files, capability semantics, review rules, store policy, version constraints | Keep as platform-level confirmed baseline |
| Taro framework canonical | Taro official docs (taro-docs), Taro GitHub `examples/` directory, Taro project templates, blessed Taro CLI defaults | Confirmed for framework facts: `app.config.ts` shape, lifecycle hooks (`useReady`, `useLoad`, `useDidShow`, `useDidHide`), `taro build --type` multi-target invocation, `process.env.TARO_ENV` value set, platform-specific file suffix resolution. The adapter-confinement rules (TARO_ENV only in adapter modules, all `Taro.*` API access through a repo wrapper) are **skill architecture guardrails for maintainability**, not Taro-canonical requirements — Taro itself permits direct usage. | Keep framework facts as canonical baseline; mark adapter guardrails as architecture preference |
| Taro ecosystem UI component library | taroify (Vant for Taro), NutUI-Taro (京东), tdesign-miniprogram with React adapter, AntMobile-style libs ported to Taro | Confirmed at component-level only: component contract shape, design-token wiring, accessibility defaults, common interaction patterns. Not whole-app architecture | Keep component-level mechanics; do not extract whole-app structure from a UI-kit repo |
| Multi-platform framework reference (non-Taro) | uni-app, Remax, kbone, mpvue official docs | Useful only for substitution mapping when reading a non-Taro source; do not absorb as primary baseline unless team migrates | Reference only; not primary |
| Native mini-program reference | Native WeChat / Alipay / Douyin / Baidu sample apps and tutorial code | Useful for host capability semantics and review-policy edge cases; native lifecycle and template syntax do not map directly to Taro JSX | Keep host-platform mechanics; discard native-only syntax patterns |
| Team-owned mini-program portfolio (quality-unverified) | The team's own existing mini-program code, if any. **Default status when a Taro / native mini-program codebase exists in the team's repo set but has not been audited end-to-end against this skill's rules**: treat as `quality-unverified` regardless of whether it is in production. Production use is evidence of distribution, not of quality. | Quality not yet confirmed; cannot be used to extract positive rules. Two legitimate uses: (a) **anti-pattern signal source** — when the same defect recurs across **2+ independent occurrences** (two different code locations, two production incidents, two source classes — not two re-reads of the same evidence), land a guardrail; (b) **pilot candidate for upgrading to `confirmed`** — run one real feature delivery cycle through this skill end-to-end, retrospect via `skill-extraction-workflow`, and land corrections before claiming any rule confirmed against this portfolio | Do not extract positive rules; record anti-patterns explicitly. **Forward work uses this skill from the start**; learnings flow back via `skill-extraction-workflow`, not by silently mining the old code. |
| Online product UX observation | Top-tier finance, tool, education, transactional mini-programs observed as a user (screenshots, flow recordings) | Pattern/idiom library only; you cannot see the internal decisions, A/B data, or constraints that produced the observed UX | Do not extract as positive rule; use as idiom or anti-pattern candidate that still needs internal confirmation |
| Weak / negative sources | Low-quality or abandoned mini-program code, demo-grade tutorials, deprecated framework versions | Useful for rejection rules only: do not absorb architecture, navigation idiom, or interaction style from weak sources | Discard as positive guidance |

## Source Classification Method

Before extracting rules from a candidate source:

1. Identify the source class from the table above.
2. For a code repository: confirm the framework signature from `package.json` (Taro version + UI-kit + state lib + build config). Stack guesses from directory name alone are not evidence.
3. For a Taro project: confirm which host targets it actually ships (`taro build --type` invocations in CI / scripts) versus which targets are declared but unverified. A multi-target declaration is not the same as multi-target proof.
4. For default-empty checked-out branches, inspect remote branches before declaring the source empty. The active code may live on a feat or release branch, not on `main`.
5. For the team-owned portfolio: confirm whether the code is in active production use, deprecating, or never shipped before deciding how to use it.

## Cross-Skill Routing

- React component structure, hooks, JSX, shared business logic in monorepo → `web-react-dev`.
- Visual / interaction / state design judgment, cross-end brand alignment → `product-ui-ux-design`.
- Native iOS / Android / Flutter / RN implementation → `app-cross-platform-dev`.
- Browser-only web implementation → `web-react-dev`.
- Test-layer planning (which tests at which layer for mini-program) → `testing-strategy`.
- Backend service / API contract / auth / payment server-side → relevant backend skill.

## Keep / Merge / Discard

Each entry carries an **evidence label** to prevent skill preferences from drifting into framework facts:

- **Keep — vendor authoritative**: host-platform official spec for config, capability semantics, and review policy. Cite the platform's current documentation URL + date when a release touches any rule from this source. (Evidence: `vendor-authoritative`)
- **Keep — framework canonical fact**: Taro-canonical facts — lifecycle hook signatures (`useReady`/`useLoad`/`useDidShow`/`useDidHide`), `taro build --type` target set, `process.env.TARO_ENV` value set, platform-specific file suffix resolution, `subPackages` declaration requirement, `tabBar.list` placement requirement. (Evidence: `framework-canonical`)
- **Keep — safety contract** (NOT waivable for maintainability reasons): late-callback fencing (per-page command controller with lifecycle epoch + late-result-ignore), full session-epoch tuple matching on every async callback before write, server-business-key idempotency on every finality mutation, pending-persist-before-action, blocking cold-start reconciliation with bounded timeout + state-uncertain recovery, webview-bridge per-message revalidation + server-signed capability grants, storage-manifest-driven purge on identity change, fail-closed flag evaluation. These are safety properties; the skill **enforces** them, not "prefers" them. (Evidence: `safety-contract`)
- **Keep — skill architecture preference** (waivable when the team has a documented alternative): wrapper placement choices — TARO_ENV branching only in adapters, all `Taro.*` API access through repo wrappers, eventCenter not as durable store. These help maintainability; Taro permits direct usage and a team may choose differently with rationale. (Evidence: `architecture-preference`)
- **Keep — component-library mechanics**: design-token wiring, accessibility defaults, interaction contracts at the component level from canonical Taro UI-kits. (Evidence: `library-canonical`)
- **Merge**: cross-stack token alignment, brand consistency, and multi-stack design rules already live in `product-ui-ux-design/references/multi-stack-strategy.md` and `multi-project-token-consistency.md`. Do not restate them here; cross-reference.
- **Merge**: React state ownership, effect discipline, and pure shared layer (DTOs, validators, mapping) already live in `web-react-dev`. Shared runtime adapters consumed by mini-program targets (request, auth, storage, finality, observability) are co-owned: web sets browser semantics; this skill approves the mini-program contract.
- **Route**: mobile / app / RN / native to `app-cross-platform-dev`; browser-only to `web-react-dev`; test-layer planning to `testing-strategy`.
- **Discard**: source business vocabulary, real app ids, tokens, reviewer accounts, internal product names, visual taste copied from weak sources, and component-library naming as a substitute for UX.

Coverage label: vendor-spec + framework-canonical baseline plus component-library-level mechanics, **not** node-by-node inventory of a confirmed production mini-program portfolio.

## Upgrade Path to `mature confirmed`

To move the baseline from `vendor-spec + framework-canonical` to `mature confirmed`:

1. Pilot at least one real feature delivery cycle (definition → design → implementation → test → review → release) using this skill end-to-end.
2. Record corrections, gaps, and unexpected platform behavior in the pilot's retrospective.
3. Confirm at least one host-platform review submission passes using only this skill's checklist.
4. Confirm cross-stack brand alignment (web / app / mini-program) does not require special-case handling beyond what `multi-stack-strategy.md` describes.
5. Run the extraction workflow's correction RCA on every defect surfaced in the pilot; land prevention in the smallest owning skill or reference before claiming confirmation.

Until then, treat positive rules as defaults to apply, anti-patterns as guardrails, and avoid wording that implies `confirmed` such as "always", "must", or "proven" beyond what the underlying vendor / framework documentation itself guarantees.

## Where The Specific Provenance Lives

Specific source repository paths, real branches, package.json signatures, app ids, real product names, and dated cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
