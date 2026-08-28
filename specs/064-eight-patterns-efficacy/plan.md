# 064 — testing-strategy 八大测试模式提效方案

目标：让 `testing-strategy/references/test-code-authoring-patterns.md` 的八大工程模式（§1 AAA/GWT、§2 命名、§3 smells、§4 Object Mother/Builder、§5 行为vs状态、§6 coverage、§7 隔离、§8 参数化/表驱动）真正作用于 agent 写测试的行为，而不是停留为目录里的被动引用。

## 0. 依据（本轮动笔前已完成的核验）

原理追查（同 session 前一轮）结论：八大模式按生效路径分三梯队——被做成 walked 步骤的（mutation walk）证据最强；有 core-rule 行内指针的（§3/§5/§6/§10）次之；只挂 Reference Loading 目录的（§1/§2/§4/§7/§8）处于休眠——SKILL.md Workflow step 4/5（fixture/断言设计的 transition 点）无加载指令，六个 stack dev 技能中五个零引用。

理论原文核验（2026-08-28，一手源）：

| 主张 | 一手源 | 结果 |
| --- | --- | --- |
| Mystery Guest 的归属 | xunitpatterns.com/Obscure Test.html | **偏差确认**：Mystery Guest 是 Obscure Test 的 cause；现文 §3 表把它列为「Erratic Test 含 Mystery Guest」。Erratic Test 的真实 causes 是 Interacting Tests / Unrepeatable Test / Resource Optimism / Test Run Wars 等（xunitpatterns.com/Erratic Test.html），现文该行描述的内容（外部依赖/顺序敏感/时间敏感）对应这些 causes，只是挂错了代表名 |
| Assertion Roulette / Eager Test 并行一行 | 同上 | **层级混**：Assertion Roulette 是 behavior smell 独立条目；Eager Test 在原书是 Obscure Test 的 cause（code smell 侧）。并列展示可保留，但 (Meszaros) 标签下的层级应准确 |
| smells 三分法 code/behavior/project | 同上（Behavior Smells 列表页可见） | 一致 |
| test pyramid 出处 | martinfowler.com/articles/practical-test-pyramid.html | **偏差确认**：概念出自 Mike Cohn《Succeeding with Agile》；该文作者是 Ham Vocke（发布于 martinfowler.com）。scenario-testing.md:133 的「Fowler-style test pyramid」归因不准 |
| Marick 论文年份 | exampler.com/testing-com/writings/coverage.pdf（版权页）；Semantic Scholar 索引 | 版权页 1997，个别索引 1999；现文写 1999。改注「1997（部分索引作 1999）」 |
| Fowler "Mocks Aren't Stubs" 界定 behavior vs state | 记忆级 + 上轮年份核验 | 低风险，本轮标 targeted-check：落地 Batch A 时打开原文核对 §5 引用的界定措辞 |
| North 2006 / Pryce 2007 / Osherove 2013 / Freeman&Pryce 2009 / Go wiki | 未核 | 书目条目、低风险，本轮不核（记录为 not-run）；若 Batch A 触碰其行则顺手核 |

## 1. Extraction Charter

