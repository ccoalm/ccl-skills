# 验证记录

方案 11.12 测的是 `product-rd-workflow` 入口 26,909 字节的一版。之后技能文本只改了一处：入口补回技术设计闸摘要里的一处触发限定（+85 字节，见 11.12 末尾）；hook 和脚本没有再改。下表的检查都跑在最终提交上，提交号见 PR。

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `CCL_BROAD_TEST_REASON=repo-required CCL_SKILL_BASE_REF=origin/main make test` | Linux，含发布 tag 的完整历史克隆 | 见下方「最终提交」 |
| `test_check_ccl_regressions.sh --heavy-only` | 同上 | 见下方「最终提交」 |
| `make eval-routing` | macOS | 见下方「最终提交」 |
| `check-ccl-skills.sh`（含体量闸、登记行锚点闸） | macOS | 见下方「最终提交」 |
| `python3 -m pytest hooks/test_skill_loading.py hooks/test_task_entry.py` | macOS | 见下方「最终提交」 |
| `python3 scripts/check-public-sanitization.py .` | macOS | 见下方「最终提交」 |
| `check_review_evidence_present.py`，fetch 目标分支之后 | macOS | 见下方「最终提交」 |
| `shared_git_surface_gate.py --base-ref origin/main`，含拟用的 PR 标题和正文 | macOS | 见下方「最终提交」 |
| 设计任务对照 | 方案 11.12 | 36 次运行，33 次有效，过 10.6 |
| 最严任务在最终文本上重测 | 方案 11.12 末尾 | 6 次，6 次有效，加载字节 100,008，不高于基线 100,135 |
| 实现探针 | 方案 11.12 | 8 次运行，8 次有效；加载了 `product-rd-workflow` 的 6 次都在写代码前读了两个阶段参考文件 |

## 最终提交

（检查跑完后填写。）

## 评审

见方案 11.7 和本目录下的结果文件：`review.json`、`challenge.json` 审的是第一版；`review-2.json`、`challenge-2.json`、`delta-2.json` 审的是第二版相对第一版新增的行为；`review3a.json`、`review3b.json` 是第三版的独立评审（方案 11.10 的改动由它们触发）；`challenge-3a.json`、`challenge-3b.json` 是第三版的对抗挑战，处置见同名的 `-dispositions.md`；`delta-3.json` 是挑战之后的增量复查。
