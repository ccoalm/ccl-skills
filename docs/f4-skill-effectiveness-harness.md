# F4 技能有效性 Harness — 方案与落地计划

> **这是写定时点的方案稿,不是当前状态说明。** 三层已全部落地,另加了本稿没有的 `make eval-health`(综合分与趋势,建议层)。当前判定口径见 [架构总览](ARCHITECTURE.md) 治理段。
>
> - `make eval-routing` — Tier-1,**阻断**
> - `make eval-routing-bank` — Tier-2,建议
> - `make eval-golden-trace` — Tier-3,建议
> 日期:2026-05-31 · Owner 技能:`skill-extraction-workflow`
> 来源:技能仓库深度 review 的 F4 roadmap 项;把 [harness-patterns-and-eval.md](../skills/skill-extraction-workflow/references/harness-patterns-and-eval.md) §3 那套**只有文字、不可执行**的 eval 方法论做成可执行。

## 1. 问题

`check-ccl-skills.sh` 管"结构合规",但没有东西管"技能是否真有效"。§3 自己承认"我们的 skill 没有这样的 benchmark"。怎么知道一次 skill 改动是变好还是变坏,目前无可执行答案。

技能有效性分两面:

- **路由正确性** — 对的 utterance 选对 skill。**已观察到的主失效面**(coordinator-vs-executor "重构" 平局、restart/redo 触发缺口,均记在 [source-register.md](../skills/skill-extraction-workflow/references/source-register.md))。大部分**不跑 agent 就能测**。
- **应用质量** — 选对 skill 后行为对不对。必须真跑 agent,贵且随机。

## 2. 设计原则

真正的风险不是"自动化太少",而是造出一个 **flaky / 可作弊、于是被人无视的门禁** —— 即刚修掉的 impact-chain "治理空转" 的重演。**阻断策略比实现野心更重要**:确定性的才阻断,随机/低置信的只报告。

## 3. 三层 + CI 策略

| 层 | 范围 | CI 策略 | 性质 |
|---|---|---|---|
| **T1 静态路由分析器** | 全仓 | 阻断,但只对客观失败 | 确定、无 LLM、便宜 |
| **T2 冻结路由 task-bank** | 全仓,种子取自历史 miss | 先 advisory,再选择性阻断 | Haiku grader 是"路由兼容性 eval",不是真值预言机 |
| **T3 golden 行为回放** | 仅 hub skill | 自动跑、判定先人工,nightly 起步 | 随机 + 环境敏感 |

**范围纠正:** "hub 聚焦" 只指 **T3** 从 `product-rd-workflow` / `defect-diagnosis` / `testing-strategy` 起步。**T1 必须全仓** —— 路由是图属性,枢纽的有效性依赖邻居不偷/不混触发词;窄化就测不到。

## 4. 阻断粒度

每层把"客观可判"与"模糊/随机"分开,只让前者挡 merge。

**T1**

| 发现 | 阻断 |
|---|---|
| 悬空重定向(`Skip → X` 而 X 未安装) | 是 |
| 精确归一触发词被 2+ skill 认领且无互斥 skip | 是 |
| `Skip → X` 但 X 完全不认领该路由族 | 是 |
| 模糊/语义近似碰撞 | 仅 advisory |
| 措辞证据弱的非对称 skip | 仅 advisory |

**T2**

- grader 输出 `{selected_skill, confidence, rationale_short}`,模型/版本钉死、temp 0。
- 报告 diff 式:新挂 / 新过 / 仍挂。
- **只在 grader 输出非法时 fail-closed**,不因低置信 miss 阻断。
- 阻断推进:首个 MR 纯 advisory → 2-3 次真实改动后,只对"高置信冻结 task 的回归"阻断 → 永不因单个新低置信 miss 阻断(需人工提升或重复失败)。
- v1 不上多 grader(成本高、不解决治理作弊);改用 **task provenance** 控制(见 §5)。

**T3**

- 只做**结构化断言**:必调 skill 出现 / 禁用 skill 不出现 / 产物路径或段落存在 / 命令族出现 / 无破坏性命令类 / 该有的覆盖边界或验证状态在。
- **不**断言精确措辞、精确顺序(硬 gate 除外)、精确 tool 数。
- 跑法:per-MR 可选/advisory 子集跑 1 次;nightly 全 hub 回放,flaky prompt 才 3 次取多数;release 分支全回放但仍人工判定,直到有稳定史。
- 失败 → 开回归报告,不自动挡 merge;只有破坏性/安全违规在 CI 阻断。

