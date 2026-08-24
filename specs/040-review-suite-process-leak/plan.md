# 040 — code-review 套件的进程泄漏

Status: **实现完成、八轮独立评审已处置 + 对抗轮，待合并授权** —— 分支 `worktree-040-review-suite-process-leak`，base `origin/dev` `9c11837`（起轮时 `f2bb7b9`；评审期间 dev 两次前进——PR #29 的 039、PR #31 的 041——各 rebase 一次）。

## 分类与路由

| 项 | 值 |
| --- | --- |
| artifact classification | `gate implementation`（改 CI harness `skills/code-review/scripts/test_review_gate.sh`，新增断言即改 failure semantics） |
| risk tags | `shared-gate`（主）、`release-ops`（本套件在 CI 关键路径上） |
| 不适用 tags | `visible-ui` / `api-contract` / `permission-access` / `money-quota` / `write-finality` / `data-migration` / `ai-*` |
| required gates | RED-first 证据；`make test-code-review`；`make test-repo-gates`；独立评审（shared-gate 强制，本地全绿不可替代） |
| 计划/状态验证器 | `python3 scripts/check-spec-references.py .`、`bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`（均实跑 rc=0） |

## 症状（一手观测）

主机上一个 `claude_review.sh --timeout 5` 进程：**存活 39 小时、ppid=1、扛住 SIGTERM，要 SIGKILL 才死**。该 wrapper 是 `test_review_gate.sh` 的 fake 反馈器，不是任何真实评审 CLI。

## 复现

基线 `f2bb7b9`，darwin 25.4.0。

| 实验 | 手法 | 实测 | 结论 |
| --- | --- | --- | --- |
| 0 控制组 | 完整跑一遍套件 | 2m31s、EXIT=0、`ps` 无残留 | **正常路径不漏**——泄漏是中断条件下的 |
| 1 | 抓到任意 `--timeout 5` wrapper 后 SIGINT 套件 | 不漏 | 抓到的多是秒退的正常用例 wrapper（`--timeout 5` 跨多种 behavior） |
| 2 | 组 SIGTERM | 不漏 | bash 在等前台子进程时**推迟** TERM，控制器得以跑完自己的杀进程路径 |
| 3 | 组 SIGKILL + 杀"第一个" `review_gate.py` | 不漏 | 杀错了控制器（同名进程多个），真控制器仍活着并自行回收 |
| **4** | **定向抓 `--focus process-group-timeout` 的 wrapper，杀它的真实父进程 + 套件组** | **wrapper ppid=1、持续存活、`kill -TERM` 无效** | **复现成功，与一手观测同形态** |

实验 1–3 三次同框失败是有信息量的：它们排除了"杀套件就漏"这个直觉版本，把成因逼到「控制器先于自己的超时路径死掉」这一条。

## 根因链（五环，各有出处）

1. 控制器用 `start_new_session=True` 起 wrapper（`skills/code-review/scripts/review_gate.py`）。wrapper 是独立 session leader，**任何打向套件进程组或控制终端的信号都到不了它**。这是控制器的正确设计（它要能整组回收），但同时切断了外部兜底。
2. `hang` fixture 让 wrapper 与其子 shell 都 `trap '' TERM`——故意对 TERM 免疫。
3. 于是回收**完全依赖控制器活到执行 TERM→KILL 那段**。控制器先死（树杀、CI 取消、外层超时、主机休眠），就再没有任何进程会杀它。
4. 套件侧兜底不覆盖它：EXIT trap 只杀 `escaped_hang_child_pid` 一个，且**只挂 EXIT，不挂 INT/TERM/HUP**。
5. **39 小时的使能项**：`hang` 分支是 `while :; do sleep 1; done`——**寿命无界**。对照组是同文件的 `escaped_hang`，其后代明确写了 300s 上界并注明理由。同一份 fixture 里两个 TERM-免疫进程，一个有界一个无界，无界那个就是能活 39 小时的那个。

## 一处被实测推翻的判断（它改了修法）

