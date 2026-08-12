# Contracts And State

Use this reference when miniapp work touches API integration, auth, storage, analytics, or finality.

## API Contracts

- Define request params, response envelope, error codes, retryability, idempotency, and trace/request id behavior.
- Map backend errors to user-facing copy and recovery controls; do not expose raw transport errors.
- Preserve cancellation semantics for route changes, repeated taps, pull-to-refresh, and background/foreground transitions.
- For long-running operations, define polling, refresh, timeout, and final-state reconciliation.

## Auth And Identity

- Separate platform login code, app session token, bound account, phone/profile authorization, and backend identity.
- Centralize auth in one state machine. Token refresh runs as **single-flight** — concurrent expired-token responses share one in-progress `Taro.login` + code-exchange, never two parallel exchanges where the slower one overwrites the newer session.
- Maintain a **session epoch** that is the tuple `(session-incarnation-uuid, user-id, tenant-id, bound-account-id, permission-scope-hash)`, not a bare monotonic counter. App restart generates a new session-incarnation-uuid so old persisted state cannot validate against a reused counter. Increment / regenerate the epoch on login, logout, account switch, **and on any silent token refresh that returns a different subject / tenant / bound-account / permission scope** — silent refresh is not always same-user, and old callbacks that wrote "under the same counter" can otherwise leak across identities. Every request, upload, poller, host-capability call captures the full epoch tuple at start; callbacks whose tuple does not match drop their write.
- Model expired session, failed silent login, user-declined authorization, account switch, logout, and account deletion.
- On logout / account deletion / account switch, the sequence must hold even when each step has implementation subtleties:
  0. **Before any purge, confirm external-finality pending operations are server-ledgered**: every pending external-finality row (payment via host gateway, third-party upload, etc.) must already exist on the backend under the old `(principal, tenant, business-key, idempotency-key)` with a discoverable support id. Purge deletes only the local mirror, never the source of truth — next login (whether same user or different) reconciles external finality from the server, not from local pending rows. If a host-finality operation is still in-flight when logout is invoked, surface a warning ("a payment/upload is still in progress; logout will keep it running on the server — you can recover it from the receipts page") and let the user confirm; do not silently strand the operation.
  1. **Capture the old identity + prefix set from the pre-advance auth context** (read `user-id`, `tenant-id`, `bound-account`, the storage manifest's prefixes for this identity, in-flight operation list) — once epoch advances, the old subject may not be reconstructible from in-memory state.
  2. **Publish the epoch advance and a new-session activation barrier in one atomic step** — new login attempts queue behind the barrier until purge completes.
  3. Cancel in-flight requests / uploads / pollers / host-capability callbacks captured in step 1.
  4. Purge the captured namespace prefixes AND any declared **legacy global / unscoped sensitive keys** (keys written by older app versions before user+tenant namespacing existed — declared in the storage manifest as `legacy-global` so the cleanup is explicit, not silent).
  5. Clear in-memory state, webview state, query cache, and stale route assumptions.
  6. Release the activation barrier; new sessions may now activate.

  A new login that starts before purge finishes can delete or repopulate the wrong user's data; the activation barrier is what enforces "purge first, then welcome the next user".
- Avoid collecting profile, phone, location, or media permission before the user action that needs it.

## Storage

- Use repo-local storage wrappers when available.
- Default-deny durable storage of sensitive fields (phone, profile, identity proof, payment metadata, tenant/role flags, location, raw tokens). If product explicitly requires durability, the field passes through a checklist: namespaced by the **full identity scope needed for restoration** — minimum `user + tenant + bound-account + platform + app-version`, plus `permission-scope-hash` for fields whose validity depends on the user's current permissions, bounded TTL, encrypted at rest or server-backed, and covered by a purge test that runs on logout / account-delete / account-switch.
- **Canonicalize identity sentinels**: for single-tenant deployments use `tenant=deployment:<deployment-id>`, never raw `null` / omitted; for products without a bound-account concept use `bound-account=user:<user-id>` so the namespace key is well-defined. Never let `null` / `undefined` / missing become a valid identity component — different "no value" representations collide into the same namespace and cross-leak between users on shared-device or family-account flows.
- Maintain a **storage manifest** that lists every namespace prefix the app uses (including historical app-version prefixes from upgrades) AND any **declared `legacy-global` keys** — unscoped sensitive keys written by older app versions before user+tenant namespacing existed. Purge / migration on logout / account-delete / account-switch consults the manifest and clears **all** historical prefixes for the user PLUS the `legacy-global` set. Old-app-version sensitive keys and pre-namespacing global keys must not survive an identity change; the manifest is the audited registry of "what could possibly hold sensitive state".
- Define key owner, namespace, TTL, migration, invalidation, and cleanup for every key.
- Mini-program storage is **device-scoped**, not user-scoped. On shared devices the next user inherits whatever the prior user left behind unless the namespace and purge discipline above is enforced.
- Validate restored state against the full session epoch tuple (incarnation + user + tenant + bound-account + permission-scope), current route params, host platform, and app version. Stale restored state must be discarded, not silently applied.

## Analytics

Track enough to debug and evaluate product behavior:

- Page exposure and unload.
- Entry scene/source, route params class, campaign or share source where allowed.
- Click/submit, validation failure, permission denial, retry, cancel, success, and final failure.
- API duration, error class, and request id in redacted form.
- Release version, platform, host version, and feature flag dimensions.
- **Error / crash reporting field set** (whether the project uses platform-native error reporting, Aegis / Sentry / Bugly equivalent, or a custom backend pipeline): each report MUST carry release version, host platform + host-client version, scene value, route + route params (sanitized), request id, sanitized error class (no PII / token / raw payload), session-incarnation, and the same identity-tuple fields used for tracing. Without these, an error report is unjoinable to back-end logs. SDK auto-capture (page crash, network failure, JS error) is subject to the privacy disclosure rules in `platform-capabilities.md` Review Policy Awareness — auto-capture without inventory declaration is a review-rejection risk. Field whitelisting at the reporter, not field-redaction-in-pipeline, is the safer default for PII.

## High-Risk Finality

Use this checklist for payment, quota, order, publishing, generated content, account, permission, or irreversible writes:

- **Server-enforced idempotency** by client-generated **idempotency key**, generated and persisted on the client **before any backend mutation call** (before order-create, before submit, before pay-invoke). The backend stores `{principal-user-id, tenant-id, action-class, business-key, idempotency-key, request-payload-fingerprint}` immutably and **rejects a second call whose principal / tenant / action / payload-fingerprint does not match the first call's record under the same key** — a bare client-generated key replayed across users, tenants, actions, or with a different payload must not collide into the first call's effect. Even if the server processed the create but the client never saw the response, the next launch finds the persisted key and reconciles by key, not by order id.
- UI duplicate-submit lock and visible pending state — **secondary** only. A UI lock that disappears on refresh, route switch, app kill, or second-device attempt is not a safety property; the server idempotency above is.
- **Persist pending state before the action**: the pending row carries `{idempotency-key, business-key, action-class, timestamp, session-epoch-tuple}` and is written *before* calling `Taro.requestPayment` / `Taro.uploadFile` / submit. If the app is killed at any point, the next launch sees the pending row.
- **Cold-start / page-show / re-login reconciliation has a bounded timeout and a 'state uncertain' recovery path**. On every entry point that could create a new high-risk action, look up pending state, reconcile against the backend (final / still-pending / canceled), with a bounded timeout (e.g. 5–10 s). On timeout or backend outage, do NOT deadlock the user: surface "state uncertain", expose support id + idempotency key, and offer recovery. **Recovery scope depends on whether the action is server-owned or externally final**: server-owned reversible actions (draft submit, server-side queue work) MAY use a server-authorized abandon path (server marks the key abandoned, new attempt allowed). External finality actions (payment via host pay gateway, third-party uploads, anything where an external provider can still report success after our timeout) **must NOT abandon until the external provider's ledger is reconciled** — abandon-then-retry would let the old provider callback succeed in parallel with a new attempt. For these, the recovery path is "wait + retry reconcile" or "open support case", not "abandon and try again". Without bounded recovery, one corrupt pending row blocks the user; without the abandon-scope rule, abandon causes double-finality bugs.
- **Cancel is not final.** Local cancel (`requestPayment` fail/cancel, user backs out, network error) does not mean the backend operation didn't succeed. Show "checking final state" until backend reconciliation confirms. Async callbacks routinely flip a locally-canceled payment to success.
- Callback/reconciliation path for payment or async work, with order/request id matched on both sides.
- Support-visible order/request id surfaced to the user; without it, support cannot disambiguate "I paid but app says canceled".
- Safe retry and user explanation for uncertain final state — never present "succeeded" or "failed" when reconciliation has not run.
