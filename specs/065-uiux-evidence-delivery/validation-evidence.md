# 065 — 可复算验证证据

本页记录仓内可重放验证，以及不入仓的私有 held-out 行为测评结论与证据边界。理论来源核查见
`skills/product-ui-ux-design/references/external-ui-ux-quality-benchmarks.md`；逐义务迁移见
`obligation-preservation.md`。本页不嵌入会造成自指漂移的 dirty-tree 摘要；所有改动冻结后，完成报告用 changed-file path + SHA-256 的 canonical manifest 绑定最终候选，不能用分支名代替内容绑定。

## 基线绑定

- 变更基线：`origin/dev@e322db47abe5736e6e1fdf0e73e2ed3eb32c006b`。
- 基线语料由 `git archive origin/dev` 导出；运行的是候选中的同一聚焦 oracle，`UIUX_CONTRACT_ROOT` 指向导出的未改语料。
- 该差分只证明候选 oracle 能区分旧语料与新契约，不证明真实产品设计质量或运行时结果。

## RED → GREEN

基线重放命令：

```bash
tmp_dir=$(mktemp -d /private/tmp/uiux-red.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
git archive origin/dev | tar -x -C "$tmp_dir"
UIUX_CONTRACT_ROOT="$tmp_dir" \
  bash skills/skill-extraction-workflow/scripts/test_uiux_delivery_contract.sh
```

结果：退出 `1`，共 `242` 条 `FAIL:`。失败覆盖 canonical contract、设计/测试/客户端/生产者双向指针、完整与轻量路径、authoritative consumer universe、阶段顺序、不可变候选绑定、终态矩阵、理论边界、既有义务和已退休阈值。聚焦 oracle 在缺少新契约的基线上受控退出，不以 shell 崩溃冒充 RED。

候选命令：

```bash
bash skills/skill-extraction-workflow/scripts/test_uiux_delivery_contract.sh
```

当前结果：退出 `0`，输出 `uiux_delivery_contract_ok`。该脚本还内置四项 killing mutation：交换 Test selection / Client execution 阶段、把 Web 客户端的正向 `Return` 改为否定、把已知受影响 consumer 错分为 `unknown-consumers`，以及把未知 consumer 缺口错误升级为 `accepted + complete`；四者都必须被 oracle 拒绝。

## 历史 locator waiver 反例

`register-firing-path-resolution.rb` 只允许三条已退休、且绑定 source-register 行摘要的历史 locator。验证必须同时杀死两种绕过：

1. 删除真实被豁免的 source-register 行，解析必须报告缺行并非 clean。
2. 保留相同 locator 但改写该行，摘要不匹配，解析必须报告 digest mismatch 并非 clean。

对应测试：

```bash
bash skills/skill-extraction-workflow/scripts/test_register_firing_path_wiring.sh
```

## Kimi / Codex 行为与效果对照

私有 held-out 任务库 SHA-256 为
`5256a0ec42952ad65abaabacd76e1ee8774d3f0df9de7427914ded9122989fb6`。任务、原始答案和盲化映射不入仓。

跨 owner 组的模型调用绑定当时 61 个变更文件的候选 manifest
`f51d173383b3476441d82830724104ea20860cb9141d911d7bd4f312038bc0fc`。调用后发生的校正都不进入七个模型 task bundle：本页结果回填、契约测试脚本清除尾随空白、source-register firing path 绑定到各 owner 本轮新增规则、推理 owner 把既有 UI/UX handoff 改成显式 `must`，以及托管 CI 暴露后的 routing-bank 共享门禁修复与回归测试。最终证据回填前冻结 63 个变更文件的 manifest
`e91302be030c19d780362474e4d5efa478438d87f089bf742c1d0b0887dac342`；此后只改本页。14 个基线/候选 task bundle hash 逐一复算不变，仍与生成协议一致。因此模型结果直接绑定最终 task 输入，但不评测这些 bundle 外校正本身。行为 manifest 为
`e45ade7c3d55f2c96b105738230e1042434bbf91b362eb016ea30670ea8c6f65`，Kimi 生成协议为
`9be47a8325e5442278787d4870a569ce8f918a908ef5113f84e98f07ebbbc96b`，Codex 盲评协议为
`6c7165597d5f4ebb0fad6a548b9e305b15e9fd0f997018060aaef450be64d430`。

