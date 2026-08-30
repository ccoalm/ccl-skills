# Operational Processing Workflows

Use this reference when designing or implementing high-intensity operational workspaces: artifact review, source capture, upload/import, queue handling, progress monitoring, assignment, exception recovery, or quality-control workflows.

Source provenance lives in `source-map.md`. Reuse the interaction mechanics, not the original source-domain vocabulary.

## Core Pattern

Treat operational processing flows as recoverable production work, not as simple forms:

- A user can always see the current item, current phase, remaining work, and next valid action.
- The artifact being reviewed or processed stays central; metadata, rules, quality signals, and ownership controls sit in side panels, drawers, or compact toolbars.
- Queue movement is explicit: previous/next, skip, return, submit, complete, reassign, retry, and escalate are separate decisions.
- Generated or processed output is not final by default. Mark unreviewed, reviewed, edited, failed, and returned states distinctly.
- Long sessions need stable controls, persistent progress, keyboard-friendly repeated actions, and recovery after interruption.

For operational, admin, moderation, and AI-review workspaces, do not use a marketing-style hero banner, decorative gradient as the design, oversized empty illustration, heavy visual drama, or a large unused first-screen area that pushes the real task below unrelated dashboard content. The default is a focused work surface. If the representative task is actually presentation or marketing, classify it as that different surface instead of weakening this operational rule.

## Focused Review Workspace

Use for moderation review, AI output validation, creator task approval, content QA, dispute handling, incident processing, or trust/safety operations:

- Header: task identity, status, owner, queue/filter context, current position, and global actions.
- Center: reviewed item, media/document preview, generated result, original source, or side-by-side comparison.
- Side panel or drawer: metadata, risk/quality signals, history, comments, rules, source details, and decision controls.
- Toolbar: previous/next, zoom, fit, annotate, mark, comment, shortcut actions, view mode, submit, and return.
- Footer or sticky action zone: low-risk navigation separate from high-commit decisions.
- Support one-item, two-item, and multi-item layouts without changing the core action model.
- Support dense artifact adaptation: single artifact, multiple artifacts, split source/result view, and full-screen review should share the same decision vocabulary.
- Preserve reviewed context when switching items; do not clear filters, zoom, or annotation state unexpectedly.

## High-Throughput Artifact Evaluation Workspace

Use when users must repeatedly inspect artifacts, assign a judgment, annotate or tag special cases, submit results, and move through a queue without losing accuracy. This applies to moderation scoring, AI output checking, creator submission review, quality labeling, dispute triage, and other high-volume evaluation flows.

Execution recipe:

- Split the workbench into four stable regions: top context/status bar, central artifact canvas, right-side evaluation tool, and bottom/session metrics. The artifact remains dominant; controls should support repeated judgment, not compete with the artifact.
- The header should expose queue identity, current unit, progress count, mode, history/statistics/settings, full-screen, and exit. Keep it compact so the first screen is work, not navigation.
- Header actions in dense review should be grouped by intent: queue switching and progress together, display/count controls together, view/reference tools together, and session actions such as full-screen/exit at the edge. Do not scatter progress, rerun, display mode, and exit controls across unrelated bars.
- Queue and mode switchers should scale by information density. A short candidate list can use compact rows; a long or heterogeneous queue needs card-like rows with status tag, progress bar, numerator/denominator, selected state, and stable tab filters.
- Support one-item, multi-item, and responsive split display with the same action model. Let users increase/decrease visible item count, but preserve minimum card width, selected item, and scroll position.
- Responsive split display should be computed from usable work-area width, not guessed from a fixed viewport. Define the minimum readable card width, then cap visible item count or switch to a scaled/stacked mode before cards become too narrow to inspect.
- Single-item and multi-item modes are not only grid changes. The header's current-unit label, progress context, artifact canvas share, selected card boundary, and tool-panel assumptions must update together so users know what is being judged.
- When one work item contains multiple sub-units, keep a visible selected sub-unit boundary and local metadata strip for each sub-unit. Floating quick actions, side-panel inputs, and bottom tools should bind to the selected sub-unit, not ambiguously to the whole artifact.
- Multi-item grids should preserve individual item identity while reducing repeated chrome. Use compact identity tags, selected outlines, and aligned mini-metadata instead of repeating full headers inside every card.
- For long or multi-part artifacts, provide explicit fit strategies: width-fill, height-bounded preview, horizontal/vertical stitching, single-part versus whole-artifact display, and scroll containment. Remember the user's per-work-unit zoom or fit choice when repeated items share the same structure.
- When artifact content is empty, delayed, or unavailable, keep the current item shell visible: selected boundary, metadata strip, loading/empty reason, retry or next action, and stable evaluation controls. A blank canvas without item context reads as navigation loss.
- Persist personal evaluation settings when they affect repeated work: display density, background, split count, submit mode, batch mode, default handling for incomplete items, common values, and toolbar visibility.
- Provide multiple evaluation input modes for different user intent: click selection for speed, step/quick adjustment for incremental judgment, keyboard/table mode for precision, and batch mode for homogeneous groups.
- Precision or keyboard/table modes need row-level states: summary row, current step row, selectable row with checkbox, hover row, inline numeric editing, quick full/zero actions, and disabled/hidden quick actions when the mode is summary-only.
- When several actors, reviewers, models, or sources judge the same item, use an aligned comparison table with fixed identity columns, compact value columns, selected row state, and status tags. Long item labels should ellipsize without pushing comparison values out of alignment.
- Make submit semantics explicit: auto-submit, context-menu submit, and manual submit are different workflows. Switching input modes may need to disable incompatible submit behavior.
- Task-type variants may add or remove modes, but they should not change the workbench skeleton. Keep header, artifact canvas, side tool, session controls, and history/statistics/settings in stable positions; shrink unavailable settings with clear disabled or hidden rules.
- Batch defaults and common-value configuration are owned by the current mode. If the user changes mode or task type, recompute batch availability, default selection, quick values, and submit behavior instead of carrying stale settings forward.
- Do not submit incomplete work silently. If some items lack judgments, require an explicit choice such as continue, submit only completed items, or apply a default value for this submission or future submissions.
- Treat queue navigation as stateful review, not simple paging. Previous/next, return to unfinished work, continue after completion, and help/overflow work need separate states and disabled reasons.
- Queue-end and no-work states are not interchangeable. Distinguish completed queue, temporarily locked work, no eligible items, stale route/task, and optional overflow/help work; each state needs a different next action and return path.
- When users must choose a subset of mutually exclusive options, make the exclusion visible immediately. Selecting the allowed count should disable the remaining choices and any downstream content that depends on them.
- Show already-reviewed history in a non-blocking drawer with filters, score/range filters where relevant, status tags, pagination, and a direct jump back to the inspected item.
- Show statistics in a non-blocking drawer: averages, distribution, flagged examples, special-case counts, and overall completion. Drill into example details only when the count is actionable.
- History and statistics should not be read-only decoration. A history drawer should preserve filters, page, focused item, and return-to-unfinished action; a statistics drawer should connect aggregate counts to example detail only when the example set can help the current decision.
- Artifact cards need source image/media retry, loading/failure state, selected/focused state, current judgment overlay, AI/generated tag where relevant, and full metadata only when it helps the decision.
- Media failure should recover locally. Retry transient image/media errors automatically a small number of times, then show a manual retry surface inside the artifact region so the user does not lose queue context.
- Inline micro-actions should handle common evaluator behavior: adjust value up/down, reset, mark as exemplary, mark as low-quality, flag issue, add reason, and cancel. Keep destructive or reroute actions behind confirmation.
- Inline micro-actions need their own state model: hidden until relevant, hover reveal, selected state, clicked/confirmed state, disabled reason, tooltip label, and compact local or global success feedback. Do not make users infer whether a tiny icon changed the item.
- Card selection should have at least default, hover, selected, and completed/confirmed states. Selected state should combine shape, border, and label treatment where needed; color alone is too easy to miss in dense repeated work.
- For repeated local adjustments, show the control near the artifact and keep the confirmation lightweight. For irreversible, exceptional, or rerouting actions, escalate to a modal/drawer with reason capture and clear cancellation.
- Sticky tags are useful when an item changes operational path. If an item is flagged as an issue, suppress incompatible inline actions and keep the issue tag visible while the card scrolls.
- Annotation tools should be movable and bounded by the work area. Drawing/marking state must belong to the selected artifact and support delete/clear without affecting other artifacts.
- Annotation tools need explicit states: default, hover, selected, disabled, cursor affordance, resize handles, keyboard delete, dropdown subtools, tooltip labels, compact/expanded toolbar variants, line/shape width, stamp size, and out-of-bounds deletion. Annotation scale must follow the artifact scale.
- Shape or mark subtools should be grouped behind a small menu when space is tight, with the current subtool reflected in the toolbar icon and the menu row selected state.
- Toolbars can switch between icon-only and labeled modes. Use icon-only for expert dense work, but provide a labeled or tooltip-rich mode when actions are many, ambiguous, high-impact, or newly introduced.
- AI-assisted evaluation is reviewable output, not final truth. Show running/finished status, retry or rerun limits, manual override, and what scope will be reprocessed before launching a rerun.
- AI-reviewed or automation-reviewed items should carry an inline status tag close to the artifact content, not only a header or toast. The tag should make manual override and rerun/recheck paths discoverable without implying the result is final.
- If AI comparison, side-by-side checking, or automatic review is unsupported for a task type, show the unsupported reason in the same review surface instead of routing users into a blank tool.
- AI-assisted evaluation configuration should be scoped before execution. Show eligibility, enabled/disabled scope, strategy presets with plain-language tradeoffs, custom strategy entry, required context, reference output, explanation/rationale fields, and save/cancel semantics. Presets should explain how strict or permissive the automation will be instead of exposing only a model name or switch.
- AI-assisted configuration for multiple items needs item-level enable switches, status tags, selected-item configuration, and a stable empty/config panel. If the source item has hierarchy, show a compact structure tree or metadata ladder in the left list so the switch clearly belongs to a specific sub-unit.
- When no item is enabled, keep the selected item, its key metadata, and the configuration area visible with the exact enablement prerequisite. Do not collapse the panel into a generic empty page; leave required reference fields in place so users understand what will be needed.
- AI or automation output needs an explicit result-use mode. Let users choose whether generated output is only a review reference or is allowed to become the committed result, and keep that choice visible near the final save action.
- Long reference, answer, rationale, or generated-output panels should have bounded heights: preserve a useful minimum height for short content, cap long content, and scroll inside the panel instead of growing the whole dialog beyond the viewport.
- Quality or timing gates should block final submission with a specific reason and the next allowed action. Avoid generic failure toasts when the user only needs to wait, complete more work, or choose a fallback handling rule.
- Full-screen mode should move popups into the full-screen container, reset floating toolbar placement on exit, and keep keyboard/context-menu behavior predictable.
- Provide low-fatigue visual modes when sessions are long, such as neutral, warm, or soft background colors. Treat them as user settings, not as brand changes.
- Settings and statistics belong in drawers when they support the current run. Settings should be grouped by review comfort, display mode, submit behavior, and footer/metadata visibility; statistics should support aggregate scan and actionable drill-down without hiding the current artifact.
- Timing, average throughput, and personal time indicators are useful only when they reduce uncertainty or support quality control. Keep them compact and avoid turning them into pressure-heavy visual noise.

