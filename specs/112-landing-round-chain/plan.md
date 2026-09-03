# 112 — 落地闸沿首父链逐轮绑定：dev 叠多轮后一个 PR 晋升

## Artifact classification

`gate implementation`（共享确定性闸 `review_ledger_binding.py`，CI required check）。改动**新增一条 accept 路径**（acceptance 语义变化），因此本文件是规则要求的仓内持久计划工件。

## 来源：被证实的缺陷

- 落地闸把候选身份定义为 `freeze_packet(fork_point..HEAD)` 的 packet 哈希，只接受两种证据：一份绑定整条候选的 closeout ledger，或（107 轮起）一份按**路径**分区的 landing partition manifest。
- dev 上叠了 108/109/110 三轮之后做 dev→main 晋升，晋升候选 = 三轮内容之和，但：① 108 与 109 都往 `references/source-register.md`（append-only 台账）追加行，任何按路径的分区都把这个文件整体划进某一个分区，该分区的 packet 哈希不等于任何一轮评审过的哈希；② 各轮的 ledger 是对着**自己当时的 dev tip**冻结的（109 对着 f156079，含 108），与晋升分叉点 54e0f36 不同。所以 0.13.0 晋升只能分三波 PR（#121–#123），每波 head 指向 dev 上那轮的 merge commit。
- 结论：107 解决了「单轮候选过大」，没解决「多轮叠加」。分波是绕行，不是闸的能力。`ci.yml` 注释也自认「Binding several queued candidates as one is unsolved」。

## 真仓复现（2026-09-02，改动前）

对触发本轮的晋升（HEAD=origin/dev `fa0a7de`，base=旧 main `54e0f36`）沿 dev 首父链回走，到第一个是 base 祖先的提交为止，得到三步，全部是 merge commit：

| dev 首父链提交 | p1 | p2（该轮分支 head） | 树 == 自动合并树 | dev 是否在分叉后前进 | 在 p2 检出、以 p1 为 base 跑现有闸 |
|---|---|---|---|---|---|
| `fa0a7de`（#119，110 轮） | `6f91948` | `c2d9551` | 是 | 前进过 | `review_ledger_binding_ok`（110 closeout） |
| `6f91948`（#120，109 轮） | `f156079` | `18a94a0` | 是 | 未前进 | `review_ledger_binding_ok`（109 closeout） |
| `f156079`（#118，108 轮） | `54e0f36` | `fd574b4` | 是 | 未前进 | `review_ledger_binding_ok`（108 closeout） |

即：每一轮在**它自己的 base** 上都已被现有闸绑定；每个 merge commit 的树都等于 `git merge-tree --write-tree p1 p2` 的自动合并结果。缺的只是闸把这条链走一遍。

## Scope

| # | 变更 | 语义轴 | 状态 |
|---|---|---|---|
| 1 | `review_ledger_binding.py` 新增首父链逐轮绑定的 accept 路径（单 ledger、分区清单都不成立时尝试） | acceptance（新增 accept 路径） | 本轮做 |
| 2 | 把闸主体重构成可对任意（检出, base）求值的函数，逐轮求值复用同一段代码 | 结构，不改既有裁决 | 本轮做 |
| 3 | `test_review_ledger_binding.sh` 链绑定用例（RED 先行）+ 突变走查 | 回归 | 本轮做 |
| 4 | `dual-track-review-gate.md` / `extraction-quickstart.md` 记录链绑定语义与晋升配方 | 文档 | 本轮做 |
| 5 | `.github/workflows/ci.yml` 注释：多轮叠加已解，merge_group 多 PR 聚合仍未解且边界另述 | 注释 | 本轮做 |
| 6 | `source-register.md` 追加一行（append-only，最后一个 commit） | 台账 | 本轮做 |
| 7 | `packages/ccl-skills-npm/package.json` + `package-lock.json` 三处 0.13.0 → 0.14.0（minor：闸新增 accept 路径） | 发版版本指针 | 本轮做 |

不在 scope：merge_group（多个**未合并** PR 合成一个 HEAD——它们没有各自落地过的 merge commit，链上没有节点可绑）；`review_gate.py` 收据 schema；`MAX_PACKET_BYTES`；嵌套链（一轮的分支内部又是一条链——按深度 1 处理，见 D2）。

## 设计裁决

### D1 — 按历史（首父链）聚合，不按路径

