# 从源到用例的派生工作流

写一组 TC 前对照这份清单：每个 Source（需求 / 设计 / 代码 / API 契约）有哪些**业内命名的派生工作流**可借鉴。每条：定义 → 何时用 → 何时不用 → 在本 scheme 怎么落 → 例子。

与 `classical-test-design-techniques.md` 互补 — 那份是"每条 TC 用什么技术（EP / BVA / Pairwise...）"；这份是"从 Source A-E 派生一组 TC 的流程形态"。

## 外部来源（按名引用）

- **Gojko Adzic**, *Specification by Example* (2011, Manning)
- **Matt Wynne**, *Example Mapping* (2015, Cucumber blog)
- **Lisa Crispin & Janet Gregory**, *Agile Testing* / *More Agile Testing* — ATDD
- **Figma Variants** 官方文档
- **Stryker** (JS/TS/.NET) / **PIT** (Java) / **mutmut** (Python) — mutation testing
- **Hypothesis** (David MacIver, Python) / **fast-check** (Nicolas Dubien, JS) — property-based testing
- **schemathesis** — OpenAPI fuzzing
- **Pact** (DiUS) — 消费者驱动契约测试
- **Dredd**（Apiary） / **Prism**（Stoplight） — spec ↔ 实现对齐

---

## A. 需求文档 → 用例

### A.1 Specification by Example（SBE）

**定义**（Adzic 2011）：用具体例子作可执行规范的核心；产品 / 开发 / 测试三方在 spec workshop 一起找"关键例子"，每个例子最终成为一条验收测试。**例子自动化能跑过 = 需求实现了**。

**用**：需求抽象（"用户应能 XXX"）、跨团队 / 外包、有 PO 配合做 workshop。

**不用**：solo dev / 小改动；没人陪你 workshop 时退到 A.2 Example Mapping。

**落地**：
- spec workshop 把每条 acceptance criterion 转成 3-5 个具体例子（含 happy / 反例 / 边界 / 异常）
- 每个例子 = 1 条 TC，操作步骤 = 例子的输入，预期结果 = 例子的输出
- spec ↔ TC 映射在 信息流转 里追加 `[spec §3.2 example 2]`
- 优先把 happy example 自动化到 contract / integration 层

**例**：
```
需求："导出文件 7 天内可下载，过期失效"
SBE 例子：
  - 导出后第 1 天访问 → 可下载
  - 导出后第 8 天访问 → 已过期（不可下载）
  - 已下载过的文件再次访问 → 不改变过期时间
  - 跨时区按租户时区计算过期（UTC+9 租户 第 7 天 23:59 仍可下载）
→ 4 条 TC，操作步骤直接抄例子
```

### A.2 Example Mapping（轻量版）

**定义**（Wynne 2015）：solo 或 3-Amigos 用四色卡片派生 TC：
- **黄卡**：1 个 user story
- **蓝卡**：规则 / acceptance criteria
- **绿卡**：例子（每条规则对应若干例子）
- **红卡**：疑问 / blocked，需回 PO

25 分钟一个 story；卡片爆炸（> 10 张绿卡 / 一个规则）说明 story 太大要切。

**用**：需求模糊 / 还没定型 / 想快速暴露歧义；没条件做完整 SBE workshop。

**不用**：需求已稳定 + 例子明确 — 直接 TC，别加流程开销。

**落地**：
- PR / Bitable 信息流转 里贴 Example Map 截图或 markdown
- 每张绿卡 = 1 条 TC（同 SBE）
- 红卡 = 未答疑问，**不入 Bitable 作 TC**（缺操作步骤 / 预期结果）— 进 信息流转 / 回查清单 / `test/cases/test-matrix.md` 的 `blocked` 列，写疑问 + 跟进人 = PO；问题清楚后再入 TC

---

## B. 设计稿 → 用例

### B.1 Variant → 状态矩阵自动派生

**定义**（Figma Variants 工程化用法）：Figma Component 用 Variants（properties + values）枚举所有显示态。**每个 Variant 组合 = 1 条 TC**。

**用**：设计稿用了 Variants 系统 / Design System；设计师交付时已枚举状态。

**不用**：设计稿是平面 mockup 没有 Variants — 退到本 SKILL.md Source B 默认映射（人工识别状态家族）。

**落地**：
- 用 Figma MCP 拉 Component Variants 列表
- 每个 `(property=value)` 组合 = 1 条 TC，功能点 = `<Component> [state=value]`
- 预期结果含 token 引用（color / spacing / typography），便于 visual regression 比对
- N 个 properties × M 个 values 爆炸时用 `classical-test-design-techniques.md` §4 Pairwise 缩减

**例**：
```
Button Component Variants:
- type:  primary / secondary / danger
- size:  sm / md / lg
- state: default / hover / focus / disabled / loading

全笛卡尔 = 3 × 3 × 5 = 45 TC
Pairwise (PICT) ≈ 15 TC（覆盖所有两两组合）
→ 写 15 条 TC，每条 1 个 Variant
```

### B.2 设计稿原型链接 → 流程 TC

