# Platform Capabilities

Use this reference when a miniapp task touches platform APIs, config, host compatibility, or review policy.

## Platform Selection

- Identify the exact host platform before implementation: WeChat, Alipay, Douyin/TikTok, Baidu, or a multi-platform framework target.
- Identify the framework and build target: native miniapp, Taro, uni-app, Remax, mpvue, kbone, or repo-specific abstraction.
- Check whether the repo treats platform differences by build target, adapter, conditional compilation, runtime capability detection, or separate packages.
- For multi-platform work, list each required platform and which evidence proves it.

## Config Files

Inspect relevant config before editing:

- WeChat native: `app.json`, `project.config.json`, `project.private.config.json`, `sitemap.json`.
- Alipay native: `app.json`, `mini.project.json`, plugin and extension config.
- Douyin/TikTok native: platform project config, `app.json`, permission and capability declarations.
- uni-app: `manifest.json`, `pages.json`, platform blocks.
- Taro: `config/index.*`, framework build config, per-platform config.
- Shared repos may also have env files, app id placeholders, CI build matrix, and generated files. Do not commit machine-local private config unless the repo already tracks it intentionally.

## Network Domain Allowlist + Regulatory Surface

Mini-program hosts enforce per-app HTTPS domain allowlists (request / socket / uploadFile / downloadFile / WebView business-domain), and the underlying domains carry regulatory obligations that often gate release more reliably than feature correctness:

- **Per-channel domain allowlist**: every domain the app calls (HTTP request, socket, file upload/download) AND every domain the embedded WebView opens MUST be pre-registered in the platform's mini-program management console; production-build calls to an unregistered domain are silently blocked at the host. Developer-tool "skip domain check" defaults mask this — disable in CI / pre-release smoke. List the allowlist in the release artifact and diff it on every config change.
- **ICP / regulatory filing (备案) — track two filings separately**: in mainland China, (1) every production **domain** serving a mini-program request typically requires its own ICP / related domain compliance filing bound to the operating entity; (2) the **mini-program / app itself** may additionally require platform APP/miniapp 备案 bound to the appid per the MIIT 2023 directive. For WeChat, new mini-program filing was required from 2023-09-01 onward; existing online mini-programs had a 2024-03-31 transition deadline. Do NOT conflate the two — domain ICP status and appid platform-filing status are independent rows in the release artifact (filing number, bound entity, status, expiry where applicable), and either can block production traffic.
- **Privacy policy + SDK data inventory**: maintain a declared inventory of every collected field, invoked privacy-sensitive API, and third-party SDK behavior in the platform's privacy guideline / template document AND in the release artifact. For WeChat specifically, enable / check the privacy authorization config (e.g., `app.json` `__usePrivacyCheck__`) where applicable — but treat that flag as a developer-convenience switch, not the gate itself: the host activated the privacy-authorization framework platform-wide on a 2023 cutover, so a privacy-sensitive call can be gated even with the flag absent. The declared guideline in the platform management console is the source of truth the reviewer compares invoked privacy-sensitive APIs and SDK behavior against; under-declaration both fails review (a common rejection cause) AND breaks the runtime call (`scope is not declared in the privacy agreement` class error). Mirror the Review Policy Awareness matrix below for the SDK data inventory. The runtime handshake APIs and the states this skill must model live in the Capability Checklist → "Privacy authorization" below.
- **Industry-vertical resolution** (finance, medical, legal, AI/generated content, minors, payment): some categories require additional qualification documents (e.g., 金融类 / 医疗类 类目资质) on top of base ICP/备案. Resolve category and qualification needs at product-definition time, not at release time.

## CloudFunction / Cloud-Development Client Boundary

If the project uses a host's serverless backend (WeChat 云开发 / Alipay 云开发 / cloud functions), the mini-program is only the **client** of those functions — service-shape and backend ownership stay with `python-service-architecture` / `go-microservice-architecture` / `platform-release-engineering` as appropriate:

- The client SDK call (`wx.cloud.callFunction` / equivalent) is treated like any other RPC endpoint: typed payload, timeout / retry / idempotency-key per the High-Risk Finality rules in `contracts-and-state.md`, error-class mapping to the same surface as normal HTTP errors, observability with the same scene / route / request-id fields.
- Identity assumption: the host's automatic OpenID injection into cloud-function context is convenient but is NOT a substitute for the project's session-epoch identity tuple — sensitive mutations still bind to the full identity tuple (`bound-account`, `tenant`, `session-incarnation`, `permission-scope-hash`) verified server-side, not to the host OpenID alone.
- Function permission policy, database security rules, payment callback validation, rate-limit / quota, cron / scheduled-trigger config stay with the backend / serverless owner — do not duplicate that logic into the client.

