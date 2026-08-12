# 技能目录

这是本仓技能的**唯一权威目录**，覆盖 `skills/` 的全集。README 和 `agent-context/` 都指向这里，不再各自维护清单。

按**交付顺序**分层——找技能时想的是"我现在在交付的哪一步"，不是"它属于哪个抽象类别"。每条两行：一行**什么时候用**，一行**什么时候别用、改用谁**。

标记是**可验证的事实，不是猜测**：

- `entry`：`agent-context/session-start.md` 的常驻注入层里有它的路由判据——那层每个会话、每个宿主都注入，字节预算是零净增长。
- `leaf`：入口路由表里没有它的判据，经宿主技能清单的 `description` 或 owner 分派到达。**这不代表你不会直接叫它**（`release-coordination` 就常被直接叫），也不代表常驻层管不着它——`worktree-isolation` 和 `multi-agent-delegation` 由常驻层的硬纪律条款约束，那是**开工前必须先做的纪律**，不是「把这个请求送给谁」的路由判据。

为什么不把更多技能塞进常驻层：实测过。用 `eval-routing-bank.rb --with-bootstrap` 对 7 个未进常驻层的技能跑了 22 条真实用例的 A/B——完整清单下 19/22 → 19/22，description 截断到 250 字符下 20/21 → 21/22，**加常驻层没多修对任何一条**。所以「某技能必须进常驻层」要先用那个 flag 测出收益，再花字节。

触发词表和执行细节都在各技能的 `description` 与 `SKILL.md` 里，这里不复制。

## 需求

- `product-rd-workflow` `entry` — 用：加功能、新需求、多阶段重构、推倒重来、技术方案、方案评估、可行性与工作量评估、技术选型、项目分析。端到端交付路由器，再分派设计/架构/实现/测试/发布，并持有生命周期 gate。
  - 不用：单个 bug、窄 stack 修复 → `defect-diagnosis`；只要风险定级和 gate 清单 → `feature-risk-router`；只要一份需求材料 → 本层其余四个窄 owner。
- `requirement-intent` `entry` — 用：交付物是「这需求到底要什么」——意图、目标用户、成功标准、用户路径、**意图级**非目标、功能点验收点、拷问问题池、决策关闭 backlog。
  - 不用：要现状清单 → `requirement-baseline`；要变更边界（含**变更级**「本轮不改哪些」）→ `requirement-scope`；要成文 PRD → `requirement-doc-writer`；要一问一答的压力拷问 → `grill-me`；进入多阶段交付或实现计划 → `product-rd-workflow`。
- `requirement-baseline` `entry` — 用：交付物是**现状清单本身**——现在怎么运作、已有哪些能力与例外、事实来源与 freshness、缺口和冲突，含按 commit 固定的代码现状取证。
  - 不用：要的是「到底要什么」→ `requirement-intent`；要的是本轮改哪些 → `requirement-scope`；问线上是否已启用 → `platform-observability`；判断代码/项目质量 → `product-rd-workflow` 加对应 stack 技能；查 bug 根因 → `defect-diagnosis`。
- `requirement-scope` `entry` — 用：交付物是**变更边界**——in/out scope、受影响对象、依赖、MVP 与后续切片、appetite 与砍项、每个切片的验收范围。前提是方向已定。
  - 不用：方向还没定 → `requirement-intent`；要现状清单 → `requirement-baseline`；风险定级和要哪些 gate → `feature-risk-router`；实现和发布计划 → `product-rd-workflow`；测试范围 → `testing-strategy`。
- `requirement-doc-writer` `entry` — 用：生命周期已判 PRD Ready 之后，把已关闭的需求组装成人读的 PRD、需求文档、需求说明。
  - 不用：需求还不清 → `requirement-intent`；事实缺失 → `requirement-baseline`；范围或决策未关闭 → `requirement-scope`；只是润色 → `tighten-doc`。

## 设计

- `product-ui-ux-design` `entry` — 用：页面怎么设计、交互怎么做、设计走查与验收、空状态与错误提示、信息层级、无障碍、设计系统一致性。
  - 不用：只是把已定稿的界面写出来 → 对应客户端技能（`web-react-dev` / `app-cross-platform-dev` / `miniapp-product-dev` / `terminal-cli-dev`）；无可视界面变化的改动 → 记 `visible surface: no` 走 `product-rd-workflow`。

## 架构

