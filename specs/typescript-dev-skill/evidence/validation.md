# 评审与验证记录

## 路由 RED → GREEN

- 命令：`ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb . --bank <十条 route-typescript-* 行> --model claude-haiku-4-5 --replicas 10 --json <报告>`，每条 10 个副本，达到行动分辨率下限。
- RED：改动前的技能树（`origin/main` e0a0568 的技能目录），报告 `routing-red.json`，逐条摘要 `routing-summary.txt`。4/10 通过，6 失败；clarify 8/100，低置信 8/100，副本 top1 一致 7/10。
  - 六条正例全部失败：库发布被 `nodejs-service-dev` 吸走；bundler tsconfig 与 Deno 类型设计判为无负责技能；monorepo 项目引用、外部输入边界、strict 迁移在 `nodejs-service-dev`、`product-rd-workflow`、`requirement-scope` 和无负责技能之间分裂。
  - 四条边界例（Node 服务、React 组件、CI 类型错误定位、测试分层）通过。
- GREEN：改动后的技能树，报告 `routing-green.json`。10/10 通过；clarify 0/100，低置信 0/100，副本 top1 一致 10/10。
- F41–F44 行为任务只冻结了任务与评分标准，本轮没有运行，结论类别仍是证据不足。

## `tc.ts` 严格配置编译

- 环境：typescript 6.0.3、`@types/node` 24、`"type": "module"` 的临时目录。
- RED（`tc-red.txt`）：基线 `tc.ts` 在 `--strict --noUncheckedIndexedAccess --exactOptionalPropertyTypes --verbatimModuleSyntax --module nodenext --moduleResolution nodenext` 下 exit 2，第 108 行 TS18048 两处、TS2322 一处。
- GREEN（`tc-green.txt`）：修复后同一配置 exit 0；`--module esnext --moduleResolution bundler --erasableSyntaxOnly` 下 exit 0。
- 运行时行为：捕获组 `([^():\s]+…)` 至少匹配一个字符，匹配成功时 `f` 一定是非空字符串，与原代码同路径。

## 确定性检查

- `check-ccl-skills.sh`（设置 `ALIAS_AUDIT_CMD` 跑私有别名审计，结论行见 `check-ccl-skills.txt`）：`ccl_skill_check_clean_ok`，`r0_status=private-ok`；`eval_routing_ok`，阻断项无；入口字数与字节预算、reference 行数预算通过；七个变更的决策负责技能的 impact-chain 行全部解析。
- `make test-repo-gates`（测试依赖装在虚拟环境里）：在 f21b487 上 exit 0。首次运行因本机缺 pytest 在最后一步失败，属环境问题，装依赖后重跑通过。
- CI 独有的 `check-public-sanitization.py`、`check-markdown-links.py`、`check-spec-references.py`、`check-skill-count.py` 及其回归测试：通过。

## Review pass

- Reviewed commit: 6b26a18（相对 `origin/main` 的整条分支；推送前已与修复合成一个提交）
- Reviewer: codex（`extraction_review_gate.sh --mode review`），结果 `review-R1.json`
- Findings: 4 total (0 P0 / 0 P1 / 4 P2)
- Dispositions:
  - P2 `type-design-and-boundaries.md`：Vitest 不开 `--typecheck` 不检查 `*.test-d.ts`。按 Vitest 文档核实属实（"To enable typechecking, just add `--typecheck` flag"）。fixed：写明开启方式、用一条故意写错的断言确认命令会失败、检查这些文件的 tsconfig 要包含测试文件。
  - P2 `modules-and-publishing.md`：`isolatedDeclarations` 写成了另有工具产出 JS 时的必选项。属实，`tsc` 跨整个程序推断声明。fixed：只在声明由不经类型检查器、逐文件产出的工具生成，或仓库自己采用该约束时才开；`compiler-config-and-checking.md` 表格同步。
  - P2 `validation.md`：评审时本文件是占位。fixed：本文件；同时 source register 第一行改为写明 F41–F44 本轮未运行。
  - P2 `source-map.md`：评审包里没有冻结的来源摘录。fixed：`source-excerpts.md` 按断言列出带日期的原文短句，`source-map.md` 指向它。

## Challenge pass

