---
name: requirement-intent
description: 产品需求沟通 / 需求讨论完善 / 产品需求澄清 / 澄清 PRD / 需求对齐会 / 需求讨论会后整理 / 用户故事 / 验收标准 / 产品意图 / 需求不清楚 / clarify requirement / requirement discussion —— 交付物是「这需求到底要什么」：意图、目标用户、成功标准、用户路径、意图级非目标、功能点验收点、拷问问题池、决策关闭 backlog。Skip 要的是现状清单（现有流程·页面·API·数据·运营规则怎么运作、已有什么能力、缺口在哪）→ requirement-baseline；要的是变更边界（in/out、受影响对象、依赖、版本切片、appetite）→ requirement-scope；要成文 PRD → requirement-doc-writer；一问一答拷问 → grill-me；多阶段交付计划 → product-rd-workflow。
---

# Requirement Intent

把不清晰的产品意图变成可关闭的决策：已知/未知、用户路径、意图级非目标、可观察验收点、拷问问题池。需求对齐会后整理、缺哪些信息、写 PRD 前补齐目标用户与约束时进入本技能。

## 硬约束（先读，全程适用）

1. **证据不足不得写成事实。** 每条结论标来源；缺来源的事实交 `requirement-baseline`，不自行推断。
2. **描述性证据不决定产品承诺。** 代码、数据、配置只补事实，不裁决产品口径。
3. **关闭表只补自己那部分。** 唯一 canonical 是 `requirement-doc-writer/references/requirement-closure-contract.md`。本技能只补用户价值、问题、方案关联、产品口径、路径和验收字段，逐字段记录 closure_method/source、decision_authority 和所需 decision_evidence，**只提出行状态候选，不得把整行设为 `closed`**。
4. **自动填写的边界。** 仅凭可引用的已批准 policy，才可以 `bounded-agent-policy` 为 decision_authority 批量确定单个 `low-risk-default` 非核心字段；没有该 policy 时保持 open 或转 `human-decision`。不得升级为核心承诺。
5. **PRD Ready 不由本技能判。** 完整 PRD 正文只有在完整 lifecycle 判定 `PRD Ready` 后才转 `requirement-doc-writer`；未关闭时只交接关闭表和下一动作。
6. **「非目标」在这里是意图级**——本轮不追求的目标、容易被误解成目标而排除的诉求。变更级的「本轮不改哪些对象」属 `requirement-scope`。同理「验收」在这里是功能点的 pass/fail 条件，不是切片验收边界。

### 安全 4 问（命中即阻断）

需求涉及身份、计费、配额、租户/用户隔离、权限、删除、覆盖时，澄清记录必须逐项包含安全 4 问的答案（无命中则显式记"无安全敏感输入"）。命中上述任一项时，必须先读取 `requirement-doc-writer/references/security-four-questions.md`（问题本体 canonical，含本技能的落点细则）再作答，并在产物中写明所依据的 canonical 文件名 `security-four-questions.md`（实测：要求一段**固定字样**的旧写法命中率仅 20.5%，而逐项作答与写明来源文件分别可达 82% / 59%——本仓无法机械校验运行时产物，故只要求可核的实质，不要求不可核的字面戳）；凭记忆或转述作答、未写明来源、或命中后仍记"无命中"，均为违规。**读取不可得时（本会话无文件读取工具 / 文件缺失 / 读取失败）走这条路径，不得声称已读**：改写 `依据: 不可得(<原因>)`；按常驻反射尽力作答、本节标 `interim` 并写出解除方式，缺口连同风险标签交 `feature-risk-router`，由风险 owner 决定是否接受**推迟**——接受的是推迟、不是关闭：本节转正式关闭仍须真实读取 canonical 后逐项重答；agent 与需求提出方均不得自行判为已关闭。always-on 常驻反射见 agent-context/session-start.md「设计期安全 4 问」；本节只定义产物落点与交接。

命中后把风险标签与 gate 选择转给 `feature-risk-router`；进入研发交付时转 `product-rd-workflow`。

## 产出

