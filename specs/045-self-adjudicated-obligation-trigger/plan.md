# 045 — 给「被裁决方自审」的义务装机械触发器

## 分类与路由

- **Artifact classification**: `gate implementation`（改的是必跑校验器 `check-ccl-skills.sh` 调用的 `impact-chain-gate.rb` 判定逻辑，新增两条拒绝条件）。
- **本轮改变 failure semantics**（新增两类 exit 1），故按 `shared-gate-artifact-classification.md` 先落此持久化 plan 再动手。
- **risk tags**: `shared-gate`（主）、`release-ops`（CI 必跑 job `repository-gates`）。
- `security-review`: `not-applicable` —— 不涉信任边界、不可信输入 sink、认证授权语义、凭据、数据可见性；改的是仓内确定性校验器的判定条件。
- **required gates**: `product-rd-workflow`（owner，已入）、`testing-strategy`（闸有可执行/变异测试行为）、动共享分支前的独立评审（`code-review`）。
- **skippable**: `visible-ui`、`api-contract`、`permission-access`、`money-quota`、`data-migration` —— 无对应改动面。
- **verifier discovery**: 仓库 agent 契约声明的权威校验器为
  `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`；CI job `repository-gates` 另跑三个独立脚本
  （`check-public-sanitization.py` / `check-markdown-links.py` / `check-spec-references.py`）。
  **本轮把这四个一并作为实现前后必跑集**——044 轮的教训正是只跑了第一个，CI 上 16 秒红在第三个。

## 来源与证据

044（review-auth-fallback，已并入 dev，PR #42）在撤回过度声称时，把若干**义务**一并降成了咨询项。
连续五轮 challenge 返回同一类，逐轮点名的可执行绕过路径：

| 被降的义务 | 绕过路径（评审逐字给出） | 现状 |
| --- | --- | --- |
| bank 测量协议「测量必做」 | 改 SKILL.md description → 不跑 bank → 冻结候选交评审。**跳过不产生任何工件**，评审看不到"缺了什么" | 无生产者、无消费者 |
| 邻居回归「须记 blocking、只能独立评审豁免」 | 上一条的推论：没跑就没有邻居 finding 可记，升级条款不可达 | 依赖上一条 |
| result 分类「缺分类留 interim」 | ①整格省略 —— 静态检查全过，没有任何东西发出 interim；②correction 轮自写 `stable success` —— 评审没有可接受/可拒绝的字段；③写 interim 照样落地 —— interim 不阻断任何可执行物 | 无解析器 |

**类的形状**：`义务的入口条件由被约束方自己陈述，且跳过时不产生可检测的缺席`。

## 设计判断：探测器 vs 删除能力

仓库记忆里有两条相反方向的先例，必须先分清本轮属于哪一类：

- `gate-bar-proxy-recurrence`：为机械豁免建的门槛被连续七次击穿，**最终解是删掉那个豁免能力**。
- `verdict-without-its-condition`：文本匹配闸补不干净该类，因为 waiver 谓词是「此处查了进程状态」的**代理**。

判据是**谓词是代理还是不变量**。本轮两个触发器都键在**diff 的客观事实**上，不是散文语义：

- 触发器 A 键于「本次 diff 是否改了 `skills/*/SKILL.md` 的 frontmatter `description`，或 `eval/routing-tasks.jsonl`」——
  `impact-chain-gate.rb` 已有 `routing_surface_diff_for` 做这件事，不是新造谓词。
- 触发器 B 键于「新增的台账行是否携带某个必填 key」——该行的 `behavioral-evidence:` 片段列表**已经**被同一个解析器强制，加第四个 key 是同形扩展。

两者跳过都产生**可检测的缺席**（没有 locator / 没有 key），这正是被降义务缺的那一半。故本轮走「装触发器」，不走「删能力」——并在下面明写它**不**关闭什么。

## 改动方案

1. **触发器 A（routing 面改动必须带 bank 证据）**，落在 `impact-chain-gate.rb`：
   本轮 diff 若改动任一 `skills/*/SKILL.md` 的 frontmatter `description`，或 `eval/routing-tasks.jsonl`，
   则该 owner 的台账行必须携带 `bank-evidence: <locator>`；locator 与既有 `firing-path:` 同一套解析
   （`command:` 或 `file:#anchor`）。缺失 ⇒ exit 1，措辞点名 owner 与缺失原因。
   **显式降范围**用 `bank-evidence: downscoped:<理由 token>`，且该 token 必须同时出现在本轮 plan 里——
   即降范围仍产生工件，而不是沉默。
