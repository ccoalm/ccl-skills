# PR #76 评审修复轮 — implementer self-review row

> 本文件是 dual-track gate 要求的 ordering-proof 工件：以独立提交先于独立评审落库，本身不是落地提交。落地提交在独立评审通过并处置发现后才产生。

## 候选 diff 范围（changed-file set）

以 PR head `d910db9` 为基线，候选 diff 恰为下列 8 个文件（本记录文件是 ordering 工件，不属于候选 diff）：

1. `skills/skill-extraction-workflow/scripts/obligation-ledger.py`
2. `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh`
3. `skills/skill-extraction-workflow/scripts/impact-chain-gate.rb`
4. `skills/skill-extraction-workflow/scripts/test_entrypoint_domain_scan_terms.sh`
5. `scripts/test_check_spec_references.py`
6. `specs/065-uiux-evidence-delivery/obligation-mapping.jsonl`
7. `specs/065-uiux-evidence-delivery/obligation-preservation.md`
8. `specs/065-uiux-evidence-delivery/validation-evidence.md`

## 验收标准复核

- PR #76 自述的完成命令 `obligation-ledger.py audit` 在 head 真仓可复跑且退出 0（修复前退出 1，`CARRIER_COMPOSITE_NOT_UNIQUE count=0`）。
- 五处解析器缺陷（table_cells 反引号配对、section_body_ranges 用 raw 而非 masked 切片、compound_clauses 未遮罩内联代码、mask_inert_markdown 段落续行误判缩进代码、末格反斜杠吞管道）各有失败输入探针 + 对照输入验证。
- DOI/W3C 允许区间的洗白逃逸（伪造 DOI 形状后缀携带长数字 ID）被封堵，且逃逸样本固化为 RED test leg `laundered-suffix-id`。
- 测试 fixture 不再摄取未跟踪文件（`--others --exclude-standard` 移除），与被测 checker 的 tracked-only 扫描口径一致。
- bank-only resolver 的失败信息补充裸引用约定说明；resolver 语义有意不改（全路径归因会误吸收 `file:skills/...` locator 行）。

## 边界与失败路径考量

- `obligation-ledger.py` 解析器改动在真实语料上字节级稳定：重渲 ledger 仅变化被修复的 carrier 行，证明修复未引入解析漂移。
- 9 位数字上限的取舍：真实 DOI/W3C 引用携带 8 位数字段；时间戳（14 位）与 snowflake（18–19 位）仍被标记。若未来出现合法 10+ 位 DOI 引用，会假阳性而非漏报（fail-closed 方向）。
- `mask_inert_markdown` 修复后，缩进行仅在空行之后（或已开启的缩进块延续）判为代码，符合 CommonMark 段落中断规则。

## 回归证明（修复前红 / 修复后绿）

- `laundered-suffix-id` leg（`test_entrypoint_domain_scan_terms.sh`）：对修复前 regex 复现逃逸（该样本通过闸门），修复后被标记。
- 五处解析器缺陷各有修复前复现探针（失败输入产出错误解析）与修复后通过验证；`test_obligation_ledger.sh` 76 mutants 全绿。
- untracked-fixture：以未跟踪 WIP spec 活探针验证双向（修复前套件假红、真 checker 绿；修复后两者一致）。
- mapping 修复：`audit` 由退出 1 转为 `audit_ok domain=50 rows=1240 unresolved=0`。

## 已跑确定性闸与各自证明

- `check-ccl-skills.sh`（`CCL_SKILL_BASE_REF=origin/dev`）→ `ccl_skill_check_clean_ok`：全仓确定性闸对候选 diff 干净。
- fast lane 31 suites 全绿：注册测试面无回归。
- `test_obligation_ledger.sh`（76 mutants）、`test_entrypoint_domain_scan_terms.sh`、`test_impact_chain_self_adjudication.sh`（A1–A23）、`test_check_spec_references.py`：各自覆盖被改脚本的既有契约未破坏。

## Remediation 轮（第一轮独立评审后的候选刷新）

第一轮独立 review+challenge（chain `pr76-review-fix-20260830`，packet sha256 `28da3272…`）返回 5 条发现，全部核实并修复；候选 diff 因此变更，本节先于第二轮 full-scope 评审落库。

新候选 changed-file set 在原 8 文件基础上新增：

9. `skills/skill-extraction-workflow/scripts/test_obligation_ledger.sh`（新增 parser-boundary 回归 leg）

逐条处置：

