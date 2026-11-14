# F41–F44 配对行为评测：摘要

评测日期 2026-11-13。上一轮把 F41–F44 只冻结、没有运行（`../validation.md` 第 10 行）；本轮按冻结的任务和评分标准跑完，没有改任务或评分标准。

## 结论

- **技能改善了建议质量，四个任务都是。** 盲评按评分标准逐项打分（满足 1、部分 0.5、缺失 0，取每个回答的平均），每臂每任务 10 个有效回答：

  | 任务 | 改前 | 改后 | 差 | 置换检验 p |
  |---|---|---|---|---|
  | F41 库发布与双格式声明 | 0.68 | 0.87 | +0.19 | 0.002 |
  | F42 strict 迁移 | 0.77 | 0.91 | +0.14 | <0.001 |
  | F43 外部输入边界 | 0.90 | 0.99 | +0.09 | <0.001 |
  | F44 monorepo 项目引用与编译器升级 | 0.78 | 0.93 | +0.15 | <0.001 |

  工具自带的成对判定（`run1/capability-delta-report.md`，只看第 1 个样本）四项都是 improved、无 reduced。
- **技能有一处缺陷，已修复。** 编译器升级的第 4 步没说在哪里压制报错，改后的回答在两轮里分别有 4/10、5/10 建议用 `@ts-expect-error` 压弃用选项的报错，而这类报错只有 `ignoreDeprecations` 能压。改前 0/10，修复后 0/10。见下文「缺陷：弃用选项的压制方式」。
- **结论类别：** 从「证据不足」改为「稳定成功，附一处已修复的缺陷」。

## 两臂与隔离

- 改前臂：`e0a0568` 的整个插件树；改后臂：`51b32dd` 的整个插件树。两棵树都删掉 `eval/`、`specs/`（不是插件运行时内容，且改后树里有 F41–F44 的评分标准）。删除后两树的差异正好是 PR #224 的改动。
- 每次运行：`claude -p --model claude-opus-5-5 --max-turns 12 --tools Read Grep Glob Skill --permission-mode dontAsk`，用 `--plugin-dir` 只加载本臂的树，关掉已安装的 ccl-skills 与 context-mode 插件，去掉父会话的环境变量。
- 文件系统隔离：每次运行在 `bwrap` 里，`/tmp`、本机所有含该技能的检出目录、宿主的会话记录目录都用 tmpfs 盖住，再只读挂回本臂的树，工作目录每次为空。原因见下文「评测工具缺陷」。隔离探针（`isolation-probe/`）让两臂主动搜 `typescript-dev`：改前臂找不到技能，改后臂只找到自己的树。
- 交错运行：按样本序、两臂交替，4 个并发，同一轮完成。80 个样本全部有效（无超时、无权限拒绝、无错误）。
- 泄漏审计：逐条检查工具调用的输入与结果，改前臂没有任何调用或结果提到 `typescript-dev` 或改后树，反之亦然（`run1/analysis.md`）。改前树全文不含 `typescript-dev`，所以这项检查能判红。F44 改前臂第 1 个样本 Glob 了一次宿主插件缓存目录（不含该技能，也没读其中文件），记为无害。
- 技能调用：改后臂 40/40 实际调用了 `typescript-dev` 并读了对应 reference；改前臂调用 `nodejs-service-dev`（F41、F44）、`product-rd-workflow`（F42）或什么都不调用（F43）。

## 评分方法

- 盲评（`harness/blind_judge.py`）：每个回答单独评，不给臂标签，技能名替换成 `[skill]`，评分顺序打乱；评分项是把冻结评分标准的「应」「弱点」两段按全角分号机械切开，逐字保留。评分模型无工具、无插件、无 hook。
- 评分器先验：用一个故意写差的 F43 回答和一个按标准写的回答试评，前者 0 项满足并标出两个弱点，后者全部满足（`harness/oracle/`）。
- 抽查：评分器给出的最大几处差异用原始文本复核，一致：F41「类型依赖放 dependencies/peerDependencies」改前 0/10、改后 7/10 提到；F44 `customConditions` 改前 0/10、改后 9/10。
- 弱点项两臂几乎都没出现（只有 F42 改前一个回答被判为靠 `skipLibCheck` 或缩小 `include` 消错误），不区分两臂。
- F42 S6（说明 `noUncheckedIndexedAccess` 不在 strict 内并让下标访问变成 `T | undefined`）两臂 20 个回答全部判部分满足：回答都把它当独立开关处理，但很少明说。两臂相同，不区分技能价值，不据此改技能。

