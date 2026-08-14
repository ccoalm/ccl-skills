# Delivery Lifecycle

Use this reference when a request needs end-to-end product R&D coordination rather than only code edits.

## Stage Routing

| Stage | Owns | Output |
| --- | --- | --- |
| Product shaping | Product workflow | User workflow, acceptance checks, constraints, non-goals |
| Design readiness | Design skill | Interaction model, UI states, design-system fit, accessibility/visual acceptance |
| Architecture | Architecture skill | Boundaries, contracts, data ownership, reliability/security decisions |
| Implementation | Development skill | Code changes, generated artifacts, migrations, tests |
| Review | Review/debug workflow | Findings by severity, fix decisions, residual risks |
| Release | Release/runtime workflow | Verification evidence, rollout, rollback, observability |
| Learning | Skill maintenance | Durable updates to the smallest relevant skill/reference |

## Stage-Entry State Checklist

Walk this at each stage boundary BEFORE crossing into the next stage. Each row names only the required state plus the rule that owns its criteria — it never restates the criteria; open the pointer for the actual bar. A row that genuinely does not apply is marked `N/A + reason`, never silently skipped. This is a firing-point enumeration of the stage-transition gates, not a master table: it duplicates no gate content and is not exhaustive of every rule in this file — it lists only the state that must exist to CROSS each stage boundary, and each pointer opens the owning section for the full gate.

**A row is satisfied only by the owning gate's actual OUTPUT — the decision/evidence/artifact that gate produces — never by a pointer to the gate or a bare claim that it "was considered".** The pointer tells you which gate to run and where its criteria live; it does not itself discharge the row. If the gate produces no output yet, the row is unmet — open the pointer and run the gate now. A row naming an owner gate is discharged only by actually consulting that gate in-session and recording its disposition; a self-written `none` / `N/A` label produced without opening the gate is self-attestation, not the gate's output, and does not discharge the row.

- Do not cross a stage boundary while any of that boundary's rows is unmet or unverified — this is a blocking walk, not a reference list.

