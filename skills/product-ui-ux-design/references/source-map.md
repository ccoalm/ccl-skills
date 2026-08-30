# Figma Source Map

Internal source-classification rules and provenance pointer for the organization product UI/UX skill. This file records *how* to classify, refresh, and judge design sources; it does NOT record the specific files, keys, paths, or branches that were inspected. Specific provenance lives outside the skill tree.

Users of this skill never need access to the original Figma files, file keys, or source code paths. Treat any "no source access" situation as normal; rely on the distilled rules in `SKILL.md` and focused references instead.

## Provenance Pointer

Specific Figma file keys, project URLs, real subproject paths, real branches, real node ids, and dated re-extraction logs are kept in a private archive outside this skill tree. When auditing or re-extracting, the maintainer loads the archive locally; normal users do not.

If this skill is distributed outside the controlling organization, the private archive does not travel with it, and this file alone remains usable. External distributions must verify that no project URL, file key, real subproject path, real branch, or domain-specific name has leaked into any reference file.

## Conflict And Duplicate Policy

When two sources disagree or overlap, decide explicitly:

- **Keep** the most current, complete, reusable pattern.
- **Merge** compatible variants into a generalized rule.
- **Discard** stale, duplicated, lower-quality, or overly domain-specific details.
- Never let one source file define the product domain. Source identity is provenance, not the product model.
- Do not infer any product domain from source identity.

Apply the same rule to code, external benchmarks, and review feedback: use them for reusable UI/UX behavior, implementation quality, launch gates, and iteration signals only; never to infer the product's business domain.

For a conflict-heavy task, the decision artifact is a row-per-property-and-state
matrix, not a blank record schema or a prose precedence list. Include the exact
artifact revision and observed value for every source, its status and owned
scope, the governing source or replacement decision, the conflict class, the
chosen result, and an explicit unknown plus verifier where evidence is missing.
Cover every applicable interaction and visual state; do not hide disagreement
inside a combined `loading/error` row or a generic `other states` entry.

Resolve the matrix in execution order:

1. Freeze the relevant source revisions or content digests and
   inventory the complete state/property rows before choosing a winner.
2. Classify authority and scope per row; a source may govern one state and be
   partial or silent for another.
3. Keep current specified decisions, merge only compatible freedom, and create
   an explicitly reviewable replacement decision for an intentional change.
4. List the exact design, component/API, token, example/story, and test updates
   in dependency order. Stories and tests expose intent or drift; existence and
   unexecuted assertions do not settle authority or runtime behavior.
5. Bind and run the resulting static, component, rendered, interaction, and
   accessibility checks. A passing test closes only its declared row/oracle.

Backend service code evidence is out of scope for this skill except where it affects product-visible lifecycle: generated API freshness, async task status, artifact readiness, permission/empty/error states, and launch observability. Detailed backend service rules belong in the relevant backend skill.

## Source Class Capability Map

For each design source available to the maintainer, classify before extraction along five dimensions. The map below is the *shape* of classification; concrete file entries live in the private provenance archive.

| Dimension | Allowed values | Purpose |
| --- | --- | --- |
| `label` | sanitized capability label (e.g. `<design-system-web>`, `<review-module>`, `<scan-module>`) | Reusable identifier in skill text; never use a real file name |
| `class` | `A1` rules-as-source (design system / UI kit / icon / annotation spec) / `A2` business-module / `B` reference-or-deprecated | Determines extraction weight: A1 anchors tokens/components, A2 anchors flows/states, B is provenance-only |
| `stack` | `react-web` / `other-web` / `mobile-h5` / `mobile-native` / `mini-app` / `terminal-tui` / `desktop-tv-shell` / `mixed-host` / `other-client` | Determines which installed implementation owner or fail-closed project convention cross-checks the source; a composite host records every layer |
| `surface` | `shell` / `auth-and-account` / `workbench` / `creation-and-import` / `review-and-evaluation` / `analytics-and-report` / `asset-management` / `roster-and-entity-management` / `device-and-capture` / `notification-and-recovery` | Determines which pattern reference owns the rules |
| `freshness` | `current` / `candidate-needs-inspection` / `deprecated` / `archived` | Determines whether the source can drive hard rules |
| `coverage` | `published-system` / `targeted-workflow` / `representative-cross-check` / `metadata-only` / `screenshot-fallback` / `unavailable` | Determines how strong the evidence is |

