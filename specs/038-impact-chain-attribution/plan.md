# 038 — impact-chain 闸的轮/归属硬化

Status: **interim** —— 实现完成、机械闸全绿；自主评审预算已用尽（八轮独立评审链），未推送、未建 MR。合并前需人工裁决点见文末。本轮只发 **Root A（纯收紧）**；Root B（merge 导入扣除）经三轮对抗评审后由风险 owner 裁决**删除**，见下方裁决节。

## 背景

034 三个批次各自记录了一个 impact-chain 闸的缺口，登记时被归为「同一族、同一根因（轮/归属靠 diff 形状推断）、绑定下一轮 gate 工具变更」：

1. owner 文件被 rebase/冲突还原成 base → 退出 changed 集，台账行留绿（漏报）。
2. 台账行 evidence 单元格未提及 owner key → 该行被行归属扫描静默跳过、永不评估（漏报）。
3. merge 集成上游分支造出新一轮 → `impact_chain_gate_missing` 必红（误报）。

本轮第一步不是修，是**复现**——闸在三个批次里一路被加固，登记的缺口未必还在。

## 复现结果（baseline = origin/dev 5146b3b）

`skills/skill-extraction-workflow/scripts/test_impact_chain_round_attribution.sh`，四腿 + 一个控制组：

| 腿 | 形状 | 期望 | 实测 | 结论 |
| --- | --- | --- | --- | --- |
| 0 控制 | 一次 owner 变更 + 一条完整行 | rc=0 | rc=0 | fixture 形状本身绿 |
| A | owner 被还原成 base，行留存 | rc=1 | **rc=0** | 形态 1 复现（假绿） |
| B | 行带 declaration 但 evidence 无 owner key | rc=1 | **rc=0** | 形态 2 复现（假绿） |
| C | merge 带进**不同** owner | rc=0 | rc=0 | 不复现 |
| C2 | merge 带进**同一** owner | rc=0 | **rc=1** | 形态 3 复现（假红） |

控制组是承重的：起草过程中出现过两次假判决——一条腿因 firing-path 锚点解析不了而红（被读成「形态复现」），同一缺陷又让另一条腿的红看起来像「形态已关闭」。控制组不绿则其余各腿的判决一律无效。

C 与 C2 的差分把形态 3 的前提钉死了：**被 merge 带进来的 owner 必须同时落在累积 changed 集内**，而这恰好发生在上下游两轮碰同一个 owner 时。台账记的「merge 必红」过宽——不碰同一 owner 时闸是绿的。

## 结论修正：不是一个根，是两个

登记时的「同一根因」在高层成立（都是归属靠 diff 形状推断），但**修改点是两处，不能当成一个补丁**：

- **Root A（形态 1 + 2）**：行的 owner 归属被 changed 集过滤。
  `upstream_paths_in_row = paths.select { |path| upstream_set[path] || lineage_extra[path] }` —— `upstream_set` 是累积 changed 集。owner 不在其中时该行既不进 `rows_by_upstream_path`（不被评估）也不进 `declared_in_round`（不被索要），两侧同时失效 → 假绿。形态 1（还原）与形态 2（无 key）都是这一行的两种进法。
- **Root B（形态 3）**：轮的 owner 索要按 span 端点 diff 推断。
  轮 = ledger 边界切分，每轮 `changed_paths = diff(span_base, span_head)`。span_head 是 merge commit 时，上游分支带进来的 owner 变更整个落进本轮；而这些变更对应的台账行早已存在于 base，`row_budget = head_count - base_count = 0` 被拒 → 有索要无行可供 → 假红。

一轮里一起修，但它们是两处独立改动、各自独立的回归证据。

## 一个会改变修法的实测

台账登记的 Root A 修法是「新增/修改台账行无条件校验 firing path」。按现行行归属实现，这需要先能把行绑到 owner。量了真实台账（183 条数据行）：

