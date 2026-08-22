# ccl-skills 安装与更新（薄封装，逻辑在 scripts/install*.sh）
.PHONY: help test test-repo-gates test-regressions-fast test-code-review test-check-ccl-regressions test-verify-sandbox install install-npm uninstall-npm install-opencode install-opencode-no-agent install-opencode-commands install-gates install-codex-cron update update-npm update-opencode update-opencode-no-agent prune-cache eval-routing eval-routing-bank eval-body-compliance eval-golden-trace eval-health npm-build npm-test npm-pack-verify npm-host-smoke npm-publish-dry
.DEFAULT_GOAL := help

help: ## 显示可用目标
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-20s %s\n", $$1, $$2}'

# `test` 是纯 prerequisites 聚合、无自有 recipe：往本地全量测试加套件必须落进某个
# 子目标，而三个子目标全部被 CI 消费（repository-gates / code-review-regressions
# 直跑，fast lane 经 regression-heavy 的 --full 超集），杜绝"进了 make test 却不进
# 任何 CI job"的 false-green（specs/035-ci-critical-path-split/plan.md）。
test: test-repo-gates test-regressions-fast test-code-review ## 运行本仓确定性 gate、脚本测试和 Python 回归

test-repo-gates: ## 仓库确定性 gate 与脚本/Python 回归（CI repository-gates job；不含 code-review 族与 fast 回归 lane）
	bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .
	bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo . --enforce
	python3 scripts/test_check_markdown_links.py
	python3 scripts/check-markdown-links.py .
	python3 scripts/test_check_spec_references.py
	python3 scripts/check-spec-references.py .
	bash scripts/test_install_opencode_skill_migration.sh
	bash hooks/test_guard_delegation_owner.sh
	bash hooks/test_guard_edit_isolation.sh
	bash hooks/test_guard_merge_authorization.sh
	bash hooks/test_merge_authorization_prompt.sh
	bash hooks/test_remind_post_merge_cleanup.sh
	bash hooks/test_session_start.sh
	bash skills/testing-strategy/scripts/client-terminal-ansi-check.test.sh
	bash skills/testing-strategy/scripts/lang-basics-ast-check.test.sh
	bash skills/testing-strategy/scripts/lang-basics-go-check.test.sh
	bash skills/worktree-isolation/scripts/test_worktree_status.sh
	bash skills/worktree-isolation/scripts/test_worktree_sweep.sh
	bash scripts/owner-dispatch/test.sh
	bash scripts/control-plane/test.sh
	python3 -m pytest -q skills/test-artifact-management/references/test_gen_report.py
	python3 -m unittest eval.test_subagent_owner_audit eval.test_skill_effectiveness_bridge eval.test_skill_effectiveness_trial eval.test_reviewer_calibration_protocol

test-regressions-fast: ## fast 回归 lane（CI 上由 regression-heavy 的 --full 超集覆盖，仅本地 make test 直跑）
	bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --fast

test-code-review: ## code-review 技能回归族（CI code-review-regressions 并行 job）
	bash skills/code-review/scripts/test_classify_envelope.sh
	bash skills/code-review/scripts/test_concern_excerpt.sh
	bash skills/code-review/scripts/test_claude_review_probe.sh
	bash skills/code-review/scripts/test_parse_opencode_review.sh
	bash skills/code-review/scripts/test_egress_schema.sh
	bash skills/code-review/scripts/test_parse_probe_result.sh
	bash skills/code-review/scripts/test_init_policy_matrix.sh
	bash skills/code-review/scripts/test_parse_review_json.sh
	bash skills/code-review/scripts/test_opencode_review_retry.sh
	bash skills/code-review/scripts/test_opencode_review_concurrency.sh
	bash skills/code-review/scripts/test_review_gate.sh
	bash skills/code-review/scripts/test_review_client_order.sh
	bash skills/code-review/scripts/test_cli_review_wrappers.sh
	python3 skills/code-review/scripts/test_review_client_compat.py
	bash skills/code-review/scripts/test_code_review_identity.sh

test-check-ccl-regressions: ## 运行 check-ccl-skills shell wrapper 全量回归（CI changes-gated 同入口）
	bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --full

