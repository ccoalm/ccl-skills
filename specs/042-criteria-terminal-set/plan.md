# 042 — 判据终态集合重设（039 判据 v4）

Status: **design**（开轮 charter；无技能变更落地，无槽位被触碰）。

**成功判据：本 program 不自判通过。** 它产出一份冻结的判据 v4 及其独立评审记录，随后产出 30 份按 v4 重走的处置。值不值、下一步做什么由用户裁决。

制品分类（`shared-gate-artifact-classification`）：**`gate design`** + **`spec/plan`**。本文件即该分类要求的持久实现计划制品。

---

## 0. 授权与裁决（先于一切，逐字记录）

本轮由用户两条裁决开启，二者均在任何设计文字产出之前给出：

| # | 裁决 | 逐字 |
| --- | --- | --- |
| 1 | 51 行 firing-path 自指的方向 | **「分流：13 修指，38 单独定性」** |
| 2 | 新判据的适用范围 | **「全部 30 槽位按新判据重走」** |

裁决 2 的代价在提出时已标注并被用户确认后仍选定：**「作者改判据后重跑」这条攻击面全开**——039 判据 v3 的全部正当性来自「作者不能在看到结果之后改评判方式」，而本轮恰恰要改评判方式并重跑同一批槽位。因此下列约束不是自述，是本文件的硬条款，违反任一条即本 program 记为 `未完成`：

- **A. 冻结先于重判。** 判据 v4 必须先落盘提交、并跑完独立评审两轮，**才**允许触碰任何一个槽位。提交顺序在 git 历史里可核（照 041 `bfaa4a6` 先于任何一次运行的先例）。
- **B. 一次性。** v4 冻结后，若因重判结果而修改 v4 任一条，本 program 即记为 `未完成` 并记录修改事由；要继续须重新冻结并**全量**重跑，不得只重跑受影响的槽位。
- **C. 判据不由结果反推。** v4 的每一条终态及其证据要求，必须能只由 041 已登记的四个缺陷 + 台账实测导出，不得引用任何一个具体槽位的结果作为理由。
- **D. 分母恒 30，名单不动。** 抽样框、种子、槽位名单一律沿用 039 的冻结结果，不重抽、不增删。重走的是判定，不是抽样。
- **E. 旧结论不追认也不推翻。** 039/041 已登记的处置记录原样保留，v4 下的重判是**并列的第二次判定**，两次结论并存并逐槽位对照，不覆盖历史。

---

## 1. 风险路由（`feature-risk-router` 结论）

| 项 | 内容 |
| --- | --- |
| risk tags | `shared-gate`（承重）。形态上像 docs/spec-only，**按 de-escalation 规则不得降级为 `docs-only`** |
| required gates | owner：`skill-extraction-workflow`（台账 firing-path 词汇与提炼判据）、`product-rd-workflow`（生命周期/闸策略）；`testing-strategy`（v4 若产出可执行判定装置）；dual-track 独立评审（review + 跨家族 challenge）先于共享分支 push 与 MR 合并 |
| skippable gates | `visible-ui`（无渲染面）、`money-quota` / `permission-access` / `api-contract` / `data-migration`（均不触及）。记 `visible surface: no` |
| stop reasons | 已触发并已由用户裁决两项（见第 0 节）。新增的停止线见第 11 节 |
| verification evidence | v4 决策表的逐格实跑轨迹；台账两个探针的可复跑输出；dual-track 两轮记录；`check-ccl-skills.sh` / `impact-chain-gate` / `register-firing-path-resolution.rb` 的原始输出 |

---

## 2. 提炼 charter（`source-to-skill-extraction.md#extraction-charter`，逐格填写）

