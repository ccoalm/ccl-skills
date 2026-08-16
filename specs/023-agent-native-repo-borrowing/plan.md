# 023 — 对标 agent-native 产品仓的开发纪律：借鉴沉淀轮（batch I–III + 待裁决 IV）

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 关闭一个源类缺口：ccl 的规则几乎全部来自内部纠错复盘（friction-biased digest），外部对标只做过技能包（superpowers / gstack）；"被 agent 大量参与开发、且把开发纪律整套开源的产品仓"从未列为源类，导致 agent 写文档 / 写测试 / 做评审 / 挖评审意见时的一批已被业界识别的病（会话视角泄漏、自述当证据、源码路径当真实入口、评审意见"已修"当采纳）在 ccl 缺席或只有零散一句。本轮把第 2 轮候选台账（A1–E5，会话 scratchpad `dsh-extraction-ledger.md`）中低争议、纯 merge 的候选落进各 owner；C3（SKILL.md 词数预算 validator）单列 batch IV 等维护者裁决。 |
| Artifact classification | `shared-skill non-wording text`（多 owner 规则文本 merge，无脚本、无 gate 语义变更、不改任何 `description`/frontmatter → 不触发 routing gate；仅 skill-extraction 新增 1 个 reference 文件 + `SKILL.md` 内 1 句 source-class 措辞）。feature-risk-router 定级：`shared-skill`（跨 7 个 owner）+ `no-routing-surface`；security-review 变更臂：**D3（权限边界不在 schema/prompt 层）、D4/D6（沙箱范围词汇、子进程环境清洗）、E5（受控提权分流）为 security-sensitive**——各自落地前必须走 feature-risk-router security-review gate，并在本 plan 判定表与 source-register 行记录具名安全 owner 的处置（approve / narrow / reject）；其余候选 not-applicable（无执行面、无凭据/权限语义变更）；D1 因触及敏感内容持久化语义已移出本轮落地范围（batch V，需具名安全 owner 参与的独立设计，见批次表）。 |
| Scope | in：candidates A1 A2 A4 B1 B2 B4 B5 B6 B7 C1 C2 C5 D2 D3 D5 E1 E2 E3 E4 E5 → owners `testing-strategy` / `llm-inference-integration` / `tighten-doc` / `product-rd-workflow`(adr-convention, code-review-checklist, implementation-completeness-and-minimality) / `defect-diagnosis` / `worktree-isolation` / `skill-extraction-workflow`；本 plan；source-register 行。out：C3 词数预算 validator（batch IV，需裁决）；D1 model-visible/日志账目不变量（batch V，需具名安全 owner 的独立设计——023-plan-r4/r5/r6 三轮同类 P1 后按同类复发规则移出）；A3（dsh implemented 记录随事实更新 vs ccl immutable+as-built——记为已知差异不引入）；三语配对 gate、Cordis/invariant 伴生插件、Agent Note 路径编码与归档 manifest（产品/规模特定）；任何 `description` 改动；任何 dsh 具体名词（`dsh-*` / Cordis / 包名 / 文件名）进入可执行文本。pending-verify 行（B8 / C4 / D4 / D6）在各 batch 全文读 owner 后就地关闭为 covered / merge / discard，不新开范围。 |
| Depth | Node/artifact inventory 已完成（第 2 轮：dsh AGENTS.md、docs/AGENTS.md、.agents/notes 制度、.agents/skills 6/11、testing.md、defensive-patterns、postmortem 制度、human-review-skill-maintenance note；ccl 侧为定向 grep + 段读）→ 本轮升为**每个 owner 目标段全文读**后再 merge。 |
| Root cause | (1) source-register 无"外部 agent-native 产品仓治理层"源类；(2) 第 1 轮只读 digest（README/官网）——digest-masks-corpus 实例；(3) 触发依赖用户追问"哪些可借鉴"。 |
| RCA analysis | widen：(a) 源类缺失（必要因；反事实：源类存在则任何"对标外部"轮会枚举到它）；(b) digest 陷阱（放大因；反事实：第 1 轮读到 code corpus 就会在同轮发现 `.agents/`）；(c) 检测缺口——无 gate 要求 benchmark 轮列出对标对象类别。控制：源类行本轮落 source-register；skill-extraction 的 benchmark 规则补"对标对象含 agent-native 产品仓"一句（batch III）。 |
| Failure mode analysis | (1) 抄术语——dsh 词汇（seam / Cordis / dsh-* / Agent Note）进可执行文本 → R0 + 对抗评审；(2) 把 evolving 仓的做法当 best practice → 每条以"业界形态之一"措辞落地，不写"标准做法"，附外部锚点仅限已在 ccl 存在的（Nygard ADR、SRE postmortem）；(3) 追加 bullet 而非 merge → 每 owner 先读全文、定位既有同类规则、改写它；(4) 例子集源形状泄漏 → C1 的例子做 example-domain 预选（`(decision 7)` / `T4` / `§4.7` 形状通用可用；不复制 dsh 的具体句子）；(5) 落地过程本身成为下一个"未沉淀"——本 plan 即轮记录，闭环写回 source-register。 |
| Lifecycle impact | testing（B*）、implementation（D*、E3）、debugging（A4）、review（E2、C1 指针）、iteration/onboarding（A1 A2 C2）、team-process（E1、E4、E5、C5）、LLM 运行时（D2 D3、B6；D1 已移出）；product intent / design / release：not-applicable（dsh 无对应纪律可见）。 |
| Evidence plan | 已产：dsh 源文件逐条摘录（台账）；ccl 侧定向 grep。待产（每 batch）：owner 目标段全文读记录；draft diff；sibling mini-map；R0 `check-ccl-skills.sh` 输出；dual-track（review + challenge）链记录；behavioral-evidence 行（每 owner 至少一条 semantic-control：改前后对同一任务形状的输出差异，或 RED-baseline 若某规则可用 eval task 复现）；source-register 行。 |
| Completion standard | 全部 in-scope 候选每条有终态（landed / merged-into / covered / discarded-with-reason）且 diff 与 target-output map 逐行一致；pending-verify 行零残留；`check-ccl-skills.sh` clean（R0 `private-ok` 或 interim 标注）；dual-track 无未处置 P0/P1；source-register 行落树；合 dev 候用户显式指令；batch IV / V 单独等待裁决与设计，不阻塞 I–III。 |

