# Interaction Design Patterns

Use this reference when designing, implementing, or reviewing interaction flows, micro-feedback, mobile gestures, AI-assisted flows, state transitions, or trust-sensitive product behavior. It combines Figma evidence with reusable frontend implementation patterns from mobile and web sources.

Do not inherit old source-domain semantics. Translate only the interaction mechanics into the new product's domain.

## Source Evidence

- Mobile app source: login, agreement consent, keyboard open/closed states, tab navigation, task cards, empty states, AI photo/upload, multi-item review, Toast, Modal, profile/settings, and explicit interaction-note sections.
- Desktop shell/workbench capability class: desktop login states, Sidebar full/collapsed states, selected/hover menu states, process/task entries, responsive workbench, Steps, Alert, Message, Dialog, Chat Bot, AI open/closed states, empty cards, upload/import workflow, and drawer/transfer patterns.
- Implementation primitives: see the catalog in `ui-ux-design-development.md`.

## Core Interaction Model

Every primary surface should state one dominant user job and support a complete loop:

1. **Discover**: scan feed/list/dashboard, understand current context, identify available actions.
2. **Inspect**: open detail, preview media/source, expand context, compare or filter when needed.
3. **Act**: create, reply, upload, analyze, follow, save, report, configure, or submit.
4. **Confirm**: show lightweight success, visible in-progress state, or explicit decision dialog.
5. **Return**: preserve context and selection when returning; make next action visible.

Do not add interaction states as decoration. Each state must answer: where am I, what changed, what can I do next, and can I undo or retry?

## Feedback Strength

Use the lightest feedback that still preserves user confidence. This is the canonical feedback-strength ladder for this skill:

- **Inline state**: validation, field errors, disabled reasons, upload progress, selected filter, current tab, active task.
- **Toast**: lightweight success or non-blocking failure after an action, such as saved, copied, sent, retried, or uploaded.
- **Notice bar / alert**: scoped persistent condition that affects a page or module, such as service migration, partial data, permission limits, stale data, or AI confidence caveat.
- **Dialog / modal**: decisions with consequence, consent, destructive actions, permission explanations, or workflow transitions that cannot be silently reversed.
- **Bottom sheet / drawer**: focused secondary workflow such as filters, selection, source settings, detail inspection, or batch setup while preserving the parent context.
- **Full-page error / empty state**: when the whole surface cannot proceed. Include a concrete recovery action whenever possible.

Avoid modal overuse. If the action can be retried or undone without major consequence, prefer inline feedback, toast, or an undo affordance.

## State Contract

Use the canonical state taxonomy in `product-surface-patterns.md`. This file adds interaction-level detail for state transitions:

- Entry states should distinguish first-use, returning-user, and empty-context entry.
- Progress states should distinguish short loading, streaming, upload/parse, long-running background task, and pagination/loading-more.
- Result states should distinguish success, partial success, no result, stale result, and generated-but-unreviewed result.
- Error states should distinguish retryable, non-retryable, permission denied, unsupported input, offline/network, and backend rejection.
- Control states should include selected, active, hover, pressed, focused, disabled, expanded/collapsed, and long-content behavior. **每态视觉必明显可辨**（不只是 5% opacity 差）：hover / focus / active 用**不同维度**的视觉变化（如 hover 改 bg、focus 加 outline、active 加 inner shadow）；disabled 视觉去活力 + 必含可见原因（参 [[design-execution-checklist.md]] §7 B）。默认 framework state（如未样式化的 `:focus`）不可见 = 等于无 state。
- Reversal states should include undo, cancel, remove, retake, replace, exit, clear, reset, and return.
- Trust states should include source visible, AI caveat, moderation/review label, reported/blocked/muted state, and risk-sensitive confirmation.

For AI or generated output, do not treat "generated" as final. Provide review, edit, regenerate, cite/source, copy/share, and failure paths as appropriate.

For embedded workspace assistants, treat the assistant as a secondary workflow surface rather than a separate chat island:

- Entry: docked panel, collapsed/floating launcher, fullscreen, hidden-by-permission, and route-local entry states.
- Compose: prompt text, attachments, preset suggestions, mode toggles, disabled submit, IME-safe send, and clear dependency rules between search, reasoning, upload, and model choices.
- Generate: waiting, streaming, cancel, interrupted, timeout, network failure, retry/regenerate, copy, and generated-content caution.
- Continue: session history, new conversation, switch conversation, delete confirmation, load older turns while preserving scroll, and return-to-bottom only when the user is not already near the latest output.
- Commit: if AI output becomes a post, resource, task, saved item, or workflow artifact, require preview/review, already-saved state, failure recovery, and a return path to the originating work.

