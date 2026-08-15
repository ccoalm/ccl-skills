# 021 — impact-chain 闸：`require "date"` 移植性修复（host 差异不得改写 verdict）

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 消除 impact-chain gate 的 host 依赖 verdict 翻转：`description_is_scalar` 在 `permitted_classes: [Date, Time]` 处引用 `Date`，但脚本只 `require "yaml"`、从不 `require "date"`。在 psych 不传递加载 date 的 host（CI ubuntu-24.04 apt ruby 3.2 / psych 5.0.1 实测；上游 psych ≤5.1 懒加载、5.2.0–5.2.5 完全不载、5.2.6 起由 psych.rb 顶部自载）上，`Date` 未定义 → `NameError` 被 `rescue StandardError` 吞成"非法 YAML" → routing-surface `#description` 定位器被静默拒绝 → 首个使用该定位器的台账行（new-tighten 轮）进入 PR 评审 diff 时 CI 红。 |
| Artifact classification | `gate implementation`：恢复设计语义的移植性修复。规则/范围/失败/完成语义不变——同一输入在设计语义下的 verdict 不变；变化是 host 环境不再能改写 verdict。分类由 product-rd-workflow 直接判定（未委托 feature-risk-router）；feature-risk-router 定级 `shared-gate`（security-review 变更臂 not-applicable：security posture unchanged，无信任边界/未信输入面/敏感 sink/鉴权/密钥变化）。 |
| Scope | in：`skills/skill-extraction-workflow/scripts/impact-chain-gate.rb`（顶部 +1 行 `require "date"`）；`skills/skill-extraction-workflow/scripts/test_check_ccl_impact_chain_refscripts.sh`（dateless-shim 差分 case + mutation 归因 + 计数断言更新，heavy 层深版）；`skills/skill-extraction-workflow/scripts/test_impact_chain_gate_dateless_host.sh`（新增 fast 层合并时含护测试，微型合成 repo、不克隆全仓——dual-track r1a 双 lane 同类 P1 的 accepted 修复）；`skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh`（fast_tests 注册）；本 plan；source-register 行。out：任何 verdict 语义变更；`rescue StandardError` 收窄为 `Psych::Exception`（基础设施错误 fail-loud——是语义变更，本轮不做，记为后续候选，见"未做项"节）；CI workflow；PR #5 内容本身。 |
| Depth | 单文件 gate 脚本 + 回归测试 + 轮 artifact。 |
| Root cause | gate 对 `Date` 的可用性押在 psych 传递加载的偶然行为上；`rescue StandardError` 把基础设施错误（NameError）与数据错误（非法 YAML）折叠为同一 verdict，使缺陷既静默又 host 相关。触发窗口：`#description` 规范字段定位器（019 后引入）首次被 CI 的评审 diff 覆盖即本 PR。 |
| RCA analysis | 反事实成立：ruby 3.2.11 @ PR 测试合并 `4ca9a97`，未修 gate exit 1 且失败文案与 CI 逐字一致；+`require "date"` 副本 exit 0。widen：全仓扫描（skills/*/scripts/*.rb）仅此一处引用未 require 的 `Date`；`register-firing-path-resolution.rb` 无 Date 引用。掩蔽机制：dev 机 ruby 4.0.5/psych 5.3.1 由 psych.rb:2 `require 'date'` 兜底。 |
| Failure mode analysis | 修法失败面：(i) require 位置/语法错 → gate 崩溃（`ruby -c` + 全 suite 防）；(ii) 回归测试的 host 模拟不忠实 → dateless shim 拦截 psych 传递 require、放行显式 require，已在 ruby 4.0.5 与 3.2.11 双 host 空跑验证（yaml-only → `Date` nil；显式 require → constant；`safe_load([Date,Time])` → NameError）；(iii) 测试对未修 gate 不红 → mutation 归因腿：对剥掉 require 行的 gate 副本同 fixture 必须 rc 1，且先 `cmp` 证明 mutation 真实生效。 |
| Evidence plan | 已产：CI 失败日志逐字比对；ruby 3.2 @ `4ca9a97` 差分（红/绿）；psych 上游源码矩阵（v5.0.0/v5.1.2 scalar_scanner 带 require date 但实测 3.2.11 不生效=懒加载、v5.2.0 双无、v5.2.6 psych.rb 自载）；shim 双 ruby 空跑。待产：新差分 case 对未修 gate RED → 修后 GREEN；mutation 腿；make test 修前 baseline + 修后全绿；dual-track 双 lane 链。 |
| Completion standard | 新 case RED→GREEN 差分成立且 mutation 归因（仅剥 require 行 → 仅 dateless 腿红）；make test 修前/修后全绿（ruby 4 host）+ ruby 3.2 对修后 gate 定向复测绿（本仓 fixture + PR 聚合形态）；checker clean；dual-track 无未处置 P0/P1；register 行 + 本 plan 落树；dev 推送后 PR #5 重生成 merge ref 的 CI 三 job 全绿；PR 合并另候用户显式指令。 |

## 缺陷与修法

**缺陷**：`description_is_scalar`（routing-surface `#description` 定位器的必经谓词）在参数处引用 `Date`，而 `[Date, Time]` 在 `safe_load` 调用前求值——`Date` 未定义即抛 `NameError`，落入 `rescue StandardError → nil`，谓词返回 false，类被拒。同一 commit 同一 base，verdict 随 host 翻转——机器闸的判定不可复现即闸缺陷。

**修法**：脚本顶部 `require "yaml"` 后加 `require "date"`（`Time` 为 core 常量，无需 require）。不动 `rescue`、不动任何谓词逻辑：修复把 `Date` 的可用性从"psych 版本的偶然行为"变为"脚本自己声明的依赖"，设计语义逐字保留。

**未做项（routed，不在本轮）**：(1) `rescue StandardError` 收窄为 `Psych::Exception` 使基础设施错误 fail-loud 而非静默拒类。这是失败语义变更（当前"任何异常=拒类"是 fail-closed 方向），需按 shared-gate 纪律独立评审；本轮修复后 NameError 类缺陷已不可达，收窄的边际收益留待有第二实例时定夺。(2) 回归 umbrella 的 heavy 层在当前 GitHub CI 上无 `--full` job（脚本注释假设的 GitLab changes-gated job 不存在于 ci.yml）——heavy 层测试在 CI 不自动执行，属既有 CI-lane 覆盖缺口，非本轮引入。**本轮性质（date 依赖回归会静默复活）已由 fast 层含护测试关闭**（dual-track r1a 双 lane 同类 P1 的 accepted 修复，沿"行为在 fast 层、wiring 在 heavy 层"的既有先例）；heavy 层整体是否补 `--full` job 仍记录待维护者定夺。

## 验收判定表（输入 → 闸 verdict）

| # | host 形态 | gate 版本 | fixture | 预期 verdict | trace（已执行） |
| --- | --- | --- | --- | --- | --- |
| 1 | date-preloading（ruby 4.0.5 / psych 5.3.1） | 修后 | description-only + `#description` 行（case-routing-surface-description-anchor） | rc 0 | 直接运行全 suite `test_check_ccl_impact_chain_refscripts: ok`（80 gate runs；该 suite 在回归 umbrella 的 heavy 层，本地/CI `make test` 走 `--fast` 不含它——本轮以直接运行 + 提交后 `--full` 覆盖）+ make test（checker/fast 层） |
| 2 | date-less（shim；等价 apt ruby 3.2） | 修后 | 同上（新 case dateless 腿） | rc 0 | 新 case dateless 腿过（ruby 4.0.5 与 3.2.11 双 host 各跑一遍全 suite） |
| 3 | date-less（shim） | mutated（剥 require 行） | 同上（新 case mutation 腿） | rc 1 + `impact_chain_firing_path_missing` | mutation 腿过（含 cmp 非空变更守卫 + owner 名断言）；外部对照：ruby 3.2.11 @ `4ca9a97`（base `2aa8cd3`）未修 gate exit 1 且文案与 CI 逐字一致，修后 gate exit 0 |
| 4 | date-less（shim） | 修后 | date 值 sibling key + description-only（fixture-dated 形态，新 case 第三腿） | rc 0 | dated-sibling dateless 腿过（safe_load 真实例化 Date 的最深路径） |
| 5 | date-preloading | 未修（=当前 dev） | 新 case 全部腿 | dateless 腿 rc 1 → 新 suite RED | RED 先行实测：未修 gate 上 suite 恰在 `a date-less host must not refuse the routing-surface class` 处 FAIL（先于修复执行） |
| 6 | 双 host（shim 与 `-rdate` 显式预载对照） | 修后 + mutant | fast 层含护测试的微型合成 repo（description-only + `#description` 行） | 四腿：修后 shim rc 0 / mutant shim rc 1+守护文案 / 修后 `-rdate` rc 0 / mutant `-rdate` rc 0（腿 2×4 = 同一 mutant 跨 host 翻转 verdict 的差分，机器化钉住掩蔽机制本身） | `test_impact_chain_gate_dateless_host.sh: ok`（ruby 4.0.5 与 3.2.11 各一遍；已注册 fast_tests，每次 `make test` 执行；原始执行证据见下节） |

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| skill-extraction-workflow | self（gate owner） | updated | `scripts/impact-chain-gate.rb` +1 require；`scripts/test_check_ccl_impact_chain_refscripts.sh` 新 case |
| source-register | ledger | updated | impact-chain 行（scripts 变更，firing-path: command:scripts/impact-chain-gate.rb） |
| specs | plan | added | 本文件 |
| CI workflow / 其余 skill | — | unchanged | 零语义变更；修复对 date-preloading host 是无操作 |

## 实施边界记录（implementation boundary）

- baseline：本 plan（轮分支 `worktree-gate-date-require`，自 dev `fb55157` 分出）。
- scope：见 charter Scope in 列，共 4 个文件。
- 实现机制 owner：仓内 ruby gate 脚本无独立 stack skill，按 skill-extraction-workflow scripts 惯例执行；测试机制 owner：`testing-strategy`（实现测试前在会话内加载）。
- `multi-agent-delegation`：local——单一微小串行 slice（1 行修复 + 1 case），无可并行独立切片，delegation 不成立。
- visible surface: no——gate 脚本无渲染面，不触发设计检查点。
- `feature-risk-router`：已跑，定级 `shared-gate`（见 charter）。
- test-case-first：验收判定表行 2/3/4 即测试用例，先于实现落定；RED 先行于修复执行。

## Status-sync 目标与评审门

- status-sync：本 plan 即轮记录；register 行按台账单次追加纪律终稿一次落。routing 台账（skill-taxonomy-optimization-plan）不涉及——非路由测量轮。
- 评审门：dual-track 双 lane（review + challenge），候选为本轮全部 diff；全部 P0/P1 处置后方可合 dev/推送（shared-gate 决定的前置）。评审记录（chain id、candidate 摘要、发现与处置、评审者身份）回填本节。
- 修前 verifier（verifier discovery：Makefile `test` 目标为权威 verifier，覆盖 checker、回归 suite、契约覆盖闸与链接/引用闸）：轮 worktree 内首次修前 baseline 因测试先行编辑与其并发而中断（时序缺陷，如实记录）；干净 baseline 改在 detached worktree @ dev `fb55157` 重跑（修前树零改动），结果回填于下。修后全量 make test 在轮 worktree 另跑。

### Dual-track 评审记录

- **chain `gate-date-require-r1a`**（candidate sha256 `f4641c21…` = 首版提交 13228df 的冻结 packet，codex 双 lane，`native_skill_binding=established`，reviewed_skills：skill-extraction-workflow / terminal-cli-dev / testing-strategy；claude 因同族被排除）：review 与 challenge 各 1×P1，**同类收敛**——三条回归腿全在 heavy 层（`--full`），`make test` 与现有 CI 均不执行，将来剥掉 `require "date"` 时全部必跑检查仍绿，host 依赖 verdict 无合并时红灯地复活。**均 accepted，按 smallest_fix 菜单第二项落**：新增 fast 层含护测试 `test_impact_chain_gate_dateless_host.sh`（微型合成 repo；初版三腿，r2 challenge 将对照腿升级为 `-rdate` 显式预载并补 mutant 对照腿成四腿，见 r2 记录；含 cmp 非空变更守卫）并注册进 fast_tests——每次 `make test`（本地与 CI）均执行；沿 umbrella 既有"行为在 fast 层、wiring 在 heavy 层"先例，不动 CI workflow（scope out 维持）。双 ruby 实测过。前序 chain id `gate-date-require-r1` 在 plan 校验期零模型消耗失败（self_review 缺派生 owner terminal-cli-dev 行），无评审内容，evidence 目录仅存空 stderr，弃用。
- **chain `gate-date-require-r2`**（candidate sha256 `eb954833…` = amend 提交 84798c8 的冻结 packet，codex 双 lane，binding established，同前 reviewed_skills）：各 1×P1，非同类。(1) challenge——fast 测试第 3 腿空 `RUBYOPT` 在 date-less host 上测不到 date-preloading 条件（gate 自己的 require 定义了 Date，腿必绿）。**accepted，按其 smallest_fix 落**：第 3 腿改 `-rdate` 显式预载（任意 host 上确定性对照），补第 4 腿 mutant+`-rdate` rc 0——腿 2×4 构成"同一 mutant 跨 host 翻转 verdict"差分，机器化钉住掩蔽机制；双 ruby 复测 ok。(2) review——发布验收依赖散文断言，packet 内无原始命令/版本/退出码，也无证明 fast_tests 被 make test 执行的 runner 接线上下文。**部分为 packet 组成缺陷**（diff-only packet 看不到未变更的 runner 上下文——按 packet 规则加宽而非改候选），**实质部分 accepted**：原始执行证据块落入本 plan 下节，r3 终审 packet 以 `--diff-file` 组装（全量 diff + 未变更 runner 接线摘录 + 原始运行输出）。
- **chain `gate-date-require-r3`**（终审候选，review lane；Agent 预算第 5/5 轮，按 p3-log-plus-test 轮先例）：（回填于下）

#### 原始执行证据（r2 review P1 的 accepted 落点）

- host A：`ruby 4.0.5 (2026-05-20 revision 64336ffd0e) +PRISM [arm64-darwin25]`（psych 5.3.1）；host B：`/opt/homebrew/opt/ruby@3.2/bin/ruby` = `ruby 3.2.11 (2026-03-27 revision 5483bfc1ae) [arm64-darwin25]`（psych 5.0.1，实测 `require "yaml"` 后 `defined?(Date)` → nil）。
- heavy 层深版：`bash skills/skill-extraction-workflow/scripts/test_check_ccl_impact_chain_refscripts.sh` → `test_check_ccl_impact_chain_refscripts: ok`，exit 0（host A 与 host B 各一遍，80 gate runs；RED 先行：修复前同命令在新 case 处 `FAIL: expected rc=0 got rc=1 (a date-less host must not refuse the routing-surface class)`，suite exit 1）。
- fast 层含护：`bash skills/skill-extraction-workflow/scripts/test_impact_chain_gate_dateless_host.sh` → `test_impact_chain_gate_dateless_host: ok`，exit 0（host A 与 host B 各一遍，四腿版）。
- runner 接线：`Makefile` `test` 目标第 2 行 `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --fast`；该脚本 `fast_tests` 数组含 `test_impact_chain_gate_dateless_host.sh`（本轮注册），故本地与 CI 的每次 `make test` 均执行 fast 层含护测试。
- 修前干净基线：detached worktree @ dev `fb55157`，`make test` exit 0（全 21 个回归计时行 status=0）。修后全量：amend 候选上 `make test` + `test_check_ccl_regressions.sh --full` 结果回填于终审后（见止点节）。
- CI 失败复现与修复对照：`CCL_SKILL_BASE_REF=2aa8cd3… ruby(3.2.11) impact-chain-gate.rb <PR#5 测试合并 4ca9a97 检出>` → 未修 exit 1（文案与 CI 日志逐字一致）/ 修后 exit 0。
