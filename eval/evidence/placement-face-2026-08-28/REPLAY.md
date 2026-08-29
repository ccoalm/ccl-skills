# placement-face 2026-08-28 — 候选绑定证据

本文件随冻结包提交，供评审方不依赖作者 scratch 复核：①SKILL 交付面 bullet 收缩片段的零损载体；②行为差分的可复算重建方式与实测记录。

## 1. 零损义务对照（SKILL bullet 收缩片段 → reference 载体；均可在仓根复算）

本轮 SKILL.md 交付面 bullet 为给新增 cue 腾出入口字数预算，收缩三处**纯示例括注**（义务本体全部保留在句中）：

| 被收缩片段 | 载体（现行原文，逐字/语义） | 复算命令 → 期望 |
|---|---|---|
| 「远端副本（飞书 / wiki 页）、附件（pdf / 大图）、导出件（png / jpg）」→「远端副本、附件、导出件」 | reference 首段逐字：「远端副本（飞书 / wiki 页）、附件（pdf / 大图）、导出件（png / jpg）」 | `grep -c '（pdf / 大图）、导出件（png / jpg）' skills/tighten-doc/references/delivery-face-closeout.md` → 1 |
| 「被要求删除的面（凭据 / 个人信息 / 有害错误说明）」→「被要求删除的面」 | reference 转出节语义载体：「旧版含凭据 / 密钥、受删除请求约束的个人信息、或已判定有害的错误操作说明时」 | `grep -c '受删除请求约束的个人信息' skills/tighten-doc/references/delivery-face-closeout.md` → 2（转出节定义句与其触发句，均为该义务载体） |
| 指针「三态定义」→「四态定义、定位判据」 | reference closeout 第 7 项走法即为四态枚举（「再逐面标**四态之一——互斥且完备」）；定位判据=新 ①b 节 | `grep -c '四态之一' skills/tighten-doc/references/delivery-face-closeout.md` → 1；`grep -c '## ①b 定位' skills/tighten-doc/references/delivery-face-closeout.md` → 1 |

row set 机械派生（终态实测，base=当前 origin/dev，完整输出入包见本目录 `chain-derivation.txt`，命令可包外复算）：`governing-chain-diff.py` SKILL → 5 行（同一 bullet 的改写行）；reference → 8 行（closeout 授权不投放 / blocked / 待安全处置行因新增要件与触发就地改写 = 6 条 left-a-rewritten-line——其中授权不投放行的改写为增加「可回读授权来源」要件、原「+ 理由」义务逐字保留在句内；另 2 条为待安全处置的子句 governing-chain-changed——子句**自身文本逐字未动**、仅父行改写导致链变；**既有删除类触发枚举逐字保留**，可复核：`grep -c '凭据 / 密钥、受删除请求约束的个人信息' skills/tighten-doc/references/delivery-face-closeout.md` ≥1，即新增触发只扩集合、不弱化既有触发与强度；新 ①b 节本身为纯新增）。**过程披露**：reference 首版编辑曾误吞 ② 节标题，正是该派生器当场抓到（② 义务整体重挂新节下）并即修复。

作者实测输出（最终候选上）：复算命令依次 1 / 2 / (1,1)；派生器 SKILL 5 行 / reference 8 行（输出入包 `chain-derivation.txt`）；既有触发枚举 grep = 2。gate 证据两层制见本目录 `gate-run.txt`（终候选绑定的权威结果=PR head 上按 SHA 键控的 CI repository-gates 运行；树内为作者本地辅助实测），已入 SHA256SUMS（自 arms/ 目录以 `shasum -a 256 -c SHA256SUMS` 可整验（Perl shasum 的 -c 模式按摘要长度自动选算法、不加 -a 亦实测通过；显式 -a 256 为跨平台明确性））。

## 2. 行为差分（headless，claude-sonnet-5，n=3/臂，隔离 cwd，污染 grep 零命中）

- 判据冻结时序分级（同 grading 的证据分级声明）：初版三维冻结先于任何编辑；评审驱动的后增维各冻结先于其首跑（历次修订披露于作者 charter，时序锚于平台侧 SHA-keyed CI run 史）；prompt 由 `arms/build_prompts.sh old|new` 从臂快照逐字重建；raw 逐跑输出与逐跑判分绑定见 `arms/grading.md`；哈希 `arms/SHA256SUMS`。
- 维度：D-pre（放置前现读结构/不按标题猜）、D-place（最具体稳定容器/标题相似非父节点）、D-loc（发布后回读父容器/完整路径）、C-ctl（既有「回读内容可识别标志」规则，两臂存活对照）。
- **主张口径**：规则可及性/引出差分（模型按清单作答能否产出义务），非真实执行场景决策行为（执行型评测未做、如实声明）。
- **行为学主张（唯一来源=终态臂计分批＝批 57（仪器 v10 十问形态；批 51 为 ctl-invalid 重采、省答跑保留包内自证；历轮评审修复——豁免括注取消、边界预读禁入、代收授权路径删除、裁决归口边界权威、预期以独立于落点的既有记录为源且无依据不自拟基线（权威裁决记录一并载明边界与 owner；私有容器路径须读回确认仅本人可及且系暂存不抵充已投放）、两态显式互斥——之后按仪器终态形态对称重跑（问题集历经 v5 四问→v9 九问，见 grading 与 charter）；批 23 计分失败已如实留档，raw 保留包内自证）；raw 全入包、臂逐字节校验；判分语义为准且覆盖全答）**：十一个差分维本批均 old 0/3 → new 3/3（D-verifyonly 上一计分批 old 曾 1/3——类推达成，跨批漂移如实留痕）；C-ctl 两臂 3/3（v6/v8/v9/v10 各新维判据均冻结先于其首跑；批 23 曾在 D-acl-pre 计分失败——形态省答，v7 修形态后过线，失败批 raw 保留包内）。勘误留痕：D-acl-pre 初版误限 A 段判 1/3，经评审对 raw 复核按冻结的全答判据改判 3/3。D-acl-over 不作差分主张——校准表述同 grading：本计分批 old 臂三跑均答清单未规定（run2 附内容命中与范围触发系不同概念的排除说明）；历史计分批曾有一跑经既有兜底直接到达同一处置（观测保留于 grading 存档表与 charter）——跨批不稳，不以差分立论。其保留依据=双 lane 收敛暴露面 + closeout 触发枚举一致性。无角色存档 raw 已按 convergence-by-deletion 移出树（原因表保留；ctl-invalid 组因需自证保留 raw）。

## 3. 与既往冻结证据的交叉说明

062 轮证据包（eval/evidence/zh-doc-borrow-2026-08-27/）为 concluded/candidate-bound：其义务检查器尾指针短语快照含「三态定义」，对本轮之后的工作树再运行将按设计 FAIL（其 AGENTS.md 已声明 concluded 语义与按包内记录 SHA 复算的方式），非本轮回归。
