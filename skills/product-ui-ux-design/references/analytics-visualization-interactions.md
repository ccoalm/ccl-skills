# Analytics Visualization Interactions

Use this reference when designing or implementing insight-heavy surfaces: creator analytics, topic health, user growth, retention, content performance, trust/safety monitoring, AI quality analytics, or operational dashboards.

Source provenance lives in `source-map.md`. Use this reference only for chart, comparison, drill-down, filter, and report interaction mechanics.

## Core Value Extracted

The strong design idea is **decision-oriented analysis**, not decorative charts:

- Filters define the analytical question before charts appear.
- Overview metrics summarize the current scope.
- Charts reveal distribution, trend, comparison, or exception.
- Tables/lists let users inspect the underlying items.
- Drill-down preserves context from overview to segment to detail.
- Permission, missing data, partial data, and comparison setup are explicit states.

## Analytics Surface Model

Use this structure:

1. **Scope bar**: time range, segment, topic/community, audience, content type, comparison target, and permission scope.
2. **Metric summary**: only metrics that drive an action or interpretation.
3. **Visualization cluster**: trend, distribution, ranking, funnel, cohort, comparison, or quality breakdown.
4. **Explainability layer**: definition, source, timestamp, sample/data scope, caveat, and benchmark.
5. **Detail list/table**: underlying items, creators, posts, comments, reports, cohorts, or AI outputs.
6. **Drill-down path**: overview -> segment -> item/detail, with persistent breadcrumb/context.
7. **Action layer**: export, share, inspect, adjust filter, create follow-up task, or open detail.

## Chart Interaction Rules

- Never rely on color alone. Label current, previous, target, benchmark, and abnormal directly.
- Keep selected filter and comparison target visible after they affect the chart.
- Pair hover/tooltips with persistent labels for important values.
- Give empty and no-comparison states a setup action, not a blank chart.
- Show partial-data, stale-data, and permission-limited labels near the affected chart.
- For dense legends, allow hide/show series but keep the default view interpretable.
- If a chart drives a decision, provide the underlying list or drill-down.
- Avoid chart variety for decoration. Choose chart type by question:
  - Trend: change over time.
  - Distribution: spread across buckets.
  - Ranking: top/bottom entities.
  - Funnel: step conversion.
  - Cohort: retention or repeated behavior.
  - Comparison: current vs baseline/target/segment.

## Mobile Analytics Rules

- Use cards and progressive disclosure instead of desktop-sized tables.
- Put filters in a sheet or compact selector, and show active filter chips after selection.
- Keep one primary chart per viewport region.
- Move detailed tables into drill-down screens or bottom sheets.
- Preserve context when returning from detail.
- For threshold/benchmark settings, treat them as advanced controls.
- Split mobile reports into overview, module, and detail layers. Overview cards summarize; module cards explain and chart; detail pages carry dense tables, fixed columns, sort, compare, and item inspection.
- Model all-scope, single-scope, permission-limited scope, and comparison setup as distinct states. Do not use an empty selector to mean "all".
- Dynamic grouped tables should generate columns from data shape but keep row identity stable with sticky context columns, stable grouped headers, visible sort state, and horizontal scroll boundaries.
- When a user setting changes a chart threshold, level band, color rule, or benchmark, refresh the affected module and preserve the rest of the report unless the scope itself changed.
- If a permission scope is narrower than a benchmark or reference scope, label the coverage difference near the affected metric and avoid overwriting fuller cached context with a shorter partial response.
- Benchmarks and reference lines need local labels that remain readable on narrow screens; if labels collide, prefer fewer labels or a drilldown over unreadable chart decoration.
- Mobile chart and table states must include loading, empty, error/retry, no comparison target, partial data, stale data, and too-little-data variants at the module level.

## Web Analytics Rules

- Use sticky filters and stable toolbar height.
- Keep metric cards compact and scannable.
- Use side panels or drawers for definitions, details, and setup.
- Tables should preserve row identity, selected state, sort/filter state, and use the sticky header/fixed-action-column primitive from `ui-ux-design-development.md` when horizontal scrolling is required.
- Wide charts need min/max width behavior and should not collapse into unreadable labels.
- Share / deep-link actions use routed identity — a URL composed of `(moduleInstanceId | metricId, level, scope, report, tenant, schema-version)` plus safe current-view parameters or references. When the recipient opens the link, authorization is re-evaluated server-side and current data is fetched; the link itself is not a data snapshot.
- Export / download actions are server-side data requests, not just routed identifiers — the export job payload must compose routed identity + current filter-set + config-version + sheet/data selection + a snapshot/generation token, and the resulting artifact must carry timestamp / staleness disclosure. Only snapshot-sharing (recipient sees the data as it was at export time) opts into export-artifact semantics; live-link sharing stays on the routed-identity path. See the multi-level "key class" matrix in the "Multi-Level Hierarchy Navigation" section for the full taxonomy.
- Alert stale, updating, or unreliable data near the affected chart/table and keep the alert sticky only when it changes interpretation.

