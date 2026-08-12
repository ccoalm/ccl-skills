# R&D Testing Standard Template

Use this template when creating a team testing standard for a product or multi-stack R&D handbook. It is a source-neutral structure: fill it with the target product's real commands, repositories, CI jobs, owners, and evidence links.

## 1. Authority And Scope

- Parent authority: link the product Spec or handbook overview that this testing standard belongs to.
- Covered surfaces: mini-program, React web, mobile app / native clients, Go services, Python services, shared packages, data jobs, CI/harness, and release smoke.
- Out of scope: exploratory-only checks, production-only verification, and stack mechanics owned by child stack standards.
- Required CCL skills: `testing-strategy` for layer and gate design; `test-artifact-management` for structured TC artifacts; stack skills for implementation mechanics; `product-rd-workflow` for product Spec and doc-family ownership.

## 2. Test Deliverables

Every feature or change must produce one of these records before merge:

| Deliverable | Required when | Owner | Evidence |
| --- | --- | --- | --- |
| Test-layer decision table | any behavior, contract, harness, or release-risk change | feature owner | unit / integration-contract / E2E-host / manual rows with command or reason |
| Test-case register | product-visible, contract-visible, bug-fix, high-risk, or workflow change | product + QA + feature owner | scenario, layer, assertion, data, command, expected current result |
| Automated tests | layer can prove the risk deterministically | stack owner | test file path, command, CI job |
| Runtime smoke / manual evidence | host/device/live dependency is required | QA or runtime owner | screenshot, recording, log, run id, blocked reason |
| Regression entry | fixed bug, incident, or confirmed bad case | feature owner | frozen case id and release gate |

## 3. Layer Policy

- Unit tests prove pure logic, validators, mappers, reducers, formatters, local state transitions, and error translation.
- Contract tests prove API, protobuf, gRPC/HTTP envelope, generated client/server compatibility, schema, and adapter behavior.
- Integration tests prove database, Redis, queue, filesystem/object storage, migrations, transactions, serialization, service clients, and permission/data-shape behavior that mocks would hide.
- Component/page tests prove rendered states, local interaction, disabled/retry behavior, and API-client response handling.
- E2E or host smoke proves critical user/caller workflows, host platform capabilities, login/session boundaries, navigation, release readiness, and one important failure path.
- Scenario testing is the planning layer. Each scenario is placed at the cheapest layer that can assert the risk; do not turn every scenario into E2E.

## 4. Harness Engineering

Each repository or service must define a tracked test harness:

- a documented local wrapper, such as `make test`, `scripts/run_tests.sh`, `npm test`, or service-local commands;
- hermetic fast-test environment: fake credentials, temp user state, pinned timezone/locale, deterministic clocks/randomness, and no live external dependency;
- fixture builders and reset hooks for MySQL, Redis, local files, queues, and generated data;
- TC mapping output when structured test cases are used;
- CI parity: the same wrapper or command family runs locally and in CI;
- clear markers for `unit`, `contract`, `integration`, `e2e`, `slow`, `live`, and release-only gates.

## 5. Stack Minimums

### Mini-Program

- Unit tests for page/component state, utility logic, request adapters, and permission/error translation.
- Host-platform smoke for login/session, navigation, storage, sharing, payment or subscription entry when present, upload/download, camera/location/Bluetooth or other host capabilities when used.
- Developer-tool preview or real-device evidence for runtime APIs that lower-layer tests cannot prove.

### React Web

- Unit/component tests for forms, state transitions, permission states, error/empty/loading/success states, and API-client parsing.
- Browser E2E smoke for one critical success path and one important failure or permission path.
- Accessibility, console error, and failed-network inspection when user-facing screens or request plumbing change.

### Go Service

- Unit tests for domain logic, validators, mappers, idempotency keys, permission decisions, and error classification.
- Contract tests for protobuf/gRPC/HTTP envelopes, Kitex/Hertz handlers, generated clients, backward compatibility, and timeout/cancellation semantics.
- Integration tests for MySQL, Redis, transactions, migrations, distributed locks, cache invalidation, message/job retry, and cross-service client behavior using local containers or approved CI infrastructure.
- E2E/API smoke for critical caller workflows and high-risk failure classes.

