# 通用 TypeScript 语言层技能

## 1. 要改善的任务结果

仓里的栈技能按运行时或框架划分：Go 服务、Python 服务、Node.js 服务、React Web、App、小程序。TypeScript 只出现在 `nodejs-service-dev` 的描述里，而且被归为服务或后端。非服务形态的 TS 任务——浏览器库、类型包、Bun/Deno 脚本、monorepo 类型共享、库的 `.d.ts` 发布——没有负责技能，Agent 只能凭通用知识回答，或者被拉到语义最近的 Node 服务技能上。

改善的是质量：在任何人的任何 TS 项目里，类型设计、tsconfig、模块解析、类型检查闸、库类型产物和外部输入边界都由一个负责技能给出可验证的做法，运行时规则仍由兄弟技能负责。

不改的：Node 运行时、React、移动端、小程序的运行时规则；服务架构；测试分层与覆盖策略；CLI 对外契约。

## 2. 结果分类

失败/纠正。依据：一个与 Node 服务无关的 TS 项目找不到负责技能（第 6 节的基线路由会复现）。

## 3. 成因

| 编号 | 成因 | 证据 | 类别 |
| --- | --- | --- | --- |
| C1 | 栈技能按运行时切分，没有语言层负责技能 | `skills/` 目录：每个栈技能都以运行时或框架命名 | 缺机制 |
| C2 | TS 只挂在 Node 服务技能的描述上，非服务形态路由不到 | `nodejs-service-dev` 的 `description` 写的是 backend and service code | 触发面过窄 |
| C3 | TS 语言规则散在三四个技能里，互不对齐 | 第 4 节盘点：strict 系列开关只在 React 架构参考里出现，typed lint 规则只在测试的 fitness-functions 表里 | 漂移 |
| C4 | Go 和 Python 的语言规则内嵌在服务技能里也够用，因为两门语言几乎只用来写服务；TS 跨浏览器、Node、Bun/Deno、移动端，同样的切法让语言层没有归属 | 兄弟技能结构对比 | 过时的前提 |

反事实：只给 `nodejs-service-dev` 补触发词，C1 和 C4 不变，非 Node 形态仍然没有负责技能；只新建技能、不改兄弟技能的路由和内容，C3 会变成两处漂移。所以两件事都做。

## 4. 现有 TS 内容盘点（B1）