**定义**：Figma Prototype 把 frame 用 interaction 串成流程图；那个流程图本身就是 e2e 用例的执行步骤。

**用**：设计稿有 prototype 链路（不是静态 mockup）。

**落地**：
- 每条 prototype 主链路 = 1 条 e2e TC
- 操作步骤 = prototype 上的 interaction 序列
- 预期结果 = 终点 frame 的可观察细节
- **高风险 / 不确定**的主链路再配合 `classical-test-design-techniques.md` §5 Exploratory charter（routine 路径已自动化为 TC，不再 charter）

---

## C. 代码 → 用例

### C.1 Mutation Testing 作"已写 TC 够不够"的回探

**定义**（PIT / Stryker）：自动改代码（删一行 / `>` 改 `>=` / `true` 改 `false`），再跑现有测试套件：**杀不死的 mutant = 漏的 TC**。

**用**：第一轮 TC 写完后回探 critical path / 核心算法 / 高风险模块。

**不用**：UI 层 / I/O 重的代码（mutant survival rate 高但常常不是漏 TC 而是断言层级不对）；全量跑代价高，按模块按需用。

**落地**：
- 不进 Bitable 作 TC，进 `test/cases/test-matrix.md` 作 module 级标记 `[mutation-checked: 88%]`
- 杀不死的 mutant → 反推 1 条 TC（操作步骤 = "覆盖 mutant 改动行 X 的行为"，预期结果 = mutant 应被现有断言抓到）
- 工具：Java PIT、JS Stryker、Python mutmut、Go go-mutesting

### C.2 Property-Based Testing 抽不变式

**定义**（Hypothesis / fast-check）：不是写 `f(2) == 4`，而是写"对所有 x, f(x) 满足 P(x)"。框架自动生成 100+ 输入测 P；失败时自动 shrink 到最小反例。

**用**：纯函数 / 算法 / 序列化 / 状态机不变式 / round-trip（encode → decode == identity）。

**不用**：副作用重 / 外部依赖多 / 业务逻辑分支多但不变式说不清。

**落地**：
- TC 操作步骤写"对生成的 N 个输入跑 P"，预期结果 = "P 全部为真，否则给出最小反例"
- 测试矩阵 `unit` 列填，标 `[property-based]`
- 工具：Python hypothesis、JS fast-check、Java jqwik、Go gopter / rapid

---

## D. API 契约 → 用例

### D.1 Schemathesis：OpenAPI 自动生成 + fuzz

**定义**：读 OpenAPI spec，对每个 endpoint 自动生成符合 schema 的请求（合法面）+ 各种 mutation（非法面），检查响应是否符合 spec。底层用 Hypothesis 做 shrinking。

**用**：API 已有 OpenAPI / Swagger；想要低手写用例维护的 contract test。

**不用**：spec 不完整 / 不准 — 先治理 spec 再谈自动测。

**落地**：
- 不是手写 TC，是把 `schemathesis run` 作为 CI 一步
- 测试矩阵 `contract` 列填 `schemathesis: <endpoint count>`
- 发现的 schema ↔ 实现 drift bug 走 Source E 流程回归

**注意点**：仍需稳定环境 / auth 设置 / seed 数据控制 / 标注非破坏性 endpoint（避免误打到 DELETE/POST 生产数据）/ 速率控制；spec 质量直接决定生成质量。

### D.2 Pact：消费者驱动契约测试

**定义**（DiUS）：consumer 写"我期望 provider 返回这样"，生成 pact 文件；provider CI 拉 pact 回放，验证是否满足。**不是测端到端集成，是把契约固化**。

**用**：微服务架构 / 多消费者共享一个 provider；担心 provider 变更打破 consumer。

**不用**：单体 / 强类型 RPC 已有静态检查（gRPC + proto）。

**落地**：
- 不进 Bitable，进 `test/cases/test-matrix.md` `contract` 列：`pact: <consumer-count> consumers`
- pact 文件版本化在 broker（Pact Broker / PactFlow）
- consumer / provider 各跑各的 pact verification

### D.3 Dredd：spec example → 真后端 sanity

**定义**（Apiary）：拿 spec 里的 example 实际调一遍真后端，比对响应是否符合 spec。简单粗暴的契约 sanity 检查。

**落地**：CI 一步 `dredd` 跑通；和 Schemathesis 互补 — Schemathesis 在 fuzz 面（spec → 大量生成），Dredd 在 example 面（spec example → 单次校验）。测试矩阵 `contract` 列标 `dredd`。

### D.4 Prism：spec 双向用（mock + 校验代理）

**定义**（Stoplight）：Prism 同一份 spec 有两种用法：
- **Mock server**：起个 mock 服务，让 frontend / consumer 在 provider 未就绪时也能开发并写 TC（**测的是 frontend ↔ mock**，不是 frontend ↔ 真后端）
- **Validation proxy**：在真请求路径上当中间层，检查 request / response 是否符合 spec

**用**：
- Mock 模式：consumer 比 provider 早交付时；想给前端隔离开发环境
- Proxy 模式：已有真 traffic，想轻量验证 spec drift（与 Schemathesis 互补 — Schemathesis fuzz 生成合成请求，Prism proxy 校验真实流量，不可互替）

