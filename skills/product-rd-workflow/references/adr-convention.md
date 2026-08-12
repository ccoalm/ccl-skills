# Architecture Decision Records (ADR)

记一个有日期、内容不可变（仅 Status/linkage metadata 可更新，外加 append-only 的 as-built 校正节，见 §5.3）、可追溯的**架构决定**。SKILL.md 是 reusable agent behavior；ADR 是 per-decision artifact — 两个不重叠。

## 外部来源

- **Michael Nygard**, "Documenting Architecture Decisions" (cognitect.com/blog, Nov 15 2011) — popularized 当代 ADR 格式（决策记录实践本身比 2011 早）
- **adr.github.io** — 社区标准格式与示例
- **ThoughtWorks Tech Radar** — "Lightweight Architecture Decision Records"（Trial Nov 2016；Adopt Nov 2017+）

---

## §1 WHEN — 何时写 ADR

**触发**（命中任一即应写 — 都用可观察特征不靠"未来感觉"）：
- **跨服务 / 跨团队 contract**：API 形状 / event schema / auth 流变更
- **选型 lock-in**：DB / framework / cloud / 消息队列 — 切换成本 > 1 sprint
- **不可逆 / 6 个月以上承诺**：数据 schema 大变；公开 API 上线后改要做 deprecation 周期
- **存在被明确拒绝的备选**：选 A 不选 B 且 B 不是 trivial naive 选项
- **非显然 trade-off**：决策有副作用 / 代价，且代价不在 code/commit 里能恢复出
- **多团队 sign-off**：决定需要跨团队同意才能推进
- **迁移 / 废弃策略**：旧系统下线节奏；新旧系统并行窗口

**不触发**（明确**不**写 ADR）：
- 变量 / 文件 / 函数命名
- 单文件 refactor / bug fix
- 单模块内部实现细节（不影响外部 contract）
- 可逆 config 调整（feature flag 切换 / 阈值 tune — 但若改默认值影响 client-visible 行为 / SLO → 触发）

**边界 case 判定**：
- "加缓存层" — 若改变 consistency / failure mode / lock-in → 触发；纯加速无语义变化 → 不触发
- "改默认 timeout" — 若改 external contract / SLO / client 行为 → 触发；只是本地可逆 tuning → 不触发

---

## §2 WHERE — 放哪

按决定的影响范围决定 ADR 放哪：

- **服务内决定**（不影响外部 contract）：`<service-root>/docs/adr/NNNN-<slug>.md`（服务自己仓 / monorepo 服务子目录）
- **平台 / 跨服务决定**（多服务 / 全栈共用）：组织级共享位置 — 单独 ADR 仓库 OR `<monorepo>/docs/architecture/adr/` OR 共享 wiki section
- **影响 N 个服务的 cross-cutting 决定**：放共享位置，每个被影响服务 README / ARCHITECTURE.md 反向引用 ADR 号
- **不放 `_local/`**：那是私人 scratch，团队看不到，违背 ADR 目的

---

## §3 WHAT — 最小字段

**Nygard 原始 5 字段**（template 核心）：

| 字段 | 内容 | 必填 |
|---|---|---|
| **Title** | 短 noun phrase（`Use PostgreSQL for primary OLTP store`，不是问题）| ✅ |
| **Status** | `Proposed` / `Accepted` / `Rejected` / `Deferred` / `Deprecated` / `Superseded by NNNN` | ✅ |
| **Context** | 当时情境 / 约束 / 要解决的问题 | ✅ |
| **Decision** | 做了什么（1 short paragraph，1-3 句；composite 决策可写 split："choose A for X, B for Y, sharing tooling Z"）| ✅ |
| **Consequences** | 正面 + 负面 outcome；**2-5 bullets**，写已接受的代价 / 后果（不是 PROs/CONs 全比较）| ✅ |

**本 skill 加的 local 字段**（推荐，方便检索 / 治理）：

| 字段 | 内容 | 必填 |
|---|---|---|
| **Number** | 顺序编号 `0001`、`0002`...（Nygard 操作约定，技术上非 template 字段）| ✅ |
| **Date** | YYYY-MM-DD 决定生效日期 | 推荐 |
| **Author / Decider** | 谁拍板（多人 sign-off 列全）| 推荐 |
| **Related ADRs** | 引用 / 取代 / 被取代的 NNNN | 推荐 |

**反模式**：写 "5 个备选方案 + 全 trade-off matrix" — 那属 spike / RFC 阶段产物。若 analysis 体量大，**分离 spike doc + ADR**（spike 记 evaluation，ADR 记最终决定 + 选择理由摘要 + consequences）。

**与 MADR（完整 PROs/CONs/decision-makers 模板）的取舍**：MADR 更结构化，本 skill 默认采 Nygard 精简版以降门槛；想要 MADR 详细度的团队可选用 — 关键是 5 字段全在。

---

## §4 HOW MANY — 数量级 sanity check（本团队启发，非行业标准）

