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

`scripts/eval-routing-bank.rb <repo-root> [--bank p] [--model m] [--limit N] [--dry-run] [--json p] [--baseline p] [--desc-budget-chars N] [--replicas N]`。`--desc-budget-chars N` 把每条 description 截到前 N 字符再评（消费端截断臂——如 Codex 在 ~2% 上下文预算/未知窗口 8,000 字符下压缩技能清单）；plain 与 budgeted 各跑一遍即可定位"只活在描述尾部"的路由触发词。`--replicas N` 每 task 评 N 次:task 判定取保守共识(任一有效副本 FAIL 即 FAIL),并报告副本 top1 一致率——不同 (bank, replicas) 配置是不同尺子,不得互相 diff 当回归。`make eval-routing-bank`。

- 冻结 task-bank `eval/routing-tasks.jsonl`:每行 `{id, utterance, expected_skill, acceptable?, must_not_route_to?, source, why_expected, frozen_at_sha}`,种子取自 source-register 历史 miss + bootstrap 路由规则。**已修复的路由 miss 必须把其 utterance 冻结成 bank task 落在同一交付里**(修复不冻结=下次同类漂移无回归面)。`expected_skill: "none"` 是否定对照/覆盖空洞哨兵:正确结果是没有技能认领;`acceptable` 列出可辩护替代结果(如空洞探针上 coordinator 接管与拒绝都对);`must_not_route_to` 点名吸入诱饵邻居。结构由 `test_routing_bank_integrity.sh` 确定性把关(sentinel 只准出现在 expected/acceptable,不准进 must_not)。
- **冻结案例神圣(regressions-are-sacred)**:已冻结案例的删除或判定面改写(bank task 的 expected/acceptable/must_not,golden trace 的 assert 块)是一次回归裁决事项,与邻居回归同权——平均改善不得抵消单条冻结案例的失守,且「曾 yes 现非 yes」**含降级为 unsure/INCONCLUSIVE** 都算回归。删除/改判的每条案例必须在同一轮的 register 追加行里写 `case-retired: <id>` 或 `case-rescoped: <id>` 并给理由,交独立评审裁决;确定性半边由 `test_frozen_case_sanctity.sh` 按 `CCL_SKILL_BASE_REF` 把关——无裁决行即红,无 base ref 时打印显式 skip token(skipped ≠ passed),它只保证交易可见,不裁决交易正当性。
- **描述触发评测的三条纪律**（Anthropic skill-creator 的 description-optimization 形态）：① utterance 要真实——带文件名、口语、错字、上下文，不写抽象短句，否定例要是**近似负例**（共享关键词但该走别的技能），不是明显无关句；② 触发率按重复取——each bank utterance must be graded at least three times per description version（`--replicas 3` 起），单次 pass/fail 不是触发率；③ 用 grader 自动改写 description 时，bank 必须按 60/40 切成训练/held-out，只按 held-out 分选优，否则描述会过拟合 bank（本仓尚无自动改写循环；这条是它的前置条件，不是已有能力）。
- **改 bank 的那一轮必须同轮重建基线**——runner 按 `bank_sha256` 与 `replicas` 判定「不同尺子」并抑制 diff，所以往 bank 增删一行就把此前**每一份**基线永久作废：不是变旧，是不可比。旧基线仍留在 `eval/evidence/` 里读着像基线，没有任何东西提示它已被孤立，于是路由面可以长期无人测量而全绿。改 bank 的交付要么同轮跑出新基线并落 evidence（报告自带 `bank_sha256`/`replicas`，将来才可比），要么在 register 追加行里显式写明旧基线自此孤立、下一轮补测。失败形态：bank 从 136 行长到 158 行，其间六条 description 变更、一个技能新增，而唯一的全量基线停在三周前且与当前 bank 在任何 replicas 设置下都无法比对——这一点直到有人主动传 `--baseline` 才由 runner 自己说出来。
- grader = 每 task(×replicas)一次本机 `claude --print --tools "" --model <haiku>`,喂 utterance + 全部 skill description(agent 真正路由的那份面),要 `{selected_skill|none, clarify, confidence, rationale_short}`。**clarify 率、低置信率(<0.5)、副本一致率是一等报告字段**,不是旁注——路由质量的残余风险常在"高置信直选却选错、无自纠路径"这类 pass/fail 看不见的分布里。
- **路由兼容性信号,不是真值预言机** —— grader 自己可能错;只衡量"当前 description 能否让廉价模型把固定 utterance 路由到 expected"。
- **advisory**:不接 `check-ccl-skills.sh`,不挡 merge。退出码:`0` = 跑完;`2` = 用法;`3` = grader 整体不可用(claude CLI 缺失则打印 skipped 后 `0`)。路由 miss 永不非 0。
- **防作弊**:runner 校验每 task 的 `frozen_at_sha` 是 HEAD 祖先(非祖先 = drift,排除出回归判定);同一改动若同时动 task-bank 和 SKILL.md description 会显式告警(防"改 skill 顺手改测试让它过")。
- `--baseline <json>` 给 diff 式报告(newly_failed / newly_passed)。

