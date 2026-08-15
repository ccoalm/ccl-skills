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

## 合并/落地前：确认"要落地的对象"已含全部预期改动（别落下 worktree 未提交 / tip 未推送的改动）

**要落地的对象**（push 的 remote 分支 / MR 的 remote head / 被合并的 tip）必须已含**所有本次要落地的改动**。两个常见静默漏项，尤其分支 checkout 在**独立 worktree**、不在当前检出里时：

- **worktree 里未提交的改动**：push/合并落地的是 commit 过的 tip，不含那个 worktree 工作区/暂存区里未提交的改动。
- **本地 tip 未推送**：本地 HEAD 领先 `origin/<branch>`，remote/MR head 还是旧的——合并那个 MR 会漏掉已 commit 但没 push 的改动。

漏了本该进的改动 = 落成**残缺版本**（本会话踩过：MR 已落地，worktree 里未提交的改动没进那次 MR，事后清理才发现）。这跟下面"落后"是**两条独立轴**（那条是分支落后于**目标**、旧快照盖回目标修复），也不同于"收尾清理前验干净"（那是集成**之后**，太晚，漏的已落地）。

push / 建 MR / 合并**之前**自证落地对象完整。下面是**给 agent 读输出用的诊断命令、不是自动闸**——真正要保证的是"**这次实际要合的 ref（MR head SHA / 你 push 的目标）= 你预期的 tip**"，别只信 `@{u}`（它只是本地配置的上游代理，可能不是这次的落地对象）：

```bash
git worktree list                                                    # 分支 checkout 在哪个 worktree？
# A) 分支在某 worktree 里（wt=该路径）：查未提交 + 未推送两轴
git -C "$wt" status --porcelain=v1 -b                                # 非空=有未提交改动；-b 行给 ahead/behind
git -C "$wt" rev-parse --verify @{u} >/dev/null 2>&1 || echo "无上游 → 先 push/set-upstream 再谈落地"  # 无上游时下一条会静默空跑，先兜底
git -C "$wt" rev-list --left-right --count @{u}...HEAD 2>/dev/null    # 右侧>0 = 本地领先上游、tip 没全推
# B) 分支没挂在任何 worktree：没有工作区=无"未提交"轴，但仍要查未推送；上游缺失要 fail-closed
git rev-parse --verify <branch>@{u} >/dev/null 2>&1 || echo "无上游 → 先 push/set-upstream 再谈落地"
git rev-list --left-right --count <branch>@{u}...<branch> 2>/dev/null # 右侧>0 = 本地领先、没全推
# 权威判据（比 @{u} 更硬）：取"这次实际要合的 ref"（MR head / 你 push 的 remote 分支）的 head，跟你的预期 tip 比 SHA
git fetch -q origin <landing-ref> && [ "$(git rev-parse FETCH_HEAD)" = "<你的预期 tip 的 SHA>" ] || echo "落地对象 ≠ 预期 tip：先补齐再合"
```

（`status` 只是脏树闸：子模块 WIP、被 ignore 的生成物它不显示；落地对象里若含生成物，另按预期产物清单 / 重跑生成校验确认。）

处置：

- **未提交、且属于这次落地** → 先 commit 再 push/合并；但只 `git add` **明确属于本次落地的路径**（先看 status/diff 名单），别 `-A` 一把梭把别人的 WIP / secret 顺带 commit。
- **本地领先上游** → **必须先 push** 到这次实际落地的 ref，让 MR head 等于你的预期 tip（平台 update-branch 只把目标并进分支、**不会**带上你未推送的本地 commit，别拿它替代 push）。
- **无关的独立 WIP** → 留着不动，这次落地对**它自己的目标范围**仍完整（无关 WIP 不算残缺）。
- **归属不清** → 按 product-rd 并发隔离规则留 pending，别替它 commit，也别默认算进这次落地。

