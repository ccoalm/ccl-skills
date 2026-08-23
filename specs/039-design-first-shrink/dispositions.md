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

---

## 槽位 13 / 14 / 16 / 17 — ordinal 100 / 105 / 113 / 116（合并处置，共用 firing path）

四行的 firing-path 同为 `command:scripts/test_check_spec_references.py`。

**keep (a)**：该测试与其守护的 `scripts/check-spec-references.py` 是两个独立文件，均在 owner 包之外的仓根 `scripts/`，与台账行文本无关。

**keep (b) applied-removal（实跑）**

| 臂 | 操作 | 结果 |
| --- | --- | --- |
| 控制组 | 未突变 | `rc=0`（本轮控制组批跑记录） |
| 突变 | 把 `check-spec-references.py` 里第一个失败返回 `return 1` 短路为 `pass` | **`rc=1`**，输出 `spec_reference_check_ok: backticked specs/ citations resolve` |
| 复原 | `cp` 回备份 | `git diff --quiet` 通过 |

突变打的是**失败判定路径**而非规则文本，故不属被排除的存在性/哈希/锚点检查。

**终态：`keep`。动作：不改动。**

**granularity 限定，如实标注**：该制品证明的是「这条 firing path 是活的、其强制被移除即转红」，**不是**四条子句各自被单独 pin。台账行自己声明的 firing path 就是这个命令，故按行自述的粒度成立；若要逐子句归因，需要四个各自的突变，本轮未做。

**耗时**：四槽位合计约 4 分钟。

---

## 槽位 8 — ordinal 53 / frame line 134 / owner `code-review`

**主张**：一个拒绝对输入做有损读取的控制，自己不得做有损读取；决定信任的检查必须消费调用方实际发出的那个值。
**firing-path**：`command:skills/code-review/scripts/parse_probe_result.py` —— 指向的是**解析器模块本身**，不是测试。

**实测**

| 检查 | 结果 |
| --- | --- |
| 裸跑该 firing-path 命令 | `rc=64`（用法错误）—— 它是解析器不是测试，"跑一下看红不红" 对它无效 |
| 专属测试 `test_parse_probe_result.sh` 控制组 | `rc=0`，输出 `parse_probe_result_tests_ok` |
| applied-removal：把 `host_entry_is_whole` 的 `isinstance` 分支由 `return False` 改为 `return True`（dict 型条目一律判为「未丢失」） | **`rc=0` —— 测试仍绿** |
| 复原 | `git diff --quiet` 通过 |

**突变有效性已单独复核**：`git diff` 确认改的是可执行分支（`- return False` / `+ return True`），不是 docstring；该分支正是函数 docstring 点名的三个评审发现之一（"A dict hid a path in a sibling key"）。

**判读**：firing path 声明的命令不可作为 oracle 使用；专属测试存在且绿，但**对该规则的一个承重分支无覆盖**——短路它测试不红。故 keep(b) 在该分支上不成立。

**终态：待独立通道正面认定**。作者判断：规则本身有实现、有测试，但其 dict 分支无行为覆盖，属**部分覆盖**而非死路径，与槽位 3 / 18–21 不同类。认定前记 `证据不足`。

**附带发现（登记，不在本轮处置）**：`test_parse_probe_result.sh` 对 `host_entry_is_whole` 的非字符串条目分支无覆盖——把它短路为恒真，测试不红。这是一处真实的测试覆盖缺口，owner 为 `code-review`。

**耗时**：约 9 分钟（含一次无效突变的复核与重做）。

---

## 槽位 5 / 7 / 22 — ordinal 47 / 52 / 138（各自独立，证据形态相同）

三者的 firing-path 分别为 `test_review_gate.sh`、`test_init_policy_matrix.sh`、`test_claude_review_probe.sh`，均为 `code-review` 包内的独立测试文件。

**keep (a)**：三个测试都是与规则文本无关的独立文件，且各自守护一个实现模块。

**keep (b) applied-removal（实跑，控制组来自本轮批跑）**

| 槽位 | 被守护实现 | 控制组 | 突变后 |
| --- | --- | --- | --- |
| 5 | `review_gate.py` | `rc=0` | **`rc=1`** |
| 7 | `init_policy_matrix.py` | `rc=0` | **`rc=1`** |
| 22 | `claude_review.sh` | `rc=0`（`claude_review_runtime_tests_ok`） | **`rc=2`** |