备选 A：扩展分区清单，允许一个文件被多份 ledger 覆盖。否决：共享 append-only 文件在晋升候选里的 diff 是两轮追加之和，没有任何一轮的 packet 含这个和；按路径永远切不开。
采用 B：晋升候选 F..HEAD 的内容全部经由 dev 首父链上的 merge commit 进入。每个 merge 的 p2 是某一轮评过的分支 head，那轮的 ledger 绑的是 `merge-base(p1,p2)..p2`——正是闸在「检出 p2、base=p1」时会重算的候选。所以闸沿 HEAD 的首父链回走，对每个 merge commit 在临时 detached worktree 里检出 p2、以 p1 为 base **重跑自己**。

### D2 — 逐轮求值复用闸本身，深度为 1

逐轮求值 = 同一段绑定逻辑（单 ledger 或分区清单）在 `(worktree(p2), base=p1)` 上执行，用**该轮检出里的** controller 与 validator（与 docstring「闸跑候选自己的 validator」同一立场；那轮进 dev 时 CI 判的就是这套）。逐轮求值**不再尝试链**——一条链的节点必须是单 ledger 或分区清单直接绑定的轮；嵌套链不在 scope，避免无界递归。

### D3 — 每一步的树必须等于自动合并树

对首父链上每个 merge commit，`git merge-tree --write-tree p1 p2` 得到的树必须等于该 commit 的树。含义：merge commit 自身没有引入任何超出「自动合并两个已知父」的内容——没有冲突解决、没有手工编辑的 evil merge。冲突（merge-tree 非 0 退出）同样拒。这条对**同步合并**也成立（见 D4）。这是链式绑定的承重不变量：每一步的内容都可归约到「已绑定的轮 + 已在目标分支上的内容」。

### D4 — 三类节点，只有一类需要证据

沿 HEAD 首父回走，直到第一个是 **base tip 祖先**的提交（`git merge-base --is-ancestor c <base tip>`）——这是链与目标分支历史的汇合点，之下的内容已在目标分支上。路上每个提交分三类：
- **同步合并**：p2 是 base tip 的祖先（`update-branch` 把 main 并进来、或早先把 main 并进 dev）。不需要证据，但树仍须等于自动合并树。
- **轮次合并**：其余 merge commit。在 `(p2, base=p1)` 上必须绑定成功（D2），且树等于自动合并树（D3）。
- **非 merge 提交**：直接推到集成分支的提交。**拒**——它的内容没有任何一轮评过。
链长上限 `MAX_CHAIN_STEPS = 64`；回走到根仍未遇到 base 祖先 → 拒。

### D5 — 顺序、触发条件与文案

既有路径优先：整条候选能冻结且有单 ledger → 通过（不变）；否则分区清单 → 通过（不变）；两者都不成立且 `--paths` 为默认值（`.`）才走链——`--paths` 收窄时链语义不成立（各轮 ledger 绑的是整轮），明确报「链绑定只对默认路径集求值」。链失败时把每一步的判定逐行打出（哪一步、哪类、为何拒），和既有的 rejected ledger / manifest 行一起输出。

### D6 — 名字级交叉核对（防御性）

在 D3 成立的前提下，F..HEAD 的变更文件集 ⊆ ∪(各轮变更文件集) 由归纳可得；仍做一次 name-only 核对，出现不属于任何一轮的变更文件即拒并点名——这是对 D3 实现缺陷的第二道网，成本是几次 `git diff --name-only`。

### D7 — 临时 worktree 的卫生

`git worktree add --detach <系统临时目录> <p2>`，路径在仓库根之外（否则会作为未跟踪文件进入被绑定路径）；`finally` 里 `git worktree remove --force` + `git worktree prune`；`sys.dont_write_bytecode` 已在，且 controller 从该轮检出加载。worktree 建不出来、`git merge-tree --write-tree` 不受支持（git < 2.38）→ `review_ledger_binding_error`（环境错误，不是拒绝也不是通过）。CI 的 checkout 已是 `fetch-depth: 0`。

### D8 — 边界（明写，不掩盖）

- 链绑定证明的仍是同一件窄事：落地的每一字节都被某轮外部评审冻结过——按轮取。不证明那轮诚实，不证明它没漏。
- 用各轮自己的 controller/validator：一轮若在自己分支里掏空 validator 而自绑，那轮进 dev 时 CI 已经放过它（既有边界「候选改写 validator 不在仓内可判范围」），本轮不扩大也不收窄这条边界。
- merge_group 多 PR 聚合仍未解：队列里的 PR 还没有各自的 merge commit，链上没有节点。`ci.yml` 注释同步改写为这个准确边界。

## Acceptance matrix（决策表：具名输入 → 单一裁决）

既有行不变（见 085/107 plan）。本轮新增：