## 合并回目标分支前：落后就先更新到目标分支（防 stale 分支静默回退目标已修复的内容）

并行/长活的 worktree 分支从某个旧基线分出去后，目标分支（main 等）往往又前进了（别的迭代合进来了）。这时直接合并这个**落后**的分支有个静默 data-loss 坑。注意 git 的实际行为：3-way 合并（含 `git merge --squash`）以 merge-base/目标/分支三方内容做合并——分支没碰过的文件保留目标版本；两侧改了**不同区域**的同一文件能各自合上；只有当分支的 diff **覆盖/改回了目标分支刚修复的那一块内容**（典型是分支**整文件重写/重新生成/格式化**了一个旧快照版本：跑了 formatter、重生成 codegen、改了 lockfile、一次大范围 find/replace），合并才会用分支的旧内容**把目标那次修复悄悄盖掉**。**squash 最危险**不是因为它机制不同，而是它把整个分支压成一个 commit、ancestry 与可审性最弱——这种回退不以独立 commit 出现，事后翻历史几乎看不出来。（别误判成两个极端：既不是"分支没碰过的文件也会被回退"，也不是"两侧都改过就一定回退"；坑只在**同一块内容被分支的旧版本覆盖**时。）

合并前（尤其 squash 前）按这个序走：

```bash
git fetch origin
TARGET=$(git rev-parse origin/<target>)            # 钉住这次要合的目标 SHA（origin 可能再动，后面都对着它验）
BRANCH_OLD=$(git rev-parse <branch>)               # 钉住"更新前"的分支 tip
OLD_BASE=$(git merge-base "$TARGET" "$BRANCH_OLD")  # 旧分叉点——必须现在算：更新分支后 merge-base 会变成 TARGET，碰撞集就空了
if git merge-base --is-ancestor "$TARGET" "$BRANCH_OLD"; then echo "分支已含该目标，无需更新"
elif [ $? -eq 1 ]; then echo "分支落后，需先更新到 $TARGET"
else echo "merge-base 出错（非 0/1），先排查别当落后处理"; fi
```

把落后分支更新到最新目标——**先分清分支是否已共享**：

- **私有 / 未推送分支**：可 `git rebase "$TARGET"`（历史更干净）。
- **已推送 / 挂着 MR / 别人可能在上面工作的分支**：**别无脑 rebase**（重写历史→要 force-push，会冲掉远端独有 commit、废掉 review 上下文）。改为把目标并进分支——按「收尾」节**「合并方向必须可读」**的 `-F` 配方执行并注明方向与目的（基线更新 merge 同受其管；ff 时按该条在交付报告里补方向），或走平台的 “update branch” 流程；非要 rebase 则按**一个固定次序**走，中间不得插入别的 fetch：① `git fetch origin <branch>`；② **立刻把这次实际取到的 OID 存成变量**——`remote_oid=$(git rev-parse FETCH_HEAD)`；别读 `origin/<branch>`：单分支 fetch 在 refspec 不匹配时只写 `FETCH_HEAD`、不更新 remote-tracking ref，读它可能拿到过期值（想用 tracking ref 就显式写 refspec `git fetch origin <branch>:refs/remotes/origin/<branch>`，但判断仍以记下的字面 OID 为准）；③ 拓扑检查对着**这个字面 OID**做——`git rev-list --left-right --count <branch>...$remote_oid`，要求右侧（远端独有）计数为 `0`（`git diff` 只比树、证明不了 ancestry，不算数），非零就停下先并入，不要 rebase；④ 再 rebase；⑤ 推送只用 `--force-with-lease=<branch>:$remote_oid`（绝不 `--force`）——**lease 要绑定你观察到的远端 OID**：重写前 `git fetch` 并记下 `origin/<branch>` 的精确 SHA，推送用 `--force-with-lease=<branch>:<observed-oid>`，远端在这之间被别人动过就会被拒。裸 `--force-with-lease` 拿**当下的本地 tracking ref**当租约：它挡得住你从没 fetch 过的远端更新，挡不住**你审阅之后 tracking ref 又被推进**——后台 fetch、IDE/工具自动 fetch、同一仓库里另一条命令都会把它刷成远端最新值，租约于是退化成「和远端现状比较」，等于没有租约，别人刚推的提交被你覆盖掉；显式钉住你亲眼看过的那个 OID 才能保证「变了就拒」；**重写推送之后重新 fetch，并把评审线程、approval、mergeable 状态、CI 状态当作全部失效重审**——重写前的 commit hash 和行内评论锚点不再是当前证据。若所用工具把"重写"和"发布"合成一步（stack 同步类命令）、无法在两者之间本地验证，就在它返回后立即对每一层重跑相关验证，验证通过前所有 PR 保持不合并。