Judgment layer extracted from this pattern:

- **Aesthetics**: dense evaluation needs a restrained production feel: dominant artifact canvas, compact right tool, quiet header, subtle but unmistakable selected states, aligned comparison values, and metrics that are readable without visual drama.
- **Interaction logic**: users select a unit or sub-unit, inspect the artifact, reveal nearby micro-actions, choose or adjust a judgment, optionally tag/annotate, submit, then move forward or review history. Return paths, disabled reasons, and unfinished work are explicit.
- **Behavioral logic**: users batch similar items, misclick, leave items incomplete, switch modes, edit precise values, compare multiple reviewers/sources, resize the screen, retry failed media, revisit completed work, and hit queue-end or locked-task states. Each branch needs a stateful response.
- **Psychology**: high-volume evaluation creates fatigue, comparison uncertainty, and fear of accidental submission. Reduce cognitive load with persistent settings, predictable next-item movement, visible progress, reversible local adjustments, aligned comparison tables, and confirmations only when consequences are high.

## Scan, Upload, And Processing Pipeline

Use for media upload, document ingestion, AI knowledge/file ingestion, evidence upload, imported data cleanup, or background processing:

- Model phases separately: no source, selecting source, uploading, uploaded, processing, preview available, completed, unsupported, failed, and retrying.
- Separate transfer progress from server/AI processing progress.
- Keep progress close to the artifact list and preview, not only in global toasts.
- If the source can arrive from device capture, local file upload, scanner, or external import, represent connection/unavailable, first-run empty, subsequent run, and unsupported-source states separately.
- Provide large-preview or full-screen mode for dense media/documents with obvious return navigation.
- Show unsupported format, permission denied, parse failed, partial success, stale result, and no-data states with clear next actions.
- For batch uploads, show per-item status and aggregate progress; failed items should be retryable without restarting the full batch.
- Preserve original file identity and extracted/processed identity so users can compare source and result.

