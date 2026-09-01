# 084 — 抽取 lane 的第三轮评审：绑定落地候选的对抗轮

Owner 集合：`skill-extraction-workflow`（闸文本、wrapper、closeout validator）+ `code-review`（链契约、controller）。
风险 tags：`shared-gate`（主）、`release-ops`、`api-contract`。`visible-ui` not-applicable（`visible surface: no`）。
`security-review`: not-applicable — security posture unchanged（不触碰信任边界、不可信输入面、敏感 sink、凭据或数据可见性；被放宽的是 agent 自授权的流程预算，人工 `continuation_authorization` 逃生阀与 reviewer 只读/有界 packet 姿态均不变）。

## Extraction Charter

| Field | Answer |
| --- | --- |
| Purpose | 防止两类漂移：(a) 闸文档承载**不可达的义务**——`dual-track-review-gate.md:616` 要求「fix 之后至少再 challenge 一次」，而 `:610` 的 cadence 加 hold-fixes 规则使其在 1+1 下永远无法执行；(b) 修复批**走出闸的管辖范围**后，唯一兜底是人工 MR 评审，而同一份文档 `:644` 明写「Human PR review without an explicit challenge framing」不算 dual-track——即依赖了一条被自己判定为不算数的 lane。 |
| Scope | In：`skill-extraction-workflow`（`references/dual-track-review-gate.md`、`scripts/extraction_review_gate.sh`、`scripts/validate_extraction_review_state.py`、两套回归、`references/source-register.md` 影响链行）、`code-review`（`references/staged-review-contract.md`、`scripts/review_gate.py`、链回归）。Out：generic transport 的 0..4 轮上限（不动）、人工 `continuation_authorization` 的授权语义（不动）、wording-only 单评审通道（不动）、reviewer 客户端路由与 egress（不动）。无 `covered-through` 水位线（非迭代式 program 源）。 |
| Depth | Generator/tooling change + full workflow extraction：改的是确定性闸的判定语义与其可执行实现，不是措辞。 |
| Result classification | **failure/correction**。支撑观察：`:616` 与 `:610` 在同一份文件里互相否定，且 `:616` 的执行前提（fix 后候选进入一轮外部评审）在现行 wrapper 固定预算下不可满足；`validate_extraction_review_state.py:389-394` 进一步证实 fix 后账本无法收尾——不是"漏检"，是修复批整体离开闸。 |
| Matching analysis | 见下节 RCA。 |
| Failure mode | 弱提炼会走两条歧路：① 直接删掉 `:616` ——矛盾消失、洞永久化且不再可见；② 直接把 `WRAPPER_CHALLENGE_BUDGET` 抬到 2 ——仓内 14 份历史收据（记 `challenge_budget=1`）集体失效，且对没有任何 fix 的轮也强收一轮最贵的 challenge。 |
| Lifecycle impact | 实现（wrapper/controller/validator）、测试（三套回归 + 历史语料复验）、评审闸（本闸自身）、团队 onboarding（读 cadence 的下一个 agent）、无源访问使用（消费收据的 CI 校验）。产品意图/设计 UX：not-applicable（无人机可见面）。 |
| Evidence plan | **第一源类＝既产工件**：`specs/*/evidence/review/**` 下 14 份历史收据（枚举命令 `find specs -path "*/review/*" -name "*.json"`），已按链读取 `challenge_budget` / `autonomous_review_index` / findings 数。第二：代码语料——`review_gate.py` 链校验段（2930–3075）、`validate_extraction_review_state.py` 预算与候选绑定段、`extraction_review_gate.sh` 全文（22 行）。第三：闸文本 `dual-track-review-gate.md`（:509–:660）。第四：`source-register.md` 行 464/465（本预算的既有裁决与其后加固）。外部权威源：not-applicable —— 本轮不作任何 state-of-the-art 主张，编码的是仓内运行约束。 |
| Completion standard | 每层 RED-first 证据（含对保护性谓词的**已施加** mutation 及右因归因）；14 份历史收据在新 validator 下仍全部合法；本轮自身过 dual-track（按**旧的** 1+1 规则，新规则尚未落地）；impact-chain 闸带 `CCL_SKILL_BASE_REF` 通过；回归注册自审通过；CI 全 lane 绿。 |

