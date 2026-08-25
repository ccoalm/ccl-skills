# 044 — abort-leak 探针 leg2：基线断言换成结构性不变量

## 分类与路由

- **Artifact classification**: `gate implementation`（改的是 CI 必跑闸 `code-review-abort-leak-1/-2` 的判定逻辑，以及共享套件 fixture）。
- **本轮改变 failure semantics**，因此按 `shared-gate-artifact-classification.md` 先落此持久化 plan 再动手。
- **risk tags**: `shared-gate`（主）、`release-ops`（CI harness）。
- `security-review`: `not-applicable` —— security posture unchanged：不涉信任边界、不可信输入 sink、认证授权语义、凭据、数据可见性，改的是测试探针。
- **required gates**: `product-rd-workflow`（owner，已入）、`testing-strategy`（闸有可执行/变异测试行为）、动共享分支前的独立评审（`code-review`）。
- **skippable**: `visible-ui`、`api-contract`、`permission-access`、`money-quota`、`data-migration` —— 均无对应改动面。
- **verifier discovery**: 仓库 agent 契约（`AGENTS.md:55`）声明的权威校验器为
  `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`；实现前已跑，结果
  `ccl_skill_check_ok` / `ccl_skill_check_clean_ok`（exit 0）。无其他 plan/status 专用校验器。

## 症状与既有证据

CI run `32778411813`，job `code-review-abort-leak-1`，leg2/fallback：

```
21:16:50.0833872 ok   - leg2: the controller was removed and the wrapper reparented to init
21:16:50.1027043 ok   - leg2: the killed suite exits without running any cleanup
21:16:50.1029600 FAIL - leg2: no reaper ran, so the wrapper is still alive right after the kill
21:16:50.1164892 ok   - leg2: an unreaped wrapper still exits on the fixture's own lifetime bound
```

用户报告累计三次误红，均在 leg2、分别挂在不同断言上。近 200 次 `ci.yml` run 中只检索到这一次
abort-leak 红（其余两次不在该 workflow 的可检索范围内），故本 plan 的一手证据以该次为准。

## 已验证的失败机制

**三个谓词对同一进程状态给出三种判定。** 实测（本机造真僵尸，pid=28633）：

| 谓词 | 僵尸 wrapper 上的结果 |
| --- | --- |
| `kill -0` | **成功** |
| reparent 检查（读 `ps -o ppid=`） | **通过**（读得到 ppid；重挂 init 后即为 1） |
| “still alive” 检查（`case ... *Z*` 排除僵尸） | **FAIL** |
| “gone within” 检查（awk `$3 !~ /Z/` 排除僵尸） | **报告已消失** |

即：一个已退出、尚未被 init 回收的 wrapper，**同时**满足 assertion 1、失败于 assertion 3、
又满足 assertion 4 —— 与 CI 上观察到的签名逐条吻合，且**不需要任何时序巧合**去解释那 19ms 间隔：
其间进程状态根本没变，变的只是谓词口径。

### 已用证据否证的假设

| 假设 | 否证证据 |
| --- | --- |
| H1 fixture 的 25s 上界在 setup 期间到期 | 三次本机实测 `since_detect=0s`、`etime=00:00`，setup 用掉的余量为 0；25s 上界余量满格 |
| H2 `kill -KILL -$suite_pgid` 打到了 wrapper | `review_gate.py` 只有一条 spawn 路径（`Popen(..., start_new_session=True)`，:545），wrapper 自成 session/pgid（实测 `pgid == 自身 pid`），套件组信号到不了 |
| H5 输给 controller 自己的 5–12s wrapper 超时 | 人为在检测后插 15s 延迟，wrapper 仍 `Ss`、`etime=00:15` 存活，controller 未回收 |

**尚未查明**：该次 CI 上究竟是什么让 wrapper 在中止前就退出。本轮不靠猜——改动让下一次复现
自带证据（见下）。这是本 plan 明确记录的残留未知。

## 根因分层

- 症状：CI 上 leg2 随机红。
- 直接原因：leg2 的基线断言是**对探针环境的时序观测**（“此刻还活着”），不是对被测代码的陈述；
  且三处观测对僵尸态口径不一。
- 使能条件：fixture 没有记录**自己是怎么结束的**，所以“上界到期”与“被别人回收”只能靠时序区分。
- 预防：断言换成结构性不变量 + 环境构造失败走有界重试而不是判红。

## 改动方案

1. **fixture 自记结束方式**（`test_review_gate.sh` 两个 hang stub）：倒计时循环正常跑完后写
   `$state/<client>_hang_bound_reached`。存在 ⇒ 是自身上界结束的；缺失 ⇒ 是被回收的。
   这是被测代码路径产出的产物，不是对时钟的观测。
2. **统一进程状态口径**（探针）：新增 `wrapper_state()` → `live` / `zombie` / `absent`，
   reparent 确认、前置条件、判决共用它。reparent 确认要求 `live`（僵尸不再算数）。