- 生成：3 个独立盲化轮次；每轮 7 个任务、基线/候选各 1 次，共 42 次 Kimi `kimi-code/k3` 调用。三份报告均为 `completed`。
- 质量原始汇总：Codex `gpt-5.5` 独立盲评 21 对答案，`semantic_self_judging=false`。候选胜 `17`，基线胜 `4`，无平局或无效结果；7 类任务都以 `2/3` 或 `3/3` 多数选择候选。逐 criterion 原始方向中，`workflow_correctness` 为 `19:2`，`owner_and_scope_coverage` 为 `19:1:1`，`completion_truthfulness` 为 `12:3:6`（候选:基线:平局）。
- 盲评位置偏差：候选位于 A 时为 `5:4`，位于 B 时为 `12:0`；Codex 总体选择 B 为 `16/21`。因此 `17:4` 只能作为有利的 advisory 信号，不能解释成无偏的 `81%` 胜率或精确效果量。消除该混杂需要把同一 21 对答案交换 A/B 后复判，并只保留顺序一致的结论。
- 上下文与答案：候选提示字节 `+0.3%`，答案字节 `-10.1%`。
- 耗时：21 个候选/基线配对比的中位数为 `0.928`，即候选 `-7.2%`；25%/75% 分位为 `0.706/1.296`，候选在 `8/21` 对中更慢。总时长为基线 `1511.656s`、候选 `1587.339s`，候选 `+5.0%`。

| 跨 owner 任务 | 轮次 1 | 轮次 2 | 轮次 3 | 配对比中位数 |
| --- | ---: | ---: | ---: | ---: |
| 复合原生/嵌入宿主 | `0.646` | `1.515` | `0.706` | `0.706` |
| 文案/布局/无障碍 | `2.093` | `0.885` | `2.497` | `2.093` |
| 多层可见状态 | `0.575` | `0.948` | `0.900` | `0.900` |
| 普通 CLI 可见状态 | `0.659` | `0.883` | `1.098` | `0.883` |
| 修复已知拒绝 | `0.807` | `1.442` | `1.000` | `1.000` |
| 只有静态产物、未执行 | `1.146` | `1.296` | `3.190` | `1.296` |
| 未知后端消费者 | `0.928` | `0.452` | `0.584` | `0.584` |

配对比小于 `1` 表示候选更快。四分位距 1.5 倍规则标记两次候选慢请求：文案/布局/无障碍轮次 3 为 `2.497`，静态产物轮次 3 为 `3.190`；保留两者时总时长为 `+5.0%`，敏感性分析排除两者后为 `-7.1%`。因此 near-final 组的 `+52.3%` 没有复现，也不能据本轮反向声称稳定提速。可支持的结论是：答案更短，质量方向有利但幅度受 A/B 位置偏差混杂，端到端耗时仍有明显方差。

设计质量组没有重新调用模型，仍只提供 near-final 的相邻候选信号：4 对答案中候选胜 `3`、基线胜 `1`。该组不绑定上述被测候选 manifest。

### 路由面测评

私有 12 题 routing bank 的 SHA-256 为 `999e99fdd0077d06e33c8ca22265b4e05b9783b577e660c6a1b61bd45215e29f`，grader 为 `claude-haiku-4-5`。

- 基线与候选各完成 10 轮有效观测；两侧每轮均为 `11/12`，合计均为 `110/120`，`error=0`、`frozen_drift=0`，没有 `newly_failed` 或 `newly_passed`。
- 唯一稳定不一致项要求把纯 CLI 用户体验设计路由到 `product-ui-ux-design`，但基线与候选均在 `10/10` 轮选择 `terminal-cli-dev`。该单 owner 期望既不能表达设计判断与终端机制的组合，又与已提交的普通 CLI 契约用例冲突。
- 结论：本轮没有测到路由提升，也没有新增路由回归。Codex 独立复核把该项判为 benchmark 歧义而非候选回归；该意见只作辅助。剩余风险是 terminal-only 路由可能漏掉设计意图、验收条件和最终设计裁决；后续应让 grader 表达主/协同 owner，或收窄这条任务的措辞。

原始 20 份报告、冻结 bank 和独立复核记录保存在维护者工作区 `.work/evals/uiux-exact-final-20260829/routing/`，不写入共享仓库。

### 共享 routing-bank 门禁

托管 CI 最初报告 `impact_chain_bank_evidence_missing`，点名已经有 owner-scoped bank locator 的 `terminal-cli-dev/SKILL.md`。调用链核对发现 bank 义务覆盖所有 skill description，但 owner 行索引只覆盖 impact-chain 的可选 owner；同时，单独修改非可选 owner description 且不写台账时，外层入口不会执行。

