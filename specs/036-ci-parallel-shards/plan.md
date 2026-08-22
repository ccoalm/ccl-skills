# 036 — CI 并行化第二轮：code-review 二分片 + 回归 lane fast/heavy 拆分

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 035 轮后关键路径 = `code-review-regressions` 12m11s（15 套件串行），次长 `regression-heavy` 7m39s–9m33s（fast ~5min + heavy clone 套件串行）。本轮把 code-review 族按实测耗时均分为两个并行 job、把回归 lane 拆为 fast/heavy 两个并行 job，关键路径预期 ~12min → ~6.5min。拓扑硬地板 ~5min（最大单套件 init_policy_matrix 251s），再往下需动测试语义，仍 out。 |
| Artifact classification | `gate implementation`（product-rd-workflow 定，未委托；风险分类沿用本会话 035 轮 feature-risk-router 裁决：`shared-gate` + `release-ops`，同一 artifact 类与变更形状；security posture unchanged）。与 035 的差别：本轮触及 `skills/skill-extraction-workflow/scripts/` 共享脚本（runner 加 `--heavy-only` 模式），故按 impact-chain 纪律补 source-register 行 + RED-baseline 行为证据。 |
| Scope | in：`Makefile`（`test-code-review` 聚合化为 `test-code-review-1/-2` 两分片，本地 `make test` 集合语义不变）；`.github/workflows/ci.yml`（code-review job 一拆二；`regression-heavy` 改跑 `--heavy-only`，新增 `regression-fast` job 跑 `--fast`，env 守卫四 job 逐字对齐——022 教训沿用）；`skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh`（新增 `--heavy-only` 模式：只跑 heavy_tests，尾 token `test_check_ccl_regressions_heavy_only_ok`；`--fast`/`--full`/`--list-unregistered` 语义不动）；`skills/skill-extraction-workflow/references/source-register.md` 追加 impact-chain 行（表尾追加，不移动 ledger citation waiver pin @171）；本 plan。out：任何套件内容与断言语义；sleep 时长压缩；三分片及以下（收益被 5min 地板吞掉）。 |
| Depth | Makefile/CI 拓扑重组 + runner 单模式增量 + 轮 artifact + register 行。 |
| Root cause | (1) 035 只拆了族级并行，族内仍串行；(2) `--full` 把 fast 与 heavy 绑在一个 job 里串行——runner 缺一个 heavy-only 执行面，CI 无法把两层并行。 |
| Failure mode analysis | (1) 分片漏/重套件——判定 1/2 机器多重集比对；(2) heavy 层失去执行面（--heavy-only 写错导致 heavy_tests 不跑）——判定 3 的 GREEN 运行要求逐套件 timing 行 + 尾 token；(3) 新 job 缺 env 守卫假红（022 类）——四 job 逐字对齐 `CCL_SKILL_BASE_REF` 守卫，fast lane 的 catalog 测试在 clone 内需要它（022 实证）；(4) required checks 漏换——`code-review-regressions` 名字消失，须换成 `-1`/`-2` 并新增 `regression-fast`（旧名残留 = 永远 pending 挡合并；漏加新名 = 红分片可合并），随合并授权处置；(5) register 行追加移动 waiver pin——表尾追加 + 本地 spec gate 验证；(6) 新增注册套件时分片失衡——分片注释记录均分基准（实测秒数），新增套件按注释再平衡。 |
| Evidence plan | 已产：035 轮 CI 实测分解（12m11s / 680s 族内分布；heavy job 7m39s–9m33s）；`--heavy-only` RED 基线（实现前 usage + exit 2，实测）。待产：判定 1–5 本地机器证据；PR CI 六 job 全绿 + 分 job 时长；register 行 + impact-chain gate 本地绿；dual-track 评审链。 |
| Completion standard | 判定 1–5 本地绿；PR 全部 job 绿且关键路径 ≈ ~6.5min；独立 dual-track review+challenge 记录并处置；required-checks 换名清单向用户列明；PR 合并候用户显式指令。 |

## 修法与判定

| # | 输入 | 预期 | trace |
| --- | --- | --- | --- |
| 1 | `make -n test` 命令多重集 vs 035 基线（38 行） | 逐行排序 diff 为空（本地集合语义继续不变） | 待执行 |
| 2 | `test-code-review-1` / `-2` 交集；两分片并集 vs 原 `test-code-review` 15 套件 | 交集空；并集恰好 15 | 待执行 |
| 3 | 修后 runner：`--heavy-only` 实跑 | 4 个 heavy 套件各 1 行 timing、`test_check_ccl_regressions_heavy_only_ok`、exit 0；实现前同参数 RED（usage + exit 2，已实测） | RED 已捕获；GREEN 待执行 |
| 4 | 修后 runner：`--fast` / `--list-unregistered` / 无参 / 非法参 | rc-parity 与修前一致（fast 尾 token 不变；非法参仍 usage + exit 2） | PASS：`--list-unregistered`/`--bogus`/`-h` 三探针新旧 rc 相等；lane 语义整套由判定 3c 机械持有 |
| 3c | 新增 `test_regression_runner_lanes.sh`（036 challenge P2 处置）@ stub fixture | 三模式各自恰好执行本 lane 多重集、heavy 红 stub 传播非零、per-mode 尾 token；已注册进 fast_tests（registration guard 绿） | PASS：`regression_runner_lanes_ok` + `test_regression_runner_registration: ok` |
| 5 | CI 内每套件执行次数：fast_tests 仅 `regression-fast`，heavy_tests 仅 `regression-heavy`，code-review 15 套件仅两分片 | 每流水线恰好 1 次 | PASS：ci.yml 六 job（YAML 解析确认），`--full` 不再被 CI 调用；配合判定 2/3c 的多重集证明 |
| 6 | PR 的 CI 运行 @ 本轮候选 | 六 job 全绿；关键路径 ≈ max(分片 ~6.6min, regression-fast ~6min, heavy-only ~3–5min) ≈ ~6.5min | 待产（PR 首跑回填） |
| 7 | 分支保护 required checks | 目标 = [repository-gates, npm-packages, regression-heavy, regression-fast, code-review-regressions-1, code-review-regressions-2]，移除 `code-review-regressions` | Runbook（036 评审两轮 P1 处置，收紧为无窗口形态）：用户以**单次原子 PATCH** 把 contexts 数组一次替换为终态六项（单调用无先加后删的中间窗口），回读确认后方可合并本 PR 的后续 dev→main 晋升；本 PR 目标 dev（无保护），合并本身不受影响；换名前旧名残留只会让晋升 pending（fail-safe），不会放行红套件 |