## Device Capture And Exception Recovery

Use this when the source can come from local files, a connected device, camera, scanner, or external capture plugin. This flow is not only an upload widget; it is a fragile real-world operation that must survive device failure, wrong files, interruption, and later cleanup.

Execution recipe:

- Separate environment readiness from capture progress: unsupported system, missing helper/plugin, missing driver, connecting, disconnected, connected, ready, running, paused, uploading, uploaded, completed, and failed are distinct states.
- Always provide a fallback source path when possible, such as local upload, manual import, or later retry. A blocked device path should not trap the user.
- Store the selected device/configuration cautiously and re-check it on entry. Cached hardware state is a starting point, not proof that the device is still usable.
- Guard startup with prerequisites: required identifiers, permission, available storage, valid source format, max file count, max file size, and required setup data.
- Treat a capture batch as a durable session. If the route, batch id, or session marker no longer matches, exit or recover explicitly instead of continuing against stale state.
- Show transfer and processing separately: captured count, uploaded count, upload speed, processing/exception count, and the current action should be visible at the same time.
- Preview is a control, not decoration. Support preview on/off for performance, large preview/full-screen view for inspection, and obvious return navigation.
- Pause, continue, stop, retry, and finish need different copy and disabled reasons. Finishing while upload is incomplete should be disabled with a concrete reason.
- Device interruptions need recovery instructions tied to the physical sequence, such as retry after loading media or re-running the last few captured items when a jam/interruption may have lost work.
- Warn before browser close, page reload, sleep, or offline transitions when capture/upload can be interrupted. Reset live speed/progress indicators when the client goes offline.
- Surface exception counts during capture and route directly to exception handling or result management after capture. Do not bury failed/abnormal items in a later report.
- Result management should separate recognized/processed items, missing items, omitted items, foreign/unmatched items, and capture records. Use tabs only when each tab has a different operational task.
- High-frequency capture management can auto-refresh compact statistics, but manual refresh must remain available and should not flicker the whole workspace.
- Async exports/downloads from the management view need job status, disabled duplicate download state, polling, success download, failure message, and cleanup.

Judgment layer extracted from this pattern:

- **Aesthetics**: make the live operation feel calm. Use a strong center progress object, compact metrics, and a stable right/side control zone; avoid moving controls while counts update.
- **Interaction logic**: users enter through readiness, choose device or fallback source, start capture, monitor capture/upload, optionally preview, finish, then inspect/manage exceptions and records.
- **Behavioral logic**: people close laptops, lose network, choose invalid files, forget physical media, re-enter stale routes, and need to continue after stopping. These are normal branches, not rare errors.
- **Psychology**: device capture creates fear of losing physical work. Reduce anxiety with live counts, explicit interruption warnings, recoverable continue/retry paths, and direct exception handling.

## Progress And Quality Monitoring

Use for review queue health, creator workflow status, moderation throughput, AI quality monitoring, content readiness, or incident handling:

- Separate progress from quality. Progress answers how much is done; quality answers whether the work is acceptable, risky, abnormal, or disputed.
- Offer pivots by item, owner, group, status, exception, time, source, and confidence where useful.
- Make exceptions first-class: overdue, blocked, low confidence, disputed, abnormal, failed, returned, or needs review.
- Prefer sortable tables and compact status tags over decorative charts when the next action is operational.
- Row actions should go directly to inspect, assign, approve, reject, return, retry, comment, escalate, or export.
- Critical workflows need audit-friendly states: pending, in progress, submitted, reviewed, returned, resolved, failed, and read-only.

## Multi-Dimensional Progress And Quality Control

Use when a workbench must monitor throughput and correctness across many work units, owners, scopes, or quality-risk categories. This pattern is for operational confidence, not decorative analytics.

Execution recipe:

- Keep progress and quality as separate top-level modes. Progress is throughput and completion; quality is risk, correctness, dispute, exception, or rework. Do not merge them into one chart or make users infer quality from progress.
- Gate each mode by permission. If a user cannot view progress or quality, the unavailable mode should be disabled or hidden consistently, with the rest of the workbench still understandable.
- Offer dimension switches based on the current context: work unit, owner/person, group/scope, and object-level inspection. Hide unavailable dimensions instead of showing empty fake tabs.
- Every progress row or card needs both percentage and numerator/denominator. Percent alone hides scale, and numerator/denominator alone slows scanning.
- For multi-stage work, show stage counts side by side: primary pass, secondary pass, escalation, issue items, and review pass. Only show stages that exist for the current work unit.
- Treat zero-denominator data deliberately. If no work is expected, show complete or unavailable according to the business rule; never let division by zero produce broken progress.
- Use compact cards for work-unit summaries and tables for owner/object lists. Cards should carry tags, progress, counts, and a detail action; tables should carry status, scope, count, and action columns.
- Quality mode needs at least two inspection levels when the work supports it: unit-level quality for batch risk and object-level quality for precise review. Preserve filters when entering object-level inspection from another route or row action.
- Scope filters reset detail expansion and collapsed-table state. A user changing scope should not see stale expanded content from the previous scope.
- Expansion should reveal the next actionable detail, not a raw data dump. Auto-open the first non-empty quality category and keep empty detail actions disabled with a short reason.
- Use sticky headers, fixed pagination zones, and measured table height for dense monitoring. The workbench should survive long labels, resized windows, and different header heights without hiding the current row.
- Refresh and export are explicit actions. Refresh should fan out to dependent panels through shared state or events, show loading/result feedback, and avoid pretending stale data is current.
- Rework, reset, return, or reprocess actions require permission, loading state, affected-scope clarity, and success feedback that tells the user where to see the latest state.
- Overall progress tables must explain denominator composition, including completed, exception, unavailable, and total counts where relevant. Preserve filters and pagination through refreshes and deep links.
- Deleted, inactive, offline, system-owned, or automated actors need distinct labels. Do not treat them as ordinary active owners, but keep their historical contribution readable.

Judgment layer extracted from this pattern:

- **Aesthetics**: make dense monitoring calm and scannable. Use a restrained table/card hybrid, compact tags, aligned count groups, progress bars with numbers, and stable section rhythm. Avoid oversized dashboard charts unless the chart directly changes the next action.
- **Interaction logic**: users enter a top mode, choose a dimension, inspect summary rows, expand details, then refresh, export, rework, or deep-link into object inspection while preserving return context.
- **Behavioral logic**: users change scope, resize windows, refresh stale reports, inspect empty detail, encounter offline/deleted actors, and act on partial or exception-heavy data. These branches must be visible, recoverable, and stateful.
- **Psychology**: progress gives confidence that work is moving; quality reveals whether the work can be trusted. Keeping them separate reduces false reassurance and helps users decide whether to wait, intervene, or escalate.

## Assignment And Ownership

Use when work must be distributed across people, queues, roles, topics, content partitions, or AI-review batches:

- Separate structure setup from ownership assignment. Users should know whether they are defining units, assigning owners, or only viewing results.
- Show state transitions: unassigned, partially assigned, assigned, not started, in progress, locked, completed, and read-only.
- Bulk assignment needs an affected-scope summary before apply.
- Split/merge actions are allowed only when users can preview downstream impact.
- Permission and mode differences must be visible through available, disabled, or hidden actions consistently.
- Dense assignment tables need sticky headers, stable row identity, and clear owner/scope columns.
- When assignment has setup and execution phases, represent unconfigured, configured/not started, started, loading, read-only, and unsupported split/merge states explicitly.

## Structured Work Partition And Assignment

Use when a surface must first define work units and then assign people, automation, permissions, or workload rules to those units. This pattern applies to moderation staffing, campaign routing, creator task assignment, AI-review workload setup, complex operations handoff, and any workflow where changing the unit structure can invalidate downstream work.

Execution recipe:

- Start with a compact context bar: parent object name, current stage, saved/saving state, permission mode, and the one final action. Keep the first viewport focused on the assignment table, not an introduction.
- Separate the two mental models visibly: unit partitioning changes what work exists; assignment changes who or what handles it. Put split/merge/structure actions together, and role/method/permission actions together.
- Use a hierarchical table when units contain sub-units. The first column should preserve unit identity, sub-unit labels, score/weight/count where relevant, collapse state, and stable row numbers so users can scan without losing where they are.
- Keep strategy, distribution method, primary owner, secondary reviewer/escalation owner, exception handler, and row actions in distinct columns. If a role is not applicable to the current strategy, show a stable unavailable marker instead of shifting columns.
- Batch mode needs its own top action bar with select-all, selected count, disabled-count reasons, the current batch operation, alternative operations, exit, and finish. Hide row-level actions while batch mode is active so users do not mix scopes.
- Batch setting must support partial completion: after the first edit, change the escape action from simple exit to finish/apply so users understand whether they are leaving a staged operation or committing changes.
- Split/merge operations need disabled reasons before selection, not only after submit. Common reasons include incompatible unit type, missing sub-units, cross-scope mismatch, automation-owned unit, downstream records already started, or permission lock.
- If split/merge after execution can clear, detach, or invalidate downstream work, escalate with a confirmation that names the consequence and still returns users to the affected unit after success.
- Reuse, import, export, and template actions are operational shortcuts. Treat them as part of the assignment workflow: show job state, failed-row recovery, download retry, and whether imported data replaces, merges, or only stages owners.
- Fixed-quota or ratio assignment needs live validation close to the field: unallocated amount, over-allocation, minimum per owner, maximum per reviewer, existing completed work that cannot be reduced, and whether counts are by unit or by sub-unit.
- Multi-scope quota assignment should expose the grouping rule. If users can allocate by organization, cohort, region, queue, or segment, show group totals, group owner lists, group-level average allocation, global average allocation, completed-work minimums, and whether the final remainder is auto-filled.
- When the same owner can belong to multiple scopes, deduplicate visual names for table scanning but keep per-scope assignment data available in the drawer or detail panel.
- Role conflicts need inline explanation and a direct repair path. If a secondary reviewer cannot review their own work, explain the permission rule and link to the permission setting instead of leaving a generic validation error.
- Finalization should check assignment completeness, exception-handler completeness, conflict rules, quota completion, optional-routing rules, and permission intent. If sensitive permissions or optional-routing rules were never opened or confirmed, show a compact confirmation popover/drawer that summarizes the current choices and offers focused modify actions plus confirm.
- Error handling should guide repair, not only block submit. Mark invalid rows with a visible boundary, scroll the first invalid row into view, keep the exact invalid field message near the field, and remove the row-level error immediately after the relevant value is fixed.
- Loading and read-only modes must preserve the table geometry. Skeletons, disabled controls, and unavailable role columns should occupy the same regions as the editable state.
- Viewpoint modes can be narrower than the full workflow, such as partition-only, assignment-only, started-but-editable, and read-only. Each mode should make unavailable operations consistent through hidden, disabled, or read-only treatment, not a mixture of surprises.
- Dense assignment tables need explicit desktop adaptation. Declare a minimum width, preserve the primary unit/owner columns, move low-frequency actions into an overflow menu before squeezing readable content, and allow horizontal scroll only after the declared minimum is reached.
- Automation assignment should be scoped per unit or sub-unit. Show eligibility, enabled units, disabled reasons, strategy/strictness, required references, and whether automation output is advisory or committed.

