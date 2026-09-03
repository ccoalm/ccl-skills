# Harness Patterns & Skill Eval

公开 harness / agent 文献里的成熟命名概念 + skill 系统的对应映射。让我们的 skill 互引用 / extraction / debug 时能用业内通用术语，而不是各自发明。

不替代 Anthropic / OpenAI 等官方 harness 文档 — 这份只总结**与我们 skill 系统直接相关的部分**。

## 外部来源（可核验）

- **Anthropic, "Building effective agents"** (anthropic.com/engineering/building-effective-agents, Dec 19 2024) — workflow vs agent 区分 + 5 workflow patterns（base taxonomy，不是最新 harness 指南）
- **Anthropic, "Building agents with the Claude Agent SDK"** (Sep 29 2025) + **"Effective harnesses for long-running agents"** (Nov 26 2025, anthropic.com/engineering/effective-harnesses-for-long-running-agents) + **"Writing effective tools for agents"** (Sep 11 2025) — 后续补充（long-running 已提炼入 §6）
- **Anthropic, "Harness design for long-running application development"** (anthropic.com/engineering/harness-design-long-running-apps, WebFetch 核 2026) — 比上一条更新：从一句话长跑**建完整应用**的 generator–evaluator–planner 三角色 harness（提炼入 §6.1）。这是 Anthropic 自己的 harness-design primary 例；社区"loop engineering / 写循环不写提示词"的公开说法（Cherny / Steinberger 等）是**相关但独立的二手讨论** —— 没有直接一手源就按 hypothesis 对待，别把本文当成那套口号的出处
- **Anthropic, "Effective context engineering for AI agents"** (2025, anthropic.com/engineering/effective-context-engineering-for-ai-agents) — context 即稀缺资源 / compaction / 结构化笔记 / JIT 检索 / context rot（提炼入 §5）
- **Anthropic, "Demystifying evals for AI agents"** (Jan 09 2026) — agent eval 方法（realistic tasks / robust criteria / multiple graders / transcripts）
- **Anthropic Claude Code sub-agent docs**（Claude Code 官方文档 sub-agents 段）— sub-agent 隔离 / 独立 context window / 独立 permission
- **Anthropic, "Building multi-agent systems: When and how to use them"** (claude.com/blog, Jan 23 2026) — single-agent-first 三问（真实约束 / 按 context 而非按角色拆 / 有清晰验证点）、3–10× token 溢价、verification-subagent 模式（提炼入 `multi-agent-delegation` 的 fan-out gate）
- **Google Research, "Towards a science of scaling agent systems"** (arXiv 2512.08296, Dec 2025) — 并行可分解任务下集中式协调收益大；严格顺序推理任务所有多 agent 变体退化；独立并行 agent 的错误放大远高于带 orchestrator 的 hub；单 agent 基线已强时协调收益递减或为负
- **Cemri et al., "Why Do Multi-Agent LLM Systems Fail?"** (arXiv 2503.13657, NeurIPS 2025) — MAST：3 类 14 种失败模式（§2 映射表）；多数失败源于系统设计而非模型
- **Cognition, "Don't Build Multi-Agents"** (Jun 2025) — 两原则：共享完整 trace 而非摘要；动作携带隐式决策、冲突决策产坏结果（提炼入 fan-out gate 的 shared-decisions 项）
- **SWE-bench** (Jimenez et al., arXiv 2023, ICLR 2024, Princeton + UChicago) — agent 在真 GitHub issues 上的 task replay eval
- **Aider benchmarks / leaderboard** (aider.chat/docs/leaderboards/) — code editing/refactoring 固定 task set + pass rate
- **AutoGen** (Microsoft Research, 2023) — multi-agent conversation framework
- **LangGraph** (LangChain, 2024) — graph-based agent orchestration
- **mem0 / MemGPT / Letta** — agent memory layering
- **OpenSSF Scorecard** (github.com/ossf/scorecard) — 仓库安全/健康度评分:**每 check 0–10 → 按风险加权聚合 0–10**(Critical=10 / High=7.5 / Medium=5 / Low=2.5),weekly 扫 + 公开 BigQuery 数据集追历史。直接印证"加权 0–10 综合分 + 趋势"是业内做法(§3.4 的外部锚)
- **Goodhart's law**(Goodhart 1975,英格兰货币政策;Strathern 1997 普及化:"When a measure becomes a target, it ceases to be a good measure")— 度量一旦成为目标就被博弈优化、失去原效。§3.4 综合分**只做 advisory 不当 gate**、历史文件 git-ignore 的依据
- **Eval-driven development**(evaldriven.org + Braintrust 等多个独立 practitioner 源)— 改动前先写 eval/场景、每次改动跑同一套、**绝不为过测试而特判 eval**;把"改了才发现"提前成"改前就量"。§3.2 的 authoring-time RED-baseline + F4 防作弊(冻结 task、改 skill 顺手改测试告警)即此实践;映射的"watch it fail first"= TDD red-green(`superpowers` owns)
- **Anthropic `skill-creator`**（github.com/anthropics/skills, `skills/skill-creator/SKILL.md` + `agents/analyzer.md`, head 2026-04-20）— 官方技能创建/改进/度量 recipe：with-skill 与 baseline 两臂同轮起跑、每臂记 token+耗时、逐断言 pattern 读数（两臂恒过/恒挂/单侧过/高方差）、description 触发 eval（20 条 should/should-not、近似负例、每条跑 3 次、60/40 held-out 选 best）。§3.1 的两臂定义、成本列与逐断言读数三条即借此
- **Trace2Skill**（arXiv 2603.25158, 2026）— 根 SKILL.md 放广适用程序、auxiliary 放**低频**细节（§2.1）；并行分析 + 分层归并优于顺序依赖的逐条编辑（§2.4、App. B）；因果讲不通的失败不进 patch pool（§2.3）。`attention-budget-ratchet.md` 的"按触发频率放置"与普查工具的依据之一；059/060 轮已借其归并骨架
- **ACE — Agentic Context Engineering**（arXiv 2510.04618, 2025-10）— context 以带 id 与 helpful/harmful 计数的条目化 bullet 表示、增量 delta 更新、grow-and-refine 去重；命名两种失效：brevity bias（优化把 context 压成短而泛的口号）与 context collapse（整体重写把细节压没）。前者是我们的"过压缩"警戒，后者是零损失义务表存在的理由；计数器对应本仓的引用访问普查
- **IFScale**（arXiv 2507.11538, 2025-07）— 指令密度上升时遵循率下降、偏向靠前指令；证据档与用法见 `external-practice-controls.md` §Instruction-following mechanisms 表
- **GAO-01-1015R / GAO-02-195**（2001–2002，NASA lessons-learned 流程调查）— 教训库"收了不用"的经典证据：管理者不常识别/提交/使用教训、系统耗时、不熟悉他中心的教训、缺激励。这是"教训要推到触发点而不是存进库"（firing point 而非 ledger）这条本仓设计的外部反例锚