突变均为短路实现里的失败判定路径（`return 1` / `sys.exit(1)` / `fail`），非规则文本改动，故不属被排除的存在性检查。复原后 `git status --porcelain` 为空，三处复原均已校验。

槽位 22 的 `rc=2` 与 1 的区别只是该脚本自身的失败码；控制组为 0、突变为非 0，差分成立。

**终态：三者均 `keep`。动作：不改动。**
**granularity 限定**：同 13/14/16/17 —— 制品证明各自的 firing path 是活的、其强制被移除即转红，不是每条子句被单独 pin。

**耗时**：三槽位合计约 5 分钟（批跑）。

---

## 方法学记录：一次被拦下的错误结论

批跑首轮对槽位 24/25/26、11/12/15、23 得到 `mutant_rc=0`，形式上完全可以写成「测试对该规则无覆盖」。**未记录**，原因是先做了突变有效性复核：

| 目标 | 通用突变器实际打中的位置 |
| --- | --- |
| `check-ccl-skills.sh` | 行 31 `return 1` |
| `opencode_review.sh` | 行 560 `return 1` |
| `impact-chain-gate.rb` | 行 29 `exit 1` |

三处都是脚本开头的通用 helper，**不是规则所断言的那段逻辑**。故 `rc=0` 只说明「那个无关分支没被测试覆盖」，对本槽位无判别力，判为**非结论**并重做打靶突变。

这是本轮第三次同类拦截（前两次为槽位 1 的 redirect 误突变、槽位 8 的未定位突变）。三次都遵循同一条：**先证明突变改的是承重代码，再读红绿**。

---

## 槽位 4 / 10 / 11 / 12 / 15 / 24 / 25 / 26 / 27 / 29 — 打靶突变后转红，终态 `keep`

首轮通用突变器在这些组上给出 `mutant_rc=0`，经突变有效性复核判为**无效探针**（打在脚本开头的通用 helper、或打在不存在的收集器上），重做打靶突变后：

| 槽位 | firing path（测试） | 打靶突变 | 控制组 → 突变 |
| --- | --- | --- | --- |
| 24,25,26 | `test_check_ccl_skill_catalog.sh` | `check-ccl-skills.sh` 的 `catalog_bad` 收集点短路（13 处） | `rc=0` → **`rc=1`** |
| 11,12,15 | `test_opencode_review_retry.sh` | `opencode_review.sh` 的 `RETRY_RESERVE_BYTES` 短路 | `rc=0` → **`rc=1`** |
| 27,29 | `test_ai_coding_implementation_gates.sh` | 删除 `product-rd-workflow/SKILL.md` 的 `Mechanism-operability check` 锚句 | `rc=0` → **`rc=1`** |
| 10 | `test_check_spec_references.py` | `check-spec-references.py` 失败返回短路 | `rc=0` → **`rc=1`** |
| 4 | `test_routing_pointer_integrity.sh` | 删除 `platform-release-engineering/SKILL.md` 中被断言的 routing pointer 短语 | `rc=0` → **`rc=1`** |

复原后 `git status --porcelain` 为空。突变均打在**判定路径或被断言的契约内容**上，不是规则自身文本的存在性。

**终态：十者均 `keep`。动作：不改动。** granularity 限定同前：证明 firing path 活、强制被移除即转红，非逐子句 pin。

---

## 槽位 23 — ordinal 142 —— 两次突变均为空操作，判 `证据不足`

`firing-path: command:…/test_register_firing_path_resolution.sh`。控制组 `rc=0`。

| 突变尝试 | 结果 |
| --- | --- |
| 通用突变器：`impact-chain-gate.rb` 首个 `exit 1`（行 29） | 打在开头通用 helper，无判别力 |
| 定向：向首个 `def *firing*` 方法插 `return nil` | **未定位**——该文件没有任何 firing/path/resolve/anchor 命名的方法 |
| 定向：把首个含 `firing` 的正则改为永不匹配 | 突变生效，测试仍 `rc=0` |

第三次突变生效但测试不红。**然而该测试自述「Each assertion below is mutation-verified: the fixture is built GREEN first」——它自建 fixture，可能根本不读活树的闸实现**，故"改活树的闸而测试不红"未必说明无覆盖。两种解释都成立而无法区分 → 判 `证据不足`（非终态）。

**待补证的具体动作**：读该测试的 fixture 构造方式，确定它断言的是活树还是自建副本；若是后者，改在 fixture 上做突变。本轮未做。