## RCA（加宽后再排因果权重）

贡献因子（跨类别枚举，不是单链）：

1. **触发/路由**：预算 1+1 由 068 轮定（反发散），hold-fixes 由 077 轮显式化，两轮都没有回读 anti-pattern 清单，`:616` 作为 0..4 轮时代的化石存活下来。
2. **过时的过程模型**：cadence 的"fix → re-challenge"写于预算是 `0..4` 的时期，预算收窄时未同步。
3. **缺失的机械控制**：没有任何检查断言"实际落地的对象＝账本收尾的候选"。validator 内部一致性很强（每轮受计收据都绑账本候选），但账本候选由调用方提供，与合并对象之间没有绑定。
4. **缺失的反馈**：收尾按 lane 名与轮次报告，不按候选身份报告，所以修复批离开闸这件事从不显红。
5. **更早埋下的潜伏条件**：`WRAPPER_CHALLENGE_BUDGET` 旁的注释写着"future budget change lands in exactly one place"——设计预期了预算会变，但预期的是**换一个常数**，没预期"按候选是否改变而条件性生效"。
6. **检测缺口**：收据本来就记 `candidate_sha256`，这个洞一直是机器可判的，只是没人问这个问题。

反事实排序：

- 移除因子 3（即：存在候选覆盖断言）→ 失败不发生。**必要因子，因果权重最高。**
- 移除因子 1/2（即：`:616` 从未成为化石）→ 洞依然存在，只是不再有人注意到。所以化石条款是**检测资产**，不是原因——它是唯一让这个洞被看见的东西。这条纠正了直觉排序：最刺眼的症状不是根因。
- 因子 4 是**失效的次级控制**（defence-in-depth），保留为次要控制，不丢弃。
- 因子 5、6 是单迹象假设，标为概率性，不进本轮可执行改动。

机械控制（落在失败**类**上，不是这一个实例）：把"落地候选必须被某一轮对抗评审绑定"变成 closeout validator 的一条断言，并同时提供使其**可满足**的机制（链继承）——只加断言不加机制等于把闸变成死锁。

## Owner-generalization / target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| `skill-extraction-workflow` | 本体 | updated | `references/dual-track-review-gate.md`、`scripts/extraction_review_gate.sh`、`scripts/validate_extraction_review_state.py`、`scripts/test_extraction_review_gate.sh`、`scripts/test_validate_extraction_review_state.sh`、`references/source-register.md` |
| `code-review` | sibling（链契约拥有者） | updated | `references/staged-review-contract.md`、`scripts/review_gate.py`、新增 `scripts/test_review_chain_succession.sh` |
| `testing-strategy` | upstream（测试层策略） | unchanged | 本轮不新增测试层策略；沿用既有 bash+python 回归层与 mutation 证据规则，无新层选择规则可落 |
| `product-rd-workflow` | upstream（生命周期闸） | unchanged | shared-gate 分类与独立评审要求已覆盖本轮形态，无新增 lifecycle 规则；本轮按其 shared-gate 分类执行 |
| `feature-risk-router` | upstream（风险分类） | unchanged | `shared-gate` tag 与其 gate 集合已覆盖，无新 tag |
| `worktree-isolation` | sibling | not-applicable | 仅消费其 Step 0，无机制变更 |
| `defect-diagnosis` | sibling | not-applicable | 非单缺陷诊断轮 |
| 外部安装包（`superpowers:*` / `gstack-*`） | external | not-applicable | 本闸是 CCL 自有的抽取 lane 契约，外部包不拥有其收据 schema 或链语义 |

## 设计裁决

### D1 — 触发谓词用候选哈希差，不用 disposition 标签

第三轮的触发条件是：**落地候选的 `candidate_sha256` ≠ 阶段一终轮 challenge 所绑定的候选哈希**。