| 输入 | 裁决 |
|---|---|
| HEAD 首父链到 base 祖先之间全是轮次合并，每轮在自己 base 上有 validator 接受的 ledger（或分区清单），每步树 == 自动合并树 | `pass`（**本轮新增的唯一 accept 路径**） |
| 同上，但链顶多一个把 base 并进来的同步合并（`update-branch`） | `pass` |
| 同上，某轮 dev 在分叉后前进过、合并仍是干净自动合并 | `pass` |
| 某轮 p2 在 `(p2, base=p1)` 上没有 validator 接受的证据 | `refuse: round <sha> … no accepted review evidence` |
| 某轮 ledger 绑的是别的哈希（评完又改） | `refuse`（同上，逐轮求值报出） |
| 首父链上有非 merge 提交 | `refuse: <sha> is not a merge` |
| 某 merge commit 的树 ≠ `merge-tree --write-tree p1 p2`（冲突解决 / evil merge） | `refuse: <sha> tree differs from the automatic merge` |
| `--paths` 收窄且前两条路径都不成立 | `refuse`，文案说明链绑定只对默认路径集求值 |
| 链长 > 64 或回走到根未遇 base 祖先 | `refuse` |
| F..HEAD 变更文件不属于任何一轮 | `refuse: changed paths outside every bound round` |
| 整条候选 ≤ 200KB 且有单 ledger | `pass`（既有路径，先于链） |
| 临时 worktree 建不出 / merge-tree 不受支持 | `error`（非 0，不是通过） |
| 跑完后 `git worktree list` 与跑前一致，被绑定树字节不变 | 不变量（用例断言） |

## 测试层决策表

| 层 | 处置 | 命令 | 理由 |
|---|---|---|---|
| unit / 脚本套件 | **add + run（RED 先行）** | `bash skills/skill-extraction-workflow/scripts/test_review_ledger_binding.sh` | 新 accept 路径每条拒绝分支各一用例 + 通过路径 + 卫生不变量 |
| 突变走查 | run | 就地突变 → 跑套件 → 复原（`git diff --quiet` 确认） | 每条承重谓词（自动合并树、非 merge、逐轮证据、名字核对、同步合并判定）恰红自己的用例 |
| integration | run | `make test` | 闸被 CI 与合成夹具调用；`make test` 不含 heavy lane |
| CI-only lane | run | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `make test` 不含它 |
| 泄漏 / 结构 | run | `python3 scripts/check-public-sanitization.py .`、`python3 scripts/check-spec-references.py`、`python3 scripts/check-release-version.py` | 新增 specs 目录 + 改共享文档 + 版本指针 |
| 真仓复现 | run | 在本 worktree 对 `54e0f36..origin/dev`（触发本轮的三轮叠加）跑改后的闸，必须 `ok` 且逐轮列出三份 closeout | 这是触发本轮的输入 |
| E2E / 渲染 | not applicable | — | `visible surface: no` |
| manual | not applicable | — | 无人工路径 |

## 风险路由记录（feature-risk-router）

- risk tags：`shared-gate`、`release-ops`（CI required check 的 accept 语义）。
- `security-review` change-triggered 臂：**security posture unchanged**——信任模型不变（evidence 仍 caller-controlled；各轮 validator 由那轮自己的检出提供，与既有「候选改写 validator」边界相同）；新增的 git 调用全部以 40-hex 提交 id 为参数（不接受调用方字符串），临时 worktree 在仓外且必删；对抗 challenge 仍需探 bypass（例如：能否构造一个「自动合并树」相等但内容未评的 merge）。
- required gates：本计划工件；RED→GREEN 套件 + 突变走查；`make test` + heavy lane；dual-track review（1 review + 1 challenge，fix 全部 hold 到 challenge 之后）绑定最终 diff 并产出 closeout ledger；CI 全绿；PR 停在待审，合并授权在用户手上。
- skippable：UI/渲染证据（无渲染面）。
- stop reasons：无（方案唯一且可逆；真仓复现已证三轮全部可绑）。

## 实施边界记录

- active baseline：本文件；scope 如上表。
- implementation-mechanics owner：`python-service-dev`（Python 脚本）+ `testing-strategy`（差分用例设计），会话内已加载；`worktree-isolation` Step 0 已过（`worktree-112-landing-round-chain`，base `origin/dev` = `fa0a7de`）。
- `multi-agent-delegation`：`local`——单文件脚本 + 单套件，无独立可并行切片。
- visible surface：no。
- test-case-first：链用例先写先红，再实现。
- verifier discovery（gate implementation）：AGENTS.md 指 `make test`（三 lane）+ heavy lane + `check-public-sanitization.py`；本轮改动前已在本 worktree 跑 `test_review_ledger_binding.sh`（54 例绿）与 `make test-repo-gates`（基线）。

## CLI 契约记录（terminal-cli-dev 轻量记录）