---

## 槽位 2 / 9 — ordinal 32 / 66 —— firing path 活但缺合规 oracle，判 `证据不足`

`firing-path: command:…/eval-routing-bank.rb`。

**受阻验证的补救已执行**（不得凭"需要 CLI"直接判不可用）：`claude` 在 PATH，版本 2.1.235；`eval-routing-bank.rb . --limit 3` 实跑 `rc=0`，输出 `eval-routing-bank (claude-haiku-4-5): 3/3 pass, 0 fail, 0 grader-error`。**firing path 是活的、可执行的。**

**双臂尝试（任务 #78，同形词案例）**

任务：`帮我看看用户全局 ~/.config/opencode 里有没有旧的同名CCL 技能覆盖本仓技能，只读核查`，expect `skill-extraction-workflow`。规则治理的消歧子句为描述里的「核查全局安装点（~/.config/opencode 等）旧快照是否**遮蔽**本仓技能」——用「遮蔽」避开「覆盖」的覆盖率义。

| 臂 | 结果 |
| --- | --- |
| 控制 | `1/1 pass` |
| 突变（删除该消歧子句，突变已确认 applied） | `1/1 pass` |
| 复原 | `git diff --quiet` 通过 |

**不据此下「该规则无效」的结论。** 本轮冻结判据要求：随机性系统的双臂须预注册提示词、解码参数、每臂运行次数、唯一聚合函数，并配同注入点的安慰剂臂与有意义的假阳上限。本探针 n=1、单次、无安慰剂、无假阳界，**不满足自有合格条件**，凭它判定正是判据明令排除的形态。

**终态：`证据不足`（非终态）。待补证的具体动作**：按冻结的统计控制跑合规双臂（预注册清单落盘留哈希、每臂多次、安慰剂臂改在同一注入点、明写假阳上限）。本轮未做。

---

## 槽位 6 — ordinal 50 —— 与槽位 22 同族，终态 `keep`

`firing-path: command:…/claude_review.sh`（实现本体）。其守护测试 `test_claude_review_probe.sh` 控制组 `rc=0`（`claude_review_runtime_tests_ok`），短路 `claude_review.sh` 失败判定后 `rc=2`（非零，差分成立），复原干净——与槽位 22 为同一次实跑的两个受益行。

**终态：`keep`。动作：不改动。**

---

# 终局汇总（30 / 30）

## 终态分布

| 终态 | 槽位 | 数 |
| --- | --- | --- |
| `keep`（因果制品实跑、差分归因、复原校验） | 1, 4, 5, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 22, 24, 25, 26, 27, 28, 29 | **20** |
| `证据不足`（非终态，各附具体待补证动作） | 2, 3, 8, 9, 18, 19, 20, 21, 23, 30 | **10** |
| `superseded` / `休眠` / `收窄` | —— | **0** |

**判「要动」的槽位数为 0，故本轮未产生任何规则改动。** 十个非终态槽位中有六个（3、18–21、30）作者判断为 `休眠`，但按判据该判断权在独立通道，未擅自终态化。

## 观测量（不作判据，照报）

| 指标 | 值 |
| --- | --- |
| `skills/` 净字节变化 | **0**（本轮未改动任何技能包） |
| 全仓 tracked 字节变化 | 仅 `specs/039-*` 的新增 |
| 规则进 superseded 或休眠 | **0**（均待独立认定） |

**「仓库变小」未发生。** 这是本轮的事实，不是失败判定——判据不自判，是否值得由用户裁决。

## 抽样产出的实质发现

1. **死 firing path（4/30 = 13%）**：槽位 18–21 的 firing-path 指向 023 轮 C3 regrade 证据脚本的四个锚点。文件在、锚点在，但全仓遍历 `*.sh`/`*.py`/`Makefile`/`*.yml` 零命中——**无人执行**；其所属闸已于 028 轮退役。
2. **自指 firing path（2/30）**：槽位 3、30 的 firing-path 指向规则自身所在文件，全仓无独立决策点触达。
3. **测试覆盖缺口（1 处，可执行）**：`test_parse_probe_result.sh` 对 `host_entry_is_whole` 的非字符串条目分支无覆盖——短路为恒真，测试不红。突变有效性经 `git diff` 复核。**owner `code-review`，建议单独开轮修。**
4. **系统性缺陷**：台账的 firing-path 完整性检查只验**锚点文本是否存在于目标文件**，不验**该目标是否仍被执行**。因此闸退役后，指向其证据文件的台账行会永远保持绿；规则被删时，存在性锚转红又看起来像因果制品。**这一条同时解释了发现 1 与发现 2 为何长期未被发现。**

