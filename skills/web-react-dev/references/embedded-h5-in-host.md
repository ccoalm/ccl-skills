# Embedded H5 In Host

Use this reference when the React web surface is embedded **inside a host** rather than running as a standalone browser page. Common hosts: mini-program `web-view` (WeChat / Alipay / Douyin / Baidu / QQ), native mobile WebView (`WKWebView` / Android `WebView`), payment-vendor WebView, vendor-app WebView (banking apps, super apps). Not for: standalone PWA, public website, marketing landing page.

The host imposes constraints a standalone React app does not face. This ref names the recurring contract surface; sibling responsibility lives in `miniapp-product-dev` (mini-program host side) and `app-cross-platform-dev/references/{ios-dev, android-dev, mobile-platform-boundaries}.md` (native WebView shell side).

## When This Ref Applies

- The page loads inside a host's WebView, not the user's browser.
- The host owns auth, navigation, share, payment, scan, file/image upload, location, status bar, and back-button behavior. The H5 is a guest.
- Source-of-truth for the contract is the host's official docs (WeChat JSSDK / WKWebView WKScriptMessageHandler / Android `WebView` `addJavascriptInterface`); H5-side guesses without consulting host docs ship broken.

## Host Environment Detection

- **Detect the host explicitly** before invoking any host-specific bridge: WeChat = prefer `wx.miniProgram.getEnv(...)` (canonical async check that resolves `{miniprogram: true|false}`) — `window.__wxjs_environment === 'miniprogram'` and UA `MicroMessenger` substring remain as legacy / early-detection fallbacks before WeChat JSSDK is loaded; Alipay = UA contains `AlipayClient`; mini-program `web-view` = check for `wx.miniProgram` / `my.miniProgram` / `tt.miniProgram` etc. Cache the detection at app init; do NOT re-sniff in every component.
- **Defensive feature checks** beat UA-sniffing for capability presence (`typeof wx !== 'undefined' && typeof wx.config === 'function'`). UA-sniffing is for env classification + analytics labeling; per-call feature check is for guarding the actual invocation.
- **In-browser fallback path** is mandatory: the same H5 may open outside the host (testing, sharing as plain URL, fallback when host restricts). For each host-capability touchpoint, design and test the in-browser degradation (disabled button + tooltip, alternative web-native flow, or explicit "open in <host>" prompt).

## Bridge Contract Abstraction

- **Never hardcode one host's bridge directly in component code**: wrap all host calls in a thin per-host adapter (`HostBridge.share(...)`, `HostBridge.pay(...)`, `HostBridge.scan(...)`) plus a single registry that resolves to WeChat / Alipay / Native / Web-fallback at runtime. Without this, every host added later means rewriting call sites. When adopting an existing native bridge library (DSBridge, WebViewJavascriptBridge, custom in-house bridge), verify the library's current maintenance state and security posture — both legacy libraries are still in use in production codebases but their repos may be inactive; the abstraction layer above them lets you swap the implementation without touching call sites.
- **Bridge calls are async** and can fail / time out / be denied by the user. Treat every bridge invocation as a network call: typed result, error class, timeout, user-cancel state, and UI feedback when the host is slow. Synchronous-call assumption is the recurring source of "tap does nothing" bugs when the bridge is slow on first invocation.
- **JS-bridge auth is per-message, not per-handshake** (per `miniapp-product-dev/references/platform-capabilities.md` WebView bridge contract): the host re-validates origin + nonce + session tuple on every inbound bridge call. H5 cannot cache a successful handshake and assume future calls succeed.

## Auth From Host (Cookieless Session)

- **Do not assume cookies / localStorage persist across host sessions**: mini-program `web-view` and many native WebViews isolate storage per app launch or even per page-open. Treat storage as cache, not as source of session truth.
- **Auth token comes from the host**, not from a cookie-based login flow. Standard patterns: (a) signed URL query parameter from the host (`?token=<host-issued-jwt>`); (b) bridge call to fetch token (`HostBridge.getAuthToken()`); (c) host-injected initial JavaScript variable. Document which pattern the project uses; do not mix.
- **Token rotation needs an explicit refresh path** (for authenticated H5 consuming a host-issued token; not needed for unauthenticated content surfaces): on 401, attempt token refresh via bridge; if refresh fails or no bridge, surface a re-login flow that respects the host's auth model (e.g., navigate back to host login surface, not to an H5 login page that the host can't drive).

## Hardware Back Button + History Integration

