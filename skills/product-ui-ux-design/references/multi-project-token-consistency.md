# Multi-Project Token Consistency

Load this reference when working on a product that has **multiple frontend subprojects on the same end stack sharing the same brand** — for example, several React desktop apps (workbench plus admin plus marketing site), or several React H5 apps (consumer H5 plus printer H5 plus account H5).

**Same framework family, different ends** (e.g. React desktop admin + React H5 consumer + React Native app, all sharing one brand): this is a *common middle case*. The subprojects share enough infrastructure (React, TypeScript, build tooling, generated API client, request layer) that a single shared theme module can serve them, but they cannot share UI-kit components because the kits differ by end (desktop kit vs mobile kit vs native kit). Load **both** this reference and `multi-stack-strategy.md`: this reference governs the shared theme-module mechanics; multi-stack-strategy governs the per-end UI-kit and surface differences. Apply both rather than picking one.

For products that mix unrelated end stacks (e.g. React + Vue 2 + native Android + native iOS + Taro mini-app), load `multi-stack-strategy.md` first; the same-framework optimisations in this file do not apply.

This reference defines how to keep tokens, themes, and UI-kit choices aligned across same-stack subprojects so the rendered product feels like one brand, not several.

## Scope Question 0

Before applying any rule below, confirm: **are these subprojects all parts of one branded product, or are they independent products under one corporate umbrella that happen to share infrastructure?** If the latter, the rules in this file do not apply — each independent product runs its own design discipline. Route to `product-rd-workflow` for the "one product or many" decision. Optional external strategy or ideation support may supplement this through local skill discovery; otherwise escalate the question to the human owner or record it as `unresolved` in the active extraction's notes, and do not apply the rules below to a portfolio whose scope is undecided. Only proceed with the rules below when the portfolio is confirmed to render as one brand.

## Triggers

- Auditing why two same-stack subprojects of the same product render with different primary colors / button styles / spacing.
- Adding a new same-stack subproject to an existing multi-app product.
- Reviewing a `ConfigProvider` / theme injection that customizes only one component while leaving the rest at library defaults.
- A same-stack subproject is about to introduce its own design system because "the shared one doesn't fit".

For cross-stack design coordination, route to `multi-stack-strategy.md` first.

## Rules

- **UI-kit stack uniqueness per end-platform**: within one product, all desktop subprojects use the same desktop UI-kit family; all mobile-H5 subprojects use the same mobile UI-kit family. A subproject choosing a different UI-kit family inside the same stack is treated as an outlier and must have an explicit retirement or isolation plan. The specific UI-kit family is a per-team decision recorded in the project's design-system file or architecture doc — it is not a recommendation from this skill. **Strong detection signal worth investigating**: a single subproject's `package.json` simultaneously depending on a desktop UI-kit (`antd` / `@mui/material` / `@mantine/core` / `@chakra-ui/react`) **and** a mobile UI-kit (`antd-mobile` / `@ionic/react` / `react-onsenui` / `vant`) is presumptively an off-stack outlier. The presumption can be cleared (without ignoring the rule) by a documented reason — a migration in progress with a known retirement plan, a deliberate adaptive UI-kit choice serving desktop+H5 from one package, a storybook / demo / lint / test dep that does not ship to runtime, or an unused dep awaiting removal. Without such a documented reason, the mixed dependency is the outlier and is owned by the subproject for fix or isolation. Per `multi-stack-strategy.md`, code-grep alone cannot distinguish accidental drift from a design-driven exception — the dependency signal triggers an audit, not an automatic verdict.
- **Theme must be shared, not copied**: all same-stack subprojects share one theme source — a published internal npm package, a monorepo workspace module, or an explicitly imported shared module. Each subproject copying its own `theme.ts` is anti-pattern; tokens will drift the moment one subproject ships a brand tweak.
- **Theme must be explicitly injected**: every subproject that depends on the brand theme injects it explicitly at the entry layer — `ConfigProvider theme={brandTheme}` at the root component or a framework-level config (`antd: { theme }` in UmiJS, `ThemeProvider` in styled-components, etc.). A subproject that ships with no theme injection silently inherits the UI-kit default and drifts away from the brand on day one.
- **Theme injection partial-customisation is leak**: a `ConfigProvider` that overrides only one component (e.g. `Tree.titleHeight: 32`) while leaving `colorPrimary` at default is worse than no injection — it signals "we have a theme" while shipping the default color. Either inject the full brand theme or remove the partial injection.
- **Empty framework-wrapper theme config = no theme**: meta-framework theme slots (`antd: { theme: ... }` in UmiJS / Next, `MaterialApp(theme: ThemeData(...))` in Flutter, mini-program platform theme fields, etc.) are evidence that the slot exists, not that it carries the brand. A wrapper with `antd: {}` / `theme: ThemeData()` / `theme: undefined` / theme key omitted is **functionally identical to no theme** and renders the UI-kit / platform default. Detection grep that matches on the slot name only (`grep "antd:"`) is a false-positive trap; the slot must be inspected and confirmed to reference the brand theme object. Apply the same standard whichever wrapper layer the stack uses.
- **Token names should map across the design-code boundary**: design tokens (e.g. `Colors/Base/Blue/400`) and code tokens (e.g. `colors.primary.main`) should resolve to the same value and ideally use the same naming scheme. Pure name renaming at the code side hides the design-source intent and makes refresh impossible to audit. Reuse the design-system's naming or document the bidirectional mapping.