| Field | 本轮答案 |
| --- | --- |
| **Purpose** | 阻止这样一类未来失败：**判据要求一种证据形态，而真实证据落在它没有的格子里，于是处置永远停在非终态**。041 在一轮内登记了四例同类，全部指向同一个根——`休眠` 要求证明一个否定，而本仓能产出的证据形式只能证肯定。不重设终态集合，后续任何收缩轮都会在同一处再停一次。 |
| **Scope** | **In**：039 判据 v3 的终态集合（`keep` / `superseded` / `休眠` / `收窄` + 非终态 `证据不足`）、`keep(a)` 的 firing-path 条款、`references/source-register.md` 的 firing-path 词汇与其解析装置。**Out**：抽样框/种子/槽位名单（第 0 节 D）、039 与 041 已落盘的处置文本（第 0 节 E）、`references/` 字节闸、写操作四值模型（`ADD/REINFORCE/SUPERSEDE/NOOP`，039 明列为处置之后的事）。**Sibling 边界**：`code-review` 只作为独立评审通道被调用，不是本轮的落地目标。`covered-through` 水位：039 的 30 槽位处置 + 041 的四缺陷登记，本轮覆盖其上的「终态集合本身」这一层。 |
| **Depth** | **Full workflow extraction**。改的是承重判据的规则/范围/完成语义，且要重走 30 个槽位。 |
| **Root cause** | v3 把终态集合当成**先验完备**的枚举——四个终态是从「留 / 换 / 睡 / 窄」这个直觉四分法写下来的，从未对着真实证据形态检验过一次。于是遇到「A、B 各自充分、联合必要」这种矩阵时无格可落；遇到散文规则时 `keep(a)` 的「自指不算」把主流写法整片判成无 firing point。判据的**终态集合**从来没有被要求覆盖它要判的证据空间。 |
| **RCA analysis** | 见第 3 节（Deep RCA 五步，多因子表）。 |
| **Failure mode analysis** | 弱提炼的三种坏结局：**(i) 补丁式**——只给对称冗余加一格，`休眠` 的三个缺陷原样留着，下一轮第五次同类复现；**(ii) 放宽式**——把 `keep(a)` 放宽到「agent 读到就算 firing」，判据从此不再能否定任何一行，039「拿得出落地后生效证据」这条承重条款被掏空，收缩轮变成橡皮图章；**(iii) 自我豁免式**——v4 的正当性依据里有一条（台账 `:112`「loosening 必须过双向 operability check」）**自己就是那 38 行纯散文自指行之一**，若 v4 判定该类行无 firing point，v4 的依据就被 v4 自己废掉。三种都要在设计期显式挡掉。 |
| **Lifecycle impact** | 产品意图：无。设计/UX：无。实现：无代码改动（除非 v4 产出判定装置）。调试：无。**测试**：v4 若产出判定装置须有 RED-first 与失败路径断言（041 方法学补记 2 明写「测量脚本本身没过任何闸」）。**发布验收**：无。**迭代反馈**：承重——本轮结论决定后续收缩轮能否终态化。**团队上手**：承重——台账 firing-path 是每条新规则都要填的字段。**无源访问的使用**：承重——判据须能被一个没读过 039/041 的 agent 照着判。 |
| **Evidence plan** | 源类按证据地位排序：**(1) 本轮之前已产出的制品**——041 的 `dispositions.md`、`d2_strict.py` / `d2b_probe.py` / `d1_widened_scan.sh` 及其原始输出，039 的 `plan.md` / `dispositions.md`（**假设级，见第 5 节**）；**(2) 台账当前状态**——`references/source-register.md` 全 186 行的 firing-path 实测（本轮已跑，见第 5 节顺序声明）；**(3) 现存解析装置**——`scripts/register-firing-path-resolution.rb`、`scripts/impact-chain-gate.rb`、`scripts/check-ccl-skills.sh` 的当前行为（一手，须实跑）；**(4) 本仓自有的元规则**——`dual-track-review-gate.md` 的 design-time operability 四腿（尤其 leg (e) loosening）、`SKILL.md` 的同类复现→问该不该存在、cross-landing sibling 的「谓词改挂自己拥有的不变量」；**(5) 外部一手源**——仅在 v4 引入任何声称代表业界实践的判定形态时才需要，否则逐条记 `not-applicable: 内部判据、不作 state-of-the-art 主张`。**产出制品类不适用声明**：本轮开轮时尚未产出任何制品，故 (1) 取的是**被本轮实现的那个前置轮（041）**的产出，非本会话产出。 |
| **Completion standard** | 冻结阶段：v4 决策表每一格有至少一条 planned 输入行；dual-track 两轮记录在案且无未处置 P0/P1；`check-ccl-skills.sh` 与 routing gate 绿。重判阶段：30 槽位各有 v4 下的裁定 + 与 039 结论的逐槽位对照 + 终态绑定动作执行完毕或明确记 `未执行及理由`。**任一阶段的任一必需行缺失即 `interim`，不得报 complete。** |

