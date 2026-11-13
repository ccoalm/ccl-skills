# 评审与验证记录

## Review pass

- Reviewed commit: ef2f6f7（相对 `origin/main` 的整条分支）
- Reviewer: codex（`extraction_review_gate.sh --mode review`），结果 `review-R1.json`
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- R0 evidence: `check-ccl-skills.sh` 输出 `ccl_skill_check_clean_ok`，`r0_status=private-ok`
- Dispositions:
  - P2 `hooks/host-input.py`：默认值规则没有唯一负责人的条件，会进入团队会话。fixed in eb07d98，条件写进提醒文字，加了断言。
  - P2 `plan.md`：最终候选缺 P7、P3 没过、没有确定性检查的结果。P7 和检查结果在本文件和计划第 13 节补上；P3 记为未达成，偏离理由写在计划第 13 节。
  - P2 `requirement-closure-contract.md`：评审包里没有 PRD Ready 的消费规则，无法判断 `requester-default` 会不会绕过它。按源文核对：第 4 档写明「字段据此确定，整行状态和 `PRD Ready` 仍按各自的门判定」，Ready 门的条件没有改。不改。

## Challenge pass

- Reviewed commit: eb07d98
- Reviewer: codex（`extraction_review_gate.sh --mode challenge`），结果 `challenge-R1.json`
- Findings: 4 total (0 P0 / 1 P1 / 3 P2)
- R0 evidence: 同上
- Gate-fireability applicability: yes — 改动的是 Stop 钩子每次触发时的提醒文字；Item 9 exercised: 第四轮 44 次运行的保存记录，路径在仓库外的私有评测目录
- Dispositions:
  - P1 `hooks/host-input.py`：唯一负责人判定缺资源归属、任务材料和平台审批三项。fixed in 34f1d9c，提醒文字带上 `session-policy.md` 规则第 1 条的全部条件和「拿不准按团队场景」，常驻层摘要补上资源归属；测试逐条断言。
  - P2 `hooks/host-input.py`：「never as blocked:」会把真缺的审批也藏起来。fixed in 34f1d9c，改成范围本身不写成 `blocked:`，独立缺的批准、权限、凭据、资源照写；测试断言旧句不再出现。
  - P2 `eval/owner-role-audit.py`：否定过滤跨逗号。fixed in 34f1d9c，加反例「实现还没做完，等你确认。」。
  - P2 `eval/owner-role-audit.py`：单独的 `you` 让整行角色免计。fixed in 34f1d9c，加反例「You need sign-off from the security owner.」；两臂重数。

## Delta pass 1

- Reviewed commit: f9339db；packet: `git diff eb07d98..f9339db`
- Reviewer: codex（`extraction_review_gate.sh --mode review --base eb07d98`），结果 `delta-R1.json`
- Findings: 3 total (0 P0 / 0 P1 / 3 P2)
- Dispositions:
  - P2 `plan.md`：第四轮 P7 写着「见下文」却没有结果。fixed：第四轮判分 23/24（基线 27/30），写进计划第 13 节的表。
  - P2 `validation.md`：缺 `make test` 的另外两条 lane 和 `regression-heavy`。fixed：结果见下面「本地验证」；其中 `regression-heavy` 首次失败，原因与处置也写在下面。
  - P2 `eval/owner-role-audit.py`：评审包里没有消费这两个正则的函数，评审无法判断。按源文核对：`role_mentions` 与 `ends_waiting` 只用这两个正则和 `DENIAL_BEFORE`，8 个测试覆盖 challenge 给出的两个反例和原有正反例。不改。

这是最后一次外部评审。之后的改动只有本文件、计划第 13 节的 P7 一行和把分支合成一个提交，都不改实现。

## Post-review delta

- 分支合成一个提交：登记表的门禁按「改动登记表的提交」把分支切成几轮，`f9339db` 改了第一轮加的两行登记，这两行就被算进第二轮，第一轮的负责技能改动没有登记行。合成一个提交后只有一轮。被评审过的提交 ef2f6f7、eb07d98、f9339db 的实现内容都包含在合成后的提交里。
- `specs/self-owner-accountability/plan.md`：第 13 节补 P7 一行。
- 本文件：补 Delta pass 1 和本地验证结果。

## 本地验证（最终提交）

- `python3 -m unittest hooks.test_proposed_next`：72 个通过
- `python3 -m unittest eval/test_owner_role_audit.py`：8 个通过
- `make test-repo-gates`（`CCL_BROAD_TEST_REASON=repo-required`，私有别名审计已配置）：通过
- `make test-regressions-fast`：45 个套件通过
- `make test-code-review-1`、`make test-code-review-2`：通过
- `make test-code-review-abort-leak-1`、`-2`：在 `unshare --user --map-current-user --pid --fork --mount-proc` 下通过。这台机器的会话里孤儿进程由 `systemd --user` 收养，不在新的 PID 命名空间里跑，第 1 段一定失败，与本改动无关
- `test_check_ccl_regressions.sh --heavy-only`：首次 1 个套件失败（`test_check_ccl_r0_status.sh`），原因是上面说的登记行轮次。合成一个提交后单独重跑该套件通过；其余套件首次就已通过。`check-ccl-skills.sh` 在不配私有审计时输出 `ccl_skill_check_interim_ok`，配上后输出 `ccl_skill_check_clean_ok`
- CI `repository-gates` 的其余步骤：`test_check_public_sanitization.py`、`check-public-sanitization.py`、`check-markdown-links.py`、`check-spec-references.py`、`test_check_skill_count.py`、`check-skill-count.py`、`check_review_evidence_present.py` 全部通过