| 桶 | 条数 |
| --- | --- |
| 恰好绑定一个 selectable owner key | 108 |
| **带 declaration 但 evidence 里没有任何 `<slug>/SKILL.md`** | **68** |
| 有 key 但都不在 curated 名单内（`worktree-isolation/`、`release-coordination/`） | 7 |

那 68 条不是坏行——它们 evidence 单元格引的是 owner 包内的**脚本路径**（`code-review/scripts/test_kimi_packet_mcp.py` 等），这是既有的合法书写约定。所以「带 declaration ⇒ 必须有 SKILL.md key」这个判据会假阳 37% 的真实行，不能用。

修正后的 Root A 判据：**从 evidence 单元格里按 owner 包前缀（`<owner>/…` 任意路径，不限 `SKILL.md`）解析归属**，再要求解析出的 owner 在交付 diff 中确有变更。7 条非 curated owner 的行必须继续静默跳过——curated 名单之外本就不在本闸辖内。

（闸是 diff-scoped 的，历史行不回溯重判，所以这 68 条不会因本轮变红；量它们是为了不把一条会长期假阳的判据写进闸。）

## 设计

### Root A：行必须为其声明负责

对**本轮新增且在 HEAD 存活**的行：

1. 归属解析改用 owner **包前缀**而非 `SKILL.md` 精确匹配，与真实书写约定对齐。
2. 解析出 0 个 selectable owner → 维持现状静默跳过（非 curated 行、其他表形态）。
3. 解析出 >1 个 selectable owner → 现状是 advisory warn 后丢弃，改为**阻断**。行被丢弃却不报错，正是形态 2 的静默面。
4. 解析出恰好 1 个 selectable owner，但该 owner **不在累积 changed 集内** → 新增硬错误 `impact_chain_row_vouches_for_unchanged_owner`。这关掉形态 1（还原后行仍替一个不存在的变更背书）与拼错/过期 key。

方向是收紧。风险是假阳，判据已按真实台账量过。

### Root B：merge 带进来的声明由上游轮承担（**已删除，见文末裁决节**）

> 以下为当时的设计，保留作为裁决的证据链。实现过、被三轮评审击穿八次、最终由风险 owner 裁决删除。

轮对 owner X 的索要，若 X 的变更是从一个 **base_ref 可达的父**带进来的，则该轮不索要——X 的声明属于上游分支自己的轮，已随该分支落地。实现上：轮头是 merge commit 时，其被并入的父若可从 `base_ref` 到达，则该父已声明的 owner 从本轮索要集中扣除。

方向是放宽，因此**必须**由对抗评审专门过一遍规避面：能否构造一个 merge，把 owner 变更藏进被扣除的那部分。护栏是「被并入的父必须 base_ref 可达」——即那部分历史已在集成分支上、已过它自己那一轮的闸。这条护栏若被评审击穿，本项停下交用户裁决，不擅自发布放宽。

## 风险路由（feature-risk-router）

- **risk tags**：`shared-gate`（主）、`release-ops`（闸是 CI 必需检查，改它即改全仓合并语义）、`security-review`（变更触发臂：Root A 是 hardening，Root B 移除拒绝条件、直接触及本闸自述的反 laundering 信任模型）。
  不适用：`visible-ui`（记 `visible surface: no`）、`data-migration`、`money-quota`、`permission-access`、`ai-output`/`ai-action`、`external-integration`。
- **required gates**：
  1. 本 spec 先于任何闸代码编辑存在（已满足）。
  2. `testing-strategy` 测试层矩阵；闸有可执行行为，RED baseline 已在。
  3. `skill-extraction-workflow`：共享技能闸的 owner；本轮自身要在 source-register 补 impact-chain 行——**自指**，改后的闸会检本轮自己的行，实现时须处理 bootstrap 顺序。
  4. 独立对抗评审绑实现 diff，并**显式带规避面透镜**审 Root B 的放宽（security-review 在无专职安全 owner 下由此承担，不声称等同专业审计）。
  5. 既有回归全绿：`test_impact_chain_gate_dateless_host.sh`、`test_check_ccl_impact_chain_refscripts.sh`（重套件）、`test_register_firing_path_*.sh`、regression runner 各 lane。
  6. 真仓自检：`check-ccl-skills.sh` 改前/改后在本仓跑，verdict 不得意外翻转。
  7. MR CI 绿。
