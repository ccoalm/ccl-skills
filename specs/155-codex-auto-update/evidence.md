# Auto-update implementation evidence

## Candidate and commands

The exact artifact hashes are in [bindings.json](bindings.json). The current
focused run passed 76/76 tests on Node 20.20.2, including real fetched-CLI rollback and its
worker-cancellation mutation probe. The preceding ownership summary is
[log-ownership-checks.txt](log-ownership-checks.txt). Bindings include
changed design, source, CLI, test and documentation files plus the generated
JavaScript actually executed. Earlier runs used Node 26.7.0 on macOS; the package
continues to declare Node 20+ and TypeScript/ESM with zero runtime dependencies.

The lifecycle repair starts from `3872d491bcd761d733b697fa3d2d4e2e62fc5887`.
Commands below ran in `packages/ccl-skills-npm` with synthetic homes and commands.

| Current repair check | Result |
| --- | --- |
| `npm run build` | Passed; generated JavaScript is included in the current bindings. |
| `node --test --test-name-pattern='command boundary\|old live-PID' test/auto-update.test.mjs test/opencode-auto-update.test.mjs` against baseline runtime | RED, exit 1: all six assertions failed. [Captured output](lifecycle-red.txt) replaces local paths with placeholders; the raw log is retained outside the repository. |
| Same six assertions against repaired runtime | GREEN, exit 0: 6/6 passed, no skips. [Captured output](lifecycle-green.txt). |
| `node --test test/auto-update.test.mjs test/opencode-auto-update.test.mjs` | Exit 0 on Node 20.20.2: 76/76 passed, no skips, including ownership/package and worker-cancellation mutation controls. The earlier 71-test summary and 69-test output remain as historical evidence. |
| `node --test --test-name-pattern='refused runner preserves' test/auto-update.test.mjs` before log-ownership correction | RED, 2/2 failed: an empty or malformed lock let a refused invocation replace an existing running record with failed. Both pass in the 71-test run. |
| `git diff --check` | Passed. |
| Fresh full repository, package, pack, host and independent review checks | Pending release verification on the repaired candidate. Earlier passes below are historical evidence. |

The baseline signal tests terminated with SIGINT/SIGTERM instead of exit 5,
retaining the lock and a running log. OpenCode also retained its refresh directory.
The management case retained its lock. Both 16-minute-old locks containing an
unrelated live PID reported healthy status. The repaired cases assert cleanup,
failed results, no next command, listener removal and retained uncertain locks.

Signal handlers previously belonged only to an active child, leaving operation
cleanup unprotected between commands. Keeping handlers for the owning operation
and yielding once after each command lets pending signal callbacks fence later
commands. Active-child cancellation and forced-termination diagnostics remain
unchanged. PID liveness cannot establish lock ownership after PID reuse, so a
15-minute age bound makes uncertainty visible without stealing a lock. Existing
active-child and dead-PID tests did not exercise either failure boundary; the new
real-signal and live-PID fixtures do.

Implementation self-review preceded the renewed independent review. The delivery
owner read the complete runtime/test diff and checked A4/A5/A11, operation-wide
signal handling, preserved child-failure details, finally cleanup, retained old
locks and true overlap. The six RED-to-GREEN cases and complete 71-test focused
run support those checks. Changed files are the package README, runtime, two
test files and this spec's plan, evidence, logs and bindings; unchanged feature
files retain their earlier file-by-file self-review. Residual limits are overlap
from a reused PID for up to 15 minutes and no cleanup after SIGKILL.
Current-head CI and publication checks remain pending.

The subsequent log-ownership check confirmed two additional RED cases before
the correction: state validation permitted writing last-run.json without owning
run.lock. The implementation now requires successful lock acquisition. A refused
invocation preserves an existing record and leaves an absent record absent;
status still reports malformed or stale locks without claiming healthy overlap.
The delivery owner rechecked every changed branch and updated assertion before
renewed review. The independent design judgment is keep the updater and narrow
log writes to their owner; no new lock protocol or automatic recovery is needed.

The existing interruption call path is cli.ts SIGINT handling, the shared atomic
flag in cli-worker.ts, unified.ts host dispatch and opencode-adapter.ts interruption
checks and rollback. The existing host-adapters test covers rollback of shared
writes mid-copy. Forced process termination still reports unknown finality.

The fetched-CLI integration now pauses immediately after the sample shared file
is renamed into place, observes the new bytes, and sends real SIGTERM to the
scheduled runner. Its unchanged command runner sends process-group SIGINT to
the fetched CLI; the real supervisor and worker complete the adapter rollback
with child exit 130. Assertions require scheduled exit 5, a failed run record,
the previous manifest and every previous managed file byte, and no run lock or
refresh/rollback/staging residue. A test-only Node preload coordinates the write
boundary without replacing cancellation handling or the adapter transaction.
The isolated mutation probe removes worker cancellation propagation; the same
test then fails at the unchanged-manifest assertion. Both targeted tests pass,
and that focused suite passed 73/73. This addition changes tests only.

