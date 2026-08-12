# Quality Attributes — 架构 trade-off 共同词汇

架构选择本质是 trade-off — A 增强常对 B 让位。没共同词汇就只能口头辩论 "好不好"。本 ref 提供 ISO/IEC 25010 + Bass et al. SEI 经典分类作 trade-off 讨论的 baseline 词汇。

不是新方法论，是 vocabulary checklist — 用在 ADR Context/Consequences、arch review、design proposal。

## 外部来源

- **ISO/IEC 25010:2023** (Systems and software Quality Requirements and Evaluation, SQuaRE; 2023-11 ed.2，撤回 2011 版) — 9 个 product quality characteristics 标准；本 ref §2 列的是常用 8 类 + sub-characteristics 子集，未完全 enumerate 2023 全部 9 类与所有 sub-characteristic
- **Bass / Clements / Kazman**, *Software Architecture in Practice* (4th ed 2021, SEI Series, Addison-Wesley) — quality attribute scenarios + tactics
- **Mark Richards / Neal Ford**, *Fundamentals of Software Architecture* (O'Reilly 2020) — architecture characteristics taxonomy

---

## §1 为什么用这套词汇

**反例**（无 vocabulary）：
> "这个方案不够 robust" / "我觉得 maintainability 更重要" / "这样性能会差"

**用 vocabulary 后**：
> "方案 A 优化 throughput（每秒 N req）但牺牲 modifiability（新加 field 需改 3 处）；当前阶段（feature 探索期）modifiability > throughput，建议 A 修 throughput 留后期。"

vocabulary 让 trade-off 具体到 attribute pair + 当前 priority，可在 ADR Consequences 字段精确记录。

---

## §2 ISO 25010 八大类 + 子类

| 顶级 attribute | 子类（常用）|
|---|---|
| **Functional suitability** | functional completeness / correctness / appropriateness |
| **Performance efficiency** | time behavior（latency / throughput）/ resource utilization / capacity |
| **Compatibility** | co-existence / interoperability |
| **Usability** | learnability / operability / accessibility / UI aesthetics / user error protection |
| **Reliability** | maturity / availability / fault tolerance / recoverability |
| **Security** | confidentiality / integrity / non-repudiation / authenticity / accountability |
| **Maintainability** | modularity / reusability / analyzability / modifiability / testability |
| **Portability** | adaptability / installability / replaceability |

加 Bass et al. 常用补充：
- **Modifiability** = maintainability 子类，但本身是常用 trade-off 轴
- **Deployability** = 不在 25010，业内常补（独立 release 频率 / 灰度能力 / rollback 时长）
- **Observability** = 不在 25010，业内常补（log / metric / trace 三件套覆盖度）

---

## §3 常见 trade-off tensions（常见张力，非铁律）

下表是设计 / 评审中常见的 trade-off 张力对。**注意**：不是物理铁律 —
- CAP 在 partition 时才强制 C-A 二选；正常 operation 下两者可共存
- Throughput / Latency 是同一系统不同 workload / 设计下的 trade-off，不是绝对反相关（Little's Law 把它们关联）

把这些当 "**讨论起点 + 常见张力提醒**"，不是 "选 A 必牺牲 B" 的数学律。

| Trade-off 对 | 典型选择 |
|---|---|
| **Security vs Usability** | 强 auth flow vs onboarding 摩擦低 |
| **Performance vs Modifiability** | hand-tune SQL/缓存 vs 通用 ORM 抽象 |
| **Consistency vs Availability** | 强一致 vs partition 时高可用（CAP 经典）|
| **Time-to-market vs Maintainability** | 快上 vs 长期改动成本低 |
| **Throughput vs Latency** | batch 大 vs 单请求小 |
| **Flexibility vs Simplicity** | plug-in 架构 vs 单一实现 |
| **Cost vs Reliability** | 单 region vs 跨 region active-active |

ADR Context 段应**声明本决定哪些 attribute 优先**（最多 3 个 — > 3 = 没真选）；Consequences 段写**为优先项让位的 attribute** + 后果可承受度。

---

## §4 在 ADR / arch review 怎么用

### 4.1 Context 段
> "当前阶段（pre-PMF 探索期）我们优先 modifiability + time-to-market；可接受 performance 和 operational complexity 的暂时妥协。"

### 4.2 Consequences 段
> "正面：modifiability 高（新字段 < 1 day）/ 部署简单（单 binary）。负面：performance 中等（p99 ~300ms 而非目标 100ms）/ scalability 受限（垂直扩展上限 ~10x 当前流量）。两者 6 个月内可承受；超过则触发 §5 fitness function 警报。"

### 4.3 arch review 用 quality attribute scenarios（Bass et al.）
每条 scenario 含 6 字段：source / stimulus / artifact / environment / response / response measure。

例：
> source: 新订单 burst<br>
> stimulus: 1000 req/s 持续 5 分钟<br>
> artifact: order-service<br>
> environment: normal operation<br>
> response: 全 request 处理完 + 无数据丢失<br>
> response measure: p99 < 500ms, error rate < 0.1%

scenario 比"performance 要好"具体得多，可作 acceptance 测试 input（→ §5 fitness functions）。

---

## §5 与现有 skill 的映射

| Attribute 类 | 谁验证 / owner |
|---|---|
| Functional suitability | `testing-strategy` + stack-dev 单测 |
| Performance efficiency | `testing-strategy` (perf 测试段) + `platform-observability` (运行时监控) |
| Reliability / availability | `platform-release-engineering` + `platform-service-connectivity` |
| Security | （目前散在各 skill；待将来抽独立的安全评审 skill）|
| Maintainability / Modifiability | code review + `testing-strategy/references/fitness-functions.md` |
| Deployability | `platform-release-engineering` |
| Observability | `platform-observability` |

---

## §6 故意不借鉴

| 概念 | 原因 |
|---|---|
| ISO 25010 完整 sub-characteristics 全 enumerate（~31 个）| 太细；§2 列的子类够日常用 |
| ATAM (Architecture Tradeoff Analysis Method, SEI 2000) 完整流程 | 适合大企业 ~10 人参与的 architecture review，本团队规模过 heavy |
| CBAM (Cost Benefit Analysis Method) | 同 ATAM，重；本团队用 ADR Consequences 段直接记 trade-off 即可 |