- `go-microservice-architecture` `leaf` — 用：Go 后端/微服务的边界划分、RPC 与 IDL 契约、数据归属、可靠性与安全不变式、平台选型。
  - 不用：写实现码 → `go-microservice-dev`；跨仓多阶段架构改造交付 → `product-rd-workflow`。
- `python-service-architecture` `leaf` — 用：Python 后端的服务与包边界、API 契约、数据归属、异步/任务边界、运行时分层。
  - 不用：写实现码或局部重构 → `python-service-dev`；跨模块多阶段重构交付 → `product-rd-workflow`。

## 实现

- `go-microservice-dev` `leaf` — 用：写或改 Go 服务、IDL、DI、DAL、缓存、MQ、配置、代码生成与聚焦测试，以及 Go 命令行工具。
  - 不用：先定架构边界 → `go-microservice-architecture`；先复现和定位失败 → `defect-diagnosis`。
- `python-service-dev` `leaf` — 用：写或改 Python 接口、模型、任务、迁移、队列、配置、客户端与聚焦测试，以及 Python 命令行工具。
  - 不用：先定分层与边界 → `python-service-architecture`；先复现和定位失败 → `defect-diagnosis`。
- `web-react-dev` `leaf` — 用：React Web 的组件结构、路由、状态归属、数据获取、表单、浏览器行为、构建部署与渲染态验证。
  - 不用：界面该长什么样还没定 → `product-ui-ux-design`；小程序 → `miniapp-product-dev`；App → `app-cross-platform-dev`。
- `app-cross-platform-dev` `leaf` — 用：Flutter、React Native、原生 Android/iOS 的页面、导航、状态、离线缓存、平台能力、打包发版与真机验证。
  - 不用：小程序 → `miniapp-product-dev`；React Web → `web-react-dev`；UI/UX 决策 → `product-ui-ux-design`。
- `miniapp-product-dev` `leaf` — 用：微信/支付宝/抖音等小程序的页面、状态、登录、分享、平台能力、审核与真机验证。
  - 不用：React Web → `web-react-dev`；原生或跨端 App → `app-cross-platform-dev`。
- `terminal-cli-dev` `leaf` — 用：命令行/TUI 的渲染面（布局、输入、ANSI、回滚、选区）与命令/子命令/flag/help 契约——**契约归它，哪怕什么都不渲染**。
  - 不用：无终端 UI 关切、且该语言有 dev owner 的命令行工具 → `go-microservice-dev` / `python-service-dev`。
- `llm-inference-integration` `leaf` — 用：接大模型、提示词、RAG、智能体与工具调用、模型路由、流式、评测、回放、影子流量、token 成本、批量推理，以及运行时 agent 的沙箱与工具授权。
  - 不用：把交付工作分派给多个 coding agent → `multi-agent-delegation`；推理服务的可观测信号定义 → `platform-observability`。

## 测试

- `testing-strategy` `entry` — 用：怎么测、测试方案、选测试层、写测试代码、补测试、mock、单测/集成/E2E、回归覆盖、CI gate、验证证据。
  - 不用：要的是测试用例文档或飞书多维表格同步 → `test-artifact-management`；层级已定、只差在某语言里跑起来 → 对应 stack dev 技能。
- `test-artifact-management` `entry` — 用：写测试用例文档、从需求或代码生成用例、初始化或同步测试用例多维表格、用例状态与废弃生命周期。
  - 不用：要的是可执行测试代码与覆盖率 → `testing-strategy`；更大的功能交付 → `product-rd-workflow`。
- `defect-diagnosis` `entry` — 用：bug、报错、测试挂了、线上问题、复现、隔离、找根因，以及验证修复并补回归证据。
  - 不用：修复触及共享确定性闸/verifier，或跨仓契约/状态/版本/发布语义 → 回 `product-rd-workflow` 的 shared-gate 分类；要补的是测试层设计 → `testing-strategy`。

## 评审

- `code-review` `leaf` — 用：让独立 CLI 评审或对抗挑战一份实现，跨 Claude/Kimi/OpenCode/Codex 按可用性与模型家族独立性路由；找茬、唱反调、第二意见。
  - 不用：拷问的是还没写成码的方案 → `grill-me`；要决定该跑哪些 gate → `feature-risk-router`。
