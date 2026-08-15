# 020 — bank/runner co-change 轮：4 项 routed 提案打包落地

**Shared-gate 分类**：runner 变更 = `gate implementation`（测量机件自识别，不改判分语义）；bank 变更 = 冻结测量语料变更（本轮为 bank 轮，co-change 纪律的对偶面：**零 description 变更**）。风险 tags：`shared-gate`；security-review not-applicable（security posture unchanged）。维护者接受依据：用户工单「下一 bank/runner 轮（4 项 routed 提案打包）」即对台账四项 routed 提案的接受。

## Extraction charter

| Field | Answer |
| --- | --- |
| Purpose | 防止 (1) 轮工件与被评措辞的归属继续依赖 operator/sidecar 外部断言——oncall r1 challenge (b) 与 r3 challenge 两 lane 两次命中「逐轮 JSON 应内嵌被评 description SHA，否则错措辞跑出的工件可冒充证据」；(2) 三个已实测路由边界（oncall 混合句、opencode 组合意图、p3 复合哨兵）无冻结回归看护，后续 description 变更悄悄回归无人发现。 |
| Scope | in：`skills/skill-extraction-workflow/scripts/eval-routing-bank.rb`（report 增 `routing_surface` 自识别块）及其 stub 测试；`eval/routing-tasks.jsonl`（+6 冻结用例、p3 行 +stability 标注）；新证据目录 `eval/evidence/routing-bank-round-2026-08-14/`；台账落地记录；register 行。out：任何 SKILL.md description（本轮零措辞变更）；`references/eval-routing.md` 测量纪律文本（执行不改规则）。watermark：not-applicable。 |
| Depth | Generator/tooling change + 冻结语料变更。 |
| Root cause | 各前轮的 co-change 纪律（bank 与 description 不同轮）把这些变更全部 routed 至本轮；runner 不自识别被评面是 sidecar 绑定机制诞生前的设计残余。 |
| RCA analysis | widen：(i) 轮工件不自识别→归属靠外部断言（两 lane 各两次独立命中，反事实成立：内嵌后逐轮工件机器可验）；(ii) 已测边界不进冻结 bank→无回归看护（反事实成立：入库后 dashboard 每轮看护）；(iii) p3 复合哨兵的 ~20-40% 翻转会被误读为新回归（标注防）。防止机制：runner 内嵌 + 冻结用例 + 机器可读哨兵标注。 |
| Failure mode analysis | runner 改坏会污染全 bank 测量（stub 确定性测试防）；晋升用例若不用实测原句会引入未测噪声（逐字晋升 + 入库后绑定轮复测防）；p3 标注若进 runner 判分逻辑会变测量语义（标注为纯 data 注释，runner 不消费，AGENTS 契约写明）。 |
| Lifecycle impact | implementation（runner+bank）、testing（stub 测试+绑定轮）、iteration feedback（台账）、onboarding（证据目录契约）。product/design/launch：not-applicable。 |
| Evidence plan | produced artifacts：not-applicable（非复盘轮）。inspected：runner 全文 367 行、绑定 wrapper `surface_hash` 语义、bank 格式与 130 用例 id 集、`eval/AGENTS.md` 与 f4c1164 证据目录契约、台账四项 routed 提案原文、两个来源证据目录的逐字原句与其测量出处（oncall `bank-variants.jsonl` 混合句 3/3；opencode `bank-probe.jsonl` 挑战者句 5/5、`bank-variants.jsonl` 四负例各 3/3）。external：not-applicable（内部测量机制）。 |
| Completion standard | stub 测试差分 RED→GREEN（无 `routing_surface` 块的 runner 使断言失败）；6 条晋升用例入库后绑定轮 ≥3 轮全过（binding_valid=true sidecar）；全 bank 1 轮绑定跑完成、无 grader-infra 失败、newly_failed 逐条核对（随机采样容差按 n=1 只作 smoke 不作回归判决）；checker clean；dual-track 无未处置 P0/P1；台账落地记录 + register 行。 |

## 四项提案的落地形态

1. **Runner 自识别（提案①，两 lane 背书）**：`--json` report 增 `routing_surface` 块：`descriptions_sha256`（与绑定 wrapper `surface_hash` 同义：全部 `skills/*/SKILL.md` description 行，dir-name-tagged、sorted glob 序 + bank 文件字节）、`per_skill_description_line_sha256` 映射（32 skill 逐行）、`catalog_sha256`（实际被评 catalog 文本，含 desc-budget 截断后形态）、`bank_sha256`、`bootstrap_layer_sha256`（--with-bootstrap 时）。逐轮工件从此自证被评面；sidecar 独立重算同量即外部校验。判分逻辑零变更。
2. **oncall 混合句晋升（提案②）**：`variant-neg-release-watch-sop` 逐字入冻结 bank（→`platform-release-engineering`，must_not `platform-observability`；实测 3/3 post-carve-out）。
3. **p3 哨兵处置（提案③）**：**保留 + 机器可读标注**，措辞再平衡**驳回**——题面即探针实质，改措辞使其通过属 Goodhart；词面锚机制已被同 token 兄弟例 15/15 证伪（台账 p3 节）。p3 行加 `stability` 注释字段（runner 不消费）。 |
4. **opencode 组合意图碰撞晋升（提案④）**：`probe-combined-impl-intent`（5/5）+ 四负例 `var-neg-opencode-review`/`var-neg-tui-commands`/`var-neg-worktree-first`/`var-neg-product-shortcut-feature`（各 3/3）逐字入冻结 bank。

