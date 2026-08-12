# Web UI Quality

## Rendered Surface Checks

- Inspect changed screens in a real browser for layout, hierarchy, density, responsive breakpoints, scroll behavior, empty/error states, and dynamic content.
- Capture screenshots or browser evidence for nontrivial UI changes.
- Watch for text overflow, unstable heights, clipped controls, nested cards, accidental hero layouts in work surfaces, and visual states that move layout unexpectedly.
- Gate web-font loading so a late font swap does not reflow text (a CLS source). Note `font-display: swap` *avoids invisible text (FOIT) but can itself cause the swap shift* — to minimize layout shift use `optional` (locks to the fallback for the page if the font is slow) or keep `swap`/`fallback` but match metrics with a `size-adjust` / `ascent-override` / `descent-override` fallback `@font-face` plus `<link rel=preload>`; reserve `block` for tiny icon-font cases. For script-measured text, do not block first render on `document.fonts.ready` alone — it only ever resolves (a stalled font can delay it to the UA timeout, and a failed font still resolves); instead reserve space with fallback-compatible metrics, render, then remeasure after `document.fonts.load("400 16px <family>", sampleText)` resolves (the first argument is a CSS font shorthand string, not a family name alone) or a bounded timeout/`requestAnimationFrame` fallback fires. Reserve space for async-loaded images, media, and embeds the same way so first paint does not jump.
- Verify the four UI/UX judgment layers in the rendered page:
  - Aesthetic: hierarchy, rhythm, contrast, spacing, material treatment, and mood match the design checkpoint.
  - Interaction: the visible flow makes the next action clear, preserves context through drawers/modals/details, and returns users to the right place.
  - Behavioral: pending, disabled, retry, cancel, duplicate-submit, offline/stale, partial, and interrupted states are visible where relevant.
  - Psychology: the screen reduces uncertainty, waiting anxiety, fear of mistakes, and loss of control.

## Accessibility

- Prefer semantic HTML before ARIA. Use buttons for actions and links for navigation.
- Every interactive control needs an accessible name, keyboard reachability, visible focus, and a clear disabled/loading state.
- Forms need labels, validation messages associated with fields, error summary when useful, and keyboard-friendly submit/retry behavior.
- Modals, popovers, menus, and drawers need focus management, escape/outside-click behavior where appropriate, and return focus on close.
- Check contrast, text wrapping, zoom/text scaling, and screen reader names for icon-only controls.

## Responsive And Browser Behavior

- Define stable dimensions for fixed-format UI such as grids, toolbars, tables, boards, and controls.
- Define the primary viewport, stress viewport, and collapse rule before coding. Secondary panels, filters, metadata, and previews should collapse or dock before the primary reading/editing region becomes unusable.
- Use virtualization or pagination for large lists/tables when rendering cost becomes visible.
- Preserve useful URL state for shareable/filterable pages.
- Handle back/forward, reload, auth expiry, offline/stale data, and browser storage expiry deliberately.
- Long task and upload/review pages should model route-leave, reload, polling timeout, stale task, and terminal failure as component states when the user could lose work or confidence.
- Dense operations tables need browser checks for long service names, domains, image tags, owner names, status messages, fixed action columns, horizontal scroll, and narrow desktop stress width before the page is treated as shippable.

## Chart And Analytics Workbench Implementation

- Own chart/table modules as runtime state, not static presentation. Keep active scope, selected module, chart/table mode, local settings, comparison target, export/download job, loading/empty/error/stale state, and drill-down context in explicit React owners.
- Use a shared chart adapter for repeated chart behavior: number formatting, percent precision, zero-label hiding, long-label rotation/truncation, scroll/data-zoom thresholds, legend scroll, tooltip wrapping, mark-line labels, resize cleanup, and negative/under-baseline label placement.
- Separate raw threshold mode from comparison mode in state and rendering. Threshold mode uses configured bands; comparison mode uses higher/lower semantics against a selected baseline. Switching modes must update legends/copy and preserve compatible filters.
- User-scoped visual settings need scoped cache keys, invalid-interval validation, disabled save, inline error, reset/default behavior, and module-level refresh of affected data without reloading the whole workbench.
- Dynamic grouped tables need fixed identity columns, right-aligned numeric cells, grouped headers generated from data shape, sticky or fixed columns only while they remain readable, horizontal scroll boundaries, and measured overflow tooltips for long labels.
- Entity/sub-item breakdown charts need source and target selectors that cannot select the same entity, special baseline options modeled explicitly, split loading/error/retry for each compared side when the data is fetched separately, and cache invalidation by scope/type/id.
- Chart cards should keep stable geometry under loading, empty, error, long legends, data zoom, and table mode. A 400px-class chart region, compact title/action row, and stable table container are safer than content-sized charts that jump while data loads.
- Visual token ownership still applies to analytics pages: theme-map repeated primary, neutral background, border, text, muted text, semantic comparison, and status colors. Local hard-coded chart series colors are acceptable when documented by the chart adapter and covered by legend/contrast checks.

