# Makefile Template for Test Report Integration

TC management is scoped **per deployable unit**, not per repo. A "unit" is one
shippable artifact: a web frontend, a mini-program, an app, an admin frontend,
one backend service. See `SKILL.md` → "Scope: one config per deployable unit".

## Directory Convention

### Single-unit repo

```
project/
├── Makefile
└── test/
    ├── .report-config.json   # Bitable config (commit; no secrets)
    ├── cases/                # TC markdown mirror
    └── results/              # JUnit XML + tc-map.jsonl (gitignore)
```

### Monorepo (multiple units)

Each unit owns its own `Makefile` (or per-unit target) and its own
`test/.report-config.json`. The root Makefile orchestrates without merging.

```
project-root/
├── Makefile                     # delegates: web-test, app-test, svc-foo-test, ...
├── web/                         # unit: web frontend
│   ├── Makefile                  # the template below
│   └── test/
│       ├── .report-config.json   # this unit's Bitable
│       ├── tc.ts                 # this unit's TC helper (tc.py/tc.go/tc.ts/tc.dart)
│       ├── cases/                # this unit's md mirror
│       └── results/              # JUnit + tc-map.jsonl (gitignored)
├── miniapp/                     # unit: 小程序
│   └── test/...                  # same per-unit layout
├── admin-web/                   # unit: 运营后台前端
│   └── test/...
├── app/                         # unit: cross-platform app
│   └── test/...
└── services/foo/                # unit: one backend service
    ├── Makefile
    └── test/...
```

Each unit has its own:

- `.report-config.json` (own `base_token` / `table_id` / `report_doc_url`)
- TC helper file (`tc.py`/`tc.go`/`tc.ts`/`tc.dart`)
- Local md mirror (`test/cases/`)
- JUnit + sidecar output (`test/results/`)
- Feishu report doc

Root Makefile example (orchestrator only):

```makefile
.PHONY: web-test app-test svc-foo-test all-test report-web report-app report-svc-foo

web-test:        ; $(MAKE) -C web test
app-test:        ; $(MAKE) -C app test
svc-foo-test:    ; $(MAKE) -C services/foo test
all-test: web-test app-test svc-foo-test

report-web:      ; $(MAKE) -C web report-run
report-app:      ; $(MAKE) -C app report-run
report-svc-foo:  ; $(MAKE) -C services/foo report-run
```

No `report-all` — each unit publishes to its own Feishu doc independently.

CI typically runs only the units changed by the PR (path-filter triggers).
Each unit's Feishu report doc is updated independently; the project-level
README links to each unit's report URL.

### Why per-unit is simpler