2. **触发器 B（result 分类不可省略）**，同文件：
   携带 `behavioral-evidence:` 的新增台账行必须再带 `result-class: failure|stable-success|insufficient-evidence`。
   缺失 ⇒ exit 1。
3. 两条都走既有的 `impact_chain_*` 诊断形状（点名文件、行、缺失项、修法），不新造输出通道。

## 本轮明确**不**关闭的（写在这里以免下一轮把它当已解决）

- **B 只关闭「省略」，不关闭「错标」**。`result-class` 的**值**仍由作者选。把 correction 轮标成 `stable-success`
  在机械层无法判定（需要判断「本轮是不是被纠正触发的」，那是语义）。本轮的收益是把**沉默的省略**变成
  **可见的声称**——评审因此有了可接受/可拒绝的字段，这正是 044 评审说「reviewer 没有字段可裁决」缺的东西。
  不得声称它关闭了自审。
- **A 只要求证据的存在与可解析，不校验证据的内容**。locator 指向的 bank 报告是否真跑过 ≥10 轮、
  邻居集是否真含兄弟用例，机械层不判。
- **`interim` 仍不阻断可执行物**。它是报告状态，本轮不改这一点。

## Acceptance matrix（verdict 决策表）

| # | 输入 | verdict |
| --- | --- | --- |
| A1 | diff 改了某 SKILL.md 的 `description`，该 owner 台账行带 `bank-evidence: command:<changed executable>` | **pass** |
| A2 | 同上，但无 `bank-evidence` | **fail** — `impact_chain_bank_evidence_missing`，点名 owner |
| A3 | diff 改了 `eval/routing-tasks.jsonl`，无 `bank-evidence` | **fail** — 同上 |
| A4 | 同 A2，但带 `bank-evidence: downscoped:<token>` 且该 token 出现在本轮 plan | **pass** |
| A5 | 同 A4，但 token 不在任何 plan 里 | **fail** — 降范围也必须留工件 |
| A6 | diff 只改 SKILL.md 正文、未动 `description` | **pass**（不触发；避免把正文编辑拖进 bank 义务） |
| B1 | 新增台账行带 `behavioral-evidence:` 且带合法 `result-class:` | **pass** |
| B2 | 新增台账行带 `behavioral-evidence:`、无 `result-class:` | **fail** — `impact_chain_result_class_missing` |
| B3 | `result-class:` 值不在枚举内 | **fail** — 同上，点名合法值 |
| B4 | 新增行不带 `behavioral-evidence:`（非本闸的行） | **pass**（不触发，保持既有 bifurcation） |
| A7 | `bank-evidence` 指回 owner 自己的包 | **fail** — 改动本身不是关于它的证据（实现中新增） |
| A8 | 只改 `eval/routing-tasks.jsonl`、不动任何 owner，无 bank-evidence | **fail** — 独立评审发现（见下） |
| G1 | 该轮 head 的台账未声明该语法 | **pass** — 不被追溯约束（实现中新增，见下） |
| G2 | 该轮 base 声明过、head 把声明删掉 | **fail** — `impact_chain_grammar_withdrawn`，独立评审发现 |
| A9 | 只改 bank 且**零台账行** | **fail** — 独立评审 round 2 发现：外层进入条件漏掉该路径 |
| A10 | 两 owner 各改 description，仅一个带证据 | **fail** — 独立评审 round 2 发现：义务按 owner 各自承担 |
| A11 | 自指 locator 写成 `command:` 形态 | **fail** — 独立评审 round 3 发现：禁的是路径不是前缀拼法 |
| A12 | 轮1 只动 bank 且带证据、轮2 只动某 owner 正文 | **pass** — 跨轮不得串扰（评审 round 4 发现） |
| A13 | `bank-evidence: downscoped:-` 退化 token | **fail** — 评审 round 5 发现：`-` 会命中任意 bullet |
| B5 | bank-only 轮的声明行缺 `result-class` | **fail** — 评审 round 6 发现：B 按 owner 收敛会整个跳过它 |
| A14 | 自指写成 `./skills/<owner>/…` 等价拼法 | **fail** — 评审 round 7 发现：禁位置就得在规范形上判 |
| A15 | `downscoped:evidence` 撞上无关行里的 “evidence” | **fail** — 评审 round 9 发现：必须逐字记录 `downscoped:<token>` |
| A16 | 新技能的第一版 description | **fail** — 评审 round 12 发现：创建路由面不是豁免 |
| A17 | 行里 token 是 spec 所记 token 的严格前缀 | **fail** — 评审 round 12 发现：声明须在 token 边界结束 |
| G3 | 删掉声明段、把 marker 塞进一行台账 | **fail** — 评审 round 13 发现：行会引用，不会立法 |
| A18 | 同一提交里改名 + 改 description | **fail** — 评审 round 14 发现：两侧豁免之间的缝 |
| G4 | 撤回被拒时的诊断 | 只能点名本闸真正实现的补救 — 误拒方向的 challenge 发现 |
| A19 | 就地删掉 description 条目（文件保留） | **fail** — 误拒轮的 review 顺带发现的逃逸路径 |
| C1 | 变异：把两条拒绝条件分别删掉 | **fail**（变异测试须逐条复现，归因到各自断言） |