| 位置 | 内容 | 决定 | 理由 |
| --- | --- | --- | --- |
| `web-react-dev/references/react-architecture.md` §TypeScript Discipline：`strict` 为底线、`noUncheckedIndexedAccess` | 语言层 tsconfig 基线 | 迁入，原处改为指向 | 与 React 无关，所有 TS 项目适用 |
| 同节：外部输入用 `unknown`、经 schema 收窄、不用 `any` | 语言层边界规则 | 迁入，原处保留 React 侧一句并指向 | 边界校验对所有运行时成立 |
| 同节：UI 状态判别联合、`never` 让非法 props 不可调用、DOM 事件类型、`React.FC`、品牌类型用于缓存与权限键 | React 侧应用 | 不变 | 判别联合和品牌类型的通用写法归新技能，React 上的用法留原处 |
| `web-react-dev/references/react-architecture.md` 共享 `tsconfig.base.json` | 多应用组合的 tsconfig 共享 | 不变 | 讲的是 React 组合的选型；项目引用的机制归新技能 |
| `web-react-dev/SKILL.md` 确定性检查一段（typed lint、`strict`） | 指向 fitness-functions §4.1.3 | 不变 | 已是指针 |
| `web-react-dev/references/web-quality-release.md` PR 闸顺序含 `tsc --noEmit`、Biome 不替代 `tsc` | Web CI 闸 | 不变 | 已与新技能的检查闸一致，属于 Web 发布面 |
| `nodejs-service-dev` 描述 `TypeScript/JavaScript module setup` | 路由面 | 改 | 收窄为 Node 运行时下的执行与模块；TS 语言层指向新技能 |
| `nodejs-service-dev/references/runtime-and-project-contract.md` TypeScript paths 表、类型剥离说明、ESM/CJS、`exports` | Node 执行路径 | 不变，加一句指向 | 类型剥离、加载器是 Node 运行时机制；tsconfig、类型产物、`exports` 的 `types` 条件归新技能 |
| `nodejs-service-dev/SKILL.md` Hard Rules 类型剥离不是类型检查 | Node 运行时 | 不变 | 新技能讲通用的「剥离类型执行不等于类型检查」，指向 Node 侧细节 |
| `software-architecture/SKILL.md` Node.js / TypeScript 部分：类型在运行时被擦除、边界用运行时 schema、类型检查闸 | 架构不变式 | 不变 | 架构层的结论；实现做法归新技能，两边说法一致 |
| `software-architecture/references/method-grounding.md` Node/TS 两行 | 出处 | 不变 | 出处记录 |
| `testing-strategy/references/fitness-functions.md` §4.1.3 JS/TS 一行（typed lint 规则、`strict`、dep-cruiser） | conformance 执行器表 | 不变 | 闸策略归测试技能；新技能指向它，不复述规则表 |
| `testing-strategy/references/integration-contract-testing.md` PR 闸含 `tsc --noEmit` | 闸顺序 | 不变 | 同上 |
| `testing-strategy/references/test-topology-and-commands.md` 运行器选择 | JS/TS 运行器 | 改 | 补类型检查独立成层，见第 5 节 |
| `test-artifact-management/references/tc_helpers/tc.ts` | 随技能分发的 TS 源码 | 改 | 严格配置下编译失败，见第 5 节 |
| `defect-diagnosis/SKILL.md` Prevention Routing | 防复发路由 | 改 | 加一行：TS 类型、编译、模块解析、类型产物的问题 → 新技能 |
| `product-rd-workflow` 开发路由（`SKILL.md`、`stage-classify-and-route.md`、`dispatch-owner-skills.md`） | 栈负责技能清单 | 改 | 加上语言层负责技能，说明与运行时技能组合加载 |
| `app-cross-platform-dev`、`miniapp-product-dev` | RN、Taro 下的 TS | 改 | 指向新技能。两个入口已在历史字数上限，入口不能增长，所以指针放在各自跑类型检查的 reference（`mobile-quality-release.md`、`qa-release.md`） |
| `terminal-cli-dev` | Node CLI → `nodejs-service-dev` | 不变 | TS 写的 Node CLI 仍由 Node 技能负责实现，类型层组合加载 |
| `go-microservice-dev`、`python-service-dev` | 各自语言规则内嵌 | 不变 | 两门语言没有跨运行时的归属问题 |
| `llm-inference-integration`、`test-artifact-management`、`product-ui-ux-design` 里的 TS 提及 | 举例或模板 | 不变 | 不是 TS 语言规则 |
| `platform-release-engineering` 语言库打 tag 机制归栈技能 | 发布 | 不变 | 已写「归栈技能」，新技能负责 TS 库的类型产物校验 |

## 5. 兄弟技能 mini-map

源栈：TypeScript 语言与编译层（跨运行时）。

| 兄弟技能 | 决定 | 理由 |
| --- | --- | --- |
| `nodejs-service-dev` | update | 描述收窄，正文路由与运行时契约加指向 |
| `web-react-dev` | update | tsconfig 基线和边界规则迁出改为指针，入口路由加一行 |
| `app-cross-platform-dev` | update | `mobile-quality-release.md` 加指针（入口在字数上限） |
| `miniapp-product-dev` | update | `qa-release.md` 加指针（入口在字数上限） |
| `terminal-cli-dev` | unchanged | 见上表 |
| `go-microservice-dev`、`python-service-dev` | unchanged | 见上表 |
| `software-architecture` | unchanged | 架构不变式已一致；新技能不做架构决定 |
| `testing-strategy` | update | `test-topology-and-commands.md` 加一条：类型检查与类型测试是独立命令层，运行时测试通过不等于类型通过；是否阻断合并归本技能，命令和断言机制归新技能。入口在字数与字节上限，不改 |
| `test-artifact-management` | update | 仓里随技能分发的 `tc.ts` 在 `noUncheckedIndexedAccess` 下编译失败，复制到开了该开关的项目会打断对方的类型检查闸。修复并在 `tc_helpers/AGENTS.md` 写明严格配置下的验证命令；`tc-marker-conventions.md` 写明复制后属于项目源码、要进类型检查 |
| `defect-diagnosis` | update | Prevention Routing 加一行 |
| `product-rd-workflow` | update | 开发路由加语言层负责技能 |
| `code-review` | unchanged | 评审按改动所属技能的检查项，无栈清单 |
| `skill-extraction-workflow` | update | 新技能登记进 impact-chain 负责技能集；按运行时切分的栈缺语言层负责技能这一类，写进兄弟技能 mini-map 的规则 |
| `docs/SKILLS.md`、README 技能数、npm README | update | 目录登记 |
| `agent-context/session-start.md` 入口路由块 | unchanged | 新技能是 `leaf`；校验器 `skill_bootstrap_leaf_in_region` 禁止 leaf 进常驻路由块，`docs/SKILLS.md` 写明进常驻层要先用 A/B 测出收益。入口登记改在 `docs/SKILLS.md` 目录完成 |
| `eval/routing-tasks.jsonl`、`eval/behavior-fixtures.jsonl` | update | 路由正反例和行为任务 |