**冲突解析就是回退的高发点**（rebase/merge 只是把碰撞提前暴露，不是修复本身）：冲突里**别直接取分支那侧的旧快照**。对生成物 / lockfile / 格式化产物，**从更新后的目标重新生成**，不要照搬分支版本，也不要 `-X ours/theirs` 一把带过——那等于亲手把目标的修复盖掉，而且事后 `--stat` 看不出来。

合并后**必须验证**，别假设干净——分两层，`--stat` 不够：

```bash
# 碰撞集：分支碰过、且目标自旧分叉点 OLD_BASE 后也改过的文件（最危险的那批）。用上面"更新前"钉住的 OLD_BASE/BRANCH_OLD，别用更新后的 merge-base
comm -12 <(git diff --name-only "$OLD_BASE" "$BRANCH_OLD" | sort) <(git diff --name-only "$OLD_BASE" "$TARGET" | sort)
# 设 AFTER = 合并后的目标 tip（集成完的 main）
# 1) 文件层：相对目标只新增了本分支预期改的文件，无意外删除/新增
git diff "$TARGET" <AFTER> --stat                  # squash 后亦可 git diff HEAD~1..HEAD
# 2) 内容层（关键，--stat 看不出文件内回退）：看"集成相对目标"改了啥，确认没把目标修复的行改回 OLD_BASE 旧值
git diff "$TARGET" <AFTER> -- <碰撞集文件>           # 出现目标已修复内容被改回旧值 = stale 回退红旗
git diff "$OLD_BASE" "$TARGET" -- <碰撞集文件>       # 对照：目标侧本应保留的修复（确认这些 hunk 仍体现在 AFTER 里）
```

`--stat` 只答“哪些文件、改了多少”，答不了“目标的新 hunk 是否幸存”——**文件内的回退** stat 看不出来，必须看碰撞集的全内容 diff。出现意外删除 / 目标修复被改回旧样 = stale 回退红旗，停下排查别推。本会话即按此做：每次 ff-merge 前先 `git diff <base>..origin/main -- <我改的文件>` 确认无碰撞、再 rebase、落后零碰撞才 ff。

（边界：这条管“合并前把分支更新到最新 + 合并后验证内容”；下面“收尾”管“已集成就清理”，两者是**独立的闸**——本节验证通过 ≠ 收尾的“已集成”判据成立，清理仍要单独按 ancestor/MR-merged 证明，squash 仍测不到祖先、仍保守保留。）

## 收尾：worktree 一集成就清理（本地 + 远端，不留垃圾）

worktree 的活一旦**集成进目标分支**就完了，立刻清理（唯一让位见下方清理序列的前置条件：未完成外部副作用任务等其完成）——别攒，**也别为"将来可能还用得上"保留已合并的临时 feature 分支**（发版 / 补丁 / 回查都从目标分支另起新分支，不复用已合并分支；"留着备用"是最常见的自我说服，攒着就是一堆 stale worktree/分支，要靠人回头扫）。Claude Code 宿主装有 `hooks/remind-post-merge-cleanup.sh`（PostToolUse）：合并命令跑完自动把本节清理清单注入会话作提醒——非阻断、best-effort，只提升"该清理了"的显著度，不替代本节的已集成判据与安全红线。**两条集成路径都要清**：