## 批次划分（按问题域，非时间片）

| Batch | 域 | 候选 | owner 与目标文件 | 独立 dual-track 链 |
| --- | --- | --- | --- | --- |
| I | 测试证据 + agent 运行时契约 | B1 B2 B4 B5 B7 → testing-strategy；B6 D2 D3 → llm-inference-integration；关闭 B8 D4 D6 pending-verify | `skills/testing-strategy/SKILL.md`（core rules 对应条目就地改写）+ 需要时 `references/ci-fixtures-and-flake-control.md`；`skills/llm-inference-integration/references/agent-session-persistence.md`、`references/agent-tool-dispatch.md`、`references/agent-command-sandbox.md`、`SKILL.md` 指针 | `023-I` |
| II | 文档散文 + 决策记录 + 评审 + git 操作 | C1 C2 → tighten-doc；A1 A2 → product-rd adr-convention；E2 → product-rd code-review-checklist；E3 → product-rd implementation-completeness-and-minimality；A4 → defect-diagnosis；E4 → worktree-isolation；关闭 C4 pending-verify | `skills/tighten-doc/SKILL.md`（新小节"session-vantage leakage"或并入既有 DELETE 列表）；`skills/product-rd-workflow/references/{adr-convention,code-review-checklist,implementation-completeness-and-minimality}.md`；`skills/defect-diagnosis/SKILL.md` postmortem 段；`skills/worktree-isolation/SKILL.md`「落后就先更新」段的 force-with-lease 条 | `023-II` |
| III | 提炼工作流自身 | E1（新 reference `review-feedback-mining.md`）；C5 → rule-consolidation.md；D5 → harness-patterns-and-eval.md（业界形态记录，非规则）；benchmark 源类一句 → `SKILL.md`；source-register 行（本轮 impact-chain 行 + 源类行） | `skills/skill-extraction-workflow/{SKILL.md,references/*}` | `023-III` |
| IV（待裁决）| SKILL.md 正文词数预算 validator | C3 | `skill-extraction-workflow/scripts/` + manifest；先过 design-time 四腿检查（author-dogfood：现有 SKILL.md 多数会红→需 baseline 冻结策略；marginal-cost；trust-model；premise）| 裁决后另开 spec |
| V（待设计）| 模型可见内容与事件日志的账目不变量 + 受控提权验证 | D1 E5 | `llm-inference-integration/references/agent-session-persistence.md`、`skill-extraction-workflow/references/source-to-skill-extraction.md#blocked-verification`；前置：具名安全 owner（由 feature-risk-router security-review gate 指定并在 spec 内记录其批准）参与设计——需覆盖凭证/敏感载荷不持久化、可重建 vs 显式不可重建的分类、低熵值摘要可枚举（不得记内容摘要，或用独立保管密钥的 keyed MAC 并写明威胁模型）、引用目标不可变版本化且与日志同保留/访问策略，以及沙箱阻断分流与受控提权 | 另开 spec，附具名安全 owner 批准为完成条件 |

每 batch 内循环：owner 目标段全文读（记录行号范围）→ draft（merge 进既有规则）→ sibling mini-map → sanitize（R0 + example-domain 预选）→ dual-track（review + challenge，`code-review` 技能 wrapper）→ 处置 P0/P1 → `check-ccl-skills.sh` → 一批一 commit（`git -C` 绝对路径）→ 更新本 plan 的判定表 trace。

## 每候选落地意图（drafting 输入，非最终措辞）

