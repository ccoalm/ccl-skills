---
name: worktree-isolation
description: 开工前先在独立 git worktree 里再改代码——**绝不在 main（主检出/main 分支）上开发**，任何迭代/功能/哪怕一行修改都先建分支+worktree（并发只是让这条更刚性，单人单线同样适用）；worktree 集成回目标分支后立即清理 worktree+本地分支+远端分支（让位见收尾节）。Never develop on the main checkout/branch — always create a dedicated worktree first (concurrency only makes it stricter, not a precondition); also covers teardown/cleanup when a worktree is integrated. 触发：凡要动代码，动手前先过本技能 Step 0（由 owner 在其实现阶段调用，本技能不抢交付入口）、并行做两个版本、改 ccl-skills 等共享仓库、被隔离闸 deny、worktree 干完要清理时。Skip when：交付级的重新开发/推倒重来/清除代码重来（"之前那版不要了，重新开发"）先回 product-rd-workflow 重新分类+重建计划——本技能只管 worktree 机制，不替代交付重入决定；product-rd 重入后仍按本技能 Step 0 先建 worktree 再动手，绝不在 main 上重写。
---

# Worktree Isolation（编辑隔离）

## 核心心法

主检出（main 那个工作树）是**干净的基线/集成点，不是开发现场**。每个迭代/任务在**自己的 worktree** 里做。并行的两个迭代 = 两个 worktree，互不碰主检出 → 天生不会 clobber。

**「天生不会 clobber」只覆盖 git 工作树 / 索引 / 分支——不覆盖仓外的共享运行时状态。** 独立 worktree 让并行 lane 互不碰彼此的 tracked 文件和 index，但不隔离仓外共享面,大致三类:①**共享服务/端口**——同一本机的测试库 / 消息队列 / 缓存服务、监听端口（如 `:3000`）、docker compose 工程名与卷；②**共享文件状态**——共享的 `.env`、跨 worktree 共享的可变 `node_modules` / `.venv` / build 输出 / 生成物目录、固定 `/tmp` 路径；③**主机全局配置与凭据**——`$HOME` 下的工具配置与 auth profile、`KUBECONFIG` / gcloud·kubectl 当前 context / cloud·registry 凭据、`~/.npmrc`、浏览器/设备 profile（切错 context 会让另一条 lane 的 migration/deploy/install 打到错误目标——是**权限/目标**级 clobber，不止数据）。两个 worktree 同时跑 `pytest` / migration / dev server / deploy 会在这些面互踩——一方的 migration 或 fixture 清库毁掉另一方、端口占用失败、缓存串写、或打到错误集群。所以并行前先隔离:每条 lane 独立的 DB/schema/namespace、不同端口、独立 compose project 与卷、每 worktree 自己的**可变**依赖安装/构建/输出目录、独立的 `KUBECONFIG`/配置 profile 并显式传 context 而非依赖全局当前值（并发安全的内容寻址/只读缓存可共享,不必强拆——如 pnpm store、Go module cache;cargo 仅指依赖下载缓存,**不含** `$CARGO_HOME` 的 config/凭据/`bin`/registry index/`target`;只拆会被并发写坏的可变面）;**隔离不了的共享面就把那部分工作串行**（呼应 `multi-agent-delegation` 的「共享 state / migration / 生成物就串行或留本地」）。单人单线顺序跑通常不触发,但共享库残留脏数据或残留的全局 context 仍可能跨 lane 串——按需重置。

**绝不在 main 上开发**：main（主检出 / main 分支）永远是干净基线/集成点，**不是开发现场**——任何迭代/功能、哪怕一行修改，都先建分支 + worktree 再改，**不论单人单线还是并发、不论是不是技能仓库**（worktree 很便宜，没有例外）。并发只是让这条更刚性，不是它的前提。

