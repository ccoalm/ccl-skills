# 065 — UI/UX 证据与交付闭环重构

## 目标

让 `product-ui-ux-design` 在真实设计任务中同时改善四个结果：

1. 更早产出可验证的设计判断，不用抽象理论口号代替问题分析。
2. 只加载当前任务需要的参考材料，减少入口和默认清单的重复上下文。
3. 让设计、测试和客户端实现形成一条双向交付链，而不是互相点名后各自结束。
4. 按主张区分源码、自动检查、渲染、用户研究和上线结果，避免把一种证据替代另一种后错误完成。

候选基线固定为 `origin/dev@e322db47abe5736e6e1fdf0e73e2ed3eb32c006b`。本轮不改 `product-ui-ux-design` 的路由 description；只为补齐 CLI 所有权与联动改写 `terminal-cli-dev` description。不改产品代码，不发布、推送或合并。

## 已核证据

### 理论与规范

| 证据等级 | 来源 | 可采用机制 | 边界 |
| --- | --- | --- | --- |
| 规范 | [ISO 9241-210:2019](https://www.iso.org/standard/77520.html) | 人本设计活动贯穿交互系统生命周期 | 标准给原则和活动概览，不指定唯一方法 |
| 规范 | [ISO 9241-11:2018](https://www.iso.org/standard/63500.html) | 可用性是具体用户、目标和使用情境中的结果 | 不提供具体设计或评估流程 |
| 情境实证 | [Sweller 1988](https://doi.org/10.1207/s15516709cog1202_4) | 手段—目标搜索在该组问题求解/学习实验中占用认知处理容量 | 研究对象主要是学习和问题求解，不能直接推出通用 UI 配方 |
| 概念框架 | [Norman 2008](https://jnd.org/signifiers-not-affordances/) | signifier 为用户提供理解状态、可能动作和结果的可感知线索 | 作者论述给概念框架，不是比较 UI 方案的受控实证；也不要求同时展示所有选项 |
| 情境实证 | [Tversky、Morrison、Bétrancourt 2002](https://doi.org/10.1006/ijhc.2002.1017) | 动画应匹配要表达的变化，并允许用户准确感知 | 动画不天然优于静态表达，复杂或过快会降低理解 |
| 情境实证 | [Faulkner 2003](https://doi.org/10.3758/BF03195514) | 样本数按研究风险和问题异质性决定 | 五人组发现比例在该研究中为 55%–99%，不能把“五人”当固定完成线 |
| Web 规范 | [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | 可测试的无障碍成功标准 | 不覆盖所有残障用户需求，也不等于一般可用性验证 |
| 信息性指导 | [ARIA APG introduction](https://www.w3.org/WAI/ARIA/apg/about/introduction/) | 常见交互语义和键盘模式可作实现参考 | APG 明确不是完整设计系统或 production-ready 代码 |
| 信息性指导 | [W3C：结合用户评估与标准](https://www.w3.org/WAI/test-evaluate/involving-users/) | 标准核验和残障用户评估互补 | 单个用户不能代表整个群体，用户评估也不能单独证明 WCAG 合规 |
| 厂商约定 | [Android accessibility guidance](https://developer.android.com/guide/topics/ui/accessibility/apps) | Android 触控目标建议和语义实现约定 | 48dp 是 Android 平台建议，不是跨平台理论常数 |
| Community Group report | [Design Tokens Format Module 2025.10](https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/) | 设计 token 的跨工具交换、类型和 alias 契约 | 文档明确不是 W3C Standard、也不在 W3C Standards Track；格式互通不证明视觉质量或治理有效 |

### 当前技能与实现证据

- `product-ui-ux-design/SKILL.md` 为 40,850 bytes、5,533 words；默认加载的 `design-execution-checklist.md` 另有 24,550 bytes，并重复实现检查点与验收义务。
- 设计技能已点名 `testing-strategy` 和 Web、App、小程序、终端 owner，但协议分散在六个入口文件，测试技能的输入与设计检查点互相等待，缺少统一阶段顺序。
- 当前参考把 Hick、Fitts、Miller、Doherty 写成直接 UI 规则，并以“五秒”作为通用视觉验收阈值；这些表述超过原始证据能支持的范围。
- 最新私有前端静态读取只产出待验证的可泛化机制候选：按影响范围/恢复/终态/重试安全分类错误；用组件 API/类型承载稳定视觉与无障碍不变量；保留有草稿/焦点/滚动的状态核心；维护可预览状态目录；自动化少量高成本确定性不变量；记录门禁覆盖边界；把 token/story/测试文件“存在”和真正执行、渲染、上线结果分开。它证明源码、测试文件或 CI wiring 存在，不证明这些机制已执行、正确渲染或改善产品结果。具体仓库、组件、状态名和品牌信息不进入共享树。
- 私有前端也显示反例：故事、测试或规则文件存在，不等于它们已接入 CI；静态源码不能证明实际渲染、恢复行为或线上结果。

## 设计决定

### 1. 主干只保留决策骨架

`SKILL.md` 保留触发边界、核心闭环、硬规则和稳定 reference 指针。默认流程为：

1. 用户、任务、情境与约束简报。
2. 测试 Phase 0 根据状态、流程、风险和设计假设选择断言层、渲染/设备证据与充分性规则。
3. 每个变更或支撑结论的生产者与受影响客户端分别实现、实跑并回传自己的不可变候选成员。
4. 测试 Phase 1 聚合 design/test/producer/client 集合，判 criterion 结果与证据充分性。
5. 设计 owner 根据同一绑定集合给 verdict、限制和复测条件。

### 2. 一份跨技能交付契约

新增 `product-ui-ux-design/references/delivery-contract.md`，作为设计、测试、生产者和客户端技能共同引用的唯一协议：

- 设计 owner 定义用户任务、状态、风险、差异分类和验收结果。
- `testing-strategy` 在 Phase 0 选择断言层、自动检查和渲染证据层，在 Phase 1 聚合执行结果并判充分性；不代替视觉/交互判断。
- 每个 backend/config/content/inference producer owner 回传被客户端实际使用的 artifact/version 和运行事实。
- 每个受影响客户端 owner 选择框架约定、入口、运行方式和证据采集机制，并回传自己的实际结果；其它 Web、桌面/TV 和其它端必须走已安装 owner 或 fail-closed project-convention lookup，复合宿主分层记录。
- 设计 owner 根据绑定候选的证据记录 `accepted`、`rejected` 或 `pending`。
- `candidate` 自评、静态源码、lint、组件测试和单张截图都不能单独升级为最终验收。

### 3. 理论写成可证伪判断

每条建议使用统一形态：

`观察 → 风险 → 设计假设 → 验证证据 → 适用边界`

不用人名定律代替机制，不把厂商数值写成跨平台常数，不把启发式检查写成完成门禁。

### 4. 按主张匹配证据维度

来源/意图、静态实现、自动验收、渲染/设备运行、代表性任务/用户和线上结果回答不同问题，不构成一条可互相替代的全局阶梯。每条结论先列所需维度，再逐项闭合；生产结果不能证明标准符合性，标准符合性也不能证明用户成功。自动门禁仍需记录检测对象、扫描范围、已知漏检和剩余人工/运行核验。

### 5. 实测上下文变化

基线入口 `SKILL.md` 为 40,850 bytes；当前候选为 17,850 bytes，减少 56.3%。基线入口加默认 checklist 共 65,400 bytes；当前入口加条件 router 为 29,645 bytes，减少 54.7%。普通运行态任务直接加载入口与 41,010-byte canonical contract，共 58,860 bytes，比旧默认组合少 10.0%；需要 specialized router 的任务共 70,655 bytes，比旧默认组合多 8.0%。因此优化点不是“所有任务总字节都更少”，而是入口定位更短、普通路径不再先读 router、专业任务为更完整的跨 owner 契约支付额外上下文。真实模型测评必须把质量与耗时分开报告：当前小样本显示质量改善，但未显示稳定的端到端时延改善。数值由 `test_uiux_loading_budget.sh` 对不可变基线和当前工作树实测，候选变化后必须重算。

### 6. 修复 routing bank 的 owner 解析

本轮 CI 暴露出共享门禁自身的缺口，分类为 `gate implementation`。`impact-chain-gate.rb` 只为 impact-chain 的可选 owner 建证据索引，却用这份索引核对所有技能 description 的 routing-bank 证据。结果是两种错误：已提供有效证据的非可选 owner 必然被拒；仅修改该类 owner description 且不写台账时，外层入口又可能完全不执行。

修复只拆出 routing-bank 专用的 owner 解析，不把 `terminal-cli-dev`、`web-react-dev` 等 owner 加进 impact-chain 集合，也不改变正文编辑、现有可选 owner 或 routing-bank 文件本身的判定。

| 输入 | 期望 verdict | 证明方式 |
| --- | --- | --- |
| 可选 owner description 改动，且同轮 owner 行含有效 `bank-evidence` | pass | 保持现有 A1 用例 |
| 非可选 owner description 改动，且同轮唯一 owner 行含有效外部 locator | pass | 新增正向 fixture；修复前必须因 owner 行不可解析而 RED |
| 非可选 owner description 改动，但同轮没有台账行 | fail：`impact_chain_bank_evidence_missing` | 新增零台账 fixture；修复前错误通过，修复后转 RED |
| 两个非可选 owner description 同轮改动，一行同时绑定两者 | fail：逐 owner 欠证据 | 新增歧义 fixture，防止一行替两个 owner 清偿 |
| 非可选 owner 只改正文 | pass | 保持 round-attribution Leg M，通过它证明未扩大 impact-chain 管辖面 |
| 只改 `eval/routing-tasks.jsonl` 且无证据 | fail：`impact_chain_bank_evidence_missing` | 保持现有 A8/A9 用例 |

测试登记：先在 `test_impact_chain_self_adjudication.sh` 加前三个非可选 owner 场景并取得 RED，再修改 gate；随后运行 self-adjudication、round-attribution、verdict-differential、reference-script 和仓库全量 lane。状态同步目标是本计划、`source-register.md`、`validation-evidence.md` 与当前 PR。实现者自审完成后，优先用 Kimi 对最终 gate/test diff 做一次独立对抗评审；若 Kimi 超时或无有效结论，则按既定 fallback 使用 Codex，并把同族残余风险和逐 finding 处置一并留痕。评审后若候选再变，重新自审、评审和相关验证。

## 义务保留索引

下表只用于浏览，不作为零损证明。完整 comparison domain 是基线中每个本轮改写的 `skills/**/*.md`，再加所有 relocation destination；对每个 pre-existing 文件运行 `governing-chain-diff.py`，机械派生 row set。[obligation-mapping.jsonl](obligation-mapping.jsonl) 是人工复核的 canonical mapping，[obligation-preservation.md](obligation-preservation.md) 只由它生成，审计要求 row set、mapping 与 projection 双向闭合。入口的 304 行和旧默认 checklist 的 240 行只是核心子集，不是完整分母。每行必须记录旧链、限定词、合法 disposition 和 `preserved` / `strengthened` / `unresolved`，并绑定一个当前精确载体；只有旧义务本身可机械拆成多个独立规范子句时，才允许用人工复核的载体集合逐子句闭合覆盖。载体集合必须给出无遗漏、无重复的子句分区，并分别保留每个子句的 actor、scope、modality、时序和结果限定。主题相似、模糊匹配或把拆散内容重新抄成一段“桥接文案”都不能替代逐项证明，`unresolved > 0` 阻断完成声明。

| 现有义务 | 新载体 | 处置 |
| --- | --- | --- |
| Figma/代码来源分级、历史源不得升格 | `SKILL.md` + `source-map.md` | 保留，入口压缩为硬规则与指针 |
| 运行态可见改动必须有设计检查点 | `SKILL.md` + `delivery-contract.md` | 保留，字段只在契约定义一次 |
| 测试 owner、各端 owner 与可能产出客户端可见内容的 Go/Python/推理 owner 必须提供具体选择，不得只点名 | `delivery-contract.md` + 各 owner 的本地职责指针 | 保留并消除循环依赖 |
| copy-only、backend-only、unknown-consumers 分流 | `delivery-contract.md` | 保留 |
| 重设计触发、RED baseline、状态矩阵、行为差异、渲染证据 | `delivery-contract.md` | 保留，合并进五阶段交付记录；旧称只作迁移别名，不再复制字段表 |
| rejected surface 不得继续小补丁冒充完成 | `delivery-contract.md` | 保留 |
| 已指定状态按设计源做 conformance，不用自我确认替代 | `delivery-contract.md` | 保留 |
| 同类缺陷发现后扫 sibling，检测范围与修复范围分开 | `SKILL.md` | 保留；全量检测、只修 in-scope/已迁移面，其余记 owner，连续复现视为前次 under-sweep |
| 证据需持久化、脱敏并绑定最终候选 | `delivery-contract.md` | 保留 |
| 高风险、乐观更新、AI、快捷键、终端约束 | 对应 focused reference，由 router 按触发加载 | 保留，不再默认展开 |
| 产品密度、视觉方向、状态、组件、token、copy 检查 | `design-execution-checklist.md` 路由到 focused references | 保留，删除重复正文 |
| 平台规范与外部理论 | `external-ui-ux-quality-benchmarks.md` | 更正证据等级和边界；撤回无一手支撑的强断言。上一轮 25 条 HIG/Material 混合走查被证据分类 ledger 取代，三个历史 locator 由行摘要绑定的显式 waiver 保存历史，不伪装成仍生效 |
| 跨技能交接状态 | `delivery-contract.md` 与 design/testing/client/product-rd 文档 | 统一为 `candidate` / `accepted` / `rejected` / `pending`、`complete` / `pre-runtime-test-ready` / `design-rejected` / `blocked`，删除空格版同义枚举 |

## RED 基线

`test_uiux_delivery_contract.sh` 在未改设计文档的 `origin/dev` 基线退出 1，并逐项报告：

- 缺少 canonical delivery contract。
- 设计 router 与 testing、producer 和各类客户端 owner 缺少共同五阶段指针或完整返回义务。
- 任意“五秒”验收阈值及无证据边界的人名定律式提炼仍可作为完成规则。
- 候选绑定、owner 全集、终态闭集和可达 reference 的独立完成路径没有被约束。

改后同一测试必须转绿；删除共同指针、阶段、角色成员、候选绑定、终态或理论边界，缩窄 owner/触发集合，把义务藏进注释/代码示例，或追加第二套完成规则，均应再次转红。

## 验证

可复算的 RED→GREEN、killing mutation、最终候选绑定和命令矩阵统一记录在 [validation-evidence.md](validation-evidence.md)。本页不复制进行中的结果，避免旧候选的全量绿与新候选的待重跑状态并存。

已完成的早期审查不是最终通过：首轮独立 review/challenge 找到循环 criteria ownership、不可达 copy-only 路径、开放式终态组合、可变 branch 证据、消费者全集漏查、弱 literal gate、逐义务证明缺失、逐屏深度丢失、漏建 pre-edit 记录无补救、source-register 证据不足、render sibling 只 grep、owner lookup 假绿和历史 waiver 缺反例等问题。当前契约与门禁已逐项修正；只有最终冻结候选再次通过全量验证和独立双 lane，才能把它们记为 closed。

验证环境处置不冒充产品修复：系统 Python 缺少测试依赖时按仓库 `requirements-test.txt` 使用隔离 venv；默认沙箱禁止 `ps` 或写 `.git/worktrees` 时，只把它记为环境阻断，并在允许对应只读/临时 Git 操作的环境重跑。任何先前候选的通过都不能替代最终候选重跑。
