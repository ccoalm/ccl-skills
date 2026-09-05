---
name: requirement-doc-writer
description: 写 PRD / 需求文档 / 产品需求文档 / 需求说明 / user story 文档 / 验收标准文档 / 产品需求正文 —— 在 lifecycle 判定 PRD Ready 之后，把已关闭的需求组装成人读的 PRD。Skip 需求实质不清 → requirement-intent；缺现状事实 → requirement-baseline；范围/版本切片/开放决策未关闭 → requirement-scope；Agent/Machine 技术规格 → llm-inference-integration；其评测与测试层 → testing-strategy；只是润色措辞 → tighten-doc；写完 PRD 还要接着往下做的多阶段研发交付·实现/发布计划 → product-rd-workflow。
---

# Requirement Doc Writer

在 lifecycle 判定 `PRD Ready` 之后，把已关闭的需求组装成一份人能读懂、能评审的 PRD。已有澄清、现状盘点与范围关闭材料、所有需求点已有确定口径时进入本技能。

## 硬约束（先读，全程适用）

1. **Ready 是门，不是措辞。** 只消费带 `product`、`version`、`scope`、`closure_table_revision`、`behavior_inventory_revision`、`issued_at` 绑定的 lifecycle-issued `PRD Ready`；绑定不匹配或输入变化时回 lifecycle 重判。任一 P0 行不是 `closed`、或 Ready 条件任一不满足，**不得生成 PRD**。用语本身不决定状态，关闭表语义才是门。
2. **`PRD Not Ready` 时不得输出 PRD 标题、目录、骨架、模板或正文**；WIP、讨论稿、会议材料也不得命名为 PRD。此时只输出产品决策视图并保留机器账本引用，不删底层审计字段。
3. **writer 不改事实。** 不得修改推导、决策权、决策证据或行状态；不得把 `human-decision` 字段改成自动确定；不得设置整行 `closed`。
4. **writer 不做技术设计。** 不得设计 Agent 技术 schema、prompt/model policy、tool contract 或 eval 实现——分别转 `llm-inference-integration`、架构/技术栈 owner 与 `testing-strategy`；writer 只检查命名引用、适用版本、owner 和逐条可追踪性在机器侧是否完整。
5. **不冒充设计 owner。** UI/用户可见产品的 IA、交互、页面状态和原型由 `product-ui-ux-design` 产出或审核，writer 只转写已确认内容。

### 安全 4 问（命中即阻断）

PRD 涉及身份、计费、配额、租户/用户隔离、权限、删除、覆盖时，文档必须有"安全与滥用"小节，逐条写安全 4 问的答案；无命中则显式记"无安全敏感输入"，命中后仍记"无命中"为违规。作答前必须先读取 `references/security-four-questions.md`（问题本体与落点细则 canonical），并在产物中写明所依据的 canonical 文件名 `security-four-questions.md`（实测：要求一段**固定字样**的旧写法命中率仅 20.5%，而逐项作答与写明来源文件分别可达 82% / 59%——本仓无法机械校验运行时产物，故只要求可核的实质，不要求不可核的字面戳）；凭记忆或转述作答、未写明来源、或命中后仍记"无命中"，均为违规。**读取不可得时（本会话无文件读取工具 / 文件缺失 / 读取失败）走这条路径，不得声称已读**：改写 `依据: 不可得(<原因>)`；按常驻反射尽力作答、本节标 `interim` 并写出解除方式，缺口连同风险标签交 `feature-risk-router`，由风险 owner 决定是否接受**推迟**——接受的是推迟、不是关闭：本节转正式关闭仍须真实读取 canonical 后逐项重答；agent 与需求提出方均不得自行判为已关闭。always-on 常驻反射见 agent-context/session-start.md「设计期安全 4 问」；本节只定义产物落点与交接。

命中后 PRD 只完成需求表达；风险标签/gate 交给 `feature-risk-router`，研发生命周期交给 `product-rd-workflow`。

## 产出

生成前读取 `references/requirement-closure-contract.md`。通过门后组装人读 PRD：**先帮读者建立产品认知，再表达已关闭的产品决定、业务规则、边界和验收。** 正文先回答三问：

1. **这是什么产品**：区分目标/非目标用户、触发问题/一般愿望、可观察结果/宣传口号，并写出价值、P0 结果和至少一个明确非目标。只替换产品名仍适用于大量无关产品的句子不合格。
2. **有哪些产品模块或等价结构**：模块按稳定产品能力、业务责任或价值流定义，参与端到端状态或结果变化，并说明作用、输入、输出、上游和下游。不得按路由、菜单、页面或弹窗定义模块；页面必须映射到模块，删掉页面名后说不清产品责任或结果的不是模块。非页面型产品可用能力地图、价值流、角色责任或状态流，但必须说明责任边界、关系和端到端运行，不得虚构模块或页面。
3. **产品如何端到端运行**：主链路，以及关键异常、纠错和回退。

正文推荐按以下顺序组织；可按读者需要调整，但**产品认知必须先于规则明细**：

| 章节 | 内容 |
| --- | --- |
| 产品全景 | 用户、问题、价值、P0 结果、非目标 |
| 模块地图 | 每个产品模块的作用、输入、输出、上下游及模块关系 |
| 核心运行流程 | 端到端主链路、关键状态变化和结果；用户可见/UI 产品还须写流程明细与关键分支 |
| 模块 / 页面体验与原型 | 模块到页面的映射、信息架构、界面关系、页面状态及设计 owner 产出或审核的原型 |
| 关键业务规则 | 已关闭的产品决定、阈值、约束和适用条件 |
| 异常与恢复 | 关键异常、取消、纠错、重试、恢复和回退 |
| 角色 / 安全边界 | 角色、权限、信任边界及安全 4 问命中项 |
| 端到端验收场景 | 按主场景、负向场景、边界场景或能力级组织；不逐条复制机器追踪表 |
| 范围 / 依赖 / 发布边界 | in/out scope、版本切片、依赖、发布条件和不承诺事项 |

