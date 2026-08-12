# 自动化测试方案

> 用例在飞书多维表格，测试代码用辅助库标记 `tc("TC-XX")`，CI 自动出飞书报告，失败时退非零。<br>
> 一条命令：`make report-run`。

## 按角色找

| 你是谁 | 看哪段 |
| --- | --- |
| 产品 / 写用例的人 | 输入源 → 六个组件 |
| 写测试代码的人 | 4 端辅助库 + 配套手册 §3 |
| CI 维护 | CI 与本地差异 + 硬规则 |
| 新人通读 | 从头看到尾，约 5 分钟 |

## 适用边界

| 适用 | 不适用 |
| --- | --- |
| 需要用例库 + 自动化测试 + 报告的项目（web / 小程序 / app / 运营后台 / 后端服务） | 一次性脚本 / 研究 spike / 总测试数 < 10 / 个人项目不跨人协作 |

---

## 六个组件

> 用例数据分散在 6 处，分工明确才不会改错地方。

| 组件 | 作用 | 谁说了算 |
| --- | --- | --- |
| 飞书多维表格 | 用例库（状态、信息流转、跟进人） | **用例状态唯一权威** |
| `test/cases/all.md` | 多维表格的本地镜像（仅定义字段） | 人读视图，供 review / 对比 |
| `test/cases/test-matrix.md` | 模块 × 测试层（单元 / 契约 / 集成 / 端到端 / 人工 / 阻塞） | 编排计划 |
| `test/results/tc-map.jsonl` | 测试代码 → 用例 ID 映射文件 | 关联 JUnit 用 |
| `test/results/last-run.json` | 上次跑的快照 | 与上次跑对比 |
| 飞书报告文档 | 自动生成的报告 | 展示层 |

> 测试用例 Base、字段语义、内容和记录写回都归 `test-artifact-management`，具体表操作使用 `lark-base`。已有 Base 时复用；通用 Wiki 或其他业务表按需使用 `lark-wiki` / `lark-base`，不要顺带初始化整套项目空间。

---

## 输入源（5 种）

> 用例从哪儿来？任意组合，多源时按规则仲裁。

| 源 | 用途 | 提取重点 |
| --- | --- | --- |
| **A 需求文档**（飞书） | 产品意图、范围、优先级 | 功能列表、验收、角色权限 |
| **B Figma 设计稿** | 可见状态、交互路径 | 状态家族、设计 token、可恢复性提示 |
| **C 仓库代码** | 当前真实行为 | API 契约、业务规则、错误路径 |
| **D API 契约**（OpenAPI / proto / GraphQL / IDL） | 服务接口 | 接口→功能点；必填字段→负例；oneOf 分支；流式 RPC |
| **E bug 报告**（先 defect-diagnosis 出 RCA） | 回归用例 | 报告字段→用例字段（标 `[回归]` + P0） |

> ⚠️ **多源冲突仲裁**<br>
> 代码赢"当前行为"。Figma 赢"可见状态"。文档赢"业务意图"。契约赢"已发布契约"。bug 报告 > 任何源（回归内容）。**冲突要记录，不能默默对齐。**

---

## 数据流

```
源（A/B/C/D/E）
   │
   ▼  test-artifact-management
多维表格 + test/cases/all.md + test/cases/test-matrix.md
   │
   ▼  各端开发技能写测试代码（用辅助库标记 tc("TC-XX")）
JUnit XML + test/results/tc-map.jsonl
   │
   ▼  make report-run → gen_report.py
   ├─ 同步多维表格状态
   ├─ 写飞书报告文档
   ├─ 保存 last-run.json
   └─ 退出码（失败时非零）
```

---

## CI 与本地差异

> 命令、报告内容一致；CI 多三件事：strict mode、并发序列化、自动发 MR 评论。

| 维度 | 本地 | GitLab CI |
| --- | --- | --- |
| 命令 | `make report-run` | `make report-run`（同） |
| lark-cli 身份 | user | bot（CI 环境自动检测） |
| 映射文件写失败 | 默认尽力而为 | `TC_SIDECAR_STRICT=1`，失败即 fail |
| MR 评论 | 无 | `after_script` 自动发（红、绿都发） |
| last-run | 本地文件 | GitLab cache 按 (unit, branch) 稳定 key + 默认分支兜底 |
| 测试失败 | 开发自己决定 | 卡 MR 合入 |
| 并发同 (unit, branch) | 单进程 | `resource_group` 序列化 |

