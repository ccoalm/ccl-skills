# Design System Source Of Truth

Load this reference when working on token decisions, theme files, design-system files, or any task that asks "which Figma file is the real source for this color/component/spacing?". It defines how to identify the design-system source, how to keep design and code in sync, and how to detect and route business-file leaks.

## Triggers

- Adding or editing theme/token files in any subproject.
- Onboarding a new subproject and deciding which theme to inherit.
- Spotting two Figma files that both seem to define brand tokens.
- A design-system Figma file appears suspiciously complete (90+ pages, full component catalog) — verify whether it is a team-authored system or a third-party mirror.

## Rules

- A Figma file labeled "design system" in the team's project list may actually be a **figma mirror of a third-party component library** (third-party kits like Ant Design, antd-mobile, Material, or Polaris are illustrative — the same pattern recurs across many ecosystems). Confirm by checking the page list for explicit names like `<Library> System for Figma` or `Figma to <Library>`; if present, treat the file as the third-party spec, not as team-authored tokens. The team's brand customisation usually lives in a smaller separate file, often named for a product framework refresh, a brand-system file, or a workbench/shell file — name conventions vary across teams.
- A design portfolio that spans multiple rendered stacks must inventory React and other web, H5, native mobile, mini-app, terminal/TUI, Electron/desktop, TV, and any additional client. Assign each stack to one canonical design-system source or an explicit shared-source decision with stack-specific variants and evidence; do not infer that a desktop/mobile pair covers the rest. Business-module files should not carry their own token/style definitions; they should reference the applicable canonical source only.
- A business-module Figma file is correctly scoped when its `/v1/files/<key>/styles` and `/v1/files/<key>/components` endpoints return zero file-local entries — all styles inherited from the design-system file. Non-zero counts on a business file = the file has forked tokens, which is a refactor flag.
- Theme/token source files in code must include an explicit machine-checkable pointer to the design-system Figma source: top-of-file comment with the file's labeled name (not the team-internal nickname) and node-id of the token frame. Pointing the comment at a business-module file instead of the design-system file is a documented anti-pattern — the next person edits the wrong source.
- Deprecated design files must carry an explicit signal: a dated deprecation page, an archive folder, or a tracked deprecation list in the private provenance archive. Do not rely only on file-name prefixes (brand prefix, copy suffix, etc.) — prefixes are easy to miss in tooling. Keep the active marker list in the private archive and audit each load.

## Portfolio Role Taxonomy

The existing `class A1 / A2 / B` labels are too coarse when a single product's design portfolio holds more than one file claiming to be system-canonical. Before treating any single `A1` file as the source-of-truth, classify every `A1` candidate by role.

| role | what it is | health rules to apply |
|---|---|---|
| `source-of-truth` | currently authoritative system file: Brand / Semantic layer fully bound, Components tier populated, multi-mode resolved, consumed by current production code. One per stack. | full Design-Source Health Check + alignment audit against live code |
| `upgrade-plan` | one or more files describing the next-version system (refresh / vendor migration / new brand). May intentionally not match current production code. A single upgrade plan may exist as a main file plus per-feature `upgrade-plan-supplement` files. | Migration-State `target` audit only; do not audit against current code for drift; treat supplements as parts of the same plan, not independent sources |
| `combined-active` | a single file that mixes system-level content (components / tokens / variables) with per-feature business pages and exploration sketches, still being edited. Often the team's original monolith, the central brainstorm scratchpad before content is extracted into dedicated files, or the shared seed file new proposals start in. May coexist with a separate `source-of-truth` that received its extracted content. | partial-authority: only the portions not yet superseded by a dedicated file are evidence; mark each page with its supersession state (`migrated-to: <file_label>` / `still-authoritative` / `wip`); pages still-authoritative get the same rules as the role that page would belong to in a split portfolio |
| `exploration-wip` | working file for direction trials and variant proposals only, with no business or system content the team relies on. Distinct from `combined-active`: nothing here is the canonical answer to anything. | weak evidence only; do not extract rules; do not audit against code |
| `ui-kit` | component-spec file (button states, form patterns, layout primitives) documenting shape and behavior without owning brand tokens; tokens reference source-of-truth. May exist in a version chain (current ui-kit aligned to current `source-of-truth` + legacy ui-kits retained for historical reference); audit must determine which is current by inspecting the link back to source-of-truth, not by file name or recency. | verify cross-file token references back to current source-of-truth; flag any locally-defined token as a fork; legacy ui-kits in the chain treat as `class B` reference-only |
| `platform-shell` | platform-specific surface file (desktop product chrome, mobile app chrome) consuming source-of-truth tokens; may exist per platform | same as `ui-kit` |
| `interaction-spec` | file focused on UX flow / behavioral annotation / state transitions / gesture spec, rather than visual composition or token definition. Recognizable by naming convention pairs such as `(UI)` / `(UX)` companion files, by page content (flow diagrams, swimlanes, state machines, interaction notes), or by an explicit annotation-tool spec doc. | health-check skipped; evidence used for interaction logic / behavioral logic rules only, not token / component / visual rules |
| `icon-library` | file owning icon set, stroke discipline, sizing rules; owns its own dimension tokens, consumes color tokens from source-of-truth | verify color / size token references; flag locally-defined color tokens as a fork |
| `per-feature` | already covered as `class A2`: business-module file inheriting all tokens, owning page-composition evidence only | existing `A2` rules (`styles_count == 0`, `components_count == 0`) |

