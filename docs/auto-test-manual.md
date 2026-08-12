# 自动化测试使用手册

配套《自动化测试方案》。本手册讲怎么用。

---

## 0 速查表

> 8 条命令覆盖 90% 日常。第一次接入看 §1，写代码看 §3，跑测试看 §4。

| 操作 | 命令 | 何时用 |
| --- | --- | --- |
| 初始化 | `make report-init [BITABLE_URL=...]` | 项目装好 Makefile 后首次接入 |
| 跑测试 + 出报告 | `make report-run` | 日常每次 |
| 看现有用例 | `make inventory` | 写新用例前 |
| 查下一个可用 ID | `gen_report.py --next-id` | 多人并行加用例避免撞号 |
| 校验编排 | `make report-validate-matrix MATRIX=...` | matrix 改后 |
| 改用例后查漂移 | `make report-diff-md MD=...` | 直接在多维表格改后 |
| 找孤儿用例 | `make report-orphans` | 周期性检查 |
| 误标恢复 | `gen_report.py --unfreeze IDs --unfreeze-reason "..."` | 误标废弃后 |

## 按角色找

| 你是谁 | 看哪些段 |
| --- | --- |
| 第一次接入项目（开发） | §1 全部 → §3 写测试代码 → §4 跑+报告 |
| 写测试用例的（QA / PM） | §2.5 QA / PM 工作流 + §0 速查表 |
| 日常开发 | §0 速查表 + §3 + §4 |
| 维护 | §5 维护 + §6 FAQ |
| CI 维护 | §1.0 路径与依赖 + §4.2 GitLab + §6.1 CI 类 |

---

## 1. 新项目初始化

> 6 步：装依赖 → 决定路径 → 初始化配置 → 装辅助库 → 配 suite → 跑一次。第一次接入约 30 分钟。

### 1.0 装依赖（Step 0，必做）

> 原则：所有脚本与辅助库**复制到项目仓库**，不依赖任何全局路径。仓库版本就是真相，CI runner 不用装 ccl-skills。

**标准 layout**（除非项目用 `GEN_REPORT` / `TC_SIDECAR` / pytest pythonpath 覆盖，默认按这个放）：

```
项目根/
├── Makefile                         # 包含 report-init / report-run 等 target
├── .gitlab-ci.yml                   # CI 模板
└── test/
    ├── scripts/gen_report.py        # ← 从 ccl-skills 复制
    ├── tc.{py,go,ts,dart}           # ← 按栈选一个复制
    ├── .report-config.json          # 配置（commit）
    ├── cases/all.md                 # 用例 md 镜像
    ├── cases/test-matrix.md         # 测试矩阵
    └── results/                     # JUnit + tc-map.jsonl + last-run.json（.gitignore）
```

**3 件事**：

1. **复制脚本与辅助库到项目**（一次性）。模板源是 ccl-skills 仓库检出，下面用 `$CS` 指它的根目录（只装了 plugin、手上没有检出时，按[贡献指南](CONTRIBUTING.md)的「找源仓库」段先克隆）：

   ```
   源：$CS/skills/test-artifact-management/references/
       gen_report.py             → test/scripts/gen_report.py
       tc_helpers/tc.{py,go,ts,dart}  → 按栈选一个，复制到 test/tc.{py,go,ts,dart}
       makefile-template.md      → 按内容生成 / 追加项目 Makefile
       bitable-setup.md          → 参考用
       ci_templates/gitlab-ci.yml → .gitlab-ci.yml（或 include）
   ```

   模板默认 `GEN_REPORT ?= test/scripts/gen_report.py`，开箱即用。

2. **复制 Makefile target**。如果项目已有 `Makefile`，按 `makefile-template.md` 的 5 态矩阵增量追加 `# Report` 区段；如果项目没 Makefile，直接生成完整版。