- Reviewed commit: f21b487（review 修复合入后的单一提交）
- Reviewer: codex（`extraction_review_gate.sh --mode challenge`，focus 为错误或过时的编译器事实、类型检查闸被绕过、模块与 `exports` 运行时失败、路由抢占、React 迁移丢义务、`tc.ts` 行为变化、项目信息泄漏），结果 `challenge-C1.json`
- 评审包：排除了 `evidence/` 下的三个 JSON 报告，否则超过 200 KB 上限；第一次未排除时控制器返回 `invalid_input`，没有评审。
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- Dispositions:
  - P2 `compiler-config-and-checking.md`：`skipLibCheck: true` 也跳过一方声明，手写 `types/` 里的错误会假绿。按 TSConfig Reference（"Skip type checking of declaration files"）属实。fixed：表格写明它跳过所有 `.d.ts`，仓库发布或手写声明时闸必须另跑一次 `skipLibCheck: false`；`modules-and-publishing.md` 的手写声明一条同步。
  - P2 `react-architecture.md`：迁移时丢了「shipped code 不用 `any`」。属实，是零损失映射的遗漏。fixed：React 侧保留这条禁令，边界解析仍指向新技能。
  - P2 `validation.md`：路由报告和编译输出不在评审包里。部分属实：JSON 报告因包大小上限被排除。fixed：加入小体积的 `routing-summary.txt`（逐条副本选择）、`tc-red.txt`、`tc-green.txt`、`check-ccl-skills.txt`。

## Delta pass

- Reviewed commit: 3fb0369；packet: `git diff f21b487..3fb0369`（排除 `evidence/` 下的 JSON）
- Reviewer: codex（通用 `review_gate.sh --mode review --base f21b487`；增量里没有提炼流程自己的文件，按评审门规定走通用控制器），结果 `delta-D1.json`
- Findings: 2 total (0 P0 / 0 P1 / 2 P2)
- Dispositions:
  - P2 `validation.md`：`make test-repo-gates` 的结果绑定在 challenge 修复之前的提交上。属实。fixed：合成最终提交后在该提交上跑完整本地 lane 与 CI 独有检查，结果见下文「最终候选」。
  - P2 `react-architecture.md`：评审包里没有 `web-react-dev/SKILL.md`，无法核对恢复的规则。不改：恢复的是 `origin/main` 原文里的同一句（`No \`any\` in shipped code`，基线中出现 1 次），没有新增义务。

这是最后一次外部评审。之后只有本文件的结果记录和把分支合成一个提交，不改实现。

## 最终候选

- 第一次在合成后的提交上跑 `make test-regressions-fast`，`test_obligation_ledger_repo_audit.sh` 报 `STALE_LEDGER`（`specs/065-uiux-evidence-delivery/obligation-preservation.md`）。对照：同一套件在 `origin/main` 上 exit 0、在本分支 exit 1。原因已核实：该台账按工作区解析承载行的行号，本轮在 `web-react-dev/SKILL.md`、`defect-diagnosis/SKILL.md`、`mobile-quality-release.md` 插入的行让十个承载位置的行号各后移一行，义务和映射内容不变。用台账工具的 `render` 重新生成，差异只有行号；重跑审计 exit 0。门禁按设计生效，不需要改规则。
- 台账重新生成属于生成型记录，审计本身逐字节校验它与工具输出一致，没有另做外部评审。
- 在 47b5ee7 上全部通过（exit 0）：`check-ccl-skills.sh`（私有别名审计 `r0_status=private-ok`）、`check-public-sanitization.py` 及其回归、`check-markdown-links.py`、`check-spec-references.py`、`check-skill-count.py` 及其回归、`check_review_evidence_present.py`、`make test-repo-gates`、`make test-regressions-fast`、`make test-code-review-1`、`make test-code-review-2`、`make test-code-review-abort-leak-1`、`-2`（在独立 PID 命名空间里跑，见本机环境说明）、`test_check_ccl_regressions.sh --heavy-only`。
- 之后只在本文件追加了这一段结果记录。

## 后续轮：F41–F44 配对评测（2026-11-13 追加）

第 10 行的「证据不足」记的是本轮落地时的状态。后续轮按冻结的任务和评分标准跑了配对评测（改前 e0a0568、改后 51b32dd 的整个插件树，每臂每任务 10 个有效样本）：

- 结论类别改为**稳定成功，附一处已修复的缺陷**。四个任务的评分标准覆盖率都提高（+0.09 到 +0.19，置换检验 p ≤ 0.002）。
- 缺陷：升级步骤没说在哪里压制报错，改后回答 4/10 建议用 `@ts-expect-error` 压弃用选项报错；第 4 步已改为按报错位置压制，修复后 0/10。
- 摘要、原始回答、评分、评测工具隔离问题和本轮的评审记录见 `behavior-eval/summary.md`、`behavior-eval/validation.md`。
