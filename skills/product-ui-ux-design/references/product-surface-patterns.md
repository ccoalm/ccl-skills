# Product Surface Patterns

Use this as the canonical product-surface taxonomy for the organization UI/UX skill. Scenario references such as community, finance/data, AI workspace, mobile, and operational workbench add domain-shaped examples, but this file owns the generic state and surface model.

## Surface Model

- Consumer discovery: browse, search, feed, detail, profile, recommendation, and return loops.
- Creation and editing: draft, validate, preview, generate, upload, save, publish, discard, and recover.
- Decision and review: inspect evidence, compare options, see provenance, accept/reject, annotate, export, or escalate.
- Operational workbench: scope/filter, queue, input/control region, review/output region, status strip, history, assignment, and recovery.
- Account and settings: onboarding, consent, login, verification, profile, privacy, notification, billing/quota where relevant, and destructive account actions.
- Analytics and data: overview, drilldown, comparison, dense table/chart, saved view, data freshness, permission scope, and export.
- AI-assisted surfaces: prompt/input, generation, streaming/progress, citation/source, edit/review, regenerate, save/publish, refusal/degraded state, and accountability metadata.

## Canonical State Taxonomy

For every product feature, map these states before implementation or acceptance:

- Empty: first visit, no data, no permission-scoped result, no search result, no configured source.
- Loading: initial load, pagination, refresh, upload, generation, export, background sync, or long job.
- Slow or weak network: delayed first feedback, retryable fetch, stale cache, degraded media, timeout, or queued state.
- Partial: some data exists but media, source, permission, generated content, or dependency failed.
- Error: network failure, validation failure, permission denied, upload/export failed, backend refusal, provider unavailable.
- Disabled: unmet requirement, missing permission, unsafe state, invalid input, pending dependency, unsupported platform.
- Success: saved, submitted, published, exported, generated, followed, approved, completed, or applied.
- Reversal/recovery: undo, cancel, retry, restore, discard, rollback, leave, return to prior context.
- Trust/risk: destructive, public, costly, permission-sensitive, privacy-sensitive, money/quota-sensitive, AI-generated, compliance-like, or support-traceable action.

## Product Loop

Use this default loop unless the product has a stronger one:

1. Enter or discover the surface.
2. Inspect current scope, data, content, or evidence.
3. Act with visible primary and secondary options.
4. Confirm only when consequence, cost, public visibility, privacy, or irreversibility requires friction.
5. Recover or return with context preserved.

## Scenario Lenses

- Community/social: use `scenario-community-patterns.md` for feed, creator, interaction, topic, notification, moderation, and social loop specifics.
- Education: when the target product is explicitly education, map learning/teaching/assessment/resource workflows intentionally; source education terms may be used only when they match the target product context.
- Finance/data/trust-sensitive: use `trust-sensitive-ai-and-data-patterns.md`, `analytics-visualization-interactions.md`, and `operational-processing-workflows.md` for evidence, provenance, dense analysis, permission, and review-before-action patterns.
- Mobile/app: use `platform-mobile-patterns.md` and app implementation skills for safe area, keyboard, orientation, native shell, and device acceptance.
- Web/workbench: use `platform-web-desktop-patterns.md` and `layout-recipes-and-screenshot-acceptance.md` for shell, density, responsiveness, and screenshot acceptance.
- Mini-app: keep design criteria here and route host/page, permission/capability, package/platform, device, and web-view bridge evidence to `miniapp-product-dev`.
- Ordinary CLI or terminal/TUI: keep product hierarchy, command semantics, states, and acceptance here; route command/help/default/exit/recovery, terminal geometry, fallback, input, and real-terminal evidence to `terminal-cli-dev`.
- Other Web and Electron/desktop/TV: React content routes to `web-react-dev`; Vue/Svelte/static/vendor/other content and shell layers route to their installed owner or the fail-closed project-convention lookup in `delivery-contract.md`. Composite hosts keep separate content and shell members.

## Workflow Surface Extensions

Use these generic workflow patterns when a product surface needs more than a simple page/detail/form. They replace source-specific formal product references; exact old business terms stay in provenance only.