---

## 3. RCA

### 3.1 Baseline RCA

| 问题 | 答案 |
| --- | --- |
| Future failure | 下一轮收缩/退役工作再次跑完全部测量，结论仍是「探针合格、结果有效、判据无格可落」，九个槽位继续悬着，且第五个同类缺陷被登记。 |
| Enabling cause | 见 3.2 多因子表（不是单因）。 |
| Prevention mechanism | 判据的终态集合必须由**它要判的证据空间**导出并被检验覆盖，而不是从直觉四分法写下；且每个终态的证据要求必须是**可正面产出的**形态。 |
| Owning layer | `skill-extraction-workflow`（判据与台账词汇），`product-rd-workflow`（闸设计的 operability 与评审闸）。 |
| Proof | 拿 041 已实测的四种证据形态（对称冗余矩阵、零命中不可满足、通道只出 findings、开放集全称否定）逐个喂给 v4，每一种都必须落进恰好一个格子。 |

### 3.2 Deep RCA（五步；多因子表）

**move 1 广度枚举**（先广后深）——列在下表，横跨六类。
**move 2 主动失效 vs 潜在条件**——可见的主动失效是「041 起草方按 v3 判不出终态」；潜在条件全部在 039 写判据那一刻就埋下了。
**move 3 local rationality**——039 写下四个终态时，能看到的是「留/换/睡/窄」覆盖了它当时想到的全部处置动作；它检验的是**动作**是否穷尽，不是**证据形态**是否穷尽。在那个视角下四分法看起来是完备的。**不写「039 当时应该想到对称冗余」——那是后见之明。**
**move 4 反事实排序**——见表内列。
**move 5 控制点**——见表内列；每条须过 firing-path proof（触发器 + 下一个 agent 真正会到达的表面）。

| 贡献因子（类别） | 主/潜 | local rationality | 反事实 | 控制（约束 + 确认反馈 + firing path） | Owner | 验证 |
| --- | --- | --- | --- | --- | --- | --- |
| **终态集合从动作四分法导出，未对证据空间做覆盖检验**（缺失控制） | 潜 | 四个动作确实穷尽了「能对一条规则做什么」；证据形态是另一个维度，当时未被识别为维度 | **必要**：移除它（即当初做过覆盖检验）则四个缺陷全不成立 | v4 的冻结形态必须是**决策表**：输入维度 × 裁定，每格至少一条 planned 输入行；空格即设计未完成。firing path：本文件第 7 节 + closeout 逐格对照 | `skill-extraction-workflow` | 第 7 节表的空格计数 = 0 |
| **`休眠` 的判据要求证明一个否定**（缺失控制 / 潜在条件） | 潜 | 「没有触发证据」是一个自然语言上完全通顺的状态描述，它的不可判定性只有在试图机械化时才显形 | **必要**：四个缺陷里三个（#1 #2 #4）直接由它生出 | 本仓自有规则已给出解法形态——cross-landing sibling：**谓词改挂控制自己拥有的不变量**。台账的 firing-path 字段是本仓自己拥有并已有解析装置（`register-firing-path-resolution.rb`，187 定位符）的对象。firing path：v4 决策表 + 该脚本 | `skill-extraction-workflow` | v4 每个终态的证据要求逐条标注「正面可产出 / 需证否」，后者计数 = 0 |
| **`keep(a)` 的「引用自身文本不算」未对台账实际写法做过计数**（process model / 知识） | 潜 | 「firing point 要在目标文本之外」在概念上无可指摘；台账 27.4% 的行是自指写法这个事实此前从未被测过 | **必要**：移除它（即当初测过）则 v3 会当场发现该条款判掉四分之一强的行 | 任何对 `keep`/firing-path 判据的改动，落地前须对**全台账**跑一次分布实测并把数写进判据文本旁。firing path：v4 冻结前的必跑项（第 9 节） | `skill-extraction-workflow` | 两个探针的原始输出进树 |
| **测量装置本身不过任何闸**（缺失控制 / 检测缺口） | 潜 | 探针是一次性脚本，直觉上不是「产品代码」；但它产出的数被用来改台账行终态 | **次级控制（保留）**：不是四个缺陷的成因，但它是本该拦住「0/5 其实是超时」这类假数的那层，041 已实证它当时是空的 | v4 若产出判定装置：RED-first + 失败路径断言 + 对照腿，按 `testing-strategy`。firing path：第 9 节测试层决策表 | `testing-strategy` | RED-baseline 行 |
| **本仓无「判据自身也要过 operability check」的触发点**（触发/路由） | 潜 | operability 四腿写在 `dual-track-review-gate.md`，触发词是「新的机械闸/校验器/证据装置」；一份**散文判据**是否算「机械闸」当时没有判例 | **概率级（单迹）**：只有本轮一次观察。标为 `probabilistic`，不据此单独立规则，作为候选留档 | 暂不立规则；在 v4 落地时如实记录「本轮把散文判据当作受 operability 管辖的对象」这一先例，供第二次观察时确认或推翻 | `skill-extraction-workflow` | 本文件第 6 节的显式声明 |

