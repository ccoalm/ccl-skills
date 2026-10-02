# Auto-update implementation evidence

## Candidate and commands

The exact artifact hashes are in [bindings.json](bindings.json). The final
focused runner output is [focused-tests.txt](focused-tests.txt). Bindings include
changed design, source, CLI, test and documentation files plus the generated
JavaScript actually executed. The runtime was Node 26.7.0 on macOS; the package
continues to declare Node 20+ and TypeScript/ESM with zero runtime dependencies.

| Command | Result and boundary |
| --- | --- |
| `npm ci` | Passed; 3 development packages, audit reported 0 vulnerabilities. |
| `npm run build` | Passed on final runtime source; TypeScript compilation and asset generation. |
| `node --test test/auto-update.test.mjs` before implementation | RED: the parser returned exit 2 / Invalid command or option instead of an action. One test, one failure. |
| `node --test test/auto-update.test.mjs test/opencode-auto-update.test.mjs` on final candidate | See captured output; isolated public-command fakes plus real filesystem, runner and process lifecycle. |
| OpenCode host-selection assertion before extension | RED: --host rejected; explicit host assertion failed. |
| Graceful output-limit assertion before fix | RED: stdout exceeded its bound while waiting for cancellation. |
| `git diff --check` | Passed. |
| `npm test` during implementation | Invalid evidence: a concurrent rebuild removed generated assets while operations tests used them. Run was stopped with exit 143; no package-wide pass claimed. |
| Full package checks | Build, build-mode checks and the complete test glob passed: 419 tests, zero failures or skips. Node test-file concurrency was limited to 2 on the local host. |
| `npm run build && npm run test:pack` | Passed on clean candidate `c2554232447ecc337d5f249295f9c3f2ceb2c34f`: 11 tests, zero skips; 669 verified asset files. |
| `npm run smoke:host` | Passed real Codex, Claude Code and OpenCode installation, update, doctor and uninstall in isolated homes. Public registration is covered; live hook enforcement is not inferred. |
| macOS launchd integration | Passed RunAtLoad, spaces/XML paths, idempotent enable, execution after the npx package was removed, failed-run status, recovery and disable/unregister. Only the Codex network boundary was substituted. |
| Repository and publication checks | Release verification owns the full repository lane, independent review, current-head CI and registry-backed publication acceptance. |

## Acceptance coverage

| Criteria | Evidence | Boundary |
| --- | --- | --- |
| A1 | Parser valid/invalid action cases, preserved update preview, actual CLI JSON/help subprocesses | Existing full package semantics require the separate package run. |
| A2 | Canonical HTTPS and SSH cases; npm, foreign marketplace/plugin source, missing/duplicate marketplace, malformed JSON and disabled plugin rejection | Public responses are synthetic fixtures following the observed CLI shape; actual host acceptance is separate. |
| A3 | Copied runner executes during bootstrap, absolute executable paths, profile with spaces/XML characters, exact child environment, default CODEX_HOME | OS may inject its own runtime variables. Executables must remain installed at the saved paths. |
| A4 | Exact upgrade/add order, failed upgrade suppresses add, provenance change during upgrade suppresses add, concurrent run skipped, process-group timeout, SIGTERM cleanup | Public Codex lacks atomic compare-and-update; checks protect the observed checkpoints. |
| A5 | Idempotent enable, bootstrap failure/retry, disable/fenced unload failure, launchd exit overriding old success, stale lock failure, concurrent first enable | launchctl itself is a test boundary; real login persistence remains a host check. |
| A6 | Managed symlink/hardlink, foreign plist/job, missing-state registration, forged profile, unsafe ancestor cases preserve targets | No authentication guarantee against a hostile writer with the same UID. |
| A7 | Real launchd and three-host lifecycle passed | Original local activation and the published npm entry remain post-publication release checks. |
| A8 | Parser defaults/host validation plus simultaneous independent Codex/OpenCode jobs; disabling OpenCode preserves Codex registration | Synthetic launchctl boundary. |
| A9 | Real adapter doctor rejects absent, source-copy, override and drift fixtures before scheduling | Synthetic host executable; real filesystem and manifests. |
| A10 | Fresh downloaded skill content and version pass through fetched CLI; older version retained; wrong identity and symlinked package refused | npm download is faked; registry transport/integrity is a release check. |
| A11 | Config/personal plugin/compatibility files preserved; fetch, removal, drift and disable before update leave assets intact; invalid post-doctor fails; SIGINT cleanup and forced unknown finality | Cancellation wrapper uses real subprocesses; adapter rollback retains existing package-suite coverage. |
| A12 | Saved OpenCode runner executes its absolute fake npm and fetched CLI; private prefix cleanup and exact allowed child env asserted | OpenCode application and real published npm artifact require release smoke. |