- No multi-sidecar merge logic (each unit's sidecar is local)
- No cross-table TC ID collisions to worry about
- No "which suite covered which TC" routing — within a unit, it's obvious
- Owners, deploy cadence, auth scopes can differ per unit without coupling
- A failure in `app/` does not block `services/foo/`'s release

If a single unit later splits into smaller services, each new service becomes
its own unit. If a service is merged into another, their Bitables merge
(one-time data migration) — the scheme has no built-in coupling to undo.

## When to Apply

Inspect the existing Makefile (if any) and apply the smallest change needed.
Never rewrite an existing Makefile — only append or surgically edit a single line.

| Existing state | Action |
|---|---|
| No Makefile | Generate from the template below; detect stack and fill in `test` target. |
| Makefile exists, no `# Report` section | Append the full `# Report` section + `TC_SIDECAR` var + sidecar `rm -f` in the `test` target. Do not touch other existing targets. |
| Makefile has `# Report` section but no `TC_SIDECAR` var | Add `TC_SIDECAR ?= test/results/tc-map.jsonl` + `export TC_SIDECAR` near the top; add `rm -f $(TC_SIDECAR)` to the `test` recipe; leave other lines alone. |
| Makefile has `# Report` section but `report-init` lacks the optional-Bitable form | Update `report-init` to the `$(if $(BITABLE_URL),...)` conditional form so minimal-mode init works. |
| Makefile has `report-run: test` (prerequisite chain) | Rewrite to `report-run:` (no prerequisite) with `-$(MAKE) test` in the body. The prerequisite form aborts on test failure and gen_report.py never runs — so red CI skips Bitable sync, Feishu update, and the PR comment. The leading `-` lets make continue past test failures; gen_report.py then decides exit code via `--fail-on`. |
| Makefile is fully up to date | No action. |

For any update, diff-and-show before writing; ask the user when an existing
target conflicts with the template's name or recipe.

## Stack Detection → `test` Target

| File present | `test` command |
|---|---|
| `pyproject.toml` / `setup.py` | `uv run pytest tests/ --junit-xml=test/results/test.xml -v` |
| `go.mod` | `mkdir -p test/results && go test ./... -v 2>&1 \| go-junit-report -set-exit-code > test/results/go.xml` |
| `package.json` (jest) | `npx jest --reporters=jest-junit --outputDirectory=test/results` |
| `package.json` (vitest) | `npx vitest run --reporter=junit --outputFile=test/results/test.xml` |
| `pubspec.yaml` | First run only: `dart pub global activate junitreport`. Then: `mkdir -p test/results && flutter test --machine \| tojunit --output test/results/flutter.xml`（`flutter test --machine` 输出 JSON 事件流，**不是** JUnit XML，需 `tojunit` 转换；直接 `> flutter.xml` 会让 `gen_report.py` 的 ET.parse crash） |
| Multiple stacks | Add one target per stack (`test-py`, `test-go`, …); `test` runs all |

## Template

```makefile
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Default to vendored copy in the project (Step 0 of the manual copies it here).
# Override with GEN_REPORT=... if you keep the script elsewhere.
GEN_REPORT    ?= test/scripts/gen_report.py
REPORT_CONFIG ?= test/.report-config.json
TC_SIDECAR    ?= test/results/tc-map.jsonl
export TC_SIDECAR

.PHONY: help test ci report report-run report-init report-orphans

help: ## 查看可用目标
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_.-]+:.*## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Test ──────────────────────────────────────────────────────────────────────

test: ## 跑测试：清空 sidecar，写 JUnit XML 到 test/results/
	mkdir -p test/results
	rm -f $(TC_SIDECAR)
	<stack-specific-test-command>

ci: test ## 本地 CI 一键跑（lint + test；lint 目标按栈自行添加）

# ── Report ────────────────────────────────────────────────────────────────────

report: ## 读 test/results/，生成/更新报告（Bitable 模式写飞书；无 Bitable 打到 stdout）
	python $(GEN_REPORT) --config $(REPORT_CONFIG)

report-run: ## 跑测试 + 生成报告（gen_report.py 拥有 exit code 决策权，--fail-on）
	# Run tests but DON'T abort make on failure — gen_report.py reads the JUnit
	# XML and decides exit code via --fail-on. If we let `test` failures bubble
	# up here, gen_report.py never runs and red CI would skip Bitable sync,
	# Feishu update, last-run.json save, and the PR comment step.
	-$(MAKE) test
	python $(GEN_REPORT) --config $(REPORT_CONFIG)

report-init: ## 初始化报告配置（Bitable 模式: make report-init BITABLE_URL="https://example.feishu.cn/base/BASxxxxxxxx?table=tblxxxxxxxx"；无 Bitable: make report-init）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --init $(if $(BITABLE_URL),--bitable-url "$(BITABLE_URL)",)

report-orphans: ## 检测孤儿 TC ID（Bitable 模式专用）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --detect-orphans

report-diff-md: ## 检查本地 md 与 Bitable 漂移（用法: make report-diff-md MD=test/cases/all.md）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --diff-md "$(MD)"

report-validate-matrix: ## 只报告 test-matrix 与 Bitable 漂移，不阻断
	@test -n "$(MATRIX)" || { echo "MATRIX is required, e.g. MATRIX=test/cases/test-matrix.md"; exit 1; }
	@test -f "$(MATRIX)" || { echo "MATRIX file not found: $(MATRIX)"; exit 1; }
	@echo "NOT A GATE: report-only MATRIX drift is printed but this target does not block"
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --validate-matrix "$(MATRIX)" --matrix-drift-gate warn

report-validate-matrix-report: report-validate-matrix ## report-validate-matrix 的非阻断别名

report-validate-matrix-gate: ## 跑测试 + 阻断式校验 test-matrix 与 Bitable / 层级证据
	@test -n "$(MATRIX)" || { echo "MATRIX is required, e.g. MATRIX=test/cases/test-matrix.md"; exit 1; }
	@echo "GATE NOTE: TC presence/Bitable sync is always gated; layer coverage is gated only after suite layer metadata is configured"
	mkdir -p test/results
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --run-tests --validate-matrix "$(MATRIX)" --matrix-drift-gate fail

inventory: ## 导出现有 TC 清单（迭代前必看；按模块分组）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --inventory

inventory-md: ## 导出现有 TC 为 md 表（管道到文件后可配 --diff-md 使用）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --inventory-md

pr-summary: ## 输出短 PR comment（CI 用）
	python $(GEN_REPORT) --config $(REPORT_CONFIG) --pr-summary
```

**为什么 test target 必须 `rm -f $(TC_SIDECAR)`**：sidecar 是 append-only JSONL。
被删的测试不再追加，但旧 entry 会一直存留，导致 gen_report.py 报告该测试仍存在。
每次跑测试前清空，确保 sidecar 反映当前真实状态。

## .gitignore

```
test/results/
```

This covers JUnit XML output **and** `tc-map.jsonl` (the sidecar).
`test/.report-config.json` should be committed (resource IDs only, no secrets).
The per-stack `tc.{py,go,ts,dart}` helper file is committed too — it is project source.