| Field | Answer |
| --- | --- |
| Purpose | 防止「模式存在但不 fire」的休眠类失败：八大模式的第三梯队在写测试的 transition 点无触发；并修正三处对一手源确认的归因/分类偏差，防止错误归因被下游复制 |
| Scope | in：`testing-strategy`（SKILL.md 净字节受限编辑、test-code-authoring-patterns.md、scenario-testing.md 归因行）、`eval/behavior-fixtures.jsonl`（advisory fixtures）。out：六个 stack dev 技能的 class-wide 指针（deferred 切片 2）、lint 下沉（deferred 切片 2）、非八大相关的 references。无 covered-through watermark（首轮） |
| Depth | Full workflow extraction（含行为基线测量）+ 归因修正（非 wording：分类语义变化） |
| Result classification | failure/correction（休眠触发结构 = 观测到的结构性缺陷：step 4/5 无指针、5/6 stack 技能零引用、目录级引用为唯一入口；归因偏差 = 对一手源确认的错误） |
| Matching analysis | RCA 加宽：①触发/路由缺失（transition 点无加载指令）②机械控制缺失（无 closeout 自查、可判定谓词未下沉 lint）③检测缺口（eval 无测试工艺类 fixture，效果不可测）④陈旧过程模型（「写进 reference 即生效」假设，被 023-I 跨 provider no-delta 证伪）。反事实检验：仅修①而无③，效果仍不可知——所以基线测量先行 |
| Failure mode | 弱执行会：改了文案但无基线对照（无法证明 delta）；SKILL.md 净增长撞 size gate；把 fixtures 做成正则判分复刻已废弃的 C3 老路；归因修正引入新的未核主张 |
| Lifecycle impact | 测试阶段（executor：testing-strategy）；实现阶段（stack dev 技能——deferred 切片 2）；评审阶段（code-review 不变，smell 识别已由 §3 指针覆盖）；提炼工作流（unchanged，无本工作流缺陷暴露）；产品工作流（unchanged，不动生命周期 gate） |
| Evidence plan | ①produced artifacts：本轮产物 = 本 plan、fixtures、基线测量数据（specs/064/evidence/）②一手源：xunitpatterns.com 两页、practical-test-pyramid、Marick PDF 版权页（已核，见 §0）③既有机制复用源：specs/023 的测量协议、register L76 的措辞 A/B 法、eval/AGENTS.md 的 advisory 契约④SKILL.md/引用文件现文（已深读） |
| Completion standard | 基线数据先于文案改动存在；SKILL.md diff 净字节 ≤0；dual-track（review+challenge）收敛；R0 zero-hit；register 行 append-once 带 RED-baseline/firing-path；三处归因修正每处带一手源 URL；deferred 项有 entry 条件记录 |

## 2. 批次

### Batch 0 — 基线测量（先于一切文案改动；判分标准先于被测改动）

1. 新增 3 条 advisory behavior fixtures（`eval/behavior-fixtures.jsonl`，`frozen_at_sha` 按契约）：
   - F28（review/judgment）：给一段含 3 个可命名 smell 的测试代码（条件逻辑、多场景断言堆叠、隐式外部文件依赖），让 agent 评审。判分谓词（结构化输出上机械可判）：命中 ≥2 个 smell 类 + 给出重写方向（拆分/参数化/显式 fixture）。
   - F29（impl/judgment）：「为 X 写测试」任务，输入含重复复杂对象构造。判分：输出用集中工厂/builder 而非逐测试复制构造 + 测试名表达行为而非方法名。
   - F30（impl/judgment)：同一逻辑 4 组输入。判分：参数化/表驱动而非 4 个复制粘贴测试函数。
   - 例域预选（本规则触发：≥2 个多行示例）：选用领域=图书借阅 / 天气缓存 / 运费计算（中性占位域）；拒绝了一个来源域（抽象记录：与本仓真实测试语料同形的域被拒绝，不记行业）；判分谓词避开正则-判语义的老路——只判结构化输出的机械字段（名称列表、是否出现参数化结构），语义留 advisory。
2. 跑 baseline：headless `claude -p`（haiku，每 fixture 10 轮），污染防护——临时 HOME 隔离全局 CLAUDE.md/auto-memory，跑前 grep 确认注入面干净（自测污染备忘）。记录 specs/064/evidence/baseline-*.json。
   - **执行偏差注记（codex review P1 处置）**：实际协议采用 023 同款 body-as-prompt + 中性 tmp 目录 + `--tools ""`，**未做临时 HOME 隔离**（隔离 HOME 会破坏 claude CLI 认证）；污染防护降级为对全部 ans 的事后 grep（0 命中，见 evidence/AGENTS.md）。两臂同环境同注入，差分有效性不受影响；绝对分受染面如实记入 evidence 边界节。
3. 基线判读：某 fixture baseline ≥8/10 → 该模式 agent 本来就会，对应文案投入降级（记录并缩减 Batch C/D 对应项）；≤5/10 → 值得投入，成为该项的 RED-baseline 依据。

### Batch A — 归因/分类修正（非 wording；一手源已核）

- `test-code-authoring-patterns.md` §3：L87 行改为「**Erratic Test**（Meszaros）：Interacting Tests / Resource Optimism / 顺序·时间敏感」；L91 Mystery Guest 行标注归属 Obscure Test；L88 Assertion Roulette（behavior smell）与 Eager Test（Obscure Test cause）标注层级。落地时打开 Fowler "Mocks Aren't Stubs" 核 §5 引用措辞（charter 里的 targeted-check）。
- Marick 年份：1999 → 1997（注：部分索引作 1999）。
- `scenario-testing.md` L133：「Fowler-style test pyramid」→「Mike Cohn 的 test pyramid（《Succeeding with Agile》；实践阐发见 martinfowler.com practical-test-pyramid, Ham Vocke）」。

