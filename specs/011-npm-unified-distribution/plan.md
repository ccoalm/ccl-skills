# 011 — 统一 npm 分发：`@ccoalm/ccl-skills`

## Artifact classification

**本节只分类 011 这个交付本身，不代表所在分支的全部内容。** 011 主体是 `runtime/code`（`packages/` 下的实现），附带一条 CI 发布自动化（publish job）。原始实现不改 `skills/` 正文、`hooks/` 判据或 `check-ccl-skills.sh`；2026-08-15 的宿主消费纠正会修改 OpenCode 的插件行为激活面，因此该增量按 `shared-gate` 重新分类，不能再用“tarball 已含 hooks”代替运行时验收。

**分支上另有一笔独立交付**：提炼轮对 `skills/tighten-doc/SKILL.md` 的规则作用域修改。那是 **shared-skill / shared-gate 改动**，按它自己的 dual-track 闸走，不因与 011 同分支而适用本节的分类结论。评审或落地时两者必须分别判定。

## 已定决策

| 项 | 结论 | 定于 |
| --- | --- | --- |
| 分发通道 | npm 与 marketplace **双通道并存**。仓库公开后 marketplace 已可用，npm 另外提供不依赖 GitHub 访问的钉版快照 | 本轮 |
| 分发形态 | 单包 `@ccoalm/ccl-skills`，内置三个 host adapter | 本轮 |
| 打包模型 | 三端统一自包含（tarball 内含完整 tracked closure） | 本轮 |
| registry | 公有 npmjs，账号 `ccoalm`（user scope 自动拥有，无需建 org） | 本轮 |
| 代码托管 | GitHub，不迁 GitLab | 本轮 |
| 仓库可见性 | 已改为 public | 2026-08-12 |
| 起始版本 | `0.1.0`。两个旧包的 0.1.6 / 0.1.4 不继承 —— 从未发布，无版本连续性约束 | 本轮 |

## 现状取证

| 事实 | 证据 |
| --- | --- |
| `codex-npm` 已自包含 | `packages/codex-npm/scripts/build-assets.mjs:9` roots = `.codex-plugin`、`agent-context/session-start.md`、`skills`、`hooks`、`scripts/owner-dispatch`、`.worktree-only`；`:27` 写 local marketplace |
| `opencode-npm` **不**自包含 | `packages/opencode-npm/scripts/build-assets.mjs` 只拷 bootstrap / plugin `.ts` / `opencode.json` / command 模板；`src/install.ts:79-94` 要求本机已有 ccl-skills checkout 并做结构校验 |
| Claude 端无 npm 包 | 只有 `.claude-plugin/marketplace.json`，git 源 |
| Claude 支持本地 marketplace | `claude plugin marketplace add --help` → "from a URL, path, or GitHub repo" |
| 两包均未发布 | `npm view` 404；`npm access list packages` 为空 |
| CI 无 publish job | `.github/workflows/ci.yml` 只有 `repository-gates` 和 `npm-packages`（build/test） |
| Makefile 声称有 | `make help` 写"发布走 CI 手动 publish job" —— 该 job 不存在 |
| closure 体量 | 508 tracked 文件 / ~8.1MB（`skills` 占 7.6M） |

## Scope

**In**：单包实现（CLI + 三 adapter + build-assets）、CI publish job、Makefile 目标收敛、README/ARCHITECTURE 同步、首发。

**Out**：技能正文与 hook 行为（一行不动）；`install.sh` / `make install` 的 marketplace 路径（保留，与 npm 并存）；`install-gates.sh` 的 GitLab CI fragment（那是给产品仓用的，与本仓发版无关）。

## 设计

### 包结构

```
packages/ccl-skills-npm/
  src/cli.ts                 install | update | uninstall | doctor | help
  src/hosts/claude.ts        marketplace add <bundled path> --scope user + plugin install
  src/hosts/codex.ts         沿用现有 operations.ts 的 marketplace add + plugin add
  src/hosts/opencode.ts      从 bundled assets 装（不再读 checkout）
  scripts/build-assets.mjs   一次构出三端各自的 closure + local marketplace
```

CLI 默认检测所有已装 host 并逐个安装，`--host claude|codex|opencode` 限定单端 —— 与 `scripts/install.sh` 现有语义一致。

### 三端 closure 差异

| host | 额外需要 |
| --- | --- |
| claude | `.claude-plugin/`、`agent-context/` **两个文件**（`session-start.md` + `subagent-start.md`，对应 SessionStart / SubagentStart 两个 hook）、`hooks/`（含 `hooks.json`） |
| codex | `.codex-plugin/`、`agent-context/session-start.md`（现状） |
| opencode | bootstrap（`session-start.md` 改名）、`packages/opencode-plugin/ccl-skills.ts`、`opencode.json`、command 模板、**外加 `skills/`（本轮新增）** |

公共部分 `skills`、`hooks`、`scripts/owner-dispatch`、`.worktree-only` 只在 tarball 里存一份，三端 adapter 各自引用。

### 更新语义

两条通道并存，语义不同。这一段的结论必须落到 README 和 `doctor` 的输出里：

- **marketplace（git 源）**：Claude `autoUpdate:true` 定期刷元数据 + `plugin update`；Codex `marketplace upgrade` + `plugin add` 两步。
- **npm（自包含快照）**：`npm i -g @ccoalm/ccl-skills@latest`，或 `ccl-skills update`（沿用 opencode 现有形态：默认 dry-run 预览，`--yes` 才执行 `npm i -g @latest` 再刷资产）。

