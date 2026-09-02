# 085 — 清偿 084 账本里明写处置的 P1

## Artifact classification

`gate implementation`（三处均是共享确定性闸）。其中两处改动**改变规则语义**，因此本文件是规则要求的仓内持久计划工件，不能用内联计划：

- `review_ledger_binding.py` 改的是 **scope 语义**（哪些路径的变动需要评审证据）与 **failure 语义**（脏树改为拒绝）。
- `review_gate.py` 改的是 **failure 语义**（继承铸造新增一条拒绝）。

## 来源与授权

084 轮终态 `continuation_authorization_required`，五条 P1 随变更记入账本交给人。其中两条是仓内闸无法自证的固有边界（残余写进 docstring，**本轮不动**）：

- `enforcement-step-is-inside-the-candidate` — 残余记于 `.github/workflows/ci.yml` 注释。
- `evidence-is-caller-controlled` — 残余记于 `review_ledger_binding.py` docstring。

另三条是"下一个碰这些文件的轮次"的挂账。本轮是那个轮次。

## Scope

| # | 变更 | 语义轴 | 状态 |
|---|---|---|---|
| 1 | `.github/workflows/ci.yml` merge_group 引用 | 覆盖边界的**声明** | 本轮做：删死分支 + 追 supersede 行（见下"第 1 条的证否"） |
| 2 | `review_ledger_binding.py` 绑定路径集合反转 | scope | 本轮做 |
| 3 | `review_gate.py` 继承铸造 chain-id 等式 | failure | 本轮做 |

不在 scope：聚合候选（merge_group）的账本绑定语义；两条固有边界。

### 第 1 条的证否（本轮新增证据，推翻了开轮时的取景）

开轮假设是"死引用、无既定义务"。实测推翻：

- `source-register.md`（append-only）第 516 行明写这是已落地义务："scoping the CI step to pull requests leaves a skipped step in a merge-queue run — where a skipped step does not fail its job. Both land: … and the step now also runs for `merge_group`."
- 但 `.github/workflows/ci.yml` 的 `on:` 只有 `pull_request` 与 `push`，从未订阅 `merge_group`。**台账那句在 HEAD 上不成立**：合并队列运行里该 workflow 根本不触发，谈不上"step 也会跑"。
- `gh api repos/ccoalm/ccl-skills/branches/main/protection` → `required_merge_queue: absent`；`dev` 未保护。**本仓当前没有合并队列**，窟窿与补丁都不是活的。

因此"补齐 `on: merge_group` 让台账成立"被否决：今天零执行，将来真开队列时反而会拒掉合法排队 PR（round3 finding：没有账本绑得住聚合 diff 哈希）。为让一句话成立而使系统变差，不做。

残留的真实风险不在代码而在文本：**第 516 行会让下一个人以为合并队列已被覆盖**，据此开队列就会带着错误的覆盖假设开。处置：删掉那条永远跑不到的分支，并向台账追一条 supersede 行写清真实覆盖边界（合并队列**未**被覆盖；要开先解聚合候选绑定）。义务本身不撤销，被纠正的是那句不成立的主张。

## 设计裁决

### D1 — 绑定路径集合反转，排除项按轮计算

现状 `DEFAULT_PATHS = ("skills", ".github")` 是白名单。round3 finding 的根因谓词是"除这两者外的每个 tracked 路径都被排除"，仓根 `Makefile` 只是其中一个实例——按同形状全类一次清扫，改白名单为"全部 tracked 路径除排除项"。

**必须有东西在候选之外，否则账本永远提交不了**：收据落在绑定集合里就会移动它自己记录的哈希。但排除的粒度是承重的——见下方 R2。

代价明写不掩盖：此后连只改 `README.md` 的 PR 也会要求账本。依据是本仓已记录的判据——共享闸上误报比漏报便宜（`same-class-recurrence-converges-by-deletion`）。

### R1 — 候选必须是已提交树（评审 round 1 的 P1）

冻结包从工作树构建且含未跟踪文件，所以脏树会算出一个干净检出永远重算不出的哈希：作者把它写进账本，合并面再报「没有证据绑定落地候选」——合法 PR 被拒。实测：仓根放一个未跟踪文件，新集合下候选哈希改变，旧集合下不变。处置为**出声拒绝**而非静默出哈希，与本仓「合并的是已提交树」的既有立场一致。

### R2 — 排除项按轮计算，不写成子树（challenge round 2 的 P1）