## Dense Chart Workbench Pattern

Use this for analysis pages where one shell contains many chart/table modules, benchmark comparisons, local parameter settings, and exportable evidence.

- Treat the page as a **measurement workbench**, not a chart gallery. The persistent shell should show current scope, source/status metadata, global filters, module navigation, and export/setup actions before the chart region.
- Use a calm visual direction: low-chroma neutral page background, white module surfaces, restrained 1px borders, compact controls, dark numeric text, muted metadata, and one primary action/selection color. Chart palettes may use repeated local colors, but repeated surface/text/action colors should map to product tokens.
- Keep the module title row dense and informative: title, chart/table switch, rule/definition popover, parameter or threshold settings, comparison selector, and export action belong near the chart they affect.
- Pair every aggregate chart with an exact table, list, or drill-down. Chart mode supports pattern recognition; table mode supports audit, sorting, copy/export, and exact-value comparison.
- Prefer progressive analytical disclosure over more cards: overview -> metric group -> chart/table -> expandable detail -> item or object detail. Long modules need local anchors or a side module menu so users can return without losing context.
- When category count grows, preserve comprehension before density: show an initial bounded window, expose horizontal data zoom or scroll, rotate/truncate long labels, keep legends scrollable, and keep fixed context columns in table mode.
- For wide grouped tables, lock the row identity and primary aggregate columns before dynamic metric columns. When many metric groups are present, horizontal scroll is acceptable only if the fixed columns, header grouping, and cell alignment remain stable.
- Baseline and benchmark lines need visible labels and collision handling. If multiple reference lines collide, move labels, reduce line count, or use a detail view rather than drawing unreadable annotation.
- Distinguish two different color semantics. Threshold coloring answers "is this value in a configured band"; comparison coloring answers "is this value higher or lower than the selected baseline." Do not mix the two without an explicit switch, legend, and copy.
- User-scoped threshold settings must say who the setting affects, validate interval order before save, show inline error state, and preserve the rest of the report while refreshing only affected modules.
- Use red/green or risk/success color only with labels, legends, or threshold definitions. Color alone is not enough for accessibility or decision confidence.
- For percentage-like values near `100.00%`, allocate enough chip/cell width before visual QA. A value that wraps, clips, or shifts the layout fails acceptance even when the chart data is correct.
- Expanded entity, sub-item, or breakdown states should preserve the parent row/module context, show child grouping clearly, support optional/additional items, and keep collapse/return controls visible.
- Empty, no-comparison, permission-limited, stale, updating, export-pending, and parameter-invalid states are module states. They should not blank the whole report unless the global scope itself is invalid.

Judgment layer:

- Aesthetic logic: quiet contrast, strong numeric alignment, restrained borders, and compact rhythm make dense analysis feel precise rather than busy.
- Interaction logic: users enter through scope and module navigation, switch chart/table for the same question, adjust settings locally, inspect exact values, then drill down without losing context.
- Behavioral logic: long labels, too many categories, missing comparison targets, invalid thresholds, export jobs, stale data, and per-module failures need local recovery paths.
- Psychology: source/status labels, explicit rule popovers, scoped settings copy, visible baselines, and exact tables reduce uncertainty and give users confidence that they can explain or defend a decision.

## Large Insight Report Workbenches

Use this when one analytics area contains a report list, a deep report detail, multiple chart/table modules, object or user detail pages, and an entry from another workbench.

