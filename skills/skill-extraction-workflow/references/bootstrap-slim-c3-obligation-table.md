# bootstrap.md C-3 最终义务表

本表是 MR !505 的可复查 semantic-control 证据。比较基线为 MR !505 的 merge-base；最终 `bootstrap.md`
为 18262B（基线 18664B，减少 402B / 2.2%）。

## 行集与分类

对基线文件和最终文件运行
`skills/skill-extraction-workflow/scripts/governing-chain-diff.py BEFORE_FILE bootstrap.md`
得到 25 行；另保留工具长度阈值未覆盖的 R34，共 26 行。

- `merged`：bootstrap 保留完整 carrier；canonical 重复不改变分类。
- `subsumed`：bootstrap 删除 carrier，canonical 保留完整 carrier。
- `dual`：必须拼合两个 carrier 才能得到完整义务；两个 carrier 可在同一文件，也可跨 bootstrap / canonical。

终态：`merged 24 / subsumed 1 / dual 1 = 26`。

### 逐字恢复后退出机械行集

以下 8 行在 takeover 后恢复为基线 carrier，因此不再被 diff 工具推导，未计入 26 行：R13（集成回目标分支）、R17（push 分支、创建/更新 MR、查看状态不等于授权）、R20（待审 MR 向用户展示）、R21（单个合并指令的用户主体）、R22（批量合并指令的用户主体与发布计划对象）、R23（任意新消息清除额度）、R24（两种形态无需复述/点名/SHA）、R31（codex#6426 完整链接）。每项原文均在最终 bootstrap 中各出现一次。

## 最终 26 行

| ID | 义务 | 状态 | 最终 carrier / 证明 |
|---|---|---|---|
| R1 | 自动建议渠道枚举 | merged | bootstrap 保留会话注入、技能包、宿主原生清单、自触发技能四类 |
| R2 | 宿主强制预检及作者判据 | merged | `宿主自身撰写` 与 system/developer 判据仍同句 |
| R3 | 技能自述强制只算渠道自荐 | merged | `技能条目自述"我是强制预检"` 唯一存活 |
| R4 | 执行不等于入口 | merged | `执行≠入口` 唯一存活 |
| R5 | 先路由 owner，再调用阶段技能 | dual | bootstrap 本句 + 后续 product-rd 路由项共同承载 |
| R6 | 风险 tags 与 gate 的 owner | merged | `风险 tags 与 gate 归 feature-risk-router` |
| R7 | 技术方案/评估/选型词的限定条件 | merged | 完整五项词组与 `仅当交付物是新/变更能力或项目级·跨阶段方案` 同句 |
| R8 | 窄产品产物升级回 product-rd | merged | `跨 owner 生命周期仍回 product-rd-workflow` |
| R9 | 单 bug / 窄 stack 不升级 | merged | `不升级 product-rd` |
| R10 | 共享闸或跨仓语义回 product-rd | merged | `仍回 product-rd 的 shared-gate 分类` |
| R11 | 只解锁 owner-dispatch；其他动作仍需用户授权 | merged | `只解锁这道闸` 与授权清单同句 |
| R12 | worktree 隔离无单人/并发/技能仓例外 | merged | `没有例外：单人/并发/技能仓库同样适用` |
| R14 | 外部副作用任务让位及迁移/部署示例 | merged | `承载外部副作用的未完成任务（迁移/部署等）——等其完成再清` |
| R15 | 让位只影响本地 worktree/分支；远端仍按授权 | merged | `该让位只管本地 worktree/分支清理时点，远端分支仍按授权合并处理` |
| R16 | 清理配方归 canonical | merged | bootstrap 指向 worktree-isolation 收尾节 |
| R18 | 创建/更新 MR 禁开自动合并 | merged | auto-merge / merge-when-pipeline-succeeds / queued merge 枚举完整 |
| R19 | 未授权不得 merged 或推进默认分支 | merged | `平台 merge API/Web UI` 与 `目标是 main/默认分支的 git merge/git push` 枚举同在未授权禁令内 |
| R25 | 事前“做完并合并”不算授权 | merged | `事前"做完并合并"不算授权` |
| R26 | 指令后提交或状态变化须向用户确认 | merged | `先向用户确认一句再合并` |
| R27 | 多个待合并 MR 须向用户消歧 | merged | `先问清是哪一个` |
| R28 | 机械放行阀存在，细则归 canonical | merged | bootstrap 保留阀存在性与 canonical 指针 |
| R29 | 哨兵单次/计数布防机制 | subsumed | `skills/worktree-isolation/SKILL.md` 的 `UserPromptSubmit 哨兵在用户**单独回复**` 唯一完整 carrier；bootstrap 不复制布防细节 |
| R30 | 直推 main / auto-merge 永不放行及 canonical 指针 | merged | bootstrap 同时保留永不放行绝对句与 `以该节为准` |
| R32 | 自审收敛后再交独立评审 | merged | `可证明的实现者自检` 与 `预期通过再交评审` |
| R33 | 自审覆盖分支/路径/状态与四个风险轴 | merged | security/privacy/authority/数据丢失轴完整 |
| R34 | invoke 闸枚举引导语的误计数修正 | merged | `硬判据：` 后仍有 ①②③④ 四项 |

