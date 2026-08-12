# PRD 组装合同（流程明细 / 验收拆分 / 反向对账 / 复述门）

`requirement-doc-writer` 在 `PRD Ready` 之后组装正文时逐节适用。入口的硬约束与章节合同在 `SKILL.md`，本文不重复。

## 流程明细与原型合同

- 用户可见/UI 产品的核心流程必须写明角色、触发、前置状态、逐步用户动作、系统响应、状态变化、页面反馈和成功结果，并覆盖适用的失败、冲突、冻结、恢复和返回分支；只有四至五条宏观链路不合格。
- 人读正文必须包含设计 owner 已确认的信息架构、页面/surface 关系、关键页面状态，以及关键动作—系统响应—状态变化—页面反馈链，并说明这些结构对产品行为和流程的影响。每个核心页面或 surface 写明用户目标、主要区域与信息层级、主次动作、进入/离开/返回路径、与模块/流程的映射，以及适用的空、加载、部分、错误、禁用、成功、恢复、权限和风险状态。
- `product-ui-ux-design` 负责 IA、交互、页面状态、原型设计及其验收，并产出或审核低保真原型、线框、流程图或等价的结构化页面描述。完整原型可嵌入正文，也可按名称、位置、版本和 owner 引用；外部链接只承载完整画布、视觉/交互细节和溯源，不得替代上条要求的 reader-facing 正文。writer 只能转写或组装设计 owner 已确认的内容并保全产品决定，不得自行冒充设计 owner；没有 Figma 不阻塞，只有一句页面列表不算原型。
- 原型未定且会改变核心路径、产品行为、权限或验收时，不得标记为可交付 UI 开发；低风险视觉细节可由设计 owner 后续补齐。具体 web/app/miniapp 实现归相应技术栈 owner，测试证据归 `testing-strategy`，不得把这些 owner 的实现方法复制进 writer。
- 非 UI 的 API、SDK、后台作业等可将原型标为 N/A，但必须记录无用户可见 surface 的依据；存在运营后台时不得整体标为 N/A，后台 surface 仍须写流程和状态。

## 验收场景拆分

角色/权限、前置状态、用户可见结果、失败结果、恢复路径或安全预期任一不同，必须拆成独立场景或明确分支；只有这些维度全部一致时才能聚合。`testing-strategy` 和 `test-artifact-management` 仍分别判断测试语义、层级与证据充分性以及结构化测试用例，不由 writer 代替。

## 反向投影对账

PRD 草稿完成后，对当前 `version` / `scope` 的全部 in-scope、`closed` requirements 按 reader-facing facet 逐项检查。每个适用 facet 单独映射到 PRD section anchor 或 acceptance scenario；至少区分产品行为/最终口径、rule/threshold、failure、cancel、rollback/recovery、compatibility、role/permission/security、dependency，以及 positive/negative/boundary acceptance。同一 requirement 可有多行；任一适用 facet 没有正文落点，PRD 失败。

对账结果生成机器侧派生索引，至少保存 `requirement_id / source_field_or_subitem（或 reader-facing facet） / PRD section anchor or acceptance scenario / closure_table_revision / coverage status`。N/A 必须引用关闭表中已有的合法不适用依据，索引不得自行创造 N/A。该索引只证明正文覆盖，不是新的事实源，不复制字段值或决策元数据，不进入人读正文；测试语义、层级和证据充分性仍由 `testing-strategy` / `test-artifact-management` 判断。

## 独立陌生读者复述门

正文完成并经过 `tighten-doc` 后，必须对 post-tighten 最终候选执行独立复述。reviewer 必须未参与起草、使用 fresh context，且只能看到 PRD 正文，不得查看关闭表、Machine Spec、测试证据或背景对话；作者自评不算。

reviewer 固定复述：产品/用户/问题/承诺结果/非目标；模块或等价能力及关系；完整主链路和关键异常；关键规则/阈值/适用条件；角色/权限/安全边界；关键负向/边界验收；范围/发布边界。对用户可见/UI 产品，还必须按上面「流程明细与原型合同」复述核心角色、触发、动作—系统响应—状态变化—页面反馈及适用分支，信息架构与核心页面/surface 关系，以及关键页面状态。保存复述结果和遗漏项；任一实质遗漏或错误均失败。正文实质内容或结构变化后必须重跑，失败时不得发布或通过 closeout。

涉及 Agent/LLM/RAG/自动判断时，PRD 另列 Agent/Machine Spec 的最小引用。缺少独立规格时，不得标记为可交付 Agent 开发。

## 分层不得丢内容

人读正文不得复制机器账本、机器侧逐条 requirement inventory、逐字段关闭元数据、数据结构/字段合同、实现合同、评估计划、完整追踪矩阵或逐需求技术证据表。这些内容留在机器账本、Agent/Machine Spec 或测试证据产物；人读 PRD 仍须完整说明面向读者的产品模块和能力，并只保留机器侧产物的名称、链接或位置、版本、owner 等最小引用。**不得因分层而丢失已关闭产品决定、关键业务规则、阈值、权限/安全边界、依赖和验收。**

引用只支持溯源或技术细节，不能替代正文中的产品行为、规则、阈值、异常、权限/安全、范围和验收；读者不打开引用也必须理解这些内容。