---

## §1 Workflow vs Agent + 5 workflow patterns

**定义**（Anthropic 2024-12 — base taxonomy；后续 Agent SDK / long-running harness / evals 帖子补充更细落地）：

- **Workflow**：LLM 与 tool 通过**预定义代码路径**编排（执行流程是人写死的）
- **Agent**：LLM **自主决定**下一步动作和 tool 使用（执行流程由模型决策）

Workflow 更适合可预测 / 可调试 / 可控成本的任务；agent 更适合开放领域 + 任务边界模糊。先从简单 workflow 起手，只在真需要 model-directed 决策时才升级到 agent。

**Anthropic workflow taxonomy 的 5 个 patterns**（按复杂度递增；非"所有 harness patterns"穷举 — ReAct / Reflexion / Tree-of-Thoughts / planning-search 等 agent 类 pattern 不在该 taxonomy）：

| Pattern | 形态 | 我们映射 |
|---|---|---|
| **Prompt chaining** | step 1 → step 2 → step 3 顺序，每步输出是下步输入；中间可加 gate check | 多轮 codex review（迭代收口）；`source-to-skill-extraction.md` 的 charter → source register → draft → validate 顺序 |
| **Routing** | input classifier 决定走哪个下游 path | **SKILL.md `Use when` / `Skip when`** + 跨 skill 路由；`product-rd-workflow` 路由到 stack-dev |
| **Parallelization** | 独立子任务并发执行，结果聚合。两子型：**Sectioning**（任务拆成独立块各跑）和 **Voting**（同任务多次跑取共识） | Sectioning = `multi-agent-delegation` 分发；**Voting = 同一改动并行跑 codex review + challenge** 两个独立视角（彼此不串行，结果聚合）|
| **Orchestrator-workers** | 中央 LLM 动态拆任务给 worker LLM，再聚合结果 | `product-rd-workflow` orchestrate + stack-dev workers |
| **Evaluator-optimizer** | 一 LLM 产出，另一 LLM 评估并给反馈，循环迭代 | **顺序的 review → fix → re-review 循环**（与 Voting 区别：是串行 + 迭代，不是并行 + 投票）|

**用**：写 skill / 设计新 workflow 时，先识别这是哪种 pattern（不识别会导致命名混乱：把 voting 写成 evaluator-optimizer、把 routing 写成 chaining 等，跨 skill 文档读起来不一致）；用通用术语描述以便互引用清晰。

**不用**：纯 chat-based 单次回答不算 workflow；不必硬套 5 patterns；agent 类（ReAct / Reflexion 等）超出此 taxonomy。

**落地**：
- 跨 skill 路由文档里直接用 `routing / orchestrator-workers / evaluator-optimizer` 术语
- 解释自动化流程时优先用 workflow 命名（更可预测），只在边界模糊时退到 agent
- 区分**有 gate 的 chaining**（推荐）vs **裸 chaining**（脆弱）— 失败模式：裸 chaining step N 失败时整链失败，无中间产物可继续；有 gate 的 chaining 每步 validate 后可在中间点止损 / 切策略

---

## §2 Sub-agent isolation patterns

**定义**（Anthropic Claude Code docs + 业内通用）：sub-agent 是**独立 context window** 的工作单元 — 不继承父 agent 的对话历史，由父 agent 通过 prompt 显式传递必要上下文。

**Why isolation matters**：
- **Context 不污染**：父 agent 的失败尝试 / 错误推理不传染给 sub-agent
- **Cost 可控**：sub-agent 用完即弃，不累积 token
- **Failure 可定位**：sub-agent 失败只回报 result，父 agent 决定 retry / escalate / proceed

**典型 isolation 失败模式**（**内部命名的 isolation failure checklist**，非业内 literature 标准命名 — 自用方便定位失败种类）：