**新增机械 gate 的 design-time operability check**（regression-fast / 分片 jobs）：author-dogfood = PR 首跑全绿后才请求合并；marginal-cost = job 数 4→6，每流水线 runner 总时长基本持平（拆分不复制工作，仅 +2 次 setup ~80s）；trust-model = 覆盖恰好一次不变，防关键路径浪费；premise = 纯拓扑 + runner 模式增量，不改任何 verdict 语义。

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| Makefile | 测试编排 | updated | `test-code-review` 聚合化 + 两分片目标 |
| CI workflow | release 执行面 | updated | code-review 一拆二；regression lane fast/heavy 拆分 |
| skill-extraction-workflow | self（runner owner） | updated | `scripts/test_check_ccl_regressions.sh` +`--heavy-only` |
| source-register | ledger | updated | impact-chain 行（runner 模式增量，RED-baseline） |
| specs | plan | added | 本文件 |
| branch protection | status sync | pending | required checks 换名（判定 7，随合并授权） |

## 独立评审记录（dual-track）

| Field | Answer |
| --- | --- |
| 链 R1 | chain `spec036-shards-r1`，round1 review + round2 challenge，tracked，同一 candidate（`candidate_sha256=e34fb165…`，packet=diff origin/dev...6f62428 + runner lane 上下文 + required-checks 现状）。评审端 codex（openai 族，anthropic 同族排除）。证据：`.work/review-evidence/spec036-shards-r1/`（本地）。 |
| Findings R1 | P1×2（round1/round2 同指 required-checks 换名窗口与顺序）+ P2×1（`--heavy-only` 无自动回归）。 |
| 处置 | P1：收紧为单次原子 PATCH runbook（判定 7），无先加后删窗口；旧名残留方向 fail-safe。P2：采纳并落地 `test_regression_runner_lanes.sh` + `REGRESSION_SCRIPTS_DIR` 执行面重定向（判定 3c），注册进 fast_tests。 |
| 链 R2 | chain `spec036-shards-r2`（codex，tracked，candidate `429d9138…` = head b998c31 的 packet）。Findings：P1（建议加 `code-review-regressions` 兼容 job 过渡）→ **不采纳**：旧名残留只使 dev→main 晋升 pending（fail-safe，可用性非安全），判定 7 原子 PATCH runbook 已覆盖，兼容 job 引入 needs-join 复杂度且需后续再删一轮（与 035 先例的合并时换保护一致）；P1（注册审计 advisory-only 的自引用洞：把 guard 测试自身移出 fast_tests 后 advisory exit 0，CI 无红）→ **采纳**：正常执行模式下 unregistered 非空即硬失败（advisory 尾巴删除），lanes 测试补 unregistered-sibling 案例（fixture 内造未注册 test_*.sh，断言 --fast 非零且报名）。 |
| 链 R3 | candidate 因硬失败收紧再变更 → 再次全程重跑（回填于下）。 |

**注册硬失败的 design-time operability check**（收紧既有 verdict）：author-dogfood = 当前树 unregistered 为空，`--fast`/`--heavy-only`/lanes/registration 守卫本地全绿；marginal-cost = 新增测试文件者必须先注册进某 lane 才能让任何 lane 过（原本只有 guard 测试红，这正是想要的强制）；trust-model = 消除"guard 测试必须自己保持注册"的自引用依赖，false-green 类（未注册套件静默不跑）从 advisory 升为硬红；premise = 收紧——当前语料干净不算证据，RED 路径由 lanes 测试的 fixture 案例机械证明。

## 实现边界记录（implementation boundary）

active baseline = 本文件；scope 如上；owner = product-rd-workflow（gate implementation）+ skill-extraction-workflow（runner 脚本与 register 归它；该 workflow 本会话已显式 invoke，本轮 charter/map 即其 durable record）；testing-strategy = not-applicable（不改层选择/阈值，集合语义由判定 1/2/5 机器证明）；multi-agent-delegation = local（单线性 diff）；visible surface = no；test-case-first = 判定表先于实现，判定 3 的 RED 已在实现前实测捕获。
