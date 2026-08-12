# 011 — 统一 npm 分发：`@ccoalm/ccl-skills`

## Artifact classification

主体是 `runtime/code`（`packages/` 下的实现），附带一条 CI 发布自动化（publish job）。**不改任何 gate 判据**：`skills/` 正文、`hooks/` 行为、`check-ccl-skills.sh` 的阻断项都不动，打包只是把它们原样搬进 tarball。因此不触发 shared-gate 分类；文档改动与 `7038b93` 同批走。

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

仅当某个 host 强制要求写入共享目录（OpenCode 的 `~/.config/opencode/skills/` 是已知的一处）时，才退到下面的 manifest 方案，并且**删除授权必须来自 manifest 之外**：与一份独立可信的来源清单取交集，manifest 完整性无法确立时 **fail closed**。

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
| A3 | 无 checkout 装 OpenCode | `~/.config/opencode/skills` 出现 32 个技能目录，**且内容来源可判定**（来自 tarball 而非某个 checkout）。只断言"目录数对"会让 A10b 的回归 false-green |
| A10 | 既有产物不被破坏 | 目标路径先放 marketplace 装的和手工定制的文件 → 安装失败或 `uninstall` 之后，这些文件**逐字节存活** |
| A11 | `CCL_SKILLS_REPO` override | a) 设了有效 override → 装的是 override 的内容；b) 未设 → 可离线用 bundled 装；c) 无效 override → **任何写入之前**失败 |
| A12 | manifest 过期 / 被篡改也不误删 | a) 装后改动该产物 → `uninstall` 保留并报告；b) 装后被 marketplace 替换 → 同样保留；c) manifest 被改成指向 allowlist 根之外或符号链接 → 拒绝，不删任何东西；d) **allowlist 内的伪造条目**（指向别的用户文件并记下其真实 hash）→ 仍拒绝删除 |
| A4 | 单端限定 | `--host codex` 只动 Codex，其余两端零副作用 |
| A5 | 快照可追溯 | `release.json` 的 `sourceCommit` 等于构建时 HEAD，`snapshotHash` 稳定可复算 |
| A6 | update | 默认 dry-run 不碰网络与全局 npm 状态；`--yes` 才升级并刷资产 |
| A7 | uninstall | 三端产物清干净，不留孤儿 marketplace 条目 |
| A8 | doctor 报双装 | 人为造出 marketplace + npm 双装，doctor 明确报出并给二选一 |
| A9 | 发布链 | tag 触发 CI publish job，`npm view @ccoalm/ccl-skills` 可见且带 provenance |

## 测试层决策表

| 层 | 决定 | 命令 / 证据 |
| --- | --- | --- |
| unit | add | `node --test test/*.test.mjs`（沿用 codex-npm 现有形态） |
| pack / 内容闭包 | add | `pack.test.mjs` —— 断言 tarball 内 closure 完整、模式位只有 644/755、无 `.gitignore` 残留 |
| build-modes | add | `test-build-modes.mjs` —— git 可用 / CI checkout 两种取文件路径都能构；**并断言 CI 路径不会纳入未跟踪文件**：在某个 asset root 下造一个未跟踪哨兵文件，要求它被排除或构建直接失败 |
| E2E host smoke | add | 临时 `HOME` + 真实 CLI 跑三端 lifecycle（现有 `host-smoke.sh` 只覆盖 Codex，扩到三端）；A1–A4、A7、A8 在这层 |
| E2E 碰撞 / 回归 | add | **不能只在干净 HOME 上测**：A10 先在目标路径埋 marketplace 产物和定制文件再跑 install 失败与 uninstall；A11 三个分支各一条；A12 三个分支各一条（装后改动、装后被替换、manifest 篡改）。这三组正是 CI 会 false-green 的面 |
| CI publish | 手动 | A9 只能在真发布时验；首发用 `--dry-run` 预演一次再真发 |
| manual | run | A5 复算 `snapshotHash` |

`host-smoke` 需要本机装有对应 CLI；缺哪端就把那端标 `blocked` 并如实报，不伪造。

## 分阶段

1. **P1 骨架**：新建 `packages/ccl-skills-npm`，搬 codex adapter（已自包含，风险最低），跑通 A2 + unit/pack/build-modes。
2. **P2 Claude adapter**：A1。closure 加 `.claude-plugin` + `subagent-start.md` + `hooks/`。
3. **P3 OpenCode adapter**：A3。这是唯一的模型变更（读 checkout → 读 bundled），工作量最大。
4. **P4 收口**：CLI 合一、doctor 双装检测（A8）、uninstall（A7）、update（A6）。
5. **P5 发版链**：CI publish job、Makefile 目标收敛、删掉 `make help` 里那句虚述、README/ARCHITECTURE 同步。**认证路径必须先定死并验证**：`id-token: write` 只服务 provenance，不提供发布权限 —— 要么在 npmjs 上把 trusted publisher 绑到确切的 repo + workflow（首选），要么配 `registry-url` + `NODE_AUTH_TOKEN`。二选一，写进 P6 的前置检查。
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
| **发布认证路径未定**（评审 P1-1） | `id-token: write` 只给 provenance，不提供发布权限。未绑 trusted publisher 或未配 token 时 `npm publish` 未认证失败，A9 与首发全卡。处置见 P5 |

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

`local status`。分支 `worktree-npm-unified-distribution`（从 `worktree-docs-readme-freshness` 切，含文档修复 `7038b93`）。未推送、未开 PR。合并需显式授权。

`skill-extraction-workflow` 提炼轮同样未跑 —— 上一批改了 `scripts/install.sh`（repo-root `scripts/`），按 closeout gate 那批提交在提炼轮跑完前记 **interim**。本轮开工前需先处置。
