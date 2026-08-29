# zh-doc-borrow 2026-08-27 — 候选绑定证据（可复算部分逐条给命令）

本文件随冻结包提交，供评审方在不依赖作者 scratch 的情况下复核两件事：①交付面收缩的零损义务表（每条被移义务的目的地原文与唯一载体计数）；②本轮声明的机械闸与行为差分证据里，哪些可从包内独立复算、哪些不能（如实分级，不冒充全可复核）。

## 1. 零损义务表（全部可从包内复算）

收缩对象：`skills/tighten-doc/SKILL.md` 交付面 bullet（改前文本见 base `origin/dev` 同路径）。逐条：被移片段 → 目的地文件的**现行原文**（逐字引用）→ 复算命令（在仓根跑，期望命中数=1）。

| # | 被移出入口的义务 | 目的地现行原文（`skills/tighten-doc/references/delivery-face-closeout.md`） | 复算命令 → 期望 |
|---|---|---|---|
| 1 | ①投放失败形态枚举 | 「超时后半成、权限被拒、覆盖到错误的页面、缓存仍吐旧版，都会让本地看着已发、远端还是旧的。」 | `grep -rc '超时后半成、权限被拒、覆盖到错误的页面、缓存仍吐旧版' skills/tighten-doc/` → 仅 reference 1 处 |
| 2 | ①「不投放」仅限授权排除 | 「**「不投放」只能是经授权的排除**（如「工作版不外发」这类决定）。」 | `grep -rc '「不投放」只能是经授权的排除' skills/tighten-doc/` → 仅 reference 1 处 |
| 3 | ②退役仅两种可逆形态 | 「旧版退役只用**可逆的两种**：归档到明确的历史目录，或原位标「已过期 → 指向新版」。」（限定词「只用/两种」与基义务同宿主共现） | `grep -rn '已过期 → 指向新版' skills/tighten-doc/` → 仅 reference 1 处 |
| 4 | ②可逆做法不构成「被要求删除」的处置 | 「旧版含凭据 / 密钥、受删除请求约束的个人信息、或已判定有害的错误操作说明时，归档或标过期都**不构成处置**」 | `grep -rc '不构成处置' skills/tighten-doc/` → 仅 reference 1 处 |
| 5 | ②处置判定与执行不归本技能 | 「但处置**不归本技能**：…全部在安全 / 法务 / 内容 owner 那边。」 | `grep -rn '不归本技能' skills/tighten-doc/references/delivery-face-closeout.md` → 1 处（SKILL 现行行保留「不归本技能」语义于收紧句，见 #9） |
| 6 | ③交互源形态枚举 | 「交互源（可折叠节点、悬浮标签、可滚动区、分页表）导成静态图片 / pdf 时…」 | `grep -rc '可折叠节点、悬浮标签、可滚动区、分页表' skills/tighten-doc/references/` → delivery-face 1 处；`figure-and-table-craft.md` §图导出另有独立同款枚举（异链独立义务，非本表载体） |
| 7 | ③oracle 与零损核对的区分句 | 「**这条的 oracle 与零损核对不同**：那条比的是重生成前后（同一路径两次输出），比不出交互 → 静态这一次性的丢失。」 | `grep -rc '比不出交互 → 静态这一次性的丢失' skills/tighten-doc/` → 仅 reference 1 处 |
| 8 | 尾指针句（就地改写） | 入口现行行点名被移内容：「三态定义、投放失败形态与绕过路径、退役的两种可逆做法、转出规则与静态导出的 oracle 见 `references/delivery-face-closeout.md`」 | `grep -c '静态导出的 oracle 见' skills/tighten-doc/SKILL.md` → 1 |
| 9 | 入口保留的摘要义务（未移） | 回读核标志、机器校验器代理定界、blocked≠不投放、待安全处置单标转出+分开列+结案前不得报同步、稳定入口、不授权删除、全部展开再导、清点承载性实体——全部仍在入口改写行内 | `grep -c '旧版退役只用可逆做法，本条不授权删除' skills/tighten-doc/SKILL.md` → 1；`grep -c '待安全处置' skills/tighten-doc/SKILL.md` → ≥2 |

### §1 作者实测输出（逐字，最终候选上）

