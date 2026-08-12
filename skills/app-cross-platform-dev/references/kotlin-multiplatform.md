# Kotlin Multiplatform (KMP) + Compose Multiplatform

KMP is a Kotlin-first technology for sharing business / domain / data / API-client logic across mobile (Android + iOS), desktop, server, and (beta) web. Compose Multiplatform extends that to share UI built with Jetpack Compose. The mature production pattern is **shared logic + native UI**; one-codebase-for-everything is a separate, narrower bet (see Compose MP section below).

This ref is for Android/iOS teams evaluating or operating KMP. For pure Android (single platform), see `android-dev.md`. For pure iOS, see `ios-dev.md`. For Flutter / React Native, see `flutter-dev.md`.

## Adoption Decision Matrix

| Signal | KMP shared logic | Compose Multiplatform iOS |
|---|---|---|
| Team owns Kotlin Android codebase + native iOS app | strong fit | weaker fit (depends on iOS team) |
| iOS team is independent / SwiftUI-owning | shared logic only via stable framework boundary | poor fit unless explicitly negotiated |
| Existing Flutter / React Native product | do NOT introduce KMP "while we're at it" | wrong stack |
| Goal: reduce duplicate business logic, keep native UI freedom | mature, production-proven path | not the right tool |
| Goal: one UI codebase across both platforms | use Flutter or accept Compose MP trade-offs | possible since Compose MP 1.8.0 (2025-05) Stable, but evaluate per Compose MP section |

## Source Set Hierarchy and expect/actual

- **Source set layout**: `commonMain` (platform-agnostic) → `androidMain` / `iosMain` / `jvmMain` (target-specific). KMP defaults now use the **default source set hierarchy** introduced in Kotlin 1.9.20 (Stable) — `iosMain` automatically aggregates over `iosArm64Main` / `iosX64Main` / `iosSimulatorArm64Main`, etc. Do not hand-roll the old `intermediate-source-set` declaration unless a sibling project's pinned Kotlin version requires it.
- **`expect` / `actual` for platform-specific implementations**: declare `expect fun method(): T` (or `expect interface X { fun method(): T }`) in `commonMain`, provide `actual fun method(): T = ...` in each platform source set. `expect class` is also supported but per Kotlin docs is Beta — prefer `expect fun` / `expect interface` for non-Beta surface. Use sparingly — every `expect` is a divergence the team must maintain; prefer pure-`common` code with platform impls injected via constructor / interface where possible.

## iOS Integration

- **iOS consumes a generated framework** (regular framework, static framework, or **XCFramework** for multi-arch). Three integration paths per Kotlin docs, pick by team workflow:
  - **Direct integration** (simplest): the Xcode build invokes a Gradle script that produces the framework; Xcode picks it up via framework search path. Best for monorepo / tightly-coupled teams.
  - **CocoaPods**: the Kotlin CocoaPods Gradle plugin generates a `podspec`; iOS team consumes via `pod install`. Required path if the KMP module needs to import other CocoaPods dependencies (`pod(...)` Gradle DSL).
  - **Swift Package Manager**: produce XCFramework + `Package.swift`, distribute via separate Git repos for the manifest vs the framework. Per Kotlin docs the SwiftPM export path is the recommended remote-distribution workflow when no Pod dependencies are needed.
- **Swift interop limits**: cinterop generates Kotlin bindings from Objective-C / C headers. Pure-Swift APIs are NOT directly consumable — Swift must expose `@objc` (or `@objcMembers`) to be visible to Kotlin. **Swift Export** (the reverse — exposing Kotlin to Swift without Obj-C bridging) had basic support since Kotlin 2.1.0; Kotlin 2.2.20 made experimental Swift Export available by default. Do not depend on it for production-critical interop yet.

## Kotlin/Native Runtime

- **New memory model is default since Kotlin 1.7.20**: no `freeze()` for cross-thread sharing, concurrent GC, GC pauses observable via Xcode Instruments (signposts). The freeze-based mental model is obsolete; if migrating from a pre-1.7 KMP project, remove `freeze()` calls and verify behavior.
- **Memory + perf still need measurement on iOS**: GC pause characteristics differ from JVM; large heaps + frequent allocation can surface as scroll jank on lower-end iOS devices. Profile via Xcode Instruments, not by JVM intuition.
- **C interop memory management**: the new memory manager manages Kotlin objects only — for C-allocated memory use `memScoped { ... }`, `Arena`, or `createCleaner`. C heap leaks are a real failure mode the GC does not catch.

## Compose Multiplatform for iOS

