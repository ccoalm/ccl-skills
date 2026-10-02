# CCL plugin automatic updates

## Acceptance and scope

Acceptance-source lookup: found in the delivery brief for this feature. This
record fixes the bounded acceptance inventory before implementation. The outcome
is less manual upkeep for a user who explicitly enables automatic updates of an
existing Git installation of `ccl-skills@ccl-skills` in the active Codex profile
or healthy npm-managed CCL assets in OpenCode.

- A1: `auto-update enable|disable|status [--host codex|opencode] [--json]` is explicit, noninteractive,
  and preserves all existing install/update/uninstall command semantics.
- A2: macOS launchd registers a daily job only after public Codex JSON confirms
  the canonical Git marketplace and installed plugin. Unsupported platforms,
  old CLI capabilities, npm snapshots, and missing installations fail clearly.
- A3: the persisted runner survives removal of an npx directory, uses absolute
  executables and fixed HOME/CODEX_HOME/PATH, and persists no inherited secrets.
- A4: each run rechecks provenance, upgrades only `ccl-skills`, then adds only
  `ccl-skills@ccl-skills` on successful upgrade; every command is bounded and
  overlapping runs are skipped.
- A5: enable is idempotent, status checks live registration and last-run evidence,
  registration failures cannot appear enabled, and disable removes only the
  owned schedule while retaining bounded diagnostic evidence.
- A6: reject the covered managed-file symlink/hardlink, mismatched ownership
  record, foreign job and unsafe-path cases; preserve spaces and XML
  metacharacters without widening plugin scope. This validates managed files
  and paths, not authentication against a hostile writer with the same UID.
- A7: actual local launchd and published-package acceptance are separate release
  checks owned by the release controller.
- A8: `--host codex|opencode` selects one independent schedule; omitted host
  continues to mean Codex. Unsupported hosts and `all` are rejected.
- A9: OpenCode enable requires healthy npm-owned bundled CCL assets. Missing,
  source-copy, override and drifted installations are refused with migration or
  repair guidance. It never implicitly installs absent CCL assets.
- A10: OpenCode runs fetch the latest public npm package into a fresh private
  prefix with lifecycle scripts disabled and fixed registry/config/cache/cwd;
  validate package identity before executing the fetched CLI. Reuse the OpenCode
  adapter for doctor/update with package self-update disabled; never downgrade.
- A11: OpenCode application, auth/config, unrelated shared files and the
  compatibility skill tree remain outside update scope. Fetch or preflight
  failures leave installed assets intact; interruption reports its actual
  finality and allows bounded adapter rollback before forced termination.
- A12: tests prove host separation, fresh artifact use, no downgrade, ownership
  refusal, fetching failure, result validation and cancellation with synthetic
  HOME and package/CLI boundaries. Real OpenCode acceptance belongs to release.

Non-goals: Linux cron (unsupported in this bounded release), global package self-update,
global/root installation, trust approval, auth changes, other hosts/marketplaces,
and edits to source installer behavior. Risk: release operations, external
integration, reversible local scheduling writes. Registration uncertainty retains
state and asks for a retry after restoring launchd; it is never a success.

## Design brief

`slice_id`: codex-auto-update. `candidate_ref`: feat/codex-auto-update based on
`dcdc9ba9c54f708348dbfc46fb4964ec8d452001`. `trigger_class`: narrow-visible,
source-code-evidence, behavior-change. `surface`: Node 20+ ESM one-shot plain
terminal CLI on macOS; unsupported response on other platforms. `density`:
one primary status plus recovery/log path; JSON is a single stdout object.

`consumer_inventory`: package.json exposes only dist/cli.js as the management
CLI; that surface is affected. Existing host installers remain unchanged.
`user_and_task`: a Codex Git-plugin or OpenCode npm-install user enabling persistent updates and checking
whether they actually work. `intent_and_risk`: explicit opt-in removes repetitive
manual refreshes; a registered schedule is distinct from a successful run.
`structure`: verb selects the action, status leads, diagnostics and recovery
follow. No prompt, animation, color, cursor positioning, or screen clearing.

