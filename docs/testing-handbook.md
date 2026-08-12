# 写测试与测试用例手册

> **何时找它**：怎么测、测试方案、覆盖、回归、CI gate、写测试代码、把用例放飞书。这块是**两个技能的同生态**：
> - [`testing-strategy`](../skills/testing-strategy/SKILL.md)：用例落到哪一层 + 怎么验证。
> - [`test-artifact-management`](../skills/test-artifact-management/SKILL.md)：用例从哪来 + 怎么管 + 怎么报告。

## 三种「自动化」，别混

团队常说的"自动化测试"其实是三件事，owner 和文档不同：

| 说的是 | 指什么 | owner | 文档 |
|---|---|---|---|
| 自动化测试**用例** | 用例从源生成、进多维表格、挂 `tc()`、出 CI 报告的 harness | `test-artifact-management` | [自动化测试方案](auto-test-scheme.md) · [使用手册](auto-test-manual.md) |
| 自动化测试（**分层**）| unit / 契约 / 集成 自动跑、当 gate | `testing-strategy` + 栈 dev 技能 | 本手册 + `testing-strategy` |
| 自动化 **e2e** | 浏览器/真机/小程序端到端自动跑关键链路 | `testing-strategy`（策略）+ 客户端技能（执行）| 本手册下方「自动化 e2e」节 + [客户端开发手册](client-dev-handbook.md) |

三者是一条链上的不同环：用例（写哪些）→ 分层（落哪层）→ e2e（关键链路端到端验）。harness 本身**层无关**——任何带 `tc()` 的测试（含 e2e）都进同一套报告。

## ownership 边界（先分清）

| 你的问题 | owner |
|---|---|
| 这个测试写在 unit / 集成 / E2E 哪一层？用什么 mock？CI gate 怎么设？怎么算验证过？ | `testing-strategy` |
| 测试用例从需求/代码/bug 怎么生成？怎么进多维表格？怎么挂 `tc()`？自动化测试报告怎么出？ | `test-artifact-management` |
| pytest/Jest/Espresso 的命令和 config 怎么写？ | 对应栈 dev 技能 |
| 测试用例 Base 没建、字段不全、用例记录或报告链路没接？ | `test-artifact-management`（具体表操作用 `lark-base`） |

`test-artifact-management` 内部会先借 `testing-strategy` 出场景/风险矩阵，不绕开它。测试用例 Base 初始化、字段、内容和记录全生命周期都归 `test-artifact-management`；通用 Wiki 和其他业务 Base 直接使用 `lark-wiki` / `lark-base`。

## testing-strategy：选层与验证

| 层 | 测什么 | 何时必须 |
|---|---|---|
| unit | 纯逻辑、窄改动 | 几乎总要 |
| 集成/契约 | 跨边界、接口契约 | 改了跨服务/跨模块边界 |
| E2E / host smoke | 真实运行链路、渲染 | 碰平台 API/生命周期/流式/权限/导航/存储/渲染状态 |
| 手动/探索 | 难自动化的 | 补充，不替代自动化 |

```mermaid
flowchart TD
  C["要测的改动"] --> U["unit：纯逻辑（几乎总要）"]
  U --> Q1{"跨服务 / 跨模块边界 or 接口契约?"}
  Q1 -->|"是"| I["加 集成 / 契约 层"]
  Q1 -->|"否"| Q2
  I --> Q2{"碰平台 API / 生命周期 / 流式 / 权限 / 导航 / 存储 / 渲染状态?"}
  Q2 -->|"是"| E["加 E2E / host smoke（blocking：lower 层证明不了就必须跑）"]
  Q2 -->|"否"| OK["够了"]
```

核心纪律：

- **先复用再新写**：动手前先 grep 同一个函数 / 接口 / 场景已有的测试，能扩就扩，别平行造一份。
- **别写变更检测器**：给"本来就会变"的数据打快照（供应商目录、配置版本号、枚举全集）不是测试，是每次改动都要手动同步的噪音。
- **test-case-first**：行为改动先写用例、跑 RED，再写实现。
- **代码改动必须测**：build/grep/typecheck/lint/review 都只是支持证据，不替代测试；至少跑一个相关层、当轮执行新加的测试。
- **mock 不证明运行时集成**：UI 接 API/生成内容要有真实渲染状态 + 契约/错误处理证据。
- **按层报告验证**：缺的层标 `not-applicable` 或 `blocked after remediation`，不collapse 成"build 过了"。
- **blocking 层失败 = 不能完成**：只有 `complete` / `pre-runtime-test ready` / `blocked` 三种收尾标签，不许把缺的 blocking 层重述成"残余风险/ready"。
- **证据分三档**：强=确定性+断言；中=有断言但依赖固定 DB/缓存/网络态；弱=只 log/sleep/随机/调真实模型/非阻断 CI。**弱证据只能提示风险，不能证明正确**。
- **冻结回归集、每次发布都跑**：每个修过的 bug / 事故 / 确认的坏 case 都进一个冻结集，**每次发布跑**（"测过一次"不算回归覆盖）。分层养得起：确定性 case 进阻断发布门；要 live 基建/模型/真索引的进发布前门，带 marker + owner + 超时，别塞进快门变 flaky。
- **覆盖看怎么跑，不看有几个文件**：按跑它的命令、marker、依赖、CI 里的位置来分类，别数测试文件个数或看文件名推断覆盖。
- **skip ≠ 跑过**：条件跳过（缺可选依赖就 importorskip、平台 marker）叠上分 job 选择，会出现"哪个 job 都没真跑它"但全绿——绿的是没跑，不是过了。
- **用仓库自带的 test wrapper**：它往往编码了必需的 env、代码生成、fixture、超时和 CI 对齐行为，绕过去自己拼命令等于换了一套跑法。