- 修复前可证伪基线：A20（唯一有效证据）实际退出 `1`、期望 `0`；A21（零台账行）实际退出 `0`、期望 `1`。
- 修复后：self-adjudication A1–A23 全部通过。A20/A21 关闭上述两个方向，A22 拒绝一行替两个 owner 清偿，A23 证明过期或拼错的精确 owner 路径先由 `impact_chain_evidence_missing_file` 拒绝。
- mutation：把唯一性条件从 `candidate_names == [owner]` 放宽为 `candidate_names.include?(owner)` 时，A22 单独转红；恢复后文件 SHA-256 回到 `f88bb0695672a31221bc08a7e4242d301038cbf3dcb211533a03c5589e9e7478`，聚焦 suite 重新通过。
- 兼容性：round-attribution 包含非可选 owner body-only 的 Leg M 并通过；64 点 verdict differential 只有 4 个已登记历史差异，没有新增 verdict 变化；reference-script suite 通过。
- 对抗评审：Kimi 登录与短调用正常，但 42,594-byte 和 10,508-byte 两份正式 packet 均以结构化 `timeout` 结束，所以不计通过。Codex fallback 首轮提出两个假设；A23 与逐轮调用链分别证明它们会在 bank 解析前 fail closed、不可复现。绑定最终 gate/test diff 的复评结果为 `passed`、findings 为空，结果文件 SHA-256 为 `f40136f61050a5ca2a33f28af899b9926c68ae8fd1021d70caeddc284b02e58a`。它仍是 OpenAI 同族复评，且只读沙箱不能创建测试 fixture；因此独立性与测试执行分别由残余风险和本地真实 suite 结果表达，不把模型结论当成测试通过。

## 完成前验证矩阵

| 层级 | 命令 | 最终结果 |
| --- | --- | --- |
| 聚焦契约 | `bash skills/skill-extraction-workflow/scripts/test_uiux_delivery_contract.sh` | 退出 `0`，`uiux_delivery_contract_ok` |
| 加载预算 | `bash skills/skill-extraction-workflow/scripts/test_uiux_loading_budget.sh` | 退出 `0`；常规直达 `58,860 B`，旧默认 `65,400 B`；专用组合 `70,655 B` |
| 义务闭合 | `obligation-ledger.py audit ...`、`test_obligation_ledger.sh` | `1240` 行，`unresolved=0`；聚焦测试退出 `0` |
| 台账生命周期 | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_source_register_lifecycle.sh` | 在 heavy lane 两次运行均通过 |
| locator 解析/接线 | `test_register_firing_path_resolution.sh`、`test_register_firing_path_wiring.sh` | 分别在 fast/heavy lane 通过 |
| 交叉引用/runner | `test_validate_skill_cross_refs.sh`、`test_regression_runner_lanes.sh` | `make test` 内通过 |
| routing-bank 共享门禁 | `test_impact_chain_self_adjudication.sh`、`test_impact_chain_round_attribution.sh`、`test_impact_chain_gate_verdict_differential.sh`、`test_check_ccl_impact_chain_refscripts.sh` | 全部退出 `0`；self-adjudication A1–A23 通过，differential 64 点无意外变化 |
| 快速门 | `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`、`git diff --check` | 均退出 `0` |
| 本地全量 | `uv run --with pyyaml --with pytest make test` | 退出 `0`；裸 `make test` 的首次失败是本机缺少 `PyYAML`/`pytest`，不是候选失败 |
| 重型回归 | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | 最终候选退出 `0`，8 个 suite 全部通过；早期候选曾在并行负载下两次只点名 differential，而该 suite 单跑通过，最终串行独占资源后未复现 |
| 公开内容 | `python3 scripts/check-public-sanitization.py .` | 退出 `0`，`public_sanitization_ok` |

> 复核补记：上表义务闭合行在生成后曾失真——分支上两条 carrier 因后续语义修订（`skills/llm-inference-integration/SKILL.md` 插入 `you must`）漂移，`audit` 以 `CARRIER_COMPOSITE_NOT_UNIQUE … count=0` 退出 1。评审修复轮更新 mapping 两行并重渲 ledger 后重跑：`audit_ok domain=50 rows=1240 unresolved=0`。该失真类已接入 CI：`test_obligation_ledger_repo_audit.sh`（heavy lane，CI `--full` 强制）按 ledger header 钉住的 base SHA 复跑真仓 audit，后续 carrier 语义漂移会在 CI 转红而非静默过闸。

## 证据边界

- 最新客户端参考只提供静态源码、测试文件和 CI wiring 的存在证据；未取得本轮真实渲染、设备运行、测试执行或线上指标。
- 上下文尺寸差分可以由字节数复算。Kimi/Codex 对照只支持本任务库上的答案质量信号；耗时方向随任务和轮次变化，不能外推为稳定模型延迟、人工介入或真实设计效果改善。
- 本地通过不等于托管 CI 通过；未运行的面必须在最终报告显式列出。