3. **装 lark-cli + 登录飞书**（首次或换机器）：

   ```bash
   npm install -g @larksuiteoapi/lark-cli
   lark-cli auth login --domain base --scope "base:app:create base:table:read base:table:create base:field:read base:field:create base:field:update base:view:write_only base:record:create base:record:read base:record:update"
   lark-cli auth login --domain docs --scope "docx:document:create docx:document:update"
   ```

**怎么拉模板更新**：ccl-skills 后续会修 bug / 加功能。拉取节奏：

```bash
CS=/path/to/ccl-skills          # 你本地的 ccl-skills 检出
# 看新版与项目副本的差异
diff -u test/scripts/gen_report.py "$CS"/skills/test-artifact-management/references/gen_report.py
diff -u test/tc.py "$CS"/skills/test-artifact-management/references/tc_helpers/tc.py
# 觉得需要：直接 cp -i 覆盖；在 commit 里说明拉了什么
```

约定：每 1-2 个迭代周期由测试 owner 跑一次 diff，决定是否拉更新；CI 不自动拉（避免 supply-chain 风险）。

### 1.1 决定路径

| 你的情况 | 走哪条 |
| --- | --- |
| 需要跨人协作 + 用例管理 + 飞书报告 | **多维表格模式** |
| 只想要 JUnit 摘要报告（无需 TC 管理） | **简化模式** |

### 1.2 初始化配置

**简化模式**：
```bash
make report-init                # 不传 BITABLE_URL
```

**多维表格模式**：由 `test-artifact-management` 使用 `lark-base` 复用或初始化一张测试用例 Base，再 init。已有 Base URL 或 `.feishu/project.yaml` 中有可用标识时优先复用；缺失时只创建测试用例资源，不顺带创建项目 Wiki 或其他业务表。

> ⚠️ `make report-init BITABLE_URL=...` 只解析 URL 写入 `base_token` / `table_id`，**不会自动创建多维表格、字段、视图**。<br>
> 第一次用多维表格模式前，照 `test-artifact-management/references/bitable-setup.md` 装好：复用或创建测试用例 Base → 加 12 个字段（用例ID、模块、功能点、优先级、测试层级、测试类型、前置条件、操作步骤、预期结果、状态、跟进人、信息流转）→ 改默认视图名 → 加分组视图。完成后再：
> ```bash
> make report-init BITABLE_URL="https://xxx.feishu.cn/base/BASxxx?table=tblxxx"
> ```

### 1.3 装辅助库

按栈把 `tc_helpers/tc.{py,go,ts,dart}` 复制到项目里。

Python 还要在 `pyproject.toml` 加：
```toml
[tool.pytest.ini_options]
pythonpath = ["test"]
addopts = ["-p", "tc"]
```

### 1.4 配 `test_suites`

`test/.report-config.json`：

```json
{
  "base_token": "BAS...",
  "table_id": "tbl...",
  "report_doc_url": "",
  "test_suites": [
    {
      "name": "unit",
      "layer": "unit",
      "test_type": "api-automation",
      "command": "pytest tests/ --junit-xml=test/results/junit.xml --cov --cov-report=xml:test/results/coverage.xml",
      "results_file": "test/results/junit.xml",
      "coverage_file": "test/results/coverage.xml"
    }
  ]
}
```

> ⚠️ **隐性契约**：`test_suites[].command` 必须按 `results_file` 列的路径输出 JUnit XML。Makefile 里的 `test` target 跑的命令产出的 XML 路径，必须和这里一致。否则 `make report-run` 会报"基础设施失败"。
> `test_suites[].layer` 用于矩阵验证，`test_suites[].test_type` 用于按执行形态出报告统计；推荐从第一版配置就写上，避免后面补录。

**多栈单仓库（Python + Go + TS 在一个 unit 里）**：每栈一个 suite，每栈一个独立的 sidecar（`TC_SIDECAR` 指向不同文件），跑完 cat 起来给 gen_report.py。例子：