The destructive disable ownership checks also carry an executable mutation probe:
remove the foreign-plist comparison or hardlink guard in a disposable copy and
require the sole corresponding assertion to fail. Each control must run and pass
one test; each mutant must parse and fail one assertion. The probe clears inherited
Node test context and cannot recurse. This is sensitivity evidence for those two
guards, not an exhaustive mutation score. The OpenCode package-identity case
also executes a clean control and a guard-removal mutant in a disposable package
copy; the wrong-package assertion must reject the mutant.

## Producer, client and design return

`producer_record`: auto-update.ts and its generated JavaScript implement the
bounded public-command integration and stable runner. `client_record`: cli.ts
uses the same result envelope and newline output as existing commands. The CLI
subprocess exercised that producer with the hashes in bindings.json. Exact test
commands and captured states resolve above.

The pre-edit client rule and Phase 0 choices are in [plan.md](plan.md). Observed
states include absent/disabled, enabled, failed registration, failed update,
unsupported platform, invalid input, ownership refusal and recovery. JSON and
plain help run without a TTY, including TERM=dumb/NO_COLOR; ANSI/cursor/focus/
mouse/resize/selection dimensions are not applicable because this path emits
plain newline output and never alters terminal state. No claim depends on a
terminal emulator screenshot. Actual scheduler and published-package behavior
are not inferred from text output.

Test Phase 1: A1-A6 and A8-A12 pass within the stated boundaries. The full package
suite and actual scheduler/host lifecycle checks close the implementation
handoff's remaining test gaps. The complete design, test, producer and client
binding set remains in bindings.json; release validation exercised the same
source and test bytes, with later changes limited to evidence records.

Design verdict: accepted for the narrow CLI state, output and recovery contract;
verdict owner: design author under the deterministic narrow-visible exception;
next state: complete for that surface. Each criterion uses a deterministic
oracle, with no aesthetic or product-direction judgment. Publication, registry
verification and activation of the original local installations remain separate
operational acceptance checks under A7/A12. This record does not claim those
post-publication outcomes or field reliability.

The first broad package run passed 417 of 419 tests. An inherited self-update
opt-out invalidated one test; a mutation subprocess exited abnormally during
parallel execution. Both passed in the clean, bounded-concurrency full rerun.
Its exact command was `npm run build && node scripts/test-build-modes.mjs &&
node --test --test-concurrency=2 test/*.test.mjs`; no test was filtered out.

## Ownership and recovery limits

The saved runner is intentionally retained across re-enable and npm upgrades;
this patch does not introduce a runner migration protocol. An abrupt crash can
leave a run.lock or manage.lock. Stale locks fail closed and require checking the
recorded PID has exited before removing that lock. Ordinary command failure,
timeout and handled SIGTERM release the running lock. Disabling retains the
runner/state/log and fences future update steps before asking launchd to unload.

Reader-document closeout covered both changed READMEs, their install/update
context and migration/recovery instructions. Technical claims were checked against
current source and focused tests. npx examples preserve access for Git users
without a globally installed CLI. Existing command defaults and npm snapshot
boundaries remain explicit. The automatic-update heading and its inbound anchor
were renamed together; both old-title and old-anchor residual scans returned
no matches. No unrelated headings or publication faces changed;
the repository and packed README are published by the release workflow.


OpenCode adds only version/sourceKind details to a healthy doctor result. Its
scheduled update reuses the existing adapter and preserves its manual command
semantics. No source installer, global npm install, application update, auth or
trust policy was added. The fresh private prefix is invocation-owned; an abrupt
runner kill can retain temporary files alongside the stale lock for inspection.
