# UI/UX Judgment Extraction

Use this reference when extracting reusable UI/UX, frontend, app, or client-facing skill rules from Figma, code, screenshots, product reviews, or repeated implementation work.

The goal is to turn source evidence into rules that help future teams produce good-looking, behaviorally sound, testable product surfaces without needing access to the original source.

Figma and code have different evidence roles:

- Figma is the experience-intent source: visual hierarchy, layout, component states, interaction model, content density, mood, and state families.
- Implementation code is the runtime-behavior source: route ownership, state machines, API/cache/rollback, disabled reasons, retry, duplicate guards, bridge behavior, persistence, performance, accessibility, and recoverability.
- Design systems and implementation themes are the visual-token source: typography family/roles, primary/semantic colors, neutral/background scale, spacing rhythm, radius, shadow/elevation, component density, and whether page-level styling follows or diverges from shared tokens.

For any extraction that claims interaction logic, behavioral logic, psychology, development guidance, testing guidance, or launch acceptance, corresponding frontend/app/client code is required unless it is unavailable or explicitly out of scope. If code is unavailable, mark the result as design-intent extraction only and do not claim runtime behavior was validated.

## Required Method

Do not start by writing principles. For each target workflow or screen family, build this chain:

| Step | Required output |
| --- | --- |
| Observation | What exact state, layout, interaction, code path, recovery path, or runtime mechanism was inspected. |
| Judgment | Which layer the observation affects: aesthetics, interaction logic, behavioral logic, psychology, accessibility, motion/feedback, or microcopy. |
| Rule | A source-neutral instruction future agents can execute. |
| Acceptance | Screenshot, rendered device/browser check, unit/component/E2E scenario, or review pressure scenario that proves the rule works. |

Rules that cannot name an observation and an acceptance check stay out of executable skill guidance. Keep them as hypotheses or discard them.

## Four Judgment Layers

| Layer | Extract from source evidence | Convert into reusable rules |
| --- | --- | --- |
| Aesthetics | Visual focal point, hierarchy, density, rhythm, spacing, type scale, color weight, material treatment, mood, and whether the screen feels intentional. | Which element leads, how dense the surface should be, what visual weight belongs to primary/secondary/exception content, and how the mood supports the task. |
| Visual direction and tokens | Typography source, primary color source, neutral/background scale, radius/shadow role, token/component theme mapping, and variant directions when no strong reference exists. | Whether to reuse the existing product visual language unchanged, tighten token usage, or compare two or three compact visual directions before implementation or acceptance. |
| Interaction logic | Entry, current task, next action, return path, modal/drawer stack, deep link, tab/route hierarchy, input method, gesture conflict, progressive disclosure, and task continuity. | Discover -> Inspect -> Act -> Confirm -> Return flow, plus navigation, keyboard, gesture, and return-context rules. |
| Behavioral logic | Repetition, hesitation, mistakes, waiting, abandonment, retry, undo, cancel, disabled states, interruption, stale state, and recovery. | State-machine and recovery rules: duplicate guard, rollback, retry, confirm, disabled reason, progress, queue boundary, and restore behavior. |
| Psychology | Anxiety, uncertainty, perceived control, confidence, trust, motivation, consequence, cognitive load, fatigue, and regret avoidance. | Certainty/control/trust rules backed by visible status, consequence copy, reversible actions, local recovery, progress proof, and risk-matched friction. |

For each layer, mark the delta: `new`, `confirmed`, `narrowed`, `routed`, or `no new evidence`. Do not count a restatement of a known principle as a new extraction.

### Visual Direction And Token Provenance Minimum

For UI/UX, Figma, web, or app extraction, the visual direction/tokens layer must record these fields before any claim of `new`, `confirmed`, or `narrowed`:

- Typography: font family, size steps, line-height rhythm, weight roles, and where dense versus expressive type is allowed.
- Color: primary/action/selection source, neutral text and background scale, line/divider color, semantic status colors, and whether raw page colors match or diverge from shared tokens.
- Shape/material: radius scale, shadow/elevation role, surface layering, density mode, and component state variants.
- Visual mood: the task mood the source supports, such as calm workbench, expressive creation, high-trust review, or fast repeated operation, plus where expressive treatments such as gradients or illustration are allowed.
- Implementation mapping: the theme, token file, component library, CSS variables, or style layer that carries the source intent; if implementation code is unavailable, mark runtime token provenance unavailable and do not claim dev validation.
- Acceptance owner: the design reference, web/app skill, testing matrix, or product workflow rule that must change. If no target changes, record why the existing rule already covers the evidence.