- Treat the surface as a report system, not a dashboard page. Define the list, detail shell, module navigation, filters, comparison setup, object detail, and export task as separate regions with their own states.
- Keep the report title, current scope, primary-entity/object filter, route tab, and download/export action visible before chart detail. Users should not need to remember which slice they are reading while scrolling.
- A long detail page needs two navigation layers: a coarse module menu or side navigation for report families, and a local anchor or section list only where the current module is long enough to lose position.
- Use compact analytics density: 60-64px page headers, about 180-220px side navigation for module families, 16-24px content padding, and chart/table sections that align to one vertical rhythm. Avoid alternating unrelated card widths.
- Preserve parent context when drilling from overview to module, module to object detail, or workbench summary to full report. The return path should restore the selected scope, selected module, scroll position when useful, and any meaningful filter.
- Make "all", single object, permission-limited, hidden, unavailable, and stale scopes visibly different. Do not let a missing selector, disabled tab, or zero value carry those meanings silently.
- Pair summary charts with exact tables, exception lists, or object detail links. A large report should answer "what changed", "where", "why this matters", and "what can I inspect next" without forcing the user to compare decorative chart blocks.
- Export and download are report jobs, not bare URLs: the job payload must include routed identity + filter-set + config-version + sheet/data selection + snapshot/generation token (see the "key class" matrix above for the full taxonomy); show current scope, pending state, success target, failure reason, retry, exported-artifact timestamp / staleness disclosure, and authority is re-evaluated server-side at job submission.
- Treat the report list as an analysis entry workbench, not a plain table. A strong list card can combine a date or timeline rail, report type/status tags, title, creator/update metadata, subject/category tags, reference-scope counts, data-coverage counts, and one primary view action. Long titles and long scope lists need measured tooltip/detail behavior; disabled view actions need a local reason instead of disappearing.
- Keep filter state compact and recoverable: year, grade/segment, subgroup, subject/category, report type, keyword, and pagination should have one owner. Cached filters are useful only when validated against the current option set; stale grade/class/subject values must be cleared deliberately.
- Opening a report often branches by authority and configuration, not just by card click. If the user can choose or manage analysis configurations, use a focused selection modal with loading/error/retry, default marker, generating status, edit/default/delete actions, create limit, duplicate-name validation, rule selection, and authoritative refresh after mutation. Non-admin or default-only users should take the shortest valid route.
- Visual treatment for report-list entry should feel like a calm timeline, not a dashboard collage. Use a low-chroma blue-gray page background, white filter/list surfaces, restrained 1px borders, 12-16px panel radius, 8px input/button radius, and compact 28-32px controls so the list reads as a repeated-use workbench. Keep shadows off or extremely subtle; use border, spacing, and hover state for grouping.
- Token provenance for this pattern: primary/action/selected color should map to the product primary token, neutral text should separate title, metadata, and labels, border/surface colors should map to neutral tokens, and status tags should use semantic token pairs for active, hidden, unpublished, custom, homework/task, or cross-scope states. If implementation uses literal colors, promote repeated values into theme variables before reusing the pattern.
- A report card needs one visual rhythm: fixed date/timeline column, small connector or divider, title/tag row, metadata row, optional subject/category tag row, and one right-aligned action zone. Hover/focus may add a primary-tinted border/background, but should not change row height or make secondary metadata compete with the title.
- If the report includes a live explanation, presentation, or annotation mode, split it from the passive analytics page. The explanation mode needs full-viewport artifact focus, stable bottom controls, side item navigation, annotation history, zoom, next/previous, and an exit path that does not destroy the report context. This mode is design-backed when Figma or screenshots show the full-viewport tool surface; the broader report-system rules may be code-backed when the implementation owns list/detail/module/filter/export behavior.
- Visual direction and tokens: keep the report calm and exact. Use semantic status colors for risk/exception/selection, restrained neutral backgrounds for long reading, numeric alignment for comparisons, and tokenized primary/action colors. Hard-coded chart colors need a legend, token mapping, and contrast check.

## Multi-Source Merge Semantics For Composite Analysis

**Scope**: this rule covers positional / aggregate / list composition — i.e. merging sources whose records are matched by *position in structure* or compared *at the aggregate*. Keyed-join composition (sources joined / unioned / intersected on a shared entity/time/foreign key — typical for transaction analysis, experiment cohorts, multi-region rollups) is a separate family with its own contract (inner/outer/anti/semi join on key K + null/dup policy) and is NOT in scope here; route those cases to the backend architecture owner of the analytical service (e.g. `go-microservice-architecture`, `python-service-architecture`, or `llm-inference-integration` for inference-side composition).