- R1-P1 缩进代码判定：`mask_inert_markdown` 由「空行后才开缩进代码」改为段落开闭跟踪（`paragraph_open`）——heading、fence 关闭后缩进代码同样遮罩；ATX heading 与 thematic break 不开段落。
- R1-P1 colon 动作词：`compound_clauses` 的 colon 前缀与 clause_like 判定均改在 code-span 遮罩后的 structural 文本上搜索。
- R1-P2 缺回归测试：`test_obligation_ledger.sh` 新增 parser-boundary leg（12 个 case），对原始 PR 版工具复跑为红（6 处失败），修复版全绿；对 remediation 中间态的 3 个 case 已按代码路径核实为红。
- R1-P2 base 可复现性：render/audit 在工具层解析 `--base` 为 commit，header 记 `origin/dev @ <sha>`；audit 的字节比对使 base 漂移显式转为 `STALE_LEDGER`。
- R2-P1 split-run 洗白：允许区间豁免改按「单分隔符合并数字段 ≤9 位」计量，任一超限合并段使整个区间失去豁免；新增 `split-run-id`、`split-timestamp-id` 两条 RED test leg，合法 DOI/W3C 控制样本仍绿。

重跑证据：`test_obligation_ledger.sh`（含新 leg）、`test_entrypoint_domain_scan_terms.sh`（含新 leg）、`test_check_spec_references.py` 全绿；真仓 `render`/`audit` 均 `*_ok domain=50 rows=1240 unresolved=0`，重渲仅变化 header base 行。全仓闸与 fast lane 在本节落库后重跑。

## Remediation 轮 2（第二轮独立评审后的候选刷新）

第二轮独立 review+challenge（chain `pr76-review-fix-r2-20260830`，packet sha256 `760a3d57…`）返回 4 条发现。changed-file set 与上节相同（9 文件）。逐条处置：

- R2-P1 双分隔符绕过 + R2-P1(challenge) 纯数字 DOI 误伤：豁免改为 payload 域内计量——DOI 取 registrant 斜杠后的后缀（named capture），W3C 取报告日期；合并段跨一个或多个连续分隔符（`[0-9]+(?:[-._/]+[0-9]+)*`），任一合并段 >9 位则该区间不给豁免。`10.1038/35057062` 转绿（新增 GREEN 控制样本），`20260830--123456` 转红（新增 `double-separator-id` RED leg）。中间实现曾把量词写成单数字吸收（`[0-9](?:…)*`），被本轮先前新增的 `split-run-id` RED leg 当场抓红后修正——回归面自证有效。
- R2-P2 TOCTOU：`--base` 在 main 里 `rev-parse <base>^{commit}` 解析一次，comparison/derive 全部改用 resolved commit，header 与行集不可能取自不同基线。
- R2-P2 comment→缩进代码：实证否决——注释独占行被空白化后按空行处理，其后缩进代码已被遮罩（masked）；`text <!-- c -->` 后缩进行保持可见是 CommonMark 懒延续的正确行为。处置为无需改动，并在 parser leg 新增 `mask-code-after-comment-line`、`mask-comment-inline-continuation` 两个钉行为 case。

重跑证据：`test_entrypoint_domain_scan_terms.sh`（12 个无效类 + 3 个合法控制样本）、`test_obligation_ledger.sh`（parser leg 现 14 case）全绿；真仓 `render`/`audit` 均 `*_ok domain=50 rows=1240 unresolved=0`。全仓闸与 fast lane 在本节落库后重跑。

## Remediation 轮 3（第三轮独立评审后的候选刷新）

第三轮独立 review+challenge（chain `pr76-review-fix-r3-20260830`，packet sha256 `5e2429fb…`）两 lane 同点收敛各 1 条 P1：合并分隔符类只覆盖 `-._/`，而 DOI payload 字符集还接受 `;():+`，`123456789+123456789` 可拆分豁免。changed-file set 与上节相同（9 文件）。处置：分隔符类扩为 payload 字符集接受的全部标点（`[-._/;():+]+`），字母仍为段边界（真实 DOI 合法混排字母数字，桥接字母会误伤 `s15516709cog1202_4` 控制样本）；新增 `plus-split-id`、`colon-split-id` 两条 RED leg。重跑：`test_entrypoint_domain_scan_terms.sh`（14 无效类 + 3 合法控制）全绿。字母作分隔符的拆分（`123456789x123456789`）与 registrant 通道同记残余（见下节）。

## Remediation 轮 4（第四轮独立评审后的候选刷新）

第四轮独立 review+challenge（chain `pr76-review-fix-r4-20260830`，packet sha256 `7af22bca…`）返回 3 条。changed-file set 新增第 10 个文件：`skills/skill-extraction-workflow/scripts/test_obligation_ledger_repo_audit.sh`（新建），并触碰 `test_check_ccl_regressions.sh`（heavy lane 注册行）。逐条处置：

