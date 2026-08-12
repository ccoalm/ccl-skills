# 需求点关闭契约

四个产品需求技能共享一张 `需求点关闭表`。每个技能只补自己的视图；不得复制、改名或另建状态表。

| 字段 | 规则 |
| --- | --- |
| `requirement_id` | 稳定且唯一的需求点标识 |
| 用户价值 | 该点为谁解决什么问题 |
| 事实依据 | 来源、取证时间和 current-state 三态结论 |
| 最终口径 | 已决定的产品行为；未决定时写阻塞点 |
| 版本/范围 | `current_version`、`in`、`out`、`deferred`，以及适用时的 appetite/砍项 |
| 异常/边界 | `failure`、`cancel`、`rollback/recovery`、`compatibility`，以及适用时的 `security/permission` |
| 验收 | `positive`、`negative`、`boundary`、`evidence_shape` |
| `closure_method` | 字段如何得到：`evidence-derived`、`low-risk-default` 或 `human-decision` |
| `decision_authority` | 谁有权决定该字段：`descriptive-fact`、`bounded-agent-policy`、有权限的人类 owner，或仍有效且有批准记录的规范性产品来源；`bounded-agent-policy` 表示授权来自已批准的有界 Agent policy，而非 Agent 或模型自身 |
| `decision_evidence` | 明确回答或已批准决策记录的 source/ref、`decided_at`、适用 version/scope |
| `status` | 整条 requirement 的状态：`open`、`blocked`、`closed` 或 `deferred` |
| `accountable_owner` | 当前人类用户，或具名、可追责且有相应决策权的人类角色 |
| `reopen_condition` | 哪类新事实、冲突、变化或撤销会重开 |

每个已填字段都必须携带自己的 `closure_method`、source、`decision_authority`；产品承诺字段还必须有 `decision_evidence`。不得用一组行级元数据代替逐字段记录。复合字段按上述子项判定：任一适用子项为 open，复合字段和整行均不能 `closed`；把子项判为不适用也必须有合法依据。

## 推导与决策权

代码、测试、界面、运行数据和架构只能证明 as-is 描述性事实，`decision_authority` 记为 `descriptive-fact`。它们不能单独决定 should-be 的最终产品行为、P0 范围、用户可见默认、权限/安全边界、异常/撤销/兼容政策、验收承诺或数值阈值。

产品承诺字段只能由以下权威关闭：

1. 当前人类用户，或具名、可追责且具备该项决策权的人类 owner 的明确决定。
2. 仍有效、已批准并带人类 owner/批准记录的规范性产品来源；使用旧来源前核验版本、scope 和 freshness。

Agent、模型、skill、workflow、工具，以及“产品团队”“需求负责人”等泛称不能签署。推荐、会议总结或 Agent 生成的关闭表不能反向成为授权证据。只知道 owner 角色但没有明确决定记录时，字段和整行保持 `open` / `blocked`。

## 三档关闭权限

1. **`evidence-derived` 可自动确定字段**：一手来源可确定 as-is 描述性事实；仍有效且具备上述批准记录的规范性产品来源可确定其授权范围内的产品承诺。每个字段记录 source、推导、版本、freshness、适用范围、冲突检查和重开条件。
2. **`low-risk-default` 可自动确定单个非核心字段**：`decision_authority` 必须记为 `bounded-agent-policy`，表示授权来自仍有效、已批准且可引用的有界 Agent policy，而非 Agent 或模型自身。只限该 policy 和既有规则均允许的单个非核心、低风险、可逆展示或表达细节。每个字段的 `decision_evidence` 必须记录 policy ref/version/scope、该字段为何落在允许范围、默认值、影响、撤销方式和 `reopen_condition`。不得用于产品承诺、P0 范围、核心路径、验收、数值阈值、安全、权限、数据语义、整个需求点、整行状态或商业口径。没有可引用的已批准 policy 时不得使用 `low-risk-default`；字段保持 `open`，或转为 `human-decision`。
3. **`human-decision` 必须由 accountable owner 决定字段**：产品方向、目标用户、核心路径、P0 in/out、商业模式、成功指标、多个方案的实质权衡、身份、权限、计费、隐私、合规、删除、覆盖和外部公开。Agent 只能给候选方案、推荐和代价，不能代签。

`bounded-agent-policy` 的批准者必须是当前人类用户，或具名、可追责且具有 policy 治理权的人类 owner。Policy evidence 必须包含批准记录/ref、approver、`approved_at`、version 和 scope。当前用户对具体任务的明确授权可作为 task-scoped policy evidence；持久或跨任务 policy 必须有仓库内稳定引用及人类批准记录。同一 Agent/模型不得在当前任务中生成 policy 后自我引用授权；未经人类批准的 repo 文档、会议总结和关闭表均不是 policy。