A row that only says "tokens confirmed" or "视觉方向已确认" is incomplete. Downgrade it to `source inventory` until the fields above are filled or explicitly ruled out of scope.

## Static Proxy Evidence

Figma and code are not live user research. To infer behavior and psychology responsibly, use observable proxies:

| Human issue | Static proxy evidence |
| --- | --- |
| User may not know what to do next | Primary action visibility, disabled reason, empty-state next step, route title, active tab, selected item, progressive disclosure. |
| User may fear losing work | Draft state, autosave indicator, unsaved-change guard, undo/cancel, return context, persisted state, restore after interruption. |
| User may make accidental bulk or destructive changes | Confirmation depth, consequence copy, preview-before-commit, apply-once versus remember choice, second confirmation, cooldown or acknowledgement. |
| User may wait or abandon | Progress state, skeleton versus spinner choice, local retry, timeout handling, partial success, queued/pending/final distinction. |
| User may repeat a high-volume task | Stable control positions, keyboard shortcuts or compact controls, low-noise visual rails, current item/progress, batch mode, fatigue-reducing density. |
| User may hit weak network or runtime failure | Retry region, old-content hold during reload, offline/weak-network state, rollback, cache hit, error mapped to next action. |
| User may lose place after navigation or orientation change | Route/context ownership, scroll restore, selected item restore, geometry reset, shell orientation cleanup, back-stack behavior. |
| User may distrust automation or generated output | Source/caveat, editable generated state, review-before-commit, confidence/quality state, regenerate/retry, human final action. |

If no proxy is visible, mark the layer `no new evidence` instead of inventing a psychology rule.

## State Family Inventory

For UI/UX extraction, read state families rather than only the default screen:

- Initial, normal, long-content, dense-content, empty/no-data, loading, slow/weak network, error/retry, permission/no-access, disabled, confirmation, success, partial-success, failure-recovery, stale/expired, interruption/return, repeated-use/cache-hit.
- Device and environment variants: narrow/wide, portrait/landscape, keyboard open, safe area, text scaling, dark/light mode, reduced motion, offline, bridge/native capability missing, old browser/WebView fallback.
- Product variants when visible: first-use, returning-use, guest/authenticated, permission-limited, feature-flagged, degraded, version-incompatible, and A/B or gray-release branches.

Record which states were read, unavailable, excluded, or still pending. Do not call the extraction complete if required state families are only sampled.

## Aesthetic Proxies And Thresholds

Use source-specific judgment, but verify with concrete proxies:

- One primary visual focus per task state; secondary controls should not compete with the main artifact or decision.
- Use stable spacing rhythm such as 4/8px increments unless the source system clearly uses another rhythm.
- Record token provenance before extracting visual rules: the source of typography, primary color, neutral/background scale, radius, shadow/elevation, and component density. If the source has multiple plausible visual directions or the implementation code hardcodes page-level colors, treat that as extraction evidence and decide whether the reusable rule should require a visual direction comparison, token cleanup, or both.
- Touch targets should meet platform norms: at least 44pt on iOS and 48dp on Android where touch is required.
- Text contrast should meet WCAG expectations for normal and small text; do not rely on brand color alone for state.
- Dense work surfaces should keep stable row/card height, fixed context when identity would be lost, and local overflow affordance instead of decorative whitespace.
- Modal, drawer, overlay, and floating tool visual weight should match consequence: lightweight details should not look as severe as destructive confirmation.
- Motion and delight should support task comprehension, success, or recovery; do not add decorative motion to error, permission, payment, or destructive states.

## Interaction Extraction Checklist

For each flow, inspect and record:

- Entry sources: home/list/card/deep link/notification/search/return.
- Current-state proof: selected item, active tab, route title, progress, pending/committed marker, scope/filter chips.
- Next action: primary action, disabled reason, secondary action, escape/cancel, help/detail.
- Progressive disclosure: drawer, sheet, modal, tooltip, advanced settings, detail page, preview.
- Return path: after submit, cancel, failure, detail view, orientation change, background/foreground, and route replacement.
- Input and gestures: keyboard reachability, IME behavior, paste/delete/caret, swipe conflict, pinch/zoom/pan, drag boundary, tap fallback.
- Stack rules: modal-over-modal avoidance, drawer return context, overlay cleanup, deep-link recovery, native/web bridge fallback.