### 实现期两处必须记录的偏离

**A7（收紧）**：description-only 的改动可以把 `bank-evidence` 指回它刚写下的那一行——工件存在、
却不构成关于它的证据，正是本轮要消灭的形态。故禁止 locator 指向 owner 自身的包。

**G1（非追溯性，承重）**：原方案没考虑「给台账行加必填字段」在**回放**下的后果。实测：
`test_impact_chain_gate_verdict_differential.sh` 回放 64 个真实历史集成点，两个触发器裸装会
**新拒 34 个**（单 A 为 5 个）——该套件会正确地把这报成回归，而它的具名分歧机制只支持单 token
加固定 SHA 列表，列 34 个等于把守卫本身作废。

解法不是日期或 commit id 的 grandfather（那是会漂的代理），而是**一轮只受其自己 head 所声明的
语法约束**：闸检查该轮 head 的 `source-register.md` 里有没有那段字段定义。历史轮没被告知过，
因而不被判；本段落落地之后的轮才承担义务。装上后 verdict-differential 回到 **64/64、零新拒**。
G1 这条腿钉的就是这个性质——删掉它，加字段就会重新变成追溯判死全部历史轮。

### 独立评审（round 1, reviewer `codex`）四条 P1 的处置

全部采纳——四条都是「义务在某条路径上蒸发」，与本轮主题同型：

1. **G1 在已提交的检出里会失效**：提交后 `git clone "$ROOT"` 自带该声明段，fixture 把克隆 HEAD
   当「早于语法」就不成立——**从未提交的工作区跑是绿的、进 CI 就红**。改为主动**删掉**声明造 base，
   而不是指望克隆碰巧没有。这正是本套件要防的那类假绿（绿的含义是「还没提交」）。
2. **bank-only 改动完全不触发**：第一版按 owner 迭代，只改 `routing-tasks.jsonl` 没有任何变更 owner，
   循环压根不进——路由 bank 可以随便动而零证据。A3 没抓到，是因为它顺手也改了 owner；洞藏在绿用例后面。
   改为**按轮 scope 求值**，并补 A8。
3. **删掉声明段即静默关闭两个检查**，且与「早于规则」不可区分。补 `impact_chain_grammar_withdrawn`：
   base 声明过而 head 不再声明是**撤回**，必须被论证而不是被提交。补 G2。
4. **跨 scope 互相满足**：`triggered` 与 `satisfied` 各自扫该 owner 的全部行，一轮的合法 locator
   会满足另一轮的裸改动。义务属于产生它的那一轮，清偿它的行必须在同一轮内。随第 2 条一并改掉。


### 独立评审 round 2（reviewer `codex`）两条 P1

同类第二次递归，两次都是**我自己的绿用例挡住了它要覆盖的洞**：

5. **只动 bank、零台账行**：A8 仍加了一行台账，于是 rows 非空、scope 存在；真正无人守的是
   「既不动 owner、也不动台账」——外层进入条件 `upstream.any? || ledger changed` 直接不进块。
   把 bank 路径并入进入条件，循环改为按 **round_bounds** 迭代而非按行分组，补 A9。
6. **多 owner 轮里一个 owner 的 locator 替另一个还债**：按轮求值太粗。改为**按 subject 求值**
   （每个移动了自己路由面的 owner 各自欠一份；bank 不属于任何包，本轮任一行可清偿），补 A10。

### 独立评审 round 3（reviewer `codex`）一条 P1

7. **自指禁令只匹配了 `file:` 拼法**：同轮顺手改了自己包内一个脚本，写成
   `command:skills/<owner>/scripts/x.sh` 就能让改动给自己作证。两种 locator 都在指一条路径，
   改为剥掉 kind 前缀后按路径判定，补 A11。

### 独立评审 round 4/5（reviewer `codex`）

