---
name: test-artifact-management
description: 'Create and maintain structured test cases from requirements or code, including initializing or reusing the Feishu Bitable, canonical fields, import, update, status sync, and deprecation. Use for 写测试用例, 写测试用例文档, test-case documents, TC, source-to-TC generation, 初始化测试用例多维表格, 测试用例放飞书, and 导入/更新/同步/废弃测试用例. Skip executable test code, coverage, CI gates, mocks, and regression verification → testing-strategy; broader feature delivery → product-rd-workflow.'
---

# Test Artifact Management

This skill owns the workflow from **source** (requirements doc or code) to **structured test case design** to **Feishu Bitable delivery**. It routes test layer selection to `testing-strategy` and Bitable operations to `references/bitable-setup.md`.

Bitable ownership:
- This skill owns testcase design **and** testcase-table delivery: initialize or reuse the Base/table, add missing canonical fields, and create, import, update, sync, or deprecate testcase records.
- Use `lark-base` for concrete Base operations and `references/bitable-setup.md` as the canonical schema and safe write path. An existing `.feishu/project.yaml` may provide reusable identifiers, but it is optional and must not trigger creation of unrelated Wiki/Base infrastructure.

## Skill Routing

- Ambiguous "写测试用例" / "write test cases" requests mean `testing-strategy` first when the user wants test code, E2E/browser/device tests, CI coverage, mocks, or verification evidence. Use this skill only when the deliverable is a structured TC artifact, Feishu/Bitable sync, or source-to-TC generation workflow.
- Use `testing-strategy` to decide which test layers (unit / integration / E2E / scenario) are needed *after* the use cases are written.
- Test-code implementation, once test cases are approved, must go to the owning stack skill: `go-microservice-dev` / `python-service-dev` / `nodejs-service-dev` / `web-react-dev` / `miniapp-product-dev` / `app-cross-platform-dev`.
- Use `product-rd-workflow` when the test case work is part of a broader feature delivery plan.
- Use `llm-inference-integration` when test cases cover LLM / agent / RAG / inference behavior.
- Use `skill-extraction-workflow` to feed lessons from test case generation or Feishu Bitable setup back into this skill after each delivery cycle.

## Scope: one config per deployable unit

A **deployable unit** is anything that ships with its own release cadence and
owner: a web frontend, a mini-program, an app, an admin/运营后台 frontend,
one backend service. TC management is scoped per unit — **not per repo**.

| Wrong | Right |
|---|---|
| Monorepo → one `.report-config.json` at root, one giant Bitable | One `<unit>/test/.report-config.json` per unit, one Bitable per unit |
| TC IDs globally unique across all units | TC IDs unique **within one Bitable**; reuse `TC-SY-001` across `web` and `app` is fine because the tables are different |
| One report doc covering everything | One report doc per unit, linked from a project-level README if cross-unit overview is needed |
| Cross-unit "合并报告" | Not provided — each unit reports independently |

Monorepo 下每个 unit 解耦自治：unit 拆分无内置耦合（各自 Bitable/config/helper/report），unit 合并只做一次性数据迁移。布局、per-unit 清单、root Makefile delegates 模式、CI path-filter 与演化规则见 `references/makefile-template.md` Monorepo 节。

## Source Types

Five sources may exist alone or in combination. Use the **fusion rules** below
when more than one is present.

**Industry workflows for deriving TCs from each source** (Specification by Example / Example Mapping for A; Variant matrix / Prototype links for B; Mutation testing / Property-based for C; Schemathesis / Pact / Dredd / Prism for D): see `references/source-to-case-workflows.md` — 10 个派生流程（含公开方法 / 工具和 Figma 映射）+ 何时用 / 何时不用 / 在本 scheme 怎么落 + 例子。

### Source A: Feishu Requirements Doc

```bash
lark-cli docs +fetch "<feishu_url>"
```

Read the output, extract: feature list, acceptance criteria, edge cases,
roles/permissions, error states, data constraints, and UI/interaction states.

**Strength**: captures business intent, stakeholder decisions, and out-of-scope
boundaries that code alone can't reveal.

### Source B: Figma 设计稿