起草时判断「用例只断言 `hang_child_gone`、不断言 wrapper 自身」是泄漏成因之一。**实测推翻**：控制组显示正常路径下 wrapper 必死，断言缺口不产生泄漏；且 `hang_child_gone` 是**更强**的断言——那个子 shell 的 pid 控制器根本不知道，**只能**被进程组信号杀到，而 wrapper 是控制器的直接子进程，`process.kill()` 就够。`escaped_hang` 那边断言 wrapper 不断言后代，是因为该用例**极性相反**（后代必须仍活着以证明控制器没等管道），不是可照搬的先例。故本轮**不补** wrapper 存活断言，改为补一条套件级的「退出时不留活口」断言。

## 修法（终态）

| # | 改动 | 关掉哪一环 | 兜底强度 |
| --- | --- | --- | --- |
| F1 | `hang` fixture 寿命上界 300s（两个 stub 都改；可经 `REVIEW_GATE_TEST_HANG_SECONDS` 覆盖，供探针 leg 2 用） | 第 5 环 | **最强**：即便整棵树被 SIGKILL、无 trap 可跑，孤儿也在上界内自消 |
| F2 | 套件按「进程组记录 ∪ 私有 WORK 路径」扫描并回收（先杀组再杀 pid），trap 扩到 `EXIT INT TERM HUP` | 第 4 环 | 覆盖 Ctrl-C / harness TERM / CI 取消等可 trap 的中断 |
| F3 | 退出时断言：本轮启动的进程一个都不许还活着（有界 settle 10s，排除僵尸） | 断言缺口 | 验收物是干净的进程表，不是绿的用例 |

F1 与 F2 不是二选一：F2 让常见中断**即时**清理，F1 让**不可 trap 的硬杀**也有上界。控制器侧（`review_gate.py`）不改——实测其回收逻辑本身是对的。

**为什么归属判据是「组 ∪ 路径」而不是其中之一**：wrapper 的 `( ... ) &` 子 shell 在 `ps` 里与 wrapper **同 cmdline**，所以按 wrapper 自己的 pid 记台账只覆盖半个组（实测：突变控制器为 no-op 后，三个 wrapper 活过套件而 pid 台账报告"无泄漏"）；纯路径扫描又漏掉 argv 里根本不含本轮路径的自有后代（实测：一个 `sleep 999` 只被组那一路抓到）。**已知残余边界**：既主动 `setsid` 脱离本组、又不含本轮路径的后代两侧都逃得掉——`escaped_hang` 的后代正是故意这么做的，它有自己专属的清理。进程组号会被 OS 复用，故 `reset_case` 顺手剪掉「已无存活成员」的记录，把陈旧窗口压到单个用例之内。

## 验收矩阵（决策表）

| 输入条件 | 期望判定 |
| --- | --- |
| 完整跑完套件，无中断 | 全绿；F3 断言 `ok`；退出后 `ps` 无残留 |
| 跑到中途收到 SIGINT / SIGTERM | 套件退出；在飞 wrapper 及其组被 KILL；退出后无残留 |
| 整棵树被 SIGKILL（不可 trap） | 孤儿存在，但 ≤ 寿命上界后自消；不得出现小时级存活 |
| 控制器仍在、正常超时路径跑完 | 现有 `hang_child_gone` 等断言维持绿（不得因本轮改动放宽） |
| 本轮启动的进程仍存活（含 argv 不含本轮路径者） | 套件红，点名每个 pid 并打印其 `ps` 行 |

## 探针

`skills/code-review/scripts/test_review_gate_abort_leak.sh`，落位 `make test-code-review-abort-leak` + CI 独立 job `code-review-abort-leak`。两条腿各锁一个机制，共 7 个断言：

- **leg 1（可 trap 的中断）**：等目标 wrapper 在飞 → 杀其控制器 → 有界确认「控制器确已消失且 wrapper 已被 reparent 到 ppid=1」→ SIGTERM 套件 → 断言 trap 回收了它。
- **leg 2（不可 trap 的中断）**：同样的前置 → **SIGKILL** 整棵树（回收器必不运行）→ 断言 wrapper 先存活（证明确无回收器）→ 再在 fixture 自身上界内自消。

