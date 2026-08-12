# Product Page Checklist

Use this reference for miniapp product surfaces, PRD-to-page mapping, and rendered acceptance.

## Page Contract

- Entry: tab, route, subpackage, share card, QR code, push/subscription, search, or embedded webview. For share / QR / scene entry, treat the payload as untrusted: schema-parse, server-authorize the target against current identity, require backend-issued share tokens for any unlock/attribution flow (TTL-bounded, replay-protected).
- Params: required, optional, defaults, expired/missing target, permission-limited target, identity-mismatched target (the share/deep-link referenced another user's resource — fail closed, do not silently fetch).
- Navigation: back behavior, tab switch, subpackage boundary, re-entry, duplicate route prevention. Verify the route-API match statically — `switchTab` only for tab pages, `navigateTo` for subpackage pages with loading/fail callback handling, `reLaunch` only for full-restart flows.
- State owner: page-local state, global app state, storage, URL/scene params, server data, and feature flags.
- Data freshness: first load, refresh, stale cache, optimistic update, invalidation, offline fallback.

## Required States

Every user-facing miniapp page should define:

- Loading: skeleton or stable reserved geometry, timeout behavior, pull-to-refresh interaction.
- Empty: first-use, filtered-empty, permission-empty, no-network-empty when different.
- Error: transport, auth/session, permission, validation, server business error, unsupported platform.
- Success: normal state, partial data, long list, pagination, and no-more state.
- Pending/finality: submitted but unresolved, payment pending, upload pending, review pending, retry in progress.
- Recovery: retry, refresh, re-login, open settings, contact support, go back, or alternate route.

## Mobile Miniapp UX

- Primary action must remain reachable with safe-area and keyboard constraints.
- Avoid layout jumps when loading, switching tabs, refreshing, or restoring from background.
- Use platform-native affordances where expected: pull-to-refresh, share menu, settings handoff, toast/modal/action sheet conventions.
- Compact pages still need accessible names for icon-only controls, sufficient touch targets, and visible focus or active state where supported.
- For dense data, keep column headers/context visible or provide strong orientation/scroll affordance.

## Design Acceptance

Before implementation or completion, record:

- Surface type and target platform.
- Primary workflow and success metric.
- Page structure, navigation, and state list.
- Trust/safety boundary: auth, money, privacy, generated content, or user data.
- Screenshot or rendered inspection evidence for changed visible states.
