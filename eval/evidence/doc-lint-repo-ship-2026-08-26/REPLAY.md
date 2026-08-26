# 枚举器进发布闭包的可复算证据

## 为什么有这一轮

058 把整仓文档扫描接进了闸，但枚举器放在仓根 `scripts/`——而 npm 打包的 `roots` 是
`.claude-plugin / .codex-plugin / agent-context / skills / hooks / packages/opencode-plugin /
scripts/owner-dispatch`，**仓根 `scripts/` 不进包**。

于是 v0.5.0 之后的发布闭包增量只有 18 行（判据文档 17 行 + 台账 1 行），
而那 17 行描述的闸本身（180 行检查器 + 338 行测试）一行都发不出去。
装了包的人读到 §10 里的路径，在自己仓里找不到任何东西。

`doc-lint.py` / `figure-lint.py` 本来就在 `skills/tighten-doc/scripts/` 下、是进包的；
枚举器放在仓根是位置放错了，不是能力不该发。

## 改了什么

| 项 | 前 | 后 |
| --- | --- | --- |
| 枚举器 | `scripts/check-doc-structure.py`（不进包） | `skills/tighten-doc/scripts/doc-lint-repo.py`（进包） |
| 测试 | `scripts/test_check_doc_structure.py` | `skills/tighten-doc/scripts/test_doc_lint_repo.py` |
| linter 解析 | 假定在被扫仓库的 `skills/tighten-doc/scripts/` 下 | 取自己的同级文件 |
| fixture 排除 | 写死 `skills/tighten-doc/scripts/tests/` | 由 linter 位置派生，只在它确实位于被扫仓库内时生效 |

后两条是**同一个不变量的两半**：脚本不再假定被扫仓库里有这个技能。本仓命中排除、
消费仓解析为空（什么都不排除），两边都对。写死路径在消费仓里是反向错误——
会去吞掉人家碰巧同名的真文档。

## 三条命令与期望

| 命令 | 期望退出码 | 期望关键行 |
| --- | --- | --- |
| `python3 skills/tighten-doc/scripts/test_doc_lint_repo.py` | 0 | `Ran 16 tests` + `OK` |
| `python3 skills/tighten-doc/scripts/doc-lint-repo.py .` | 0 | `doc_structure_check_ok: <N> tracked doc(s), 0 ERROR, <M> WARN` |
| `CCL_SKILL_BASE_REF=origin/main make test` | 0 | `alias_audit_ok`、`r0_status=private-ok` |
| `cd packages/ccl-skills-npm && npm ci && npm test` | 0 | `shipped-doc-lint-repo.test.mjs` 5 pass |

前两条完全由包内文件决定、可自行复算；第三条依赖维护者私有 alias，
**如实标为不可从包内独立复核**。

## 发布物包含性有了自己的测试（评审两条 lane 都要求的）

手工跑一次构建再把结果贴进证据文件，**不可重跑**——打包明天再漏装，全部测试与闸照样绿。
这正是 058 的形状在本轮身上复现：验证面覆盖正确性，不覆盖可交付性。

`packages/ccl-skills-npm/test/shipped-doc-lint-repo.test.mjs` 补上这一面。它跑在 `npm test` 里
（该命令第一步就是 `npm run build`，所以 `dist/` 已就位），由 CI 的 `npm-packages` job 消费。
五条断言：两个必需文件在 dist 中；**用 dist 里的那份脚本**跑干净仓 / 含 ERROR 仓 /
消费者自己的 `tests/` 目录不得被吞 / 大写扩展名。

**反向差分**：把 `dist/.../doc-lint-repo.py` 删掉后 5 条全部转红，还原后回绿。

## 外部仓实测（这一轮的全部意义）

在三个 `git init` 现造的、完全不含本技能的仓库上跑迁移后的脚本：

| 场景 | 期望 | 实测 |
| --- | --- | --- |
| 干净（含一篇 `.MD`） | rc=0 | rc=0，`2 tracked doc(s), 0 ERROR` |
| 含 ERROR | rc=1 | rc=1，点名 `WCAG-131-TABLE` |
| 缺陷在大写扩展名文件上 | rc=1 | rc=1，点名 `WCAG-131-TABLE` |

## 突变差分 17/17

058 的十五条全部保留并复验，另加两条本轮新增维度：**排除写死成本仓路径**、
**linter 改回在被扫仓库里查找**。逐一施加后套件均转红，施加后一律还原并复验 baseline 为绿。

新增测试腿 `test_consuming_repo_excludes_nothing_and_still_works`：
被扫仓库里放一篇路径为 `skills/tighten-doc/scripts/tests/their-own-doc.md` 的**真文档**，
写死排除会吞掉它、判定翻绿；派生排除不吞，判定保持 rc=1。