## 6. 压力场景（RED → GREEN）

路由任务冻结在 `eval/routing-tasks.jsonl`（`route-typescript-*` 十条），四个形态的行为任务冻结在 `eval/behavior-fixtures.jsonl`（F41–F44）。

| 编号 | 形态 | 期望 |
| --- | --- | --- |
| 1 | 库发布：ESM/CJS 双格式与类型解析 | `typescript-dev` |
| 2 | 非 React 的浏览器 bundler 项目 tsconfig | `typescript-dev` |
| 3 | monorepo 类型共享与项目引用 | `typescript-dev` |
| 4 | 外部输入边界：`JSON.parse(x) as T` | `typescript-dev` |
| 5 | strict 迁移 | `typescript-dev` |
| 6 | Deno 脚本的判别联合与穷尽检查 | `typescript-dev` |
| 7–10 | Node 服务、React 组件、CI 类型检查失败定位、TS 项目测试分层 | 原负责技能不变，且不被新技能抢走 |

路由用 `eval-routing-bank.rb --replicas 10`（达到行动分辨率下限 10），模型 `claude-haiku-4-5`。RED 在改动前的技能树上跑，GREEN 在改动后跑。结果见 `evidence/validation.md`。

另一条一手 RED：仓里分发的 `tc.ts` 在 `strict` + `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes` + `verbatimModuleSyntax`、`nodenext` 下 rc=2（第 108 行三个错误）；修复后 `nodenext` 和 `bundler` 两套配置都 rc=0，运行时行为不变（捕获组至少匹配一个字符，空串分支不可达）。

## 7. 来源

一手：TypeScript 官方 TSConfig Reference、Modules 手册三篇、Narrowing、Project References、Publishing、4.9/5.0/5.8 发布说明，TypeScript 6.0 与 7.0 发布公告，typescript-eslint 文档，arethetypeswrong CLI，Vitest 类型测试文档。理论：TypeScript 设计目标（健全性与运行时类型信息是非目标）、结构化类型兼容、parse don't validate 与 LangSec 的 shotgun parsing。业界：一份广泛使用的 tsconfig 速查表，只用来交叉检查选项表，选项以官方参考为准。逐条出处在 `skills/typescript-dev/references/source-map.md`。没有使用任何私有项目作为规则来源，规则全部来自公开资料。

## 8. 与原定方案的偏差

- 入口路由表（原定在常驻路由块登记）：新技能是 `leaf`，不进 `agent-context/session-start.md` 的常驻路由块（校验器禁止 leaf 进入，进常驻层要先测出收益），登记在 `docs/SKILLS.md`。
- 兄弟技能入口：三个入口在历史字数上限，指针改放在各自的 reference，见第 4、5 节。
- `skill-extraction-workflow`：成因 C4 是提炼流程没发现的问题，按「路由缺口必须在提炼流程里落一个防复发点」，在 `extraction-quickstart.md` 的兄弟技能 mini-map 一步加一条：先看兄弟技能按什么维度切分，跨运行时的语言没有语言层负责技能时记为覆盖缺口，不能记 `unchanged`。
- 改了路由 bank，旧的全量路由基线从此不可比；本轮只对新增的十条跑了 RED/GREEN，全量基线留到下一轮补测。