**坑**：npm 装的是快照，注册的是 **local path** marketplace。Claude 的 `autoUpdate` 只刷 git 源，对本地 marketplace 拉不到新内容 —— npm 用户不走 npm 就会静默停在旧版。

**冲突**：仓库已公开，同一 host 同时装 marketplace 版和 npm 版会重复加载。`doctor` 必须检出这种双装并给出二选一指引（先例：`install.sh` 的旧 symlink 提醒）。

### 通道所有权与碰撞规则（评审 P1-3）

`doctor` 报告双装是**不够**的 —— 它拦不住写入。两条通道写的是同一批宿主目标路径，所以必须定所有权：

- 安装时把每个 npm 写出的产物登记进 **ownership manifest**，每条记 **归一化相对路径 + 产物类型 + 安装时内容 hash**，且路径限定在每个 host 的固定 allowlist 根之下
- 目标路径上存在**非 npm 所有**的产物（marketplace 装的、用户手工定制的）时**拒绝安装**，或先保存以便还原 —— 不覆盖
- 安装失败必须让既有产物原样存活，不留半写状态

**首选做法：把产物放进 npm 独占的命名空间**（评审 P1-6 的结论）。可变的 manifest 不能自己给自己授权删除 —— 它被改过之后可以指向 allowlist 内任何一个用户文件并记下该文件当前的类型与 hash，下面那四道校验会全部通过。只要 npm 只往自己独占的路径写，卸载就根本不碰共享路径，这一整类问题消失。

仅当某个 host 强制要求写入共享目录（OpenCode 的 `~/.config/opencode/skills/` 是已知的一处）时，才退到下面的 manifest 方案，并且**删除授权必须来自 manifest 之外**。那个外部权威要具体到不留解释空间：**包内自带的不可变 inventory**，每条记 归一化相对路径 + 类型 + 该内容在包里的期望 hash。但**共享路径上 `uninstall` 一律不删**。理由是所有权在那里根本证明不了：字节相同的替换（marketplace 或用户装了同样内容）会让 inventory、安装回执、类型、hash 全部匹配，而它已经不属于 npm。既然判据无法区分，就不要那个删除能力 —— 共享路径上只**保留并报告**，把清理交给人。inventory + 回执双匹配仍然要做，但它的用途是**报告归属**，不是授权删除。

A12 因此要覆盖：d) 伪造条目；b) 替换内容与安装内容**字节相同**时同样不删（只测内容不同的替换会 false-green）。

**manifest 会过期，所以卸载不能只信它**（评审 P1-5）：装完之后用户可能改了那个文件，或 marketplace 把它换掉了；manifest 本身也可能被篡改成指向别处。`uninstall` 因此按下面执行：

- 拒绝越出 allowlist 根的路径和符号链接
- **只删类型与 hash 仍然匹配**的条目 —— 内容变了就说明它已不是 npm 那份产物
- 变化的条目**保留并报告**，不静默删
- 目录只在空了之后才删

### OpenCode 现有用法不得回归（评审 P1-4）

现有用户把 `CCL_SKILLS_REPO` 指向通过结构校验的 checkout，依赖其中更新或定制过的技能。P3 若直接改成读 bundled assets，install/update 会用 tarball 里的旧快照**静默替换**它们。

处置：`CCL_SKILLS_REPO` 保留为**显式 source override** —— 设了就装它（保留现有结构校验），没设才用 bundled assets；无效 override 在**任何写入之前**失败。

**这两条是打包模型的属性，不是包数的属性。** 拆成三个包一样存在，而且更糟：三套各自的 `doctor` 只看得见自己那一端，跨端双装更难检出。真正的取舍轴是**快照 vs 自动更新** —— 要自动更新就走 marketplace（git 源），要可钉版的快照就走 npm。两条通道各自说清楚，不试图在一条路里同时满足。

## Acceptance matrix

| # | 行为 | 可观察判据 |
| --- | --- | --- |
| A1 | 无 checkout 装 Claude | 干净 HOME 下 `npm i -g` 后 `claude plugin list` 出现 ccl-skills，注入内容与仓库源逐字节相同 |
| A2 | 无 checkout 装 Codex | 同上，`codex plugin list` 可见 |
| A3 | 无 checkout 装 OpenCode | `~/.config/opencode/skills` 出现 tarball 动态发现的全部技能目录，**且内容来源可判定**（来自 tarball 而非某个 checkout）。技能数只作当前快照信息，不写死为门禁；只断言"目录数对"会让 A10b 的回归 false-green |
| A3H | OpenCode 安装后消费 hooks | 安装结果含宿主可达的 runtime closure；插件的显式 binding inventory 与 `hooks/hooks.json` 中全部 command hook 一一对应，新增 hook 未映射时测试失败 |
| A3R | OpenCode hook 运行时行为 | 原生插件 harness 至少证明：SessionStart bootstrap、edit/write 与 `apply_patch` 隔离、UserPromptSubmit 授权哨兵、Bash merge guard、PostToolUse reminder、Task/Subagent context、session-idle stop backstop 均在对应宿主事件触发 |
| A10 | 既有产物不被破坏 | 目标路径先放 marketplace 装的和手工定制的文件 → 安装失败或 `uninstall` 之后，这些文件**逐字节存活** |
| A11 | `CCL_SKILLS_REPO` override | a) 设了有效 override → 装的是 override 的内容；b) 未设 → 可离线用 bundled 装；c) 无效 override → **任何写入之前**失败 |
| A12 | manifest 过期 / 被篡改也不误删 | a) 装后改动该产物 → `uninstall` 保留并报告；b) 装后被 marketplace 替换 → 同样保留；c) manifest 被改成指向 allowlist 根之外或符号链接 → 拒绝，不删任何东西；d) **allowlist 内的伪造条目**（指向别的用户文件并记下其真实 hash）→ 仍拒绝删除 |
| A4 | 单端限定 | `--host codex` 只动 Codex，其余两端零副作用 |
| A5 | 快照可追溯 | `release.json` 的 `sourceCommit` 等于构建时 HEAD，`snapshotHash` 稳定可复算 |
| A6 | update | 默认 dry-run 不碰网络与全局 npm 状态；`--yes` 才升级并刷资产 |
| A7 | uninstall | 独占命名空间下的产物清干净、不留孤儿 marketplace 条目；**共享路径下的产物一律保留并报告**（见「通道所有权」节）—— A7 与那条规则冲突时以那条为准，不得为满足"清干净"去删共享路径 |
| A8 | doctor 报双装 | 人为造出 marketplace + npm 双装，doctor 明确报出并给二选一 |
| A9 | 发布链 | tag 触发 CI publish job，`npm view @ccoalm/ccl-skills` 可见且带 provenance |