| 失败 | 症状 | 修 |
|---|---|---|
| **Context starvation** | 父 agent prompt 太短 / 模糊，sub-agent 缺关键信息硬编 | prompt 必含：任务目标 + 已有 context 摘要 + 期望输出形状 + 边界（"不要做 X"）|
| **Result inflation** | sub-agent 返回大段 raw output，污染父 agent context | prompt 显式 "report in under N words" + 结构化字段 |
| **Hidden dependency** | sub-agent 默认能读某文件 / 调某 tool，父 agent 没确认 | prompt 明确列可用工具 + 文件路径 |
| **Trust drift** | sub-agent 自信报告"完成"，实际只完成一部分 | 父 agent 用独立 verification（read diff / grep / 跑 test）核对，不只看 sub-agent 自述 |

**在本 scheme 怎么落**：
- `multi-agent-delegation` skill 主体覆盖 isolation 决策；本 ref 补充失败模式 checklist
- 用 sub-agent 后**必须独立核对结果**（reading diff / grep specific changes），不依赖 sub-agent self-report

- **与文献标准命名（MAST）的对应**——上表是自用名；评审一次失败的 worker 返回时必须先按 MAST 类别定位该修哪一层（MAST 的结论：多数失败源于系统设计而非模型，先改 brief / 拓扑 / 验证，别先换模型）：

| MAST 类 | 失败模式 | 对应上表 / 我们的规则 | 修哪层 |
|---|---|---|---|
| FC1 系统设计 / 规格 | 1.1 违背任务规格；1.2 违背角色规格；1.3 步骤重复；1.4 丢失对话历史；1.5 不知终止条件 | Context starvation；`multi-agent-delegation` 的 spec-compliance review、同错 ~3 次升级、wall-clock deadline、stop line | brief（目标 / 边界 / 输出形状 / effort budget）或拓扑 |
| FC2 agent 间失配 | 2.1 对话重置；2.2 该问不问；2.3 任务跑偏；2.4 扣留信息；2.5 忽略他方输入；2.6 推理-动作不一致 | Hidden dependency；brief 逐字携带全局约束与邻接契约、5 字段 escalation、owned-path manifest 核对、integrate 步查隐式决策分歧 | brief 契约 / escalation / 集成检查 |
| FC3 任务验证 | 3.1 过早终止；3.2 无 / 不完整验证；3.3 错误验证 | Trust drift；不信 success report、blocked 声明先补救、reviewer 的 verdict_scope / cannot_verify 槽位 | 控制器侧验证 |

Result inflation 没有 MAST 对应——它是 context / 成本问题，不是任务失败。

---

## §3 Skill effectiveness eval（task replay / before-after / golden trace）

**定义**（**内部 skill eval 方法 — 受 SWE-bench / Aider leaderboard / Anthropic 2026 evals 启发的本团队 recipe**，非已发表的命名方法）：业内 agent eval 走固定 task-set + golden answer 比对（SWE-bench / Aider 是此类）。Anthropic 2026 evals 文章强调 realistic tasks / robust success criteria / multiple grader types / 读 transcript（不只看 final prose）。

我们的 skill 没有这样的 benchmark。**真问题**：怎么知道 skill 改动是变好还是变坏？

3 个可落地方法（轻重排）：

### 3.1 Before-after task diff（轻量）

**跑之前先过 consolidation 检查**（canonical 在 `SKILL.md` 的 `Consolidate and retire rules` 条，不在这里重复）：候选若是"往既有技能加文本"型，那条规则要求先找同 failure-class 的既有 owner 并**合并**——那是合并决策，不是一个待验的新增文本，别拿 eval 给重复落地放行。本处只加一条读数纪律：**别把零差分读成"这类文本一律无效"**。实测踩过一次：一条候选原理句被既有的一条判定规则整条覆盖，5 任务 16 次跑两臂行为无差异，唯一差别是 agent 引用时换了措辞；把那个结果当通用结论，就是把一次选题失误记成了规律。

每次 skill 重大改动前：
1. 在 changed skill 触发场景下记录**预先冻结的 task set 中代表性 task** 的 agent 行为（任务描述 + tool calls + final output）
2. 改动后跑同一 task，diff 两次行为
3. **diff 显示行为**朝预期改善 = 改动有效；恶化 = 反效；**unchanged 不在这一步定性**——按下面 anti-game 最后一条先分清成因再下结论

**Anti-game 要求**（防止 agent 自选简单 task 造假证)：
- **Task bank 在 skill 改动之前就冻结**，agent 不能改动后再挑 task
- 抽样必含历史失败 / user correction / known regression case，不只 happy path
- 至少 1 个 hard / control case（agent 改不动也不该挂的 task）
- reviewer 或 challenger 核准 task 抽样
- 成功标准 改前定义 (specific assertions on output / behavior)
- 比对 **transcript + outcome**，不只 final prose（per Anthropic 2026 evals）
- **两臂的定义按改动类型定**：新技能 → 对照臂是 *无技能*；改既有技能 → 对照臂是改前快照（先 `cp -r` 冻结再改，别拿改后的树当基线）；两臂**同一轮并发起跑**（the with-skill and baseline arms must start in the same turn），别先跑实验臂再补对照臂。每臂记录 **token 用量 + 耗时**（宿主的子 agent 完成通知里有，过时不候），效果与成本同列——一条只提 pass rate 不提成本的对照没法判"值不值"（Anthropic skill-creator 2026 的 benchmark 形态）
- **逐断言读数，不只看聚合通过率**：两臂都恒过 = 该断言不区分技能价值；两臂都恒挂 = 断言坏了或超出能力；有技能过、无技能挂 = 技能在此生效；有技能挂、无技能过 = 技能在此帮倒忙；高方差 = 断言 flaky 或行为非确定。任何一类都先记录再定性，聚合分会把这些抵消掉（同上源 analyzer 判据）
- **两臂无差异时不得在这一步定性为该文本无用**：成因至少两种——既有规则已覆盖该 failure-class（那是合并决策，见上），或该行为在 host 基线上本就存在。要分清得另取证据，**本节不规定取法**：低 N、臂配置混杂、以及"只给对照臂换夹具或换权限就多一个变量"这三样让这类归因很容易做错，宿主自身系统层也始终在场。取不到可靠证据就把成因判为**未确定**，别猜一个填上——本节判"改动有没有效"的对照始终是 before/after 两臂