## 5. 防作弊(要执行,不是写进文档就算)

挡住"改 skill + 顺手改测试让它过"。

- 每个 task 带 `frozen_at_sha`;runner **校验它是当前 HEAD 的祖先**。
- 一个 PR 同时改了 description 和 task-bank → 显式报告,且**新增/改动的 task 本次改动不计入阻断**。
- 删除 task 或改 `expected_skill` 需 `reason` 字段,并作为治理 warning 显示。
- task provenance 必含:`source` · `frozen_at_sha` · `why_expected` · `added_by_change_sha`。

## 6. 治理挂钩(scoped Core Rule)

`skill-extraction-workflow` 加一条 Core Rule:**改了路由面就要跑 routing eval**。仅当改动触及以下才触发,避免每个小改都跑(重演 impact-chain 的过度/失灵):

- 任一 `SKILL.md` 的 `description`
- 路由 prose:`Use when` / `Proactively invoke` / `Skip when` / redirect
- `source-register.md`
- eval task-bank
- eval runner / checker 脚本

body-only、typo、非路由 docs、非路由 reference 改动 → 只跑现有结构校验。

## 7. 落地计划(3 个独立 MR)

> 状态:三个 MR 均已落地。T1 = 门禁(阻断客观失败);T2/T3 = advisory dashboard(`make eval-routing-bank` / `make eval-golden-trace`)。基线:T1 0 blocking、T2 16/16、T3 3/3 hub。运行契约见 [eval-routing.md](../skills/skill-extraction-workflow/references/eval-routing.md)。

**MR-1 · T1 静态路由分析器**(先做,真价值且可独立验证)

1. `skills/skill-extraction-workflow/scripts/eval-routing.rb` — 解析全部 SKILL.md,抽路由行,查 悬空重定向 / 精确碰撞 / 明显非对称 skip,输出人读 + JSON。
2. `make eval-routing`。
3. 接进 `check-ccl-skills.sh`,只对 §4 客观失败阻断,沿用现有 marker 风格。
4. `skills/skill-extraction-workflow/references/eval-routing.md` — 定义 T1/T2/T3 契约,明说"可执行 benchmark 从 T1 起步,T2/3 分阶段"。
5. scoped Core Rule(§6)。

**MR-2 · T2 路由 task-bank + grader**

- `eval/routing-tasks.jsonl`,种子取自 source-register 历史 miss。
- `skills/skill-extraction-workflow/scripts/eval-routing-bank.rb`,advisory dashboard。

**MR-3 · T3 hub golden trace**

- 每个 hub skill 1 条 golden trace + 一个 runner,advisory / nightly / 手动判定起步。

每个 MR:worktree 隔离 + dual-track codex 评审后落地,自身走门禁。

## 8. 边界(刻意不做)

- SWE-bench 规模的全任务集(§3.3 自己标"待用";维护成本 > 收益)。
- v1 的多 grader 投票(用 task provenance 替代)。
- T3 的精确 transcript / 措辞 / tool 数断言(随机,必 flaky)。
- 自动判定 T3 通过与否(无稳定史前由人定)。

## 9. Health roll-up(综合分 + 趋势,advisory)

三层各自答"这次/这面好不好",但没有"仓库整体在变好还是变差"的一个数。`eval-health.rb`(`make eval-health`)把 structural + T1 + T2 + T3 卷成**加权 0–10 综合分 + 趋势**,沿用 OpenSSF Scorecard 的形态(每信号 0–10 → 按风险加权聚合,跨时间追)。

两条护栏:**advisory 永不阻断**(不接 `check-ccl-skills.sh`、历史 git-ignore;Goodhart:分变成 gate 就被博弈,二元门禁仍是真值);**corpus/version 守卫**(趋势只跟尺子相同的历史比,换了 task-bank/golden-traces 就 reset)。契约见 [eval-routing.md](../skills/skill-extraction-workflow/references/eval-routing.md) Health roll-up 节,业内映射见 [harness-patterns-and-eval.md](../skills/skill-extraction-workflow/references/harness-patterns-and-eval.md) §3.4。
