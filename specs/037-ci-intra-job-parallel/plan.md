# 037 — CI job 内并发：共享套件执行器 + 变异走查并发化

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 036 后关键路径 ~6.2min，仍嫌长。分解 run 32598844164 得到：shard-1 341s（`init_policy_matrix` 239s 一个就占七成）、shard-2 362s（`review_gate` 167s + `cli_review_wrappers` 155s）、regression-fast 279s（`route_drift` 101s + `skill_catalog` 83s）。**性质判定**：这些时间绝大部分是「等」（进程 timeout、stub sleep）或互不相干的子进程，而不是 runner shell 里的算力——`opencode_review_retry` 85s 里脚本自带 sleep 就有 86s，`review_gate`/`cli_review_wrappers` 合计 30 处 timeout + 8 个 busy-loop，`init_policy_matrix` 则是 17 次零 sleep 的独立 python 子进程。串行执行因此在空耗墙钟。本轮把每条 lane 内部改为有界并发，关键路径预期 ~6.2min → ~3.5min。 |
| Correction of a prior claim | 035/036 两轮我记录过「拓扑硬地板 ~5min，因为 `init_policy_matrix` 的 251s 不可压缩」。**该结论是错的**：它不是单体，而是 1 个控制 + 16 个变异体、各写各的 `mutant_<name>.py` 副本、彼此零共享的独立子进程，可并发。本轮据此把它从 239s 压到 46s（本地实测），地板随之下移。原判据未经检验就当成不可动，属 blocked-verification 类误判，记录在案。 |
| Artifact classification | `gate implementation`（product-rd-workflow 定，未委托）。风险沿用 035/036 裁决：`shared-gate` + `release-ops`；security posture unchanged（无凭据、权限、trust boundary 变更）。 |
| Scope | in：新增 `scripts/run-parallel-suites.sh`（共享有界并发执行器）与 `scripts/test_run_parallel_suites.sh`（其机械守卫，注册进 `test-repo-gates`）；`Makefile`（两个 code-review 分片改经执行器；新守卫入 `test-repo-gates`）；`skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh`（fast/heavy 两条 lane 改经执行器，`run_test` 由执行器取代）；`skills/code-review/scripts/test_init_policy_matrix.sh`（变异走查改「登记 + 并发调度」，**断言函数一字未改**）；source-register 行；本 plan。out：任何套件的断言语义；缩短 timeout/sleep 时长（真动语义，仍不做）；`test-repo-gates` 并发化（146s，已在关键路径之下，且其 recipe 含带参命令，执行器只收路径——不为它引入 shell 串接口）；三分片及更细拓扑（并发后分片对墙钟不再有收益）。 |
| Depth | 新增一个共享执行器 + 其守卫；两处调用点接线；一个套件的调度重构；轮 artifact + register 行。 |
| Root cause | 前两轮只在 **job 之间**并行，每个 job 内部仍严格串行；而这些 lane 的耗时结构是「等」，串行等于把可重叠的等待排成队。缺的是一个可复用、语义正确的 job 内并发执行面。 |
| Failure mode analysis | (1) 并发套件互踩仓外共享状态——用 lane 级共享状态审计把关（见下节），且执行器文档写明该前置条件；(2) 并行输出交织成不可读日志——执行器按**输入顺序**回放各套件的完整输出，守卫用「慢的排前、快的排后」的 fixture 断言顺序，并用真实反序变异证明该断言非摆设；(3) 并发退化成串行而无人察觉——守卫直接断言墙钟（两个 2s 套件必须 <4s 完成），**本轮已实际抓到一次**：信号量用 `jobs -r | wc -l` 数的是命令文本行数而非作业数，多行后台块被当成 8 个作业，立刻判满载；改 `jobs -rp` 修复；(4) 失败被并发吞掉——守卫断言非零退出、失败套件被点名、失败套件 stderr 与通过套件输出都不丢；(5) 变异走查并发后失去敏感性——把某个已登记变异改成 no-op，走查必须红（已实测「flipped NOTHING」）；(6) 新套件进了 `make test` 却不进 CI——沿用 036 的注册硬失败；新守卫已挂进 `test-repo-gates`，并由套件集合等价判定核过。 |
| Evidence plan | 已产：run 32598844164 分套件计时与「等 vs 算」性质证据；lane 级共享状态审计；执行器守卫 3 处施加式差分变异；变异走查并发后 no-op 变异实测红；`init_policy_matrix` 239s→46s（本地，CPU 300%）。待产：四条 lane 本地全绿与计时；套件集合等价判定；PR CI 六 job 全绿与分 job 时长；dual-track 评审链。 |
| Completion standard | 判定 1–8 绿；PR 全部 job 绿且关键路径 ≈ ~3.5min；dual-track 收敛（终轮对准确 landing candidate 零未处置 P0/P1）；**required checks 不变**（job 名与数量均未改，无需再动分支保护）；PR 合并候用户显式指令。 |

