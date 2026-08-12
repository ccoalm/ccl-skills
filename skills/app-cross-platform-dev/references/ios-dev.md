# iOS Dev

## Architecture

- Use SwiftUI for new UI when the repo supports it; keep UIKit work behind clear boundaries when the repo or platform feature requires UIKit.
- Compose screens from small views, but keep durable state and side effects outside leaf views.
- Use State, Binding, Observable-style objects, environment, and model ownership deliberately. The source of truth should be obvious.
- **For new code on iOS 17+, prefer the `@Observable` macro (Observation framework) over `ObservableObject` + `@Published`** — `@Observable` tracks property reads finer-grained per view (less invalidation, fewer rebuilds), and migration drops the `@Published` wrappers + switches `@StateObject` to `@State`. Keep `ObservableObject` only where (a) targets older than iOS 17 must be supported, or (b) existing Combine pipelines on `@Published` properties are load-bearing — `@Observable` does not expose Combine publishers, so a refactor must replace those pipelines.
- Keep URLSession/API clients, persistence, permissions, notifications, and native SDK calls isolated behind services or protocols.
- Use async/await where it fits the repo; preserve cancellation and main-actor boundaries. **Swift 6 strict concurrency** (compiler-enforced `Sendable` and actor isolation checking) is opt-in on Swift 5 / Swift 6 compilers — enabling it surfaces real data-race bugs but requires explicit `nonisolated` / `@MainActor` annotations across the codebase; turn on per-target incrementally, not big-bang.

## App And Platform Behavior