- **MR 路径**（远端分支合并）：合并时顺手删远端分支。
- **本地 merge 路径**适用于开发分支之间的同步 / 集成 / 基线更新。`main`/默认分支不走本地 merge；agent 不在本地把 feature 分支 merge 进 `main`/默认分支，也不 push 这种本地 merge 结果。
- **合并方向必须可读（源→目标）**：agent 执行或报告任何合并，都要让"哪个分支合进哪个分支"一眼可读。本地 merge 一律显式给信息，格式为 `Merge branch '<src>' into '<dst>': <一句话目的>`。目的句由 agent 自己撰写成一行——**不逐字复制**仓库/MR/外部文本（commit message 是持久 VCS 元数据，属 `product-rd-workflow` artifact-egress 门枚举的出口面，机密语义按该门处理；也别把 `[skip ci]` 之类 CI 指令 token 带进信息）。**任何来自仓库/MR/外部文本的内容（分支名、目的句）都不进 shell 插值**——git ref 名可以合法包含 `` `id` ``/`$(...)`，目的句同理，粘进双引号命令行即命令注入（对抗评审连续多轮各击穿一处插值后，配方收窄为免插值形态）：用编辑器/Write 工具把完整信息写进**仓外唯一**临时文件（`mktemp` 生成，别用固定 `/tmp/xxx` 路径——上文共享运行时状态警告同样适用，固定路径会被并行 lane 互相覆盖、合错信息还可能泄漏别条 lane 的目的句；别落在目标检出里被顺手 commit；git 只读不删，merge 后含失败路径都自己清掉），`git merge -F <信息文件> -- "$src"`（信息内容完全不经 shell；选项在 `--` 之前）。`$src` 同样不手拼：git ref 名可合法包含单引号，粘进任何引号形态的赋值都可能逃逸——从 git 输出赋值（如 `src=$(git branch --show-current)` 在源 worktree 里取、或 `git for-each-ref --format='%(refname:short)'` 列表选取；command substitution 的结果只作变量值、不会再被 shell 求值），agent 自建的分支可直接用自己起的安全名——执行前先核对当前分支确实是预期的 `<dst>`，并用 `git -C "<abs-dst-worktree>" merge`（别靠 cwd——cwd 会在工具调用间被重置，见核心心法「绝不依赖 ambient cwd」）：信息里的方向是标注不是校验，git 不会帮你验，站错分支就会"合进 B、信息却写着 C"（错误合并 + 虚假审计记录）；git 只在目标分支非默认分支时才自动补 "into <dst>"，且历史信息只有分支名、读不出目的；可 ff 时 `-m` 会被忽略（不产生 merge commit），按下面 ff 条款走报告；把目标分支合入 feature 分支更新基线的 merge 同样照此注明。ff-merge / rebase / squash 等不产生 merge commit 的集成方式，历史里没有方向记录——在交付报告里补上方向。（信息里的引号定界只是**人读标注**：ref 名合法含单引号时定界会歧义——机器可读的权威方向记录以交付报告与变量值为准，别拿 commit 信息做解析源。）平台合并（MR/PR）的 merge commit 自带方向，agent 的交付/执行报告仍统一写明「`<源分支>`（source head SHA=…）→ `<目标分支>`」，SHA 要点名是**源分支 head**（被评审的那个对象；已集成后可另附合并后的目标 tip SHA，两者别混写成一个含糊的 "head SHA"），别只说"已合并"。