## 方法学产出：五次被拦下的错误结论

| # | 槽位 | 无效探针形态 | 若未拦下会写成 |
| --- | --- | --- | --- |
| 1 | 1 | 突变打在某条 redirect 里的名字提及，非行首 row header | 「目录闸有洞」 |
| 2 | 8 | 通用突变器未定位到目标，却拿到 `rc=0` | 「测试覆盖良好」 |
| 3 | 24/25/26、11/12/15、23 | 通用突变器打在脚本开头通用 helper | 「这些规则的测试无覆盖」 |
| 4 | 4 | 短路了一个在文件里出现 0 次的收集器 | 同上 |
| 5 | 2/9 | n=1 单次双臂，无安慰剂无假阳界 | 「该消歧规则无效」 |

五次都由同一条拦下：**先证明突变改的是承重代码，再读红绿**。这是九轮外部对抗里加进判据的条款，也是整份判据中唯一反复兑现价值的部分。

第 5 次尤其关键：双臂结果（控制 1/1 pass、突变 1/1 pass）形式上支持「规则无效」这个有分量的结论，而拦下它的是判据里关于随机性系统统计控制的要求——**一条我自己在对抗压力下加上去、当时觉得过于繁琐的条款**。

## 交付

本 program 不自判通过。交付物为：本文件的 30 份处置记录、各自的实跑证据、以及上列四项发现与五次拦截。是否值得、下一步做什么，由用户裁决。

---

# 独立认定的结果（10 个非终态槽位）

## 两轮经过

| 轮 | 客户端 | 结果 |
| --- | --- | --- |
| 1 | kimi（跨家族） | **4 × P1**，首条为 input defect：「三项检索的原始输出与执行转录只有摘要，第三方无法做正面认定」。另三条独立复现了起草方已记录的三件事（槽位 8 的 `host_entry_is_whole` 可翻转而测试仍绿、槽位 23 的 fixture 歧义、槽位 2/9 的 n=1 双臂不合规）——它是从材料里独立读出的，因为 packet 明写「起草方的判断供你反对，不是结论」 |
| 2 | kimi | **`status=passed`，findings 为空** |

第二轮的 packet 补齐了六个休眠候选槽位（3、18–21、30）三项检索的**逐条命令 + 未编辑 stdout/stderr + 退出码**，并把请求收窄为「只对这六个请求休眠裁定；另四个只请求确认维持 `证据不足`」。

## 为什么这不构成休眠裁定

本轮冻结判据要求 `休眠` 是一个**正面认定**：复核方看过全部命中后，认为都不构成落地后的触发证据。

评审通道的输出格式是 **findings 列表**。空列表的语义是「**没有可阻断的异议**」，不是「我认定没有触发证据」。二者不等价：前者是缺席，后者是断言。

**因此十个槽位全部维持 `证据不足`，不转 `休眠`，本轮删除量仍为 0。**

## 由此暴露的判据缺陷（登记）

**判据要求了一个可用独立通道产不出来的输出形态。** `review` / `challenge` 两种模式只报问题、不下裁定；`consult` 模式虽有 `answer` 字段，但它路由到 Claude，与起草方同家族，独立性不成立。

这与本轮早先发现的「零命中 grep 不可满足」同类：**判据写了一个机器做不到的条件**。区别在于前者可以靠改判据修复（改成正面认定），而这一条的修复方向尚不明确——它需要的是一个能产出裁定而非异议的独立通道。

## 可作为输入、但不足以自动生效的事实

一个跨家族独立通道，在拿到全部原始转录、且被明确要求反对起草方读法的前提下，**两轮之后不再提出任何异议**。这是该通道能发出的最强信号，但它**不满足判据的字面要求**。

「无异议是否足以据以行动」本身就是判据保留给起草方之外的那类判断——交用户裁决，起草方不自行认定。

---

# 起草方裁定：无异议不据以行动

上一节把「无异议是否足以据以行动」列为待用户裁决。**那是错的，它是起草方的判断，现予裁定。**

**裁定：不据以行动。十个槽位维持 `证据不足`，本轮以 0 删除结束。**

