# 039 槽位处置记录

抽样见 [`sample-slots.txt`](sample-slots.txt)（seed 源 `44c11cb7`，框 `1fc647e2…7f33`）。
判据见 [`plan.md`](plan.md) 的「终态判定条件」，处置期间不得修改。
每槽位记：锚点 → 定义跨度 → 检索/因果制品 → 终态 → 动作 → 耗时。

---

## 槽位 1 — ordinal 15 / frame line 41 / owner `skill-extraction-workflow`

**台账行主张**：手工维护的技能目录只有在同一次落地里被做成机械不可漂移时才允许存在——目录与 always-on 路由层互相为闸，而按名字做集合差不是那道闸。

**锚点**：`skills/skill-extraction-workflow/SKILL.md:212`（`Do Not Extract When` 节内那条「standalone skill index / quick-reference catalog」）。
**定义跨度**：该 blob 中包含锚点的最小 Markdown 块 = 该单个列表项（一行）。

**有序判据逐项**

| 序 | 终态 | 结果 |
| --- | --- | --- |
| 1 | `superseded` | 不成立——无其它规则或闸覆盖其义务 |
| 2 | `收窄` | 不成立——未举出「按当前措辞会触发但触发是错的」的具体情形 |
| 3 | `keep` | **成立**，两项俱备（见下） |

**keep (a) 目标文本之外的 firing point**：`skills/skill-extraction-workflow/scripts/check-ccl-skills.sh:72–110+` 的 catalog contract 段，按 `- \`name\` \`entry|leaf\`` 行首锚定解析 `docs/SKILLS.md`，与 `agent-context/session-start.md` 互相校验。与 SKILL.md:212 的规则文本是两处独立文件。

**keep (b) 因果制品 — applied-removal 行为 oracle**（实跑，非假设）

| 臂 | 操作 | 闸退出码 | 令牌 |
| --- | --- | --- | --- |
| 控制组 | 未突变 | 0 | `skill_catalog_map_ok` / `skill_catalog_contract_ok entries=32` |
| 突变 A | 删除 `docs/SKILLS.md` 中 `- \`grill-me\` \`entry\`` 整行 | **1** | `skill_catalog_map_mismatch` / `missing_in_catalog=grill-me` |
| 突变 B | 该行头改名为不存在的 `grill-zz` | **1** | `skill_catalog_map_mismatch` / `missing_in_catalog=grill-me` + `extra_in_catalog=grill-zz` |
| 复原 | `cp` 回备份 | 0 | `git diff --quiet` 通过 |

两个突变方向不同、令牌各自点名具体技能，属差分归因而非「非零退出即算红」。

**一次失败的探针，如实记录**：首次突变把 SKILLS.md 第 21 行某条 redirect 里提到的 `grill-me` 改名，闸保持绿。当时看起来像「闸有洞」，实为探针无效——闸按**行首 row header** 锚定，而该处是别的条目里的一次提及。闸源码的注释恰好写明了这个区分（松散的反引号扫描会把别处的提及当成覆盖）。若未复核就记录，会得出一个与事实相反的结论。

**终态：`keep`。动作：不改动**（唯一允许不动的终态）。
**耗时**：约 4 分钟（含读行、定位锚点、两次突变与一次失败探针的复核）。

---

## 槽位 3 — ordinal 37 / frame line 112 / owner `skill-extraction-workflow`

**台账行主张**：放宽一道闸的判决等于移除证据而非增加一道红，故必须双向过 design-time operability check，且要在给人提供选项之前而不只是在落地之前；`recommended` 标签即断言逐选项的证据移除对比已经做过。

**锚点**：`skills/skill-extraction-workflow/SKILL.md:194`。**定义跨度**：含锚点的最小 Markdown 块 = 该单个列表项。
**台账声明的 firing-path**：`file:…SKILL.md#a loosening must be checked hardest` —— **指向规则自身所在文件**，按判据 keep(a)「引用自身文本不算」，该声明本身不构成 firing point。