For in-scope composition (multi-report / multi-run / multi-survey / multi-form composite analysis), the **merge semantic is a typed contract — three modes — not free-form**. Pick the mode at creation time, surface the source-shape constraint to the user before they commit, and never silently fall back to a different mode. The contract is **server-enforced**, not just client-displayed: the mode, source-shape preconditions, aggregation operators, dedupe/provenance policies, and recomputation rules live in a typed versioned spec that the server validates on every commit and replay — same discipline as the Business Logic Separation rule below (the merge math is business logic, not UI ornament).

- **Aggregate-collapse merge**: sources must share the same aggregate shape (matching aggregate metric id / unit / window). The merged unit collapses to a single aggregate row / record / score. Source structure beyond the aggregate is discarded. Use when the analytical question is about the aggregate ("the total"), not the underlying items. Required typed fields in the spec: **aggregate metric id, unit, window**; **value-composition policy** when source values differ (fail-on-disagreement / first-wins / last-wins / average with stated denominator / weighted-sum with named weight field — never a silent default); **null / conflict policy** (skip / treat-as-zero / propagate-null / fail); and **per-source contribution + provenance** retained for audit replay even though the user-visible result is a single aggregate. Without value-composition policy, two sources with the same aggregate shape but different values collapse silently with whatever the implementation happened to pick — exactly the kind of "looks fine, ships wrong" bug the typed contract is meant to prevent.
- **Isomorphic-structure merge**: sources must have isomorphic structure — same logical fields (by stable field id, not by display order) in the same nesting, with the same item count per nesting level. The merged unit preserves that structure 1:1; each position becomes a composite value derived by an **explicitly chosen aggregation operator** (sum / weighted-sum / average / min / max / count) with explicit **denominator / weighting policy** (whose denominator drives the average — per-source counts, total counts, or weighted by a named field), an explicit **null/missing policy** (skip / treat-as-zero / propagate-null / fail), and an explicit **metric-compatibility check** (cannot average a rate with a count, cannot sum a percentage with a duration). Use when the analytical question is per-position comparison ("how did this item score across runs").
- **Append-concat merge**: sources are concatenated; cardinality of the merged unit defaults to the sum of source cardinalities, but the spec must declare an explicit **overlap / dedupe / provenance policy**: how a record present in two sources is handled (keep-both with `source` tag / dedupe-by-key with chosen winning policy / fail-on-overlap), and how source-of-record is preserved through downstream metrics. "Treated as one larger pool" without dedupe policy is how double-counting bugs ship — and downstream percentages, participant counts, and rate computations silently misreport.

Surface discipline:

- The mode selector is a first-class form field, not a hidden default. Switching modes mid-creation invalidates the source-shape check and must re-validate against the new mode's constraints.
- Source-shape preconditions are validated as soon as source metadata is available, and always re-validated before commit / export / replay. The validation result is a typed error naming which source violates which constraint (which field is missing, which aggregate differs, which cardinality is incompatible); a generic "sources are incompatible" message is insufficient.
- The merged unit's downstream metrics (counts, percentages, participant cardinality, weighted averages) are derived by the server from the typed spec. Show "derived from mode = <X>, operator = <Y>, dedupe = <Z>; modify source set → recompute" cues so users understand a source change re-runs the merge math.
- Persisted merge configs version the full spec (mode + operators + denominator/weighting policy + null policy + dedupe policy + source-shape snapshot). A historical merged analysis viewed later must reflect the spec it was created under, even if the product later offers different modes / operators / policies. Recomputation against the historical spec is the audit replay path.

## Multi-Level Hierarchy Navigation

Analytics surfaces commonly ship multiple hierarchy levels (per-row / per-group / per-tenant / per-org / per-federation) of the same module. Navigation can vary by level and that is fine, but the variance must be a product decision, not an accident.