- **skippable gates**：渲染证据 / 设备 / 浏览器（无可见面）；live 基础设施（无）；`multi-agent-delegation` 记 `local`——两处改动落在同一个 964 行文件的互相咬合的谓词上，拆给并行 worker 会产生语义不一致，收益为负。
- **stop reasons**：
  - 对抗评审在 Root B 的放宽上找到 laundering 路径且无有界修法 → 停，交用户裁决，不发布放宽。
  - Root A 收紧若被证明会回溯改判已落地历史 → 停（闸自述 diff-scoped，实现须自证不回溯）。
  - 本轮自指 bootstrap 若无法在不自我豁免的前提下闭合 → 停。
- **verification evidence**：上述 gate 1–7 的实测输出，逐条记入本文件的 gate 记录节。

## 实现记录

**Root A** 落在行归属段。归属改为按 owner 包前缀解析（与台账真实书写约定对齐），并把「是谁的行」与「那个 owner 变没变」拆成两个先后独立的问题——旧实现用同一个累积 changed 集过滤解析结果，于是 owner 一旦退出该集，行同时停止被评估与被索要。新增拒绝 `impact_chain_row_vouches_for_unchanged_owner`；多绑定由 advisory 改阻断（丢弃行却只告警，是三者里最坏的组合）。另外把整段的执行条件从 `upstream.any?` 放宽到「或台账本身有变更」——这是 owner-restored 洞的另一半：owner 被还原后全程无变更 owner，整段直接跳过，存活的行连看都没被看一眼。

**Root B** 落在轮索要段。轮头是 merge、且某个父可从 `base_ref` 到达时，扣除「本轮为该 owner 新增的行全部已存在于该父包内」的 owner。护栏是逐行包含：一行新内容即不扣除，所以夹带在冲突解决里的规则行仍被索要。

**入口尺寸闸的介入（记录，因为它改变了落点）**：F6 规则原本写进 `SKILL.md`，被仓库自己的 `entrypoint_size_block` / `entrypoint_word_budget_block` 拦下——该入口是 severe size-debt 面，规则集不得单调增长。规则改落 `references/source-to-skill-extraction.md` 的 charter 邻接小节，触发点在 Step 0（修复轮开启的那一刻），入口零字节增长。这是闸提了个真意见，不是绕行。

## Gate 记录

