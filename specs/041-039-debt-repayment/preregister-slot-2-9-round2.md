# 槽位 2/9 第二轮预注册（双删臂 + 归因臂）—— 先于本轮任何一次运行落盘

承接 `specs/039-design-first-shrink/preregister-slot-2-9.md`（sha256 `37d30b57…`）。该清单的全部冻结项**逐字继承**，本文件只增两条臂与其读数规则。

## 冻结项（继承，不重述即不改）

| 项 | 值 |
| --- | --- |
| 观察点 | `skills/skill-extraction-workflow/scripts/eval-routing-bank.rb` |
| 被测用例 | `route-opencode-global-snapshot-audit`（`eval/routing-tasks.jsonl` 第 79 行，逐字节取用，不改 bank） |
| 每臂运行次数 | **5** |
| 判定函数（唯一，写死） | 该臂 5 次运行中该用例被路由到 `skill-extraction-workflow` 的次数（`pass_count ∈ 0..5`） |
| 效应判据 | `pass_count(控制) − pass_count(某臂) >= 3` 方可认定该臂删掉的文本承重 |
| 假阳上限 | 安慰剂臂与控制臂的差 `>= 3` 即判本探针失效 |
| 模型 | `eval-routing-bank.rb` 默认（本机 claude-haiku-4-5） |
| 注入点 | `skills/skill-extraction-workflow/SKILL.md` 的 frontmatter `description` 字段 |

## 被删文本跨度（冻结，逐字节）

| 记号 | 跨度（含前导 ` / `） |
| --- | --- |
| A | ` / 核查全局安装点（~/.config/opencode 等）旧快照是否遮蔽本仓技能` |
| B | ` / 本仓（ccl-skills 等共享技能仓）OpenCode 项目配置·命令治理` |

A 是槽位 2/9 的被测规则。B 是**另一轮**（`route-opencode-project-config`）的产物，带 `OpenCode`、`本仓`、`技能仓` 全部字面 token，是 039 的删 A 单臂**未排除的位移候选**。

## 本轮新增的臂

| 臂 | 操作 | 次数 |
| --- | --- | --- |
| 删 A+B | 同时删除两个跨度 | 5 |
| 删 B | 只删 B | 5 |

039 已实测的三臂（控制 5/5、删 A 5/5、安慰剂 5/5）直接引用，不重跑。

## 读数规则（先于运行冻结，不得事后挑选）

设 `C=5`（控制），`X=pass_count(删A+B)`，`Y=pass_count(删B)`。

| 条件 | 结论 | 槽位 2/9 终态路径 |
| --- | --- | --- |
| `C − X >= 3` 且 `C − Y < 3` | A 承重；B 是掩盖了 A 效应的位移锚 | `keep` (b) 成立 |
| `C − X >= 3` 且 `C − Y >= 3` | B 承重、A 不承重（或 A/B 冗余互备） | 按 `superseded` 走零损失义务表，义务由 B 承接 |
| `C − X < 3` | A、B 均不承重于该用例 | 按 `收窄`/`superseded` 重判；并**另行登记**台账行 `source-register.md:58` 的因果主张与当前表面不符 |

## 复原与校验

每臂跑完以 `git checkout -- skills/skill-extraction-workflow/SKILL.md` 复原，并以 `git diff --quiet` 校验；未通过即本臂作废重跑。

## 边界（先写死，防事后外推）

本探针只界定**该一条用例**在**当前 grader 与当前 description 表面**下的行为。不外推到其它用例；不追认也不推翻台账行当初在旧表面上的测量；`C − X < 3` 的结论是「当前表面下不承重」，不是「这条规则从来无用」。
