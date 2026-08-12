# App Client Source Evidence Map

Use this reference when auditing or re-extracting mobile app guidance. The rules below describe *how* to classify Flutter/native Android/native iOS/H5/WebView/RN sources; specific local repository paths and dated cross-check logs live in the private provenance archive outside this skill tree. Mini-program sources route to `miniapp-product-dev`.

Users without code access can still apply the distilled patterns in this file. Do not require access to specific paths unless the task explicitly asks to audit, update, or re-extract implementation evidence.

## Source Coverage

For each app subproject in scope, classify before extracting rules. The shape below is the classification frame; specific entries live in the private archive.

| Dimension | Typical stack signature | Useful extraction | Decision |
| --- | --- | --- | --- |
| Broad app inventory | Batch manifest scan across Flutter `pubspec.yaml`, Android `build.gradle`, iOS `Podfile`, H5/Webview projects, and third-party test apps | App skill must classify Flutter, native Android, native iOS, mini-app, H5/webview-like, or mixed host/module before implementation | Keep |
| Flutter app sources | Flutter manifests including assets, Material/Cupertino, chat/PDF/markdown, Dio, shared_preferences, provider, url launcher | Supports Flutter shared app workflows, asset handling, API clients, local persistence, document rendering, rendered device verification | Keep |
| Native Android sources | Gradle manifests in product app and third-party test-app areas | Native Android evidence exists but some is third-party/test-app; classify source quality before extraction | Keep only product-app mechanics; discard third-party test-app noise |
| Native iOS sources | Xcode/Podfile-based app projects, WKWebView shells, JSBridge | Supports iOS shell contracts, native bridge handlers, orientation/safe-area/status sync | Keep |
| Mobile/H5 sources | React H5 apps with safe-area shell, keyboard avoidance, dialogs, upload/image crop, bottom tabs, route guards, responsive containers, async/error/retry | Strong evidence for mobile interaction states even when implemented as web/H5; route browser specifics to `web-react-dev` | Merge state/interaction mechanics, keep stack boundary clear |
| React Native sources | `react-native` + navigation/storage/image-picker deps | Supports cross-platform navigation, storage, image-picker contracts; not a substitute for native shell when the product hosts a WebView | Keep when present, otherwise note absence |
| Mini-app sources | Taro/UniApp/wepy manifests with platform plugins for h5/weapp/alipay/jd | Supports mini-program shell, page lifecycle, platform variant builds, host-bridge differences | Route implementation, platform APIs, developer-tool verification, review, and release to `miniapp-product-dev`; keep only H5/WebView evidence that runs inside a native app host |
| Design-system mobile source | Published mobile design-system Figma + mobile UI files | Supports safe area, navigation, modal/bottom sheet, toast, image viewer, review landscape/portrait, compact state rules | Route visual/UX rules to `product-ui-ux-design` |

## Source Classification Method

Before extracting rules from a subproject:

1. Confirm the stack signature from manifests (`pubspec.yaml`, `build.gradle`, `Podfile`, `package.json` with native or RN deps). Directory-name guesses alone are not evidence.
2. For default-empty checked-out branches, inspect remote branches (feature, develop, or release patterns are common; the active prefix list is recorded in the private archive). Pick the one with real content. Many native projects keep `main` as a scaffold and ship from a feature branch.
3. Note whether the subproject is a true native app, a WebView host, an RN bridge, a Taro mini-app, or a pure H5 surface. Each has a different contract with the design source.
4. Treat third-party test apps and demo folders as noise. Use them only when explicitly required, never as positive baselines.

## Cross-Skill Routing

- Visual/UX judgment → `product-ui-ux-design`.
- React/browser implementation → `web-react-dev`.
- Native/Flutter/RN implementation → stays here.
- Mini-program/Taro/UniApp implementation → `miniapp-product-dev`.
- Test-layer planning → `testing-strategy`.

## Keep / Merge / Discard

