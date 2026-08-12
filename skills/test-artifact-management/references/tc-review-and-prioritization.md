# 用例评审与优先级评定

写完一批 TC 之后 / release 之前的两道质量门：
- §1 **评审**：写完 TC 怎么知道写好了（review checklist）
- §2 **定优先级**：P0 / P1 / P2 怎么从经验判断改成可执行方法

不替代 `classical-test-design-techniques.md` / `source-to-case-workflows.md` — 那两份是"怎么写"，这份是"写完之后"。

## 外部来源（按名引用）

- **IEEE 829** / **ISO/IEC/IEEE 29119-3:2021** test documentation lineage — TC 应含字段
- **ISTQB CTFL** v4 syllabus — test documentation + 评审术语
- **George Dinwiddie**（2009）— Three Amigos meeting origin
- **Lisa Crispin & Janet Gregory** — *Agile Testing* / *More Agile Testing*（Power of Three / 全团队协作）
- **Hans Schaefer** — *Risk Based Testing*（实务派 risk-based testing）
- **Erik van Veenendaal** / **TMAP** — Product Risk Analysis（PRISMA 实际归属）
- **ISTQB Advanced Test Manager** syllabus — Risk-Based Testing 章节
- **James Bach & Michael Bolton** — Heuristic Test Strategy Model（HTSM quality criteria 作打分补充维度）

---

## §1 TC Review Checklist

### 1.1 谁 review

**第二人原则**：自己写自己看不算 review。每批 TC 必须有 1+ 第二人过：
- **同伴 review**（任一：dev / tester / PM）：必须
- **PO review**：当 TC 来自需求文档（Source A），PO 必须扫一遍确认"这就是我要的"
- **架构 review**：当 TC 涉及钱 / 权限 / 数据一致性 / 跨服务关键流程

### 1.2 七要素 review checklist

（条目源自 IEEE 829 / ISO 29119-3 test documentation 字段 + ISTQB CTFL 静态评审术语 + 业内通用经验。review 时按 7 项打勾，任一不过 → 改完再 review。）

1. **意图明确**：1 句话能说出"这条测的是什么"。说不出 → fail
2. **操作可复现**：另一个人按步骤跑得同样结果，不依赖测者经验
3. **预期可观察**：预期结果是外部可见输出（return value / DB 行 / 视觉变化 / 日志 / metric），不是"程序应正常运行"
4. **数据明确**：前置条件枚举具体数据（"用户 A 已登录，角色 = admin" 而非"用户登录"）
5. **隔离性**：TC 不依赖其他 TC 的执行顺序 / 残留状态
6. **覆盖必要边界**：相邻有 boundary / negative / error 同伴 TC，不能 happy-only
7. **可维护**：模块拆得清楚，重命名 / 重构后只改一处

### 1.3 Three Amigos 轻量评审（Dinwiddie 2009 + Crispin/Gregory "Power of Three"）

**理想**：PM（business）+ dev + tester 围一张桌子 / 视频会，每条 TC 念出来，三人都点头 → 入库。注意这是**轻量评审**用途，不是 `source-to-case-workflows.md` 故意不借鉴段所指的"全套 Spec Workshop"（那是产品过程，归 `product-rd-workflow`）。

**退化**（凑不齐三人时）：tester 写完 → dev review（"按这条 TC 我开发吗？"）+ PM 异步 review（"这就是我要的？"）。两个独立角色至少各过一次。

### 1.4 Review 流转

- 不通过 → 评论留 Bitable 信息流转：`[reviewer 日期] review 不通过：操作步骤第 3 步歧义，请明确 X 值`
- 改完作者主动 ping reviewer，不要让 reviewer 反复追
- 通过 → reviewer 在 信息流转 留 `[reviewer 日期] review 通过`
- **review 状态与执行状态分开追踪**：信息流转里用 `[作者 日期] review pending @reviewer 期待 X 月 Y 日前回复` 让 release 计划能区分"未 review"和"未执行"，避免 review 卡周级别时也混进"已就绪"统计

---

## §2 Risk-Based Prioritization

SKILL.md 现状 P0 / P1 / P2 是经验判断（"blocking / important / nice"）。本节给可执行方法。

### 2.1 风险公式（最通用）

**Risk = Probability × Impact**（业内 30 年共识，ISTQB / ISO 29119 同源）