## Behavioral And Psychology Anchors

Each behavioral or psychology rule needs at least one falsifiable anchor:

- Hick: reduce active choices while the user is deciding; reveal controls when inspecting or correcting.
- Fitts: repeated or high-risk controls need stable placement and adequate hit area.
- Miller/cognitive load: chunk dense information; do not force users to hold hidden context across modal or route changes.
- Doherty/feedback timing: show feedback quickly for user actions; use visible pending/final states for long work.
- Error prevention: prevent invalid input before submit when possible; when not possible, show local repair guidance.
- User control: provide cancel, undo, retry, edit, restore, or explicit irreversible confirmation depending on consequence.
- Trust: show source, scope, permission, timestamp, automation caveat, and consequence near the affected decision.
- Fatigue: for repeated work, reduce visual noise, preserve motor memory, show progress, keep current item visible, and avoid surprising layout shifts.

## Microcopy And Error Attribution

Microcopy is part of UI/UX extraction:

- Empty states should explain what is missing and what the user can do next.
- Disabled states should name the missing requirement or permission when user action can repair it.
- Error copy should map failure to a recovery path; avoid raw transport envelopes, stack traces, or blame-shifting.
- Confirmation copy must state consequence, scope, and reversibility for destructive, public, costly, bulk, or default-setting actions.
- Automation copy should separate generated suggestion from user-owned final decision.

## Routing And Landing

Before editing target skills, build a target-output map:

- Design/reference target owns visual hierarchy, interaction model, UX states, mood, acceptance screenshots, and no-source-access usage.
- Web or app dev target owns route/state/API/cache/bridge/gesture/performance implementation rules.
- Testing target owns scenario matrices, assertions, device/browser smoke, accessibility checks, and recovery tests.
- Product workflow target owns readiness gates, launch acceptance, high-risk consequences, and iteration signals when the change affects product delivery.
- Extraction workflow owns method, coverage, evidence, and validation rules.

If a source-derived rule touches more than one owner, update each owner or record why it is unchanged.

## Minimum Pressure Set

For UI/UX extraction beyond wording-only cleanup, pressure-test the resulting rules against:

- Long content or dense content.
- Empty/no-data.
- Loading and slow/weak network.
- Error with retry.
- Permission/no-access or disabled action.
- Narrow viewport or small device.
- Accessibility text scaling or screen-reader/focus implication.
- Orientation, viewport, keyboard, or safe-area change when relevant.
- Interruption and return recovery.
- Repeated-use or cache-hit path.

For mobile/native-hosted surfaces, also check native bridge unavailable, back behavior, foreground/background, and host-shell cleanup when relevant.

## Completion Gate

Do not claim systematic UI/UX extraction unless all are true:

- The validation pass reopened relevant Figma/design/code/runtime artifacts after the method or target skill changed. A pressure test that reads only the skill files is a static review and cannot prove the method changes future extraction behavior.
- Source register rows for required Figma/code/state families are closed, explicitly excluded, unavailable, or downscoped.
- Observation -> judgment -> rule -> acceptance is recorded for each landed rule.
- Judgment-delta matrix covers visual direction/tokens, aesthetics, interaction logic, behavioral logic, and psychology.
- Target-output map matches the actual diff across design, web/app, testing, product workflow, and extraction workflow owners.
- Minimum pressure set is passed or explicitly marked not applicable.
- Executable guidance has no source-domain names, internal project names, real business copy, source IDs, or one-off implementation details.

## Pressure-Test Protocol

Use this when validating that an extraction skill or design/client skill actually changes future behavior:

1. Pick a source-backed workflow that previously exposed a failure, such as missed source reads, shallow UI/UX rules, routing gaps, accessibility gaps, or overclaim.
2. Reopen at least one design artifact and one runtime artifact when behavior, psychology, implementation, testing, or launch acceptance is being claimed.
3. Record what changed in the extraction method before the test, then run the source evidence through the required chain: observation, judgment, rule, acceptance.
4. Compare the result against current skills. If the source reveals a gap, update the smallest owning skill/reference. If it confirms existing guidance, record that no new rule was needed.
5. Mark the coverage honestly: targeted pressure test, file-level refresh, node/artifact inventory, or full workflow extraction. Never upgrade a targeted pressure test into a full-source claim.
