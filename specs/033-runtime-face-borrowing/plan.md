# 033 — 借鉴轮计划：agent-native 产品仓的运行时架构面（phase 2）

Status: plan-only（评估轮已完成，候选未落地）。本文件是落地轮的分档执行计划；候选台账与真实来源指针存 per-host 私有档（provenance 不入共享树，见 extraction-lifecycle-handoff）。

## 背景

- 023 轮对同一外部源（source-register label：agent-native product repository, evolving portfolio）完成了开发纪律面的借鉴并全部闭环（023 → 030/031/032）。
- Phase 2 评估轮（2026-08-22）覆盖了 023 未登记的第二面：**源码运行时架构 + 其可组合性理论论文**。产出候选台账 16 条处置（11 keep / 5 route-discard），按 owner 分三档。
- 证据等级：全部 observed（代码 doc-comment/契约层 + 论文 ch1/5/6/8 深读）；单源，落地一律按"一个行业形态"表述，不作 standard claim。

## 分档

### 第一档（先做）：llm-inference-integration，agent runtime 架构簇（8 条）

内容（详见私有档台账 A1–A8）：能力分解三元结构（契约 seam / 可换 provider / 独立 model-facing tool 包）；注册配对逆操作、teardown=作用域回收；上下文管理三件套（超限工具结果外溢政策含 fail-open 与防循环、压缩的模型无关剪枝层先于摘要层与失败码分类、replay-aware token 压力信号）；model 请求与工具副作用前的持久化 checkpoint；沙箱 policy/enforcement 分离与 replay 可重建快照；护栏 wrapper（重复调用提醒、协作式超时）；subagent 多 provider seam 与 one-shot/continuable 分离；read-before-edit 观察态政策插件。

- Merge 锚点（merge-not-append，动手前全文读目标段复核 covered/gap）：
  - `skills/skill-extraction-workflow/references/harness-patterns-and-eval.md` §7（现仅 doc 层形态记录）——A 簇主锚点归属评估后可能移至 llm-inference 侧文件；
  - `skills/llm-inference-integration/references/agent-session-persistence.md`（checkpoint 时机 vs 030/D1 的记账分类，互补不重复）；
  - `skills/llm-inference-integration/references/agent-command-sandbox.md`（policy/enforcement 分离 vs 031/E5 的升级政策，先做 delta）。
- 预计一轮内完成；若 dual-track 发现簇过大，按"上下文管理三件套"独立拆轮。

### 第二档：testing-strategy，测试工程面（3 条）

内容（台账 B1–B3）：LLM 恢复路径的故障注入 fixture 分层（可编程兼容 fault server / 录制回放短路 / keyless 自跳+credentialed preflight 的既有政策承接）；覆盖门指名到 path:line:col 与分区执行、perf/stress 车道以配置清单隔离；查重与死码门、派生产物"再生成而非拒绝"。

- Merge 锚点：`skills/testing-strategy/references/ci-fixtures-and-flake-control.md`、`e2e-real-flow-testing.md`、`test-code-authoring-patterns.md`（023 落点，先 delta 再 merge）。

### 第三档：route / defer（不排轮）

- 应用层 rolling provider transition → `platform-release-engineering`：hypothesis-grade（单源、论文自认 observational），落地前需 ≥2 独立外部源佐证，暂 defer 并挂在该 owner 的下次设计轮。
- 包自有 runtime invariants 注册表 → `*-architecture` 泛化评估，弱保留。
- 其余：launch-env 分层溯源（discard-lean）；理论演算章（no-new-lesson，可执行含义已由第一档承载）；model-facing 文案细节（confirm-only，归 023 已落规则作佐证）。

## 每轮硬性 gate（不因分档减免）

1. 新会话、每轮重新 invoke `skill-extraction-workflow`（per-round re-invocation 规则），round 自建 charter。
2. worktree 先行，绝不在 main/dev 检出上编辑。
3. R0 零命中：真实来源名不入可执行文本与仓库历史；新 label 先入 alias YAML（fail-closed）；example 若成套需 pre-draft 域选择。
4. dual-track：独立评审 + 对抗 challenge；非 wording 变更配 behavioral-evidence 行（RED-baseline / semantic-control）。
5. source-register 行按 Round-consolidation 规则单次追加；upstream owner 变更走 impact-chain 行与 `check-ccl-skills.sh` 机械闸。
6. 源为 evolving portfolio：落地前按台账中的源指针重取当前快照做 delta 确认，不以本评估快照为确认基线。

## 验收

- 第一/二档各自：owner 目标段 diff 与 target-output map 一致；merge 锚点无 append 型重复；R0 `r0_status=private-ok`；dual-track 收敛（无未处置 P0/P1）。
- 第三档：每条在 owner 侧有 route/defer 的登记行或显式 discard 理由。
- 全部完成后：per-host 程序记忆更新为 phase-2 closed。