- **Choose the navigation paradigm per role, not per developer preference.** Roles that visit the report frequently and want to browse top-to-bottom (typical front-line user view) are well served by an in-page anchor-scroll group: one viewport, all modules stacked, side menu acts as a scroll-spy with URL-synced anchor. Roles that visit less frequently and inspect a specific module (typical management view) are well served by a leaf menu that routes to module-only views.
- **Same module key, different label per level is acceptable; same label, different key is not — and key shape varies by key class**. A module computed by the same formula should carry the same metric identifier across levels even when the display label differs (the level changes what one row means; the underlying comparison is the same kind of comparison). What must NOT happen is using the bare metric identifier across every key class. The five key classes have distinct required shapes:
  - **Routed identity — route, deep-link, export filename**: minimum tuple `(moduleInstanceId | metricId, level, scope, report, tenant, schema-version)`. This is the identity surface that travels in URLs, shared links, and downloaded-artifact filenames.
  - **Export job payload / server-side data request**: routed identity above PLUS the data request parameters — `filter-set`, `config-version`, sheet/data selection, and a server-side snapshot or generation token. An export job that omits filter-set/config-version produces a downloaded artifact that does not match the visible chart/table state. Authorization on the job payload is server-side, not derived from the routed identity.
  - **Data cache key (server response cache, in-memory store)**: `(sheetType | moduleInstanceId | metricId, report, level, scope, filter-set, tenant, schema-version, config-version)`. Cache identity must include `sheetType`, `filter-set`, and `config-version` because the same metric and same level resolve to different server responses under different filters or rule configs.
  - **Local persistence key (per-user filter / comparison target / last-selected module)**: `(userId, tenant, report, level, scope/resource, schema-version, surface-version)`, plus `metricId | moduleInstanceId` where the persisted value is module-specific.
  - **Analytics event taxonomy**: the exception. Event names / event-taxonomy keys stay stable and low-cardinality (`metricId` plus a small enumerated dimension set, e.g. `level=class|school|union`). ALL high-cardinality identifiers — `tenant`, `report`, `userId`, `scope` / `resourceId`, `moduleInstanceId`, subject/object ids, free-form session ids — belong only in first-party correlation dimensions, hashed/salted/omitted per the data-handling policy. None of them is ever baked into the event name itself. Per-tenant cardinality blows up the analytics warehouse and may leak tenant or user identity downstream; the rule is "if it has more than O(10) possible values across the population, it is a correlation dimension, not a taxonomy key."
  Define `metricId` (shared across levels, used in formulas, labels, analytics taxonomy) separately from `moduleInstanceId` (per-level, used in routing, cache, export, persistence). A bare metric id used as any of the routed / cache / persistence / export-job keys collides across levels or instances.
- **The shell visibly identifies the current level**. A user dropped into a module by deep link must see the level (chip / breadcrumb / scope bar entry) before scrolling to a chart, otherwise the same chart's numbers are ambiguous.
- **Inter-level navigation preserves scope, not just the page.** Drilling from a per-group view to a per-row view should carry forward the active filter set, the selected module, and the scroll/anchor when useful — and "return" should restore them, not just navigate back.
- **Permission shape changes by level, and the visible permission gate stays in one place — but the decision key is the full tuple, and mutation must re-authorize.** Higher-level views typically have read-only roles for managers and read+edit roles for owners. The "edit rules" / "export" / "publish" affordance visibility should be decided in one centralized gate so per-module surface stays consistent. The decision key for that gate is `(action, level, scope, resource)`, not action alone — collapsing it silently widens the surface (a user with `export` at the parent level should not get `export` affordances inside a leaf-level view they cannot actually export). The centralized visible gate is for UX consistency only; every `edit-rules` / `export` / `publish` submit MUST re-authorize against the server/API on submit, since client gating is bypassable. Submenu modules read from the shell gate, they do not invent parallel checks.
- **Two navigation paradigms in one product are acceptable; two paradigms in one level are not**. Mixing in-page anchor scroll with leaf-menu module routing inside the same level creates a UX where users cannot predict whether clicking a menu item scrolls or navigates. Pick one per level.

## Business Logic Separation From UI Copy

Analytics surfaces accumulate inline business explanations: parameter ranges (e.g. "metric M ∈ [0,1], higher means …"), threshold bands (e.g. "≥T_high excellent, T_mid–T_high good, …"), and applicability constraints (e.g. "this rule does not apply to <segment X>, so <control Y> is hidden"). When these explanations live as long `tooltip="…"` strings or `title="…"` text directly inside component JSX/templates, every business-rule change forces a code redeploy.