```json
{
  "test_suites": [
    {
      "name": "py-unit",
      "layer": "unit",
      "test_type": "api-automation",
      "command": "TC_SIDECAR=test/results/tc-map.py.jsonl pytest tests/ --junit-xml=test/results/py.xml",
      "results_file": "test/results/py.xml"
    },
    {
      "name": "go-unit",
      "layer": "unit",
      "test_type": "api-automation",
      "command": "TC_SIDECAR=test/results/tc-map.go.jsonl mkdir -p test/results && go test ./... -v 2>&1 | go-junit-report > test/results/go.xml",
      "results_file": "test/results/go.xml"
    },
    {
      "name": "ts-unit",
      "layer": "unit",
      "test_type": "ui-automation",
      "command": "TC_SIDECAR=test/results/tc-map.ts.jsonl npx vitest run --reporter=junit --outputFile=test/results/ts.xml",
      "results_file": "test/results/ts.xml"
    }
  ]
}
```

Makefile 加一步合并 sidecar（gen_report.py 只读单文件）：

```makefile
test:
	mkdir -p test/results
	rm -f test/results/tc-map.*.jsonl test/results/tc-map.jsonl
	$(MAKE) test-py test-go test-ts
	cat test/results/tc-map.*.jsonl > test/results/tc-map.jsonl

test-py:  ; TC_SIDECAR=test/results/tc-map.py.jsonl pytest ...
test-go:  ; TC_SIDECAR=test/results/tc-map.go.jsonl go test ...
test-ts:  ; TC_SIDECAR=test/results/tc-map.ts.jsonl npx vitest run ...
```

**单仓库多 unit**（monorepo）走另一条路：一 unit 一份配置 + 一个多维表格 + 一份飞书报告，根 Makefile `$(MAKE) -C <unit> ...` 委派，不合并报告。

### 1.5 第一次跑

```bash
make report-run
```

- **多维表格模式**：自动创建飞书报告文档，URL 写回配置
- **简化模式**：报告打 stdout（设了 `report_doc_url` 时写到该飞书文档）

---

## 2. 日常：写用例

### 2.1 新功能（从 0 新建）

1. 选源（需求 / Figma / 代码 / API 契约）
2. test-artifact-management 拉源 → 写用例表 → 入多维表格 + `test/cases/all.md`
3. 同时写 `test/cases/test-matrix.md`：模块 × 测试层，每格列用例 ID，阻塞格写原因 + owner

> 写每条用例时不确定该用什么经典方法（EP / BVA / 决策表 / 状态转移 / Pairwise / Exploratory+SBTM / Soap Opera / CRUD / Visual Regression / Error Guessing / Checklist / Syntax）？看 `test-artifact-management/references/classical-test-design-techniques.md` — 11 个经典 / 常用方法 + 何时用 / 何时不用 + 在本 scheme 怎么落 + 例子。

### 2.2 迭代（增量）

> ⚠️ 先 `make inventory` 看现有用例，否则会重复造。

按文档说法分类：

| 文档说 | 现有用例 | 操作 |
| --- | --- | --- |
| 新增 | 无 | NEW：续编 ID 入多维表格 |
| 调整 | 有 | UPDATE：改操作步骤/预期结果，追加信息流转 |
| 下线 | 有 | DEPRECATE：状态改 `废弃` + 触发测试代码级联 |
| 已有未变 | 有 | NO-OP：跳过 |

### 2.3 bug 回归

1. 先 `defect-diagnosis` 出 RCA
2. test-artifact-management 写 P0 `[回归]` 用例（操作步骤抄 bug 复现 / 预期结果 = expected / 信息流转留 RCA 链接）
3. 写测试代码标 `tc("TC-XX")`

### 2.4 竞态 / 不可稳定复现

