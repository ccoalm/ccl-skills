# 已关闭：路由 bootstrap 劫持独立评审通道

> **状态：不复现，根因不成立，不再是待办项。**
>
> 「影响 / 现象 / 根因 / 修复方向」是缺陷记录当时的原文，其中「根因」已被证伪；保留是为了让当时的判断可追溯。

## 复核（2026-08-10，dev tip `f3b18cf`）

按本文自己的验收判据实跑，**判据已满足**：排除同族评审器后 `review_gate.sh` 返回 schema 合法、`findings` 为数组、`status` 非 `inconclusive` 的结果。

| 输入 | 模式 | 结果 |
| --- | --- | --- |
| 19 行探针 diff，裸 `codex_review.sh` | review | `findings`，1 条 P0 |
| 同上，走 `review_gate.sh` | review | `findings`，3 条分级 + 5 项 `concern_results` |
| 真实候选（47 文件 / 189KB） | review | `findings`，2 条 P1，packet `ed862d10…` |
| 同一候选 | challenge | `findings`，1 条 P1，同 packet |

三次经 gate 的调用都选中 codex，`claude` 每次按 `same_family_as_implementer` 在 preflight 被正确跳过。

**「根因」一节写的 hook 注入不是当前机制。** `code-review/scripts/codex_review.sh` 早已用 `codex exec --disable hooks` 启动评审器，并且用 `codex features list` 做能力探测——`hooks` 不在受支持的生命周期状态就直接判 `codex_hook_disable_unavailable` 拒绝运行，防的正是「`--disable hooks` 静默 no-op」。这段代码在初始快照 `fb5da95` 里就存在，即缺陷记录当时它已在现役。所以「hook 把 bootstrap 注进每个评审器会话」与观察到的失败之间，缺少一环。

**当时为什么失败，不可判定。** 那两次运行的 packet（`6d6e2e86…` / `a7495373…`）从未落盘——仓里没有任何评审产物目录，哈希只作为散文出现在方案文档里。证据已不存在，无法回溯复检。可能是 codex 侧当时的模型/版本行为，也可能是别的调用参数；**本文不为它编一个根因**。

教训在取证：**评审 packet 与结论应当落盘**，否则一次失败在事后完全不可审计。

### 一个真实的相邻缺陷（调用侧）

复核过程中发现：`review_gate.py` 的 challenge 模式有三道**无文档**的必填前置，任何一道不满足都以 `next_action: stop_reviewer_lane` 秒退——这个返回值和"评审器真的坏了"在肉眼上难以区分。

| 前置 | 表现 |
| --- | --- |
| `--focus` 必填非空 | `challenge mode requires a non-empty --focus` |
| `--challenge-budget` 必须为正 | `challenge mode requires a positive challenge budget` |
| `--challenge-index` 是 **1-based** | `--challenge-index must be within the challenge budget` |

第三条是真缺陷：`review_gate.py` 要求 `challenge_index >= 1`，而 argparse 的默认值是 `0`——**默认值在 challenge 模式下永远非法**。尚未修复，单独立项。

---

以下为缺陷记录当时的原文。

## 影响（原文）

`skill-extraction-workflow` 规定任何非 wording 的 shared-skill 改动必须过 dual-track 闸（事实一致性 review + 对抗 challenge），且实现者同族的评审器要被排除。**在本仓，这道闸目前无法满足**——三个非 Anthropic 评审器全部失败。

影响面不止某一次改动：只要这个缺陷在，本仓每一次 shared-skill 改动都在没有独立评审的情况下落地。

## 现象

`IMPLEMENTER_FAMILY=anthropic`（排除同族 Claude）下经 `code-review` 网关：

| 通道 | 结果 | reason_code |
| --- | --- | --- |
| codex | inconclusive | `invalid_model_output`（`cascade_eligible: false`） |
| kimi | inconclusive | `tool_boundary_violation`（Kimi emitted an event outside the stream allowlist） |
| opencode | inconclusive | `transport_unverifiable` / `review_run_failed` |
| codex（收窄 packet 重跑） | inconclusive | `invalid_model_output` |