| # | owner / 段 | 落地意图（merge 目标） | 处置预期 |
| --- | --- | --- | --- |
| B1 | testing-strategy 核心规则 "Classify test evidence quality" 邻近 | 增：对 agent/自动化产出的验证，断言外部世界（重跑命令 / 重读文件 / 未触碰文件字节一致），不接受对产出自身的关键词探测为证据；指向 multi-agent-delegation 同款 | merge |
| B2 | testing-strategy "smoke real critical path" 条 | 增："已发布产物即真实入口"——构建产物 / 安装后入口 / 真实 loader 至少一条 smoke；源码路径（dev runner / hot loader）会掩盖 settle race 与吞掉的加载失败 | merge |
| B4 | testing-strategy 覆盖门 / 变更探测条 | 增：覆盖门下未覆盖行先问"删不删"再问"补不补"；行覆盖必要不充分 | merge 一句 |
| B5 | testing-strategy test-double 条 | 增：mock 只到昂贵 / 非确定边界（模型、网络、时钟），边界内下游用真实现；手搓替身只证明桥接搬字节 | merge |
| B7 | testing-strategy runner-config policy / evidence 条 | 增：evidence-to-surface 选择（行为→focused test；模型/用户可见输出→snapshot；文档→doc gate；发布路径→build+built smoke；外部 provider→real e2e）；本地不默认全量、CI 拥有穷尽；报告只列实跑命令；**已过检查可复用的前提是被测 commit/树与相关依赖、环境输入未变且有记录**——amend / rebase / 重生成 / 改配置之后受影响的检查必须重跑，不得以旧绿当 push 证据 | merge（与既有"CI 权威"措辞合并）|
| B8 | testing-strategy ci-fixtures 参考 | 全文读后判：e2e 资源归测试自己（afterEach 释放含失败/超时）；共享 fixture 放 plain 模块不 import 另一 spec | pending-verify → covered/merge |
| B6 | llm-inference-integration eval/replay 段 | 增（收窄）：推理便宜或自有模型时，real-model smoke 是一等 tier，keyless 只证明管道；self-skip 是无钥匙保护不是成本信号；第三方不可控模型仍按 testing-strategy weak 判定 | narrow + merge |
| D1 | （移出本轮 → batch V）| 023-plan-r4/r5/r6 三轮同类 P1（凭证持久化 → 可变引用 → 低熵摘要可枚举 + 安全 owner 不具名）触发同类复发规则：不再原地补丁，整体移出 batch I，另开需具名安全 owner 的设计 spec；本轮 agent-session-persistence.md 不改 | held（narrow→defer）|
| D2 | agent-tool-dispatch.md / prompt 段 | 增：模型面契约从模型视角写（只含任务概念，不含 UI/传输/实现词汇）；措辞即行为——稳定文本逐字 pin，改措辞走 snapshot/eval | merge |
| D3 | agent-tool-dispatch.md 权限/工具段 | 增：schema 省略、prompt 过滤、facade、监听顺序不是权限边界；拒绝路径在执行器测；指向 testing-strategy enforcement 矩阵 | merge |
| D4/D6 | agent-command-sandbox.md | 全文读后判：沙箱模式词汇明示范围（文件效果 vs 网络/进程）、enforcement 是"报告的事实"（full/partial）；子进程 scrubbed env / 私有临时目录 / link-shaped path 用 lstat+unlink | pending-verify → covered/merge |
| C1 | tighten-doc SKILL.md（DELETE 列表邻近或新小节） | 增"会话视角泄漏"类：死的设计会话引用、stack/PR 视角、变更叙事与版本戳、评审编排、对评审者辩护、推导流水账、hedge 残留、工作语言碎片；判据 = HEAD 读者无会话访问能否解析每个引用；修法先重述事实再删；过矫正陷阱（issue 引用 / suppression 理由 / 反事实现在时 / 测量值不删）；例子做 example-domain 预选 | merge |
| C2 | tighten-doc DELETE 列表 | 合并：durable prose 写现状不写变更史（previously/now/no longer/PR/commit）；实现状态注记；强调通胀；每事实一个家其余链接 | merge（不抄 dsh tier 表）|
| C4 | tighten-doc | 全文读后判："scope 缺失即停、不推断仓级"是否已有 | pending-verify |
| A1 | product-rd adr-convention §3 / §5 | 增：Alternatives considered 必填且"只记录不编造"（无法重建时显式标注）；同 PR 附决策记录的触发已在 §5.1，核对措辞是否覆盖"非平凡改动"而非仅架构级——按 ccl 既定 WHEN 判据不放宽 | merge 窄 |
| A2 | adr-convention §5.3 | 增：归档=冻结不删；Rejected 保留判据 = 仍能阻止一个诱人的错误，否则可清；不按字数/年龄/配额 | merge 窄 |
| A4 | defect-diagnosis SKILL.md postmortem 段（现 blameless / Swiss-cheese 条附近） | 增：正式 postmortem 判据 = subtle + systemic + costly-to-rediscover 同满足；开头 30 秒执行摘要；必须回链它催生的 guardrail（测试/规则/记录） | merge |
| E2 | product-rd code-review-checklist | 增两评审维度（agent/LLM 类改动）：模型视角（模型实际收到的 prompt/schema/结果/诊断）；enforcement 追到执行器（直接/替代调用者能否绕过）；"一条有据 blocker 胜过 nit 列表"若既有条已含则 unchanged | merge |
| E3 | product-rd implementation-completeness-and-minimality | 增：删除前 consumer 三分类（production / non-production / ambiguous corpus）；"只有测试/文档消费"= 强候选；对且小 → 带稳定 tag 的 TODO 而非记录 | merge 窄 |
| E4 | worktree-isolation 「落后就先更新」force-with-lease 条 | 增：重写前记观察到的远端 OID 并 `--force-with-lease=<branch>:<oid>`；重写后重 fetch 并重审 review threads / approvals / checks（旧 hash 与行内评论锚点不再是当前证据）；无法在重写与发布之间验证的工具→事后立即验证并 hold merge | merge |
| E1 | skill-extraction 新 reference `review-feedback-mining.md` + SKILL.md Reference Loading 一行 | 采纳证据纪律：只取 human-authored 且被采纳；采纳 = 反馈时刻补丁 vs 最终落地补丁（merge / resolved / "fixed" 回复 / 同文件编辑都不算）；无法重建基线 fail-closed 为 unclear；独立评审器分类+起草+审同一 diff；singleton 可成立；对当前技能幂等（covered 不再进候选）；"无候选"是常态；操作者裁决、不逐字提交模型输出；agent-quality 指向 | new reference |
| C5 | rule-consolidation.md | 增：临时性规则须写明退役触发条件（"X 发生时删除本节"）| merge 一句 |
| E5 | **held（待维护者安全处置）** | 起草意图不变（先分流沙箱阻断 vs 真实失败；提权只对已审阅可信命令、只授被阻断能力、须宿主策略与用户批准；不作默认动作；不绕过真实失败），但本轮**不落地**——判定表第 10 行要求安全 owner 处置，执行 agent 不得自任 | held |
| D5 | harness-patterns-and-eval.md | 增一段"插件式 harness 形态"业界记录（无特权核心、能力三角、事件即扩展点、profile/bundle 分层），标注为形态记录非执行规则、evolving 来源；**不含任何日志/持久化表述**——凡涉及模型可见内容与事件日志的内容一律归 batch V（按 023-plan-r7 challenge P1）| route（记录，无日志措辞）|
| 源类 | skill-extraction SKILL.md benchmark 规则（"A deep review / benchmark of the skill repo…"）| 一句：对标对象含被 agent 开发的产品仓的治理层（AGENTS/notes/repo skills/testing policy），不只技能包 | merge 一句 |

## 判定表（validation cases；trace 在执行时回填）