- R4-P1 Setext heading：属实。`Title\n===\n    code` 的下划线行既非 ATX 也非 thematic break，段落误保持开启。修复：段落开启时匹配 `^[ ]{0,3}(?:=+|-+)[ \t]*$` 判为 Setext 下划线并关闭段落；parser leg 新增 `mask-code-after-setext-eq`、`mask-code-after-setext-dash` 两个 case（leg 现 18 case）。
- R4-P2 真仓 audit 无 CI lane：属实。新建 `test_obligation_ledger_repo_audit.sh`：从 committed ledger header 提取钉住的 40-hex base SHA，对真仓 mapping/ledger 复跑 audit（实测 ~6.7s）；注册进 heavy lane（CI `--full` 强制，不加重 pre-commit）。为使其可字节复现，render header 改记纯 resolved SHA（恢复 PR 原稿形态；`ref @ sha` 标签是修复轮引入的偏差，已撤）；preservation.md 从而与 PR head 字节一致。轮中实测 origin/dev 已被并发会话推进（e322db4→7433f69），ledger 保持 PR 原基线 `e322db47…` 重渲，pinned audit 在 ref 前进后仍绿——正是该测试要守的性质。
- R4-P1(challenge) sub-8 拆分（`1234567+1234567`）：**拒绝其修法**。把「合并段 >9 位直接判泄漏」会误伤常见真实 DOI（`10.1016/S0140-6736(20)30183-5` 的标点合并段 16 位、SICI 形态 19 位）；且 <8 位数字组在 prose 中同样低于全闸检测下限（基础谓词是连续 `[0-9]{8,}`），DOI shape 对 sub-8 组不提供超出普通文本的走私能力——豁免机制的职责是不抵消基础扫描会报的项，而非提高全闸下限。记入残余通道 (c)。

重跑证据：`test_obligation_ledger_repo_audit.sh` 绿（`audit_ok domain=50 rows=1240 unresolved=0`）；ledger 套件、全仓闸、fast lane 在本节落库后重跑。

## Remediation 轮 5（第五轮独立评审后的候选刷新）

第五轮独立 review+challenge（chain `pr76-review-fix-r5-20260830`，packet sha256 `ddc0cf26…`）两 lane 各 1 条 P1，均属实。changed-file set 与上节相同（10 文件）。处置：

- R5-P1 W3C 豁免区间过宽：`CG-FINAL-123456789-format-20251028/` 的报告名 9 位 ID 因整 URL 都在豁免区间而被洗白。修复：豁免区间收窄为 payload capture 本身（W3C 只豁免日期，DOI 豁免通过计量的 suffix）。副作用是关闭了残余通道 (a)——≥8 位的伪造 registrant 现在落在豁免区间外直接被标记（真实 registrant 4-6 位，低于扫描下限，不受影响）。新增 `report-name-id`、`registrant-id` 两条 RED leg（现 18 无效类）。
- R5-P1(challenge) 列表项内 Setext+缩进代码：`- Title\n  ===\n      code` 未遮罩。修复：列表内容分支引入与顶层一致的段落跟踪——相对 content column ≥4 的缩进行在段落关闭时遮罩；列表内 Setext 下划线、ATX heading、thematic break 关闭段落。masker docstring 契约同步改写（列表懒延续仍可见）。parser leg 新增 `mask-list-code-after-setext`、`mask-list-code-after-blank`（现 20 case）。真实语料字节稳定性已验证：重渲与 committed ledger `cmp` 一致，audit 绿。

## Remediation 轮 6（第六轮独立评审后的候选刷新）

第六轮独立 review+challenge（chain `pr76-review-fix-r6-20260830`，packet sha256 `7b82b259…`）两 lane 各 1 条 P1，同族（容器前缀行的段落分类），均属实。changed-file set 与上节相同（10 文件）。处置：

- R6-P1 块引用内 heading：`> # Heading\n    code` 的引用行被当作开段落。修复：顶层 fallthrough 先剥 `^[ ]{0,3}(?:>[ ]?)+` 前缀再分类内容——引用内 heading/thematic 关闭段落，引用内 prose 仍开段落（其后缩进行是引用的懒延续，保持可见）。
- R6-P1(challenge) 列表项首行 heading/thematic：`- # Heading\n      code`、`- ***\n      code` 的 item 分支无条件开段落。修复：按 item 首行内容分类（空、ATX、thematic 均不开段落）。
- parser leg 新增 4 个 case（item-heading/item-break/quote-heading 遮罩 + quote 懒延续可见，现 25 case）。真实语料字节稳定性重验，全部套件与闸重跑。

## Remediation 轮 7（第七轮独立评审后的候选刷新）

第七轮独立 review+challenge（chain `pr76-review-fix-r7-20260830`，packet sha256 `ce562e6d…`）各 1 条 P1。changed-file set 与上节相同（10 文件）。处置：

