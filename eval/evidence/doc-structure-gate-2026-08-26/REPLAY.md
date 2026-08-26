# 文档结构闸的可复算证据

> **路径已迁移（059 轮）**：枚举器与其测试从仓根 `scripts/` 移进技能包，成为
> `skills/tighten-doc/scripts/doc-lint-repo.py` 与 `test_doc_lint_repo.py`。
> 原因是仓根 `scripts/` 不进 npm 发布闭包——本文记录的能力当时**发不出去**，
> 装了包的人只能读到描述它的那 17 行说明、拿不到闸本身。下面命令按当时的路径原样保留
> 作为历史记录；要复算请用迁移后的路径，验收记录见 059 轮的 REPLAY。

**能被独立重跑才算证据，我说跑过了不算。** 冻结评审包只含 diff，所以下面每条都用
包内 tracked 文件表述，评审方可自行复算。

## 三条命令与期望

| 命令 | 期望退出码 | 期望关键行 |
| --- | --- | --- |
| `python3 scripts/test_check_doc_structure.py` | 0 | `Ran 15 tests` + `OK` |
| `python3 scripts/check-doc-structure.py .` | 0 | `doc_structure_check_ok: <N> tracked doc(s), 0 ERROR, <M> WARN` |
| `CCL_SKILL_BASE_REF=origin/main make test` | 0 | `alias_audit_ok`、`r0_status=private-ok` |

前两条**完全由包内文件决定**（检查器、测试、被调用的 linter 都在 diff 里）。
第三条依赖维护者的私有 alias 配置，本地实测通过、包内不可复算——**如实标为不可从包内独立复核**，
不当成已验证。

## 落地前的语料实测（决定分档的那组数）

| 口径 | 篇数 | ERROR | WARN | 耗时 |
| --- | --- | --- | --- | --- |
| tracked，排除 fixture | 481 | 0 | 75 | 0.15s |
| fixture 目录（`skills/tighten-doc/scripts/tests/`） | 13 | 2 | 9 | — |

fixture 那 2 个 ERROR 是按构造存在的，所以排除是必需条件而非图省事：扫它等于让这道闸对
"证明检查器有效"的输入永久红。

## 突变差分 15/15

对 `scripts/check-doc-structure.py` 逐一施加下列突变，套件必须转红；施加后一律还原并复验 baseline 为绿。

排除放宽成子串 / 放宽成全排 / 完全失效；扩展名改回大小写敏感；枚举退回 `git ls-files '*.md'`；
去掉退出码与汇总的交叉核对；交叉核对方向写反；有 ERROR 仍返回 0；去掉退出码范围检查；
去掉空作用域守卫；去掉合计行解析守卫；ok 行不报篇数；ok 行不报 WARN 数；缺 linter 也放行；
git 失败当成空清单。

复算方式：把某条突变施加到该文件后跑第一条命令，应转红；还原后应回绿。

## 三条本来会静默通过的假断言（两条由评审发现）

1. **排除只是单向断言**。带缺陷的文档放在不含 `tests/` 的路径上，于是把前缀放宽成子串匹配时
   掉的只是一篇干净文档、判定不变、腿照样绿，而注释里明写"双向"。突变探针发现。
2. **WARN 那条腿断言的是静态字样**。搜的是成功行里恒存在的 `WARN` 与 `non-blocking`；
   加上计数断言后当场暴露：那个 fixture **一条 WARN 都不产生**，这条腿此前什么也没测。challenge lane 发现。
3. **非 git 目录那条腿只断言通用 token**，分不开"git 失败"与"空作用域守卫接住了空清单"。
   突变探针发现（唯一一条 GREEN 假通过），改为点名 `git ls-files exited` 后转红。

**共同形状**：断言写在"输出里恒存在的东西"上，而不是写在"会随缺陷变化的量"上。