**second-harvest check**：本轮的「谓词改挂自己拥有的不变量」映射到 `docs/skills-theory-foundations.md` 已认出的理论行时，须按该文件〔认出或借来之后〕节做一次有界读，产出三种之一（候选规则 / `no-new-lesson` 且点名既有规则 / 证据支持的 `discarded`）。**本轮开轮时未做，登记为待办，在 v4 冻结前完成。**

---

## 4. 目标产出映射（编辑前建立）

| Target | Owner role | Expected decision | Source mechanism | Actual diff or reason |
| --- | --- | --- | --- | --- |
| `specs/042-criteria-terminal-set/plan.md` | 本轮 charter 与判据 v4 的持久制品 | `updated` | 全部 | 本文件 |
| `skills/skill-extraction-workflow/references/source-register.md` | 台账；firing-path 词汇与 impact-chain 行 | `pending` | 51 行自指实测；13/38 分流 | 冻结阶段只加本轮的 impact-chain 行；13 行改指属重判阶段 |
| `skills/skill-extraction-workflow/SKILL.md` | 提炼判据与 firing-path 语义的 owner | `pending` | v4 的 firing-path 条款若改变台账填写要求 | 由 v4 定稿决定；若不改须记 `unchanged` 及理由 |
| `skills/skill-extraction-workflow/references/dual-track-review-gate.md` | operability 四腿；散文判据是否受其管辖 | `pending` | RCA 第 5 因子（probabilistic） | 单迹，默认 `unchanged`；只登记先例 |
| `skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb` | firing-path 解析装置（现有，187 定位符） | `pending` | v4 若把「定位符解析到自身文本」做成可判定信号 | 属 `gate implementation`，须 RED-first |
| `skills/product-rd-workflow/SKILL.md` + `references/shared-gate-artifact-classification.md` | 闸设计/评审闸的生命周期 owner | `pending` | 「判据本身是否受 operability check 管辖」 | 默认 `unchanged`（单迹）；若 v4 落成通用规则则回到此处 |
| `skills/testing-strategy/SKILL.md` | 判定装置的测试层与 RED-first | `pending` | v4 若产出可执行判定装置 | 无装置则 `not-applicable: 无可执行制品` |
| `skills/code-review/*` | 独立评审通道（执行者，非落地目标） | `unchanged` | —— | 只被调用，不被修改 |
| `specs/039-design-first-shrink/*`、`specs/041-039-debt-repayment/*` | 历史处置记录 | `unchanged` | 第 0 节 E | 不追认不推翻，原样保留 |
| 外部/系统技能（`superpowers:*` / `gstack-*` / `context-mode` 等） | —— | `not-applicable` | 本轮判据是本仓自有的收缩判据，无外部 owner | 可编辑性分类：reference-only，非落地目标 |

**sibling-generalization mini-map**：本轮不是 stack-specific 提炼（判据不属于任何技术栈），无 sibling stack。记 `not-applicable: 非栈特定`。

**provenance-to-target diff** 在 v4 定稿时补齐（冻结阶段每条 `pending` 均阻断 complete 声明）。

---

## 5. 输入的证据地位：041 的四个缺陷是**假设级源类**，不是工作说明书

按 `source-to-skill-extraction.md`「A deferred registration is a hypothesis source class, not a finding」——本轮的活正是实现前一轮针对**本仓自有机制**登记的欠账，故该规则整条适用：