3. **leg2 重构**：
   - orphan 之后、杀套件之前 `rm -f` 该 marker —— 用删除做**发生序屏障**，不比较时间戳。
   - 断言（结构性）：`$WORK` 目录在 SIGKILL 后仍在 ⇒ EXIT trap（含 `rm -rf "$WORK"`）没跑过。
     取代原“套件在 30s 内退出”。
   - 断言（行为）：`bound+grace` 内进程组与私有路径残留清空。
   - 断言（结构性）：marker 重新出现 ⇒ 结束它的是 fixture 自身上界。取代原“杀完后还活着”。
4. **前置条件构造失败走有界重试**：只有“场景没构造出来”（wrapper 在 orphan 阶段非 `live`）才重试，
   最多 2 次，每次一整轮套件。**断言失败绝不重试。**
5. 失败路径打印结构化诊断：wrapper 状态、marker 有无、WORK 列表。

## Acceptance matrix（verdict 决策表）

| # | orphan 时 wrapper 状态 | SIGKILL 后 `$WORK` | bound+grace 内残留 | 屏障后 marker | verdict |
| --- | --- | --- | --- | --- | --- |
| A | live | 存在 | 空 | 存在 | **pass** |
| B | live | 存在 | 非空 | 任意 | **fail** — 真泄漏（040 修的那个缺陷） |
| C | live | 存在 | 空 | 缺失 | **fail** — 上界未被行使，wrapper 是被回收的 |
| D | live | 缺失 | — | — | **fail** — SIGKILL 下仍有 cleanup 跑过，前置条件破了 |
| E | zombie / absent | — | — | — | **retry**；N 次后 **fail** — 场景不可构造（环境红，措辞明确） |
| F | 变异：fixture 上界改回无界 | 存在 | 非空 | 缺失 | **fail**（变异测试须复现此行） |

## Test / register 覆盖

| 层 | 动作 | 命令 / 证据 |
| --- | --- | --- |
| 探针自身（本轮的“单元层”） | run | `make test-code-review-abort-leak-1` / `-2` |
| 变异测试（行 F） | add + run | 把候选 stub 上界改回无界 ⇒ leg2/fallback 必须红；claude stub 同理对 leg2/claude |
| 变异测试（行 C） | add + run | 令 marker 不写 ⇒ leg2 必须红 |
| 回归族 | run | `bash skills/code-review/scripts/test_review_gate.sh`（套件本身未变语义，只加 marker 写入） |
| 仓库权威校验器 | run | `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` |
| CI | run | 两个 abort-leak job 在 PR 上转绿 |

**测试注册自审**：本轮不新增 `test_*.sh` 文件，只改既有两个已注册入口，无新增注册欠账。

## Status-sync target

`specs/046-abort-leak-baseline-invariants/plan.md`（本文件）+ PR 描述。仓库无独立 status doc。

## Review / challenge gate

动共享分支前跑 `code-review`（独立评审），记录具体反对意见与处置。合并需用户显式授权。

## Phase C：5 Whys 与预防

**复杂度判定：`complex`**（触发项：间歇性、重复三次、Phase A 触发过 three-strike 换帧、
测试层本身即成因）。按规则先展开再深挖，不做正式 postmortem 仪式（无用户可见影响）。

1. 为什么 leg2 在套件正常时还红？—— 前置条件检查**接受**僵尸 wrapper，判决检查**排除**僵尸，
   于是一个已死的 wrapper 通过了 setup、又挂在“还活着”上。
2. 为什么 wrapper 那时已经死了？—— **那一次 CI 上未知**（三个候选已被证据否证）。fixture 没有
   记录自己是怎么结束的，所以事后无从回答。
3. 为什么一开始就用瞬时存活采样？—— “上界被行使过”没有任何可观测产物，探针只能拿某一瞬间的
   进程状态去推断它。
4. 为什么测试/评审没拦住？—— **规则早就在**：`testing-strategy/references/ci-fixtures-and-flake-control.md:39`
   明写“an unreaped zombie still answers `kill -0`…needs a bounded grace period instead of an
   instantaneous sample”。套件自身的 hang 用例**是遵守的**（`test_review_gate.sh:2292` 起同时查
   `^Z`）；只有 040 轮新写的这个探针，在 4 处存活判断里违反了 2 处。**控制存在，但没有任何东西
   让它触发。**
5. durable prevention —— 不是再复述一遍规则，而是给它一个**触发器**：对仓库测试脚本里
   “裸 `kill -0` / 读 ppid 当存活谓词、且邻近没有进程状态检查”的确定性检查。

### Swiss Cheese：这次每层的洞

