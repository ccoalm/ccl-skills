# 步骤 2 零丢失映射

基线 `origin/main` 2126c9d。本文件说明两个旧架构技能的内容各自去了哪里，以及每一类是怎么核对的。脚本在 `specs/architecture-skill-consolidation/evidence/`，结果见同目录的 `validation.md`。

## 1. 核对方式

| 内容 | 去向 | 核对 |
| --- | --- | --- |
| 两个旧入口的正文（平台边界、通用化纪律、核心流程五步、架构默认值） | `skills/software-architecture/references/service-design-rules.md`，按步骤分"共享 / Go / Python"三栏；入口每步保留一行压缩后的义务 | `entry_rules.py verify`：旧入口每个块（段落、表格、顶层条目连同子条目）要么在规则文件里原文出现，要么属于下表 7 组手工合并。123 块原文保留，13 块手工合并，0 丢失 |
| 两个旧入口的 Skill Routing | 新入口的 Routing 一节；三条平台 owner 条目另在规则文件里原文保留 | 逐条人工对照，见第 3 节 |
| 两个旧入口的 Reference Loading | 新入口的 Reference index 表 | 脚本核对：`references/` 下每个文件都在表里出现，表里没有不存在的文件 |
| 3 对镜像资料 | 各合成一个文件 | `migrate_refs.py verify`：合并结果由脚本从两份旧文件重建，磁盘上的文件必须与重建结果逐字节相同。共享区域两侧在基线上逐行相同（脚本断言），只改了 4 处按栈写的文件名引用 |
| 其余 43 个资料 | 原样迁入，9 对同名的加 `go-` / `python-` 前缀 | 同一脚本：30 个与旧文件逐字节相同，13 个只改了指向改名文件的链接或一句"sibling"措辞，见第 2 节 |

脚本只证明"内容相同"和"没有块被丢"。手工合并的块是否保住了两侧的意思是人工判断，列在下面供评审核对。

### 手工合并的 7 组

每组两侧原文只差括号里的几个词，合并后的文本同时写出两侧。

| 步骤 | 规则开头 | 两侧差异 → 合并写法 |
| --- | --- | --- |
| 通用化纪律 | Do not copy product nouns | `callback types` / `callbacks` → `callback types` |
| 契约 | API contracts must define | `request messages` / `request schemas` → `request messages/schemas` |
| 契约 | Internal service data models | `transport/application` / `route/application` → `transport (route)/application` |
| 契约 | Inventory the service's exposed surfaces | 两侧各举本栈的路由、订阅和破坏性变更检测工具 → 并列写出；删去"Mirror any change to this rule in 另一入口"一句 |
| 运行时 | Dependency clients | Go 有 `secret provider`，Python 有 `inference calls` → 取并集 |
| 运行时 | When comparing … mature internal reference | `MQ` / `queue` → `MQ/queue` |
| 架构默认值 | Mature reference code is useful only | `transaction helpers, MQ lifecycle helpers` / `unit-of-work or transaction helpers, queue lifecycle helpers` → 取并集 |

另有两条规则（Internal RPC contracts、capability requirement）去掉指向另一入口的路径和"Mirror any change"一句后两侧逐字相同，脚本直接并入共享栏。

## 2. 资料迁移表

`identical` 表示改名前后内容哈希相同；`links-rewritten:N` 表示有 N 行只改了文件名引用；`reworded` 表示另改了一句措辞（两个 source-evidence-map 里"另一栈的架构技能"改为"本技能的另一栈"，四个 Python 资料里"不在一致性闸下"改为"单独的按栈文件"）。

