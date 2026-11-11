# 步骤 2 验证记录

基线 `origin/main` 2126c9d。除特别说明外，命令都在候选工作树根目录执行。

## 零丢失

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 资料迁移 | `python3 specs/architecture-skill-consolidation/evidence/migrate_refs.py . origin/main verify` | `VERIFY_OK files=46`：3 个合并文件与脚本从两份旧文件重建的结果逐字节相同；30 个与旧文件逐字节相同；13 个只改了文件名引用或一句措辞 |
| 旧入口正文 | `python3 specs/architecture-skill-consolidation/evidence/entry_rules.py . origin/main verify` | `entry_rules verbatim=123 hand_merged=13 lost=0`，且规则文件与脚本生成结果相同 |
| 入口索引 | 比较 `references/` 的文件集与入口里出现的文件名 | 48 个文件全部在索引里，没有指向不存在文件的条目 |
| 合并文件的共享区域 | 各文件 `## Shared-region grep gate` 里的命令 | 三个文件均为零命中 |

脚本证明的是内容相同和没有块被丢。7 组手工合并是否保住两侧的意思是人工判断，逐组列在零丢失映射里。

## 先红后绿

| 改动 | 红 | 绿 |
| --- | --- | --- |
| 定位符解析闸支持"文件已迁移" | 先写 7 个新用例；在未改的闸上，套件停在第一个新用例（期望 rc=0，实际 rc=1） | `register_firing_path_resolution_tests_ok (66 assertions)` |
| 安装脚本迁出两个旧架构技能目录 | 先扩测试；在未改的脚本上，测试停在"原生目录下的旧 Go 架构技能目录应已不存在"这条断言 | `install_opencode_skill_migration_tests_ok` |
| 路由指针 | 用候选的套件跑基线树（`POINTER_ROOT=<origin/main 的导出>`）：15 条断言失败，即本轮新增的 10 条和改指新路径的 5 条 | 候选树 `routing_pointer_integrity_ok` |

迁移表的五个保护各有一条会红的用例：迁移后改写规则文字、新路径不存在、旧路径重新出现、表项无人引用、目标指向仓库外。

## 台账

`ruby skills/skill-extraction-workflow/scripts/register-firing-path-resolution.rb .` 输出 `register_firing_path_moved_paths_used: 12` 和 `register_firing_path_resolution_ok (671 locators resolved)`。

- 12 个指向旧技能文件的定位符经迁移表解析到新路径，锚点文字全部仍命中。
- 1 个指向已退役一致性闸脚本的定位符、3 个指向已改写的"Node 无架构同级入口"措辞的定位符，按已有机制登记豁免并各绑定原台账行的摘要；本轮追加的行指向新措辞。
- 路由存在性检查登记了 15 行历史台账行和 `platform-observability` 自己台账的 1 行（均按行摘要），md 引用检查登记了 4 条历史引用。路由漂移测试的"饱和"用例原本在注释里说按豁免表过滤、代码里没有实现，此前豁免的名字已不在台账中所以一直无害；本轮补上了按表过滤和逐项的前提断言。
- `specs/065-uiux-evidence-delivery` 的冻结义务台账有 1 行把旧 Python 架构入口当作承载文件；按 cff2e76、748037c 的先例把承载刷新为新入口 Routing 一节里的同一义务，重新生成可读索引，`test_obligation_ledger_repo_audit.sh` 通过。
- 本轮追加的台账行一度把 `source-register.md` 推到 1,053,439 字节，超过评审闸单个技能文件 1,048,576 字节的上限，任何涉及 `skill-extraction-workflow` 的评审都无法启动。已把本轮行压缩，现为 1,046,980 字节，余量约 1.6 KB。这是需要单独决定的问题：再有一两轮正常追加就会触顶。

## 路由

静态分析 `ruby skills/skill-extraction-workflow/scripts/eval-routing.rb .`：`blocking: none`，`advisory (0)`。

题库结构 `bash skills/skill-extraction-workflow/scripts/test_routing_bank_integrity.sh`：`routing_bank_integrity_ok rows=163`。

受影响用例的路由实测见下节。

## 路由实测

