# 算法服务上线手册

算法服务上线的材料入口、流程和评审要点。门禁与模板的权威版在 `product-rd-workflow/references/`。

## 先看哪份

| 你要做什么 | 阅读材料 |
|---|---|
| 工程上怎么接 LLM / RAG / prompt / 评测 / streaming | [接入 LLM/算法能力与上线手册](llm-algorithm-handbook.md) |
| 判断一个算法能力能不能进入研发或上线 | [算法能力上线门禁 SOP](../skills/product-rd-workflow/references/algorithm-launch-sop.md) |
| 写测评报告 | [算法服务测评报告模板](../skills/product-rd-workflow/references/algorithm-launch-evaluation-report-template.md) |
| 上线评审前逐项检查 | [算法服务上线检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) |
| 细化灰度、回滚、组合链路、评测集治理 | [算法服务上线执行规范](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md) |
| 让 OpenCode/Codex/Claude 帮你生成或核查材料 | [使用skill辅助算法服务上线手册](algorithm-service-launch-with-skills.md) |

## 上线流程速查

立项 → 方案评审（冻结阈值）→ 研发（多版本 + 监控 + 回滚）→ 测评验收 → 上线评审（给四类结论）→ 灰度观察 → 全量 → 复盘沉淀。

| 阶段 | 出什么 | 不过不进下一步的硬线 |
|---|---|---|
| 立项 | 产品定义三问 + 业务基线草案 | 产品定义不清，不进方案评审 |
| 方案评审 | 冻结业务/算法/工程/成本阈值 | 评审现场临时改阈值 |
| 研发 | 服务 + 接口契约 + 多版本可区分 + 监控 + 回滚 + 日志 | 分不清版本 / 无回滚 / 无兜底 |
| 测评验收 | 测评报告 + 业务和工程指标 + 组合链路三层验收 | 缺测评报告或数据集说明 |
| 上线评审 | 对检查表逐项确认，给四类结论之一 | 用「基本可以 / 先上再看」替代结论 |
| 灰度观察 | 按业务/算法/工程指标观察 | 触发阈值即暂停或回滚 |
| 全量 | — | — |
| 复盘 | 收益 / 坏例 / 数据集 / 后续优化 | — |

完整门禁与一票否决项以 [SOP](../skills/product-rd-workflow/references/algorithm-launch-sop.md) 和 [检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) 为准。

## 按角色找

| 角色 | 主要负责 | 先看 |
|---|---|---|
| 产品负责人 | 产品定义三问、业务效果基线、验收标准、上线结论 | 本页「上线前必须说清楚」+ [SOP](../skills/product-rd-workflow/references/algorithm-launch-sop.md) |
| 算法负责人 | 算法方案、核心指标、测评数据集、测评报告、风险样例、评测集治理 | [测评报告模板](../skills/product-rd-workflow/references/algorithm-launch-evaluation-report-template.md) + [执行规范 §评测集治理](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md) |
| 研发负责人 | 接口契约、多版本灰度、监控、回滚、稳定性、成本 | [执行规范](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md) |
| 测试负责人 | 功能/回归/异常验收、组合链路三层验收、回归坏例集 | [检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) + `testing-strategy` |
| 数据/分析负责人 | 线上指标口径、灰度分析、业务结论 | [执行规范](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md) |
| 项目负责人 | 组织评审、查门禁材料齐全、推动风险闭环 | [检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) + [SOP §一票否决项](../skills/product-rd-workflow/references/algorithm-launch-sop.md#17-一票否决项) |

## 上线前必须说清楚

| 问题 | 输出 |
|---|---|
| 给谁用，哪个任务变好 | 用户、场景、入口、目标链路、上线范围 |
| 哪个业务结果改善，什么不能变差 | 业务效果基线、护栏指标、观察周期、数据来源、owner |
| 为什么现在自研、采购或迭代 | 自研与三方 ROI、效果、成本、交付、风险和退出方案 |

完整阻断项以 [算法能力上线门禁 SOP 的一票否决项](../skills/product-rd-workflow/references/algorithm-launch-sop.md#17-一票否决项) 和 [算法服务上线检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) 为准。

## 新能力和迭代能力的区别

| 类型 | 重点 |
|---|---|
| 新能力算法 | 先证明业务上线基线成立，再证明自研/采购选择合理，最后证明算法效果、工程指标、行业或三方对比达标 |
| 迭代算法 | 先证明老版本基线和新旧版本差异，再证明局部算法改动不会让整体业务链路变差 |
| 多算法组合链路 | 先核实真实链路，再验收被改模块、上下游契约、端到端结果、版本归因和回滚路径 |

## 评审概览

上线评审看三类证据：

- 产品证据：产品目标、业务效果基线、能力边界和风险边界。
- 测评证据：测评报告、数据集说明、新旧版本或三方对比、失败样例。
- 上线证据：多版本实验或灰度、版本归因、监控告警、回滚授权和风险 owner。

上线评审用 [算法服务上线检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) 逐项确认。

## 常见提问

- **算法指标涨了能上吗？** 不一定。算法局部指标变好只是必要条件；业务核心指标低于最低上线标准、或长链路只给局部指标不评估整体业务，都会被否决。
- **小迭代能跳测评集说明吗？** 不能。缺测评数据集说明，或缺评测集版本/标注规则/固定基准集/回归坏例集说明，都是一票否决。
- **评审会上想把阈值放松一点？** 不行。基线/阈值/口径/停止规则在评审现场临时改 = 否决；要改在方案评审阶段改并冻结，留原因、影响范围和批准人。
- **用了三方大模型 / 客户文件 / 金融 / 用户隐私数据？** 必须有安全合规确认，否则否决。
- **哪个集能当固定基准？** 没被训练、微调、调提示词、调阈值、反复看着改过的 held-out 集；被碰过的归类成 dev/训练集另存，别当基准。详见 [执行规范 §评测集治理](../skills/product-rd-workflow/references/algorithm-launch-execution-spec.md)。
- **高风险 100% 人工复核做不到怎么办？** 缩上线范围，或走产品/合规批准认领残余风险；不准静默把高风险复核率降到 0。

权威规则以 [SOP §一票否决项](../skills/product-rd-workflow/references/algorithm-launch-sop.md#17-一票否决项) 和 [检查表](../skills/product-rd-workflow/references/algorithm-launch-checklist.md) 为准。

## 文档同步要求

- 项目主文档、测评报告、上线检查表、执行规范都应同步到飞书。
- 主文档应引用子文档链接。
- 本仓库 `docs/` 和 `references/` 保存可复用模板和手册，不保存项目专属证据、真实客户信息、内部 ID 或一次性评审记录。