不用"本轮有 P0/P1 被处置为 fixed"，理由是闸文档 `:540` 自己的规则：分类动词若没有一个能产出该分类的具名测试，就是自裁决条款；而 disposition 标签正是作者自填的。候选哈希是控制自己拥有的不变量——改标签没用，改字节才算，且它恰好就是我们真正关心的性质（落地的那个对象被对抗轮看过）。

顺带得到"效率"那一半：候选未变（所有发现都是 accepted / pre-existing / source_refuted）→ 第三轮不触发，仍是 1+1，零额外成本。

### D2 — per-chain 预算保持 1，第三轮走第二条链（两阶段账本）

强制约束（读代码得出，不是推测）：`review_gate.py:2995` 要求同一条链内每轮的 `challenge_budget` 一致，且它参与 `review_scope_sha256`。**预算必须在 round 1 之前定死，不能中途追加**——否则改 scope 摘要、当场断链。因此"条件性预算"不可能实现为"先 1 后 2"。

可行形态：

- 阶段一：链 C1，`challenge_budget=1`，round 1 review + round 2 challenge，绑候选 A。**收据形状与今天逐字节相同，14 份历史收据继续合法。**
- 阶段二（仅当 D1 触发）：链 C2，`challenge_budget=1`，round 1 直接是 **challenge**，绑候选 B（= A + 整批 fix），携带指向 C1 终轮收据的继承指针。

走第二条链不是妥协，是机制的实然形态：fix 只要触碰 owner 包的 `SKILL.md` 或 `references/**.md`，`_stable_binding_matches`（`review_gate.py:3003`）就判 `review_chain_invalid`，链本来就断。

（附带修正一条长期误读：候选变化**本身**不断链——`review_gate.py:3060` 附近只把它记为 `material_candidate_change` 自审触发器，不 raise。断链的是 owner 包摘要，而该摘要不含 `scripts/`，所以修复若只落在脚本/测试上，同链内即可续跑。）

### D3 — `code-review`：链继承指针

`review_gate.py` 放开 `mode == "challenge" && autonomous_review_index == 1`，条件是提供 `--predecessor-chain-result-file`，且该收据通过全部校验：

- `schema_version == 3`、`status ∈ {passed, findings}`、`review_chain_tracked is True`；
- 是其所属链的终轮（`autonomous_review_index == challenge_budget + 1`）；
- 其 `review_scope` 除 `selected_skills_sha256` 外与当前一致——owner 包摘要的移动正是被修复这一事实本身，其余 scope 字段（stage / depth / risk_tags / budget）任一不一致即拒；
- 其 `candidate_sha256` **≠** 当前 packet hash。候选相同的"继承"不是继承，是重复轮，拒绝——这条堵住把继承机制当额外预算刷的路径；
- `prior_challenge_focuses` 从前一条链带过来，阶段二的 focus 必须与阶段一的所有 focus 相异。

新收据字段：`predecessor_chain_id`、`predecessor_result_sha256`、`predecessor_candidate_sha256`。

### D4 — wrapper：不改（原裁决已作废）

初稿写的是"wrapper 放行继承参数并拒绝第三条链"。读源后作废：`extraction_review_gate.sh` 全文 22 行，只有一条 `--challenge-b*` 拒绝循环，**没有参数白名单**，继承指针参数天然透传；而"拒绝第三条链"它也执行不了——它是无状态 exec 包装，跨轮状态不在它手里。lane 上限（**≤2 条链、≤3 轮**）全部落在 closeout validator。wrapper 本轮零改动。

### D7 — 合并面执行力（本轮的承重半）

实测事实：`.github/workflows/` 与 `check-ccl-skills.sh` 对 `extraction_review_state` / closeout / receipt / review_chain 的引用数为 **0**。评审账本今天完全没有合并时的执行力——validator 由 agent 自愿跑，账本候选由 agent 自填，CI 全程不看。因此**只加第三轮不改变任何机械结果**：那只是给文档加一条义务。按本仓提炼纪律（规则存在但不触发＝验证闸缺陷，必须落触发机制），本轮必须同时落执行面。

