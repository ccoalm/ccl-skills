# 064 evidence — 测量设计与边界（引用任何数字前先读）

## 探针设计（probe-064-patterns.rb）

- 形态：023 同款 body-as-prompt 差分。`claude --print --tools "" --model claude-haiku-4-5`，中性 tmp 目录，180s 超时，10 轮/任务，错误轮计 fail 且留痕。
- 两臂：base = 当前 SKILL.md Workflow 段（slice-base.md，sha256 见结果 JSON）；head = 改后 Workflow 段 + 快速选用决策表 + 写完测试走查清单（模拟指针被跟随后可见的面）。
- 判分：关键词合约（机械谓词），跑正式臂前已过 `--selftest`（对已知好/坏样例各能绿能红——oracle 可失败性已证）。

## 这些数字不是什么

1. **不是 merge gate**（eval/AGENTS.md advisory 契约）。
2. **不证明"agent 会跟随指针"**——head 臂直接嵌入了指针指向的内容；真实 agent 需要自己决定读 reference，那是另一个（live-repo）探针形态，本轮未做。head−base 的 delta 只支持「firing point 处可见面变化会改变输出」。
3. **关键词合约 ≠ 语义质量**。谓词判的是结构特征（命名了 smell 类、出现工厂/参数化结构），不是测试代码整体好坏。
4. **单 provider 单 model**。023 先例：Claude 臂的 delta 在 codex 复跑中未复现；本轮结论限定在所用 provider/model，跨 provider 不外推。
5. **污染面**：两臂同环境同注入，差分有效性成立；但 `claude --print` 可能加载用户全局 CLAUDE.md，绝对分可能受染。跑后对 ans_head 抽查 grep 全局指令特征词（CodeGraph / context-mode 等），结果记于下方。

## 判分器校准记录（r1 废弃轮）

第一次 base 臂（probe-064-base-r1-discarded.json，T1 2/10 / T2 0/10 / T3 0/10）判读后**废弃**，原因与处置：

- T1 假红：模型以意译命名问题类（「条件跳过」「混合多个关注点」），初版正则只认近术语。→ 放宽同义词类，并把该意译输出钉进 `--selftest` good[1] 作回归 pin。
- T2 测量污染：任务上下文不自包含，模型合理追问而不写代码——测的变成「是否追问」。→ 任务与 F29 fixture 补足模块定义 + 明示不需更多上下文；「追问不写码」钉进 selftest bad[1] 保持 RED。
- T3 真红：7–11 个复制粘贴测试函数、零参数化，判分成立，未改。

校准发生在被测改动（SKILL.md）落地**之前**，符合「判分标准先于被测改动」；校准后 base 臂全量重跑，不与 r1 分数混配。

## 正式两臂结果（claude-haiku-4-5，10 轮/任务，errors 0；判分器经 codex 评审后二次收紧的终值）

| 任务 | base | head | 判读 |
| --- | --- | --- | --- |
| T1-smells（未投入） | 9/10 | 9/10 | 配对对照：无改动处无 delta |
| T2-fixture（§4 指针+自查表） | 1/10 | 9/10 | +8 |
| T3-param（§8 指针+自查表） | 1/10 | 4/10 | +3 |

演变链（全程留痕）：初版判分 T2 10/10 被 codex review 指出 keyword-only 假绿通道（实测 6/10 pass 走该通道）→ 收紧后重跑（真模型调用）得 T2 5/10 / T3 4/10 → 抽查 fail 发现 Builder 类/pytest-fixture 集中构造形态被误杀（假红）→ 谓词补两形态 + selftest pin → 对 ans_full 离线重判（regrade-064.rb，T3 作不变对照验证）得终值。T3 head 的主要真红是漏 1kg/5kg 边界行——真实残余缺口，不是测量伪影。

差分归因：delta 只出现在改动瞄准的两个模式上，未瞄准的 T1 持平。切片 sha256 见两份 JSON；head 臂含义受「不证明 agent 会跟随指针」边界约束（见上）。

## Dual-track 第 4 轮（预算末轮）处置

- 2×P1（非 ONLY 重跑覆写 canonical 文件 / ONLY 合并不校验实验契约）：覆写-混配类第三轮同类复现 → **replace（删除收束）**：废除可变 canonical 输出与一切隐式合并，每次 run 写含实验契约（arm/model/rounds/slice sha）的不可变 run-ID 文件（O_EXCL 拒绝覆写）；ROUNDS 强校验正整数。本轮已冻结的 probe-064-<arm>.json 保持为历史证据，此后脚本不再写它们。此前第 2 轮的 keep-with-flock 决策被第 3 轮击穿，据此修订。
- 2×P2（要求判分器验证断言存在性/全场景/双侧边界/case id）：**scope-cut，risk owner（用户）已于 2026-08-28 批准**——按 F0-contract 与本文件边界节，关键词合约是量级证据不是语义质量判定器；把它推向完备语义判分是本仓明确否决过的方向（正则判分器伪装语义判定的教训）。处置记 accepted-boundary：引用 T2/T3 数字时须连同「判分是结构特征合约」的边界一起引用。同日用户授权一轮 **scope-bound 确认收敛 challenge**（范围仅限 probe/regrade 脚本的第 4 轮修复）。

## 收敛轮（用户授权的 scope-bound challenge，2026-08-28）

5 条发现，处置后 in-scope 零未处置 P0/P1，判 **converged**（收敛裁决按用户「按质量自行判断」授权由实现者做出并记录）：
- P1 regrade 不识别新 envelope 格式 → 修：双格式输入 + 可传 run 文件路径。
- P1 regrade 固定输出名 last-writer-wins（同形状第四次）→ 修：immutable 输出（唯一 id + grader/input sha 入 payload + link(2) no-replace 发布）。
- P1 stdin write 在 timeout 区外可阻塞、非 timeout 异常不收割 → 修：write 入 timed region，ensure 对一切异常路径 TERM→KILL 收割进程组。
- P2 run-id 秒级+PID 可撞 → 修（1 行）：加密随机段。
- P2 crash 截断文件顶 final 名 / checkpoint / fsync → 半修：tmp+link 原子 no-replace 发布已做；**checkpoint/fsync cut**（30 调用证据脚本，崩溃重跑即可；单机顺序边界已声明）。
验证：selftest 绿；regrade 对冻结文件幂等（9/9、4/4 不变）；live 冒烟出 envelope run 文件并被 regrade 正确消费；双次 regrade 无冲突；全部输出 JSON 可解析。

## 污染抽查记录

r1 轮与正式 base/head 臂全部 ans_head 对 `CodeGraph|context-mode|ctx_|lark-cli|ccl-skills` 抽查：均 0 命中。