实测踩过的那次里，零差分的成因是既有规则已覆盖，不是这句话本身无效。

**用**：本 skill `skill-extraction-workflow` 自身的 R0 / drafting 类大改动；产品 skill 的 routing 调整。

### 3.2 Golden trace（中量）

为每个 stable skill 沉淀 1-2 个 **golden agent trace**：
- 触发 prompt（"写测试用例 for 这个 module"）
- 期望 agent 行为序列（"读源 → 跑 testing-strategy → 写矩阵 → 入 Bitable"）
- 期望最终产出（"N 条 TC + matrix"）

skill 改动后，让 agent 重跑这条 trace，**结构性偏离 = 回归信号**。

**用**：被多 skill 引用的 hub skill（`product-rd-workflow` / `defect-diagnosis` / `testing-strategy`）。

**不用**：单次或 niche skill — 写 golden trace 的成本 > 收益。

**双用途（authoring-time RED-baseline）**：同一条 golden-trace 机制(F4 Tier-3 `eval-golden-trace.rb`)除了**回归**,还可当**改技能前的 RED**——改前手动跑触发场景看真 agent 不带改动时是否**真的**路由错(**只有真观察到 miss 才算 RED**;PASS/INCONCLUSIVE 不算),改后再看 compliance。借的是 **eval-driven development** 的*原则*(改动前先量、绝不为过测试而特判),**不是**说这套小 N、advisory、只断言路由结构的回放有生产级 eval gating 的严谨度。落地契约 + 防作弊注意(优先用既有冻结 trace;同改动新写的 trace 是 self-authored 证据)见 [validation-and-landing.md](validation-and-landing.md) "Optional real-agent RED-baseline"。**可选**:小改动用**执行并记录**的 pressure scenario 即可。code 级 RED-GREEN 方法 route→`superpowers:writing-skills` + `:test-driven-development`,不抄。

### 3.3 Behavioral task-set A/B（重量，system-wide 变更专用）

学 SWE-bench 思路：维护一个固定的**行为夹具集**（每条 = 一个 prompt + 一条 rubric，覆盖一条纪律轴：安全反射 / 无证据不声称完成 / 回归测试负控 / 假绿识别 / re-entry gate / 测量先于断言 …），把**候选操作层**与**当前操作层**双臂并跑同一夹具集，逐夹具比行为。

**落地形态**（不再是"待用"）：`skill-extraction-workflow/scripts/skill-behavior-eval.py` + `eval/behavior-fixtures.jsonl`（12 条起，与 `eval/routing-tasks.jsonl`、`eval/golden-traces/` 并列同一 `eval/` 语料区）。两臂：

- `current` —— 普通 `claude -p`：装好的 bootstrap + 全部 skills（当前操作层）。
- `candidate` —— `--settings '{"disableAllHooks":true}' --disable-slash-commands --append-system-prompt "$(候选契约)"`：**关掉 ccl-skills 的 bootstrap + skills**，把候选契约**追加**注入。注意这不是"唯一常驻层"——base Claude Code 系统层仍在；准确说法是"移除 ccl-skills 层后、以候选契约为附加操作层"。契约用 `--contract PATH`（或 env `CANDIDATE_CONTRACT`）传。

**输出 = 能力 delta 报告（这才是 A/B 的点）**：跑完双臂后产出 `capability-delta-report.md` + `judge-verdicts.jsonl` —— 逐夹具给"候选比当前**减少的能力** / **新增的能力** / **表现怎么变**"+ 汇总 delta 计数。delta 由 **LLM-judge**（一个模型读**两臂**回答、对着 rubric 轴推理行为）产出——这正是硬教训要求的"判断评分"的**自动形态**,不是关键词打分。它是 judgment-**assist** 非 score:原始回答留存可审、judge 对畸形输出拒绝猜判、每条 security/authority/data-loss 轴或低置信行标 🔴 HUMAN 待人眼确认。`--no-judge` 则只出**填空脚手架**(judge 不跑、由人填 delta)。别只把双臂回答堆一地叫"自己看"——工具**一定要产出 delta**。