`eval-routing-bank.rb --model sonnet --replicas 10`，基线树 `origin/main` 2126c9d 只跑受影响的 15 题，候选另加 4 道新题。判定取保守共识：10 次里任一次选错即 FAIL。默认的 haiku 档只作筛查，这里的结论以 sonnet 档为准。

| 用例 | 基线预期 | 基线结果（10 次选择分布） | 候选预期 | 候选结果（10 次选择分布） |
| --- | --- | --- | --- | --- |
| `new-arch-vs-dev` | `go-microservice-architecture` | PASS：go-microservice-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `new-py-arch` | `python-service-architecture` | PASS：python-service-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `new-go-dev` | `go-microservice-dev` | PASS：go-microservice-dev 10 | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `p-go-scale` | `go-microservice-architecture` | PASS：go-microservice-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `p-go-errgroup` | `go-microservice-dev` | PASS：go-microservice-dev 10 | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `miss-refactor-python-unqualified` | `python-service-architecture` | FAIL：python-service-architecture 8、python-service-dev 2 | `software-architecture` | PASS：software-architecture 10 |
| `route-python-multitenant-arch` | `python-service-architecture` | PASS：python-service-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `route-python-eventdriven-arch` | `python-service-architecture` | PASS：python-service-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `route-python-dataplatform-arch` | `python-service-architecture` | PASS：python-service-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `route-go-multitenant-arch` | `go-microservice-architecture` | PASS：go-microservice-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `route-go-eventdriven-arch` | `go-microservice-architecture` | PASS：go-microservice-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `route-go-dataplatform-arch` | `go-microservice-architecture` | PASS：go-microservice-architecture 10 | `software-architecture` | PASS：software-architecture 10 |
| `gap-rust-service` | `product-rd-workflow` | FAIL：go-microservice-dev 8、product-rd-workflow 1、none 1 | `product-rd-workflow` | FAIL：go-microservice-dev 6、none 4 |
| `route-nodejs-multistage-to-product-rd` | `product-rd-workflow` | FAIL：product-rd-workflow 8、nodejs-service-dev 2 | `product-rd-workflow` | PASS：product-rd-workflow 10 |
| `route-nodejs-architecture-not-go-python` | `product-rd-workflow` | FAIL：nodejs-service-dev 4、product-rd-workflow 3、none 3 | `software-architecture` | PASS：software-architecture 10 |
| `route-cross-stack-domain-model` | — | 新题 | `software-architecture` | PASS：software-architecture 10 |
| `route-typescript-service-architecture` | — | 新题 | `software-architecture` | PASS：software-architecture 10 |
| `route-local-dto-field-not-architecture` | — | 新题 | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `route-add-trace-existing-path-not-architecture` | — | 新题 | `platform-observability` | PASS：platform-observability 10 |

14 道共同用例里，基线失败 4 道，候选失败 1 道（`gap-rust-service`，基线也失败，且候选的错选更多落到 `none`）；没有一道在候选上退化。新增 4 道题全部通过，其中两道是"不该进入架构技能"的反例。

这组数据是在候选提交较早的版本上测的；此后改过的路由面只有 `product-rd-workflow` 描述里一个词（"无对应栈 owner"→"无栈 owner"）和 `python-service-dev`、`go-microservice-dev` 正文里一条指针的措辞。改动之后在 e1f7eca 上全部 19 题按同样设置复测；e1f7eca 之后没有任何 `SKILL.md`、题库或 `agent-context/` 文件再变动，这次复测即代表最终提交的路由面。`error` 是评分调用自身失败，不计为选错。

