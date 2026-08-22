# 测试代码写法的工程实践

写测试代码本身的工艺（stack-agnostic）。与 testing-strategy 主体的"该测什么 / 哪一层测"互补 — 这份是"该写什么形状的测试代码"。

不替代 stack-specific dev skill（pytest fixture 细节 → python-service-dev；Go table-driven 语法 → go-microservice-dev）；这份只覆盖跨语言通用模式。

## 外部来源（按名引用 + 可核验）

- **Gerard Meszaros** — *xUnit Test Patterns: Refactoring Test Code* (2007, Addison-Wesley) — test smells、test doubles 分类、fixture 模式权威
- **Roy Osherove** — *The Art of Unit Testing* (2nd ed. 2013, Manning) — 测试命名约定
- **Steve Freeman & Nat Pryce** — *Growing Object-Oriented Software, Guided by Tests* (2009, Addison-Wesley) — outside-in / London school TDD
- **Martin Fowler** — "Mocks Aren't Stubs" (martinfowler.com, first published 2004; significant 2007 revision) — behavior vs state verification 界定
- **Daniel Terhorst-North** — "Introducing BDD" (dannorth.net, 2006) — Given-When-Then 来源
- **Nat Pryce** — "Test Data Builders: an alternative to the Object Mother pattern" (natpryce.com, 2007) — Test Data Builder
- **Go 官方 wiki** — Table Driven Tests (go.dev/wiki/TableDrivenTests) — Go 社区主流模式
- **Brian Marick** — "How to misuse code coverage" (testing.com, 1999) — coverage 不是目标

---

## 1. AAA / Given-When-Then 结构

**定义**：把一个测试拆 3 段：**Arrange**（准备前置）→ **Act**（执行被测代码）→ **Assert**（断言结果）。等价 BDD 形式：**Given** / **When** / **Then**（Terhorst-North 2006）。Meszaros《xUnit Test Patterns》用 4 段：Setup / Exercise / Verify / Teardown（Teardown 多由框架接管，所以日常简化为 3 段）。

**用**：所有测试默认都该有清晰的 3 段。一段空行隔开即可（注释可选）。

**不用**：参数化 / 表驱动的单条 row 不必每个都标 3 段；整个表外层结构本身就是 AAA。

**落地**：
- 视觉上一空行分段
- 一个测试只一组 AAA — 多组 AAA 说明该拆 2 个测试
- 注释 `// Arrange` / `// Act` / `// Assert` 是可选的；命名清楚的情况下不必加
- BDD 框架（Cucumber / Behave）可直接用 Given/When/Then 关键字

**例**：
```python
def test_export_request_returns_signed_url_when_user_has_quota():
    # Arrange
    user = create_user(quota_remaining=1)
    fake_storage = FakeStorageBackend()

    # Act
    result = export_service.request(user, fake_storage)

    # Assert
    assert result.signed_url.startswith("https://storage.example/download/")
    assert result.expires_at > now()
```

---

## 2. 测试命名约定

**定义**（Osherove）：测试名表达 3 段意图：被测单元 + 场景 + 期望行为。各栈惯例：

- **Python (pytest)**：`def test_<unit>_<scenario>_<expected>()`
- **Go**：函数名 `func TestXxx(t *testing.T)`；场景通过 `t.Run("scenario_<expected>", ...)` 表达；表驱动 row 字段 `name string` 兜场景描述
- **Java / C#**：`<UnitName>_<Scenario>_<ExpectedBehavior>`
- **JS (mocha / Jest / Vitest)**：`describe("<unit>", () => { it("should <expected> when <scenario>") })`
- **Dart (flutter_test)**：`testWidgets('<unit> should <expected> when <scenario>', ...)`

**用**：测试代码命名一律遵守。test1 / testFoo / testCase 这种零信息名不接受。

**不用**：极短一次性 helper 测试（如临时调试）可放宽，但不要 commit。

**落地**：
- code review 阻塞：测试名读不出"测什么 / 什么情况 / 期望什么" → reject 重命名
- 长 → 拆分被测单元；不接受"名太长"作借口（短名意味着该测试在掩盖范围过广）