| 项目年级数量 | 信号 — **investigate, do not optimize 到这个数** |
|---|---|
| 5-20 / 年 | 本团队认为中型 system 健康区间 |
| > 50 / 年 | WHEN 标准可能太松；但**例外**：迁移/重构密集年、平台拆分、incident-driven arch work 可合理高 |
| < 5 / 年 持续 | WHEN 标准可能太严；但**例外**：maintenance-only 系统 / 早期 single-engineer 项目可合理低 |
| 0 / 6 个月 | maintenance-only 是 OK；活跃项目则查 "谁该写没写" |

ADR 是**项目级别**（每个 repo / system 一套），不是 PR 级别。**别把数量当 KPI 凑** — 凑出来的 ADR 是 ceremony，等于淹没真重要的。

---

## §5 操作集成 — 让 ADR 真触发

写出来没用进流程就是死信。集成点：

### 5.1 Code review block — trigger checklist
Reviewer 见以下任一即 block "需先有 ADR"：
- 新加 datastore / cache / queue / framework / cloud provider
- 公开 API / event schema / auth flow 变更
- 数据 schema migration 或字段 deprecation
- 不可逆 data model 改动
- 跨团队 sign-off 决定
- 长期 config 默认值变更影响 client-visible 行为 / SLO

implementation PR 不能在缺 ADR 时 merge；先开 ADR PR → review pass → ADR Accepted → implementation PR 引用 ADR number。

### 5.2 Architecture review
设计评审 input 必含相关 ADR（既往的 + 新提议的）；ADR draft 走 architect / tech lead review pass 再变 Accepted。

### 5.3 Status 生命周期（Superseding / Rejected / As-built）
旧 ADR 不删，标 `Status: Superseded by NNNN`。新 ADR（superseder）必须：
1. **Link back**：引用被替代的 ADR number
2. **解释变化**：什么改变了 / 为什么旧决定不再适用（context drift / 新约束 / 旧方案失败）
3. **分类**：`Full supersede`（旧 ADR 完全废）vs `Partial supersede`（旧 ADR 部分仍生效，明确哪部分）
4. **同 PR 改两边**：superseder 创建 + 旧 ADR Status 修改在**同一个 PR** 里完成（避免半 superseded 状态）

**Rejected / Deferred**：被评审推翻的设计标 `Rejected`，搁置的标 `Deferred`，被拆分的把拆出部分链接到新 ADR — 原文一律保留、不删不改写。"为什么不做"的论证链和"为什么做"同样有价值，删掉它就等着下个人把同一方案再提一遍。

**As-built 校正**：`Accepted` 后实现与设计出现事实性偏离时，在文末**追加**带日期的 `As-built` 校正节（append-only；原 Context/Decision 文本不改写）— 按实现事实校正比装作设计一次到位诚实。边界：as-built 只**记录事实**，不是偏离的批准通道，也从不关闭风险——**实质性偏离**（auth/权限、数据保留/丢失语义、超时/失败模式、对外契约等改变决策实质的）**无论何时发现**都触发决策 owner 评审：合并前发现的，评审通过（superseding ADR 或显式决策记录）前 block 合并；合并后/线上发现的，追加 as-built 记录事实的同时必须走缓解/回滚或 superseding 决策，不能以"已如实记录"当作处置完毕。实现者不能靠追加 as-built 节自行放行。偏离大到推翻决策本身时，写 superseding ADR 而不是校正节。

### 5.4 Onboarding
新人入项目先读 `docs/adr/` 全集（按 number 顺序），了解"为什么是现在这样"。

---

## §6 与 ccl-skills 的区别（避免混淆）

| 维度 | SKILL.md | ADR |
|---|---|---|
| 属性 | reusable agent behavior + routing 规则 | per-decision artifact，dated，immutable |
| 时间 | 持续演进（rewrite OK）| 一次决定一份，新决定写新 ADR（用 Status: Superseded 标旧的）|
| 范围 | shared 跨项目 | per-project |
| 触发 | 用户请求 trigger 匹配 | 架构 review 流程 |

ccl-skills 仓内**不**放项目 ADR。ccl-skills skill 规则变更走 commit message + review/challenge 记录 + 必要的 reference 文档说明 — 这些是**shared skill repo 的 change provenance**，不是 ADR log，也**不替代每个项目自己的 ADR**。

---

## §7 故意不借鉴（清单）

| 概念 | 原因 |
|---|---|
| ADR 模板生成器（如 `adr-tools` CLI，~5.4k stars） | 本 skill 默认不要求；团队可选用 — 手写 Markdown 是最低依赖路径 |
| MADR 全模板默认采用 | MADR 本身 lean+structured 设计良好（含 options/pros/cons + decision-makers metadata）；本 skill 选 Nygard 精简版以降门槛，团队若需 MADR 详细度可改用 |
| Decision matrix scoring 进 ADR | scoring 适合 spike / RFC 阶段；ADR 记"决定 + 已接受 trade-off"，不重复 RFC 评分 |
