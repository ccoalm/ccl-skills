# Testing Source Evidence Map

Use this reference when auditing or re-extracting testing strategy. The rules below describe *how* to classify Go/Python/web/app tests and CI gates; specific local repositories and dated cross-check logs live in the private provenance archive outside this skill tree.

Users without code access can still apply the distilled patterns in this file. Do not require access to specific paths unless the task explicitly asks to audit, update, or re-extract test evidence.

## Source Coverage

For each codebase in scope, classify before extracting rules. The shape below is the classification frame; specific entries live in the private archive.

| Dimension | Typical signature | Useful extraction | Decision |
| --- | --- | --- | --- |
| Broad test inventory | Batch file scan across Go, Python, frontend, app, config, CI, and script-like tests while excluding dependency/generated noise | Test strategy must not infer coverage from file names; classify by command, marker/tag, infra need, CI gate, and assertion strength | Keep |
| Go tests | Many unit, handler, logic, DAL/DDL, Redis/ES/object-store, traffic/shadow, benchmark/replay, and integration-tag tests | Supports layer split, live-infra isolation, generated-contract checks, replay/shadow as opt-in regression evidence | Merge |
| Python tests | pytest markers, API/contract/integration/e2e scripts, inference handler tests, benchmark pipelines, local integration stacks | Supports marker-aware topology, failure/drill/shadow gates, separating live infrastructure from default fast tests | Merge |
| Web tests | Vitest, Testing Library, Playwright e2e, structure checks, build/typecheck/lint scripts across React/Vue projects | Supports layered frontend testing: component state, API-client/contract, browser smoke, build checks | Merge |
| App tests | Flutter test dependency and mobile manifests; native tests are typically thinner | Keep platform verification rules; do not overstate native automated-test coverage from sparse evidence | Keep with gap |
| Weak/noise sources | Vendored SDK tests, third-party libraries, generated clients, old worktrees, static outputs | Must be excluded from topology unless the task targets those artifacts | Discard/noise |

## Source Classification Method

Before extracting test obligations:

1. Discover local test wrappers and CI gate truth before inventing test commands. The CI file is authoritative, not the `package.json` script.
2. Distinguish strong / medium / weak tests by assertion shape, not by file count:
   - **Strong**: deterministic assertions, no live dependencies, runs in a default fast gate.
   - **Medium**: assertions present but depend on fixed DB/cache/inner-network state; runs in an explicit infra gate.
   - **Weak**: logs/prints only, randomness or long sleeps, calls live model/Ray/data paths, or sits behind `allow_failure`.
3. Inventory by command, marker/tag, infra need, and CI gate — never by file count.
4. Treat build/format/typecheck scripts as structural gates only; they do not substitute for behavioral assertions.

## Cross-Skill Routing

- Stack-specific test mechanics live in `web-react-dev` (browser), `app-cross-platform-dev` (mobile/native), the relevant backend skill (services).
- Scenario testing is a planning layer that maps risk to the lowest sufficient assertion layer plus real-flow smoke only when cross-boundary behavior matters.
- LLM inference/eval testing routes to the relevant inference/eval guidance, not here.

## Keep / Merge / Discard

- **Keep**: discover local wrappers and CI truth before inventing test commands.
- **Keep**: scenario testing is a planning layer that maps risk to the lowest sufficient assertion layer plus real-flow smoke only when cross-boundary behavior matters.
- **Keep**: frontend API-backed UI needs component, API-client/contract, and browser/device smoke evidence when feasible.
- **Keep**: precision workspaces need tests for media reliability, gesture conflicts, repeated input modes, batch/default submission consequences, lock/expiry recovery, native orientation, and shell exit cleanup; a route build or click-only smoke is not enough.
- **Keep**: complex web shells need scenario tests for route/permission shell load, hosted/embedded fallback, process tab persistence and active deletion fallback, route-versus-process selection exclusivity, measured overflow only after real overflow, permission-hidden workbench modules, shell/module minimum widths, stacked-module fallback, sticky-disabled behavior when stacked/narrow, AI launcher geometry, streaming/session/input states, and login/auth/partner branding states.
- **Keep**: high-throughput evaluation workbenches need component/API tests for split-count state, selected-item preservation, incomplete-submit confirmation, media retry, preference restore, drawer filters, plus browser evidence for long artifact, narrow viewport, queue-end/no-work, and recovery states.
- **Keep**: structured assignment workbenches need component tests for batch selection, disabled reasons, split/merge mode transitions, quota under/over-allocation, role conflict messages, permission-summary finalization, and read-only/started variants; API/client tests for save/autosave/finalize normalization, import failure payloads, and export job status; browser evidence for sticky headers, selected-count action bar, drawer return context, long owner names, and narrow desktop stress.
- **Keep**: mobile/H5 hybrid work needs adapter/unit tests for storage TTL, sensitive-field transforms, route gating, bridge capability detection, and orientation fallback; component tests for async retry and foreground/background restore; device/host-container smoke for safe area, keyboard, orientation, and tab/sticky action visibility.
- **Keep**: native-assisted media flows need test obligations for bridge callback contracts, malformed payloads, transition overlay/page-ready cleanup, camera permission/hardware/album/torch/focus states, crop/aspect/EXIF correction, processed-preview versus uploaded-byte parity, all-black/all-white and size-budget guardrails, runtime upload config fallback, signing-version switch, redacted logging, upload failure, foreground/background interruption.
- **Keep**: client foundation auth/profile needs test obligations for splash/consent, password login, phone-code login, account-opening or binding when supported, first-login password setup, forgot/reset, verification paste/autofill/focus/backspace, resend countdown, foreground/background restore with sensitive fields, logout/delete cache cleanup across web/native storage, profile/privacy/about route clusters, version update states, and route/tab behavior after session changes.
- **Keep (backend)**: Go service testing identifies service shape and local wrappers before choosing commands; keep generated-code drift, IDL changes, handler/logic tests, DAL/cache/MQ tests, async task finality, streaming timeout/cancel/error, and live-infra tests in separate gates instead of one undifferentiated `go test ./...`.
- **Keep (backend)**: Python/AI testing handles readiness-before-registration, service metadata, heartbeat/unregister, version routing, request/log id propagation, parser boundaries, and inference handler/router behavior with fast tests or targeted integration tests; hosted inference capacity and quality evaluation route to LLM testing/eval guidance.
- **Merge**: stack-specific mechanics live in Go/Python/Web/App skills after this skill chooses the layer.
- **Discard**: test-count based confidence, click-only E2E, live credential tests in default fast gates, dependency/generated test noise, and demo modules as primary service coverage.

Coverage label: broad topology inventory plus representative file-level refresh, not full assertion audit of every test.

## Where The Specific Provenance Lives

Specific repository inventories, test file counts, CI file lists, and dated cross-check logs live in the maintainer's private archive. They are not included in this file, so any cross-organization use of this skill stays clean.