排除整棵 `specs/` 会连带排掉**历史**：一个 PR 可以删改早先轮次的 plan 与收据（即已提交的评审历史本身）而无需任何证据，闸照样通过。改为只排除**本轮新增**的、位于该轮自己 `<round>/evidence/` 目录下的路径；`specs/` 下的任何修改与删除、以及 evidence 目录之外的任何新增，一律绑定。留在外面的残余明写：往**更早**轮次的 evidence 目录里新增文件也会被排除，因为该规则是结构性的、不认轮次。

### R3 — 排除谓词从路径代理换成内容不变量（继承轮 round 3 的 P1）

同类第三次：往 evidence 目录里新增任意非收据文件（`payload.py`、二进制夹具、无候选绑定的 JSON）同样被排除，可无证据落地。前两次都是在**收窄路径**，第三次说明路径本身就是代理——「它在 evidence 目录里」被当成了「它是一份收据」。

按本仓已记录的判据（同类复发不做第四次收窄，把谓词换成控制方自己拥有的不变量），排除条件改为：该路径在某轮 evidence 目录下 **且** 其已提交 blob 能解析为带 64 位十六进制 `candidate_sha256` 的 JSON 对象。脚本、夹具、无绑定的 JSON 一律绑定。

差分证据：把该谓词退化为恒真，恰好红那三条走私用例，别的不动；真收据仍被排除（否则任何账本都提交不了）。

### R4 — 第四次同类击穿：停止收窄，明写处置（新链 round 1 的 P1）

新链在最终候选上又找到同一类：构造一个带任意 64 位十六进制 `candidate_sha256` 字段的 JSON，仍会被当作收据排除，任意 JSON 载荷可搭车。

**本轮不修，这是判据要求的动作而不是预算耗尽的借口。** 四轮四次击穿，每一版谓词——子树、路径、内容字段——都是「这是控制器生成的真收据」的代理；而该文件由候选自己提供，所以**没有任何仓内谓词能认证它**。这与本仓已经记录并接受的固有边界 `evidence-is-caller-controlled` 是同一条：闸跑候选自己的 validator，读到的东西都没有独立认证。本仓判据明写：同类复发要质疑该能力是否该存在、按不变量或删除收束，**不做第四次收窄**。

已缩小的部分是真实的：子树排除（可改写历史）与路径排除（可走私脚本/二进制）都已关闭，剩下的走私面窄到「一个带假绑定字段的 JSON 数据文件」，且它必须作为新增文件出现在 PR diff 里、被人看见。

留给人的裁决（本轮不代为决定）：接受该残余并如实记录；或另开一轮把排除机制整体换掉——例如让账本绑定 evidence 提交之前的树，从而根本不需要任何排除谓词。后者动的是闸的形状，不是再打一个补丁。

### R5 — 撤回一条被夸大的发现，并保留其中站得住的部分（收尾链的两条 P1）

- **pathspec 被当模式解释**：排除项由候选自己的文件名构成并交回 git。评审定性为「一个名为 `*` 的收据可排除一切、候选变空、闸静默通过」。**实测未复现**——排除项带完整路径，glob 只在该 evidence 目录内展开，而同目录成员本就是收据。故按证据把主张收窄，不按夸大版落地；同时**删掉了我为它写的那条用例**，因为它在未修的代码上也不会红，一个永远不会红的断言在本仓是明令禁止的。改动仍然保留（`:(exclude,literal)`）：把「按模式解释这些名字」这个本就不需要的能力去掉，成本为零。
- **shell 命令替换**：已证否。本文件所有 subprocess 调用都传 argv 列表、无 `shell=True`，没有任何 shell 解析这些文件名。

### R6 — 所有者处置：接受 `evidence-is-caller-controlled` 残余

2026-09-02，仓库所有者把 R4 留下的同一 occurrence 裁为 `accepted_tradeoff`。处置精确绑定 round 1 receipt `0d4ec074…` 与 finding `be4f285d…`；完整哈希和依据见 `evidence/disposition-evidence-is-caller-controlled.json`。

这里不新增规则。`dual-track-review-gate.md` 已规定：已接受发现被后续候选合法重报不算升级，但每个候选都须重新证明 reachability / severity 没有变化。重复写一条同义规则只会造成单调增长和漂移。

`needs_human_decision` 不能由后续候选内证据消解；本次是所有者对原 occurrence 的外部裁决，而不是用新的候选收据覆盖历史人工决策。另一个 finding class `residual-stated-in-the-candidate` 不在本次处置范围，继续保持原状态。

