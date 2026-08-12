# 经典测试设计方法对照

写新一批 TC 前，对照这份清单看有没有漏掉公认的经典方法。每条：定义 → 何时用 → 何时不用 → 在本 scheme 怎么落 → 例子。

不替代外部文献，是「公开文献 ↔ 我们的管道（多维表格 / 测试矩阵 / 5 种源 / 报告）」的映射。

## 外部来源（按名引用）

- **ISTQB Foundation Level（CTFL）** syllabus — 测试设计技术章节
- **Lee Copeland**, *A Practitioner's Guide to Software Test Design* (2004)
- **ISO/IEC/IEEE 29119** — Software Testing standard
- **Cem Kaner**, BBST (Black Box Software Testing) course materials
- **James Bach & Michael Bolton**, *Rapid Software Testing* — HTSM / SFDPOT
- **Elisabeth Hendrickson**, *Explore It!* — test heuristics cheatsheet
- **James Whittaker**, *Exploratory Software Testing* — tours
- **Pairwise / Combinatorial**: **Kuhn / Wallace / Gallo 2004 NIST 实证**（多被测系统 2-way 捕到 50–90% 的缺陷，差异大）；工具：Microsoft PICT、NIST ACTS、Hexawise
- **Hans Buwalda 2004** — soap opera testing
- **Lisa Crispin & Janet Gregory**, *Agile Testing*
- **Glenford Myers**, *The Art of Software Testing* (1979) — error guessing 起源
- **Boris Beizer**, *Software Testing Techniques* (1990) — syntax / grammar testing

---

## 1. Equivalence Partitioning + Boundary Value Analysis（EP + BVA）

**定义**（ISTQB / Copeland）：把输入域切成系统行为相同的等价类，每类取一个值（EP）；测每个类的边界（BVA）。BVA 仅适用于**有序**分区；ISTQB v4 区分 2-value（边界 + 下一格）和 3-value（边界 + 两侧）。下面例子用 3-value 形式：`min-1`、`min`、`min+1`、`max-1`、`max`、`max+1`（含越界负例）。

**用**：数值范围 / 长度限制 / 枚举 / 文件大小 / 日期范围 — 所有有显式边界的输入。

**不用**：开放文本 / 无边界输入。换成 error guessing 或 fuzz。

**落地**：
- 每个等价类 1 条正向 TC；每个边界 1 条 TC。多个边界值可合并到一条 TC 的 操作步骤 里（值表）。
- 枚举字段见 Source D 规则：1 条 TC + 值表覆盖普通值；unknown / default / deprecated / 安全敏感值各起一条。

**例**：
```
TC-ORD-007 [BVA]: 订单数量边界
前置: 用户已登录
步骤: 提交订单，数量取下表
  | 数量  | 预期                |
  | 0     | 报错"数量须 > 0"    |
  | 1     | 通过                |
  | 2     | 通过                |
  | 99    | 通过                |
  | 100   | 通过                |
  | 101   | 报错"超出单次上限"  |
```

---

## 2. Decision Table Testing

**定义**（ISTQB / IEEE 29119）：把布尔 / 分类条件的组合穷举成表，**每条规则（组合）→ 一个预期动作**。专门补"漏组合"。经典 ISTQB 排版是列向（每列一条规则）；本文示例用行向，markdown 更易读。

**用**：业务规则是 2–6 个条件的合取（典型：权限矩阵、计费规则、资格判定、风控放行）。

**不用**：> 7 个维度（列爆炸）。换 Pairwise。

**落地**：**每条规则（行向排版即每一行）= 1 条 TC**（操作步骤 = 输入组合，预期结果 = 动作）。共享 setup 的多条规则如果落在 unit / contract 层，可合并为 1 条参数化 TC（matrix 层填 `[parametric]` 标记）。

**例**：
```
TC-AUTH-001..005 [decision table]: 资源访问放行
| #   | 已登录 | 资源属主 | 二步验证 | 预期           |
| --- | ---    | ---      | ---      | ---            |
| 1   | Y      | Y        | Y        | 放行           |
| 2   | Y      | Y        | N        | 要求二步验证   |
| 3   | Y      | N        | -        | 403 无权限     |
| 4   | N      | -        | -        | 302 去登录     |
| 5   | -      | -        | -        | 默认拒绝       |
```