### Python Service

- Unit tests for domain logic, validators, settings parsing, dependency adapters, idempotency decisions, permission/resource-scope resolution, and error mapping.
- API/contract tests for FastAPI/Flask/Django routes, Pydantic/OpenAPI or protobuf/gRPC contracts, response envelopes, generated clients, compatibility-sensitive fields, and canonical validation failures.
- Integration tests for SQLAlchemy/Django ORM, Alembic or framework migrations, Redis/cache/lock behavior, queues/workers, transactions, async cancellation, and service clients using local containers or approved CI infrastructure.
- Mark live-provider, private-network, real dataset, model-server, or callback-delivery checks outside the default fast gate with owner, timeout, and release decision.

### Mobile App / Native Client

- Fast tests for reducers/view models, validation, API-client parsing, cache/persistence boundaries, permission state mapping, retry decisions, and offline or lifecycle state transitions.
- Widget/component/UI tests for loading, empty, partial, success, error, retry, disabled, permission-denied, optimistic, and account/session states.
- Device/simulator integration for native plugins, deep links, push opens, auth redirects, camera/files/media, background work, local database, and installable build smoke.
- Public or staged rollout gates include mapping/dSYM or symbolication upload, app version/build metadata, crash/performance observability, store/review artifacts, and rollback or staged rollout evidence.

## 6. CI Gates

Use layered gates:

| Gate | Blocks | Typical contents |
| --- | --- | --- |
| Fast PR gate | every merge | format, compile/typecheck, lint/static checks, codegen-clean, focused unit tests |
| Contract/integration gate | contract, storage, cache, service-client, migration changes | protobuf/gRPC/HTTP contracts, MySQL/Redis/container tests, migration dry-run |
| Scenario gate | product-visible and high-risk changes | selected scenario matrix across cheapest sufficient layers |
| E2E/release gate | release, host platform, cross-service, or critical workflow changes | browser/device/API smoke, failure path, runtime evidence |
| Long gate | scheduled or pre-ramp | load, replay, compatibility matrix, visual regression, migration rehearsal |

CI must fail closed for required gates. Optional or live-only gates must name the owner, trigger, timeout, environment, and release decision they inform.

## 7. High-Risk Coverage

High-risk workflows require a compact risk matrix before implementation. Cover all triggered classes:

- duplicate submit, callback, message, or job restart;
- permission service uncertainty and cross-tenant/user/resource mismatch;
- money, quota, billing, inventory, or write-finality side effects;
- partial failure, retry, rollback, timeout, cancellation, and unclear final status;
- AI provider/model failure or degraded answer path;
- missing trace id, support id, audit log, or incident reconstruction evidence.

Happy-path tests alone cannot approve these changes.

## 8. Evidence And Sign-Off

The completion report must include:

| Layer | Command or artifact | Result | Missing layer reason | Residual risk / owner |
| --- | --- | --- | --- | --- |
| Unit |  |  |  |  |
| Contract / integration |  |  |  |  |
| E2E / host smoke |  |  |  |  |
| Manual / exploratory |  |  |  |  |
| Build / static / CI |  |  |  |  |

Do not report "tested" from command output alone. Map important scenarios to written cases or to explicit `blocked`, `live-only`, `product gap`, or `not applicable` rows.

## 9. Sync Rules

- Product Spec owns acceptance scope and scenario priority.
- This testing standard owns layer policy, harness expectations, CI gates, and evidence format.
- Stack standards own the exact test framework, file layout, helper APIs, and command mechanics.
- Repo-local specs or `AGENTS.md` own local boundaries and required wrappers.
- When a feature changes a stable contract, generated surface, workflow, or CI gate, update the owning Spec, stack standard, and repo-local execution artifact in the same slice.