## Lane 级共享状态审计（并发的安全前置）

对三条并发 lane 的全部成员扫固定 `/tmp` 路径、`$HOME`／全局 git config 写入、端口、写入仓库树，逐条核实命中：

| 命中 | 判定 | 依据 |
| --- | --- | --- |
| `test_opencode_review_concurrency.sh` 的 `/tmp/opencode-review.lock` | 误报 | 实为 `$WORK/tmp/opencode-review.lock`，在该套件自己的临时目录内 |
| `test_review_gate.sh` 的 `/tmp/plan.json`、`/tmp/diff.patch` | 误报 | 是断言 argv 的 fixture 字符串，不落盘 |
| `test_cli_review_wrappers.sh` 的 `/tmp/forbidden*` | 误报 | 是「隔离若失效才会被创建」的诱饵路径，正常路径无人写；且该套件在一条 lane 内只有一个实例 |
| fast lane 多个套件的 `> "$REPO_ROOT/..."` | 误报 | 每个套件先 `TMP="$(mktemp -d ...)"` 再 `REPO="$TMP/repo"`，写的是各自的克隆 |
| 端口、`$HOME`／`git config --global` 写入 | 无命中 | — |

结论：三条 lane 内均无可变的仓外共享面，满足并发前置。该前置条件写进了执行器头部注释——**往并发 lane 里加违反它的套件，是执行器检测不到的正确性 bug**。

## 修法与判定

| # | 输入 | 预期 | trace |
| --- | --- | --- | --- |
| 1 | `make -n test` 可达的套件文件集合，改前 vs 改后 | 除新增守卫外完全一致，零丢失 | PASS：before 41 / after 43，only-in-after = `run-parallel-suites.sh` + `test_run_parallel_suites.sh`，only-in-before 为空 |
| 2 | 执行器守卫全套 | 8 组性质全绿（全跑到、输入序回放、并发为真、`SUITE_JOBS=1` 确为串行、失败传播并点名、缺文件先于启动即失败、路径不过 shell、非法 jobs 值被拒） | PASS：`run_parallel_suites_ok` |
| 3 | 对执行器施加 3 处变异（信号量数行数／失败不传播／启动+回放反序） | 每处都红、且红在对应断言上 | PASS：分别命中「concurrency is not happening」「did not make the runner exit nonzero」「replayed in completion order, not input order」；未变异控制组绿 |
| 4 | 并发化后的 `init_policy_matrix` | 16 个变异体全部断言、exit 0、显著提速 | PASS：16 条 `sensitive to`、exit 0、**239s → 45.9s**（CPU 300%） |
| 5 | 把某个已登记变异改成 no-op | 走查必须红且报「flipped NOTHING」 | PASS：rc=1，命中该串；控制组恢复后绿 |
| 6 | `--fast` / `--heavy-only` / lane 语义守卫 / 注册守卫 | 与改前同集合、同判定；036 的 lane 守卫仍绿 | PASS：`regression_runner_lanes_ok` + `test_regression_runner_registration: ok`（并发执行下） |
| 7 | 四条 lane 本地实跑 | 全绿，且各自耗时降到「最慢单套件」量级 | PASS（本机 jobs=8，CI 上 nproc=4 故增益略低）：shard-1 rc=0 **97s**、shard-2 rc=0 **152s**、fast lane rc=0 **169s**、heavy lane rc=0 **170s**；对照 CI 串行基线 341s／362s／279s／231s |
| 8 | PR 的 CI 运行 @ 本轮候选 | 六 job 全绿；关键路径 ≈ ~3.5min | PASS（PR #28，run 32619750500 @ 准确候选 7f764fd）：code-review-regressions-2 **2m59s**（关键路径）、regression-heavy 2m41s、repository-gates 2m28s、regression-fast 2m27s、code-review-regressions-1 2m22s、npm 53s。对照 036 终态 6m13s → **2m59s**；连同 035/036，整线自 ~19–21min 降至 ~3min。（前两个候选 6dcdbad／2578448 亦各自六 job 全绿，同量级） |

