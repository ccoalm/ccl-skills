# Complex Creation Interactions

Use this reference when designing or implementing a real, high-friction creation flow: upload/import, AI-assisted draft extraction, structured editing, matching, manual correction, preview, publish, or export.

Source provenance lives in `source-map.md`. Use this reference only for interaction mechanics, not source-domain workflow.

## Core Value Extracted

The strong design idea is not "a wizard." It is a **recoverable structured creation system**:

- Users can start from multiple sources: blank, manual input, template/library reuse, upload/import, or AI-assisted generation.
- The system makes intermediate machine work visible: upload, parse, match, classify, extract, generate, and validate.
- Users can correct machine output before it becomes final.
- The product preserves structure, progress, counts, and save state while users perform complex edits.
- Commit/publish/export is a separate decision after review, not an accidental result of editing.

## Interaction Model

Use this sequence for complex creation:

1. **Choose source**: blank/manual, upload/import, template/reuse, AI generation, or existing draft.
2. **Ingest**: upload, paste, connect, capture, or select source material.
3. **Process**: parse, classify, match, generate, deduplicate, or extract structure.
4. **Review structure**: show groups, sections, items, metadata, missing fields, conflicts, counts, and confidence.
5. **Manual correction**: edit fields, split/merge, reorder, tag, relabel, delete, add, reset, or re-run part of the process.
6. **Configure output**: visibility, format, grouping, length, audience, publishing settings, or downstream behavior.
7. **Confirm**: summarize what will be created, changed, published, exported, or invalidated.
8. **Return loop**: saved draft, published result, retry path, or next creation.

Do not hide processing or correction inside a single loading state.

## State Requirements

Map the canonical taxonomy in `product-surface-patterns.md`, then add creation-specific states:

- No source selected.
- Source selected but not uploaded/imported.
- Uploading or ingesting.
- Processing/parsing/generating.
- Parsed empty result.
- Parsed partial result.
- Conflict or unmatched items.
- Manual correction in progress.
- Unsaved local edits.
- Saved draft.
- Ready to publish/export.
- Publish/export in progress.
- Published/exported.
- Failed upload/process/publish/export.
- Re-upload or replace source confirmation.
- View-only or locked after downstream use.
- Source structure selected but not yet confirmed.
- Machine match finished with unmatched/conflicting items.
- Split/merge/reorder mode active.
- Preview/confirmation shows downstream layout or generated artifact before commit.

## Structured Recognition And Correction Workspaces

Use this when a user creates an object by importing source material that must be validated, processed, matched to structure, corrected, and saved. This is heavier than a normal form: it is a recoverable workbench for uncertain input.

Execution recipe:

- Source choice must distinguish start, continue, replace, reuse, and unsupported source. If replacing the source invalidates previous work, ask for confirmation and state what will reset.
- Step phases must own real state: source settings, upload list, processing task, structured correction, draft autosave, final save, and downstream preview/export.
- Upload should validate before work begins: file type, count, size, dimensions or aspect constraints, duplicate/invalid items, and source-specific limits. Keep preview, reorder, rotate, delete, and retry available when those actions matter.
- Processing should be a durable task with visible pending text, polling or subscription state, success, failure, stale task, retry, and safe return after navigation. Do not hide recognition behind a toast.
- Machine output is provisional. Show unmatched, conflicting, missing, duplicate, or low-confidence structure near the action area and provide a direct correction path.
- Correction mode should be explicit: drawing/selecting regions, splitting, merging, moving, tagging optional/extra parts, bulk configuring repeated items, or editing a rule matrix should each lock unrelated controls and show how to exit.
- Canvas/image/PDF correction needs zoom, pan, reset, selected-region labels, handles/anchors, and cleanup of dependent derived data when a region, item, or group is deleted.
- Drag-and-drop structure editing needs cancellable drag, restore-on-cancel, valid target rules, maximum-depth or nesting limits, and clear warnings when a move is blocked.
- Validation should block final save for missing names, missing mapped regions, invalid counts, zero/invalid rule values, unresolved duplicates, and ambiguous base settings. Show both global count and local field errors.
- Autosave and final save are different decisions. Autosave should preserve draft correction without implying the object is ready; final save/export should summarize consequences.
- Once downstream work starts, show locked or partially editable state instead of letting users silently change upstream structure that downstream data depends on.
- Preview before commit when the output has layout, file, downloadable, or downstream operational consequences.

### Source-Material Creation Workbenches

Use this variant when the source is a document, image set, scan, imported file, or existing template that must become a structured editable artifact. The source can be blank/manual, reused, uploaded, scanned, or AI-recognized, but the workbench should preserve the same mental model: source material is uncertain until reviewed.

Execution recipe:

- Start with a source-choice layer, not a single upload button. Separate blank/manual creation, file recognition, scanned/image recognition, reuse, and existing-draft continuation. Show what each source will preserve, reset, or generate.
- Treat source settings as part of recognition quality. Page size, column count, identifier style, file count, file type, image dimensions, source order, rotation, and template compatibility should be visible before processing begins.
- Keep source acquisition and structure review visually connected. A good layout uses a stable header/stepper, a central source or artifact canvas, a compact structure list, and an inspector/action area. The user should not lose the source when correcting the extracted structure.
- For multi-page or multi-image input, show page thumbnails, order, delete, rotate, invalid-size warnings, and page labels before the user commits recognition. Reordering is a semantic action, not decoration.
- For document/PDF/image input, choose an explicit representation after parsing: rich text/HTML editor when the parser produced editable content; image-canvas mode when the source remains page images. The user should understand why the current mode supports text editing, region drawing, or only preview.
- Recognition progress needs a durable state: pending, processing, success, failure, discarded/stale, retry, and safe return after navigation. If a process tab, task row, or resumable route exists, keep it visible.
- Review should expose both global quality and local repair: total item count, duplicate or non-continuous names, unmatched/conflicting regions, missing required fields, and direct actions such as draw region, split, merge, move, relabel, or add item.
- Region or coordinate matching is a first-class correction mode. Provide selected-region labels, zoom/pan/reset, page/image context, hover/click linkage between structure list and source, disabled states for non-editable region types, handles for resizing, and cleanup of derived coordinates when items move or are deleted.
- Structure editing should make invalid moves impossible or recoverable: collapse/expand during drag, restore on cancel, valid targets, depth limits, target-state feedback for default/hover/selected/disabled rows, and explicit move-to-child or split-to-new-group actions.
- Splitting or regrouping needs a confirmation surface that shows where the new group will be inserted, which target group or item is selected, and whether confirm is currently valid. Preserve cancel as a safe exit from the structural mode.
- Missing-source matches need local repair calls, not a global warning only. Show the missing count or affected item near the source/structure area and provide a direct "go draw/map/select" action that enters the right correction mode.
- When a source has both primary content and supplementary content, keep their identity separate. Supplementary images or documents can use the same source-canvas mechanics, but they may have different editability, clearing, preview, and final-save consequences.
- Reupload/reparse is destructive enough to require confirmation. The confirmation should name which extracted parts, manual edits, regions, answers, annotations, or derived data will be cleared and which source or structure will remain.
- Autosave preserves work-in-progress; final save/export/publish confirms consequences. Keep "saved draft" and "finished" visually distinct, especially when downstream scanning, review, analytics, billing, publication, or operations will depend on the artifact.

### AI Source-Choice Lifecycle Entry

Use this variant when an existing object has a lifecycle action that can start from multiple source modes, including AI recognition, reuse, blank/manual creation, imported files, or library assets. The key pattern is a source-choice state machine attached to the object row or process step, not a separate AI page.

Execution recipe:

- Treat source availability as server-owned capability. The UI should request allowed source modes at action time, filter unavailable modes, and explain blocked modes through permission, lifecycle, or feature-state copy instead of showing dead options.
- Separate first start, continue, view/edit, and switch-source actions. Button labels and placement should reflect the current artifact state rather than using one generic "create" action.
- AI recognition modes must state the input form and generated artifact type before start, then route users to a review/editor surface after the recognition task creates the draft. Recognition is not the final commit.
- If the user switches source after generated or manually edited work exists, require a consequence confirmation that names what will be cleared or regenerated. After success, show a visible reset/success state and route to the new source flow.
- Source-choice popovers should remain compact but contentful: title, one-line source descriptions, start/continue/change actions, disabled reasons, and current-source indication are enough. Do not make the popover a marketing menu.
- Post-generation detail should expose completion by content group: answer, structure, body text, explanation, metadata, tags, attachments, or other domain-specific sections. Users need direct "view" or "complete" actions for partial groups.
- AI parse workspaces should support paste/upload/manual fallback in the same task surface. After recognition, keep the original source, parsed result, editable fields, attachments, tags/metadata, and final confirmation in one scrollable review flow.
- Knowledge/tag/category selection after AI parse is a correction step, not decoration. Multi-column or cascading selectors need selected state, long taxonomy handling, clear/cancel, and disabled confirmation until required metadata is valid.
- If downstream processing has begun, edit actions should check runtime blockers before opening the editor. For example, an active scan/import/review job may allow viewing but block source editing until the job finishes.

Judgment layer extracted from this variant:

- **Aesthetics**: AI source choice should look procedural and low-noise: compact row action, compact popover, restrained status copy, and dense review form. The source mode is important, but the lifecycle object remains the visual anchor.
- **Interaction logic**: users enter from an object/process row, choose or continue a source, complete AI/manual review, optionally switch source with confirmation, then return to the same object context.
- **Behavioral logic**: users will choose the wrong source, change their mind after generation, return while recognition is partial, attempt duplicate actions, and try to edit during downstream processing. These become explicit states and guards.
- **Psychology**: AI output earns trust only when users see the source, generated structure, missing sections, editable corrections, and consequences of replacing prior work.

Judgment layer extracted from this variant:

- **Aesthetics**: dense source workbenches stay calm when the visual hierarchy is stable: stepper/header first, source canvas second, structure/inspector third, status text close to the affected action. Use compact controls, but keep enough breathing room around warning banners, selected regions, and destructive confirmations.
- **Interaction logic**: the user moves between source settings, upload/capture, processing, representation mode, structure review, correction, preview, and finalization. A mode switch must state what is currently editable and how to leave the mode.
- **Behavioral logic**: users will provide wrong source quality, wrong order, wrong format, partial source, repeated items, duplicate names, wrong drag targets, and incomplete region mapping. The design should filter what it can, warn early, preserve recoverable work, and localize repair.
- **Psychology**: recognition uncertainty makes users distrust automation. Confidence comes from inspectable intermediate output, visible counts, reversible repair, explicit destructive warnings, and a final preview that proves the output matches the source.

Judgment layer extracted from this pattern:

- **Aesthetics**: dense workspaces can look good when header, stepper, source list, canvas, and inspector have stable hierarchy. Keep dense controls compact, but preserve enough spacing for selection handles, validation text, and preview regions.
- **Interaction logic**: the flow is source -> ingest -> process -> match -> correct -> review -> final. The user should always know which phase owns the next action and how to return to the prior phase.
- **Behavioral logic**: users will upload wrong files, wait, interrupt, drag to wrong targets, create duplicates, forget required mapping, and return after navigation. Treat those as first-class states, not edge cases.
- **Psychology**: uncertain recognition creates anxiety. Reduce it by making machine work reviewable, showing missing/conflict counts, explaining blocked actions, preserving draft progress, and giving visible recovery routes.

## UI Structure

Use stable regions:

- Top context/header: object title, source, current step, save state, exit, previous/next, publish/export.
- Left or top outline: sections, groups, steps, source pages, or item partitions when structure is deep.
- Main workspace: current artifact, editor, preview, or extracted item list.
- Right/bottom inspector: metadata, conflicts, settings, AI suggestions, validation messages, and bulk actions.
- Persistent summary: total items, valid items, missing items, conflicts, selected count, and downstream impact.

For mobile, collapse outline/inspector into sheets or step screens. For web, keep context visible in side panels or sticky headers.

## Correction Mechanics

Complex creation is only usable if correction is cheap:

- Show inline edit for simple fields.
- Use drawer/modal for rich or multi-field edits.
- Let users split/merge/reorder repeated items.
- For imported or scanned source material, let users select structural regions, move items between groups, mark optional/extra sections, and restore original grouping when correction goes wrong.
- Show selected count before batch actions.
- Use semantic tags for missing, generated, manually edited, verified, conflict, and invalid states.
- Preserve undo/cancel for destructive correction.
- Show before/after identity when replacing source material or reusing templates.
- Distinguish preview-only settings from settings that change the final output.

## AI-Assisted Creation

When AI is involved:

- AI output is a draft, never final by default.
- Show selected source/context after generation.
- Provide regenerate, edit, accept, discard, and cite/source actions.
- Mark generated, user-edited, and reviewed sections distinctly.
- If AI partially succeeds, preserve usable sections and show failed/missing sections.
- Long-running AI generation should persist as a task/progress entry.

## Community Translation

Use this pattern for:

- Post/article creation with AI draft or media extraction.
- Topic/community setup from imported material.
- Creator profile or portfolio setup.
- Event/challenge/campaign creation.
- Imported contact/member/community data cleanup.
- Moderation evidence packaging.
- AI-generated collection, guide, digest, or recommendation review.

Avoid using this heavy flow for simple comments, likes, quick replies, or low-stakes lightweight posts.

## Acceptance Checklist

- The user always knows the current phase and whether work is saved.
- Machine-generated structure can be inspected and corrected before publish/export.
- Counts and conflicts are visible near the action area.
- Re-upload, reset, manual edit, retry, and cancel paths are available.
- Long sessions preserve context after navigation or returning from detail.
- Final confirmation describes consequences in product language.
- Import/recognition workspaces have tested upload validation, processing state, autosave/final-save split, validation blockers, correction modes, and downstream lock state.
- Source-material creation workspaces have tested source settings, file/page order, source-quality warnings, region/coordinate correction, structure split/move/reorder, reupload clearing confirmation, and preview before final save/export.