- 041 登记的四个缺陷记录了两样东西，**两样都会衰减**：机制当时的行为、以及对着当时代码看起来对的补法。衰减是默认预期而非已观测事实——本轮 base 就是 041 的合并点 `9c11837`，台账含 `firing-path` 的行仍是 186，与 041 报数一致；但 `worktree-040` 在飞且会追加台账行，`register-firing-path-resolution.rb` 等装置也可能已被无关轮次改过。**复现要求不因「看起来没动」而豁免**：没跑过就是没验过。
- **每个形态必须对当前 baseline 复现，且每个探针配一条对照腿**（探针自身形态、把被测特征去掉后跑一次）。没有对照腿，因 fixture 缺陷而红的探针会被读成「形态复现」，反之亦然——041 自己在一次坐下里两个方向都撞到过。
- **不再复现的形态记 `closed`，不是 `fixed`**：保留探针作回归守卫，不为它写代码。
- **登记的补法一律重新导出**，不得照抄。四的计数不是活缺陷的计数。

**顺序声明**：下表的台账实测（51/186 分布、13/38 分流）跑在 charter 落盘**之前**——它是回答用户裁决 1「方向未定」所需的决策支撑，先于本轮存在。故其证据地位是**假设级前置测量**：冻结阶段须按上述对照腿要求重跑并把原始输出进树，重跑数与预跑数不一致以重跑为准并记录差异。预跑不算已验证证据。

**当前（dev @ `9c11837`）预跑读数，待复验**：

| 分类 | 行数 | 说明 |
| --- | --- | --- |
| 含 `firing-path` 的台账行 | 186 | 与 041 报数一致 |
| `command:` 定位符（指向可执行体） | 113 | `keep(a)` 已把「闸脚本」列为合法 firing point，机械化不影响 |
| `file:` 非自指 | 22 | 不受影响 |
| `file:` 全自指 | **51** | 041 的 D2-宽口径，逐位复现 |
| ├ 其中 Evidence 含可执行制品（`.sh`/`.py`/`.rb`） | **13** | 例：`:53` firing-path 指 `SKILL.md#…`，同行 Evidence 写明回退 hook token 会让 `hooks/test_guard_delegation_owner.sh` 转红——**执行体存在，只是定位符没指它** |
| └ 其中 Evidence 仅 `.md` | **38** | 例：`:112`、`:119`、`:271`。纯散文条款，无可改指的对象 |

---

## 6. 本轮的设计约束

下列四条约束在 v4 定稿前即生效，任何候选设计违反其一即出局。它们全部由本仓自有规则或 041 实测导出，不引用任何槽位结果（第 0 节 C）。

1. **leg (e) loosening check——本轮的主约束。** v4 相对 v3 在多处让判据「接受它原先拒绝的东西」（新增终态、放宽 firing-path），属 loosening；loosening 比 tightening 更难做对且不产生红。该腿的两条义务：**(i)** 用行为语言陈述被豁免的类，并对照本仓自己对该类的定义——若树里已有规则把同一种 diff 形态判为「有行为」，豁免即自相矛盾，正解是**修证据形态**而不是丢证据；**(ii)** 若该类确实带行为，豁免必须被**「给出供给证据的路径」**替代（放宽锚点可落之处、增加该形态能满足的证据形式）。
   - 直接后果 1：用户裁定的「13 行改指可执行体」**正是 (ii) 规定的修法形态**——放宽锚点可落之处，而非豁免。方向与本仓规则同向。
   - 直接后果 2：「把 `keep(a)` 放宽成 agent 读到就算 firing」是 (i) 明令禁止的形态——38 行是**带行为最多**的那一类，豁免对它伤害最大。故 38 行的处置必须走**供给路径**（给出这类行能满足的证据形式），不得走豁免。