8. **bank 变更让 `routing_surface_touched` 对任何 owner 返回 true**：多轮范围里，改 bank 的那轮
   会去要求别轮变更 owner 的行——加一个不相关的后续提交就能改变对前一轮的判定。拆成
   `description_touched`（只管该 owner 自己的 description），bank 作为独立 subject，补 A12。
9. **`downscoped:` 的 token 用 `\S+` 解析**：`downscoped:-` 会在任意 bullet 行的连字符上命中，
   拿一条什么都没说的记录清偿义务。token 必须成其为 token（≥8 位、字母数字起头），补 A13。
10. 另有一条被判为**输入缺陷而非候选缺陷**：评审包里只有计划与自述、没有执行结果。按技能规则
   加宽包重跑（把全部套件与四个门禁的实跑输出并入 packet），而不是改候选去迎合它。

11. **B 按变更 owner 收敛留下自己的洞**：bank-only 的轮没有变更 owner，声明行压根不被检查。
   非追溯性本就由 grammar 闸独立承担，让 owner 集合兼这份差事没有收益、却换来一个假绿。
   改为扫全部声明行（仍受 grammar 闸约束），补 B5；放宽后 verdict-differential 仍 64/64。

12. **自指禁令拿裸 `start_with?` 比一种拼法**：`./skills/<owner>/…` 指同一个文件却躲过检查。
   改为归一化路径段后再判，补 A14。
13. **我自己冻结的变异证据已经过期**：加了 B5 之后「disable result-class ⇒ 恰好 B2 B3」不再成立。
   评审指出后重新实测并改正（见下表）。冻结的证据不会自己跟着代码走，这条要当成纪律记住。

14. **降范围留痕只搜裸 token**：一个常见英文词就能被无关行命中（`downscoped:evidence` 撞上
   「Bank evidence anchor …」），沉默自审又被从子串匹配里重建出来。改为要求 spec 逐字记录
   `downscoped:<token>` 这句声明本身，补 A15。

15. **CI 上 `regression-heavy` 红而本地绿**：我只挑着跑了五个 impact-chain 套件，没跑整条 lane。
   `test_check_ccl_impact_chain_refscripts.sh`（91 条 fixture 行、16 个 routing-surface 用例）
   同样要 `result-class`，其 routing-surface 用例还要逐轮的降范围留痕。**验证面必须是 lane，不是套件**：
   `test_check_ccl_regressions.sh --full`（fast 26 + heavy 7）现已纳入本轮必跑集。
16. **被改名删走的 owner 曾被当成「移动了路由面」**：base 有 description、head 没有该路径，
   两者不等就被判为改了 description。要求两侧都存在才算——改名/删除/新建由既有机制处理。
   **明记的范围限制**：新技能的第一版 description 因此也不触发；保守而非猜测，未关闭。

17. **我把「新技能的第一版 description」当作范围限制写进 plan，评审点破那是洞不是限制**。
   创建一个路由面恰恰决定了哪些请求会到这个新技能，是最大的一次变更。该排除的只有
   删除/改名走（head 无条目），以及 git 能证明的改名目标。全新包不在闸的 owner 集合里
   （base 时它不存在），所以改为直接从 changed_paths 识别，补 A16。
   **教训**：把没想清楚的洞写成「保守的范围限制」，措辞会让它看起来已被处置。
18. **`include?` 的前缀碰撞**：spec 记 `downscoped:TOKENLONGER` 会满足行里的 `downscoped:TOKEN`，
   别人的 token 顺手替这一行还债；`not-downscoped:TOKEN` 同样命中。改为带 token 边界的匹配，补 A17。
19. **候选超过单包上限（213KB > 200KB）**：按技能规定拆成三个分区、覆盖全部 11 个文件。
   第一次拆分只把实现放进 p1，另两区的评审因此无从判断，三区返回的都是同一条「只拿到一个分区」
   ——那是**输入缺陷**不是候选缺陷。第二次把实现 diff 作为共享上下文**重复进每一个分区**，
   两条真 finding 才浮出来。分区不是把候选切开，是让每一份都能独立判断。

20. **`grammar_declared_at` 在整份 blob 上 include?**：删掉声明段、把同一串字面量塞进任意一行台账，
   base/head 都读作「已声明」，撤回检测哑掉，之后每一轮都继续被一个权威已不再陈述的语法判定。
   G2 抓不到——它把所有含 marker 的行都删了。改为只认**非表格行**（散文才立法，行只引用），补 G3。
   这是本轮第四次同一形状：**子串匹配把「记录」和「碰巧含有」混为一谈**（downscoped 前缀、
   downscoped 撞词、自指路径拼法、这一条）。