| 字段 | 内容 |
| --- | --- |
| 功能点 | `[回归][race]` + 标签 |
| 前置条件 | 触发包络（并发数 / 缓存冷 / 网络延迟 / db pool） |
| 操作步骤 | 压力参数（M 轮 × K 并发 + seed） |
| 预期结果 | 不变式断言（不是单一输出） |
| 信息流转 | RCA 链接 + flake budget（容忍重试比例） + 重现 seed |

### 2.5 QA / PM 工作流（不写代码）

不写测试代码也能用这套，做下面 4 件事：

1. **接需求 → 写用例**：参照 §2.1，把功能拆成用例填多维表格的 12 个字段（用例ID 续编 / 模块 / 功能点 / 优先级 P0/P1/P2 / 测试层级 / 测试类型 / 前置条件 / 操作步骤 / 预期结果；状态默认"未测试"；跟进人 / 信息流转初始化 `[姓名 日期] 用例初始化`）
2. **预占用例 ID**：跟开发并行写用例时，先 `make inventory` 看每个模块当前最大 ID，再续编，避免撞号
3. **执行后改状态**：手动 / 自动跑完后，直接在多维表格 UI 改状态（通过 / 失败 / 阻塞 / 跳过），信息流转追加 `[姓名 日期] 测试结论`
4. **配合开发挂钩**：QA 写完用例 → 通知开发在测试代码里标 `tc("TC-XX")`（开发看 §3）

PM 主要看的：发布建议（飞书报告底部，✅/⚠/❌）+ "P0 未通过明细" + "📋 覆盖与残余风险"。

**QA / PM 的"我完成了"清单**（不必等开发确认）：

- [ ] 这次需求里所有功能点都有用例 ID 入了多维表格
- [ ] 每条用例 12 个字段填齐（用例ID / 模块 / 功能点 / 优先级 / 测试层级 / 测试类型 / 前置条件 / 操作步骤 / 预期结果 / 状态=未测试 / 跟进人 / 信息流转初始化）
- [ ] `test/cases/test-matrix.md` 这次涉及的模块至少有一格列了用例 ID；阻塞格写了 reason + owner
- [ ] 已通知开发"需要在测试代码里挂这些 TC ID"（列清单或评论 @ 到 PR）
- [ ] 下次报告出来后，回看 "P0 未通过明细" + "📋 覆盖与残余风险"，没遗漏自己的用例

---

## 3. 日常：写测试代码

> 原则：所有栈都用辅助库挂用例 ID，**不要内嵌函数名**。<br>
> 注册时（标记 / 包装）写映射文件，**跑代码时不丢 skip**。

### 3.1 Python (pytest)

```python
# tests/test_login.py
import sys
import pytest

@pytest.mark.tc("TC-SY-001")
def test_login_success():
    ...

@pytest.mark.tc("TC-SY-002")
@pytest.mark.skipif(sys.platform != "linux", reason="requires linux")
def test_env_only():
    ...                          # skip 也会记录到映射文件
```

### 3.2 Go

```go
// internal/auth/login_test.go
import "yourrepo/internal/testkit/tc"

func TestLoginSuccess(t *testing.T) {
    tc.Mark(t, "TC-SY-001")      // ⚠️ 必须第一行
    if runtime.GOOS != "linux" {
        t.Skip("requires linux")  // Mark 之后才 Skip
    }
    // ...
}
```

> ⚠️ **包装层用 `MarkAt`**：项目把 `Mark` 又包了一层？必须改 `tc.MarkAt(t, 1, ids...)`，否则包名解析到包装层的包，永远不会关联 JUnit。<br>
> ```go
> // internal/testkit/tcsmoke/smoke.go
> func Smoke(t *testing.T, ids ...string) {
>     t.Helper()
>     tc.MarkAt(t, 1, ids...)    // 1 = 包装层自己占 1 层
> }
> ```

### 3.3 Vitest / Jest