前置确认放在两条腿共用的 `orphan_target_wrapper` 里：`kill` 返回不等于目标已死，而 leg 2 随后杀套件组时可能顺带杀掉控制器，那样每条断言都会通过而所需的先后顺序从未成立。

## 证据（全部实跑）

| 证据 | 对象 | 实测 |
| --- | --- | --- |
| 控制组 | 候选套件完整跑 | 全绿、无 stderr、残留 0（2m34s，基线 2m31s） |
| RED（leg 1） | 基线套件 | 前置三条绿后第三腿红：wrapper 存活 30s、ppid=1 |
| RED 差分（leg 1） | 只去掉 INT/TERM/HUP trap（保留上界） | **只有 leg 1 红**，leg 2 绿 |
| RED 差分（leg 2） | 只去掉 hang 上界（保留 trap） | **只有 leg 2 红**，leg 1 绿 |
| RED（F3，路径侧） | 突变控制器 `signal_reviewer_process_group` 为 no-op | F3 红并点名 3 个泄漏 wrapper；EXIT reaper 仍把它们收干净 |
| RED（F3，组侧） | 上条 + `hang` stub 多起一个裸 `sleep 999` | F3 红并点名 **`sleep 999`**（argv 不含本轮任何路径），只可能来自进程组那一路 |
| RED（F3，脱组后代） | 把 escaped 后代的 inline kill 与 trap 清理**同时**改成 no-op | F3 红并点名那个 ppid=1 的 python 后代；此前它对两侧记录都隐形 |
| 全量 | `make test-code-review` / `make test-repo-gates` | 均 rc=0（含 `lane_isolation_ok: 45 lane members, 0 unreviewed`、impact-chain、firing-path） |

## 实现与探针自身被推翻的四处（都是先绿后被证伪）

1. **pid 台账不成立**：`( ... ) &` 子 shell 与 wrapper 同 cmdline，按 wrapper pid 记的台账只覆盖半个组。改为「组 ∪ 路径」。
2. **扫描器自匹配**：`awk -v a=<路径>` 让 awk 自己的 argv 含该路径，`ps -e` 于是把扫描器数进去——干净跑也报泄漏，且诊断时那个 pid 已消失。改为经环境变量传 needle。
3. **探针按时长挑目标**：挑到的是 `passed_slow`（sleep 5）这类会自己退出的 wrapper，对**有缺陷的基线**也绿。改为按用例名 `--focus process-group-timeout` 定位。
4. **诊断重定向顺序反了**：`ps ... 2>/dev/null >&2` 先把 fd2 指向 `/dev/null`，再把 fd1 复制到"当前的 fd2"，输出全进 `/dev/null`——一次失败点得出 pid 却描述不了它们，连着三次观测到。改为 `>&2 2>/dev/null`。

第 2 条还顺带说明 F3 需要有界 settle：最后几个用例的 wrapper 可能正在退出，直接判定会把 flaky 当承重。

## 独立评审（shared-gate 强制）

reviewer 均为 **codex**（OpenAI 族，与实现方 anthropic 不同族），`native_skill_binding=established`，`review_plan_source=implementer-supplied`。

**第一轮 7 条**：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | 探针在选中 wrapper 与读其父进程之间可能发生 reparent/pid 复用，随后无条件 `kill -KILL`——root 容器里可能杀到 PID 1 | **采纳**：信号前三重校验（数字且 >1、仍是该 wrapper 的父进程、cmdline 含本轮私有 tmp 路径），不满足则不发信号 |
| 2 | P1 | 回收器只匹配 `harness/scripts/`，套件起的其他后代活着也不被看见 | **采纳**：先放宽到整个 `$WORK/`，第二轮再补进程组一路 |
| 3 | P1 | 探针只验回收器；把上界改回无界它照样绿 | **采纳**：上界可覆盖 + 新增 leg 2（SIGKILL 整棵树） |
| 4/5/6 | P1/P1/P2 | diff "删除了" firing-path 可达性块 / 整个 `specs/039-design-first-shrink/` / `test_parse_probe_result.sh` 一条用例 | **不成立（基线假象）**：评审期间 `origin/dev` 前进（PR #29 合入 039，`ad5f5a6`），候选基于旧 dev，两点 diff 把 039 落地内容显示成删除。三点 diff 恒为 6 文件。处置是按 `worktree-isolation` 规则 rebase 到 `ad5f5a6`（台账冲突按 append-only **两侧都保留**） |
| 7 | P2 | "不占关键路径"只有注释支撑，无 CI 实测 | **部分采纳**：改成可兑现的说法（见下） |