## Startup Performance Config

Cold-start time is a host-measured quality signal and a common reason a mini-program feels slow on low-end devices. Two low-code host-config levers are worth evaluating before hand-tuning code, but both are behavior-affecting changes — do not enable either as a default without baseline startup measurement and affected-flow regression evidence:

- **按需注入 / lazy code injection** (`app.json` `"lazyCodeLoading": "requiredComponents"` on WeChat; verify the host-specific equivalent on others): the host injects only the custom components and page code the current page actually uses, instead of evaluating every registered component at startup. This can materially cut startup work with no code change, but it changes *when* component code runs — re-test pages that relied on eager evaluation (a component referenced only dynamically, or an app-launch side effect expected from an otherwise-unused component, can break).
- **初始渲染缓存 / initial rendering cache** (`initialRenderingCache` page config on WeChat — a mode, not a boolean: `"static"` caches only the static parts of the first render; `"dynamic"` additionally caches a snapshot the page supplies via `this.setInitialRenderingCache(data)`, and clearing it requires `this.setInitialRenderingCache(null)`): the host shows the cached first render immediately on next entry while real data reloads — a space-for-time trade. Use `static` for pages with a stable, identity-agnostic first-screen skeleton. Do NOT cache (especially via `dynamic` with real data) a first screen that contains any identity-specific, tenant-specific, personalized, regulated, or otherwise sensitive visible data — even one field such as avatar, nickname, phone suffix, balance, status, or count: a cached first render of the previous account's screen is both a UX bug and a privacy leak after account switch. When such a page is cached at all, explicitly clear the cache on logout / account switch before the next account can view it. Pair this with the storage-namespacing / account-switch rules in `contracts-and-state.md`.

These config keys are WeChat-named; confirm the equivalent key and behavior before applying to Alipay / Douyin / Baidu. Place the startup-time budget + regression gate via `testing-strategy` (performance budgets own the gate). This skill still blocks mini-program completion until the target-specific build/runtime evidence and affected-page smoke are present; `testing-strategy` owns budget design and test-layer selection, not a waiver of this skill's runtime-evidence gate. This reference owns the config recipe and its correctness caveats.

## Capability Checklist

For every capability, define success, cancel, denial, unsupported, timeout, and recovery behavior:

- Privacy authorization (WeChat privacy framework — a precondition gate in front of the privacy-sensitive capabilities below, distinct from each capability's own permission state): geolocation, camera/album, profile, phone, clipboard read, and similar `scope`-gated calls are governed by the user-privacy-protection guideline the host enforces independently of the `__usePrivacyCheck__` flag. Runtime contract (WeChat API shape): `wx.getPrivacySetting` returns `{ needAuthorization, privacyContractName }` — whether an authorization step is still needed, NOT a plain "user agreed" boolean (`needAuthorization: false` can mean prior agreement OR that no privacy collection is declared, so do not read `false` as proof the user consented or as proof a scope is declared); `wx.requirePrivacyAuthorize` proactively triggers the agreement ahead of a sensitive call; `wx.onNeedPrivacyAuthorization` registers a handler that fires when a sensitive API is invoked without prior agreement, and the app resolves agree / disagree; `wx.openPrivacyContract` opens the guideline page. **Call placement**: invoke `wx.requirePrivacyAuthorize` only inside a user-initiated path that is about to call a declared privacy-sensitive API — do not run it at app launch or as a blanket global entry gate; prefer handling `onNeedPrivacyAuthorization` around the actual sensitive path. States to model: already-agreed (call proceeds, no popup — do not re-prompt), needs-authorization (handler fires, app must surface the agree/disagree UI before the call can proceed), user-disagrees (the sensitive call fails — render an explicit denied/recovery state, never a frozen spinner), and scope-not-declared (call fails with a `scope is not declared in the privacy agreement` class error — the fix is declaring the scope in the console's privacy guideline, not a code change; the declaration inventory itself lives in the "Privacy policy + SDK data inventory" bullet above). **Two independent gates**: passing privacy authorization does NOT grant the capability — location / camera / album still run their own permission / denial / settings-handoff flow (see those rows below); model the privacy-agreement gate and the per-capability permission gate separately. Multi-platform note: this is the WeChat contract. Alipay / Douyin / Baidu have their own privacy-authorization mechanisms; do not assume the WeChat API names or flow carry over — verify each host's current API before reusing this recipe.
- Login/session: code exchange, session renewal, expired login, silent retry limits, logout cleanup.
- User profile and phone: authorization copy, bind/unbind state, declined permission, stale bound data.
- Payment: order creation with server-enforced business-key idempotency, persist-pending-before-invoke, pay invoke, cancel (treat as non-final until backend confirms), fail, duplicate tap, callback reconciliation, **blocking cold-start / page-show reconciliation against backend before enabling a new attempt**, and reconciliation on re-login if identity changed mid-flow.
- Share and scene entry: treat scene/share/QR params as untrusted input. Schema-parse, server-authorize the referenced target against current identity, and require backend-issued share tokens that are TTL-bounded and replay-protected for any unlock, attribution, or capability-granting flow. Client-side attribution is not the final source of truth. Track expired target, missing permission, and identity-mismatched scene as explicit states.
- Subscribe messages: template availability, user choice, denied state, repeated request policy.
- Camera/album/file/scan: permission, compression, upload, cancel, unsupported device, background interruption. Uploads that cannot be canceled mid-flight must reconcile on next entry rather than mutating UI from a stale callback.
- Location: temporary denial, permanent denial, settings handoff, stale coordinates, privacy copy.
- WebView/plugin/bridge as security boundary. Initial allowlist is not enough — once the page navigates, redirects, or executes XSS, an allowed origin can keep invoking the bridge. Contract:
  - strict HTTPS origin + path allowlist (an allowed domain with an open redirect is not safe — pin path or use signed routes);
  - nonce / handshake bound to `(webview-instance, current-route, session-epoch)` and **re-issued on every navigation**;
  - origin + path **revalidated on every inbound message**, not only at handshake;
  - per-message capability invocation requires a **server-signed capability grant** scoped to the **full identity + session tuple**: `(route, action, session-incarnation, user, tenant, bound-account, permission-scope-hash, webview-instance, short-expiry)`. The `session-incarnation`, `bound-account`, and `permission-scope-hash` are mandatory — without them, an unexpired grant survives a permission downgrade or bound-account switch and the compromised page can keep invoking what the user no longer has rights to;
  - **offline / outage contract** for the signing dependency: pre-mint a short-lived bundle of grants for the capabilities the route's first interaction needs and ship them with the route transition (still scoped + short-expiry); on weak network / backend outage, additional grants fail closed (bridge disables those capabilities with explicit "unavailable" UX) — never cache grants on the client beyond the pre-minted short-lived window, and never bypass signing because the backend is slow;
  - payload schema validation on every message;
  - timeout per message;
  - teardown on `useDidHide` / `useUnload` revokes outstanding grants.

  Treat the embedded page as adversarial input even when it is "your own" H5.
- Clipboard/open setting/open document: explicit user intent, privacy-safe copy, unsupported or failed invocation.

## Review Policy Awareness

- Treat platform review rules as product constraints, not after-the-fact release issues.
- For every review-sensitive area touched by a release, record the **current official platform-policy doc URL + date** read. Platform-policy text (especially around payments, AI/generated content, financial advice, medical/legal, minors, privacy collection) changes faster than skill rules; "I remember the rule was X" is not evidence.
- Per-platform review matrix that every release passes:

  | Dimension | What the matrix records |
  |---|---|
  | Permission timing | Each permission (location, camera, album, phone, profile, file, scan) is requested only at the user action that needs it; nothing collected on app launch. |
  | Privacy disclosure | Privacy policy URL, last-reviewed date, mapping from each collected field to a policy clause, account-deletion path declared. |
  | Account deletion | Reachable from a non-buried route, second-confirmation copy, server + storage purge tested, post-deletion landing state. |
  | Minors / sensitive demographic | Age gate or compliance carve-out, restricted-feature handling, parental consent if required. |
  | SDK data inventory | Every third-party SDK named with what data it collects, purpose, opt-in or opt-out state, and whether the SDK auto-collects on load. |
  | Sensitive copy | Payment, financial, medical, legal, AI/generated-content wording reviewed against current policy; forbidden claims removed. |
  | Generated content | UGC moderation path, AI-output disclaimer, takedown route, audit trail. |
  | Reviewer evidence | Test data, accounts, capability sandbox path stored in the **release artifact**, not in this skill or shared references. |

- Keep reviewer-visible test data, feature flags, and account instructions outside shared skills; store them only in the owning repo or release artifact.
