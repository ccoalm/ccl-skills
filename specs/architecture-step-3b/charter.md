# 步骤 3b 的提炼 charter 与目标映射

设计见 `specs/architecture-skill-consolidation/plan.md` 第 11 节。本文件在第一处技能改动之前写下。

## Charter

| 字段 | 内容 |
| --- | --- |
| Purpose | 防止两类已观察到的结果：架构设计请求进了 `product-rd-workflow` 后不加载 `software-architecture` 就直接写设计（基线 12/25）；加载了架构技能但设计文档不写截止时间、客户端装配和依赖方向（2/7、1/5、3/15） |
| Scope | `agent-context/session-start.md` 的入口路由行、`product-rd-workflow` 入口的架构路由行、`software-architecture` 第 6 步。不含：高风险请求先进 `product-rd-workflow` 的顺序、`tighten-doc`、评分表、各栈 dev 技能 |
| Depth | 定向检查：57 次有效基线运行的记录、工具调用流和设计文档原文；三个入口文件的相关行 |
| Result classification | failure/correction。依据：基线里按加载与否拆开的计数（方案 11.1） |
| Matching analysis | 触发与路由：常驻路由块没有架构这一行，`product-rd-workflow` 入口只提到一次架构技能且转交闸只管多 owner 设计。缺机械控制：架构技能入口把栈约束写成实现规则，没有对设计文档的产出要求。反事实检验由候选臂完成：只改这两处，其余不变 |
| Failure mode | 弱提炼会再加一段入口文字去复述已经在入口里的约束，或针对只量了一边的评分表做优化 |
| Lifecycle impact | 只影响设计阶段。实现、测试、发布阶段的 owner 不变 |
| Evidence plan | 先看产出物：基线运行目录（判分、运行记录、工具调用流、设计文档）；再看三个入口文件；评分表与样例只读不改 |
| Completion standard | 方案 10.6 与 11.3 的通过线；路由静态分析无阻断；一次独立评审加一次对抗挑战；整条 lane 在 Linux 上通过 |

## 目标映射

| owner | 方向 | 状态 | 文件或理由 |
| --- | --- | --- | --- |
| 常驻路由层 | 上游 | updated | `agent-context/session-start.md` 入口路由第一行 |
| `product-rd-workflow` | 上游，协调方 | updated | 入口「Architecture routing」一行；同时删去下一行里重复的那次提及 |
| `software-architecture` | 目标 | updated | 第 6 步新增设计文档的运行时契约清单 |
| `go-microservice-dev`、`python-service-dev`、`nodejs-service-dev` | 下游 | unchanged | 清单只约束设计文档写什么；这些约束的实现规则已在各自入口和架构技能的栈默认值里，没有改 |
| `testing-strategy` | 下游 | unchanged | 不改变测试层的选择 |
| `tighten-doc` | 同级 | unchanged | 收尾行为不在本步范围 |
| `skill-extraction-workflow` | 流程 | unchanged | 本步没有暴露提炼流程自身的缺口 |
| 已安装的外部技能包 | — | not-applicable | 没有外部包拥有后端架构设计的路由 |

栈间泛化：清单五项不分语言，Go、Python、Node.js/TypeScript 共用；只有第 1 项举了 Go 的传递方式作例子。

## 第二版的范围变更

第一版没有过字节线，且评测记录里看到带插件的设计文档留给请求方的问题和虚构的人员角色更多（方案 11.5）。范围因此增加两项，目标映射里的 owner 不变：

| owner | 状态 | 文件或理由 |
| --- | --- | --- |
| 常驻路由层 | updated | 入口路由第一行改为只出设计的后端请求从 `software-architecture` 开始；安全四问一段改为自行作答 |
| `software-architecture` | updated | Routing 一节：只出设计的请求不先加载 `product-rd-workflow`；第 6 步新增设计者自行解决的三条 |
| `product-rd-workflow` | unchanged（相对第一版） | 高风险闸的条文没有改，它本来就写在实现或上线之前 |
| `requirement-doc-writer` | unchanged | 安全四问的完整规则在它的参考资料里，没有要求向请求方提问，不需要改 |
| `tighten-doc` | unchanged | 把技能名换成角色发生在它的收尾里，但根因是设计文档写了技能名；改在源头 |