| Gate | 结果 |
| --- | --- |
| 探针套件（**终态 4 腿**） | 全绿：leg 0 控制组、A、B、H（不相关表格回归）。对 origin/dev 的反向差分：A、B 复现；H 对中间那版未加条件的加宽复现。期望拒绝的腿都断言**具体令牌**——rc 单独是弱 oracle，起草时抓到过一次「rc 对但拒绝原因不对」的假绿。中途为 Root B 建过的八条规避腿随 Root B 一并删除 |
| 既有回归 | `test_check_ccl_impact_chain_refscripts.sh`（重套件）、`test_impact_chain_gate_dateless_host.sh`、`test_register_firing_path_resolution.sh`、`test_register_firing_path_wiring.sh`、`test_check_ccl_source_register_lifecycle.sh`、`test_check_ccl_register_pending_exclusion.sh` 全绿 |
| 真仓改前/改后差分 | `test_impact_chain_gate_verdict_differential.sh`：**全量 64 个 merge**（对 git 自身枚举做完整性断言，漏一个即失败）+ 2 条合成复演用例（含一条基线红，使放宽臂可达），两个方向任一变化即失败。结果：60 个点两向一致；**4 个点有意变红**——它们用 corrective rewrite 回填台账行，owner 变更在其 base 之下，这个形状与「owner 被还原后遗留的行」在 diff 上不可分。四个逐一具名，且各自约束到 `newly refused` + 确切诊断令牌，豁免吞不掉反方向（用 always-accept 闸实证过）。闸是 diff-scoped，不回判已落地历史，故四者无运行影响。**覆盖边界**：只覆盖 CI 实际评估的合并结果拓扑（base=M^1, HEAD=M）；分支 tip 拓扑不在其中 |
| 路由面 | `make eval-routing`：32 skills，blocking none，advisory 0 |
| 自指 bootstrap | 改后的闸检本轮自己的三行：rc=0。RED-baseline **实跑**（非假设）：轮内 amend 突变——改写锚定句、单独回退闸脚本——各自以 `impact_chain_firing_path_missing` 点名本 owner 转红，未突变控制组绿。两行的 firing path 各自承重。注：用新 commit 而非 amend 做突变会因新建一轮而红在 `impact_chain_gate_missing`，是误归因 |
| `check-ccl-skills.sh` | 见下方状态节 |
| 独立评审 r1/r2/r3 | codex（OpenAI 家族，与实现者 Anthropic 家族互斥）；tracked，implementer-supplied plan，三个 owner 技能原生调用（skill-extraction-workflow / testing-strategy / terminal-cli-dev）。r1：2 条（P1 规避 + P2 回归），采纳修复。r2：1 条 P1（部分导入 / 完全不导入）。r3：2 条 P1（重复行抵消、二进制与模式变更不可见）。r1 的 P2 与全部 Root A 相关项已修并有反向差分；Root B 相关项触发删除裁决 |

### r1 发现与处置

**P1 — Root B 的包含判据可被绕过（真洞，采纳）。** 第一版判据只问「本轮为该 owner 新增的每一行是否存在于父的包内」。这是拿本轮的动作去比父的**内容**，而不是比父**改了什么**，于是三种形状都能穿过：

- **删除**：merge 解决里删掉一条既有 owner 规则，同时导入一行合法上游行。导入满足了新增行判据，删除从未被检查，那次删除无声落地——这正是放宽本该堵死的 laundering 路径。
- **重定位**：规则从 owner 的 SKILL.md 挪进同包的 reference。路径盲的行集合看来「两边都在父的包内」。
- **重复**：集合丢弃出现次数，父已有的行再加一份仍读作导入。

修法（按评审给的 smallest_fix）：判据改为**逐路径、计出现次数、涵盖删除**——本轮为该 owner 每条路径新增/删除的行**多重集**，必须分别被**该父自其分叉点起**的新增/删除多重集包含。父没做过的事就是本轮自己做的。

**P2 — 前缀解析拖进了不相关表格（我违反了自己的验收条件，采纳）。** 台账不止承载本闸这一张表，其行过滤刻意宽松（五列、状态词、非表头），而 `<slug>/SKILL.md` 精确匹配在事实上一直充当判别器——不相关的五列行几乎不会含它。前缀解析把这个判别器拆掉了，于是一条引用 `skills/<owner>/references/note.md` 的无关行会新绑到某个 selected owner，可能被当作 unchanged-owner 拒绝或被拖进行为证据校验。

修法：前缀这一档**加条件**——行必须带 `behavioral-evidence:` 片段（本闸独有、别的台账表格不用的声明）才享受加宽；精确 SKILL.md 解析保持无条件，故既有拒绝路径一条不丢；不作声明的行也不受新的 unchanged-owner 拒绝约束（什么都没声称的行谈不上背书）。

**新增四腿并做反向差分。** leg E（删除）、F（重定位）、G（重复）、H（不相关五列表格回归）。对**修复前**的闸：E/F/G 全绿（本该拒绝却放行）、H 红（本该跳过却拒绝）——四条全部复现。对修复后的闸：十腿全绿。没有这个反向差分，新腿只是装饰。