- **Android hardware back is part of the contract**: the host's `Activity` `onBackPressed` (or modern `OnBackPressedDispatcher` per `app-cross-platform-dev/references/android-dev.md`) typically intercepts back and either calls `webView.goBack()` (when `canGoBack()` is true) or finishes the host activity. H5 `history.pushState` / `popstate` integrates correctly when host wires this through; without it, hardware back exits the entire WebView when H5 expected internal navigation.
- **WeChat Android JSSDK + HTML5 History API caveat**: per WeChat JSSDK docs (defensive against Android-WeChat-specific signing behavior, not anchored to a single historical version), `pushState` SPA routing can break `wx.config` signature on Android because the signed URL diverges from the runtime URL. Workaround: re-call `wx.config` after route change with a freshly-signed URL, or use hash routing (`#/path`) for WeChat-embedded SPAs.
- **iOS swipe-back gesture**: WKWebView's interactive `allowsBackForwardNavigationGestures` (host-side flag) drives the swipe-back-to-previous-page behavior. H5 cannot block this from the page; if a flow MUST prevent unsafe back (mid-payment, mid-upload), coordinate with the host to disable the gesture for that route.

## Safe Area + Viewport In WebView

- **Viewport-fit cover + env(safe-area-inset-*) is mandatory for full-screen H5 on notched devices**: `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">` is the opt-in for content extending into the safe-area region; CSS `padding-top: env(safe-area-inset-top)` / `padding-bottom: env(safe-area-inset-bottom)` etc. then keeps interactive content inside the safe region. Without `viewport-fit=cover` the page leaves system white space at notch; without `env(safe-area-inset-*)` the page hides behind the home indicator.
- **`100vh` is unreliable in WebView**: mobile browsers compute `100vh` including/excluding URL bar inconsistently; in WebView the host chrome height shifts on scroll. Use `100dvh` (dynamic viewport units, well-supported in modern browsers) or measure `window.innerHeight` + observe `visualViewport` for keyboard-affected sizing.
- **Keyboard handling**: iOS WebView pushes the entire viewport up when the keyboard appears (forcing layout shifts); Android WebView resizes the viewport (so `position: fixed` elements may not stay fixed). Use `visualViewport.height` + `visualViewport.offsetTop` to position keyboard-following UI, not raw `window.innerHeight` deltas.

## Host Capability Surfaces

- **Native capability invocation routes through host APIs, not browser APIs**. Common surfaces with their host-vs-browser distinction:
  - **Share** — host has its own share sheet (`wx.shareToTimeline` / `wx.miniProgram.postMessage` + `onShareAppMessage`); `navigator.share` is rarely available in WebView. Always check `HostBridge.canShare()` before showing share UI.
  - **Image / file upload** — host wraps native camera + photo library (`wx.chooseImage` + `wx.uploadImage`); `<input type="file">` may be blocked / quirky inside WebView. Use the bridge if available.
  - **Payment** — host has native payment (`wx.requestPayment` from mini-program web-view; WeChat Pay JSAPI; Alipay tradePay). Web payment via `<form>` POST works but loses the native UX (no Touch ID / Face ID prompt, no host wallet UX).
  - **Scan (QR / barcode)** — host has native scan (`wx.scanQRCode`); web-only via `getUserMedia` + decoder library works but requires camera permission and adds bundle weight.
  - **Location** — host has native location with the host's permission state (`wx.getLocation`); browser `navigator.geolocation` works but prompts independently of host permission and may have lower accuracy.
  - **Subscribe message / push** — H5 cannot subscribe to mini-program / app push directly; coordinate with host (mini-program `requestSubscribeMessage` runs on the host page, not in `web-view`).
- **Degrade gracefully when the host capability is absent** (when running in browser): hide the action, swap to a web-native alternative, or show "Please open in <host>" call-to-action. Crashing or silently failing on missing host APIs is the recurring source of "works in WeChat, broken everywhere else" tickets.

## WeChat JSSDK Specifics (Public Account / web-view)

- **`wx.config` signature requires all five parameters** (`appId` + `timestamp` + `nonceStr` + `signature` + `jsApiList`) — signature is computed server-side from the current page URL excluding hash. SPA hash routing keeps the signed URL stable; SPA `pushState` routing requires re-signing on every route change. Verify in WeChat developer tools / `wx.ready` + `wx.error` callbacks.
- **`web-view` in mini-program only exposes a subset of JSSDK** — the full JSSDK API list works in WeChat browser (公众号 H5); inside mini-program `web-view`, only `wx.miniProgram.*` bridge methods (`navigateTo`, `redirectTo`, `navigateBack`, `switchTab`, `reLaunch`, `postMessage`, `getEnv`) are reliably available. Test the actually-needed API on the actually-targeted host surface.
- **Domain whitelist (业务域名)**: per `miniapp-product-dev/references/platform-capabilities.md` Network Domain Allowlist, every domain the H5 loads (HTML / API / asset) must be registered in the mini-program / public-account console as an authorized business domain — production calls to unregistered domains are silently blocked. Developer-tool "skip domain check" masks this; CI / pre-release smoke disables that flag.

## Offline / Cache / Lifecycle

