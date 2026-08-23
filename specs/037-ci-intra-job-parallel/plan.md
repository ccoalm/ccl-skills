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
| 8 | PR 的 CI 运行 @ 本轮候选 | 六 job 全绿；关键路径 ≈ max(shard-2 ~167s, fast ~101s, shard-1 ~85s) + setup ≈ ~3.5min | 待产（PR 首跑回填） |

**新增机械 gate 的 design-time operability check**（`run-parallel-suites.sh`）：author-dogfood = 本轮四条 lane 全部经它跑通后才提交；marginal-cost = 零新增 CI job、零 required-checks 变更，单次调用替代逐行 recipe；trust-model = 它不新增任何判定，只改调度，**唯一新增的失败面是并发本身**，由守卫的并发/顺序/传播三组断言 + lane 共享状态审计共同兜住；premise = 不是「当前语料干净」，三处施加式变异证明守卫能红。

## 独立评审记录（dual-track）

| Field | Answer |
| --- | --- |
| 链 R1 | chain `spec037-parallel-r1`（codex，openai 族，tracked）。5 条有效发现全部采纳：① lane 隔离只是散文审计 → 落地 `scripts/test_lane_isolation.py` 机械闸；② 取消时子进程被遗弃 → `set -m` + 进程组 TERM/KILL；③ 变异 worker 死亡无状态文件被当成功 → 每个 index 必须写显式终态；④ 尾随 `--jobs`/`--label` 无操作数会死循环 → 校验操作数；⑤ dash 前缀套件名被当解释器选项（`bash --help` 静默 exit 0）→ `bash --` / `python3 --`。第 6 条（CI 证据待产）由判定 8 关闭。 |
| CI 首跑暴露的两处（非评审发现，同轮修复） | ① 两个 lane 套件的 `printf \| grep -q` 在 pipefail 下因 SIGPIPE 误判失败——**并发只是改变时序把这个既有缺陷暴露出来**，本仓别处早已因同一理由改用纯 bash 匹配；含正则 token 的调用点保留 `=~`。② impact-chain 闸判 `code-review` 欠台账行（改了其 scripts 即算 owner 变更），补行；且**基线刷新从 merge 改为 rebase**——merge commit 会多造一个轮 span，闸就看不到本轮的台账行（本仓已记录过的教训）。 |
| 链 R2 | chain `spec037-parallel-r2`（codex，tracked，candidate `0890f48c…`）。3 条有效发现全部采纳：① KILL 阶段重读 `jobs -rp` 会漏掉「组长已退出但后代仍在」的进程组 → 改为复用 TERM 前捕获的组列表；② **lane 闸 SAFE 命中即跳过整行**（两轮同判）——`printf "$TMP" > /tmp/shared` 这类同时带安全标记与真实危害的行会被漏掉 → 改为**逐个命中判定**，豁免上下文必须紧邻匹配点，并补 6 个 must-flag（含掩盖形态）+ 2 个 must-stay-quiet 自检；收紧后立刻暴露出一行此前被跳过的 MCP 诱饵，已按同类核实入白名单；③ 选项守卫探针放在位置参数之后，解析早停 → 移到解析位并精确断言 exit 2（变异验证：去掉守卫即挂死 124 被抓）。 |
| 链 R3 | 修复后终轮全程重跑（回填于下）。 |

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
