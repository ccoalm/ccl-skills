# 107 — 落地闸接受分区清单：解除 MR 大小与模型输入上限的耦合

## Artifact classification

`gate implementation`（共享确定性闸 `review_ledger_binding.py`，CI required check）。改动**新增一条 accept 路径**（acceptance 语义变化），因此本文件是规则要求的仓内持久计划工件。

## 来源：被证实的缺陷

- 落地闸把「候选身份」定义为 `freeze_packet(fork_point..HEAD, paths=".")` 的 packet 哈希（`review_ledger_binding.py:297`）；`MAX_PACKET_BYTES=200_000` 是 reviewer 一次能完整读取的模型输入上限（`review_gate.py:23`、`opencode_review.sh:40-41`）。
- 整条 diff 超过 200,000 字节时 `freeze_packet` 抛错，闸报 `cannot freeze the candidate packet`，且闸只寻找**一份**哈希等于整条 diff 的 ledger。`code-review/SKILL.md:224` 允许评审层按文件组分区，但落地层不消费分区收据。
- 实测：0.11.0 dev→main 晋升整条 diff 623,458 字节（去 `specs/` 仍 323,945），被迫拆成 8 个 wave PR（#108–#115）。`ci.yml` 注释自认「Binding an aggregate candidate is unsolved」。
- 结论：MR 的 Git 身份（base SHA → head）与模型评审输入（≤200KB packet）是两个身份，当前被同一个哈希绑死。修法是给闸补分区聚合，不是继续拆 MR。

## Scope

| # | 变更 | 语义轴 | 状态 |
|---|---|---|---|
| 1 | `review_ledger_binding.py` 新增 landing partition manifest 的绑定路径 | acceptance（新增 accept 路径） | 本轮做 |
| 2 | `review_ledger_binding.py` 新增 `--print-manifest --partition …` 渲染器 | 作者侧工具，不改裁决 | 本轮做 |
| 3 | `test_review_ledger_binding.sh` 分区用例（RED 先行） | 回归 | 本轮做 |
| 4 | `dual-track-review-gate.md` / `extraction-quickstart.md` 记录分区落地配方 | 文档 | 本轮做 |
| 5 | `.github/workflows/ci.yml` 注释：单候选过大已解，多 PR merge_group 聚合仍未解 | 注释 | 本轮做 |
| 6 | `source-register.md` 追加一行（append-only，最后一个 commit） | 台账 | 本轮做 |
| 7 | `packages/ccl-skills-npm/package.json` + `package-lock.json` 三处 0.11.0 → 0.12.0（minor：闸新增 accept 路径与 CLI flag） | 发版版本指针 | 本轮做；`check-release-version.py` 已过（地板 0.11.0） |

不在 scope：merge_group（多个 PR 合成一个 HEAD）的聚合绑定；`review_gate.py` 收据 schema（收据不新增字段）；`MAX_PACKET_BYTES` 数值。

## 设计裁决

### D1 — 分区按 pathspec 切，不按历史组合

备选 A：晋升候选 = 历次 dev 落地 ledger 的组合。否决：`update-branch`/冲突解决后 main..dev 的 diff 不等于历次 packet 之和，且历史形状（merge/rebase）会改哈希。
采用 B：候选按**路径**分区。`freeze_packet` 已支持 `--paths`，分区 packet 的字节只取决于该分区路径下的 diff，与其他分区无关；作者用现有 `--print-candidate --paths <分区路径>` 就能得到每个分区的哈希。

### D2 — manifest 是一份「关于聚合候选的收据」

清单文件落在某轮的 evidence 目录下（路径模板 `<round>/evidence/<name>.json`，不带 specs 前缀以免被当作引用），形状：

```json
{
  "schema_version": 1,
  "kind": "landing_partition_manifest",
  "base": "<fork point 40-hex>",
  "partitions": [
    {"paths": ["skills/code-review"], "candidate_sha256": "<该分区 packet 哈希>"},
    {"paths": ["skills/skill-extraction-workflow", ".github"], "candidate_sha256": "<…>"}
  ],
  "candidate_sha256": "<聚合身份 = sha256(canonical JSON{schema_version, kind, base, partitions})>"
}
```