### Bank 用例修复的测量协议（测量必做；落地裁决归本轮实际门禁）

以下是生成可比较证据的默认协议。**降级的是「F4 自己充当统一合并门禁」这个声称，不是「必须测、且必须有人裁决」这个义务**——这两件事分开：落地判断交给本轮实际的 owner／风险／评审门禁，但**测量本身不可选**。任何动 routing 面（SKILL.md description、task-bank 判定面）的改动都必须按下列协议产出证据；没跑就是没收敛，不得进入独立评审、也不得声称本轮无回归。采用不同样本量时，须随工件记录理由，且该理由与本轮证据一同进入独立评审——「记了理由」本身不是豁免，自审通过的理由不构成已裁决：

**筛查分辨率 ≠ 行动分辨率（是两个数，不是一个）**：全量基线默认 `--replicas 3`，它是**筛查器**——把候选捞出来，不是给结论。判定面是保守共识（任一副本 FAIL 即 FAIL），于是三副本下一条真实认领率 80–90% 的用例读起来就是红的，一次孤立偏离读起来就是一条 finding。**任何按用例采取的行动——改它 owner 的 description、判它是回归、判某条冻结期望已过期——都要求那条用例自己有 ≥10 个有效观测**；runner 对任何 `replicas < 10` 的报告打 `screening_resolution_only`、并在 JSON 里落 `action_resolution: false`，两侧的 10 由 `test_eval_routing_bank_resolution.sh` 钉在一起，防止文档与执行体漂移。实测形态（115 轮，同一轮内三次反向出错）：3 副本全量基线报 14 条失败，10 副本下其中 5 条是抖动、六条已起草的 description 改动全部建立在它们上面；其中 `p3-spec-then-tc` 的单次偏离被据以论证某冻结期望已过期，10 副本下该对手 3/17、论证撤回；`ab-c5` 被判成「改前 PASS、改后 FAIL」的邻居回归，钉在未改动树上的对照臂显示它改前就是 8/10 的边缘失败。**留在 `eval/evidence/` 里的三副本基线因此是候选清单，不是 findings 清单**——引用它开轮的人要先为自己要动的每条用例补齐观测。

**地板管「能不能动手」，不等于「点估计已经准到能和阈值比」**：10 次有效观测在 70–85% 区间的抽样误差约 ±15–20 个点。实测形态（115 轮，同一个候选、同一条用例 `ab-b5`）：一次 10 副本得 5/10（50%），紧接着 20 副本得 17/20（85%），合并 22/30（73%）——单看前者会判成「稳定失败」并据以改描述，单看后者会判成「健康」。所以**任何按阈值分档的判断（稳定失败 / 边缘 / 抖动）必须读合并观测，落在约 45–75% 之间的读数在 10 副本下不构成判定**，要么补到 30 次以上，要么如实记成「区间未定」。同理，改前/改后的差值也按合并观测比：本轮那条 8/10→5/10 的「回归」在 24/30 vs 22/30 下相差两次命中，不可分。

1. 动任何 description 之前必须先跑 **≥10 轮有效观测**的稳定性基线,把稳定失败与抖动分开;抖动不得作为修改依据(grader 超时/不可解析轮不算有效观测,须补跑)。
2. 改后通过数必须在**最终措辞**上重测:中间稿的通过数在措辞再变的那一刻作废,不得挪用到最终候选的证据里。
**`newly_failed` 是候选，不是回归判定。** runner 的 `--baseline` diff 在三副本下按保守共识判 status，于是一次孤立偏离就把一条用例记进 `newly_failed`；而这个集合**每跑一次就换一批**。实测（115 轮，同一条分支上四次全量三副本运行）：`{route-opencode-project-config, route-nodejs-arch}`、`{skip-pytest-cmd, ctrl-ai-risk, miss-refactor-python-unqualified, route-nodejs-arch}`、`{mem-api-log-redact, route-nodejs-arch}`——除 `route-nodejs-arch` 外每一条只出现过一次、再未复现，逐条做成对 20 副本探针后**无一可归因于该轮改动**（两例两臂分布完全相同，一例两臂都红，一例合并后相差两次命中）。所以：`newly_failed` 的每一条都要按「同一用例、改前/改后两棵树、合并 ≥20 次观测」复测才能称为回归，不得直接写进轮记录当回归清单；同样地，不得因为它每轮都有内容就把整轮判红。