**绝不依赖 ambient cwd**（机械纪律，与上条并列）：多 worktree 下 shell 的 cwd 可能在**两次工具调用之间**被 harness 静默重置（常见回显 `Shell cwd was reset to <某路径>`；被重置的是 `cd` 出来的 shell cwd——宿主原生 `EnterWorktree`/`--worktree` 设的持久工作上下文不受此影响，对它 `git -C` 是双保险）。所以凡**必须落到某个特定检出**的操作都不靠"当前恰好 cd 在哪"：**git 变更**（`add`/`commit`/`merge`/`branch` 等）一律显式 `git -C "<abs-worktree-path>" …`（`-C` 等价于在该目录里起 git，pathspec 也按 `-C` 目录解析，故配绝对文件路径）；**文件写入**用绝对路径（宿主原生 Write/Edit 本就要求绝对路径，自动满足）；**确实需要工作目录的命令**（在 worktree 内跑 `pytest`/build/dev server，或本技能自己的 cwd 相关操作——Step 0 的 `worktree-status.sh`、收尾「在主检出里跑」的 `git worktree remove/prune`、`worktree-sweep.sh`）用单条 `cd <abs> && <cmd>` 在**调用当刻**设好工作目录，绝不假设它存活到下一次工具调用。为什么"cd 前先确认 cwd"不够：确认之后、下次调用之前 cwd 仍可能被重置，裸 `git commit`/相对路径就落到 cwd 当时指向的检出——多 worktree 下常是主检出，把提交落到**错的分支**，到 `ff-only` 合并才暴露（即收尾节「合并方向」条的"站错分支就会合进 B、信息却写着 C"）。命令若落到非 git 目录或空索引会**显式报错**，真正危险的是 add+commit 都静默落进主检出那种。诱因不止重置——删除已用 worktree 后路径复用同样让 cwd 失效（见收尾节「已删 worktree 的路径从此作废」），两者都是本条实例。

## Step 0：开工先自检（每次实现任务的第一步，agent 自己做，不等人安排）

先跑只读 preflight/status/lane inventory：

```bash
bash skills/worktree-isolation/scripts/worktree-status.sh --slug <task-slug>
```

- 结果 `SAFE` 且默认/基线分支已确证时才能编辑；`UNSAFE` 时不要编辑，先按脚本打印的 `git worktree add -b ...` 建功能 worktree，再进入新路径。若脚本提示 `default/base branch not confirmed`，先显式传 `--base <ref>` 或按下面的手工检查复核默认分支。
- 需要机器可读 gate 时加 `--json`；需要固定基线时加 `--base <ref>`；脚本只读，不会创建、删除、checkout 或改 git 状态。
- 这个工具借鉴 OMO worktrees 的 preflight、lane inventory 和 cleanup safety；本仓侧只采用这些能力。`.work/worktrees/<slug>` 是**新 lane 的默认/推荐路径**（每条 lane 的本地 metadata 约定放在 `.work/lanes/<slug>.json`），不是硬性安全条件：已存在的、不在 `.work/worktrees` 下的独立 worktree 只要满足硬安全条件（独立 worktree、命名功能分支、非 submodule、非 detached、干净树、基线已确证）仍算 `SAFE`，status 脚本只会对它打一条非阻断 warning 提示新 lane 用 `.work/worktrees`。不引入 `.slim/worktrees/` 目录约定，也不强制 `.slim/worktrees.json`。
- `.work/` 是本地工作目录和本地忽略目录（应被 `.gitignore` 忽略）。当前 status 脚本只读：只打印/JSON 暴露建议路径、metadata 路径和 metadata snippet，不写入 metadata；真正建 worktree 仍由你复制脚本打印的 `git worktree add -b ...` 命令完成。