```typescript
// test/auth.test.ts
import { test, describe } from 'vitest'
import { createTcSuite } from './tc'
const { tcTest, tcDescribe } = createTcSuite(test, describe)

tcDescribe('Auth', () => {
  tcTest('TC-SY-001', 'login', () => { /* ... */ })
  tcTest.skip('TC-SY-002', 'wip', () => { /* ... */ })
  tcTest.skipIf(!process.env.LIVE)('TC-SY-003', 'live only', () => { /* ... */ })
  tcTest.each([1, 2, 3])('TC-SY-004', 'row %s', (n) => { /* ... */ })
})
```

> ⚠️ **必须用 `createTcSuite(test, describe)` 工厂**（要传 describe），不要只用 `createTcTest(test)`；否则嵌套 describe 的路径丢失。

### 3.4 Dart / Flutter

```dart
// test/login_test.dart
import 'tc.dart';

void main() {
  tcTest(['TC-SY-001'], 'login success', () { /* ... */ });
  tcTest(['TC-SY-002'], 'wip', () { /* ... */ }, skip: 'pending');
}
```

> ⚠️ **`flutter test --machine` 输出 JSON 不是 JUnit XML**：要装 `dart pub global activate junitreport`，Makefile 里管道转换：<br>
> `flutter test --machine | tojunit --output test/results/flutter.xml`

### 3.5 e2e / 浏览器 / 真机测试

e2e 测试（Playwright / Cypress / Appium / Espresso / 小程序自动化等）**和上面一样在注册时挂 `tc()`**，产出 JUnit XML 后进同一份报告、同样卡 MR——harness 层无关，不用为 e2e 单独搭。

只要：测试框架能出 JUnit XML（不能就像 Flutter 那样管道转换），并在 `test_suites` 里配成一个 suite（可标 `blocking`，或用 opt-in marker 与快测试分开跑）。

**怎么写 e2e、断言什么、各端 smoke、blocking 与 unavailable 补救** → 见 [写测试与测试用例手册 §自动化 e2e](testing-handbook.md) + `testing-strategy`。本手册只管它怎么挂进 harness。

---

## 4. 跑 + 看报告

### 4.1 本地

```bash
make report-run
```

行为：跑 `test_suites` → 关联映射文件 → 写多维表格状态 + 飞书报告 → 保存 `last-run.json` → 退出码（失败 / 基础设施缺失 → 1）

### 4.2 GitLab CI

模板：`test-artifact-management/references/ci_templates/gitlab-ci.yml`

**接入两步**：
1. 替换所有 `<unit>` 占位符为单元目录名（web / app / services/auth ...）
2. 加 CI/CD 变量（masked + protected）：
   - `LARK_BOT_APP_ID`
   - `LARK_BOT_APP_SECRET`
   - `GITLAB_API_TOKEN`（scope = api，发 MR 评论用）

**模板已配好**：
- `resource_group` 序列化同 (unit, branch)
- cache 按 (unit, branch) 稳定 key + 默认分支兜底
- `after_script` 红 / 绿都发 MR 评论
- `TC_SIDECAR_STRICT=1` 默认开

> ⚠️ **不要把 `report-run` 写成 `report-run: test` 前置依赖**！red `make test` 会短路 make，gen_report 不跑，`--fail-on` 失效。模板用 `-$(MAKE) test` 写在 body 里。

### 4.3 报告内容

1. 总览（含代码覆盖率 + 与上次跑对比）
2. 按模块统计
3. P0 未通过明细
4. P1 / P2 失败明细
5. 未链接 TC 的测试统计（没标 `tc(...)` 的测试集合）
6. 孤儿 TC ID（测试标了 ID 但多维表格没记录 / 已废弃）
7. 📋 覆盖与残余风险
8. 发布建议（✅ / ⚠ / ❌）

### 4.4 MR 评论格式

评论正文由 `make pr-summary` 产出（`gen_report.py --pr-summary`）：打印一段短摘要到 stdout，含总览 + 与上次跑的对比，CI 里把它贴成评论即可，不用自己拼字符串。