新增闸：non-wording 的 `skills/**` 改动，必须携带一份绑定**本次落地候选**的合法 closeout 账本。

自指问题及其解：账本若被计入候选，则"含账本的树"的哈希永远无法被账本自己记录。解法是把候选钉在 `skills/` 上——

- controller 侧：终轮以 `--base <merge-base> --paths skills` 冻结 packet（`freeze_packet` 的 `--base` 分支即 `git diff <base> -- skills`）；
- 账本与证据写在 `specs/<round>/evidence/` 下，**不在候选内**，提交它不扰动 packet hash；
- CI 侧：在干净检出上复算 `git diff <base> -- skills` 的 SHA-256，要求等于账本 `candidate_sha256`，并调用 validator 校验账本本身。

推论（可执行纪律，不是建议）：终轮必须在**已提交的干净树**上跑——工作区脏则 packet 含未提交状态，CI 复算必不相等。这正好是"被评审的对象＝落地的对象"的机械形态。

边界（不假装收窄）：`--diff-file` 自组包的账本无法被 CI 复算，按声明拒绝而非默默放行；omitted history、账本伪造仍是 caller-owned，与今天相同。

### D5 — closeout validator（schema v4，v3 收据向后兼容）

`WRAPPER_CHALLENGE_BUDGET = 1` 不动 → 历史收据零改动继续合法。新增两个模块常量 `LANE_MAX_CHAINS = 2`、`LANE_MAX_ROUNDS = 3`，所有数值边界继续从常量导出（沿用行 464 已确立的"预算只钉在两处"纪律）。

收尾判定分两支：

- **账本候选 == 阶段一候选**（无 fix 落地）：完全走今天的 v3 路径，逐条断言不变。这是向后兼容支，也是 14 份历史收据的支。
- **账本候选 ≠ 阶段一候选**（有 fix 落地）：必须存在一份绑定账本候选、且携带合法继承指针的阶段二 challenge 收据；缺失即 fail（**这是本轮新增的那条红**）。`:392` 的"每轮受计收据都绑账本候选"改述为：阶段一收据绑继承指针里记录的候选 A，阶段二收据绑账本候选 B。

行 465 当年那条"拒绝超出 wrapper 可铸造轮数的链"的加固不废除，改述为两条边界：per-chain ≤ 2 轮 **且** lane 累计 ≤ 3 轮 / ≤ 2 条链。放宽的只是"第三份收据"这一个形状，且只在它携带合法继承指针时。

### D6 — 闸文本

- `:610` cadence 改为三轮，第三轮标注条件性触发与其机械谓词；
- `:616` 的 anti-pattern 从不可达的绝对句（"Always do at least one re-challenge after a non-trivial fix-up"）改写为条件形态，与 D1 谓词一致；
- `:534-535` 的 v3 描述更新为 v4 双支判定；
- `:546` / `:549` 的跨链算术更新为 ≤2 链 / ≤3 轮，并保留"重启链花的是同一份预算"这条不变式；
- `:644`（人工 PR 评审不算 dual-track）**保持原文不动**——它一直是对的，本轮改动使它不再被隐性依赖。

## Design-time operability check（四条腿）

| 腿 | 结论 |
| --- | --- |
| author-dogfood | 本轮自身在 CI 的 base 解析下走完新闸：本轮的 fix 批会改 owner Markdown → 必然触发阶段二 → 用自己的机制收尾自己。若跑不通，就是设计不成立。 |
| marginal-cost | 最便宜的常规改动（无发现或全部 accepted）**零额外成本**，与今天完全一致；有 fix 的轮多付一个 challenge 轮（review 的 2–5 倍 token）。成本由用户本轮显式接受（"质量和效率，成本可接受"）。 |
| trust-model fit | 防的是"落地对象未经对抗评审"。**不防**调用方省略历史、伪造账本候选或跳过 wrapper —— 这些仍是 caller-owned 边界，与今天相同，本轮不扩大也不假装收窄。 |
| premise check（收紧向） | 当前语料跑绿**不算证据**：14 份历史收据全部落在"候选未变"支，天然通过新断言。因此必须另造有 fix 落地的 fixture 才谈得上验证这条新红。 |

