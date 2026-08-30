# Verification, Diagnostics, and Security

Use this reference when selecting concrete Node.js test mechanics, proving runtime behavior, changing dependencies, or reviewing Node-specific security exposure.

## Test mechanics after strategy is chosen

Preserve the repository's runner. `node:test` is a first-class built-in option, not a mandatory migration target. Choose a new runner only from actual needs such as ecosystem integration, transform support, watch/UI workflow, mocking behavior, coverage maturity, or multi-project support.

| Behavior | Focused proof |
|---|---|
| Handler/domain logic | direct unit test without port/global mutation |
| HTTP/RPC adapter | in-process integration test for status/schema/error mapping |
| Database/queue/cache adapter | real protocol dependency or contract-faithful test double at the adapter boundary |
| Timeout/cancellation | fake/controlled time where sound, plus assertion that underlying work stopped |
| Stream | backpressure, partial failure, disconnect, cleanup, size bound |
| Worker/background job | ownership, retry/idempotency, poison input, shutdown/drain |
| Process lifecycle | child-process test for signal, exit code, readiness/drain deadline |
| Package/module boundary | start/import/require the built or packed artifact on the supported runtime matrix |

Mock the narrow external boundary, not the implementation under test. Reset mocks/timers and avoid cross-test process-global mutation. When concurrency is meaningful, test ordering independence and run the suspected flaky case repeatedly before calling it stable.

Coverage is a gap detector, not the acceptance oracle. Keep an existing threshold; change policy through `testing-strategy`. Node's built-in coverage and threshold flags have version/stability differences, so verify them against every supported runtime before making them a required gate.

## Diagnostic decision table

| Symptom | Start with | Avoid claiming from |
|---|---|---|
| high CPU / latency | reproducer, CPU profile/flame graph, event-loop and queue evidence | one stack sample or code inspection |
| event-loop stall | event-loop delay/utilization plus long-callback attribution | total CPU alone |
| memory growth | heap/GC trend, retained-object comparison, active resources | RSS snapshot alone |
| process will not exit | active handles/resources, owned timers/listeners/workers, lifecycle trace | adding forced `process.exit()` |
| worker-pool starvation | workload class, async-resource duration/concurrency, pool queue symptoms | increasing pool size first |
| flaky async test | repeated isolated run, seed/time/concurrency capture, leaked-resource check | blanket timeout increase |

Bind evidence to the candidate runtime and commit. A diagnostic command that failed, timed out, or could not attach is missing evidence, not a clean result.

## Security review axes

- **Input and complexity:** validate type/shape/range; limit headers, bodies, decompression, records, regex complexity, recursion, and parsing work. An input-dependent long callback is both performance and DoS risk.
- **Injection and paths:** use parameterized database/process APIs, avoid shell construction, normalize and constrain filesystem paths, and define archive/symlink behavior.
- **HTTP boundary:** keep secure parser defaults, schema-validate untrusted network input, set explicit timeouts/limits appropriate to the framework/runtime, and do not expose framework diagnostics or raw errors.
- **Outbound access:** validate destinations and redirects where user input influences network access; apply platform egress controls for service-level guarantees.
- **Secrets and logs:** never log credentials/tokens/raw sensitive payloads; redact at structured logging boundaries and test representative failure paths.
- **Dependencies:** review direct and transitive changes, install scripts, lockfile delta, known advisories, maintainer/package identity, and rollback. `npm audit` or equivalent is one signal, not a pass/fail security proof.
- **Runtime containment:** the Node.js Permission Model can reduce filesystem/network/process/addon/worker capabilities on supported runtimes. Verify flags and framework needs in the deployment environment. It is defense in depth and does not make malicious in-process code trustworthy.
- **Prototype/object hazards:** accept only expected keys, use schema validation, avoid unsafe recursive merge of untrusted objects, and keep framework/runtime patched.

Route threat-model and required-review gate decisions to `feature-risk-router`. Route service-wide identity, authorization, tenant isolation, data ownership, or network-policy architecture through `product-rd-workflow` and the appropriate platform/security owner before implementation.

## Verification transcript

Capture a compact table:

| Check | Command/probe | Result | Candidate/runtime |
|---|---|---|---|
| focused behavior | repository command | pass/fail | SHA + Node line |
| failure/cancellation | test or reproducer | pass/fail | same |
| lint/type/check | repository command | pass/fail | same |
| package/service suite | repository command | pass/fail/skipped | same |
| build/start/package | repository command | pass/fail/skipped | same |
| performance/diagnostic | frozen workload/probe | measured/inconclusive | same |

Do not collapse skipped, unavailable, inconclusive, and passed into one “green” status.