For assistant geometry, responsive collapse, and workbench placement rules, use `platform-web-desktop-patterns.md#ai-assistant-in-workbench`.

## Mobile Interaction Rules

- Keep the main loop one-handed and screen-local. Primary actions should be reachable near the bottom or within the active card.
- Use bottom tabs for durable product areas, not transient workflow steps. Map tabs to core loops such as feed, create/AI, notifications, profile, or community spaces.
- Use a NavBar for screen identity and return behavior. Avoid hiding back/close behind browser controls.
- Use bottom sheets for filters, selector lists, advanced settings, and focused confirmation workflows.
- Keyboard-sensitive screens must handle visual viewport changes, Android overlay/resize differences, and safe bottom padding.
- Edge-swipe back is useful only when it does not conflict with horizontal content scrolling, carousels, drawing, annotation, or drag selection.
- Multi-item review or upload flows need current position, previous/next, retake/remove/replace, confirm, and done states.
- Empty mobile states should distinguish first-use guidance, no current items, no permission, and temporary loading/no-update conditions.

## Desktop / Web Interaction Rules

- Use a stable shell: account/context area, primary navigation, selected state, collapsed state, and discoverable hover labels.
- Put process/task entries near navigation only when they represent active user work, uploads, reviews, imports, generation jobs, or downloads.
- Keep dense workflow pages anchored by a title/context area, a toolbar, visible filters, and a persistent next action.
- Use drawers for detail or setup when the parent list/table should remain mentally available.
- Use explicit stepper phases for upload/import/configure/review/publish flows. Users should always know which phase they are in.
- For large workspaces, define min/max widths and collapse secondary panels before compressing primary content below usable size.
- Opening external systems or new windows should have clear feedback for failure and should not silently break the user's current task.

## Presentation Mode vs Workbench Mode

A product surface that exists in both an authoring/editing context (workbench mode) AND a "show this to a room" or "annotate live" context (presentation mode) is two distinct UIs sharing data, not one responsive UI. Treat them as different surfaces with explicit rules:

- **Fixed viewport vs responsive**: presentation mode targets a known display (typically projector / shared screen at one resolution like 1920×1080); design and test against that fixed viewport. Workbench mode is responsive across the user's window sizes. A single responsive surface trying to serve both will either fail the presentation case (controls too small at projector distance, text wraps unpredictably) or fail the workbench case (excess whitespace at normal window sizes).
- **Curated subset, not full data**: presentation mode shows only the artifacts the presenter chose to display (a selected item + curated supporting artifacts + the slide they navigated to), not the full table / list / search space. Workbench mode shows full data with filters; presentation mode shows the post-filter selection. Switching between modes must preserve the selection, not reset it.
- **Simplified control surface**: presentation mode strips workbench controls that don't apply to a live audience — sort, multi-select, batch actions, deep filters, account/settings entry, secondary nav. Keep navigation between items (next / previous / jump), the annotation/highlight toolset, fullscreen, and exit. Anything else is noise on a projector.
- **Annotation state is context-scoped, not global**: when the surface supports live drawing / highlighting / pen markup, the annotation state belongs to the current context (current item × current source pane), and each context owns its own annotation layer. Switching item or source pane must **switch to the new context's annotation layer** — show that scope's existing annotations if any, or start empty if none — and **preserve** every other scope's annotation layer until explicit discard or mode exit. A common wrong implementation uses one global canvas that wipes on every navigation; the presenter then loses every annotation the moment they navigate to compare items. Never wipe other scopes; only the current scope's layer is the one being drawn into.
- **Privacy mode is a live toggle**: when the presented content includes identifiable individuals (participant names, customer ids, employee photos, any personal identifier), provide a `hide / show real identifier` toggle that flips in real time without losing position or annotation. Default state is policy-driven (some venues default-show, others default-hide); do not bake the default into the workbench-mode user setting.
- **Mode entry and exit are first-class actions**: getting into presentation mode is an explicit affordance (a "Present" button), not a coincidental fullscreen press; exiting returns to the workbench in the same state (same selection, same scroll, same filter). Exit must be reachable from the keyboard (Esc) AND from the toolbar — projector audiences sometimes need the presenter to exit without alt-tabbing.
- **Persistence and replay**: any annotations the presenter wants to keep (for later review with audience members who were absent, for follow-up tasks) need a save path that survives mode exit. Annotations the presenter doesn't save are discarded on exit; do not silently persist every stroke.

## Community Product Translation