`state_matrix`: absent/disabled, installed and registered, registration failed,
unsupported platform/source/capability, failed last run, running/overlap,
unsafe/foreign ownership, and interrupted operation with retained evidence.
Retry is explicit enable; disable is reversible. No optimistic success.
`adaptation_matrix`: pipe and terminal, TERM=dumb/NO_COLOR, 80 columns and 40
columns; lines wrap naturally and are not truncated. Raw mode, focus, mouse,
selection, resize, and keyboard navigation are N/A: output uses only newline
terminated text, never terminal controls or interactive input.
`behavior_contract`: see A1-A6 and A8-A12. Enable/disable execute directly because their
verbs explicitly request reversible local scheduling changes. JSON preserves
the existing code/status/message/details result envelope. No --yes ambiguity.
`design_source` and `reference_surface`: existing cli.ts output/result convention
and this feature's acceptance inventory; no visual redesign.
`design_record`: this file. `owners`: design product-ui-ux-design; testing
testing-strategy; producer nodejs-service-dev; client terminal-cli-dev; release
controller owns actual host and npm acceptance. `evidence_plan`: filesystem and
fake-boundary integration, CLI subprocess output, package tests; real scheduler
and public package smoke are delegated release checks, not asserted here.

## Test Phase 0 and client entry

`client_entry`: terminal-cli-dev Core Workflow 2 requires the terminal contract
before coding. Decision: reuse code/status/message, plain text and JSON with no
TTY requirement, no confirmations, no terminal state changes, no notifier for
auto-update. Target Node 20+ CLI. Capture commands below. Preserve previous
command tree, defaults, self-update and preview semantics.

| Cases | Layer and oracle | Command | Baseline | Owner |
| --- | --- | --- | --- | --- |
| A1 command tree/help/errors/JSON | CLI subprocess and parser, exact action and nonzero misuse | `node --test test/auto-update.test.mjs` | fail: command absent | terminal-cli-dev |
| A2 provenance/platform | public JSON boundary fake, refuse noncanonical Git/npm/absent/invalid | same | gap: feature absent | nodejs-service-dev |
| A3 stable runner/env | isolated filesystem and executable fake, run copied JS after install | same | gap | nodejs-service-dev |
| A4 ordering/failure/timeout/overlap | real runner with fake Codex, inspect calls and durable result | same | gap | testing-strategy |
| A5 registration/retry/disable | launchctl fake and owned files, no false success or foreign delete | same | gap | testing-strategy |
| A6 path/state attacks | isolated synthetic HOME, reject collisions and preserve sentinels | same | gap | testing-strategy |
| A1 existing semantics | existing package suite | `npm test` | invalidated by concurrent build; isolated rerun required | nodejs-service-dev |
| A7 actual scheduling and published entry | real launchd and package smoke | release controller commands | live-only | release controller |

Test definitions: test/auto-update.test.mjs plus existing package suites. Tests
double only public Codex and launchd process boundaries; filesystem, JSON/XML,
copying, locks and runner execution use real Node APIs and synthetic directories.
CLI stdout is the rendered evidence layer; no emulator-specific behavior is
introduced. Stop on unknown ownership/provenance, unverified registration, or
failed timeout cleanup. Before handoff bind implementation/test bytes and map
each acceptance point to evidence; do not equate lower-layer success to A7.

## OpenCode extension design and Phase 0

The active scope includes the explicit OpenCode request in addition to Codex.
The previous Codex-only implementation is the baseline, not a user restriction.
The same Node/terminal/test/design owners apply; full loads were refreshed after
context recovery. Reader-facing finalization uses tighten-doc. No subdelegation.

`surface`: the existing one-shot management CLI, with a host flag and separate
host status. `consumer_inventory`: dist/cli.js plus the OpenCode adapter's JSON
doctor result (additive version/sourceKind details). Existing install/update
default selection remains unchanged. `state_matrix`: npm-owned healthy, absent,
source-copy/override, drifted, refresh pending/failed, wrong package identity,
newer installed version, disabled mid-run and interrupted/unknown finality.
The original plain-output adaptation matrix and client_entry remain applicable.

