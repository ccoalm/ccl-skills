# Quality And Testing Patterns

Use this when adding tests, fixing brittle tests, setting CI targets, validating codegen, or building traffic replay/regression checks.

## Test Target Split

- Keep the default test target fast, deterministic, and runnable without live DB, Redis, MQ, service discovery, cloud credentials, or network-only dependencies.
- Put infrastructure-dependent tests behind an explicit target, tag, environment variable, or separate package path.
- Mark long-running tests clearly. Do not leave unbounded sleeps, watch loops, or manual inspection tests in the default path.
- Generated output tests should compare structured objects or golden files, not rely on developers manually opening emitted files.
- If a test writes files, write under a temp directory and clean up through `t.Cleanup`.

## Unit Tests

- Prefer table-driven tests for validation, domain rules, key builders, config parsing, route matching, retry decisions, and error mapping.
- Unit tests should assert behavior, not log output. Use `t.Fatalf` or assertions for required outcomes.
- For finite domain values, tests should use the domain constant/type names or boundary conversion helpers instead of repeating raw literals. Raw literals are acceptable only inside boundary conversion tests that prove specific external wire/storage values map to domain symbols. Those tests must be machine-findable by BOTH a file/test name containing `boundary`, `conversion`, `wire`, or `storage` AND a sentinel comment `finite-value boundary conversion tests only`; there is no unmarked "dedicated converter file" exception. The sentinel comment is invalid unless the project's lint, grep panel, or required review checklist for import isolation is active and passing for that file; for a repo without that enforcement yet, the same PR must add the checklist/check or link a tracked enforcement task before claiming the sentinel exception. Boundary conversion test files must contain no assertions on business-rule inputs or application state; shared setup/helpers are allowed only when they do not assert application state. Any mixed assertion file is non-compliant regardless of sentinel presence. A project lint, grep panel, or required review checklist MUST fail/block when sentinel boundary files import or call application service, repository, or workflow layers. Cover every known wire/storage value plus at least one unknown or invalid value and the converter-level default/empty output, such as returning the domain unknown/default symbol; do not assert downstream application state in these tests. When adding a finite-value boundary module, migrate existing test raw literals for that value in the same pull request or mark each remaining use with `finite-value-debt: <task-ref> <owner> <deadline> <reason>`. Pre-existing scattered raw literals in non-boundary tests are in scope only for the same touched file/module and finite value; flag them with the same debt marker even when the current slice does not introduce a new mapper. A PR containing an in-scope non-compliant `finite-value-debt` marker, or an in-scope unmarked raw literal in a non-boundary test, must not be approved; treat it as a blocking finding equivalent to a missing test. For out-of-scope occurrences found by grep, record the tracking issue instead of expanding the current PR indefinitely.
- Exercise negative paths: missing required fields, malformed config, forbidden auth subject, resource-scope mismatch, duplicate idempotency key, and dependency timeout.
- For context-sensitive code, test shorter parent deadlines and canceled contexts.
- For concurrency code, test cancellation, duplicate starts, bounded worker count, panic recovery, and final state.

## Fakes And Mocks

- Put external RPC/HTTP, object storage, notification, and repository boundaries behind interfaces when behavior needs testing without infrastructure.
- Prefer small handwritten fakes for domain tests. Use monkey patching only for hard legacy boundaries or when refactoring the boundary is out of scope.
- Fake clients should support:
  - success.
  - transport error.
  - timeout.
  - non-OK domain status.
  - malformed response.
  - slow response with context cancellation.
- Keep fake data minimal and named by domain scenario, not by copied production identifiers.

## Component And Integration Tests

- DB wrapper tests should cover read/write routing, transactions, rollback on error, panic recovery, upsert columns, pagination, and sharding/table routing if used.
- Redis tests should cover TTL, cache miss vs infrastructure error, lock acquire failure, compare-and-delete unlock, lease expiry, and idempotency states.
- MQ tests should cover selector/filter expression, duplicate delivery, retry/skip/dead-letter behavior, ordering assumptions, and worker concurrency.
- Dynamic config tests should cover get/set/delete, cache TTL, list pagination, malformed JSON, listener callback, and listener close.
- Release-platform tests should cover manifest rendering, route patch preservation, canary report classification, approval task idempotency, and callback validation.

## End-To-End And Real-Flow Evidence