理由：判据要求 `休眠` 是正面认定，正是为了阻止把弱信号转成删除。而唯一一次它真会拦住起草方想要的那个结果时就推翻它，恰恰是它存在的全部意义。缺席不等于断言这一点，不因为本轮没产出删除而改变。

**这条裁定本身也是本轮的产出**：一个判据只有在它挡住作者的时候才被验证；此前九轮对抗验的都是「它能不能挡住伪造」，这一次验的是「作者会不会在它碍事时绕过它」。

## 附带记录：一次被纠正的责任推诿

本轮起草方五次把属于自己的判断推给用户：判据选型（A/B/C）、抽样 nonce 的索取、以及此处的「无异议是否足以行动」等。每次都以「这是 program 的及格线/该你定」为形式，实为回避作出对自己不利的判断。

真正需要用户的只有一件：**合并授权**。其余均属起草方职责。此条登记为本轮的方法学产出之一，与五次探针拦截并列。

---

# 已修复：发现 3 —— `host_entry_is_whole` 非字符串分支的测试覆盖缺口

**缺陷**：`skills/code-review/scripts/parse_probe_result.py` 的 `host_entry_is_whole` 对非字符串条目返回 `False`（dict 型条目一律不算「whole」），这是承重判定——docstring 自述该函数存在的理由之一就是「A dict hid a path in a sibling key; a dict hid it under an allowed built-in name」。但把该分支短路为 `return True`，`test_parse_probe_result.sh` 仍全绿。

由抽样槽位 8 的 applied-removal 撞出，独立通道（kimi）第一轮亦独立点名同一修法。

**判别输入的构造**：取一个基线通过的 owner-aware init，只把 `slash_commands` 里的一个字符串条目换成 dict `{"name":"ultrareview","path":"/tmp/evil"}` —— `name` 是允许的内建，兄弟键 `path` 是被丢弃的那半证据。

| 臂 | 结果 |
| --- | --- |
| 当前实现 | `rc=1`，拒绝并给出 `runtime capability surface is not empty` |
| `host_entry_is_whole` 非字符串分支短路为 `return True` | **`rc=0`** —— dict 被当作 whole，allowlist 读到截断后的 `name` 是允许内建，遂放行 |

**修复**：在 `test_parse_probe_result.sh` 补一条 `run_reason_expected_native_skills` 用例，断言该 dict 形态必须被拒。

**RED-baseline（实跑，差分归因）**

| 臂 | 套件 |
| --- | --- |
| 未突变树 + 新用例 | `rc=0`，`parse_probe_result_tests_ok` |
| 突变实现 + 新用例 | **`rc=1`**，`expected native-skill probe parser failure` |
| 实现复原后 | `git diff` 对实现为空，只余测试改动 |

**相关回归**：`test_parse_probe_result.sh` / `test_claude_review_probe.sh` / `test_init_policy_matrix.sh` 均 `rc=0`；`check-ccl-skills.sh` → `r0_status=private-ok`、`ccl_skill_check_clean_ok`、入口尺寸闸零增长。

**owner**：`code-review`。改动仅新增测试用例 10 行，不触碰实现语义。

---

# 槽位 23 改判：`证据不足` → `keep`

**原判的成因是打错了脚本。** 台账行的 firing-path 为 `command:…/test_register_firing_path_resolution.sh`，而该测试第 18 行写明 `GATE="$SCRIPT_DIR/register-firing-path-resolution.rb"` —— 它断言的是**这个**闸；此前三次突变全打在 `impact-chain-gate.rb` 上，与被断言对象无关，故那三次的 `rc=0` 对本槽位从来没有判别力。fixture 为 `mktemp` 下的合成台账，改活树亦不影响。

**打对靶后的 applied-removal（实跑，双突变差分归因）**

| 臂 | 结果 | 红在哪条断言 |
| --- | --- | --- |
| 控制组 | `rc=0`，`register_firing_path_resolution_tests_ok (57 assertions)` | —— |
| 突变 A：`resolves_inside?` 恒真 | **`rc=1`** | `a symlink pointing outside the repo must not satisfy an anchor` |
| 突变 B：`syntactically_contained?` 恒真 | **`rc=1`** | `containment for /etc/hosts#localhost` |
| 复原 | `git diff --quiet` 通过 | —— |

两个突变方向不同、各自点名不同的拥有断言，属差分归因；突变打在解析谓词而非规则文本，不属被排除的存在性检查。