重开只有两个信号：

1. 账本因独立于本残余的原因需要移出候选工作树，此时重新评估能否替换或删除排除机制。
2. 真实交付中首次出现非评审构造的走私；纯合成对抗用例只重验已接受边界，除非当前候选扩大了 reachability 或 severity，否则不单独触发重开。

### D2 — 继承铸造拒绝 `predecessor_chain_id == review_chain_id`

定级更正（开轮时说高了）：这**不是**堵住敞口。`validate_extraction_review_state.py:386` 已有 `if current_chain == chain_id: fail("succeeds its own chain")`，084 台账第 516 行也明写"a self-succession is refused one layer up by the closeout validator rather than at mint time"，实测属实。

本轮的价值是**把已有拒绝下沉到铸造点**：只走 controller、不走 closeout 的路径上，目前无人比对。等式方向被 `:386` 现存代码反向印证（同一谓词、同一语义），故取"必须不同"。

## Acceptance matrix（决策表：具名输入 → 单一裁决）

### `review_ledger_binding.py`（现有裁决集合不变，仅 scope 输入变）

| 输入 | 裁决 |
|---|---|
| base 不可解析（`--quiet` / 不存在的 ref / 空） | `unevaluated`（拒绝并给具名诊断，非通过） |
| diff 相对 fork point 在绑定集合上为空 | `no-change` |
| diff 非空，且已提交 evidence 中存在绑定该候选哈希的账本 | `pass` |
| diff 非空，无账本绑定该候选哈希 | `refuse` |
| evidence 树脏（未提交） | `refuse` |
| **新增**：diff 只新增「某轮 evidence 目录下、且带 `candidate_sha256` 绑定」的 JSON 收据 | `no-change`（唯一排除项） |
| **新增**：diff 在 evidence 目录下新增非收据文件（脚本 / 夹具 / 无绑定 JSON） | `refuse`（继承轮找到的走私路径） |
| **新增**：diff 修改或删除 `specs/` 下已提交的 plan / 收据 | `refuse`（此前为 `no-change`——challenge 找到的历史可被改写） |
| **新增**：绑定路径内存在未提交改动或未跟踪文件 | `refuse: uncommitted changes`（此前静默产出不可复算的哈希） |
| **新增**：diff 只触及仓根 `Makefile` / `scripts/` / `README.md` 等此前被排除的 tracked 路径 | `refuse`（此前为 `no-change`——**本轮改变的就是这一行**） |

### `review_gate.py` 继承铸造

| 输入 | 裁决 |
|---|---|
| predecessor 非终轮（索引或算术任一不终） | `reject`（既有） |
| predecessor 无 chain id | `reject`（既有） |
| predecessor 候选未移动 | `reject`（既有） |
| predecessor scope / controller / owner 不一致 | `reject`（既有） |
| **新增**：`predecessor_chain_id == review_chain_id` | `reject: succeeds its own chain`（此前为 `accept`） |
| 以上全不触发 | `accept`，铸造 succession |

## 测试层决策表

| 层 | 处置 | 命令 | 理由 |
|---|---|---|---|
| unit / 脚本套件 | **add + run（RED 先行）** | `bash skills/skill-extraction-workflow/scripts/test_review_ledger_binding.sh`、`bash skills/code-review/scripts/test_review_gate.sh` | 两条语义改动各需一个先红后绿的差分用例 |
| integration | run | `make test`（`test-repo-gates` / `test-regressions-fast` / `test-code-review`） | 反转绑定集合会波及跑该闸的合成夹具 |
| CI-only lane | run | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `make test` 不含它，本地绿≠CI 绿 |
| 泄漏 / 结构 | run | `python3 scripts/check-public-sanitization.py .`、`python3 scripts/check-spec-references.py` | 改共享技能文本 + 新增 specs 目录 |
| E2E / 渲染 | not applicable | — | 无渲染面（`visible surface: no`） |
| manual | not applicable | — | 无人工路径 |

## Status-sync target

`skills/skill-extraction-workflow/references/source-register.md` — 追加本轮行（append-only，不改既有行）；第 1 条若裁为撤销，走 supersede 行而非编辑第 516 行。

## Review / challenge gate

`shared-gate` + `release-ops` + `security-review`（change-triggered 臂，(2)(3) 是绕行闭合/加固）。需要绑定最终 diff 的独立对抗评审；无专职安全 owner，故安全侧最多到 `security-first-pass-only`，不得记为审计通过。合并授权在用户手上。