## 残留与边界

- **重命名链的修复没有专属探针（已知残留）。** 声明支原本用 `selectable_path` 过滤，漏掉了 `lineage_extra` 里的中转名——旧谓词用 `upstream_set[path] || lineage_extra[path]`，是把中转名算进来的。修法是恢复同款准入（`selectable_path || lineage_extra`），方向上严格更安全（只会多认一条合法声明，不会少拒绝）。但我没能构造出可复跑的 fixture：`rename_excused` 要求包是**纯移动、字节一致**，而要让行有效又需要实质变更，两者在同一轮里互斥；真实的 X→Y→Z 中转形态需要跨轮编排。故这条修复目前只有代码对照证据，没有探针。写下来是因为它就是本轮反复强调的那件事——未应用的突变只是假设。

- **形态 2 未全闭**：evidence 单元格用技能相对路径（`scripts/x.rb`、`references/y.md`，无 owner 段）的行仍绑定不到 owner，真实台账里有 42 条。可用 firing-path 回退补上，本轮**不做**：抽样 5 条里 2 条会误绑——evidence 单元格写的是非 curated owner，回退却把行绑给 firing-path 指向的 owner；闸自己的文案把 evidence 单元格定为 machine key，回退等于反转该契约。需要独立证据驱动，不搭本轮便车。
- **分支 tip 直评与 CI 评估点不同**：CI 走 GitHub 的 merge ref（base=M^1, HEAD=M），本地直接评估分支 tip 会看到不同的轮切分。PR #25 的分支 tip 在新旧闸下都红（其一轮内有 owner 变更、而该轮的台账追加落在导入 dev 行的 merge 上），非本轮引入、非形态 3。
- **新拒绝的作者体验**：unchanged 的配对控制行按既有约定写裸名（`` `testing-strategy` ``）才不被读成「本行声称的变更 owner」；已把这条写进拒绝文案。

## 待办

- [x] RED baseline（0934e62）
- [x] 复现判定与两根结论
- [x] 真实台账归属分布实测
- [x] 风险路由与 gate 清单
- [x] Root A 实现 + 各腿转绿
- [x] Root B 实现 + 规避面自审（leg D）
- [x] 既有回归 + 真仓差分 + 路由面
- [x] source-register 行 + 自指 bootstrap（含实跑 RED-baseline 差分）
- [x] 独立评审 r1/r2/r3（带规避面透镜）——Root A 相关发现全部修复，Root B 触发删除裁决
- [x] 风险 owner 裁决：Root B 删除
- [ ] 终态候选的最后一轮 review + challenge
- [ ] MR + CI


## 裁决：Root B 删除（keep / delete / narrow / **replace** → **delete**）

Root B 是放宽——它移除一条拒绝条件。三轮独立评审在**同一个代理**上找到八条穿透路径：

| 轮 | 泄漏 |
| --- | --- |
| r1 | 删除、重定位、重复 |
| r2 | 部分导入、完全不导入、拒绝父的删除 |
| r3 | 重复行抵消、二进制/文件模式变更不可见 |

每一次修复都是把同一个形状——「用文本 delta 比较来代理『这一轮什么都没自己写』」——再实例化到更多输入上。本仓 `skill-extraction-workflow` 自己的规则说：同类发现跨轮复现是设计信号，应当把判据重表述到自己拥有的**不变量**上，或删除该能力；且该裁决必须由**独立于提出者的风险 owner**做出。

**真实需求强度**：形态 3 只在上下游两轮碰同一 owner 时触发，代价是作者改用 rebase 集成一次——034 批次三就是这么过去的，已经是成文实践。

**风险不对称**：Root B 的失效模式是静默接受未申报的 owner 变更，正是形态 1、2 那一类的丢失风险。用「一次 rebase 的不便」去换「共享合并闸上的静默漏报」，方向是反的。