## 逐项读数

完整表在 `run1/analysis.md`。改后提升集中在：

- F41：S3 类型依赖位置（0→7 满足）、S4 先确认是否需要 `require`（0→3 满足）。
- F42：S4 CI 覆盖每个 tsconfig（1→10）、S5 最后移除局部覆盖（4→9）。
- F43：S3 按边界决定剥离或拒绝未知字段（0→9）。
- F44：S3 引用方向与架构一致、循环是设计问题（0→5）、S4 先构建还是源码直连（0→8）。

两臂都满分的项（如 F41 S1/S2/S5、F43 S1/S2/S4/S5）不区分技能价值：没有技能，这个模型也做到了。

## 成本

| 臂 | 40 次总费用 | 平均每次 |
|---|---|---|
| 改前 | 13.71 USD | 0.34 USD |
| 改后 | 14.20 USD | 0.36 USD |

改后每次约多 0.01 USD（约 4%）。每任务每臂的平均费用、耗时、轮数见 `run1/analysis.md`。

## 缺陷：弃用选项的压制方式

- 失败形态（改后技能树）：「目标是不加 `ignoreDeprecations` 也能零报错。确实修不了的报错，用 `// @ts-expect-error <原因>` 局部压住」；「不要加 `ignoreDeprecations`……每个新报错要么修掉，要么加 `// @ts-expect-error`」。逐条见 `run1/deprecation-check.jsonl`。
- 专项判定（`harness/deprecation_judge.py`，同样盲评）：问「是否建议用源码注释压住弃用编译选项的报错」。先验：已知错误的回答（第一轮改后第 8 个样本）判为是，一个故意同时提到两种机制的正确回答判为否（`harness/oracle/F44-deprecation-oracle.jsonl`）。
- 事实核实（TypeScript 6.0.3 实跑）：`baseUrl` + `moduleResolution: node10` 的配置，源码里放 `// @ts-expect-error`，`tsc` 仍报 `tsconfig.json` 上的 TS5101、TS5107，退出码 2；只加 `"ignoreDeprecations": "6.0"`，退出码 0。
- 修复：第 4 步写明按报错位置压制——源码行用 `// @ts-expect-error <reason>`；弃用选项报在 `tsconfig` 上，源码注释压不住，只有 `"ignoreDeprecations": "6.0"` 能压，并且在迁到 7.0 前必须去掉（与第 3 步一致）。
- RED → GREEN（`run2-fix/`）：同一轮交错跑，改前一臂是 `51b32dd` 原技能树，改后一臂只多了这一段修复。专项判定：修复前 5/10、修复后 0/10（Fisher 精确检验单侧 p≈0.016）。评分标准覆盖率 0.97 对 0.96，无回退。第一轮同一问题是 4/10，两次结果一致。

## 未归因于技能的错误

评分器在改后回答里报的事实错误比改前多（第一轮 F41 4/10 对 1/10，F42 5/10 对 2/10）。逐条核对（`run1/judgments.jsonl` 的 `wrong_facts`）：

- `import { foo } = require(...)` 语法错：改前臂也出现，技能里写的是正确的 `import x = require()`。
- `--noCheck` 版本（5.5 还是 5.6）：技能里没有这个内容。
- `in` 判断不能收窄 `Record` 下标、`localStorage` 返回值不是 `any`：模型自身的错误，技能没有相关说法。
- 「`types` 不在第一位 TypeScript 就不读类型」的说法过强：技能写的是「`types` 条目不会被读到」，是准确的；夸大出在回答。
- `@ts-expect-error` 压弃用报错：归因于技能，已修复，见上节。

## 评测工具缺陷（不在本 PR 修复）

本轮先用 `skills/skill-extraction-workflow/scripts/skill-behavior-eval.py` 的原始臂配置做冒烟，发现它的隔离不成立：

