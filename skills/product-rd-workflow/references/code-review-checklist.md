# Code Review Checklist

Use this for a general product R&D review pass before merge or release. Stack-specific skills may add deeper checks.

## Review Invocation

- Scope independent reviews to the smallest useful diff or file set. Prefer passing the base-branch diff through stdin or an equivalent bounded input over asking for a broad repository review.
- Load local repository rules and conventions, such as `AGENTS.md`, `CLAUDE.md`, harness rules, or project review context, when they exist.
- Exclude generated files, vendored code, dependency directories, large artifacts, and docs from review input unless the change specifically targets those files.
- Treat empty output, timeout, auth failure, or continuation-like output as inconclusive. Record a pending review artifact with scope, attempted command shape, and retry questions; do not call it approved.
- Retry inconclusive reviews with narrower input before abandoning the gate. If a later retry succeeds, update the pending artifact to completed and capture blocking/non-blocking findings.
- If a reviewer gives a small non-blocking cleanup that is within the current low-risk change scope, fix it and rerun the relevant deterministic gates before merge.

**Effectiveness rules**：

*Google Engineering Practices 公开 guidance*（google.github.io/eng-practices）：
- **Small CLs preferred** — Google 原文 "no hard and fast rules" 但给参考："100 lines usually reasonable; 1000 lines usually too large"；reviewer 注意力 / 缺陷检出率随 PR 大小衰减
- **Reviewer first response within 1 business day**（Google 明确上限）；不是 review 完成是首轮 acknowledge + 首批 finding

*本团队本地操作阈值*（非 Google 数字）：
- PR ≤ 400 LoC changed 是 sweet spot；> 800 LoC 强烈拆分
- Reviewer 累积 review queue > 5 个 = 排队信号（默认启发，按团队 size / capacity 配置）
- **Exception 允许大 PR**：generated / mechanical refactor（如 codemod）/ migration / lockfile-vendor 更新 / pre-approved 大设计变更 — 这些 reviewer consent 后可放行

*Specific feedback*：每条 finding 必含 (a) 具体位置（file:line）+ (b) 问题描述 + (c) 建议方向（"see X pattern" / "this could be done as Y"）。空话如 "looks weird" / "改下" / "不够好"不接受 — 作者无法 act。

*Author 响应纪律*：reviewer 留 N 条，作者**逐条 reply**（修了 + commit ref / 不修 + 理由 / 协商需新一轮讨论），不 silently 改完了之 — 见 `review-reception.md`。大 review（50+ findings）允许按主题 batch reply + 明确标 unresolved/blocking 哪些。

## Security

- Inputs are validated server-side for type, length, format, range, and authorization scope.
- Queries and commands do not concatenate untrusted input.
- Protected endpoints authenticate before side effects and authorize resource access; no IDOR-style access.
- **Enforcement lives in the operation that performs the side effect.** For an agent/LLM surface specifically: a tool omitted from the schema, filtered out of the prompt, hidden behind a facade/wrapper, or gated by listener order is *not* denied — a direct or alternate caller still reaches the executor. Trace every denial path to the code that executes it and require the deny to be tested there (`llm-inference-integration/references/agent-tool-dispatch.md` owns exposure-vs-authorization; `testing-strategy` owns the enforcement matrix).
- Secrets, tokens, credentials, and PII are not committed, logged, exposed in errors, or returned in responses.
- Public callbacks, uploads, redirects, outbound fetches, and dependency calls have explicit validation and limits.
- Rate limits, concurrency limits, or cost guards exist for expensive or abuse-prone paths.

## Correctness

- Empty, nil/null, zero, negative, max, duplicate, and malformed inputs are handled deliberately.
- Pagination, loop boundaries, time ranges, and cursor/order semantics are correct.
- Concurrent writes use transaction, compare-and-update, lock, idempotency key, or unique constraint as appropriate.
- Multi-step durable changes are transactional or have compensation/reconciliation.
- Time zones, Unicode/multibyte strings, precision, and currency/decimal values use appropriate types.
- Async errors, dependency errors, and partial failures are not swallowed.

## Performance And Reliability

- No obvious N+1 query, unbounded full-table scan, unbounded fanout, unbounded queue, or indefinite sleep.
- Lists and exports are paginated, streamed, batched, or otherwise bounded.
- Expensive work is cached, queued, or rate-limited where appropriate.
- Timeouts, retries, circuit breakers, and fallback behavior are explicit for dependency calls.
- Resources are closed or cleaned up: files, response bodies, streams, timers, subscriptions, locks, and temp directories.

## Maintainability