---

## 3. State Transition Testing

**定义**（ISTQB）：把功能建模成有限状态机；覆盖维度依次扩大：每个**状态** → 每条**合法转移** → 每条**非法转移** → **N-switch 覆盖**（Chow 1978，连续 N 步合法转移）。

**用**：有生命周期的功能 — 订单状态机、支付状态机、登录-OTP-冻结链、视频播放器 play/pause/buffer/error、文件上传 progress/retry/cancel。

**不用**：无状态（请求 → 响应，无持久态）。

**落地**：
- 1 条 TC 覆盖主向前流；每条非法转移 1 条负例 TC；每条 skip / back / abort 路径 1 条 TC。
- test-matrix.md 该模块加 `[stateful]` 标记，提醒 review 检查转移覆盖。

**经验法则**：如果你画不出状态机草图，说明对功能理解不到位，先别写 TC。

---

## 4. Pairwise / Combinatorial Testing

**定义**（Kuhn / Wallace / Gallo 2004 NIST 实证）：N 个入参各有 K 个值时，完整笛卡尔积 K^N 爆炸。Pairwise 覆盖所有 (param_i, param_j) 的值对，**Kuhn 等的多被测系统实证：2-way 捕到 50–90% 的缺陷，差异大**（具体看产品形态；少数系统需 3-way 才覆盖大头）。

工具：Microsoft PICT（开源）、NIST ACTS、Hexawise。

**用**：≥ 3 个入参，每个 ≥ 2 个值，组合爆炸到不能穷举时。

**不用**：参数有已知三元交互（要 3-wise / N-wise）；或参数独立（各自单测就行）。

**落地**：用 PICT 生成；TC 数量 = PICT 输出行数，每条 1 行。PICT 输入文件归档在 `test/cases/pairwise-<feature>.txt`，可复现。

**例（PICT 输入）**：
```
浏览器: Chrome, Firefox, Safari
OS:    macOS, Windows, Linux
登录方式: 密码, OTP, SSO
设备类型: 桌面, 平板, 手机
```
全笛卡尔 = 81 组合；pairwise 通常 9–12 条 TC 即可。

---

## 5. Exploratory Testing + Session-Based Test Management（SBTM）

**定义**：探索测试 = 边设计边执行；**SBTM（Jonathan Bach & James Bach 2000）**给探索套上 **charter + 时间盒 + session report** 三件套，让它可管理。Hendrickson《Explore It!》与 Bach / Bolton RST 提供配套 heuristics。

**用**：新功能 / 高风险 / 理解不深；脚本化 TC 会过度约束覆盖；测试人有产品上下文。

**不用**：回归套件（那是脚本化的）。

**落地**：
- 测试矩阵 `manual` 列填 charter ID（`TC-ORD-EXP-001 [charter]`）
- 操作步骤 = charter（"探索下单流程，重点看部分失败恢复，90 分钟"）
- 预期结果 = success criteria / 不变式（"最终态唯一、无重复创建、错误有恢复路径"）
- 信息流转 = session report 摘要 / 链接，按 append-only 规则追加
- 时间盒：默认 90 分钟 / session；不是"直到找到 bug 为止"
- session 找到的真 bug → 单独走 Source E（bug 回归 TC）流程

**Whittaker tour 启发（充当 charter 提示）**：
- **FedEx tour**：跟着数据投递走端到端
- **Garbage Collector tour**：按某种顺序（菜单 / 字母序）系统遍历每个入口，看是否还能正常打开
- **Saboteur tour**：每个输入故意破坏
- **All-Nighter tour**：连续运行 8+ 小时看泄漏

---

## 6. Soap Opera Testing（Buwalda 2004）

**定义**：把现实的灾难场景串成一条 TC（灵感来自肥皂剧 — 一个角色经历 5 重危机）。专门捕**集成 bug**，那种孤立 happy-path 测试看不到的。

