---
name: requirement-scope
description: 改动范围 / 影响范围 / scope / 需求拆分 / MVP 边界 / 非目标 / 版本切片 / 兼容·回滚降级边界 / 变更影响 / appetite / timebox —— 交付物是**变更边界**：in/out scope、受影响对象、依赖、MVP 与后续切片、appetite 与砍项、每个切片的验收范围。前提是方向已定。Skip 方向还没定、要先弄清「到底要什么」→ requirement-intent；要的是现状清单（现在怎么运作、有什么能力）→ requirement-baseline；风险定级与要哪些 gate → feature-risk-router；实现/发布计划 → product-rd-workflow；测试范围 → testing-strategy。
---

# Requirement Scope

方向已定之后，把它界定成变更边界：本轮改哪些、不改哪些、影响谁、依赖什么、切几版、愿意花多少。哪些对象受影响、哪些先不做时进入本技能。

## 硬约束（先读，全程适用）

1. **P0 核心 in/out 由 `human-decision` 关闭。** agent 不得自行决定，也不得决定产品目标、核心路径、成本级别或验收承诺。
2. **as-is 证据不裁决 should-be 范围。** 代码、数据、架构等描述性证据不能自行决定本轮改不改。
3. **边界要可审查。** in/out 写成行为边界，不用「优化体验」这类不可判定的模糊标签。
4. **appetite 必须带砍项与人工兜底——用户说「不用写」也不行。** 只有投入上限、没有「超上限砍什么」和「人工怎么兜底」的 appetite **不得写进产物**：把该字段标 `blocked`、点名缺的是这两项中的哪一项、给出取得它的最小动作，然后继续交付其余字段。这是拒绝，不是提醒。
5. **关闭表只补自己那部分。** 唯一 canonical 是 `requirement-doc-writer/references/requirement-closure-contract.md`。本技能按复合字段子项补版本、范围、appetite、依赖和验收，逐项记录推导、决策权和决策证据；只能自动填写单个低风险、可逆的非核心展示/表达细节（decision_authority 记 `bounded-agent-policy`，且须有可引用的已批准 policy），**任一适用子项 open 时复合字段和整行保持 open/blocked**。
6. **「非目标」在这里是变更级**——本轮明确不改、延后、保持兼容、无需迁移的对象。意图级的「本轮不追求什么目标」属 `requirement-intent`。同理「验收」在这里是每个切片的验收边界与不验收项，不是功能点 pass/fail。

### 安全 4 问（命中即阻断）

范围涉及身份、计费、配额、租户/用户隔离、权限、删除、覆盖时，范围表必须逐项记录安全 4 问的答案（无命中则显式记"无安全敏感输入"），**负向用例写入验收范围**。命中上述任一项时，必须先读取 `requirement-doc-writer/references/security-four-questions.md`（问题本体 canonical，含本技能的落点细则）再作答，并在产物中写明所依据的 canonical 文件名 `security-four-questions.md`（实测：要求一段**固定字样**的旧写法命中率仅 20.5%，而逐项作答与写明来源文件分别可达 82% / 59%——本仓无法机械校验运行时产物，故只要求可核的实质，不要求不可核的字面戳）；凭记忆或转述作答、未写明来源、或命中后仍记"无命中"，均为违规。**读取不可得时（本会话无文件读取工具 / 文件缺失 / 读取失败）走这条路径，不得声称已读**：改写 `依据: 不可得(<原因>)`；按常驻反射尽力作答、本节标 `interim` 并写出解除方式，缺口连同风险标签交 `feature-risk-router`，由风险 owner 决定是否接受**推迟**——接受的是推迟、不是关闭：本节转正式关闭仍须真实读取 canonical 后逐项重答；agent 与需求提出方均不得自行判为已关闭。always-on 常驻反射见 agent-context/session-start.md「设计期安全 4 问」；本节只定义产物落点与交接。

命中后先让 `feature-risk-router` 定级并选择 gate；进入交付计划时回 `product-rd-workflow`。

