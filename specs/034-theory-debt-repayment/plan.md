# 034 — 理论基底欠账清偿计划（三批次）

Status: 批次一 **interim**——机械闸全绿、dual-track 评审 + 4 轮 challenge 跑毕（链见批次一 gate 记录）；余一项决策依赖：r3 P1-a 闸缺口的 defer / 扩轮裁决，由 PR 合并人行使（merge=批准 defer，拒绝=扩轮修闸后重走收敛）；裁决前不标完成，理论文档的清偿表述与本候选同一落地原子生效。批次二、三待排。本文件是 `docs/skills-theory-foundations.md` 自点名欠账的分批执行计划；每批次独立 fresh invocation + charter + worktree + dual-track，round WIP 与 charter 存 per-host scratch（provenance 不入共享树）。

## 背景

- `docs/skills-theory-foundations.md` 建立了理论↔规则的三档标记体系（🔗 内核 / 🔗 / 无标记 / 团队取舍），并自点名了三笔待处理项：
  1. **架构技能零举证**（⚠️ 行）：仓库规则要求 product-agnostic 架构技能有外部权威源，`go-microservice-architecture` / `python-service-architecture` 的边界与契约主线连理论名都未入包。文档自判"真该补的欠账"。
  2. **UI/UX 单透镜**：`product-ui-ux-design` 只覆盖社区实践透镜，HIG / Material 等平台级规范未纳入。
  3. **二次收割未落**：文档〔认出或借来之后〕一节要求去读已认出理论的未覆盖部分与失效边界，目前停在号召，无可达触发点。
- 处置裁决（会话内定案）：第 1 项是违反存量规则的标准红，立即清偿；第 2、3 项是增强，改写为有界任务后执行，允许空手结论。

## 分批

### 批次一（先行，独立收口）：架构技能外部举证回填

- 范围锁死：两个架构技能的**边界与契约主线**补外部一手源举证（限界上下文 / 康威定律或经核验更贴切的源），写清借了哪部分、没声称哪部分；不重写规则实质。
- 同步面：`docs/skills-theory-foundations.md` ⚠️ 行升级为 🔗、文末欠账注记删除；`references/source-register.md` 补两条 impact-chain 行（`*-architecture` 属 `check-ccl-skills.sh` 机械闸清单）。
- 附带裁决（批次一内做，不预设结论）：事后认出理论的"回填包内"义务要不要在 `skill-extraction-workflow` 落 firing point、要不要机械闸扫架构类技能外部源——按 design-time operability check 四腿（author-dogfood / marginal-cost / trust-model fit / premise check）裁决 update / unchanged。
  - 裁决结果（2026-08-22）：**机械闸不建**——URL 存在是形态代理，证不了 grounding 质量（oracle 只能假绿）；边际成本落在每个新架构规则上，而外部举证的触发类只是 state-of-art claim 子集（over-broad hook）；premise 是单次欠账、无复发证据。**firing point 落在理论文档演进规则**（〔事后认出〕小节新增回填义务条）而非 extraction workflow 包：认出对应关系的动作发生在编辑本文时，读者必经该节；extraction workflow 的 external-authoritative-source 规则已覆盖新提炼轮，`unchanged`。