### Batch C — firing-point 迁移（SKILL.md 净字节 ≤0）

- Workflow step 4（data/dependency 策略）末尾加一句：构造重复/复杂 fixture 时按 `test-code-authoring-patterns.md` 快速选用决策表选 §4/§7。
- Workflow step 5（断言与证据）加一句：断言结构与命名按决策表选 §1/§2/§5/§8。
- 指针指「快速选用决策表」（按症状 10 行）而非整份文件，压加载成本。
- 字节对冲：从 step 1 的两处重复（L151 与 L153 几乎同句的 release-plumbing 分类）压缩一处；不足时再压 Reference Loading L208 的枚举措辞。净字节以 size gate 实测为准。
- Batch 0 判读为「本来就会」的模式不加指针（避免无效增重）。

### Batch D — closeout 自查表（walked enumeration）

- `test-code-authoring-patterns.md` 决策表旁新增「写完测试走查」5 行清单（断言了结果而非仅调用？名字说的是行为？体内无 if/loop？重复构造已收进工厂/builder？同 logic 多输入已参数化？）——每行标对应 §。
- SKILL.md 不新增条目：killing-mutation walk 条已是 walked 形式，只在 step 5 指针句内并入「写完走自查表」半句（受 Batch C 同一净字节约束）。

### Batch E — 复测与 register 落账（终轮）

- 对 Batch 0 中 ≤5/10 的 fixture，用改动后技能文本复跑同协议 10 轮/fixture，记录 delta（诚实规则照 023：不沿用好看的旧分，跨 provider 不稳如实记）。
- source-register 行 append-once（终轮追加）：upstream rule（八大模式的 firing-point 结构）| downstream owner（stack dev 技能 deferred）| RED-baseline（Batch 0 基线 + 归因偏差的一手源证据）| firing-path 锚点（≥16 字符、唯一、白名单规范词）。

### Deferred（切片 2，本轮不做，绑定 entry 条件）

- 六个 stack dev 技能加「写测试时载入八大决策表」指针：class-wide 改动，须一次覆盖完整集合（六技能逐一 update/unchanged），entry 条件 = 本轮 Batch E 显示 delta 为正（否则指针无据）。
- 可判定 smell 谓词下沉 stack lint（条件逻辑/sleep/无断言测试）：entry 条件同上 + 每 stack 核实 linter 现有能力后按栈落地。

## 3. Gates 与风险

- dual-track：非 wording shared-skill 改动 → 独立 review + 对抗 challenge 全量；终轮对 exact candidate 做 fresh 完整 challenge。
- R0：`check-ccl-skills.sh` 到 `ccl_skill_check_clean_ok`（无私档环境则 interim + R0 pending）。
- size gate：SKILL.md 为存量超限入口，任何净增长即红——Batch C/D 合并成一次 SKILL.md diff，实测字节。
- eval 契约：fixtures 仅 advisory（eval/AGENTS.md），判分谓词不做 merge gate；`frozen_at_sha` 按 ancestry 规则。
- 预覆盖轴：(5) 过宽绝对化——指针句不得写成「必须读全文件」；(6) 枚举完整性——deferred 的 class-wide 六技能集合已列全；(1)(2)(3)(4) not-applicable（无删除/并发/资源/发布语义）。
- 风险：基线测量的 provider 波动（023 先例）→ 同 provider 同 model 对照，跨 provider 差异如实记录；判分谓词过严产生假红 → 每谓词先对已知好/坏样例各跑一次证明 oracle 能红能绿。

## 4. 目标输出图（owner map）

| owner | direction | status | 说明 |
| --- | --- | --- | --- |
| testing-strategy | executor/upstream | updated | Batch A/C/D/E |
| eval fixtures | 测量面 | updated | Batch 0（advisory） |
| stack dev 技能 ×6 | downstream | deferred | 切片 2，entry=正 delta；非 silent omission |
| skill-extraction-workflow | meta | unchanged | 无本工作流缺陷暴露；本轮由其流程执行 |
| product-rd-workflow / test-artifact-management / llm-inference-integration / code-review / tighten-doc | sibling/coordinator | unchanged | 不动生命周期 gate、TC 文档、eval 语义、评审机制；措辞定稿本轮自理 |
| 外部包（superpowers:test-driven-development 等） | reference-only | 非落地目标 | RED-first 已由本技能自有条目拥有，不复制 |