新用例 `frozen_at_sha` = 本轮 fork 点 `d63ac44bd37b9375309515c8ff62bc91d3f78072`（HEAD 祖先，integrity test 可验）；utterance/expected/must_not 与测量原件逐字节一致（判分面不动），source 字段记测量出处。

## 验收判定表

| # | 检查（输入 → 判定） | 断言 |
| --- | --- | --- |
| 1 | stub runner（无 routing_surface 的旧 runner）跑新测试 | **fail**（差分 RED） |
| 2 | 新 runner + stub grader，--json 输出 | routing_surface 全字段在、sha 与测试独立重算一致、per-skill 映射覆盖全部 catalog skill；desc-budget 臂 catalog_sha256 变而 descriptions_sha256 不变 |
| 3 | 判分语义 | 与旧 runner 在同一 stub 输入上 results/pass/fail 完全一致 |
| 4 | 6 条晋升用例绑定轮 ×3 | 18/18 PASS，sidecar binding_valid 全 true |
| 5 | 全 bank 绑定轮 ×1（136 用例） | 完成、无全量 grader-infra 失败；newly_failed 与 124/130 已知失败集逐条对照（n=1 只作 smoke） |
| 6 | 本轮 diff vs fork 点 | 零 SKILL.md description 变更（`git diff d63ac44..HEAD -- 'skills/*/SKILL.md'` 空）；runner co-change 警告若现，属 dev-vs-main 历史差异，非本轮 co-change |

## Target-output map

| owner | direction | status | changed-file-or-reason |
| --- | --- | --- | --- |
| skill-extraction-workflow | self（runner owner） | updated | `scripts/eval-routing-bank.rb` + 新 stub 测试 |
| eval 测量语料 | corpus | updated | `eval/routing-tasks.jsonl` +6 用例 + p3 标注；新证据目录 |
| source-register | ledger | updated | impact-chain 行（scripts 变更） |
| skill-taxonomy-optimization-plan | status doc | updated | 本轮落地记录 + 四项 routed 提案结清 |
| testing-strategy | sibling | unchanged | stub 测试沿用既有 diagnostics harness 惯例 |
| platform-release-engineering / platform-observability / code-review / terminal-cli-dev / worktree-isolation / product-rd-workflow | routing owners | unchanged | 零 description 变更；新用例仅看护其已实测边界 |
| 其余 lifecycle stage | — | not-applicable | 无产品/设计/发布面 |

## 评审门与状态同步

- dual-track（codex 双 lane），本轮自主预算独立计（initial review + ≤4 challenges）；无未处置 P0/P1 方可合 dev。
- **链记录**：chain `bank-runner-round-r1`（candidate `2abc0523…`，codex 双 lane，`.review-evidence/bank-runner-round-r1/`）：双 lane 各 1×P1 **同类收敛**——多行 YAML description 续行编辑逃过 raw 首行 hash 绑定（runner 与 wrapper 同盲区互证假绿；catalog_sha256 含真相但无人校验）。**均 accepted 修复**：wrapper 独立重算被评 catalog hash 三向校验、runner 测试多行差分 fixture、stub 回归扩 7 case；全部测量轮在终稿 wrapper 下重生成（一修前轮次删除，MANIFEST provenance_correction 记载）。终稿数字：新用例 18/18；全 bank 133/136（3 失败全部有处置，见 MANIFEST）。候选变更 → 换链 `bank-runner-round-r2` 终审。chain `bank-runner-round-r2`（candidate `20f9786c…`）：review passed 零发现；challenge 2×P1 均 accepted 修复——wrapper 结果完备性强校验（id 严格相等 + 总数自洽 + 10-case stub 回归）；superseded 一修前工件恢复入树。预算 4/5 轮用尽后**维护者批加时（工单回复「跑」）**，因 276KB 整包超 200KB 上限按 oncall 先例分区双链：chain `bank-runner-round-h1a`（决策面，candidate `ccfb1286…`）review 1×P1（runner 双读 bank TOCTOU→单快照读）、challenge 2×P1（wrapper rerun 先 mv 后验可毁不可变工件→前置拒绝+全验后落盘；逐字主张不可复算→`test-promoted-case-provenance.sh` 入树 ALL VERBATIM）；chain `bank-runner-round-h1b`（数据工件，candidate `15115013…`）双 lane 同类收敛 1×P1（现行 sidecar 缺 `results_match_bank` 腿→终稿 wrapper 第三次权威重生成，18/18 + 133/136，四腿全 true；第二代移入 `superseded-pre-idscheck-wrapper/`）。全部发现 accepted+修复；止点：加时增量不另开轮，随合并暴露。各链无未处置 P0/P1。
- status-sync：台账「下一轮的新靶子」区与四项 routed 提案原文位置随本轮结清；register 行为机械闸输入。
- 测试层决策表：unit/stub=add+run（确定性）；bank 绑定轮=run（live 模型，证据进树）；E2E/host smoke=not-applicable；manual=not-applicable。
