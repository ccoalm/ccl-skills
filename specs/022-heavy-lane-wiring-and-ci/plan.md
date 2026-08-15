# 022 — heavy 层修复轮：wiring anchor 运行时派生 + CI `--full` job

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 关闭 021 轮路由给维护者、维护者裁决"解决了再合并（PR #5）"的两项：(1) `test_register_firing_path_wiring.sh` 的 seed fixture anchor 钉死 README 已不存在的标题，测试在 dev 上恒红（021 轮以修前基线 `fb55157` 差分证明为既有损坏）；(2) 回归 umbrella heavy 层在 GitHub CI 无执行 job（脚本注释假设的 GitLab `--full` job 不存在于 ci.yml），坏测试因此长期零反馈。 |
| Artifact classification | `gate implementation`（wiring 测试 fixture 修复，断言语义不变）+ `status sync` 性质的 CI 执行面补齐（新增 job 不改任何既有 job/闸的 verdict 语义，但为 heavy 层新增合并时红灯面——按 shared-gate 纪律全闸走查）。feature-risk-router 定级 `shared-gate` + `release-ops`（CI workflow 变更）；security-review 变更臂 not-applicable：security posture unchanged。 |
| Scope | in：`skills/skill-extraction-workflow/scripts/test_register_firing_path_wiring.sh`（seed anchor 运行时 fence-aware 派生 + 三个派生/计数自测 + 断言计数守卫按机器清单修正，终态 16=13 原有 case+3 自测）；`.github/workflows/ci.yml`（新增并行 `regression-heavy` job 跑 `--full`）；本 plan；source-register 行。out：wiring 测试其余断言语义；`register-firing-path-resolution.rb` 本体；README 内容（不为测试恢复旧标题——那是把词表反向钉进 README）；`--fast`/`--full` 分层策略本身。 |
| Depth | 单测试脚本 fixture 修复 + CI workflow 增量 + 轮 artifact。 |
| Root cause | (1) seed anchor 是"控制不拥有的词表"（README 标题字面量）——README 演化即断，cross-landing predicate 规则的实例：钉具体值而非自有不变量；(2) heavy 层无 CI 执行面 → 断了无红灯。互为放大：无执行面使词表钉死的脆弱性零反馈。派生缺陷：断言计数守卫 16 与实际 13 不符（suite 恒红期间计数漂移，历史被 squash 无法考据 16 的来源——以机器计数真值修正）。 |
| RCA analysis | widen：(a) anchor 钉死词表（必要因；反事实：运行时派生后，旧 pin 失效的同一份 README 上测试转绿——本轮 RED→GREEN 即该反事实的实测）；(b) heavy 层无 CI job（必要因；反事实：有 job 则 README 改标题当次 PR 即红）；(c) 检测缺口——021 轮首次跑 `--full` 才暴露。两个机械控制同轮落地。 |
| Failure mode analysis | (1) 派生失败静默——守卫：派生不出合规标题即 `fail` 快停（≥16 字符、文件内唯一、无 `\|`/`;`/`#`/反引号）；(2) 派生标题破坏 row 格式——同一约束集排除定界符；(3) CI job 依赖缺失假红——依赖安装步骤逐字对齐既有 repository-gates job；(4) 拖慢 CI——并行 job，不入关键路径（repository-gates ~15min > heavy job 预估 ~10min）；(5) 计数守卫改错方向——13 为本轮实测执行数（`register_firing_path_wiring_tests_ok (13 assertions)`）。 |
| Evidence plan | 已产：021 轮 `--full` 红灯日志 + `fb55157` 差分（既有损坏证明）+ README grep=0 + 本轮 RED 复现（anchor 修后 suite 在计数守卫处再红，实测 13）。已产（本轮）：修后 wiring 单跑绿；待产：make test + `--full` 全绿（author-dogfood）；dual-track 链；CI 上新 job 首跑绿。 |
| Completion standard | wiring 测试绿且 anchor 不再依赖任何标题字面量（派生自当前 README，旧 pin 失效的 README 即反事实证据）；`--full` heavy 层 5/5 绿；make test 绿；checker clean（R0 private-ok）；register 行 + 本 plan 落树；dual-track 无未处置 P0/P1；合 dev 推送后 PR #5 全部 job（含新 `regression-heavy`）绿；PR 合并候用户显式指令。 |

## 修法与判定