**judge 的固有限度（诚实写清,别当它是权威裁决）**:(1) LLM-judge 读的是**不可信的模型输出**,理论上可被 answer 里的注入操纵——所以 answer 里出现指令状内容会**程序化强制标 🔴 HUMAN**(judge_prompt 里也 fence+禁止服从,双保险),但没有任何单行 verdict 在没核对原始回答前算权威。(2) 敏感轴的关键词表**永远不可能穷举**——它只是 best-effort 兜底;**真正权威的标记是夹具里显式 `"human": true`**,凡涉及 security/权限/隐私/PII/数据丢失/删除/计费/凭证 的夹具**必须**设它(见 `behavior-fixtures.jsonl` 里 F1/F5)。(3) 每行只取单 sample,多 sample 差异看 `.sN.txt`。incomplete(缺臂/陈旧/judge 报错/额度跳过)行**顶部横幅显式计数**,别把部分跑当满覆盖。(4) **invoke 证据 vs 自报(name≠invoke)**:agent 回答里"我先加载 owner 技能 X"是**自报**,不等于真调了 Skill 工具。harness 从 stream 里抓真实 `Skill` tool_use 记进 `# skills_invoked` 头(空则 `[]`)——这正是 owner-dispatch invocation-evidence 那条"验 invoke 别信 name"用在 eval 自身。**注意**:这个头是 `#` 注释头,`read_saved_response` 会把它剥掉,所以**自动 LLM-judge 看不到它**;它是**人工/原始文件审计**的证据,不喂给 judge。判"某能力靠加载 skill 存活"时**人工先看 `# skills_invoked`**:若为空、而纪律却在,说明能力来自契约文本/通用知识而非被加载的 skill,别把自报当已加载。

**触发边界（不是 routine 迭代工具）**：只在**一次改动同时改动多行为的常驻操作层**时用 —— 换/瘦 bootstrap、替换路由层、采用一套新操作契约。单个 skill 的普通改动仍用 3.1（before-after）/ 3.2（golden trace），别用这个重家伙。它回答的是"压缩/替换操作层后,安全纪律是否还在",不是"这条 skill 改好没有"。

**硬教训（首次真跑校准出来的，写进来免得重犯）**：

1. **判断评分,不是关键词评分。** regex/关键词 grader 是**噪声**:会 false-fail 真正优秀的回答（把否定句里被引用来反驳的禁语当命中;概念在但精确词不在;行为做了但没吐出 skill 的**名字**),并在同夹具的不同 sample 间 PASS↔FAIL 翻转。所以 harness **不自动打分**:它把每条夹具双臂 × N sample 跑完、连同 rubric **存下回答**,由人（或另行校准、带 human-golden 锚点的 LLM-judge）读判。报告**逐夹具**给结论,永不给单一 regex 通过率。
2. **非确定性是真的。** 同 prompt 不同跑会微差,`--samples ≥2`,单 sample 只当一个数据点。
3. **rate-limit 中止护栏。** 一次全量 A/B（12 夹具 × 2 臂 × 2 sample = 48 次 headless 跑）会吃掉可观的额度池;harness 从流里解析 7 日利用率,超 `--stop-util`（默认 0.93）**在下一次跑前中止**、存部分结果、可续跑,免得大 A/B 把用户的真实活儿挤没。
4. **抓全部 assistant 文本。** route-first 的操作层会**先**吐一条路由消息**再**给实质答案;只抓最后一条会漏掉实质回答。拼接全部 assistant text 再判。
5. **臂配置细节。** `--bare` 会连 OAuth/keychain 认证一起去掉（需要 API key,否则跑不起来）;`disableAllHooks + --disable-slash-commands` 才是"去掉 bootstrap 但保住认证"的正确姿势 —— 已在 candidate 臂验证:该 flag 组合下 agent 确认自己没有 ccl-skills 路由。

**用时机**：操作层月级别稳定 + 要做一次 system-wide 换层/瘦身时;把它当"换层前的对抗性回归证据",不是频繁迭代期的日常闸。

### 3.4 Health signal dashboard（描述性 roll-up）

3.1–3.3 都保留各自的判定对象；跨时间还需要一个快速入口，显示本次有哪些信号在场、哪些维度变化，方便继续下钻。

**外部锚**:OpenSSF Scorecard 用每个 check 0–10、风险加权聚合和历史变化展示代码仓信号。这里仅借它的**展示形态**，不继承“一个总分代表整体健康”的解释。

**我们的映射(route-not-copy)**:`eval-health.rb` 展示四个信号，并保留一个兼容既有实现的加权 0–10 值与同尺子变化 ——

| 维度 | 风险/权重 | 0–10 来源 |
|---|---|---|
| `structural` | Critical 10 | `validate-skill.sh` pass→10 / fail→0 |
| `routing_static` | Critical 10 | T1 blocking=0→满分、有 blocking→3、advisory 轻罚 |
| `trace` | High 7.5 | T3 pass/considered |
| `bank` | Medium 5 | T2 pass/tasks |

`composite = Σ(score·weight) / Σ(weight)`,只算在场维(skip 维权重重分,同 OpenSSF/gstack)。确定性两维自动跑,T2/T3 喂报告进来(否则 skip)。契约见 [eval-routing.md](eval-routing.md) 的 Health roll-up 节。

**三条不可省的护栏**:

1. **advisory,不当 gate**(Goodhart):度量变成 target 就被博弈。综合分**永不接门禁**,二元门禁(结构 + T1 blocking)仍独立挡 merge;历史文件 git-ignore,免得"committed 的数"招人调数不修仓。
2. **corpus/version 守卫**:T2/T3 的 task-bank、golden-traces **本身会变**。加 10 条简单 task,pass-rate 涨了但仓没变好 —— **尺子换了**。每条历史记 `corpus` 指纹(输入内容 hash)+ 在场 `dims`;**趋势只跟 `(corpus, dims)` 全同的历史比**,否则 baseline reset 不偷偷比。等价于 gstack-health "尺子变了就从新基线重新追"。
3. **不平均掉质量失败**:结构、路由、真实回放和任务结果的语义不同；任何质量或安全阻断仍由自己的门禁决定，不能被其它维度的高值抵消。

**用**:周期性看一眼信号变化并下钻。**不用**:别据此单独声称仓库整体变好/变差，别把它当通过标准、别 committed、别跨 corpus 硬比。

---

## §4 Failure escalation thresholds

**定义**：agent 何时应**停止重试 / 升级到人** vs **继续自主迭代**。Anthropic + AutoGen 等都有讨论但无统一标准。

**Trigger 类别**（分两种性质 — 命中行为不同）：

**Hard stop（命中即停 + 必须用户确认 / 解决依赖才继续）**：

| Trigger | 启发阈值 | 行为 |
|---|---|---|
| **副作用边界触达** | 任何 destructive op（rm -rf / force-push / drop table / cross-team shared-doc overwrite）| stop + 等用户确认 |
| **不可解决依赖** | 等外部服务 / 等人审批 / 等数据到 | stop + 报当前状态 + 等依赖解除 |

**Warning（命中即报告 + 用户决策继续 / 切策略 / 停，不自动停）**：

| Trigger | 启发阈值 | 决策 |
|---|---|---|
| **同一失败重复 N 次** | N = 3（同 error 第 4 次出现）| 报告 + 等人；**严格指"identical retry"**，不是 challenge 多轮发现新问题 |
| **预算 warning** | tool call > 100 / token 紧张 / wallclock > 30 分钟 | 报中间状态 + 用户决定继续 / 切策略 / 停；不自动停（大 codebase + flaky 外部依赖 + 长跑但有进展的工作 都可能合理超阈值）|

**与 convergence standard 的区别**（重要）：本节阈值针对 **same-error retry**（重复尝试同一失败方案），不替代 [convergence standard](../SKILL.md)（针对 challenge round — 只要每轮还有 P1 required 就继续，不按 round 计数停）。区分：
- **Same-error retry**：每次尝试本质相同方案 → N=3 后升级
- **Challenge convergence round**：每轮发现不同新层 / 新 P1 → 继续直到 0 P1 required（recursive self-validation 类 extraction 可能走 5-6 轮，每轮抓不同层的新 P1，不该按 round count 停）

**Escalation 必含 5 字段**（避免"escalate"沦为"stop"）：
1. **Blocker**：具体卡在哪步（不是"卡住了"）
2. **Attempts made**：试过哪 N 种方案 + 各自结果
3. **Current state**：worktree diff / 工作区状态 / 已 commit 哪些
4. **Safest next action**：建议的下一步（让用户对齐）
5. **Lower-risk continuation**：agent 能不能在等 escalation 同时做其它低风险工作？能 = 继续；不能 = 停

职责切分：`multi-agent-delegation` skill 定义 agent / sub-agent 执行中的 broad "stop and escalate" 条件 + review / completion gates；本 ref §4 补充通用 failure-escalation thresholds（same-error retry / budget warning / dependency stop）+ escalation **message 5 字段 contract**。

---

## §5 Context engineering（harness 的核心 = 管 context，不是堆 prompt）

**定义**（Anthropic "Effective context engineering for AI agents" 2025，primary，WebFetch 核）：harness 的核心不是更聪明的 prompt，而是把**有限 context 当稀缺资源**管理 —— "find the smallest possible set of high-signal tokens that maximize the likelihood of some desired outcome"。原因是 **context rot**：token 越多，模型从中精确召回的能力越降（部分源于 transformer attention 的 n² 关系等因素），所以 working set 要小而高信噪，不是越塞越好。

5 个技术 + 我们的映射：

| 技术 | 含义 | 我们已/应怎么落 |
|---|---|---|
| **最小高信噪集 / 渐进式披露** | 不预载全部，只放当前所需 | SKILL.md 入口只放 trigger+路由，细节进 references 按需读；skill-system 三级渐进式披露（见 `llm-inference-integration` 的 retrieval-agent-safety 参考）|
| **Compaction** | 近 context 上限时摘要历史（保留架构决策/未解 bug/实现细节，丢**冗余/可复现**的 tool 输出），重开窗口 | 长 extraction 线程靠 harness 自动 compaction；写 skill 时把"决策+未决项"放在可被摘要保留处。**只丢可复现/噪声输出**：compaction 前把 load-bearing 实证（命令 + 路径/source id + 关键摘录 + 退出码 + validation/audit 结论）落进 durable 产物，别让下一 session 从丢了唯一可证伪细节的摘要里"确认"完成 |
| **结构化笔记 / agentic memory** | 在窗口外持续写笔记（NOTES.md / memory tool），需要时再注入；"persistent memory with minimal overhead" | **我们的 source-register + 私有 provenance YAML + per-host scratch 就是外部持久记忆**；跨轮的 owner-map / R0 结论写文件、不靠记忆。**项目级分层 context 文件（从根目录到各层目录的 AGENTS.md/CLAUDE.md/agent.md "地图模式"）也是这一条**：每层约定写在该层文件，agent 进到该目录才加载，是文件系统级的结构化外部记忆 |
| **Just-in-time retrieval** | 只存轻量标识（文件路径/查询/链接），运行时再拉数据，不预载 | reference-loading 指针（`read references/X.md`）+ alias-map 查表 + 分层 AGENTS.md 按目录加载都是 JIT。**但 JIT 不能绕过 trigger 必读的 ref/gate**（R0 / lifecycle handoff / dual-track / incident / two-source 等必读项）：minimal-context 只省非必需上下文，不省强制工作流依赖 |
| **Sub-agent 隔离** | 专项 sub-agent 独立窗口，只回精简摘要（context-engineering post 给的典型值 1,000–2,000 token）| 见 §2；"report in under N words" 即此条落地 |