- Names reveal intent and exported APIs have stable semantics.
- Modules have clear responsibility and dependency direction.
- Duplicated logic is removed only when shared abstraction is genuinely clearer.
- Generated files are reproducible and not hand-edited.
- Comments explain non-obvious decisions, not obvious statements, and state contracts rather than the authoring session — flag dead design-session citations, PR/stack vantage, change narration, reviewer-addressed justification, and hedges per `tighten-doc/references/session-vantage-leakage.md`.

## Scope Completeness And Concept Delta

- **Review both negative space and concept delta.** Review from the original acceptance source, the acceptance-to-evidence closure table, the concept-to-current-need table, and the final diff; the diff alone cannot show required behavior that is absent.
- For negative space, confirm every in-scope acceptance point maps to an implementation surface and fresh evidence. Reject silent omissions, implementer-created downscoping, and tests derived only from the code that happens to exist.
- For concept delta, require every new abstraction, indirection, module/service, state/entity, dependency, config/flag, generalized path, or extension point to identify its current acceptance point or observed hard constraint and the simpler alternative considered. Reject hypothetical future reuse; allow refactoring and testability work tied to a current observed constraint.
- Grade every stated guarantee at one of four levels — **strong / eventual / best-effort / unsupported** — and reject prose that presents a desired property as an implemented guarantee: "X is guaranteed" in a doc/comment/MR while the code delivers best-effort is a finding, not wording polish.
- A "no impact when disabled / flag off" claim is verified by walking the disable paths, not by trusting the flag: check imports/side-effectful module init, startup/registration hooks, API surface exposure, shared state/schema touched, and UI/entry visibility — any of the five can leak behavior while "disabled".
- Reconcile the active acceptance-source stable ID set against the closeout table and verify every out/deferred row cites a real product/human decision. Accept two-axis `not-applicable` only for a reviewed documentation-only diff. For a pure refactor or mechanical maintenance with no contract/behavior delta, accept functional-axis `not-applicable` only with the concept-delta table still present. The implementer's label alone is never evidence, and diffs touching the behavior-bearing surface classes enumerated in `implementation-completeness-and-minimality.md` (contracts, schemas/migrations, permissions, quotas/pricing, config defaults, user-visible copy — that list is canonical) qualify for no exemption. A rejected classification returns the delivery to the implementer to build the required tables; do not reconstruct them in review.

## Testing And Evidence

- **Model-visible wording is behavior.** For agent/LLM changes, inspect the exact prompts, tool schemas, tool results, and diagnostics the model receives in every affected mode: flag implementation-only concepts (internal plugin/transport/renderer names the model can neither act on nor needs for a valid call), confirm legitimate tool-contract discriminators survived, and require snapshot/replay or eval evidence for the wording change — "just reworded the description" is an unreviewed behavior change (`llm-inference-integration/references/agent-instruction-composition.md`).

- New behavior has focused tests at the right level.
- Contract-visible changes include an explicit test matrix before MR readiness is claimed: unit, API/contract, integration, and browser/device/E2E where relevant, with executed commands and unavailable layers called out as residual risk.
- The MR description is an evidence carrier: record the exact verification commands run and what each proved, precisely enough for a reviewer to reproduce — "tests all pass" is a claim, not evidence. Accepted risks and deferred items get an explicit named section with the accepting owner recorded, never buried in implementation detail; recorded acceptance there is evidence for the reviewer, not merge authorization.
- API/RPC/event/config or response-envelope changes include the contract definition and compatibility decision in the review context. If reviewers must infer success/error semantics, business-code placement, data location, or compatibility policy from implementation diffs, the MR is not ready.
- Boundary, failure, permission, idempotency, and compatibility cases are covered when relevant.
- Generated output, migrations, and contract changes have deterministic checks.
- Live dependency, browser, real-data, replay, or canary evidence is present for release-critical workflows where mocks cannot prove integration behavior.
- Failing tests are fixed or invalidated with evidence; they are not deleted or weakened just to pass.

## Review Output

Lead with findings. For each issue include severity, file/line, impact, and suggested correction. If there are no findings, state residual risk and any verification gaps.

Tag each load-bearing statement in the review by its evidence class — **Observed** (you observed the fact itself — ran the command, exercised the path, or read the code text — and the tag covers only what that observation proves: a runtime/concurrency/authorization property merely inferred from static code is Hypothesis until exercised; reading someone's assertion, including an implementer-authored CI or runtime claim, is Reported), **Reported** (a doc, comment, or another party asserts it), or **Hypothesis** (inferred, unverified) — and attach a suggested verification step to every non-Observed tag. A review whose key claims are all Reported/Hypothesis is a reading summary, not review evidence.