The Node 20 CI run exposed two fixture assumptions: the build-mode test leaves
directories at 0775, whereas an actual registry install produced 125 directories
all at 0755; filtered TAP totals also include skipped tests on Node 20. Running
the same build-mode command and OpenCode suite locally on Node 20.20.2 reproduced
all six CI failures. The fetched fixture now models npm extraction modes, and
mutation controls require one passing test instead of one total test. A separate
writable-package case retains rejection of 0775 package directories. The complete
build-mode path also exposed a 0664 release.json; the real registry package has
0644 data files and 0755 executables. The fixture now normalizes both kinds and
a writable-file negative retains rejection of 0664 metadata. Production ownership
checks are unchanged. Every pre-update failure also asserts refresh cleanup.
The existing Codex SIGTERM case now covers both upgrade and add, proving failed
status, the existing instruction to inspect Codex, and lock release. The full
focused suite passes 76/76 on Node 20.20.2.

### Historical implementation checks

The following checks preceded the lifecycle repair. The original 63-test focused
output remains in [focused-tests.txt](focused-tests.txt); its candidate bindings
remain recoverable at the baseline commit above. Broad checks do not establish
the current repair's release readiness.

| Command | Result and boundary |
| --- | --- |
| `npm ci` | Passed; 3 development packages, audit reported 0 vulnerabilities. |
| `npm run build` | Passed on the pre-repair runtime source; TypeScript compilation and asset generation. |
| `node --test test/auto-update.test.mjs` before implementation | RED: the parser returned exit 2 / Invalid command or option instead of an action. One test, one failure. |
| `node --test test/auto-update.test.mjs test/opencode-auto-update.test.mjs` before lifecycle repair | 63/63 passed; isolated public-command fakes plus real filesystem, runner and process lifecycle. |
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
| A4 | Exact upgrade/add order, failed upgrade suppresses add, provenance change during upgrade suppresses add, concurrent run skipped, process-group timeout, signals during/between commands | Public Codex lacks atomic compare-and-update; checks protect the observed checkpoints. |
| A5 | Idempotent enable, bootstrap failure/retry, disable/fenced unload failure, launchd exit overriding old success, stale/old live-PID lock failure, concurrent first enable | launchctl itself is a test boundary; real login persistence remains a host check. |
| A6 | Managed symlink/hardlink, foreign plist/job, missing-state registration, forged profile, unsafe ancestor cases preserve targets | No authentication guarantee against a hostile writer with the same UID. |
| A7 | Real launchd and three-host lifecycle passed before the lifecycle repair | Current candidate host checks are tracked separately; original local activation and the published npm entry remain post-publication checks. |
| A8 | Parser defaults/host validation plus simultaneous independent Codex/OpenCode jobs; disabling OpenCode preserves Codex registration | Synthetic launchctl boundary. |
| A9 | Real adapter doctor rejects absent, source-copy, override and drift fixtures before scheduling | Synthetic host executable; real filesystem and manifests. |
| A10 | Fresh downloaded skill content and version pass through fetched CLI; older version retained; wrong identity and symlinked package refused | npm download is faked; registry transport/integrity is a release check. |
| A11 | Config/personal plugin/compatibility files preserved; fetch, removal, drift and disable before update leave assets intact; invalid post-doctor fails; signal cleanup during/between commands and forced unknown finality | Cancellation wrapper uses real subprocesses; adapter rollback retains existing package-suite coverage. |
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

Test Phase 1: A1-A6 and A8-A12 pass within the focused suite's stated boundaries,
including R1-R4 in plan.md. Current full-package and actual scheduler/host checks
remain pending. The design, test, producer and client binding set is in
bindings.json. The current CLI adds `uncertainLock` to status details and returns
exit 5 with inspection guidance for an old lock instead of healthy overlap.
True recent overlap still skips safely, and listeners are restored on success,
failure and early return.

Design verdict: accepted for the narrow CLI state, output and recovery contract;
verdict owner: design author under the deterministic narrow-visible exception;
next state: complete for that surface. Each criterion uses a deterministic
oracle, with no aesthetic or product-direction judgment. Publication, registry
verification and activation of the original local installations remain separate
operational acceptance checks under A7/A12. This record does not claim those
post-publication outcomes or field reliability. The lifecycle repair uses the
same deterministic design criteria; fresh independent review and release
verification remain pending.

The first broad package run passed 417 of 419 tests. An inherited self-update
opt-out invalidated one test; a mutation subprocess exited abnormally during
parallel execution. Both passed in the clean, bounded-concurrency full rerun.
Its exact command was `npm run build && node scripts/test-build-modes.mjs &&
node --test --test-concurrency=2 test/*.test.mjs`; no test was filtered out.

## Ownership and recovery limits

The saved runner is intentionally retained across re-enable and npm upgrades;
this patch does not introduce a runner migration protocol. An abrupt crash can
leave a run.lock or manage.lock. Locks at least 15 minutes old, or dated at least
15 minutes into the future, fail closed even if the recorded PID is alive. A
younger reused PID can count as overlap until that limit; the clock and file
timestamp determine it. Inspect the PID and job, then remove only the lock after
confirming no updater owns it. Ordinary command failure, timeout and handled
SIGINT/SIGTERM release owned locks, including between commands. Disabling retains
the runner/state/log and fences future update steps before asking launchd to unload.

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