21. **改名 + 改 description 同一提交，从两侧豁免的缝里溜过去**：目标路径以「只是改名」豁免、
   源路径以「没有 head 条目」豁免。豁免给的是「description 没变」，不是「路径动过」——
   改为跨改名对比较 base 源与 head 目标的 description，补 A18。
22. **我的台账行数字第二次过期**：行里冻着「十二腿、恰好 A2/A3/A5 与 B2/B3」，而套件已到 26 腿。
   评审两个分区同时点出。已按实测改正（bank→14 腿、result→3 腿、grammar→2 腿）。
   **同一形状第二次出现，说明这不是疏忽而是缺机制**：冻结的数字不会跟着代码走，
   每次加腿都必须重测并回写，否则最权威的那份工件反而最先过期。

23. **误拒方向的定向 challenge 抓到唯一一条真误拒**：`impact_chain_grammar_withdrawn` 的诊断
   写着「或由具名风险 owner 承担」，而代码里没有任何解析风险 owner 的路径，`exit 1` 无条件——
   **承诺了一条落不了地的补救**。修法不是去造那个 waiver，而是把话说对：撤回一个机械义务
   应当改那个机制本身（可评审的代码 diff），数据侧 waiver 就是本轮要消灭的自审面。补 G4，
   钉的是「诊断与实现一致，不许出现只存在于措辞里的出口」。
   同一条在配对的 challenge 里再次出现，**驳回**：那不是误拒，是设计上不存在的数据侧出口；
   合法的撤回路径存在且被诊断点名（在自己的评审轮里删掉这些检查）。

24. **「head 没有条目」被一律当成删除/改名走**：文件还在、只是 description 被就地删掉——技能
   从此不再声明自己接什么请求，那和改写它一样是路由面变更，而且是最彻底的一种。按
   「文件在不在」与「条目在不在」分开判，补 A19。

**记一笔方法上的发现**：把最后一轮评审**定向到「会不会误拒合法轮次」**，而不是继续在
逃逸方向找洞，一次就问出了那条唯一的真误拒（诊断承诺了未实现的补救），还顺带带出 A19。
换个方向问，比同一个方向多问一轮更有产出。

**这条教训本身值得记账**：两轮评审、六条 P1，其中三条的形状都是「fixture 顺手多做了一件事，
把要测的路径挡住了」。负向用例必须**只**构造它要证伪的那一个条件。

## Test / register 覆盖

| 层 | 动作 | 命令 / 证据 |
| --- | --- | --- |
| 闸自身（单元层） | add + run | 新增 `test_impact_chain_self_adjudication.sh`，逐行覆盖 A1–A6、B1–B4 |
| 变异测试（行 C1） | add + run | 分别删除 A、B 两条拒绝条件 ⇒ 对应断言必须红，且**只有**它红（差分归因） |
| 注册自审 | run | 新增 `test_*.sh` 后必跑 `test_regression_runner_registration.sh`——本仓已有「发出去的测试没注册」的先例 |
| 回归族 | run | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --full`；既有四个 impact-chain 套件 |
| 仓库权威校验器 | run | `check-ccl-skills.sh .` **加** `check-spec-references.py` / `check-markdown-links.py` / `check-public-sanitization.py` |
| 自举 | run | **本轮自己的台账行必须满足 B**（它就是第一个被新闸判定的行）；A 是否触发取决于本轮是否动 description |
| CI | run | `repository-gates` 等七个 job 在 PR 上转绿 |

## Status-sync target

`specs/045-self-adjudicated-obligation-trigger/plan.md`（本文件）+ PR 描述 + `source-register.md` 本轮行。仓库无独立 status doc。

## Review / challenge gate

动共享分支前跑 `code-review`（独立评审 + challenge，tracked chain）。**本轮的评审重点须显式包含**：
新装的两个触发器自身是否又是「代理谓词」，以及是否存在不产生工件的绕过路径——
这正是 044 连续五轮没能收敛的地方，不能靠同一种自审再走一遍。合并需用户显式授权。

## 残留风险

- 触发器 A 依赖 `CCL_SKILL_BASE_REF` / base ref 可解析。base 解析失败时必须**闭式失败**
  （报 UNAVAILABLE 并 exit 1），绝不能因为算不出 diff 就静默放行——那会复制 044 的原始缺陷形状。
- 两个新拒绝条件会让**存量**台账行在下次被判定时红。实现时须确认判定只作用于**本轮新增行**
  （既有 bifurcation 已是这个形状），否则会把 append-only 台账变成不可通过。