---

## 4 端辅助库

> 4 个栈各一个辅助库。API 形态不同但做同一件事：**在测试注册时**把用例 ID 写映射文件。<br>
> 注册时（不是运行时）是关键——这样 skip 的测试也能挂上用例。

| 栈 | API | 注册时机 | skip 是否记录 |
| --- | --- | --- | --- |
| Python (pytest) | `@pytest.mark.tc("TC-XX")` | 收集阶段 | ✅ |
| Go | `tc.Mark(t, "TC-XX")` 首行；包装层用 `tc.MarkAt(t, n, "TC-XX")` | 运行时（`t.Skip` 之前） | ✅（前置约定） |
| Vitest / Jest | `createTcSuite(test, describe)` 工厂；配 `tcTest` / `tcDescribe` | 注册阶段 | ✅（含 `.skip` / `.skipIf` / `.todo` / `.each` / `.concurrent`） |
| Dart / Flutter | `tcTest([...], desc, fn, skip: '...')` 包装层 | 注册阶段 | ✅ |

详见 `test-artifact-management/references/tc-marker-conventions.md`。

---

## 相关技能分工

| 技能 | 职责 |
| --- | --- |
| `test-artifact-management` | 源 → 用例 → 多维表格 → 测试矩阵 → 报告（本方案主体） |
| `testing-strategy` | 用例落到哪一层 / 怎么验证 / 夹具与替身 |
| 各端开发技能 | 实际测试代码（pytest / go test / vitest / flutter test） |

---

## 硬规则

> ⚠️ 违反会导致报告错误或 CI 误判，不是建议。

**设计前提**
- 用例 ID 在单个多维表格内唯一；跨部署单元不要求唯一
- 每个部署单元独立配置（web / 小程序 / app / 运营后台 / 每个后端服务），各一份配置 + 各一个多维表格 + 各一份飞书报告
- `废弃` 是永久终态，自动化不修改；误标用 `--unfreeze` + 必填 `--unfreeze-reason`

**使用纪律**
- 用例 ID 不要内嵌测试函数名；用辅助库注册保持函数名干净
- CI 必须 `TC_SIDECAR_STRICT=1`；映射文件写失败即 fail（防多维表格静默过期）
- `report-run` 目标不能写成 `report-run: test` 前置依赖（make 会被红测试短路）；用 `-$(MAKE) test` 写在 body 里
- 信息流转默认保留最近 100 条（`TC_INFO_KEEP=0` 改无限）

---

## 报告内容（按顺序）

1. **总览** — 通过 / 失败 / 阻塞 / 跳过 / 代码覆盖率 / 与上次跑对比
2. **按模块统计**
3. **P0 未通过明细**
4. **P1 / P2 失败明细**
5. **未链接 TC 的测试统计** — 没标记 `tc(...)` 的测试集合
6. **孤儿用例 ID** — 测试标了 ID 但多维表格没记录 / 已废弃的
7. **📋 覆盖与残余风险** — 弱模块 / P0 未测 / 基础设施失败 / 未关联但失败的测试
8. **发布建议** — ✅ 全过 / ⚠ 仅非 P0 失败 / ❌ P0 未通过或未测试

---

## 配套文档

> 本方案是**自动化测试用例 + 报告 harness**这一片。"测试落哪层、自动化 e2e 怎么做"见 [写测试与测试用例手册](testing-handbook.md)（总览三种自动化）+ `testing-strategy`。

- **日常用法**：见《自动化测试使用手册》
- **模板源（参考用，复制到项目即可）**：ccl-skills 仓库的 `skills/test-artifact-management/` —— `SKILL.md`（完整规则）、`references/tc-marker-conventions.md`（辅助库接入）、`references/ci_templates/gitlab-ci.yml`（GitLab CI 示例）
- 实际项目使用时所有脚本与辅助库**复制到仓库本地**（推荐 `test/scripts/` 和 `test/tc.{py,go,ts,dart}`）；CI 不依赖任何全局路径
