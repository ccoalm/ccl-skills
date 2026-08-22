# 架构总览（速查）

> 这是维护者入口：一屏看清当前目录、路由、分发与治理边界，以及与外部技能包的关系和跨项目安装方式。

本仓是 Agent Skills 的**唯一入口层**：交付入口与生命周期 gate 永远在本仓 owner 技能。外部技能包按「条件性外部依赖」处理，不构成分层：

| 外部包 | 当前关系 |
|---|---|
| superpowers | 仅少数能力被条件 route(worktree / 写计划 / writing-skills):装了就 route,没装按本仓技能内联原则执行,不留悬空引用 |
| gstack | 对标参考源:benchmark 找 gap 时比对,不是运行时依赖 |

> 历史备注:本仓最初按「三层分工」(superpowers 通用方法 / gstack 工具运行时 / 本仓业务规则)设计,实践后收敛为上述「唯一入口 + 条件性外部包」;本文的三层旧表述长期未随之更新,2026-08 修正。教训照旧:给人读的文档没有门禁守护,权威始终在可执行面(技能文本、注入、hook)。

## 目录结构

| 路径 | 作用 |
|---|---|
| `skills/<name>/SKILL.md` | 技能入口:触发、路由、核心流程、硬规则。**首读区**,要短要可扫描 |
| `skills/<name>/references/*.md` | 深度:清单、模板、场景矩阵、案例。SKILL.md 用指针引到这里 |
| `skills/<name>/agents/openai.yaml` | Codex 端接口 overlay(display_name / short_description / default_prompt) |
| `skills/skill-extraction-workflow/` | 元技能:如何提炼/更新/评审技能(贡献规则的权威来源) |
| `skills/skill-extraction-workflow/scripts/check-ccl-skills.sh` | 仓库验证门禁(frontmatter / overlay / 泄漏 / 路由 / 引用),内含 F4 Tier-1 路由分析器 |
| `skills/skill-extraction-workflow/scripts/eval-routing*.rb` · `eval-golden-trace.rb` | F4 路由有效性 harness(静态分析器 / 廉价 grader / 真 agent 回放),见治理段 |
| `hooks/` | 三端共用的运行时护栏；Claude Code 与 Codex 直接消费 plugin hooks，OpenCode 通过原生事件 adapter 调用同一批脚本。`hooks.json` 把 10 个脚本挂在 7 个事件上；另有 `session-context.sh` helper 和 6 个 `test_*.sh` |
| `agent-context/session-start.md` | 注入每个会话的路由指引(被 SessionStart hook 加载) |
| `agent-context/subagent-start.md` | 子 agent 派活时的 owner 路由约定(被 SubagentStart hook 加载) |
| `AGENTS.md` · `opencode.json` | OpenCode / 通用 agent 开工契约、项目级技能扫描配置和高频场景 command |
| `scripts/install.sh` · `Makefile` | 安装/更新/清缓存/跑门禁与 eval(`make help` 列全部目标) |
| `scripts/control-plane/` · `scripts/owner-dispatch/` · `scripts/verify-sandbox/` | 给产品仓装的 gate backstop、owner 派发闸、沙箱校验(`make install-gates` 一键装) |
| `eval/` | F4 用的任务库和夹具:路由任务、golden trace、技能有效性、行为夹具 |
| `packages/` | 对外分发物：统一 npm 包 `ccl-skills-npm`（三端 CLI、离线资产与发布校验）加 OpenCode 插件源码 `opencode-plugin` |
| `.github/workflows/ci.yml` · `.githooks/` | GitHub Actions 门禁接线和本地 git hook |
| `docs/` | 给人读的手册和本仓 review;agent 执行用的门禁/模板仍在各技能 `references/` |
| `.claude-plugin/{marketplace,plugin}.json` · `.codex-plugin/plugin.json` | 两端 plugin manifest |
| `.agents/plugins/marketplace.json` | Codex 端 marketplace 清单；Codex 与 Claude 清单都使用本仓 GitHub HTTPS 源 |
| `opencode.json` | OpenCode 仓库本地配置:加载 `agent-context/session-start.md` 和 `skills/`,便于在源仓内直接使用/验证技能；若同时装了全局 `~/.agents/skills`,以当前 OpenCode 实际加载结果为准 |
| `packages/opencode-plugin/ccl-skills.ts` | OpenCode 原生 plugin：注入 bootstrap，把 prompt、tool、subagent 和 session-idle 事件适配到 bundled hooks，并对 `edit`、`write`、`apply_patch` 执行主检出隔离 |
| `packages/opencode-plugin/commands/` | OpenCode command 模板源:安装到 `~/.config/opencode/commands/` 或项目 `.opencode/commands/` 后提供 `/ccl-*` 入口 |

