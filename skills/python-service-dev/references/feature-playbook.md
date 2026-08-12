# Feature Playbook

Use this for concrete Python service implementation.

## Steps

1. Locate the project root and commands.
   - Prefer `pyproject.toml` and lockfiles over guessing.
   - Identify framework app, package root, tests, migrations, and scripts.
2. Define the contract.
   - Pydantic/OpenAPI, Django serializer/form, generated client, or protobuf.
3. Define state changes.
   - ORM model, migration, repository, transaction, cache, queue, or artifact.
4. Implement the use case.
   - Keep route/view thin and put decisions in service/domain code.
5. Add focused tests.
   - Unit for pure logic, API/contract for route behavior, integration only when real dependency behavior matters.
6. Run the repo's quality commands.
   - pytest target, ruff, mypy/pyright, formatting, migrations/codegen checks.

## Common Implementation Slices

- New HTTP endpoint: update schema/OpenAPI or serializer first, add route/view wiring, keep handler thin, pass resolved auth/context into service code, add API/contract tests for success and canonical failures.
- New repository or DB mutation: design model and migration together, keep transaction scope explicit, add rollback/error-path tests, and verify pagination or uniqueness/idempotency behavior when relevant.
- New Redis cache/lock/idempotency path: define key namespace, tenant/resource scope, TTL, miss/error behavior, compare-and-delete unlock, and tests for expiry or duplicate submit.
- New queue or background worker: define payload schema, retry/drop/DLQ policy, idempotency key, concurrency bound, graceful shutdown, metrics, and duplicate-delivery tests before business handler logic.
- New external or inter-service client: define typed request/response, auth/signature headers, timeout, retry policy, error mapping, trace propagation, fake client, and integration marker for live contract checks.
- New generated artifact or report: render from typed inputs, write under a controlled output path, compare parsed structures or stable golden files, and verify generated-file drift in CI when deterministic.

## Public API And Callback Security

- Authenticate before trusting request body, query, path, or header identity fields unless signature verification requires canonical raw body bytes.
- Resolve actor, tenant, resource scope, app/integration source, and permission from authenticated context; client-supplied owner/creator/scope fields are claims, not authority.
- Validate signatures/tokens, timestamp windows, nonce or request id replay protection, payload schema, event type, and resource id before callback side effects. State-changing public APIs and callbacks require replay defense unless the exception is explicitly read-only or already idempotent.
- Cache dynamic auth config briefly and fail closed for unknown app ids, disabled integrations, malformed config, expired timestamps, signature mismatch, or permission lookup errors.
- Add tests for signature canonicalization, timestamp expiry, replay, spoofed owner/tenant/scope fields, duplicate callback delivery, malformed payloads, and unknown event types. Keep provider sandbox/live-callback tests outside the default fast target.

## Do Not

- Add untyped dictionaries at API boundaries when the repo uses schemas.
- Introduce hidden global clients or import-time network I/O.
- Mix live dependency tests into default fast test suites.
- Copy local business terms from source examples into generic implementation rules.