OpenCode state belongs under ~/.config/opencode; it never depends on CODEX_HOME.
Its launchd label, state, log and locks are separate. Enable runs the current
package's OpenCode doctor with a minimal environment and requires bundled npm
ownership. Each run creates one exclusive temporary package prefix beneath its
owned updater directory; npm uses a fixed public registry, private empty config
files and cache, ignored lifecycle scripts and no executable links. Only that
newly created prefix is cleaned up. The saved runner contains no temporary npx
reference. Absolute node/npm/OpenCode executables and fixed HOME/PATH persist.

After fetch, verify package name, stable version, CLI location and bundled
release identity; run the fetched CLI's doctor and explicit OpenCode update with
CCL_SKILLS_SKIP_SELF_UPDATE=1. A newer installed version is retained. Require a
valid JSON result and a healthy post-update receipt. Recheck enabled state before
mutating shared assets. The existing adapter owns collision/drift/downgrade and
rollback checks; the scheduler never writes those shared assets directly.

OpenCode asset updates use bounded graceful SIGINT cancellation so the existing
CLI worker can roll back; expiry of the grace period forces termination and
reports unknown/partial finality. Fetch/preflight failure preserves installed
files, but a hard kill during mutation cannot claim atomic rollback. Config,
auth, OpenCode itself and the compatibility skills tree are not mutated.

| Cases | Layer and oracle | Command | Baseline | Owner |
| --- | --- | --- | --- | --- |
| A8 explicit host/default/invalid values | CLI parser and independent state/labels | focused auto-update tests | fail: host flag absent | terminal-cli-dev |
| A9 absent/source-copy/drift/override | real OpenCode adapter with isolated fixture | focused OpenCode auto-update tests | gap | nodejs-service-dev |
| A10 fresh/older/invalid artifact | npm boundary fake plus real fetched CLI/adapter, receipt/content assertion | same | gap | testing-strategy |
| A11 failure/cancel/disable | process lifecycle plus exact owned files and logs | same | gap | testing-strategy |
| A12 real installation and published entry | release smoke | release verification | live-only | release controller |

Security questions: caller controls profile/path but persisted host and paths
must match the current canonical context; mismatched host/profile state and the tested foreign package identities are
refused; same-account hostile writers are outside the authentication claim; npm's fixed public registry supplies the
package and the adapter verifies installed ownership; adversarial tests cover
wrong identity, source override, symlinked prefix and host crossover.

Security questions: callers control HOME/CODEX_HOME/PATH; owned state rejects
structurally invalid and profile-mismatched records; Codex public JSON establishes plugin identity; filesystem
ownership plus exact persisted job content establishes scheduling authority.

Implementation entry: active baseline is this newly created plan, local status.
The four dispatched owners were loaded in full in-session before edits. Triggered
mechanics: Node ESM/build, bounded child lifecycle, atomic writes, CLI output and
recovery, test-case register/RED, UI design contract. Risk routing and delegation
were completed by the controller; this is its single cohesive implementation
slice with no subdelegation. Existing nearest contracts already cover this
distributable CLI and its public-host/ownership boundaries; no contract edit is
needed. Auth/trust, schema migration and cross-repo edits are
not applicable to the scheduler. First source-edit checkpoint requested a recheck; session-policy
and implementation-entry-reentry-gate were read and the same owners applied.

RED-baseline: `npm ci && npm run build && node --test test/auto-update.test.mjs`
ran successfully through build, then failed the A1 assertion: expected parsed
action, actual `{code:2, stream:stderr, text:"Invalid command or option. Run --help."}`.
One assertion test ran, zero passed, one failed. No implementation existed then.

OpenCode design disposition: accepted for implementation within the expanded
scope. Post-doctor must match fetched version and bundled sourceKind; cancellation
may report partial/unknown after forced termination. Source-copy migration stays
an explicit backup/install operation outside the scheduler. Test-case-first
entry used the new host-selection assertion in test/auto-update.test.mjs; existing source/test owners
and the plain terminal client entry remain active.

OpenCode RED: the explicit-host parser assertion ran before implementation and
failed because the command rejected --host. The graceful-output regression then
failed against unbounded accumulation before that fix. Both are included in the
final focused run. Re-entry retained this same local, unlanded baseline; the
Node, terminal, testing, design and documentation owners were reloaded and the
accepted safety/test boundaries reapplied before further edits.

## Release-check repair