## Shared UI Fallback Surface

In a portfolio that ships multiple React apps, the three "non-happy-path" surfaces below drift visually and behaviorally when each app re-rolls its own. Treat them as portfolio-level shared components, not per-app implementations:

- **Loading surface**: spinner / skeleton / shimmer choice, sizes (page-level vs box-level vs inline), and copy (a localized "loading..." string vs nothing). Apps consuming the same brand should share at least the box-level and page-level loading components.
- **Empty surface**: empty illustration / icon, primary message, secondary explanation, primary action (refresh / create / change filter), and the "this is empty because" diagnostic line when the user might think the page is broken.
- **Error surface**: error illustration / icon, user-readable message, support handle (request id / trace id surfaced to the user for support), primary recovery action (retry, go home), and a secondary path (report bug). A bare generic "request failed" toast that never surfaces the request id is a support-cost finding.

A single global `ErrorBoundary` at the route layer plus one inline `<DataBoundary>` (loading / empty / error tri-state) component cuts most of the per-page reinvention. Per-app variants are acceptable only when the surface has a domain reason (chart card vs list vs form).

## Shared Device And Inactivity Session

When the surface runs on a shared device (a public kiosk, a counter-staff terminal, a lobby check-in screen, a clinic intake tablet, a retail store-back tablet) rather than a personal device, the session-management contract differs from a normal web app:

- **Inactivity detection listens on the full input event set**: `pointerdown / mousedown / click`, `touchstart / touchmove / touchend`, `mousemove`, `scroll`, `keydown` — at minimum. A subset misses real activity classes: pointer-only misses touch; click-only misses scroll-only browsing; keyboard-only misses pure-touch UIs. Each registered listener is removed in the cleanup return value of the same hook / effect — leaked listeners survive Hot Module Replacement and accumulate during development.
- **Custom scroll containers register their own listeners**: when the page uses CSS-Y-scroll containers (`overflow: auto` divs, virtualization wrappers) instead of body scroll, the `scroll` event does not bubble to `document` and the inactivity timer does not reset on scroll-only interaction. Add an explicit selector (`.scrollable-div`, `[data-scroll-region]`, framework's scroll-container class) and register the listener on each matched node, with the same cleanup.
- **Reset is throttled, not raw-debounced**: `lodash.throttle(..., 200ms)` (or equivalent) wraps the timer-reset callback so a continuous gesture (mousemove drag, touch scroll inertia) does not call `clearTimeout / setTimeout` hundreds of times per second. The throttle window is short enough that the user's last gesture still resets the timer.
- **Two-stage terminal UX**: detect inactivity → show a modal with a visible countdown ("system will exit in 5s") that the user can dismiss with a primary "stay" action; on countdown 0 with no dismissal, run the terminal action (logout, return to neutral home, lock screen). Single-stage immediate logout loses the user's in-progress work on a stale screen; no-countdown modal leaves users uncertain what is about to happen.
- **Terminal action is "return to neutral", not "log out and stay"**: on a shared device the next user is a different person, so the terminal action navigates to a known clean state (the public home page with no user context, the login screen, the device's welcome surface). Just unsetting `auth.user` leaves the previous user's UI state visible until the next navigation — a privacy leak the rest of the page does not know to clear.
- **Cross-tab / cross-component coordination: durable store is authoritative, broadcast is only notification**: tabs coordinate through `localStorage` (or another durable same-origin store like IndexedDB) holding the shared `lastActivityAt` / `expiresAt`. `BroadcastChannel` may be added as a low-latency notification path that wakes other tabs, but the broadcast carries no authority — every consumer re-reads the durable store before acting. Immediately before running the terminal action, the tab re-reads `expiresAt` from the same durable store that holds it and aborts if another tab has extended it. `BroadcastChannel` alone is unsafe: BroadcastChannel state is per-tab and in-memory, a throttled background tab or a BFCache-resumed tab missed every prior broadcast and has no way to learn the current `expiresAt`. Broadcasting "activity happened" alone (without the durable store backing it) lets an idle tab run the terminal action milliseconds after another tab refreshed activity. Scoping: the shared key includes `device-mode` (shared-device vs personal-device) so personal-tab activity on the same origin does not extend shared-device sessions.
- **Inactivity timeout is shorter on shared devices than personal**: 30s to 5min is the realistic shared-device range (public kiosk ≈ 30s-2min, counter terminal ≈ 5-15min); the same app on a personal device might be 30min to never. Choose the value from the deployment context, not from the developer's laptop.
- **Server-side session expiry is independent of client-side inactivity**: client-side inactivity is a UX defense (clean handoff between users on the device); the server enforces session lifetime, idle-token expiry, and concurrent-session limits independently. A client that quietly extends a session by faking activity must still be cut off by the server's token TTL. Conversely, a network-disconnected client whose timer pauses does not get an indefinite session — the server invalidates it on its own clock.

## Animation And View Transitions

- **Prefer compositor-friendly properties for hot-path motion.** Use `transform` and `opacity` for high-frequency, large-area, route, scroll-linked, or continuous motion — the browser can usually animate them off the main thread; avoid animating layout properties (`width`, `height`, `top`, `left`, `margin`) on hot paths, since they retrigger layout each frame and jank. Targeted paint-only transitions (`color`, `background-color`, `border-color`, shadow) are fine for small state/theme changes. Never use `transition: all` — list the exact properties so an unrelated change does not animate unexpectedly. Use `will-change` sparingly and remove it after the animation.
- **Honor `prefers-reduced-motion` for any non-essential motion.** Wrap transitions / parallax / autoplay / continuous-loop animations in `@media (prefers-reduced-motion: reduce)` (CSS) or `matchMedia('(prefers-reduced-motion: reduce)')` (JS) — substitute instant state change for animation. Decorative motion that ignores the user setting is an accessibility finding.
- **View Transitions API is progressive enhancement only.** For SPA in-app transitions use `document.startViewTransition()`; for cross-document MPA navigation the `@view-transition` CSS at-rule is the opt-in. Feature-detect (`'startViewTransition' in document`) before invoking the JS API; the non-transition path (instant DOM update) MUST be the fallback. Browsers without support, users with `prefers-reduced-motion: reduce`, and slow devices all need the no-animation outcome to work identically. **Framework router integration is not universal** — Next's view-transition config and React's `<ViewTransition>` component are still flagged experimental / Canary at the time of writing; verify your router's integration status before adopting at the route layer.
- **Transitions never delay user-perceptible feedback.** A submit button that animates the form away before showing pending/success state hides the action result. Use view transitions for navigation choreography between stable states, not as a substitute for loading / disabled / error UI.
- **Transitions cannot block focus restoration.** When a route or modal transition starts, focus must still land on the post-transition target (heading, primary action, error message) within the same frame the transition completes — keyboard users cannot wait for animation to interact.
- **One transition system per portfolio.** Mixing `framer-motion` + `react-spring` + raw `@keyframes` + View Transitions in the same app fragments timing curves, easing, and reduced-motion handling. Pick one for component-level motion (framer-motion is common) and use View Transitions for route-level choreography when supported; document the split.

## Cross-Cutting Concerns At Implementation Time

These cross-cutting concerns get under-invested when each PR ships one feature; capture the implementation rules at the portfolio level:

- **i18n boundary**: wrap user-visible strings in the i18n call site even when the portfolio ships in one language today; the lint plugin (or a custom one) flags string literals in JSX as findings. The cost of catching them at write time is small; the cost of migrating thousands of literals later is large.
- **a11y baseline**: enable `eslint-plugin-jsx-a11y` recommended rules; a per-PR cap of jsx-a11y violations starts at "current count" and only ratchets down. Focus management for modal / drawer / popover open-close cycles is a per-component checklist, not optional polish.
- **Responsive breakpoint source**: read breakpoint values from one place (the CSS engine config, the component suite theme, or a shared `breakpoints.ts`). A raw `max-w-[600px]` in one app and `lg:px-8` in another is acceptable as long as both resolve to the same scale.
- **Trace surface for support**: every user-visible error should surface the request id / trace id (small text, copy-on-click, or attached to the bug-report flow). Without it, on-call cannot map a screenshot to a log line. Read it from the response header (the back end already emits it — see the cross-stack contract in `python-service-architecture/references/api-contract-and-schema.md` and `go-microservice-architecture/references/protobuf-contract-architecture.md`).