**用**：组件多、运行时才组合；怀疑只有真实多步用户旅程才能触发的 bug。

**不用**：unit 层 / 纯无状态函数。

**落地**：每个**高风险** feature 加 1–2 条 soap-opera TC，按真实业务风险评 P0 / P1（不强制每条 release-blocker），标 `[soap-opera]`：
- 操作步骤：8–15 条编号步骤，每步都是现实用户触发（"用户登录 → 提交订单 → 网络断开 → 重新登录 → 状态恢复 → 取消订单 → 重新提交 → 撤销"）
- 预期结果：**不变式**（"订单状态始终一致、无重复提交、支持工单可定位 trace"），不是单一可观察输出

---

## 7. CRUD 启发法

**定义**（启发法，非 ISTQB 经典设计技术；常见来源：Hendrickson cheatsheet 等）：每个实体覆盖 Create / Read / Update / Delete + 各自负例。后端服务首轮覆盖快查清单。

**用**：服务暴露资源式 API（REST、gRPC unary on entities）；首轮快速看缺啥。

**不用**：行为驱动 / 事件驱动（用 state transition 更好）。

**落地**：默认 checklist，按 endpoint 实际能力 waive（read-only 表跳 Update / Delete；append-only 表跳 Update / Delete）：
```
{Create-OK, Create-validation-fail,
 Read-by-id-OK, Read-not-found,
 Update-OK, Update-conflict,
 Delete-OK, Delete-not-found, Delete-cascading-OK}
```
审过后 test-matrix.md 标 `[crud-checked]`；waive 的格子在矩阵里写 `n/a (read-only)` 等理由。

---

## 8. Visual Regression Testing（现代自动化检查，非经典文献方法）

**定义**：捕基线截图；每次跑测试 diff 当前 vs 基线。工具：Percy / Chromatic / Applitools / Playwright `toHaveScreenshot()` / Vitest + `vitest-image-snapshot`。

**用**：视觉敏感的 UI（营销落地页、复杂布局、设计系统关键组件、深 / 浅色主题切换）。

**不用**：纯后端 / 纯数据视图 / 无视觉细节。

**落地**：
- 测试矩阵 `e2e` 列填该 TC
- 测试代码用栈级视觉回归库
- 基线截图按所选工具默认位置 commit（Playwright 默认在 spec 旁、jest-image-snapshot 在 `__image_snapshots__/`）；想统一目录需显式配 `snapshotPathTemplate` 或等价选项
- 每条 TC 的预期结果写最大可接受像素 diff 阈值（如 `< 0.1%`）

**限制**：视觉回归只能捕"看起来不一样"，不能捕"看起来变差"。要配合 `product-ui-ux-design` 的 judgment-layer review 看 taste。

---

## 9. Error Guessing

**定义**（ISTQB / Myers《The Art of Software Testing》1979）：基于经验、bug 历史、相似产品的故障模式，**主动想"哪里最可能出问题"**，定点设计 TC。是其他方法的补充，不替代它们。

**用**：写完 EP / BVA / 决策表 / 状态转移后，再过一遍想想"还有什么我们之前在类似系统踩过的坑"。

**不用**：作为唯一覆盖手段。Error Guessing 高度依赖个人经验，缺乏系统覆盖。

**落地**：经验驱动，不是每模块固定配额 — **高风险 / 历史高缺陷 / 相似系统踩过坑**的模块加 1+ 条 TC 标 `[error-guessing]`；操作步骤直接写"复现过去 bug 库里 XXX 类故障"，预期结果是"不复现"。bug 库见 Source E 流程。

**常见 guess 来源**：
- 组织内部 bug 库的高频 / 高严重度归因
- 同栈历史 incident（如：DB 主从切换瞬态、限流降级误命中、时区切换、夏令时）
- 安全 top 10：SQLi、XSS、CSRF、IDOR、SSRF、open redirect

---

## 10. Checklist-Based Testing

**定义**（ISTQB）：按预定义清单逐项检查。清单可以是合规要求、UI 标准、行业 best practice、过去 retrospective 沉淀。

**用**：合规 / 安全 / 可访问性 / 移动端发布前、合规审计。