| # | 输入 | 预期 | trace |
| --- | --- | --- | --- |
| 1 | 每 owner 目标段全文读 | 记录文件 + 行号范围 + 既有同类规则定位（merge 点） | done：Batch I 读取 testing-strategy 与 llm-inference-integration 的入口及相关 references；Batch II 读取 tighten-doc、product-rd-workflow 三个目标 reference、defect-diagnosis 与 worktree-isolation 的现有同类段；Batch III 读取 skill-extraction-workflow 入口及 review mining / consolidation / coverage / harness 相邻 references。D3、D4、D6 判 covered，C4 判 covered，B8 判 merge；E5 保持 held |
| 2 | draft diff vs 台账 | 每候选一个 merge 点，零新增顶层 bullet 除非无既有同类规则（记录理由） | done：现有同类规则均就地合并；只在没有既有承载面的 session-vantage、review-feedback-mining 与 cross-model caveat 新建 reference。入口增长用既有 reference 指针压缩抵消；未引入新的 description/frontmatter 路由面 |
| 3 | R0：`scripts/check-ccl-skills.sh` @ 候选 | `ccl_skill_check_clean_ok`（r0_status=private-ok）或 interim 标注；grep `dsh\|Cordis\|deepseek\|Agent Note` 于变更文件可执行文本 = 0 命中（provenance 段除外） | Batch I @ 8713cf4：`ccl_skill_check_clean_ok`、`r0_status=private-ok`、`entrypoint_size_blocking_ok`、impact-chain 行齐；leakage grep 0 命中 |
| 4 | dual-track chain 023-I/II/III | review + challenge 各 ≥1 轮，终轮为对最终候选的 fresh full challenge；无未处置 P0/P1 | 历史各 batch 链见下。Kimi 对候选 `dd52ab3` 的完整 diff 初审产出 1×P2（CI blocking-job 限定只留在懒加载 reference），已接受并在 `8de5167` 把承重限定恢复到 testing 入口；合并前对含修复、rebind 与本 plan 的最终完整 diff 再执行 fresh Kimi review + challenge，仓外原始 artifact 为权威，任一 finding 或无效终态均阻断合并 |
| 5 | behavioral-evidence | 每 owner ≥1 semantic-control 行；仓库 impact-chain gate 要求非措辞 owner 至少一条 RED-baseline 行；runner 必须对 provider 非零退出与空输出 fail closed | done。register 回填 run（base=`759dc603`、head=`fb41e11b`）保留为对应行的原始 truth；最终 evidence 均为 provider=`codex`、model=`gpt-5.6-luna`、4 rounds/arm，且持久化 regex source + flags，可从 raw 独立重评分。Kimi 修复后 Batch I 重新绑定 base=`31d3b3f`、head=`17b3231`：ts-verify-world **0/4→0/4**、with-key **4/4→4/4**、wording **0/4→4/4**；Batch IIb alternatives 独立最终文件绑定 `17b3231` 为 **0/4→4/4**，consumer corpus 的 prompt inputs 从 `f4e03ed` 到 `17b3231` 逐字节相同，保留原 **0/4→1/4** 与原 revision；Batch III review mining 绑定 `17b3231` 为 **4/4→4/4**。其余未触及输入仍绑定 `f4e03ed`：Batch II session-vantage **3/4→4/4**、enforcement **4/4→4/4**、postmortem **0/4→4/4**；Batch IIc lease **0/4→3/4**。全部有效调用均有非空 raw、无 ERROR；consumer 补跑因 21 分钟仍无首条输出以 exit 130 终止，不计为证据；无差分与弱差分原样保留 |
| 6 | 例子集（C1）| example-domain 预选记录：选定中性域、抽象记录拒绝的源域、核对的例子清单 | done：F22/F23 使用通用文件搜索与部署域；F24–F27 使用通用 ADR、事故、git 重写与公开 API 删除域；拒绝源仓专名、包名、文件名。F0-contract 明示语料仅人工 advisory，分数引用已改绑 fail-closed provider 结果 |
| 7 | target-output map vs 最终 diff | 每行 updated 有实 diff；unchanged/covered/routed/discarded 有理由；pending-verify 零残留 | done：B8 merge；C4、D3、D4、D6 covered；E5 held 并移入 batch V；其余 in-scope 行均有对应 diff，未把 held 项写入技能 |
| 8 | source-register | 本轮每个 changed owner 有 row，真实分数回填，`impact-chain-gate.rb` 通过 | done：testing / llm / tighten / product-rd / defect / worktree / skill-extraction 均有行；register 保留对应落地 run 的原始分数，最终 evidence 由判定表 5 绑定。真实单次 merge 形态以 parent=`31d3b3f` 运行 `CCL_SKILL_BASE_REF=31d3b3f bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`；最终候选重跑并要求 `r0_status=private-ok`、56 个 firing-path locator resolved、`ccl_skill_check_clean_ok`。Kimi 修复后 severe entrypoint 相对基线为 testing -146 bytes、skill-extraction -118 bytes，大小 blocking gate 应为通过；旧临时 merge 上叠第二次 merge 的验证拓扑已废弃且不冒充候选失败 |
| 9 | 合并候选 | 最终候选 `make test` 与仓库必跑门禁全绿；合 dev 候用户显式指令 | 用户已明确授权 commit + 本地 dev merge，不授权 push/main。全新临时 worktree 从 parent=`31d3b3f` 单次 no-ff merge feature=`e989415`，merge tree 与 feature tree 逐字节相同；`CCL_SKILL_BASE_REF=31d3b3f make test` exit 0。其后只回填本轮生成的 Batch I evidence 与本 plan，不再改变技能/runner/eval 语义；最终另跑 contract coverage、public sanitization、markdown links 与 `git diff --check`。未设 base 的 plain gate 会把本地 dev 上已合入、但不属于本轮的 code-review lane 纳入 `origin/dev..HEAD`，不作为本轮候选判据 |
| 10 | security-sensitive 候选（D3 D4 D6 E5）| 全文读安全 owner 后先分类：现有规则已完整覆盖且本轮不改安全文本的候选退出 landing scope；仍要新增/改写安全语义的候选才需 feature-risk-router security-review gate 记录 + **安全 owner 处置**（approve / narrow / reject）后落地。安全 owner = **本仓维护者（仓库 owner 账户持有人）**；**执行 agent 不得自任或代填**。维护者未处置的 landing 候选 = held | **D3 / D4 / D6：全文读 owner 后判 `covered` 并退出 landing scope，本轮未新增/改写安全规则，故没有待处置 landing 候选**（`agent-tool-dispatch.md` 已有 exposure-vs-authorization、cached-manifest-never-bypasses-authorization、side-effect authorization boundary；`agent-command-sandbox.md` 已有 profile 枚举、network 独立授权、显式降级、scrubbed env / closed FDs / 私有 temp / symlink canonicalization）。**E5：held，未落地**——它需要新增沙箱阻断分流 + 受控提权语义，等待 batch V 具名维护者处置；`source-to-skill-extraction.md#blocked-verification` 本轮不改 |

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| testing-strategy | executor | updated | B1/B2/B4/B5/B7 合并进 SKILL.md 与三个既有 references；B8 合并进 ci-fixtures |
| llm-inference-integration | executor | updated + covered | B6/D2 落 agent instruction / workflow；D3、D4、D6 现有规则已覆盖；D1 保持 batch V |
| tighten-doc | executor | updated + covered | C1/C2 落 session-vantage reference 与入口指针；C4 由现有 scope 规则覆盖；cross-model caveat 独立 reference |
| product-rd-workflow | coordinator | updated | A1/A2、E2、E3 分别合入 adr-convention、code-review-checklist、implementation-completeness-and-minimality |
| defect-diagnosis | executor | updated | A4 合入 Phase C postmortem 段 |
| worktree-isolation | executor | updated | E4 合入 published-branch history rewrite / explicit lease 条 |
| skill-extraction-workflow | this workflow | updated + held | E1/C5/D5 与 benchmark 源类落地；source-register 七个 owner 行已落；E5 未改 source-to-skill-extraction，保持 batch V held |
| 本仓维护者（安全 owner）| authority | no current action | D3/D4/D6 判 covered，无新增安全语义；E5 未落地，待 batch V 独立设计时再请求明确处置 |
| code-review | executor | unchanged→pointer | C1/E2 由 tighten-doc 与 product-rd checklist 持有；本技能是否加一行指针在 batch II 判 |
| agents-file-coverage-gate | executor | unchanged | C2/C3 的 AGENTS.md 分层与预算：C2 不抄 tier 表；C3 归 batch IV |
| multi-agent-delegation | sibling | unchanged: covered | B1 已有"不信 agent 自述"（SKILL.md）；testing-strategy 落地时互相指向 |
| go/python-dev、go/python-architecture | sibling | unchanged: covered | D6 的子进程环境与生命周期规则已有 owner 覆盖，本轮不改 |
| agent-quality | sibling | unchanged: routed | E1 采纳证据标准归 skill-extraction；本轮无需增加跨仓指针 |
| release-coordination | sibling | unchanged | E4 归 worktree-isolation（推送/重写纪律）；release 只做授权 |
| product intent / design / release-eng | lifecycle | not-applicable | dsh 无对应纪律可见 |
| superpowers:receiving-code-review（外部）| reference-only | unchanged | "verify each claim, no performative agreement" 已由其持有，E2 不重复 |
| specs | plan | added | 本文件 |