右海拔 system prompt（"specific enough to guide … yet flexible enough … strong heuristics"）= 我们 skill 措辞的同一标准（对应 skill-authoring 的 set-appropriate-degrees-of-freedom）。

**用**：写/改 skill 时问"这段 token 值不值它占的位置"；长流程靠外部文件（register/provenance/git）保状态，不靠长 context。

## §6 Long-running / 多 session harness（跨 context 窗口保进度）

**定义**（Anthropic "Effective harnesses for long-running agents" 2025，primary，WebFetch 核）：长任务的核心难点 —— **"each new session begins with no memory of what came before"**（每个新 session 从零记忆开始）。只靠 compaction 不够；解法是 **durable、可查询的状态产物**跨窗口桥接：

- **进度文件**（如 `claude-progress.txt`）：记录已做/在做
- **特征清单**（JSON，逐条带 pass/fail 状态）：**用 JSON 不用 Markdown** —— 模型更不易误改/覆盖 JSON
- **git history**：descriptive commit message = 可恢复 checkpoint

**Context reset vs compaction**（区分）：compaction 原地摘要、保连续性但不给干净 slate；**reset 给干净 slate，代价是 handoff 产物必须含足够状态让下一 session 干净接手**。新 session 第一步：读 git log + 进度文件 get up to speed。

**单 session 循环**：① 读目录状态+进度产物 → ② 选下一个未完成项 → ③ 增量实现 → ④ **按任务合适的真实验证后才标完成**（web app 场景优先 browser/end-to-end 验证；不验证会"以为做完、实际没通"）。反模式：**一次想做太多（one-shot 整个任务）→ 半成品 + context 耗尽**；强制单项增量。

**映射到我们的 extraction**：多轮"深度提炼"本质就是 long-running 多 session 任务 ——
- durable handoff 产物按**存储类**分（R0 + lifecycle handoff 红线，不可混）：项目实证（真路径/key/分支/人名/provenance）只进**私有 scratch + 私有 provenance YAML**；shared 树的 source-register 只放**泛化方法行/模板**；git history 与 commit message 是 shared 树，**只用 sanitized label**。"状态进文件"绝不等于"把项目实证写进共享 register / 进度文件 / commit"。
- 单 session 循环 = per-round Skill 重新 invoke + charter（gather/plan）→ 落 diff（act）→ dual-track gate（verify-before-done）
- 反 one-shot = challenge **每轮只收敛一层 P1**，不一次性宣称全完成

**用**：任何跨多 session / 多轮的 skill 工作，状态进文件不进记忆（按上面存储类分流），每轮 verify 后才标 landed。**不用**：单轮小改不需要 progress-file 开销。

### §6.1 Generator–Evaluator–Planner build-harness（长跑*建应用*的前沿 harness 形态）

（Anthropic "Harness design for long-running application development"，primary，WebFetch 核 2026）：把"从一句话长跑建出完整应用"拆成三角色 —— 核心的 generator↔evaluator 回路就是 §1 **evaluator-optimizer**，planner 的 spec 展开 + sprint 契约协商是绕着它的 **chaining / orchestration**；整体不是新 pattern，别重造命名：

- **Planner**：把 1–4 句 prompt 扩成完整 product spec —— 只管产品上下文 + 高层技术取向，**不下沉实现细节**（过早定细节会向下游级联错误）。缺 planner 时 generator 会 under-scope、直接开干、产出更单薄。
- **Generator**：按 spec 实现 feature。（"一次一个 feature 分 sprint" 是**可拆的脚手架、不是角色本质** —— 原文在 Opus 4.6 后整段去掉 sprint、让模型自己分解；见第 4 条。）
- **Evaluator**：用**真交互**（如 Playwright 点真应用、测 UI/API/DB 状态）按任务专属标准打分，**不是只读 diff**。

四条落到我们已有纪律上（route-not-duplicate，别在本 ref 重写下游 owner 的规则）：

