# 推送 / 建 MR / 合并前的落地检查

worktree-isolation 的按触发点拆分页：push、建或更新 MR、合并**之前**读本页。入口 `SKILL.md`「推送、合并与收尾」节保留本页两节的承重义务清单；文中「下面/下文的收尾」「收尾节」指同目录 `merge-and-teardown.md` 的「收尾」节。

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

把落后分支更新到最新目标：先按入口 `SKILL.md`「推送、合并与收尾」节里的「已共享分支」分流硬规则执行（私有分支可 rebase，已推送/挂 MR 的分支默认并入目标或平台 update；台账 firing-path 锚点钉在入口），再回到下面的冲突解析与合并后验证。

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