**裁决（风险 owner，2026-08-23）**：删除。约 140 行扣除逻辑与八条规避腿一并移除。若日后要重开，必须基于不变量（例如以 `git merge-tree` 算出干净三方合并本该产出的 owner 子树再比对），不得再用代理——本机 git 2.50.1 支持该路径，但那需要独立的证据驱动，不搭本轮便车。

**Root B 的两条台账行已重写**（尚未落地 dev，append-only 保护的是已落地行）：其中一条改为 `semantic-control` 配对控制，记录同类复现规则本轮**按写好的样子触发了**，这本身是该规则的行为证据。

## 最终范围

- **Root A（发布）**：归属按 owner 包前缀解析（加宽档以 `behavioral-evidence:` 声明为条件，保住不相关表格的既有行为）；归属与变更与否拆成两问；新增 `impact_chain_row_vouches_for_unchanged_owner`；多绑定由 advisory 改阻断；台账单独变更时也进入评估。
- **形态 1、2**：关闭。
- **形态 3**：不修。rebase-not-merge 仍是成文绕行解。
- **探针**：四腿——控制组、A、B、不相关表格回归。A/B 对 origin/dev 复现、对本候选关闭；回归腿对中间那版未加条件的加宽复现。


## 评审史（八轮，全部 codex / OpenAI 家族，与实现者 Anthropic 家族互斥）

每轮都绑一个新候选（候选一变，上一轮的判定即失效）。发现全部采纳修复，没有一条被降级或搁置：

| 轮 | 发现 | 处置 |
| --- | --- | --- |
| r1 | P1 Root B 包含判据可绕过（删除/重定位/重复）；P2 前缀解析拖进不相关表格 | 判据改逐路径计数；前缀档加 `behavioral-evidence:` 条件 |
| r2 | P1 单向包含放过「部分导入 / 完全不导入」 | 改双向 + 父侧枚举 |
| r3 | P1 重复行抵消；P1 二进制与文件模式变更不可见 | **触发 Root B 删除裁决** |
| r4 | P2 探针只覆盖形态、不覆盖验收项；P2 差分工具只存在于 scratch | 补 leg L/M；差分工具落成 tracked 套件并进 heavy lane |
| r5 | P1 差分工具把「基线拒绝→候选接受」只当提示 | 两个方向都计失败 |
| r6 | P1 基线非零被当普通判决，会掩盖候选回归 | 逐点断言基线必绿 |
| r7 | P1 不作声明的多绑定行被硬挡（原为告警） | 多绑定阻断加声明条件；补 leg N |
| r8 | P1 不作声明的行丢了一条既有拒绝；P1 `./` 前缀路径解析不到 | 改为**二分**：作声明走新语义，不作声明逐字保留旧谓词；前缀允许 `./skills/`；补 leg O/P |
| r9 | P1 差分未覆盖 PR tip 拓扑；P2 前缀正则过宽（`../`、`/`） | 收窄声称到工具真实覆盖；正则收紧为仅 `./skills/` |

**两次是我自己的假绿被抓住**：r7/r8 那两条都是我为修上一条发现而引入的新洞——「修复本身属于当前候选，要重新走完整枚举」这条规则在本轮实证了两次。

## 合并前的人工裁决点

- **自主评审预算已用尽**。规则给的是初审 + 至多四轮 challenge；本轮因候选反复变化开了八条链。按预算规则，此处标 `interim`，是否再开评审轮由风险 owner 定。
- **challenge lane 已跑**（见下节），不再是缺口。
- **形态 3 不修**是已裁决项，rebase-not-merge 仍是成文绕行解。
- **形态 2 残留**：evidence 单元格用技能相对路径（`scripts/x.rb`）的行仍绑不到 owner；firing-path 回退会误绑，故本轮不做。


## 对抗 challenge（补跑）