**检索三项（原始输出留存，见下）**

| 项 | 结果 |
| --- | --- |
| 全仓引用 | 7 处：1 处为 SKILL.md 内该规则自身指向其详解页；1 处在 `references/rule-consolidation.md` 引用其 author-dogfood 腿；5 处在 `references/source-register.md`，均为叙述历次应用的台账行 |
| owner 包内断言 | 2 个脚本命中关键词：`test_ai_coding_implementation_gates.sh` 断言的是 `product-rd-workflow` 的 **Mechanism-operability check**（另一条规则）；`test_check_ccl_impact_chain_refscripts.sh:978` 只在注释里提及 |
| applied-removal（实跑） | 见下表 |

**applied-removal 行为 oracle（实跑，含控制组）**

| 检查 | 控制组 | 删除该规则后 | 判读 |
| --- | --- | --- | --- |
| `test_ai_coding_implementation_gates.sh` | 0 | **0** | 不断言这条规则 |
| `test_check_ccl_impact_chain_refscripts.sh` | 0 | **0** | 仅注释提及 |
| `check-ccl-skills.sh` | 0 | **1** | 红，令牌 `source-register.md:112: anchor text absent from target: file:…#a loosening must be checked hardest` |

**关键判读：唯一转红的是锚点存在性检查。** 判据明写排除「对规则本身的存在性、哈希、锚点或 schema 检查」——删掉文本使「该文本存在」的断言转红是同义反复。故该红**不构成 keep(b) 的因果制品**。

**有序判据逐项**：`superseded` 不成立（无其它规则覆盖其义务）；`收窄` 不成立（未举出误报形态）；**`keep` 不成立**——(a) 台账声明的 firing point 指向自身；另找到的两个脚本一个断的是别的规则、一个只是注释；(b) 唯一的红属被排除的存在性检查。

**终态：待独立通道正面认定。** 按检索协议，材料（三项原始输出 + 上表 + 逐处命中标注）交独立通道，由它判定这些命中里有没有一处构成落地后的实际触发证据。作者的判断是**没有**（锚点存在性检查 + 五条自著台账叙述），但**判断权不在作者**——这正是把 `休眠` 从「grep 返回零行」改成正面认定的原因。在独立认定到位前，本槽位记 `证据不足`（非终态）。

**耗时**：约 8 分钟（含两套测试的控制组与突变组各一次，突变运行 92 秒）。

---

## 槽位 18 / 19 / 20 / 21 — ordinal 127 / 132 / 134 / 136（合并处置，同一 firing path 目标）

四个槽位的 firing-path 都指向同一个文件的不同锚点：
`specs/023-agent-native-repo-borrowing/evidence/test_red_baseline_023_c3_regrade.rb#…`

**实测**

| 检查项 | 结果 |
| --- | --- |
| 该证据文件是否存在 | 存在，33163 字节 |
| 四个锚点是否仍在文件中 | 在（`c3_regrade_contract_tests_pending` ×1、`make_test_candidate_invocation` ×8、`effective_c3_invocations` ×2） |
| **是否有任何东西执行它** | **无**。`grep -rln` 遍历全仓 `*.sh` / `*.py` / `Makefile` / `*.yml`（排除 `specs/` 自身）零命中 |
| 其所属的闸 | C3 preservation gate，**已在 028 轮退役**（`specs/028-c3-preservation-gate-retirement/plan.md`） |

**判读**：锚点在、文件在，所以任何**存在性**检查都是绿的；但**没有任何决策点会到达它**——文件不被执行，闸已退役。按 keep(a)，firing point 必须是一个会去取用该规则的决策点，一个无人运行的文件不是。按 keep(b)，无因果制品可言：删掉它不会让任何在跑的检查转红。

这正是判据里「文本存在于某文件而无决策点触达 = `downgraded` 而非 `landed`」所描述的形态，也是本轮第一次在真实抽样中命中**死 firing path**。