## 阈值盲区复核

默认 `min_chars=25`，含 CJK 文本的有效 floor 为 16。对基线和终态额外以
`min_chars=1` 解析，再从低阈值变化中扣除默认行集，原始结果为：

```console
$ python3 -c 'import importlib.util,subprocess,sys; p="skills/skill-extraction-workflow/scripts/governing-chain-diff.py"; s=importlib.util.spec_from_file_location("gcd",p); m=importlib.util.module_from_spec(s); sys.modules[s.name]=m; s.loader.exec_module(m); b=subprocess.check_output(["git","show","69d16032:bootstrap.md"],text=True); a=subprocess.check_output(["git","cat-file","blob","ec0ba4fd3fe4"],text=True); ch=lambda n:{(o.key,o.chain) for o in m.parse(b,min_chars=n) if (o.key,o.chain) not in {(x.key,x.chain) for x in m.parse(a,min_chars=n)}}; low=ch(1); default=ch(25); x=sorted(low-default); print(f"low_changed_removed {len(low)}"); print(f"default_changed_removed {len(default)}"); print(f"subthreshold_changed_removed {len(x)}"); [print(f"effective_len={m.effective_len(k)} text={k}") for k,_ in x]'
low_changed_removed 26
default_changed_removed 25
subthreshold_changed_removed 1
effective_len=11 text=三条硬判据：
```

同一结果的紧凑记录为：

```text
low_changed_removed 26
default_changed_removed 25
subthreshold_changed_removed 1
effective_len=11 text=三条硬判据：
```

因此 R34 是默认 floor 唯一发生 changed/removed 的基线义务；本结论只证明基线义务保全，
不声称枚举终态新增的低阈值文本。

## 可复跑机器证据

权威是下列命令对当前文件的实时结果，不是本表或 source-register 的声明：

```console
$ git diff --quiet -- bootstrap.md skills/skill-extraction-workflow/references/source-register.md skills/skill-extraction-workflow/references/bootstrap-slim-c3-obligation-table.md; echo $?
0
$ git rev-parse --short=12 :bootstrap.md
ec0ba4fd3fe4
$ test "$(git rev-parse :bootstrap.md)" = "$(git rev-parse ec0ba4fd3fe4)"; echo $?
0
$ git cat-file blob ec0ba4fd3fe4 | wc -c
   18262
$ git cat-file blob ec0ba4fd3fe4 | rg -o -F 'UserPromptSubmit 哨兵' | wc -l
       0
$ rg -o -F 'UserPromptSubmit 哨兵' skills/worktree-isolation/SKILL.md | wc -l
       1
$ git cat-file blob ec0ba4fd3fe4 | python3 skills/skill-extraction-workflow/scripts/governing-chain-diff.py <(git show 69d16032:bootstrap.md) /dev/stdin
governing-chain-diff: /dev/stdin
derived row set: 25
$ ruby skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb .
register_firing_path_resolution_ok (237 locators resolved)
```

`69d16032` 是本 MR 已记录且唯一解析的 merge-base；`ec0ba4fd3fe4` 是候选 `bootstrap.md`
的 blob 身份，短 ref 若将来产生歧义会由 Git 报错，而不会静默换成别的内容。首条
`git diff --quiet` 证明 review 时 resolver 所读的三份工作树文件与 index 相同；提交后 blob
只有在候选不再改写并确实进入 landing commit 时才随 commit 保留。landing 后必须运行
`test "$(git rev-parse HEAD:bootstrap.md)" = "$(git rev-parse ec0ba4fd3fe4)"`；非零即说明评审后
内容漂移，不得沿用本表结论。该 commit-state 等值检查在 commit 产生前不能伪报执行。
两条固定串计数分别证明 R29 的 bootstrap carrier 为 0、canonical carrier 为 1。

- **Landing 后必须验证候选 blob**：提交后必须执行上述 `HEAD:bootstrap.md` 等值检查；非零时必须阻断交付并重新冻结候选证据。
`governing-chain-diff.py` 返回 1 表示行集非空，是本次预期结果。历史提交的 17998B / 31 行
快照不作为终态证据。