- Dense creation/import: source choice, upload/import, parsing or matching, manual correction, validation, preview, confirmation, save/publish, and recovery.
- Structured editing: tree or outline plus selected-node editor, explicit add/move/split/merge/reorder/delete actions, bulk selection count, and status tags for missing/generated/verified/conflict states.
- High-throughput review: persistent task identity/progress/filter header, artifact-dominant center, compact side or bottom controls, previous/next, annotation, final confirmation, failed media retry, and queue-end recovery.
- Upload/processing pipeline: no source, upload, server processing, preview, completed, unsupported, failed, retry, and separate local-transfer versus server-processing state.
- Analytics/report: stable filter bar, decision-driving metrics, chart plus inspectable table/list, drill-down path, comparison labels, permission/partial-data states, and export/share where useful.
- Management list: search, filters, status tabs, batch action, import/export, create action, dense identity/status rows, side preview, and destructive or high-commitment modal.
- Progress/quality monitoring: separate "how much is done" from "how good or risky it is"; support pivots by item, owner, group, status, and exception.
- Assignment/ownership: separate unit setup from owner assignment, show unassigned/partial/assigned/in-progress/locked/completed/read-only states, and summarize affected scope before bulk apply.
- Role owner configuration: when a product object needs different owner groups by unit, role, permission, or processing mode, show object context, role columns/cards, existing owners, add/edit/reuse actions, and empty-role affordances in one compact workbench. Long owner lists should summarize counts with full tooltip/details; reuse/copy must show the target scope and exclude the current source by default.
- Owner selection drawers: title the drawer with the current unit and role, separate candidates from the selected list, keep selected count visible, support search and cascade filters, show qualification/relationship metadata beside each candidate, use all/partial selection states, and let users remove selected people from the selected area. A large or multi-tenant candidate list may use a tree, but leaf identity, disabled reason, and removal behavior must remain obvious.
- Permission exception lists: treat early-access, blocked-access, and other exception owners as explicit risk lists, not normal ownership roles. The UI should explain when the exception takes effect, what output or action it changes, whether the permission survives lifecycle transitions, and how to undo it.
- Resource/asset center: stable category rail, main list/card area, search/filter/sort, upload states, preview/full-view, ownership/availability status, and before/after identity for replacement.
- Post-publish correction: restricted access, audit, original versus corrected values, dependent-output impact, confirmation, and reversible or support-traceable paths.
- Entity tracking/comparison: support single-entity and all-entity modes as siblings, keep baseline/comparison visible, pair trend charts with exact row/detail evidence, preserve drill-down context, and label current/previous/target/benchmark directly instead of relying on color alone.
- Configurable project or event management: split creation, editing, viewing, and post-publish management; keep list actions near the table toolbar; progressively reveal dependent settings; support save-after-edit and view-only states with the same layout; preview reused template data before it replaces current values; confirm destructive lifecycle actions with specific consequences.
- Lifecycle object management: when an object moves through multiple operational phases, the list item should show identity, scope, status, permission-relevant tags, and the next executable phase together. Model each workflow variant with its own phase labels and action states, including not-started, available, hover/pressed, in-progress with percent where useful, paused, completed, exception, no-permission, and disabled-with-reason.
- Lifecycle management actions: separate high-frequency actions from high-risk actions. Detail, edit, member/owner management, progress inspection, notification/publish, export, and check/recalculate actions can live in an overflow or drawer entry; pause/resume, end/reopen, delete, overwrite, and publish/unpublish need consequence copy, scoped confirmation, pending state, success refresh, and a visible return to the originating item.
- Creation and configuration drawers: complex creation should not be a single flat form. Use mode selection first, then reveal dependent fields, batch-versus-per-item settings, member/scope selection, optional templates or reuse, and help/documentation entry only where it supports the current decision. Once downstream records, processing, or published outputs exist, mode and scope controls become locked or conditionally editable with a local reason.
- Participant or membership rosters: treat roster management as its own workbench, not a subform. It needs tabs or segments for whole-object versus per-unit scope, cascade filters, search, missing-required toggle, count summaries, single add, batch import, reuse, template creation, export, batch delete, and deletion locks after downstream processing starts.
- Roster identity and numbering: when members need local identifiers, seats, slots, groups, or access codes, expose generation/copy-from-source modes, minimum and maximum length or format constraints, overwrite consequences, newly-added-only versus all-member scope, optional auto-download/export after generation, and downloadable repair lists for invalid records.
- External roster sync: when current membership can be refreshed from an authoritative external source, show a preview-before-apply drawer with added, removed, and changed rows grouped by scope. The preview must state whether it is informational only or actually applies the change; the apply action needs overwrite copy, scoped selection, pending state, and post-apply refresh.
- Roster reuse and templates: reuse should be a two-step flow: searchable source/template list, then preview with metadata, per-unit tabs if applicable, counts, sticky member table, delete-template action when allowed, and explicit overwrite confirmation before applying. A successful reuse should state that out-of-scope members were filtered instead of implying a blind copy.
- Automated roster import and identity repair: when a roster comes from file import, external sync, recognition, AI extraction, or generated identifiers, keep automation accountable. Show required scope before import, source/template download, upload and server-processing states, successful file identity, reupload, error report download, invalid-identity repair instructions, and a post-repair return action. Do not make a toast the only place users learn that imported or generated identities failed.
- Roster scope inheritance: when a sub-scope inherits a whole-object roster, show the inheritance note near the scope tabs and make the edit path explicit. If users switch a sub-scope to independent membership, warn which future imports, generated identifiers, templates, and external sync actions will affect only that sub-scope.
- Notification and publish settings: distinguish enablement, automatic/manual mode, recipient or role scope, content/template choice, preview/sample where the outcome is hard to infer, read-only inherited settings, and cancel/unpublish states. A publish scope change should summarize exactly who or what can see the output after confirmation.
- Check/recalculate operations: a "check" action that triggers computation is a lifecycle transition. Show when prerequisites are missing, when computation is already running, when output is ready to view, and when the calculation state is abnormal. Polling or refresh should update the originating item, not leave the user guessing from a toast.
- Object list import and repair: separate single add, batch import, reuse, preview update, and export; validate invalid, duplicate, missing, and unmapped rows before commit; provide templates for strict formats; preview ambiguous identity matches; keep selectors/tabs stable across scope changes; do not silently clear unsaved data.
- Drawer and modal repair patterns: place global drawer alerts directly below the title when they affect the whole drawer, use consistent side padding, avoid nested rounded alerts that fight the container, and keep sibling title bars visually consistent.
- Workflow conflict rules: prefer design-system tokens over local product exceptions unless repeated current sources prove the exception; preserve platform-specific behavior when mobile and desktop differ; keep newer/current sources over archive/backup; merge repeated patterns with different labels into generic rules; treat image-only patterns as weak evidence unless confirmed elsewhere.