## 测试层决策表

| 层 | 决定 | 命令 / 证据 |
| --- | --- | --- |
| unit | add | `node --test test/*.test.mjs`（沿用 codex-npm 现有形态） |
| pack / 内容闭包 | add | `pack.test.mjs` —— 断言 tarball 内 closure 完整、模式位只有 644/755、无 `.gitignore` 残留 |
| build-modes | add | `test-build-modes.mjs` —— git 可用 / CI checkout 两种取文件路径都能构；**并断言 CI 路径不会纳入未跟踪文件**：在某个 asset root 下造一个未跟踪哨兵文件，要求它被排除或构建直接失败 |
| E2E host smoke | add | 临时 `HOME` + 真实 CLI 跑三端 lifecycle（现有 `host-smoke.sh` 只覆盖 Codex，扩到三端）；A1–A4、A7、A8 在这层 |
| OpenCode plugin runtime | add | 直接加载打包后的 TypeScript plugin，触发 OpenCode 原生 hooks；覆盖 A3H/A3R，禁止用“文件存在”替代事件执行 |
| E2E 碰撞 / 回归 | add | **不能只在干净 HOME 上测**：A10 先在目标路径埋 marketplace 产物和定制文件再跑 install 失败与 uninstall；A11 三个分支各一条；A12 三个分支各一条（装后改动、装后被替换、manifest 篡改）。这三组正是 CI 会 false-green 的面 |
| CI publish | 手动 | A9 只能在真发布时验；首发用 `--dry-run` 预演一次再真发 |
| manual | run | A5 复算 `snapshotHash` |

`host-smoke` 需要本机装有对应 CLI；缺哪端就把那端标 `blocked` 并如实报，不伪造。

## 分阶段

1. **P1 骨架**：新建 `packages/ccl-skills-npm`，搬 codex adapter（已自包含，风险最低），跑通 A2 + unit/pack/build-modes。
2. **P2 Claude adapter**：A1。closure 加 `.claude-plugin` + `subagent-start.md` + `hooks/`。
3. **P3 OpenCode adapter**：A3。这是唯一的模型变更（读 checkout → 读 bundled），工作量最大。
4. **P4 收口**：CLI 合一、doctor 双装检测（A8）、uninstall（A7）、update（A6）。
5. **P5 发版链**：CI publish job、Makefile 目标收敛、删掉 `make help` 里那句虚述、README/ARCHITECTURE 同步。认证采用 npm [Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)：npmjs 绑定确切的 GitHub repo + workflow，workflow 申请 `id-token: write`，用 OIDC 短期凭据发布并自动生成 provenance。发布环境固定为 Node.js 24，npm CLI 不低于 11.5.1；包的 `repository.url` 必须与 GitHub 仓库精确匹配。P6 真发前先核对 npmjs 绑定已生效。
6. **P6 首发**：先确认 P5 选定的认证路径已生效 → `--dry-run` 预演并核对 `files` 清单 → 真发 → A9 验证。

旧的 `packages/codex-npm` / `packages/opencode-npm` 在 P4 通过前保留，P4 绿了再删；两者从未发布，无需 deprecate。

## 风险与停止条件

| 风险 | 处置 |
| --- | --- |
| Claude 的 local marketplace 行为与 Codex 不同 | P2 第一步就用临时 HOME 实测；不通则该端回退到 git marketplace，npm 只装 Codex/OpenCode，并如实写进 README |
| 8.1MB tarball 触及 registry 限制 | npm 单包上限远高于此，但 P1 用 `npm pack --dry-run` 先量实际压缩体积 |
| `skills/` 增长推高每次发布体积 | 记录在案，不本轮处理；后续可考虑按 host 裁剪 closure |
| 首发即公开不可撤 | npm unpublish 有 72 小时窗口且有限制；P6 先 `--dry-run`，确认 `files` 清单无多余内容再发 |
| **CI 路径把未跟踪文件打进公开包**（评审 P1-2） | `build-assets.mjs:16-22` 的 CI fallback 在 git 不可用时按 `CI=true` + commit SHA 放行，然后递归拷贝 asset root 下**所有**条目，不按 tracked 清单；`removeIgnored` 只删 `.gitignore` 文件、不删 ignored 内容。仓里现有实例：`skills/*/scripts/__pycache__/`。处置：git 元数据不可用时**fail closed**，除非构建收到一份可验证的 tracked 清单；并按上表加未跟踪哨兵用例 |
| **Trusted Publisher 尚未在 npmjs 绑定**（评审 P1-1） | workflow 只实现 OIDC 发布入口；npmjs 仍须把 `@ccoalm/ccl-skills` 绑定到确切 repo + workflow。未绑定时 `npm publish` 认证失败，A9 与首发全卡。处置见 P5/P6 |