3. 受影响邻居用例集默认改前/改后各 **≥3 轮**,集合须含期望 owner 自己的兄弟用例与高词面重叠的他 owner 用例;邻居回归作为独立 finding 交由本轮实际门禁处置——**该 finding 须以 blocking 记入本轮 dual-track 评审记录,且只能由独立评审方豁免,不能由实现者自行判定「本轮没有门禁采用这组证据」而放行**。降级的是「F4 自己充当合并门禁」这一声称,不是「回归必须被人裁决」这一义务;后者若也随之消失,这一条就只剩被裁决方自审。
4. 每轮判决必须连同 **runner 调用、grader 模型身份、候选身份**(commit 或描述内容指纹)与**原始逐轮工件的持久定位符**一并记入轮记录;没有定位符的通过数只能标注为 operator-reported,不得据以宣称修复轮已 concluded。
5. **单变量归因**:一次改前/改后对照只准动**一个路由变量**(一条 description,或同一 skill 不可分割的一组路由面)。同时动多条 description 的批量改动,其对照差值不可归因到任何一条,只能按整包回归读——要归因就拆成逐条 A/B。(源侧实测形态:仅替换一条 description 的成对子集对照,把命中从约 2/3 提到 95%,且提升可归因到那一条改动——多条同动时这句话说不出口。)

## 路由失效形态词表(跨层;报告与修复讨论用这套名字)

pass/fail 之外,路由失败有可命名的形态;每个形态有不同的检测器与不同的修法,混称"路由不准"会修错面:

| 形态 | 判据 | 检测器 | 典型修法 |
|---|---|---|---|
| **吸入 (absorbed)** | 应被拒绝(expected none)或应远离诱饵邻居(must_not)的 utterance 被某技能认领——覆盖空洞不被承认而被最近邻低置信/clarify 拉走 | bank 否定对照+空洞探针,runner `absorbed` 标签 | 认领空洞(补 owner)或在诱饵邻居 description 加排除句;不要靠 grader 自觉 |
| **归属分裂 (ownership_split)** | 同一 utterance 多副本给出不同 top1——所有权不稳定,谁都像 owner | `--replicas ≥2` 一致率 + `ownership_split` 标签 | Skip-when 互相消歧或触发词改具体(description-authoring 的 80% 阈值) |
| **静默跳过 (silent skip)** | 路由"成功"但被选技能的正文从未被读/其硬规则从未被应用——选择层过了,质量层空转。判据阶梯:mounted → invoked → 文件真被读 → 下游行为改变;mounted-only 不证明任何生效 | 非 Tier-1/2 可见;B 面 body-compliance 探针 + Tier-3 真 agent 事件流 | 修正文 firing point/read routing(body 指针补齐四元组,见 description-authoring.md「Body routing pointers」),不是修 description |
| **高置信错选** | 错选但 confidence 高、无 clarify——事后无自纠路径,比低置信错选更危险 | 报告里 FAIL ∩ 高置信 ∩ clarify=false 的行 | 触发词消歧;必要时在正文加入口自检;残余风险如实记录 |

## Tier-3:hub golden trace 真 agent 回放(已落地,advisory,人工判定)

`scripts/eval-golden-trace.rb <repo-root> [--traces d] [--max-turns N] [--timeout S] [--only id] [--limit N] [--json p] [--dry-run]`。`make eval-golden-trace`。

- golden trace `eval/golden-traces/*.json`(每个 hub skill 一条):`{id, hub_skill, trigger_prompt, assert{must_invoke_skill, must_not_invoke_skill, no_destructive_command}, allowed_variance, frozen_at_sha}`。当前 3 条:product-rd-workflow / defect-diagnosis / testing-strategy。
- runner 把 trigger 喂给 headless `claude -p --output-format stream-json --max-turns N --allowedTools Skill Read Grep Glob`(**allowlist:只读 + Skill,无副作用** —— Bash/Edit/Write/NotebookEdit/cron/task 全因不在白名单而禁用),从事件流抽**真 agent 实际 invoke 的 Skill**,做**结构化断言**:must_invoke ⊆ invoked、must_not ∩ invoked = ∅、命令无破坏性类。
- **只断言路由结构,不断言措辞/顺序/tool 数**。v1 因禁用工具,聚焦路由结构;产物/命令族断言留待沙箱化后扩展。
- **比 Tier-2 高保真**:观察真 agent(完整 skill 体 + hook + context),不是廉价模型对 description 的看法。
- **advisory + 人工判定**:不接门禁、不挡 merge。状态 PASS / FAIL / INCONCLUSIVE(agent 未在 max-turns 内路由)。退出码:`0` = 跑完;`2` = 用法;`3` = agent 整体不可用(claude 缺失则 skipped 后 `0`)。路由漂移永不非 0。
- **随机性**:agent 非确定;判定先人工、nightly 起步,有稳定史前不自动 gate。防作弊同 T2(`frozen_at_sha` 祖先校验)。
- **双用途**:除回归外,Tier-3 还可当**改技能前的 RED-baseline**(改前手动跑触发场景看真 agent 是否真路由错,改后看 compliance)——可选;只有真观察到 miss 才算 RED(PASS/INCONCLUSIVE 不算),小 N + 非确定有噪声,手动跑两次自己留两份报告。落地 + 防作弊注意见 [validation-and-landing.md](validation-and-landing.md) "Optional real-agent RED-baseline"。