```
1: grep -r ... 超时后半成... skills/tighten-doc/ | wc -l = 1（references/delivery-face-closeout.md）
2: 「不投放」只能是经授权的排除 = 1（references/delivery-face-closeout.md）
3: 已过期 → 指向新版 = 1（references/delivery-face-closeout.md:22）
4: 不构成处置 = 1（references/delivery-face-closeout.md）
5: 不归本技能（reference 内）= 1（references/delivery-face-closeout.md）
6: 可折叠节点、悬浮标签、可滚动区、分页表（references/ 内）= 1（delivery-face-closeout.md；figure-and-table-craft.md:242 为「滚动区」变体的独立义务，不计此表）
7: 比不出交互 → 静态这一次性的丢失 = 1（references/delivery-face-closeout.md）
8: 静态导出的 oracle 见（SKILL.md 内）= 1
9: 旧版退役只用可逆做法，本条不授权删除（SKILL.md 内）= 1；待安全处置（SKILL.md 内出现次数）= 4
hdr: 仅取适合中文交付文档的；英文语法/标点规则不适用，已剔除（SKILL.md 内）= 1
governing-chain-diff: derived row set: 28
```

句子层 20 行 nesting-closure 的集体判据：节头仅新增来源归属，范围/强度限定逐字保留——`grep -c '仅取适合中文交付文档的；英文语法/标点规则不适用，已剔除' skills/tighten-doc/SKILL.md` → 1。

**义务检查器（会红）**：`gen_obligation_report.sh <base-ref>` 校验 base 可读、解析并打印不可变 base SHA、base bullet 唯一，且**每条「被移」义务确实存在于 base bullet**（拿 HEAD 当 base 会直接 FAIL——移出主张不成立）后，输出 base/head bullet 与目的地全文，并跑 33 项检查（移出载体 7 条各做 全包唯一+定位于目的地 双查、rephrased 载体与排他限定、入口保留摘要锚含 稳定入口/分开列+禁报同步/人读 sweep 照跑/载体无关/head bullet 唯一、双载体设计项、节头限定、代词规则锚）逐条数**出现次数**，任一不符 `obligation_check_failed` + exit 1；`--self-test` 双负测（非法 base、canary 短语）证明失败路径可触发。tracked 快照 `obligation-report.txt`（复核：`diff <(bash .../gen_obligation_report.sh origin/dev) .../obligation-report.txt`，或直接跑并看 `obligation_check_ok`）。

row set 派生可复算：`python3 skills/skill-extraction-workflow/scripts/governing-chain-diff.py <(git show origin/dev:skills/tighten-doc/SKILL.md) skills/tighten-doc/SKILL.md`（期望 derived row set: 28 = 句子层 20 nesting-closure + 交付面 8 rewritten-line；比较基取本轮 base）。

## 1b. 代词规则 ←→ 一手源逐条映射（developers.google.com/tech-writing/one/words，本会话 fetch）

| 源原文（EN，逐字） | 落地条文（中文） |
|---|---|
| "Only use a pronoun *after* you've introduced the noun; never use the pronoun before you've introduced the noun." | 它 / 它们 / 其 必须先有名词、后有代词 |
| "In general, if more than five words separate your noun from your pronoun, consider repeating the noun instead of using the pronoun." | 指代名词离得远…直接重复名词（数字阈值刻意不搬——5 words 是英文词距，中文无对应可靠换算，见 figure-craft §9 无源阈值教训） |
| "If you introduce a second noun between your noun and your pronoun, reuse your noun instead of using a pronoun." | …或中间插入另一名词时，直接重复名词 |
| "Replace **this** or **that** with the appropriate noun." / "Place a noun immediately after **this** or **that**." | 指示词 这 / 那 / 该 / 此 要么换成名词，要么后接名词 |

映射范围说明：源课程的代词术语（it/they/this/that）按中文常用歧义代词本地化为 它/它们/其 与 这/那/该/此；「其/该/此」为中文特有书面指代词，归入对应分支属本地化判断（非源逐字），已在台账行以「中文改编」如实标注。

## 2. 机械闸（可从包内复算，私有项如实标注）