2. **同类复现 → 问该不该存在，而不是再补一格。** 041 在一轮内登记四例同类，全部同根。按本仓规则，正确的问法是 **`休眠` 这个终态该不该存在**，而不是给它换第五种判法。删除式收敛（convergence-by-deletion）在此是首选候选，须以 `keep / delete / narrow / replace` 显式记录，附同类证据（轮次与发现）、它服务的真实需求、更安全的替代、以及爆炸半径。
3. **bootstrap 自指不得自我豁免。** v4 的正当性依据之一是台账 `:112`（「loosening 必须过双向 operability check」），而 `:112` **自己就在那 38 行纯散文自指行里**。若 v4 判定该类行无 firing point，则 v4 是踩着自己要废掉的规则站起来的。039 `plan.md:292` 已明写「不得自我豁免」。处置：v4 必须能对 `:112` 这一条给出**它自己的**判定，且该判定不得依赖「本轮除外」。
4. **承重假设（标为 hypothesis，不预设结论）。** 由约束 2 的 cross-landing sibling 形态导出的最强候选是：**把谓词从「是否存在任何东西执行这条规则」（开放集全称否定）改挂到「这一行是否声明了一个能解析、且解析到某个会执行/取用它的对象的 firing point」（封闭、可判定、且本仓自己拥有并已有解析装置）**。它同时覆盖两个 item：51 行正是「声明的 firing point 解析不到任何会执行它的对象」的那批。**这是假设不是结论**——按 evidence-first，它必须先被四种已实测证据形态与全台账分布检验，通过才写进 v4；不通过就换。

---

## 7. 验收矩阵（planned decision table；closeout 换成实跑轨迹）

`shared-gate-artifact-classification` 要求：发出裁定的闸，其验收矩阵必须是**输入→单一裁定**的决策表，每个裁定至少一条 planned 输入行。下表是 v4 的**候选骨架**，冻结阶段逐格填实并接受独立评审；**任何一格没有 planned 输入行 = 设计未完成**（第 3.2 表第一因子的控制点）。

| # | 候选裁定 | 输入（须可正面产出） | planned 输入行（来自 041 实测的四种形态之一或台账分布） | 绑定动作 |
| --- | --- | --- | --- | --- |
| 1 | `keep` | 声明的 firing point 解析到一个**会执行/取用该规则的对象**（≠该行自身文本）**且**有可核验因果制品 | 113 条 `command:` 行的任一条 | 不改动 |
| 2 | **`联合承重`**（新，对称冗余那一格） | 单删各臂不红、联删红——A 与 B 各自充分、各自不必要、联合必要 | 041 批 2：控制 5/5、删A 5/5、删B 5/5、删A+B 0/5 | 待定：不得默认落到「删一条」（该方向对起草方有利，041 已记） |
| 3 | `superseded` | 零损失义务表可填满且无 `intentionally-dropped` 行 | 待补：须从台账找一条真实候选，找不到则该格标 `无 planned 输入行` 并记录 |  规则离开取用路径 |
| 4 | `收窄` | 至少一个可判定断言：按当前措辞会触发、但触发是错的 | 待补，同上 | 实施作用域编辑 |
| 5 | **替代 `休眠` 的那一格**（名称待定） | **正面可判定**：该行未声明 firing point / 声明的定位符不解析 / 解析到该行自身文本；**且已先走过修复路径而失败** | 38 行纯散文自指行的任一条（例 `:112` —— 须能判自己，见约束 3） | 待定 |
| 6 | `修指`（非终态，前置修复步） | 定位符自指，**但**同行 Evidence 已含可执行制品 | 13 行的任一条（例 `:53` → `hooks/test_guard_delegation_owner.sh`） | 改指后回到 #1 重判 |
| 7 | `证据不足`（非终态） | 上述任一格的输入拿不到 | —— | 阻断，不绑定动作 |

**排序义务**：#6 必须先于 #5 判——leg (e)(ii) 要求先给供给路径再谈豁免。一行在没跑过 #6 之前不得落 #5。

**覆盖检验（冻结前必跑）**：把 041 实测的四种证据形态逐个喂进上表，每种必须落进**恰好一个**格子。落进零个 = 集合仍不完备；落进两个 = 判据有歧义。两者都是设计未完成。

---

## 8. 交付顺序（两阶段，不可交叉）

**阶段 A — 冻结判据 v4**（本轮当前所处阶段）
1. 复验第 5 节两个探针（配对照腿），原始输出进树。
2. 对 041 四缺陷逐个做当前-baseline 复现 + 对照腿；不复现的记 `closed`。
3. 完成 second-harvest check（第 3.2 节末待办）。
4. 填实第 7 节决策表，跑覆盖检验。
5. 记录 `keep / delete / narrow / replace` 对 `休眠` 的显式裁决（约束 2）。
6. dual-track：独立 review + 跨家族 challenge；处置全部 P0/P1。
7. **v4 落盘提交**——这一次提交的 SHA 是阶段 B 的准入凭证（约束 A）。