| # | 输入 | 预期 | trace |
| --- | --- | --- | --- |
| 1 | 修后 wiring 测试 @ 当前 README（旧 pin 在此失效） | 13/13 PASS、exit 0 | `register_firing_path_wiring_tests_ok (13 assertions)`（已执行） |
| 2 | anchor 修后、计数守卫未修 | 尾部 `expected 16 assertions, saw 13` FAIL | RED 实测（已执行，先于计数修正） |
| 3 | README 无合规标题（假想输入） | 派生守卫 `fail` 快停，不 seed 不可解析行 | 代码路径（`[ -n "$seed_anchor" ] \|\| fail`），由 dual-track 评审员核 |
| 4 | `--full` @ 本轮候选 | heavy 5/5 status=0、exit 0 | 首版候选实测 exit 0（wiring 144s status=0）；终版候选复跑回填于"终版候选验证"节 |
| 5 | PR #5 重生成 merge ref @ CI | 四 job 全绿（含新 `regression-heavy`） | 推送后回填（detached-HEAD 行为的活体证明也在此步） |
| 6 | （历史）围栏/混标记 decoy fixtures @ 派生设计 | 派生选真标题 | RED 取证 ×2 留档（旧正则选围栏 decoy、旧布尔翻转选混标记 decoy）；**派生设计已按 r3 `replace` 裁决整体删除**——anchor 改为 fixture 自有注记文件，解析面不复存在，本行与行 7 保留为过程证据 |
| 7 | （历史）无合规标题 fixture @ 派生设计 | 派生输出空 → fail 快停 | 同上，随派生设计删除；自有注记文件设计下 seed 无条件可解析 |
| 8 | 脚本自身 pass 清单 vs 守卫字面量 | 三向一致（静态清单 = 守卫 = 执行数，终态 14） | 计数自测过（14/14 suite 绿）；守卫咬合的实测证据 = 观测到的 expected-16-saw-13 活体 RED |
| 9 | fixture 自有注记文件 anchor（终版设计） | 干净 clone checker 过、mutation case 可变异真 anchor | 14/14 `register_firing_path_wiring_tests_ok`（终版候选，见"终版候选验证"节） |

**新增机械 gate 的 design-time operability check**（`regression-heavy` job）：author-dogfood=判定 4（`--full` 在候选上全绿后才落地）；marginal-cost=+1 并行 job（约 10 分钟，与 15 分钟的 repository-gates 并行，不延关键路径；每 PR/push 多一台 runner 的成本）；trust-model=防"heavy 层测试静默腐坏"类（本轮 wiring 即实证）；premise=非收紧既有 verdict，为无执行面的既有 suite 补执行面。

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| skill-extraction-workflow | self（suite owner） | updated | `scripts/test_register_firing_path_wiring.sh`（anchor 派生 + 计数 13） |
| CI workflow | release 执行面 | updated | `.github/workflows/ci.yml` +`regression-heavy` job |
| source-register | ledger | updated | impact-chain 行（scripts 变更，firing-path: command:scripts/test_register_firing_path_wiring.sh） |
| specs | plan | added | 本文件 |
| README / resolution gate 本体 / 其余 skill | — | unchanged | README 不为测试改内容；gate 本体断言语义不动；无其他 owner 受影响 |

## 实施边界与评审门

- 实施边界：baseline=本 plan；worktree `worktree-heavy-lane-fix` 自 dev `8b0f44b` 分出；实现机制 owner 按 skill-extraction-workflow scripts 惯例；测试机制 owner `testing-strategy`（021 轮同会话已加载，本轮沿用其 mutation-walk/executed-count 纪律）；`multi-agent-delegation`: local——两个微小串行 slice；visible surface: no；`feature-risk-router`: shared-gate + release-ops（见 charter）；test-case-first：判定表 1/2 先于修正执行（RED 天然存在于 dev）。
- 评审门：dual-track 单链（review + challenge）对本轮全部 diff；全部 P0/P1 处置后合 dev；Agent 预算本轮独立计。
- status-sync：本 plan 即轮记录；register 行终稿一次落。

### Dual-track 评审记录

- **chain `heavy-lane-r1`**（candidate sha256 `26f50106…` = 首版提交 6efaec9 的冻结 packet，codex 双 lane，binding established，reviewed_skills：skill-extraction-workflow / terminal-cli-dev / testing-strategy）：review 3×P2、challenge 3×P1。处置：
  1. **challenge P1（围栏 decoy）accepted**——旧正则确会选中围栏代码块内的 `#` 行（判定表行 6 的 RED 对照实测）；派生改为 fence-aware 扫描器，decoy 回归 fixture 入自测。
  2. **review P2（fail-fast 无回归保护）accepted**——无合规标题 fixture 自测入 suite（判定表行 7）。
  3. **challenge P1 + review P2（计数守卫不可验/无 dropped-case 突变）accepted 变体**——落"静态 pass 清单 = 守卫字面量 = 执行数"三向钉（判定表行 8）；活体 dropped-case 整套双跑（+144s）以两项实测证据替代：守卫咬合已由本轮 expected-16-saw-13 RED 观测证明，字面量↔清单漂移由静态钉机械捕获。
  4. **challenge P1（CI 含护）部分 accepted**——失败传播与 `--full` 识别的证据入下节（021 轮 `--full` exit 1 = 真实失败经 umbrella 传播到命令退出码的实测负控；本轮 `--full` exit 0 且逐 suite timing 行证明 heavy 全执行）；CI 级 fault-injection harness **谢绝**：所防的"umbrella 吞子状态"类已被上述实测负控证伪，harness 边际成本超出其价值（design-time operability 判定）；**detached-HEAD 残余留待合并前 CI 首跑活证**（判定表行 5 本就前置于合并）。
  5. **review P2（plan pending 格）accepted**——判定表 trace 已回填；终版候选的 make test + `--full` 复跑结果落"终版候选验证"节。
