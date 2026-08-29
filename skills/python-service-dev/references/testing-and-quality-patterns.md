# Testing And Quality Patterns

Use this for pytest, async tests, fixtures, fakes, ruff, mypy/pyright, and CI quality gates.

## Scope

- Use `testing-strategy` when deciding which test layer should own confidence.
- Use this file for Python mechanics after the layer is chosen.

## pytest

- Prefer focused tests for changed modules.
- Use fixtures for app, settings, fake clients, DB sessions, and sample payloads.
- Use markers to separate unit, integration, API, contract, E2E, live-infra, failure-mode, and drill tests.
- Use `pytest-asyncio` for async code according to repo configuration.
- Avoid long sleeps and live credentials in default tests.

## TC Traceability And Deprecation Cascade

- **TC traceability**: link tests via `@pytest.mark.tc("TC-XX-NNN")` marker. Registers at collection time so `@skip` / `@skipif` / fixture failures still map to Bitable status. Needs the `tc` plugin from `test-artifact-management/references/tc_helpers/tc.py` loaded via `addopts = -p tc`. See `test-artifact-management/references/tc-marker-conventions.md`. Before adding tests, `grep -rn 'pytest\.mark\.tc' tests/` plus the sidecar `test/results/tc-map.jsonl` to check for existing coverage — extend rather than duplicate. When a TC is marked 废弃, grep both source and sidecar; follow deprecation cascade in `testing-strategy`. Tests without any TC link: prompt user only when the underlying code is also removed.
- **废弃级联：业务代码是否仍在用** — grep 只找出"测试函数引用了什么 import"是第一步；判断"该 import 是否还有其他 caller"才能定生死。Python 顺序：
  1. 看测试体导入的模块：`grep -E "^(from |import )" tests/test_<x>.py`
  2. 对每个产品模块（非 stdlib / 非测试 helper），找全仓库 caller：`grep -rEn "from <pkg>\.<mod>|import <pkg>\.<mod>" --include='*.py' --exclude-dir=tests`
  3. 零产品 caller → 同 commit 删该模块 + 测试；有产品 caller → 测试目标仍在用，不删测试（若 TC 已废弃但代码活，先确认产品决策）
  4. 边界：动态 import（`importlib.import_module("...")`）grep 抓不到；含 reflection 的代码人工确认；DI/插件注册（`@register` 装饰器）的产品代码需查注册表而非 import
- For scenario tests, use `testing-strategy` to build the scenario matrix first; in Python services, map scenarios to unit tests, API/contract tests, integration tests, workflow tests, or marked E2E/live-infra tests instead of putting every case into a slow end-to-end suite.

## Test Target Split

- Keep the default target fast, deterministic, and runnable without live DB, Redis, MQ, service discovery, cloud credentials, private-network endpoints, or external model servers.
- Put infrastructure-dependent tests behind explicit markers, environment variables, separate pytest targets, or separate CI jobs.
- Mark long-running tests clearly. Replace fixed sleeps with condition waits such as persisted state, emitted event, queue drain, HTTP response, or visible status.
- Generated output tests should compare parsed structures or stable golden files, not require manual inspection.

## Unit And Boundary Tests

- Unit-test validation, domain rules, config parsing, cache-key builders, retry decisions, error mapping, idempotency decisions, and authorization/resource-scope resolution.
- For finite domain values, tests should use the domain `Enum`/`Literal` alias/constants or boundary conversion helper instead of repeating raw strings. Raw strings are acceptable only inside boundary conversion tests that prove specific external wire/storage values map to domain symbols. Those tests must be machine-findable by BOTH a file/test name containing `boundary`, `conversion`, `wire`, or `storage` AND a sentinel comment/docstring `finite-value boundary conversion tests only`; there is no unmarked "dedicated converter file" exception. The sentinel comment is invalid unless the project's lint, grep panel, or required review checklist for import isolation is active and passing for that file; for a repo without that enforcement yet, the same PR must add the checklist/check or link a tracked enforcement task before claiming the sentinel exception. When the repo supports markers, add a `boundary_conversion` pytest marker or equivalent so the boundary-only set is easy to audit. Boundary conversion test files must contain no assertions on business-rule inputs or application state; shared fixtures/helpers are allowed only when they do not assert application state. Any mixed assertion file is non-compliant regardless of sentinel presence. A project lint, grep panel, or required review checklist MUST fail/block when sentinel boundary files import or call application service, repository, or workflow layers. Cover every known wire/storage value plus at least one unknown or invalid value and the converter-level default/empty output, such as returning the domain unknown/default symbol; do not assert downstream application state in these tests. When adding a finite-value boundary module, migrate existing test raw literals for that value in the same pull request or mark each remaining use with `finite-value-debt: <task-ref> <owner> <deadline> <reason>`. Pre-existing scattered raw literals in non-boundary tests are in scope only for the same touched file/module and finite value; flag them with the same debt marker even when the current slice does not introduce a new mapper. A PR containing an in-scope non-compliant `finite-value-debt` marker, or an in-scope unmarked raw literal in a non-boundary test, must not be approved; treat it as a blocking finding equivalent to a missing test. For out-of-scope occurrences found by grep, record the tracking issue instead of expanding the current PR indefinitely.
- Exercise negative paths: missing required fields, malformed config, forbidden actor, tenant/resource-scope mismatch, duplicate idempotency key, dependency timeout, and malformed downstream response.
- For async code, test cancellation, shorter parent deadlines, bounded worker count, duplicate starts, exception recovery, and final state.
- API/contract tests should assert response shape, canonical error code, auth failure behavior, OpenAPI/Pydantic schema behavior, and backwards-compatible defaults.