有界取证 pass 按以下顺序执行一次：① canonical owner/source；②与字段直接相关的当前代码、数据和规范；③记录已查类别及未查原因。证据缺失、冲突或过期时，在当前已授权来源内完成该 pass，并按权威性、freshness 和适用范围核对。同等级权威来源对产品口径冲突时立即升级，不用低等级描述性证据裁决。只有一轮有界 pass 完成、继续取证需要额外访问授权，或权威冲突仍未解决时，才升级为 `human-decision` / `blocked` 并提出最少一组问题。新权威源可替代旧非权威源，并以 `evidence-derived` 确定字段，但必须记录冲突处置和 `reopen_condition`。不得假设拥有未授权网络、生产环境或客户数据访问；输出不得包含 secret 或 PII。

## Current-state 与 N/A

Current-state 只能取三态：

- `required-and-evidenced`：需要现状取证，且证据已满足。
- `satisfied-by-authoritative-baseline`：由新鲜、权威且适用的 baseline 满足；baseline 不是 N/A。
- `not-applicable`：有边界的存在性检查证明目标行为净新增，且不修改、复用、替换或依赖既有流程、权限、数据、API 或规则，也没有迁移、兼容或旧版本行为；必须记录检查范围。不能证明时为 unknown/blocked。

安全/合规不得笼统 N/A。逐项检查身份、权限、计费、配额、隐私、删除、覆盖等触发类别并记录理由；任一项不确定即路由 `feature-risk-router`，artifact skill 不能自行判安全/合规 N/A。

## 行状态权限

Agent 只能自动确定具体字段，不能自动关闭整条 requirement。`requirement-intent`、`requirement-baseline` 和 `requirement-scope` 只能补各自字段并提出行状态候选。只有所有 P0 必填字段及适用子项均已确定、全部 `human-decision` 字段有合法 `accountable_owner` 和 `decision_evidence`，且安全与合规门已满足时，`product-rd-workflow` lifecycle 才能把整行 `status` 设为 `closed`。

## 分层视图与产物

- **机器账本**：保留完整关闭表及全部逐字段元数据。Agent 负责维护，产品人员无需手工逐格填写。
- **产品决策视图**：只显示待决定问题、候选/推荐、代价、`accountable_owner`、受影响的 requirement/P0，以及机器账本引用。
- **人读 PRD**：承载产品理解和面向读者的决策；用户可见/UI 内容必须由设计 owner 确认，非 UI 产品记录原型 N/A 的依据。具体正文和原型合同见[本技能“流程明细与原型合同”](../SKILL.md#流程明细与原型合同)。
- **Agent/Machine Spec（如适用）**：承载数据结构/字段合同、实现合同、逐条需求追踪关系、评估计划，以及技术验证证据的引用与状态等机器合同与技术细节。

关闭表是生成这些视图和产物的输入与证据，不等于人读 PRD 正文。不得把完整关闭表、逐字段关闭元数据、机器侧逐条 requirement inventory 或完整追踪矩阵直接投影进人读 PRD；人读 PRD 仍须完整说明面向读者的产品模块和能力，并只保留机器账本、Agent/Machine Spec 和测试证据的名称、位置、版本、owner 等最小引用。分层不得删除底层审计字段，也不得遗漏已关闭产品决定、关键业务规则、阈值、权限/安全边界、依赖和验收。

人读 PRD 不得遗漏当前范围内已关闭的 reader-facing 决定；具体 facet 级覆盖索引和失败条件见[本技能“反向投影对账”](../SKILL.md#反向投影对账)。

UI/用户可见产品的信息架构、交互、页面状态、原型设计及验收归 `product-ui-ux-design`；writer 不替代设计 owner。具体客户端实现归相应技术栈 owner，测试证据归 `testing-strategy`。

`PRD Not Ready` 优先展示产品决策视图，并把机器账本作为引用或附录；不得为简化展示删除底层审计字段。

## PRD Ready 门

仅当以下条件全部满足，完整 lifecycle 才能判定 `PRD Ready`：

- 问题已澄清。
- Current-state 已记录三态之一，并满足相应证据要求。
- 已与 `product-rd-workflow` 的独立可失败行为/acceptance inventory 对账；每个行为都有 `requirement_id`，或由合法 human decision 明确 `out` / `deferred`。未建行不等于不在范围。
- P0 范围已确定，且 lifecycle 已按行状态权限把所有 P0 需求点设为 `closed`。
- 版本/范围、异常/边界和验收的所有适用子项均已确定。
- 安全与合规已完成；逐项检查后不适用的类别有合法依据。

Lifecycle-issued Ready verdict 必须绑定 `product`、`version`、`scope`、`closure_table_revision`、`behavior_inventory_revision` 和 `issued_at`。关闭表、behavior inventory、P0 scope、human decision 或安全判断任一变化，旧 Ready 自动失效，必须重新判定。

任一条件不满足即 `PRD Not Ready`。此时不得输出 PRD 标题、骨架或正文；只输出产品决策视图、下一动作和机器账本引用/附录。`deferred` 仅表示不进入当前版本，不能伪装成当前 P0 已关闭。