1. **别让 generator 自评**：模型对自己的产出会"自信地夸"，哪怕明显平庸；"把一个独立 evaluator 调 skeptical"比"让 generator 自我批判"可操作得多。= 我们的 **dual-track gate**（独立 review + 对抗 challenge）+ §2 trust-drift 的产品-harness 版。建产品 agent loop 时同理 —— role-separation / LLM-as-judge owner 是 `llm-inference-integration` 的 `model-prompt-evaluation.md`。
2. **写码前先谈拢 "done" 契约**：每个 sprint 前 generator 提"建什么 + 怎么验证成功"，evaluator 审范围（是否过大 / 测试太弱 / 漏边界）形成契约；之后 evaluator **按契约验收，不按最初模糊 prompt 验收**。= `product-rd-workflow` "先定 done 再实现" + challenge 审范围的强化命名（owner 仍是 product-rd，本条只给映射）。
3. **主观质量也能打分**：把"品味"拆成显式量规（原文举例：design / originality / craft / functionality 加权）+ few-shot 校准 evaluator 降 judge drift。量规/校准机制 owner = `llm-inference-integration` 的 `model-prompt-evaluation.md`（LLM-as-judge）；设计维度 owner = `product-ui-ux-design`。
4. **scaffold 是模型版本的函数、会过时**：能力提升后该**减 scaffold**、别镀金 —— 原文 **Opus 4.5** 后去掉 context-reset（靠 SDK 自动 compaction 接管），**Opus 4.6** 后又去掉 sprint 分解（模型能自己分解任务）。呼应 §5/§6 的 reset-vs-compaction：选哪个取决于当前模型、不是永久结构；写 harness 规则时别把某代模型的脚手架（context-reset / sprint 这类）写成不变式。

**用**：描述/设计多 agent 建造 workflow 时用 planner/generator/evaluator 通用术语，并把上面 4 条 route 到对应 owner。**不用**：小改 / 单文件任务不需要三角色 harness（原文成本例：solo 20min/$9 vs 全 harness 6hr/$200，~22×，与 `multi-agent-delegation` 的并行 ~15× 同量级 —— 只对高价值、宽度优先的工作划算）。

## §7 业界形态记录：插件式 agent harness（可借鉴的架构原则，非执行规则）

2026 年公开的一类 agent harness 把**运行时的每个部件都做成可热插拔的插件**——模型适配器、工具注册表、审批策略、沙箱、子 agent provider，乃至 agent 主循环本身——并声明"没有特权核心可打补丁"：扩展 = 在旁边挂一个插件，注册是可逆的效果，卸载即撤销。与我们 skill 层直接相关、值得在设计 agent 运行时或评审别人的运行时时拿来对照的原则（来源是一个仍在 developer preview 的开源仓，按 evolving portfolio 处理：**形态之一，不是标准**）：

- **能力三角**：一个可替换能力 = 接口定义 + 实现（提供者）+ 消费者（通常是面向模型的工具）三者齐备才算一个可替换的能力边界；只有其中一角不算。为**所有当前消费者**设计接口，不让某一个消费者的 UI/传输/私有需求定义契约；一个只有单个内部调用者的公共方法是不必要的 API 扩张——改成构造时注入的私有能力闭包。
- **事件即扩展点**：持久事实（可重放）、在途 agent 事件（观察/拦截）、能力事件（给能力边界挂策略）三类分开；瀑布式监听器必须显式 `next()` 委托，返回即短路。
- **组合分层**：运行时 = 有序的 profile/bundle 层叠加出来的插件树，每层可用 patch 覆盖任一行配置；能打印出机器实际启动的树来核对。
- **决策在执行处强制**：schema 省略、prompt 过滤、facade、监听顺序都不是权限边界（已进 `llm-inference-integration` / `product-rd-workflow` 评审清单）。
- 与之相对，把插件系统的**依赖注入与跨插件解析**做得很重是否值得，业界有争议（一线 harness 作者的公开评价：多数插件互不依赖，复杂 DI 在 90% 场景不带来收益，且跨插件类型仍需另解）；本仓不采纳"人人可发的插件生态"作为 skill 分发形态。
- **可执行落点在 llm-inference-integration，本节只留形态记录**：设计或评审 agent 运行时按该 skill 的 `agent-capability-composition.md`（能力三元、可逆注册、子 agent provider seam）、`agent-tool-dispatch.md`（结果外溢与护栏 wrapper）、`agent-session-persistence.md`（剪枝先于摘要、请求前 checkpoint）、`agent-command-sandbox.md`（policy 单一解析 owner）执行；不得再从本节直接提炼可执行规则——那会与 owner 侧产生双写漂移。

不含日志/持久化表述——模型可见内容与事件日志的账目不变量另由安全 owner 参与的独立设计处理。

## 故意不借鉴

| 概念 | 原因 |
|---|---|
| 多 agent 角色扮演（CrewAI / MetaGPT 的 PM / Engineer / Tester 多角色对话）| 我们的 SKILL.md routing 已分工，没必要再加 role-play 层 |
| Graph-based orchestration（LangGraph）| 我们的 routing 是 description-driven，不需要图结构；图结构对大型 workflow 才划算 |
| Approval mode / sandbox profile 设计 | Claude Code / Codex CLI 自带，无需在 skill 层重做 |
| Memory layering（mem0 多层显式分层 API） | 结构化笔记/外部记忆的**原则**已采纳（见 §5：source-register / provenance / scratch 即外部持久记忆）；此处只拒 mem0 式**显式多层分层 API** —— 当前 auto-memory + MEMORY.md + repo docs + register 已是事实层级，分层 API ROI 低 |
| Cost-aware model routing 显式实现 | 当前不是主要优化目标。**规范的是 tier（成本/延迟/能力档）**：简单/高频任务路由到便宜快档，复杂任务留 frontier 档 —— 这条原则不过时。**vendor 型号名只是举例、用时再核**（各家 tier 标签如 Haiku/Sonnet/Opus 且版本随时间漂移，别把型号或版本号写死进规则）。未来成本压力上来可重启显式路由 |
| MCP server 开发 | harness 实现层，不是 skill 内容；跳 |