**MR 不是合并授权**：agent 可以按任务需要 push 分支、创建/更新 MR、设置 remove-source-branch、查看 CI/MR 状态；这些动作只交付待审入口。创建/更新 MR 时也不得开启 auto-merge / merge-when-pipeline-succeeds / queued merge。未获合并授权，不得执行任何会让 MR/PR 现在或稍后变成 merged、或推进 `main`/默认分支的动作（例如 `glab mr merge`、`glab mr merge --auto-merge`、`gh pr merge`、`gh pr merge --auto`、平台 merge API / Web UI、目标是 `main`/默认分支的 `git merge` 或 `git push`；列表非穷尽）。本地开发分支之间的 merge/rebase/push 允许；把目标分支合入/变基到当前 feature worktree 分支用于更新基线也允许，但不得推进 `main`/默认分支。`这些要默认授权` 这类查看/推送/建 MR 授权不覆盖合并；过去轮次对别的 MR 的合并授权也不延续到当前 MR。

**合并执行协议（canonical——always-on 层「硬纪律 1」指向本节，两面同步修改；执行配方只放这里，不进 always-on 层）**：
1. **前置条件（先于以下所有条款）**：仅当用户明确下达合并指令后，才进入本节其余条款；未获指令时，本节任何合并命令都不得执行。指令有两种形态：**单个合并指令**（"合并"/"merge"/"land it" 等动词指令，指向当前对话中待合并的那个 MR/PR）；**批量合并指令**（"批量合并 N"，如"批量合并 30"——对 agent 已展示的发布计划授权至多 N 个平台合并，适用多仓依赖链/批量发布；额度自武装起 4 小时内有效，用户发送任何新消息即清除剩余额度，需 agent 重新请求）。事前一句"做完并合并"不算授权——交付完成后停在待审、等用户明确说合并。展示与确认的分工：agent 交付待审 MR 时照常展示 MR 链接、分支、head SHA、CI/验证状态（展示是 agent 的义务）；**批量授权前 agent 须已展示发布计划**（波次顺序、各仓及其 MR 或将要创建 MR 的方式），批量额度只用于该计划内的合并——计划外新出现的合并对象须重新请求授权；用户回一句合并指令即算授权，无需复述、点名或确认 SHA（点名确认不是用户的义务）。
2. **轻量确认**：若用户下达合并指令后分支又有新提交、或 CI/mergeable 状态明显变化，先向用户确认一句再合并（批量链式发布中 agent 自己按计划新增的提交/新建的 MR 属于已授权计划内，不触发此条）；若当前对话中有多个待合并 MR/PR，一句"合并"指向不明，先问一句是哪一个（"批量合并 N"则指向已展示的发布计划，无此歧义）；对象唯一且无变化则直接执行。
   **机械放行阀**（Claude Code 宿主）：合并授权闸（`hooks/guard-merge-authorization.sh`）会机器核验这条用户指令——UserPromptSubmit 哨兵在用户**单独回复**"合并/merge"（一次性布防）或"批量合并 N"（计数布防，每个平台合并消费 1 个额度，TTL 4 小时锚定武装时刻；见 `hooks/merge-authorization-prompt.sh` 的锚定匹配）时布防，闸在放行平台合并命令（`glab mr merge`/`gh pr merge`/merge API）时消费之；直推/直合 `main` 的形态与 auto-merge/排队/`--admin` 形态在任何授权下都永不放行；一条命令内多个合并调用会被拒——拆成逐条执行（批量授权下每条消费 1 个额度）。若合并命令仍被闸拦（授权词嵌在长消息里没被识别），请用户单独回复一句"合并"或"批量合并 N"即可，不要求用户改措辞之外的任何补偿动作；其他宿主（codex 等）无此机械阀，仍按 prose 执行。