Classification: gate implementation; risk tag shared-gate, in addition to the
release-ops route. The public sanitizer incorrectly classifies GitHub SSH Git
transport userinfo as a private email address. The release check reported three
affected candidate files. Scope is the existing sanitizer and its regression
suite; private addresses and other privacy checks must retain their verdicts.

| Named input | Required verdict |
| --- | --- |
| Canonical GitHub Git SSH URL or SCP-style repository address | pass |
| Bare GitHub email, other username, other domain, malformed repository path | fail |
| Existing private IP, hostname, tenant and email cases | fail |
| Existing public/example and escaped-decorator cases | pass |

Implementation owner: python-service-dev; failure evidence: defect-diagnosis;
test strategy: testing-strategy. Add the passing Git transport case first and
observe RED, then recognize only that exact transport grammar. Add near-miss
negative cases to the existing table. Run the focused sanitizer suite, repository
sanitizer and full make lane. Independent review and challenge must include the
gate's false-positive and false-negative boundary before shared branch push.
Status and results are recorded with this feature's release evidence.

Verifier discovery: root contract, Makefile and CI name check-spec-references.py
as the applicable spec-reference verifier; it passed before this gate edit. No
runtime plan-status format is introduced. This is a simple deterministic
non-incident regression; no customer data, credentials or permissions change.

## Runner lifecycle repair

Re-entry baseline: local, unlanded candidate
`3872d491bcd761d733b697fa3d2d4e2e62fc5887`, clean isolated feature worktree.
The accepted A4/A5/A11 lifecycle and truthful-status requirements remain active.
Prior full-suite and host evidence remains bound to that candidate. This repair
does not change installer behavior, scheduling scope or release authorization.

Hypotheses to verify before runtime edits: a signal after a child finishes can
escape cleanup; an old lock whose PID is now alive can be reported as healthy
overlap indefinitely. Controlled subprocess boundaries and filesystem timestamps
provide deterministic falsifiers. No real launchctl or host installation is used.

| Case | Layer and expected evidence | RED → GREEN |
| --- | --- | --- |
| R1 Codex signal between commands | subprocess receives real SIGINT/SIGTERM; failed log, released lock, no later mutation | Both terminated by signal with lock/running log → both exit 5, clean lock, failed log |
| R2 OpenCode signal after fetch | subprocess receives real SIGTERM without an active child; failed log and private-prefix/lock cleanup | Terminated with lock/running log/refresh directory → exit 5, cleanup, no next command |
| R3 old lock with unrelated live PID | filesystem/runner/status integration; nonzero failure, retained lock and no host mutation | Both lock types reported healthy → both return exit 5 and preserve lock |
| R4 adjacent lifecycle controls | repeated signals, listener cleanup, management lock and existing true overlap/graceful-child cases | Management signal retained lock → clean exit 5; full focused suite 69/69, no skips |

Implementation owner: nodejs-service-dev (async lifecycle reference); diagnosis:
defect-diagnosis; layers and RED/GREEN: testing-strategy. Terminal and product
UI owners preserve the existing plain/JSON envelope and recovery surface while
requiring a visible uncertain-lock failure instead of a healthy running claim.
The original Design brief, adaptation matrix and client entry apply. Documentation
finalization uses tighten-doc. Product-rd re-entry and session policy were applied.
This is one continuing delegated slice; no child delegation or new owner boundary.

Implemented correction: cancellation listeners cover the complete runner and
management operation, with checks around child commands. A single event-loop
yield lets queued signals run before accepting a command result. Child failure
details and OpenCode rollback grace remain intact; listeners are removed in
finally. Locks whose timestamps differ from the current time by at least 15
minutes fail closed, even with a live PID. The lock stays available for inspection.
Younger live-PID locks still count as overlap; this is a bounded age policy, not
process identity verification. No automatic lock reclamation was added.

Build passed, the six reproducers changed from 0/6 to 6/6 passing, and both complete
auto-update suites passed 69/69 without skips, including the mutation controls.
Logs and current artifact hashes are in evidence.md and bindings.json. Fresh
full-package/repo/pack/host checks and renewed independent review remain release
verification work. No manual visual test is needed for unchanged newline-only
rendering.
