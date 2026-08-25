# F4 技能有效性 Harness

> 当前正式口径。Owner：`skill-extraction-workflow`。可执行契约见 [eval-routing.md](../skills/skill-extraction-workflow/references/eval-routing.md)。

结构校验只能证明技能可加载、引用可解析、路由关系满足确定性约束；它不能单独证明 Agent 在真实任务中选对技能、执行正确或交付更好。F4 把这些问题拆开测量，不用一个分数代替不同性质的证据。

## 三层分别回答什么

| 层 | 回答的问题 | 运行与判定 | 合并语义 |
|---|---|---|---|
| **T1 静态路由分析** | 路由图是否存在可确定判定的结构错误 | `make eval-routing`；无 LLM，结果可重复 | 悬空显式 redirect、未消歧的精确触发词冲突等客观失败阻断 |
| **T2 冻结路由 task-bank** | 当前 description 能否让廉价 grader 把固定 utterance 路由到预期 owner | `make eval-routing-bank`；模型输出是兼容性信号，不是真值 | runner 始终 advisory；结果是否成为某次改动的落地条件，由该改动已有的 owner、风险或评审门禁决定 |
| **T3 golden trace** | 真 Agent 在完整技能与 hook 环境中是否走到预期路由结构 | `make eval-golden-trace`；真实回放、非确定、人工判定 | runner 始终 advisory；破坏性或安全问题由各自确定性门禁独立阻断 |

“runner 是否以非零退出”与“这次改动是否允许落地”是两件事。T2/T3 不把 grader 或单次 Agent 输出当真值，因此 F4 不因 miss 生成统一阻断；若改动的 owner、风险或评审门禁预先把某项 T2/T3 证据纳入本轮接受标准，则由那道门禁作落地判断并记录理由。

## 各层的判定边界

### T1：只阻断客观失败

| 发现 | 判定 |
|---|---|
| 显式 `Skip → X`，但 X 未安装 | blocking |
| 同一归一触发词被多个技能认领，且没有互相 redirect 消歧 | blocking |
| 模糊词面碰撞、疑似散文死链、已消歧的精确碰撞 | advisory |

判定以 `skills/skill-extraction-workflow/scripts/eval-routing.rb` 为准（`blocking` 只在 dangling redirect 与未消歧的 exact collision 两处产生，已消歧的碰撞进 advisory）。此前这张表还列过第三条 blocking「`Skip → X` 但 X 完全不认领该路由族」——runner 从未实现它，只查 target 是否已安装；那是文档单方面的声称，已删。改这张表前先读 runner，别反过来。

T1 必须覆盖全仓。路由是图属性，枢纽技能是否有效取决于相邻技能是否抢占或遗漏同一触发族。

### T2：提供稳定性与邻居对照证据

- grader 固定模型与参数，输出结构化选择、置信度和短理由。
- task 带 `frozen_at_sha` 与来源；同一改动同时修改 description 和 task-bank 时，新增或改动 task 不作为本轮回归依据。
- 对路由失败做改前/改后比较时，默认取得至少 10 轮有效基线；超时或不可解析轮不计数。采用不同样本量时，随工件记录理由。
- 最终措辞重新测量；中间稿结果不得挪用。
- 受影响邻居默认在改前、改后各至少 3 轮；邻居回归作为独立 finding 交给本轮实际的 owner、风险或评审门禁处置。
- 每轮绑定 runner、grader 身份、候选指纹和原始工件位置。

这里没有通用的“先 warn，积累几次后自动升级为阻断”，也没有 F4 自己生成的统一合并门禁。是否阻断由负责该改动的既有门禁依据确定性、误报风险、预注册标准和后果决定。

### T3：看结构，不追求 transcript 一致

- 断言应加载或禁止加载的 skill、允许的命令类别和破坏性行为边界。
- 不断言精确措辞、普通步骤的精确顺序或固定 tool 次数。
- `PASS`、`FAIL`、`INCONCLUSIVE` 都保留原始回放；单次结果不等于稳定结论。
- T3 可作为路由行为的改前/改后证据，但只有真实观察到旧候选 miss 才能称为 RED baseline。

## 最小度量记录

每次声称某项技能改动“更好”之前，至少记录：

| 字段 | 必须回答 |
|---|---|
| 比较单元 | 同一任务、同一输入、同一候选边界是什么 |
| baseline / candidate | 两个候选的版本、配置、模型与运行条件 |
| 质量结果 | 正确性、验收结果、缺陷或回归；质量门先判 |
| 效率与自主性 | 时间、轮次、工具调用、人工介入；只比较同一口径 |
| 混杂因素 | corpus、模型、权限、环境、工具版本是否变化 |
| 决策 | 保留、回退、继续观察，以及由谁决定 |

质量、效率、自主性和人工介入不是可随意互换的量。质量未过线时，不能用更少 token、更快或更高综合分抵消。

## Health roll-up 的正确用途

`make eval-health` 汇总 structural、T1、T2、T3 的在场信号，保留一个 0–10 加权值和同 corpus、同维度下的历史变化，便于快速发现“哪里值得看”。它是**描述性仪表盘**，不是仓库优劣的总判决：

- skipped 维度不会被当成已通过；报告必须显示本次实际包含的维度。
- task-bank、golden traces 或在场维度改变时重置比较基线，不能跨尺子读趋势。
- 综合值不进入 `check-ccl-skills.sh`，不替代 T1、结构校验、行为证据、验收或人工判断。
- 不得据此单独声称“仓库整体变好/变差”；结论回到对应维度、任务结果和最小度量记录。

## 运行入口

```bash
make eval-routing
make eval-routing-bank
make eval-golden-trace
make eval-health
```

具体输入、退出码、防作弊字段和报告 schema 以 [Routing Eval 契约](../skills/skill-extraction-workflow/references/eval-routing.md) 为准。
