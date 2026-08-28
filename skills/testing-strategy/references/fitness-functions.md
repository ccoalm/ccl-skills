# Architecture Fitness Functions

把架构 invariants 写成**自动化测试**，每次 build / CI 跑 — 架构不再靠口头约定 + 文档守护。

不替代普通单测 / e2e；这是**结构性约束**的测试（无循环依赖 / 分层不越界 / latency budget / etc）。

## 外部来源

- **Neal Ford / Rebecca Parsons / Patrick Kua**, *Building Evolutionary Architectures* (O'Reilly, 1st ed 2017) + **+ Pramod Sadalage** (2nd ed Dec 2022) — fitness function 定义 + 分类
- **ThoughtWorks Tech Radar** — "Architecture Fitness Functions"（Trial → Adopt）
- **ArchUnit / NetArchTest / Dependency-Cruiser** — 工具示例

---

## §1 定义

**Fitness function**：可执行的测试 / 检查，判断**架构是否仍符合某个所声明的不变量**。失败 = 架构 drift / 违反预设。

与普通测试区别：
- **单测 / e2e**：测**业务正确性**（"用户能否完成 X 流程"）
- **fitness function**：测**结构正确性**（"X 模块是否仍是无依赖 leaf；p99 是否仍 < 100ms；DAL 是否仍唯一 DB 访问出口"）

---

## §2 分类（精选自 Ford et al. taxonomy）

Ford 等原书有更多维度（Temporal / Intentional vs Emergent / Domain-specific / Coverage / Proactivity 等；2nd ed 2022 reframe 为 Scope/Cadence/Result/Invocation/Proactivity/Coverage）。本 ref 只取最高 ROI 的 4 个常用维度：

| 维度 | 选项 | 含义 |
|---|---|---|
| **Atomic vs Holistic** | atomic | 测单个 attribute（如纯 latency）|
|  | holistic | 多 attribute 组合下的行为（latency 在 50% CPU 时仍 < 100ms）|
| **Triggered vs Continuous** | triggered | CI / commit / merge 触发 |
|  | continuous | 生产持续监控（与 §5 集成）|
| **Static vs Dynamic** | static | 无需运行代码（grep / AST / dep graph）|
|  | dynamic | 需运行（load test / chaos）|
| **Automated vs Manual** | automated | CI 卡点 |
|  | manual | code review checklist / 季度审计 |

本 ref 重点：**triggered + static / dynamic + automated**（最高 ROI），manual 类只在 automated 不可行时用。

---

## §3 典型 fitness function 例

### 3.1 模块依赖 / 分层（static + automated）
- 无循环依赖：`go vet` / `dep-cruiser` / ArchUnit `slicesShouldBeFreeOfCycles()`
- 分层不越界：`domain` 不依赖 `infrastructure`；`infrastructure` 不能 import `web` handler
- 实现：ArchUnit (Java) / dep-cruiser (JS/TS) / go-arch-lint (Go) / pytest-arch (Python)

### 3.2 数据访问出口（static + automated）
- **Invariant**：DB 操作只能经特定模块（如 `repository/` 包）；HTTP 出口只能经特定 client 包
- **Go 例**：linter 检查其它包不能 `import "database/sql"` / ORM 包；业务代码不能 `import "net/http"`
- **其它栈类比**：Python — 检查非 DAL 模块不 `import sqlalchemy`；JS/TS — eslint rule 阻 `import 'pg'` 在 service 层外

### 3.3 性能 budget（dynamic + automated）
- p99 latency < 100ms：CI 跑 benchmark / load test 卡 budget
- bundle size < N kB：webpack-bundle-analyzer / size-limit CI 卡
- cold start < N ms：benchmark + 阈值（适用 serverless / CLI / mobile startup / container scale-to-zero / plugin host；常驻 backend 服务不必）

### 3.4 复杂度上限（static + automated）
- 单 function 圈复杂度 ≤ 10：gocyclo / radon / eslint complexity rule
- 单文件行数 ≤ 500：linter rule
- API 总数 ≤ N：API gateway config 检查

### 3.5 安全 invariants（static + automated）
- 无硬编码 secret：gitleaks / trufflehog / 自写 grep
- HTTPS only：lint config
- SQL 不拼接：linter（sqlc / 检查 ORM 使用）

### 3.6 接口稳定性（dynamic + automated）
- OpenAPI breaking-change 检测：oasdiff / openapi-diff
- proto breaking-change：buf breaking
- DB migration 向后兼容：linter（pt-online-schema-change 兼容性）

---

## §4 实现路径

### 4.1 起手 — 3 个原则

1. **每个 fitness function 必有 owning decision record**（ADR 或同等 reason 记录）：function 测的是哪个决定的 invariant？没记录 = function 易被随便删。新发现的 guardrail 可先以 reason comment 起步，**当它编码 material 架构 invariant 时 promote 到 ADR**
2. **Fail loud, fail early**：CI 红，不只是 warning；本地 pre-commit 也跑
3. **每个 function 必有名字 + reason**：commit message / config 写明"why this function exists"，避免后人删时不知 trade-off

### 4.1.1 规范到健康度检查

团队研发规范要能落成项目健康度检查，而不是只靠人工 review。把每条规范先分类：

| 类型 | 适合检查的内容 | 执行器 |
|---|---|---|
| Deterministic | 文件/目录、IDL、生成产物、配置、依赖锁、CI、覆盖率、命令、日志字段、trace 字段 | 脚本、lint、测试、CI |
| Agent review | 分层是否绕过、领域边界、组件职责、测试有效性、Spec 对齐、异常/降级语义 | bounded agent prompt + evidence packet |
| Manual | 需要真实账号、真机、外部审批、生产窗口或人工判断的项 | 手工证据 + owner + 到期时间 |
| Not automatable yet | 当前没有稳定输入或工具的项 | 缺口记录 + 自动化计划 |

健康度报告至少包含：规则 id、规范来源、severity、检查类型、执行命令或 agent prompt、证据、结果、owner、CI 行为。结果只能是 `pass`、`fail`、`blocked`、`inconclusive` 或 `not_applicable`。CI 只卡 `blocker` 或团队已声明卡关的规则；warning/info 进入报告并要求责任人，不伪装成通过。

脚本负责事实，agent 负责判断。不要让 agent 去猜文件是否存在、覆盖率是多少、CI 是否配置；也不要让脚本用 grep 代替架构判断。任何检查类型缺少具体证据时都不得写成 `pass`。`agent_review` 没有具体证据、超时、范围不足或只返回泛泛结论时，结果必须是 `inconclusive`。`manual` 在人工证据到位前必须是 `blocked` 或 `inconclusive`；`not_automatable_yet` 必须是 `blocked` 或 `not_applicable`，并记录缺口和自动化计划。

字段存在不等于链路正确。grep/lint 只能证明日志字段、trace 字段、请求头或配置项存在；跨 HTTP/RPC/MQ/worker/client 的传播必须由集成测试、E2E/host smoke、运行时观测证据，或明确的 `agent_review` 判断补足后才能写成 `pass`。

**grep 不够时优先 AST；标准库 AST 是常见零依赖路径——但别当反射、也别因没装第三方工具就退回 grep smell 或 defer 成 `not_automatable_yet`。** 代码形态类确定性检查（"边界是否返回 ad-hoc error dict"、"导出函数是否传 ctx"等）用 grep 既会被注释/字符串内同形文本误匹配、又易被改写绕过，只能算 `smell-grep / advisory`（命中=待查、干净≠合规）。要做成 `deterministic`：**先看现有工具/lint 选项 + owner 决定**；没有合适第三方工具时，**Python `ast`、Go `go/ast` 是 stdlib 零依赖路径**（JS/TS 的 TypeScript compiler API / ESLint / Babel parser **不是 stdlib**，仅在仓里已装时用，否则记一个 tooling 决定、别号称零依赖）。自写检查器**有真实成本**（正确性、parser 边界、维护——看似简单的检查可能要多轮才稳），只对**窄的、高价值的枚举不变量**这么做，并配 test harness（正例命中、反例不误报、坏 scope 报 `inconclusive` 不报 clean）；需要完整类型/数据流分析才能判的形态，**保持 `blocked`/`inconclusive` + 自动化计划**，别硬 ship 一个半成品 linter。AST 只对**枚举形态**确定，把覆盖边界（抓哪些、哪些是 accepted residual）写进文档与 result-schema，干净跑只代表"未发现枚举形态"。

### 4.1.2 语言基本规范 conformance — 示例 fitness functions

承载 `service-language-basics` 规范的可机判子集。本轮 ship **确定性 AST 检查**（stdlib，不依赖 semgrep/ast-grep）：解析 AST → 不误匹配注释/字符串里的同形文本、能抓 grep 抓不到的形态。**确定性边界（诚实）**：只对下列**枚举形态**确定；"是否真伪造错误 / 是否真传 ctx"语义上不可判定，干净跑 = "未发现枚举形态"，**非完全合规**。ccl-skills 只 ship 可采纳件；**机械 firing 发生在消费仓**（接 pre-commit / CI），ccl-skills 对外部仓无强制力 → opt-in，未采纳前对应规范仍是 salience + 人 review 兜底。

**LB-1 — Python 在边界用返回值伪造错误**（check_type：`deterministic`，限枚举形态）

- owner：`python-service-dev`；severity：warning → blocker（消费仓采纳后定）。
- 脚本：`python3 skills/testing-strategy/scripts/lang-basics-ast-check.py <transport_paths>`（stdlib `ast`，零三方依赖）。配套 test harness `lang-basics-ast-check.test.sh`。
- scope：只传 transport / handler / view / router 路径；**pure / domain 层豁免**（那里允许 `Result` / `Either`）。
- 抓的形态（含旧 grep 抓不到的）：`{"success"/"ok": False}`（任意引号）、`{SUCCESS: False}`（常量键）、`dict(success=False)`、`return (data, err/error/exc/e)`、`return (None, <msg>)`。**注释 / 字符串内同形文本不误报**（AST 不看），故无需 `# lb-allow` 抑制机制。
- 残留未覆盖（诚实）：ad-hoc `{"code":...,"message":...}`（与合法 envelope 无类型/流分析难分，不抓，避免误伤）、经变量别名传递的 error 对象；比 return root / 一层构造器 / `(body, status)` tuple 更深的嵌套或动态构造的 fake dict 不抓——这是枚举形态边界，不是 bug。
- 退出码：`1`=命中（fail）；`2`=scope 无效 / 语法错（inconclusive，绝不报 clean）；`0`=未发现枚举形态（**≠完全合规**）。
- result-schema：`{"rule_id":"py.error.boundary_return_fake","severity":"warning","check_type":"deterministic","status":"pass|fail|inconclusive","evidence":["file:line"],"owner":"python-service-dev"}`。

**LB-2 — Go ctx 传播**（check_type：`deterministic` proxy）

- owner：`go-microservice-dev`；severity：warning → blocker（按层）。
- 脚本：`go run skills/testing-strategy/scripts/lang-basics-go-check.go <dir>`（go/ast；**目录用 `go run`，单文件先 `go build`** —— `go run` 会把尾随 `.go` 当成源文件）。配套 test harness `lang-basics-go-check.test.sh`。
- 抓的形态：非 `main`/`init` 函数里调 `context.Background()` / `context.TODO()` —— 常见的"丢了 caller 的 ctx、自造 root ctx"信号（丢 cancel/deadline/trace 传播）。解析 per-file import 名，**alias（`import ctx "context"`）与 dot-import 都能抓**。`_test.go` 跳过（目录遍历与显式文件参数都跳）；`vendor`/`.git`/`testdata`/`node_modules` 跳过。
- **proxy 边界 + 已接受残留（诚实）**：低误报代理，非完整"导出 IO 函数缺 ctx 形参"检查（需 `go/types`）。**接受的残留**（修了反而误伤合法用法）：① `main`/`init` 内的闭包/goroutine 调 Background 不报（常是合法 background worker）；② 局部变量 shadow 了 context alias / dot-import 的 `Background` 名可能误报。干净跑 ≠ 每个函数都正确传 ctx。
- 退出码同 LB-1。

### 4.1.3 客户端 language-basics conformance — 示例 fitness functions

承载 `client-language-basics`（spec 006）规范的可机判子集，覆盖 `web-react-dev` / `app-cross-platform-dev` / `miniapp-product-dev` / `terminal-cli-dev` 四个客户端 surface 栈。把 Go/Python 的 language-basics（分层=依赖方向、错误契约、ctx/取消传播）映射到客户端 analog。

**关键诚实（与 005 不同的客户端现实）**：

- **生态 linter 是默认执行器，非组织自写脚本**。不像 Go/Python（`go/ast`/`ast` stdlib 零依赖、且 LB-1/LB-2 抓的是 `go vet`/`ruff` 漏掉的窄不变量），客户端 language-basics **多数已被成熟生态 linter 覆盖**：JS/TS 的 `eslint-plugin-react-hooks` + `@typescript-eslint` + `dependency-cruiser`、Dart 的 `dart analyze`+`flutter_lints`、Kotlin 的 detekt+Android Lint、Swift 的 SwiftLint。**故客户端 conformance 的 deterministic 那半 = enforce 这些生态规则的 config**，不重写成自写检查器（重复劳动 + monotonic）。
- **JS/TS / Dart / Kotlin / Swift 的 AST 都不是 stdlib**：自写检查器要么依赖消费仓 toolchain（TS compiler / custom_lint / detekt custom rule / SwiftLint custom rule）→ **记 tooling 决定，不号称零依赖**；要么退化 source-text 扫读（advisory-leaning，命中=待查）。**不 ship 半成品自写 parser**（见 §4.1.1）。
- 每栈 analyzer 默认规则集**很薄**（RN 默认仅 2 条 hooks 规则；SwiftLint 安全规则多 opt-in；Dart lints 默认 `info` 严重度不卡 CI，需 `analyzer>errors:` 升级；detekt 多条 inactive）→ **"开/升级 baseline" 本身是每栈 setup 义务**，写进消费仓 conformance config。

**A. 全栈 STD 覆盖（开/升级生态规则即可，禁自写）** — 错误处理（空/泛 catch、typed throw）+ 空安全（强解包禁令）两族全栈 STD：

| 栈 | deterministic 执行器（生态规则，需 enable/config） |
|---|---|
| web/RN(JS/TS) | `react-hooks/rules-of-hooks`·`exhaustive-deps`·`set-state-in-effect`·`error-boundaries`(v6+)；`@typescript-eslint/no-explicit-any`·`no-floating-promises`·`no-misused-promises`·`only-throw-error`(typed，需 `parserOptions.project`)；`no-empty`；tsconfig `strict`(+`noUncheckedIndexedAccess`)；dep-cruiser `forbidden`/`no-circular`、ESLint `no-restricted-imports`/`no-restricted-globals` |
| Flutter/Dart | `flutter_lints` baseline + `empty_catches`·`avoid_catches_without_on_clauses`·`only_throw_errors`·`use_rethrow_when_possible`·`unawaited_futures`·`discarded_futures`·`cancel_subscriptions`·`close_sinks`·`use_build_context_synchronously`·`avoid_dynamic_calls`；**`analyzer>errors:` 升级严重度**（关键 gotcha） |
| Android/Kotlin | detekt `exceptions/*`(SwallowedException·TooGenericExceptionCaught/Thrown·PrintStackTrace)·`empty-blocks/EmptyCatchBlock`·`coroutines/*`(GlobalCoroutineUsage·InjectDispatcher·SleepInsteadOfDelay·SuspendFunSwallowedCancellation)·`potential-bugs/UnsafeCallOnNullableType`(`!!`)·`LateinitUsage`；开 inactive 规则；Kotlin explicit-API 编译 flag |
| iOS/Swift | SwiftLint `force_try`·`force_cast`(默认) + 启用 opt-in `force_unwrapping`·`no_empty_block`·`untyped_error_in_catch`·`weak_delegate`·`private_outlet`·`implicitly_unwrapped_optional` |

权威源：react.dev / typescriptlang.org / typescript-eslint.io / dependency-cruiser；dart.dev linter-rules+effective-dart；developer.android.com architecture + detekt.dev；swift.org API guidelines + realm.github.io/SwiftLint。

**B. 本轮 ship 的 runnable 检查器**（生态无标准规则 + 高价值 + 低依赖低误报，对标 LB-1/LB-2）：

**CB-1 — terminal `no-hardcoded-ANSI`**（check_type：`deterministic`，语言无关，Python stdlib 零依赖）

- owner：`terminal-cli-dev`；权威源 clig.dev Output（capability-aware lib + `TERM=dumb`）；severity：warning → blocker（消费仓采纳后定）。
- 脚本：`python3 skills/testing-strategy/scripts/client-terminal-ansi-check.py <src-path...> [--allow=<substr>]...`。配套 test harness `client-terminal-ansi-check.test.sh`（green）。
- 抓的形态：源码字面 ESC 编码（`\x1b` / `\x1B` / `\033` / `\e` / `` / `\u{1b}` / 裸 ESC 0x1b）后跟 **CSI `[` 或 OSC `]`** 引导符——OSC 覆盖 hyperlink/OSC-52 clipboard（terminal §6 视其为安全边界）。仅扫源码扩展名（不误伤 golden/fixture）。`--allow=` 豁免渲染/ANSI 模块路径。
- 诚实边界：抓"硬编 CSI/OSC 转义字面存在"，**不**判语义（是否走 capability lib / NO_COLOR / isatty 守卫=agent-review）；只覆盖 CSI/OSC 引导符（charset `\x1b(`、DCS `\x1bP`、经变量传递的 ESC 不抓）；**不跟随 symlink 目录**（os.walk 默认）。干净跑 = 已遍历非 symlink 源树未发现硬编转义，≠完全合规。
- 退出码：`1`=命中；`2`=scope 无效/不可读（inconclusive，绝不报 clean）；`0`=未发现。
- result-schema：`{"rule_id":"terminal.ansi.hardcoded_escape","severity":"warning","check_type":"deterministic","status":"pass|fail|inconclusive","evidence":["file:line"],"owner":"terminal-cli-dev"}`。

> **miniapp `react-dom`/`TARO_ENV` conformance is executed by ESLint config, NOT a repository script** (see C). A regex/source-text Python checker for these was prototyped and **rejected**: across adversarial-challenge rounds it spawned the SAME class of new defect each round (`/*` inside a string literal flipping comment state, whitespace around `process.env . TARO_ENV`, multiline forms…) — i.e. it was re-implementing a JS lexer in regex, the half-baked-parser anti-pattern (005 §4.1.2). JS/TS already has an AST linter; the correct executor is ESLint, which gets string/comment/whitespace state right for free. (CB-1 stays a script because terminal/CLI has NO ecosystem ANSI-aware linter and a byte-scan needs no JS parser.)

**C. executor config 模板（生态 linter = 默认执行器，非仓库自写脚本）**

miniapp `react-dom` ban + DOM/BOM ban + `TARO_ENV`-confinement — repo-authored ESLint config (runs on the real AST, so string/comment/whitespace edge-cases are handled correctly; owner `miniapp-product-dev`, sources developers.weixin.qq.com js-support + docs.taro.zone envs):

```jsonc
// .eslintrc — mini-program build target (exempt H5 via an overrides block on *.h5.* / h5/**)
"rules": {
  // CB-2a: no react-dom (logic layer has no DOM); also bans react-dom/* and type-only imports
  "no-restricted-imports": ["error", { "patterns": ["react-dom", "react-dom/*"] }],
  // no DOM/BOM globals in mini-program runtime
  "no-restricted-globals": ["error", "window", "document", "navigator", "localStorage"],
  // CB-2b: TARO_ENV branching only in the adapter/platform layer — confine via an overrides block
  // that ENABLES this rule for src/**, then DISABLES it for src/adapters/** and *.{weapp,alipay,tt,...}.*
  "no-restricted-syntax": ["error", {
    "selector": "MemberExpression[property.name='TARO_ENV'][object.property.name='env'][object.object.name='process']",
    "message": "process.env.TARO_ENV branching belongs in the adapter/platform layer, not scattered"
  }]
}
```

Layering/dependency-direction (**全栈 custom 旗舰，无 out-of-box 规则**) likewise落各栈 import-ban config——JS/TS dep-cruiser `forbidden`、Kotlin Konsist/ArchUnit 或 custom detekt、Dart custom_lint、Swift custom；点禁用 `no-restricted-imports`。这些都是**消费仓 config**，由对应 client `*-dev` owner 提供/维护，不在 ccl-skills 落 runnable 脚本。

**D. backlog（named owner + 触发条件，不半 ship）**：每栈 dispose 生命周期 / 取消协作（Swift Task `isCancelled`、RN useEffect abort）/ 语义吞异常 / JS-TS finite-value 集中 / 分层自定义规则——需 AST/类型分析或各栈 toolchain，触发=该栈消费仓启用 dep-conformance CI 时拾取。

### 4.1.4 测试 smell conformance — 可判定谓词的生态执行器

承载 `test-code-authoring-patterns.md` §3 中三个可机判 test smell 的 lint 下沉：**测试内条件逻辑**（Conditional Test Logic）、**测试内 sleep**（Slow/Erratic 常见成因）、**无断言测试**。原则同 §4.1.3：生态 linter 是默认执行器，**本节不 ship 自写检查器**；无生态规则的格子如实记 agent-review（按 §3 清单人审兜底），不做半成品 parser。均为**消费仓 config**（opt-in，采纳语义同 §4.1.2），由对应 stack `*-dev` owner 提供/维护；六个 stack `*-dev` 技能从各自 verify 步指到本节，`terminal-cli-dev` 按实现语言复用 Go/Python/JS 行（Rust：实扫 rust-lang.github.io/rust-clippy/master/index.html 的 lint 索引——三列均无专用规则，`assert*` 类 lint 均为断言写法类 → agent-review；sleep 可经 `clippy::disallowed_methods`（clippy.toml 配置型，未配置不触发）列禁 `std::thread::sleep`）。

| 栈 | 条件逻辑 in test | sleep in test | 无断言测试 |
|---|---|---|---|
| JS/TS unit — Jest（web/RN/Taro 单测） | `jest/no-conditional-in-test`；辅 `jest/no-conditional-expect` | 无专用规则（实扫 github.com/jest-community/eslint-plugin-jest README rules 表）→ agent-review（可选 repo 级 core ESLint `no-restricted-syntax`——eslint.org/docs/latest/rules——禁测试内裸 `setTimeout` 等待） | `jest/expect-expect` |
| JS/TS unit — Vitest（`@vitest/eslint-plugin`） | `vitest/no-conditional-in-test` | 无专用规则（实扫 github.com/vitest-dev/eslint-plugin-vitest README rules 表）→ agent-review（可选 core ESLint `no-restricted-syntax`——eslint.org/docs/latest/rules——禁测试内裸 `setTimeout` 等待） | `vitest/expect-expect` |
| web E2E — `eslint-plugin-playwright` | `playwright/no-conditional-in-test`（recommended） | `playwright/no-wait-for-timeout`（recommended） | `playwright/expect-expect`（recommended） |
| Python — pytest | 无生态规则（实扫 docs.astral.sh/ruff/rules 的 PT 集：PT009/PT015/PT017/PT018 均为断言写法类，无「条件逻辑 in test」规则）→ agent-review | Ruff `TID251` banned-api 列禁 `time.sleep`（`[tool.ruff.lint.flake8-tidy-imports.banned-api]`；确需处 `# noqa: TID251`） | 无生态规则（实扫 docs.astral.sh/ruff/rules 的 PT 集：无「测试无断言」规则）→ agent-review |
| Go | 无生态规则（`golangci-lint help linters` v2.12.2 本机实扫：相邻仅 `forbidigo`/`testifylint`/`thelper`，均不判此类）→ agent-review | `forbidigo` pattern `^time\.Sleep$`（其 `-tests` 默认含测试文件；经 golangci-lint file-based 配置圈定/豁免非测试路径） | 无生态规则（`golangci-lint help linters` v2.12.2 本机实扫）→ agent-review |
| Android/Kotlin | 无生态规则（实扫 detekt.dev/docs/rules/ 下 comments·complexity·coroutines·empty-blocks·exceptions·libraries·naming·performance·potential-bugs·ruleauthors·style 11 页，最近仅 `CoroutineLaunchedInTestWithoutRunTest`（检测 @Test 内 runTest 外启协程），不判此类；formatting 页 404 未扫——ktlint 格式包装，无测试语义规则）→ agent-review | detekt `coroutines/SleepInsteadOfDelay`（默认启用、需 type resolution；**仅报 suspend 函数/协程块内的 `Thread.sleep`**——非 suspend 测试代码不触发 → agent-review） | 无生态规则（实扫 detekt.dev/docs/rules/ 下 comments·complexity·coroutines·empty-blocks·exceptions·libraries·naming·performance·potential-bugs·ruleauthors·style 11 页；formatting 页 404 未扫——ktlint 格式包装）→ agent-review |
| iOS/Swift 与 Flutter/Dart | 无生态规则（实扫 realm.github.io/SwiftLint/rule-directory.html 与 dart.dev/tools/linter-rules）→ agent-review | 无生态规则（实扫 realm.github.io/SwiftLint/rule-directory.html 与 dart.dev/tools/linter-rules）→ agent-review | 无生态规则（实扫 realm.github.io/SwiftLint/rule-directory.html 与 dart.dev/tools/linter-rules；SwiftLint `empty_xctest_method` 只判空测试方法、不判「有动作无断言」，不算数）→ agent-review |

jest/vitest 各规则的 recommended 覆盖面随插件版本变化——消费仓 config 里**显式启用**上列规则，以所用版本 README 为准。空格子的检索边界（诚实）：各空格子均**实扫具名官方规则清单**（清单 URL 或本机命令已写进对应格；2026-08 核验；深度=规则存在+语义匹配，未逐规则跑样例）；「无生态规则」= 该清单内未见，非全生态穷尽——新规则出现时按 A 表同款方式登记，不自写。权威源（核验 2026-08，以所用版本为准）：github.com/jest-community/eslint-plugin-jest（README rules 表）、github.com/vitest-dev/eslint-plugin-vitest（`@vitest/eslint-plugin` README）、github.com/mskelton/eslint-plugin-playwright（README rules 表 + `src/plugin.ts` recommended 配置）、docs.astral.sh/ruff/rules/banned-api 与 /settings（`[lint.flake8-tidy-imports.banned-api]`）、github.com/ashanbrown/forbidigo（README；`-tests` 默认 true）、detekt.dev/docs/rules/coroutines（SleepInsteadOfDelay 默认启用 since v1.21.0、需 type resolution）、eslint.org/docs/latest/rules（core `no-restricted-syntax`）、rust-lang.github.io/rust-clippy（master lint 索引；`disallowed_methods`）。

### 4.2 起步 sequencing
新项目从最便宜的开始上：
1. **Linter rules**（语法 / 命名 / 简单依赖）— 零启动成本，本地 IDE 即时反馈
2. **Static dep graph 检查**（无循环 / 分层）— 几分钟接入 dep-cruiser / go-arch-lint
3. **Pre-existing tools 的 invariant 模式**（gitleaks / breaking-change linter）— 1 小时接入
4. **Performance budget**（最贵 — 需要稳定 load test 环境）— 项目稳定后再上

### 4.3 与 ADR 配合
每个 ADR 的 Consequences 段如果声明了"承诺保持 X"，对应应有 fitness function 验。

例：ADR-0007 "DAL is only DB access point" → fitness function `no_db_import_outside_repository_pkg`。

没 fitness function = consequences 仅口头承诺，迟早违反。

---

## §5 与现有 skill 的映射

| Fitness function 类型 | 集成进哪 |
|---|---|
| Linter / static dep | 各 stack-dev skill（`go-microservice-dev` / `python-service-dev` / `web-react-dev` / `app-cross-platform-dev` / `miniapp-product-dev`）的 CI gate |
| Performance budget | 见 `testing-strategy/references/test-code-authoring-patterns.md` §3 (slow test heuristic) + `platform-observability` 运行时验证 |
| Breaking change detection | `test-artifact-management/references/source-to-case-workflows.md` §D (schemathesis / Pact / Dredd) — 契约层 fitness function |
| Security invariants | code review + `code-review` skill（CI 集成）|
| R&D standards conformance | `product-rd-workflow` owns the standards family and conformance map; this reference owns the executable invariant model; stack skills own concrete commands |
| Repo-local agent contracts | `agents-file-coverage-gate` for AGENTS.md coverage; `product-rd-workflow` decides when contract changes are required |

- Security-invariant reviews must route through `code-review`; the selected CLI keeps its local provider and model configuration.

### 5.1 健康度检查输出

Prefer a stable machine-readable result so CI, dashboards, and agents can reuse it:

```json
{
  "rule_id": "go.contract.idl_first",
  "severity": "blocker",
  "check_type": "deterministic",
  "status": "pass",
  "evidence": ["idl repo found", "generated package imported by service"],
  "owner": "service owner",
  "ci_gate": true
}
```

For `agent_review` checks, include the prompt or review packet path and quote only the concrete finding summary, not the whole source. If the review cannot make a concrete judgment from the evidence packet, emit `inconclusive` with the missing evidence; never convert it to `pass`. A health score is optional; blockers, failed gates, and evidence quality matter more than a single number.

---

## §6 故意不借鉴

| 概念 | 原因 |
|---|---|
| Ford 等 *Building Evolutionary Architectures* 整书的 evolutionary architecture 哲学 | 完整哲学体系太重；本 ref 只取 fitness function 这个 actionable 部分 |
| Mutation testing 作架构 fitness function | mutation 测的是 test suite quality，已在 `test-artifact-management/references/source-to-case-workflows.md` §C.1；不重复 |
| Chaos engineering 全套（Netflix Chaos Monkey 等）| 是 reliability fitness function 的具体方法，归 `platform-release-engineering` 实现层 |