**例**：
```
✅ test_export_request_returns_signed_url_when_user_has_quota
✅ test_export_request_returns_403_when_user_quota_exhausted
✅ test_export_request_returns_429_when_rate_limit_exceeded
❌ test_export_1 / test_export_basic / test_happy_path
```

---

## 3. Test smells（测试异味）

**定义**（精选自 Meszaros 2007 及其衍生分类）：测试代码的反模式。Meszaros 原书列约 18 项分 code/behavior/project 三类；下面是日常 review 最常碰到的子集（部分名字 / 阈值是团队启发，非原书字面）：

| 异味 | 含义 | 后果 |
|---|---|---|
| **Fragile Test**（Meszaros） | 实现细节变动就挂 | 重构成本高 |
| **Change-Detector Test**（Fragile 的高频子类；名为团队启发） | 断言"预期会变的数据"的快照（目录/注册表项、版本号字面量、枚举计数、硬编码清单）而非行为 | 例行数据更新即挂 CI、零行为覆盖、浪费工时"修测试" |
| **Erratic Test** 含 Mystery Guest（Meszaros） | 隐含外部依赖 / 顺序敏感 / 时间敏感 | flaky |
| **Assertion Roulette / Eager Test**（Meszaros） | 一个测试塞多场景或多个独立断言 | 失败定位难、报错无意义 |
| **Slow Test**（Meszaros 项；阈值是**团队启发**：单 unit 测 > 100ms / 整 unit 套 > 30s 触警） | 反馈慢 → 开发者跳过 | 见下方"用"段中的层级豁免 |
| **Conditional Test Logic**（Meszaros） | 测试体内有 if/else/loop | 实际测的是什么不明 |
| **Mystery Guest**（Meszaros 子项） | 依赖外部文件/数据但未声明 | 不可复现 |

**用**：code review / 重构 / 排查 flaky test 时按这清单查。Slow Test 阈值只对**默认快速单测目标**（unit 层）严卡；integration / E2E / host-smoke / benchmark 测必有独立的更宽 budget，按 marker 分离（如 `@pytest.mark.integration` / Go `-short` 区分）或按 runner 配置级 include 清单隔成独立套（perf/stress 类车道优先用清单——清单可审计，运行时 skip 标记会静默腐烂，见 `ci-fixtures-and-flake-control.md` Coverage As Signal），不混入 unit 套时间预算。

**不用**：写新测试时不必预先记住名字 — 用 §1 §2 §7 等正面规则反过来就避开了大半。

**落地**：
- 测试矩阵 / CI 报告里发现 flaky → 先按 Sensitive Test 排查（时间/顺序/外部依赖）
- 一次 review 抓到 ≥ 3 处同类异味 → 列入技术债跟进，不只口头指出
- 自动检查工具：pytest `-x --tb=short` + flake-detector / pytest-randomly；Jest `--bail`；Go `-race -count=10`

**例**：
```
Lazy Test（坏）：
def test_export_flow():
    r1 = service.request(...)
    assert r1.ok
    r2 = service.poll(r1.id)
    assert r2.status == "done"
    r3 = service.download(r1.id)
    assert r3.content_length > 0

拆成 3 个测试（好）：
def test_request_returns_ok_when_input_valid(): ...
def test_poll_returns_done_when_request_completed(): ...
def test_download_returns_non_empty_content_when_request_done(): ...
```