Use the Figma MCP integration (`mcp__claude_ai_Figma__*` tools). Inspect:
frame/component hierarchy, state families (空 / 加载 / 成功 / 失败 / 禁用 / 恢复 / 错误),
interaction paths and transitions, design tokens (color/spacing/typography
roles), psychology cues (disabled reasons, confirmation consequences, retry
safety, return context), and responsive/density variants.

Map to TC fields:

| Figma observable | → 模块 / 功能点 / 字段 |
|---|---|
| 顶级 frame 或 page | 模块 |
| 子 frame / component | 功能点 |
| 一个 state（empty / loading / error / disabled） | 一条独立 TC，状态体现在 前置条件 |
| 交互路径（A→B→C） | 操作步骤（分步） |
| 状态变化 + 文案 + token | 预期结果（含可观察细节） |
| 禁用/确认/恢复 文案 | 预期结果 必须含 psychology 提示原文 |

**Strength**: captures the visible contract — what users actually see and
recover from — which neither requirement doc nor code reliably encode.

### Source C: Repository Code

Read the relevant files (service handlers, router, models, business logic).
Extract: API contracts, data models, business rules, error paths, permission
checks, and state transitions. For large codebases, focus on: entry points,
domain logic, and recently changed files.

**Strength**: ground truth for current behavior; the contract that already ships.

### Source D: API Contract (OpenAPI / proto / gRPC IDL)

For backend services / cross-service integrations, the contract file is often
the most authoritative source — it's what consumers code against. Read the
`.openapi.yaml` / `*.proto` / `*.graphql` file and extract:

| Contract artifact | → TC mapping |
|---|---|
| Each `paths` / RPC method | One 模块 + one or more 功能点 (success, validation, auth, rate limit) |
| Each request schema field with `required: true` | A negative-path TC: missing → 400 / VALIDATION_ERROR |
| Each enum field | One "enum boundary TC" with a value table in the steps; do NOT explode 1 TC per value (a 50-value enum becomes 50 noisy TCs). EXCEPT: known/unknown default value, deprecated values, security-sensitive values (admin/root, sandbox/prod) — each gets its own dedicated TC because their business behavior differs |
| Each response status code (200/4xx/5xx) | A separate 预期结果 (success path + each error envelope) |
| Each `security:` scope / auth method | A permission TC matrix (authenticated / unauthenticated / wrong scope) |
| Rate-limit / quota annotations (`x-rate-limit`, custom extensions) | A `阻塞`-prone TC: rate-limit exceeded → 429 |
| `deprecated: true` paths | A 废弃 TC (functionality permanently retired) |
| Backwards-compatibility constraints (additive only?) | Contract-test layer (testing-strategy will route this to integration/contract tier) |

遇到 versioned paths / discriminator(oneOf·anyOf) / vendor extensions(`x-*`) / gRPC streaming / GraphQL subscriptions·nullability 时，映射规则见 `references/source-to-case-workflows.md` D.5。

**Strength**: machine-readable, version-controlled, language-agnostic. The
only source that doesn't lie about field types or required-ness. Combine with
Source C (code) to spot drift: if proto says `required` but server reads as
optional, that's a TC for missing-field behavior + a 回查 to owning team.

### Source E: Bug Report (regression TC)

When a bug is filed and reproduced (route through `defect-diagnosis` first
for root cause), generate a P0 `[回归]` TC to lock in the fix:

| Bug-report field | → TC mapping |
|---|---|
| Title / summary | 功能点 prefixed with `[回归]` |
| Affected component / surface | 模块 |
| Reproduction steps | 操作步骤 (verbatim, no editorialising) |
| Expected vs actual | 预期结果 = "expected" wording; the "actual" is the bug, captured in 信息流转 |
| Environment / version | 前置条件 (note: include the exact version where the bug was first reproduced) |
| Severity → P0 always | 优先级 = P0 (regression of any severity must not silently re-ship) |
| Linked commit / MR that fixed it | 信息流转: `[<author> <date>] 修复见 <MR url>` |

无法稳定复现的 race/heisenbug 不套标准「步骤+预期」：用不变式断言（非单一预期输出）+ stress 参数布局 + flake budget（可接受 rerun 率），字段表与 stress/property 落法见 `references/source-to-case-workflows.md` E.1；层级 call 走 `testing-strategy`。

**Strength**: the only source guaranteed to surface a real user-visible
failure. Every shipped bug fix should leave a regression TC behind, otherwise
the same bug ships again next quarter. `defect-diagnosis` owns the root-cause
narrative; `test-artifact-management` owns the durable test that catches it next time.