## 实施边界与评审门

- 实施边界：baseline = 本 plan；worktree `.work/worktrees/dsh-borrowing`（分支 `worktree-dsh-borrowing`）自 dev `673fece` 分出；每条 git 变更 `git -C "<abs>"`；`multi-agent-delegation`: local（三批串行，共享 source-register 文件不并行）；visible surface: no（不改 description）；`feature-risk-router`: shared-skill + no-routing-surface（见 charter）；portfolio-stability: dsh = evolving → 措辞为"形态之一 / 可借鉴"，不写"标准做法"。
- 评审门：每批一条 dual-track 链（review + challenge），终轮 fresh full challenge；P0/P1 处置后才 commit；R0 每批跑；Agent 预算每链独立计（初审 + ≤4 challenge）。
- status-sync：本 plan 即轮记录，判定表 trace 与 dual-track 记录随批回填；source-register 行终稿一次落（routing-round-ledger-append-once）。
- 授权边界（按 023-plan-r1 / r2 / r3 的 review 与 challenge P1 逐轮收窄）：**本 plan 不授予任何变更权限**——包括对 owner 文件的本地编辑、任何有状态的验证（会写盘/改仓库状态的检查）、本地 commit、push、创建/更新 MR、合并 dev、任何 `main` 推进。每个 batch 的执行开始（首次编辑）以及上述每一项动作，都以会话中**各自独立、可记录的用户明确指令**为前提，由执行者在动作前核对该指令存在并在轮记录中注明其出处；本文只描述范围与判定标准，任何句子都不得被引为授权依据。不在此列的只有**已核实无本地/网络/凭证/子进程/远端效果**的只读操作（读文件、只读 grep）；`--dry-run` 之类靠命令拼写声明的"只读"不算——其实际效果未核实前按有状态验证处理。
- Batch IV（C3）：不与 I–III 同批；先出 design-time 四腿检查文书交维护者裁决，裁决通过再开 spec。

### Dual-track 评审记录