顶层 `candidate_sha256` 让它满足现有排除谓词（`is_candidate_receipt`），所以提交清单不会移动任何分区的哈希——这是它必须带顶层哈希的承重理由，不是装饰。闸重算聚合哈希，不一致即拒。**不新增排除谓词**，085/R4 已接受的 `evidence-is-caller-controlled` 残余不因本轮扩大。

### D3 — 覆盖必须精确：并集 = 变更集，两两不交

对每个分区计算 `git diff --name-only base -- <分区路径> <排除项>`：
- 空 → 拒（分区没覆盖任何变更）。
- 并集 ≠ 整条候选的变更文件集 → 拒，列出未覆盖文件。
- 两分区相交 → 拒，列出重叠文件（一个文件同时受两份 verdict 覆盖，哪份算数不可判）。
- 并集 ⊋ 变更集（`--paths` 收窄时分区伸到审阅范围之外）→ 拒，列出范围外文件（round 1 命中：只查缺不查多会让并集不等于候选却通过）。

「每一部分都在某个 packet 里，一个不落」（`code-review/SKILL.md:224`）由并集等式机械化；不交把它收紧成真正的分区。

### D4 — 每个分区各需一份 validator 接受的 closeout ledger

与今天的单 ledger 路径同一判据：`closeout_state` + `controller_receipts` 存在且 `validate_extraction_review_state.py` 接受，`candidate_sha256` 等于该分区哈希。收据本身不认证（既有边界），闸只证「落地的每一部分都是某轮外部评审冻结过的那一部分」。

### D5 — 顺序与失败文案

整条候选可冻结时先走既有单 ledger 路径（行为不变）；找不到再走清单。整条候选冻结失败（超 200KB）不再直接退出，记下错误继续找清单；两者都不成立时把冻结错误、每份清单的拒绝原因一起打出，并提示分区配方。`--print-candidate` 在冻结失败时保持既有报错。

### D6 — 渲染器把规范化放在一处

`--print-manifest --partition <paths…> [--partition …]` 由闸自己算 fork point、各分区哈希、聚合哈希并输出完整 JSON；分区不覆盖 / 重叠 / 为空时拒绝渲染。作者不手算聚合哈希，避免两份实现漂移（与 docstring 里「两份实现的哈希会漂移」同一理由）。

### D7 — 分区路径的卫生

