# 验证记录

方案 11.12 测的是 `product-rd-workflow` 入口 26,909 字节的一版。之后技能文本只改了一处：入口补回技术设计闸摘要里的一处触发限定（+85 字节，见 11.12 末尾）；hook 和脚本没有再改。下表前八行的检查跑在最终提交上；后三行是行为对照，各自写明测的是哪一版文本。

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `CCL_BROAD_TEST_REASON=repo-required CCL_SKILL_BASE_REF=origin/main make test` | Linux，含发布 tag 的完整历史克隆 | 通过（退出码 0） |
| `test_check_ccl_regressions.sh --heavy-only` | 同上 | 一个套件被 SIGPIPE 中止，单独重跑两次通过；见下方「最终提交」 |
| `make eval-routing` | macOS | 通过，无阻断项、无提示项 |
| `check-ccl-skills.sh`（含体量闸、登记行锚点闸） | macOS | `ccl_skill_check_clean_ok` |
| `python3 -m pytest hooks/test_skill_loading.py hooks/test_task_entry.py` | macOS | 37 条通过 |
| `python3 scripts/check-public-sanitization.py .` | macOS | `public_sanitization_ok` |
| `check_review_evidence_present.py`，fetch 目标分支之后 | macOS | `review_evidence_present_ok: 6 review, 4 challenge` |
| `shared_git_surface_gate.py --base-ref origin/main`，含拟用的 PR 标题和正文 | macOS | 通过 |
| 设计任务对照，测的是入口 26,909 字节的一版 | 方案 11.12 | 36 次运行，33 次有效，过 10.6 |
| 最严任务重测，测的是最终文本 | 方案 11.12 末尾、`retest-strictest-task.md` | 6 次，6 次有效，加载字节 100,008，不高于基线 100,135 |
| 实现探针，测的是入口 26,909 字节的一版；之后入口只补回技术设计闸的一处限定，没有改加载指令和 hook | 方案 11.12 | 8 次运行，8 次有效；加载了 `product-rd-workflow` 的 6 次都在写代码前读了两个阶段参考文件 |

## 最终提交

上表前八行跑在提交 e1865f5 上，基线是 origin/main 65956e3。

heavy lane 里，`test_impact_chain_gate_verdict_differential.sh` 以退出码 141 结束，其余套件都通过。中止前打出的分歧行都是这个套件预先列明的十处之一。原因在套件自身：第 305 行 `printf '%s\n' "$candidate_out" | head -8` 跑在 `set -o pipefail` 下，门禁输出超过 8 行时，`head` 可能先退出，`printf` 随即收到 SIGPIPE。本分支没有改这个脚本。同一检出上单独重跑两次，都以 `impact_chain_gate_verdict_differential: ok (64 integration points, 10 named expected divergences, ...)` 结束。这个时序问题不在本改动范围内，留给下一个改这个脚本的改动修。

## 评审

见方案 11.7 和本目录下的结果文件：`review.json`、`challenge.json` 审的是第一版；`review-2.json`、`challenge-2.json`、`delta-2.json` 审的是第二版相对第一版新增的行为；`review3a.json`、`review3b.json` 是第三版的独立评审（方案 11.10 的改动由它们触发）；`challenge-3a.json`、`challenge-3b.json` 是第三版的对抗挑战，处置见同名的 `-dispositions.md`；`delta-3.json` 是挑战之后的增量复查。