- R7-P1 8-9 位 registrant「误报」：**拒绝**。8-9 位 DOI registrant 未见于真实实践（常见 4-6 位）；误报方向 fail-closed，本仓语料全闸绿即无实际误伤；豁免它会重开轮 5 关闭的洗白通道 (a)。`registrant-id` RED leg 是有意锁定的行为。若未来出现真实 8+ 位 registrant 引用，作者可按 leg 注释放宽——那是有证据时的策略变更。
- R7-P1(challenge) 引用内容器相对缩进代码：属实。`> # Heading\n>     code` 的引用内代码从 quote marker 起算缩进，原实现只看 raw 行首。修复：剥引用前缀后按内容相对缩进套用同一 cannot-interrupt-paragraph 规则。parser leg 新增 `mask-quote-internal-code`（现 26 case）。
- 收敛声明：轮 4-7 的 masker 发现同属「块级容器的段落/缩进分类」一类，本轮已把顶层、列表、引用三种容器统一到同一套内容分类+相对缩进规则并逐一钉入回归。更深的嵌套组合（引用内列表内代码等）若再被提出且真实语料字节稳定不受影响，将按 documented accept 处置而非继续逐条修——真实语料在每一轮均验证字节稳定，该 masker 服务的是本仓 skill 文档语料而非通用 CommonMark 实现。

## 轮 8（收敛检查轮）终局处置

第八轮独立 review+challenge（chain `pr76-review-fix-r8-20260830`，packet sha256 `a309008f…`）各 1 条 P1，均落在已文档化的处置类内，按轮 7 收敛声明作 documented-accept，候选 diff 不再变更：

- R8-P1 字母分隔拆分（`123456789x123456789`）：即残余通道 (b)，轮 3 起已记档。评审提出的「合并字母段 + 实例白名单」是从 shape-allowlist 到 instance-allowlist 的策略重设计（每次新引用都要改闸），且合并字母段会使真实控制样本 `s15516709cog1202_4`（字母合并后 13 位）转红。取证：`rg -q '[0-9]{8,}[A-Za-z][0-9]{8,}' skills/*/SKILL.md skills/*/references/*.md` 无命中。
- R8-P1(challenge) 引用标记后 tab 的列偏移（`>\tMUST…` 被过度遮罩）：已清扫容器类的 tab 变体；方向是过度遮罩（若命中真实义务 carrier 会让 audit 响亮失败而非静默通过）。取证：`rg -q $'>\t'` 在 masker 语料无命中，真实语料八轮字节稳定。

本记录即两条发现的 disposition 工件；第八轮评审绑定的候选（packet `a309008f…`）与落地 diff 一致。

## 整合轮 downscope 声明

- downscoped:PR76-INTEGRATION-TRIM-NO-BANK-RERUN — 整合轮对 `terminal-cli-dev` 的唯一路由面改动是把 description 里冗余的短契约枚举并入完整枚举（预算修复，831→785 字符）；四条 mapping carrier 句逐字保留，audit 全绿。`Node.js CLI → nodejs-service-dev` 分流腿随其原轮（bank task `route-nodejs-cli-not-terminal`）落地并由该轮行清偿。纯措辞收缩不改变任何路由判定输入的语义类，故本轮不重跑 routing bank；如后续路由测评显示该 trim 影响选择，按常规回归处理。

## 已知残余风险 / 有意不修（待作者裁决）

- 065 语义层：WCAG 2.2 SC 摘要与 APCA 指引的删除在 ledger 里记为 `retired-dead`+`strengthened`（schema 规定的词表），以及 row 175 的 rehost 主张是否应改为显式 retirement——是 065 实质裁决，不属本修复轮。
- `test_uiux_loading_budget.sh` 的 90% 上限当前余量为 0 字节且钉死 magic SHA——改为绝对上限或 merge-base 基线是策略变更，不属本修复轮。
- 真仓 `audit` 仍未接入任何 CI lane（`test_obligation_ledger.sh` 仅跑合成 fixture）；已在 `validation-evidence.md` 补记人工重跑义务。
- `register-firing-path-resolution.rb` 的 EXEMPT waiver 表与新增 suite 的 fast-lane 耗时为评审观察项，未在本轮改动。
- 数字洗白残余通道（两条，均为 shape 允许的构造性拆分；原 (a) registrant 通道已被轮 5 的 payload-区间收窄关闭）：(b) 字母作分隔符（`123456789x123456789`）不参与合并——桥接字母会误伤真实 DOI（`s15516709cog1202_4`）；(c) 全部 <8 位的数字组拆分（`1234567+1234567`）低于全闸的连续 `[0-9]{8,}` 检测下限，prose 与 URL 同等不可见，收紧会误伤含多个小数字组的常见真实 DOI（Lancet/SICI 形态）。进一步封堵需语义校验（在线 resolver），超出确定性 lexical 闸的边界，留作策略裁决。