停止条件：A1/A2/A3 任一在干净 HOME 下装不出可用技能 → 停下报告，不用"本机能跑"替代。

## Review / challenge gate

本方案改的是**对外分发面**，首发即公开且有外部消费者，技术设计闸触发：实现前需一次独立对抗评审，记录具体反对意见、处置与评审者身份。评审对象是本文件，重点在打包模型（自包含 vs git 源）、三端 closure 差异、以及 P3 那次模型变更是否会让 OpenCode 现有用法回归。

### Round 1 — review（已跑）

| 项 | 值 |
| --- | --- |
| 评审者 | `codex`（OpenAI 家族）。`claude` 被 preflight 以 `same_family_as_implementer` 排除 |
| 实现者家族 | anthropic |
| 模式 / 深度 | review / explore；risk tags `external-consumer`、`release-ops` |
| 评审包 sha256 | `0524bca04d3fd91b7c57535ac4020b0c0ee776c05a8debb0ae5a987fffe24eb5`（计划正文 + codex/opencode 两个 `build-assets.mjs` + `opencode/src/install.ts` 1-100 + `ci.yml`） |
| 结论 | `findings` —— 2 条 P1 |
| chain | `npm-unified-011`，tracked；challenge 轮次剩 1 |

| 发现 | 处置 |
| --- | --- |
| P1-1 发布认证路径未定 | **接受**。P5 加认证路径二选一并前置到 P6 检查；风险表登记 |
| P1-2 CI 路径纳入未跟踪文件 | **接受**。风险表登记 fail-closed 处置；测试层加未跟踪哨兵用例 |

两条均已改进计划，**未修改评审包 —— 当前候选与 round 1 的 sha256 已不同**，challenge 轮需对新候选另起 chain。

### Round 1b + 2 — 新候选上的 review + challenge（已跑）

chain `npm-unified-011b`，候选 sha256 `3a1edf23e1bfe2aac03149bc773cacc67fcaec118a1388e868ac561b55c2ed88`，两轮评审者均为 `codex`，均 tracked、均 conclusive。challenge 的 focus 是打包模型选型 / 三端 closure 差异 / P3 的 OpenCode 模型变更回归。

| 发现 | 处置 |
| --- | --- |
| P1-3 通道所有权缺失：npm 写共享路径、`uninstall` 按路径清扫会删掉 marketplace 与用户定制产物；`doctor` 只报告拦不住写入 | **接受**。新增「通道所有权与碰撞规则」节；补 A10 与对应 E2E |
| P1-4 P3 静默替换现有 `CCL_SKILLS_REPO` 用户的技能，且 A3 只数目录会让 CI false-green | **接受**。`CCL_SKILLS_REPO` 保留为显式 source override；A3 补内容来源判定；新增 A11 三分支与对应 E2E |

### Round 3 — 确认轮 review（已跑）

chain `npm-unified-011c`，候选 `77848be52f620c4edab16999c67731d9e20ffcdb91dc350099060418d0fd6cf1`，评审者 `codex`，tracked。

| 发现 | 处置 |
| --- | --- |
| P1-5 ownership manifest 会过期：装后产物被改动或被 marketplace 替换，`uninstall` 仍按过期条目删掉当前文件；manifest 被篡改还能把删除重定向出 allowlist | **接受**。manifest 条目改为 归一化相对路径 + 类型 + 内容 hash，限定在每 host 的 allowlist 根下；卸载只删类型与 hash 仍匹配的条目，变化的保留并报告，拒绝越界路径与符号链接，目录空了才删；新增 A12 三分支与对应 E2E |

### Round 4 — 止损轮 review（已跑，触发止损）

chain `npm-unified-011d`，候选 `344f592c0ee93c0f297a9ffa0bfdb39b055019d36375927e3da809b6993a9435`，评审者 `codex`，tracked。

| 发现 | 处置 |
| --- | --- |
| P1-6 可变 manifest 不能自我授权删除：伪造条目可指向 allowlist 内的无关用户文件并记下其真实类型与 hash，P1-5 加的四道校验全部通过后仍会删掉它 | **接受，并改为首选独占命名空间** —— 它从结构上消解这一整类问题，而不是叠第三道守卫。共享目录（OpenCode skills）退到 manifest 方案时，删除授权必须来自 manifest 之外并 fail closed。A12 补 d) 分支 |

### 闸的当前状态：按约定止损，停止评审

四条 chain 共 5 轮，累计 6 条 P1，全部接受并已改进计划。**没有任何一轮返回零发现。**

止损依据（事前约定）：前四条是结构性缺失（认证路径、打包纳入未跟踪文件、通道所有权、OpenCode 回归），第 5、6 条都落在同一处（卸载的删除授权）的连续细化。轮次已不再指出新的结构缺失，继续推演的边际收益低于让实现与 E2E 去暴露。

