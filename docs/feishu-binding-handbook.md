# 飞书绑定手册：全场景 × 飞书归位地图

研发生命周期产物可以归位到飞书 Wiki 和多维表格，但不要求预先初始化固定的项目空间。通用 Wiki/Base 操作使用 `lark-wiki` / `lark-base`；测试用例 Base、内容与记录归 [`test-artifact-management`](../skills/test-artifact-management/SKILL.md)，CI 执行策略归 [`testing-strategy`](../skills/testing-strategy/SKILL.md)。

## 按角色找

| 你是谁 | 看哪段 |
|---|---|
| 第一次接触飞书绑定 | [总览](#总览) → [飞书侧承载](#飞书侧承载按需参考拓扑) |
| 想知道我的工作产物去哪 | [按生命周期阶段](#按生命周期阶段) |
| 想知道某个 skill 跟飞书的关系 | [按 skill 归位](#按-skill-归位) |
| 给新仓接入 | [新仓接入路径](#新仓接入路径) |
| CI 反写排错 | [鉴权与失败排查](#鉴权与失败排查) |

---

## 总览

研发数据三个 SoT：

| SoT | 内容 | 形态 |
|---|---|---|
| **Git 仓库** | 代码、AGENTS.md、技术方案、CI 配置 | 文本 |
| **飞书 Wiki 项目空间** | 需求 / 用例 / 批次 / 报告 / bug / 提测 | 多维表格 + Wiki Doc |
| **CI runner** | 测试通过/失败、构建产物、commit | 临时，写回飞书后留痕 |

**硬规则**：

1. 飞书是需求 / 用例 / 提测的 SoT；Git 是代码与 agent 契约 SoT
2. **仅 CI 写** 测试报告、用例状态
3. MVP 期允许部分产物 `feishu-deferred`，证据写到对应 plan，不强制每条同步

---

## 飞书侧承载（按需参考拓扑）

```
<root_wiki_token>/                              ← 已有或按需创建的项目空间根
└── {repo_name}/                                ← 仓节点（= Git 仓库名）
    ├── README                                  ← Wiki Doc：仓库 5 段门面
    ├── 需求/
    │   └── 需求清单 (多维表格)                  ← 需求 ID/标题/状态/版本
    ├── 测试/
    │   ├── 测试用例 Base（默认表）              ← 用测试层级字段区分功能/接口/单测
    │   ├── 批次清单 (多维表格)                  ← 跑批 ID/关联需求/状态
    │   ├── 测试报告 Doc / CI artifact ⭐       ← 通过失败/MR/触发与残余风险
    │   └── bug 清单 (多维表格)                  ← bug ID/严重度/状态
    ├── 提测/
    │   └── 提测文档库 (多维表格)                ← 提测 ID/轮次/分支/commit
    └── 归档/                                   ← 历史决策/复盘 Wiki Doc
```

测试用例字段契约见 [`test-artifact-management/references/bitable-setup.md`](../skills/test-artifact-management/references/bitable-setup.md)；其他表由各领域 owner 按实际需求定义，不再维护全局六表 schema。

---

## 按生命周期阶段

### 阶段 1：需求与方案

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| 需求清单行 | `需求清单` 多维表格 | [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md) | 人手 / 未来 omo req | 需求确立 |
| 需求 PRD | `需求/REQ-YYYY-NNN-vX.Y` Wiki Doc | [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md) + [`tighten-doc`](../skills/tighten-doc/SKILL.md) | 人手 / lark-cli | 需求评审前 |
| 跨模块技术方案 | `需求/方案-XX` Wiki Doc | [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md) 技术设计 gate | 人手 | 技术评审前 |
| 风险标签 | 需求 Doc 元数据 / 评审记录 | [`feature-risk-router`](../skills/feature-risk-router/SKILL.md) | 人手记录 | 立项 |
| 算法上线材料 | `需求/算法上线-XX` 或独立 Wiki | [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md)（算法上线 SOP） | 人手 | 算法评审 |

### 阶段 2：设计与契约

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| UI/UX 设计走查记录 | `需求/<REQ>-design-review` Wiki Doc | [`product-ui-ux-design`](../skills/product-ui-ux-design/SKILL.md) | 人手 | 设计验收 |
| API 契约 / IDL | Git 仓内（不进飞书） | [`go-microservice-architecture`](../skills/go-microservice-architecture/SKILL.md) / [`python-service-architecture`](../skills/python-service-architecture/SKILL.md) | git commit | 契约评审 |
| 数据库 schema / migration | Git + 提测文档库的"数据库变更"字段 | [`go-microservice-dev`](../skills/go-microservice-dev/SKILL.md) / [`python-service-dev`](../skills/python-service-dev/SKILL.md) | git + 提测时人填 | 改 schema 时 |

### 阶段 3：用例与测试

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| 测试用例 | 测试用例 Base 的默认表（用测试层级字段区分功能/接口/代码单测） | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | `lark-base` / lark-cli | 编码前 |
| 测试策略 / 测试矩阵 | `test/cases/test-matrix.md` + 测试用例 Base 字段 | [`testing-strategy`](../skills/testing-strategy/SKILL.md) | git + 多维表格 | 编码前 |
| 跑测批次 | `批次清单` 多维表格 | [`testing-strategy`](../skills/testing-strategy/SKILL.md) | 跑批时填 | 提测前 |
| **测试报告** ⭐ | 测试报告 Doc / CI artifact | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | 仓内 `gen_report.py` 写报告；[`testing-strategy`](../skills/testing-strategy/SKILL.md) 定义执行与证据语义 | 每次 MR / push |
| **测试用例状态回写** ⭐ | 测试用例 Base 默认表的"状态"字段 | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | 仓内 `gen_report.py --sync` 写状态；[`testing-strategy`](../skills/testing-strategy/SKILL.md) 定义执行与结果语义 | 每次 CI 跑完 |

### 阶段 4：缺陷与诊断

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| bug 行 | `bug 清单` 多维表格 | [`defect-diagnosis`](../skills/defect-diagnosis/SKILL.md) | 人手 / 飞书 OpenAPI | RCA 后 |
| RCA 报告 | `归档/RCA-<ts>` Wiki Doc | [`defect-diagnosis`](../skills/defect-diagnosis/SKILL.md) | 人手 | 修复后 |
| 回归 TC | 测试用例 Base 加新行（标 `[回归]` + P0） | [`test-artifact-management`](../skills/test-artifact-management/SKILL.md)（从 bug 生成） | lark-cli | bug 关闭前 |

### 阶段 5：提测与上线

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| 提测行 | `提测文档库` 多维表格 | [`release-doc-writer`](../skills/release-doc-writer/SKILL.md) | 人手 | 提测时 |
| 提测 Doc | `提测/REQ-XX-vY-roundN` Wiki Doc | [`release-doc-writer`](../skills/release-doc-writer/SKILL.md) | 人手 | 提测时 |
| 发布门审批记录 | 提测 Doc / 需求 Doc 评论区 | [`feature-risk-router`](../skills/feature-risk-router/SKILL.md) | 人手 | 上线前 |
| 灰度 / 回滚记录 | 提测 Doc | [`platform-release-engineering`](../skills/platform-release-engineering/SKILL.md) | 人手 | 灰度 / 回滚 |

### 阶段 6：复盘与沉淀

| 产物 | 飞书位置 | Owner skill | 写入方式 | 时机 |
|---|---|---|---|---|
| 复盘 Doc | `归档/post-mortem-<topic>-<ts>` Wiki Doc | [`skill-extraction-workflow`](../skills/skill-extraction-workflow/SKILL.md) | 人手 | 事故后 |
| skill 沉淀 | Git 仓内 `skills/*/SKILL.md` + references | [`skill-extraction-workflow`](../skills/skill-extraction-workflow/SKILL.md) | git commit | 复盘后 |

---

## 按 skill 归位

按 skill 跟飞书的关系分 4 档。

### A. 飞书写入主角

| Skill | 飞书行为 | 触发 |
|---|---|---|
| `lark-wiki` / `lark-base` | 按请求创建或维护通用 Wiki 节点与业务 Base | 人手 / 按需 |
| [`test-artifact-management`](../skills/test-artifact-management/SKILL.md) | 初始化/复用并维护测试用例 Base、字段、记录、状态同步和报告链路 | 人手 / CI 派生 |

### B. 产物有飞书归位（skill 主体在 Git，产物可写飞书）

| Skill | 飞书归位 | 写入方式 |
|---|---|---|
| [`release-doc-writer`](../skills/release-doc-writer/SKILL.md) | 提测 / 上线文档（可写入飞书 Wiki） | 人手 |
| [`testing-strategy`](../skills/testing-strategy/SKILL.md) | 测试策略、矩阵与执行证据（供测试用例和报告链路消费） | 间接 / CI |
| [`defect-diagnosis`](../skills/defect-diagnosis/SKILL.md) | bug 诊断结果与 RCA（可写入业务 Base 或 Wiki） | 人手 |
| [`product-rd-workflow`](../skills/product-rd-workflow/SKILL.md) | 需求清单 + 技术方案 Doc（PRD 正文归下面的 requirement-doc-writer）| 人手 |
| [`requirement-intent`](../skills/requirement-intent/SKILL.md) | 澄清记录、问题池、待定决策 Doc（挂需求/）| 人手 |
| [`requirement-baseline`](../skills/requirement-baseline/SKILL.md) | 现状盘点 Doc（挂需求/）| 人手 |
| [`requirement-scope`](../skills/requirement-scope/SKILL.md) | 改动范围 / 非目标 / 版本切片，写进需求 Doc | 人手 |
| [`requirement-doc-writer`](../skills/requirement-doc-writer/SKILL.md) | PRD Doc（挂需求/）| 人手 |
| [`multi-perspective-research`](../skills/multi-perspective-research/SKILL.md) | 调研简报 Doc（挂需求/ 或技术方案/）| 人手 |
| [`product-ui-ux-design`](../skills/product-ui-ux-design/SKILL.md) | 设计走查 Doc（挂需求/） | 人手 |
| [`feature-risk-router`](../skills/feature-risk-router/SKILL.md) | 风险标签写在需求/提测 Doc 元数据 | 人手 |
| [`tighten-doc`](../skills/tighten-doc/SKILL.md) | 不直接写飞书；润色后人推 | 间接 |
| [`agents-file-coverage-gate`](../skills/agents-file-coverage-gate/SKILL.md) | 不写飞书；扫 AGENTS.md 覆盖 | — |

### C. 实现型（产物在 Git，CI 间接写飞书）

| Skill | Git 产物 | CI 关联 |
|---|---|---|
| [`go-microservice-architecture`](../skills/go-microservice-architecture/SKILL.md) / [`go-microservice-dev`](../skills/go-microservice-dev/SKILL.md) | 代码 + IDL | 测试结果→测试报告 |
| [`python-service-architecture`](../skills/python-service-architecture/SKILL.md) / [`python-service-dev`](../skills/python-service-dev/SKILL.md) | 代码 | 同上 |
| [`web-react-dev`](../skills/web-react-dev/SKILL.md) | 代码 | 同上 |
| [`app-cross-platform-dev`](../skills/app-cross-platform-dev/SKILL.md) | 代码 | 同上 |
| [`miniapp-product-dev`](../skills/miniapp-product-dev/SKILL.md) | 代码 | 同上 |
| [`terminal-cli-dev`](../skills/terminal-cli-dev/SKILL.md) | 代码 | 同上 |
| [`llm-inference-integration`](../skills/llm-inference-integration/SKILL.md) | 代码 + eval | eval 结果可挂算法上线 Wiki |

### D. 平台 / 横切（产物不进飞书）

| Skill | 边界 |
|---|---|
| [`platform-observability`](../skills/platform-observability/SKILL.md) | dashboards / alerts 在监控系统 |
| [`platform-service-connectivity`](../skills/platform-service-connectivity/SKILL.md) | 配置在 mesh / config-center |
| [`multi-agent-delegation`](../skills/multi-agent-delegation/SKILL.md) | 元能力，不产物 |
| [`worktree-isolation`](../skills/worktree-isolation/SKILL.md) | git 操作，不产物 |
| [`skill-extraction-workflow`](../skills/skill-extraction-workflow/SKILL.md) | 沉淀回 Git skills |
| [`code-review`](../skills/code-review/SKILL.md) | review 结果在 PR/MR 评论 |
| [`release-coordination`](../skills/release-coordination/SKILL.md) | 发版编排走 Git / CI（tag、pipeline 证据）；文档正文归 release-doc-writer |
| [`grill-me`](../skills/grill-me/SKILL.md) | 拷问在会话里进行，结论回到对应产品需求产物 |

---

## 新仓接入路径

新仓不预建固定六表空间。需要测试用例管理时走以下路径：

```
Phase 1: test-artifact-management + lark-base        ← 复用或初始化测试用例 Base
Phase 2: test-artifact-management 报告/CI 模板       ← 按目标技术栈接入
人工:    CI secret / 目标 Base 文档应用权限
Phase 3: CI 自动同步状态和报告              ← 有需要才启用
```

测试执行栈由 `testing-strategy` 和对应开发技能决定；`test-artifact-management/references/ci_templates/` 提供报告链路模板，使用前按仓库实际命令调整。

通用 Wiki 目录或需求、缺陷、提测等业务表，仅在对应工作实际需要时通过 `lark-wiki` / `lark-base` 创建。

---

## 既有六表项目迁移

删除 `feishu-project-init` 不会删除已建飞书资源，也不会自动移除目标仓中已
vendor 的 `feishu_writer.*` 或现有 CI job。旧链路在明确迁移前保持原状；不要
把技能升级当成跨仓脚本发布。

迁移时按以下边界执行：

1. 记录当前 `.feishu/project.yaml`、`test/.feishu-mvp.yaml`、CI 配置和历史
   测试报告 Base 的位置；只记录资源 ID/URL，不复制 secret。
2. 用 `test-artifact-management` 的报告设置步骤安装 `gen_report.py`、TC helper 和
   `test/.report-config.json`。旧三表用例 Base 先按 `bitable-setup.md` 的迁移
   分支由用户选择，不自动合并或删除。
3. 在独立变更中把旧 `feishu_writer.*` job 切换为 `test-artifact-management` 的
   `report-run` 链路，并完成授权 one-shot CI 写回；验证当前目标 TC、报告和
   `91403` 后再停用旧 job。
4. 历史测试报告 Base 默认保留为只读归档。导出、搬迁或删除历史记录属于
   单独的数据处置，必须由用户明确授权，并通过 `lark-base` / `lark-drive`
   精确操作目标资源。

---

## 团队推广

自建应用的"添加文档应用"是**应用维度**，不是人维度。Admin 给 App 授权一次，**全员 / 全 CI runner 共享**。secret 永不分发个人。

### 3 个角色 × 3 套授权对象

| 角色 | token | 飞书侧授权对象 | 谁配 |
|---|---|---|---|
| 同事本地创建/检查资源 | 同事的 user OAuth | 同事飞书账号可访问目标 Wiki/Base | 同事飞书登录 |
| 同事本地干跑 CI 路径 | tenant token (`FEISHU_APP_ID/SECRET`) | **自建应用**已加到目标多维表格 + Wiki 父页 | Admin 一次性 |
| CI runner 跑 | 同上 | 同上 | 同上 |

### Admin 一次性配置清单（全员受惠）

```
[ ] 飞书开放平台：自建应用勾选目标 Base 读写及报告 Doc 所需权限 + 发布版本
[ ] 飞书：目标测试用例 Base（及 CI 会写的可选报告资源）→ 添加文档应用（自建应用 → 可编辑）
[ ] GitLab Variables：FEISHU_APP_ID + FEISHU_APP_SECRET（Masked，仅项目可见）
[ ] 飞书项目空间：给团队成员加访问权（如未默认）
```

飞书"添加文档应用" **不向下继承**：每个由 CI 写入的目标 Base/文档都要单独确认授权，不能把父目录权限当作子资源写权限。

### 每个团队成员一次性配置

```
[ ] OpenCode/Claude/Codex 装飞书 MCP：~/.claude/feishu-mcp/server.mjs
[ ] 一次 OAuth 登录（写 ~/.claude/feishu-mcp/tokens.json）
[ ] git clone 仓库；需要测试用例同步时确认 `test/.report-config.json` 指向正确 Base
```

### 每个团队成员日常

```
[ ] git push / 开 MR → CI runner 自动反写飞书（透明）
```

### 不能给同事的东西

- ❌ `FEISHU_APP_SECRET`（密钥；只能在 GitLab Variables）
- ❌ 你的 user OAuth token / refresh token（个人凭证；外传 = 别人冒充你）

### 推到新项目空间（别的部门 / 别的飞书根）

1. 用 `lark-wiki` / `lark-base` 在新空间创建或复制实际需要的资源。
2. 用 `test-artifact-management` 校验目标测试用例表字段，并更新 `test/.report-config.json`。
3. Admin 给目标 Base 授权同一个自建应用，并重新登记对应 CI Variables。

### 反写跑通的最小完成态

| 项 | 谁做 |
|---|---|
| 一个自建应用（`FEISHU_APP_ID`） | Admin 创建 + 发布版本 |
| 该 App 加到 CI 要写的目标 Base / 报告 Doc | Admin 配置 |
| GitLab Variables 配 secret | Admin 一次配置 |
| 仓内 `test/.report-config.json` 指向正确 Base | `test-artifact-management` 初始化/校验 |
| 仓内报告脚本 + CI 配置 | 使用 `test-artifact-management` 模板按仓库命令接入 |

5 条齐 → 任何团队成员 / CI runner push 代码都能自动反写飞书。

---

## 鉴权与失败排查

### 鉴权三档

| 场景 | token 类型 | 来源 |
|---|---|---|
| 人工创建 Wiki/Base | **user OAuth** | lark-cli / host Lark 工具登录态 |
| CI 反写（写多维表格记录） | **tenant token** | GitLab Variables `FEISHU_APP_ID/SECRET` |
| 本机模拟 CI | tenant token | `export FEISHU_APP_ID=...` + `env -u FEISHU_USER_ACCESS_TOKEN` |

Wiki/Base 结构变更使用具备目标资源权限的用户身份；CI tenant token 只承担已授权表的记录读写。

### 飞书两层授权（每个新仓必做）

1. **开放平台**：应用勾 `bitable:app` → **发布新版本**（仓共享，一次性）
2. **文档级**：每个要写入的测试用例 Base 或报告 Doc → `···` → 更多 → 添加文档应用 → 同一 App → **可编辑**

漏哪个就 91403。

### 失败决策树

测试用例表的初始化和权限边界见 [`bitable-setup`](../skills/test-artifact-management/references/bitable-setup.md)。常见三档：

| 现象 | 含义 | 处理 |
|---|---|---|
| 91403 Forbidden | 文档级未授权 | 加文档应用 |
| FieldNameNotFound (1254045) | 字段被改名 / 未建 | 按 `bitable-setup` 列出字段并补缺；类型冲突停下确认 |
| 测试报告写了但用例 0 条更新 | JUnit ↔ TC ID 匹配失败 | 检查 pytest `-p tc` 标记 / `test/.report-config.json` 指向 |

---

## 测试用例配置流向

```
测试用例 Base URL / 已有兼容配置       (人工输入或 lark-base 查询)
                                     ↓ test-artifact-management 初始化
test/.report-config.json             (仓内, 入 git, 无密钥)
  ├─ 测试用例 base_token + table_id
                                     ↓ CI runner 读
GitLab Variables                     (Masked, 不入 git)
  ├─ FEISHU_APP_ID / FEISHU_APP_SECRET
                                     ↓ gen_report.py 用
测试用例 Base / 测试报告 Doc          (写入)
```

---

## 边界与硬规则

- 飞书是结构化 + 人读 SoT；Git 是代码与契约 SoT
- **CI 只写测试报告 Doc / artifact 与测试用例状态**；其他按需业务表都人手写
- 不要把私有 token 写进 SKILL.md 或 references（shared skill 必须通用）
- 资源 ID 可以进入项目配置；`FEISHU_APP_SECRET` 永远不入 git
- 已有 `.feishu/project.yaml` 只作为兼容输入，不要求新仓生成，也不授权批量创建其他资源

---

## 相关入口

- 通用 Wiki/Base 操作：`lark-wiki` / `lark-base`
- 测试用例 Base 初始化与字段契约：[`bitable-setup`](../skills/test-artifact-management/references/bitable-setup.md)
- CI 反写策略：[`testing-strategy` SKILL](../skills/testing-strategy/SKILL.md)
- 写用例：[`test-artifact-management` SKILL](../skills/test-artifact-management/SKILL.md)
- 自动化测试方案（团队视角）：[auto-test-scheme](auto-test-scheme.md) / [auto-test-manual](auto-test-manual.md)
- 产物路由总入口：[`product-rd-workflow` SKILL](../skills/product-rd-workflow/SKILL.md)