```
Change-Detector（坏）—— 注册表一增/版本一升就挂，零行为覆盖：
assert "fahrenheit" in SUPPORTED_UNITS         # 目录/注册表项快照
assert len(SUPPORTED_UNITS) == 7               # 枚举计数
assert CONFIG["schema_version"] == 4           # 版本号字面量

改成不变式 / 契约（好）—— 注册表增长、版本升级仍成立：
assert "celsius" in SUPPORTED_UNITS                            # 仅当 celsius 是文档承诺的基准单位（契约锚点），见判据
assert all(u in CONVERSION_FACTORS for u in SUPPORTED_UNITS)   # 每个单位都必须有换算因子（关系不变式）
assert CONFIG["schema_version"] == CURRENT_SCHEMA_VERSION      # 迁移抵达当前版本，而非字面量
```
判据：读起来像"当前数据的快照"就删；读起来像"两份数据必须如何关联"的契约就留。
区别于 Fragile Test —— Fragile 是实现细节变就挂，Change-Detector 是**本就预期会变的数据**变就挂；
PR 新增 provider/model/单位想加测试时，断言"关系不变式"（如每项都有换算因子），不要断言具体名字/计数。
**字面量锚点的取舍判据（防把有效契约/回归测试当快照删掉）**：断言某个字面量值合法 = 仅当该值本身就是被保证的行为——
对外承诺/文档化的名字、不得静默回退的 wire/API 或 schema 迁移版本、安全 allow/denylist 项、合规枚举映射、或冻结的缺陷回归用例（a frozen defect-history regression case）。
判定法：该值能追溯到**文档化的**产品/API/安全契约或历史缺陷（而非你刚从当前实现里读到的现状），且测试名点出该契约
（如 `test_celsius_is_documented_base_unit` / `test_v2_envelope_field_stays_stable`）→ 留；否则就是快照 → 改成关系不变式。上例 `"celsius"` 之所以合法，正是因为它是文档承诺的基准单位，不是因为它此刻恰好在注册表里。

---

## 4. Fixture 模式：Object Mother / Test Data Builder

**定义**：复杂测试对象的构造法。两种主流：

- **Object Mother**（Fowler、Meszaros）：集中工厂方法 `aValidUser()` / `aBlockedUser()` / `aUserWithRole(role)`，按典型场景命名
- **Test Data Builder**（Pryce 2007）：fluent builder `UserBuilder().withRole("admin").withQuota(0).build()`，组合灵活

**用**（按这个顺序判）：
1. **优先沿用 repo 已有 fixture 约定** — 哪个已铺开就跟哪个，避免双轨
2. 新模块无现成约定时：场景枚举少（< 10）且业内说法稳定 → Object Mother；字段多 / 组合频繁 → Test Data Builder
3. 两种可共存（named mother methods 内部用 builder 实现）

**不用**：单字段 primitive 测试（直接 inline 参数即可，不必 builder）。

**落地**：
- `test/helpers/<entity>_mother.py` 或 `test/helpers/<entity>_builder.py` — 共享于该模块所有测试
- builder 必有 sensible defaults — `Build().build()` 应能造一个合法 minimal 对象，免每个测试列全字段
- 不在 builder 里放业务逻辑（验证 / 派生字段）；那是被测代码的事

**例**（Test Data Builder）：
```python
# helpers/user_builder.py
class UserBuilder:
    def __init__(self):
        self._role = "user"
        self._quota = 100
        self._verified = True
    def with_role(self, role):
        self._role = role; return self
    def with_quota(self, q):
        self._quota = q; return self
    def build(self):
        return User(role=self._role, quota=self._quota, verified=self._verified)

# 测试侧
def test_admin_can_export_when_quota_zero():
    user = UserBuilder().with_role("admin").with_quota(0).build()
    assert export_service.allowed(user)
```

---

## 5. 行为 vs 状态验证（Behavior vs State）

**定义**（Fowler, "Mocks Aren't Stubs", 2004; revised 2007）：两种 oracle 选择：

- **状态验证**：执行后查对象 / 数据库 / 返回值的状态。古典 (Detroit / classical) school 偏好
- **行为验证**：用 mock 检查"被测代码以正确的方式调用了协作者"。Mockist (London) school 偏好

**用**：
- 状态验证：纯函数 / 单一聚合内部、可观察的输出明确
- 行为验证：跨边界协作（消息发布、外部 API 调用、metric/log emit）— 状态不可见，必须验证调用本身

**不用**：
- 不要为内部实现细节用行为验证（"调了 helper 几次"）— 会成为 Fragile Test
- 不要对纯查询用行为验证（"调了 DB 一次"）— 实现细节，重构就挂