- `CCL_SKILL_BASE_REF=<本轮 base> bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .` → 期望末组 token 含 `entrypoint_word_budget_legacy_ok`、`entrypoint_size_blocking_ok`、`ccl_skill_check_ok`、`ccl_skill_check_clean_ok`。
- 作者最终候选上的实测关键行（逐字）：
  - `entrypoint_word_budget_legacy_ok: skills/tighten-doc/SKILL.md base_body_words=9833 head_body_words=9831 allowed_body_words=9833`
  - `entrypoint_size_blocking_ok`
  - `ccl_skill_check_clean_ok`
- 其中 `alias_audit_ok` / `r0_status=private-ok` 依赖维护者私有 alias YAML，**不可从包内独立复核**——评审方只能核公共 fallback 层；此处如实分级，不当作已独立验证项。

## 3. 行为差分（部分可复算）

- **臂文本快照、逐字 prompt 生成器（`arms/build_prompts.sh`）、原始逐跑输出（`arms/runs/`）、逐跑判分表（`arms/grading.md`，每行绑定输出文件）与哈希清单（`arms/SHA256SUMS`）均 tracked 于本目录**；唯 sample1 的 old 臂三份 raw 被作者脚本覆盖丢失，在 grading.md 如实标 `verdict-recorded, raw-lost` 并给出两种口径。臂文本亦可从版本控制重建——old 臂=base 的「句子层+中文自然表达」两节 / 「交付面」行+reference ①节；new 臂=候选同两处（与 arms/ 快照 diff 一致）；样本句与判分维度如下，任何评审方可用任意 LLM 以同构 prompt 重跑（结果为随机变量，报 spread 而非点估计）：
  - 仪器 A prompt 骨架：「只按下面的规则清单审查待审文本，逐条列出规则命中的问题（引用原文+指出所依规则）；不得使用清单之外的判断」+ 臂文本 + 四句样本：①系统会对返回结果进行校验，并对超时情况加以处理。②服务启动时会加载插件并重建索引。这会拖慢启动速度。③本次升级全面提升了系统性能。④构建产物写入 dist 目录。判分：D1=句②被按代词消歧规则命中；C1=句③被按空话规则命中（两臂存活对照）；句④为误报哨兵——针对**新增**条文应零命中，被既有规则命中的情况另行如实记录、不计 D1。
  - 作者实测（claude-sonnet-5，n=3/臂，逐跑判分见本目录 arms/grading.md）：D1 old 0/3、new 3/3；C1 两臂 3/3；句④哨兵 old 2/3、new 1/3 被**既有**主动语态条命中——两臂皆现、与新增条文无涉（初版把 old 两跑误记为无命中，经外部评审对 raw 复核纠正，勘误记录在 grading.md）。弱动词维 old 臂 3/3 被既有「删冗词的定式」类推命中 → 该子句撤回未落。
  - 仪器 A2（先行词分支补测，c13 评审要求；判据冻结于运行前）：样本句①「打包器维护一份依赖清单。缓存目录在每次构建前被清空。它随后被写入锁文件。」（「它」距先行词远且插入另一名词）；D1b old 0/3（run1 明写该问题不属于清单覆盖——天然对照）→ new 3/3（均引先行词分支）；C1 两臂 3/3；哨兵 old 1/3、new 1/3 被既有主动语态条命中（对称噪声）。prompt 可由 arms/build_prompts.sh A2-old|A2-new 重建，raw 在 arms/runs/A2-*。
  - 仪器 B2 prompt 骨架：场景=已回读命中标志、结构校验脚本已通过，问「还需要人工通读吗」，限答「需要/不需要/清单未规定」并引所依规则原文。判分：hit=答需要且引「校验绿只是人读性的代理」条文。作者实测（预冻结非对称口径：old 计终答「需要」数、new 计严格 hit=需要+引代理条文；仅计最终臂快照且 raw 在包内的跑，样本 2+3 共 6 跑/臂）：old 终答「需要」2/6、严格 hit 0/6 vs new hit 6/6，逐样本均过冻结线 → clean pass；raw-lost 与 prefinal 组不进汇总主张，仅存档（沿革见 arms/grading.md）。
  - 仪器 B1（列步骤形态）已判 ceiling 失效（场景点名校验器则两臂都会纳入），不计入证据。