`--mode challenge`，同链绑定同一候选，focus 显式指向收紧面的规避：行能否靠 evidence 单元格写法 / 声明片段 / 列布局躲开三条新拒绝；`behavioral-evidence` 判别器能否被操纵以在两支谓词间搬行；作声明/不作声明的二分是否丢了旧闸的拒绝；轮划分与行存活预算能否被操纵使行落进不索要其 owner 的轮。

**一条 P1，采纳修复**：rooted `/skills/<owner>/…` 引用解析不到——我先前为堵 `/<owner>/` 过宽，把 `/skills/` 一并排除了。引用解析不到的行会在任何拒绝生效**之前**被跳过，所以少一个字符的前缀就是完整的规避路径。修法：允许 `./skills/` 与 `/skills/`（分隔符仅在 `skills/` 紧随时接受），九种路径形态逐一实测；补 leg O2 并做反向差分（对修复前的闸复现）。

这条正是 review 模式九轮没找到的东西——它问「这段代码对不对」，challenge 问「怎么绕过去」。补跑 challenge 的价值就在这一条上。

## 最终证据

| Gate | 结果 |
| --- | --- |
| 探针套件 | **10 腿全绿**：控制组、A、B、H、L、M、N、O、O2、P。期望拒绝的腿全部断言具体令牌；A/B/L/N/O/O2/P 各有反向差分 |
| 判决差分 | **全量 64 个 merge** + 2 条合成用例（含一条基线红）。60 点两向一致；4 点有意变红（corrective-rewrite 回填），逐一具名并约束到方向+令牌；always-accept 与 always-refuse 两个 mutant 均被抓 |
| 全量回归 | 30 套件 `test_check_ccl_regressions_full_ok`，零失败 |
| 仓库检查 | `ccl_skill_check_clean_ok`，`r0_status=private-ok` |
| 路由面 | `make eval-routing` blocking none |
| 评审 | 九轮 review + 一轮 challenge，全部 codex（OpenAI 家族，与实现者互斥）；所有发现采纳修复，无降级、无搁置 |


## 第三次同类复现：路径谓词重表述（裁决 = replace）

`owner_package_path` 连续四轮被同一类发现击穿——`./skills/`、rooted `/skills/`、`@`/Unicode 余段、`../../<owner>/`。每次后果相同：引用解析不到，而**解析不到的行会在任何拒绝生效之前被跳过**。

根因：我在用**路径语法**解析**散文**。evidence 单元格是人写的说明，顺带提到路径；穷举合法 git 路径写法这件事四轮没穷举完，也不会穷举完。

**裁决（replace，非 patch）**：归属解析改为对闸自己拥有的有限词表做**成员匹配**——selectable owner 名 ∪ lineage 名，问「单元格是否把某个名字当作路径段提到」（`(?<![\w-])<name>/`）。没有语法可穷举；四种泄漏形态全部包含 `<name>/`，一次覆盖而非四次接受。

**残留（镜像面，更小）**：URL 路径里恰好含 selectable 名会绑定该 owner。这类链接通常正指向该技能、绑对了；真正误绑要求无关站点的路径段恰好等于某个 owner 名，代价是一条带诊断的可见红——相对于「行静默不被评估」是更轻的方向。

**实测**：真实台账 189 条数据行下 122 条绑定单一 owner、**零多绑定**（阻断规则安全）、67 条跳过。探针 12 腿全绿；对路径解析版的闸，leg O4 复现；对 origin/dev，12 腿红 7。


## CI 前置（已核，非改动）

差分工具需要基线 blob 与 64 个祖先 merge 对象。评审提过浅克隆会挡住每一次改动——本仓不成立：`.github/workflows/ci.yml` 全部六个 job 都是 `actions/checkout` + `fetch-depth: 0`，`npm-publish.yml` 同。评审看不到这点是因为 packet 未含 CI 配置，属**输入缺陷**（code-review 自己的规则：补 packet 重跑该 lane，而不是改候选去迎合）。工具在对象缺失时已带可操作信息 fail-closed（点名不可达的 SHA 与「取回集成分支历史或有意重新定基」），不是静默跳过。