test-verify-sandbox: ## verify-sandbox 行为套件（需本机 docker，故不进默认 test；改 scripts/verify-sandbox 必跑）
	bash scripts/verify-sandbox/test.sh

install: ## 安装检测到的 Claude Code、Codex 和 OpenCode 集成
	bash scripts/install.sh

install-opencode: ## 安装/刷新 OpenCode 原生全局 skills、兼容 skills、plugin 和 commands
	bash scripts/install-opencode.sh

install-opencode-no-agent: ## 同 install-opencode，但跳过 ~/.agents/skills 兼容同步（技能只进 ~/.config/opencode/skills）
	bash scripts/install-opencode.sh --no-agent

install-opencode-commands: ## 给目标项目安装 OpenCode command（用 TARGET=/path/to/project）
	bash scripts/install-opencode-commands.sh "$${TARGET:-.}"

install-gates: ## 给产品仓一键安装 gate backstop（agent-contract + owner-dispatch + control-plane，warn-only；用 TARGET=/path/to/repo）。改阻断是后续手动一步（见 README）
	@[ -n "$(TARGET)" ] || { echo "用法: make install-gates TARGET=/path/to/repo"; exit 2; }
	bash scripts/install-gates.sh "$(TARGET)"

eval-routing: ## F4 Tier-1 静态路由分析器（触发词碰撞 / 悬空重定向；客观失败非 0 退出）
	ruby skills/skill-extraction-workflow/scripts/eval-routing.rb .

eval-routing-bank: ## F4 Tier-2 路由 task-bank 廉价 grader（advisory dashboard；需本机 claude CLI）
	ruby skills/skill-extraction-workflow/scripts/eval-routing-bank.rb .

eval-body-compliance: ## 技能正文硬规则是否真被执行（advisory；需本机 claude CLI）
	ruby eval/body-compliance-eval.rb . --json /tmp/body-compliance.json

eval-golden-trace: ## F4 Tier-3 hub golden trace 真 agent 回放（advisory，人工判定；需本机 claude CLI）
	ruby skills/skill-extraction-workflow/scripts/eval-golden-trace.rb .

eval-health: ## F4 health 综合分 roll-up（advisory 0-10 + 趋势；跑确定性 T1+结构，T2/T3 用 --bank-json/--trace-json 喂入）
	ruby skills/skill-extraction-workflow/scripts/eval-health.rb .

install-codex-cron: ## 同 install，并给 Codex 装每日 cron 伪自动更新（改 crontab）
	bash scripts/install.sh --codex-cron

update: ## 刷新 Claude Code、Codex 和 OpenCode 集成
	# Claude：必须用 `plugin update`。`plugin install` 对已装插件只会 no-op（"already installed"），不会更新。
	-claude plugin marketplace update ccl-skills && claude plugin update ccl-skills@ccl-skills
	# Codex：upgrade 刷新 marketplace git 快照，plugin add 再把快照装进运行缓存（安装是快照的拷贝，
	# 单 upgrade 只刷快照、不动安装）。同 install.sh。
	@if command -v codex >/dev/null 2>&1; then \
	  if ! { codex plugin marketplace upgrade ccl-skills && codex plugin add ccl-skills@ccl-skills; }; then \
	    echo "  ⚠ Codex 更新失败：检查 GitHub 访问和本地 marketplace 配置后重试"; \
	  fi; \
	else echo "  ⓘ 未检测到 codex CLI，跳过 Codex 更新"; fi
	# OpenCode：原生 skills/plugin/commands 从当前 checkout 安装（install-opencode.sh 不联网拉远端；
	# 此处也不动本地 git）。要装最新 main 先自行 `git pull`，或用 `make update-opencode-no-agent`（它会先 ff-only 拉）。
	# --no-agent：技能只进 ~/.config/opencode/skills。整块非致命，
	# 失败不影响上面已完成的 Claude/Codex 更新。
	@if command -v opencode >/dev/null 2>&1; then \
	  echo "  ⟳ 刷新 OpenCode 原生 skills（--no-agent，从当前 checkout）"; \
	  if ! bash scripts/install-opencode.sh --no-agent; then \
	    echo "  ⚠ OpenCode 更新失败，运行 make update-opencode-no-agent 重试"; \
	  fi; \
	else echo "  ⓘ 未检测到 opencode CLI，跳过 OpenCode 更新"; fi