- **chain `023-plan-r1`**（candidate sha256 `9b53a0d4…` = 提交 eb7ea2f 的冻结 packet；codex 双 lane，`review_plan_source=derived-default`；review 2×P1，challenge 1×P1）。处置：
  1. **review P1（E5 提权原样重试是安全脚枪）accepted**——源仓的规则前提是"仓库自有可信命令"，泛化到面向任意仓的 ccl 会让仓库控制的命令借沙箱阻断为由拿到 host 凭证/网络。E5 落地意图改写为"先分流沙箱阻断 vs 真实失败；提权只对已审阅可信命令、只授被阻断能力、须宿主策略与用户批准；不作默认动作"。
  2. **review P1 + challenge P1（授权边界自授权 push/MR）accepted**——plan 文本不能给自己远端授权。授权边界条改为：本地编辑/验证/功能分支 commit 由会话确认覆盖；push / MR / 合 dev / main 推进各需独立用户指令。
  3. challenge 未发现术语泄漏、过度泛化、owner 缺失或不可验完成标准类问题（focus 已点名这些类）——不代表落地阶段免检，判定表 3/7 仍逐批跑。
- **chain `023-plan-r2`**（candidate `7db20d88…` = 提交 4d76d64；codex 双 lane；review 1×P1，challenge 1×P1，同源）。处置：**accepted**——r1 修法仍让 plan 文本自证"会话确认授权本地 commit"，评审 packet 内无该证据，候选文本不得成为自身权限来源。授权边界条重写为"本 plan 不授予任何 git 变更权限；各动作授权来自会话中独立记录的用户指令，执行前核对并注明出处"。
- **chain `023-plan-r3`**（candidate `db1bebcb…` = 提交 fd6c3e0；codex 双 lane；review **passed 0 findings**，challenge 1×P1）。处置：**accepted**——"默认边界 = 本地编辑与验证"仍是 plan 自授的变更权限（用户可能只授权了规划/评审）。改为 plan 不授予任何变更权限（含本地编辑与有状态验证），每 batch 开工与每项动作各以会话中独立记录的用户指令为前提；只读验证除外。
- **chain `023-plan-r4`**（candidate `1b3e9d35…` = 提交 ebd45ab；codex 双 lane；review **passed 0 findings**，challenge 1×P1 新类）。处置：**accepted**——D1 原意图会把用户消息/工具结果中的凭证与敏感载荷强制持久化进日志。D1 改为 secret-safe 版：可重建≠原文持久化；凭证只以引用解析、不进模型可见内容与日志；敏感载荷脱敏或访问受控引用；保留/访问边界随既有持久化策略；落地由 security-review gate owner 复核。charter 的"security-review 变更臂 not-applicable"相应收窄为"仅 D1 需安全 owner 复核"。
- **chain `023-plan-r5`**（candidate `bdf391df…` = 提交 3b79506；codex 双 lane；review 1×P1，challenge 1×P1，同源，均针对 D1）。处置：**accepted，且按同类复发规则缩窄设计**——r4 修法引入的"访问受控引用"目标可变，重放会取到不同内容或空，"可重建"成假承诺。D1 不再补丁式细化，改为 honest 形态：model-visible ⟹ accounted-for（可重建 = 原文或不可变版本化引用+摘要且同保留/访问策略；否则显式 non-reconstructable+摘要+原因），断言只查记录与分类完备、不强制持久化。**决定 `narrow`**（同类证据：r4 凭证、r5 可变引用；真实需要：审计/重放的完备账目；更安全替代：分类完备而非内容完备；blast radius：仅 D1 措辞，无迁移）。若 r6 再挑 D1 → 移出 batch I 另开设计。
- **chain `023-plan-r6`**（candidate `5a821553…` = 提交 79f8942；codex 双 lane；review 1×P1，challenge 1×P1，均针对 D1）。处置：**accepted → 按 r5 预记的规则执行 `defer`**——第三轮同类（低熵敏感值的内容摘要可被枚举匹配；"security-review gate owner"未具名、未进完成条件）。D1 整体移出 batch I，新设 batch V（待设计）：另开 spec、具名安全 owner 参与并以其记录批准为完成条件；本轮 `agent-session-persistence.md` 不改。charter security 臂、scope、lifecycle、批次表、意图表、target-output map 同步。
- **chain `023-plan-r7`**（candidate `7f5d4913…` = 提交 0c78860；codex 双 lane；review **passed 0 findings**，challenge 1×P1）。处置：**accepted**——D5 形态记录里的 "everything-logged" 是 D1 同类的日志表述残留，会绕过 batch V 的安全设计。D5 意图删除该词并声明不含任何日志/持久化表述，相关内容一律归 batch V。
- **chain `023-plan-r8`**（candidate `8b52190c…` = 提交 0da11d9；codex 双 lane；review **passed 0 findings**，challenge 1×P1）。处置：**accepted**——`--dry-run` 豁免按命令拼写而非核实效果授权。改为只豁免已核实无本地/网络/凭证/子进程/远端效果的只读操作；`--dry-run` 类按有状态验证处理。
- **chain `023-plan-r9`**（candidate `b0d54c41…` = 提交 7bc7d00；codex 双 lane；review 1×P1，challenge 1×P1）。处置：**均 accepted**——(1) D3/D4/D6/E5 触及权限边界/沙箱/提权，不得标 security n/a：charter security 臂改为这四条 security-sensitive，各自过 security-review gate 并记录具名安全 owner 处置（判定表新增第 10 行）；(2) B7 "不为 push 重复已过检查"补前提：被测树与依赖/环境输入未变且有记录，否则重跑。
- **chain `023-plan-r10`**（candidate `7aac7f68…` = 提交 a421dae；codex 双 lane；review **passed 0 findings**，challenge 1×P1）。处置：**accepted**——"具名安全 owner"可被执行者自任。判定表第 10 行与 target-output map 改为：安全 owner = 本仓维护者本人，执行 agent 不得自任或代填；批准 artifact = 维护者逐条明确处置的记录，独立于执行者；未处置 = held。
- **chain `023-plan-r11`**：未跑——用户于 r10 后要求停下汇报并直接开工；plan 以 r10 状态（review passed、challenge 1×P1 已处置）作为 interim 基线进入实施。

