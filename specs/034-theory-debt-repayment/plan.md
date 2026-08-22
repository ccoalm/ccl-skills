# 034 — 理论基底欠账清偿计划（三批次）

Status: 批次一进行中（本轮）；批次二、三待排。本文件是 `docs/skills-theory-foundations.md` 自点名欠账的分批执行计划；每批次独立 fresh invocation + charter + worktree + dual-track，round WIP 与 charter 存 per-host scratch（provenance 不入共享树）。

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
- 引用核验纪律：一律 WebFetch 核标题与内容，不凭记忆写出处（theory doc 有 PubMed ID 挂错先例）。

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
