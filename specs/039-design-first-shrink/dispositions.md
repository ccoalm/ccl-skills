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