#### Batch I（testing-strategy + llm-inference-integration）
- `023-I`（cand 8771349… = 60bd221）：review 1×P1 + challenge 1×P1（with-key self-skip 绿=没跑、不能当 proof；第三方模型只算 confidence）→ accepted，B6 改写。
- `023-I-r2`（05e20ddb… = c3a40f4）：review P1（D2 绝对化会删掉模型必需的 schema 判别词）+ P2（缺 skill eval）+ challenge P1（逐字 pin 与 keep test 冲突）→ P1 均 accepted（D2 收窄为"仅剔除 implementation-only；公开契约判别词保留；快照按 keep test、行为靠 replay/eval"）；P2 记 routed。
- `023-I-r3`（3c74ba48… = 98318b3）：review P1（"重跑命令"对有副作用命令危险）+ challenge P1（"只有真模型才证明"与 weak 分类冲突）→ 均 accepted（只读观测持久效果；live smoke = 集成/可达置信度）。
- `023-I-r4`（8131c3d4… = 05bc3da）：review passed；challenge P1（"recent"太模糊）→ accepted（绑定候选树 + provider/model/config/env 代次）。
- `023-I-r5`（1c7959fa… = c71bae0）：review P2（规则本身缺 eval）；challenge P1（CI 拥有穷尽的前提是 CI 确有 blocking job）→ P1 accepted。
- `023-I-r6`（e6ab0153… = dd7e9be）：review passed；challenge P1（vendored-drift 压缩后行内丢了 network/delete/exec/human-authorized 不变量措辞——reference 第 24/43 行确有，但评审器看不到）→ accepted，行内恢复并等量压缩。
- `023-I-r7`（c0d47757… = 82ad944）：review P1（live smoke 可能选到有副作用工具）+ challenge P1（新段与诊断脱敏规则未调和）→ 均 accepted（隔离租户/最小权限/可逆工具白名单；公开契约判别词只经 schema/bounded repair diagnostic 暴露）。
- `023-I-r8`（0e0eee3c… = 2a8dc46）：review P1（teardown 在被杀进程里跑不到）+ challenge P2（前段"禁 mode/agent 名"需明示 internal）→ accepted（TTL+janitor 进程外兜底；前段加"internal"限定）。
- `023-I-r9`（8d5e1683… = 52a7888）：review P1（缺 skill eval，升 P1）+ challenge P1（被测对象自写的审计/日志=自述）→ 后者 accepted（权威子系统外部记录或独立状态观测）；前者按仓库 eval 契约（`eval/AGENTS.md`：advisory by construction、fixture 人工评分）以证据 refuted，并加 advisory fixture F22/F23。
- `023-I-r10`（d8632a3e… = e552e7f）：review P1（要求跑 behavior eval 出结果）+ P2 & challenge P1（B5 "只 mock 昂贵/非确定边界"排除了不安全/特权边界）→ B5 放宽 accepted；eval P1 按同上契约 refuted，另做 body-as-prompt 差分作为 RED-baseline 依据（见判定表 5）。
- `023-I-r11b`（cand … = 3553a6b 系列）：review P1（第三方 provider 无 generation 可记）→ accepted（记 identity+限制、按 weak 携带）；P2（D2 无差分）→ 如实记 semantic-control。
- `023-I-r12e`（19aff362… = a97d371）：review P1（"credentialed job"排除本地/自托管模型）→ accepted（"指定 live-model job，凭证仅 provider 需要时"）；challenge P2（RED-baseline 行诚实性：全 rubric 0/3 两臂）→ accepted：修正评分器重跑（base 1/4、head 1/4；标记级 1/7→6/7），行改标 partial、原始输出入 evidence 目录。
- `023-I-r13`（6c29320… = 8713cf4）：review P1（证据脚本 WT 未加引号、忽略 git 退出码）+ P1（证据不完整）+ challenge P1（脚本读可变 dev、无 SHA/摘要绑定）→ 脚本重写为 argv git + 不可变 SHA + 输入 sha256 + 失败即停，SHA 绑定重跑（evidence/red-baseline-023-I-final.json）；"证据不完整"如实保留为已知残余（advisory eval 无法成为 gate；行已标 partial）。