3. **执行建议（agent 防呆，不增加用户负担）**：获授权后的执行一次性立即合并、不转 auto-merge/排队；显式点名目标 MR/PR（glab/gh 缺省都解析"当前分支"，同分支多 MR/PR 时会合错对象）；建议把自己已知的 head SHA 作为守卫传给命令：`glab mr merge <iid> --sha <head SHA> --auto-merge=false --yes` / `gh pr merge <PR号|URL> --merge --match-head-commit <head SHA>`（合并策略显式给 `--merge`/`--squash`/`--rebase`，缺省会进交互）。守卫被平台拒绝通常说明分支已变化——回到第 2 条向用户确认后再执行。**一次性合并授权按「命令被放行」消耗，不按「合并成功」消耗**：命令因你自己的参数错误而失败（自造不存在的 flag、SHA 用前缀而非平台现读的完整值、点错 MR 号）同样烧掉这次授权，用户得重新放行。所以执行前把 flag 与取值当成不可凭记忆的东西核一遍——**flag 拼写以本机该 CLI 的 `--help` 为准**（同名工具跨版本/跨平台差异很大，"我记得有这个 flag" 是最常见的烧授权方式），**SHA 一律从平台 API 现读完整值**（前缀补全会被守卫拒成 409）。已实测两次：一次前缀补全 409，一次自造 `--merge`（该版本 glab 无此 flag，合并策略缺省即 merge commit）——守卫两次都按设计挡住了错误合并，代价都是让用户重新授权一次。
4. **仓库策略例外**：仓库强制 merge queue / auto-merge、或只能直推默认分支时，停下把该仓的合并语义摆给用户裁决，不得套用立即合并流程近似执行。
5. **合并后自查**：合并后核对实际合入内容与本次交付预期一致，发现超出如实报告用户裁决（回滚/接受），不得静默带过。

**"已集成"判据**：`main`/默认分支只认平台 MR/PR 已在当前 head SHA 上完成 merge（或等价的、可追溯到该 head SHA 的平台合并事件）；开发分支之间可用 `git merge-base --is-ancestor <branch> <target>` 判断。squash 合并测不到祖先 → 当作"未确认集成"保守保留，别自动删。

**自动清理序列**（仅在已集成后，在主检出里跑，不在要删的 worktree 内。动手删之前先确认没有进程仍在使用该 worktree——cwd 在其中，或经其路径持续读写：开发辅助进程——watcher/dev server 之类——正常停掉；**承载未完成外部副作用的任务（迁移/部署等）绝不为清理而杀**，此时"一集成就清理"让位、等待即是正确的收尾，任务完成后再删。该让位只管**本地** worktree/分支的清理时点；远端分支仍按下方「远端分支」条跟随授权合并处理）：

