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

Apply the same rule to code, external benchmarks, and review feedback: use them for reusable UI/UX behavior, implementation quality, launch gates, and iteration signals only; never to infer the product's business domain.

Backend service code evidence is out of scope for this skill except where it affects product-visible lifecycle: generated API freshness, async task status, artifact readiness, permission/empty/error states, and launch observability. Detailed backend service rules belong in the relevant backend skill.

## Source Class Capability Map

For each design source available to the maintainer, classify before extraction along five dimensions. The map below is the *shape* of classification; concrete file entries live in the private provenance archive.

| Dimension | Allowed values | Purpose |
| --- | --- | --- |
| `label` | sanitized capability label (e.g. `<design-system-web>`, `<review-module>`, `<scan-module>`) | Reusable identifier in skill text; never use a real file name |
| `class` | `A1` rules-as-source (design system / UI kit / icon / annotation spec) / `A2` business-module / `B` reference-or-deprecated | Determines extraction weight: A1 anchors tokens/components, A2 anchors flows/states, B is provenance-only |
| `stack` | `desktop-web` / `mobile-h5` / `mobile-native` / `mini-app` / `mixed-host` | Determines which implementation skill cross-checks the source |
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

Coverage discipline:

- "Full coverage" means every relevant source class has been used, routed, discarded, or marked unavailable with a reason — not "everything inspected".
- "Targeted" passes are explicit about which surfaces and which frames were read. Do not promote a targeted pass to a full audit in language alone.
- For large Figma files, use page-level inventory first, then targeted frame/node reads, then screenshot fallback. Failed reads are recorded with the smaller read attempted; "unavailable" requires a remediation attempt first.

## Naming And Scope Decision Record

A product UI/UX skill must be product-agnostic. If the skill name or default scope leaks one business domain or surface category, rename and demote the leaked context to a scenario lens (e.g. `scenario-community-patterns.md`) rather than letting it drive defaults.

Routing boundary:

- Implementation rules belong to `web-react-dev`, `app-cross-platform-dev`, and `miniapp-product-dev` for mini-program implementation.
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

Use these as named quality benchmarks only, not as visual or product-domain sources:

- Nielsen Norman Group usability heuristics: heuristic review layer for status visibility, user control, consistency, error prevention, and recovery.
- W3C WCAG 2.2: accessibility baseline for labels, keyboard, focus, contrast, target size, error identification, and consistent behavior.
- web.dev Core Web Vitals: launch/performance benchmark for LCP, CLS, INP, and field/lab measurement.
- Google HEART framework: iteration metric lens for happiness, engagement, adoption, retention, and task success.
- Material Design / Atlassian Design System guidance: platform/design-system support for touch targets, progressive disclosure, empty states, errors, and feedback clarity.

Extracted patterns live in `external-ui-ux-quality-benchmarks.md`.

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