**第二轮 4 条**（对 rebase 后的新候选）：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | 路径扫描是**代理谓词**：自有后代若 argv 不含 `$WORK`（裸 `sleep`）则既不报红也不被回收，与"本轮启动的进程都要让断言变红"这条验收不符 | **采纳**：两个 stub 开头记录自身**进程组**，扫描与回收改为「组 ∪ 路径」，`reset_case` 剪除死组记录。敏感度实证：裸 `sleep 999` 被点名（见证据表） |
| 2 | P1 | `orphan_target_wrapper` 不验证 `kill` 是否生效就返回；leg 2 随后杀套件组可能自己把控制器带走，于是断言全过而顺序从未成立 | **采纳**：前置确认（控制器消失 + wrapper ppid=1）上提到两条腿共用的 helper 内，有界 10s，失败即报 setup 错 |
| 3 | P2 | 该 job 是必需分支，而注释自承 CI 耗时未测，本地数字支撑不了"不占关键路径" | **采纳**：**删掉**该验收断言。改为陈述可兑现的事实：本机空载 262s、两个分片本机各 ~350s，CI 数字未测；`timeout-minutes` 是唯一硬界。首次 CI 跑完后把实测写回本节 |
| 4 | P2 | 本计划文档自相矛盾：状态仍写"开轮"、base 是旧的、还在描述 pid 台账与"五腿"、110s/262s 并存 | **采纳**：本文件整体重写为终态一致版本 |

**第三轮 2 条**（对最终候选）：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | 后代若 `setsid` 脱组再 exec 一个裸命令，则既不属任何已记录的组、argv 也不含本轮路径，两侧归属判据都逃得掉 | **驳回并保留记录**（不是遗漏，是可移植原语的边界）：`setsid` 后 session 与组都是新的、父进程被 reparent 到 init，进程本身已抹掉一切可归属标记；Linux 上要靠 cgroup / PID namespace 才行，macOS 无对应且远超测试 harness 的职责。本仓的 `escaped_hang` 后代**正是故意这么做的**，它有自己专属的清理。该边界已同时写在代码注释与本文修法节 |
| 2 | P1 | 探针 `cleanup()` 用**缓存的** `suite_pgid` 与早前扫到的 pid 直接发信号；组号/pid 会被复用，可能打到无关进程组 | **采纳**：发信号前对**当前**进程表重新证明归属——某组只有在仍含携带本探针私有 tmp 路径的存活进程时才会被整组信号，其余一律按 pid（而那些 pid 刚由同一路径判据重新匹配过） |

**第四轮 1 条**（同类第二次触发，故不逐点打补丁）：leg 2 那句刻意的硬中断仍用**缓存的** `suite_pgid` 发信号——与第三轮第 2 条同一类。**采纳，并按同类复现的规矩全枚举**：把探针里所有指向套件的信号（leg 1 的 TERM、leg 2 的 KILL、cleanup 的兜底）统一收进 `signal_suite`，发信号前先证明「该 pid 仍在跑本套件脚本、且仍领着我们记录的那个组」。这里**不能**用 tmp 路径成员判据——按设计，组里唯一带该路径的成员（控制器）刚被杀掉；靠一个能点名的存活成员来验证组号才是可行的那条。

**第五轮 1 条**（同类第三次触发 → 全矩阵自枚举）：pgid 记录本身仍是未经验证的归属凭据——组空了而记录还在时，若组号被复用，`prune_dead_pgid_records` 会看到"有存活成员"而保留记录，回收器就会杀掉陌生人的进程组。**采纳**：记录里存下**组长的启动时刻**，每次读取都重新证明。三种情形，中间那种正是记录仍可被信任的理由：

