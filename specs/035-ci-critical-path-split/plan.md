# 035 — CI 关键路径拆分：code-review 族独立并行 job + fast lane 去重

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | CI 单次成功跑 ~19–21 分钟，关键路径是 repository-gates 的 `make test` 单步（实测 18m15s，run 32590712961）。分解：`test_check_ccl_regressions.sh --fast` 296s + code-review 测试族 ~680s（62%），38 条命令全串行。且 fast lane 每条流水线跑两遍（repository-gates 直跑 + regression-heavy `--full` 超集内含）。本轮把 code-review 族拆为独立并行 job、CI 内去掉 fast lane 重复，关键路径预期从 ~19 分钟降到 ~12 分钟。 |
| Artifact classification | `gate implementation`（product-rd-workflow 定，未委托）：检查集合语义不变——每套件每条流水线仍恰好执行一次，改变的是 job 拓扑与 required-check 集合。feature-risk-router 定级 `shared-gate` + `release-ops`；security-review 变更臂 not-applicable：security posture unchanged（pinned ripgrep 安装、权限、trust boundary 均不动）。 |
| Scope | in：`Makefile`（`test` 改为纯 prerequisites 聚合目标，拆出 `test-repo-gates` / `test-regressions-fast` / `test-code-review` 三个子目标，本地 `make test` 集合语义不变）；`.github/workflows/ci.yml`（repository-gates 改跑 `make test-repo-gates`；新增并行 `code-review-regressions` job 跑 `make test-code-review`，安装步骤与 env 守卫逐字对齐既有 job——022 轮首跑红灯教训；regression-heavy 注释同步）；`scripts/test_check_spec_references.py` 的 Makefile-recipe 守卫（`test_repository_gate_invocations_scan_the_owning_root`）从"命令在 `test:` 自身 recipe 里"改为"命令从 `make test` 可达（自身 recipe ∪ prerequisites 的 recipe）"——不变量不减弱、只理解聚合形态，RED 证据见判定 3b；本 plan。out：任何测试脚本内容与断言语义；`--fast`/`--full` 分层定义；code-review 族内部的 sleep/超时模拟时长（收益中等、语义风险最高，deferred）；code-review job 二次分片（regression-heavy ~10min 是流水线下限，分片收益 <2min，deferred）。 |
| Depth | Makefile 目标重组 + CI workflow 增量 + 轮 artifact。无脚本语义变更。 |
| Root cause | (1) `make test` 是单一串行清单，CI 只能整体消费，无法并行化其中互相独立的套件族；(2) fast lane 同时被 `make test` 直跑与 `--full` 超集包含，CI 双跑（超集关系源码核验见判定 3）。 |
| Failure mode analysis | (1) 新测试加进 `test:` 却不进任何 CI job 的 false-green——防：`test` 无自有 recipe、纯 prerequisites 组合，往 `test` 加套件必须进某个子目标，而三个子目标全部被 CI 消费（repository-gates / code-review-regressions 直跑，fast lane 经 `--full`）；(2) 新 job 缺依赖/缺 env 假红——防：安装步骤与 `CCL_SKILL_BASE_REF` 守卫逐字对齐 repository-gates（022 轮 run 31895063645 实证过的失败类）；(3) required-check 集合漏更新——code-review 族移出 repository-gates 后若新 job 不设为必需检查，code-review 红灯可被合并——防：status-sync 行钉住，合并授权时一并处置；(4) 子目标拆分漏行/重行——防：判定 1 的命令多重集等值比对（机器 diff，非人眼）。 |
| Evidence plan | 已产：run 32590712961 分步计时（18m15s 归因）、分命令耗时表（296s/251s/165s/141s/85s/35s）、`--full` ⊇ `--fast` 源码核验。待产：判定表 1–4 本地机器证据；PR CI 四 job 全绿 + 分 job 时长（判定 5）；required checks 现状/目标对照（判定 6）。 |
| Completion standard | 判定 1–4 本地绿；PR 全部 job 绿（含新 `code-review-regressions`）且 repository-gates 时长显著下降；独立 adversarial review 已记录并处置；required-checks 更新作为合并授权附带动作向用户列明；PR 合并候用户显式指令。 |

## 修法与判定

