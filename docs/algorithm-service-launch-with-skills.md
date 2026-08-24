# 使用skill辅助算法服务上线手册

让 OpenCode、Codex 或 Claude 按 CCL Skills 协助产出算法服务上线材料，统一梳理产品目标、测评、测试、灰度、监控、回滚和复盘。

技能按门禁标准帮你核对上线证据；真实指标、eval、看板、回滚记录需你提供，技能本身不连线上监控。

## 适用场景

| 场景 | 例子 | 首选入口 |
|---|---|---|
| 新能力算法 | 语音输入、首次新增某类智能能力 | `product-rd-workflow` |
| 迭代算法 | 翻译、问答 QA、模型、prompt、检索、排序、后处理调整 | `product-rd-workflow` |
| 多算法组合链路 | 意图识别、RAG、检索、排序、NL2SQL、Agent、总结等组合能力 | `product-rd-workflow` + `llm-inference-integration` + `testing-strategy` |

## 推荐技能顺序

| 步骤 | 技能 | 让它做什么 |
|---|---|---|
| 1 | `product-rd-workflow` | 定义产品目标、能力类型、业务效果基线、上线门禁和材料清单 |
| 2 | `llm-inference-integration` | 处理 LLM、RAG、Agent、prompt、模型版本、评测、replay、shadow 和推理观测 |
| 3 | `testing-strategy` | 决定模块级、链路级、产品级测试怎么验收 |
| 4 | `platform-release-engineering` | 设计多版本实验、灰度、扩量、暂停、回滚和兜底 |
| 5 | `platform-observability` | 设计指标、日志、trace、看板、告警和归因 |
| 6 | `release-doc-writer` | 写上线文档正文：发布范围、变更清单、验证证据 |
| 7 | `tighten-doc` | 材料定稿后的文字层：去废话、黑话和不可执行表达 |
| 8 | `release-coordination` | 真要发这一版时的执行：上线范围确认、合主干、打 tag、生产构建、发布后收尾 |
| 9 | `skill-extraction-workflow` | 上线后复盘，把可复用经验沉淀到正确技能或手册 |

如果任务只是问“这个改动风险多大、要跑哪些门禁”，先用 `feature-risk-router`。

## 可复制提问

### 新能力算法

```text
使用 product-rd-workflow，基于产品文档、技术文档和代码，帮我梳理这个新算法能力的上线材料。
请先判断产品定义三问、业务效果基线、自研与三方 ROI、行业/三方对比、算法效果指标、工程指标、测评数据集、多版本实验或灰度、监控和回滚是否齐全。
不确定的链路节点标为待确认，不要编。
```

### 迭代算法

```text
使用 product-rd-workflow + llm-inference-integration + testing-strategy，帮我评审这个算法迭代是否满足上线门禁。
请检查新版本和老版本核心指标对比、业务指标是否不变差、测评数据集是否可信、组合链路是否端到端验收、灰度和回滚是否可执行。
```

### 多算法组合链路

```text
使用 product-rd-workflow，先核实真实产品链路和代码链路，再设计验收方案。
这个能力由多个算法/策略/工具组成，请分别给出被改模块验收、上下游接口契约、端到端业务验收、版本归因、监控和回滚要求。
未核实的模块不要写成固定真实链路。
```

### 文档优化

```text
使用 tighten-doc 优化这份上线材料。
保留决策、owner、阈值、门禁和风险，不要删实质要求；删除废话、重复、黑话和不可执行表达。
```

### 复盘沉淀

```text
使用 skill-extraction-workflow 总结这次算法上线过程的经验。
同时检查失败、返工和稳定成功：先解释形成结果的机制，再判断现有内容应保持、合并、删除、移位还是新增，并更新到真正会在下次任务中起作用的 CCL Skill、手册或检查机制。
```

## 执行门禁

正式要求以这些文件为准：

| 材料 | 用途 |
|---|---|
| [算法能力上线门禁 SOP](../skills/product-rd-workflow/references/algorithm-launch-sop.md) | 产品定义、业务效果基线、新能力/迭代能力上线要求和一票否决项 |
| [算法服务测评报告模板](../skills/product-rd-workflow/references/algorithm-launch-evaluation-report-template.md) | 测评报告必须填写的模块 |
| [算法服务上线检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) | 上线评审逐项确认材料、证据、状态和 owner |
| [算法服务上线执行规范](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md) | 多版本实验或灰度、组合链路、监控回滚、评测集治理和全量后运营 |

让 agent 辅助生成材料时，可以直接要求它"按上述正式门禁逐项检查，缺失项标为不可上线或待补齐"。

## 材料位置

| 材料 | 位置 |
|---|---|
| 团队阅读入口 | `ccoalm/ccl-skills/docs/` |
| 算法上线执行模板 | `ccoalm/ccl-skills/skills/product-rd-workflow/references/` |
| 临时草稿和分析过程 | 各自的私有临时工作目录（不入仓库 docs/ 与 references/）|

[AI/Algorithm Launch Templates](../skills/product-rd-workflow/references/algorithm-launch-templates.md) 是上述 4 份门禁文件的索引入口；正式执行时先看它，再进入对应 SOP、报告模板、检查表和执行规范。