**删 worktree 前先救 gitignored 产物**：`git worktree remove`（不带 `--force`）会拒绝脏树/未跟踪文件，但 **gitignored 文件不算"脏"**——worktree 里生成的 gitignored 内容**会随目录一起被删且 git 不会拒绝**，删后不可恢复。绝大多数（依赖目录、构建/测试产物、缓存、日志）本就该删；要救的是其中**重算代价高的数据产物**（data/、output/、feather 等跑很久才拿到的中间数据），所以删前要看一眼而不是一律保留。**批量清理开发分支间的已集成积压用 `worktree-sweep.sh <integration-ref>`**（按已安装技能根解析——常见候选 `~/.kimi-code/skills*/`、`~/.claude/skills*/`、本仓检出 `skills/`——定位后先 `test -x` 并**把探测输出给用户看**，缺失/不可执行不得凭记忆声明，给出证据才算降级；dry-run 对任何 ignored/未跟踪/脏文件机械判 KEEP（异常退出 exit 2/非零按没扫处理：停下查因，不得照删），KEEP 清单必须向用户列出并逐条处置，**不得**改用 `--force`/`rm -rf` 绕过、**不得**先手动删除被拒文件再重跑，`--include-ignored` 不是"清 KEEP 的开关"，但也不必事事请示：dry-run 的 KEEP 行下面会列出该 worktree 里到底是什么（最多 8 条 + 剩余计数），照它按下方判据③判——只剩可重生成产物（.venv、node_modules、构建/测试产物、缓存、日志）就直接用它清掉，遇到**重算代价高的数据产物**（跑很久的中间数据、采集结果、训练产物）或拿不准才保留。注意该 flag 是**整批生效**、不是逐个挑选：一批里混了贵产物就别整批加它，先单独处理那一个；`--apply` 会清掉所有判定可删的，绝不碰远端；默认分支目标它保守 KEEP——默认分支的已集成判据是平台 MR 合并证据，见「批量清积压」条）。**任何方式删除单个 worktree 目录之前**（`remove` / `--force` / `rm -rf` / IDE / 外部工具，含让位等待结束后的补删），都必须先 `git -C <worktree路径> status --ignored -s` 扫 gitignored 产物（别省 `-C`：从主检出对另一 worktree 的路径直接跑 `git status` 会报 "outside repository"）。三条硬判据：① 该命令**必须 exit 0**——执行失败（报错/非零退出）按没扫处理，停下查原因，**不得**把失败时的空输出当作"扫出来为空"继续删；② 输出非空即逐条判定保留/丢弃并向用户列出结论；③ 判据看**重算代价**，不看"是不是 gitignored"——可重生成产物（.venv、node_modules、构建/测试产物、coverage、缓存、日志）直接丢，不必请示；重算代价高的数据产物（跑很久的中间数据、采集结果、训练产物）先 rsync 回主检出（成本低），拿不准按后者处理。worktree 是否已集成同样不自评：默认分支看平台 MR 在当前 head SHA 上的合并证据，开发分支用 `git merge-base --is-ancestor <branch> <integration-ref>`。（`git worktree prune` 只清登记不删目录，不在此前置范围；sweep 本身也不适用此前置——它的 `has_local_state` 是比手工扫更严的内置检查：同样对 `git status` 非零**闭式失败**判 KEEP（reason 写 `unscannable`），不把失败时的空输出当"干净"，拒绝即停。）