- **Exit Product shaping → enter Design readiness / Architecture**
  - [ ] Product-shaping answers exist → [Product Shaping Checklist](#product-shaping-checklist)
  - [ ] Product-requirement routing disposition exists → [`../SKILL.md#scope`](../SKILL.md#scope)
- **Design readiness → enter Architecture / Implementation**
  - [ ] Design-readiness disposition exists → [`design-routing-and-readiness.md`](design-routing-and-readiness.md)
- **Architecture Gate → enter Implementation** (also the entry-time firing point for the states below)
  - [ ] Architecture-gate decision + any required contract definition exists → [Architecture Gate](#architecture-gate)
  - [ ] High-risk resilience product/architecture disposition exists → [`high-risk-resilience-gates.md`](high-risk-resilience-gates.md) (risk identification → `feature-risk-router`)
  - [ ] Implementation entry / re-entry preconditions met → [`implementation-entry-reentry-gate.md`](implementation-entry-reentry-gate.md)
  - [ ] Proportionate plan-authoring output exists → [Plan Authoring](#plan-authoring)
  - [ ] Implementation-entry invariant state set → [Implementation Gate](#implementation-gate)
  - [ ] Acceptance/concept closure inputs set → [`implementation-completeness-and-minimality.md`](implementation-completeness-and-minimality.md)
- **Implementation → before Review**
  - [ ] Final-diff completeness/minimality closure state met → [Implementation Gate](#implementation-gate), [`implementation-completeness-and-minimality.md`](implementation-completeness-and-minimality.md)
- **Review Gate → before merge/release**
  - [ ] Review-gate disposition exists → [Review Gate](#review-gate); checklist [`code-review-checklist.md`](code-review-checklist.md); incoming feedback via [`review-reception.md`](review-reception.md)
- **Completion Evidence Gate → before any done/fixed/passing claim**
  - [ ] Completion-evidence state exists → [Completion Evidence Gate](#completion-evidence-gate)
- **High-risk slice → before starting the next slice**
  - [ ] High-risk-slice checkpoint run → [Completion Evidence Gate](#completion-evidence-gate)
- **Release Gate → before release**
  - [ ] Release-gate precondition state exists → [Release Gate](#release-gate)
- **Finalization → after a delivery slice lands or reaches pending-MR handoff, before the final response / next-slice decision**
  - [ ] Pre-Final Continuation Gate walked → [`pre-final-continuation-gate.md`](pre-final-continuation-gate.md)

## Product Shaping Checklist

- Do not start implementation until there is an approved design or acceptance shape proportional to the task.
- Who is the user or caller?
- What workflow or job changes?
- What is the externally visible behavior?
- What are the non-goals?
- What data, permission, latency, reliability, and compliance constraints matter?
- What must be true for acceptance?
- What can be released incrementally?

For user-facing surfaces, use `design-routing-and-readiness.md` before architecture or implementation when interaction, IA, UI states, visual system, accessibility, or design-system fit is not already clear.

Objective closure belongs to shaping, not only to closeout: before acceptance points are frozen, name the objective's population basis (one static instance vs many members or repeated arrivals) and the outcome classes it implies — positive, negative, corrected/recovered, and ambiguous-or-superficially-successful. A per-operation sample/batch/time/resource bound schedules work and must not be recorded as a narrower total objective. The recorded verdicts, their authority rules, and the no-starvation evidence live in [`implementation-completeness-and-minimality.md`](implementation-completeness-and-minimality.md#objective-closure).

Acceptance-coverage matrix detail: enumerate each functional point plus the risk points it touches (negative / authorization / data-isolation / partial-failure / idempotency, and similar — not limited to these), and map every point to an *observable pass/fail* acceptance check (never a restatement of the feature name), flagging the non-goal boundary where a point's scope is ambiguous. The risk points drive coverage, not grading: how and at which layer to test a point is `testing-strategy`'s scenario/risk matrix downstream, and risk tagging / gate selection stays with `feature-risk-router`.

## Architecture Gate

Run an architecture pass before implementation when any of these change:

- service boundary, ownership, or runtime topology.
- API/RPC/protobuf contract, public route, callback, or event contract.
- source-of-truth storage, migration, indexing, or retention.
- auth, permission, audit, sensitive data, or external integration boundary.
- async workflow, idempotency, retry, lock, queue, or scheduled job behavior.
- release runtime, canary, rollback, observability, or operational ownership.

For Go backend work, use `go-microservice-architecture` for this gate. For Python backend, AI-service host, worker, SDK/package, or batch-job architecture, use `python-service-architecture`.

Architecture evidence should name the runtime surface that proves the design can operate after launch: generated-contract ownership, dependency timeout/secret/discovery contracts, health/readiness, trace/log context, durable state for long-running work, retry/idempotency policy, and rollback or repair path. Do not accept a plan that only names the happy-path API or screen while leaving async tasks, generated code, or runtime dependencies implicit.

For any API/RPC/event/config or response-envelope change, the architecture gate must produce a contract definition before implementation: exact request and response shape, success/error semantics, transport status versus business code, where business data lives, versioning or compatibility strategy, launch status, known consumers, and the minimum test matrix. If the shape is not defined, do not let client or server implementation infer it independently.

## Implementation Gate

Use the implementation skill after architecture is stable enough to code. For Go backend work, use `go-microservice-dev`. For Python backend, AI-service host, worker, SDK/package, or batch-job implementation, use `python-service-dev`.

Implementation should preserve:

- local instruction precedence: read the nearest project instruction file such as `AGENTS.md` or `CLAUDE.md`, then parent rules; if child rules merge with or override parent rules, state that precedence explicitly before changing shared boundaries.
- test-first behavior for user-visible or contract-visible changes: write or update the failing test first and verify it fails for the right reason.
- contract-first changes for protobuf/OpenAPI/Pydantic/API/DDL/config.
- clean transport/application/domain/infrastructure layering.
- deterministic code generation and generated-file ownership.
- focused tests for the changed behavior.
- explicit infra-dependent tests when DB, Redis, MQ, or external services are required.

## Plan Authoring

- Plans should use exact file paths, commands, acceptance checks, and verification expectations.
- Break implementation into bite-sized tasks that produce reviewable, testable progress.
- Avoid placeholders such as TBD, TODO, "add appropriate validation", or "handle edge cases" without concrete cases.
- Check that names, types, method signatures, and contract fields are consistent across tasks.
- Naming known work as out of scope — a defect observed in passing, a debt or hardening item, or follow-up work — is visibility, not tracking: a landed plan is an archive, and "recorded so the next agent sees it" has no reader. Each such named item must carry a disposition that outlives the plan — an owner locator resolving to an item-specific durable entry that names the work (a tracker row, issue, status-document entry, an item-specific entry in the owning skill or gate, an existing successor slice that carries it as in-scope work, or, for an item already owned elsewhere, that owner's item-specific locator — never an ownership assertion, and never a bare destination) or a terminal disposition (declined, with the reason). This invariant's closeout instance is the deferred-point rule in `implementation-completeness-and-minimality.md` and its review instance is the accepted-risk/deferred-items row in `code-review-checklist.md`; this bullet is its plan-authoring instance, where the naming happens first.
- If work will be delegated to agents, route through `multi-agent-delegation`.

Scale the plan to risk: a simple low-risk single-file change can use a short inline plan with concise acceptance checks; multi-file, user-visible, cross-skill, bug-fix, release, branch/MR, or unclear-risk work needs an explicit task split with acceptance checks, verification commands, and stop conditions before edits; larger work (multiple modules/skills, high blast-radius, or a durable process sample) additionally records a requirement summary, decision record, test plan, release plan, and known risks.

Multi-step assessment-to-fix-to-test work always needs a reviewed plan, but it upgrades from a lightweight workflow plan to a formal external spec plan only when scale or risk justifies the extra artifact: the work spans multiple modules or skills, needs branch/worktree isolation, will be executed by subagents or delegated workers, is intended as a durable process sample, changes high-risk user/business or high-blast-radius technical outcomes, or has unclear scope that could expand during implementation. If not upgrading, record why a short inline plan is sufficient.

For any multi-step request that combines assessment, fixes, and verification, the task plan must name the branch/worktree boundary, selected findings and the disposition of findings named but not selected, files to touch, design checkpoint if visible behavior changes, test strategy, test-case register, commands to run, rollback/stop conditions, and whether an external planning/TDD/debugging skill will supplement the CCL workflow.

## Review Gate

Review should lead with findings, not summaries. Classify issues by impact:

- Critical: security, data integrity, broken contract, irreversible migration, release blocker.
- Major: likely production bug, missing transaction/idempotency, broken permission, missing important test.
- Minor: maintainability, small performance risk, incomplete edge case.
- Info: optional cleanup.

Do not approve critical issues without either a fix or an explicit product/engineering decision to defer with risk accepted.

For independent AI reviews, require usable output before treating the review as evidence. If a broad review returns no output, appears continuation-like, or omits the requested finding structure, narrow the prompt to the diff, files, or risk class and rerun. Do not treat silence as approval. For long-running CLI reviews, poll before interrupting; around 30 seconds with no output is a wait-and-observe point, while around 60 seconds with no output is a stuck-review signal unless the process then returns concrete findings.

For a concrete review checklist, use `code-review-checklist.md`.
For incoming review feedback, use `review-reception.md`.

## Completion Evidence Gate

- After a high-risk slice, run a checkpoint before starting the next slice. Treat schema or migration, protobuf/OpenAPI/Pydantic or external contracts, platform runtime, auth or permission, cross-service behavior, KMS/secrets, observability, deployment, and other high-blast-radius architecture as high risk.
- The checkpoint definition of done should stay short: review the diff, resolve blocking findings, update the nearest repo docs or harness when boundaries changed, rerun the relevant local gate, and commit before stacking another high-risk slice.
- Do not make skill or memory updates mandatory for every slice. Update skills only when a reusable pattern has repeated enough to be durable; update memory only when explicitly asked or when the fact cannot be derived from repo docs.
- Do not claim work is complete, fixed, passing, or ready without fresh verification evidence.
- Identify the command or inspection that proves the claim, run it, read the output, and report the actual result.
- A passing linter does not prove the build, test suite, migration, or user workflow passes.
- Agent or subagent success reports are not evidence until their diff and verification output are checked.

- Deep self-audit rule: never claim complete, fixed, or passing without fresh verification evidence from the current turn. Before that claim — and before handing the change to any third-party/independent review — run the deep self-audit as a **walked enumeration over the properties this delivery asserts**, not as a re-read: list every property the delivery states in prose (design doc, code comment, commit message, MR body, test name), and for each one name the killing mutation that would make it fail, per the `testing-strategy` assert-the-outcome rule. External review is the backstop for what the audit missed, never the substitute that makes it optional. (The executable/unverified discipline, the re-owe rule for review-fix code and outgoing claims, and the `interim` consequence for late commits are stated once in the execution-bounds paragraph below.)

Deep self-audit execution bounds: apply it where it is executable; a mutation you only imagined is a hypothesis, not evidence — bound the killing mutation's blast radius — never disable an authorization, idempotency, or deletion guard and then exercise it against a shared or live dependency, where buying a RED can destroy real data or perform a real unauthorized action. Mutate against isolated dependencies or at the lowest layer that avoids them, and if neither is possible record the property `unverified`. For a property with no executable test — a design-doc claim, an MR-body assertion — name the concrete observation that would contradict it and where that observation lives, then go look — and where no executable check or contradicting observation exists, record the property `unverified` rather than counting it audited. Prove the check itself can fail before believing it: a lookup aimed at the wrong path, matched case-sensitively, scoped too narrowly, or swallowing a non-zero exit returns a confident clean that is indistinguishable from a true one, and it fails toward letting the claim through. Re-reading prose only confirms the prose is self-consistent; it cannot detect prose that disagrees with the code, so it never discharges this. The candidate is whatever exists right now: code produced while fixing review findings re-owes the enumeration, and so does the completion message or MR body you are about to emit. A completion message or MR body that introduces a claim absent from the diff ("all variants supported", "no regressions") is a new asserted property, even though no file changed; walk any new claim in it before sending, or do not write it — a delivery whose last commit landed after the final audit is `interim`, and reporting it as complete is a false completion claim regardless of how many external review rounds preceded it.

Mechanical-gate degradation ladder: prefer a tracked verify script plus blocking CI / branch protection over an untracked local hook; any hook must call only tracked, non-destructive commands and is never the sole evidence; treat the prose norm as the fallback, not the primary control. When no CI / shared runner exists, the mechanical control degrades to a tracked verify script plus an *installed* pre-commit/pre-push hook — committed `hooks/` dir + a setup step that sets `core.hooksPath`, since that config is per-clone and must be installed, not just committed (see `agents-file-coverage-gate` for the worked bootstrap) — with the tracked script as the source of truth.

## Release Gate

Before release, confirm:

- codegen, migrations, config, and deploy metadata are complete.
- health/readiness, logs, metrics, traces, and alerts cover the changed path.
- rollback or mitigation is defined.
- data backfill, replay, or compatibility windows are planned when needed.
- user-facing or integration-facing acceptance checks have evidence.
- long-running jobs, uploads, imports, exports, downloads, AI generation, or other async work expose visible status, terminal success/failure, timeout behavior, retry or repair behavior, and persisted result or artifact pointers where relevant.
- frontend shells, mobile app surfaces, and operational web workspaces have explicit handling for permission, empty, loading, partial, retryable error, unrecoverable error, cancellation, stale data, version/update notice, and responsive/keyboard or collapsed-sidebar behavior where relevant.

## Automated Workflow Evidence

- Automated verification should observe the system, not only exercise it. For UI flows, check visible state, console errors, network failures, and backend logs or traces at critical steps.
- For backend-only flows, check response contract, trace/log id, persisted state, emitted events, dependency outcomes, and metrics/log signals where relevant.
- Do not accept "automation passed" when the test only clicked through a path and ignored hidden errors.

## Branching Strategy

**Default：short-lived branch + trunk-based 倾向**。原则：

- **Branch 寿命 < 1-2 天**（本团队启发；trunk-based 倡 daily integration）：超过要么拆 PR，要么开 feature flag 把未完功能合主干（隐藏在 flag 后）— 长寿 branch 会 merge conflict + 阻塞他人 + 测试集成态飘
- **PR 越小越好**：本团队 sweet spot / split 阈值见 `code-review-checklist.md` Review Invocation 段（本地操作阈值，非外部固定规则）
- **Trunk-based** 适用：CI 强、测试覆盖好、小团队 / 高频 release；本团队默认走这条
- **GitFlow / 长寿 release branch / stabilization branch** 仅在 release / version management 需求**真大于** trunk-based CI/CD 收益时考虑：典型场景 — 并行维护多 prod 版本（SDK / 产品 LTS）、scheduled release cycle 含稳定化窗口、prod hotfix channel 与 next-version dev 并行、合规要求 release 隔离审计、外部交付物有版本承诺
- Feature branch 形态保留作为"开发期协作隔离"工具但**不用作功能可见性 gate** — 那是 feature flag 的事

## Delivery Health Metrics（DORA software delivery metrics）

评估 engineering delivery health 时用 DORA 系列 metrics（起源于 Forsgren / Humble / Kim *Accelerate* 2018，**模型随年度 State of DevOps Report 演进**）作可量化共同词汇。当前 DORA 模型为 5 metric：

| Metric | 定义 | 备注 |
|---|---|---|
| **Deployment Frequency** | 多久 deploy 一次 prod | — |
| **Change Lead Time** | commit 到 prod 的时长 | — |
| **Change Failure Rate (CFR)** | release 中需要 hotfix / rollback / fail forward 的比例 | — |
| **Failed Deployment Recovery Time** | failed deployment 恢复时长 | 2023 年 DORA 重命名（原 MTTR）|
| **Deployment Rework Rate** | release 后需要 rework 的比例 | 2024 年新增 |

Elite / High / Medium / Low 具体阈值**按当年 DORA Annual State of DevOps Report 取**（不同年份数字略有变化，本 ref 不固定数字以免过时）。

操作约束：
- 提"加 CI step / 简化 release / 改 branching" 等建议**至少关联一个 delivery metric 或邻近 engineering outcome**（on-call 负担 / DX / 可靠性 / 安全 / 认知负载），并显式声明 tradeoff
- 反对例：单纯说"我们的 CI 太慢" 不是 trigger；"lead time 当前 N 天目标 < 1 天，CI build 占 N% — 优化 build 缓存" 才是
- 不把 metrics 当 KPI 凑（Goodhart's law）— 当观察轴，不当强制目标
- Incident retro / 5-Why / blameless post-mortem 走 `problem-resolution-and-learning.md`（该文件覆盖 production symptoms / 5-Why / evidence capture / learning routing）
- Keep live dependency, browser, or real-data checks separate from fast default tests, but require them for release-critical workflows when mocks cannot prove integration behavior.