- **chain `heavy-lane-r2-probe`**（candidate = amend 提交 ab3b91a 的冻结 packet，codex review lane；名带 -probe 因后台首跑 `heavy-lane-r2` 零输出瞬态失败——无模型消耗、evidence 目录仅空 stderr，弃用该 id 前台复跑即本链）：1×P1+1×P2+1×P1。处置：
  1. **P1（16 与"冻结验收 13"矛盾）= 评审输入缺陷，候选无缺陷**——我提供的 review-plan JSON 验收文案未随 amend 更新（仍写"16→13"），评审员按其判定正确；修输入后 r3 重审（按 packet 规则改输入不改候选）。
  2. **P2（围栏混标记）accepted**——布尔翻转确会被 ``` 围栏内的 `~~~` 行误闭（RED 取证：旧逻辑对混标记 fixture 实测选中 decoy）；扫描器改标记感知（记录开栏标记字符与长度，仅同字符且不短于开栏长度的行闭合），混标记 decoy 并入自测 1 fixture（不增计数）。
  3. **P1（终版验证占位）accepted**——终版候选的 make test + `--full` 机器输出落"终版候选验证"节后再落地（与 021 轮同款收口；CI 行为的活证仍前置于合并）。
- **chain `heavy-lane-r3`**（candidate sha256 `f0503dc5…` = 提交 2eb2739 的冻结 packet，codex review + challenge 双 lane，binding established；Agent 预算 r1×2 + r2-probe×1 + r3×2 = 5/5 用尽）：review 2×P1+1×P2、challenge 2×P1，**fence 解析正确性跨轮同类收敛**（r2-probe 混标记翻转、r3 双 lane 闭栏后缀识别——CommonMark 闭栏须仅尾随空白，prefix-only 匹配会把围栏内 ` ```python `/` ```not-a-close ` 行误当闭栏）。**按"同类对抗发现跨轮复现=设计味"纪律裁决 `replace`**：
  - 同类证据：两轮三条 fence 解析发现（fenced decoy、mixed-marker、close-suffix），每条修复都在为"解析 suite 不拥有的 artifact"这个能力补丁。
  - 真实需要：suite 只需要"clone 树内一条可解析、可变异的 anchor"——不需要它来自 README。
  - 更安全替代：fixture **自写自提交** anchor 注记文件（`wiring-fixture-note.md`，标题即 anchor），词表 100% suite 所有，解析面整类删除；派生函数与两条派生自测随之移除（其 RED 取证留档为过程证据），计数三向钉保留，终态 14=13 原有 case+1 计数自测，实测 14/14 绿。
  - 爆炸半径：仅本 suite 的 seed 段；resolution gate 与其余 13 case 语义不变；无迁移面。
  - r3 的 plan 占位 P1 照 021 先例处置：终版验证机器输出落"终版候选验证"节（本次即回填）；dropped-case 负控以"观测到的 16-vs-13 活体 RED + 静态三向钉"覆盖，detached-HEAD 以合并前 CI 首跑活证（判定表行 5）。
  - **止点声明**：Agent 自主预算 5/5 用尽；本 `replace` 增量（r3 后落地）与 r3 未消费容量按 021/p3 轮先例随合并决定暴露给维护者——各链无未处置 P0/P1，全部确定性闸在含增量的终版候选上复跑（见下节）。

#### CI 含护证据（r1 处置 4 的落点）

- 失败传播负控（实测而非注入）：021 轮首次跑 `--full` 时 wiring suite 失败，umbrella 逐 suite 记录 `status=1` 并以非零退出码终止（`post-commit full verification exit: 1`）——子失败确实穿透 umbrella 到 CI 将消费的命令退出码。
- `--full` 识别与全执行：本轮首版候选 `--full` exit 0，逐 suite `regression_test_timing` 行覆盖 heavy 全部 5 个 suite（wiring 144s status=0）。
- `regression-heavy` job 依赖步骤与 repository-gates 逐字一致（ripgrep/ruby/pytest/pyyaml + fetch-depth 0）。

#### 终版候选验证（closeout 回填）

- （amend 后复跑 make test + `--full`，回填于此）