| 层 | 洞 | 本轮是否补上 |
| --- | --- | --- |
| fixture | 不记录自己走的是哪条退出路径 | 补上（bound-reached marker） |
| 探针断言 | 时序代理而非不变量 | 补上（WORK 存活 + marker） |
| 探针存活口径 | 三处不一致 | 补上（`wrapper_state()` 单一口径） |
| 探针 setup | 环境构造失败被报成断言失败 | 补上（有界重试） |
| 规则执行 | 规则存在但无触发器 | **本轮补上** —— Anti-pattern 28 + `liveness_predicate_scan` 确定性闸 |
| 合并保护 | 这两个 job 至今不在 main 的 required checks 里（040 遗留） | **未补** —— 需仓库管理员操作 |

## 触发机制（本轮第二部分）

extraction gate 的规则明确禁止把「让既有规则触发」的机制推到下一轮（"the owner skill already
states the rule" 不构成 no-op landing 的许可）。故本轮按仓库既有做法把它**从 checklist 提升为闸**
——与 Anti-pattern 27 同形（该条也是「同类复现两次后提升」）。

- **checklist 行**：`recurring-anti-patterns-checklist.md` 新增 Anti-pattern 28。
- **确定性闸**：`check-ccl-skills.sh` 的 `liveness_predicate_scan`。谓词只认**孤儿判据**这一形态
  ——`ps -o ppid=` 与 init pid 同行比较；窗口内有 `stat=` 或 `*_state` 即放行（这正是修法）。
- **精度优先**：按 checklist 自己的 promotion guidance（blocking 闸上，误报比漏报更贵），
  当前语料 100% 精度、零误报。三项 recall limit 已在闸注释与 checklist 行里写明。
- **RED-baseline（差分、且是 applied mutation）**：
  - mutant = 恢复修复前探针 → `liveness_predicate_scan_failed`，且**点名 285 行**，即本轮实证的缺陷点；
  - control = 修复后探针 → `liveness_predicate_scan_ok` / `ccl_skill_check_clean_ok`。
  - 归因是差分的：失败由该闸自身产生，非其它断言。
- **行为套件**：`test_liveness_predicate_gate.sh`（9 probe：触发 / 定位 / 两种修法放行 /
  注释豁免 / 非测试脚本越界 / ppid 作父进程识别不误报 / 诊断独占一行），已注册进
  `test_check_ccl_regressions.sh` 快车道，`test_regression_runner_registration.sh` 通过。
- **套件自身发现的两个真缺陷**（写进来是因为它们正是闸存在的理由）：
  1. 诊断行与命中行连成一行（命令替换吞掉尾换行）；
  2. `trap 'rm -f "${var:-/dev/null}"'` 惯用法在变量未设时会 `rm -f /dev/null`
     ——非特权用户无害，**root 容器里会删掉设备节点**。已改为带守卫的 cleanup 函数。

同类三处站点里，第三处（`kill -0` 在循环体内做存活分支）在本轮顺手修掉（探针 273 行）；
另两处 `while kill -0` 看门狗循环**不改**：都等的是直接子进程且紧随 `wait`，风险显著更低，
按 review-finding-disposition-bar 不做反射式修改，已作为 recall limit 记录在案。

## 评审驱动的设计变更：把"观察顺序"改成"强制顺序"

七轮评审共 9 条 finding，**八条同型**：某个判定不需要它所声称的条件成立就能通过。其中两条出在
我为该类写的修复里，一条出在为防该类而建的闸里。第六轮把 bound race 又提了一次——按
same-class-recurrence 规则，这是设计信号而非再补一个补丁。

**改法**：arming 阶段对 wrapper 的**进程组** `SIGSTOP`，跨过整个中止窗口，套件确认消失后才
`SIGCONT`。被停住的进程根本到不了 marker 写入那一行，于是"controller 先死、bound 后到"这个顺序
不再是探针去*观察*的东西，而是它*强制*的东西——正是本轮主张在自己修复上的应用。
组而非组长：claude stub 的倒计时跑在同组的后台子进程里，只停组长会让它继续数。
`wrapper_state` 增加 `stopped`，否则 SIGSTOP 没落地时 arming 会假报成功。

**行为证据**：把上界压到 3s（不停住的话必然在中止窗口内到期）跑 leg2/fallback，五条断言仍全绿
——wrapper 确实被冻住了。

**顺带发现（既有缺陷，本轮只报不改）**：`probe_group_is_ours` 在 macOS 实测对一个组长
**同一瞬间**能被 `probe_processes` 按私有路径匹配到的进程组回答 no。原因未查明。影响面：
`cleanup` 的组杀被它把门，于是退化成逐 pid 杀——因为每个成员都带私有路径，仍能回收，所以一直
没被发现。按 review-finding-disposition-bar 不在本轮扩面修改，已写进代码注释与此处。

## 残留风险

- 该次 CI 上 wrapper 早退的**真正触发者仍未查明**（三个假设已被证据否证）。本轮的 marker 让下一次
  复现自带归因；在此之前，行 C/E 的红属于“已正确命名但成因待查”。
- 有界重试会在**环境确实构造不出场景**时把 job 拉长（最坏约 3 轮套件，仍远低于 20min job 上限）。