### Portfolio-pass rule

When the portfolio holds multiple `A1`-shaped files, the audit MUST enumerate the full portfolio and assign a role to every entry **before** judging any single file. Single-file-in-isolation audits produce predictable false findings:

- Mistaking an `upgrade-plan` for a broken `source-of-truth` because its values do not match production code.
- Mistaking a `ui-kit` for a competing `source-of-truth` because it defines components.
- Mistaking a `combined-active` monolith for either a broken `source-of-truth` (because not all roles are clean inside it) or an inert `exploration-wip` (because it has scratch pages). It is neither — record per-page supersession state.
- Treating an `interaction-spec` file as a visual/token source because the team named it after a product surface. Read the page content, not the file name.
- Treating an `exploration-wip` as authoritative because it was the most-recently-edited file.

### Predecessor / ancestry tracking

The portfolio enumeration must record relations between files, not only per-file roles. For each entry, capture at least one of:

- `predecessor_of: <file_label>` — an earlier file that has since been split into newer files; the newer file is now authoritative for the migrated content.
- `derived_from: <file_label>` — a newer file that extracted content out of a predecessor; the predecessor may still hold non-migrated pages.
- `supplements: <file_label>` — a companion file (most often `upgrade-plan-supplement` to `upgrade-plan`, or a `per-feature` extension to a parent product surface).
- `succeeds-version: <file_label>` — a later version in a ui-kit / platform-shell version chain; the predecessor in the chain becomes legacy.
- `no-relations` — explicitly stand-alone (rare in mature portfolios; flag for review).

Sibling files without recorded relations are treated as competing source candidates, which is usually wrong: most files in a mature portfolio descend from earlier monoliths or supplement an existing parent. Missing ancestry is a portfolio-enumeration defect, not a system defect — fix the enumeration before judging the files.

Record the portfolio (entries + relations) in the private provenance archive (one entry per file: role + relations + last-updated + owner + relation to current production code). The audit references the archive, not its own assumption about which file is canonical.

## Decision Checklist

When starting work on tokens/theme/design-system:

0. Enumerate every file in the project's design portfolio (system, upgrade plan + supplements, combined-active monoliths, exploration, UI kit version chain, platform shells per stack, icon library, interaction-spec, per-feature). Assign a Portfolio Role from the taxonomy above to every entry, plus the predecessor / derived / supplements / succeeds-version / no-relations relation to other entries. Recording the portfolio with role AND relations is mandatory before any single-file judgment; missing relations is a portfolio-enumeration defect, not a system defect.
1. Pull the project's Figma file inventory; mark each entry `class A1` (rules-as-source), `class A2` (business-module), or `class B` (deprecated/reference) using the source-map rules.
2. For each `A1` file, verify whether it is team-authored or third-party-mirror via page-name pattern.
3. For the active `A1` files, map every rendered stack in the authoritative consumer inventory—React and other web, H5, native mobile, mini-app, terminal/TUI, Electron/desktop, TV, and any additional client—to exactly one canonical source or one recorded shared-source decision. If multiple sources compete for a stack, choose one as canonical and demote the others to `class B` until merged.
4. For the theme/token source file in code, verify its top-of-file Figma comment points at the canonical `A1` file's node-id, not at a business-module file.
5. For each `A2` business file, confirm `styles_count == 0` and `components_count == 0` via Figma API. Non-zero = file-local forked tokens; route to the design-system maintainer to merge.
6. Cross-check deprecation: every file the team treats as deprecated must appear in the private deprecation list. Files-only-marked-by-prefix get a follow-up to add them explicitly.

