# Routing Eval — Tier-1 静态分析器契约（+ T2/T3 阶段计划）

可执行的技能有效性 harness。本 ref 定义 Tier-1 的契约;完整方案见 [docs/f4-skill-effectiveness-harness.md](../../../docs/f4-skill-effectiveness-harness.md)。

可执行 benchmark 从 **Tier-1 起步**;Tier-2(冻结路由 task-bank)、Tier-3(hub golden trace)分阶段落地。

## Tier-1:静态路由分析器

`scripts/eval-routing.rb <repo-root> [--json <path>] [--quiet]`。只读每个 `skills/*/SKILL.md` 的**frontmatter `description`**(body 里的 `→` 是叙述,不是路由),分段抽:

- **claim 触发词** = `Use when` / `Proactively invoke` 段里的引号短语(归一 = 去引号 + trim + lowercase,CJK 原样)。
- **redirect** = `Skip` 段里 `->`/`→` 后的 skill token(backtick 可选)。

退出码:`0` = 无 blocking;`1` = 有 blocking;`2` = 用法/解析错。

## 发现分类

只让**客观可判**的挡 merge;模糊/随机的只报告。

| 类型 | 级别 | 判据 |
|---|---|---|
| `dangling_redirect` | **blocking** | backtick 的 `` `X` `` redirect,X 不是已装 skill(显式 skill-ref 语法 + 未知目标) |
| `exact_trigger_collision` | **blocking** | 同一归一触发词被 ≥2 skill 认领,且认领方之间无互相 redirect 消歧 |
| `exact_trigger_collision_disambiguated` | advisory | 同上但认领方之间存在 redirect(已消歧) |
| `fuzzy_collision` | advisory | 一个 skill 的完整触发词是另一 skill 触发词的子串 |
| `possible_dangling` | advisory | 裸(无 backtick)redirect 目标含连字符、像 skill 名但未安装(疑似改名/删除) |
| `prose_redirect_target` | advisory | Skip redirect 的目标从句含 `owner`/`reviewer` 却没有任何 backtick 的已装 skill —— 无法确定路由的散文死链(如 `→ the adversarial or delete-code review owner`) |

**为什么这么分级**:真正的风险是造出 flaky/可作弊、于是被无视的门禁。裸单词 redirect(`-> stack skill`)按普通英文忽略,不误报;单向 `A->B`(枢纽→叶)是正确路由,不报。`prose_redirect_target` 只在从句显式说"owner/reviewer"却给不出可解析 skill 时报,避免对通用散文误报——刻意留在 advisory:散文匹配非 ground truth,只 nudge 作者点名真 skill,不挡 merge。

## 怎么用

- `make eval-routing` — 人读报告。
- `check-ccl-skills.sh` 末尾自动跑;有 blocking → 整个校验失败(`eval_routing_blocking`),否则 `eval_routing_ok`。
- 落地门禁见 host 技能 Core Rule「Routing-surface change gate」。

## 解 blocking

- `dangling_redirect`:目标 skill 不存在 —— 改对名字,或目标确实没装就别用 backtick skill-ref 语法。
- `exact_trigger_collision`:两个 skill 抢同一触发词 —— 要么在一方 `Skip when … → 另一方` 显式消歧,要么把触发词改具体让两者不再字面相同。

## Tier-2:路由 task-bank + 廉价 grader(已落地,advisory)

`scripts/eval-routing-bank.rb <repo-root> [--bank p] [--model m] [--limit N] [--dry-run] [--json p] [--baseline p] [--desc-budget-chars N]`。`--desc-budget-chars N` 把每条 description 截到前 N 字符再评（消费端截断臂——如 Codex 在 ~2% 上下文预算/未知窗口 8,000 字符下压缩技能清单）；plain 与 budgeted 各跑一遍即可定位"只活在描述尾部"的路由触发词。`make eval-routing-bank`。

- 冻结 task-bank `eval/routing-tasks.jsonl`:每行 `{id, utterance, expected_skill, must_not_route_to?, source, why_expected, frozen_at_sha}`,种子取自 source-register 历史 miss + bootstrap 路由规则。
- grader = 每 task 一次本机 `claude --print --tools "" --model <haiku>`,喂 utterance + 全部 skill description(agent 真正路由的那份面),要 `{selected_skill, confidence, rationale_short}`。
- **路由兼容性信号,不是真值预言机** —— grader 自己可能错;只衡量"当前 description 能否让廉价模型把固定 utterance 路由到 expected"。
- **advisory**:不接 `check-ccl-skills.sh`,不挡 merge。退出码:`0` = 跑完;`2` = 用法;`3` = grader 整体不可用(claude CLI 缺失则打印 skipped 后 `0`)。路由 miss 永不非 0。
- **防作弊**:runner 校验每 task 的 `frozen_at_sha` 是 HEAD 祖先(非祖先 = drift,排除出回归判定);同一改动若同时动 task-bank 和 SKILL.md description 会显式告警(防"改 skill 顺手改测试让它过")。
- `--baseline <json>` 给 diff 式报告(newly_failed / newly_passed)。

## Tier-3:hub golden trace 真 agent 回放(已落地,advisory,人工判定)

`scripts/eval-golden-trace.rb <repo-root> [--traces d] [--max-turns N] [--timeout S] [--only id] [--limit N] [--json p] [--dry-run]`。`make eval-golden-trace`。

