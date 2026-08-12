# Domain Feature Patterns

## Handler Pattern

- Keep handlers thin: bind request, validate shape and limits, resolve auth/resource scope context, call application logic, and map response/error.
- Put reusable validation in small check functions instead of burying it in domain orchestration.
- Validate batch size, required IDs, enum values, pagination, and mutually exclusive fields before side effects.
- Use canonical error codes for validation failures; do not leak raw dependency errors in public responses.
- Always return a response envelope even when downstream logic returns an error.
- Avoid mutating inbound generated request objects except for narrowly documented compatibility normalization; prefer converting into application parameters.

## Parameter And Result Mapping

- Convert transport requests into application parameter structs before domain logic.
- Parameter constructors should tolerate nil input only when nil is a valid no-op; otherwise validate at the handler boundary.
- Use pointer fields or explicit presence flags for patch/update semantics where zero and absent differ.
- Keep helper getters such as `GetX()` value-or-zero only after validation has decided whether absence is allowed.
- Result structs should own conversion back to transport response objects when response assembly is non-trivial.
- Add a safe `Meta` or summary method for audit/logging when complex params need observability; include identifiers and option flags, not raw sensitive payloads.

## Domain Model Mapping

- Keep domain objects separate from DB models when they carry behavior, derived flags, runtime-only fields, or compatibility transforms.
- For finite domain values such as market, region, status, scene, source, provider, priority, permission, or channel, define one domain-owned constant/type set and one canonicalization/parse function before using the value across application, persistence, or tests. Transport enums, DB strings, headers, and query params should convert at the boundary; business logic and tests should reuse the domain symbols instead of scattering raw literals such as `"US"`, `"CN"`, `"active"`, or `"default"`.
- When the same finite value crosses service or package boundaries, put the canonical type/constants and parser in the smallest shared domain or platform package already allowed by the repo. Do not let two services invent parallel canonical sets for the same concept. A shared package exempts local debt markers only after it actually contains the canonical type/constants and parser, not merely because the package exists; a CI check, grep panel, or required review checklist MUST verify the package contents before accepting the exemption. If no eligible shared package exists, the shared package lacks the canonical type/parser, or creating one needs architecture approval, keep the local constants for this slice, add a same-line `finite-value-debt: <task-ref> <owner> <deadline> <reason>` comment at every temporary duplicate/raw use outside boundary conversion, and record a consolidation task. A debt marker without task reference, owner, and deadline is non-compliant.
- When a finite value already has a protobuf enum or external enum, do not treat the generated enum as the only domain model unless every non-transport layer can safely depend on it. If storage, headers, or existing domain models remain string-based, add domain constants plus explicit enum/string conversion helpers first, mark direct generated-enum or raw-string use outside transport/storage conversion with `finite-value-debt: <task-ref> <owner> <deadline> <reason>`, and migrate call sites incrementally.
- Architecture owns cross-boundary semantic consistency for finite values: approve the shared package or contract location, approve any transport-coupled exception through a traceable architecture decision, and make sure every `finite-value-debt` marker has an exit owner, deadline, and consolidation task.
- Use explicit `FromModel`, `Model`, or `Populate` methods for conversion; do not rely on reflection-based copying for behavior-rich objects.
- For patch/updater structs, use pointer fields to mean "set this field" and nil to mean "leave unchanged".
- Generate or centralize repetitive getters/mappers when many services need stable map/group/sort keys.
- Do not let storage-only columns leak into public response objects unless the API contract intentionally exposes them.

## Application Logic Pattern

- Application logic orchestrates domain rules and infrastructure calls; it should not parse transport-specific headers, cookies, or query strings directly.
- Convert transport DTOs into domain/application parameters before deep domain logic.
- Group related side effects into phases:
  - validation and read preconditions.
  - durable writes inside a transaction. **Required async side effects (MQ publish, projection update, downstream notify that the workflow depends on) MUST be written to an outbox row in the SAME transaction**, then dispatched by a separate poller/relayer — see `db-schema-and-dal-patterns.md` outbox pattern. Publishing MQ "after the transaction commits" loses messages whenever the process dies between commit and publish.
  - only explicitly **best-effort** side effects (cache warm-up, low-priority counter, optional notification) may happen post-commit; document each one as opt-in best-effort, not the default.
- Mark best-effort side effects explicitly in logs and metrics; failures should not silently disappear. If a side effect's failure would leave the system in an inconsistent state, it is NOT best-effort — promote it to the outbox.
- For external file or HTTP fetches, use bounded clients with context, validate content type/size/status, and close response bodies with `defer`.
- Do not accept caller-provided URLs, file paths, or object keys directly into fetch/read/delete operations without validation and namespace checks.

## Transaction Pattern

- Use a DB transaction only for writes that must commit atomically in the same database.
- Pass transaction-bound repositories into inner calls rather than letting inner code reopen the default write connection.
- Keep network calls, MQ sends, object storage writes, and long CPU work outside the transaction where possible.
- Re-read mutable quantities or counters inside the transaction when correctness depends on latest state.
- Use row locks or compare-and-update when concurrent writers can affect the same record.
- Do not hide post-commit side effects inside transaction callbacks.
- Transaction helpers should rollback on returned error and recovered panic, then return a typed error instead of swallowing the failure.
- Always check begin and commit errors; if rollback fails, log it with safe context without replacing the original operation error unless the rollback failure changes correctness.

## Batch Write Pattern

- Enforce a maximum batch size at the handler or application boundary.
- Split huge imports into chunks and make each chunk idempotent.
- Use upsert with explicit update columns; avoid update-all unless the whole row is intentionally replaceable.
- For per-row status updates, prefer generated update helpers or parameterized expressions. If raw SQL is unavoidable, never construct it from untrusted strings.
- Treat empty input as a no-op only when that is semantically valid; otherwise return a validation error.

## Pagination And Listing

- Normalize page/limit or offset/limit at the boundary.
- Set a maximum limit for public APIs and high-cost internal queries.
- For ordinary UI lists, count plus ordered page is acceptable.
- For backfills, exports, and large reads, prefer cursor/id-window iteration over offset pagination.
- Always specify a deterministic order when paginating.

## Concurrency In Domain Logic

- Use bounded concurrency for fan-out RPC/HTTP calls.
- Combine timeout, retry, and concurrency limit; do not retry unboundedly.
- Preserve result mapping by stable key when concurrent calls return out of order.
- Decide fast-fail versus collect-partial-results deliberately.
- Tests that stress concurrency should be separate from default fast tests when they need real services.