| 当前状态 | 判定 |
| --- | --- |
| 组长在，启动时刻与记录一致 | 是我们的 |
| 没有任何进程占着 `pid == pgid` | 是我们的：组长已死，仍带该组号的只能是它的后代，且再没人能成为该组组长 |
| 组长在，启动时刻不一致 | 组号被复用——删记录，永不对该组发信号 |

本轮所有归属谓词的全矩阵（这是第三次同类触发，按仓规不再逐点打补丁）：① 指向套件的信号 → `signal_suite` 重新证明；② 探针 cleanup 的路径匹配 pid → 当场重新扫描；③ 套件回收器的路径匹配 → 本就是实时扫描；④ 套件回收器的 pgid 记录 → **本条**，改为自证；⑤ 探针杀控制器 → 早已三重校验。矩阵闭合。

**第六轮 3 条**：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | `suite_is_ours` 用 argv + pgid 认身份，但 job control 下套件的 pgid 就等于它自己的 pid，两条件塌缩成"这个 pid 在跑这个脚本"——同一套件的另一次运行拿到复用 pid 也满足 | **采纳**：把**启动时刻**并入身份判据（与 pgid 记录同一手法），矩阵里最后一个用间接凭据认身份的成员就此闭合 |
| 2 | P1 | escaped 后代主动 setsid 脱组且不含 WORK 路径，两侧记录都看不见它；其清理若被改坏，新断言也发现不了 | **采纳**：它是残余边界里**唯一本套件知道 pid 的**成员。该用例自己的 pid 文件会被它的清理一并删掉，故另落一份 `state/audit/escaped_pid`（该用例与 `reset_case` 都不清它）并纳入退出断言。实证：把 inline kill 与 trap 清理**同时**改成 no-op，退出断言点名了那个 ppid=1 的 python 后代——此前它完全隐形 |
| 3 | P2 | 探针只由这个新 standalone job 承载；若 main 的 required checks 没有它，它就是非阻断的 | **交接项，非代码问题**：改分支保护要仓库管理员操作。已写入本节遗留与 PR 正文——合并后需把 `code-review-abort-leak` 加进 main 的 required checks，否则本轮的闸只是"能跑"而不是"卡关"（035/036 两轮也是这样由用户改的） |

**第七轮 3 条**（第三、四次同类变体 → 不再逐点修，改做结构切分）：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | 组空后组号被复用、且新组长起了子进程后自己退出，`ps -p <pgid>` 就查无组长——我的"无组长即是我们的"那一档会把陌生组认成自己的并整组杀掉 | **采纳，但用结构切分而不是再加一层校验**：**报告可以宽，发信号只能窄**。组分三档——组长在且启动时刻吻合＝已验证（既报也杀）；查无组长＝只报不杀；组长在但启动时刻不符＝删记录。共享闸上，误报一次红跑的代价远小于误杀陌生人的进程组 |
| 2 | P1 | `state/audit/escaped_pid` 只存了个裸 pid，复用后会把无关进程报成本轮泄漏 | **采纳**：记录里并存启动时刻，与其余归属判据同一手法 |
| 3 | P1 | 探针只以 standalone job 存在；plan 自己也写着还需加进 required checks，那它就不阻断合并 | **仍为交接项**：分支保护不在本 diff 的可改范围内（仓库管理员操作），已记入遗留与 PR 正文 |

**到此停止逐条追加**。第三～七轮全部落在同一类（"发信号前证明归属"）的越来越窄的变体上，而本仓 `scripts/test_lane_isolation.py` 自己写下的立场就是这条：*"successive review rounds will always be able to name one more shape. Chasing them one at a time buys less than being honest about the boundary."* 结构切分（报告宽/信号窄）把这一类里**危险的那一半**一次性关掉，剩下的是明写的边界，不是欠账。

**第八轮 3 条**（两条是新类，不是同类变体）：

| # | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| 1 | P1 | `live_wrapper` 取第一条匹配的 `ps` 行，但 wrapper 与它 `( ... ) &` 起的子 shell **共用 cmdline**；若内核先列出子 shell，下一步就会把 **wrapper 本身**当成控制器——而 wrapper 的 cmdline 恰好满足 tmp 路径校验，这个错会一路通过并杀错进程 | **采纳**：改按**血缘**选取——wrapper 是那个"父进程是控制器（cmdline 含 `review_gate.py`）"的匹配项，不再依赖 `ps` 的输出顺序 |
| 2 | P1 | `LEG2_HANG_BOUND=45` 与"某 hang 用例 `--total-timeout 50`"矛盾，注释里引的又是 25s | **采纳（改的是理由不是数值）**：真正的约束是**控制器传给 wrapper 的 `--timeout`**（abort 之前的 hang 用例里 claude 恒为 5s、fallback 由那些用例自身断言 <12s），而不是约束整个 gate 的 `--total-timeout`。45 对最大值留了约 4 倍余量。注释已改成可从 packet 直接核对的表述 |
| 3 | P1 | required checks（第三次提出） | **仍为交接项**，见遗留 |

**第九轮（tracked review + challenge 对，同一冻结候选）**：

| 来源 | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| review | P1 | leg 1 的判据"wrapper 没了"本身是**代理**：wrapper 那个 TERM-免疫的子 shell 可能还活着，腿却通过，而探针自己的 cleanup 随后把证据抹掉 | **采纳**：判据改为**整组**——记录 wrapper 的 pgid，要求该组无存活非僵尸成员，且探针私有路径下无残留，才算通过 |
| review | P1 | required checks（第四、五次提出） | **仍为交接项**，见遗留 |
| challenge | P1 | cleanup 从扫描到 `kill` 之间存在 TOCTOU：那个 pid 可能已退出并被复用 | **部分采纳**：发信号前紧邻再验一次 cmdline，把窗口压到一次 `ps` 的宽度。**剩余 TOCTOU 关不掉**——shell 没有可移植的 kill-by-handle，这是明写边界不是疏漏 |

组判据的差分：造出"裸 argv 的组成员 + 回收器不杀组"后**两条腿都红**并点名幸存成员；旧的 pid 判据在同一形态下会放行（首次尝试的差分没能隔离出这一点——当时子 shell 与 wrapper 同 cmdline，路径扫描已把它一并杀了，所以那次突变根本没造出洞。这一条如实记下）。

**探针选择器的第三次改版（不是评审提的，是全量跑出来的）**：加了血缘判据后，探针单独跑连续绿，但在 `make test-code-review` 里**两条腿都在 setup 就红**（`abort_leak_probe_unreached`，各烧满 420s）。

- 先怀疑 `ps` 在非终端下按宽度截断、而 `--focus process-group-timeout` 恰在 argv 尾部 —— **实测否定**：make 下与直接跑一样，最长命令行都是 2002 字符，无截断。
- **真因未查实**，如实记下。当时探针也分不清两种失败（"套件正常但没跑到 hang 用例"与"套件先死了"），这本身是诊断缺口，已修：两种情形现在分别打印，其中一种还会带上套件退出码。
- 选择器改为读**套件自己的 state**（`state/claude_behavior == hang`）再按血缘选 wrapper：不再依赖 argv 如何渲染，且命中的是**第一个** hang 用例而非最后一个。`make` 下实测转绿，耗时从 4m27s 降到 3m00s。

**第十轮（最终 tracked review + challenge 对，冻结候选 `e47381d`）**：