A new source extraction must declare all six dimensions before producing rules. A source with `freshness: deprecated` or `class: B` cannot create a hard rule alone; it can only confirm a pattern present in stronger sources.

## Re-Extraction Protocol

For any new extraction, broad refresh, or conflict-heavy update, run `skill-extraction-workflow` first.

Collection strategy default: **local-plus-external**.

- Local sources are authoritative for source status: current Figma files, prior source-classification decisions, local frontend implementation evidence, and the active target product context.
- External sources are challenge/quality inputs only: usability, accessibility, performance, community-product benchmarks, and public skill-engineering practices. They do not define the product domain or visual language.
- If Figma or code access is unavailable, do not fabricate coverage. Apply the distilled references directly and mark source verification as unavailable.
- If a Figma file's name carries a team-specific deprecation prefix or suffix (the team's known deprecation markers are kept in the private archive; common categories include a brand-bracketed prefix used to flag legacy snapshots, an automatic `(Copy)` suffix from Figma duplication, or an explicit "deprecated" page name in the team's working language), classify the file `freshness: deprecated` before any read. Such files cannot drive hard rules.
- If a Figma frame carries inline version or date stamps (e.g. a version suffix `_verN`, a "current/latest" marker in the team's language, an `MMDDnew` date stamp, or a designer-added disambiguation parenthetical), treat the source as in-flight and prefer the latest stamp. Older sibling frames remain as discardable provenance.

For a formal source re-extraction or full portfolio audit, first enumerate every formal design file in the portfolio, apply the exclusion rules, and fully extract every non-excluded file. A targeted frame pass cannot substitute for that all-file obligation. Ordinary product design may inspect only the sources relevant to its decision, but must not describe that targeted pass as full extraction.

Coverage discipline:

- "Full coverage" means every non-excluded formal source has been inspected/extracted and every relevant source class has been used, routed, discarded, or marked unavailable with a reason. It is stronger than a targeted pass, not a synonym for "some representative files inspected".
- "Targeted" passes are explicit about which surfaces and which frames were read. Do not promote a targeted pass to a full audit in language alone.
- For large Figma files, use page-level inventory first, then targeted frame/node reads, then screenshot fallback. Failed reads are recorded with the smaller read attempted; "unavailable" requires a remediation attempt first.

## Naming And Scope Decision Record

A product UI/UX skill must be product-agnostic. If the skill name or default scope leaks one business domain or surface category, rename and demote the leaked context to a scenario lens (e.g. `scenario-community-patterns.md`) rather than letting it drive defaults.

Routing boundary:

- Runtime delivery follows `delivery-contract.md`; it is the single shared contract for design, testing, producer execution, client execution, evidence, and verdict. Each owner writes its own record; the design verdict cites the complete bound set rather than copying evidence.
- Implementation rules follow the complete affected client-owner set in `delivery-contract.md`: React web → `web-react-dev`; Vue/Svelte/static/vendor/other web → its installed web-content owner or fail-closed project-convention lookup; native mobile/host → `app-cross-platform-dev`; mini-app → `miniapp-product-dev`; terminal/CLI/TUI → `terminal-cli-dev`; Electron/desktop/TV shell → its installed owner or the same lookup. Composite hosts keep separate content and shell members; a missing owner is never silently treated as Web or React.
- Test-layer rules belong to `testing-strategy`.
- This skill owns UI/UX judgment, state completeness, visual acceptance, design readiness, and scenario-specific design lenses.

## Coverage Audit Frame

When the maintainer claims coverage, the audit table records the shape, not the content:

| Dimension | What it answers |
| --- | --- |
| Current product Figma files | Were the current `freshness: current` design files inspected, or only by file key? Direct team/project enumeration may or may not be possible. State clearly. |
| Design systems | Were published desktop and mobile design-system files inspected? Were any reference-only UI kits or icon libraries promoted to rules? They should not be. |
| Code evidence | Was implementation code cross-checked per stack class? Code is implementation evidence only, not product-domain or visual source. |
| Backend code evidence | Was any backend module referenced? Only product-visible lifecycle consequences belong here; detailed backend belongs in backend skills. |
| External quality benchmarks | Was at least one usability/accessibility/performance/iteration-metric source named? |
| Public skill practice | Were public skill examples used as engineering method only, not as persona or domain donors? |

Each row must be fillable as "inspected / not inspected / not applicable" with one short rationale.

## Thin-Evidence Handling

- Weak/reference-only files may confirm a pattern already present in stronger sources, but they cannot create a hard rule alone.
- Image-only, archived, copied, deprecated, or `todo`-marked evidence must be labeled weak unless a stronger source confirms it.
- When a future file is named with a "supplement" or "exploration" prefix (in the team's working language), inspect before use; do not exclude or promote by name alone.
- Record corrections as a compact entry: scene, wrong prior rule, corrected generalized rule, decision, target reference, and source status. Keep this entry in the private archive, not in this file.

## External Quality Sources

Use named external sources at their actual evidence strength, never as visual or product-domain donors:

- ISO 9241-210 and ISO 9241-11: human-centred lifecycle and context-dependent usability framing; neither supplies a page recipe or proves a particular design.
- W3C WCAG 2.2 and ARIA Authoring Practices: normative accessibility criteria plus informative implementation patterns. APG examples are not a complete design system or production-ready code.
- Primary empirical papers: contextual evidence for a bounded mechanism. Record participants/task/materials and contradictory or limiting findings before turning a result into a rule.
- Current platform guidance: host convention for the named platform and input mode, not a cross-platform constant.
- Design Tokens Community Group format: interchange vocabulary, not proof of visual quality, token governance, rendered themes, or standards status.
- Expert heuristics: risk-discovery prompts only. Heuristic review is not acceptance proof.

The claim ledger, primary links, and boundaries live in `external-ui-ux-quality-benchmarks.md`.

## Candidate Formal Sources Policy

Some files cannot be excluded by name alone — for example, files marked as supplement or exploration in the team's working language, or any file appearing in the project that lacks an explicit current/deprecated marker. Treat them as candidates: inspect their pages, compare against current files, and only then promote, weak-keep, or discard.

A candidate that survives inspection joins the current class only with explicit reason; otherwise it is `freshness: candidate-needs-inspection` and cannot drive hard rules.

## Default Exclusion Set

By naming convention, exclude or downgrade:

- Any file whose name uses a team-specific deprecation marker (the active marker list is kept in the private archive — common categories include Figma's automatic `(Copy)` suffix, explicit deprecation page names in the team's working language, and team-specific brand prefixes used to mark legacy snapshots).
- Slides/report documents (e.g. project-visual-summary slides). These are reference, not source.
- Broad library placeholders (e.g. someone's team library / sandbox) that do not represent a published design system.
- Any file with clear old / deprecated / archive labels in name or page.
- Code-side equivalents: page or component folders with `V<N>` suffix that coexist with the unsuffixed version. Treat the suffixed one as in-flight; verify which the runtime entry imports before extracting rules from either.

## Where The Specific Provenance Lives

This file deliberately does not list current/strong/candidate/discarded file names. That list, with file keys, modification dates, real subproject paths, real branches, and dated re-extraction logs, lives in the maintainer's private archive (one path-private YAML per product). The archive is not published with this skill.

When a future maintainer needs to refresh provenance, they:

1. Load the private archive locally.
2. Re-read the listed Figma files and code paths against the current source.
3. Update the archive with the new dated entry.
4. Update this file *only* if the classification rules, dimensions, or policy themselves change.

The skill content remains usable even when the archive is absent.