## B 面:正文合规探针 body-compliance(已落地,advisory)

`eval/body-compliance-eval.rb <repo-root> [--arm L] [--json p] [--model m] [--timeout s] [--ids a,b]`。`make eval-body-compliance`。路由三层测「选没选对技能」;B 面测**已激活技能的正文硬规则是否真被应用**——正文即 prompt,逐探针 required/forbidden marker 契约判分,覆盖是 NAMED SUBSET(见 runner 头部声明)。

- 含 product-rd-workflow 停机谓词的**成对分类探针**(prd-stop-*/prd-continue-*):每对场景恒定、只变谓词判别特征,按闸自身的字面 `continuing:`/`blocked:` marker 判分——确定性锚钉的是这些谓词的**措辞存在性**,只有这些探针检验**案例被分到哪边**。
- 触发纪律:改动触及某技能正文硬规则或停机谓词时,must run the affected `--ids` probe subset on this machine before landing,结果按该改动既有门禁处置;advisory 契约与升级路径(提炼确定性不变量,永不阻断 LLM 判定)见 `eval/AGENTS.md` 与 [f4 手册](../../../docs/f4-skill-effectiveness-harness.md)「双轨承载面与运行分层」。
- 实测的双轨互补边界(锚管措辞、探针管行为漂移、不是埋句绊线)与小样本告诫,单一落点在 f4 手册「双轨承载面与运行分层」,此处不复述。

## Health roll-up:描述性仪表盘(已落地,advisory)

把上面各信号卷成**一个加权 0–10 显示值 + 同尺子变化**,用于定位值得继续检查的维度。它借用 OpenSSF Scorecard 的呈现形态,但不把不同性质的 F4 信号变成“仓库整体变好/变差”的总判决。映射与限制见 [harness-patterns-and-eval.md](harness-patterns-and-eval.md) §3.4。

`scripts/eval-health.rb <repo-root> [--trace-json p] [--bank-json p] [--history p] [--no-write] [--json p] [--quiet]`。`make eval-health`。

- **维度(各 0–10,按风险加权,OpenSSF 风格)**:`structural` 权重 10(Critical,`validate-skill.sh` pass/fail)· `routing_static` 权重 10(Critical,T1 blocking=0 满分、有 blocking 砸到 3、advisory 轻罚)· `trace` 权重 7.5(High,T3 pass/considered)· `bank` 权重 5(Medium,T2 pass/tasks)。
- **只跑确定性两维**(structural + routing_static,无 LLM、快);`trace`/`bank` 需 `claude` 且随机,**不自动跑** —— 用 `--trace-json` / `--bank-json` 把 T3/T2 报告喂进来,否则该维 **skip,权重按比例重分**给在场维(诚实标注 `dims=…`)。
- `composite = Σ(score_i·w_i) / Σ(w_i)`,只对在场维求和;skip 维自动从分母剔除。band 只是浏览提示,不得当作验收等级。
- **advisory,永不因显示值阻断**:退出码 `0` = 跑完 **或** 没有可算的维(都不是失败);`2` = 用法/setup 错(`<repo-root>` 不对或无 `skills/` 目录)。低值、坏报告、空历史都不会非 0。畸形的 T2/T3 报告(非对象 / 非整数 / `pass>total`)直接 **skip,不静默打分**。**绝不接进 `check-ccl-skills.sh`**。结构校验、T1 blocking、任务验收和行为证据分别独立判定；质量失败不能被其它维度的高值平均掉。
- **corpus/version 守卫(防跨变更 task-bank 当稳定指标比)**:每条历史记 `corpus`(= task-bank + golden-traces 输入内容的指纹)+ `repo_sha` + 在场 `dims`。**趋势 delta(IMPROVING/DECLINING)只跟最近一条 `(corpus, dims)` 都相同的历史比**;否则打印"baseline reset, not compared",不偷偷比。这样"加了 10 条简单 task → 分涨了"不会被读成真进步(尺子换了)。
- **历史文件**:默认 `eval/health-history.jsonl`,**git-ignore**(同 Goodhart 理由:committed 的数会招"调数不修仓";也免 append 把树搞脏)。`--history` 可改路径,`--no-write` 不落盘。
