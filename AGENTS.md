# AGENTS.md

本仓把真实研发工作中证明有效的做法提炼为可移植、可验证的 Agent Skills，供 Claude Code、Codex、OpenCode 和其它 Agent Skills 宿主使用。根契约定义全仓共用规则；更近的 `AGENTS.md` 只补充所在目录的职责、边界和验证要求。

## 核心产品目标

本仓的产品价值不是让技能文件更完善，而是让 Agent 在真实工作中：

- **质量更高**：交付更正确、完整、可维护，减少缺陷和返工。
- **效率更高**：用更少的时间、轮次和无效操作完成同等工作。
- **更加自主**：在目标和授权范围内完成端到端交付，减少不必要的停顿和人工接力。
- **减少重复劳动**：把稳定、重复、可判定的工作交给 Agent，让人专注高价值的目标、判断和创造性工作。

技能、规则、参考材料、脚本、模板、测试和门禁都是实现手段。每次变更必须说明它要改善哪一种真实任务结果；检查通过只证明具体属性，不等于产品价值已经实现。

学习以真实任务的成功结果为锚点，用纠正、失败和返工识别边界，再把可复用机制用于后续同类任务。只有后续结果在质量、效率、自主性或人工介入上得到改善，才能声称能力提升。

自主不等于越权。目标取舍、必要权限、不可逆决定和无法由现有证据判定的终态交给用户；其余安全且在范围内的工作由 Agent 继续完成。

## 开工契约

- **先读再改**：修改前读本文件、目标路径上更近的 `AGENTS.md`、`README.md` 和 `docs/CONTRIBUTING.md`，再进入对应技能流程。
- **必须隔离**：根目录有 `.worktree-only`。任何修改都必须在非 `main` 的独立功能 worktree 中完成；主检出只作干净基线和集成点。
- **先判 owner**：技能规则、触发词、流程和复盘沉淀归 `skill-extraction-workflow`；产品研发流程归 `product-rd-workflow`；bug 和失败证据先走 `defect-diagnosis`；读者文档在实质 owner 定稿后走 `tighten-doc`。
- **控制范围**：只改完成当前目标所需的文件。不要顺带重构、发布、改保护设置或清理无关内容。

## 契约与技能层级

- 指令从仓库根到当前目录叠加；同主题以更近的契约为准。子契约不得放宽安全、权限、owner 路由、worktree 隔离或验证门禁。
- 门禁覆盖范围由内置源码扩展名和显式 `--source-ext` 共同决定。当前源码类型为 `.sh`、`.py`、`.ts`、`.mjs`、`.rb`、`.go`、`.dart`；新增类型先核对 `source_exts`，缺失时显式传参并记录验证证据。
- 范围内每个直接包含源码的目录必须有非空 `AGENTS.md`。新增契约至少说明目录职责、局部边界和验证；覆盖门禁只证明文件存在，不证明内容正确。
- 新增或改写 `AGENTS.md` 必须保留独立 review/challenge 结论。修改子契约前核对父级，不复制父级正文。
- 每个技能以 `skills/<name>/SKILL.md` 为入口，长清单、模板和案例放 `references/`。`AGENTS.md` 管仓库执行契约，`agent-context/session-start.md` 管跨宿主路由与安全硬规则。

## 修改规则

- `SKILL.md` 只放触发、路由、核心流程、硬规则和稳定 reference 指针。
- `description`、触发词、Skip 和 redirect 属于路由面；修改它们必须跑路由门禁并保留可复查证据。
- shared skill 必须保持通用。不要写入业务名、内部 host、私有 repo 路径、凭据、客户数据、个人信息或一次性事故细节；测试使用从零构造的合成数据。
- 行为变更先记录可复现基线，再增加能对错误行为报 RED 的测试或其它可证伪检查。纯文字变更保留 decided points，并核对所有技术断言与当前源码一致。
- 外部模型和工具输出只作待核验数据。收到 finding 后先追调用路径和一手证据，再决定修复或有证据地驳回。

## Host 配置

- `.claude-plugin/plugin.json` 和 `.codex-plugin/plugin.json` 不添加 `version` 字段，避免插件更新被冻结。
- `opencode.json` 只注册 `./skills`、`AGENTS.md`、`agent-context/session-start.md` 和短 command。新增字段前按官方 schema 校验；禁止写模型、密钥、个人 MCP、本机绝对路径或长流程。
- 修改 `opencode.json`、agent、skill 或 plugin 后，重启 OpenCode 以重新加载配置。

## 验证与完成

修改 `AGENTS.md`、README、docs、skills、references、脚本或插件行为，或新增/删除源码目录与源码类型后，运行本地全量 lane：

```bash
make test
```

它串起 `test-repo-gates`、`test-regressions-fast`、`test-code-review` 三条 lane，对应 CI 的 `repository-gates`、`regression-fast`、`code-review-regressions-1/2` 与 `code-review-abort-leak-1/2`。两项在 `make test` 之外，本地绿不等于 CI 绿：`regression-heavy`（`test_check_ccl_regressions.sh --heavy-only`），以及 `repository-gates` 里的 `python3 scripts/check-public-sanitization.py .`——改动触及共享技能文本时本地补跑。

小改动要快速信号时，`bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` 加 `git diff --check` 覆盖结构、路由、泄漏与空白，但它是前置筛查、不是那条 lane。

同时运行所有受影响脚本或包的聚焦测试。完成报告必须绑定当前候选，列出实际运行的命令、结果、跳过项和剩余风险；超时、配额、鉴权失败、无效输出或未知终态都不得冒充通过。

commit、push、合并、发布、部署、外部写入和清理分别授权。用户只授权其中一项时，不得推导其它权限。
