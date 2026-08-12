# 空仓初始化手册：按栈调 skill 的顺序清单

从空 Git 仓到"可开发 + 飞书已接 + CI 反写就绪"的端到端 skill 调用顺序。覆盖 Python (FastAPI/Django/Flask) 和 Node（含 Vite 变体）。

不替代 [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md)——本文是机械顺序清单；遇到"做不做、怎么拆"的决策仍走 product-rd-workflow。每步标了"必须 / 推荐 / 可选"，按需取舍。

## 按角色找

| 你是谁 | 看哪段 |
|---|---|
| 新仓 Day 1 落地 | [流程总览](#流程总览) → [Python](#python-仓-7-步) 或 [Node](#node-仓-7-步) |
| 想知道哪些是"通用前置" | [Phase 0 通用前置](#phase-0通用前置与栈无关) |
| 想知道为什么没列某个 skill | [明确不在 init 范围](#明确不在-init-范围的-skill) |
| Vite 项目跟普通 Node 的差异 | [Vite 变体补丁](#vite-变体补丁) |

---

## 流程总览

```
┌── Phase 0：通用前置（不分栈，1 次性） ────────────────┐
│  worktree-isolation → agents-file-coverage-gate            │
│  → product-rd-workflow（charter / AC）               │
└──────────────────────────────────────────────────────┘
                          ↓
┌── Phase 1：栈骨架（python OR node） ─────────────────┐
│  python: python-service-architecture                  │
│          → python-service-dev                         │
│  node:   web-react-dev / app-cross-platform-dev /     │
│          miniapp-product-dev / terminal-cli-dev       │
│          （依实际选一）                                │
└──────────────────────────────────────────────────────┘
                          ↓
┌── Phase 2：测试 ─────────────────────────────────────┐
│  testing-strategy → test-artifact-management                  │
└──────────────────────────────────────────────────────┘
                          ↓
┌── Phase 3：测试用例飞书交付 ─────────────────────────┐
│  test-artifact-management 初始化/复用测试用例 Base（lark-base）│
│  → 按需接报告与 CI；其他飞书资源按需创建              │
└──────────────────────────────────────────────────────┘
                          ↓
┌── Phase 4：发布与可观测（可延迟） ───────────────────┐
│  platform-release-engineering                        │
│  + platform-observability                            │
│  + feature-risk-router                               │
└──────────────────────────────────────────────────────┘
```

每个 Phase 的 skill 显式点名调用：

```
使用 <skill-name> 帮我 ...
```

---

## Phase 0：通用前置（与栈无关）

保证不在 main 上直接改、每个目录都有 AGENTS.md、新需求先走 charter。

| 步 | Skill | 何时跑 | 必要性 | 怎么调 |
|---|---|---|---|---|
| 0.1 | [`worktree-isolation`](../skills/worktree-isolation/SKILL.md) | 仓建好的第一刻 | **必须** | "使用 worktree-isolation 给当前仓建一个功能分支 worktree" |
| 0.2 | [`agents-file-coverage-gate`](../skills/agents-file-coverage-gate/SKILL.md) | worktree 建好后 | **必须** | "使用 agents-file-coverage-gate 给本仓 init AGENTS.md 覆盖" |
| 0.3 | [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md) | 第一个真实需求来时 | **推荐** | "使用 product-rd-workflow 规划这个新项目，列出 charter / AC / 技能路由" |

0.3 在写第一行业务代码前必须跑——它产出 AC、产物路由、风险标签，给后面所有 skill 用。

---

## Python 仓（6 步）

目标产物 = 可跑的 FastAPI（或同类）后端，含 pytest，能 CI 反写飞书测试报告。前置：Phase 0 已完成。

| 步 | Skill | 跑什么 | 产物 | 必要性 |
|---|---|---|---|---|
| P1 | [`python-service-architecture`](../skills/python-service-architecture/SKILL.md) | 定服务边界、分层、DB/queue 选型 | 架构 Doc / `docs/architecture.md` | 推荐 |
| P2 | [`python-service-dev`](../skills/python-service-dev/SKILL.md) | 搭骨架：`pyproject.toml`、`uv` 或 `poetry`、入口、第一个 endpoint、`pytest` 配置 | 仓内代码 | **必须** |
| P3 | [`testing-strategy`](../skills/testing-strategy/SKILL.md) | 定测试层（unit / integration / e2e）+ fixture 策略 + CI gate | 测试方案 | **必须** |
| P4 | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | 建 `test/cases/`，初始化/复用测试用例 Base，接 `tc()` 与报告/CI 模板 | 用例 Base、`test/cases/`、报告配置 | **必须**（要用例管理） |
| P5 | `lark-wiki` / `lark-base` | 仅按真实需求创建其他 Wiki 节点或业务表 | 请求指定的飞书资源 | 可选 |
| P6 | 人工配置与写入 canary | CI secret、目标 Base 文档应用权限、只读 preflight、授权 one-shot CI 写回 | — | 使用 CI 反写时必须 |

### 调用脚本（Python 仓）

```bash
# Phase 0
"使用 worktree-isolation 给 <repo> 建 feature/<owner>/init 分支 worktree"
"使用 agents-file-coverage-gate 给 <repo> --check 后 --fix 缺失"

# Phase 1
"使用 python-service-architecture 设计 <product> 的服务边界"
"使用 python-service-dev 用 FastAPI 搭一个最小可跑骨架，含 pytest 和 uv"

# Phase 2
"使用 testing-strategy 给本仓定测试方案"
"使用 test-artifact-management 接 tc 辅助库到 test/"

# Phase 3
"使用 test-artifact-management 为 <repo> 初始化或复用测试用例 Base，并配置 Python 报告/CI 链路"
"仅在确有需要时，用 lark-wiki / lark-base 创建指定的其他飞书资源"
```

测试用例表结构和写回按 [`bitable-setup`](../skills/test-artifact-management/references/bitable-setup.md) 收口；通用飞书资源不做整套预建。

---

## Node 仓（6 步）

目标产物 = 可跑的 Node 客户端（React/Vue/小程序/CLI），含 vitest 或 node-test，能 CI 反写飞书测试报告。前置：Phase 0 已完成。

### 选择 Phase 1 的 owner skill

Node 范畴大，按客户端类型分：

| 你做的是 | Phase 1 owner skill |
|---|---|
| React Web / SSR / Next.js | [`web-react-dev`](../skills/web-react-dev/SKILL.md) |
| Vue / Svelte 等其它 web | [`web-react-dev`](../skills/web-react-dev/SKILL.md)（暂归入 web 系；语法差异自行映射） |
| Flutter / RN / 原生 App | [`app-cross-platform-dev`](../skills/app-cross-platform-dev/SKILL.md) |
| Taro / 微信/支付宝/抖音小程序 | [`miniapp-product-dev`](../skills/miniapp-product-dev/SKILL.md) |
| 终端 / CLI / TUI | [`terminal-cli-dev`](../skills/terminal-cli-dev/SKILL.md) |

### 步骤

| 步 | Skill | 跑什么 | 产物 | 必要性 |
|---|---|---|---|---|
| N1 | Phase 1 owner（见上） | 定路由、状态、API/数据、构建 | 架构 + 骨架 | 推荐 |
| N2 | 同上 | 搭骨架：`package.json`、vitest/jest、`tsconfig` 等 | 仓内代码 | **必须** |
| N3 | [`testing-strategy`](../skills/testing-strategy/SKILL.md) | 定测试层 + 浏览器/设备自动化 | 测试方案 | **必须** |
| N4 | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | 建 `test/cases/`，初始化/复用测试用例 Base，接 `tc()` 与报告/CI 模板 | 用例 Base、`test/cases/`、报告配置 | **必须**（要用例管理） |
| N5 | `lark-wiki` / `lark-base` | 仅按真实需求创建其他 Wiki 节点或业务表 | 请求指定的飞书资源 | 可选 |
| N6 | 人工配置 | CI secret、目标 Base 文档应用权限、本机干跑 | — | 使用 CI 反写时必须 |

### 调用脚本（Node 仓）

```bash
# Phase 0
"使用 worktree-isolation ..."
"使用 agents-file-coverage-gate ..."

# Phase 1（按你的客户端类型选）
"使用 web-react-dev 用 Vite + React + vitest 搭一个最小可跑骨架"
# 或
"使用 miniapp-product-dev 用 Taro 搭一个微信小程序骨架"

# Phase 2
"使用 testing-strategy ..."
"使用 test-artifact-management ..."

# Phase 3
"使用 test-artifact-management 为 <repo> 初始化或复用测试用例 Base，并配置 Node 报告/CI 链路"
"仅在确有需要时，用 lark-wiki / lark-base 创建指定的其他飞书资源"
```

---

## Vite 变体补丁

Vite 是 Node 的一种构建链，不是独立栈。Node 流程的"测试命令"换成 Vite 习惯即可。

| 项 | 普通 Node（小程序等） | Vite 项目（React/Vue Web） |
|---|---|---|
| 跑测命令 | `node --test ...` 或 `jest` | `npx vitest run` |
| JUnit 输出 | `--test-reporter=junit --test-reporter-destination=test/results/junit.xml` | `--reporter=junit --outputFile=test/results/junit.xml` |
| `package.json` scripts | 目标仓实际测试命令 | Vite 项目使用 `npx vitest run --reporter=junit --outputFile=...` |
| `.gitlab-ci.yml` | `test-artifact-management` CI 模板中的测试步骤 | 按同一 vitest 命令调整 |
| 依赖装命令 | `npm ci` | `npm ci`（或 `pnpm install --frozen-lockfile`） |

`test-artifact-management` 提供通用报告/CI 模板；目标仓若使用 Vite/vitest，必须按本仓实际命令审查并合并 `.gitlab-ci.yml` 与 `package.json`，不能照搬示例命令。

---

## 明确不在 init 范围的 skill

| Skill | 为什么不在 init 范围 | 什么时候才用 |
|---|---|---|
| [`defect-diagnosis`](../skills/defect-diagnosis/SKILL.md) | 没业务代码就没 bug 可修 | 第一个真实 bug |
| [`feature-risk-router`](../skills/feature-risk-router/SKILL.md) | 没具体改动就没风险标 | 第一个有风险特性 |
| [`platform-release-engineering`](../skills/platform-release-engineering/SKILL.md) | 没东西可发 | 第一次提测 |
| [`platform-observability`](../skills/platform-observability/SKILL.md) | 没业务流量没指标 | 上线前补可观测 |
| [`platform-service-connectivity`](../skills/platform-service-connectivity/SKILL.md) | 单服务时不需要 | 第一次跨服务调用 |
| [`llm-inference-integration`](../skills/llm-inference-integration/SKILL.md) | 跟 LLM/RAG 无关的仓不用 | 接 LLM 时 |
| [`tighten-doc`](../skills/tighten-doc/SKILL.md) | 没文档可润色 | 写第一份正式文档 |
| [`product-ui-ux-design`](../skills/product-ui-ux-design/SKILL.md) | 没 UI 可设计 | 第一个用户可见界面 |
| [`multi-agent-delegation`](../skills/multi-agent-delegation/SKILL.md) | 元能力，触发式自动加载 | agent 多任务并发时 |
| [`code-review`](../skills/code-review/SKILL.md) | 没代码可 review | 第一次 review 时 |
| [`skill-extraction-workflow`](../skills/skill-extraction-workflow/SKILL.md) | 没经验可沉淀 | 复盘 / 沉淀时 |

---

## 检查每一步是否真的完成

每个 skill 都有自检命令，串成一条 verify 链：

```bash
# Phase 0
bash skills/product-rd-workflow/scripts/check-agent-contract-coverage.sh --repo .
git worktree list | head      # 应有非 main worktree

# Phase 1 (Python 例子)
uv run python -c "import <your_pkg>; print('ok')"
uv run --group dev python -m pytest tests/ -q

# Phase 1 (Node 例子)
npm ci && npm test

# Phase 3
python3 test/scripts/gen_report.py --config test/.report-config.json --dry-run
lark-cli auth status --json --verify
lark-cli auth check --scope "base:record:read base:record:update"
BASE_TOKEN=$(python3 -c 'import json; print(json.load(open("test/.report-config.json"))["base_token"])')
TABLE_ID=$(python3 -c 'import json; print(json.load(open("test/.report-config.json"))["table_id"])')
lark-cli base +record-list --base-token "$BASE_TOKEN" --table-id "$TABLE_ID" --limit 1 --format json --as bot
```

以上是只读 preflight：干跑应生成预期报告；`auth status/check` 验证当前
profile 的 token 与 scope，不冒充 bot 证明；`record-list --as bot` 才是 CI
bot 的资源级读取证据。它仍不能证明 bot 的资源级写权限。

用户明确授权后，在一次性 CI job 中用合成或可清理、且已完成 TC ID
关联的测试运行常态写回命令（不要加 `--dry-run`）：

```bash
CI=true TC_SIDECAR_STRICT=1 python3 test/scripts/gen_report.py \
  --config test/.report-config.json --run-tests --as bot
```

只有命令成功退出、目标 TC 的状态/信息流转和报告都已更新、且输出中没有
`91403`，才算写路径验证通过。合成记录的删除或其他清理仍交给
`test-artifact-management` + `lark-base`，先精确确认记录，再取得用户的删除授权。
未完成这次真实写回时，Phase 3 仍是 preflight-ready，不是 complete。

---

## 一句话决策表

| 你现在 | 调谁 |
|---|---|
| 拿到空 git 仓，第一件事 | `worktree-isolation` |
| 仓里没 AGENTS.md | `agents-file-coverage-gate --fix` |
| 不知道这仓做什么、要不要做 | `product-rd-workflow` |
| 决定用 Python 后端 | `python-service-architecture` + `python-service-dev` |
| 决定用 React/Vue Web | `web-react-dev`（vitest 变体） |
| 决定用小程序 | `miniapp-product-dev`（Taro / `node --test`） |
| 决定用 Flutter/RN | `app-cross-platform-dev`（当前 skill 无 CI 模板） |
| 决定用 CLI/TUI | `terminal-cli-dev`（当前 skill 无 CI 模板） |
| 要 pytest/vitest 接进来 | `testing-strategy` + `test-artifact-management` |
| 要测试用例 Base 或 CI 自动反写测试结果 | `test-artifact-management`（表操作用 `lark-base`） |
| 要通用飞书目录或其他业务表 | `lark-wiki` / `lark-base` |
| 要上线发布门 | `platform-release-engineering` |
| 要监控告警 | `platform-observability` |

---

## 相关入口

- [`test-artifact-management` SKILL](../skills/test-artifact-management/SKILL.md) — 测试用例设计、Base 初始化、记录与报告链路
- [`test-artifact-management` Bitable setup](../skills/test-artifact-management/references/bitable-setup.md) — 安全复用/建表、字段和视图契约
- [`feishu-binding-handbook`](feishu-binding-handbook.md) — 全场景 × 飞书归位地图
- [`product-rd-workflow` SKILL](../skills/product-rd-workflow/SKILL.md) — 产品研发主路由
- [`testing-handbook`](testing-handbook.md) — 测试策略入口

---

## 已知差距

| 差距 | 影响 | 临时解法 | 长期方案 |
|---|---|---|---|
| Phase 1 owner skill 不保证 init 出最小骨架 | 调用时要自己说清栈/模板 | 调用时给清楚 | owner skill 加 `init` 模式（不在本 skill 范围） |
| 缺"自动跑 Phase 0–3"的 meta 命令 | 要手工逐个调用多个 owner skill | 按本文清单一个个跑 | 待评估 |