### Multi-source fusion

| Source pair | Conflict resolution |
|---|---|
| Doc says X, code does Y | Code wins for **current behavior**; doc wins for **intended behavior**. Write the TC against code; open a回查 task for product to confirm whether the gap is a bug or stale doc. Do **not** silently align doc to code. |
| Figma says X, code does Y | Figma wins for **visible state / interaction**; code wins for **data/contract**. The TC's 预期结果 follows Figma; backend contract assertions follow code. If the visible state has no corresponding state in code (e.g. Figma shows a 恢复 button code never renders), open a回查 task. |
| Doc says X, Figma says Y | Figma wins for **user-visible behavior**; doc wins for **business rules and constraints**. Most "doc vs Figma" diffs are: doc lists features without states; Figma adds the state families. Keep both — they're complementary. |
| All three present | Use code for the contract, Figma for the visible surface, doc for the priority/scope/business rule. Conflicts: log them; do not paper over. |
| Only one source available | Note the missing dimensions explicitly in the TC register so the user knows what wasn't verified (e.g. "no Figma → state families derived from code; visual review pending"). |
| API contract vs code | Contract wins as the published behavior; code wins as the current behavior. Drift = 回查 task (is the server bug or the contract stale?). The TC tests against the contract; in-flight implementation work tracks closing the gap. |
| Bug report vs any other source | Bug report wins for the regression TC content (steps + expected) — it captures the field-witnessed failure. Other sources fold into 信息流转 for context. |

A TC is **not complete** until the most-authoritative source for each field has
been consulted: 优先级 from doc, 模块/功能点 from doc or Figma or contract,
前置条件 + 操作步骤 from Figma (when UI) or code/contract (when API) or bug
report (when regression), 预期结果 from Figma + code + contract combined.

## Test Case Design

Before writing test cases, consult `testing-strategy` for the scenario matrix. For each scenario, capture:

| ID | 模块 | 功能点 | 优先级 | 测试层级 | 测试类型 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|---|---|---|

**Canonical semantics for the two new fields:**
- `测试层级` answers **where the main proof lives**: `unit` / `contract` / `integration` / `e2e` / `manual`
- `测试类型` answers **how the scenario is exercised**: `ui-automation` / `api-automation` / `device-automation` / `contract-validation` / `llm-eval` / `manual-verification`
- Do not collapse the two axes into one enum. `e2e` is a layer; `ui-automation` is an execution form. A web admin flow may legitimately be `e2e + ui-automation`; an OpenAPI drift case may be `contract + contract-validation`.
- v1 rule: one TC carries **one primary `测试层级` + one primary `测试类型`**. If the same business scenario must track separate statuses at multiple layers, split it into multiple TCs or add a separate execution record system — do not overload one row with multi-status semantics.
- The two fields are definition fields, so they belong to both the local md mirror and Feishu Bitable and participate in md ↔ Bitable drift checks.

**Mandatory coverage per module** (use scenario matrix from `testing-strategy`):
- Primary success path (P0)
- Key error / negative path (P0–P1)
- Edge / boundary case (P1–P2)
- Permission / role path when access control exists (P0–P1)
- Data edge (empty, partial, large list) when UI or data surface exists (P1–P2)