清单里的路径必须是相对、无 `..`、不以 `:` 或 `-` 开头（不允许 pathspec magic，排除项由闸自己追加）、不含 glob/转义元字符 `* ? [ ] \`（git 对非 magic 路径同样按通配解释，评审 round 1/2 各自命中）、无控制字符、跨分区不重复。最多 64 个分区。

## Acceptance matrix（决策表：具名输入 → 单一裁决）

既有行不变（见 085 plan）。本轮新增：

| 输入 | 裁决 |
|---|---|
| 整条候选 > 200KB，无清单 | `refuse`，文案含冻结错误 + 分区配方提示（此前为 `error` 直接退出，语义同为拒） |
| 清单存在，各分区哈希复算一致、并集 = 变更集、两两不交、每分区有 validator 接受的 ledger | `pass`（**本轮新增的唯一 accept 路径**） |
| 清单某分区遗漏变更文件（并集 ⊂ 变更集） | `refuse: uncovered` |
| 清单两分区覆盖同一文件 | `refuse: overlap` |
| 清单某分区哈希与复算不符（候选在写清单后又动了） | `refuse: partition hash` |
| 清单某分区没有 validator 接受的 ledger | `refuse: no accepted ledger for partition` |
| 清单 `base` ≠ 闸算出的 fork point | `refuse: base` |
| 清单顶层聚合哈希不能复算 | `refuse: aggregate` |
| 清单路径含 pathspec magic / `..` / 绝对路径 | `refuse: partition path` |
| 整条候选 ≤ 200KB 且有单 ledger | `pass`（既有路径，不变） |
| `--print-manifest` 给出的分区不覆盖或重叠 | 渲染拒绝，非 0 退出 |
| `--print-manifest` 分区完整 | 输出 JSON，其 `candidate_sha256` 与闸复算一致，提交后即通过 |

## 差分证据（已执行，2026-09-02）

RED 基线：新用例落在旧代码上，18 条红、既有 35 条绿（`test_review_ledger_binding: 18 failing case(s)`）；实现后 54 条全绿。

突变走查（提交 `92d7bc4` 后就地突变、跑套件、`git checkout --` 复原，每次复原后 `git diff --quiet` 确认）：

| 突变 | 恰红的用例 |
|---|---|
| 并集等式改恒假 | 2 条：渲染拒绝未覆盖、清单遗漏 lane 被拒 |
| 不交检查改恒假 | 2 条：渲染拒绝重叠、清单重叠被拒 |
| 聚合哈希复算改恒假 | 1 条：聚合哈希伪造被拒 |
| base 等式改恒假 | 1 条：他 base 清单被拒 |
| 分区哈希复算改恒假 | 1 条：候选移动后清单被拒 |

每个突变只红自己归属的用例，其余不动。

真仓复现：对触发本轮的 623,458 字节候选（`6c14975b..origin/main`）跑 `--print-manifest`，六个分区全部可冻结、渲染成功（聚合 `45121cb24664…`）：references+SKILL.md / scripts（`skill-extraction-workflow` 单独已 222,995 字节，必须再切）/ 其余十个技能 / specs 两组 / 仓根与 `.github`。此前该候选只能拆 8 个 PR。

## 测试层决策表

| 层 | 处置 | 命令 | 理由 |
|---|---|---|---|
| unit / 脚本套件 | **add + run（RED 先行）** | `bash skills/skill-extraction-workflow/scripts/test_review_ledger_binding.sh` | 新 accept 路径每条拒绝分支各一用例 |
| integration | run | `make test`（`test-repo-gates` / `test-regressions-fast` / `test-code-review`） | 闸被 CI 与合成夹具调用 |
| CI-only lane | run | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | `make test` 不含它 |
| 泄漏 / 结构 | run | `python3 scripts/check-public-sanitization.py .`、`python3 scripts/check-spec-references.py` | 新增 specs 目录 + 改共享文档 |
| 真仓复现 | run | 在本 worktree 对 `6c14975b..origin/main` 的 623KB 候选跑 `--print-manifest`，证明分区可渲染 | 这是触发本轮的输入 |
| E2E / 渲染 | not applicable | — | `visible surface: no` |
| manual | not applicable | — | 无人工路径 |

## 风险路由记录（feature-risk-router）

- risk tags：`shared-gate`、`release-ops`（CI required check 的 accept 语义）。
- `security-review` change-triggered 臂：**security posture unchanged**——信任模型不变（evidence 仍是 caller-controlled，已接受残余），不新增信任边界或不可信输入 sink；对抗 challenge 仍需探 bypass。
- required gates：本计划工件；RED→GREEN 套件；`make test` + heavy lane；dual-track review（1 review + 1 challenge）绑定最终 diff 并产出 closeout ledger；CI 全绿；PR 停在待审，合并授权在用户手上。
- skippable：UI/渲染证据（无渲染面）。
- stop reasons：无（方案唯一且可逆）。

## 实施边界记录

- active baseline：本文件；scope 如上表。
- implementation-mechanics owner：`python-service-dev`（Python 脚本）+ `testing-strategy`（差分用例设计），会话内已加载。
- `multi-agent-delegation`：`local`——单文件脚本 + 单套件，无独立可并行切片。
- visible surface：no。
- test-case-first：分区用例先写先红，再实现。

## CLI 契约记录（terminal-cli-dev 轻量记录）

新增两个 flag：`--print-manifest`（渲染清单到 stdout，JSON，缩进 2）与 `--partition PATH [PATH…]`（可重复，仅随 `--print-manifest`）。约束：两者缺一即 argparse 报错退出 2；诊断一律 stderr，既有 `review_ledger_binding_ok / failed / error / no_change` token 不变；通过行报「as N partitions」并逐分区一行列出绑定它的 ledger。无交互、无颜色、无 TTY 依赖；`visible surface: no`（CI/作者侧工具，不面向产品用户）。

## 提炼 charter 与 owner map（skill-extraction-workflow 本轮记录）

| 字段 | 内容 |
|---|---|
| Task | 落地闸接受分区清单（capability 命名，无源项目名词） |
| Purpose | 防止「reviewer 输入上限变成 PR 上限」再迫使作者拆 PR；保留「落地的每一字节都被某轮外部评审冻结过」的不变量 |
| Scope | In：`skill-extraction-workflow`（binder 脚本、其套件、dual-track 与 quickstart 两份 reference、台账行）；`.github/workflows/ci.yml` 注释。Out：`code-review` 收据 schema 与 `MAX_PACKET_BYTES`；merge_group 多 PR 聚合 |
| Depth | tooling change + targeted reference refresh（重读了 binder、controller `freeze_packet`、validator 候选校验段、ci.yml、SKILL.md:221-224） |
| 结果分类 | failure/correction（可观测失败：0.11.0 晋升被迫拆 8 个 PR） |
| Evidence plan | 一手源＝仓内代码与 CI 注释 + 对触发候选的实测字节数；外部实践不适用（本仓自有闸的实现缺口，无 state-of-art 主张） |
| 完成标准 | 54 例绿 + 5 突变差分 + 真候选渲染 + 各 lane 绿 + dual-track 1+1 + closeout ledger 绑定本候选 |

RCA（widen 后再深入）：
1. 触发/设计：落地闸把候选身份定义为 packet 哈希——一个尺寸有界的对象——而 Git 候选无界；两个身份合一是主因（反事实：若身份是 base/tree 或分区聚合，8 次拆分不会发生）。
2. 缺失的机械控制：评审层 `code-review/SKILL.md:224` 早已允许分区，但落地层没有消费者；规则存在而无 firing path，是「规则存在但不触发」形态。
3. 检测缺口：binder 在 wave 5 才引入，首次遇到晋升级 diff 就是 0.11.0；之前 #99 晋升（51 文件）无闸故未暴露。
4. 潜在条件：`ci.yml` 注释把「聚合未解」写成一类，掩盖了「单候选过大」与「多 PR 合并队列」是两个不同聚合。
预防＝机械控制：binder 消费 manifest（本轮落地）+ 渲染器统一规范化 + 注释区分两类聚合。人为纪律（「下次别拆 PR」）不作为原因或预防。

Owner map（`owner | direction | status | reason`）：
- `skill-extraction-workflow` | 本体 | updated | 脚本、套件、两份 reference、台账行
- `code-review` | upstream（packet 分区规则的定义者） | unchanged | SKILL.md:223-224 已定义评审侧分区且措辞正确；落地侧配方放在 ledger 的 owner 文档，避免双 owner 行
- `product-rd-workflow` | upstream（shared-gate 分类） | unchanged | 本轮按其 shared-gate 分类走，规则无缺口
- `testing-strategy` | sibling（评审/测试层） | unchanged | 突变走查与精度行按其既有规则执行，无新规则
- `platform-release-engineering` | downstream（晋升/发布） | unchanged | 晋升配方不变，只是不再需要拆 wave；无技能文本需改
- `.github/workflows/ci.yml` | 非技能 | updated | 注释区分两类聚合

## 评审轮记录（dual-track，extraction lane 1+1，fix hold 到 challenge 之后）

- Round 1 review（codex，候选 `1fcd7cd4…`）：2 条 P2——分区路径未拒 glob 元字符；`--paths` 收窄时并集可超出变更集。
- Round 2 challenge（codex，同一候选，focus＝通过清单路径绕过接受）：1 条 P2，与 round 1 第一条同类（独立命中）。
- 处置：两类均 fixed（拒 `* ? [ ] \`；并集与变更集要求相等），各补用例并跑 RED 差分；修复批移动了候选，按规则欠一轮 succession challenge 绑定落地候选。

## Status-sync target

`skills/skill-extraction-workflow/references/source-register.md` 追加本轮行（append-only，作为最后一个 commit，firing-path 指向 `command:skills/skill-extraction-workflow/scripts/test_review_ledger_binding.sh`）。

## Review / challenge gate

`shared-gate` + `release-ops`。需要绑定最终 diff 的独立对抗评审（extraction lane：1 review + 1 challenge，fix 全部 hold 到 challenge 之后）；closeout ledger 绑定本轮自己的落地候选。合并授权在用户手上。
