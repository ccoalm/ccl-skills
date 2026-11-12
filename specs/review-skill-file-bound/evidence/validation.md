# 验证记录

代码候选是提交 82651fb 的树；本文件是之后加入的唯一内容。

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| `CCL_BROAD_TEST_REASON=repo-required CCL_SKILL_BASE_REF=origin/main make test` | Linux，完整历史的克隆，含发布 tag | 通过 |
| `test_check_ccl_regressions.sh --heavy-only` | 同上 | 通过，9 个套件 |
| `bash skills/code-review/scripts/test_review_gate.sh` | macOS | 310 条通过 |
| `python3 scripts/check-public-sanitization.py .` | macOS | 通过 |
| `check_review_evidence_present.py`，fetch 目标分支之后 | macOS | 通过：2 份评审、1 份挑战 |
| `shared_git_surface_gate.py --base-ref origin/main` | macOS | 通过 |
| 变异：每次读取都用整包上限 | 控制器副本 | 新增用例失败（记录到的上限为三次整包上限，超限的包被算出哈希） |

环境上的三次无效运行，不计入结果：整条 lane 的前两次分别因为克隆里没有发布 tag、克隆是浅历史而停在与本改动无关的套件上；heavy 的第一次因为克隆里没有本地 `main` 分支，一个需要再次克隆的套件找不到合并基点。三项补齐后各重跑一次通过。

整条 lane 在 macOS 上通不过，原因在未改动的 `main` 上就存在，与本改动无关，所以在 Linux 上跑。
