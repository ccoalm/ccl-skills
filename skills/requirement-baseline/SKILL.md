---
name: requirement-baseline
description: 现状盘点 / 当前能力梳理 / 现有流程、页面、API、数据、运营规则盘点 / as-is audit / current state inventory —— 交付物是**现状清单本身**：现在怎么运作、已有哪些能力与例外、事实来源与 freshness、缺口和冲突，含按 commit 固定的代码现状取证。Skip 要的是意图、用户故事、验收标准、问题池（「到底要什么」）→ requirement-intent；要的是本轮改哪些、不改哪些、切几版（变更边界）→ requirement-scope；问线上是否已启用 → platform-observability；代码/项目质量评估 → product-rd-workflow；bug 根因 → defect-diagnosis。
---

# Requirement Baseline

把「现在到底怎么运作」变成一份有来源、有 freshness、缺口显式的 as-is 清单。改需求之前先弄清现状、已有能力是什么、缺口在哪里时进入本技能。

## 硬约束（先读，全程适用）

1. **不下产品决策。** 只描述现状，不判断「应该怎么改」。代码、数据、架构等描述性证据**不裁决 should-be**。
2. **三态判定，权威 baseline 不得记 N/A。** 用共享契约的 current-state 三态；新鲜权威 baseline 记 `satisfied-by-authoritative-baseline`。
3. **`not-applicable` 的全部前置条件**：仅当是有边界的存在性检查、**且**能证明净新增、**且**不触及既有流程、权限、数据、API、规则、迁移、兼容或旧版本行为时才可判。任一条不成立即不得判。
4. **未查到 ≠ 不存在。** 正常取证后仍未查到的能力、接口、数据、权限、审核流或模型能力，不得写成已确定字段；对应 requirement 行不得设为 `closed`。
5. **关闭表只补自己那部分。** 唯一 canonical 是 `requirement-doc-writer/references/requirement-closure-contract.md`。本技能以 `evidence-derived` 只填 as-is 描述性事实，或有效已批准规范性来源授权范围内的字段；记录 decision_authority、source、推导、冲突处置和重开条件，**只提出行状态候选，不得把整行设为 `closed`**。

### 安全 4 问（命中即阻断）

现状涉及身份、计费、配额、租户/用户隔离、权限、删除、覆盖时，盘点必须逐项记录安全 4 问的现状答案（无命中则显式记"无安全敏感输入"）。命中上述任一项时，必须先读取 `requirement-doc-writer/references/security-four-questions.md`（问题本体与现状（as-is）应用细则 canonical）再作答，并在产物中写明所依据的 canonical 文件名 `security-four-questions.md`（实测：要求一段**固定字样**的旧写法命中率仅 20.5%，而逐项作答与写明来源文件分别可达 82% / 59%——本仓无法机械校验运行时产物，故只要求可核的实质，不要求不可核的字面戳）；凭记忆或转述作答、未写明来源、或命中后仍记"无命中"，均为违规。**读取不可得时（本会话无文件读取工具 / 文件缺失 / 读取失败）走这条路径，不得声称已读**：改写 `依据: 不可得(<原因>)`；按常驻反射尽力作答、本节标 `interim` 并写出解除方式，缺口连同风险标签交 `feature-risk-router`，由风险 owner 决定是否接受**推迟**——接受的是推迟、不是关闭：本节转正式关闭仍须真实读取 canonical 后逐项重答；agent 与需求提出方均不得自行判为已关闭。always-on 常驻反射见 agent-context/session-start.md「设计期安全 4 问」；本节只定义产物落点与交接。

命中后把风险标签和 gate 选择交给 `feature-risk-router`；需要研发改动时交给 `product-rd-workflow`。

## 产出

| 模块 | 内容 |
| --- | --- |
| 事实来源 | 文档、界面、代码、配置、数据样例、运营规则、访谈记录；标注新旧和可信度 |
| 用户路径 | 用户入口、步骤、状态变化、异常/回退路径 |
| 系统路径 | 页面/API/服务/数据/规则之间的链路；不确定处标注 |
| 已有能力 | 已可用能力、约束、默认行为、例外规则 |
| 缺口 | 与目标或问题陈述不匹配的空白、冲突、重复能力 |
| 风险/不确定 | 事实不足、过期来源、权限/数据/删除/覆盖风险 |
| 需求点关闭表 | 按共享契约补事实依据、freshness、冲突和证据缺口 |

## Workflow

1. 判定 current-state 三态：记录存在性检查范围；硬约束 3 的任一前置条件不成立时，不得判 `not-applicable`。
2. 定义盘点对象：流程、页面、API、数据、规则、角色或能力边界。
3. 主动查证：按共享契约完成一轮有界取证 pass；记录已查类别和未查原因，不假设未授权网络、生产或客户数据访问。
4. 核验权威性、freshness 与适用范围：同等级权威产品来源冲突时立即升级；新权威源替代旧非权威源时记录冲突处置和重开条件。
5. 画用户路径和系统路径，列出现有行为、入口、条件、限制和例外。
6. 标缺口、冲突和风险：事实不足、目标不匹配、重复能力、规则矛盾和安全命中项分开写。
7. 更新 `需求点关闭表`（按硬约束 5 的字段权限）。
8. 交接决策 owner：把完整关闭表交回 lifecycle、`requirement-intent`、`requirement-scope`、`defect-diagnosis` 或风险 gate。

## 不用本技能，改用谁

- 要「到底要什么」（意图、用户故事、验收标准、问题池）→ `requirement-intent`。
- 要变更边界（in/out、切片、appetite）→ `requirement-scope`；多阶段交付 → `product-rd-workflow`。
- 问某能力线上是否已启用、要实时指标 → `platform-observability`。**代码里存在 ≠ 已部署启用**。
- 代码质量、架构质量、项目整体评估 → `product-rd-workflow` 分派 stack/architecture/testing/UI owner。
- bug、线上症状、失败测试、根因定位 → `defect-diagnosis`。
- 风险 tag / gate 选择 → `feature-risk-router`。
- 只润色已成文的盘点报告 → `tighten-doc`。

## 完成标准

逐条可核，缺一条即为 `interim` 而非完成：

- 每条现状结论都有具名来源，并标了 freshness 与可信度；无来源的结论标为未确认。
- 已查类别与**未查类别及其原因**都写出来了；未解析来源单独列出。
- 三态判定已记录；若判 `not-applicable`，硬约束 3 的每条前置条件都逐条写明成立依据。
- 缺口、冲突、风险三者分开列，未混进「已有能力」。
- 关闭表只填了 `evidence-derived` 允许的字段，且没有任何整行被设为 `closed`。
- 安全 4 问：记了「无命中」，或四项逐条答案 + 写明所依据的 canonical 文件名；读取不可得时写了 `不可得(<原因>)` 并把本节标 interim。

## 输出模板

```text
现状盘点
- 盘点对象：
- 事实来源：
- 用户路径：
- 系统路径：
- 已有能力：
- 缺口 / 冲突：
- 风险 / 不确定：
- 未解析来源 / 未查类别及原因：
- 需求点关闭表：
- 安全 4 问：无命中 / <逐项作答四项>
- 依据来源：<读到了写 `security-four-questions.md`；没读到写 `不可得(<原因>)` 并把本节标 interim。不得留空>
- 下一步 owner：
```