- **Stable since Compose Multiplatform 1.8.0** (released 2025-05 per JetBrains blog): API surface finalized; JetBrains claims feature parity with Jetpack Compose for popular use cases, first-class accessibility (VoiceOver, AssistiveTouch, Full Keyboard Access), and native-feel scrolling / text editing / RTL. This is a real "Stable" milestone, not a marketing-only label — but per Apple HIG conformance is your team's evaluation, not a JetBrains certification.
- **Stable ≠ universally production-ready for every team**. Adopt only when ALL hold: (a) team is Kotlin-first (iOS engineers comfortable reading Compose / Kotlin code, or pure-Compose-MP UI team), (b) the design system tolerates Compose's rendering of iOS UI (or a native escape hatch is mature for the surfaces that need pure SwiftUI / UIKit), (c) the iOS team accepts the build / debugging / profiling tooling trade-off (Xcode Instruments + Android Studio rather than Xcode-only), (d) concrete native-feel parity evidence on iOS (component fidelity, gesture / scroll physics, accessibility behavior on real devices).
- **Native escape hatch via UIKit / SwiftUI interop**: Compose MP supports embedding UIKit `UIViewController` into a Compose surface and vice versa; SwiftUI interop is also documented but adds complexity (state ownership, lifecycle, navigation). Treat interop as an architecture boundary, not as ad-hoc per-screen mixing.

## Code Reuse Discipline — Tier by Layer

Reject "80%+ code shared" marketing as a planning input. Realistic ranges per layer:

| Layer | Typical reuse | Why |
|---|---|---|
| Domain logic / use cases | 80%+ | language-agnostic business rules |
| API client / serialization | 70-90% | shared Ktor / kotlinx.serialization wrapper |
| Local persistence | 50-80% | SQLDelight cross-platform; platform-specific storage details may diverge |
| ViewModel / presenter | 50-80% | when shared; varies if platform UIs need different state shapes |
| UI | 0% (native UI) to 80% (Compose MP) | depends on Compose MP adoption decision above |

A project's actual reuse percentage is an outcome of architecture choices, not a goal — published case-study numbers (e.g., Forbes 80%+, Respawn 96%) reflect those teams' specific architecture + product surface, not a generic target.

## Build and Toolchain

- **Convention plugins (`build-logic`) prevent Gradle drift across multi-target modules**: KMP projects have meaningfully more Gradle complexity than single-target Android (target declarations, source-set wiring, framework export config). Encapsulate shared build logic in convention plugins consumed by each module — without them, the build files become the project's largest maintenance surface.
- **Kotlin/Native compile time is non-trivial**: native compilation (LLVM lowering + linking) is slow vs JVM compile. Reserve dev workflow for incremental builds; full clean builds should run in CI, not at every desk-side iteration.

## Testing Matrix

- **`commonTest`** holds tests for pure-common code using `kotlin.test` — runs on every target.
- **Platform-specific test source sets** (`androidUnitTest` / `iosTest` / etc.) hold tests that need real platform APIs or test framework features.
- **iOS test on simulator AND device for release-gating flows**: simulator catches most issues but background tasks, push, biometrics, and capability gates need device runs (per `mobile-quality-release.md` runtime-test rules).
- **Mocking on KMP**: `mockative` (codegen) and `mockmp` (manual) are options when interfaces are mocked across common code. Default to interface + hand-rolled fake first per `ios-dev.md` mocking discipline; reach for codegen mocking only when the protocol surface is large.

## Platform Stability (per Kotlin docs)

| Target | Stability |
|---|---|
| Android / iOS (Native) / Desktop JVM / Server JVM | Stable |
| Web based on Kotlin/JS | Stable |
| WebAssembly (`wasmJs`) | Beta |
| Linux / Windows desktop native | Stability varies; consult current Kotlin docs before betting on them |

Treat the Stable table as the only source for adoption decisions; do not infer stability from the existence of a target in `kotlin.targets`.

## Rejected as Hype (do not write into rules)

- "Compose Multiplatform replaces Flutter / React Native" — different value props; Compose MP is a Kotlin-first team's UI-sharing bet, not a general cross-platform default.
- "One codebase, ship everywhere" — true only if every platform accepts Compose MP UI; otherwise the realistic model is shared logic + native UI.
- "80%+ code reuse guaranteed" — reuse is an outcome, not a goal (see tiering table above).
- "Hot reload across platforms" — verify per-target before claiming; not all platforms support equivalent hot-reload at production-quality.
- "Wasm production-ready for mobile" — Wasm is Beta; not a mobile path.
- "Cinterop seamlessly bridges Swift" — cinterop targets Objective-C / C ABI; Swift APIs require `@objc` exposure.

## Sibling Routing

- iOS-native design judgment (Material vs native iOS feel, gesture, accessibility): `product-ui-ux-design` owns the design call; this skill does not.
- Pure Android implementation (not in `commonMain`): `android-dev.md`.
- Pure iOS implementation (not consuming KMP framework): `ios-dev.md`.
- Cross-platform release verification (multi-target test matrix, symbolication, image library audit): `mobile-quality-release.md`.