**阶段 B — 30 槽位按 v4 重走**
8. 逐槽位重判，与 039 结论并列对照，不覆盖历史（约束 E）。
9. 终态绑定动作执行；13 行改指在此阶段落地。
10. closeout：diff 对照第 4 节映射、provenance-to-target 补齐、台账 impact-chain 行、R0、`check-ccl-skills.sh`。

**阶段 A 未完成前不得触碰任何槽位**（约束 A）。

---

## 9. 测试与台账覆盖

| 层 | 决策 | 命令 / 证据 | 理由 |
| --- | --- | --- | --- |
| unit | `add`（条件） | 仅当 v4 产出可执行判定装置时；须 RED-first + 失败路径断言 + 对照腿 | 041 方法学补记 2：测量装置本身没过任何闸，而它产出的数改了终态 |
| integration/contract | `run` | `scripts/register-firing-path-resolution.rb`、`scripts/impact-chain-gate.rb` | v4 若改 firing-path 语义，这两个装置的行为必须同步且可核 |
| E2E / host smoke | `not applicable` | —— | 无运行时产品面 |
| manual/exploratory | `run` | 第 7 节覆盖检验（四形态逐个喂表） | 这是判据完备性的唯一检验方式 |
| build/static | `run` | `scripts/check-ccl-skills.sh`、`make eval-routing` | 共享技能改动的既有闸 |
| independent review | `run` | dual-track 两轮，跨家族 challenge | 共享闸非 wording 改动的强制项 |

**台账覆盖**：本轮属 upstream-owner 改动，closeout 须在 `references/source-register.md` 追加 impact-chain 行（`upstream rule | downstream owner | expected executable behavior | status | evidence`），带 `behavioral-evidence` / `observed-failure` / `firing-path` 字段。**注意自指**：本轮追加的行自己也要满足 v4 的 firing-path 要求，不得自我豁免（约束 3）。按 `source-register.md` 的 Round-consolidation 规则，本轮台账行**单次追加**，不逐 commit 追加。

**status-sync target**：本文件即状态源；`docs/skill-taxonomy-optimization-plan.md` 若被 v4 影响则同批更新，否则记 `unchanged`。

---

## 10. 评审 / 挑战闸

- **dual-track 强制**：本轮是共享闸的非 wording 改动 → 独立 review + 对抗 challenge 两轨齐跑，challenge 用跨家族客户端（codex）。
- **预算**：Agent 自主预算 = initial + ≤4 challenges = 5 轮。候选一变即全量重跑（本仓规则）。**预算耗尽仍出新 P1 → 停在 exhausted-budget checkpoint 待用户裁决，不自行续轮**（`dual-track-review-gate` 的 scope-bound continuation_authorization）。
- **findings 分类先于修**：mechanical finding 进修复清单；**design-level finding**（质疑机制该不该存在、成本、trust-model、或把范围推进显式 deferred 的关切）是**风险 owner 决策项**，在投入加固轮之前先把 `keep / delete / narrow / replace` 摆给用户。
- **自审先于外审**：`self_review_gate` 在外审前、findings/候选/范围变更后、预算耗尽 checkpoint、以及任何 completion 声明前机械触发。

---

## 11. 停止线与不做什么

- **不做**：不给 `references/` 加字节闸（039 已判定只会再位移一次）；不造写操作四值模型（039 明列为处置之后的事）；不重抽样、不改分母、不动槽位名单；不追改 039/041 已落盘的处置文本。
- **停止线**：出现下列任一即停下交裁决，不自行推进——(a) 覆盖检验显示 v4 仍有格子接不住已实测的证据形态；(b) 约束 3 的自指判定做不出来（v4 判不了 `:112` 自己）；(c) 评审预算耗尽仍有未处置 P1；(d) 阶段 B 中发现 v4 需要修改（触发约束 B，本 program 记 `未完成`）。
- **交付物**（照文首的不自判通过条款）：一份冻结判据、一份独立评审记录、30 份重判处置及其 diff。

---

## 附：与在飞轮次的关系

`worktree-040-review-suite-process-leak` 独立在飞（`specs/040-review-suite-process-leak/`），与本轮无重叠面，除二者都会追加 `source-register.md` 行——集成时按栈式 PR 规则用 **rebase 不用 merge**。本轮 base = `origin/dev` @ `9c11837`。