红、绿都发：
```
### 🧪 自动化测试结果

通过 45 / 总 48 · ❌ 失败 2 · 📊 覆盖率 82.3% (412/501)

🔴 本次新增失败 / 阻塞（2）：
- `TC-SY-005`
- `TC-AU-003`
```

基础设施失败时顶部加 🚨 banner。

---

## 5. 维护

### 5.1 改用例步骤

```bash
# 直接在多维表格 UI 改 → 查本地 md 是否漂移
make report-diff-md MD=test/cases/all.md
```

### 5.2 废弃用例

```
1. 多维表格状态改 `废弃`，信息流转留废弃原因
2. grep 该用例关联的测试：
   grep -rn 'tc(.*"TC-XX-001"\|tc\.Mark.*"TC-XX-001"\|tcTest.*"TC-XX-001"' .
3. 用各端导入图命令判断业务代码是否还在用：
   - Python: grep "from <pkg>" 找 caller
   - Go:     go list -f '{{.Imports}}' ./...  找 importer
   - TS:     npx madge --dependents src/path/Module.tsx
   - Dart:   dart analyze + grep imports
4. 业务代码已删 → 同 commit 删测试；仍在用 → 不动
```

### 5.3 误标恢复（废弃 → 未测试）

> ⚠️ `废弃` 是永久终态，自动化不会动。误标只能用 `--unfreeze`：

```bash
python test/scripts/gen_report.py \
  --config test/.report-config.json \
  --unfreeze "TC-SY-001,TC-SY-003" \
  --unfreeze-reason "误标恢复：功能未下线"
```

`--unfreeze-reason` 必填。

### 5.4 校验编排

```bash
make report-validate-matrix MATRIX=test/cases/test-matrix.md
```

报 3 类漂移：matrix 列了多维表格没的 / 多维表格有但 matrix 没列的 / matrix 列了 `废弃` 的。

**这个 target 只打印、退出码 0、不挡 CI / merge**（模板里它自己会打印 `NOT A GATE`）。要让 CI 真的挡，用阻断变体，别自己 grep stdout：

```bash
make report-validate-matrix-gate MATRIX=test/cases/test-matrix.md
```

它跑测试 + 阻断式校验。注意它的门是分层的：**用例存在性和多维表格同步一直是阻断的；层级覆盖只有在给测试套件配了层级元数据之后才阻断**。`report-validate-matrix-report` 是非阻断版的别名，跟不带后缀的那个等价。

### 5.5 检测孤儿用例

```bash
make report-orphans
```

找测试代码标了 ID 但多维表格没记录 / 已废弃的。

### 5.6 看下一个可用 ID

```bash
python test/scripts/gen_report.py --config test/.report-config.json --next-id
```

打印每个模块下个可用 TC-XX-NNN，多人并行加用例避免撞号。

---

## 6. FAQ

### 6.1 CI 行为

**Q: CI 显示绿，但测试明明红了？**

A: Makefile 是不是用了 `report-run: test`（错的前置依赖）？必须 `-$(MAKE) test` 写在 body 里，否则 make 被红测试短路，gen_report 不跑，`--fail-on` 失效。

**Q: PR 上想看回归差异但 CI 红时不发评论？**

A: 看 GitLab runner log 里 after_script 的 stderr。缺工具（python / curl / jq）会跳过；MR token 没 `api` scope 也会失败。模板已加 `command -v` 探针 + `|| true` 保证不再 fail，但缺工具会直接 skip。

### 6.2 首次跑就 fail（按发生频率排）

**Q: `lark-cli: command not found`？**

A: §1.0 第 3 件事没做。`npm install -g @larksuiteoapi/lark-cli`。

**Q: `lark-cli` 报 `missing_scope` / `unauthorized`？**

