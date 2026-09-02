# Problem Resolution And Learning

Use this when a bug, failed test, flaky behavior, production symptom, review finding, or repeated confusion appears.

Prefer the dedicated skills for active work:

- Use `defect-diagnosis` for reproduction, isolation, instrumentation, fixing, regression verification, 5Why, and prevention design. Use `skill-extraction-workflow` to generalize and land durable skill/reference updates.

## Non-Negotiable Rules

- Do not skip the problem because another path appears to work.
- Do not delete, comment out, or weaken a failing test just to make the suite pass.
- Do not treat a workaround as the fix unless the original issue is explicitly deprioritized by an owner and residual risk is recorded.
- Do not start broad refactoring while the root cause is unknown; first isolate and fix the defect, then refactor if useful.

## Seven-Step Debug Flow

1. Reproduce: record exact steps, inputs, environment, logs, and whether it reproduces consistently.
2. Isolate: narrow the failing layer, change, dependency, or condition. Use minimal reproduction or bisect when useful.
3. Hypothesize: state concrete, testable causes and what evidence would prove each one.
4. Instrument: add targeted logs, assertions, traces, metrics, or local probes. Avoid noisy logging that hides signal.
5. Verify cause: prove or reject each hypothesis. If wrong, return to hypothesis rather than guessing.
6. Fix minimally: address the root cause first. Keep unrelated cleanup separate.
7. Regression test: add or update a test that fails before the fix and passes after it when feasible.

## Five-Why Root Cause

Use five-why analysis after the immediate failure is understood:

- Why did the observable failure happen?
- Why did the code/process allow that condition?
- Why did tests/review/monitoring miss it?
- Why was the assumption or contract unclear?
- What reusable rule, guard, or skill update prevents repetition?

Stop when the answer points to a durable prevention mechanism, not when it only names the broken line of code.

## Evidence To Capture

- user-visible symptom or failing command.
- reproduction steps and inputs.
- relevant logs, traces, screenshots, payloads, or database/cache state.
- root cause and rejected hypotheses.
- fix summary and verification command/result.
- regression test or reason it is not feasible.
- follow-up skill/reference update, if the lesson is reusable.

## Learning Routing

Update the smallest correct durable place:

- Product workflow issue: update `product-rd-workflow`.
- Go backend architecture issue: update `go-microservice-architecture`.
- Go backend implementation, testing, codegen, DB, Redis, MQ, or protobuf issue: update `go-microservice-dev` references.
- Python backend, AI-service host, worker, SDK/package, or batch-job architecture issue: update `python-service-architecture`.
- Python implementation, pytest, packaging, schema, ORM/migration, Redis, queue, async, or service-wiring issue: update `python-service-dev` references.
- Node.js implementation, runtime/module/type path, package-manager or lockfile, async lifecycle, stream, worker, outbound-client, or `node:test`/runner issue: update `nodejs-service-dev` references.
- Node.js architecture or service-boundary issue: there is no Node architecture sibling skill by decision — update this workflow's architecture gate text or the relevant `platform-*` owner, and record which one absorbed it rather than filing it under a sibling stack's architecture skill.
- UI/product interaction issue: update the relevant design or frontend skill.
- One-off business/domain issue: do not turn it into a generic skill rule.

For extraction mechanics, source triage, conflict resolution, business-leakage cleanup, pressure-scenario validation, or landing discipline, use `skill-extraction-workflow`.

When in doubt, write a concise new rule only if it would change future behavior on another product.