## 路由模型

- **描述驱动**:每个技能的 `description` 是路由面,AI 客户端据此自动加载。写法纪律见 `skills/skill-extraction-workflow/references/description-authoring.md`。
- **入口路由器**:跨阶段交付先走 `product-rd-workflow`,它再分派设计/架构/dev/测试/发布。
- **会话注入**:`agent-context/session-start.md` 经 SessionStart hook 注入 Claude Code 与 Codex；OpenCode 在源仓内通过 `opencode.json` 加载，在安装场景由原生 plugin 的 system transform 调用 bundled `session-start.sh`。
- **OpenCode 原生路径**:`scripts/install-opencode.sh` 默认同步 skills、commands、plugin、bootstrap 和 `ccl-skills/runtime`，并兼容刷新 `~/.agents/skills`；`--project` 把同一闭包同步到当前仓 `.opencode/`。
- **运行时拦截**:路由没走对也拦得住这一层,靠 hook 在动手那一刻校验,不靠模型自觉。

| 事件 | hook 干什么 |
|---|---|
| `SessionStart` · `SubagentStart` | 注入 `agent-context/` 下同名文件的路由纪律 + 当前 repo/branch/head/dirty/近期提交等会话上下文 |
| `PreToolUse` | 四道闸:编辑隔离(主检出/`.worktree-only`)、owner-dispatch、合并授权、委托 owner 校验 |
| `UserPromptSubmit` | 合并授权哨兵——用户单独回"合并"/"批量合并 N"时布防 |
| `Stop` · `SubagentStop` | 收尾核 owner 是否真被调用、技能改动是否挂过提炼 |
| `PostToolUse` | 合并命令跑完注入 worktree 清理清单(非阻断提醒) |

## 分发与更新

整库是一个**多端 plugin**，并通过 `packages/ccl-skills-npm` 作为唯一 npm 分发入口；CI 验证单一 tarball，受保护的 tag workflow 才能发布。

安装、autoUpdate 边界、`make update` / `prune-cache` 的真实行为见 [`README.md`](../README.md) 的 "Install and update" 段。要点:autoUpdate 只定期刷 marketplace 元数据、不保证当场重装;可靠更新用 `make update`(Claude 必须 `plugin update`,`install` 会 no-op;Codex 要 `marketplace upgrade` + `plugin add` 两步;OpenCode 装的是当前 checkout、自身不联网拉)。

## 治理

共享技能需要比通用工具层更严格的 provenance 与泄漏治理。GitHub Actions 会在 push 和 pull request 上执行仓库门禁，但 workflow 文件本身不会建立分支保护或强制 review；这些属于仓库管理设置，声称已启用前必须单独核验。

- **一条命令复现 CI 判定**:

  ```bash
  CCL_SKILL_BASE_REF=origin/main bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .
  ```

  看末行:`ccl_skill_check_clean_ok` 才是干净落地;`ccl_skill_check_interim_ok` 表示私有泄漏审计没跑过——可 push、可开 MR,但不可标 clean。
- **阻断项**:R0 泄漏、结构与元数据、路由存在性与跨包引用、入口体积增量(单入口 50KB / `agent-context/session-start.md` 净增长)、语义同步、影响链登记。以门禁输出和对应 validator/reference 为准。
- **建议层(不挡合并)**:`make eval-routing-bank`(廉价模型路由回归)、`make eval-golden-trace`(真 agent hub 回放)、`make eval-health`(综合分与趋势);方案见 [F4 技能有效性 Harness](f4-skill-effectiveness-harness.md)。
- **不在这条命令里的门**:dual-track 评审(独立 review + adversarial challenge,评审员由 `code-review` 挑)、契约同步(`check-agent-contract-coverage.sh`)。

贡献流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。
