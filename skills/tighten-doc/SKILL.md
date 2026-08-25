---
name: tighten-doc
description: "润色文档 / 精简文档 / 改下文档 / AI 味太重 / 废话太多 / polish / make shorter / remove AI tone → finalize wording after substance is settled: clarify, shorten, restructure lightly, preserve decisions, and keep comments safe. Proactively draft a no-owner deliverable doc（「写一份分享/给同事的文档」）. Skip while a sibling owns the substance（定稿仍回本技能）: spec/PRD/标准 → product-rd-workflow; 技术方案/架构文档 → architecture 技能; 发布文档 → release-doc-writer; 测试用例文档 → test-artifact-management."
---

# tighten-doc — 文档写作与优化

Use this as the default document finalization and editing skill; new-substance authoring routes to the owner skill first. A deliverable doc is written for its reader (product / business / exec / teammate), not for the author. Default form = one-page operational/task manual: few short headings, enumerations as tables/bullets (one point per line), short sentences, no bracket piles, no template scaffolding.

## When to use

Use any time you rewrite, tighten, polish, or finalize a doc someone else must read, after owner and scope are clear: strategy, plan, spec, task card, runbook, release note, or collaborative doc.

Three modes:

- Draft: after the owner skill has settled the substance, turn rough intent, notes, meeting output, or task context into a readable first version. Route to an owner when substance is unsettled and the type matches an installed owner skill: spec/standards/guideline -> `product-rd-workflow`, test cases -> `test-artifact-management`, architecture -> architecture skill, code/correctness -> stack/review skill. For new standards/spec authoring, `product-rd-workflow` is the single entry; the hand-back marker is product-rd `owner-ready` with authority statement, doc-family layer, and enumeration evidence — after that, finish wording here. If that marker is absent for a standards/spec artifact, polish only locally and mark `pre-owner blocked` (share/publish gate below). Standalone non-spec artifacts without family references skip it. If no owner skill is installed or reachable, draft from the charter plus user/session-supplied substance — never invent substantive decisions; they stay owner/user-provided. 多轮文档先锁 charter：`references/doc-charter-first.md`
- Rewrite: restructure an existing doc so decisions, owners, gates, and next actions are easier to scan.
- Tighten: remove filler, duplication, AI tone, meta narration, and over-long sentences without deleting decisions.

**先判文档类型，再定形态**：读者是在**用一件已存在的东西**（tutorial / how-to / reference / explanation 四模式），还是要**据此决定或执行一件尚未做完的事**（方案·架构 / 调研 / 现状梳理 / 评审 / 计划）。两轴的判据、每类的首稿必答节、正文与证据分册、图形态，以及「只标记拆分候选、不自行拆分」的收尾边界，见 `references/deliverable-doc-genre-skeletons.md`。一页纸操作手册默认形态对应 how-to / reference，别硬套到其他类型上。

For spec/standard/guideline artifacts, the `pre-owner blocked` marker rule applies to all three modes — do not share/publish until the owner marker exists; local wording polish must preserve the blocked label.

Before sharing, syncing, committing, or publishing a concrete deliverable artifact, run Tighten mode by default. Do not ask the user whether to optimize unless the edit would change a substantive decision, remove required detail, or risk collaborative-comment loss. A request to write a template, SOP, report, checklist, Feishu/Lark doc, task card, or launch material already includes the optimization pass after the owner skill has settled the substance.

After multi-round edits that added, restructured, or changed reader-facing prose or meaning, always run the Tighten mode before sharing or publishing; rounds of only exempt trivial edits (typo/link/format) may record that exemption instead. **What counts as evidence for this pass**: re-read the affected deliverable surface against the rubric (duplication — including same-content-different-face introduced by your own earlier edits in the same session — 一坨, term drift, cell-fits-column) and record: the surface, the touched blocks since the last full pass (the minimum index of scope, not the ceiling — include sections whose meaning the edits change), whether a full-card / family-wide sweep trigger below applies, the defects found or an explicit none, and the reason if scope stops at the touched blocks. Per-edit rubric compliance while writing, grep-only closeout scans (halfwidth / residual-wording checks), or a substance review do not substitute, singly or jointly — the recurring miss is accepting them as equivalent evidence and shipping a self-introduced duplication the surface re-read would have caught.

**技术 / 参考文档：form 优化 ≠ 内容已核。** 当本轮**新增 / 改写 / 发布**了可对源码核验的承载性技术断言（API 签名、env 行为 / 优先级、字段 / label 名、默认值——这类文档常自述真值源），**且一手源用户已给、在当前工作区可得、或用户明确授权查证**时，form 清理之外要把这些断言对一手源码（SDK / specs / fixtures / 可跑命令）核一遍。核出不符：**仅 source-literal 的 typo / 名称 / 默认值笔误**可直接照证据改；**会改动 substantive contract / decision 的**只标 discrepancy / pending 交 owner（stack / review skill），tighten-doc 不接管纠错。源不可得、超出本轮范围、或只是轻量润色：只做 form 并声明「形式已优化、内容未核」，不得裸称「文档已优化 / 准确」（别把每次 tighten 滚成一次代码审计）。

## DELETE (废话 — cut these)