## Anti-Patterns

- **Mistaking a third-party mirror for a team design system**: leads to "we already have a complete design system" claims that ignore the missing brand customisation layer.
- **Pointing the theme-file Figma comment at a business module**: future edits chase the wrong frame; design-code drift accumulates.
- **Business module owns its own tokens**: `styles_count > 0` on an `A2` file is a fork. New brand updates ship only to the design-system file and silently bypass the business module.
- **Deprecation-by-prefix-only**: a brand prefix used to mark legacy snapshots will eventually conflict with active naming. Maintain a tracked deprecation list outside the file names.
- **Single-file audit without portfolio enumeration**: judging one design file in isolation, comparing it to current code, and reporting "drift" or "incomplete system" without checking whether other portfolio files (upgrade plan, exploration WIP, UI kit, platform shell) explain the difference. The recurring failure shape is N revisions of the audit verdict as the auditor discovers each missing role in turn — every additional file the user surfaces flips an earlier conclusion. Fix: enumerate the portfolio first, assign roles, then audit each role with the rules that apply to it.
- **Two `colorPrimary`-shaped variables in one source with no per-platform role naming**: a design-system file that defines both a tier-correct `Brand/.../colorPrimary` AND a free-floating orphan brand variable (e.g. a `Global/<brand-color>` / `legacy/brandColor` / un-grouped top-level brand token, often in product-vernacular or non-English naming) holding a different value. Whether the divergence is intentional cross-platform branding or accidental legacy is irrelevant to consumers — they cannot tell which is "the" brand because neither name carries the platform role. Fix is in the source: either (a) consolidate to one value and remove the orphan, or (b) rename to express the divergence explicitly (`colorPrimary-web` / `colorPrimary-native`, separate variable collections per platform, etc.). See `multi-project-token-consistency.md` for the cross-platform brand-divergence classification and the consumer-side audit signal.

## Green-Field Fallback (No Existing Figma DS Yet)

A new product or a new team may not have a Figma design-system file at all. The rules above assume one exists; without one, do not stall the build. Instead:

1. Define the **token role taxonomy** first, in code or a short doc, before any Figma file: primary, primary-text-on-fill, fill/surface, text strong/secondary/muted, border/line, background, semantic (success/warning/danger/info), and any product-specific semantic role (e.g. "evidence", "automated", "destructive"). Names only at this stage; values can be placeholders.
2. Set placeholder hex values that satisfy contrast and obvious-brand-distance from the third-party library default. Pick values that are clearly the team's own (not a vendor default), record them as the working palette, and note that they are provisional.
3. Inject these token roles at the entry layer of every same-stack subproject from day one (`ConfigProvider theme={brandTheme}` / `MaterialApp.theme` / equivalent). The injection mechanism is the source-of-truth — the values can still be replaced when a designer commits them.
4. When a Figma design-system file later arrives, register it in the private archive, point the code's theme source file at it via a top-of-file comment with file name + node-id, and replace the placeholders. The role taxonomy survives unchanged; only the values shift.
5. Do not block product work on "we don't have a design system yet." A token role taxonomy + injected theme is a sufficient starting design system; the Figma file is provenance and refinement, not a prerequisite.

This fallback exists because the standard rules above require a Figma file inventory; without one, those rules return "no action" instead of "act on the role taxonomy". The fallback fills that gap.

## Routing

- Implementation enforcement of the comment-pointer rule and the `styles_count == 0` audit follows every affected client owner in `delivery-contract.md`: React web → `web-react-dev`; other web → its installed owner or project convention; native mobile → `app-cross-platform-dev`; mini-program → `miniapp-product-dev`; terminal/TUI → `terminal-cli-dev`; Electron/desktop/TV → its installed owner or the fail-closed project-convention lookup. The check must inspect the source shape actually used by that stack; a Web-only tool is not evidence for a native, terminal, or desktop client.
- Acceptance layer and cross-client evidence sufficiency → `testing-strategy`.