- Treat scene lifecycle, app restore, push/deep-link entry, background execution, files/media, share sheet, biometrics, and in-app purchases as platform contracts.
- Model unavailable capability, denied permission, interrupted task, expired session, and offline state explicitly.
- Keep schemes, configurations, signing, entitlements, Info.plist changes, and store-sensitive capabilities reviewable.
- **Runtime permission UX (TCC) is separate from the Privacy Manifest gate**: every TCC-gated capability (Camera / Photos / Microphone / Location / Contacts / Calendars / Reminders / FaceID / Bluetooth / LocalNetwork / Tracking) MUST have a clear, specific `NS<Capability>UsageDescription` string in Info.plist explaining the user-visible purpose (Apple rejects vague / generic strings). The app must also model the four states explicitly: not-yet-asked / granted / denied / restricted — and provide a Settings-app deep link (`UIApplication.openSettingsURLString`) when denied. Privacy Manifest declares what IS collected; usage strings + state handling are how it appears at runtime.
- **Sign in with Apple (`ASAuthorization`) for App Store Review Guideline 4.8**: apps offering third-party social login (Google / Facebook / etc.) must offer an equivalent privacy-respecting login option — Sign in with Apple satisfies the requirement, but the rule is "another login service with these features", not literal Apple SDK. When using `ASAuthorization`, handle credential-revoked state on app launch (`getCredentialState`), the relay-email path (Apple proxies the user's real email), and an explicit account-deletion path the user can find without contacting support.
- **Privacy Manifest (`PrivacyInfo.xcprivacy`) — App Store Connect gate since 2024-05-01**: the app bundle MUST ship a privacy manifest declaring (a) collected data types per Apple's taxonomy, (b) required-reason API usage (file timestamp / system boot time / disk space / active keyboards / `UserDefaults`), and (c) tracking domains if any. Every third-party SDK on Apple's named "commonly used SDKs" list MUST ship its own privacy manifest; when the SDK is delivered as a binary dependency, the binary must also be code-signed. Apple's enforcement point is App Store Connect submission, not local `xcodebuild archive` — missing manifest fails submission, not local build, so the check belongs in pre-submission CI / dependency-upgrade checklist, not at submission time.

## Theme And Brand Color

Shared design discipline lives in `product-ui-ux-design/references/multi-project-token-consistency.md`; consult it before applying the iOS-specific implementation rules below.

- **Xcode scaffold color asset is empty by default**: a freshly generated iOS project ships `Assets.xcassets/AccentColor.colorset/Contents.json` with `colors: [{ idiom: "universal" }]` — no `color.components` field, so the asset resolves to system default. An app that leaves `AccentColor` empty AND has no other brand-color asset / theme module renders system blue throughout. Audit signal: empty `AccentColor.colorset` + no other named brand color asset = no native brand theme.
- **Brand color must live in the asset catalog or a typed token module, not scattered hex literals**: define brand colors as named entries in `Assets.xcassets` (color sets with light + dark variants and per-display-gamut variants where relevant) OR as a Swift constant module (`enum BrandColor { static let primary = Color(hex: ...) }`). Per-view `Color(red:..., green:..., blue:...)` literals duplicate the brand and silently diverge.
- **Vendor-default literal leak in custom theme** (cross-stack rule): system-default colors typed deliberately into the brand layer — `UIColor.systemBlue` / `Color.blue` as a brand color, Material defaults copied from cross-platform code, Apple HIG sample palette values — fall under the shared anti-pattern in `multi-project-token-consistency.md`. Detection: any literal in the brand-color asset or token module that matches a known system / vendor default. A hit resolves to one of three classes per the shared rule: **leak** (replace with brand token), **deliberate documented reuse** (keep with rationale comment), or **legitimate convergence** (brand role independently resolves to the same hex — keep but reference the brand token, not the literal).

### WebView-wrapper iOS shells

An iOS app whose main product flows are hosted in a `WKWebView` plus a thin shell of native helper screens (`AppDelegate`, network, photo upload, image picker, network-error fallback, splash, settings) is a **hybrid WebView shell**. The audit verdict is per-surface, not per-app: WebView-hosted product flows route their brand audit to the loaded web app; native-owned shell screens (splash, login, settings, offline / network-error fallback, permission prompts, photo upload modal chrome, status-bar / safe-area chrome, deep-link landing) are audited as native surfaces with normal three-layer evidence.

- Detection signals: very small Swift source count relative to the app's feature scope, primary content loaded into `WKWebView`, JS-bridge dependency (`WebViewJavascriptBridge`, `WKScriptMessageHandler`-based bridge), no SwiftUI / UIKit screen classes for product features (only infra: `AppDelegate`, `Network`, `PhotoUpload`, `ImagePicker`, `NetworkErrorView`).
- Audit verdict is **per-surface, not per-app**: WebView-hosted product flows → `native-theme: not-applicable (webview-hosted, brand audited via loaded URL)`; native-owned iOS surfaces in the SAME app (splash, login, settings, offline / network-error fallback, permission prompts, photo upload modal chrome, status-bar / safe-area styling, deep-link landing) → `audit native brand tokens normally`. A whole-app `not-applicable` verdict is wrong whenever the iOS shell ships ANY native screen with brand-relevant chrome.
- Wrapper-specific native concerns: JS-bridge auth + URL-allowlist, WebView file/camera permission plumbing (`UIImagePickerController` integration, `Photos` permission), safe-area + status-bar styling under the WebView, deep-link handoff into the loaded URL, the native error / offline fallback view's branding (since the user sees this when the WebView fails), and any native modal flows (photo upload, login bridge) whose chrome belongs to the iOS app not the web. Those still need native brand attention even when the main visual brand lives in the web app.

## Data Persistence

- **SwiftData (iOS 17+) is a niche default, not a universal one**: SwiftData is appropriate for SwiftUI-native new modules with light schema, simple migrations, and no cross-platform schema sync needs. For apps with complex migrations, server-synced schemas, audit / history requirements, or large legacy Core Data models, Core Data (or a hand-rolled SQLite layer behind a service) remains the safer choice — SwiftData is still adding history / custom store / inheritance capabilities. When mixing both, the Core Data and SwiftData schemas must stay in lockstep (`NSManagedObjectModel` materialization is required for new SwiftData fields).
- **Keychain for credentials and secrets**; `UserDefaults` for non-sensitive preferences only. Cross-process sharing requires explicit entitlements: `keychain-access-groups` (Keychain access groups) for credential sharing across sibling apps / extensions, and `com.apple.security.application-groups` (App Group identifiers) for shared container / shared `UserDefaults(suiteName:)` for widgets / extensions / sibling apps. Use sparingly and clear on logout. Storing tokens in `UserDefaults` / file is a security finding regardless of obfuscation.

## Capability Contracts

For each platform capability the app uses, model success / cancel / denial / unsupported / timeout / recovery explicitly — these are the same axes mini-program skill enforces but Apple's contract is per-capability:

- **APNs / UserNotifications (`UNUserNotificationCenter`)**: registration / device token retrieval / token rotation; authorization status (provisional / authorized / denied / ephemeral); foreground presentation options; deep-link payload schema; silent push (`content-available`) for background refresh; `UNNotificationServiceExtension` for payload mutation; APNs vs. third-party push provider boundary.
- **WidgetKit** (iOS 14+): use when there is a clear glanceable use case (calendar / status / metric snapshot); `TimelineProvider` returns entries — keep timeline budget realistic; widgets read from App Group / shared container, not from main app's `UserDefaults`.
- **Live Activities / ActivityKit (iOS 16.1+)**: scope to genuinely ongoing real-time state (delivery / live game / call / countdown). **Dynamic Island is hardware-specific** — iPhone 14 Pro / 14 Pro Max and later supported Pro models; never hardcode a model list, runtime-detect via `ActivityAuthorizationInfo` / capability check, and design Lock Screen presentation first as the fallback. Apple enforces duration limits, data-update frequency, and 4KB payload caps.
- **App Intents (iOS 16+, evolving 17+/18+)**: replace SiriKit + manual Shortcuts donation for new apps; expose discrete user-meaningful actions for Spotlight / Shortcuts / Siri / Focus / Controls / widgets; do NOT model complex transactional flows here.
- **AVFoundation / AVPlayer / AVCaptureSession**: required for video / audio / capture. Handle `AVAudioSession` category + interruption (call / Siri / other audio); `AVPlayerItem` failure / stall / preroll states; for background playback, enable Background Modes capability with `UIBackgroundModes=audio` in Info.plist AND set the matching `AVAudioSession.Category` (e.g., `.playback`).
- **MapKit / CoreLocation**: bind to TCC (precise vs reduced accuracy, when-in-use vs always); explain background-location usage in the usage string; respect battery — request the lowest accuracy that works.

## Dependencies

- **Swift Package Manager is the default for new Apple-platform dependencies** — `Package.swift` integrated into Xcode, every recent Apple-shipped framework / WWDC sample uses SPM. CocoaPods entered maintenance mode in 2024; the public CocoaPods Trunk / Specs repository is announced to go read-only on 2026-12-02 (new podspecs / new versions no longer accepted after that — the `pod` tool itself keeps working against existing data). New code should not introduce CocoaPods; existing CocoaPods projects migrate at their own pace with test evidence.
- **Binary SDKs (XCFramework) need three checks** before adoption: (1) Xcode 15+ verifies the SDK's signing identity if signed — fail fast if signature is missing or untrusted; (2) Privacy Manifest present if the SDK is on Apple's "commonly used SDKs" list (App Store Connect submission gate); (3) per-architecture slices match the app's deployment matrix (arm64 / arm64e / x86_64 simulator).

## Tests And Verification

- Unit test models, reducers/view models, API clients with fakes, persistence boundaries, validation, mapping, and error handling.
- UI tests should assert expected elements and outcomes for critical flows.
- Use previews for fast inspection, but do not treat a preview as proof of runtime integration.
- Verify dynamic type, VoiceOver labels/order, contrast, safe areas, keyboard behavior, and localization-sensitive layout when touched.
- **Swift Testing (Xcode 16+) vs XCTest**: Swift Testing's `#expect` / `#require` macros + parameterized tests + parallel execution by default + cross-platform support are the right defaults for new test code in Swift Testing-capable Xcode targets. XCTest remains valid for UI tests (`XCUITest`) and legacy suites; the two coexist in the same target — migrate incrementally, do not rewrite.
- **Mocking discipline**: prefer protocol + fake-by-hand for adapter / network / persistence boundaries (clearer dependency graph, no codegen). Code-generated mocks (`Mockingbird` / `Cuckoo` / `Sourcery` / `MockoLo`) are appropriate only when the protocol surface is large (10+ methods) AND the test suite already depends on the codegen path — do not introduce a mock framework for new small surfaces.

## Performance

- Keep launch initialization fast; move noncritical work after initial UI.
- Watch main-thread work, large view recomputation, image decoding, memory pressure, and list scrolling.
- Use Instruments or Xcode diagnostics for suspected performance defects.
- **MetricKit (`MXMetricPayload`) for production observability**: Apple's daily-aggregated metric payload (crash diagnostics, hang diagnostics, app launch / responsiveness / disk / memory / energy / animation / network metrics) is delivered to the app via `MXMetricManagerSubscriber`. Subscribe early in app lifecycle, forward to the crash backend (per `mobile-quality-release.md` symbolication gate) — MetricKit fills the gap between user-reported issues and crash reports for non-crash perf regressions (hang / slow launch / energy).