- 引用核验纪律：一律 WebFetch 核标题与内容，不凭记忆写出处（theory doc 有 PubMed ID 挂错先例）。
- Gate 记录（2026-08-22，落地候选）：
  - 源核验：Fowler 两页标题+内容实取确认；Conway 1968 论文作者自存页（"Committees Paper"，thesis 原文确认）作为一手源入引；Evans 归属经 Fowler 页内脚注（"Eric Evans in Domain-Driven Design"）核实。
  - 机械闸：`check-ccl-skills.sh` → `ccl_skill_check_clean_ok`（r0_status=private-ok，零命中）；`make eval-routing` → blocking none。
  - RED-baseline（applied、差分归因、一次性副本）：改写 Go / Python 锚行各自使 impact-chain 闸红且只点名本侧 owner，恢复即绿；删除探针在 Python 侧退化（删行还原 base、owner 退出 changed 集、行不被检查）——已如实记入台账行并改用改写突变。
  - dual-track 评审：codex review r1 = 1 P1 + 2 P2，全部采纳修复（限界上下文降为边界输入、不再把事务所有权判据归给源、显式否认 context=service 一比一；补 Conway 一手源与 Evans 归属核验；计划状态与理论文档表述对齐）。
  - dual-track challenge 链：codex challenge r1（对 v2 候选）= 2 P2，均采纳修复：(1) 理论文档行把「边界与契约」整条欠账标为全额清偿，而引用只覆盖边界输入判据——行内改为精确表述：边界半边清偿 🔗，契约/数据所有权操作判据按包内显式声明记为技能自有（团队取舍性质的准确留白）；(2) 计划状态先于 challenge 记录声称 dual-track 完成——本链记录落入计划，最终轮对含本记录的候选重跑，收敛判定=无未处置 P0/P1。
  - challenge r2（对 v3 候选）= 1 P1（协议性发现：pending 占位与清偿声明同候选落地，且回填后候选将异于被审候选）——采纳：回填本行并对回填后的精确 diff 继续跑轮。
  - challenge r3（对 v4 候选）= 2 P1 + 1 P2，处置：
    - P1-a（真缺口，deferred + 登记）：本轮如实记录的退化探针暴露 impact-chain 闸的既有缺口——owner 文件被冲突解决 / rebase / partial cherry-pick 还原为 base 时退出 changed 集，其台账行与清偿声明留存而闸保持绿，落地内容可被静默丢失（暴露类：单行新增型 owner 变更）。修复在闸侧（新增/修改的台账行无论 owner 是否在 changed 集都校验 firing path），属共享工具轮，超出本批锁定范围——登记为 `skill-extraction-workflow` 闸硬化跟进项，绑定其下一轮 gate 工具变更；此 scope-cut 需风险 owner 裁决，载体即本 PR 的合并决定（合并=批准 defer，拒绝=本批扩轮修闸）。
    - P1-b（终局记录可靠性，采纳）：收敛轮结果不入 PR 描述（可变、可丢），改为**计划内回填**：收敛轮 clean 后，唯一允许的审后编辑是把该轮 verdict 逐字回填到下方 r4 行（仅限 gate 记录行本身，规则实质零变动；任何其他 diff 使收敛作废、必须重跑）。
    - P2（采纳修复）：Conway 归属收窄为团队所有权/沟通结构这一分割输入；deployment/release cadence、scaling、rollback 判据在两 playbook 中显式归为技能自有操作判据，不归任一来源。
  - challenge r4（对 v5 候选，packet SHA-256 26493f72a5c86a804c9dcbab5a82118385901b4f27d040b9dab4aa7c04790033）= 2 P1：其一为记录递归协议类（r2/r3 P1-b 已处置——本回填即其 smallest_fix 的执行，规则实质零变动）；其二重申 r3 P1-a 并反对 prose-only defer、要求先修闸再发布清偿声明。Agent 自主 challenge 预算（初审 + 4 轮）至此用尽，P1-a 按预算规则 park 为**决策依赖项**：本批不自标完成，状态 interim，裁决权在 PR 合并人——merge = 批准 defer（闸硬化跟进项已登记并绑定 skill-extraction-workflow 下一轮 gate 工具变更），拒绝 = 本批扩轮修闸（新增/修改台账行无条件校验 firing path + owner-restored-to-base 回归 fixture）后重走收敛。

### 批次二：UI/UX 平台规范落成走查判据

- 改写后的交付物：把 HIG / Material 中与 `product-ui-ux-design` 现有规则主线相交的部分（状态完整性、可达性、平台惯例）落成**可执行走查判据**——不是链接清单。落不成判据的部分显式弃掉并记录，弃掉本身是有效产出。
- 范围护栏：只借与现有主线相交的判据；不整章搬运；单源（各平台官方文档）按"平台规范"表述，不作跨平台 standard claim。
- Owner 面：`product-ui-ux-design` 为主；若判据涉及实现/测试证据形态，按 uiux-routing-map 分派 `app-cross-platform-dev` / `miniapp-product-dev` / `testing-strategy`，各标 update/unchanged。

### 批次三：理论二次收割——机制 + 有界试点

- (a) 机制：在 `skill-extraction-workflow` 落一个可达触发点——提炼轮 RCA 阶段对本轮涉及的已认出理论顺带查"未覆盖部分 + 失效边界"（满足 `landed` 须命名 fetch point 的自有规则）。落法优先 merge 进现有规则，不新增顶层 bullet（rule-consolidation）。
- (b) 有界试点：挑 2–3 个高概率有存货的理论（候选：双环学习的组织防卫机制、Safety-II 的 sustain 侧、Checklist Manifesto 的 killer items）各跑一次收割：读一手源未覆盖部分 → 产候选规则或显式 no-new-lesson。
- 允许空手：试点全部 no-new-lesson 时，机制 (a) 降级或撤销，结论记入本计划——这是有效终态，不是失败。

## 每批硬性 gate（不因分批减免）

1. 每批次新一轮 invoke `skill-extraction-workflow`，round 自建 charter（per-round re-invocation 规则）。
2. worktree 先行，绝不在 main/dev 检出上编辑。
3. R0 零命中：本 program 源均为公开文献/官方文档，预期无敏感 provenance；仍跑审计不豁免。
4. dual-track：独立评审 + 对抗 challenge；非 wording 变更配 behavioral-evidence 行；`description`/frontmatter 一旦触碰即按 routing-surface 走 `make eval-routing`。
5. upstream owner（`*-architecture`、`product-ui-ux-design` 涉及时）变更走 source-register impact-chain 行与 `check-ccl-skills.sh` 机械闸。
6. 引用落地遵守 theory doc 演进规则：核标题不只核 HTTP 200；包内留引用后才可标 🔗；写清借了哪部分、没声称哪部分。

## 验收

- 批次一：两技能包内可 grep 到引用；theory doc ⚠️ 行升级且欠账注记清除；impact-chain 行齐；dual-track 收敛。
- 批次二：每条纳入的判据可执行（有 pass/fail 走查形态）；每条放弃的部分有显式记录；owner 分派各有 update/unchanged 行。
- 批次三：机制有命名的 fetch point；试点每个理论有"候选规则落地 / no-new-lesson"终态；空手时机制降级决定记录在案。
- 全部完成后：theory doc 三笔自点名项全部消项或转为显式记录的终态。