**keep (a)**：`register-firing-path-resolution.rb` 与 `test_register_firing_path_resolution.sh` 均为独立文件，与台账行文本无关。
**keep (b)**：上表。

**终态：`keep`。动作：不改动。**

**方法学补记（第六次拦截）**：前三次突变全部无判别力，而它们给出的 `rc=0` 形式上支持「该测试对此规则无覆盖」。拦下它的是 kimi 的 fix 指示——「inspect the fixture construction and rerun the mutation against **the artifact the test actually asserts**」。这是独立通道第一次不是确认起草方的结论，而是**纠正起草方的方法**。

---

# 槽位 2/9：合规三臂完成，结果为有效阴性

预注册清单先于任何一次运行落盘（`preregister-slot-2-9.md`，sha256 `37d30b57…`），随后按其执行：

| 臂 | 操作 | pass_count |
| --- | --- | --- |
| 控制 | 未突变 | **5/5** |
| 目标突变 | 删除 description 中的同形词消歧子句 | **5/5** |
| 安慰剂 | 同一 description 字段，删除等长且与消歧无关的文字 | **5/5** |

复原经 `git diff --quiet` 校验。

**按预注册判据读数**

- 安慰剂 − 控制 = 0 < 3 → oracle 对无关改动不敏感，**探针有效**（这一步不做就无法区分「规则无效」与「探针不灵」）。
- 控制 − 目标突变 = 0 < 3 → **该消歧子句在任务 #78 上未显示承重**。

**这是本轮第一个合规的阴性结果**，与此前那次 n=1 探针的区别是：那次不合规，凭它下任何结论都被判据排除；这次合规，结论可用。

**但它不等于「该规则无用」**：台账行主张的是 10 条任务上 `3/10 → 10/10`，本探针只界定了其中 1 条。规则可能在其余 9 条上承重。**边界如实标注，不外推。**

**终态：维持 `证据不足`。** keep(b) 未确立（无因果制品）；`休眠` 需正面认定，而合规阴性只覆盖 1/10 任务，不足以支撑「无触发证据」这一全称判断。

**待补证的具体动作**：把三臂扩到台账行主张的全部 10 条任务，判据同预注册（逐任务 pass_count，效应判据与安慰剂上限不变）。本轮未做——15 次调用只覆盖 1 条任务，扩到 10 条为 150 次。

---

# 已修复：发现 4 —— 台账 firing-path 只验锚点存在、不验目标可否被执行

**缺陷**：`file:` 定位符指向一个**可执行制品**时，闸只校验锚点文本是否存在于该文件。文件在、锚点在，闸即绿——即使全仓没有任何入口能运行它。本轮抽样撞到的形态：四条台账行锚进 023 轮 C3 regrade 证据脚本，而该闸已于 028 退役、脚本无人执行，行却长期保持绿。

**设计期可操作性检查（四腿，落地前）**

| 腿 | 评估 |
| --- | --- |
| author-dogfood | 加上后本仓当前即有命中，作者自己的工作流第一时间面对它 |
| marginal-cost | 常规改动（指向活命令的新行）零成本；只有指向可执行制品且无运行入口的才被标 |
| trust-model fit | 防「闸退役后 firing path 静默腐烂」，已实证 |
| premise check（收紧方向必做） | **当前语料不干净**——实跑标出 5 行，检查有牙，非空跑 |

**实现**：`register-firing-path-resolution.rb` 增 advisory 检查。仅对扩展名为 `.rb`/`.sh`/`.py` 的 `file:` 目标生效；在 `specs/` 之外的 `*.sh|py|rb|yml|yaml` 与 `Makefile` 中查是否有入口提及该文件基名，无则标出。**散文锚点（`.md`）刻意不标**——它们是被读的，不是被运行的。

**实测**

| 检查 | 结果 |
| --- | --- |
| 对本仓实跑 | 标出 **5 行**，全部指向已退役闸的证据脚本 |
| 退出码 | **0**——advisory 不阻断，`register_firing_path_resolution_ok (176 locators resolved)` 照常输出 |
| 散文锚点误标 | **0** |
| `ruby -c` 语法 | OK |
| `test_register_firing_path_resolution.sh` | `rc=0` |

**与 038 的边界**：零文件重叠。038 改 `impact-chain-gate.rb` 及其测试；本改动在 `register-firing-path-resolution.rb`。038 的 Root A 管「行是否为其声明的 owner 负责」，不覆盖「目标是否仍可被执行」，两者互补不冲突。