Translate old source mechanics into C-end community equivalents:

- Login/consent -> onboarding, account security, privacy agreement, notification permissions.
- Sidebar/process tabs -> creator workspace, moderation queue, upload/generation jobs, saved drafts.
- Workbench cards -> feed shortcuts, creation prompts, topic onboarding, community health, recent activity.
- Upload/parse/review -> media upload, AI draft extraction, source citation, content moderation, attachment processing.
- Analysis dashboards -> creator insights, topic health, retention, trust/safety, AI answer quality.
- Task review flows -> moderation decisions, report handling, creator payout review, campaign setup, AI classification correction.

Discard old source-domain scoring, hierarchy, workflow, and role vocabulary. Keep source-specific terms only in provenance notes.

## Serious / Financial Product Adaptation

When this skill is used for finance, health, legal, enterprise admin, or other trust-sensitive products, add an extra interaction layer:

- Show source, timestamp, data scope, and known gaps for AI or analytics outputs.
- Separate "informational insight" from "actionable decision" through copy, controls, and confirmation.
- Use stronger confirmation for irreversible, externally visible, account, money, permission, or compliance-sensitive actions.
- Avoid optimistic UI for actions that change money, permissions, identity, compliance status, or official records.
- Make partial data and delayed data explicit; do not let empty charts or `--` values masquerade as normal results.
- Prefer audit-friendly labels over cute microcopy for critical states.

This adaptation does not turn the skill into a finance compliance skill. It only prevents generic consumer interaction patterns from becoming unsafe in serious domains.

## Form & Defensive UI Patterns

- **"Labels are a last resort" — 仅适用于展示型数据，不是表单输入**：(a) **展示数据**（profile 字段、商品规格、详情页 attribute 列表）能用 layout / 值文本本身 / icon / 分组让意思自明，就**不重复贴 label**（"$42" 不必 "Price: $42"；"alice@example.com" 不必前缀 "Email:"）。(b) **表单输入则相反 — accessible label 是默认必须**（screen reader、autofill、低视力都依赖；WCAG 1.3.1 / 2.4.6 / 3.3.2 要求 — 见 [[external-ui-ux-quality-benchmarks.md]]）。可视觉隐藏（visually-hidden）label 仅当 placeholder/icon 等已提供持久可见 name；浮动 label、icon 内嵌等都是 label 仍存在的形式，不是"省略 label"。
- **User-supplied / 外部资源必有 fallback，按内容类型分对应模式**：avatar → initials / 默认头像；通用 media (cover/banner) → placeholder / blurhash；语义关键媒体（chart / map / PDF preview / 法律凭据）→ **不可用"看起来正常"的默认替代**（会误导用户认为渲染成功），必给明确"unavailable"或"无法渲染"状态；远程加载 → skeleton + retry control；生成型 preview → 明确"生成失败"状态 + retry。设计时显式给 fallback 视觉，不让 dev "实现时再说"。

## UI Copy Patterns（quick reference）

Operational microcopy patterns; 完整规则见 `design-execution-checklist.md` §7 B 段。

- **Button label**：verb + 具体对象（`Save changes` / `Send message`），avoid generic when action 不明（`Submit` 弱、`OK` 遮蔽结果）；platform dialog 标准位 `Cancel`/`OK` 仍可用。Destructive 更显式（`Delete forever`）
- **Error**：happened / why（安全可披露时给）/ what to do；不出 stack trace 或纯 error code 作主文案
- **Disabled**：默认给原因 + 启用条件；policy/permission/security 暴露条件不安全时改隐藏 control 或通用解释
- **Success / confirmation**：说清成功了什么 + 下一步（不只 `Done`）
- **Empty state**：见上文 "Full-page error / empty state" — 必含 recovery / next action
- **Voice consistency**：(a) 无内部代号 (b) 同动作/对象不混术语 (c) 无未解释 jargon (d) 无翻译腔 (e) 时态/人称/大小写统一

## Review Checklist

- The primary loop is visible without reading documentation.
- The next action is clear in happy, empty, loading, error, and partial states.
- Feedback strength matches the canonical ladder in this file.
- Mobile screens handle keyboard, safe area, return navigation, long labels, and one-handed action placement.
- Web screens handle collapsed navigation, selected state, filters, task/process entries, detail drawers, and responsive secondary panels.
- AI flows include generating, failed, reviewed, editable, source/citation, and regenerate paths.
- Trust-sensitive actions include source, timestamp, confirmation, retry, and audit-friendly state labels.
- Domain terms from source Figma/code have been translated or discarded.
