# 评审与验证记录

## 行为证据

- 类别：RED-baseline，构造场景（冻结夹具 F44，同一轮交错跑两臂）。
- 改前：`51b32dd` 原技能树，专项判定 5/10 建议用源码注释压弃用选项报错（`run2-fix/deprecation-check.jsonl`）；第一轮同一棵树 4/10（`run1/deprecation-check.jsonl`）。
- 改后：只多第 4 步这一段修复的技能树，0/10；评分标准覆盖率 0.97 对 0.96。
- 事实核实：TypeScript 6.0.3 实跑，见 `summary.md`「缺陷」一节。

## 确定性检查

- `check-ccl-skills.sh`（设置 `ALIAS_AUDIT_CMD` 跑私有别名审计）：`ccl_skill_check_clean_ok`，`r0_status=private-ok`，`eval_routing_ok`，impact-chain 无告警。
- `make test-repo-gates`、`make test-regressions-fast`：exit 0。
- CI 独有检查 `check-public-sanitization.py`、`check-markdown-links.py`、`check-spec-references.py`、`check-skill-count.py` 及其回归：通过。

## Review pass

- Reviewed commit: f61f2fb；base `origin/main` 51b32dd（`git ls-remote` 于 2026-11-14T01:47Z 确认）
- Reviewer: kimi（`extraction_review_gate.sh --mode review`），结果 `review-R1.json`
- 评审包：技能改动、登记行、上级 `validation.md`、本目录的 `summary.md`、`AGENTS.md`、`harness/`、`run*/analysis.md`、`run*/deprecation-check.jsonl`、`run1/capability-delta-report.md`、`isolation-probe/`。原始回答、`meta.jsonl`、`judgments.jsonl` 因 200 KB 包上限未进包，但都在候选里。
- 第一次调用 inconclusive：评审计划缺 `python-service-dev`（控制器因 `harness/*.py` 派生出该负责方）；补上后重跑。
- Findings: 2 total (0 P0 / 0 P1 / 2 P2)
- Dispositions:
  - P2 `summary.md`：引用 `run*/layers.jsonl`，驱动写的是 `layers.json`。部分属实：入库文件就是 `layers.jsonl`（入库时转换），但摘要没说明转换。fixed：写明 `layers.json`、`*.meta.json` 入库时各合成一个 JSON Lines 文件，并列出原始回答与盲评输出的位置。
  - P2 `AGENTS.md`：声明的原始回答、评分输出、评审记录和 `behavior-eval/validation.md` 不在候选里。部分属实：原始回答与评分输出在候选里，只是没进评审包；本文件当时还不存在。fixed：新增本文件，并写明评审包排除了哪些文件。