| # | 输入 | 预期 | trace |
| --- | --- | --- | --- |
| 1 | 基线 `make -n test` 命令多重集 vs 新 `make -n test`（= 三子目标之和） | 逐行排序 diff 为空（集合语义不变） | PASS：38 行多重集逐行一致（实现前 RED：新目标不存在） |
| 2 | 新 `make -n test-repo-gates` / `test-code-review` / `test-regressions-fast` 两两交集 | 空（无套件双跑） | PASS：三对 `comm -12` 均为 0 |
| 3 | CI 内 fast lane 执行次数：repository-gates 步骤不再含 `test_check_ccl_regressions.sh`；`--full` 含 fast_tests | 每流水线恰好 1 次（regression-heavy 内） | PASS：ci.yml 全文仅 regression-heavy 一处 `test_check_ccl_regressions.sh --full`；runner 源码 `--full` = fast_tests + heavy_tests 已核 |
| 3b | 聚合化后 `make test-repo-gates` @ 本 worktree | 全绿；且 Makefile-recipe 守卫在守卫更新前应 RED | 守卫 RED 实测（`not found in []`，先于守卫更新）；守卫更新后全套件绿（run2 日志） |
| 4 | 子目标某行失败（make 逐行 recipe 失败即目标失败，同既有 `test:` 机制） | 对应 CI job 红 | 机制继承，不新增验证面；判定 3b 的守卫 RED 即为该机制的活体实测（recipe 行失败 → 目标失败 exit 2） |
| 5 | PR 的 CI 运行 @ 本轮候选 | 四 job 全绿；repository-gates 从 ~18.5min 降至 ~3min 量级，code-review-regressions ~12min，关键路径 ≈ max(code-review, regression-heavy) ≈ ~12min | PASS（PR #23 首跑，run 32593624728 @ c112bf6）：repository-gates **2m18s**（基线 18m31s，run 32590712961）、code-review-regressions **11m33s**、regression-heavy **9m33s**、npm-packages 1m58s；关键路径 11m33s，整线约 -42%～-45% |
| 6 | 分支保护 required checks | 现状读取；目标 = 现状 + `code-review-regressions`（repository-gates 语义收窄但名称保留） | 现状已读（gh api）：main 保护 contexts=[repository-gates, regression-heavy, npm-packages]、strict=true；dev 无保护、npm tag ruleset 无关。写入随合并授权处置 |

**新增机械 gate 的 design-time operability check**（`code-review-regressions` job）：author-dogfood = PR 首跑全绿后才请求合并（判定 5）；marginal-cost = +1 并行 runner ~12min，但 repository-gates 减 ~16min、去掉 5min 重复 fast lane，每流水线 runner 总时长净降 ~9min；trust-model = 覆盖集合恰好一次不变，防的是关键路径浪费而非新增 verdict；premise = 纯拓扑变更，不收紧不放宽任何既有 verdict 语义。

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| Makefile | 测试编排 | updated | `test` 聚合化 + 三子目标 |
| CI workflow | release 执行面 | updated | repository-gates 步骤替换 + `code-review-regressions` job |
| specs | plan | added | 本文件 |
| source-register | ledger | not-applicable | 无 skill 脚本变更，无外部借鉴源 |
| branch protection | status sync | pending | `code-review-regressions` 加入 required checks（合并授权时处置） |

## 独立评审记录（dual-track）

| Field | Answer |
| --- | --- |
| 链 | chain `spec035-ci-split-r2`，round1 review + round2 challenge，`review_chain_tracked=true`，同一 candidate（`candidate_sha256=c97e6d52…`，packet=diff origin/dev...c112bf6 + runner 超集上下文 + required-checks 现状）。证据行：`.work/review-evidence/spec035-ci-split-r2/`（本地持久，不入库）。 |
| 评审端 | `selected_client=codex`（family=openai；implementer=anthropic 同族排除生效）；`native_skill_binding=established`，`reviewed_skills=[python-service-dev, testing-strategy]`；`review_plan_source=derived-default`；depth=release，risk tags=[release-ops, shared-gate]。 |
| Findings | 两轮各 1 条 P1，同一缺口：code-review 族移出 repository-gates 后，若 `code-review-regressions` 不进 main 的 required checks，红 code-review 套件可在全部现有必需检查绿的情况下合并（即判定 6 / Failure mode (3) 已钉住的缺口，评审独立复现）。 |
| 处置 | 接受，顺序化缓解：required-checks 更新（+`code-review-regressions`）在 dev 合并**之前或同时**执行——先加保护只会挡住不含该 job 的 main 晋升（fail-safe 方向），不产生 false-green 窗口；评审端的备选缓解（把 test-code-review 留在 repository-gates 直至保护更新确认）会抵消本轮全部收益，不采纳。protection 写入是仓库设置面动作，随合并授权一并请示用户。 |
| 复审绑定 | 本 verdict 绑定实现 candidate（Makefile / ci.yml / 守卫测试，c112bf6 后不再变更）。此后提交仅允许 `specs/035-*/plan.md` 证据回填（git diff 可机验）；任何代码文件再变更即触发全程重跑。 |

## 实现边界记录（implementation boundary）

active baseline = 本文件（本分支未合并 plan）；scope 如上；implementation-mechanics owner = product-rd-workflow（gate implementation；无 stack dev skill 拥有 Makefile/CI YAML 编排面）；testing-strategy = not-applicable（不改测试层选择/阈值/gate 策略，检查集合语义不变，由判定 1–3 机器证明）；multi-agent-delegation = local（单一线性小 diff，无独立可并行 slice）；visible surface = no（纯 CI 编排）；feature-risk-router = 已跑（`shared-gate` + `release-ops`）；test-case-first = 判定表先于实现写就，判定 1 在实现前为 RED（子目标不存在）。