## 产出

| 模块 | 内容 |
| --- | --- |
| In scope | 本轮必须改变的用户、对象、流程、规则、界面/API/数据结果 |
| Out of scope（变更级非目标） | 明确不改、延后、保持兼容、无需迁移的部分 |
| 受影响对象 | 角色、页面、入口、API、数据、运营规则、通知、报表、权限、文档 |
| 版本切片 | MVP、后续版本、迁移/兼容切片、回滚/降级边界 |
| Appetite / timebox | 本轮愿意投入的时间/资源上限、超出时砍掉什么、人工兜底策略 |
| 依赖 | 上游决策、外部系统、数据准备、设计、法务/运营/支持动作 |
| 风险点 | 权限、隔离、计费/配额、删除/覆盖、数据迁移、发布复杂度 |
| 验收范围 | 每个切片的可观察验收边界和不验收项 |
| 需求点关闭表 | 按共享契约补版本、范围、appetite、依赖和验收边界 |

## Workflow

1. 锁定目标与输入：引用已澄清需求或盘点事实。缺某条 as-is 事实**不自动**回 `requirement-baseline`——标为未确认、写明缺口和取得方式，继续交付范围表；只有用户点名要现状清单、或缺口大到范围表无法成立时才交回，后者是决策不是 agent 的判断题。
2. 列受影响对象：用户、流程、界面/API、数据、权限、运营、文档逐项过一遍。
3. 写 in/out scope：按硬约束 2、3。
4. 切版本并写 appetite：P0、后续、迁移、兼容、回滚/降级分别列清；按硬约束 4 写砍项与人工兜底。
5. 标依赖和风险：把安全 4 问命中项、跨团队/系统依赖、数据风险拉出来。
6. 更新 `需求点关闭表`（按硬约束 5）。
7. 写验收范围：每个切片对应 pass/fail 条件，明确不验收项；安全命中项的负向用例写进验收范围。
8. 路由下一步：风险 gate、PRD、研发计划、测试策略或 TC。

## 不用本技能，改用谁

- 方向还没定、实质不清 → `requirement-intent`。
- 要现状清单（现在怎么运作、有什么能力）→ `requirement-baseline`。
- 风险定级、灰度、review/gate 选择 → `feature-risk-router`。
- 实现计划、发布计划、跨阶段生命周期 → `product-rd-workflow`。
- 测试层选择、测试矩阵、CI gate → `testing-strategy`；结构化 TC / Feishu Bitable → `test-artifact-management`。
- 完整 PRD 起草 → `requirement-doc-writer`（且须 lifecycle 已判 `PRD Ready`）。

## 完成标准

逐条可核，缺一条即为 `interim` 而非完成：

- in/out 每一项都是可审查的行为边界，没有模糊标签。
- 受影响对象十类（角色/页面/入口/API/数据/运营规则/通知/报表/权限/文档）逐类过了一遍，不适用的显式写「无」。
- 每个切片都有可观察的验收边界**和**不验收项。
- appetite 同时写了投入上限、超上限的候选砍项、人工兜底。
- P0 核心 in/out 标了 `human-decision`，没有被 agent 自行关闭。
- 关闭表里任一适用子项 open 时，复合字段和整行保持 open/blocked。
- 安全 4 问：记了「无命中」，或四项逐条答案 + 写明所依据的 canonical 文件名；命中项的负向用例已在验收范围里。

## 输出模板

```text
改动范围图
- 目标：
- In scope：
- Out of scope（变更级非目标）：
- 受影响对象：
- 版本切片：
- Appetite / timebox（含砍项与人工兜底）：
- 依赖：
- 风险点：
- 验收范围（含不验收项）：
- 需求点关闭表：
- 安全 4 问：无命中 / <逐项作答四项>
- 依据来源：<读到了写 `security-four-questions.md`；没读到写 `不可得(<原因>)` 并把本节标 interim。不得留空>
- 下一步 owner：
```