## Source vs Export Distinction (Precondition for All Token Audits)

Before applying any audit below, classify the artifact under review. The same audit applied to a source and to a derivative export produces opposite verdicts.

- **Source artifact**: the live design-tool file with Variables panel access (URL + named collection), the canonical theme package in code source-of-truth, or a generator output the build pulls every build. Source lets the auditor inspect alias chains, mode bindings, group counts, and component-tier coverage directly.
- **Derivative export**: JSON / YAML / CSV / markdown produced by a plugin or one-shot export. Common shapes: built-in "Import and export variables" plugin, Tokens Studio export, Style Dictionary input JSON, community plugin exports, panel screenshots, sliced markdown spec. **Always lossy** relative to the source in at least one dimension.

### Known data-loss modes in derivative exports

Assume these by default when reading a derivative; only set aside on explicit, named evidence:

- Cross-collection alias links collapse to `$alias-unresolved` / empty string / literal alias name. The semantic binding **is present** in the source — only lost on export.
- Multi-mode setups (Light / Dark / brand variants) export per-mode files; cross-mode aliases break.
- Component-collection tokens often dropped entirely. A source can carry hundreds to thousands of component-level tokens; many plugins export only base / semantic tiers.
- Group / folder hierarchy flattened or renamed at export; semantic group names (Brand / Neutral / Component) merged or lost.
- `description` and `scope` metadata exported as empty strings even when the source has them.

### Required record before any audit verdict

```
artifact_class: source | derivative | unknown
source_link: <design-tool URL + collection / theme package path / generator config path>
derivative_provenance: <plugin name + export mode + collection scope + mode coverage + timestamp>
known_loss: <which of the data-loss modes above apply to this export shape>
```

- `artifact_class == derivative`: either (a) pull the source and re-audit against it, or (b) explicitly label the audit `derivative-only` and restrict to checks that survive export loss (token-name typos, value mismatch in non-aliased tokens). Do **not** issue Design-Source Health Check verdicts (below) against a derivative — four of the five failure classes can be reproduced by export tools, not by the source.
- `artifact_class == unknown`: block the audit. A token file whose origin is unknown is insufficient evidence for any maturity or alignment finding.

## Design-Source Health Check (Pre-Consumption Gate)

Before any downstream stack (web desktop, web H5, native app, mini-program) is told to **align with** a design-system token source, run this health check on the source itself. The cross-source validation procedure that follows assumes each source is internally consistent; if a source is internally broken, alignment work copies the brokenness into every downstream stack and the cross-source drift gets harder to detect, not easier.