| 来源 | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| review | P1 | 组长身份只用 `lstart` 认，而 `ps -o lstart=` 只有**秒级**粒度——同一秒内被复用的 pid 会认错 | **采纳**：组长必须同时满足「启动时刻吻合」**且**「命令行含本轮私有 WORK 路径」（我们组的组长必是 wrapper）。用 shell `case` 做精确子串匹配，不写正则、无需转义 |
| review | P1 | setsid + 裸 argv 的后代仍逃得掉 | **同第七轮，驳回并保留记录**：可移植原语下无法归属 |
| review | P2 | 「stock macOS 的 BSD find 不支持 `-maxdepth`」，`reset_case` 会静默不清理 | **驳回并附实测证据**：本机 `find` 其实是 Homebrew 的 bfs，所以第一次验证不算数；改用 `/usr/bin/find` 复验——rc=0、顶层文件已删、子目录保留。BSD find 支持 `-maxdepth`，该前提不成立 |
| review | P1 | required checks（第六次提出） | **仍为交接项** |
| challenge | P1 | setsid + 裸 argv（同上） | 同上，驳回 |

**评审到此收束**。最后一对里已无新类：两条是明写边界的复述，一条前提与实测相反，一条是仓库管理员的配置动作。真正被采纳并改掉的是那条秒级粒度。

十二轮 43 条的收敛形状：第一轮 4 条采纳 + 3 条基线假象，第二轮 4 条全采纳，第三轮 1 采纳 1 驳回。采纳项全部落在「谓词是代理还是不变量」和「信号前先证明归属」这两类上。

**第十一轮（extraction gate 触发的 owner 扫描 + 对最终候选的 dual-track，7 条）**：

| 来源 | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| owner 扫描 | — | `testing-strategy` **已经**拥有这一类，且其措辞正是许可无界写法的那句 | **updated**：按 rule-consolidation 并入既有条款（不新增 bullet），补「far past 但不得无界」与「套件自己 owns 回收」两半，零损失核对了原条款全部义务 |
| review | P1 | 探针只盯 claude stub，**把 `candidate_stub` 的上界改回无界它照样绿** | **采纳（新缺口，真的）**：加 `ABORT_LEAK_PROBE_CLIENT` 选择器；差分实证——只改 candidate stub 的上界，**leg2/fallback 红而 leg2/claude 绿**。覆盖结构随之写清：**回收器是一份共享代码**（leg 1 证一次即够），**上界每个 stub 各一份**（leg 2 逐个证） |
| review | P1 | 套件回收器扫描后到 `kill` 之间未重证归属（与探针同类，但我只在探针里修了） | **采纳**：两处发信号点（wrapper 回收器、escaped 后代 trap）都改为紧邻重证 cmdline 含本轮 WORK 路径 |
| review | P1 | setsid + 裸 argv（第四次） | 驳回，边界已明写 |
| review/challenge | P1/P2 | required checks（第七次）、frozen acceptance 与已实测的 CI 数字不一致 | 前者仍为交接项；后者是我自己的 acceptance 措辞过期（当时未测、现已测），已改为实测表述 |

**第十二轮（收束轮，4 条）**：

| 来源 | 严重度 | 结论 | 处置 |
| --- | --- | --- | --- |
| review | P1 | `kill -0` 对**僵尸**也成功，而 leg 2 的判据排除僵尸——一个已死的 wrapper 会同时满足"杀完后仍活着"与"随后消失"，让该腿在上界从未被行使的情况下通过 | **采纳**：前置改为要求存活且非僵尸 |
| review | P2 | 路径判据不对称：`probe_processes` 认逻辑与物理两种写法，而紧邻重证、`live_wrapper`、控制器校验只认物理——symlink 主机（macOS `/var`→`/private/var`）上会漏掉本探针自己起的进程 | **采纳**：四处统一认两种写法 |
| challenge | P1 | `review_owned_pgids verified` 先缓冲后循环，验证与 `kill` 之间仍有窗口 | **不再打补丁，改为明写残余**：shell 里没有把「证明」与「发信号」绑定的原语，每一轮评审都能点出更窄的一例。代码能做的是把证明放到尽可能晚（已是紧邻发信号）并把危险的一半收窄（只对有已验证存活组长的组发信号；无组长的记录只报不杀）。这段话已写进 `reap_review_wrappers` 的注释 |
| review | P1 | required checks（第八次） | 交接项 |

**收敛判定**：最后一轮里 review 的两条是**具体且新的**（僵尸假通过、路径不对称），已修；challenge 的一条抵达该类的不可约核心，明写而非再修；剩一条是仓库管理员的配置动作。同类补丁已无新形态可关。

