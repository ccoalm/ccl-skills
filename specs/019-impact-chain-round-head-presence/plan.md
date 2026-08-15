# 019 — impact-chain 闸：证据存在性按轮次 head + `--first-parent` 承重用例

**Shared-gate 分类**：`gate implementation`（失败语义变化：关闭 renamed-away owner 逃逸）。风险 tags：`shared-gate`；security-review not-applicable（security posture unchanged——确定性 git 读取逻辑收严，无信任边界/凭据/授权语义变化）。

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 防止两类未来失败：(1) renamed-away owner 的 pre-rename 实质变更永远无人申报（闸静默放行未申报的共享技能行为变更）；(2) `--first-parent` 轮界语义被重构无意删除而测试全绿（轮次分区静默变形）。 |
| Scope | in：`impact-chain-gate.rb`（证据存在性 ref、per-round 主体集、行申报映射、校验迭代面）、`test_check_ccl_impact_chain_refscripts.sh`（新 fixture）、台账残留表两行结清、source-register 行。out：闸 251/252 行 cumulative 剔除条件的工作树读取（树干净时与 HEAD 等价，非本轮缺陷）、其他分类器语义、check-ccl-skills 接线。watermark：not-applicable（非迭代程序源）。 |
| Depth | Generator/tooling change（确定性验证器变更）。 |
| Root cause | 轮次分区落地时证据存在性检查沿用工作树读取；rename-excuse 的理据（「行引用已消失 SKILL.md 会被拒」）因此成立并被写进 per-round 交集，形成 pre-rename 轮次的主体集空洞。`--first-parent` 由设计论证选定但无判别 fixture，属「机制存在但无 firing 证明」。 |
| RCA analysis | widen：(i) 分区重构迁移各检查时未逐一审视 ref 基准（工作树 vs 轮次 head）；(ii) merge fixture 只覆盖「合并轮次可用」正例，未构造区分两种走法的判别用例（enumeration-completeness 轴缺失）；(iii) 上轮对抗评审收敛后残余如实进台账（检测机制正常，本轮消化其输出）。反事实：修 (i)/(ii) 则对应缺陷不存在；(iii) 非缺陷。防止机制：判别 fixture（机械控制）+ 台账结清。 |
| Failure mode analysis | 修复不当的三个洞：存在性改 ref 后若把删除轮 fail-closed 一并放行，比原逃逸更大；per-round 加回 excused owner 若不同步行申报映射→「要求行但行无法被认可」死锁；若不同步校验迭代→该 owner 的行逃过 RED 底线。fixture 须覆盖这三面。 |
| Lifecycle impact | implementation（闸脚本）、testing（fixture）、iteration feedback（台账结清）、onboarding（闸内注释同步）。product/design/launch：not-applicable。 |
| Evidence plan | produced artifacts：not-applicable（非 session 复盘）。inspected：闸全文关键段（round 分区 41-63、选集 141-255、行收集 256-335、证据/presence 336-405、锚解析 657-760、校验 761-874）、harness 结构与 rename/merge case、台账 38-47。external grounding：not-applicable（内部闸语义，无 state-of-art 主张；git 行为以 fixture 实测为 primary source）。 |
| Completion standard | 新 fixture 中逃逸/接纳两条在未修复闸上差分 RED（实测记录）；first-parent 判别条在去 flag 突变体上差分 RED（实测记录）；整套 harness 绿；`check-ccl-skills.sh` clean；dual-track 无未处置 P0/P1；台账两行结清 + register 行（RED-baseline + firing-path）。 |

## 缺陷与修法

**(a) 证据存在性按轮次 head。** `bad_evidence_files`（原 376 行）用 `File.file?` 按工作树查证据引用的 SKILL.md——改为按行所属轮次 head（`row[:scope].head` 的 git blob）。联动三处（否则按 Failure mode 列出的洞）：

1. per-round 主体集（`upstream_for_round`）：按轮次顺序沿各轮自己的 git rename_pairs 传播 **lineage 集**（种子 = cumulative 选集 ∪ rename-excused 源名）；lineage 名（excused 源名与瞬态中间跳名）在其 SKILL.md 仍存在于该轮 head 的轮次里被要求申报（rename 掉它的那一轮不要求——彼轮由幸存名申报；删除 owner 从未被剔除，行为不变，维持 fail-closed）。瞬态中间跳（X→Y→Z 的 Y）由 dual-track r1 双 lane 同类命中后并入——cumulative 端点选集看不见 Y。
2. 行申报映射（evidence 识别集）：lineage 名的行可被认可为申报。
3. 校验迭代面：lineage 名（有行时）进入 RED 底线/firing-path 校验（锚按行自己的轮次 scope 解析，本就支持）。

**(b) `--first-parent` 承重用例。** 判别历史形状：worktree 分支上「先 append 行、后落 owner 变更」再 `--no-ff` 合并。first-parent 走法：整分支收敛为一轮（merge commit 为唯一轮界）→ 行与变更同轮 → 通过。全走法：分支内碰账本的 commit 成为轮界 → 变更落进无行的后一轮 → 拒绝。fixture 断言 rc=0；去掉 flag 的突变体上该 fixture 转红（差分实测入证据）。

## 验收判定表（输入 → 闸判定）