## 零损失义务表（`:616` 改写）

| 改写前义务 | 去向 |
| --- | --- |
| "round-1 的修复本身可能引入 bug" | 存活：作为第三轮的动机句保留在改写后的 anti-pattern 与 cadence 第三轮说明中 |
| "fix 之后至少再 challenge 一次" | **条件化后存活**：改为"落地候选与被 challenge 的候选不同时，必须再 challenge 一次"——义务未删除，改为可满足且可机械判定 |
| "不要单轮 challenge 就收工" | 存活：anti-pattern 标题句不变 |
| （隐含）"每次微小编辑都自动开新轮"仍是反模式 | 存活：`:619` 该条不动，且 D1 谓词与它不冲突——只有候选真变了才触发，措辞变动不触发 |

无义务被静默丢弃。

## 测试层决策表

| 层 | 决策 | 命令 / 证据 | 当前预期 |
| --- | --- | --- | --- |
| unit（bash，wrapper） | add | `test_extraction_review_gate.sh`：拒绝 `--challenge-b*`、放行继承参数、拒绝第三条链 | fail（新断言） |
| unit（python，validator） | add | `test_validate_extraction_review_state.sh`：兼容支、缺阶段二 fail、有阶段二 ready、同候选伪继承 fail、超 lane 上限 fail | fail（新断言） |
| contract（python，controller） | add | 新增 `test_review_chain_succession.sh`：index 1 challenge 需合法前驱、scope 不符拒、同候选拒、focus 重复拒 | fail（新断言） |
| corpus 复验 | run | 14 份历史收据在新 validator 下全部合法 | pass-existing（必须保持） |
| CI 注册自审 | run | 新增 `test_*.sh` 必须进回归 runner 注册（本地绿 ≠ CI 会跑） | fail until registered |
| impact-chain 闸 | run | 带 `CCL_SKILL_BASE_REF` 跑 `check-ccl-skills.sh` | fail until 台账行落 |
| E2E / 设备 / 浏览器 | not applicable | 无运行宿主、无渲染面 | — |

Mutation 证据要求（保护性谓词，须**已施加**且右因归因，差分判定）：删掉继承校验的任一条（前驱终轮性、scope 同一性、候选相异性）必须让**其所属断言**转红且无非属主断言转红；删掉 lane 上限必须让超限 fixture 转红。仅"非零退出"不算数。

## 台账与 register

- 影响链台账：本交付**只追加一次**（memory 教训：一个交付里台账只能动一次，只加注释也算触碰）。
- register 行须含 `behavioral-evidence: RED-baseline`（本轮 `observed-failure: yes`）、`result-class: failure`、`firing-path:` 指向新回归命令，锚点 ≥16 字符、唯一、含白名单规范词。
- 行 464 / 465 按 append-only 契约**不得原地编辑**，以 supersede-by-pointer 方式指出预算形态的变更。

## 本轮自身的闸

本轮改的是 dual-track 闸自己，但必须按**改动前的 1+1** 过闸：review + challenge，fix 全程 HELD，challenge 绑冻结的 round-1 候选，整批 fix 在闸后随 MR 落地。不得用本轮正在新增的第三轮来评审本轮自己——那是循环自证。

## 执行记录（实测，非声称）

| 项 | 结果 |
| --- | --- |
| controller 套件 | 257 ok / 0 fail；6 条继承用例在**未改动的 controller** 下红、改后绿，既有断言不受影响（差分归因成立） |
| validator 套件 | 全绿含 7 条继承用例；把 validator 回退到 HEAD 后 `succession-ready` 红在 `controller receipt 1 does not bind the ledger candidate`——正是本轮要改的那条不变量 |
| 合并面闸套件 | 11 条全绿（通过、拒绝、precision、以及"不得扰动被哈希的树"） |
| 快回归 lane | 41 套全绿；新增套件已进注册，`--list-unregistered` 空 |
| 仓库闸全套 | `CCL_SKILL_BASE_REF=origin/dev` 下 rc=0（含 R0 private-ok、影响链、契约锚点） |
| author-dogfood | 合并面闸对**本轮自己**返回 rc=1 并点名 `ecdde3a2…`——闸有牙齿是实测的，不是声称的 |
| 历史收据兼容 | per-chain 预算常量未动，14 份历史收据保持逐字节合法；无继承的账本走原路径逐条不变 |