## Fakes And Integration Boundaries

- Prefer small fakes or protocol-backed test doubles for external HTTP/RPC clients, object storage, repositories, queues, inference clients, and notification providers.
- Fake clients should cover success, transport error, timeout, non-OK domain status, malformed response, slow response with cancellation, and duplicate delivery where relevant.
- DB tests should cover transaction commit/rollback, migration shape, pagination, uniqueness/idempotency constraints, and query-safety expectations when the repo has hooks or review tooling.
- Redis tests should cover TTL, cache miss vs infrastructure error, lock acquire failure, compare-and-delete unlock, lease expiry, and idempotency states.
- Queue/worker tests should cover duplicate delivery, retry/drop/dead-letter behavior, ordering assumptions, worker concurrency, graceful shutdown, and replay visibility.

## Real-Flow Evidence

- Real dependency, E2E, and live-infra tests stay outside the default fast target, but they become release-blocking evidence for high-risk paths where fakes hide credential, runtime, network, callback, data-shape, queue/DB semantics, or deployment behavior.
- A real-flow test should assert the user or caller outcome plus the durable backend result: response envelope, canonical error code, trace/log id, persisted state, emitted event, callback receipt, or generated artifact.
- If a required real-flow gate is unavailable, record the remediation attempted, residual risk, and next unblock action. If a real-flow test fails, route through `defect-diagnosis`; do not replace it with a mock-only assertion unless the original scenario is invalid.
- Keep screenshots, payload samples, log snippets, or trace ids as evidence pointers; the test still needs deterministic assertions.

## Codegen And Migration Checks

- When Pydantic/OpenAPI/protobuf clients, Alembic migrations, templates, or deployment manifests change, run the repo's generation/check command and verify generated output is either clean or intentionally reviewed.
- Migration tests or review evidence should cover upgrade path, downgrade/rollback expectation when supported, data backfill order, and compatibility with old readers/writers when the change is contract-visible.

## Quality Tools

- Run ruff for lint/import/style when configured.
- Run mypy or pyright when configured.
- Keep generated or vendored code excluded according to repo policy.
- Use coverage gates when the repo already enforces them or the change is high risk.
- **`ruff` (Astral) is the current default-recommendation single tool for lint + format + import sort** — per Astral docs, replaces Flake8 (and dozens of plugins), Black, isort, pydocstyle, pyupgrade, autoflake with one Rust binary; ~900 lint rules (vs Pylint ~409, with ~209 rule overlap); ~tens to hundreds of times faster than the tools it replaces (e.g., the FAQ cites 250k-LOC codebase 2.5min on Pylint vs 0.4s on Ruff). Auto-fix for most violations. Use ruff for new projects by default; existing projects can migrate piecewise (linter and formatter are independent — adopt one without the other). **Pylint coverage gap to audit before retiring it**: ruff does NOT replicate Pylint's deeper semantic / data-flow analysis (Pylint's inference engine can catch e.g. argument-count mismatches across complex call chains, unreachable-after-mutation patterns, type-confusion in dynamically typed code that doesn't reach the type checker), Pylint's broader dead-code detection (beyond ruff's import-level checks — unused-method, unused-attribute, unused-private-member with project-aware reasoning), design smells (cyclomatic-complexity bands, too-many-arguments / too-many-locals / too-many-branches thresholds), duplicate-code detection (`similarities` checker), and any custom in-project Pylint plugin or rule. Strategy: ruff + a type checker (mypy / pyright / ty) replaces Pylint for ~80% of teams; teams relying on the specific Pylint capabilities above should keep Pylint as a slower secondary gate or migrate the equivalents (e.g., use `radon` for complexity, `vulture` for dead-code, a type-checker-level config for design smells) before retiring.
- **`ty` (Astral, Beta announced 2025-12-16 per Astral's own announcement) is the current state of Rust-based type-checker work** — per the Astral announcement, on full check "consistently between 10x and 60x faster than mypy and Pyright" depending on workload, with editor incremental recompute on the order of ~80x faster than Pyright on a touched load-bearing file in benchmark workloads. Read these as Astral-published numbers on Astral-chosen benchmarks; actual speedup on a given codebase varies. Notable features: first-class intersection types, advanced narrowing, reachability analysis. Status: **Beta, not GA** (re-verified 2026-08: still beta; Astral projects a stable release within 2026, with the beta→stable gap focused on stability, typing-spec completeness, and first-class Pydantic/Django support) — appropriate for piloting on a separate CI job alongside the existing mypy / pyright / basedpyright gate, NOT for replacing the production type-check gate on its own yet. **Dual-gate operational cost to size before adopting**: running ty plus mypy/pyright produces a "triage tax" — divergent type narrowing (one tool reports, the other doesn't), different stub-package assumptions (typeshed version skew), duplicated CI latency, and a "fix one, break the other" churn pattern that slows MRs. Make the pilot a non-blocking informational job and budget time for periodic finding-diff review rather than treating both as equal blocking gates. Watch for ty GA before flipping defaults. basedpyright remains a viable strict-mypy-like alternative if Pyright's strictness gaps matter and ty isn't ready.