**落地**：
- 默认状态验证；只在 cross-boundary 副作用（外部 IO / event emit / metric）时上 mock
- 替身放在**昂贵、非确定、不安全/不可逆、需特权、或不可用的边界**（模型适配器 / 网络 / 时钟 / 设备 / 部署·迁移·支付执行器 / 删除类文件操作）；单元隔离与确定性故障注入（拒绝、回滚、部分失败）也可用替身；边界内其余下游用真实现——**且只在隔离的、测试自有的资源上**运行。给正式组件手搓的替身只证明"桥接把字节搬过去了"，证明不了该组件按断言行为——集成/桥接类测试用脚本化的边界替身 + 真工具/真执行器（发布入口 smoke 仍按 e2e 参考走真实路径）
- 行为验证必须 assert 业务可观察的 interaction（"以正确参数调了一次"），不是"调了某 helper"
- 一个测试只用一种风格 — 混用难读

**例**：
```
状态验证（好）：
result = signed_url_generator.generate(file_id, ttl=300)
assert result.expires_at == now() + 300

行为验证（好，因为跨边界）：
audit_log_mock = Mock()
service.generate(file_id, ttl=300, audit_log=audit_log_mock)
audit_log_mock.emit.assert_called_once_with(
    event="signed_url_generated", file_id=file_id, ttl=300)

行为验证（坏，测了实现）：
service.generate(file_id, ttl=300)
internal_helper_mock.parse.assert_called_once()  # 重构改 parse 就挂
```

---

## 6. Coverage 解读：floor 非 goal

**定义**（Brian Marick 1999 / 业内共识）：代码覆盖率是 floor 检测器（"哪行没跑过"），不是质量 goal（"这行测得好"）。常见覆盖类型：

- **Line coverage**：行级别，最低门
- **Branch coverage**：条件分支，比 line 强
- **MC/DC**（Modified Condition/Decision Coverage）：每个 boolean 子条件独立影响过决策。**DO-178C 航空 / 医疗 / 汽车 functional safety 才用**；普通业务代码无监管要求时不必上。
- **Mutation coverage**（见 source-to-case-workflows §C.1）：才是真"测得好"的 proxy

**用**：CI 设 floor（如 line 60% / branch 50%）防覆盖崩塌；critical-path 模块定专项目标（line 90%）。

**不用**：
- **不用 100% 作 KPI** — 强行凑 100% 会产生 lazy assertions（`assert result is not None` 这种）
- **不把整库平均覆盖率作 PR gate**（个别 PR 不应承担整体覆盖率波动）

**落地**：
- CI floor：仓库整体 line ≥ X%；要防"大文件覆盖率补贴裸文件"时改用 per-file 门（阈值团队定，见 `ci-fixtures-and-flake-control.md` Coverage As Signal）
- **PR 覆盖率不可下降原则有例外**：删冗余测试 / 移除已废弃代码 / 合并重复 fixture 等清理类 PR 覆盖率下降允许，但 PR 描述必须给 **preservation proof row**：`deleted: <test path/name>; preserved scenario: <TC-ID or behavior statement>; replacement: <test path or "still covered by <existing test>">; oracle parity: <断言形状等价说明>; evidence: <command output / report ref>`。没 row = 当作场景失守 = 阻挡。Reviewer 用 row 验证：跑 replacement test 应能 catch 删掉的 mutant；equivalent assertion 不是"两个都跑过"，是"等价业务断言"
- critical-path 模块单独定 ratchet（如 `<critical-module> line ≥ 90% 且 branch ≥ 80%`）— 模块名按 repo 实际填
- 用 mutation testing 周期性检查（见 source-to-case-workflows §C.1）— 比追 100% line 更省力且更真实
- coverage 报告 + uncovered lines 进 PR comment（不要靠开发者主动看）；覆盖门失败输出指名到可点击的 `path:line:col`（runner 内建只报文件名时加自定义 reporter，绿时静默）——只报文件名等于让作者本地重跑一遍才能找到缺口
- 覆盖门下的 uncovered line **先当删除候选、再当补测候选**：门在正确地标记死代码/不可达分支时，补一个测试只是把死代码钉死；行覆盖是必要不充分——证明行跑过了，不证明功能按交付形态工作