## 第三版：统一从 `product-rd-workflow` 进入，并给它的入口瘦身

起因是请求方的裁决：后端设计请求统一从 `product-rd-workflow` 进入，成本靠优化它本身解决，不靠绕开它。所以撤回第二版的路由改动，保留运行时契约清单和设计者自行解决的三条，再给 `product-rd-workflow` 的入口瘦身。本节在入口的第一处改动之前写下。

| 字段 | 内容 |
| --- | --- |
| Purpose | 设计类请求经 `product-rd-workflow` 进入时，读到的入口字节明显下降，同时保持第一版已达到的三条栈约束（方案 11.4）和第二版的「不停下来问」效果（方案 11.6） |
| Scope | `agent-context/session-start.md` 入口路由第一行、`software-architecture` 的 Routing 一节（两处撤回）；`product-rd-workflow/SKILL.md` 的整体结构：入口只留路由、各阶段的触发点和被钉住的规则行，阶段细则原文移到按触发点加载的参考文件。不含：`tighten-doc`、评分表、`design-review-gate-mechanics.md` 的签字一节（另一轮） |
| Depth | 定向检查：基线 `base` 臂 25 次加载过 `product-rd-workflow` 的有效运行里，加载之后的工具调用和 agent 文字；入口全文按块读完；仓库内所有钉住该入口的脚本、登记行锚点、契约锚点和同步指针 |
| Result classification | failure/correction。依据：第一版统一走 `product-rd-workflow` 时加载字节比基线多约 25 KB，没过 10.6 的字节线（方案 11.4） |
| Matching analysis | 入口 75,578 字节，其中「Workflow」一节 40 KB，大部分是实现、验证、落地阶段的规则，设计阶段用不到；而且这些规则多数已有专门的参考文件，入口是在复述。基线 25 次运行加载入口后没有一次读参考资料，agent 文字里能看出用到的只有 `proposed-next` 收尾约定（25/25）。反事实：入口只留设计阶段需要的部分，设计会话读到的字节应接近入口新体量 |
| Failure mode | 弱瘦身会删掉被钉住或被登记行锚定的规则，或把实现期的硬规则移到没人会去读的地方而入口不再指向它；也可能为了过字节线把设计闸本身移走 |
| Lifecycle impact | 所有经 `product-rd-workflow` 的阶段都受影响：入口变短，阶段细则改为在阶段转换时加载。规则内容不变，按零丢失义务表核对 |
| Evidence plan | 先看产出物：基线运行记录（上面的计数）；再看入口全文和现有参考文件，逐条确认移走的文字在参考文件里原样存在；钉点用 `git grep -F` 按路径搜 |
| Completion standard | 零丢失义务表无遗漏；`check-ccl-skills.sh` 和钉住入口的各套件通过；候选臂按 10.6 原文的通过线判定；一次独立评审、一次对抗挑战、之后改动的一次增量复查；整条 lane 和 heavy 在 Linux 上通过 |

| owner | 方向 | 状态 | 文件或理由 |
| --- | --- | --- | --- |
| 常驻路由层 | 上游 | updated | 入口路由第一行回到「backend design also loads **software-architecture** before drafting」 |
| `software-architecture` | 目标 | updated | Routing 一节恢复高风险请求先进 `product-rd-workflow`；第 6 步的清单和三条保留 |
| `product-rd-workflow` | 协调方 | updated | 入口瘦身；阶段细则移到参考文件，入口保留触发点和加载指针 |
| 各栈 dev 技能、`testing-strategy`、`code-review` | 下游 | unchanged | 规则内容不变，只是 `product-rd-workflow` 内的位置变了；它们指向 `product-rd-workflow` 某一节的说法要逐条检查 |
| `tighten-doc` | 同级 | unchanged | 不在本轮范围 |
| `skill-extraction-workflow` | 流程 | unchanged | 本轮按它已有的按触发点放置规则做，没有暴露它自身的缺口 |
