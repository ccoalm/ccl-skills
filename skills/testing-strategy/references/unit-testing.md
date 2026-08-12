# Unit Testing

Use this when the behavior can be proven without live infrastructure.

## What Belongs Here

- Domain rules and invariants.
- Validation and permission decisions.
- DTO/protobuf/Pydantic/request-response mapping.
- Error wrapping and canonical error mapping.
- Config parsing and defaults.
- Retry/fallback decision logic.
- Cache key, Redis key, idempotency key, and lock value builders.
- State-machine transition rules.
- Small concurrency units with cancellation or bounded workers.

## Frontend Component Tests

- Render behavior for components, hooks, forms, stores, and view-model logic.
- Props/state transitions, validation messages, empty/loading/error states, permission-gated controls, and emitted events.
- Accessibility roles, labels, keyboard behavior, focus transitions, and disabled/aria states when they are part of the component contract.
- Keep browser-only routing, uploads, responsive layout, and cross-page flows in E2E unless a component test can prove the behavior directly.

## Patterns

- Write the test skeleton around the risk being protected: name the scenario, expected behavior, and why it matters.
- Use Arrange/Act/Assert or Given/When/Then structure so setup, behavior, and assertion stay readable.
- Prefer table-driven tests for input/output matrices.
- Test negative paths explicitly: missing fields, malformed input, forbidden scope, duplicate idempotency key, timeout, and canceled context.
- Use small handwritten fakes for dependency behavior.
- Keep fixtures minimal and named by scenario.
- Assert behavior, not logs or private function calls.
- Test request deadlines, cancellation, or context propagation when the stack exposes them.
- For bug fixes and visible behavior changes, make the focused unit or contract test fail before changing implementation when feasible.

## Avoid

- Live DB/Redis/MQ/network in unit tests.
- Broad golden snapshots for unordered data.
- Sleeping to wait for async/concurrent work; use fake clocks, condition polling, task joins, channels, or explicit synchronization.
- Monkey patching when a small interface boundary is practical.
- Large production payload dumps as fixtures.

## Completion Evidence

Report the focused command and outcome, such as changed-package tests, typecheck/compile, or specific unit test names. If unit coverage is intentionally omitted, state why the behavior is only provable at integration/E2E level.