---

## 7. Test isolation（测试隔离）

**定义**：每个测试不依赖其他测试的执行 / 状态 / 顺序。任意子集任意顺序跑结果一致。

**用**：所有测试默认应满足。

**不用**：性能基准 / 长生命周期场景 / runtime smoke 等可豁免，但必须 **marker + reason + owner + review_at（失效条件 / 重审时间）4 字段全齐**；裸标 serial 无 owner 不接受 — 那是把"顺序依赖"藏起来。各栈编码（4 字段在哪存）：

- **Python (pytest)**：自定义 marker kwargs — `@pytest.mark.serial(reason="...", owner="alice", review_at="2026-Q3")`
- **Go**：serial **必须显式标记** —— 不是"缺 `t.Parallel()`" 即 serial（正常隔离测试也常省略 `t.Parallel()`，那不是 serial exception）。serial 测试必须在函数上方有 `// serial: reason=... owner=... review_at=...` 注释，**或** 注册到 `test/serial-tests.yaml` 中心 registry。CI lint 强制：无 marker / 无 registry entry = 不视作 serial（当作普通可并行测试，并行不安全是 bug，不是免标的理由）
- **Jest / Vitest**：Vitest `describe.serial(...)` / Jest `--runInBand`；4 字段在 describe 块上方 JSDoc 注释；或 registry
- **JUnit 5**：`@Execution(SAME_THREAD)` + `@Tag("serial")`；4 字段在测试类 Javadoc
- **Flutter / Dart**：tests 顺序串行执行是默认；4 字段在 test 描述上方 `///` 注释；并必有 `// owner: ...` 行

**通用 fallback**：上面未列出的栈（如 Bun test / Playwright / Cypress / Android instrumented / iOS UI test 等）或 native marker 不支持 4 字段时，所有 serial 测的 metadata 集中维护在 `test/serial-tests.yaml`（key = 测试 path/name；value = `{reason, owner, review_at}`），CI 加 lint：所有 marker 标 serial 的测试都必须在 registry 出现。

**落地**（按"违反隔离"的常见来源逐项杜绝）：
- **全局可变状态**：module-level 缓存 / singleton / 进程级 `ContextVar` — 每测前 reset，或测试用 fixture 隔离实例。当 reset 易漏、状态分散难穷举、或框架本身留有进程级残留时，升级到**进程级隔离**：每个测试在新进程里跑（`spawn` 而非 `fork`，跨 Linux/macOS/Windows 一致），module 级 dict/set/`ContextVar` 物理上无法跨测泄漏；配合**每测超时**把 hang 变成可报告的失败而非挂死。代价/边界：每测进程启动开销（用并行 worker 摊薄）；fixture/参数需可跨进程序列化（spawn 会拒绝不可 pickle 的对象）；每测超时阈值要给慢但合法的测留余量，别把正常慢测当 hang 杀掉。**只用于消除跨测污染**——若套件的被测对象本身就是进程生命周期 / import 顺序 / 连接复用 / 并发清理，进程隔离会把这些真 bug 藏掉，那类套件不要上。不是默认全开。
- **共享 DB / 文件**：每测起独立 schema / 临时目录；用 transaction rollback / `tmp_path` (pytest)
- **顺序依赖**：用 `pytest-randomly` / `go test -shuffle on` / Jest `--randomize` 强制随机化暴露
- **并发安全**：能并行就并行（`pytest -n auto` / `go test -parallel N`）；测试本身不该用 sleep 解决竞态
- **时间依赖**：**注入 / 集中 clock**（依赖注入 Clock 接口 / 用 `freezegun` / `time.frozenTime()`），**确定性测试里 freeze**；**真实时间只在显式标记的 benchmark / runtime-deadline / signature-window / replay 测试里允许**，且必须有合理 bound 不靠"假设运行够快"

