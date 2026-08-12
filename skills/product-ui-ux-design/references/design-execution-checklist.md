# Design Execution Checklist

Use this checklist when applying the skill to a concrete product screen, feature, implementation, or review.

## 0. Resolve Target Context

Before loading detailed references, translate the active task into the target product frame:

- Classify the target as community/social, education, finance/data, AI workspace, operational tool, consumer content, mobile app, web workbench, settings/account, or shared system.
- Translate source-domain terms into target-product interaction patterns; do not output source-domain UI copy or source-domain information architecture.
- Exclude source-domain terminology, role models, and workflow structure from product-facing output.
- If the task context is mixed, state which product assumption is being used before design or implementation.

## 1. Classify The Task

Identify the target surface:

- Mobile consumer surface: feed/detail, creation, profile, onboarding, notifications, AI assistant, settings, or finance/data mobile task flow.
- Web consumer surface: content/detail/community, creator center, AI workspace, finance/data research surface, settings, notifications.
- Web operational surface: moderation, trust/safety, analytics, data/research workbench, creator tools, admin-like settings.
- Shared system work: tokens, components, theming, interaction states, visual QA.

Then load only the relevant references:

Core layer:

- Always: `product-surface-patterns.md`.
- Broad design, implementation, or review work: `design-intake-and-acceptance.md`.
- Interaction logic, attention, motivation, perceived effort, trust psychology, habit loops, or aesthetic judgment: `behavioral-aesthetic-logic.md`.
- UI/UX audit, implementation review, code/design comparison, usability risk, accessibility, or responsive QA: `ui-ux-audit.md`.
- UI/UX design and frontend implementation: `ui-ux-design-development.md`.
- Product launch acceptance, lifecycle review, and iteration planning: `product-lifecycle-acceptance-and-iteration.md`.
- Frontend visual polish, brand feel, or anti-slop review: `visual-craft.md`.
- Layout recipes, component density, empty/loading/error templates, workbench structure, or screenshot acceptance: `layout-recipes-and-screenshot-acceptance.md`.
- Interaction flow, feedback strength, gestures, AI generated states, or serious/trust-sensitive states: `interaction-design-patterns.md`.
- Shared token/component capability map: `tokens-and-components.md`.

Platform lenses:

- Mobile/App/H5/WebView: `platform-mobile-patterns.md`.
- Web/Desktop/workbench/auth/admin: `platform-web-desktop-patterns.md`.

Scenario lenses:

- Community/social/feed/creator/moderation: `scenario-community-patterns.md`.
- External usability, accessibility, performance, or metrics benchmark: `external-ui-ux-quality-benchmarks.md`.
- Trust-sensitive AI/data, citation, upload, permission, instrumentation, or dense operational patterns: `trust-sensitive-ai-and-data-patterns.md`.
- Local frontend implementation evidence, codebase source classification, reusable primitives, or build/launch scripts: `frontend-code-evidence-map.md`.
- Complex creation, upload/import, AI draft extraction, structured editing, matching, manual correction, or publish/export flows: `complex-creation-interactions.md`.
- Analytics, visualization, charts, comparisons, drill-down reports, creator/topic health, retention, or AI quality metrics: `analytics-visualization-interactions.md`.
- Operational processing workspaces for capture/upload, focused review, moderation queues, quality/progress monitoring, assignment, or ownership workflows: `operational-processing-workflows.md`.
- Resource libraries, AI cloud-drive style storage, media/template centers, saved prompts, knowledge sources, content packs, sharing, or resource governance: `resource-management-interactions.md`.

Provenance and multi-project lenses:

- Identifying which Figma file is the real design-system source, detecting third-party-mirror design systems, deciding which file owns brand tokens, or auditing theme/code comments pointing at the wrong figma file: `design-system-source-of-truth.md`.
- **Same-stack multi-subproject** theme consistency (e.g. multiple desktop apps, or multiple H5 apps, sharing one brand), detecting silent default-theme drift across same-stack subprojects, or deciding how to share one theme module: `multi-project-token-consistency.md`. Use this when the subprojects are on the same end (all web-desktop, or all web-h5, etc.).
- Resolving Figma↔code naming drift, deciding which of `Foo` / `FooV2` is active, planning retirement of in-flight version stamps, or maintaining a design-code terminology glossary: `design-impl-naming-and-versioning.md`.
- **Cross-stack** strategy when a product spans multiple client stacks (web + H5 + native + mini-app + RN), handling stack outliers (a Vue island in a React organization, a single mini-app surface, etc.), splitting design system by stack, or writing the native-shell ↔ H5 contract: `multi-stack-strategy.md`. Use this when stacks differ across subprojects, not when the subprojects share a stack.
- **Same-framework cross-end** (e.g. React desktop + React H5 + React Native, sharing one brand and one TS toolchain but different UI-kit per end): a common middle case. Load **both** `multi-project-token-consistency.md` (for the shared theme module across same-framework subprojects) and `multi-stack-strategy.md` (for the per-end UI-kit and surface differences). Do not pick one — apply both.