| 旧路径（相对 `skills/`，省略 `references/`） | 新文件 | 结果 |
| --- | --- | --- |
| `go-microservice-architecture/event-driven-architecture.md` + `python-service-architecture/event-driven-architecture.md` | `event-driven-architecture.md` | merged |
| `go-microservice-architecture/multi-tenant-isolation.md` + `python-service-architecture/multi-tenant-isolation.md` | `multi-tenant-isolation.md` | merged |
| `go-microservice-architecture/data-platform-architecture.md` + `python-service-architecture/data-platform-architecture.md` | `data-platform-architecture.md` | merged |
| `go-microservice-architecture/api-security-boundaries.md` | `go-api-security-boundaries.md` | identical |
| `go-microservice-architecture/architecture-playbook.md` | `go-architecture-playbook.md` | links-rewritten:4 |
| `go-microservice-architecture/artifact-generation-architecture.md` | `artifact-generation-architecture.md` | identical |
| `go-microservice-architecture/audit-history-architecture.md` | `go-audit-history-architecture.md` | identical |
| `go-microservice-architecture/bulk-workflow-architecture.md` | `bulk-workflow-architecture.md` | links-rewritten:1 |
| `go-microservice-architecture/config-rule-routing-architecture.md` | `config-rule-routing-architecture.md` | identical |
| `go-microservice-architecture/cross-cutting-concerns.md` | `cross-cutting-concerns.md` | links-rewritten:1 |
| `go-microservice-architecture/data-modeling-and-migrations.md` | `go-data-modeling-and-migrations.md` | identical |
| `go-microservice-architecture/dependency-platform.md` | `dependency-platform.md` | identical |
| `go-microservice-architecture/developer-tooling-architecture.md` | `developer-tooling-architecture.md` | identical |
| `go-microservice-architecture/error-contract-architecture.md` | `error-contract-architecture.md` | identical |
| `go-microservice-architecture/http-gateway-architecture.md` | `http-gateway-architecture.md` | identical |
| `go-microservice-architecture/mq-consumer-architecture.md` | `mq-consumer-architecture.md` | identical |
| `go-microservice-architecture/notification-architecture.md` | `go-notification-architecture.md` | identical |
| `go-microservice-architecture/ops-checklist.md` | `ops-checklist.md` | identical |
| `go-microservice-architecture/performance-capacity-architecture.md` | `performance-capacity-architecture.md` | identical |
| `go-microservice-architecture/protobuf-contract-architecture.md` | `protobuf-contract-architecture.md` | links-rewritten:1 |
| `go-microservice-architecture/redis-cache-coordination.md` | `go-redis-cache-coordination.md` | identical |
| `go-microservice-architecture/release-runtime-readiness.md` | `release-runtime-readiness.md` | identical |
| `go-microservice-architecture/replay-comparison-architecture.md` | `go-replay-comparison-architecture.md` | identical |
| `go-microservice-architecture/runtime-observability.md` | `runtime-observability.md` | identical |
| `go-microservice-architecture/service-scaffold.md` | `service-scaffold.md` | identical |
| `go-microservice-architecture/source-evidence-map.md` | `go-source-evidence-map.md` | reworded:1 |
| `go-microservice-architecture/workflow-state-architecture.md` | `go-workflow-state-architecture.md` | identical |
| `python-service-architecture/ai-service-integration-boundaries.md` | `ai-service-integration-boundaries.md` | identical |
| `python-service-architecture/api-contract-and-schema.md` | `api-contract-and-schema.md` | links-rewritten:1 |
| `python-service-architecture/api-security-boundaries.md` | `python-api-security-boundaries.md` | identical |
| `python-service-architecture/architecture-playbook.md` | `python-architecture-playbook.md` | links-rewritten:4 |
| `python-service-architecture/async-execution-model.md` | `async-execution-model.md` | identical |
| `python-service-architecture/audit-history-architecture.md` | `python-audit-history-architecture.md` | links-rewritten:1+reworded:1 |
| `python-service-architecture/background-jobs-and-scheduling.md` | `background-jobs-and-scheduling.md` | identical |
| `python-service-architecture/batch-and-pipeline-architecture.md` | `batch-and-pipeline-architecture.md` | identical |
| `python-service-architecture/config-secrets-runtime.md` | `config-secrets-runtime.md` | identical |
| `python-service-architecture/data-modeling-and-migrations.md` | `python-data-modeling-and-migrations.md` | identical |
| `python-service-architecture/notification-architecture.md` | `python-notification-architecture.md` | links-rewritten:1+reworded:1 |
| `python-service-architecture/observability-and-ops.md` | `observability-and-ops.md` | identical |
| `python-service-architecture/packaging-runtime-readiness.md` | `packaging-runtime-readiness.md` | links-rewritten:1 |
| `python-service-architecture/redis-cache-coordination.md` | `python-redis-cache-coordination.md` | identical |
| `python-service-architecture/reliability-and-error-contract.md` | `reliability-and-error-contract.md` | identical |
| `python-service-architecture/replay-comparison-architecture.md` | `python-replay-comparison-architecture.md` | links-rewritten:1+reworded:1 |
| `python-service-architecture/source-evidence-map.md` | `python-source-evidence-map.md` | reworded:1 |
| `python-service-architecture/web-framework-boundaries.md` | `web-framework-boundaries.md` | identical |
| `python-service-architecture/workflow-state-architecture.md` | `python-workflow-state-architecture.md` | links-rewritten:1+reworded:1 |

合并的三个文件里，除共享区域和两个栈小节外：

- 原来两份文件头的"Sibling sync"和"Conforms to the parallel-stack references pattern"两段换成一段"Layout"，说明单文件结构和共享区域不得出现的三类栈专有词。"Sanitization boundary"一段原文保留。
- 原来每侧各一份的"Mirrored-section grep gate"合成一个 `## Shared-region grep gate`，放在两个栈小节之后。词表两侧在基线上相同，扫描止于第一个栈小节。三个文件的共享区域按各自的闸命令扫描均为零命中。
- `multi-tenant-isolation.md` 的"Topic-extension backlog"两侧在基线上相同，保留一份。

## 3. Skill Routing 逐条对照

