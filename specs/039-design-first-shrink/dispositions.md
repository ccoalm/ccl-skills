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