第四档落地时对着新候选独立复现了一次（不是沿用上表）：`--mode review` 与 `--mode challenge` 各一次，claude 仍在 preflight 被判 `same_family_as_implementer` 跳过，codex 仍返回 `invalid_model_output` 且 `cascade_eligible: false`，网关自己给出 `next_action: stop_reviewer_lane`（packet `6d6e2e86…` / `a7495373…`）。因为 codex 这条不是传输失败而是内容失败，网关不会级联到 kimi / opencode——所以上表后两行在这种形态下**根本不会被尝试**，这也是本缺陷比"三个通道都坏了"更难绕的原因。

绕开网关直连同样失败：

- `codex exec`（仓内）：只输出一句"我会按 `skill-extraction-workflow` 的深度评审路径执行……不会修改文件"就结束，无评审内容。
- `codex exec`（严格要求以 `VERDICT:` 开头）：assistant 输出为空，退出码 0。
- `codex exec`（改到仓库外跑、评审材料随 prompt 内联）：assistant 输出仍为空。
- `kimi -p`：整段回复都在推演"这个任务该路由到哪个技能"，然后被截断，无评审内容。

三个客户端本身都可用（`codex-cli 0.147.0` / `kimi 0.34.0` / `opencode 1.18.15`），不是安装或认证问题。

## 根因（原文——**已证伪，见「复核」节**）

`~/.codex/config.toml` 全局注册了 ccl-skills 插件，SessionStart 与 UserPromptSubmit hook 把路由 bootstrap 注入**每一个**评审器会话。评审器读到"按交付物路由到 owner、先挂技能再产出 substance"，就把"评审这份 diff"当成待路由的交付物处理，于是产出路由宣告而不是评审结论。

hook 是用户全局级的，所以把 cwd 挪到仓库外**不解决**——已验证。

附带信号：codex 每次启动都报 `Skill descriptions were shortened to fit the skills context budget`，说明技能清单本身已在挤占该会话的上下文预算。

## 修复方向（原文——第 1 条**早已落地**，见「复核」节）

1. **评审器侧关闭注入**——`codex exec` 需要一个能关 hook 的开关。已试 `-c hooks=false`，报 `invalid type: boolean, expected struct HooksToml`，说明该字段是结构体，正确写法待查。
   （**正确写法是 `codex exec --disable hooks`，写下本条时它已在跑**——陈旧信息，不是待办。）
2. **wrapper 侧声明豁免**——`code-review` 的各 wrapper 在启动被评审器时设一个环境变量，`hooks/session-start.sh` 认这个变量则跳过注入。这条最可控，因为豁免范围由 wrapper 而不是宿主配置决定。
3. **bootstrap 自述豁免**——在 bootstrap 里加一句"本会话若是受限评审通道，本块不适用"。最弱：散文规则不可靠，而且评审器已经证明它会照着 bootstrap 走。

## 验收

修复算完成的判据只有一条：`review_gate.sh --mode review` 在排除同族评审器的前提下返回 **schema 合法且 `findings` 为数组**的结果（`status` 为 `passed` 或 `findings`，不是 `inconclusive`）。任何"看起来能跑了"都不算。

## 与技能体系优化方案的顺序关系（原文，已无约束力）

修复大概率要改 `hooks/session-start.sh` 或注入条件，而该文件正是 `docs/skill-taxonomy-optimization-plan.md` 第四档要改的机器面文件之一，`bootstrap.md` 本身也要改名搬到 `agent-context/session-start.md`。

因此：**这项修复若与该方案同期进行，必须基于 `dev` 分支**，否则会写在一个即将消失的路径上，最终合并必然冲突。

（复核结论是无需修复，本节的排序约束随之作废。第四档的 dual-track 反而是靠这条通道跑出来的，见方案文档的执行状态。）
