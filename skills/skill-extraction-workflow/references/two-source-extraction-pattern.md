# Two-Source Extraction Pattern (Design + Code)

Use when extracting frontend skill content from **both** a design source (Figma / Sketch / Penpot / equivalent) and a code source (web React monorepo / mobile app monorepo / native iOS-Android workspace). The two sources together describe what the product should look like AND how it is built; either one alone produces incomplete or contradictory skill content.

This is a sub-pattern of the main extraction workflow — charter / source register / batch loop / sanitize / dual-track / commit all still apply. This reference covers the **two-source-specific procedural discipline** layered on top. The concrete design judgments (file classification, deprecation markers, token validation, naming/versioning) live in `product-ui-ux-design/references/`; this file routes to them rather than duplicating them.

## When this pattern applies

- Figma project + React web monorepo for the same product → both feed `product-ui-ux-design` + `web-react-dev`.
- Figma project + Flutter / native iOS / Android workspace → both feed `product-ui-ux-design` + `app-cross-platform-dev`.
- Design tokens (typography / color / spacing / motion) need cross-validation against implementation tokens.
- Multi-package frontend monorepo with mixed targets (web app + admin console + design-system package + shared utils) — class-based subproject mapping is essential.

## When this pattern does NOT apply

- Code-only extraction (no design source available) → use the main workflow.
- Design-only extraction (no implementation yet) → use the main workflow + route findings to design skills.
- Backend service extraction → use the main workflow; sibling stacks via the sibling mini-map rule.

## Source pinning (snapshot before mining)

Before each batch loop iteration, pin both sources so mining and cross-validation operate on a fixed snapshot:

- Design source: file key + version (the explicit version id from the design tool's version history, not just `lastModified`) + selected page/frame node ids + token export timestamp (if a token bridge tool is in use).
- Code source: branch + commit SHA + lockfile hash (`package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` / `Podfile.lock` / `pubspec.lock` as applicable) + any generated-asset content hash.

If either snapshot changes during the batch (designer pushes a new version; branch rebases; tokens re-export; a code-mod sweep lands), the batch is invalidated. Either restart the batch on a fresh pinned snapshot or mark the affected cross-source rows `stale — re-mine` and exclude them from this commit. Do not land token, drift, or routing rules from mixed snapshots; they describe a state that never existed.

## Source register extends the standard row

This pattern **extends** the standard source-register row defined in `source-register.md` (`source_id | source_type | class | path/file_key | status | min_depth | actual_depth | extracted_mechanisms | discarded_business_details | target_skill | evidence_link`). The columns below are the additions and the conventions specific to two-source extraction; do not omit the required columns from the standard row when applying this pattern.

This pattern **specializes the standard singular `target_skill` field into plural `target_skills`** (see below). The shared register schema remains singular until a parent rewrite lands plural ownership across all extraction classes; treat the plural variant as a documented per-pattern specialization, not a contradiction.

| Column added or specialized | Convention |
| --- | --- |
| `source_type` | `design` or `code` |
| `class` | for `source_type=design`: `A1` (rules source — design system / tokens), `A2` (business module / page-layout source), `B` (deprecated / reference-only). For `source_type=code`: `web`, `native`, `pkg-shared`, `infra`, `legacy`, `excluded-support`. |
| `path / file_key` | design: design-file key placeholder; code: monorepo-relative path. Real keys/paths live only in the private alias map. |
| `target_skills` | **plural — list every affected skill.** A single source row often updates `product-ui-ux-design` + `web-react-dev` (or + `app-cross-platform-dev`) + `testing-strategy`; never collapse to one target when the mechanism touches design judgment + implementation + tests. Each owner gets its own target-output row downstream. |
| `pinned_snapshot` | the version/SHA captured by the pinning rule above |

Real source identifiers (design file keys, monorepo paths, contributor names) live in the project's private alias map per the Extraction lifecycle handoff rule in `SKILL.md`. The shared register carries only sanitized placeholders.

### Subproject classification for `source_type=code`

The five-class `web / native / pkg-shared / infra / legacy` scheme covers runtime sources of truth. Real monorepos also contain support packages that look like code but **cannot define positive skill rules**. Add a sixth class:

- `excluded-support` — candidate examples: Storybook / docs / examples / generated SDK output / fixtures and mocks / visual preview sandboxes / vendor mirrors / test-data builders. Inspectable for *context* only; never the runtime source. Findings drawn from an `excluded-support` package alone must be downgraded to working hypothesis or routed to the runtime source that the support package serves.

**Classification is by runtime participation, not by package type.** Before marking any package `excluded-support`, run the runtime-participation test:

- Is the package imported by production code (any path that reaches a release artifact)?
- Is it included in any runtime bundle (web bundle, app image, server container, lambda)?
- Does it define contract or wire-format semantics actually executed at runtime (request serialization, auth headers, error normalization, schema validation, capability checks)?
- Is its output published to a real consumer (real users, real services, real downstream pipelines)?

If **any** answer is yes, the runtime slice classifies as `web` / `native` / `pkg-shared` / `infra` — even if the package is generated, vendored, fixture-shaped, or "support"-named. A package may have a runtime slice AND a support slice; split it conceptually in the register (one runtime row + one support row) before mining. Mis-applying `excluded-support` to a runtime package will silently dodge real rule extraction.

## Where the design judgments live (route to these)

This file is the *procedure*. The *judgments* — which file is the source of truth, what deprecation markers mean, how tokens align across sources, how naming drift is resolved — live in dedicated references. Load them when you reach the corresponding step in the quickstart below.

| Two-source decision needed | Owning reference (load this) |
|---|---|
| Identifying which design file is the real source-of-truth; A1/A2/B file classification; team deprecation-marker discipline; business-module file should have zero file-local styles | `product-ui-ux-design/references/design-system-source-of-truth.md` |
| Code monorepo subproject classification + the `excluded-support` carve-out; per-class routing; retire/isolate/coexist for stack outliers | `product-ui-ux-design/references/multi-stack-strategy.md` |
| Token cross-source validation procedure (match / drift / missing / renamed) + per-class token table + audit YAML shape | `product-ui-ux-design/references/multi-project-token-consistency.md` |
| Design ↔ code naming drift; `FooV2` coexistence; date-stamp-as-page-name discipline; conflict precedence between discriminators | `product-ui-ux-design/references/design-impl-naming-and-versioning.md` |
| Visible state / runtime behavior / cross-owner acceptance (states families, navigation/return paths, disabled reasons, recovery controls, timing/feedback, accessibility, responsive variants) | `skill-extraction-workflow/references/uiux-routing-map.md` — load **first** before deciding whether a finding is design-judgment vs implementation vs testing |

Routing precedence: load the UI/UX routing map first; it tells you which owner(s) a cross-source decision belongs to. The four `product-ui-ux-design` references above own only the **design-judgment** slice; runtime behavior, implementation mechanics, and test strategy route to `web-react-dev` / `app-cross-platform-dev` / `testing-strategy` / `product-ui-ux-design` (acceptance) — each gets its own target-output row, not one collapsed owner.

Do not duplicate the content from these references in this file. If a rule shifts, it shifts in one place.

## Token cross-validation must record context

Tokens with the same name in design and code can legitimately disagree when they live in different contexts (brand vs product, light vs dark mode, tenant override, platform-specific). Before declaring drift, classify each token comparison by **context**:

- `global-brand` — colors/typography defined by the brand layer; design file is authoritative.
- `product-semantic` — product-level semantic tokens (e.g. `surface.default`, `text.muted`); design and code should match within a context.
- `platform` — platform-specific token (iOS vs Android vs web); differences expected, not drift.
- `theme-mode` — light/dark/high-contrast variant; value differs by mode, not by source.
- `tenant / runtime` — value injected at runtime per tenant; design carries placeholder, code carries injection point.
- `local-exception` — explicit override in a specific surface; documented divergence.

Only compare tokens **within the same context**. A value mismatch across contexts is a **mapping**, not drift. Validation must run for every token class touched by the batch (typography / color / spacing / radius / shadow / motion) or explicitly mark untouched classes `not in scope` with evidence — sampling one class and claiming cross-source consistency is a false pass.

**Non-drift context classifications require both-side evidence.** When labeling a comparison `mapping` (rather than `drift`), record:

- Design-side context evidence — the design-file frame, layer, theme variable, or token-export field that declares this context.
- Code-side context evidence — the code symbol, theme switcher, tenant config field, or build target that declares this context.
- Owner — the team or skill that owns the cross-context mapping.
- Lifecycle — `permanent` (intentional ongoing mapping) or `expires_when:<concrete trigger>` (temporary divergence pending reconciliation).

If any of the four is missing, the comparison is `unresolved drift`, not `mapping`. A stale code comment, a single-side TODO, or an undocumented runtime override is not evidence; it is the failure mode itself.

## Sanitization additions specific to two-source extraction

These extend the main `recurring-anti-patterns-checklist.md` and the R0 hard-gate audit; they do **not** replace either. Zero hits required across all categories before commit.

### Design-source-specific patterns

| Anti-pattern | Symptom | Fix |
|---|---|---|
| Design file key in shared skill content | `https://www.figma.com/file/<key>/...`, `https://www.figma.com/design/<key>/...`, `https://www.figma.com/proto/<key>/...`, `figma://file/<key>...` deep-links, bare 22-char alnum key, `?node-id=<id>` and `?fileVersion=<id>` query params | URL/link → "the design system file"; key, version id, and node id → private alias only |
| Design project / team name in skill text | `<product-name> Design System`, `<team-name>'s tokens` | "the platform's design-system project" |
| Real page / frame / business-noun names | "<product> <business-flow> detail page", "<product> <entity> management" | Generic role: "feature detail page", "entity-list page" |
| Real contributor names | `designed by <name>` in metadata, `Last edited by <name>` | Strip; provenance only |
| Real component instance names that leak business identity | a tenant-named picker, a bureau-named approval card | Generic role: "tenant-scoped picker", "approval card" |

### Code-monorepo-specific patterns

| Anti-pattern | Symptom | Fix |
|---|---|---|
| Real subproject path | `<monorepo>/<env>/<product>/<role>-web` | "the operator web package" (role) |
| Real package / workspace name | `@<org>/<product>-ui-kit`, pnpm workspace name `@<org>/<product>-*`, yarn workspace path | `<ui-kit-package>` / `<workspace-scope>` placeholder |
| Real import path examples | `import { Foo } from '@<org>/<pkg>'` | `import { Foo } from '<pkg-shared>'` |
| Internal API base URL | product API host, environment-scoped internal host | `<api-base-url>` placeholder |
| Build pipeline / CI workflow names | `<product>-ci`, `<product>-staging-deploy`, GitHub Actions workflow file names that contain product | "the project's CI pipeline" |
| Git provenance literals | real branch names, commit SHAs, remote URLs, tags in code excerpts or examples | strip; provenance only — examples use `<branch>` / `<sha>` |
| Mobile / desktop app identifiers | iOS bundle id `com.<org>.<product>`, Android applicationId, macOS bundle id, Expo slug | `<app-bundle-id>` placeholder |
| Env-var prefixes carrying brand | `<PRODUCT>_API_KEY`, `<PRODUCT>_FEATURE_FLAG_*` | `<APP>_*` placeholder |
| Storybook / dev-tool URLs | product Storybook host, real preview deploy URLs | "the project's Storybook" / "preview deployment" |

The specific grep commands and per-project allow-lists for these categories live in the private alias map per the parent skill's R0 rule. The shared file carries only the category list above.

## Quickstart adaptation for two-source

The main extraction quickstart (charter / register / batch / sanitize / review / commit) applies; substeps that change:

1. **Charter** — declare both sources in scope, name the source corpora at a class level (not by specific keys).
2. **Source register** — extended standard row above; pin both sources; classify every design file AND every monorepo subproject (including the `excluded-support` carve-out) before mining. For design-file classification load `product-ui-ux-design/references/design-system-source-of-truth.md`; for subproject classification load `product-ui-ux-design/references/multi-stack-strategy.md`.
3. **Batch plan** — batches are typically by feature surface, with design + code mined together per feature (NOT design in one batch, code in another — that loses cross-source validation).
4. **Per-batch loop** — runs the standard quickstart substeps; the two-source-specific insertions are:
   - **Snapshot check** before mining: confirm both sources still match their pinned snapshot; if not, restart the batch or mark rows stale.
   - **Source reading**: load both design and code evidence for the feature.
   - **Cross-source token validation**: a new substep that sits **after source reading and before `3b. Draft skill / reference`**. Load `product-ui-ux-design/references/multi-project-token-consistency.md` for the procedure; classify each comparison by `token_context` (above) before declaring match/drift/missing/renamed; record results in the evidence ledger.
   - **Drafting and `3e. Dual-track review`**: proceed per the standard quickstart.
5. **Naming/versioning resolution** — if the batch hits design ↔ code naming drift, `FooV2` coexistence, or contradictory current-discriminators, load `product-ui-ux-design/references/design-impl-naming-and-versioning.md`.
6. **Sanitization** — main R0 checklist + the two-source-specific anti-pattern tables above (extending, not replacing, R0).
7. **Dual-track review** — for design-judgment skills, the review pass MUST inspect the design evidence (not just the skill text); the challenge pass focuses on what could break under chaos (deprecated files mistaken for fresh, drift undetected, business nouns leaked, snapshot drift).
8. **Commit** — separate commits per evidence type when possible (design rules vs implementation rules vs cross-cutting), so reviewers can see which source drove each change.

## Failure modes specific to this pattern

- Mining deprecated design files as fresh evidence → stale rules ship to skill tree. (Mitigation: load `product-ui-ux-design/references/design-system-source-of-truth.md` for deprecation discipline.)
- Skipping monorepo subproject classification or the `excluded-support` carve-out → support packages leak example-only patterns into rules. (Mitigation: classify every package before mining; downgrade `excluded-support` evidence.)
- Skipping token cross-validation, or running it without `token_context` → design and code differences treated as drift when they are intentional mappings, or real drift hidden under context excuses. (Mitigation: classify context first, then compare.)
- Cross-validating moving snapshots → fake drift / fake match shipped as rules. (Mitigation: pinning rule above; restart batch on snapshot change.)
- Batching design in one session, code in another → cross-source validation never happens; per-feature batching prevents this.
- Treating design-file naming as ground truth → team-convention markers (bracket prefixes etc.) silently mean "deprecated"; easy to miss without explicit deprecation rule.
- Letting business page / component names leak into shared skill text → sanitization gap. (Mitigation: tables above + R0 hard-gate audit.)
- Collapsing a multi-owner mechanism into a single `target_skill` → design-judgment rule lands but implementation/test owners get nothing. (Mitigation: `target_skills` is plural; UI/UX routing map loaded first.)
- Two-source mismatch (design says X, code does Y) treated as a skill rule → coordination decision masquerading as design discipline. (Mitigation: resolve outside the skill; design + code owners decide; record only the *resolution shape* — never the specific case — in skills.)

## Verification

- Source register shows extended-row columns populated; both sources have pinned snapshots; every file/package has a class (including `excluded-support` where applicable) and a status; `target_skills` is a list, not a single value, whenever the mechanism touches multiple owners.
- Token cross-validation audit ran for every token class touched by the batch (or marked `not in scope` with evidence), with `token_context` recorded per comparison; audit results in the project's alias map per `product-ui-ux-design/references/multi-project-token-consistency.md`.
- Sanitization re-audit: 0 hits across the design-source and code-monorepo category tables above plus the main R0 categories (design-file keys/URLs/versions/node ids, Git provenance literals, workspace scopes, app bundle ids, env var prefixes, Storybook URLs, business page nouns, project/team names, contributor names).
- Routing check: every cross-source decision is present in the target-output map and routed to its actual owners — design judgment to `product-ui-ux-design`, implementation/runtime to `web-react-dev` / `app-cross-platform-dev`, state/acceptance to `uiux-routing-map.md`'s owners, test strategy to `testing-strategy`. A decision with no owner blocks landing until the owner is named.
- Skill content reviewable by both a designer (design evidence cited at the class level) and a frontend engineer (code evidence cited at the class level) without either party objecting to mis-routing.

## Worked example (link, not content)

A two-source extraction pass for a real project lives in the maintainer's private alias map at `~/.<host>/.private-aliases/<project>.yaml`. Concrete A1/A2/B file classifications, code subproject classifications (including `excluded-support`), deprecation markers, pinned snapshots, sanitization grep patterns, and token-audit rows live there. The shared skill tree carries only the methodology in this file and the design-judgment rules in the referenced files; no specific project provenance.
