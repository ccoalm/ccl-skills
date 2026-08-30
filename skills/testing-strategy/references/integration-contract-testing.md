# Integration And Contract Testing

Use this when real boundaries matter and mocks would hide risk.

## Agreement — Conformance, Compatibility, Interop — With An External Contract Needs Real Samples

(also pinned-to, implements, supports, matches: the spellings live in the heading
itself so a reader or router scanning headings reaches this rule whichever word the
claim used)

Fires on any claim that the implementation AGREES WITH a contract it does not own —
pinned to, conforms to, compatible with, implements, supports, matches, interoperates
with — over a peer service's schema, a published wire/file format, or a vendor API
envelope. The trigger is the agreement claim itself, not the word chosen for it;
rephrasing "pinned to v2" as "compatible with v2" changes nothing about what was
or was not exercised. Fixtures hand-built by reading the contract document prove only that the
code matches *your reading* of the document, so the claim stays unverified until at
least one **real sample produced by that external side** has been exercised against
the implementation.

- This is a different gap from the two neighbouring ones. The vendored-artifact
  drift gate (`vendored-contract-drift-checklist.md`) compares a checked-in copy
  against its manifest — both sides are yours. Mock-vs-runtime coverage is about
  your own layers. Here the *producer's actual output* was simply never executed,
  so a producer that violates its own published contract stays invisible no matter
  how carefully the schema was read.
- One real artifact — a captured response, a recorded frame, an exported file, a
  replayed request — is **necessary but not sufficient**. It moves the claim from
  "matches my reading of the document" to "matches the producer on the shapes I
  exercised", and no further. A happy-path body says nothing about error
  envelopes, absent optional fields, or the arms of a discriminated union, so
  **the verified claim is scoped to the exercised shapes**. Claiming agreement
  across the whole contract requires a representative sample per variant AND per
  ROLE, DIRECTION, and OPERATION the claim covers — shapes alone are not the axis.
  Replaying a peer capture of every documented variant through your DECODER says
  nothing about whether your ENCODER emits anything that peer will accept; a
  request-side claim is not evidence for the response side, and a read operation
  is not evidence for a write. Enumerate the cells the claim covers and mark each
  `exercised` or `unexercised` rather than letting one sample stand for the set —
  a whole-contract claim needs one per cell it covers.
- **Inbound and outbound cells take different evidence.** An inbound cell is
  exercised by replaying a real producer artifact through your consumer, and for
  that direction captured samples replayed offline are enough — this is still not a
  request for a live-integration suite. An OUTBOUND cell is not exercised that way:
  no peer-produced capture can vouch for bytes YOU emit, and neither can decoding
  your own output with your own decoder. It is exercised only when something the
  other side owns accepts what you emitted — their validator, their published
  conformance suite, a schema validator they publish, or a recorded acceptance from
  their endpoint. Absent that the outbound cell stays `unexercised`, however many
  inbound samples were replayed. **Obtaining that acceptance must not itself be the
  damage**: never fire a write, delete, or otherwise state-changing operation at a
  live peer merely to mark a cell `exercised`. Use their sandbox, their conformance
  suite, or an offline validator they publish; where only a live endpoint exists,
  restrict it to non-mutating operations, or obtain explicit authorization for the
  specific mutating call and record it. An `unexercised` cell is cheaper than a real
  deletion bought for evidence.
- When no real sample is obtainable, record `real-sample: unavailable` with the
  remediation attempted, and scope the claim to "matches the documented contract" —
  never "matches the peer". Scoping the claim is a downgrade, not a waiver.
- A real producer sample is untrusted payload, not just test data: it can carry
  credentials, tokens, personal data, customer records, licensed content, or a
  hostile payload aimed at whatever parses it. **Acquiring it, exercising it, and
  committing it are three separate decisions, and the first two are not free.**
  The isolation starts at the CAPTURE, not at the later inspection: taking an
  authorized but sensitive response through an instrumented shell, proxy, SDK, or
  terminal writes it into telemetry, request logs, scrollback, and temp files
  before any screening can run, and no later care undoes that — capture on the same
  isolated path you will inspect on.
  Authorization comes BEFORE the capture is taken, not merely before it is used:
  obtaining a proprietary or personal-data payload is already the disclosure event,
  and asking afterwards cannot undo it. Then the screen runs on the raw bytes
  BEFORE application code loads them —
  merely running a parser over an unscreened capture copies it into logs, traces,
  crash dumps, and temp files, which is disclosure whether or not a fixture is
  ever committed. The isolation covers **exercising it too, not only eyeballing
  it**: a capture that passes a secrets screen can still be a payload aimed at
  whatever parses it, and the default place people replay samples is a developer
  machine holding live credentials and open network access. Run both the raw
  inspection and the first exercise on a path with no egress, no telemetry, and no
  ambient credentials. **An uneventful isolated replay is not evidence that the
  capture is safe** — a conditional payload can stay dormant precisely because the
  credentials, network, telemetry sink, or filesystem state it looks for were
  absent, so treating one quiet run as clearance re-exposes exactly what the
  isolation protected. The raw capture therefore never graduates to the normal
  test path: what graduates is the redacted, minimized fixture derived from it.
  Nor may the raw bytes simply LIVE in the isolated path — authorization to take a
  capture is often one-time or purpose-limited, so indefinite retention can exceed
  the permission that was granted even though nothing ever reached the normal path.
  Destroy them once the fixture is derived, or bound the retention explicitly to
  what the authorization allows and record when it expires.