流程明细与原型合同、验收场景拆分、反向投影对账、独立陌生读者复述门、以及分层不丢内容的规则，见 `references/prd-composition-contract.md`——组装正文前读它。

## Workflow

1. 校验 Ready 判定：确认 lifecycle 已完成 behavior inventory 对账、复合字段子项检查、合法人类决策证据和逐项安全/合规检查，并已把所有 P0 行设为 `closed`。
2. `PRD Not Ready`：按硬约束 2 输出产品决策视图，停在这里。
3. `PRD Ready`：确定文档目标和读者，以关闭表为生成输入和证据，组装人读 PRD，不重新解释或重签决策，也不直接投影完整关闭表。
4. 按上面的三问与章节合同组装正文，细则按 `references/prd-composition-contract.md`。
5. 用户可见/UI 产品：检查 `product-ui-ux-design` 的 IA、流程、页面状态和原型产出或审核；涉及 Agent/LLM/RAG/自动判断：检查独立 Agent/Machine Spec 引用。缺口转对应 owner。
6. 建最小引用：机器账本、设计产物、Agent/Machine Spec 和测试证据的名称、位置、版本与 owner。
7. 填依据并按场景拆分规则写验收：无来源不得写成确定结论。
8. 运行 `tighten-doc`，得到 post-tighten 最终候选。
9. 对最终候选跑反向投影对账，生成机器侧派生覆盖索引；任一适用 facet 无正文落点即失败。
10. 对同一最终候选跑独立陌生读者复述门；保存结果和遗漏项。
11. 交接：研发计划回 `product-rd-workflow`；TC 转 `test-artifact-management`；技术规格与评估工具转对应 owner。**反向对账和独立复述均通过后才可发布、分享、同步或提交。**

## 不用本技能，改用谁

- 需求实质未澄清 → `requirement-intent`。
- Current-state 未满足共享契约三态及证据要求 → `requirement-baseline`；权威 baseline 不能写成 N/A。
- 范围、版本切片、开放决策未关闭 → `requirement-scope`。
- UI/用户可见产品的 IA、交互、页面状态和原型 → `product-ui-ux-design`；具体实现 → 相应 web/app/miniapp 技术栈 owner。
- 只润色已定稿文档、去废话、改结构表达 → `tighten-doc`。
- 测试用例文档、Feishu/Bitable TC → `test-artifact-management`；测试层/覆盖策略 → `testing-strategy`。
- 多阶段研发交付、技术方案、实现/发布计划 → `product-rd-workflow`。

## 完成标准

逐条可核，缺一条即为 `interim` 而非完成：

- Ready 绑定的六个字段都已核对，且当前 `version` / `scope` 的全部 P0 行为 `closed`。
- 正文三问都答了，且「这是什么产品」经得起替换产品名的检验。
- 每个模块写了作用、输入、输出、上下游；没有按页面或菜单定义的伪模块。
- 反向投影对账已跑，覆盖索引已生成，无任一适用 facet 缺正文落点。
- 独立陌生读者复述门已跑（reviewer 未参与起草、fresh context、只看正文），遗漏项已记录且无实质遗漏。
- `tighten-doc` 已在最终候选上跑过，且对账与复述是在 post-tighten 候选上跑的。
- 安全 4 问：记了「无命中」，或四项逐条答案 + 写明所依据的 canonical 文件名；读取不可得时写了 `不可得(<原因>)` 并把本节标 interim。

## 输出模板

### 仅 PRD Ready

```text
PRD / 需求文档
1. 产品全景（用户 / 问题 / 价值 / P0 结果 / 非目标）
2. 模块地图或等价结构（责任 / 输入 / 输出 / 上下游）
3. 核心运行流程与流程明细（端到端主链路 / 动作 / 响应 / 状态 / 分支）
4. 模块 / 页面体验、信息架构与原型（非 UI 时写 N/A 依据）
5. 关键业务规则
6. 异常与恢复（异常 / 纠错 / 回退）
7. 角色与安全边界
   - 安全 4 问：无命中 / <逐项作答四项>
   - 依据来源：<读到了写 `security-four-questions.md`；没读到写 `不可得(<原因>)` 并把本节标 interim。不得留空>
8. 端到端验收场景
9. 范围、依赖与发布边界

最小引用
- 产物 / 位置 / 版本 / owner

Agent/Machine Spec 引用（仅在涉及 Agent/LLM/RAG/自动判断时）
- 产物 / 位置 / 版本 / owner
```

### PRD Not Ready

```text
产品决策视图
- 待决定问题：
- 候选 / 推荐：
- 代价：
- accountable_owner：<具名且有权限的人类 owner>
- 受影响 requirement / P0：

下一动作
- <最小取证、授权或决策动作>

机器账本
- <关闭表引用或附录；保留全部逐字段审计元数据>
```

## Reference Loading

- `references/requirement-closure-contract.md`：唯一 canonical 需求点关闭表，生成前必读。
- `references/security-four-questions.md`：安全 4 问本体与各 owner 落点细则，命中时必读。
- `references/prd-composition-contract.md`：流程明细与原型合同、验收场景拆分、反向投影对账、独立复述门、分层不丢内容。
