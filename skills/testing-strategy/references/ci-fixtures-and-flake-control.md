# CI, Fixtures, And Flake Control

## CI Gate Design

Use layered gates:

- Fast PR gate: format, compile/typecheck, lint/static checks, focused unit tests, deterministic codegen clean check.
- Integration gate: DB/Redis/MQ/API/dependency adapter tests with stable local containers or provisioned CI infra.
- Scenario gate: selected acceptance/risk scenarios mapped to unit, contract, integration, component, or E2E commands. Keep it small enough to diagnose failures quickly.
- E2E/release gate: critical browser/API workflows and smoke tests in an isolated environment.
- Optional long gate: replay, load, compatibility matrix, visual regression, or migration dry-run.

Use the same command wrapper locally and in CI when feasible. If CI invokes a wrapper such as `scripts/run_tests.sh`, `scripts/dev.sh test`, `make test`, or service-local package commands, use that wrapper for local verification unless debugging a lower-level runner.

## Frozen Regression Set And Adversarial Passes

Tier the frozen regression set so the gate stays affordable: deterministic frozen cases run in the blocking release gate; cases needing live infra / model calls / real indexes run in the release or pre-ramp gate with an explicit marker, owner, and timeout (do not stuff flaky live cases into the fast gate); human-review-only cases are release evidence, not mislabeled automated tests.

The proactive complement — the adversarial pass over code already considered "done": run it as an active defect-discovery step, deliberately hunting coverage blind spots — error-mapping boundaries, concurrency-protection bypass, double-release/double-close paths — instead of waiting for review or production to surface them. Each confirmed gap lands as a failing test first. Candidate blind-spot classes: the risk-matrix failure classes in `scenario-testing.md`, plus the dependency fault-injection and concurrency/cache cases in `integration-contract-testing.md`.

## Fixtures

Use `test-data-and-determinism.md` as the canonical source for fixture shape, anonymization, data builders, golden-file normalization, and deterministic clocks/randomness/ordering.

## Flake Control

- Replace sleeps with explicit conditions. When an assertion still depends on time, make the ORACLE a state whose existence proves the invariant — the helper process still alive, the record not yet written, the lock still held — rather than "finished within N seconds"; a wall-clock margin only holds while the runner is fast enough, so it turns into a red on a loaded runner and, worse, into a silent pass when the margin is generous. Where a fixture's own lifetime is what the assertion races (a sleeping helper, a TTL, a retention window), push that lifetime far past any plausible run so it stops being a deadline, and keep any wall-clock bound as a coarse backstop only. Sample process state, not just liveness: an unreaped zombie still answers `kill -0`, so "still running" and "already gone" both need the state check, and reap lag on a loaded runner needs a bounded grace period instead of an instantaneous sample.
- Isolate tests by namespace, temp directory, tenant, user, DB schema, or unique id.
- Clean up with test cleanup hooks.
- Avoid shared global state or reset it explicitly.
- Track flaky tests as defects; do not normalize reruns as the fix. Diagnose from the failing run's own evidence before calling the mechanism: a conjoined assertion that prints nothing on failure cannot say WHICH clause failed, so give every multi-clause case a per-clause diagnostic (the retry-green reds otherwise arrive with only the test name, and the mechanism gets guessed from the most memorable clause rather than read).
- A test for a bounded guard (timeout, retry cap, circuit breaker, kill/cleanup path) must pin what the guard BOUNDS, not only what it reports — asserted against that guard's own contract: a cancellation-owning guard (timeout, kill/cleanup) asserts the bounded work actually stopped; a retry cap asserts the attempt count; a breaker asserts open/reject/probe behavior. Do not force a termination assertion onto a guard whose contract does not own cancellation — a breaker may deliberately leave an in-flight call running, and changing runtime behavior to satisfy such a test is a contract regression, not a flake fix. Separately from the contract, bound the TEST itself with a watchdog that is independent of the call under test (run it asynchronously and fail on the watchdog), or a guard that merely waits the stall out and then reports the right code passes — and a suite whose only bound is an elapsed check evaluated after the call returns parks for the fixture's whole lifetime before it can fail. The guard's own protected path also needs a case that enters it: a guard whose first entry crashes stays green forever behind happy-path tests, and its crash surfaces later as a load-dependent flake rather than as the defect it is.

## Flake Quarantine Protocol

- Quarantine only to keep the main gate useful while a defect is actively owned.
- Record owner, reason, reproduction evidence, and expiry date.
- A stale quarantine should fail or alert; quarantine is a deadline, not a permanent lane.
- Reruns/retries are triage aids, not fixes.

## Coverage As Signal

- Use coverage to find untested risk, not as a target to hit.
- High line coverage with weak assertions is not safety.
- For high-risk pure logic, consider mutation testing or equivalent assertion-strength checks.

## Verification Report

When claiming tests pass, report:

- command run;
- scope covered;
- result;
- skipped or unavailable tests — for a suite that PROVES an optional integration works this is gated, not merely reported: assert a minimum-executed count and fail on unexpected skips (`importorskip`/skip-on-missing-dependency turns a broken or unprovisioned environment into a false green that executed nothing), and isolate heavy optional-dependency integration into its own explicitly-provisioned CI lane where a skip is a failure; the same applies to any env-gated live tests (DB DSN, API key): at least one pipeline lane must actually provision the resource and execute them, and "the whole suite skipped" is a failure signal, not green — provision that lane with synthetic/test-scoped resources (dedicated test DB/tenant, sandboxed or quota-capped API keys, short-lived masked secrets in the CI secret store with log redaction), never production or shared-live credentials by default; the lane runs only on protected/trusted refs and trusted runners — fork or otherwise untrusted-MR pipelines must not receive the secrets (they report the live lane as blocked/not-run, which is distinct from a silent skip), since attacker-controlled test code in a secret-bearing lane is an exfiltration path; pointing the lane at live/prod state requires explicit authorization plus read-only or fenced-tenant scoping;
- known residual risk.

Do not report "tests pass" from memory or from a previous turn. Verification must be fresh for the current change.

## Conditional-Skip × Job-Selection Executed-Count Guards

Strongest form — a per-file invariant: the expected-file list derives from the job's own selection manifest, per job/environment (static; never from post-skip collection, which already lacks the silently-skipped file, and never shared across env-split jobs where different files legitimately run), and each expected file collects AND executes > 0 tests, with a missing-optional-dependency skip a hard failure in the job that exists to provide that dependency, never an "expected skip".

Fallback ONLY where per-file reporting is genuinely unavailable after remediation: a minimum-executed floor above the expected total minus the smallest selected file's contribution (e.g. files contributing 46+23 tests: floor 50 > 69−23 catches dropping either file), re-derived whenever selection or parametrization changes (total floors are masked by unrelated test growth; a floor merely above any one file's own count stops protecting once three or more files are selected).