1. 元语自证 / doc-about-itself: "这是X不是Y文档", "本文档/本卡…", "读者是…", "别写空话". **最高频的 agent 自插入形态**：给自己新写的段落加的向导式 opener/closer —— "本节只做X", "本页/这里不维护Y", "这张表只是…", "执行时不要只按本页…", 以及自述用途的引用开场（"用于配套《X》…放引用链接"）。读着像帮读者，其实是 元语自证 + 废话；删掉让内容自己站住。发布任何**你自己写的**段落前，先扫它的开场/收尾句是否是这一类——这正是"我把信息写对了"之后还残留、要读者来挑的废话。（承载真实决策/边界/受众约束/例外/后果的开场不算，删的是只描述"本节存在/本节是什么"的句子。）
2. 翻旧账 / blame: "没人跟全空", "证据：…当初也写过".
3. 修辞尾巴 / 口号 used as a closer: "…= 没解决", "做得再全也…", "上线≠X" as a rallying shout.
4. 无动作语气词: "周会点名" (doesn't say who / when / what) — replace with the real mechanism.
5. 无谓条件前缀 / 连接: "…时", "节奏跑不动时", "总之", "换句话说", "值得一提的是".
6. 重复: a heading restating the table's column names; a clause duplicated in another section. **Index docs especially**: define each term/role exactly once — later sections reference, never re-explain. When a line is challenged, first check if its content already appears in another section; keep only the delta. Aggregation / cross-cut / "references" sections are the prime filler suspect (they compress per-card content into slash-soup that also duplicates the cards) — collapse to a plain short gate list or delete.
   **近义词斜杠堆 = 重复**：一行里 `A/B/C` 若各词同指一件事，收成 1 个代表词；各项确为不同事才留斜杠列表。**逻辑子集措辞 = 表面冗余**：并列两项中一项是另一项子集时读着冗余——删子集项，或点名两个不同失效机制让区分显式。**跨节正反复述 = 隐蔽 dup**：同一组判据被一节正面写（"满足 A+B = 通过"），另一节反面 / 否决形式重写（"反面 ¬A / ¬B 任一成立 = 不通过"）——内核同一份内容、换面孔。审查主动配对扫：每个"判定为 Y"句的 criteria 在别处是否以"否决 / 反证 / 不通过"形式重列；命中 pick 一处保留（通常留反向 / 否决列表，更直接 checkable），另处删。这类 dup 在"已清"二审里最易漏过，是 R1 review-completeness 的重点 watch。
   **图↔文字双写 = 重复**：图承载流程 / 连线 / 状态迁移，文字别逐条复述。但文字要保留图说不清或**不能丢的执行信息**——判据 / 为什么 / 例外 / owner / 硬规则 / 阈值 / 后果 / 验收 / 非渲染 fallback（即 KEEP 项一律留，别当"复述图"删掉）。
   **加图 / 表后必做配对扫**（加图时最常自引入的 dup）：是找 delete candidate **不是命中即删**——只删**纯步骤 / 节点复述**；查的范围覆盖图所在小节 + 相邻小节 + 验收 / 红线段，不只邻近 bullet。
   **Row-granularity in an index/owner/lane table**: one row per domain/lane. A row that is actually a sub-component of another row's domain (e.g. an SDK or a gateway sub-piece listed beside whole domains) → merge it into the parent row (fold its owner/progress/goal in), renumber, update the heading count. Do NOT merge two rows with distinct owners or timelines — that loses accountability; an owner-justified split stays.
7. 病句 / bulk-replace artifacts: e.g. "一键回退排障手册" (missing separator).
8. 自造版本号或前缀: never invent "v7 战略文档" — verify the real title first; a `_v1` filename ≠ the doc title.
9. 编辑性括号副标题: "（按对的赌注不折中）", "（诚实校准）", "（怎么算通过）", "（含…前置底座）".
10. 画蛇添足的解释尾: "中途不换手", "（DoD）" tacked onto an already-clear line.
11. 假目标: a 目标/DoD cell that is a bare verb with no object or threshold ("V1 修完 + V2 决议", "止血/打通/完善", "韧性补齐"). Not filler-to-delete but filler-to-fix → rewrite as a falsifiable DoD traced to the owning card (never invent a threshold); if the real DoD lives in that card, replace with the pointer "见〔X 域卡〕". If the cell references an undefined term (e.g. "V2"), trace it to its definition point and either inline-gloss it once so the cell is self-explanatory, or point to the card — a reader having to ask "X 是啥" means the cell failed.
12. 会话视角泄漏：句子立足于写作会话而非文档；**必须先读 `references/session-vantage-leakage.md`，逐项走完 8 类：死会话 / PR-stack / 变更史与无锚点 / 评审编排 / 辩护 / 推导账 / hedge / 工作语言**；HEAD-reader 可解？存事实、删过程；勿删稳定版本、issue、抑制理由、反事实钉、实测。

## KEEP (实质 — NOT filler; deleting them drops a decision)

owner · 硬规则 · 完成标准/DoD · 里程碑 · 数值阈值 · the real build-vs-buy decision · severity/consequence rationale ("=资损法律风险 / =假安全 / =刑责风险 / 损失大" — that IS the judgment, keep it). **Word it as severity, never as "死".** The consequence label is KEEP, but the word "死" (资损法律死/刑责死/信任死/组织死) is rejected — reword to 风险高 / 损失大 / 刑责风险 / 信任崩 / 组织级风险. ("死" only stays in its non-consequence senses: 死线=deadline, 死约束=hard constraint, 死信=dead-letter, 钉死/封死=lock, 生死=critical-emphasis.) Compression ≠ deleting decisions: before compressing, extract the decided-points checklist (目标 / owner / 硬规则 / 后果论据 / build-vs-buy / DoD / 里程碑 / 最小交付) and verify each survives the rewrite.

## FORM

- Named hyperlinks, never bare URLs: `[真实文档名](url)`. Verify the real title before naming a reference; don't fabricate version prefixes.
- Collaborative docs that support rich structure (Feishu/Lark Docx/wiki, Confluence-like pages) should use the platform's rich-text structure when creating or materially rewriting a document: headings, tables, bullets, and named hyperlinks should be real document nodes, not plain Markdown pasted as body text. Use Markdown only when the target surface is Markdown-native or the user explicitly asks for it.
- In Feishu/Lark standards families, document references must be named hyperlinks, not quoted plain titles such as `《测试规范》`. If a sibling doc is referenced more than once, verify the title once and reuse the same named link across the family.
- **断言写到证据等级为止。** 交付文档里的结论按主张状态分「来源明确陈述 / 有证据支持的推论 / 作者判断」三态，不得混写成同一种口气；「来源明确陈述」是归因不是真实性——写成「来源 X 声称」，不得因有出处就用事实定论口气；作者判断句显式带「判断 / 预计 / 我认为」类标记，证据只到推论级就用分级句式写（如「机制可证、参数不可证」）。三态管**解释性/推断性主张**；直接观测豁免只限原始计数/测量值（如「本次查询返回 N 行」按本来面目写，不强套归因句式）——工具生成的分类/评分/裁决仍须标状态并写明工具权威边界。**状态沿用实质 owner 或证据表已定的等级**：润色时不得自行升降格；owner 未定状态的断言不改文、按既有通道标 discrepancy 交还 owner——已生效的决定、门槛、验收标准不因缺状态标签而被标「待确认」降级（调研类交付物的状态产出由 `multi-perspective-research` 合成简报持有，本条管所有交付文档的表达面）。
- **外部基线 / 标准值入文档 = 独立标注 + 命名来源 + 内部门（若有）仍权威。** 引用外部 benchmark、行业阈值、标准默认值（评测目标、性能预算、参考 SLO 等）时，放成独立的列 / 行 / 标注并配命名来源超链，别和本系统自己的验收门 / 阈值混写成同一个数。**当本系统有自己的验收门时**显式声明本系统门为准、外部值只作对标参考（反模式：把外部基线直接当验收标准，读者误以为外部数就是上线门）；**若文档本身即标准 / 评测报告 / 无内部门**，则标清来源 / 范围 / 权威，别杜撰一个内部门。**评自己的稿是这条的另一半**：对自己产出的文档评可实测呈现属性（加粗密度、句长、结构层级）前，先建同体裁实测基准——长文或系列交付物在**初稿前**建（写完被纠正后再补测，是实测过的返工形态）——按**预先声明的抽样框与纳排规则**（在实测待评稿自身指标**之前**冻结，防止看完自己的数再挑参照系）取同体裁公开样本（记录样本量、口径与局限；不得挑对自己有利的样本充数，"若干份"本身不构成充分门槛），中英文样本分开统计，把待评稿放进分布里定位；找不到可靠公开样本或体裁不可比时如实记「未对标 + 原因」；流行排版阈值逐条核到一手出处再用，核不到不用。**分布定位的合法输出是描述**（"高于/低于所选样本分布"），**不是裁决**："合适"要再结合读者任务与可用性判断；"优于同类"不得由密度类粗指标推出；无基准时该属性只能报「未对标」——自己的审美不是分布。密度居中更推不出「稿子写得好」：整体质量仍按文档目的、读者任务、事实核验与本 rubric 分轴判断，呈现分布不背书内容正确性。
- No inline `｜` / pipe-delimited lists (RACI / 分工) — break into bullets or a table.
- Short sentences, one point per line, enumerations as tables.
- **表达形式匹配内容**：分支关系 / 状态迁移复杂到文字难扫时优先**图**（mermaid 等）；字段对比、分桶属性、owner/gate/证据矩阵优先**表**；线性步骤用编号列表；一两点判断一句话或 bullet。别为单个判断加**装饰性**多桶图，但桶间有不同 owner / 阈值 / 例外 / 后果时**必须结构化**（该结构别压成一句）。**目标环境不稳定渲染图时**，文字版流程为准、图只作辅助。**callout / 图内文字 = 概览形态，只承一个要点**：callout 塞成多点密块（"一坨"）就拆开或降到正文 / 表。**图种由主张形态定**（有事件触发→状态机 / 消息序→时序 / 随完成流转→流程）；**画了必须有标题与图例、连线单向且标签具体**；**量级对比别全压进表**。余下见 `references/figure-and-table-craft.md`。
- **代码进代码块，不进段落**：**多行 / 独立执行步骤 / 长 flag 串命令 / 多命令序列**放代码块（带 lang），不写成段落里的纯文本或一长串内联 `code`。**短的随文 one-liner / 表达式、对照表单元格、「用 `func()`」式符号引用可留 inline**，只要不长到影响扫读（与上面的表格单元格 / 内联引用规则一致，别硬塞进代码块）。多语言对照两端形态对齐——一端给了代码块，另一端别写成「Go：`call(...)`」式内联段落。
- **Enumeration sections (依赖/兜底/分工/里程碑 子项) = multi-line sub-bullets, NOT a `；`-collapsed single line.** Readability beats compactness here; a `- 依赖：A；B；C；D` run is hard to scan — split to `- 依赖：` + one `- A` sub-bullet per item. Do not collapse to one `；` line just for parity with another card; parity is not a reason to reduce scanability. Single-line `；` is only for a true 2-item short pointer where sub-bullets would be heavier than the content.
- Table cells that list multiple skills, owners, checks, environments, or evidence items should be split into multiple lines or shorter rows. A readable table beats a compressed cell when the cell is used as an execution checklist.
- Terms unified and glossed once in a 白话 section (e.g. 红灯 = 卡住/NO-GO 到点必升级; 排障手册 = 排障 SOP). Also catch **intra-doc term drift**: the same concept written two different ways in one doc → align to that doc's prevailing term. Drift includes **unit drift in a sequenced ladder** (a milestone list mixing 第N周 and N天 — align the lone odd unit to the ladder's prevailing one).
- A column/section header must match what its cells actually hold (a "文档化进度" header over cells that hold 现状 is a defect — rename the header to the truth). An editorial paren in a header/heading that restates an intro rule is the same 编辑性括号 as DELETE #9 — cut it.
- **Reader-facing published docs: the problem is unexplained or non-navigable internal references, not the names themselves**. Fix three recurring reader-blockers: ① internal repo paths used as navigation (`see README.md`) a non-author can't follow → name the human destination or link the published doc; ② opaque internal gate/code labels (`R0` / `F4`-style) → plain-name or drop the code; ③ unglossed in-house English / abbreviations (`mTLS` / `PTY` / `SLO`) → 中文化 or gloss at first use. **Keep** anything the reader actually operates on or that is a public convention / protocol / API / field / contract / standard name (`AGENTS.md`, `CODEOWNERS`, `package.json`, well-known abbrevs) — gloss if unfamiliar, don't delete.
- **A cell must fit its column's semantic role.** A 负责人/owner column entry must be a who (person/role), a 事项/规则 column a what (a parseable clause). Over-terse text — including a value the user dictated in an earlier pass — that no longer parses as that column's type ("业务真值+ 误差" in a 负责人 column; "…必需的指标建立" as a 规则 clause) is a 病句 (DELETE #7). On re-review, read each dictated/compressed value back **in its column context**, not in isolation; flag it with the rule even if the user set it (don't silently override, but don't pass it as clean either).
- **Title altitude + doc-family prefix.** A doc / section / reference title names the capability at goal-altitude — drop words the doc type already implies and any scope-enumeration that isn't doing distinguishing work (an SOP titled with its own gate-cases is usually over-long).
  - Keep the capability plus whatever distinguisher(s) actually separate it from its siblings — a scope enumeration can itself be the load-bearing distinguisher, so cut by the test "does removing this still uniquely name the doc?", not by a fixed word budget.
  - Same altitude rule as a 目标 cell, applied to titles.
  - When docs genuinely form a set, align their titles to the family's shared prefix so they scan as a group; do not force a prefix onto a title that does not belong.
  - Renaming then propagates per the family-wide label sweep in WORKFLOW: update every inbound reference label to the one canonical title and residual-scan the old title = 0; leftover ad-hoc short variants are cross-doc term drift.
- **Doc-family structure before wording.** When drafting or tightening a standards/guideline family with several stack, service, or repo docs, first identify the family shape: overview/index, product Spec authority, stack/service child docs, and repo-local execution docs. Tighten the overview/index for authority, ownership, links, and sync gates before polishing child docs; otherwise the leaf docs may read well while the system lacks a source of truth. If the family shape is missing, add or request the overview/index and authority rules before claiming the child docs are optimized.
- Process self-justification stays in chat, never in the file.

## RESTRAINT

- If one sentence says it, don't pile modifiers.
- Delete only when nothing is lost (compression ≠ deleting decisions).
- Generic process docs should carry rules, gates, owners, and acceptance logic; project evidence should live in launch notes, evaluation reports, appendices, or linked child docs. Do not make a general SOP unreadable by embedding code paths, source evidence tables, or full implementation proof unless the doc is explicitly an audit/report.
- **Compression ≠ compressing past comprehension.** Over-tightening collapses a rule into a bare noun-pile with no verb/object (a list of nouns where each item names a thing but not what to DO with it), so the reader can't act. That noun-pile is the over-compression signal — readability > terseness. Fix by restoring verb+object (who does what to which, by when), not by compressing more. After a 干练/简化 pass, re-read each item as a stranger: if you can't tell the action from the phrase, it went too far.
- Prefer the plainer word: "负责到完成" not "负责到完成定义"; drop jargon the audience won't parse.

## 执行卡精简范式 (domain/execution cards only)

For a 域卡/执行卡 (a card that sets WHAT a domain must achieve + who owns it), the converged skeleton is: **目标(决策化) · 负责人(owner+RACI) · 关键规则(红线/后果/NO-GO/0容忍) · 里程碑(动作+gate) · 验收(过关条件,brief) · 最小可交付 · 每周怎么跑/依赖/兜底 · 相关文档**.

- DROP: 术语/白话 gloss section, build-vs-buy / 自营不外包 rationale walls (keep the one-line decision, cut the why-wall), 硬指标 numeric blocks, 枚举/机制 implementation detail, per-item evidence/threshold columns — **数值阈值、验证步骤、工具清单 are the owner's to decide, not the card's**. Also the 默认流程动作 (回填某表/提工单), self-referential / process-aside parens (（边界已划不重叠）（其余降独立验收）). Also **ceremony controls** — 签字/签收, 版本号戳 (v0.1/v1 stamped on every deliverable), 「列…清单」mechanism wrappers — are the owner-accountability (single-A RACI) model's job, not card substance: cut unless the user explicitly keeps them, and state the rule directly instead of wrapping it in its list/sign-off mechanism (a 红线 is "X 未到位 = 不得 Y", not "列一张写着『无 X 不得 Y』的清单").
- KEEP verbatim: 红线、后果论据(severity不用"死")、NO-GO/0容忍、关键可证伪判定定义 (a load-bearing N-criteria pass definition), 锁定决议, owner/RACI, 砍清单. Promote a load-bearing judgment list to its own short section rather than burying it.
- **目标/红线/验收 = a define-once ladder, never restated down the card.** 目标 stays at goal-noun altitude (don't gloss it with the concrete bar). 红线 carries the 0容忍 rule + falsifiable definition once. 验收 = "红线全部达标" **plus only the verification-specific items red lines don't state** (test method / adversarial cases / exportable / a feature-works check / rollback-rehearsed) — never a verbatim re-list of red-line field lists. A downstream gate references, never restates (公测门 = "验收全过", not a re-enumeration of the bars). When 验收 or a milestone gate repeats a red line's exact clause/field-list, that is DELETE #6 — collapse to the reference.
- **Cross-card consistency.** When optimizing one card in a family, the owner-line format (`1 人（X 线），1 周内定，…`) and the section skeleton must not drift per-card: aggressive per-card trimming can silently regress one card below its siblings (owner loses 线+1周内定, the ## 验收 section gets dropped). On a per-card pass, diff its owner line + section list against a sibling and restore parity. When a family of cards shares the same broken framing premise, converge ONE card to the corrected skeleton first (get it reviewed + published), then re-derive each sibling to mirror that reference skeleton — do not independently re-invent each sibling.
- **Global boilerplate-strip + retitle = per-card guarded, never a blanket `replace` fallback.** When deleting a globally-duplicated line and retitling its section across N docs: (1) check the line isn't that doc's *substance* — a line that is boilerplate in most docs may be the entire point of one doc; stripping there destroys content. (2) the new header must name **all** sub-blocks still in the section, not just the first — a blanket `replace` fallback will mis-title a doc whose section held more than the stripped part. Per-doc compute the remaining content and title to it; exclude any doc the user flagged as do-not-touch.
- **Applicability guard — this 范式 is ONLY for 执行/域卡.** Do NOT apply it to: a **spec** (the detail IS the deliverable), an **ops runbook/playbook** (steps are the value), a **strategy doc** (WHAT/WHY/WHEN, different purpose), or an **index doc** (rule there is define-once + cross-section dedup, not altitude-strip). Blanket-applying the strip to those destroys them — stop and ask scope instead of auto-processing a different doc kind.
- **Premise-rejection guard.** Line-tightening is the wrong tool when the user rejects the doc's *framing premise*, not a line.
  - Signals: "这不对 / 没有 X 之分 / 什么玩意儿 / 这是什么东西" aimed at the doc's organizing concept, not one sentence.
  - Why: the whole lower structure (红线/里程碑/验收/owner 拆分) is coherent only relative to that dead premise, so per-line edits produce compliant-but-weak output.
  - Required flow: STOP line edits → confirm the corrected core with the user (one short question, don't guess again — this failure class recurs precisely from re-guessing) → re-derive 负责人/红线/里程碑/验收/依赖兜底 from the corrected core as a **draft for review** (not a blind blast-write) → publish on approval.
  - Repeat signal: repeated user "这是什么/什么玩意儿" on the same card = the premise is wrong; escalate to re-derive, do not keep tightening.

## 句子层（吸收 Strunk《风格的要素》，仅取适合中文交付文档的；英文语法/标点规则不适用，已剔除）

> 英文文档：用完整 Strunk 规则（含被本节剔除的语法/标点条），本节只是中文交付子集。

- 主动语态、点名施动者：写"谁做什么"，不写"被…/由…完成"（呼应 DELETE #4 无动作语气词）。
- 肯定式陈述：直接说"必须 X"，不绕"不是不 X / 并非没有"。
- 具体优于空泛：用 数字/对象/阈值，删"全面提升/大力推进/高度重视/至关重要"这类空话（呼应 KEEP 的数值阈值）。
- 删冗词的定式：把"是否…的问题/在…的情况下/做出…的决定/关于…方面"压成 "是否…/…时/决定…/…"。
- 相关词靠拢、少套从句：修饰语紧挨被修饰对象，长定语拆短句，避免一句里多层"的…的…"。
- 强调位放句首或句尾：最该被记住的词别埋在句子中间。
- 结论前置（BLUF / 倒金字塔，业内通行做法）：bullet、段落开头先放**结论 / 动作 / 信息词**，例子和非结论性背景后置——读者扫读，埋在后面的结论会被跳过。**但会改变结论的条件不算"例子"**：凡是改变结论、适用范围、红线 / NO-GO / 阈值 / 例外 / 责任边界的条件，必须与结论同句同屏，不得降级到后面或塞进括号弱化（如「满足 A、B、C 时，做 X」，不要用括号把条件视觉降级）。作用范围：bullet/段落级，区别于上一条词级"强调位"；只重排各 bullet/段落内部，不得为前置结论删除或降级 KEEP 项，执行卡仍按固定骨架排序。
- 防分词歧义：中文动宾或多义连写串可能被切成另一个意思——「门禁止血」会读成「门 / 禁止 / 血」。加分隔、连接词或重排消歧（「门禁来止血」）。只改**真实会误读、误切后动作/对象/责任会变**的词组；通行术语、项目内已定义术语、读者熟悉的短词不为消歧而重写，避免 churn。

## 中文自然表达（吸收 humanizer-cn 的交付文档子集）

目标不是"更像人"，而是去掉 AI 腔/广告腔/假深度，让读者一眼看清事实、动作、边界。

- 删宏大意义词：彰显、标志着、里程碑、树立标杆、重新定义、开启新篇章。改成实际变化、对象、结果。
- 删动词堆砌：致力于、旨在、聚焦于、依托于、围绕、基于、着眼于。改成"谁为谁做什么"。
- 删广告口吻：精心打造、匠心、领先、一站式、全链路、赋能、助力。保留能力、边界、验收条件。
- 删模糊归因：业内认为、专家表示、相关人士透露、多方消息显示。要么给真实来源，要么改成"未验证"。
- 删套路结尾：未来可期、任重道远、砥砺前行、让我们拭目以待。结尾只留下一步动作、风险或决定。
- 不强行书面化：保留用户认可的短句、白话、紧凑 `/` 和 `+` 枚举；只修元语、重复、空泛、病句。
- 不引入创作向技巧：不要为了"有人味"加入第一人称、幽默、情绪、跑题插入语；交付文档以清楚、可执行为准。

## COMMENT-SAFE EDITING (hard rule)

Never destroy collaborative comments. Before editing a collaborative doc, fetch its real title and count comments.

- 0 team comments on a doc you own: full overwrite can be safe after title/body checks.
- >0 team comments: do not overwrite the whole doc. Use a platform-safe targeted edit, or return a read-only audit for the user to apply.
- **A restructure that deletes, renames, merges, or reorders a section must re-resolve every internal reference that points into the changed area.** The reference-label residual-scan verifies a pointer's *wording* (the old title/label is gone), but a Rewrite that removes or renames a target leaves an `[title](#anchor)`, a "见〔X 域卡〕", a "see the Y section", or a numbered-section cross-reference **dangling** even when its text is untouched — and a moved KEEP/decided-point a pointer no longer reaches is a silent drop. After a structural edit, list the document's internal cross-references/anchors and confirm each still resolves to a present target (repoint or remove otherwise) — the prose-navigation counterpart of the comment-anchor integrity rules below.

  - **Inbound references must be re-resolved too — that half is what link checkers miss.** The re-resolve above is intra-document, but a deleted/renamed section is just as often named from *other* artifacts, including **non-Markdown files a doc linter never opens** (install/build scripts, CI configs, Makefile help, code comments); a prose pointer (`见 README 的「X」段`) is invisible to a link checker anyway, since those resolve the *file* and commonly discard the `#fragment`. So on any heading you delete or rename, run `git grep -F --untracked -- "$old_heading"` repo-wide, then repeat for its **anchor slug** (`install-and-update`) — `[x](README.md#install-and-update)` carries the slug, not the heading text, and the link checker strips the fragment, so the literal search alone misses every anchored link. `-F --` keeps a `-`-leading heading from parsing as an option; `--untracked` keeps a new unstaged file from reading as clean. Read the exit code: `0` = repoint the hits, `1` = clean, `≥2` = the scan failed and proves nothing. Neither pass sees a paraphrase — that needs a read. Failure shape: a README section is dropped, and a sibling doc plus a shell script keep telling readers to go read it — each pointer's own wording is untouched, so every residual-scan and link gate stays green until a human reads both files.
- If changing a quoted/commented string, preserve anchors deliberately or delete/re-add only your own comment at the new text.
- After any comment-affecting edit, re-list comments and verify anchors/count; do not infer safety from substring search alone.
- For Feishu/Lark command mechanics, load `references/comment-safe-feishu.md` before editing.

## WORKFLOW

1. Extract the decided-points checklist from the current text.
2. Apply the DELETE list; keep everything in KEEP.
3. Rewrite to FORM; confirm every decided point still present.
4. Dirty-scan = 0 (no internal codes / agent names / meta / Day-Week tokens, no bare-URL refs, no AI腔/广告腔/假深度, no `｜`). A keyword grep is a **fixed-token prefilter, not sufficient** — the 元语自证 / 修辞尾 / 废话-prefix / 跨节重复 classes aren't fixed tokens, so dirty-scan-0 needs the grep **plus** a human read against the DELETE/FORM rubric. "脏扫 0" claimed from grep alone is the false-clean failure.
5. Push back, respecting the COMMENT-SAFE rule.

**交付前 closeout checklist（阻断项索引，不是通过证书）。** 报「已优化」仍需跑完 Workflow 1-4 + KEEP / decided-point 保全 + 下方 closeout-sweep 全量；本清单只把高频阻断项收敛成可判定的最后一道闸，逐项标 ✓ / N-A、任一未过即不得报已优化（每项指向下方 / FORM 的 canonical 规则，不在此复述全部语义）。发布、同步、commit 前离开生成态，把改过的块当"刚被粘进来"逐行读一遍再判：

1. **callout / 图内文字 = 一个要点**：无多点密块（一坨）就拆或降正文 / 表；图的形态项过 `figure-and-table-craft.md`。
2. **管理 / 业务 jargon 对目标读者已 plain-name / gloss**（协议 / API / 字段 / 契约名 + 用户认可的紧凑 `/` `+` 枚举保留；保留项里读者不熟的首次解释）。
3. **编号连续、父子号同步**；族内同义术语 / label 漂移**全族扫 = 0**。
4. **图 ↔ 文字无双写**（图承流程、文字留 KEEP 项）；外部基线 / 标准值独立列 + 命名来源，门权威按「外部基线」条（有内部门则其为准，无则标清来源不杜撰）。
5. **comment-safe**：协作文档先取真实评论数，> 0 则定向编辑不整篇 overwrite + 改后复核锚点 / 条数；N-A 仅限非协作 / 本地件或已取 comments = 0。
6. **脏扫 = 0**：grep 固定 token + 逐行 standalone-paste 人读（元语 / 修辞尾 / 跨节重复 / 假目标非固定 token，grep 会漏）。
7. **交付面逐面判定**（走枚举，不是单个 ✓）：先列出本交付物的**全部**面——远端副本 / 各附件 / 各导出件 / 历史多代产物，列不出面的清单等于没跑——再逐面标**四态之一（互斥、不叠加）**：已投放（带回读到的标志，只写「已上传 / 命令成功」不算）/ 授权不投放+理由 / blocked+补救+下一步 / **待安全处置**（命中删除要求即**替代**前三态，单独列不并进 blocked 或待投放；触发为客观命中——凭据 / 受删除请求约束的个人信息 / 已判定有害的错误说明——或有权 owner 的删除决定，拿不准按命中处理并问 owner）；多代并存另标当前版入口与退役方式；有交互源导出的另标已全展开再导并对照清点。**有 blocked 或待安全处置面即不得报已优化 / 已同步。** 三态定义、各自的绕过路径与转出规则见 `references/delivery-face-closeout.md`。

本清单是可判定下限，不替代下方 closeout-sweep 全量（改后重扫早期类、长散文转 bullet / 编号等）；用户还能单 paste 挑出同类缺陷 = 清单未真跑，是 firing 失败，不是"reactive 再补一处"。

- **Review-completeness gate — a reactive single-point pass is not "optimized", and "脏扫 0" from it is a false claim.** When a converged reference card already exists in the family, optimizing a sibling means a **systematic full-card audit against that reference skeleton + the entire rubric in one pass**: scan every section for the same defect classes the reference already shed (RACI/owner-枚举, 阈值机制 owner-detail, jargon/英文 token, 跨节重复, run-on `+`/`、` mega-lines, 元语/why-wall) and fix them all at once before reporting done. Do not declare 已优化/脏扫0 while the user can still point at same-class defects you didn't sweep — that recurring "你不认真看么" is the compliant-but-weak defect. Proactively de-jargon for the product/biz/exec reader; do not wait to be asked "这是什么/看不懂" line by line.
- **A jargon term/label rename is a family-wide sweep, not per-card.** When plain-ifying a term or label that recurs across sibling cards (a gate name, a status word, an acronym), rename it across the whole card family in one pass and residual-scan the old term = 0 across all family cards; renaming only the card in hand causes intra-family term drift.
- **Standards-family dirty scan must include cross-doc drift terms.** For R&D standards, scan all sibling docs for old jargon, plain-text doc references, and bulk-replace artifacts before reporting done. Typical Chinese team-doc cleanup terms include `owner`, `deadline`, `runbook`, `Bitable`, `lockfile 未漂移`, `有限值`, bare quoted sibling titles, and spacing artifacts like `负责人 和` or `截止时间 和`. Preserve true protocol/field names when they are part of the technical contract, but rewrite management/action wording into reader-facing Chinese.
- **Full-pass ≠ token-pass — every audited line must be parsed as if user just pasted it standalone.** Full-card R1 / "逐行修改" / "整文档优化" 都让 attention 摊薄 across N lines → pattern-match 过快 → token-level defects 经常漏：同义词堆（"宁过度拒答不越界" + "不按比例" + "0 容忍" 三处同 threshold）、paren 重述前句（"AI 只读、只建议、只生成草稿" 第 3 项是 "只建议" 的子情况）、reorder 后 ordinal 错位（序换 "A 改为 B" → "B 不是 A" 但 "前者" 仍指 A）、单 sentence 内正反复述（"须给路径，不得只否决不给出路"）、severity paren 与 sibling rule verbatim subset（红线 L1 severity + 五前置 L2 同句）。规则：full-pass 每行必跑 standalone-paste-parse — 每 token 检 redundancy / 每 paren 与前句配对扫 echo / 每 "前者/后者/前一项" 在 reorder 后追位 / 每 sub-list 与 cross-section verbatim subset 配对查 R2 ladder。声明 "R1 clean" 而 user 单 paste 即可挑出问题 = evidence-depth overstatement；下一句 single-line paste 必破。
- **New drafts don't escape the rubric.** Any newly-drafted content during this workflow — premise-rejection re-derive, doc split / new sub-card creation, family-wide refactor, or skeleton-from-scratch — must run steps 1–4 (decided-points → DELETE → FORM → dirty-scan = 0) before push. "User approved the split / structure / premise core" approves the *structure*, not the content; the rubric still applies to every new draft. Skipping line-by-line audit on new content lets 元语 / cross-句正反复述 / label-self dup / R2 ladder verbatim subset / 假目标 slip through, and the next message will be "有用技能优化内容么".
  - **Cadence for added blocks**: owner decides substance → run one tighten pass each time deliverable text/structure settles → a final closeout sweep before "done".
  - **The closeout sweep is a read separate from drafting** — leave generate-mode and re-read the changed blocks as if just pasted, swept by the defect-classes present, re-scanning an earlier class if a later edit reintroduces it. Applying the rubric inline while still drafting is the default miss (established self-editing practice: one blended sweep lowers catch rate).
  - **What the sweep does (FORM)**: gloss reader-facing or newly-coined jargon at first use (one-stop 术语 block when terms scatter; preserve protocol/API/field/contract names, explain only if the target reader — default: a new teammate without source context — wouldn't know them); convert long prose to bullets and decision-blobs to numbered lists.
  - **Fire on the objective edits** (add/**delete**/split/merge paragraphs or list items — deleting a paragraph or list item also fires, since it can silently drop a KEEP / decided point — new heading/callout, prose↔bullet/numbered, section reorder, introduce/rename term), not a vague "materially"; trivial already-rubriced edits stay exempt **only for same-workflow carry-over with audience and publication surface unchanged** (re-fire when an already-swept block is moved to a different reader, publish target, or a later/unrelated workflow). Leaving these for the user to surface term-by-term or 段-by-段 is the "baggage 是啥 / 这也要优化成 1,2,3" reactive-discovery failure.
  - **A regeneration / re-sync that rebuilds or may change reader-facing prose/structure is itself a firing pass — machine re-emit is NOT exempt.** Rebuilding a deliverable from updated source and re-publishing it (re-pushing a Feishu/wiki page, regenerating a doc) feels mechanical, but each such regen re-authors prose/structure and must run the closeout sweep on the changed output — running tighten once on the first draft and skipping it across later regens is how filler/meta accretes unseen. (A byte-identical republish, metadata-only sync, or unchanged already-swept block stays exempt.) The sweep especially targets review-round artifacts that pile up across iterations: in a **non-provenance** deliverable, process/version self-narration (version-composition notes, "已过 N 方评审" review-history) and review-provenance tags (parenthetical "(per <reviewer/rule>)"-style cross-refs added during review rounds) are 元语自证 / 编辑性括号 (DELETE #1/#9) — they belong in chat or review notes, never baked in; a genuine changelog / audit / release-note may legitimately carry version content.

- **终版修订不 append，每轮修订过零损核对。** 适用域：**可原位维护的 reader-facing 交付物**（本体即 changelog / 审计记录 / 发布说明 / 正式勘误，或已签发、append-only、必须保留原版的文档，走版本化或附录，不受此禁令）。对适用域内已定稿交付物的后续修订：就地整合进原结构（改正文、改表格、必要时重排节），不得在文末追加「修订 / 更新 / 补充说明」节——逐轮追加会把终版退化成过程日志。**协作文档上 comment-safe 优先于不 append**：评论锚点使安全的原位重排不可行时，允许版本化替代件或明确的勘误/附录（旧版保留并指向新版），不得为满足形式禁令破坏评论。每轮修订收尾跑零损核对：**对照的是稳定标识 + 关键值/单位/结论限定的清单，且核对应关系（哪个值/限定挂在哪个实体/系列/行上——值全在但对应关系接错同样是损），计数只是快速 sanity check**——计数不变可能是错误替换（假绿），计数变化可能是正当的合并/撤回（假红），本轮有意的增删并入预期变更清单后再判；**清单随工作版或访问受控的工作区持久化（工作记录不进 reader-facing 发布目录）并绑定修订前版本**——修订跨会话时从该基线重建 diff，不得从当前输出反推基线（丢了的实体会被当成"本来就没有"）；**派生物同查**——由本文重生成的图表 / 导出件 / 附件按同一清单比对修订前后，不凭观感扫一眼——重生成是最容易静默丢数据的一步。
- **读者版与工作版分离：过程痕迹换归宿，不是删除。** 同一交付物既要服务外部读者、又要承载内部工作记录（全量附录、覆盖工作表、评审史、修订史）时，读者版围绕「怎么读 / 只记三件事 / 怎么用」重构，覆盖工作表、修订史、评审记录只进工作版。**拆分本身是结构决定，不归本技能自裁**：spec / standards / guideline 族按上面 When-to-use 的规则先报拆分候选、owner 确定 doc set 后执行；单体交付物的拆分也须用户或内容 owner 明确同意，拆时登记：**工作版为承重内容的唯一可编辑真值源，读者版单向派生**（承重字段——数字、限定、结论——不得在读者版单独改，发现差异回工作版改再派生；读者版的表达层调整也须回写工作版或存为可重放的派生调整，否则下次重派生会静默覆盖）、工作版的访问边界（评审史等内部内容不随读者版外发）、同步绑定的工作版版本；**读者版评论反向回流**——每次从工作版重生成读者版前，先处置读者版**全部**未解决评论：涉承重内容的登记回工作版处置完再派生，其余按 comment-safe 红线保留锚点，防止两版长期分叉或评论静默丢失。上面 regen 条删的过程自述在有工作版时不是丢弃——移过去。（调研类交付物侧的同款纪律由 `multi-perspective-research` 的"过程自省不进交付物"条持有。）
- **交付面：改完 ≠ 交出去（投放 / 退役 / 导出保真）。** 上两条管的是文内不丢与正副本权威；交付物还有一组**文外的面**——远端副本（飞书 / wiki 页）、附件（pdf / 大图）、导出件（png / jpg），以及历史上生成过的多代同名产物。逐面判定，未判定不得报「已更新 / 已同步」：**①投放要回读远端、不认本地动作**——上传 / 推送命令返回成功不等于那一份已经变（超时后半成、权限被拒、覆盖到错误的页面、缓存仍吐旧版），本地改完、远端还是旧版是最常见的静默残缺；核到本轮的可识别标志才算已投放。「不投放」只能是经授权的排除，**推不上去是 blocked 不是「不投放」**，有 blocked 面或待安全处置面即不得报已同步。**②当前版给稳定入口，旧版退役只用归档或原位标「已过期 → 指向新版」两种可逆做法，本条不授权删除**；反过来，涉凭据 / 个人信息 / 有害错误说明这类**被要求删除**的面，可逆做法不构成处置，但判定与执行都不归本技能——单标 `待安全处置` 转出给安全 / 法务 / 内容 owner，与投放类 blocked 分开列，其结案前不得报已同步。**③交互源（可折叠节点、悬浮标签、可滚动区、分页表）导成静态图前全部展开再导**，导出后对照交互源清点承载性实体。**③的 oracle 与零损核对不同**：那条比的是重生成前后（同一路径两次输出），比不出交互 → 静态这一次性的丢失。三态定义、各自的绕过路径、退役沿革与转出规则见 `references/delivery-face-closeout.md`。

When the user probes sentence-by-sentence ("这是废话么 / 什么意思 / 能精简么"), answer per this rubric, give the tightened version, and apply it — don't ask permission unless the comment-safe red line is triggered.

## Reference Loading

- For Feishu/Lark comment preservation, range update mechanics, overwrite pitfalls, and cross-doc rename safety, read `references/comment-safe-feishu.md`.
- 交付面收尾（投放回读、三态定义与绕过路径、旧版退役与「被要求删除」的转出、静态导出全展开）展开在 `references/delivery-face-closeout.md`；closeout 第 7 项与「交付面」条都指向它。

## CROSS-MODEL / CODEX CO-REVIEW CAVEAT

Cross-model agreement is a recommendation, not a decision: take only rubric hits, reject every 口语化→书面 rewrite and any re-expansion of a deliberately terse line, present its output verbatim, state what you took/rejected and why — `references/cross-model-co-review.md`.