**不用**：行为驱动的功能正确性（用决策表 / 状态转移）。

**落地**：把清单作为一份 `test/cases/checklist-<topic>.md`，每项 = 1 条 TC。常见清单：
- A11Y：WCAG 2.2 AA 关键项（对比度、键盘可达、焦点可见、aria 标签）——a11y 验收标准（含 2.2 新增项）由 `product-ui-ux-design` 拥有，这里只取"每项 = 1 条 TC"的落地形态，不复制标准细节
- 安全：OWASP ASVS L1 项
- 移动发布：小程序 / iOS / Android 上架审核常见拒因清单
- 国际化：时区、语言、RTL、长文本截断

---

## 11. Syntax / Grammar Testing

**定义**（Beizer《Software Testing Techniques》1990）：基于输入文法（BNF / 正则 / schema）系统派生测试输入：**合法**（覆盖每条产生式）+ **非法**（每条规则的 mutation）。

**用**：被测系统消费有文法的输入 — OpenAPI / GraphQL payload、SQL / 搜索 DSL、config 文件（YAML / JSON / TOML）、URL / 路由模板、日志解析。

**不用**：无 schema 的自由文本字段（用 EP / fuzz）。

**落地**：
- 合法面：每条产生式至少 1 条 TC（操作步骤 = 1 个合法输入，预期结果 = 通过 + 解析正确）
- 非法面：对每条产生式做 mutation（缺字段、错类型、超长、嵌套深、循环引用、字符集越界），每类 1 条 TC（预期结果 = 明确报错 + 不崩溃 + 错误信息可定位）
- 工具：OpenAPI 用 schemathesis（合法 + 非法两面都覆盖）；JSON schema 合法面用 hypothesis-jsonschema，非法面用 schema mutation / 手写负例；DSL 用 antlr grammar + 自写 fuzz

**例**：
```
TC-API-021 [syntax]: PUT /v1/users 缺 required 字段
步骤: 发送 {"name": "x"}，缺 "email"
预期: 400 + 错误信息含 "email is required" + 不落库
```

---

## 快速选用决策表

新功能坐下来写 TC 前，30 秒过一遍：

| 功能形态 | 用 |
| --- | --- |
| 数值范围 / 大小限制 / 日期边界 | EP + BVA |
| 权限 / 资格 / 计费规则 | Decision Table |
| 订单 / 生命周期 / 状态 | State Transition |
| > 3 个入参可组合 | Pairwise（PICT） |
| 全新 / 高风险 / 理解不深 | Exploratory + SBTM charter |
| 多步用户旅程 | Soap Opera |
| REST / gRPC 资源 | CRUD 启发法 |
| 可见 UI | Visual Regression |
| 历史踩过坑 / 经验型补漏 | Error Guessing |
| 合规 / A11Y / 安全 / 上架审核 | Checklist-Based |
| 有 schema 的输入（API / DSL / config） | Syntax / Grammar |

11 条都不沾边？大概率是：
- 在过度工程（"这里其实不需要 TC"）
- 或遇到不寻常问题，回 testing-strategy 求助 scenario matrix

---

## 故意不借鉴

| 技术 | 原因 |
| --- | --- |
| Classification Trees（层级 EP） | 太学院；EP + BVA 覆盖 |
| Cause-Effect Graphing | 决策表覆盖同问题 |
| FMEA（失效模式与影响分析） | 默认不用；regulated / safety-critical / 高 blast-radius 释放场景才适用 |
| HTSM / SFDPOT 全套 | 太重；可借鉴个别 heuristic（如 SFDPOT 的 Structure / Function / Data 维度）通过 exploratory charter 单点采用 |
| Mutation Testing | 是 test-suite adequacy（测套件的覆盖质量），不是用例设计技术；接入工具时单独评估 |
| Performance / Load Testing | 是非功能测试类型 / 测试层选择，不是用例设计技术；route 给 `testing-strategy` |
| BDD Gherkin（Given/When/Then） | 我们用「前置 / 步骤 / 预期」三列，等价但不强求 Gherkin 关键字 |