不新增 flag。既有 `review_ledger_binding_ok / failed / error / no_change` token 不变；链绑定通过时报 `review_ledger_binding_ok: the first-parent chain binds the landing candidate as N rounds`，随后逐轮一行 `round <sha12> <- <ledger> -- <validator 输出>`，同步合并一行 `sync <sha12> (already on the base)`。失败诊断一律 stderr。无交互、无颜色、无 TTY 依赖；`visible surface: no`。

## 提炼 charter 与 owner map（skill-extraction-workflow 本轮记录）

| 字段 | 内容 |
|---|---|
| Task | 落地闸沿首父链逐轮绑定（capability 命名，无源项目名词） |
| Purpose | 防止「集成分支叠多轮后晋升必须分波」再发生；保留「落地的每一字节都被某轮外部评审冻结过」的不变量，按轮取而不是按路径取 |
| Scope | In：`skill-extraction-workflow`（binder 脚本、其套件、dual-track 与 quickstart 两份 reference、台账行）；`.github/workflows/ci.yml` 注释；npm 版本指针。Out：merge_group 多 PR 聚合；嵌套链；收据 schema |
| Depth | tooling change + targeted reference refresh（重读了 binder 全文、controller `freeze_packet`、ci.yml 两个 job 的 checkout 配置、107 plan、dev 首父链真仓复现） |
| 结果分类 | failure/correction（可观测失败：0.13.0 晋升被迫分三波 PR） |
| Matching analysis | RCA 见下 |
| Evidence plan | 一手源＝仓内代码与 CI 注释 + 对触发候选的逐轮实测（上表）；memory 里「根治＝链式验证聚合」按规则视为 hypothesis-grade 的 deferred registration，本轮先在真仓复现了它的三个前提（各轮自绑、树自动合并、汇合点可判）才动手；外部实践不适用（本仓自有闸的实现缺口） |
| 完成标准 | 新用例 RED→GREEN + 突变走查 + 真仓三轮复现 `ok` + 各 lane 绿 + dual-track 1+1 + closeout ledger 绑定本候选 |

RCA（widen 后再深入）：
1. 触发/设计：闸只认「一个哈希对一份 ledger」和「按路径切」两种形状；集成分支上多轮叠加是第三种形状（按历史切），107 轮把它和 merge_group 混写成「聚合未解」一类，掩盖了它其实可解（各轮已各自绑定）。
2. 缺失的机械控制：每轮进 dev 时 CI 已经对着那轮的 base 绑定过，这份证据在晋升时被丢弃了——闸没有回走历史的能力。
3. 检测缺口：107 只用「单候选过大」的真仓输入验收，没有用「dev 叠多轮」的输入验收；两种聚合的差别在实现完成后才被 0.13.0 晋升暴露。
4. 潜在条件：分波晋升有效且便宜，让「闸缺能力」看起来像「流程可绕」；memory 里写了根治方向但没有开轮的触发。
预防＝机械控制：闸消费首父链（本轮落地）+ 自动合并树不变量 + 注释精确区分三种聚合。人为纪律（「下次别分波」）不作为原因或预防。

Owner map（`owner | direction | status | reason`）：
- `skill-extraction-workflow` | 本体 | updated | 脚本、套件、两份 reference、台账行
- `code-review` | upstream（packet 冻结与分区规则的定义者） | unchanged | 冻结语义不变；链绑定只重用 `freeze_packet`
- `product-rd-workflow` | upstream（shared-gate 分类） | unchanged | 本轮按其 shared-gate 分类走，规则无缺口
- `testing-strategy` | sibling（评审/测试层） | unchanged | 突变走查与精度行按其既有规则执行
- `platform-release-engineering` | downstream（晋升/发布） | unchanged | 晋升配方回到「一个 PR」，dev→main 配方本身不变
- `worktree-isolation` | sibling | unchanged | 闸内部用的临时 detached worktree 是脚本机制，不是开发隔离
- `.github/workflows/ci.yml` | 非技能 | updated | 注释精确区分三种聚合

## 评审轮记录（dual-track，extraction lane 1+1，fix hold 到 challenge 之后）

（实施后填写）

## Status-sync target

`skills/skill-extraction-workflow/references/source-register.md` 追加本轮行（append-only，作为最后一个 commit，firing-path 指向 `command:skills/skill-extraction-workflow/scripts/test_review_ledger_binding.sh`）。

## Review / challenge gate

`shared-gate` + `release-ops`。需要绑定最终 diff 的独立对抗评审（extraction lane：1 review + 1 challenge，fix 全部 hold 到 challenge 之后）；closeout ledger 绑定本轮自己的落地候选。合并授权在用户手上。