**例**：
```python
# 坏：依赖 module 状态
counter = 0
def test_a():
    global counter
    counter += 1
    assert counter == 1
def test_b():
    global counter
    counter += 1
    assert counter == 2  # 顺序依赖 + 全局态

# 好：每测独立
def test_a():
    c = Counter()
    c.increment()
    assert c.value == 1
def test_b():
    c = Counter()
    c.increment()
    assert c.value == 1
```

---

## 8. 参数化 / 表驱动测试

**定义**：同一 logic 不同输入 → 用表 + 循环展开成 N 个 case，不写 N 个测试函数。

- **Go**：社区主流（go.dev/wiki/TableDrivenTests）— `t.Run(name, func() {...})` 内层每 row 独立 fail
- **Python**：pytest `@pytest.mark.parametrize`
- **JS**：Jest / Vitest `it.each([...])`
- **Java**：JUnit 5 `@ParameterizedTest`

**用**：相同 setup + 相同断言形状、只换输入/期望的场景（边界值 / 枚举 / 等价类 — 见 `test-artifact-management/references/classical-test-design-techniques.md` §1 §2）。

**不用**：每 row setup 截然不同 / 断言形状变 → 拆独立测试更清楚。

**落地**：
- 每 row 必有 name 字段（Go `name string`, pytest `ids=[...]`）— 失败时报告读得懂哪 row 错
- 不在 row 数据里塞 logic（`{want: computeExpected(input)}` ← Bad）— 用字面 expected
- row 数量参考：3-20 适中；> 20 考虑拆表或上 property-based（见 source-to-case-workflows §C.2）

**例**（Go table-driven）：
```go
func TestExportTokenTTL(t *testing.T) {
    cases := []struct {
        name    string
        plan    string
        wantTTL time.Duration
    }{
        {"free plan: 5 minutes", "free", 5 * time.Minute},
        {"pro plan: 1 hour", "pro", time.Hour},
        {"enterprise: 24 hours", "enterprise", 24 * time.Hour},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            got := computeTTL(tc.plan)
            if got != tc.wantTTL {
                t.Errorf("plan=%s: got %v, want %v", tc.plan, got, tc.wantTTL)
            }
        })
    }
}
```

---

## 9. 跨栈移植测试：移植对抗输入本身

把一个 stack 的测试移植/镜像到兄弟 stack（Go adapter 测试搬到 Python adapter，或反向）时，**移植对抗输入本身**，不只移植断言形状：

- 要带过去的是**对抗语义类别**——大小写混写/别名化的 header / metadata key、畸形或非法编码输入、伪造的 trusted-only 字段、边界值——**经目标 stack 真实 ingress 边界注入**，而不是把源栈的原始字节照抄进来。原始非 UTF-8 字节只在目标生产链路确实接收原始字节时才照搬；否则移植对应的语义类别（同样攻击意图、用目标栈解码/入口能表达的形式），别测出一条生产不可能到达的假路径。
- 对抗 fixture 一律用**合成凭据 + scratch/synthetic 目标**，不带真实 secret、不打真实/生产端点（同主 SKILL 的 scratch-only matrix 纪律）——"为了更真实"用真凭据移植伪造 trusted 头，会泄漏 token、在真系统留审计事件。但"合成"不等于 **auth-bypass 打桩**：合成凭据要**结构合法、经目标栈真实校验/解析路径**（用测试签发者/密钥），否则伪造 trusted 字段的测试根本没过真 verifier、等于没测；无法安全构造就记 `safe-unavailable` + 残余风险。
- 在**每个**文档化 ingress 边界都跑，不只公网边缘：公网网关 strip 掉攻击输入，不代表内部 trusted 调用方不能伪造同样的字段——先画 trust-boundary map，对外部可达与内部 trusted 边界各跑一遍对抗 fixture，差异记 intentional-divergence。
- 只搬断言、把输入替换成干净/规范值的移植会**静默丢掉原测试的覆盖**：新 stack 上照样绿，但它本来要守的敌对路径根本没测到（假绿）。逐条对账 **input fixtures** 与源测试、不只对账期望输出；每处差异要么记 intentional-divergence，要么是 ported-away gap，**绝不静默省略**。
- **权威是文档化的契约、不是源测试的行为**：源栈测的可能是一个 legacy bug，照搬会把 bug 移植进兄弟栈、破坏更安全的规范契约；发现源行为不安全时记 `legacy-bug-closed` divergence，别静默继承。
- 用 mutation 证明移植后的测试真有牙口，但 mutation 打在**实现/oracle**上、不是打在对抗输入本身：**破坏新 stack 的防御实现**（去掉 strip/校验、放过伪造字段）后移植测试应转 RED；或临时移除/规范化对抗 fixture 看覆盖是否掉——mutation 一律在 scratch/临时进行、跑完 **restore + 核 clean diff**，别把削弱后的 fixture 提交进去永久丢掉防御。注意正确实现下喂对抗输入测试应当 **PASS**（它断言系统正确处理/拒绝了该输入），别把"喂对抗输入就该失败"写进断言（呼应 §182 行为验证与主 SKILL 的 mutation 要求）。