- Committing it is then a further, separate decision, taken only after (a) the
  data owner permits that use, and (b) a secret / personal-data / proprietary-content
  screen has run over the exact bytes, with structure-preserving redaction applied —
  replace values, keep shapes, so the fixture still proves the contract. When a safe
  committable form cannot be produced, keep the run ephemeral and retain only the
  sanitized evidence (the assertion outcome, a redacted excerpt, a schema digest);
  the conformance claim still counts as verified. Never resolve this by committing
  the raw capture "temporarily" — history is not a scratch space.

## API And Contract Tests

- Verify generated clients/servers compile after IDL changes.
- Assert HTTP/RPC route mapping, status/error envelope, enum unknown handling, default values, validation errors, and backward-compatible fields.
- For shipped or externally consumed contracts, default contract tests must prove backward compatibility: old clients can read new responses, new servers still accept old valid requests, and removed/renamed fields are not required until the approved compatibility window ends.
- If a breaking change is explicitly approved, tests must prove both sides of the decision: old compatibility paths fail or are absent in the intended way, and the risk-assessment migration/cutover path is covered by contract, integration, replay, or E2E evidence. Do not treat "grep found no old field" as sufficient proof.
- For public APIs and callbacks, test signature/auth, idempotency, replay prevention, and malformed payloads.
- The in-process layer usually cannot express "unset": many stacks make "unset" and "explicit zero/empty" the same in-memory value (a zero-valued enum, a default-initialized struct field, an omit-empty encoder), so an in-process assertion silently reads the defaulted value and passes either way — which is why the entry rule assigns absence assertions to the wire/rendered layer. This is a distinct obligation from the per-surface field-visibility policy below: that policy decides which fields are forbidden on which surface; this one decides where absence can be proven at all.
- Field-visibility / redaction assertions must be **per surface (per response shape), not one global forbidden-field set**: the same field can be legitimately public in one surface and forbidden in another (e.g. an identifier returned correctly in an identity / session / capability response but which must be absent from a public comment / report surface). A single global sweep produces both false negatives (a field forbidden on surface A slips through because it's allow-listed for surface B) and false positives (it blocks a field that is legitimately public somewhere). Assert the allowed/forbidden set per consumer-visible shape; keep only the *truly-never-public* fields (raw secrets, internal idempotency keys, cross-actor ids) in the global set, and enforce the context-dependent ones case by case. Redaction also needs a secret-leak negative test: inject a realistic-shaped (synthetic) secret into the error paths — dependency error body, exception message, wrapped error chain — and assert it appears in no returned error string or log line; asserting only happy-path response shapes misses the leak channel. Where absence can be proven at all (in-process vs wire layer) is the separate obligation in the bullet above.
- For protobuf, add compile checks and compatibility tests when field numbers, enum values, or HTTP annotations change. For OpenAPI/Pydantic contracts, add schema, validation, generated-client, and backward-compatibility checks when request/response models change.
- For cross-service and event contracts, test compatibility against consumer or registry expectations: added optional fields, removed/renamed fields, enum/version changes, and old-consumer-reads-new-payload behavior.
- Keep contract tests assertion-based. Benchmarks, smoke calls, or generated-code compilation alone do not prove runtime compatibility.
- For IDL portfolios with a dedicated breaking-change gate (`buf breaking`, `kitex check`, equivalent), include the gate command in CI as a separate stage from generation; failure of the gate fails the build. Pre-commit format/syntax checks do not satisfy this gate.
- For cross-RPC typed error envelopes, test a roundtrip: server raises a typed error, the wire-format payload is captured, the client reconstructs a typed error of the same class with the same code/message. Include the unknown-shape path: a wire payload that does not match the canonical envelope returns a transport/unknown error without silent loss of the original cause.
- For Code-range allocation, test that a service trying to register a code outside its allocated range fails at build/test time, not at runtime.

### Cross-Repo Field Change — End-to-End Checklist

Adding, renaming, or retyping a field that crosses a repo/service boundary is one end-to-end contract change, not N independent edits. Before calling it covered, walk all five steps (each is a distinct failure site with its own evidence):

1. **Producer fallback** — the producer emits a safe default/absent form for consumers that have not upgraded; asserted, not assumed.
2. **Every transport mapper preserves the field explicitly** — do not assume an object spread/copy crosses a mapper or DTO boundary; each mapper in the chain gets an assertion that the field survives it.
3. **Consumer coverage spans all active consumer variants** — enumerate them from the delivery record's consumer inventory (`../../product-ui-ux-design/references/delivery-contract.md` consumer_inventory for UI variants); testing one variant of a multi-variant consumer is the classic escape.
4. **One real inbound frame through the mapper, plus one unchanged generic path as control** — the real-frame test proves the new field flows; the untouched-path test proves the change did not perturb everything else (the control catches over-broad mapping edits).
5. **Paired changes are cross-linked and land in a compatibility-safe order** — not by mutually blocking merges (that deadlocks): consumer tolerance for the field's absence/new form lands first, then the producer emission (its fallback from step 1 keeps not-yet-upgraded consumers safe), then cleanup removes the fallback once all consumers are confirmed upgraded. Each stage gates on the previous stage's **deployed** compatibility state, and the MRs cross-reference per `../../product-rd-workflow/references/cross-repo-coordination.md` for visibility.

## Platform Contract / Protobuf / RPC Test Obligations

Platform-service-connectivity owns policy and proof mechanics for protobuf-backed HTTP, response envelopes, RPC/base fields, and boundary exposure. `testing-strategy` owns assertion coverage, verdict shape, and CI placement.

The detailed obligations below were moved from the `testing-strategy` entrypoint without semantic changes; keep the entrypoint as the trigger / owner-boundary / open-gap anchor.

   - Restated from the entrypoint: for API contract changes, first record the contract definition being tested: request shape, response envelope, success/error semantics, compatibility mode, consumers, and rollout assumption. If this is missing, stop and route back to product/architecture before writing broad tests.
   - For new or modified HTTP surfaces whose contract source/wire behavior is in scope, apply `../platform-service-connectivity/references/protobuf-http-contract-signals.md`.
     1. Enter the protobuf wire-format test gate only when the canonical gate says the surface is in scope.
     2. If in scope, record whether protobuf is the contract source only or also the binary wire format before claiming coverage.
     3. If the protobuf/wire-format decision is unrecorded, stop and route to the contract owner instead of reporting partial contract coverage as pass.
     4. Routine JSON/OpenAPI tests use the normal contract-definition record when the canonical reference classifies the surface as out of the protobuf wire-format gate.
     5. Cover the applicable items for the layer and owner under test: route binding, JSON mapping when used, binary protobuf content-type when used, error/envelope mapping, generated-client compatibility, and breaking-change checks.
     6. Backend-only generated-client and breaking-change checks belong in the contract owner's suite when a client/frontend test layer cannot run them. Claim contract coverage only when the linked owner-suite run is confirmed passing against the changed surface and exact contract/generated-artifact version under review. Unexecuted, inaccessible, stale, unverifiable, mismatched, or unpinned owner-suite links are an explicit open coverage gap, not pass.
   - API contract tests must assert the service's contract-recorded response envelope per `../platform-service-connectivity/references/http-response-envelope-contract.md`: for the canonical `code`/`message`/`data` envelope, success cases assert `data` matches the typed business model and error cases assert `code`/`message` semantics; other shipped or non-JSON envelopes assert their own recorded contract.
   - Internal service contract tests must cover shared model compatibility: request/response DTOs, common metadata fields, enum/status values, unknown/default behavior, and explicit mapping between transport DTOs and service-private domain or persistence models.
     1. Always evaluate the boundary-exposure gate independently of the base-field gate. When any trigger fires, report each sub-check below as `pass`, `open gap`, `blocked`, or `not applicable` with evidence; any untested or inconclusive required sub-check keeps the boundary gate open. The prove-it mechanic + executable probe for every sub-check is the single source of truth in `../platform-service-connectivity/references/rpc-framework-recipe.md` (its `Metadata-carried base struct` + `CORS defaults` sections and the `Verification` probes 2a/3a–3d); this skill records the verdict shape only — `pass` requires that reference's evidence for the selected outcome, and missing required evidence is an open coverage gap, not coverage.
        - Trigger classification: the gate must run when any canonical boundary trigger fires — the canonical trigger set is in `../platform-service-connectivity/references/rpc-framework-recipe.md` (`Boundary-exposure classification — canonical trigger set, rerun, and local-relaxation bar`); this skill records the verdict shape only; if that canonical trigger set is unresolvable, treat boundary classification as an open coverage gap.
        - Sub-checks (give each a verdict; the recipe owns how to prove each): **classification freshness** (cite dated deployment/mesh/gateway/policy record-version; planned-only evidence cannot close release coverage); **authenticated-caller proof** (caller-supplied base/headers/`Tags` used for authz/attribution/tag-routing need runtime mTLS or signed-platform identity — internal-network/static-owner evidence does not satisfy it); **ingress identity discard/reset** (discard caller base/header identity, reset/regenerate caller `LogId`, drop/overwrite caller `Tags` unless positive auth + owner allowlist); **tag allowlist** (owner-approved; rejected keys absent downstream; uncited/service-local = open); **egress metadata zeroing**; **remap provenance** (CSPRNG issuance + table-only external→internal resolution, not recomputable); **CSPRNG generator** (unit/component test against the unmocked production generator); **first-egress issuance** (CSPRNG-backed opaque token, never the internal `LogId`/empty/fallback); **mapping mode** (resolve idempotent-vs-per-request first; unknown = open); **one-external-token-per-internal-LogId**; **no-token-reuse-across-distinct-LogIds**; **conflict branch** (regenerate exposes only a distinct token reverse-resolving to the new `LogId`; reject leaks no internal `LogId`/colliding token in headers/metadata/body/client-logs/request-base echo); **waiver expiry** (idempotent-mode reject-without-retry is open unless a platform-owner waiver records behavior/owner/scope/future-deadline AND CI-enforced expiry — committed CI job + committed pre-deadline-pass/post-deadline-fail test path/line + paired green required-pipeline/branch-protection status; missing/stale/advisory/non-blocking = open); **cleanup/tombstone** (expired tokens stay tombstoned, never recycled to another `LogId`); **CORS exposure** (browser/CORS-exposed log-id must be opaque-remapped; raw internal echo ≠ coverage); **header/metadata allowlist** (cite concrete owner allowlist/gateway-policy/owner-suite id); **public `Message` allowlist** (external `Message` cites owner-approved fixed public strings keyed by mapped `Code`; uncited/service-local/non-allowlisted = leak).
     2. **Applicability + re-run.** Run the remap sub-checks (provenance, CSPRNG, first-egress, mapping-mode, token-reuse, conflict, waiver, cleanup/tombstone) ONLY for confirmed or still-unresolved external/gateway/browser-exposed egress; mark them `not applicable` only under a fresh valid internal-only classification (governing deployment/mesh/gateway/policy records unchanged since its dated baseline) or actual evidence of no external egress — planned-only classification keeps them open until first-release re-verification. After any canonical boundary trigger (the recipe's trigger set), rerun the applicable ingress/egress tests; an unchanged internal surface needs only a freshness citation against dated baselines (a classification without explicit dated record/version baselines is not citeable — reclassify), and unrelated internal DTO/service-logic changes leave the remap sub-checks `not applicable` unless another trigger creates external/gateway/browser egress. If a changed surface's positive deployment/network/gateway/policy evidence is missing, stale, or contradictory after the lightweight internal path, default to the external-safe ingress/egress tests and keep boundary classification an open coverage gap.
     3. The carrier is scenario-driven (recipe Carrier decision): apply the ordered in-message base-field gate in `../platform-service-connectivity/references/rpc-framework-recipe.md` **only when the in-message `base` carrier is used** (a platform that standardized it, or a contract that declares/publishes `base`) — as the single source of truth for protobuf-backed shared-IDL method-message triggers, owner-artifact evidence, diff-only deferral, descriptor proof, JSON-wire disposition, and non-shared-IDL onboarding. For a metadata-carrier contract (recipe item 5, first-class — no "exception note" required for a new/non-standardized/not-binary-published gRPC service; a base-standardized or already-published/base-carrying contract instead keeps the owner-exception or item-6 migration evidence), do NOT apply the field-number gate — assert the R7 owner-recorded header-set propagation covering the full `base.Request`/`base.Response` metadata set instead. This testing skill records the required verdict shape only: pass requires the recipe's evidence for the selected outcome; `coverage deferred to owner suite` requires the recipe's enforced owner-action conditions; missing required evidence is an open coverage gap, not coverage.
     4. Handler, adapter, route/view, or DTO changes that manually create generated request/response DTOs, or write/mutate/overwrite `base`, `LogId`, caller, `From`, `To`, `Tags`, or equivalent identity fields on generated DTOs, must execute an assertion at or after the middleware fill point proving the outbound or inbound DTO from the touched path has platform base context populated through the contract-source channel recorded for that surface and does not propagate caller-supplied identity without positive authenticated-caller evidence. A bare middleware-binding citation is not coverage for a manual or mutating path that bypasses or changes the fill point. If the touched manual construction hands the DTO to the normal middleware-filled path, prove the post-fill path with an integration/component assertion at the middleware fill point or outbound RPC send point for that specific touched call site, using request-scoped correlation only to select the concrete outbound RPC under test and reading the contract-source channel: in-message `base` for binary-protobuf method messages, or mirrored metadata/header base channel only when the surface contract makes metadata/header the source. A business-field marker may label the scenario but is not sufficient proof of base population. A freshly constructed DTO, local identity overwrite, or a generic surface run alone is not enough. If middleware owns population and the touched code does not manually construct or mutate the DTO/base identity, test or cite the middleware binding instead of expecting app code to touch `base`. Missing touched-path post-fill population evidence is an open coverage gap.
     5. Metadata-carrier and WKT/empty/streaming shapes (recipe item 5). For a new / non-standardized / not-binary-published gRPC contract choosing the metadata carrier — including well-known-type, empty, and streaming messages — no owner "exception note" is required: assert the actual message shape from the generated descriptor or owner-suite and assert R7 owner-recorded header-set propagation tests covering the full `base.Request`/`base.Response` metadata set. A metadata-only carve-out ON a base-standardized platform, or off an already-published/base-carrying contract, is a true exception/migration and must additionally cite a concrete shared IDL owner exception note (repo/path, document URL, generated-artifact provenance field, or owner-suite id) or item-6 migration evidence. Non-inventory messages follow the owner record; unverifiable shape, or (where required) missing exception/migration evidence, is an open coverage gap.
     6. Do not let a service-local regenerated artifact self-certify a renamed, retyped, or renumbered `base` field. During a platform-owner-recorded collision migration on the owner-pinned base field number, the interim reserved/no-base state must cite the owner record, deadline, and verification gate; an unrecorded or unbounded interim is a failing gate, not a benign gap.
     7. A ccl-internal protobuf-backed RPC surface not generated from the platform shared IDL must be reported as an explicit open coverage gap until it is onboarded or has a platform owner record; external/vendor gRPC dependencies follow external-contract tests and must cite the dependency/owner record.
     8. When the service repo cannot verify the upstream pin directly, link the owner-suite run or generated-artifact provenance that verifies the exact shared IDL/generated-artifact version and exact method request/response message types under review; an unexecuted, stale, mismatched, inaccessible, or message-incomplete owner-suite link is an open coverage gap.
     9. For Kitex/Thrift/metadata-only variants, assert the platform-pinned base struct, field id, or metadata key against the platform owner record or linked owner-suite for that transport instead of applying protobuf field-number checks; a local-only field id or metadata key is not coverage. Also assert propagation of log/request id, caller/callee, tags, time, and result code/message where applicable.

## Architecture And Boundary Tests

- Use architecture tests for dependency direction, forbidden imports, package layering, module ownership, schema drift, and generated-code clean checks.
- Keep these checks fast enough for the default gate when possible.
- Treat architecture tests as guardrails; still add behavior tests for user/caller outcomes.
- For services that use double-layer middleware composition (framework default + business level), include a chain-order test that asserts the effective order of the merged stack. Hidden defaults plus invisible business overrides are a common source of ordering bugs.
- For services using DI generation (Wire, dependency-injector, Dishka, etc.), include a smoke test that instantiates the production graph once and asserts no missing-provider error. Layered DI sets (`inject/infra` → `inject/service` → `inject/logic` → top-level) need the smoke test at the composition root.
- For services with dynamic config listeners (etcd `Watch`, config-center `AddListener`), test that the listener recovers from a panic, updates the local cache atomically, and stops cleanly on parent-ctx cancellation. A silently-dead watcher is harder to detect than a missing one.
- For IDL-first HTTP gateways, prove that fresh regeneration of the router tier + untouched stub tier + handler tier still compiles and routes correctly. This catches generator shape changes that would otherwise reach production.
- For recovery middleware on HTTP gateways, assert that a panic produces a stable error code and a sanitized message; the stack trace must appear in the log capture, not in the response body.

## Database Tests

- Cover migrations, ORM models, generated models/DAL where used, transactions, rollback, upsert/update columns, pagination, uniqueness, and sharding/table routing if used.
- Use containers or an explicit integration target when available.
- **Testcontainers (Java / Go / Python / Node / .NET / Rust, per `testcontainers.com`) is the current default-recommendation for spinning up real DB / cache / MQ dependencies in integration tests** — replaces the "mock the database" anti-pattern when SQL semantics, transactions, migrations, or driver behavior matter. Official modules cover Postgres / MySQL / MariaDB / Redis / Kafka / RabbitMQ / Elasticsearch / WireMock and more; each module exposes the canonical connection URL after container start so test code does not assemble JDBC/DSN strings by hand. **Use Testcontainers when**: (a) the test is asserting against real driver / dialect / migration behavior the team historically got wrong with mocks; (b) the test suite already has Docker available in CI (GitHub Actions / GitLab shared runners typically yes; Kubernetes-based self-hosted runners often do NOT have a Docker socket unless explicitly mounted, and corporate-policy CI sometimes forbids privileged Docker — confirm the CI runner type and the Docker access contract before standardizing on Testcontainers, and document the fallback path for runners where Docker is unavailable). **Do NOT use Testcontainers when**: (a) the test is a pure unit test that doesn't touch DB at all (overkill — keep in-memory fake); (b) the dependency is unsupported by Testcontainers and no module exists (manual Docker setup with health-check polling is acceptable, but call it out as bespoke); (c) per-test container startup cost would push the suite over the team's fast-tier budget (use a single shared container across the test session with explicit reset-between-tests). Per-stack implementation lives in `python-service-dev/references/testing-and-quality-patterns.md` / `go-microservice-dev/references/quality-and-testing-patterns.md`; this skill owns the use-or-don't-use decision and the "real container vs mock" choice.
- Seed minimal rows per scenario and clean up deterministically.
- Assert persisted state and transaction boundaries, not only returned values.
- For upsert paths that re-query to recover generated fields, assert both the persisted rows and the in-memory/result mapping. Include a missing-conflict-key or duplicate-key case when the repository promises id repair or idempotency.
- For query performance or index-risk tests, assert a budget, query plan expectation, row count, or deterministic result order. Tests that only insert many rows, log latency, or print results are diagnostic evidence, not release-gating proof.
- Index-risk tests should exercise the real repository predicate shape, not only `SELECT by id`. Cover composite-index left-prefix use, joined-table predicates, soft-delete filters, order/pagination, and any index hint expected by the implementation. Assert the chosen key or acceptable key set when the database target makes that stable; otherwise assert bounded row estimates and deterministic results.
- For leading-wildcard `LIKE`, `OR`, tuple or large `IN`, `DISTINCT` joins, and offset pagination, include representative row counts plus either an explicit query-plan budget or a documented reason the path is diagnostic/offline only. Printing elapsed time from a local live database is not enough.
- For sharding SQL rewriting, cover positive and negative SQL statements: insert/select/update/delete, missing shard key, ambiguous shard key, multi-shard rejection, shard-key update rejection, and explicit bypass/admin paths. A single smoke query does not prove routing safety.
- For async session boundaries, prove that the session is not shared across `asyncio.gather` child tasks: tests should launch concurrent workers from one request and assert each acquires its own session/connection. A regression test for the leak case (one session passed into multiple `gather` children, observing connection-state corruption or detached-instance errors) protects future code.
- For outbox-based dual writes, cover the partial-failure path: business write succeeds + relay outage; outbox row stays pending; relay restart drains the backlog; consumer is idempotent on replay. Test outbox row reaping/archival, oldest-pending-age alarm boundary, and consumer-side duplicate handling.
- For read-replica routing, test that read-after-write within the consistency window routes to primary; that pure reads outside the window may go to replica; that forced-master flag is honored on diagnostics paths; and that a write attempt against a replica session fails at the database boundary rather than silently succeeding against the wrong endpoint.
- For long-running transactions, assert that `statement_timeout` and `idle_in_transaction_session_timeout` kill the offending transaction within the budgeted time; that transaction-duration histogram emission is correct; and that background tasks launched mid-request do not extend the request-scoped transaction.
- For Alembic CI, gate on `alembic upgrade --sql head` running clean against a known starting revision, `alembic check` (or autogenerate-with-check) reporting no drift, and migration replay on both an empty database and a copy of the previous release schema.

## Redis Tests

- Cover TTL, cache miss vs infrastructure error, lock acquire failure, compare-and-delete unlock, lease expiry, counters, rate limits, and idempotency windows.
- Use short TTLs only with deterministic waiting or fake time where possible.
- For Lua, `WATCH`/transaction, pipeline, and script-cache behavior, assert return-code semantics: success, compare failure, missing key, invalid payload, retryable conflict, and Redis unavailable. Logging or smoke calls alone are diagnostic evidence and do not satisfy this obligation.
- For idempotency stores, test first claim, duplicate completed event, already-pending event, expired/stale pending claim, owner mismatch, retry counter behavior, and Redis failure policy.
- For sliding-window rate limits and counters, test boundary timestamps, transaction conflicts/retries, TTL preservation or extension, missing-key semantics, and underflow/positive-only behavior.
- For Redis Streams or lightweight queues, test start id/resume behavior, heartbeat/no-message behavior, TTL/trim/delete cleanup, duplicate/replayed messages, malformed fields, and consumer cancellation.
- For pattern deletes or key scans, test no-match, many-match, prefix isolation, batching if present, and that unrelated scoped keys are not removed.
- For cache stampede defense, cover concurrent miss: N parallel readers see a miss on the same key simultaneously, only one fetch fires against the source of truth, the rest read the populated cache (or wait for the leader). Test single-flight lock failure path, negative cache TTL, and TTL jitter distribution (collect N expirations, assert no lockstep).
- For Redis Cluster (or Cluster-compatible) deployments, include a cross-slot violation test: a Lua script or `MULTI/EXEC` against keys that hash to different slots must raise `CROSSSLOT`. Hash-tag-correct keys must pass. SCAN-based delete must walk all primary nodes, not assume a single keyspace.
- For TLS/IAM Redis, test that connections without TLS or with expired IAM tokens are rejected; that the auth callback refreshes tokens before expiry; that ACL command restrictions are enforced (e.g., the application user cannot run `FLUSHDB`).
- For retry + circuit breaker, test transient-error retry on idempotent reads, no-retry on write commands that could double-apply, circuit-open behavior (fast-fail without hitting Redis), and circuit half-open probe success and failure.

## MQ / Async Tests

- Cover payload decode, duplicate delivery, idempotency, retry/skip/dead-letter behavior, ordering assumptions, worker concurrency, and activation gates.
- Assert emitted messages, state transitions, retry counts, and terminal state behavior.

## Dependency Adapter Tests

- Test real serialization and status mapping for external HTTP/RPC clients with local test servers when possible.
- Cover timeout, non-OK response, malformed response, partial response, and context cancellation.
- Do not require external credentials for ordinary PR tests.

## Stateful-Component Lifecycle And Fault-Injection Tests

For a component that holds mutable state across a lifecycle — a registry / pool / per-object state map, an adapter that installs multiple hooks, or any resource with open→use→close — happy-path single-thread tests miss the exact classes of bug that ship: partial-failure state, cross-request leakage, and use-after-close. Two test families, each pinning an invariant:

- **Fault-injection — force a failure at a specific internal step, assert clean degradation (not just the happy path).** Make step *k* of a multi-step op fail (the k-th hook/listener registration, a mid-init resource, a sink write) and assert the invariant holds: **no partial state** — an all-or-nothing rollback of the handles *you own*, touching no other owner's state; and the host behaves per the classification the component's **contract actually declares** — a genuinely *optional-telemetry* concern fails **open** with a visible degraded signal; a *mandatory control / source-of-record* (auth, enforced policy, or audit/metering that is the system of record) fails **closed**. Don't assume by category: best-effort audit/metering telemetry is optional (fail-open), only enforcement / source-of-record is fail-closed — test the declared policy, not a hardcoded one. Also inject the runtime failure (a per-hook/callback error, an export/sink failure, a mid-stream write error) and assert the host path survives-or-fails-per-classification and the failure is **observable, not silently swallowed**. A positive-only test ("all N registered / happy send works") does not establish the rollback or degraded path — the footguns hide there.
- **Concurrency-lifecycle — exercise the interleavings *in-process*, and test only the invariants the component can actually violate.** Drive the interleavings with **in-process** threads / goroutines / async tasks that share the component's real state, and **engineer the specific race window with explicit interleaving control** — channels / `sync` barriers / `WaitGroup` / a controlled scheduler in Go, a `threading.Barrier`/`Event` or `asyncio` sync point in Python — to force the close-vs-use, double-close, and reinit overlaps deterministically. Detectors and stress are a complement, not the mechanism: `go test -race` *catches* a data race only when your engineered interleaving hits it (Python's GIL masks low-level data races, so logical lifecycle races there need the engineered interleaving even more); `-count=N` repetition, `pytest-randomly` (randomizes test *order*), and `pytest-xdist` worker *processes* (no shared in-process state) do **not** by themselves produce the race window. The **unconditional** set for any closeable component: **close-during-concurrent-use** neither corrupts nor deadlocks (the close path drains with the lock *released*, not held); **use-after-close** is rejected, not served stale; **double-close/dispose** is idempotent. The rest are conditional on the component's shape (a plain open/use/close resource with no per-object map, hooks, or per-request state needs only those three — don't force the rest and manufacture flaky tests): *if it keys state by object identity* — a **reused `id()`/pointer** (after GC or close) does not cross-attribute to a later object; *if it can be re-referenced after close* — a **post-close call does not resurrect state** (object-owned closed flag); *if it installs hooks* — **re-init/reconnect** does not accumulate duplicates; *if it carries per-request state* — **interleaved-request isolation**: two concurrent requests on one reused worker/connection never leak lane / caller / log-id / tenant between them.