```bash
<skills根>/worktree-isolation/scripts/worktree-sweep.sh <integration-ref>  # 批量积压 dry-run 机械判定（先 test -x）：ignored/脏/未跟踪/status 非零判 KEEP；KEEP 清单向用户列出逐条处置，不得 --force 绕过；--include-ignored 仅在确认只剩可重生成缓存时用
git -C <path> status --ignored -s  # sweep 之外的手工删除前必须先跑且必须 exit 0；非空即按重算代价判定，可重生成的直接丢、贵的先 rsync 救回
git worktree remove <path>      # 删本地 worktree 目录（不带 --force：脏树/锁会拒绝→先查原因，别强删）
git branch -d <branch>          # 删本地分支（-d 不是 -D：未合并会拒绝=安全网）
git worktree prune              # 清残留登记
git worktree list && git branch # 验证：都没了
```
- **已删 worktree 的路径从此作废**：任何还停在该路径上的 shell/会话立即 `cd` 离开，别让后续命令以它为 cwd 跑（会遇到 "Unable to read current working directory" 一类怪错）。落脚主检出只作**停靠点**——不在那里开发，要继续干活按 Step 0 重新建 worktree。旧路径不经 `worktree add` 不得直接复用作 cwd：目录"还存在/又出现"不代表还是原来那个 worktree（可能已被并发任务重建），需要续做就从主检出重新 `worktree add`（同一路径亦可——add 会重建登记），禁止的是凭记忆直接 `cd` 进残留或来历不明的目录接着干。（删除导致的路径失效与核心心法「绝不依赖 ambient cwd」的 harness 重置是同一失败类的两个诱因——git 变更一律 `git -C "<abs>"`，不靠 cwd。）
- **远端分支**：待审 MR 的远端分支不是 stale；MR 已由用户授权合并后，才用平台的 remove-source-branch 或 `git push origin --delete <branch>` 清理。不要为了“顺手删远端分支”去触发 MR 合并。本地开发分支 merge 后可按已集成判据清理对应开发分支；`main`/默认分支没有本地 merge 清理路径。**当 MR 的源分支本身是永久/集成分支时（如 `dev`→`main` 的 promotion，源是 `dev`），绝不设 `remove-source-branch`、也不删除它——该 flag 只用于临时 feature 分支；删掉 `dev`/集成分支会摧毁团队集成点。** 临时 feature 分支合并进**任何**目标分支（含 `dev`/集成分支，不止 `main`/默认分支）后，都随授权合并清理其源分支（本地 + 远端）；例外见下两条。

  **例外一：源分支自身是永久/集成分支时不删**（上一句）。

  **例外二：分支名含 `release` 的一律不自动删除**（`release/*`、`release-1.2`、`hotfix-release` 等，大小写不敏感、匹配分支名任意位置）。判据是**名字**不是拓扑：发布分支合并后仍要留着打 tag、追溯发版内容、出补丁，而它在 git 拓扑上与临时 feature 分支毫无区别——「已合并」在这里不蕴含「可删」。要删由用户显式指名，agent 不自动清理，也不设 `remove-source-branch`。同理，`remove-source-branch` 在建 MR 时就要按这条判断，别等合并后才想起来。**发布分支的命名是各仓的约定**（`rc/1.2`、`stabilization/v2`、`hotfix/*` 都真实存在），本条只把 `release` 定为关键字且**刻意不做成可配**——三轮对抗评审各找出一种「配置传不到下一个克隆」的形状（env 只保护导出它的那一次、`.git/config` 是单克隆的、新 CI 克隆直接丢），每次都在追脚本自己不拥有的东西；硬编码在共享脚本里反而随技能走到哪都在。别的叫法**不受自动保护**，这是明写的残留风险：sweep 在 `--apply` 前会把完整 KEEP/REMOVE 计划打给人看，而删除本来就只由用户指名。要重新加配置源，先解决它怎么到达一个全新克隆。
- **安全红线**（承 `testing-strategy` 的破坏性清理纪律）：只在**确认已集成**后删；用 `git worktree remove`（不 `--force`）+ `git branch -d`（不 `-D`）——未合并/脏树被拒绝正是防误删未交付工作的网；**绝不盲删主检出/默认分支**，绝不为图省事 `--force`/`-D`。

**批量清积压**：已攒下的 stale worktree 用 `scripts/worktree-sweep.sh`——默认 **dry-run 只打印**，`--apply` 才动手；它只适合清理开发分支之间可用 ancestor 证明的积压。对 `main`/默认分支的 MR 分支，不能只靠“tip 已是默认分支祖先”判定可删，必须先有平台 MR/PR 在当前 head SHA 上已合并的证据；拿不到证据就保守保留。脚本跳过主检出/目标分支/detached/脏树（含 gitignored 产物）/`git status` 扫不动的/未合并，绝不碰远端。它的 `--include-ignored` 会把"只剩 gitignored 内容"的 worktree 判为可删，且**整批生效**。按判据③用即可：dry-run 会在 KEEP 行下列出实际内容，只剩可重生成产物（.venv、node_modules、构建/测试产物、缓存、日志）就直接清，遇到重算代价高的数据产物就把那个 worktree 单独拎出来处理、别整批加 flag——本节要救的是后者，不是所有 gitignored 文件。

> **交互式 merge 选项菜单**（PR vs 本地 merge vs 保留分支）：若装了 `superpowers:finishing-a-development-branch`，route 给它出菜单走流程；本技能管的是"**已集成就自动两侧清理**"这条收尾 gate + 批量 sweep。Step 0 检测与 `superpowers:using-git-worktrees` 一致，可直接用其原生 worktree 工具；本技能是本仓侧"默认隔离 + 并行迭代 + 收尾清理"策略与硬闸说明。