- End-to-end tests should assert the critical user or caller outcome, not only that a button was clicked or a handler returned 200.
- Prefer structured snapshots or stable selectors for UI automation, then re-read state after every action that should change the page or workflow.
- Use isolated browser/session contexts for different users or roles; save/load authenticated state only when the test is not about login itself.
- Wait for explicit conditions such as visible text, URL transition, network idle, emitted event, or persisted state instead of fixed sleeps.
- For UI-backed workflows, collect browser-visible state plus console errors, failed network requests, and backend logs for each critical step.
- For API/backend workflows, collect response envelope, canonical error code, trace/log id, dependency call result, and persisted state or emitted event when relevant.
- Real dependency tests should be explicit and isolated from the default fast target; use them for critical paths where mocks hide contract, credential, data-shape, or runtime integration failures.
- For scenario tests, use `testing-strategy` to build the scenario matrix first; in Go services, map scenarios to table-driven unit tests, handler/service tests, protobuf/HTTP contract tests, DB/Redis/MQ integration tests, replay checks, or opt-in real-flow tests based on the risk.
- If a real-flow test fails, route through `defect-diagnosis`; do not replace it with a thinner mock-only assertion unless the original scenario is invalid.
- Keep screenshots, payload samples, log snippets, or trace ids only as evidence pointers; tests should still assert deterministic conditions.

## Traffic Replay And Regression Checks

- Treat traffic replay as a regression tool, not a substitute for unit tests.
- A replay task should record batch id, config, status, start/end time, total count, processed count, success/failure count, and result summary.
- Bound replay concurrency with a semaphore or worker pool.
- Replay must support filters, mock rules, timeout, rate limit, environment tags, and variable mapping.
- Diff results should include original response, replay response, field path, diff type, similarity, ignored fields, and representative samples.
- Reports should include success rate, diff rate, average latency, original latency, performance change, sample diffs, and error summary.
- Cancellation and cleanup must be explicit and should not delete results for a running task.

## Codegen And Template Tests

- Test manifest/template generation from typed inputs.
- Validate required deployment/config inputs before rendering.
- Compare generated YAML/JSON through parsers when possible; avoid brittle raw string snapshots for unordered fields.
- For protobuf or API generation, add compile checks and contract tests for default values, enum unknowns, error envelope, and HTTP path mapping.
- For DI generation, compile the service and run a smoke constructor test after provider changes.
- Generated-file churn should trigger inspection of generator version, input files, and command arguments.

## CI Quality Gates

- Minimum useful gates for backend changes:
  - formatting.
  - static checks or lint if available.
  - compile for changed modules.
  - focused fast tests.
  - `go test -race` on the fast target for any goroutine-spawning service (goleak on key packages optional) — baseline hygiene, not an advanced gate.
  - codegen clean check when IDL, DDL, routes, or DI providers changed.
- Add integration gates only where the environment is reliable; otherwise keep them opt-in and document how to run them.
- CI should fail on generated output drift when generation is deterministic.
- Do not require external secrets for ordinary pull-request tests.
- Audit precision gates and baseline hygiene together. Failure shape: a repo builds elaborate custom gates (attestation, drift checks) while its CI never runs `-race` — the missing piece is usually the boring baseline, not another bespoke gate.

## Testing Time And Concurrency

- **`testing/synctest` (Go stdlib, stable since Go 1.25) is the default-recommendation for testing time-sensitive or concurrent code** — replaces hand-rolled fake clocks (`github.com/benbjohnson/clock` and similar) and the "sprinkle `time.Sleep(50*time.Millisecond)` and hope" pattern. Per Go blog, `synctest.Test(t, func(t *testing.T) { ... })` runs the test in an isolated "bubble" where time is virtualized: `time.Sleep`, `time.NewTimer`, `time.AfterFunc`, `context.WithTimeout` advance instantaneously when all goroutines in the bubble are blocked. Use for: retry-backoff verification, timeout handling, periodic loop pacing, expiry / lease / TTL behavior, multi-goroutine choreography. Do NOT use for tests that genuinely need wall-clock interaction (real DB query latency, real network call cancellation timing — those stay in integration tests). For services on Go 1.24 or older, `synctest` is available behind `GOEXPERIMENT=synctest` in Go 1.24 only; do not depend on it cross-version without a build tag.