Judgment layer extracted from this pattern:

- **Aesthetics**: structured assignment should feel calm and exact. Use compact rows, sticky headers, aligned role columns, subtle tags, and restrained warning color; avoid making bulk bars or warnings visually louder than the work units they modify.
- **Interaction logic**: users enter from context, inspect unit structure, choose single-row or batch mode, configure strategy and owners in drawers, validate quotas and conflicts, confirm permissions, then finalize or save. Split/merge and import/export are side paths that must return to the affected unit.
- **Behavioral logic**: users partially configure rows, select incompatible units, import imperfect owner lists, adjust after work has started, resize the browser, and revisit read-only historical states. Each branch needs disabled reasons, staged change feedback, and a recoverable return point.
- **Psychology**: assignment mistakes feel expensive because they can overload people, create unfair work, or invalidate completed effort. Reduce anxiety with saved-state feedback, selected-count clarity, live quota math, consequence-specific confirmations, permission summaries, and visible recovery after bulk changes.

## Community Translation

- Review workspace -> moderation queue, report handling, creator submission approval, AI draft validation, quality review, appeal/dispute workflow.
- High-throughput evaluation workspace -> content rating, moderation labeling, AI answer checking, creator submission QA, dispute triage, annotation queue, trust/safety review.
- Scan/upload pipeline -> media ingestion, evidence upload, file-to-AI context, imported contact/community data cleanup, portfolio upload, event asset processing.
- Progress/quality monitoring -> trust/safety health, creator task completion, AI response quality, campaign readiness, content review throughput.
- Assignment workflow -> moderator routing, creator task ownership, incident owner, campaign staffing, queue partition, AI-review workload distribution.

## Acceptance Checklist

- Current item, phase, owner, progress, and next action are visible.
- High-throughput evaluation keeps artifact canvas dominant, computes responsive split count from minimum readable card width, supports one/multi-item and sub-unit display, provides explicit submit modes, handles precision/table input states, supports aligned multi-actor comparison when present, prevents silent incomplete submission, recovers media failure in-place, and preserves history/statistics/detail context.
- Upload/processing failures are recoverable at item level.
- Device capture distinguishes readiness, capture, upload, completion, unsupported, and interruption recovery states.
- Progress and quality monitoring separates throughput from correctness, provides mode/dimension switches, shows percentage plus numerator/denominator, preserves filters through detail entry, and handles stale refresh, empty detail, scope changes, and rework/reset permission.
- Review decisions are separate from navigation.
- AI or processed output has unreviewed/reviewed/edited/failed states.
- Batch operations show affected scope and allow cancellation before commit.
- Dense workspaces preserve scanability: sticky controls, stable rows, aligned metadata, and no hidden critical state.