| 模块 | 内容 |
| --- | --- |
| 已知 | 已确认的用户、场景、目标、约束、事实来源 |
| 未知 | 阻塞问题、需确认对象、默认假设 |
| 用户路径 | 触发入口、主路径、异常/取消/回退路径 |
| 非目标（意图级） | 本轮不追求的目标、容易被误解成目标而排除的诉求 |
| 验收点 | 可观察的通过/失败条件，不复述功能名 |
| 讨论闭环 | 沟通记录、争议点、已决策、未决项、下一轮问题 |
| 拷问问题池 | 可用于 `grill-me` 的一问一答压力测试问题、推荐默认值、错判代价 |
| 需求点关闭表 | 按共享契约记录合理性、产品口径、验收和待关闭项 |

## Workflow

1. 定位意图：记录用户目标、目标用户、触发场景和成功标准。
2. 检查需求合理性：逐项判断问题是否真实、方案是否直接关联问题、是否有替代或更小方案、核心价值能否闭环、范围投入是否经济、失败代价是否可接受。
3. 主动补全：按共享契约完成一轮有界取证 pass，再升级权威冲突、额外授权和人类决策项。
4. 拆用户路径：主路径、分支、异常、退出和撤销路径。
5. 分离事实与假设：每条结论标注来源；缺来源的事实交 `requirement-baseline`。
6. 明确意图级非目标并整理讨论：分开记录争议、已决、未决和下一动作。
7. 更新 `需求点关闭表`（按硬约束 3、4）：只知道 owner 而没有明确决定记录时保持 open/blocked。
8. 最小化追问：批量处理可自动项后，只提出一组仍阻塞的 `human-decision` 问题；每题给候选方案、推荐、代价、accountable owner 和受影响 requirement/P0。Agent 维护完整机器账本，产品人员无需逐格填写。需要一问一答压力测试时转 `grill-me`。
9. 写验收点并交接：每个功能点至少一个可观察 pass/fail 条件；安全命中项补负向验收；把完整关闭表交回 lifecycle 或下一窄 owner。

## 不用本技能，改用谁

- 要现状清单（现在怎么运作、有什么能力、缺口在哪）→ `requirement-baseline`。
- 要变更边界（in/out、受影响对象、依赖、切片、appetite）→ `requirement-scope`。
- 把结论沉淀成 PRD / 需求文档正文 → `requirement-doc-writer`（且须 lifecycle 已判 `PRD Ready`）。
- 一问一答压力测试、只追问一个阻塞决策 → `grill-me`；本技能只生成问题池并整理拷问后的结论。
- 技术实现计划、研发排期、跨阶段生命周期 → `product-rd-workflow`。
- 结构化测试用例 / Feishu TC → `test-artifact-management`；测试层与验证策略 → `testing-strategy`。
- 风险定级、灰度、必跑 gate → `feature-risk-router`。

## 完成标准

逐条可核，缺一条即为 `interim` 而非完成：

- 产品意图、目标用户、成功标准三者都有明确记录，或明确列为 `human-decision` 待关闭项。
- 每个功能点至少有一个**可观察的** pass/fail 验收条件（不是「体验更好」这类不可判定表述）。
- 已知与未知分开；每条已知有来源，每条未知有 accountable owner。
- 用户路径含异常/取消/回退，不只主路径。
- 关闭表没有任何整行被设为 `closed`；自动填写项都能指出所依据的已批准 policy。
- 安全 4 问：记了「无命中」，或四项逐条答案 + 写明所依据的 canonical 文件名；读取不可得时写了 `不可得(<原因>)` 并把本节标 interim。

## 输出模板

```text
需求澄清结果
- 产品意图：
- 目标用户 / 场景：
- 已知事实（含来源）：
- 未知 / 待确认（含 owner）：
- 用户路径：
- 非目标（意图级）：
- 沟通记录 / 争议点：
- 已决策 / 未决项：
- 下一轮问题 / 拷问问题池：
- 需求合理性：问题真实性 / 方案关联 / 更小方案 / 价值闭环 / 范围经济性 / 失败代价
- 需求点关闭表：
- 验收点：
- 安全 4 问：无命中 / <逐项作答四项>
- 依据来源：<读到了写 `security-four-questions.md`；没读到写 `不可得(<原因>)` 并把本节标 interim。不得留空>
- 下一步 owner：
```