| # | 历史形状（输入） | 修复前 | 修复后（=断言） |
| --- | --- | --- | --- |
| 1 | 轮1 实质改 X 无行；账本边界关轮；轮2 rename X→Y 携 Y 行 | pass（逃逸） | **fail**：`impact_chain_gate_missing`，missing path = X |
| 2 | 轮1 实质改 X 携 X 行（锚在轮1 变更行）；轮2 rename X→Y 携 Y 行 | fail（`impact_chain_evidence_missing_file`） | **pass**（行按轮1 head 认可） |
| 3 | 分支上行先于变更、`--no-ff` 合并（first-parent 判别形） | pass | **pass**；去 `--first-parent` 突变体上 **fail**（差分证明承重） |
| 4 | 既有全部 fixture（rename/删除/merge/round-scope 等） | 各自现值 | **不变**（回归护栏；删除 owner 仍 fail-closed） |
| 5 | 瞬态跳：X→Y（携行）；Y 实质变更轮无行；Y→Z（携行） | pass（逃逸；一修候选同样放行，r1 双 lane 各 1×P1 同类命中） | **fail**：missing path = Y |
| 6 | 同 5 但 Y 变更轮携 Y 行（锚在该轮变更行） | — | **pass**（诚实全申报链通过） |
| 7 | 跨轮洗白：A 轮删 X 无行；B 轮重建形似包为 Y 携 Y 行 | pass（cumulative 端点配对读作 rename；二修候选同样放行，r2 review 1×P1） | **fail**：missing path = X（豁免要求某轮自己的 pair 含源名——原子轮内 rename 才豁免） |
| 8 | 已申报 rename 环：A→B（携 B 行）；B→A（携 A 行） | fail（误拒——absent 的 upstream 名被无条件要求，r2 challenge 1×P1；二修候选实测 rc=1 应 0） | **pass**（absent 名仅当本轮 pair 把它改名到**按名可选**后继时抑制要求） |
| 9 | 未申报环：A→B 轮无行；B→A 携 A 行 | — | **fail**：missing path = B；curated→非选集 slug 既有 fixture 语义不变（源名仍是主体） |

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| skill-extraction-workflow | self（闸 owner） | updated | `scripts/impact-chain-gate.rb`、`scripts/test_check_ccl_impact_chain_refscripts.sh` |
| source-register | ledger | updated | impact-chain 行（RED-baseline、firing-path=command:闸脚本） |
| skill-taxonomy-optimization-plan | status doc | updated | 残留表两行结清 |
| product-rd-workflow | upstream coordinator | unchanged | shared-gate 分类/评审按其既有规则执行，无规则变更 |
| testing-strategy | sibling（测试机制） | unchanged | fixture 沿用既有 harness 惯例；差分突变实测是其 mutation 纪律的应用，非新规则 |
| code-review | reviewer lane | unchanged | dual-track 按既有 runbook |
| 其余 lifecycle stage | — | not-applicable | 无产品/设计/发布面 |

## Status-sync 目标与评审门

- status-sync：台账 docs/skill-taxonomy-optimization-plan.md 残留表（43/47 行）随本轮结清；register 行即 impact-chain 机械闸的输入。
- review/challenge：dual-track（独立 review + 对抗 challenge，codex lane 优先），无未处置 P0/P1 方可合 dev。
- **链记录**：chain `gate-round-head-presence-r1`（candidate `432be5ca…`，codex 双 lane，`.review-evidence/gate-round-head-presence-r1/`）：review 1×P1 与 challenge 1×P1 **同类收敛**——瞬态 rename 跳（X→Y→Z 的 Y）逃过以 cumulative 端点为键的加回。**均 accepted，按 smallest_fix 落 lineage 传播 + 三段式 fixture**（判定表 5/6 行；fixture 在一修候选上差分 RED 实测 rc=0 应 1）。chain `gate-round-head-presence-r2`（candidate `d392452a…`，codex 双 lane）：review 1×P1（判定表 7 行，跨轮删+重建洗白）、challenge 1×P1（判定表 8 行，诚实环误拒）——**均 accepted 修复**，各携二修候选上的差分 RED 实测；两修与 curated-escape 既有 fixture 的纠缠按判定表 9 行收敛（selectable 按名判定）。预算记账（诚实披露）：r1 双 lane + r2 双 lane = 4/5 轮，全部 conclusive、发现全部 accepted+修复+差分 RED。余下 1 轮在机制上无法构成终稿的合法评审单元——控制器实测拒绝两种形态（`.review-evidence/gate-round-head-presence-r3/` 留档）：tracked 单 challenge 被 `review_chain_invalid`（challenge index 须紧随同链 review）拒绝；release/shared-gate 的 solo review 被 `invalid_input`（release/high-risk 至少一条 challenge）拒绝。按 exhausted-budget checkpoint 停下后**维护者批加时（2026-08-14，工单回复「跑」）**。
**加时终审（chain `gate-round-head-presence-h1`，candidate sha256 `c3fadabc…`，codex 双 lane）**：review **passed 零发现**；challenge 1×P1——**SKILL.md 同名目录伪装**：`git show ref:path` 对树也成功，故 raw_blob 存在性把「entrypoint 被换成同名目录」读作在场，嵌套文件锚可代为过闸——这是本轮把存在性从 `File.file?` 改为 raw_blob 时**引入的回归**（改前工作树检查会拒目录）。**accepted 修复**：存在性判定三处统一换 `regular_blob_at`（ls-tree 模式，仅 100644/100755 常规 blob 计存在；symlink/子模块/目录一律读作缺席、落回删除 fail-closed），新增 fixture `case-round-scope-skillmd-directory-masquerade`（加时前候选上差分 RED 实测 rc=0 应 1；修复后 77 fixture 全绿）。**无限回归止点**：加时轮修复增量不再另开 Agent 轮，随本记录一并暴露给合并（h1b 先例同构；维护者的加时授权以无未处置 P0/P1 后合并为条件）。至此各链（r1/r2/h1）无未处置 P0/P1。
- 测试层决策表：unit/fixture=run+add（harness 差分 RED→GREEN）；integration=run（check-ccl-skills.sh 全量）；E2E/host smoke=not-applicable（无宿主面）；manual=not-applicable。