- **Host may aggressively cache the entry HTML** (WeChat caches public-account HTML for performance). Cache-bust strategy: append a content-hash query parameter to the entry URL, OR use HTTP cache headers the host respects (`Cache-Control: no-cache, must-revalidate` for HTML; immutable hashed JS/CSS assets). Hash-busted JS without a fresh HTML reload = stale code shipping.
- **Service Workers in WebView are NOT a portable guarantee** — verify per target host. Android `WebView` has an official `ServiceWorkerController` API (must be explicitly enabled and respects same-origin); WeChat WebView's full SW support is not something you should assume. Do not bet on Service Worker for critical offline behavior in WebView without per-host verification; use host-side cache (where the host owns the WebView) or accept online-only operation.
- **Visibility / lifecycle events**: H5 inside WebView receives `pageshow` / `pagehide` / `visibilitychange` events but the timing differs from a browser tab (the host may freeze the WebView when backgrounded, terminate on memory pressure). Save in-progress state on `pagehide` / `visibilitychange`, not on `beforeunload` (often not fired in WebView).
- **Cold-start vs warm-start**: if the host keeps the WebView alive across navigations, the H5 may re-receive a `pageshow` event with `persisted=true` (BFCache-style restoration). Initialize idempotently — code that assumes single `DOMContentLoaded` per session breaks when warm-started.

## Cross-App / Cross-Page Navigation

- **Open a mini-program from H5** (only in WeChat browser, NOT inside mini-program web-view): requires the page domain to be associated with the target mini-program in the WeChat console; primary API is the `wx-open-launch-weapp` web component (current public path). JSSDK `wx.invoke(...)` legacy paths may exist in some integrations but verify against current WeChat docs before adopting.
- **Open native app from H5**: URL schemes (`myapp://...`) work when the app is installed and the host allows it; Universal Links (iOS) / App Links (Android) are more reliable but require server-side `apple-app-site-association` / `assetlinks.json` setup. Inside many in-app WebViews, URL scheme jumps are blocked — coordinate with the host.
- **Inside mini-program `web-view`, navigation between H5 and mini-program pages** uses `wx.miniProgram.navigateTo` (to mini-program page) / `wx.miniProgram.postMessage` (sends data back to the mini-program's `web-view` `bindmessage` handler, delivered at host-defined moments — typically mini-program back navigation, component destroy, or share — NOT guaranteed immediate delivery).

## Anti-Patterns — Avoid Or Require Justification

- Using `window.alert` / `window.confirm` / `window.prompt` as primary user UI — WebView host may render them in confusing ways or block them entirely; use host bridge for modal UI when available, otherwise an in-page React modal. Low-risk dev-only diagnostics in `alert()` are not blanket-forbidden, but should never ship as production user flow.
- Using `document.cookie` for **session** state — WebView cookie persistence is unreliable across cold-starts; use host token via bridge for session. First-party non-session cookies (preferences, tracking with consent) remain valid where the host respects them.
- Relying on third-party cookies — most WebViews and modern browsers block them; use first-party storage + server-side session if cross-origin auth is needed.
- Calling `window.open` for new windows — WebView typically does not support multi-window; route through host bridge.
- Assuming `console.log` reaches the developer — WebView consoles are not always exposed; use a host bridge logging method or remote logging service for production diagnostics.
- Polling `navigator.onLine` for connectivity — unreliable in WebView; use fetch-failure as the actual signal and let the host-level network indicator (mini-program / system notification) handle the user-visible offline state.
- Adopting **PWA acceptance criteria** (manifest install prompt, Service Worker offline-first, push notifications) for the H5-in-host build — these are valid for standalone PWA but are NOT acceptance criteria inside a host WebView; the host owns app-shell / push / offline. If the same H5 also ships as standalone PWA, treat as a separate build target with its own acceptance.

## Verification

- **Real host device test is blocking when the change touches host-dependent behavior**: bridge invocation, auth-from-host, share / payment / scan / image-upload / location, hardware back, lifecycle (cold-start / warm-start / visibility), safe-area + viewport, keyboard handling. Browser smoke + responsive emulator is structural only for these. Per `mobile-quality-release.md` and `miniapp-product-dev/references/qa-release.md` real-host flow templates: open the H5 inside the actual host (real WeChat client, real native app build) on a real device; verify the host-specific path end-to-end. For copy-only / static-layout / pure-React-internal changes that don't cross the host boundary, browser smoke plus a single targeted host smoke is sufficient.
- **Multi-host smoke matrix** when shipping to ≥2 hosts: WeChat browser / WeChat mini-program web-view / native iOS app WebView / native Android app WebView are four distinct environments — the same H5 may render correctly in three and break in the fourth (most commonly: Android WebView with custom UA or AppCompat WebView).
- **In-browser fallback test**: open the H5 in a plain mobile browser (Safari iOS, Chrome Android). Confirm the in-browser degradation is sane: actions that need host APIs are disabled with explanation, no JavaScript errors in console, no host-specific assumptions break the page.
