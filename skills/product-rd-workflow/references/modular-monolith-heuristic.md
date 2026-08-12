# Modular Monolith vs Microservices — 决策启发

不是"monolith 不好 / microservice 好"的争论，是**给当前阶段的项目选对结构**的启发清单。早期项目错误起步成 microservice = distributed monolith（最差形态）；成熟项目错把 monolith 撑过承载 = team / 部署 / scaling 受限。

本 ref 给可观察 trigger 让团队知道**何时该 monolith / 何时该开始拆 / 不该拆**。

## 外部来源

- **Simon Brown**, "Modular Monolith" talks + *Software Architecture for Developers* (2014+) — modular monolith 概念命名
- **Sam Newman**, *Building Microservices* (2nd ed 2021, O'Reilly) — Ch.3 splitting the monolith + when not to
- **Martin Fowler**, "MonolithFirst" (martinfowler.com 2015) — start monolith, split when justified
- **DDD bounded context** (Evans 2003) — split boundary 的语义基础

---

## §1 何时 monolith 更合适（默认起点）

下列同时成立 → **modular monolith 起步**，不要 microservice。**数字阈值是本团队启发默认，非 Newman/Fowler/Brown 文献规定**；用证据覆盖默认（如 ops 成熟度足够 / 团队组织模式特殊 等）：

- **团队 < 15 人**（默认值；Conway's law 给方向但不给具体数）：1 个工程团队内部，service-per-team 切分通常无必要
- **bounded context 未稳定**：domain 模型还在变，service boundary 切了会反复挪
- **flow 内 transaction 强一致需要**：跨多 service 的事务复杂度（saga / outbox）超过单 DB transaction 收益
- **scale 尚未触界**：当前 / 预期 6 个月内单节点垂直扩展能撑（如 < 1k req/s / < 100k row table / < 数 TB 数据）
- **release cadence 同步**：features 跨多模块联动发布是常态，不是个别例外

### Modular monolith ≠ ball of mud
**关键纪律**让 monolith 仍可演化：
- **模块边界用 package / module 强制**：跨模块通信只走 public API 接口，不直接 `import` 内部
- **Module-level fitness function**（见 `testing-strategy/references/fitness-functions.md`）：阻止跨模块违规依赖
- **每模块自己的 DAL**：DB schema 按模块分组 / 表前缀
- **预留 service split 接口**：模块间通信用 in-process function call，但 signature 像 RPC（可序列化、避免共享 mutable state）

---

## §2 何时开始拆 service

下列**至少 2 个**同时成立 → 考虑开始拆某模块出去。**数字阈值是本团队启发默认（非文献规定），用证据覆盖**：

| Trigger | 信号 |
|---|---|
| **Team scaling** | 团队 > 15 人（启发），要按 product line / 子系统分团队独立 release |
| **Bounded context 稳定** | 该模块 6+ 个月没大改 boundary（启发），contract 清晰 |
| **Independent release cadence** | 该模块 release 频率与主体差量级显著（启发：5x+，如主体周级、该模块小时级）|
| **Scale heterogeneity** | 该模块 CPU / memory / DB load 比主体高量级显著（启发：10x+），需独立扩展 |
| **不同 tech stack 收益明显** | 该模块用别的语言 / runtime 收益 > 拆分代价（如 ML 服务需 GPU + Python；rest 是 Go web）|
| **独立故障隔离强需要** | 该模块挂不能拖垮主流程（如 payment / auth — 但要看真实流量分布，不是空想）|

**不是 trigger 的 trigger**（这些**不**该作拆分理由）：
- "感觉 monolith 太大了" — 量化 size 不是问题，coupling 才是
- "想用 X 新框架" — 拆 service 是大成本，新框架可在 monolith 内引入
- "面试问的都是 microservice" — 是 hiring 问题不是 architecture 问题
- "CTO/技术总监 push microservice" — 让 Ta 给量化的 trigger，不是 mandate

---

## §3 不要拆的反信号（hard stop）

下列任一成立 → **不**拆，先解决根因：

- 团队 < 10 人 → 拆了反而每人维护多 service，运维成本陡增
- bounded context 还在变 → 拆完发现切错位置，retrofit 比初始拆贵 3-5x
- 跨模块强一致 transaction 是核心需求 → 拆完上 saga / 分布式事务，复杂度爆炸
- 当前 ops / 可观察性基础设施 immature → 拆完 debug 黑盒。**最低 debug path** 要求：centralized log + 基础 metric + correlation ID + runbook；**distributed tracing 是 high-chatter / high-criticality 拆分必备**；service mesh 不是普遍前置（按场景按需）
- **distributed monolith warning signs**：所有 service 必须同步部署 / 共享 DB / 互相 sync 调用密集 → 是 monolith 被假装成 microservice，最差形态

---

## §4 决策清单（在 ADR 里用）

写 ADR "Service-X split from monolith" 时，§Context 段答这 7 问：

1. 当前团队人数 + service 拆出后由谁维护？（< 2 人 owning team → 危险）
2. 该模块 boundary 6 个月内变了几次？（> 1 次大变 → 暂缓）
3. 该模块独立 release 频率 vs 主体频率比？
4. 该模块对主体的 in-process call 路径数有多少？（高 = 拆后 RPC 噪声大）
5. 该模块当前 DB 是否独享 schema？还是与主体共享表？（共享 → 拆 service 前先拆 schema）
6. observability 基础设施满足该次拆分的 minimum debug path 吗？（参 §3 — central log + 基础 metric + correlation ID + runbook 是底线；distributed tracing 只在 high-chatter / high-criticality 拆分必备）
7. 拆完 rollback 路径是什么？（无 rollback 路径 → 拆是单程，慎用）

每问**给明确答案**或**标 N/A + 写 rationale**；未解决的 high-risk 项（如 1 + 6 — 维护者 owning team 缺 + 无 observability 基础）阻止 ADR Accepted。低风险拆分（如 vendor / runtime 隔离 / team-owned 抽取）部分问题 N/A 是常态。

---

## §5 渐进迁移 default menu（不是 big-bang，且不一定按下序）

如果当前 monolith 大且 §2 多 trigger 成立，下面是**常见 default 顺序**；真实迁移可能先拆 read replica / event stream / runtime 而非按 schema 起步。按场景选起手：

1. **强化模块边界**（数周）：先在 monolith 内把模块边界用 package / fitness function 锁死 — 这本身就解决很多问题，可能消除拆分需求
2. **抽 anti-corruption layer**（数周）：模块间通信接口标准化（in-process），signature 像 RPC
3. **抽 DB schema**（月级）：该模块用独立 schema / 独立 DB instance，但仍 in-process
4. **拆出 service**（月级到季度级）：上面 3 步都做完后，service 化只是部署形态变化，业务代码改动小
5. **观察 + 决定继续 or rollback**：拆完 N 个月看 §2 trigger 是否真消退，没消退 = 拆错了，回 monolith

每步独立可 ADR + rollback。big-bang 不可。

---

## §6 故意不借鉴

| 概念 | 原因 |
|---|---|
| Team Topologies 全套 operating model（Skelton 2019）| 本团队规模未到完整采用门槛 — 但**借 vocabulary**（team ownership boundary / cognitive load / stream-aligned vs platform team）在跨团队职责讨论时仍有用 |
| Service mesh / sidecar 选型决策 | 是拆 service 后的实施细节，归 `platform-service-connectivity` |
| Saga / outbox pattern 实现 | 是拆 service 后的具体技术，归 `go-microservice-architecture` / `python-service-architecture` |
| DDD strategic patterns 全套（context map / anticorruption layer / shared kernel 等）| 太学院；本 ref 取 bounded context 概念即可 |