**残余状态如实记：本计划从未取得干净的评审通过。** 当前候选在 `344f592c…` 之后又改过，未被任何一轮覆盖。进入实现的依据是止损决定，不是通过。A10 / A11 / A12 三组 E2E 是这些发现的兑现凭据 —— 它们在 P4 之前必须真跑绿，不得以"计划里写了"充数。

## Landing state

**计划本身已 `landed`，实现尚未开始。** 分支 `worktree-npm-unified-distribution`（从 `worktree-docs-readme-freshness` 切，含文档修复 `7038b93`）经 PR #1 合入 `main`，合并提交 `15a89e9`。落地的是本计划文档与同批的提炼轮改动，**不含任何 `packages/ccl-skills-npm` 代码**。

对着 `15a89e9` 复核实现侧：`packages/` 下无 `ccl-skills-npm`，上面现状取证表的「CI 无 publish job」「Makefile 声称有」两行仍然成立。P1–P6 全部未动工。

`skill-extraction-workflow` 提炼轮**已跑**（`6965a18`，tighten-doc 的入站引用规则），随后 `3dbb275` 补上该改动欠的 impact-chain 行。上一版此处记的"提炼轮未跑、本轮开工前需先处置"已作废。

## 2026-08-15 实现重入记录

用户在当前交付中明确选择本方案作为实现基线。对 `dev@673fece` 复核后，P1–P6 仍未落地：`packages/ccl-skills-npm` 和 publish workflow 均不存在，两个旧包在 npm registry 查询仍为 404。本轮实现 P1–P5；P6 的 npmjs 配置和真实发布需要单独授权。

### 实现边界

| 项 | 结论 |
| --- | --- |
| active baseline | 本文件；已落地，当前选择后重新核实 |
| implementation owner | `terminal-cli-dev`；一次性 CLI，沿用既有 Codex/OpenCode 机制 |
| release owner | `platform-release-engineering`；包管理器接管更新，CI 只使用 OIDC 短期凭据 |
| risk | `release-ops`、`external-integration`、`security-review`；不提交 token，不执行真实 publish |
| delegation | 不适用；P1–P5 共用包结构、ownership 模型和发布产物，按依赖顺序串行 |
| visible surface | CLI help、错误和 doctor 输出；无 ANSI、raw mode、PTY 或交互式 TUI |
| test source | 本文件 A1–A12 与“测试层决策表” |
| landing target | 本地功能分支；commit、push、PR、合并、tag、publish 分别授权 |

### CLI 设计 checkpoint

- Surface：一次性 installer/updater CLI，紧凑纯文本输出，不依赖颜色。
- Primary flow：`install | update | uninstall | doctor | help`，`--host` 可限定单端。
- States：成功、无 host、参数错误、冲突拒绝、dry-run、外部 CLI 不可用、部分 host 失败。
- Safety：写入前完成来源与碰撞检查；错误信息点明 host、未执行的动作和修复方式。
- Evidence：单元测试覆盖解析与状态；临时 HOME host smoke 覆盖真实输出和副作用。页面级 redesign gate 不触发，因为没有布局或视觉系统变更。
- Owner checkpoint：`product-ui-ux-design` + `terminal-cli-dev` + `testing-strategy`；checkpoint rules read: `product-ui-ux-design/SKILL.md#implementation-owner-checkpoint`。Rendered evidence 先记 `planned`，由 host smoke 的真实 CLI 输出在收口时补齐。

### P1 验收与测试登记

| ID | 场景 | 层 | RED / 验证命令 |
| --- | --- | --- | --- |
| A2 | 无 checkout 安装 Codex | integration / host smoke | `npm test`；`npm run smoke:host` |
| A5 | release metadata 可追溯、hash 可复算 | unit / pack | `npm run test:pack` |
| P1-pack | tarball closure 完整、mode 仅 644/755 | pack | `npm run test:pack` |
| P1-build | git 与 CI 构建路径都只含 tracked closure | build-modes | `npm test`，含未跟踪哨兵 |

Objective：交付 P1 的统一包骨架与 Codex adapter。Member unit：上表四个验收点；集合由本方案固定，不存在运行期新增成员，`population: does-not-fire`。正向、负向、恢复和表面成功四类分别由成功安装、无效输入/缺失资产、事务恢复、写入后核验覆盖；缺口在对应测试为绿前保持 `gap`。

P1 只保留三类新概念：统一包目录对应单包决策；host adapter 边界对应三端差异；可复算 release metadata 对应 A5。没有为未来 host、远程下载器或第二套更新协议预留扩展层。

## 2026-08-15 实现候选收口

### 分阶段状态

| 阶段 | 状态 | 当前证据 |
| --- | --- | --- |
| P1 统一包骨架 | 本地候选完成 | `@ccoalm/ccl-skills@0.1.0` 构建、137 个包测试和 9 个实际 tarball 测试通过 |
| P2 Claude adapter | 本地候选完成 | 临时 HOME lifecycle、未拥有 marketplace、符号链接和 host 缺失分支均有断言 |
| P3 OpenCode adapter | 本地候选完成 | bundled / override / invalid override 三分支通过；共享文件在卸载时保留 |
| P4 CLI 收口 | 本地候选完成 | 默认多 host、显式单 host、doctor 双装、update / uninstall 和故障恢复均通过 |
| P5 发版链 | 本地候选完成 | tag-only workflow、固定 action SHA、Node 24、npm 11.5.1、OIDC、精确 tarball 发布和发布手册均已落到候选 |
| P6 首发 | `blocked` | GitHub `npm` environment 和发布 tag 保护已配置并回读；npm 包当前仍为 404，包级 Trusted Publisher 只能在首发后配置，真实 publish 尚未授权或执行 |