1. `--allowedTools Read Grep Glob Skill` 只是预先批准，不限制工具。在以 `bypassPermissions` 运行的宿主上，两臂都用了 Bash、Write、`npm install`，往共享工作目录写文件，改前臂还执行了 `find / -name SKILL.md`。脚本注释说的「read-only MODEL tools」不成立。`--tools` 才限制可用工具；`eval-golden-trace.rb` 用了同样的参数。
2. 子进程继承父会话的 `CLAUDE_CODE_SESSION_ID` 等环境变量，从而把父会话的临时目录当作允许路径；`/tmp` 下 Claude Code 自己的目录对只读工具也可读。
3. Read、Grep、Glob 不受工作目录限制，`--add-dir` 加 `dontAsk` 也拦不住对父目录和 `/tmp` 的搜索；只有命名空间隔离（本轮用 `bwrap`）能保证一臂看不到另一臂的树和本机检出。

本轮的驱动（`harness/paired_tree_eval.py`）只替换臂的启动命令，复用工具的流解析、失败即拒、签名和报告。工具本身的修复属于 `skill-extraction-workflow`，状态 `pending`，后续单独处理。

## 局限

- 只用一个模型（claude-opus-5-5），其他模型未测。判断：更弱的模型差距可能更大。
- 评分器与被测模型同一家族；用了盲评、先验和原始文本抽查来降低偏差，但不是独立家族评分。
- 四个夹具都是 `human: true`，评分器结论是辅助判断。本轮人工复核限于上面的抽查和缺陷样本逐条阅读，没有逐个读完 100 个回答。
- 每臂每任务 10 个样本，满足单任务行动分辨率下限（≥10 个有效观测）。

## 目标映射

| 负责方 | 方向 | 状态 | 文件或理由 |
|---|---|---|---|
| `typescript-dev` | 本体 | updated | `references/compiler-config-and-checking.md` 第 4 步 |
| `nodejs-service-dev`、`web-react-dev`、`app-cross-platform-dev` | 兄弟（运行时） | unchanged | 编译器升级与弃用选项属于语言层，已路由到 `typescript-dev`；这些技能里没有压制弃用报错的说法（全仓搜索 `ignoreDeprecations` 只命中 `typescript-dev`） |
| `testing-strategy` | 下游（验证） | unchanged | 修复不改测试分层或类型检查闸 |
| `product-rd-workflow` | 上游（交付流程） | unchanged | 不改阶段闸或路由 |
| `skill-extraction-workflow` | 评测方法 | pending | 评测工具隔离缺陷，见上节；不在本 PR 修复 |

## 复现

```bash
git archive e0a0568 | tar -x -C <root>/before   # 改后臂用 51b32dd；两棵树都删 eval/ specs/
python3 harness/paired_tree_eval.py --tool skills/skill-extraction-workflow/scripts/skill-behavior-eval.py \
  --fixtures eval/behavior-fixtures.jsonl --before <root>/before --after <root>/after --cwd <root>/cwd \
  --out <out> --model claude-opus-5-5 --only F41,F42,F43,F44 --samples 10 --workers 4 \
  --mask /tmp --mask <每个含该技能的检出目录> --mask <宿主会话记录目录> ...
python3 harness/blind_judge.py --tool ... --fixtures eval/behavior-fixtures.jsonl --run <out> --out <judge> \
  --model claude-opus-5-5 --skills-dir <root>/after/skills
python3 harness/analyze.py <out> <judge>
```

驱动输出的 `layers.json` 与每个样本的 `*.meta.json` 入库时各合成一个 JSON Lines 文件：`run*/layers.jsonl` 记录每轮实际用的树、模型、轮数和遮盖目录（家目录写作 `~`，本机目录名已泛化），`run*/meta.jsonl` 每行是一个样本的工具调用、费用、耗时和泄漏审计用的工具结果开头。原始回答在 `run*/responses/`，盲评输出在 `run*/judgments.jsonl`。

入库副本相对原始输出的改动，只为通过公开脱敏和引用检查，均在评分之后：家目录与本机目录名泛化；三个 F43 回答里模型自拟、域名不在 example 保留域内的两个测试邮箱，改为 `a@example.org`、`a@example.net`；隔离探针回答里一处指向 specs 目录的省略路径改为 `<specs-dir>/...`。