#### Batch II + III（tighten-doc / product-rd / defect-diagnosis / worktree-isolation / skill-extraction-workflow）
- `023-II-r1`：review P1（版本戳规则会连稳定 API/schema 版本号一起删）→ accepted，第 3 类收窄并加「稳定版本标识」保留项。
- `023-II-r2`：review P1（alternatives 必填 + 禁编造 + 只给历史 not-recorded 出口 = 新决定无合法值可填，反而诱导编造）+ P1（缺 eval）+ challenge P1（三判据会把有用户影响的事故豁免掉）→ 前后两条 accepted（加 `none-considered`；仪式豁免限定为无影响）。
- `023-II-r3`：review P2（F23 用了语料里不存在的 type 值）+ P2（force-with-lease 失败机制讲错——真实路径是审阅后 tracking ref 被推进）+ challenge P1（`this cut` 禁令过宽，会删掉变更史体裁里有锚点的正当措辞）→ 全 accepted。
- `023-II-r4`：review P1（fixture type）+ challenge P1（公开导出接口的消费者在仓外，「只有测试/文档消费」会误删公开契约）→ accepted，加「公开接口自成契约语料，走 deprecation 窗口」。
- `023-II-r5`：review P1（F23 owner 规则不在 packet）+ challenge P2（adr-convention 里「采自 agent-native 仓」是不可解析的 provenance——**恰好违反本轮新加的会话视角泄漏规则**）→ 后者 accepted 删除，前者给每条 fixture 加 owner 字段。
- `023-II-r6`：review P1（拓扑检查用陈旧 tracking ref → 应固定次序 fetch→记 OID→对同一引用检查→rebase→lease）+ P1（typo 警告与无条件仪式冲突）+ P1（fixtures 未执行）+ challenge P1（F26 rubric 复制了错误机制）→ 前三条 accepted。
- `023-II-r7/r8`：review P1（`none-considered` 要求「说明为何无需比较」，在「当时就是没做」的情况下**逼人编造**——与本条要防的是同一件事）→ accepted，改为如实写原因（含赶时间 / 没想到 / 流程疏漏）。
- `023-II-r9` 未产出可计入的 verdict，不作为评审证据；编号保留以维持仓外 artifact 对应关系。
- `023-II-r10/r11`：challenge P1（F27 rubric 奖励删除公开 API）→ accepted 重写 rubric；review P1（F26 无差分探针）→ 补跑探针 base 0/4→head 4/4。
- `023-final2`：review P1（worktree 那条 `fetch origin <branch>` 可能只写 FETCH_HEAD，读 `origin/<branch>` 拿到陈旧值 → 拓扑检查假绿）→ accepted，改为记 `remote_oid=$(git rev-parse FETCH_HEAD)` 并全程用该字面值；review P2（register 行与 owner 规则对 postmortem 阈值表述不一致）→ accepted 改写。
- `023-evidence`（证据专审 lane）：P2（探针 runner 忽略 CLI 退出码与 stderr，失败调用会被当 MISS 计分，可能**伪造 base→head 改进**）→ accepted，runner 改为退出码/空输出即 abort，并以坏模型名自测证明守卫会报错；随后**用修好的 runner 重跑全部探针**，结果回填。
- **同类复发裁决**（dual-track same-class recurrence）：五轮评审反复要求把新增 judgment fixtures 变成可执行 blocking gate；仓库 `eval/AGENTS.md` 明文「本目录任何东西都不得成为 merge gate」。裁决 `narrow` 而非再补丁：fixture 语料内写入 `F0-contract` 说明其 advisory 地位与证据引用规则，每条 fixture 标注 owner 与（若有）独立差分探针结果；要让它成为 gate 须先改那份契约，不在本轮范围。

#### Kimi final-candidate lane
- 正式 wrapper 先后在大包上以 `packet_too_large_for_inline`、在 16KB 内语义包上以 `kimi_tool_capability_unverified` fail closed，均未产生模型 verdict、不得计入评审。诊断确认后者是本机 Kimi capability probe 启动时 Node watcher 报 `EMFILE`；用户明确授权本会话手工使用 Kimi，wrapper 修复在独立会话进行。
- 手工 Kimi 初审在无 Git 的仓外临时目录只读取完整 diff（candidate=`dd52ab3`，548044 bytes，sha256=`30111d12d8dbe18d34c4bb2898eebd44891f05a8d12d5ac401d520f8786cdd66`），逐块覆盖 3176 行并重读长行，产出 1×P2：testing 入口无条件写「leave exhaustive matrix to CI」，把 blocking-job 限定只放在 lazy reference，能在 absent/partial/non-blocking CI 下制造假绿。回查属实，accepted；`8de5167` 恢复行内限定，Batch I 在该 head 重跑并以新分数回填。
- 对 candidate=`8e5a28c` 的 fresh 完整 review 产出 1×P2：历史 raw answer 泄漏本机 `/var/folders/.../rb023...` 临时路径，使 evidence 子契约的 no-host-path 声明为假。回查属实，accepted；仅把该路径替换为 `<probe-tmpdir>`，同步 `len` 并增加显式 `redactions` 元数据，评分关键词、pass/missed 与分数不变。
- 最终单次 merge 门禁随后发现 testing severe entrypoint 因第一条 Kimi 修复净增 133 bytes；保留 blocking-job 承重限定并压缩重复措辞，candidate=`e989415` 相对基线降为 -4 bytes。Batch I 因输入字节改变再次重跑，最终真值为 0/4→1/4、4/4→4/4、1/4→4/4，不沿用更好看的旧 wording base 分数。
- 对 candidate=`57282f8` 的 fresh 完整 review 返回 10×P2。回查后接受 8 条：恢复三个 reference-load 的 mandatory qualifier 与 affirmative-continuation 前提；修正 literal keep-test 的保留/转换方向；让所有 runner/JSON 持久化 regex flags；修正 Batch III header；澄清 covered 安全项退出 landing scope、E5 归 Batch V；解释 r9 无有效 verdict；合并 ADR 重复段。另 2 条有证据驳回：宽关键词只用于明确标成 advisory/no-delta 的观察，不支撑因果或完成声明；`屆.` 是 runner 原样保存的模型输出，删除它才会违反 verbatim。受影响探针重新绑定到 `17b3231`：Batch I 0/4→0/4、4/4→4/4、0/4→4/4；IIb alternatives 0/4→4/4；III 4/4→4/4；再跑 fresh 完整 review + challenge。
- 上述处置后的最终完整 diff 重新执行 fresh Kimi review + challenge；原始事件与提取 verdict 保存在仓外临时 artifact，只有两轮均为明确 clean 才可合并。

- 过程教训（进 batch III）：(a) 评审器只见 diff，凡引用 reference 的行内压缩会被判"丢失不变量"——压缩时把承重不变量留在行内；(b) 探针评分器先自证能报失败再用；(c) 宿主 shell 是 zsh，`--paths $VAR` 不拆词会得到空 packet（`empty_diff`），字面写路径或 `${=VAR}`；(d) `review_gate.sh --timeout` 传 >600 直接判 `invalid_input`（不是 clamp），packet >200KB 同样 `invalid_input`；(e) bounded packet 评审器看不到 paths 之外的文件，「证据缺失」类 finding 要先判是候选缺陷还是 packet 视野——后者补 paths 或另跑证据专审 lane，不要改候选去迎合；(f) 自建测量脚本先按本仓「先证明检查器能报失败」规则自测——本轮 runner 忽略 CLI 退出码的缺陷正是评审在证据专审 lane 抓到的。