## 2. Translate Source Patterns

Before designing or coding, state the translation explicitly:

- What source pattern is being reused?
- What target-product behavior does it become?
- What source-domain details must be discarded?
- Which source-domain details must remain provenance-only and excluded from product-facing output?

Examples:

- Source dashboard card -> community feed module, creator task card, or AI suggestion.
- Source task/progress state -> publish, review, moderation, AI-generation, upload, or sync state.
- Source answer/analysis region -> post body, comment, AI response, annotation, or explanation panel.
- Source settings/report view -> creator analytics, moderation tools, trust settings, or account preferences.
- Source complex creation/import flow -> media creation, AI draft extraction, structured content setup, event/campaign setup, or imported data cleanup.
- Source chart/report interaction -> creator analytics, topic health, retention, trust/safety monitoring, or AI quality analytics.
- Source operational-processing workspace -> media ingestion, moderation queue, AI output validation, evidence review, creator approval, or incident processing.
- Source resource/cloud-drive management -> creator asset library, AI knowledge source management, saved prompt library, topic template library, media pack, or content-pack governance.

## 3. Choose Product Density

Pick one density mode:

- Consumer relaxed: feed, detail, profile, onboarding, creation. Use readable spacing, clear hierarchy, visible reactions, and approachable empty states.
- Productive compact: creator tools, analytics, moderation, settings, AI workspace. Use denser cards, filters, side panels, tables/lists, and compact controls.
- Hybrid: discovery page with a secondary creator/AI panel. Keep primary content readable and collapse secondary panels first.

Do not make consumer discovery pages look like internal operations software.

## 3.5 Required Design Checkpoint

Before implementing or approving any visible UI change, write a compact checkpoint that can be tested against the final screen:

- Surface type: mobile consumer, web consumer, web operational, or shared system.
- Density mode: consumer relaxed, productive compact, or hybrid.
- Implementation-owner checkpoint (rule text is canonical in `SKILL.md`'s implementation-owner checkpoint section; this checklist lists only the slots to fill — a checkpoint record must cite `checkpoint rules read: product-ui-ux-design/SKILL.md#implementation-owner checkpoint`, and a record without that citation is not valid):
  - Record before the first implementation edit for a runtime visible UI/UX slice (slice definition and rendered-vs-backend-only routing: see `SKILL.md`): persistent artifact (plan/checklist, MR notes, or evidence file) for branch/MR-bound work; the visible progress update only for a single-turn local edit reverted or discarded before the final response (chat-only exception conditions per `SKILL.md`), and any change that remains at final response, push, or MR time repeats the full checkpoint fields in a persistent artifact.
  - Include design owner (`product-ui-ux-design`), stack implementation owner, test owner (`testing-strategy`, loaded, with its assertion layer and rendered-evidence choice recorded, not only its name), entry-rule evidence, and rendered/device evidence status.
  - Stack owner mapping: `app-cross-platform-dev` for Flutter/RN/native mobile, `web-react-dev` for React web, `miniapp-product-dev` for mini-programs, `terminal-cli-dev` for terminal/TUI, the recorded project client-code convention, or `no-installed-owner` with the surface type named — `no-installed-owner` only when no project convention exists and the lookup completed — name the runtime/framework and where conventions were looked for; an incompletable lookup is recorded `unavailable`, never `no-installed-owner`; container-wins, project-convention lookup minimum, shared-token consuming-stack inventory, and `unknown-consumers`/`out-of-scope` handling all per `SKILL.md`'s stack-owner entry rules; an entry list limited to stacks the author happened to name is not an inventory.
  - Entry-rule evidence: a short quote, or the exact section/rule identifier plus the decision it produced — never only a file path, runtime name, or a vague anchor; runtime copy-only edits record `not-triggered (copy-only, existing component/viewport unchanged)` plus classification evidence that is measured — new text no longer than the old in every shipped locale, by rendered extent rather than byte/character count for width-constrained components (or a named length/viewport check; an unmeasured no-overflow assertion does not qualify; acceptable anchors and copy-only conditions: per `SKILL.md`); project-convention owners quote the convention line/rule applied; `no-installed-owner` records `no owner rule available`; trust/safety/risk-bearing copy never takes the copy-only path — full checkpoint plus risk grading routed to `feature-risk-router` (per `SKILL.md`).
  - Evidence status: `captured/verified` with an inspected artifact pointer, `planned` with a capture command, or `unavailable-with-owner`/`unavailable-no-owner` with attempt records — status semantics, fabrication bars, persistence/review-resolution rules, completion-claim consequences, and evidence-artifact sanitization (sanitized/test accounts; tokens, PII, credentials, private paths redacted) per `SKILL.md`; a bare `captured/verified` without a pointer is treated as `planned`; any status other than `captured/verified` blocks completion claims — report `pre-runtime-test ready`, `blocked`, or an explicit evidence gap with owner and next command/unblock action.
  - Remediation: naming an owner without loading its entry rules does not satisfy the checkpoint (the copy-only `not-triggered` path exempts only the stack-owner entry-rule quote, with every other checkpoint field still required); a missed checkpoint discovered by anyone is redone with an audit of the already-made diff per `SKILL.md`'s remediation rule.
- Primary workflow: the shortest successful path and the main return loop.
- Human logic: user intent in the next 10 seconds, likely anxiety/friction, attention order, motivation to continue, and trust concern.
- Aesthetic logic: intended mood, visual focus, density rhythm, contrast role, material treatment, and which details should feel restrained versus expressive.
- Visual direction: typography source, primary color source, neutral/background scale, radius/shadow role, token source versus new page-specific values, and whether two or three compact visual options were compared or deliberately skipped.
- Interaction logic: Discover -> Inspect -> Act -> Confirm -> Return, including what is progressively disclosed, what stays persistent, and where the user returns after modal/drawer/upload/generation/detail work.
- Behavioral logic: duplicate action protection, waiting feedback, disabled reasons, undo/retry/cancel, interruption recovery, and risk-matched confirmation.
- Psychology: users should know what is happening, what changed, what is safe to wait for or retry, what mistake risk exists, and how to recover without losing context or control.
- Layout structure: navigation/context, input/control region, content/result region, and secondary metadata.
- Required states: empty, loading/generating, success, failure/retry, disabled/permission, long-content, and narrow-width behavior where relevant.
- Trust boundary: generated content, publish/save limits, source/context/cost/model metadata, and any action that must not be implied.
- Visual acceptance: hierarchy, spacing, component fit, copy tone, no nested-card clutter, no generic dump of fields, and no text overflow.
- Behavioral/aesthetic acceptance: primary action feels obvious, feedback matches consequence, friction matches risk, mood fits the surface, and the result does not feel like a generic component demo.
- Recipe: choose one concrete recipe from `layout-recipes-and-screenshot-acceptance.md` before drawing or coding.
- Adaptation matrix: name the primary viewport, the stress viewport(s), the collapse rule, the spacing/density mode, and the screenshot/device checks that will prove the layout. For mobile, include safe-area and keyboard behavior; for desktop workbenches, include secondary-panel collapse before primary content becomes unreadable.

Run the checkpoint in this order so it changes the result, not just the wording:

1. Aesthetic logic: decide layers, white space, density, alignment, rhythm, color weight, radius/shadow restraint, and visual focus around the primary task.
2. Visual direction: if the screen is new or substantially reshaped and no strong design reference exists, compare two or three compact directions before coding or final acceptance; if reusing existing product language, state the exact theme/token source and what stays unchanged.
3. Interaction logic: decide entry point, current task, next step, progressive disclosure, confirmation, return path, and how complex work is split across pages, drawers, sheets, toolbars, or stages.
4. Behavioral logic: decide what users may repeat, misclick, wait for, abandon, undo, retry, cancel, or recover after interruption, and place visible state/control for each risk.
5. Psychology: reduce cognitive load and uncertainty, explain disabled or risky actions, keep users feeling in control, and make high-impact actions feel deliberate before execution.

For admin, operations, moderation, analytics, creator-tool, and AI-review workspaces, a component library is only the implementation vocabulary. Do not describe the design as "Ant Design style" or similar without the checkpoint above. A good operational screen should make the next operator action obvious within five seconds. It should not rely on a dark hero, decorative gradient bar, oversized empty illustration, or marketing-page composition; use compact controls, readable hierarchy, clear status, and obvious work regions instead.

## 3.6 Operational Workspace Quality Pattern

For admin, operations, moderation, analytics, creator-tool, and AI-review pages, use this pattern unless a stronger product-specific design exists:

- Header: keep the app shell header factual and restrained. Do not repeat a large inner page title unless it adds task context.
- Control bar: place scope/filter/mode switches and primary context in a compact horizontal band near the top.
- Status strip: expose trust boundary, selected scope, permission/state, and mode as small operational facts, not as promotional copy.
- Workbench: use a clear input/control region and a review/output region. The output region should show the shape of the future review object even before data exists.
- Dynamic workbench: data-driven module visibility, ordering, and status are valid. The empty or no-permission view should still show the intended module structure, next action, and future data slots.
- Empty state: prefer a compact placeholder skeleton, checklist, or next-action hint over a large illustration. Empty states should teach what will be reviewed, not fill space.
- Review state: make generated title, summary, reasons, model/prompt/cost/status, and source/trust metadata scannable without a table dump.
- Visual tone: quiet contrast, crisp borders, stable spacing, readable labels, no decorative gradients, no oversized cards, no unused first-screen dead area.
- User psychology: operators need certainty and control more than delight. Show where the work came from, what changed, what is pending, what is safe to retry, and how to recover after interruption.
- Component hierarchy: navigation, tables, modals, empty states, charts, progress steps, alerts, annotations, and toolbars are chosen for their task role. Do not drop a component onto the page until its state, density, fallback, and return behavior are defined.

## 4. Required States

Use `product-surface-patterns.md` as the canonical state taxonomy. For every feature, map that taxonomy to concrete UI behavior. Add community, finance/data, AI, or operational scenario states only when the target surface needs them.

Do not ship only the happy path.

For visual implementation, use the empty/loading/error/success templates in `layout-recipes-and-screenshot-acceptance.md`. The state must occupy the same layout geometry as the final content unless the whole surface is terminally unavailable.

## 5. Component Defaults

Mobile:

- Navigation: `TabBar`, `NavBar`, `Tabs`, `CapsuleTabs`.
- Feed/detail: `List`, `Card`, `Avatar`, `Image`, `ImageViewer`, `Tag`, `InfiniteScroll`, `Skeleton`.
- Creation/AI: `ImageUploader`, `TextArea`, `Input`, `Button`, `ProgressBar`, `Toast`, `Dialog`, `Modal/Bottom sheet`.
- Comments/actions: `FloatingPanel`, `Popup`, `ActionSheet`, `SwipeAction`.
- Account/settings: `Form`, `List`, `Switch`, `Picker`, `CheckList`, `Radio`, `PasscodeInput`.

Web/Desktop:

- Feed/detail: `Card`, `List`, `Avatar`, `Image`, `Tag`, `Badge`, `Tooltip`, `Popover`, `Skeleton`, `Empty`.
- Creator/moderation/settings: `Form`, `Input`, `Select`, `Switch`, `Radio`, `Checkbox`, `Upload`, `Steps`, `Progress`, `Drawer`, `Modal`.
- Notifications/feedback: `Message`, `Notification`, `Alert`, `Result`.
- AI workspace: `Layout`, `Splitter`, side panels, upload, progress, streaming/loading, retry, edit, and result states.

## 6. Token Rules

- Use design-system semantic tokens before raw colors.
- Tokens should express a coherent product visual language, not fall back to generic neutral defaults without a reason.
- Preserve Light/Dark mode support when the surface supports theming.
- Use mobile 4/8/12 radius roles for mobile; use desktop 2/4/6/8/12/16 radius roles for web.
- Use desktop Default mode for consumer web readability; use Compact mode for dense tools.
- Do not invent one-off spacing, color, radius, or font rules unless the product requirement clearly needs a new token.

## 7. UI Copy Guardrails

**A. Domain / product copy**：
- Do not copy old source domain words into the new product UI.
- Use product-appropriate copy. For community products: post, reply, topic, creator, follow, join, publish, draft, review, report, block, mute, notification, AI suggestion, generated draft. For finance/data products: source, evidence, watchlist, portfolio, risk, review, explain, export, permission, data freshness, and decision support.
- Keep destructive copy explicit: delete, report, block, publish publicly, leave community, discard draft.
- Empty states should invite the next action, not just say no data.

**B. Microcopy structural rules**（reviewer 可直接 block 不满足的 PR）：
- **Button labels = verb + specific object**：`Save changes` / `Send message` / `Discard draft`. **Avoid generic labels when action/consequence is not obvious from context**（典型弱例：`Submit` 无对象、`OK`/`Confirm` 遮蔽结果）。在平台 dialog 标准位 `Cancel` / `Close` / `OK` / `Done` 等仍可用。Destructive 必须比中性更显式（参 [[behavioral-aesthetic-logic.md]] + `interaction-design-patterns.md` Serious/Financial 段的 destructive/irreversible/外部可见/付费 trust-sensitive 边界）：`Delete forever` 而非 `Remove`。
- **Error message 结构**：(1) **what happened**（用户语言，非 stack trace / error code）+ (2) **why — when useful and safe to disclose**（auth/session/policy/anti-abuse/backend 内部不暴露；如 `Session expired. Sign in again.` 不必给原因）+ (3) **what to do**（具体动作：retry / contact support / 修哪个 input）. Anti-pattern：`Something went wrong` / `Error 500` / `Unknown error` 作主 copy（error code 可入 expandable technical details / support reference）。
- **Disabled control**：默认必有原因（tooltip / inline helper / 旁边一句话）+ 启用条件，让用户知道下一步。**例外**：unavailable by policy / permission / security 且暴露条件不安全 → **隐藏 control** 或给通用 permission 解释（不暴露具体策略）；不存在"恒不可启用"且只剩 disabled 状态的 control（应直接隐藏）。
- **Success / confirmation 必具体**：说清成功了什么 + 如适用给下一步。`Message sent to alice@example.com — view in Sent` 而非 `Success` / `Done` / `OK`。
- **Voice consistency**（可枚举的 reviewer 检查项，不空喊）：(a) 无内部代号 / 项目代号 / 服务名出现在用户文案；(b) 同一动作 / 对象不混用术语（如不同页面别一处叫 "send"、一处叫 "submit"、一处叫 "post"）；(c) 无未解释 jargon；(d) 无翻译腔（直译机翻味）；(e) 时态 / 人称 / 大小写统一。

## 8. Review Checklist

Before calling a design or implementation complete, verify:

- The screen supports the primary product loop: discover/enter -> inspect -> act -> confirm -> recover/return.
- Main action and secondary actions have proper hierarchy.
- Interaction logic passes `behavioral-aesthetic-logic.md`: the canonical Discover -> Inspect -> Act -> Confirm -> Return loop from `interaction-design-patterns.md` matches user intent, risk, trust, and motivation.
- Aesthetic logic passes `behavioral-aesthetic-logic.md`: mood, rhythm, contrast, material treatment, and delight support the product purpose.
- Frontend, test, and acceptance checks use `behavioral-aesthetic-logic.md`: rendered behavior preserves attention order, risk friction, recovery, trust cues, and return context, not only visual component correctness.
- Long names, long posts, badges, tags, and metadata do not break layout.
- Mobile keyboard/safe-area states are covered where relevant.
- Web narrow-width behavior collapses secondary panels before damaging content readability.
- AI states include generating, retry, edit, source/citation where relevant, and failure handling.
- Trust/safety states are visible and understandable.
- Trust-sensitive AI/data features expose source/context, permission state, recovery, and observable request/task outcomes.
- Visual polish passes `visual-craft.md` anti-slop and brand-consistency checks.
- Screenshot acceptance passes `layout-recipes-and-screenshot-acceptance.md` with realistic long text, no data, partial data, and error data.
- The adaptation matrix was checked in the rendered implementation: primary viewport, stress viewport, collapse behavior, safe-area/keyboard where relevant, long text, empty/partial/error state, and no layout shift around loading or dynamic modules.
- For operational/admin/AI-review workspaces, the rendered screen looks like a focused work surface, not a landing page: no hero-style banner, no decorative gradient-as-design, no oversized empty illustration, no large unused first-screen area, and no layout where the real task starts below unrelated dashboard content.
- Component choices follow this skill and existing codebase primitives.
- Launch readiness and iteration risks pass `product-lifecycle-acceptance-and-iteration.md` when the work is close to release or already shipped.
