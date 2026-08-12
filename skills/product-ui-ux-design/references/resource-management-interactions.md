# Resource Management Interactions

Use this reference when designing or implementing resource libraries, cloud-drive style asset centers, media/template management, reusable knowledge sources, saved prompts, or content-pack management.

Source provenance lives in `source-map.md`. Reuse the asset-management mechanics, not the original source-domain vocabulary.

## Core Pattern

A resource center is a managed inventory, not a passive file list:

- Users need to find, preview, trust, reuse, publish/share, update, and recover resources.
- Navigation, ownership, status, and actions must stay visible at list density.
- Upload/import is part of the resource lifecycle and needs the same care as browsing.
- Resource identity should survive preview, replace, move, publish, archive, and batch operations.
- Classify mixed sources by section or frame, not by file name. Current mainline frames can be positive visual and interaction evidence, while sections marked "reference", "to optimize", "old version", or similar should be downgraded unless code or current frames confirm them.

## Information Architecture

- Use a stable left tree, category rail, or workspace selector when resources have durable hierarchy.
- Use top-level tabs or segmented controls for major availability states: personal/private, shared, pending publish, published, platform/library, team/workspace, archived.
- Keep search, filters, sort, create/upload, import/export, and batch actions in a predictable toolbar.
- Do not split closely compared resource states into unrelated pages; use tabs and filters when users repeatedly compare them.
- Show active category/filter state near results so the current scope remains clear after scrolling.
- For deep libraries, keep the left tree and the result toolbar independent: tree controls scope, tabs/filters control state, and sticky filter bars preserve the active query after scrolling.
- For desktop asset workbenches, use a stable shell: global navigation, a 240-280px hierarchy rail when the taxonomy is deep, a compact filter block, and one dominant results/preview region. Keep the active scope, resource type, and availability state visible at all times.
- For mainline desktop resource workbenches, keep the shell dense and operational: a narrow global nav, a left resource rail around 184-280px when needed, a main work area around 1200px at 1440-class width, 32-40px top controls, compact tabs/dropdowns/search in one control band, and list/card content below. Avoid hero spacing, oversized empty panels, or decorative cards that reduce scan density.
- Sticky filter mode should compress, not disappear. Preserve the current query, show the compressed state, expose clear/reset and expand actions, and avoid moving the result list when the filter collapses.
- Treat scope, sub-scope, resource type, hierarchy node, filter mode, search query, and selected item as separate axes. Do not merge them into one tab set or one query object unless the implementation still clears stale dependent state deliberately.
- For heterogeneous search results, keep result types visually separable through columns, sections, or tabs. Use a compact search result header, keep filters near the result type, and show the active query, active scope, no-result state, and return path so users do not lose whether they searched the full library or one resource family.
- Directory and taxonomy management needs its own interaction model: empty tree, selected node, add/edit/delete, reorder, max-depth or max-count limits, read-only nodes, nodes with children, nodes already used downstream, rename conflict, unsaved edits, cancel, save, and restore to the affected node after refresh.
- Directory finalization should not be a blind submit. If some leaf nodes are unbound, disabled, hidden by current filters, or no longer valid after refresh, show the affected scope and require explicit continue/cancel. Preserve the selected collection, volume or tab, and return focus to the invalid node or refreshed node after the operation.

## Resource List And Card Rules

Every list row or card should expose enough identity for confident reuse:

- Name/title, thumbnail or type icon, resource type, source, owner, visibility, status, updated time, and primary usage signal.
- Compact row actions for preview, use/import, share/publish, edit, move, duplicate, download/export, archive, and delete where relevant.
- Badges for generated, imported, shared, pending, published, archived, private, failed, and unsupported states.
- Tags describe attributes; do not overload tags as filters, permissions, and workflow status at the same time.
- Long names and dense metadata must wrap or truncate predictably without hiding status or primary action.
- Repeated resource actions should use stable placement: preview/use/open first, then edit/replace/share/download, then archive/delete. Do not make users rediscover actions per card state.
- Cards that represent in-progress generated/imported resources must make "still processing", "failed", "retry", and "continue editing" visibly different from complete resources.
- Status labels need an authoritative vocabulary. Do not create ad hoc chip colors or mixed terms per screen; define which labels are workflow states, source/type labels, availability labels, and user actions.
- Selection baskets or temporary collections should show count, item identity, remove/clear, stale or unavailable items, disabled commit reasons, and the final action. A floating basket is a commitment surface, not decoration; for dense desktop, use a narrow vertical entry plus a drawer sized to content complexity. A compact metadata basket can use a 480px-class drawer, while rich question/media previews may need a wider 760-820px-class drawer.

## Upload, Import, And Parse States

Treat upload/import as a first-class workflow:

- No category selected, selecting files, uploading, uploaded, parsing, preview available, completed, unsupported type, failed parse, partial success, duplicate detected, and retrying.
- No directory/category available, directory maintenance required, or missing upload destination should be explicit states rather than hidden validation errors.
- For batch import, show per-file status and summary counts.
- For AI knowledge sources, show source file, parse status, freshness, visibility, and whether the resource is usable by AI.
- If a resource can be replaced or swapped, show before/after identity and preserve a cancel path until commit.
- Permission denied or quota full should explain the blocked capability and the available next action.
- AI parsing or enrichment needs a real waiting state, not just a spinner: show what is being processed, what action would interrupt it, whether retry is possible, and where the user returns after success.
- Save-to-library from a lightweight capture or H5 entry is not the same as a full library surface. The lightweight flow should validate destination metadata and commit status; the full workbench owns search, hierarchy, sharing, editing, and lifecycle management.
- Creation entry should first dispatch by resource type, because file support, metadata, parse path, editor handoff, and post-save landing can differ by type.
- Metadata forms should cascade rather than accumulate invalid state. When a parent field changes, clear incompatible child fields, tree selections, type filters, and derived IDs; show required-field blockers before upload or parse starts.
- Long-running parse jobs should expose submit, parsing, background/continue, completed, failed, retry, reupload, and cleanup-on-close states. Polling timers or subscriptions must stop when the dialog unmounts.

## Preview And Detail

- Use drawers or side panels for quick details; use large preview or full-screen mode for media, documents, or rich artifacts.
- Keep return navigation obvious. Do not rely on browser back for core resource flow.
- Detail views should show metadata, history, usage, permissions, related resources, and destructive actions.
- Preview should make public/private or shared/published consequences visible before use.
- For generated or AI-derived resources, expose source/context and review status where trust matters.
- Rich resource preview should preserve object orientation. When a preview has an outline, page list, chapter tree, question list, media strip, or related-detail rail, selection in the rail and position in the main preview should stay linked; hover/click/focus states should tell users which child item is being inspected before they reuse, edit, download, or share it.
- Download/export settings are decision dialogs, not passive confirmations. Group output format, visibility of sensitive fields, page/layout preset, and output variant; show selected state clearly; keep cancel and commit fixed at the bottom.
- Long-running downloads or exports need a visible task surface: queued/running, finished, failed, retry/download action, file identity, retention window, and empty state. Do not make users guess whether a generated export is still being prepared or already expired.
- Edit/replace flows should preserve user orientation: identify the current item, allow inline edits for small fields, cap rich text/editor height with local scrolling, and confirm destructive removal of parent items that would delete children.
- Tag or metadata editing should distinguish generated/default metadata, user-edited metadata, locked metadata, and metadata already used downstream. If a resource has been used in another workflow, make editability and consequences explicit.

## Permissions, Sharing, And Publishing

- Distinguish ownership from availability: owner, editor, viewer, team/workspace, public/published, platform/library.
- Permission or publish changes should show before/after impact and affected scope.
- Batch changes must show selected count, affected categories, and irreversible consequences before commit.
- Archive is preferable to delete when recovery or audit matters; delete requires explicit confirmation.
- Shared resources need conflict handling: already exists, newer version exists, missing permission, or cannot overwrite.
- Sharing dialogs should show both the target availability scope and the resource attributes being shared. Disable commit until the required scope is selected, and make unshare/cancel-share a separate explicit action.
- Shared-state buttons need two distinct modes: an unshared action that opens the scope/attribute confirmation flow, and a shared state that exposes cancel/unshare without reopening the create-share flow. Refresh the authoritative shared state after either operation.
- Permission-limited metadata should render as read-only rather than disappearing. This prevents users from thinking the resource has no metadata and protects trust in shared libraries.

## Responsive And Hosted Boundaries

- A desktop resource workbench can be hosted inside a mobile app shell only when the host contract is explicit. If the mobile H5 only provides a save or entry action, do not pretend the full library is mobile-optimized.
- Hosted resource flows must account for safe area, injected app info, native/web storage availability, page-ready handoff, back behavior, orientation, and weak network recovery.
- For narrow desktop or tablet stress widths, collapse secondary panels and advanced filters before shrinking the main preview or list below readable width.
- Verify 1280-class and 1440-class desktop widths separately. At 1440, the workbench should show global navigation, active resource scope, controls, and usable results together. At 1280, secondary text/actions may compress or move into overflow, but the active scope, search/filter entry, primary list/card identity, and primary action must remain visible.
- At 1280-class width, preserve the left rail and primary content before preserving every secondary control. A workable pattern is roughly 184px navigation plus a 1060px-class content region with compact 30px tabs and a single-line divider/header.
- For mobile-first asset management, prefer task-specific entry flows, saved/recent lists, and detail/edit sheets over copying a dense desktop left-tree workbench.

## Community Translation

- AI cloud drive -> creator asset library, AI knowledge base, saved prompt library, reusable media pack, moderation evidence library.
- Resource center -> topic templates, content-pack marketplace, onboarding assets, creator kit, community rule library, event materials.
- Replace/swap -> change source media, update template, refresh AI context, replace cover/banner, revise reusable content block.
- Publish/share -> make asset available to collaborators, community members, creators, moderators, or AI workflows.

## Acceptance Checklist

- Users can tell where they are, which resource scope is active, and what actions are allowed.
- Search/filter/sort remain available at list density.
- Upload/import/parse has item-level progress, failure, retry, and partial-success handling.
- Resource identity, ownership, visibility, status, and usage are visible before reuse.
- Preview, replace, share/publish, archive, and delete each have clear confirmation or recovery behavior.
- Tags, permissions, and workflow states are visually distinct.
- Download/export settings expose the consequences of selected format, visibility, layout, and output variant before commit.
- Hosted or H5 entry flows state their boundary: save/capture entry versus full resource workbench.
- Directory edits and resource creation can be completed, cancelled, retried, or resumed without losing the current library context.