- **Keep**: verify each affected platform explicitly; one platform passing does not prove all platforms.
- **Keep**: app-hosted H5/WebView features need explicit checks for full-screen container behavior, safe-area normalization, keyboard mode, orientation bridge/fallback, native bridge/session state, foreground/background recovery, public/guest/auth route gating, in-region retry, and development-only debug tooling.
- **Keep**: native WebView shells require branch discovery as part of evidence collection when the checked-out default branch is empty; inspect candidate remote branches before declaring native code unavailable.
- **Keep**: native bridge contracts need typed handler payloads, scoped callback ids, terminal callback states, storage sync failure handling, permission denial, orientation cleanup, network/load retry, and production debug gating.
- **Keep**: native media/update flows need platform-specific state coverage: permission denied/cancel/unavailable/upload failure/success callback for camera, and store handoff versus APK download/install-permission paths for updates.
- **Keep**: mobile feature flows need device-behavior tests for inputs, bottom sheets, list refresh/pagination, chart/card overflow, media retry/zoom, custom keypads, persisted control placement, and portrait/landscape variants.
- **Keep**: mobile precision workspaces need source-of-truth state for task context, selected item or batch, cached tasks/media, geometry/scale, timer/quality gates, shell orientation, unlock/exit, and final submission. Media reliability, gesture conflict handling, and orientation cleanup are implementation requirements, not polish.
- **Keep**: app-hosted mobile products need lifecycle and dense-data tests for state restore expiry, sensitive-field handling, route/context mismatch, orientation failure, landscape table geometry, active selector auto-scroll, overflow-only motion, temporary settings validation, and cleanup on exit.
- **Keep**: AI media extraction and account-risk flows need staged state machines and tests for capture/crop/upload/analyze/render/classify/save, retake/retry, disabled-save reasons, disclosure loading, acknowledgement gates, second confirmation, session cleanup, and post-action navigation.
- **Keep**: native-assisted media extraction needs parity checks between preview and final upload, runtime upload-config fallback, redacted observability, and host/web bridge cleanup; do not treat a returned native callback as sufficient if the H5 destination page has not mounted and acknowledged readiness.
- **Keep**: app startup/account flows need native plus web verification for splash, privacy consent, login, registration/binding, first-login password setup, verification restore, logout/delete cache cleanup, and deterministic return to login or onboarding.
- **Keep**: platform capabilities need permission, denial, retry, and fallback UI states.
- **Keep** (external-skill benchmark): a debug-instrumentation teardown skill (external reference, sanitized) showed that a manual removal flow is a convenience path, not the safety mechanism — debug-only instrumentation must be structurally excluded from every real-user build at the dependency/target level (per variant, scoped by channel + data sensitivity) and the exclusion verified on the exact signed artifact (dependency/manifest/plist/entitlement/OTA checks, with a symbol/string grep only as a backstop) via a release-blocking evidence row. Landed in `mobile-quality-release.md` Release Readiness and the SKILL Non-Negotiable Rules; this extends the existing "production debug gating" rules from runtime-flag framing to structural exclusion + signed-artifact verification.
- **Keep** (external-skill benchmark + sibling-sync): an external iOS codegen-resync skill (sanitized) confirmed mobile codegen needs a regeneration discipline that the backend stacks own in parallel (per-stack attribution at the end of this row): never hand-edit generated files, edit source-of-truth then regenerate, never blind-overwrite hand-maintained/user-edited files (gate on the pre-overwrite preimage), and after a generator/toolchain upgrade force a fresh no-cache regen and review the diff vs expected drift — clean/no-op is valid when semantically neutral; confirm the runtime reflects a new schema when a shape change is expected OR appears in the diff (input-only cache keys serve stale output across a generator bump). Closed the sibling-coverage gap in SKILL.md Step 5. Backend stacks unchanged (not extended this round): `go-microservice-dev` already owns the fuller parallel discipline (guarded-backup overwrite, fresh-regen shape-change smoke, regenerate-and-verify); `python-service-dev` owns the core (never hand-edit generated, source-then-regenerate, verify clean/reviewed) but not the guarded-backup/no-cache-smoke specifics — narrowed to what each actually owns rather than claiming full parity.
- **Merge**: React implementation details route to `web-react-dev`; visual density and interaction acceptance route to `product-ui-ux-design`.
- **Merge**: Flutter feature implementation, native Android/iOS boundaries, mobile rendered verification, app build/release checks stay here.
- **Route**: React H5/browser implementation to `web-react-dev`; design acceptance to `product-ui-ux-design`; test-layer planning to `testing-strategy`.
- **Discard**: third-party native test-app folders, source-domain nouns, visual style from low-quality UI, debug logs/tooling in production, and provider-specific storage or bridge names.

Coverage label: broad manifest inventory plus representative file-level refresh, not node-by-node mobile source inventory.

## Where The Specific Provenance Lives

Specific subproject paths, real branch names, manifest signatures, and dated cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