**有序判据**：`superseded` — 需要指出承接者，而这四行的主题是一个已退役闸的证据脚本契约，无现存承接者；`收窄` — 不适用；`keep` — (a)(b) 皆不成立。

**终态：待独立通道正面认定**，作者判断为 `休眠`（四条合并为一次认定，因共用同一死目标）。材料：上表 + 全仓执行方 grep 的原始输出 + 028 退役记录。在认定到位前记 `证据不足`。

**附带发现（超出本槽位，登记不在本轮处置）**：台账的 firing-path 完整性检查只验**锚点文本是否存在于目标文件**，不验**该目标是否仍被执行**。因此一个闸退役之后，指向其证据文件的台账行会**永远保持绿**。这与槽位 3 的存在性锚问题同源：`check-ccl-skills.sh` 验的是文本在不在，不是它还起不起作用。

**耗时**：四槽位合计约 6 分钟。

---

## 槽位 28 — ordinal 164 / frame line 255 / owner `skill-extraction-workflow`

**主张**：blocked-verification 的补救获得 sandbox 拒绝分诊与受控提权规则的安全形态——必需命令失败时先分诊，提权绝不作为默认动作。
**锚点**：`references/source-to-skill-extraction.md:306`。**firing-path**：`file:…#Sandbox-denial triage precedes any escalation`。

**keep (a) 目标文本之外的 firing point**：`skills/skill-extraction-workflow/scripts/test_controlled_escalation_pins.sh` —— 独立文件，以该短语为断言（第 102 行）。

**keep (b) 因果制品（实跑）**：控制组 `rc=0`，输出
`test_controlled_escalation_pins: ok (52 applied mutations, each red on its owning assertion; controls green)`。

该套件自带两类突变，均非存在性检查：

- **删除突变**：把该短语从副本中删掉 → 必须红；未红即 fail。
- **位移探针**：把短语从其所属小节删掉、改附到文末的诱饵标题下 → **必须仍然红，且红在正确的那条断言上**（`controlled escalation (invariant: triage before escalation…)`）。这一条正好排除了「全文 grep 式存在性检查」——短语在文件里还在，断言照样红。

**终态：`keep`。动作：不改动。** 这是本抽样里最强的因果制品：52 个突变逐个差分归因，且位移探针主动证伪了存在性解释。
**耗时**：约 3 分钟。

---

## 槽位 30 — ordinal 180 / frame line 271 / owner `skill-extraction-workflow`

**主张**：but-for 检验带一条涌现结果边界——反事实在难解交互中无法稳定时，重构出来的因子应……
**锚点**：`references/source-to-skill-extraction.md:115`，位于「反事实检验每个候选原因」那条编号项内部的一个子句。

| 检查 | 结果 |
| --- | --- |
| 有无测试 pin 该短语（`*.sh`/`*.py`/`*.rb` 全仓） | **零命中** |
| 目标文件与台账之外的 md 引用 | **零命中** |
| firing-path 声明 | 指向该规则所在的同一份 reference 文件 |

**判读**：keep(a) 不成立——firing path 指向自身所在文件，且全仓无任何独立决策点触达；keep(b) 无从谈起——没有会因它被删而转红的检查。`superseded` 无承接者，`收窄` 未举出误报形态。

**终态：待独立通道正面认定**，作者判断为 `休眠`。认定前记 `证据不足`。
**耗时**：约 2 分钟。

---

## 阶段小结（8 / 30 已处置）

| 终态 | 槽位 | 数 |
| --- | --- | --- |
| `keep`（因果制品实跑） | 1、28 | 2 |
| 待独立认定（作者判断无真实触发证据） | 3、18、19、20、21、30 | 6 |

**已浮现的形态差异**：拿得出因果制品的两条，其证据都来自**独立测试套件对规则做 applied mutation 并差分归因**（槽位 28 甚至自带位移探针主动排除存在性解释）；拿不出的六条，firing path 要么指向规则自身所在文件，要么指向一个**已无人执行的死文件**。