## Owner-generalization map（按生命周期影响推导，非凭记忆）

| owner | 方向 | 状态 | 改了什么 / 为什么没改 |
| --- | --- | --- | --- |
| `code-review` | 本体 | **updated** | 缺陷与修法所在：`scripts/test_review_gate.sh`、新探针 `scripts/test_review_gate_abort_leak.sh`。`SKILL.md` 未动（不改路由与规则面） |
| `testing-strategy` | sibling（同类通用规则的 owner） | **updated** | 它**已经**拥有这一类（`references/ci-fixtures-and-flake-control.md` 的 sleep-replacement 条款），但其措辞「push that lifetime far past any plausible run」正是许可无界写法的那句。按 rule-consolidation **并入**该条款而非新增 bullet，补上两半：寿命须有界、以及**套件自己**owns 回收（不能委托给被测组件） |
| `skill-extraction-workflow` | 台账 | **updated** | 两条 impact-chain 行（`code-review`、`testing-strategy`），append-once 与改动同一 commit |
| `defect-diagnosis` | 上游（诊断方法） | unchanged | 本轮的诊断纪律（先证明前提再读绿、三次同框失败反而定位成因）已被其现有「不得在读到失败方自身证据前下根因裁决」覆盖并**实际触发**了——本轮正是照它走的，无未触发缺口 |
| `product-rd-workflow` | 上游（shared-gate 分类） | unchanged | 其 shared-gate 分类规则本轮**正常触发**：产出了 artifact classification + 持久化 plan + feature-risk-router 路由，无缺口 |
| `terminal-cli-dev` | sibling（进程/信号机制） | unchanged | 本轮的 signal/session/process-group 机制是**测试 harness 的自清理**，不是终端渲染/PTY/输入面；该技能被评审 gate 选为 owner 并实际参与了评审，但无需改其规则 |
| `platform-release-engineering` | 下游（CI 落位） | not-applicable | 改动只新增两个 CI job 与 Makefile 目标，未触碰 rollout/灰度/回滚语义 |
| `worktree-isolation` | 流程 | unchanged | 本轮两次「落后分支先 rebase」按其现有规则执行，规则已触发、无缺口 |
| `test-artifact-management` | 下游（TC 文档） | not-applicable | 本轮无结构化测试用例文档/Bitable 记录 |

## 状态同步目标

`skills/skill-extraction-workflow/references/source-register.md` 台账行（按本仓 append-once 规则，与改动同一个落地 commit），以及本文件的 Status 行。

## 遗留

- **`code-review-abort-leak-1` 与 `code-review-abort-leak-2` 需加进 main 的 required checks**（仓库管理员操作）。不加则这两个 job 会跑但不阻断合并——评审连提六次的就是这条。
- ~~CI 实测耗时未获取~~ **已兑现，且实测推翻了我的第一版处置**：
  - 首次 CI（run 32672861414，全绿）：`code-review-abort-leak` **213s，是最长分支**（次长 `code-review-regressions-2` 188s）——评审警告的情形确实发生了。
  - 第一版处置按"leg 2 的等待是大头"把 fixture 上界 45s→25s。第二次 CI（run 32673779089）：**214s vs 190s**——**动了 1s，等于没动**。模型是错的：成本大头是**每条腿各要跑一整轮** `test_review_gate.sh`，不是那段等待。
  - 终版处置：CI 把两条腿拆成**两个并行 job**（`code-review-abort-leak-1` / `-2`）。第三次 CI（run 32674745023）实测 80s / 111s；补齐 per-stub 覆盖后终态实测 **177s / 114s**，最长分支 188s ——**本轮新增的闸对关键路径零成本**。本地 `make test` 仍两条都跑；25s 的上界保留（让 leg 2 更短且仍留约 2 倍余量）。
- `hang` 寿命上界取 300s（对齐 `escaped_hang`）。若将来某用例的预算超过它，需同步抬高——目前最大是 50。
- 既 `setsid` 脱组、又不含本轮路径的后代不在归属判据覆盖内（见修法节的残余边界）。