> **非功能 / 专项测试**（性能、安全、可访问性等）要不要进门禁、要什么证据，也归 `testing-strategy` 判；具体怎么测由对应领域 owner 负责。

## 场景/风险矩阵（动手写测试前先列）

高风险 / 产品可见改动，动手写一堆测试前先列一张小矩阵：按**风险**裁剪，不是每个排列都测。每行 = 一个有区分度的风险场景，标它在最便宜够用的那层证。

| 场景 | 风险 | 落哪层 | 断言（pass / fail）|
|---|---|---|---|
| 主成功路径 | 功能不通 | 集成 | 返回契约 + 落库正确 |
| 参数非法 | 脏数据入库 | unit | 拒绝且不写库 |
| 越权访问 | 数据泄露 | 集成 | 无权限 = 拒绝 |
| 并发重复提交 | 重复副作用 | 集成 | 幂等 / 去重 |
| 大数据量 / 中途失败 | 资损 / 截断 | E2E smoke | 可重试、不交付截断结果 |

> 矩阵小而准：覆盖不同**风险**，不是穷举排列。它**上游接**需求成形的覆盖矩阵（功能点+风险点×验收，见 [做需求手册](feature-delivery-handbook.md)）——需求覆盖 → 这里决定在哪层怎么证；**下游**决定测试代码写哪些。

## 自动化 e2e

e2e 策略归 `testing-strategy`，执行归客户端技能（浏览器/真机/小程序）。要点：

- **只测关键链路**：关键用户/调用旅程 + 发布信心，不要每个分支都走浏览器。
- **断言可见结果，不只点控件**：前端 API 页面要验 loading / success / failure / disabled-retry，并抓 console error 和失败网络请求。
- **覆盖一条真实成功路径 + 一条真实失败路径**，失败路径要可读、不崩。
- **各端 smoke 形态**：
  - Web → 浏览器打开真实页面 + 受控数据/稳定后端。
  - App → 设备/模拟器。
  - 小程序 → 开发者工具编译/预览或真机，验 route/scene 参数、状态、host 能力（分享/支付/订阅/扫码/webview bridge）。
- **运行时依赖的 host smoke 是 blocking**：碰平台请求/分块、流式终态、前后台恢复、host 导航、权限/能力弹窗、bridge 回调、存储/会话恢复、host 渲染错误态——lower 层证明不了就必须跑。
- **标 unavailable 前先补救**：起 emulator/browser/server、等就绪、重启 client daemon、跑仓库 setup 脚本、重跑发现命令；设备类先确认 `adb devices -l` + 就绪。仍不可用才记 `pre-runtime-test ready`（有 owner 交接，非 merge-ready）或 `blocked`。
- **组合链路三层验收**：module-level（改动模块自身）+ chain-level（上下游契约、端到端恢复回滚）+ product-level（用户可见结果不退）。一个子模块只看局部指标不够。
- e2e 测试同样挂 `tc()`，进同一套报告。

## test-artifact-management：源 → TC → 代码 → 报告

这条链：

```mermaid
flowchart LR
  SRC["需求 / Figma / 代码 / API 契约 / bug"] --> TC["结构化 TC（多维表格，分组视图 + 信息流转日志）"]
  TC --> HOOK["测试代码挂 tc('TC-XX')（4 端 helper）"]
  HOOK --> RPT["CI 自动化测试报告（残余风险 + vs 上次跑 diff + MR 评论）"]
```

4 端 helper：pytest marker / Go `tc.Mark` / Vitest `tcTest` / Dart `tcTest`。

- TC 在 多维表格，测试代码用 marker/wrapper 挂 `tc("TC-XX")`，sidecar `test/results/tc-map.jsonl` 维护映射。
- bug → 回归 TC：`defect-diagnosis` 出 RCA → `test-artifact-management` 生成 P0 [回归] TC → 栈技能写测试挂钩。
- 需求变更/功能下线：TC 标 `废弃`（不是 `跳过`），走 product-rd-workflow 的 Feature Deprecation 级联。

团队落地细节（辅助库标记、make 目标、飞书报告、CI/本地差异、孤儿检测）见 [自动化测试使用手册](auto-test-manual.md) 和 [自动化测试方案](auto-test-scheme.md)。

## 走查示例：给一个新接口补测试

1. `testing-strategy` 选层：纯参数校验 → unit；落库 + 返回契约 → 集成。
2. `test-artifact-management` 从接口契约生成 TC 到多维表格：正常、参数非法、并发重复提交。
3. 写测试代码挂 `tc("TC-XX")`，先 RED。
4. 实现接口 → 测试转绿。
5. CI 报告自动评论到 MR，带 vs 上次跑 diff。

## 常见坑

- **先跑了测试才补用例**：已发生就停下补用例、如实报告，不声称走了 TDD。
- **删/跳过失败测试求绿**：修代码或纠正无效测试，不是把测试跳过。
- **TC 标"跳过"代替"废弃"**：功能下线要走废弃级联，否则孤儿测试腐烂。

## 延伸阅读

- [`testing-strategy` 技能](../skills/testing-strategy/SKILL.md) · [`test-artifact-management` 技能](../skills/test-artifact-management/SKILL.md)
- [自动化测试方案](auto-test-scheme.md) · [自动化测试使用手册](auto-test-manual.md)
- [排查与修复 bug 手册](defect-diagnosis-handbook.md)
