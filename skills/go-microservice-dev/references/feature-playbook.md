# Feature Playbook

## Before Business Feature Work

1. Inspect the existing platform layer before adding business code.
2. Reuse existing cross-cutting primitives for runtime wiring, config, secrets, dependency clients, lifecycle, readiness, observability, request metadata, response envelopes, and canonical errors.
3. Do not promote by category name alone. Promote a capability to platform only when it has at least two real reuse points, stable behavior across those features, and can remain domain-agnostic without importing domain/application/interfaces types.
4. Keep concrete external adapters in infra unless the repository already defines a platform-level dependency lifecycle primitive for them.
5. Keep product-specific workflow, policy, schema, query, feature-specific readiness, business error classification, and side-effect orchestration outside platform.

## New HTTP Endpoint

1. Add or update protobuf/API contract.
2. Regenerate HTTP router/handler stubs if the stack uses codegen.
3. Implement handler validation and auth/context extraction.
4. Call application/service layer; do not put domain workflow directly in handler.
5. Map domain errors to stable API errors.
6. Add handler/service tests and update Swagger/OpenAPI if used.

## New RPC Method

1. Add protobuf request/response and service method.
2. Regenerate RPC code.
3. Implement generated interface in handler/server package.
4. Put domain workflow in service/logic layer.
5. Add client wrapper if other services will call it.
6. Add compatibility tests for default/empty fields and error cases.

## New DB Table Or Column

1. Write migration/DDL first.
2. Generate or update model/query/update helpers if codegen exists.
3. Add DAL methods using context and read/write connection conventions.
4. Keep batch sizes bounded.
5. Use transactions for multi-table writes.
6. Add tests for query conditions, empty inputs, duplicate/upsert behavior, and transaction rollback.

## New Redis Cache / Lock / Limiter

1. Define key format and scope.
2. Define TTL and stale-data behavior.
3. For caches, decide cache-aside read-through behavior and invalidation path.
4. For locks, use unique values and compare-and-delete unlock.
5. For rate limiters, define scope, window, limit, and transaction/retry behavior.
6. Add tests around key generation and miss/error behavior.

## New MQ Consumer

1. Define event schema and producer ownership.
2. Define topic, group, tag/filter, ordering, retry count, and worker count.
3. Implement handler idempotency before side effects.
4. Distinguish invalid messages that should be skipped from transient failures that should retry.
5. Add metrics for consumed, skipped, retried, failed, and lag if available.
6. Start consumer through service lifecycle, not package init.

## New External Client

1. Wrap generated or third-party client behind a small adapter.
2. Centralize timeout, retry, discovery, auth, tracing, and logging.
3. Convert external errors into service/domain errors.
4. Add tests with fake adapter or mock client.