- **Business formulas, thresholds, level bands, and applicability constraints belong outside the component — and the external store needs versioning, audit, and server-side enforcement**. House them in a per-domain spec module (an i18n file, a YAML/JSON config, a content-management entry, or a server-served metadata blob) and let the component reference the entry by key. The component renders the explanation; it does not author it. But pulling business rules out of code without a contract is its own footgun: a domain owner edits a threshold in a CMS, the client hides a control or explains a different formula, while the server is still enforcing the old rule (or none) — and now the displayed explanation is unauthorized prod logic. The external store must (a) be typed and versioned so a client cached against schema version N rejects an entry written under schema version N+k, (b) ship with an audit trail of who changed what when, (c) enforce the rule server-side as the source of truth (the client only displays what the server applies), and (d) sanitize any user-authored text fields before render. Migrating from "code-owned business rule" to "config-owned business rule" without these is changing the surface but not the safety story.
- **Threshold bands are first-class config**. A band like "≥T_high excellent / T_mid–T_high good / …" is not a tooltip string; it is a typed config array `{label, min, max}[]` whose tooltip is derived. Storing it as a string forces every reader (including future engineers) to parse it from prose.
- **Localization-readiness ≠ extracted-to-i18n**: text moved out of JSX into a translation file is necessary but not sufficient. The translation file must structure the entry so the source-of-truth maintainer (a domain expert, a PM, a designer) can edit it without reading code — i.e. break per-section paragraphs, label each value, separate copy from formula.
- **Inline copy in the design source is fine for designer-authored guidance**; inline copy in the implementation is an indication that the rule never made it out of the design hand-off into a maintained spec. When extracting evidence from a design file annotation (e.g. a TEXT layer that reads "this rule does not apply to non-high-school grades"), check whether that constraint exists in code as a typed condition or only as a hard-coded branch — the latter is the smell.
- **Avoid letting display-only state become business state**: a per-user UI knob (column visibility, color preference, chart-vs-table toggle) is local UI state, not a rule. Conflating it with the business rule layer is how user preferences accidentally start gating data correctness.
- **Business prose templates that interpolate HTML are XSS-class problems, not just maintenance debt**. A helper that returns paragraph strings combining business prose, hardcoded thresholds (e.g. an inline percentage literal), and `<span>${rawApiValue}</span>` interpolation — then rendered via `dangerouslySetInnerHTML` — turns every contributing field into an XSS sink unless every contributing field is server-trusted and HTML-sanitized. The threshold is harder to spot than a tooltip threshold because it sits inside a narrative sentence rather than next to a typed config. Fix on three axes simultaneously: (a) render the template as React nodes (not strings), so interpolated values are React text content, not HTML; (b) externalize the prose to a typed spec with named placeholders (`{metric1}`, `{metric2}`, `{listValue}`); (c) each placeholder's value source is audited for HTML safety at the boundary, not at render time. **Defining the lint target narrowly is unreliable.** The same bug class hides under destructured API values, renamed local variables, `array.join('…')` into markup, i18n rich-text helpers (`<Trans>` with component slots), Markdown / HTML renderers, CMS-authored template strings, and any other path that composes a string containing markup plus dynamic placeholders and hands it to an HTML-capable renderer. The lint target is: any HTML/Markdown/rich-text string composition that mixes markup tokens with dynamic placeholders and reaches an HTML-capable sink (`dangerouslySetInnerHTML`, `innerHTML`, a Markdown/HTML renderer, an i18n rich-text helper). Default behavior at the sink is text-rendering of every placeholder; intentional rich HTML requires an explicit reviewed allowlist with a typed source and a sanitization step.

## Insight States

Map the canonical taxonomy in `product-surface-patterns.md`, then add analytics-specific states:

- No scope selected.
- No permission for this scope.
- No data in selected range.
- Partial data.
- Stale data.
- Loading chart.
- Loading detail list.
- Comparison target missing.
- Benchmark unavailable.
- Too little data for reliable interpretation.
- Drill-down selected.
- Export pending/success/failed.
- Data updating or unreliable.
- Table horizontal/vertical scroll with fixed header or fixed action column.

## Community Translation

Use this pattern for:

- Creator analytics: post performance, follower growth, engagement quality.
- Topic/community health: activity, retention, contribution mix, moderation pressure.
- Content performance: reach, interactions, saves, shares, comment quality.
- Trust/safety: report rate, mute/block clusters, moderation queue quality.
- AI quality: suggestion acceptance, regenerate/edit rate, source usage, failed generation.
- Notification effectiveness: delivery, open, return, action after return.

Do not make relaxed feed/detail pages look like analytics dashboards.

## Acceptance Checklist

- The chart answers a product question, not just fills space.
- Active filters and comparison targets remain visible.
- Every chart has source/scope/timestamp or a nearby definition when trust matters.
- Empty, partial, stale, permission-limited, and too-little-data states are explicit.
- Users can reach the underlying items from important aggregate views.
- Drill-down and back navigation preserve context.
- Mobile analytics avoids desktop-like dense tables.
