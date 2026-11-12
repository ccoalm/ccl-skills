# 验证记录

整条 lane 跑在提交 7b19cc2 的树上；本文件是之后唯一的改动。行为对照跑在提交 e205911 的技能文本上，之后技能文本只在清单第 3 条补了一句（方案 11.7）。本分支叠在 `specs/review-skill-file-bound/plan.md` 的修复之上。

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `CCL_BROAD_TEST_REASON=repo-required CCL_SKILL_BASE_REF=origin/main make test` | Linux，完整历史的克隆，含发布 tag，提交 7b19cc2 | 通过 |
| `test_check_ccl_regressions.sh --heavy-only` | 同上 | 通过 |
| `make eval-routing` | macOS | 无阻断项，无提示项 |
| `check-ccl-skills.sh`（含体量闸、登记行锚点闸） | macOS | 通过；`agent-context/session-start.md` 7,796 → 7,796 字节，`product-rd-workflow` 入口没有增长 |
| `python3 -m pytest hooks/test_task_entry.py` | macOS | 8 条通过 |
| `python3 scripts/check-public-sanitization.py .` | macOS | 通过 |
| `check_review_evidence_present.py`，fetch 目标分支之后 | macOS | 通过 |
| `shared_git_surface_gate.py --base-ref origin/main`，含拟用的 PR 标题和正文 | macOS | 通过 |
| 行为对照 | 见方案 11.6 | 60 次运行，40 次有效 |

评审见方案 11.7 和本目录下的结果文件：`review.json`、`challenge.json` 审的是第一版；`review-2.json`、`challenge-2.json`、`delta-2.json` 审的是第二版相对第一版新增的行为。