- `grill-me` `entry` — 用：一问一答压力访谈，在实现前挑战一个方案、设计、API 形状、数据模型或功能方向。
  - 不用：评审已写成的代码 → `code-review`；完整交付或计划撰写 → `product-rd-workflow`；需求澄清的问题池 → `requirement-intent`。
- `feature-risk-router` `entry` — 用：风险定级、要不要灰度、需要哪些 gate、双人 review、架构评审、安全评审与威胁建模的**闸位判定**。
  - 不用：要执行评审本身 → `code-review`；要决定测试层 → `testing-strategy`；交付物分类与阶段路由 → `product-rd-workflow`。
- `multi-perspective-research` `leaf` — 用：调研一个主题、深度调研、多视角研究、写作前调研；视角枚举 → 矛盾图 → 合成简报 → 自评。
  - 不用：一查便知的单点事实——直接回答；已点名候选让你选、或要"选哪个/可不可行"的裁决 → `product-rd-workflow`；拷问已有方案 → `grill-me`。

## 发布

- `release-coordination` `leaf` — 用：发版、生产发布、上线范围确认、合并 main、打 tag、生产构建、pipeline 证据、watcher 与发布后 reset。
  - 不用：设计构建/环境/灰度/回滚等长期发布能力 → `platform-release-engineering`；写上线文档正文 → `release-doc-writer`。
- `release-doc-writer` `leaf` — 用：写、填或核对提测文档与上线文档的实质内容，从 Git/配置/部署/验证证据里取材。
  - 不用：要协调一次发布事务、授权合并或改动生产状态 → `release-coordination`；只是润色措辞 → `tighten-doc`。
- `platform-release-engineering` `leaf` — 用：设计或评审一次改动如何从构建走到流量再安全退回——rollout 策略、环境泳道、审批、回滚、密钥、配置与部署控制面。
  - 不用：这一次具体发版的范围确认与合并授权 → `release-coordination`；判断放量看哪些信号 → `platform-observability`。

## 运维

- `platform-observability` `leaf` — 用：服务日志、指标、分布式追踪、日志与 trace 关联、看板、告警与 on-call 路由、SLI/SLO 与错误预算。
  - 不用：mesh、路由与 mTLS → `platform-service-connectivity`；发布闸与回滚证据 → `platform-release-engineering`；服务内部分层 → 对应 `*-architecture`。
- `platform-service-connectivity` `leaf` — 用：服务互通、服务发现、service mesh、mTLS、重试、超时、熔断、泳道路由——一个请求如何跨环境安全到达另一个服务。
  - 不用：请求到达后要看什么信号 → `platform-observability`；发布与灰度机制 → `platform-release-engineering`。

## 跨阶段

- `skill-extraction-workflow` `entry` — 用：复盘、沉淀、总结经验、把教训固化进技能、技能缺陷与流程优化、深度 review 或审计技能仓库、对标外部技能包找 gap。
  - 不用：普通 bug/QA/评审纠正——留在当前 owner 里处理；只是把文档写顺 → `tighten-doc`。
- `worktree-isolation` `leaf` — 用：动手改任何代码前先建分支和 worktree（**绝不在 main 上开发**），以及集成回目标分支后清理 worktree、本地分支和远端分支；合并授权协议也归它。
  - 不用：交付级的推倒重来、清除代码重新开发 → 先回 `product-rd-workflow` 重新分类，再按本技能建 worktree。
- `multi-agent-delegation` `leaf` — 用：把交付工作分派给多个 coding agent——切独立分片、隔离上下文与写入面、分阶段评审、验证 agent 产出。
  - 不用：产品里要发布的 agent 运行时（工具调用契约、注入防御、会话持久化）→ `llm-inference-integration`；单条线性本地编辑——直接做。
- `agents-file-coverage-gate` `leaf` — 用：在一个仓跑 AGENTS.md 契约覆盖 gate——扫哪些源码目录缺 AGENTS.md，可一键补 stub 并接 CI 卡关。
  - 不用：问契约本身何时该更新、分层策略怎么定 → `product-rd-workflow` 的 spec/repo-contract sync gate；定义 agent 工具调用的输入输出 schema → `llm-inference-integration`。
- `tighten-doc` `entry` — 用：实质定稿之后收口表达——润色、精简、轻度重构、去 AI 味、保住已定决策与注释安全。
  - 不用：实质内容还没定 → 先回对应 owner（spec → `product-rd-workflow`，用例 → `test-artifact-management`，复盘 → `skill-extraction-workflow`）。