**落地**：
- Mock 模式：`test/cases/test-matrix.md` `contract` 列标 `prism-mock`；提醒 frontend TC 实际打的是 mock，需另跑端到端 smoke 才证明真集成
- Proxy 模式：作 CI 中间件 / 灰度环境验证手段，不入 TC（是基础设施层）

### D.5 进阶契约形态 → TC 映射（本 scheme 自有规则）

以下映射是本 scheme 的自有规则（非 D.1-D.4 业内命名流程）。遇到这些形态
时显式点名，不要按普通 endpoint 处理：

| Shape | TC implications |
|---|---|
| Versioned paths (`/v1/x` and `/v2/x` coexist) | Treat as two distinct 模块 unless they share implementation. Cross-version contract TC: `/v1` consumer must still work after `/v2` ships (deprecation window). |
| `oneOf` / `anyOf` / discriminator | One success TC per discriminator branch + one failure TC for unknown/missing discriminator. Polymorphic response: assert the discriminator field is present and matches the body shape. |
| Vendor extensions (`x-rate-limit`, `x-idempotency-key`, `x-tenant-scoped`, etc.) | Each `x-` extension implies a TC: rate-limit exceeded → 429; idempotency key replay → same result; tenant-scoped → cross-tenant 403. Don't ignore them just because OpenAPI doesn't standardise. |
| gRPC server-streaming RPC | TC dimensions: first chunk arrival, mid-stream cancellation, server-side EOF, error mid-stream, slow consumer / backpressure. |
| gRPC client-streaming / bidi RPC | TC dimensions: half-close semantics, interleaving, deadline propagation, partial submit + server response. |
| GraphQL subscriptions | TC dimensions: subscription start handshake, first event, reconnect-with-resume, server termination, client disconnect. |
| GraphQL nullability | Each non-null field with `@deprecated` or downstream-dependent → TC for the propagation when downstream returns null. |

---

## E. Bug 报告 → 用例

主映射表见 SKILL.md Source E（bug 字段 → TC 字段一一映射）。

### E.1 Heisenbug / race 无稳定复现的 TC 布局

标准 操作步骤 + 预期结果 形态装不下无法稳定复现的 race/heisenbug——用不
变式断言（invariant，而非单一预期输出）+ stress 参数布局 + flake budget：

| Field | Content for unreproducible bugs |
|---|---|
| 功能点 | `[回归][race]` or `[回归][heisenbug]` + concise label |
| 前置条件 | Trigger envelope: concurrent N workers / cache-cold / network latency Xms / specific db pool size — list every input dimension you *suspect* matters |
| 操作步骤 | Stress params: "loop M iterations, K parallel goroutines/threads, seed=S if reproducible; capture full trace on first occurrence" |
| 预期结果 | Invariant assertion (NOT a single expected output): "no two threads observe stale-and-fresh in the same iteration" / "transaction.committed_at strictly monotonic" |
| 优先级 | P0 (regression of unknown frequency is still a regression) |
| 信息流转 | Original RCA link + flake budget ("acceptable rerun rate < 0.1%; above this re-open the bug") + log/trace artefact pointer + seed value(s) that have reproduced |

The TC then ships as a stress/property test in the codebase (route to
`testing-strategy` for the layer call — usually integration or scenario with
explicit stress harness). It validates the invariant, not the exact symptom.
Flake budget is the honest part: race fixes rarely give 100% reproducibility.

---

## 快速选用决策表

| 情境 | 用 |
| --- | --- |
| 需求文档抽象 + 有 PO 配合 | SBE workshop |
| 需求文档抽象 + solo | Example Mapping |
| Figma 用了 Variants | Variant → 状态矩阵自动派生 |
| Figma 有 prototype 流 | Prototype 链路 = e2e TC |
| 写完 TC 想知道漏没漏 | Mutation Testing 回探 |
| 纯函数 / 算法 / 不变式 | Property-Based Testing |
| 有 OpenAPI 想免维护 contract test | Schemathesis |
| 多消费者共享 provider | Pact |
| 想快速 sanity OpenAPI ↔ 实现 | Dredd / Prism |

---

## 故意不借鉴

| 工作流 | 原因 |
| --- | --- |
| BDD Gherkin（Given / When / Then 关键字） | 我们用「前置 / 步骤 / 预期」三列，等价但不强求 Gherkin 关键字（与 `classical-test-design-techniques.md` 同立场） |
| 3 Amigos / Spec Workshop 全套 | 团队过程 / 组织文化，route 给 `product-rd-workflow` |
| LLM 辅助生成（Diffblue Cover / Copilot test gen） | 本 skill 即是 LLM 辅助生成；说"用别的 LLM 工具"无增量 |
| Postman / Newman | 执行 / collection 管理工具，不是派生流程 |
| Chromatic / Percy / Applitools 自动化 visual diff | 是 visual regression 实现层，归 `classical-test-design-techniques.md` §8 |
| User Story Mapping（Jeff Patton） | 是产品发现 / 路线图工具，不直接派生 TC；route 给 `product-rd-workflow` |