### Acceptance → implementation → evidence

| ID | 实现面 | 2026-08-15 新鲜证据 | 状态 |
| --- | --- | --- | --- |
| A1 | `claude-adapter.ts` 的 package-owned local marketplace lifecycle | `npm test` 中 Claude lifecycle、冲突拒绝、符号链接和 host-missing 场景通过；三宿主 smoke 通过 | satisfied |
| A2 | 既有 Codex transaction engine + 统一 dispatcher | 事务、信号中断、rollback / partial finality 测试通过；三宿主 smoke 通过 | satisfied |
| A3 | `opencode-adapter.ts` bundled install | bundled、有效 override、无效 override、tampered manifest 测试通过；三宿主 smoke 通过 | satisfied |
| A4 | `--host` 显式隔离 | `explicit Codex host has zero Claude and OpenCode side effects` 通过 | satisfied |
| A5 | `build-assets.mjs` + `release.json` | 522 文件校验，`snapshotHash=34e90fdb97d0b9372dfb9edc06301ee14fcb187ce16c35fa0a73ef5f4c3f14c0`；dirty worktree 正确标记 `development-dirty` | satisfied for local candidate |
| A6 | dry-run update + `--yes` self-update/delegate | 缺失安装拒绝、默认无变更、fresh CLI delegation 测试通过 | satisfied |
| A7 | 独占根删除；OpenCode 共享文件保留 | clean uninstall、修改文件保留、共享文件 retained、故障恢复测试通过 | satisfied |
| A8 | legacy / npm 双装检测 | doctor double-install 测试通过 | satisfied |
| A9 | tag → OIDC publish → registry read-back | workflow 和 YAML 静态检查通过；GitHub `npm` environment 与 `ccl-skills-v*` tag 保护已配置；真实 tag、Trusted Publisher 与 publish 未执行 | blocked at P6 |
| A10 | 写前碰撞检查和 package-owned roots | unowned registration、legacy、custom file、symlink、unknown state 测试通过 | satisfied |
| A11 | `CCL_SKILLS_REPO` override | valid / absent / invalid 三分支测试通过 | satisfied |
| A12 | manifest 与路径安全 | traversal、malformed JSON、tamper、drift、symlink、hash 不匹配和 shared retention 测试通过 | satisfied |

Objective closure：member unit 是 A1–A12；A9 的真实 registry 终态属于 P6，已按用户授权边界保留为 `blocked`，因此本轮只能声称“P1–P5 本地候选完成”，不能声称 011 全部完成或 release-ready。正向、负向、恢复和表面成功四类分别由三宿主成功路径、写前拒绝、事务/故障恢复、public-state 与 tarball 再校验覆盖；A9 的真实成功类仍待首发。

### Structural minimality

| 新概念 | 当前需要 | 更简单方案 | 结论 |
| --- | --- | --- | --- |
| 单一 `ccl-skills-npm` 包 | 单包决策和 A1–A9 | 继续维护两个包无法覆盖 Claude，且重复 release contract | keep |
| Claude / Codex / OpenCode adapter 边界 | 三端宿主协议和所有权模型不同 | 单一无类型分支会混淆碰撞与卸载语义 | keep |
| package-owned marketplace snapshot | A1、A2、A5、A10 | 运行时下载 git 违反自包含和钉版目标 | keep |
| OpenCode shared-file retention | A7、A10、A12 | 自动删除无法证明当前所有权 | keep |
| 独立 tag publish workflow | A9 和发布权限隔离 | 在普通 CI 或本地发布扩大凭据与误发面 | keep |

没有加入远程下载器、新 host 扩展框架、第二套版本协议或长期 npm token。两个旧 npm 包在统一包测试通过后删除，属于已定单包迁移，不保留重复实现。

### 验证记录

- `NPM_CONFIG_CACHE=/private/tmp/ccl-skills-npm-cache npm test`：137/137 passed。
- `NPM_CONFIG_CACHE=/private/tmp/ccl-skills-npm-cache npm run test:pack`：9/9 passed；产物 `ccl-skills-0.1.0.tgz`，integrity `sha512-FpFVHmdWIsU5+ALZ4XW96aalFQ3kS2bp34BXFlN45oo4ya1j6TANm9B3IDBdnRxZyEabuGD8OcUv6mX2qlM9ow==`，shasum `9a72de350622bdbf03ae0023f441343f942e5c44`。
- `npm run smoke:host`：`three-host-smoke-passed`；Codex trust 仍明确为 `pending-unverified`，OpenCode shared files 为 `retained`。
- tarball 中有 19 个 `hooks/` 条目；`hooks.json`、`session-start.sh`、`guard-edit-isolation.sh` 同时存在于 tarball 和 hash 绑定的 `release.json`。
- workflow YAML、agent contract coverage、`check-ccl-skills.sh`、public sanitization、Markdown links、staged / unstaged diff check 全部通过；`check-ccl-skills.sh` 只有基线 advisory，无 blocking。
- `npm whoami`（隔离 cache）返回 `ccoalm`；`npm view @ccoalm/ccl-skills` 返回 404，未发生首发。
- GitHub `npm` environment 已设置 `ccoalm` required reviewer，并只允许 `ccl-skills-v*` tag 部署；active tag ruleset 仅允许 `ccoalm` 创建、改写或删除该命名空间。当前仓库只有这一名管理员，因此 environment 保留 `prevent_self_review=false`，避免首发永久阻塞。
- `actions/checkout@v6.0.2` 与 `actions/setup-node@v6.4.0` 的官方 tag 分别解析到 workflow 固定的完整 SHA。