A: §1.0 的 `auth login` 没跑全。base 与 docs 两次都要。验证：`lark-cli auth check --scope "base:record:read"`。

**Q: `make report-run` 报 `gen_report.py: No such file`？**

A: §1.0 没复制脚本到项目。把 `gen_report.py` 复制到 `test/scripts/gen_report.py`。模板默认 `GEN_REPORT ?= test/scripts/gen_report.py` 找这个路径。

**Q: 多维表格 `+record-upsert` 报 `field not found` / 创建记录失败？**

A: `make report-init BITABLE_URL=...` 只解析 URL，不创建字段。先按 `bitable-setup.md` 装好 12 个字段（用例ID / 模块 / 功能点 / 优先级 / 测试层级 / 测试类型 / 前置条件 / 操作步骤 / 预期结果 / 状态 / 跟进人 / 信息流转）再 init。

**Q: `make report-run` 报"基础设施失败：N 个测试套件未产出 JUnit XML"？**

A: `test_suites[].command` 跑出来的 XML 路径和 `test_suites[].results_file` 不一致。检查 `pytest --junit-xml=...` / `go-junit-report > ...` / `tojunit --output ...` 的输出路径。

**Q: 所有测试都报"未链接 TC"？**

A: 映射文件没关联到 JUnit。检查：
- Python：`pyproject.toml` 有没有 `addopts = ["-p", "tc"]`
- Go：用包装层时改 `tc.MarkAt(t, n, ids...)`，n = 你在测试和 `MarkAt` 之间包了几层函数（直接调 1 层包装函数 → n=1；再包一层 → n=2）
- Vitest：必须用 `createTcSuite(test, describe)`（要传 describe），不要只 `createTcTest(test)`
- 通用：Makefile `test` target 有没有 `rm -f $(TC_SIDECAR)`？上次跑的 stale entries 会让本次 join 不上

### 6.3 项目结构

**Q: monorepo 多 unit 怎么办？**

A: 一 unit 一份 `.report-config.json` + 一个多维表格 + 一份飞书报告。根 Makefile 用 `$(MAKE) -C <unit> ...` 委派；不要合并报告。

**Q: 测试不需要关联用例 ID 可以吗？**

A: 可以。不进多维表格报告，但会进"未链接 TC 的测试"段。单元 / 边界 / 内部不变式测试默认就这样，不强求关联。

### 6.4 状态映射

**Q: 同一个用例被多个测试 cover，报告状态怎么算？**

A: 悲观合并：`失败 > 阻塞 > 跳过 > 通过`。任何一个测试失败就标整个用例失败。跨套件同理。

**Q: pytest `@skip` 我想让它映射到 `阻塞` 还是 `跳过`？**

A: 看 reason 关键词。含 `requires / needs / no driver / no device / service unavailable / platform / linux / windows / darwin / fixture not ready / environment / credential` → `阻塞`（环境性）；其他 → `跳过`（人工排除）。

**Q: 用例越来越多，信息流转字段会爆吗？**
A: 默认保留最近 100 条，更早的丢。要全保留设 `TC_INFO_KEEP=0`（受多维表格单字段字数上限约束）。

**Q: `last-run.json` 报告全是"新失败"？**

A: Schema 升级了，冷启动一次后正常。`load_last_run` 见 schema_version 不一致就当冷启动。

---

## 配套文档

- **设计原理**：见《自动化测试方案》
- **模板源（参考用，复制到项目即可）**：ccl-skills 仓库的 `skills/test-artifact-management/` —— 包含 `SKILL.md`（完整规则）、`references/` 下的 `tc-marker-conventions.md`（辅助库详解）、`bitable-setup.md`（多维表格初始化）、`makefile-template.md`、`ci_templates/`（CI 模板）、`gen_report.py`（脚本源）、`tc_helpers/`（4 端 helper 源）
- 多源融合、Source A-E、测试矩阵、残余风险段：test-artifact-management SKILL.md 对应章节