脚本不可用时，按下面的手工检查兜底：

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# 防 submodule 误判：
SUPER=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)   # 当前分支
```

- `GIT_DIR != GIT_COMMON` 且非 submodule **且 `BRANCH` 非空、是个命名功能分支（不是 main/默认分支、也不是 detached）** → 已在独立 worktree 的功能分支上，直接干。
- 否则（在主检出，**或虽在某 worktree 但还停在 main/默认分支上、或 detached**）→ 先给本任务建**功能分支 + worktree** 再进去干（光在 worktree 里但分支是 main 仍是"在 main 上开发"，detached 也不行）：
  ```bash
  PRIMARY_ROOT=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" 2>/dev/null && pwd -P)
  git worktree add -b <iter-or-feature-name> "$PRIMARY_ROOT/.work/worktrees/<iter>" <base>
  cd "$PRIMARY_ROOT/.work/worktrees/<iter>"
  ```
  分支名/路径从任务本身推（迭代号/功能名）。Claude Code 也可用原生 `--worktree` / `EnterWorktree`。这里的 `cd` 只是给**首个动作**落位——**别依赖它存活到下一次工具调用**，后续每条 git 变更仍按核心心法「绝不依赖 ambient cwd」显式 `git -C "<abs-worktree-path>"`。
- **跨检出的同路径文件是不同文件**：刚进的 worktree 里，除非本会话已读过**这个 worktree 里的实际路径**，否则一律视为未读——不能凭另一份检出/上个会话的记忆直接编辑，先读本 worktree 的该文件再改。带 Read-before-Edit 闸的宿主会直接报错拒绝（反复重试白烧轮次）；没这道闸的宿主风险更高——可能按旧内容误改。编辑锚点（old_string 等）必须取自**刚读过的目标区域原文**：读过文件别处 ≠ 目标区域字节可信，grep/摘要片段的排版推断不算数（档案级 Read 闸拦不住这种区域级失配）；读取后该文件又被改写过（rebase/formatter/codegen/并发进程），或会话中断/休眠后恢复、期间该路径可能已被删除重建（见下文收尾节：路径复用不保身份），目标区域一律重新读取——worktree 身份本身存疑时（路径可能重建）先重验身份再谈读（可执行判据：`git branch --show-current` 必须等于本任务的功能分支名，不符即身份已换，停手重走 Step 0）；旧锚点仍能匹配时更危险，会把基于旧版本的改动写进新内容，甚至写进别的任务重建的同路径 worktree。

## 并行两个迭代（agent 驱动，人不参与）

```
主检出   = 干净基线（没人在里面开发）
迭代 A → 会话A：Step 0 → worktree-A(branch iterA) → 在里面干
迭代 B → 会话B/后台：Step 0 或 bgIsolation → worktree-B(branch iterB) → 在里面干
```
后台/二级会话由 harness `worktree.bgIsolation` 默认隔离（自动逼进 worktree）。

## 被隔离闸 deny 时

Claude Code 端有 PreToolUse 硬闸：直接改共享/并行主检出会被 deny，deny 文案带 `git worktree add` 命令。**照着建 worktree 再改即可**，不用找人。

## 推送、合并与收尾：到那一步再读对应 reference

下面这些只在开工之后的时点用到，按触发点拆到同目录 reference，开工（Step 0）时不必加载。本技能其它段落、always-on 层和合并相关 hook 所说的「收尾节」「合并执行协议（canonical）」都在 `references/merge-and-teardown.md`。

| 触发点 | 先读 | 承重义务（配方、命令与判据细节只在 reference） |
| --- | --- | --- |
| push / 建或更新 MR / 合并之前 | `references/pre-merge-landing-checks.md` | 落地对象必须已含全部预期改动：worktree 里未提交、本地 tip 未推送都算漏，以这次实际要合的 ref 的 head SHA 对预期 tip，不只信 `@{u}`；分支落后目标先更新再合，已推送/挂 MR 的分支默认并入目标或平台 update，不无脑 rebase；合并后看碰撞集的全内容 diff，`--stat` 不够 |
| 执行或报告任何合并、平台合并前 | `references/merge-and-teardown.md`「合并执行协议」 | 按用户目标判断授权，MR 本身不是授权；一次性立即合并，不开 auto-merge / 排队 / `--admin`，不直推默认分支；显式点名 MR/PR 并带 head SHA 守卫，flag 以本机 `--help` 为准；方向「源→目标」必须可读 |
| 已集成后清理 worktree / 分支 | `references/merge-and-teardown.md`「收尾」节 | 只在确认已集成后删（默认分支看平台 MR 在当前 head SHA 上的合并证据，squash 测不到祖先就保守保留）；删任何 worktree 目录前先跑 `git -C <path> status --ignored -s`，必须 exit 0，重算代价高的产物先救回；`git worktree remove` 不加 `--force`、`git branch -d` 不用 `-D`；永久/集成分支与名字含 `release` 的分支不自动删；承载未完成外部副作用的任务等它完成再清 |

落后分支的分流规则管破坏性改写（rebase 已共享分支），且台账 firing-path 锚点钉在这里，所以留在入口；`$TARGET` 的钉住步骤、冲突解析与合并后内容验证在 `references/pre-merge-landing-checks.md`。

把落后分支更新到最新目标——**先分清分支是否已共享**：

- **私有 / 未推送分支**：可 `git rebase "$TARGET"`。
- **已推送 / 挂着 MR / 别人可能在上面工作的分支**：默认并入目标/平台 “update branch”，**别无脑 rebase**；方向/报告见「收尾·合并方向必须可读」`-F`。rebase 前**必须读** `references/shared-branch-rebase.md`：`git fetch origin` 刷新目标；再 fetch 本分支一次（`git fetch origin <branch>` / `git fetch origin <branch>:refs/remotes/origin/<branch>`，择一），`remote_oid=$(git rev-parse FETCH_HEAD)`（禁读 `origin/<branch>`），推前勿再 fetch 本分支；必须原样 `git rev-list --left-right --count <branch>...$remote_oid`，右侧（远端独有）非 `0` 即并入、禁 rebase，`git diff` 不证拓扑；`0` 才 rebase；`--force-with-lease=<branch>:$remote_oid`，禁 `--force` / 裸 lease；post-push fetch，重审六项 thread / approval / mergeable / CI / commit / 行锚；工具合并重写/发布后逐层重验，绿前禁合并。