The gate runs against the source artifact (Figma file, token JSON export, theme package, or whichever shape the team's source-of-truth ships). It is a precondition, not a one-off; re-run when the source has a material change.

### Failure classes

A source fails the gate if any of the following holds. Each class blocks downstream alignment until the source-of-truth owner fixes it.

1. **Third-party UI-kit mirror or vendor-derived source, undeclared.** The token set substantively reproduces a third-party UI-kit's palette / scale / control sizes (Ant Design v5, antd-mobile, Material, Polaris, Tailwind defaults, shadcn, others) — typically detected by sampling 5–10 named values and finding most or all match the third-party kit's published values. A vendor-derived theme that intentionally retains vendor neutrals / spacing / control sizes while overriding brand-level roles is **legitimate**, but only when the vendor basis and the local override boundary are **declared** in the source (metadata, file name, top-of-file note, README). Per `design-system-source-of-truth.md` rule on third-party mirrors, the gate blocks **undeclared substantive mirrors**, not vendor-derived themes that have stated their basis. An undeclared mirror lets downstream teams treat the third-party kit as the team's brand customisation, blocking later real brand work and obscuring which values are negotiable.
2. **Drift inside one source.** The same role (primary colour, neutral text, primary action) carries **two or more competing canonical values** in one file (e.g. one Figma variable plus one "global" override). Per the Token Cross-Source Validation Procedure below, drift across sources is a recorded finding; drift inside a single source is worse — it means the source itself cannot answer "what is the primary colour" without a side conversation. The block is scoped to the affected role plus any token class that consumes it, not the entire source.
3. **Unresolved / placeholder values in shipped semantic tier.** The source defines role names (`colorSuccess`, `colorWarning`, `colorError*`, `colorBgContainer`, `colorTextDisabled`, semantic / state / data-viz roles) but the values are placeholders (`$alias-unresolved`, `TBD`, raw alias strings, empty), AND the source is being handed to consumers as "ready". Per the existing rule that missing semantic tokens must fail audit (not silently fall back to brand primary), shipping a source with unresolved semantic tier means every downstream stack either inherits a literal `"$alias-unresolved"` string or invents a local value — both are drift. The block is scoped to the touched roles (a downstream release that consumes none of the broken roles is not blocked by this class alone).
4. **No source provenance metadata.** The source artifact carries no machine-checkable pointer back to its origin. "Origin" is the Figma file labeled name + node-id when a Figma source-of-truth exists; **for the green-field / pre-Figma case** described in `design-system-source-of-truth.md` (token role taxonomy injected as code-side starting point before a Figma DS exists), the equivalent is a stable provisional pointer such as `taxonomy module path + package version + commit hash + token-set version`. The gate requires the pointer in whichever form the team's source-of-truth currently takes; it does not require Figma when Figma is not yet the source.
5. **No versioned snapshot for the source artifact.** The source carries no revision marker, export hash, package version, Figma version label, or generated-artifact checksum that downstream consumers can pin against. Without a snapshot identifier, "the team aligned with the source on date X" is unverifiable; a later source change silently invalidates earlier alignment evidence. Block until the source declares a versioning convention (semver / commit hash / Figma version / build hash / sync-pipeline build number).

### Procedure

1. **Pick the artifact** the design-system owner currently calls "the source" (Figma file URL + variable collection, token JSON export, the published theme package, or whatever the team uses).
2. **Run the five checks** above. Each check produces `pass` / `fail` / `not applicable` (with reason). Failures name the specific tokens / variables involved.
3. **If any check fails, scope the block to the affected source artifact + the specific token classes / roles / surfaces the downstream release would consume.** A release that touches only roles the source can answer cleanly is not blocked by an unrelated unresolved-semantic-tier finding. The fix lives in the design-system source, not in the consumer. Open the finding with the source-of-truth owner (route to `product-ui-ux-design` if no named owner exists), specify the failure class + concrete tokens, and record the block in the active extraction's notes / private alias map. **Escape valve when the source-of-truth owner cannot or will not fix in the release window**: the named design owner (and a paired risk owner for any safety-/trust-sensitive surfaces) MAY approve a **time-boxed provisional consumption** — pinned source version + recorded defect + downstream release labeled "not fully aligned" + an expiry date by which the source must be fixed or the provisional approval lapses. Provisional consumption is logged as a finding, not erased; do not use it to skip the gate quietly.
4. **Re-run when the source changes materially**: new variable collection, new semantic tier, palette refresh, mirror-vs-custom realignment. Do not silently consume a previously-passing source after a structural change.

### Routing for the fix

- Third-party mirror / vendor-derived source → declare the vendor basis and the local override boundary explicitly (Figma file name, top-of-file note in JSON export, README in theme package).
- Drift inside one source → one canonical value chosen by the source-of-truth owner; the loser becomes a documented alias or is removed.
- Unresolved semantic tier → owner resolves the aliases or removes the role names until they are real. Half-shipped role names are worse than missing role names.
- Missing provenance → add the origin pointer in the form the team's source-of-truth takes (Figma labeled-name + node-id when Figma is the source; taxonomy module path + package version + commit hash + token-set version when the team is still in the green-field / pre-Figma stage from `design-system-source-of-truth.md`).
- Missing versioned snapshot → declare a versioning convention (semver / commit hash / Figma version / build hash / sync-pipeline build number) so downstream consumers can pin and prove what they aligned with.

This gate intentionally does not legislate **which** values the source should pick (that is the team's design decision); it legislates that the source can give a single, internally-consistent, traceable answer before downstream consumers spend time aligning with it.

## Migration-State Classification (Before Reporting Drift)

When values differ — design source vs code, design file vs design file, code path vs code path — classify the state before reporting drift. Differences are not findings by default; only `drift` is a finding.

| state | definition | audit verdict |
|---|---|---|
| `current` | source-of-truth and live production code render the same value; other claimants either agree or are subordinated to it | aligned, no finding |
| `target` | a different value lives in an explicitly-declared upgrade-plan artifact (separate file labeled as such, tracked work item, named migration branch); current production unchanged | planned change, open migration item — not drift |
| `in-flight` | some surfaces adopted the new value while others render the old, AND a visible migration signal exists (see below) | partial-rollout finding (list remaining surfaces) — not drift |
| `drift` | values differ AND zero migration signals present | drift finding |

### Migration signals required to leave drift

To classify a non-current difference as `target` or `in-flight`, the audit must point at **at least one** signal by direct reference, not by hypothesis:

- An upgrade-plan design artifact, recognizable by file-name pattern, page label, or dated migration plan inside the design tool.
- A code-side deprecation marker on the old value: comment, JSDoc tag, lint suppression, deprecation decorator, or equivalent.
- A parallel-runs switch — ConfigProvider variant, theme module flag, runtime config, feature flag — allowing surfaces to opt into either value.
- A tracked work item with explicit migration scope recorded in the project's private provenance archive.
- A live computed-style sample across surfaces showing partial-but-deliberate adoption (new modules render the new value, legacy modules render the old, no random scatter).

"Possibly an upgrade" is not a signal. Default to drift until proven otherwise.

### Cross-platform brand divergence — a recurring sub-case

When the same product surfaces on multiple platforms (web desktop + native app + mini-program, etc.) and an audit finds different brand-primary values per platform, **first run the Migration-State Classification above** — different values are not findings by default. A value difference that is `target` or `in-flight` with the migration signals (upgrade-plan artifact, deprecation marker, parallel-runs switch, tracked work item, deliberate partial rollout) is the brand refresh rolling out unevenly across platforms; it is NOT cross-platform divergence and does NOT require per-platform role naming. The role-naming requirement below applies only to **permanent intentional cross-platform divergence**:

| sub-case | what it looks like | required design-source signal |
|---|---|---|
| **intentional cross-platform divergence** | Product owner has decided web brand = A, native app brand = B (history, market, accessibility, or stack-constraint reason). | Two distinct role names in the design source: `colorPrimary-web` / `colorPrimary-native`, or `brand.web.primary` / `brand.native.primary`, or per-platform variable collection. The two values must NOT both be named "primary" without disambiguation. |
| **accidental cross-platform drift** | Two values exist because different platforms shipped at different times against different sources; no product decision was made. | None — this is drift to fix, not a state to preserve. |

The recurring failure shape: **both values exist in one design source under colorPrimary-shaped roles with no per-platform suffix** (e.g. one in `Brand/.../colorPrimary` and another in a free-floating, often Chinese- or product-vernacular-named `Global/<brand-color>` orphan, or two same-named variables in different collections). An outsider cannot tell which is "the brand". This is Health-Check failure class 2 (drift inside one source) materialized at the cross-platform level. The fix is bilateral: name the two roles explicitly OR converge to one value; do not leave both unnamed.

**Detection signals**:
- Design source: ≥2 variables whose name/role expresses "primary brand color" but values differ.
- Code: cross-subproject grep of `colorPrimary` / `primaryColor` / `PrimaryColor` / `--brand-primary` returning ≥2 distinct hex literals across surfaces of one product.
- Product decision record: no PM-owned doc, ticket, or design-system note explaining the divergence.

### Output shape

A migration-state audit always returns one of: `current` / `target (owner: <named role>)` / `in-flight (N of M surfaces migrated)` / `drift` / `cross-platform-divergence (intentional, roles named)` / `cross-platform-divergence (unnamed → drift)`. Returning "different value found" without state classification is an incomplete audit.

### Hardcoded-value grep must cover both the stylesheet AND the component layer

A code search for raw token values (the color-literal detection above, or any "is this surface migrated to tokens yet" sweep) returns a **false-complete** result when it scans only stylesheets (`.css` / `.scss` / `.less`). Use grep for plain literals, but reach for AST / typed search / resolved-runtime evidence where values hide in CSS-in-JS, styled templates, or typed config. Component UI frameworks carry style values *outside* CSS, in the component/markup layer, and a stylesheet-only sweep leaves them in place while reporting the surface migrated/drift-free:

- **component props** — color / fill / background / track / thumb / active-state color props on icon, slider, chart, progress, and similar components;
- **inline style objects** — `style={{ backgroundColor: … }}` / `:style` bindings / equivalent;
- **imperative config / option objects** — dialog / toast / sheet option fields (e.g. a confirm-dialog's color field), chart option palettes, and other JS-config color strings.

Before reporting a token migration complete or a surface drift-free, enumerate the stack's component-layer color sites and grep them **alongside** the stylesheets. The owning stack skill (`web-react-dev` / `app-cross-platform-dev` / `miniapp-product-dev`) owns the concrete prop / option names for its component set; this rule owns the two-layer requirement. Color literals are the most common case, but the two-layer requirement generalizes to any token class with a component-layer site (typography / spacing / radius props, theme-option objects); the stack skill names those sites per class. The same caveat applies in reverse to the slot-name false-positive trap above — a slot that exists is not a slot that carries the brand, and a value that is absent from the stylesheet is not a value that is absent from the surface.

## Token Cross-Source Validation Procedure

Design tokens drift almost guaranteed without cross-validation. They live in the design source (Figma type styles / color styles / spacing variables / effect tokens / motion specs) AND in the code source (CSS variables / Sass / Tailwind config / native theme objects / asset catalogs). Run this procedure per token class per extraction batch.

### Token classes to validate

| Token class | Design-source representation | Code-source representation (illustrative) |
|---|---|---|
| Typography | Type styles (font-family, weight, size, line-height, letter-spacing) | Theme typography scale, CSS variables, framework theme objects, native font definitions |
| Color | Color styles / palette variables | CSS custom properties, theme palette, color tokens, asset catalogs |
| Spacing | Spacing tokens / scale | Spacing scale variables, theme spacing, native dimension resources |
| Border radius | Radius tokens | Radius variables, theme radius scale, native dimensions |
| Shadow / elevation | Effect tokens | Shadow variables, native elevation/shadow constants |
| Motion / duration | Component or annotation specs | Transition / animation duration variables, native motion constants |

### Procedure per token class

1. Extract source-of-truth values from the design system (class A1 file).
2. Extract implemented values from the code design-tokens package (the `pkg-shared` design tokens or equivalent).
3. Compare token by token; classify each as one of:
   - **match** — values identical → record as confirmed, no action.
   - **drift** — small value difference (e.g. `#3366FF` vs `#3366FE`) → record as finding; ask design + code owners which side is canonical; update the lagging side.
   - **missing** — token exists on one side, not the other → record as finding; decide add or remove.
   - **renamed** — same value, different name → record as finding; align names so search across sources works.
4. The validation result becomes part of the extraction batch's evidence ledger.

### Token audit shape (in the maintainer's private alias map)

For each token decision, record in `~/.<host>/.private-aliases/<project>.yaml`:

```yaml
tokens_audit:
  - token_class: typography
    name: heading-1
    design_value: "<font-family>, <size>, <weight>, <line-height>, <letter-spacing>"
    code_value: "<theme-key-or-resolved-value>"
    code_resolved: "<resolved-value>"
    status: match | drift | missing | renamed
    decision: <which side is canonical; one of: design / code / undecided>
    confirmed_at: <YYYY-MM-DD>
```

The audit lives in the private alias map (project-specific provenance). The procedure shape above is the reusable rule and stays in this shared skill content. Specific tokens, project names, or values must not be added to this shared file.

## Pre-Check (Mandatory Before Any Audit Verdict)

Audits routinely produce confidently-wrong verdicts when the auditor reasons from one artifact in isolation. Every question below needs a sourced answer **before** any finding leaves the agent. "I think" / "the file shows X so X is true" / "based on the file name" are not sourced answers — they block the audit.

1. **Where is the source-of-truth?** Name the design-tool file (URL + label + collection) or the canonical code theme module path. If the portfolio holds multiple `class A1`-shaped candidates, run the Portfolio Role Taxonomy in `design-system-source-of-truth.md` first; the answer here must be a single file (or a single per-platform set) tagged `source-of-truth`.
2. **Is the artifact under review source or derivative?** Apply Source vs Export Distinction (above). Derivative: record provenance + known loss. Unknown: block.
3. **What is the related-file portfolio?** List files tagged `upgrade-plan`, `exploration-wip`, `ui-kit`, `platform-shell`, `icon-library`, `per-feature`. These may explain differences that would otherwise read as drift.
4. **In the source-of-truth, what is the Brand/Semantic layer actually?** Open the source (Variables panel, theme module, generator config) and record: total Brand entries, total Semantic / Neutral entries, and the alias chain for the top-five roles (primary, primary-text, text-strong, bg-container, border). Do not infer from a derivative export.
5. **For each code surface, what does live rendered output actually contain?** Sample the deployed surface — computed style on the live URL, screenshot, or built-CSS profiling. Code-side audits require **three layers** of evidence: design-source alias resolution + code-source theme injection + live computed style. Two layers without the third fails — bundled CSS diverges from theme files, and theme files diverge from runtime injection. **WebView-wrapper hybrid app exception is per-surface, not per-app**: a native shell that hosts the main product UI inside a `WebView`/`WKWebView`/`Activity` delegated to a remote URL plus a JS bridge has WebView-hosted flows that route their brand audit to the loaded web app — mark those `native-theme: not-applicable (webview-hosted)`. Any native-owned surface in the SAME app — splash, login, settings, offline / network-error fallback, permission prompts, native modal flows, status-bar / safe-area chrome, deep-link landing — is audited normally; whole-app `not-applicable` is wrong whenever the shell ships any native screen with brand-relevant chrome. See `app-cross-platform-dev/references/mobile-platform-boundaries.md` for the per-surface implementation rule.

### Skipping any question → these failure modes recur

- Skip Q2 → judge a derivative export's data-loss modes as the system's failures.
- Skip Q3 → declare drift when the difference is a documented upgrade plan or partial rollout.
- Skip Q4 → report "Brand layer empty" from a JSON where cross-collection aliases collapsed to placeholders.
- Skip Q5 → trust theme files while ConfigProvider injects a different value at runtime, or trust computed values without knowing whether they came from theme files or from inline hex literals.

## Decision Checklist

When auditing or starting multi-project token work:

1. List every subproject and its UI-kit (read `package.json` deps). Confirm they fit the stack-uniqueness rule. Outliers = the off-stack-outlier anti-pattern; route to multi-stack strategy.
2. For each same-stack subproject, find the theme injection point (`ConfigProvider`, framework config, `ThemeProvider`). Classify as: **full custom** / **partial custom (single prop)** / **none (default)**.
3. If any subproject is in **partial** or **none**: that subproject is silently off-brand. File a fix or document a deliberate exception.
4. Find the theme source file (or pkg) and confirm it is imported, not copied. If multiple subprojects have their own `theme.ts` with different values, the brand has already drifted; pick the canonical source and migrate.
5. Cross-check token naming alignment: the design-source names (e.g. semantic-tokens in the design-system Figma file) should map to the code-token names by an explicit dictionary. If the dictionary does not exist, build it before refactoring.

## Anti-Patterns

- **Each subproject ships its own theme.ts**: 4 desktop subprojects, 4 different primary colors. Detected by missing shared-pkg import.
- **Single-prop `ConfigProvider`**: `<ConfigProvider theme={{components: {Tree: {titleHeight: 32}}}}>` overrides one micro-detail while inheriting full default brand. Worse than no theme because it signals false confidence.
- **No theme at all**: subproject renders with the third-party library's marketing color (often `#1677ff`). Detected by zero `ConfigProvider theme=` usage in the source tree.
- **Off-stack outlier**: one subproject uses a different UI-kit family inside the same end. Detected by `package.json` deps. Usually a legacy survival; needs an explicit retirement or isolation plan.
- **Business-module files carry zero styles/components**: a per-feature design file that holds no `styles` and no published `components` (the API returns empty arrays) is not lightweight — it means every fill, border, radius, and type style inside the business file is a local literal that does not reference the design-system source. When code rendering a corresponding feature also hard-codes the same literal value, both ends are drifting independently. The fix is bilateral: business design files must consume the design-system styles/components library, AND code must consume the token output package, both sides verified by audit.
- **Hard-coded chart palette / module gradient / overview-card color in code, plus raw local fill in the matching design frame**: when the same color value appears as a literal in both the implementation and the design source, neither side is the source of truth. Resolve by promoting the value into a named token (design semantic style + code token), then deleting both literals. **Two important caveats**: (a) brand tokens and data-visualization tokens are different categories — a brand-color refresh that changes `colorPrimary` must NOT also flip chart-series-1/2/3/4 colors or risk/grade/status semantic chart colors, or chart legends silently lie about historical data. Keep `brand.*` tokens and `chart.*` / `dataViz.*` / `semantic.risk.*` tokens in separate namespaces so a brand refresh is one PR and a data-viz refresh is a separate PR with chart-legend regression tests. (b) Every chart color promotion must come with a contrast check (text-on-fill at the relevant size) and a color-blind check (deuteranopia / protanopia / tritanopia simulation). Promoting a value into a token does not by itself make the chart accessible.
- **Feature-local palette ownership is sometimes correct**: when a chart color encodes domain semantics that the brand cannot define (e.g. a domain-specific risk taxonomy, a domain-specific level band that the product owner authors), the right answer is a documented feature-local palette under `dataViz.<domain>.*` or `semantic.<feature>.*`, not a forced promotion into brand-level tokens. The rule "no literal in code, no raw fill in design" still applies — but the named token can live in a feature-level taxonomy with feature ownership. **Brand fallback is allowed only for neutral unstyled surfaces** (page background, default border, generic text-on-fill). A missing `semantic.risk.high` / `dataViz.<domain>.<series>` token MUST NOT silently fall back to a brand primary color — that turns a missing-token bug into a misleading chart. Make missing semantic / data-viz tokens fail the audit/build, or render an explicit unstyled state (gray + warning indicator) that surfaces the gap during QA.
- **Treating "the design file has no styles" as a green signal**: an empty `styles` array is not "this file inherits from the design system." It is "this file does not formally claim any token usage." Confirm by spot-checking a few frames for `boundVariables` / referenced styles before concluding the file is token-aligned.
- **Vendor-default literal leaked into a custom theme**: a team theme file that mostly customizes brand tokens but leaves at least one value set to a well-known third-party UI-kit default — antd v5 `#1677ff`, antd v4 `#1890ff`, Material `#6750A4` / `#D93025`, MUI `#1976d2` / `#9C27B0`, shadcn slate `#0F172A`, Bootstrap `#0d6efd`, Tailwind `blue-500 #3B82F6`, Chakra `#319795` and equivalents. The leak is more dangerous than an obvious omission because the value *looks* deliberate (someone typed it), so static "no-hex-literals" checks don't fire and reviewers assume it was a designer choice. Brand refreshes that update `colorPrimary` will silently skip these. Detection: maintain a per-stack vendor-default lookup table and grep the team's theme module(s) for any literal in the table, regardless of which property key holds it. A hit resolves to one of three classes — confirm against the design source before treating as anti-pattern: (a) **leak** — value is the vendor default, no design-source role independently resolves to it; replace with a brand token; (b) **deliberate documented reuse** — team explicitly wants this vendor color, recorded in the source comment / theme module / brand doc; keep with a comment naming the rationale; (c) **legitimate convergence** — the brand role in the design source independently resolves to the same hex (a team whose actual brand color happens to be `#1677ff` is not "leaking antd"); keep but reference the brand token, not the literal, so future audits can trace the value back through the brand layer instead of re-flagging.
- **Algorithmic secondary/tertiary color derivation without design approval** — applies to **custom** algorithmic derivation, NOT to standards-based platform schemes: a theme file that computes secondary/tertiary/hover/active/disabled state colors from primary via custom algorithm — HSV hue shift, alpha tint, complementary, lightness step, brightness modulation, etc. — without a designer-signed record. The pattern is convenient (brand refresh auto-updates derived colors) but skips designer judgment for every derived state. Allowed only when: (a) the derivation is documented in the theme file (one-line comment naming the algorithm and the designer/date sign-off), AND (b) the brand-refresh flow includes a derived-color visual check (screenshot diff or designer pass) before shipping. Silent algorithmic derivation that nobody reviews ships brand-tinted but designer-unapproved hover/disabled states, then no one notices when they read wrong against the new primary. **Standards-based platform carve-out**: Material You's `ColorScheme.fromSeed` / `dynamicLightColorScheme`, antd's automatic palette derivation from `colorPrimary`, MUI's `createTheme` tonal palette, and equivalent vendor-provided derivation algorithms are acceptable as the design policy when (a) the variant/version in use is recorded, (b) accessibility/contrast checks pass against the brand seed, (c) visual QA on canonical screens at the seed value is signed off. Designer sign-off applies to the policy adoption + the seed/canonical-screen pass, NOT to every runtime-generated tonal value. Stack-specific implementation guidance lives in `app-cross-platform-dev/references/{android,flutter}-dev.md`.

## Routing

- Implementation tooling (shared theme package, automated check that every subproject imports the shared theme) → `web-react-dev`.
- Mobile / native equivalent (`MaterialApp.theme`, `UIAppearance`) → `app-cross-platform-dev`.
- Mini-app equivalent (mini-app `app.json` theme and host-platform theme constraints) → `miniapp-product-dev`.
- Test acceptance (screenshot diff on canonical components per subproject; runtime assert that primary color matches brand) → `testing-strategy`.