### 许可证与发布边界

用户已明确允许复用，候选采用 Apache License 2.0：仓库根和 npm 包都带完整 `LICENSE`，`package.json` 声明 `Apache-2.0`，pack test 同时校验元数据与许可证正文。本轮未发现需要额外 `NOTICE` 的已知归属材料；发布手册要求每次发布前复核。

GitHub 发布侧配置已获授权并完成；commit 与本地 `dev` merge 也已获授权，执行证据在提交后回报。push、PR、tag 和 `npm publish` 未获授权，也未执行。由于包尚不存在，npm 官网没有该包的 Settings / Trusted Publisher 页面；P6 必须从一次明确授权的 bootstrap publish 开始，随后立即绑定 Trusted Publisher、撤销 bootstrap 凭据，并补 registry provenance 与干净 HOME 安装证据。

### 实现评审状态

实现者自审已按 correctness、filesystem authority、failure finality、compatibility、release safety、tests、observability 和 external-boundary 八个关注面完成。OpenCode 独立 reviewer 对首个 runtime 分区在 600 秒内未返回终态，记录为 `inconclusive/timeout`，候选哈希 `538ae45f9cecc647ce41bdcd81aaad34fb0caf6ebe9a6f49c5e06b58158e2c8b`；该结果不计通过。按用户决定，OpenCode reviewer 自身的修复转到独立会话，不在 npm worktree 扩 scope。

Claude 直接 CLI 的无工具独立 review + challenge 首轮共指出 10 类有效问题，均已按一手源码复核后接受：发布前改为重验实际 tgz 及 metadata integrity；tag 必须属于默认分支历史；多宿主遇到 `partial` / interrupt 停止后续写入并保留更强退出码；Claude/OpenCode 接入 interrupt channel；OpenCode 拒绝共享路径 symlink；缺失 HOME 时 fail closed；Claude 卸载后清理失败报 `partial`；包内许可证与根许可证逐字一致；技能数量从资产动态发现；首次发布前的 README/Makefile npm 入口显式门控。正式 `review_gate` 因 Claude CLI 初始化能力字段不兼容返回 `capability_missing`，不冒充通过；最终冻结候选另做一次直接 Claude review + challenge，结果只绑定该候选并在交付记录中报告。

哈希 `801525ef8d08acd5c51211644fbb55a4c1d6078843907f7eb29363fbf45f78e4` 的 staged 候选随后由 Claude Opus 直接 CLI 进行无工具 review + challenge，两路均返回 findings（8 + 7 条，合并为 13 类修复），不计通过。全部按源码复核后接受并增加 RED→GREEN 回归：OpenCode 中断清理空目录且可重试、更新删除旧 owned entries、版本不变内容 hash 时不误删 active snapshot；默认 doctor/uninstall 纳入 CLI 已消失但 manifest 仍在的 host；Claude CLI 不可达时保留 ownership；Claude 路径比较处理 macOS canonical alias；两端快照有界保留且清理失败报 partial；OpenCode 卸载清理失败报 partial；self-update 先做无变更 preflight、downgrade 不先装 `@latest`、dry-run/help 明示全局包更新；`artifacts/` 不污染 sourceState；release metadata 同时绑定 assets 与编译后 JS runtime；稳定版规则在构建前失败；Makefile 区分 E404 与 registry 故障。修复后第一次 host smoke 还暴露“OpenCode 版本变但内容 hash 相同，清理误删 active snapshot”，已补回归并修复，重跑三宿主 smoke 通过。

哈希 `ccaa7c142da39d390313aaaddf0d6cce11deeab800d44e08afb30ce9c213631f` 的 staged 候选再由 Claude Opus 做最终直接 review，返回 5 条 finding，均经源码复核后接受并修复：生产 CLI 的 `CCL_SKILLS_REPO` 回退到 `process.env`；OpenCode 临时 staging 不再残留于共享目录阻塞重试；Claude 在任何变更前收到 interrupt 时不再误入 rollback；默认 update 只选择已拥有的可用 host；OpenCode dry-run 先执行 preflight，且 delegated self-update 失败时明确披露全局包已经更新。对应回归使包测试增至 137 项，最终 tarball 9 项和三宿主 smoke 重新通过。按已声明的评审停止边界，没有再启动 post-fix 模型 clean pass；最终结论以这些 finding 的逐项处置和确定性门禁为依据，不将 Claude 结果表述为 clean/pass。

## 2026-08-15 OpenCode hooks 消费纠正

### 纠正结论

- Codex 能消费 `.codex-plugin` 中的 hooks；缺少独立 runtime smoke 只能记为验证缺口，不能误报为产品能力缺失。
- npm tarball 已包含 `hooks/`，但 OpenCode adapter 只安装 skills、bootstrap、commands 和一个仅实现两处行为的插件；“运输闭包”不等于“宿主消费闭包”。
- 本轮不改 hook 规则，改的是 OpenCode 的宿主激活面及其验收，因此触发 `shared-gate`、`external-integration`、`security-review`。