**Priority mapping** (same P0/P1/P2 blocking tiers as the canonical severity rubric in `../skill-extraction-workflow/references/review-finding-standards.md`; here the tier is picked by scenario centrality, not by a defect's consequence):
- P0: blocking, must pass before release
- P1: important, should pass before release
- P2: nice-to-have, can follow up post-release

## Feishu Bitable Delivery

See `references/bitable-setup.md` for exact lark-cli commands, auth scopes, and field schema.

### Field Schema (canonical)

| Field | Type | Notes |
|---|---|---|
| 用例ID | text | TC-{module_abbr}-{seq:03d}, e.g. TC-SY-001 |
| 模块 | select | one of the module names from source |
| 功能点 | text | specific feature being tested |
| 优先级 | select | P0 / P1 / P2 |
| 测试层级 | select | primary proof layer: unit / contract / integration / e2e / manual |
| 测试类型 | select | execution form: ui-automation / api-automation / device-automation / contract-validation / llm-eval / manual-verification |
| 前置条件 | text | setup state before test starts |
| 操作步骤 | text | numbered steps |
| 预期结果 | text | observable outcome |
| 状态 | select | 未测试 / 通过 / 失败 / 阻塞 / 跳过 / 废弃（功能永久下线；不计入统计） |
| 跟进人 | user | person currently responsible |
| 信息流转 | text | rolling log（最近 N 条，默认 100；`TC_INFO_KEEP=0` 表示无限）: `[姓名 日期] 内容` |

**How to assign the two fields:**
- Visible browser/admin-web user journey with rendered assertions → `测试层级=e2e`, `测试类型=ui-automation`
- Mobile/miniapp real-device or host-runtime proof → `测试层级=e2e`, `测试类型=device-automation`
- Backend or service endpoint proved by API suites → `测试层级=contract` or `integration`, `测试类型=api-automation`
- OpenAPI / proto / GraphQL compatibility and published-contract drift checks → `测试层级=contract`, `测试类型=contract-validation`
- Model / prompt / replay / eval harness behavior → `测试层级=integration` or `e2e` (pick the main proof layer), `测试类型=llm-eval`
- Human-only or currently non-automatable acceptance evidence → `测试层级=manual`, `测试类型=manual-verification`

### 信息流转 Convention

This field is a multi-person rolling log (only the most-recent N entries are
retained; N=100 by default, configurable via `TC_INFO_KEEP` env). Each entry format:

```
[张三 2026-05-25] 初始化用例，等待开发完成
[李四 2026-05-28] 开发已提测，可以开始测试
[张三 2026-05-29] 测试通过，关闭
```

When creating records, initialize 信息流转 with: `[创建人 日期] 用例初始化`

## TC ID Linking (test code ↔ Bitable)

Tests link to Bitable records via a tiny per-stack helper. Each registration
appends one JSONL line to `test/results/tc-map.jsonl`; `gen_report.py` joins
JUnit XML against that sidecar by test name. **Function names stay clean** —
TC linking is metadata, not coupling.

**Recording happens at REGISTRATION time** (not runtime) so skipped tests,
fixture failures, and conditional skips still register their TC IDs:

四栈 marker/wrapper 用法与 install 见 `references/tc-marker-conventions.md`（Go 高频坑：`tc.Mark` 必须是测试函数首行，先于任何 `t.Skip`；记录发生在 REGISTRATION 时，skipped/条件跳过照样登记 TC ID）。

Helper files live in `references/tc_helpers/`; copy the relevant one into the
project. See `references/tc-marker-conventions.md` for install, multi-TC tests,
CI integration, and overriding `TC_SIDECAR`.

For TC IDs computed at runtime (rare — property-based tests, ID derived from
input), an in-body `tc(...)` form exists. It records only when the body runs,
so it doesn't cover skipped tests — prefer the marker / wrapper forms above
for anything that may skip.

**Tests with no TC linkage run normally.** They are silently excluded from
Bitable sync — by design, for unit/boundary/internal tests that have no
corresponding TC entry. The report surfaces their count under "未链接 TC 的测试".

## CI Exit Gate

`gen_report.py` exits non-zero when tests or suites failed (so CI can gate):

- Default (`--fail-on=any`): non-zero if ANY suite command returned non-zero
  OR any TC ended up `失败`/`阻塞` OR any untracked test failed
- `--fail-on=tc-failures`: non-zero only on TC failures/blocks
- `--fail-on=suite-only`: non-zero only on suite command failure
- `--fail-on=never`: always exit 0 (use only for testing the report itself)

Without this, a red `make test` plus a successful Feishu publish would exit 0
and CI would go green. Every Makefile / CI template in `references/ci_templates/`
relies on this gate.

## Workflow Steps

### Entry Decision: Greenfield vs Iteration

Before any TC generation, check whether the project already has a Bitable
with TCs. **A requirement doc is almost never the entire feature set** —
in real iterations, the doc describes deltas (新增 / 变更 / 废弃) and assumes
the existing system is known. Skipping this check causes duplicate TCs,
missed updates, and orphaned废弃 records.

```bash
# If Bitable is configured for this project:
python gen_report.py --config test/.report-config.json --inventory > /tmp/tc-inventory.md
```

Branch on the result:

| Inventory state | Workflow | Why |
|---|---|---|
| Bitable empty / not configured | **Create (初次生成)** — full extraction below | No existing TCs to reconcile against |
| Bitable has TCs, new doc looks like a delta (mentions "迭代 / 新增 / 优化 / 调整 / 下线") | **Iteration (增量更新)** — see below | Most cases — extract delta, classify per existing TC |
| Bitable has TCs, new doc looks like a rewrite (full spec, no mention of prior) | **Iteration with reconciliation** — classify every doc-derived TC against inventory | Doc author may have re-described stable features; inventory tells you what already exists |

### Iteration (增量更新) — most common case

When existing TCs exist, **do not** generate from doc as if greenfield.
Classify each doc-mentioned feature against the inventory:

| Doc says about feature | Inventory has matching TC? | Action |
|---|---|---|
| 新增 / brand-new | no | **NEW TC** — create with next available ID (`--next-id`) |
| 调整 / 优化 / 变更 / changed | yes | **UPDATE** existing TC (steps/预期 fields); 信息流转 records the doc reference |
| 下线 / 废弃 / removed | yes | **DEPRECATE** existing TC → 废弃 + 信息流转 reason; trigger测试代码级联 |
| (Re-described, no change marker) | yes | **NO-OP** — verify field-level consistency via `--diff-md`; do nothing if aligned |
| (Re-described, no change marker) | no | **NEW TC or doc gap** — confirm with product owner whether truly new or doc-only description |

Workflow:

1. **Pull inventory** — `--inventory` to get current TC list grouped by 模块
2. **Read the doc** — `lark-cli docs +fetch <url>` (or Figma / code if applicable)
3. **Extract doc-derived features** — list them as `(模块, 功能点, change_type)` tuples
4. **Classify each** against the inventory table above
5. **For NEW**: write TC rows in md, get next ID, batch-create in Bitable
6. **For UPDATE**: use the Update workflow's `+record-upsert` flow; 信息流转 append
7. **For DEPRECATE**: status → 废弃 + 信息流转 + 测试代码级联 (see `product-rd-workflow`)
8. **For NO-OP**: skip; verify via `--diff-md` later
9. **Sync local md** — modify md row by row matching the actions taken
10. **Verify**: `--diff-md` should report 0 added / 0 removed / 0 changed after the iteration

### Create (初次生成) — greenfield only

Use this **only when Bitable is empty for the project**. Otherwise see Iteration above.

1. **Identify source** — pick the most authoritative for this task:
   - **A: Feishu requirements doc** (`<feishu_url>`) — for product intent, scope, priority
   - **B: Figma design** — for visible state families, interaction paths, UI/UX TCs
   - **C: Repository code** — for current behavior ground truth, business rules, error paths
   - **D: API contract** — `.openapi.yaml` / `*.proto` / `*.graphql` for service surfaces
   - **E: Bug report** — for regression TC; route to `defect-diagnosis` first for RCA, then back here for the durable TC
   - Most real projects have 2-3 sources; apply Multi-source fusion table when sources disagree
2. **Fetch/read source**:
   - A: `lark-cli docs +fetch "<url>"`
   - B: Figma MCP tools
   - C: Read tool on repo paths
   - D: Read tool on contract file (or fetch from artifact registry)
   - E: bug tracker URL or pasted issue text
3. **Extract modules and features** — list them explicitly before writing cases. For D, this is endpoints/RPCs/types; for E, this is the failure scope
4. **Consult testing-strategy** — use scenario matrix to ensure risk coverage
5. **Write the test matrix artifact** — generate `test/cases/test-matrix.md` and check it in. Columns: `模块 | unit | contract | integration | e2e | manual | blocked`. Each cell lists the TC IDs that will be covered at that layer; `blocked` cells must include reason + owner. This matrix stays layer-centric; `测试类型` remains on the TC row and in the report, not as extra matrix columns by default. This is a planning artifact that survives across iterations and shows reviewers the coverage shape at a glance — it answers "for module X, are we relying on unit tests only? does it have any integration test?". Update on every iteration. Example:

   ```markdown
   | 模块 | unit | contract | integration | e2e | manual | blocked |
   |---|---|---|---|---|---|---|
   | 登录 | TC-SY-001 | — | TC-SY-002 (Redis session) | TC-SY-003 (real browser) | — | — |
   | 支付 | TC-PY-001, TC-PY-002, TC-PY-003 | TC-PY-004 (OpenAPI) | TC-PY-005 (DB tx) | — | TC-PY-006 (真机 OCR) | TC-PY-007 (waiting for sandbox cert · @alice) |
   ```

   **Validation**：report-only 校验（`make report-validate-matrix` / `gen_report.py --validate-matrix`）只做双向 presence check、恒 exit 0、**不得作 merge gate**；blocking 校验用 `make report-validate-matrix-gate`（`--run-tests` 自跑 fast-gate suites、自备份 `results_file` 到 `.pre-gate-bak-*`、fail on drift，fail mode 先 matrix drift 后 standard result gate）。字段与语义契约见 `references/report-config-schema.md`；matrix 列逐 ID 列出，禁 range shorthand。

   **Layer enforcement 是 opt-in**：suite 配了 `layer` 才成为 blocking 证据要求；未配置时 automated layer 格留 TC ID 会报 unverified 并卡 blocking gate，直到被 fast-gate suite 覆盖或移到 `manual`/`blocked`（这两类是 owner 行不是 layer 声明）。`matrix_gate: false` 用于有意放在 fast gate 外的 live/device/slow suites。canonical 六列之外的扩展列（mutation/fuzz/property/chaos）`parse_matrix_tcs` 既不报错也不校验，见 `references/report-config-schema.md` 的 allowed-layers 段。

   **Picking which classical method to apply per cell** (EP / BVA / Decision Table / State Transition / Pairwise / Exploratory+SBTM / Soap Opera / CRUD / Visual Regression / Error Guessing / Checklist-Based / Syntax-Grammar): see `references/classical-test-design-techniques.md` — 11 个经典 / 常用方法 + 何时用 / 何时不用 / 在本 scheme 怎么落 + 例子。

6. **Write test case rows** — write TC rows in markdown table first, review with user if needed; save the md file as the local markdown mirror under `test/cases/all.md`
7. **Prepare Bitable** — follow `references/bitable-setup.md` to create app/table/fields
8. **Import records** — batch create via lark-cli or Python script; Bitable is the authoritative tracking source, local md is the human-readable mirror of the definition fields; both must stay in sync going forward
9. **Rename default view + create grouped view** — rename "Grid View" → 全部用例, create 按模块分组 + group by 模块 field (substitute for mind map); see `references/bitable-setup.md` Step 6
10. **Share Bitable** — set org-wide sharing in Feishu UI (no API available via lark-cli)
11. **Optional: hand off to test implementation** — use `testing-strategy` (TC list input mode) + stack skill to write tests from the delivered TC list; tests link to TC IDs via the `tc(...)` helper (see TC ID Linking above); `test-artifact-management` does not implement test code
12. **Optional: set up test report** — follow the steps below:
    1. **Directory structure** — create `test/` in the project root if not present; put `.report-config.json` and `cases/` (TC markdown mirror) under `test/`; JUnit XML and `tc-map.jsonl` go to `test/results/` (add to `.gitignore`).
    2. **Vendor the report script** — copy this skill's `references/gen_report.py` into the project as `test/scripts/gen_report.py` and commit it. All later commands (local, Makefile `GEN_REPORT` default, CI templates) call this vendored copy, so CI never depends on a skill being installed on the runner. When the skill's copy gains features you need, re-copy it.
    3. **Init config**:
       - Bitable mode: `python test/scripts/gen_report.py --config test/.report-config.json --init --bitable-url "<url>"`
       - No-Bitable mode (skip TC management; report only): `python test/scripts/gen_report.py --config test/.report-config.json --init` (leaves `base_token`/`table_id` empty)
       - See `references/report-config-schema.md`.
    4. **Install TC helper** — copy `references/tc_helpers/tc.{py,go,ts,dart}` for the project's stack; follow `references/tc-marker-conventions.md`.
    5. **Makefile check** — inspect the project root and apply the smallest change. See `references/makefile-template.md` for the 5-state matrix (no Makefile / missing report section / missing TC_SIDECAR var / outdated report-init form / up to date) — never rewrite an existing Makefile, only append or surgically edit a single line.
    6. First `make report` (Bitable mode) creates the Feishu doc and writes its URL into `test/.report-config.json`; subsequent runs replace the doc in place. In no-Bitable mode, the report prints to stdout unless `report_doc_url` is set.

### Test Report (测试报告)

After automated tests run, generate the report:

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json
```

(`test/scripts/gen_report.py` is the project-vendored copy from setup step 2 above; equivalently `make report`.) Author, source, and version are auto-detected from git; only override with `--author`, `--source`, `--version` when needed.

**Modes (auto-detected from config):**
- **Bitable mode** (`base_token` + `table_id` set): syncs JUnit results to Bitable, generates a full TC-centric report (总览 + 按模块 + 按测试层级 + 按测试类型 + P0 明细 + 未链接 TC 的测试 + 发布建议), publishes to Feishu doc.
- **Minimal mode** (Bitable fields empty): no Bitable, generates a slim JUnit-summary report (总览 + 按套件 + 可选按测试类型 + 失败明细) to stdout, or to Feishu doc if `report_doc_url` is set.

**Common:**
- First run (Bitable mode): creates a new Feishu doc and writes its URL into the config file
- Subsequent runs: replaces the entire doc content in place (`replace_all`)
- CI: `test/.report-config.json` is committed (resource IDs only); inject only auth secrets (`LARK_BOT_APP_ID`, `LARK_BOT_APP_SECRET`) via CI environment; templates for GitHub Actions, GitLab CI, and Jenkins live in `references/ci_templates/` (each includes last-run snapshot caching + PR/MR comments via `--pr-summary`)
- `--dry-run`: prints the Markdown without writing to Feishu (useful for previewing locally)

See `references/gen_report.py` and `references/report-config-schema.md`（Report Structure 节）for full details.

### Update (需求变更 / 迭代补充)

Classify the update before acting:

| 变更类型 | 操作 |
|---|---|
| 需求细节调整（步骤/预期结果变化） | 更新对应记录的 操作步骤 / 预期结果，信息流转追加变更说明；以 用例ID 为键同步改本地 md 对应行 |
| 新增功能点 | 新建记录，用例ID续编，不复用旧 ID；同步在本地 md 对应模块末尾追加行 |
| 功能废弃 | 将状态改为「废弃」，信息流转追加废弃原因，不删除记录；本地 md 保留行，在功能点列标注 `[废弃]`；通知开发在同一 commit 删除该 TC ID 对应的测试代码（见下方级联规则） |
| 测试结果更新（通过/失败/阻塞） | 只更新 状态 + 跟进人，信息流转追加测试结论；本地 md 不需同步（状态/跟进人不在 md 定义字段中） |
| 回归 bug 补充用例 | 新建记录，优先级 P0，功能点注明"[回归]"；同步在本地 md 对应模块末尾追加行 |

**功能废弃 → 测试代码级联**：废弃 TC 后**同一 commit**级联——grep sidecar 与 marker 找关联测试，用 dev skill 的 import-graph 判业务代码是否仍有效（已删→删测试、部分废弃→只摘 ID、无关联不进此流程）；步骤细则见 `references/update-lifecycle.md`。

**误标恢复**：`--unfreeze "<ids>" --unfreeze-reason "<原因>"`（reason **必填**；**不与 `--run-tests` 同跑**——需要"测红不解冻"就先单独 `make test`），细则见 `references/update-lifecycle.md`。

**update 三原则**：用例ID 是唯一稳定键（匹配/续编都以它为准）；本地 md 只镜像定义字段（不同步状态/跟进人/信息流转）；漂移检查 `--diff-md` 多人编辑后必跑。命令细节与 update 工作流见 `references/update-lifecycle.md`。

## Quality Checks Before Delivery

- Every module from source has at least one P0 test case
- Every identified error path has a negative test case
- 用例ID values are unique and follow naming convention
- 操作步骤 uses numbered steps (1. 2. 3.)
- 预期结果 describes observable outcome, not implementation detail
- 状态 defaults to 未测试 for all new records

**Deeper review and prioritization method** (7-element TC review checklist; Three Amigos / Power of Three lightweight review; Risk = Probability × Impact scoring; PRISMA / TMAP-inspired product-risk shortcut; P0 / P1 / P2 触发升级规则): see `references/tc-review-and-prioritization.md` — 谁 review / 评什么 / P0-P1-P2 用方法定 + 例子。