**Probability**（发生概率，1-5 分）：
- 1 = 罕见（新代码 + 简单逻辑 + 测试覆盖好）
- 3 = 中等（已上线但近期改过 / 跨服务调用 / 复杂条件）
- 5 = 高频（用户每天碰 / 历史多次 incident / 复杂分支 / 时间敏感）

**Impact**（影响，1-5 分）：
- 1 = 用户体感差但不丢数据 / 可解释
- 3 = 部分用户阻塞 / 单点数据错（可改 / 可补）
- 5 = 全量阻塞 / 钱算错 / 数据丢失 / 安全 / 合规事故

**得分 → 优先级**：

| Score | 优先级 |
| --- | --- |
| 15-25 | **P0**（必须 release 前过）|
| 6-14 | **P1**（应当 release 前过；可豁免须 owner + 理由）|
| 1-5 | **P2**（可 post-release）|

> 分段是本团队 release-gate 校准（非公认标准）；跑 1-2 个 release 后按 incident 复盘调阈值。

### 2.2 内部三因子产品风险 shortcut（启发自 PRISMA / TMAP）

PRISMA / TMAP 的产品风险分析（van Veenendaal）比较深；这里取一个轻量三因子作业内日常评分用：

- **业务关键性**：用户多频 / 钱 / 监管 → 高
- **技术复杂度**：新框架 / 多线程 / 重写 / cross-cutting → 高
- **变更程度**：本次改了多少 / 是否影响 hot path → 高

三维都高 → P0；任一极高 → P1；都低 → P2。和 2.1 公式互校（不一致时讨论再定）。

**当 Prob × Impact 评分太窄**（典型：架构稳定性 / 可观察性 / 可维护性 / 可恢复性 这种 horizontal 风险）：用 HTSM (Bach/Bolton) 的 quality criteria 作 prompt 补维度（**完整列表见 Bach HTSM PDF；以下是常用子集**）— capability / reliability / usability / charisma / security / scalability / performance / installability / compatibility / development（含 supportability / testability / maintainability / portability / localizability）。

### 2.3 触发升级的规则

默认按公式打分；以下情况无论得分都升级：

| 触发 | 处理 |
| --- | --- |
| 历史上同模块出过 P0 incident | 该模块全部 TC 在公式得分基础上 + 1 级 |
| 监管 / 合规要求强制覆盖 | 强制 P0 |
| `[回归]` TC（Source E） | 自动 P0（SKILL.md 已规则） |
| `[soap-opera]` / `[charter]` | 按真实业务风险评，**不强制 P0**（classical-techniques.md 已规则） |

### 2.4 例

某报告导出模块 TC list：
```
TC-EXPORT-001 报告导出请求成功
  Prob 5（每天用） × Impact 5（导出失败 = 主流程断） = 25 → P0

TC-AUTH-007 token 过期自动续期幂等
  Prob 3（每天少量碰） × Impact 5（重复发起验证 / session 错位） = 15 → P0

TC-DOC-020 文档预览页 footer 排版
  Prob 5（每天看） × Impact 1（不丢数据） = 5 → P2
```

---

## §3 整体落地

| 阶段 | 谁 | 做 |
| --- | --- | --- |
| 写 TC 时 | 作者 | 按 §2 给每条打分评 P0 / P1 / P2；分数写 Bitable 信息流转 `[作者 日期] risk=4×4=16 → P0` |
| 提 review 时 | 作者 | 按 §1.2 七要素自查；自查不过别提 review |
| Review 时 | reviewer | 按 §1.2 七要素扫；不过留 信息流转 |
| Review 通过 | reviewer | 信息流转留 `[reviewer 日期] review 通过`，状态可改"未测试" |
| Release 决策 | 发布人 | P0 全过 才能 release；P1 可豁免须有 owner + 理由；P2 post-release |

---

## 故意不借鉴

| 方法 | 原因 |
| --- | --- |
| ISO 29119 完整 risk catalog（含资源 / 进度 / 合规等 ~20 维） | 太重；产品风险三维够用 |
| FMEA RPN（Severity × Occurrence × Detection） | 制造业用法，detection 在软件里难量化；用 Prob × Impact 二维 |
| Test prioritization regression algorithms（如 history-based ML 排序） | 是 CI 自动化层面的题，归 `testing-strategy` / CI 工具 |
| TestRail-style approval state machine | 我们 Bitable `信息流转` append-only + 状态 字段已等价 |
| Heuristic-only review（凭感觉过） | 不可执行；用 §1.2 七要素作清单 |