**新增机械 gate 的 design-time operability check**（`run-parallel-suites.sh`）：author-dogfood = 本轮四条 lane 全部经它跑通后才提交；marginal-cost = 零新增 CI job、零 required-checks 变更，单次调用替代逐行 recipe；trust-model = 它不新增任何判定，只改调度，**唯一新增的失败面是并发本身**，由守卫的并发/顺序/传播三组断言 + lane 共享状态审计共同兜住；premise = 不是「当前语料干净」，三处施加式变异证明守卫能红。

## 独立评审记录（dual-track）

| Field | Answer |
| --- | --- |
| 链 R1 | chain `spec037-parallel-r1`（codex，openai 族，tracked）。5 条有效发现全部采纳：① lane 隔离只是散文审计 → 落地 `scripts/test_lane_isolation.py` 机械闸；② 取消时子进程被遗弃 → `set -m` + 进程组 TERM/KILL；③ 变异 worker 死亡无状态文件被当成功 → 每个 index 必须写显式终态；④ 尾随 `--jobs`/`--label` 无操作数会死循环 → 校验操作数；⑤ dash 前缀套件名被当解释器选项（`bash --help` 静默 exit 0）→ `bash --` / `python3 --`。第 6 条（CI 证据待产）由判定 8 关闭。 |
| CI 首跑暴露的两处（非评审发现，同轮修复） | ① 两个 lane 套件的 `printf \| grep -q` 在 pipefail 下因 SIGPIPE 误判失败——**并发只是改变时序把这个既有缺陷暴露出来**，本仓别处早已因同一理由改用纯 bash 匹配；含正则 token 的调用点保留 `=~`。② impact-chain 闸判 `code-review` 欠台账行（改了其 scripts 即算 owner 变更），补行；且**基线刷新从 merge 改为 rebase**——merge commit 会多造一个轮 span，闸就看不到本轮的台账行（本仓已记录过的教训）。 |
| 链 R2 | chain `spec037-parallel-r2`（codex，tracked，candidate `0890f48c…`）。3 条有效发现全部采纳：① KILL 阶段重读 `jobs -rp` 会漏掉「组长已退出但后代仍在」的进程组 → 改为复用 TERM 前捕获的组列表；② **lane 闸 SAFE 命中即跳过整行**（两轮同判）——`printf "$TMP" > /tmp/shared` 这类同时带安全标记与真实危害的行会被漏掉 → 改为**逐个命中判定**，豁免上下文必须紧邻匹配点，并补 6 个 must-flag（含掩盖形态）+ 2 个 must-stay-quiet 自检；收紧后立刻暴露出一行此前被跳过的 MCP 诱饵，已按同类核实入白名单；③ 选项守卫探针放在位置参数之后，解析早停 → 移到解析位并精确断言 exit 2（变异验证：去掉守卫即挂死 124 被抓）。 |
| 链 R3 | chain `spec037-parallel-r3`（codex，tracked，candidate `26913616…`）。CI 在该候选上**六 job 全绿、关键路径 3m02s**。三条发现：① 扫描器覆盖窄（漏 `touch "$HOME/x"`、`/var/tmp`、`python -m http.server 8000` 等）；② 只扫套件自身，不跟进它 source/执行的本地助手；③ 两个 P2：`timeout(1)` 在原生 macOS 缺失会让 `make test-repo-gates` 无法运行；失败清单用空白拼接 + `wc -w`，含空格的路径会被算成多条。 |
| **同类复现的设计裁决**（R1/R2/R3 三轮都在追「隔离扫描器还漏了哪种写法」） | 按 dual-track 的同类复现规则，这不该再打一个补丁，而要裁决主张边界。**裁决 = narrow（收窄主张）+ 取具体覆盖增量**：静态文本无法证明隔离（套件随时可以调用任意工具、运行期拼路径），所以本闸在文档与命名上明确定位为**已枚举危害类的回归绊线**，不是隔离证明；长期保障 = 当轮成员审计 + CI 本身（真竞态表现为 flakiness）。同时把评审点名的具体形态一次补齐：`/var/tmp`、`$HOME` 作为写目标的各种形式（不止重定向）、XDG 共享根、`http.server`/`--port`/`--bind`/`nc -l` 端口占用，并跟进套件 source/执行的本地助手（有 visited 集与深度上限）。 |
| R3 覆盖增量的副产物 | 收紧后立刻在两个套件里扫出 XDG 用法；核实为**它们自己**把 `XDG_DATA_HOME` 指向 `$WORK/...`，属误报 → 增加「变量是否被本文件限定到工作区」的按变量判定（有赋值证据，区别于已被否决的整行跳过），并补 4 条自检：继承的 XDG／HOME 必须报，自限定的必须不报。 |
| 链 R4 | chain `spec037-parallel-r4`（codex，tracked，candidate `42c4dbe2…`）。两条 P1 均采纳：① **自检往源码树写探针文件再删**——会覆盖同名用户文件、只读检出直接失败、并发调用互踩；改为探针全部落在临时目录，`with_helpers` 增加 `root` 参数把遍历限定在该临时树内。② `scoped_roots` 按整文件且不看顺序/注释判定；`HOME=... cmd` 是命令前缀、只对那一条命令生效，注释里的赋值更是什么都不限定 → 改为**必须是整条语句的独立/export 赋值**，并补两条自检（命令前缀不生效、注释不生效）。第三条 P1（CI 证据须对准确候选）由判定 8 关闭。 |
| R4 收紧的副产物 | 严格化后两个 opencode 套件的 XDG 行重新暴露。**实地核实而非假设**：这些读取行位于套件用 `cat >"$WORK/bin/opencode" <<'STUB'` 生成的桩脚本内，且该文件 14 处 `XDG_DATA_HOME` 赋值全部指向 `$WORK`，无例外——运行期只会看到工作区内的根。文本扫描无法解析这一点（正是本闸声明的边界），故登记为**文件级已核实例外**，而不是把规则放松到会掩盖真实危害；陈旧的文件级例外同样会让闸变红。 |
| 链 R5 | chain `spec037-parallel-r5`（codex，tracked，candidate `f5c8a6a0…`）。两条 P1：① 作用域按整文件计算、不看顺序——`touch "$HOME/.shared"` 出现在 `HOME="$WORK/home"` **之前**仍被抑制，安全赋值后又被不安全重赋值也继续抑制 → 改为**按源码顺序**推进作用域（前置赋值才授予、不安全重赋值即撤销），并补两条自检（危害在赋值之前、重赋值撤销）。② CI 证据须对准确候选 → 已产（判定 8，run 32619750500 @ 7f764fd 六 job 全绿）。另：赋值是否**实际被执行到**（条件分支、未调用的函数）文本不可判定，已按本闸声明的边界写进代码注释——属已声明残余，走已核实例外而不是放松规则。 |
| 链 R6 | chain `spec037-parallel-r6`（codex，tracked，candidate `c3d53ee9…`）。两条 P1 均采纳，都是作用域授予过宽：① `WORKSPACE_VALUE` 按前缀匹配，`$TMPDIR`/`$WORKSPACE` 会被当成私有工作区 → 改为**精确变量名 + 边界**；② 所有 `XDG_*_HOME` 折叠成一个键，限定了 `XDG_DATA_HOME` 就连带豁免继承来的 `XDG_CONFIG_HOME`/`XDG_CACHE_HOME` → 改为**逐变量跟踪**，只豁免该行上出现的那个变量。补三条自检（TMPDIR／WORKSPACE 前缀、跨 XDG 变量）。 |
| 链 R7 | chain `spec037-parallel-r7`（codex，tracked，candidate `677810ba…`）。两条 P1 均采纳：① 作用域值里的 `..` 逃逸——`HOME="$WORK/../shared"` 含 `$WORK` 却解析到工作区之外（所有套件在那里相遇）→ 拒绝父级穿越；② 文件级白名单按 `(文件, 危害类)` 一刀切，该文件里**新出现**的不安全 XDG 写入也会被放行 → **用规则取代白名单**：只有当该文件对某个 XDG 变量的**全部**赋值都限定在工作区内，才豁免该变量的使用；每次运行现算，不再依赖我一次性人工核读，后来新增一处不安全赋值即重新变红。已核实例外因此从 19 条降到 7 条。第三条 P1（准确候选需跑满六 job）由本轮 CI 关闭。 |
| R7 收紧时自检的一次纠正 | 新规则一度把整文件式授予也用到 HOME 上，导致既有自检「命令前缀不作用于后续行」变红——**自检是对的**：`HOME="$WORK/h" cmd` 之后的 `touch "$HOME/x"` 用的是继承的 HOME。整文件式授予是较弱证据（只说明所有赋值都在工作区内，不说明使用点跑在那个前缀下），仅对实地核实过的 XDG 形态成立，故限定在该类；HOME 只走严格的按序规则。 |
| 链 R8 | chain `spec037-parallel-r8`（codex，tracked，candidate `2b778f95…`）。两条 P1 均采纳：① **我引入的真缺陷**：把 `mutate_and_expect_mismatch` 放进 `if` 条件，会在其整个函数体内关闭 errexit——中途未加保护的失败之后，helper 末尾那条成功命令仍会让 worker 写出 `ok`，把没跑完的变异体记成通过。改为**简单命令 + EXIT trap 捕获真实退出码**，errexit 在函数体内保持有效（复验：16/16 仍敏感，no-op 变异仍红）。② XDG 的整文件式授予仍可被"先用后赋值"绕过 → **彻底放弃规则式豁免，改为 12 条逐行显式例外**：三轮下来每一个试图表达「本文件限定了该变量」的规则都被证明可绕，显式清单没有这个面；新出现的 XDG 写入不在单子上，照样红。 |
| 链 R9 | chain `spec037-parallel-r9`（codex，tracked）。两轮同指一条：packet 里没有 lane 成员正文，隔离前置**无法被独立核验**。按 code-review 技能自身的规则，这是**输入缺陷不是候选缺陷**——处置为扩 packet 重跑该轮，而不是改候选去迎合。 |
| 链 R10（扩 packet 后） | chain `spec037-parallel-r10`（codex，tracked）。两条 P1：① 扫描器把 `${TMPDIR:-/tmp}/shared` 和无 `XXXXXX` 的 `mktemp -d /tmp/shared` 当安全 → 豁免收紧为**只认带唯一占位符的 mktemp 模板**；过程中还发现 `fixed-tmp` 模式要求尾随斜杠，`${TMPDIR:-/tmp}` 这种以 `}` 收尾的形态**从来没被匹配过**，一并修宽（随即又扫出两处 inert 命中，逐条登记）。② **我在 packet 里写错了事实**：说「四个成员没有自建工作区」，实际是九个。已逐个核实：其中八个完全不写任何文件，第九个的四个"写入目标"是正则片段（`<label>`、`[0-9]+` 等）而非文件——九个全是只读校验器。这条记在案：数字要数过再写。 |
| 链 R11 | 修复后终轮全程重跑（回填于下）。 |

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| repo scripts | 新共享执行器 | added | `scripts/run-parallel-suites.sh` + `scripts/test_run_parallel_suites.sh` |
| Makefile | 测试编排 | updated | 两分片改经执行器；新守卫挂进 `test-repo-gates` |
| skill-extraction-workflow | self（runner owner） | updated | fast/heavy 两 lane 改经执行器，`run_test` 由其取代 |
| code-review | self（suite owner） | updated | `test_init_policy_matrix.sh` 变异走查改登记+并发调度，断言未改 |
| source-register | ledger | updated | impact-chain 行（执行面变更，RED-baseline） |
| specs | plan | added | 本文件 |
| branch protection | status sync | not-applicable | job 名与数量均未变，required checks 无需改动 |
| testing-strategy | 测试层策略 | unchanged | 不改层选择、阈值或 CI gate 策略；改的是同一批套件的调度，集合等价由判定 1 机器证明 |

## 实现边界记录（implementation boundary）

active baseline = 本文件；scope 如上；owner = product-rd-workflow（gate implementation）+ skill-extraction-workflow（runner 与 register）+ code-review（其套件调度）；multi-agent-delegation = local（单线性 diff，两杠杆共用一个执行器，拆开反而增加接口面）；visible surface = no；feature-risk-router = 沿用 035/036 的 `shared-gate` + `release-ops` 裁决（同 artifact 类、同变更形状）；test-case-first = 判定表先于实现写就，判定 3/5 的 RED 均为实现后施加式变异实测，判定 2 的并发断言在实现过程中真实抓到信号量缺陷。