## 本轮踩到并已修的两个坑

1. **假绿断言**：继承的四条拒绝用例最初只断言 `reason_code=review_chain_invalid`——而**旧 controller 对同样参数也返回这个码**（`index != challenge_index + 1`）。它们在没有实现时就"通过"了。改为钉在继承专属诊断文本上，并给"无前驱"那条加了反向断言（必须**不**出现继承诊断）。判据仍是那条老规矩：断言要锚在会随缺陷变化的量上。
2. **闸扰动了它要哈希的树**：合并面闸用 `importlib` 导入 controller，Python 在被评审路径下写了 `__pycache__`，未跟踪二进制文件当场让 packet 冻结失败。已在任何 import 之前 `sys.dont_write_bytecode = True`。这类"测量行为改变被测对象"的缺陷，探针写在自己的套件里。

## 与设计的偏差（如实记录）

- **D4 作废**：wrapper 零改动（读源后发现它无参数白名单、且无状态无法计链），lane 上限全部落在 validator。
- **TDD 顺序**：controller 半程是严格 RED-first；**validator 半程是实现在先、用例在后**，事后用"回退到 HEAD 再跑"取得真实 RED 基线。这是顺序上的偏差，如实记录，不按 TDD 报告。
- **register 行**：初稿在 `code-review` 行里引了 `skill-extraction-workflow` 的包路径，被影响链闸判 `impact_chain_row_ambiguous`（memory 已有此坑）；已收窄为一行一 owner 包。
- **firing-path 锚**：改写 enumeration item 1 时打断了 register 行 487 的锚，闸报 `register_firing_path_unresolved`；原短语所载义务在 round 1–2 仍然成立，故原样保留该短语而非豁免。

## 终态（本轮实际结果，取代上文"执行记录"中的中途数字）

- 落地候选 `57e7b766`；账本 `evidence/closeout.json` 三份收据（review + frozen-candidate challenge + succession），validator 通过，终态 `continuation_authorization_required`。
- 合并面闸对本分支自证：账本存在前拒绝、存在后绑定通过。
- 套件：controller 261、fast lane 41 套、仓库闸 `ccl_skill_check_clean_ok`（带 `CCL_SKILL_BASE_REF`）。
- PR #104（base=dev），合并授权仍在用户手上。

### 四条链、21 条发现——以及为什么没有"修到零"

外部链跑了四轮（084-r1 / 084-r4 / 084-close / 084-succession，另有两次因基线漂移与控制器自改而作废的尝试）。每一链都返回真实缺陷，因为被评审的是本轮刚写的新代码。修完一批候选就移动，于是下一链又有新面可打——这正是闸文档禁止的"迭代到零发现"。停在这里的依据是它自己的条款：预算尽头的终态是**处置**，不是再开一链；终轮自身带发现即 `continuation_authorization_required`，发现随变更走给人。

### 这轮暴露的、值得记住的机制事实

1. **改评审器自身的轮次不能对自己用继承**——前驱无法保留一个本轮刚移动的控制器摘要。实测两次，是规则在工作。
2. **修复必须在账本之前全部落定**：账本绑定的是字节，任何后续修复都让它失效；本轮为此重跑了继承轮。
3. **测量不能扰动被测对象**：闸导入 controller 时写 `__pycache__` 进被哈希的树，当场把 packet 冻结打挂。
4. **断言要接受被测对象所有合法输出**：只认哈希、不认 `no_change` 的断言，在证据提交后当场变红——继承轮把它作为 P2 预言，几分钟后应验。
5. **跨界契约锚点会打挂合成夹具**：把 `.github/workflows/ci.yml` 钉进锚点表，锚点闸在别的套件的合成仓里先红并连累两条无关套件。