- golden trace `eval/golden-traces/*.json`(每个 hub skill 一条):`{id, hub_skill, trigger_prompt, assert{must_invoke_skill, must_not_invoke_skill, no_destructive_command}, allowed_variance, frozen_at_sha}`。当前 3 条:product-rd-workflow / defect-diagnosis / testing-strategy。
- runner 把 trigger 喂给 headless `claude -p --output-format stream-json --max-turns N --allowedTools Skill Read Grep Glob`(**allowlist:只读 + Skill,无副作用** —— Bash/Edit/Write/NotebookEdit/cron/task 全因不在白名单而禁用),从事件流抽**真 agent 实际 invoke 的 Skill**,做**结构化断言**:must_invoke ⊆ invoked、must_not ∩ invoked = ∅、命令无破坏性类。
- **只断言路由结构,不断言措辞/顺序/tool 数**。v1 因禁用工具,聚焦路由结构;产物/命令族断言留待沙箱化后扩展。
- **比 Tier-2 高保真**:观察真 agent(完整 skill 体 + hook + context),不是廉价模型对 description 的看法。
- **advisory + 人工判定**:不接门禁、不挡 merge。状态 PASS / FAIL / INCONCLUSIVE(agent 未在 max-turns 内路由)。退出码:`0` = 跑完;`2` = 用法;`3` = agent 整体不可用(claude 缺失则 skipped 后 `0`)。路由漂移永不非 0。
- **随机性**:agent 非确定;判定先人工、nightly 起步,有稳定史前不自动 gate。防作弊同 T2(`frozen_at_sha` 祖先校验)。
- **双用途**:除回归外,Tier-3 还可当**改技能前的 RED-baseline**(改前手动跑触发场景看真 agent 是否真路由错,改后看 compliance)——可选;只有真观察到 miss 才算 RED(PASS/INCONCLUSIVE 不算),小 N + 非确定有噪声,手动跑两次自己留两份报告。落地 + 防作弊注意见 [validation-and-landing.md](validation-and-landing.md) "Optional real-agent RED-baseline"。

## Health roll-up:综合分 + 趋势(已落地,advisory)

把上面各信号卷成**一个加权 0–10 分 + 趋势**,答"仓库在变好还是变差"。这是 OpenSSF Scorecard 给代码仓用的形态(每 check 0–10 → 按风险加权聚合 0–10 → 跨时间追);我们把它套到 **F4 技能 eval 信号**上,不是去打分代码工具。映射依据见 [harness-patterns-and-eval.md](harness-patterns-and-eval.md) §3.4。

`scripts/eval-health.rb <repo-root> [--trace-json p] [--bank-json p] [--history p] [--no-write] [--json p] [--quiet]`。`make eval-health`。

- **维度(各 0–10,按风险加权,OpenSSF 风格)**:`structural` 权重 10(Critical,`validate-skill.sh` pass/fail)· `routing_static` 权重 10(Critical,T1 blocking=0 满分、有 blocking 砸到 3、advisory 轻罚)· `trace` 权重 7.5(High,T3 pass/considered)· `bank` 权重 5(Medium,T2 pass/tasks)。
- **只跑确定性两维**(structural + routing_static,无 LLM、快);`trace`/`bank` 需 `claude` 且随机,**不自动跑** —— 用 `--trace-json` / `--bank-json` 把 T3/T2 报告喂进来,否则该维 **skip,权重按比例重分**给在场维(诚实标注 `dims=…`)。
- `composite = Σ(score_i·w_i) / Σ(w_i)`,只对在场维求和;skip 维自动从分母剔除。band:≥9 CLEAN / ≥7 WARNING / ≥4 NEEDS WORK / <4 CRITICAL。
- **advisory,永不因分数阻断**:退出码 `0` = 跑完 **或** 没有可算的维(都不是失败);`2` = 用法/setup 错(`<repo-root>` 不对或无 `skills/` 目录)。低分、坏报告、空历史都不会非 0。畸形的 T2/T3 报告(非对象 / 非整数 / `pass>total`)直接 **skip,不静默打分**。**绝不接进 `check-ccl-skills.sh`**。二元门禁(结构校验 + T1 blocking)仍是真值、独立挡 merge,与这个分无关。理由是 Goodhart 律(measure 变成 target 就不再是好 measure):一旦这个综合分成了 merge gate,人会去调分而不是修仓。
- **corpus/version 守卫(防跨变更 task-bank 当稳定指标比)**:每条历史记 `corpus`(= task-bank + golden-traces 输入内容的指纹)+ `repo_sha` + 在场 `dims`。**趋势 delta(IMPROVING/DECLINING)只跟最近一条 `(corpus, dims)` 都相同的历史比**;否则打印"baseline reset, not compared",不偷偷比。这样"加了 10 条简单 task → 分涨了"不会被读成真进步(尺子换了)。
- **历史文件**:默认 `eval/health-history.jsonl`,**git-ignore**(同 Goodhart 理由:committed 的数会招"调数不修仓";也免 append 把树搞脏)。`--history` 可改路径,`--no-write` 不落盘。
- **基线**(本机、本 corpus):确定性两维 = `9.5/10`(structural 10 + routing_static 9,advisory=1)。