Run these against scratch / synthetic targets only (throwaway registry, fixture pool, in-process fake), never live workspaces, real data, or live credentials; a case that cannot be exercised safely is a recorded safe-unavailable gap with its residual risk, not a silent skip.

## Front-End Tests

When a portfolio ships multiple React / web apps sharing a back-end:

- Pick one unit-test runner at the portfolio level (Vitest, Jest, Bun test). Per-app runner choice multiplies CI setup and shared-utility coverage. The runner gates the most-imported utilities first (env-aware config, API client wrapper, error mapping helpers).
- Pick one component test layer (`@testing-library/react` + the unit runner). The per-app top-five risky components — forms with validation, the API-error fallback, the auth/permission gate, the long-running task UI, the global error boundary — are the minimum component-test coverage. Snapshot tests by default add noise without catching real regressions; reserve them for stable token-driven primitives.
- Pick one E2E framework (Playwright is the common choice; Cypress is acceptable). One golden-path scenario per app — login → main screen → primary action → terminal state — gates the most common production-killing regressions. Adding flows after the wiring is cheap; the wiring is expensive.
- The front-end contract test is the consumer side of the back-end contract: assert that the client correctly classifies success / domain error / transport error against the agreed envelope shape; assert that 401 with refresh-eligible signal triggers one silent refresh + retry while 401 without it routes to login; assert that `X-Request-ID` is attached on every outbound request and surfaced from every response.
- PR gate runs install → type check (`tsc --noEmit`) → lint → unit + component → build, in that order, on every PR. Pre-commit alone (husky + lint-staged) is local hygiene, not a gate.
- A portfolio with zero front-end tests across every app is a structural finding; do not patch one app at a time without naming the portfolio-level decision. Coverage floors (e.g., 30% on shared utilities, 50% on API client, golden-path E2E green) ratchet up over time and only ratchet down with explicit approval.
- Visual / accessibility / i18n gates are progressive: when the portfolio adds a token sync pipeline, a Storybook with token-snapshot tests catches sync drift; when the portfolio adopts `eslint-plugin-jsx-a11y`, the rule cap ratchets down per PR; when the portfolio adds a second locale, a single-locale lint flags hard-coded strings.
- **Vitest 2 browser mode (per `vitest.dev/guide/browser/`) is the current component-test default for new React / Vue / Svelte projects** when component-level rendering against a real browser engine is needed (true layout, real CSS, real DOM events, true `getBoundingClientRect`) but the test scope is below "full E2E flow". Vitest does NOT use Playwright as a test runner; it uses Playwright as a browser-provider via `@vitest/browser-playwright` (or `webdriverio` provider for non-Playwright stacks). Specify `test.browser.provider` in `vitest.config.ts`. **Status caveat**: browser mode is still labeled "in early stages" by the Vitest team — pin the version, watch for breaking changes in minor releases, and budget time for occasional flake-debug cycles. **Env-divergence trap**: do NOT run an identical test suite under both jsdom and browser-mode expecting it to count as "double coverage" — many libraries detect environment differently at runtime (date-fns timezone resolution, `Intl.LocaleMatcher`, `crypto.subtle` presence, `IntersectionObserver` semantics, browser-native form validation, fetch implementation), and the same test can pass in one env while failing or running different code paths in the other. Pick one env per test file, label which env each suite proves coverage for, and run env-specific code paths under their corresponding env only. **When to use**: visual-tree-sensitive component tests (`@testing-library/react` jsdom can't catch — CSS positioning bugs, real-event ordering, browser-native form validation, real `IntersectionObserver`). **When to skip**: pure logic/state component tests stay on jsdom (faster, less flake surface); cross-page interaction tests stay on full Playwright E2E. Per-stack Vitest+browser config implementation goes to `web-react-dev/references/web-quality-release.md`.

## Inference Service Tests

When the portfolio includes Python inference services (Triton-wrapped, Ray Serve, FastAPI + model, llama-server) and Go business services calling them:

- **Triton model serving tests**: cover model warmup (first-call latency ≤ N when warmup config is in place vs cold call), per-model batching effective when `dynamic_batching` is declared (assert that requests are actually batched, not just sequentially queued), and version policy (assert that `model_version: -1` returns the expected version under the documented routing).
- **Inference API (FastAPI + Ray Serve) tests**: cover model load on startup (readiness probe returns ready only after model load completes; the choice of startup probe / separate health server / async load flag is the test target, not the assumption that lifespan blocks readiness), per-handler timeout (request exceeding the handler timeout cancels in-flight inference, not hangs), backpressure (assert that `max_ongoing_requests` caps per-replica in-flight count and drives autoscaling but is NOT the rejection threshold; assert that `max_queued_requests` is what triggers 503/back-pressure when the queue exceeds the cap — write the test against both knobs explicitly), and GPU OOM mapping (a forced OOM produces a typed error, not a generic 500).
- **Inference-as-RPC contract tests** (Go business calling Python inference): cover the wire envelope (HTTP 2xx + JSON `{code, message, data}` parsed correctly; HTTP non-2xx mapped to transport error; inference-specific error codes mapped to typed errors); large-payload signed-URL roundtrip (client constructs signed URL, server fetches successfully; assert that the inference response **preserves** any binary output fields the contract declares — do not assert the server stripped inline bytes from the response, that would push tests to break the wire contract; instead assert size limits and redaction live at the logger / persistence layer); trace propagation (W3C `traceparent` injected via OTel propagator survives the hop and the inference service's spans become children of the parent trace; platform `X-Request-ID` / `X-Log-Id` headers also travel and the inference service's logs show them); method-level timeout selection (`min(method, config, ctx-deadline)` returns the expected effective deadline). Add an authentication test: an unauthenticated caller is rejected; a caller with the wrong allowlist scope is rejected. Add a signed-URL trust test: a URL pointing outside the allowed bucket allowlist is rejected before fetch.
- **Multi-stage ML pipeline tests**: cover per-stage idempotency (replaying stage 2 with the same work_item_id does not re-run stage 1), checkpoint resume (stage 3 restart fetches stage 2 output from object storage rather than re-running), per-item partial failure (`return_exceptions=True` style — one ROI failing leaves the rest with results, not the whole batch failing), and fire-and-forget task observability (an `asyncio.create_task()` that fails must surface in metrics, not just disappear).
- **Experiment routing tests**: cover ratio validation with floating-point tolerance (e.g. `abs(sum - 1.0) < epsilon` for normalized weights; do not assert exact `0.999 == fail` — float exact equality is brittle and many routers intentionally support weights plus an implicit default/control bucket), per-request experiment-id and variant recording, shadow inference (candidate output stored but not returned to the user, shadow traffic ratio capped, automatic cut-off triggered when shadow error or latency exceeds threshold), and rollback (deactivating an experiment returns immediately to the prior variant without redeploy).
- **Service-discovery + lifecycle tests** for inference services: register only after readiness, heartbeat failure does not crash the service, SIGTERM deregisters before drain, lane filter prevents canary fallback to production, and stale cached endpoints refresh within the documented interval.

## CI Placement

Integration tests should be explicit: target, tag, environment variable, package suffix, or CI job name. Keep them separate from fast unit tests unless the environment is stable and cheap.

Prefer the repository's documented integration wrapper when one exists. If a local stack is required, record the stack command and health check used before the test command.