update-opencode: ## 手动刷新 OpenCode skills、plugin、commands 和 install manifest
	git pull --ff-only
	bash scripts/install-opencode.sh

update-opencode-no-agent: ## 同 update-opencode，但跳过 ~/.agents/skills 兼容同步
	git pull --ff-only
	bash scripts/install-opencode.sh --no-agent

prune-cache: ## 删除 Claude 端 ccl-skills 旧版本插件缓存（保留当前安装版本）
	# `claude plugin prune` 只清自动装的依赖，不清旧版本目录；Claude 每次更新会留一个旧版本目录。
	# Codex 端缓存原地替换（恒为 local），不累积，无需处理。安全起见：拿不到当前版本就不删。
	@base="$$HOME/.claude/plugins/cache/ccl-skills/ccl-skills"; \
	[ -d "$$base" ] || { echo "无缓存目录，跳过"; exit 0; }; \
	active=$$(jq -r '.plugins["ccl-skills@ccl-skills"][0].version // empty' "$$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null); \
	[ -n "$$active" ] || { echo "⚠ 无法确定当前版本（缺 jq 或无安装记录），为安全不删，请手动清理 $$base"; exit 0; }; \
	[ -d "$$base/$$active" ] || { echo "⚠ 当前版本 $$active 的缓存目录不存在，安装记录可能不一致，为安全不删"; exit 0; }; \
	removed=0; for d in "$$base"/*/; do v=$$(basename "$$d"); [ "$$v" = "$$active" ] && continue; echo "删除旧版本缓存 $$v"; rm -rf "$$d"; removed=1; done; \
	[ "$$removed" = 0 ] && echo "无旧版本缓存可清（当前 $${active}）" || echo "完成，保留当前版本 $$active"

# --- 统一 npm 分发（Claude Code + Codex + OpenCode）---
NPM_PKG_DIR := packages/ccl-skills-npm

install-npm: ## 从 @ccoalm/ccl-skills 安装所有检测到的宿主
	@out=$$(npm view @ccoalm/ccl-skills version 2>&1) || { case "$$out" in *E404*) echo "@ccoalm/ccl-skills 尚未完成首次发布；当前请使用 make install" >&2 ;; *) echo "npm registry 查询失败；请检查网络、registry 和登录状态" >&2 ;; esac; exit 4; }
	npm install --global @ccoalm/ccl-skills
	ccl-skills install

update-npm: ## 升级 npm 包并刷新所有检测到的宿主
	@out=$$(npm view @ccoalm/ccl-skills version 2>&1) || { case "$$out" in *E404*) echo "@ccoalm/ccl-skills 尚未完成首次发布；当前请使用 make update" >&2 ;; *) echo "npm registry 查询失败；请检查网络、registry 和登录状态" >&2 ;; esac; exit 4; }
	ccl-skills update --yes

uninstall-npm: ## 卸载 npm 管理的注册；OpenCode 共享文件保留并报告
	ccl-skills uninstall --yes
	npm uninstall --global @ccoalm/ccl-skills

npm-build: ## npm ci + 构建统一 npm 包
	cd $(NPM_PKG_DIR) && npm ci && npm run build

npm-test: ## 运行三端 adapter、事务和安全回归
	cd $(NPM_PKG_DIR) && npm ci && npm test

npm-pack-verify: ## 构建并验证统一包的精确 tarball closure
	cd $(NPM_PKG_DIR) && npm run test:pack

npm-host-smoke: ## 用临时 HOME 和真实宿主 CLI 跑 lifecycle smoke
	cd $(NPM_PKG_DIR) && npm run smoke:host

npm-publish-dry: ## 构建 + 预览 pack + 验证，不发布（发布只走受保护的 tag workflow）
	cd $(NPM_PKG_DIR) && npm ci && npm test && npm run test:pack && npm pack --dry-run