| 旧条目 | Go | Python | 新入口位置 |
| --- | --- | --- | --- |
| 本技能管什么 | 有 | 有 | Routing 第 1 条。两侧列举的范围取并集 |
| 实现、改码、脚手架、生成、测试归开发技能；局部重构归开发技能；整服务重构留在架构；多阶段重构回 `product-rd-workflow`；不带限定的整服务重构进架构 | 有 | 有 | Routing 第 1、2、3 条 |
| 调试 | 归 `go-microservice-dev` | 先 `defect-diagnosis` | Routing 第 4 条，统一为先 `defect-diagnosis`。`go-microservice-dev` 自己的 `description` 本来就要求复现和定位先走 `defect-diagnosis`，所以这是对齐，不是新规则 |
| 跨阶段请求先走 `product-rd-workflow` | 有 | 有 | Routing 第 3 条 |
| 测试层选择先走 `testing-strategy` | 无 | 有 | Routing 第 4 条 |
| 推理、RAG、提示词等归 `llm-inference-integration` | 无 | 有 | Routing 表第 4 行 |
| 另一栈用另一个架构技能；除非明确做跨语言契约，否则不加载另一栈规则 | 有 | 有 | Routing 第 5 条：只加载服务所在栈的默认值 |
| 三个 `platform-*` owner 及本技能保留的服务侧面 | 有 | 有 | Routing 表前三行为压缩写法；每侧三条原文在规则文件"Platform boundary contract" |
| 只有明确针对既有仓库时才用仓库专属技能 | 有 | 有 | Routing 第 5 条 |
| 资料写判据与不变式，代码模式放开发技能 | 有 | 无 | Routing 最后一条 |
| 改实现必须遵守的规则前先点名下游 owner；跨栈适用时走 `skill-extraction-workflow` 并镜像或明确跳过 | 有 | 有 | Routing 最后一条。"镜像到另一个架构技能"改为"逐个栈小节和开发技能明确更新或跳过" |
| 高风险事项先走 `product-rd-workflow` 的高风险韧性闸 | 有 | 有 | Routing 第 3 条 |

两侧开头的定位段（不假设既有仓库；先按归属、数据真值、隔离、伸缩、发布节奏和回滚需要定边界）分别进了新入口的开头和 Method 第 1 步。

## 4. 有意不保留的内容

| 内容 | 理由 |
| --- | --- |
| 两个入口各 3 处"Mirror any change to this rule in 另一入口"和 Reference Loading 里"维护者改共享区域必须同时改两份文件" | 规则和共享区域现在各只有一份，这条义务没有对象了 |
| Reference Loading 里对三份镜像资料内容的长段列举 | 属于指针的说明文字，不是义务；各文件开头已写明自己的范围 |
| 三份镜像资料文件头里指向一致性闸脚本的句子 | 闸随镜像对一起退役 |

## 5. 被钉住的文字

| 钉住处 | 文字 | 现位置 |
| --- | --- | --- |
| 台账第 737 行的定位符 | `human sign-off only before a destructive one` | 新入口 Method 第 3 步；经迁移表解析到新路径后锚点仍命中 |
| `test_routing_pointer_integrity.sh` | `Python 服务重构`（frontmatter） | 新入口 `description`，并新增 `Go 服务重构` 一条 |
| 同上 | Go 依赖方向图的 5 条断言 | 改指 `go-architecture-playbook.md`，内容未动 |
| 台账其余 11 处指向旧技能资料的定位符 | 各自的锚点文字 | 经迁移表解析到新路径，锚点全部仍命中 |

## 6. 从单栈写法上升为共同方法的条目

方案把"两份核心流程里的栈无关条目"合并进共同方法。下面这些条目在旧入口里只有一侧写了，内容不依赖栈，新入口把它们放进了共同方法，对另一栈来说是新增的显式要求。两侧原文都在规则文件里按栈保留，没有改写。

| 新入口位置 | 条目 | 原来只在 |
| --- | --- | --- |
| 第 1 步 | 分层为 transport、application、domain、infrastructure、generated contracts；共享库只放基础设施关注点 | Go |
| 第 2 步 | 对外 API 模型与内部 RPC 模型在稳定性需求不同时分开 | Go |
| 第 3 步 | 跨服务读走 RPC/API 或显式读模型，不共享表写入；写数据访问代码前先定 schema、索引、唯一约束、迁移路径和分片键 | Go |
| 第 4 步 | 内部信任基于工作负载身份而不是网络位置；准入控制属于可靠性设计 | Go |
| 第 4 步 | 就绪检查通过后才注册接流量；就绪状态对外可观察；服务路径与管理、迁移、修复、批处理的超时预算分开 | Python |
| 第 5 步 | 包与运行时选择可复现；上线前定好部署资源、进程模型、并发、冒烟检查、回滚和迁移顺序 | Python |
| 第 5 步 | 生成命令写进仓库、可移植、不含本机绝对路径 | Go |

Node.js/TypeScript 一节的条目全部来自 `nodejs-service-dev` 现有约束，对应关系：运行时契约（其流程第 1 步）、事件循环与取消、请求上下文、出站客户端（第 2 步）、显式依赖与不加无依据的重试缓存（其硬规则）。"类型在运行时被擦除，边界上用运行时 schema 校验"一句由其"在归属边界校验不可信数据"和 Node 官方 TypeScript 文档合成，出处记在 `method-grounding.md`。
