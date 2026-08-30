# Complex Workspace Patterns

Use this reference after `web-react-dev/SKILL.md` identifies a React surface as a dense workspace rather than a normal page/form/list. Keep the entrypoint small; apply only the relevant pattern family below.

## Pattern Families

### Review / evaluation workspaces

- Own queue/task identity, selected record, selected sub-unit, current-item header, queue switching, batch selection, submit mode, incomplete-item confirmation, and queue-end recovery.
- Keep artifact layout readable by deriving split count from container width and a declared minimum card width. Persist user display preferences with scope and expiry, then validate restored settings against route, permission, task type, and item count.
- Preview media/documents with automatic transient retry plus manual retry. Keep per-item annotation, disabled reasons, local/global success feedback, quality/timing gates, and history/statistics drawers as separate state owners.

### Insight / report / analytics workspaces

- Treat list filters, detail route params, selected report/module, menu state, local section anchors, scope filters, exports/downloads, module config changes, and parent return context as one route contract.
- Validate cached filters against the current option set; clear stale dependent filters deliberately and refetch authoritative data after create/edit/delete/default mutations.
- Chart, canvas, image, PDF, or annotation components need cleanup, resize handling, device-pixel-ratio correctness, zoom/pan/reset where relevant, and browser evidence for overflow, long labels, and drill-down linkage.

### Assignment / roster / resource management workspaces

- Keep structure edits, owner edits, permission edits, quota edits, import/export jobs, save/autosave/finalize, and read-only/started variants as separate state transitions.
- Selection drawers need search, cascade filters, role/qualification filters, all/partial selection, selected-count panel, disabled existing owners, max-count handling, bulk clear, removal, and no-result states.
- Resource and taxonomy flows need route scope, resource type, hierarchy mode, selected tree node, filters, pagination, selected resource, preview/detail, share/publish/download settings, upload/import jobs, and cached-filter restoration as distinct owners.

### Assistant / AI workspaces

- Compose state should separate prompt text, attachments, capability modifiers, model indicator, send/cancel, generated-output actions, IME composition, and scroll/history recovery.
- Streaming needs terminal states: waiting for first response, append, timeout abort, auth/session expiry, quota/content refusal/model unavailable, network/user-send failure, user cancel, server interrupt, done, regenerate, copy, and timer/controller cleanup.
- AI-generated structured output needs validation, renderer failure fallback, save/retry/remove semantics, already-saved state, and generated-to-saved-object reviewability.

### Media / capture / import workspaces

- Capture/import flows should model file identity, metadata form state, parent/child cascades, consistency checks, parse/enrichment polling, background continue, retry/reupload, partial failure, and navigation to the next editor/detail step.
- Native-assisted or app-hosted capture treats the bridge payload as an API contract: normalize success/cancel/failure, parse payloads safely, validate object key/URL/file type/name, and keep callback cleanup scoped.
- Do not clear loading or host overlay state immediately after native success if a route handoff is still pending; hold it until the destination route mounts and signals readiness.

### Auth / account / app-hosted foundations

- Auth/onboarding surfaces need explicit mode ownership: splash handoff, consent, password login, phone-code login, account opening/binding, first-password setup, reset, guest/public mode, privacy/legal links, and deterministic back paths.
- App-hosted React surfaces need lifecycle ownership in React code: save/restore foreground/background state, expire stale state, omit or protect sensitive fields, validate restored route/context, and recover when browser storage, host storage, or injected app info is unavailable.
- Account/profile/privacy/about routes should share logout, account deletion, legal document loading, version/about, cache cleanup, and post-action navigation contracts.

## Acceptance Checks

- State owner map exists for every selected pattern family.
- Long content, empty/no-data, error/retry, slow/weak network, permission/disabled, narrow/responsive, accessibility text scaling, interruption/return recovery, and repeated-use/cache-hit behavior are either tested or explicitly out of scope.
- Browser or host-container evidence captures the declared stress widths and the primary pending/final/error states. If rendered evidence cannot run after normal remediation, status is `pre-runtime-test-ready` or `blocked`, not complete.