| 用例 | 预期 | 结果（选择分布，含评分错误） |
| --- | --- | --- |
| `new-arch-vs-dev` | `software-architecture` | PASS：software-architecture 10 |
| `new-py-arch` | `software-architecture` | PASS：software-architecture 10 |
| `new-go-dev` | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `p-go-scale` | `software-architecture` | PASS：software-architecture 10 |
| `p-go-errgroup` | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `miss-refactor-python-unqualified` | `software-architecture` | FAIL：software-architecture 7、python-service-dev 3 |
| `route-python-multitenant-arch` | `software-architecture` | PASS：software-architecture 10 |
| `route-python-eventdriven-arch` | `software-architecture` | PASS：software-architecture 10 |
| `route-python-dataplatform-arch` | `software-architecture` | PASS：software-architecture 10 |
| `route-go-multitenant-arch` | `software-architecture` | PASS：software-architecture 10 |
| `route-go-eventdriven-arch` | `software-architecture` | PASS：software-architecture 10 |
| `route-go-dataplatform-arch` | `software-architecture` | PASS：software-architecture 10 |
| `gap-rust-service` | `product-rd-workflow` | FAIL：go-microservice-dev 7、software-architecture 3 |
| `route-nodejs-multistage-to-product-rd` | `product-rd-workflow` | PASS：product-rd-workflow 9、error 1 |
| `route-nodejs-architecture-not-go-python` | `software-architecture` | PASS：software-architecture 8、error 2 |
| `route-cross-stack-domain-model` | `software-architecture` | PASS：software-architecture 10 |
| `route-typescript-service-architecture` | `software-architecture` | PASS：software-architecture 10 |
| `route-local-dto-field-not-architecture` | `go-microservice-dev` | PASS：go-microservice-dev 10 |
| `route-add-trace-existing-path-not-architecture` | `platform-observability` | PASS：platform-observability 10 |

复测里失败 2 道。`gap-rust-service` 在基线和前一次候选上同样失败。`miss-refactor-python-unqualified`（"重构这个 Python 用户服务"，没说是局部还是整体）在前一次候选上 10/10，这次 7/3，有 3 次选了 `python-service-dev`；基线上同题是 8/2，也失败。这道题本身有歧义，两次结果的差别在采样波动范围内，不判为退化；如果后续想压到 10/10，属于步骤 3a 行为评测要看的路由边界。

## 仓库通道

以下结果对应候选提交 `318237e`，也就是本记录所在提交的父提交。

本地先在 `9cc1a4a` 上跑过一轮：`test-code-review` 有 3 个 Kimi 计时用例失败（诊断和修复见 `review-dispositions.md` 的"9cc1a4a 本地通道暴露的第四处计时失败"），其余 4 条通道都通过。修复并入候选后，全部通道在 `318237e` 上重跑，负载约 17–35：

| 通道 | 命令 | rc | 关键结论行 |
| --- | --- | --- | --- |
| repository-gates | `make test-repo-gates` | 0 | `ccl_skill_check_clean_ok`，`r0_status=private-ok` |
| regression-fast | `make test-regressions-fast` | 0 | `regression_fast_lane_ok: 45 suites, jobs=8` |
| code-review 分片 | `make test-code-review` | 2 | `code_review_shard_1_ok: 10 suites`，`code_review_shard_2_ok: 8 suites`；修过的 Kimi 用例全部通过。失败的是 abort-leak 第 1 段，见下文 |
| code-review abort-leak | 在 PID 命名空间里跑 `make test-code-review-abort-leak-1`、`make test-code-review-abort-leak-2` | 0、0 | `review_gate_abort_leak_ok leg=1 client=claude`、`leg=2 client=fallback`、`leg=2 client=claude` |
| regression-heavy | `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | 0 | `regression_heavy_lane_ok: 9 suites, jobs=8` |
| 公开脱敏 | `python3 scripts/check-public-sanitization.py .` | 0 | `public_sanitization_ok` |

`make test-code-review` 的 rc=2 来自 abort-leak 第 1 段，失败输出是 `could not build the scenario in 3 attempts`（`wrapper ... was never reparented`）。这一段要求被弃置的 wrapper 由 1 号进程收养（ppid=1）。本机的会话跑在 `systemd --user` 下，它是 child subreaper，孤儿进程会被它收养：实测一个孤儿进程的 ppid 是它的 pid，不是 1。所以这一步无论代码对错都建不起来；`make` 在第一处错误处停下，第 2 段这次也没跑到。对照：同一检出、同一环境，只换掉收养者，用 `unshare --user --map-current-user --pid --fork --mount-proc` 让命名空间里的 1 号进程收养孤儿，这时三段全部通过。这个套件和被测的 `review_gate` 都与 `origin/main` 相同；CI 的 runner 由 1 号进程收养孤儿，`main` 最近 3 次 CI 都是绿的。

PR 侧检查：先 fetch `origin/main`（`2126c9d`），再运行 `check_review_evidence_present.py --base "$(git merge-base origin/main HEAD)"`，结果为 `review_evidence_present_ok: 18 review, 6 challenge`。
