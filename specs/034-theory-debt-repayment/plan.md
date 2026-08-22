# 034 — 理论基底欠账清偿计划（三批次）

Status: 批次一已闭环（PR #22 合并进 dev，af3f5e7；合并即批准 r3 P1-a defer，闸硬化跟进项绑定 skill-extraction-workflow 下一轮 gate 工具变更）。批次二 **interim**——机械闸全绿、dual-track 5 轮跑毕（链见批次二 gate 记录）；两处终轮后记录一致性修复（哈希域说明、弃项措辞）由 PR 合并人裁决：merge=接受，拒绝=扩轮重走收敛；批次一同款闸缺口（owner-restored-to-base）defer 沿用已获批登记，本轮未加宽。批次三待排。本文件是 `docs/skills-theory-foundations.md` 自点名欠账的分批执行计划；每批次独立 fresh invocation + charter + worktree + dual-track，round WIP 与 charter 存 per-host scratch（provenance 不入共享树）。

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
- Gate 记录（2026-08-22，落地候选）：
  - 源核验（全部实取核标题+内容，非记忆）：Apple HIG feedback / accessibility / loading / designing-for-ios 四页经官方 JSON 数据端点取全文（SPA 正文纯 HTTP 不可达，按 blocked-source 补救梯换端点）；Material 3 States（title "States"）与 Accessibility Designing（title "Designing"，含 Color contrast / Structure / Flow / Elements）经站点内容 JSON 端点取全文（headless browser 定位端点）。44×44pt 最小命中区在 Apple 一手源（HIG Buttons："a button needs a hit region of at least 44x44 pt — in visionOS, 60x60 pt"）核实，不转引 Material 的转述。
  - 落地形态：`product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md` 新增 Platform Convention Walkthrough 节——25 条 pass/fail 走查判据按三条主线分组（状态完整性 9 / 可达性 12 / 平台惯例 4；减动效条与既有 design-intent 条款互指不重复），逐条标 (HIG) / (Material) 单源出处；Source Anchors 升级为一手平台规范锚；弃项显式记录 5 类（媒体可达性分类学、平台能力集成与 watchOS/visionOS 专章、state-layer token 机制、ARIA landmark 全目录、视觉风格内容）。`ui-ux-audit.md` Audit Procedure 增第 10 步走查入口。theory doc UI/UX 行升级为双透镜 🔗。
  - Owner 分派（judgment-delta 附后）：`product-ui-ux-design` updated；`app-cross-platform-dev` unchanged——判据是设计验收层，同平台规则的实现机制（Dynamic Type / reduce-motion API / predictive back）既有路由已指向该 owner，本轮无新义务；`miniapp-product-dev` unchanged——HIG/Material 不辖小程序宿主，对应平台规范（微信运营规范）超出本批锁定范围，theory doc 该行引用已在；`testing-strategy` unchanged——走查判据不改测试层选择规则；`web-react-dev` unchanged——web 可达性验收线仍是同文件 WCAG 2.2 节，平台走查节明示与其互补关系。
  - Judgment-delta matrix：aesthetics = no new evidence（平台视觉风格刻意不吸收，弃项已记）；interaction logic = confirmed + narrowed（Material 六态词汇印证既有状态矩阵；新窄化：不可禁用组件类清单与"不可用即移除 FAB"）；behavioral logic = new（HIG 数据丢失警告双向边界、成功确认克制+失败必说明、Material 焦点归还契约）；psychology = confirmed（HIG 打断层级配比印证既有 feedback-strength 阶梯，无新增）。
  - RED-baseline（applied、差分归因、一次性副本，沿批次一 reword-not-delete 协议，v2–v5 每版候选各重跑）：control 绿（gate exit 0）→ 改写锚行 "Disabled semantics are real, not painted" 使 `impact-chain-gate.rb` exit 1，`impact_chain_firing_path_missing` 只点名 `product-ui-ux-design`，其余 owner 行不受影响 → 恢复即绿（exit 0）。哈希域定义（终轮 P1 要求的可复现说明）：评审 controller 的 candidate_sha256 哈希**整包文件**（裸 diff + 附加上下文），probe transcript 的 candidate diff sha256 哈希**裸 `git diff af3f5e7..HEAD` 字节**；落地时实测两域收敛于同一候选——工作树 `git diff af3f5e7 | sha256` = transcript 记录值（13f9d883…逐字节相等），packet 文件 sha256 = controller 记录值（af37e737…）。
  - 机械闸：`check-ccl-skills.sh` → `ccl_skill_check_clean_ok`（`alias_audit_ok`，`r0_status=private-ok`，零命中）；`eval_routing_ok` blocking none（本批未触碰任何 description/frontmatter）；entrypoint size/word budget delta 全 +0。
  - dual-track（tracked chain 034-b2-c3，review + challenge 预算 4，implementer family=claude → 选中 codex）：r1 review = 3 P1 + 1 P2，全部采纳修复——(P1) loading 判据泛化到 mutation 会许可 duplicate-submit → 收窄至 content/asset loading 并显式指回 SKILL.md 高风险韧性态；(P1) 减动效条与既有 opt-in 庆祝动画例外矛盾 → 改"默认停+唯一既有窄例外保留"；(P1) RED-baseline 仅 prose 断言不可核 → 重跑探针并捕获候选/闸脚本哈希绑定的 transcript 入包；(P2) 三条 (HIG/Material) 混源标签违反单源承诺 → 拆为独立标注条目，22→25 并同步计数。challenge r2（对 v2 候选）= 3 P1 + 1 P2，全部采纳修复——(P1) 状态矩阵判据把六态写成普适义务，与 M3 组件类继承表冲突 → 收窄为"按组件类继承的状态"；(P1) 推荐级阈值（200% ideally / 44pt general rule / 48dp consider / 8dp most cases / 12·24pt generally）被写成无条件 fail → 节首加 normative-strength 规则（推荐级=记录在案的例外可过，静默不足才 fail），逐条标注源措辞强度；(P2) system-colors 条无 pass/fail 边界且渲染面不可判 → 改为可观察的 Increase Contrast 渲染闸+非阻塞实现指引；(P1) 台账 app-owner 行声称判据路由了 Dynamic Type 机制但判据未写 → text-scaling 判据补显式路由，行措辞对齐实际。challenge r3（对 v3 候选）= 4 P1，处置：(P1 采纳) disabled 判据比 M3 原文更强且漏 drag → 照原文精修（cannot be focused/dragged/pressed，不禁说明性反馈）；(P1 采纳) standalone 对比度豁免未限定 → 收窄为仅 container-vs-background，内容/图标/焦点指示仍需达标；(P1 采纳，scope 修正) 评审计划冻结 acceptance 中遗留 22/9+10+3 旧计数与候选 25 冲突 → 修正计划 acceptance 为 25，按 review_scope 变更重开新链跑 review+终轮 challenge（Agent 预算 5 轮内收口）；(P1 deferred-已登记) owner 文件被冲突/部分落地还原为 base 时行留绿——与批次一 r3 P1-a 同一闸缺口，其 defer 已由 PR #22 合并人批准并绑定 skill-extraction-workflow 下一轮 gate 工具变更，本轮不扩轮、缺口未加宽；本 PR 合并人可在合并决定中再次行使裁决（拒绝=要求先修闸）。acceptance 计数修正构成 review_scope 变更，链 034-b2-c3（review+2 challenge，3/5 轮）就此 superseded——其 findings 全部已处置如上；按修正后 scope 重开链 034-b2-c4。c4 r1 review（第 4/5 轮，对 v4 候选）= 3 P1，全部采纳：focused 模态照 M3 原文改"keyboard or voice"（switch 不再冒充 Material 措辞）；手势替代判据收窄至 core functionality/任务流（HIG 原文范围），可选便捷手势不再误判；本 gate 记录在终链后须标明 c3 superseded 并逐字回填 c4 终轮 verdict（即本段+下行）。c4 终轮 challenge（第 5/5 轮，对 v5 候选，packet sha256 af37e737f3e74b26b9494c4b7f63cabfe5708235b22664006ad143860808251a）= 1 P1 + 1 P2，Agent 自主预算（初审+4 challenge）至此用尽。处置（审后修复，构成 v6 落地候选，未再入轮）：(P1) probe transcript 的 diff 哈希与 controller 的 packet 哈希域不同、无可复现说明 → 按其 smallest_fix (b) 补哈希域定义并实测两域各自吻合（见上 RED-baseline 行）；(P2) 弃项清单"visionOS-specific rules"与判据内保留的 60×60pt 冲突 → 弃项行显式记录该保留值为 informational、walkthrough 范围不辖 visionOS。二者均为记录一致性修复，判据语义与台账声明零变动。按批次一先例，本批状态 **interim**：v6 与被审 v5 的差异（上述两处记录修复）由 PR 合并人裁决——merge = 接受该差异与全部处置，拒绝 = 扩轮重走收敛。

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