### 实现边界与测试先行

| 项 | 结论 |
| --- | --- |
| active baseline | 本文件 + 当前 `hooks/hooks.json`；纠正增量从 `dev@759dc60` 开始 |
| implementation owner | `skill-extraction-workflow`（plugin-shipped behavior）+ `terminal-cli-dev`（安装/诊断面） |
| delegation | 不适用；runtime 事件适配、安装 closure 与测试共享同一 binding contract，串行实现 |
| visible UI | 不适用；无布局、ANSI、PTY 或交互变化 |
| risk gates | `shared-gate`、`external-integration`、`security-review`；RED→GREEN、真实宿主 smoke、独立 review + challenge |
| test source | A3H、A3R；先让 unchanged baseline 在 runtime closure、`apply_patch` 和事件映射上失败 |
| landing target | 功能 worktree提交后合并到本地 `dev`；不 push、不 tag、不 publish |

### Functional completeness

| Requirement / acceptance point | Source decision | Implementation surface | Verification | Status |
| --- | --- | --- | --- | --- |
| A3H runtime closure + binding inventory | in，用户纠正 | OpenCode source/npm installers + plugin binding inventory | adapter integration test + source-installer closure test + manifest parity test | satisfied：两种安装器只安装同一最小 closure；10 个 command hook 全量映射 |
| A3R edit/write/`apply_patch` | in，用户纠正 | `tool.execute.before` | protected-primary negative probes | satisfied：`apply_patch` 在主检出被真实拒绝 |
| A3R prompt/merge/post-tool | in，用户纠正 | `chat.message` + before/after hooks | real shell-hook harness | satisfied：授权哨兵、merge guard、post-merge reminder 均执行 canonical shell hook |
| A3R delegation/subagent | in，用户纠正 | Task/Agent before-hook adaptation | deny-then-load owner probe + prompt-context assertion | satisfied：未加载 owner 时拒绝，完成结构化 Skill 调用后放行并注入 subagent context |
| A3R stop backstop | in，用户纠正 | `session.idle` / `session.status=idle` event adaptation | one-shot resume assertion | satisfied：结构证据触发一次续跑，敏感正文不进入 bridge transcript |
| Codex hook behavior rewrite | out，能力已存在 | none | existing plugin registration + explicit no-diff check | out |

### Structural minimality

| New concept | Current acceptance point or hard constraint | Simpler alternative | Decision |
| --- | --- | --- | --- |
| OpenCode hook binding inventory | A3H future-drift detection | prose matrix cannot fail CI | keep |
| installed runtime closure | shell hooks are canonical and already packaged | duplicate every shell rule in TypeScript would drift | keep |
| bounded OpenCode transcript bridge | delegation/stop scripts require transcript evidence | omitting those events leaves hooks inert | keep, bounded and locally cleaned |

### 实现者自审与行为证据

| Concern / axis | Negative case or conclusion | Evidence |
| --- | --- | --- |
| correctness / enumeration completeness | 新增 command hook 若未绑定或未被事件 handler 实际调用必须失败；当前 `hooks.json` 的 10 个 command hook 与 inventory 集合相等，runtime trace 也覆盖全部 10 个脚本 | RED baseline：原实现缺 binding inventory、`apply_patch` 拒绝和 `chat.message`，新增 3 个 runtime 测试均失败；GREEN：`opencode-hooks.test.mjs` 4/4 |
| security / privacy / authority / data loss | 主检出编辑继续 fail closed；安全 hook 丢失/异常时拒绝操作；delegation 的 `ask` 不再被降级为提示后直接执行；临时 transcript 不复制 prompt、文件内容或工具输出 | runtime harness 覆盖 missing-runtime 拒绝、delegation deny-then-load、`apply_patch` add/move-in/move-out、canonical `file_path` 存在且 `super-secret-*` 不存在；临时目录 0700、文件 0600、4 MiB 上限、dispose 删除 |
| concurrency / lifecycle | 重复 idle 不并发执行；`session.idle` 与 `session.status=idle` 都映射 stop；子会话引用父 transcript 并保留自身 agent transcript | `idleInFlight`、parent-session map、one-shot resume 断言；三宿主 smoke 通过 |
| resource bounds | shell hook 有逐事件 timeout、256 KiB 输出上限；bridge transcript 有 4 MiB 上限并清理 | TypeScript 聚焦检查通过；runtime harness dispose 后目录不存在 |
| compatibility | Codex hook 注册与 canonical hook 脚本不改；OpenCode source installer 与 npm adapter 都安装同一 runtime closure | `git diff -- .codex-plugin hooks` 为空；source-installer closure test、package tests 141/141、pack tests 9/9、三宿主 smoke 通过 |
| rollout / migration ordering | 安装先走既有 ownership/collision preflight；OpenCode shared runtime 按现有保留策略卸载，不猜测删除所有权 | adapter lifecycle 测试验证 runtime 内容与 tarball 一致且 uninstall 后 retained |
| over-broad absolute | 不宣称 smoke 已执行 Codex runtime；只记录 native plugin registered；OpenCode runtime 另由原生插件 harness 执行 | `host-smoke.sh` 终态字段区分两种证据强度 |
| residual risk | OpenCode 公共事件 API 的未来 schema 变化仍需跟随宿主升级重跑；本轮不发布，真实 registry 首发与 Trusted Publisher 仍是独立发布授权 | 本轮边界保持 local commit + local `dev` merge，无 push/tag/publish |