这是主 skill "port/mirror enforcement guard 逐条 parity" 规则在**跨栈测试代码**上的具体化（那条针对 enforcement guard；本条针对任意跨栈测试的输入保真）。

---

## 10. 行为纠正时的断言清扫

当变更**纠正**一个行为（compliance / contract / privacy / spec-conformance fix）时，入口规则要求找出钉住旧行为的断言、逐层清扫、同批改写为纠正后的契约。本节承载机制解释：

- **为什么旧行为必然被钉住**：A defect that shipped normally shipped with tests, and those tests encode it as intended —— 一个断言写"this response must carry X"，就是一份"X 是正确的"的承重声明；行为纠正必然把它打红。那个红是规则在 firing，不是回归——改写后的断言形态才是阻止旧行为回来的东西。
- **层枚举从变更自身的可达面走**：unit、contract、integration、host/E2E smoke、fixture 与 golden 文件。the assertion that pins the old behavior is often in the layer you did not plan to touch —— 于是替你发现它的是 CI，不是你。

---

## 快速选用决策表

| 写代码时遇到 | 用 |
|---|---|
| 单个测试结构混乱 | §1 AAA / GWT |
| 测试名表达不清 | §2 命名约定 |
| 测试 flaky 或重构成本高 | §3 排查 test smells |
| 复杂对象构造重复 | §4 Object Mother / Test Data Builder |
| 决定用 mock 还是查状态 | §5 行为 vs 状态验证 |
| Coverage 数字焦虑 | §6 floor 非 goal |
| 跑顺序变化结果不同 | §7 隔离 |
| 相同 logic N 个输入 | §8 表驱动 |
| 把测试搬到另一个语言/stack | §9 移植对抗输入本身 |
| 行为修复后旧断言变红 | §10 行为纠正时的断言清扫 |

---

## 故意不重复（在别处已有）

| 模式 | 已在何处 |
|---|---|
| TDD red-green-refactor 周期 | `superpowers/test-driven-development` skill |
| Mock 分类（dummy/stub/spy/mock/fake） | `testing-strategy` SKILL.md 主体（test double 段）|
| Property-based testing | `test-artifact-management/references/source-to-case-workflows.md` §C.2 |
| Mutation testing | `test-artifact-management/references/source-to-case-workflows.md` §C.1 |
| 测试层选择（unit/integration/E2E） | `testing-strategy` SKILL.md 主体 |
| Outside-in vs Inside-out TDD（设计哲学） | 选 GOOS Freeman & Pryce 2009 自行学；本 ref 不替代书 |
| Snapshot testing | 工具特定（Jest `toMatchSnapshot()` / `vitest-image-snapshot`），归各 stack-dev skill 实现段 |
| Golden file / Approval tests | 已在各 stack-dev skill release-ops / feature-playbook ref 里覆盖（生成产物快照、API 响应快照、报告快照）|
| Contract tests | 已在 `test-artifact-management/references/source-to-case-workflows.md` §D（schemathesis / Pact / Dredd / Prism）覆盖 |
