# 逐跑判分记录（每行绑定 runs/ 下原始输出；哈希见 SHA256SUMS）

臂文本：arm-old.txt = base 的 SKILL 交付面 bullet + delivery-face reference 全文；arm-new.txt = 最终候选同两处（组包时逐字节校验）。prompt 由 `build_prompts.sh old|new` 逐字重建（v10 形态：十问——A/C 问均要求列全不省略、D 问过宽情形、E 问放置前边界义务、F 问 owner 失配、G 问路径披露、H 问无基线路径、I 问权威裁决效力、J 问只核不改；历次仪器修订均披露于作者 charter，维度定义各自冻结于对应重跑之前）。**判分语义为准且覆盖全答**（不限于单个小题段落）；token grep 仅初筛。

**主张口径声明**：本仪器测的是**规则可及性/引出**——模型只按清单作答时能否产出对应义务及其条文（old 臂产不出=规则缺失的可及性差分）；它不测真实执行场景中的决策行为（那需要执行型评测：给模型真实层级结构与工具让其实际选点/核验——超出本轮范围，如实声明为未测面）。所有 0/3→3/3 差分主张按此口径读。

## 计分批（唯一聚合主张来源：批 57——c85 challenge P1（授权不投放的授权方权限同按权威身份锚定规则核验）落地后的终态臂重跑；raw 全入包）

| 批 57 输出 | 臂 | D-pre 现读 | D-place 容器 | D-loc 路径 | D-acl-pre 放前记边界与 owner | D-acl-post 回读生效权限 | D-preread 放前读容器边界+禁入 | D-ownermatch owner 失配→待安全处置 | D-pathdisc 完整路径+披露限界 | D-nobasis 无基线不自拟+两路 | D-authrec 权威侧可回读裁决 | D-verifyonly 只核不改 | C-ctl 内容标志 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| runs/old-run1..3.txt | old | miss ×3 | miss ×3 | miss ×3 | miss ×3 | miss ×3 | miss ×3（E 答均清单未规定） | miss ×3（F 答均清单未规定） | miss ×3（G 答均清单未规定） | miss ×3（H 答均清单未规定） | miss ×3（清单未规定或限删除场景、无权威侧回读要件） | miss ×3（J 答清单未规定或类推止于删除场景——历史计分批曾有一跑经该类推达成两半判 1/3，跨批漂移已在存档表如实留痕） | hit ×3（标志措辞跨跑有变体——按判分语义为准命中） |
| runs/new-run1..3.txt | new | hit ×3 | hit ×3 | hit ×3 | hit ×3 | hit ×3 | hit ×3 | hit ×3 | hit ×3 | hit ×3（H 答均含不自拟基线语义——「不得自拟」等变体按判分语义为准——且两路完整） | hit ×3（I 答均权威侧回读+不得代收/转述/自记） | hit ×3（J 答均不构成授权+各需自身授权） | hit ×3 |

十一个差分维本批均 old 0/3 → new 3/3；C-ctl 两臂 3/3；通过线全部满足（D-verifyonly 上一计分批 old 读数曾为 1/3——经删除条款类推达成，跨批漂移如实留痕于存档表，不隐藏）。D-verifyonly 为仪器 v10 新维（判据冻结先于其首跑，见作者 charter v10 节）。D-pathdisc（v8）与 D-nobasis/D-authrec（v9）为评审「安全条款无维覆盖致假绿」系列发现的修复，判据各冻结于其首跑之前（见作者 charter v8/v9 节）。D-preread/D-ownermatch 为仪器 v6 新维（判据冻结先于其首跑，见作者 charter v6 节）——回应评审「安全关键条款无计分维会致假绿」的发现。
**勘误（评审揪出，方向对主张有利故此前反而少报）**：D-acl-pre 初版判分误限于 A 段（1/3），冻结判据本为全答语义计分——按 raw 复核后改判 3/3；erratum 留痕于此。**该勘误对历史批的含义（校准表述）**：此前各批 pre 维计数用的是同一 A 段误限判法，与其表观不稳的时间线一致；因历史 raw 已按 convergence-by-deletion 移出树，此解释**不可从包内证明**、仅为过程记录——历史批不承载任何证据角色，本轮全部行为学主张（正反两向）仅由计分批的包内 raw 承载。

**不作差分主张的维（D-acl-over）——校准表述**：计分批（批 57）old 臂三跑对问题 D 均答「清单未规定」——逐跑读 runs/old-run1..3 的 D 段可复核；new 臂三跑均直接引新条文。**本批差分表面成立，但仍不作稳定差分主张**：上一计分批（批 19，raw 已按 convergence-by-deletion 移出）old 臂曾有一跑经既有「拿不准按命中」兜底推理直接到达同一处置（过程记录于作者 charter 与下方存档表）——该维对模型推理深度敏感、跨批不稳。该子句不以行为差分立论，保留依据=review 与 challenge 两 lane 独立收敛的暴露面 + closeout 触发枚举一致性（把兜底推理显式化）。

**计分保真标注政策（如实声明）**：计分只对冻结维定义负责——raw 中出现与条文相悖的引出（如某跑把「确知更窄」误表述为通过），若其相悖处不落在任何冻结维的命中定义内，不构成该维失分，但**须在存档/计分说明中如实标注**，不作为条文正确性的证据、也不因此背书该表述；标注的目的（防误导读者把 raw 全文当条文正确性证明）与计分目的（维差分）分开持有。

**本批保真标注（按上项政策）**：本计分批（批 57）逐跑复核未见与条文相悖的引出。

**冻结时序的证据分级（如实声明）**：「维度判据冻结先于对应重跑」是过程性时序主张，**包内不可回溯证明**（任何包内文本都可能事后写成）。其证据按类分级：(a) **平台侧不可变锚**——本轮每个中间候选 head 都经推送并触发 SHA-keyed CI run（run 记录含 UTC 时间戳与该 SHA 树内容；各 head 的 run URL 由 controller 逐版记于评审 plan 的 ci-attestation 演进史），v6 仪器定义所在的树先于 v7 树存在，可由平台记录复核；(b) **包内部分自证**——批 23 formfail raw（v6 六问输出、D-acl-pre 失败）与其后 v7 重跑的通过结果构成「修复晚于失败」的一致性证据；(c) **controller 侧过程记录**——作者 charter 的历次仪器修订节（每节含冻结声明），属过程记录非独立可证。评审对时序的信任以 (a) 为准、(b) 佐证；(c) 仅供追溯参考。

**仪器不覆盖的义务（显式声明，防假绿）**：安全关键条款的维覆盖经评审逐轮补齐——v6 补 D-preread/D-ownermatch、v8 补 D-pathdisc、v9 补 D-nobasis/D-authrec（各判据均冻结先于其首跑）。当前仍不设维、不作差分主张的：D-acl-over（见下）；以及 c55-ch 后新增的「选点自评、未经独立复核」注记义务——其判据若此刻补冻结会晚于批 36 产出（带偏向），不作差分主张，保留依据=challenge lane 收敛；批 36 new 臂三跑的 C/G 段实际均已引出该注记（读者可复核，但该观察不进通过线）；**以及 c85-ch 后新增的「授权不投放之授权主体排除权须按权威身份锚定规则核验」条款——十一冻结维与十问 prompt 均无授权不投放场景，删除或弱化该条款不会改变本批任何分数，故对它不作任何差分主张（c87 review 据实指出该缺口）**：批 57 new 臂仅 run1 的 C2 段自发引出授权方排除权核验（1/3，低于 3/3 证据线，该观察不进通过线），runs/new-run2、new-run3 未提及；该条款的保留依据=review/challenge 两 lane 的暴露面（其唯一防线）+ 风险 owner 于 2026-08-29 明示接受此测量残差（处置选项 A：诚实降主张而非补第十二维重跑）。

**风险归属声明**：无角色存档 raw 的删除是评审 controller 的裁决（依据：连续三轮包内核验发现的源头、且它们不承载任何主张），已在 PR 正文向人类 risk owner 显式标出待复核——risk owner 可要求从各历史推送的平台记录恢复或接受删除。

## 存档批（原因记录；raw 已按 convergence-by-deletion 移出树——它们不承载任何主张或依据，在树三轮制造「无法包内核验」发现后删除；ctl-invalid 两组因其失效判定需 raw 自证而保留）

| 批/组 | 处置 | 原因 |
|---|---|---|
| v1prompt-old / armstale-preheading / ctlinvalid-v1prompt(raw 保留) / armstale-preacl / ctlinvalid-v1prompt-acl(raw 保留) / preoversplit(old+new) / batch8 / batch9 / batch10 | raw 删除（除注明保留者） | 臂过期或仪器改版前批次；无主张/依据角色；判定过程与原因记录于作者 charter（历次仪器修订节） |
| batch11 / batch12 | raw 删除 | 批 13 之前的候选微调使臂过期（过程记录于作者 charter）；同上按 convergence-by-deletion 处置 |
| batch13 | raw 删除 | 曾为计分批；c27 challenge P1 修复（取消 owner 失配可自证豁免括注）改动 reference 文本使臂过期，按冻结纪律对称重跑为下一计分批；其各维结果与后继批一致（差分维 old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch14 | raw 删除 | 曾为计分批；c28-r1 P1 修复（增补放置前读目标容器生效边界的前置禁入）改动 reference 文本使臂过期，按冻结纪律对称重跑为下一计分批；其各维结果与后继批一致（差分维 old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch15 | raw 删除 | 曾为计分批；c31-r1 P1 修复（owner 授权更宽投放时同步更新预期边界记录，防把刚授权的范围误判成暴露）改动 reference 文本使臂过期，对称重跑为下一计分批；其各维结果与后继批一致（差分维 old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch16 | raw 删除 | 曾为计分批；c32 challenge P1 修复（授权分支绑定与待安全处置转出同一证据标准：主体须为预置记录的预期 owner/授权主体、授权落记录、拿不准即转出）改动 reference 文本使臂过期，对称重跑为下一计分批；其各维结果与后继批一致（差分维 old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch17 | raw 删除 | 曾为计分批；c33 challenge P1 修复（投放者代收授权路径整体删除——授权记录可由投放者自记故可伪造；只认能从 owner 侧回读到的裁决记录，裁决前按 blocked 记）改动 reference 文本使臂过期，对称重跑为下一计分批；其各维结果与后继批一致（差分维 old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch18 | raw 删除 | 曾为计分批；c34-r1 P1 修复（扩边界裁决归口到边界权威——文档预期 owner 未必拥有受众扩大权限）改动 reference 文本使臂过期，对称重跑为下一计分批；其五差分维结果与后继批一致（old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch19 | raw 删除 | 曾为计分批；c35-r1 P1 修复（预期受众以既有记录为源+预读不可核验即禁入）改动 reference 文本使臂过期，对称重跑为下一计分批；其五差分维结果与后继批一致（old 0/3→new 3/3、C-ctl 双 3/3）；**其 old-run2 的 D 答曾经兜底直接到达待安全处置**（该观测保留于此与 charter，是 D-acl-over 跨批不稳的依据之一）；同上按 convergence-by-deletion 处置 |
| batch20 | raw 删除 | 曾为计分批；c36-r1 P1 修复（放前裁决等待 blocked 与已放入即暴露待安全处置两态显式互斥——本批 new-run3 的 D 答曾把已发布过宽面记回 blocked，评审据此定位条文歧义）改动 reference 文本使臂过期，对称重跑为下一计分批；其五差分维结果与后继批一致（old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch21 | raw 删除 | 曾为计分批（v5 五维形态的末批）；c37-r1 双 P1 修复（无依据不自拟基线；仪器 v6 增 E/F 两问两维）使臂与 prompt 双过期，对称重跑为批 22；其五差分维结果与批 22 对应维一致（old 0/3→new 3/3、C-ctl 双 3/3）；同上按 convergence-by-deletion 处置 |
| batch22 | raw 删除 | 曾为计分批（v6 首跑，七维全过）；c38-r1 P1 修复（owner 预期来源须独立于落点选择）改动 reference 文本使臂过期，对称重跑；其七差分维结果与批 24 一致；同上按 convergence-by-deletion 处置 |
| batch24 | raw 删除 | 曾为计分批（v7 首跑，七维全过）；c39-r1 P1 修复（无既有依据路径的权威裁决记录须一并载明边界与预期 owner，私有容器路径 owner=投放者本人）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch25 | raw 删除 | 曾为计分批（七维全过）；c40-r1 P1 修复（私有容器路径不凭名字认定——须读回其生效边界确认仅投放者本人可及，否则回转权威路径）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch26 | raw 删除 | 曾为计分批（七维全过）；c41-r1 P1 修复（私有容器路径定性为暂存不是交付——原交付面仍 blocked，不得抵充已投放）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch27 | raw 删除 | 曾为计分批（七维全过）；c43-r1 P1 修复（补回暂存面的显式预期 owner=投放者本人——该语句曾在 c41 改写中被吞）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch28 | raw 删除 | 曾为计分批（七维全过）；c45-r1 P1 修复（暂存路显式不授权新建副本——仅适用投放者按内容持有规则本就可持有的工作副本，另有持有/复制约束的内容此路不适用）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch29 | raw 删除 | 曾为计分批（七维全过；其 old-run2 的 F 答按类推止于 blocked=判 miss 的观测记录于当批说明）；c46-r1 P1 修复（放前预读同时覆盖容器控制方 owner——audience 合规但 owner 非预期时放入即失控）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch30 | raw 删除 | 曾为计分批（七维全过）；c48-r1 P1 修复（基线记录须由任务/需求/密级各自 owner 或流程产生/确认——独立于落点选择、也独立于投放者，自写记录等同无既有依据）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch31 | raw 删除 | 曾为计分批（七维全过）；c50 challenge P1 修复（定位回读的「预期」分级——任务/需求记录载明落点的以其为独立预期、未载明的回读仅证执行没走样不构成选点自证，选点正确性由选点判据+边界/owner 核验持有并靠完整路径暴露给读者/owner 复核）改动 reference 文本使臂过期，对称重跑为下一计分批；其七差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch32 | raw 删除 | 曾为计分批（七维全过）；c51-r1 P1 修复（路径披露以读者对结构的既有可见范围为限——受限层级段不进面向该读者的交付信息，防路径披露成为新的结构泄露面）改动 reference 文本使臂过期，对称重跑为批 33；其七差分维结果与批 33 一致；同上按 convergence-by-deletion 处置 |
| batch33 | raw 删除 | 曾为计分批（v7 七维全过）；仪器 v8 增 G 问与 D-pathdisc 维（c52-r1 假绿发现的修复，判据冻结先于批 34）使 prompt 过期，对称重跑为批 34（臂文本未变、prompt 变更）；其七个既有维结果与批 34 对应维一致；同上按 convergence-by-deletion 处置 |
| batch34 | raw 删除 | 曾为计分批（v8 八维全过）；仪器 v9 增 H/I 两问与 D-nobasis/D-authrec 两维（c53-r1 假绿发现的修复，判据冻结先于批 35）使 prompt 过期，对称重跑为批 35（臂文本未变、prompt 变更）；其八个既有维结果与批 35 对应维一致；同上按 convergence-by-deletion 处置 |
| batch35 | raw 删除 | 曾为计分批（v9 十维全过）；c55 challenge P1 修复（未载明落点面的已投放标注须注明「选点自评、未经独立复核」，复核通道成为申报一部分）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch36 | raw 删除 | 曾为计分批（十维全过）；c58-r1 P1 修复（closeout 已投放定义绑定 ①b——涉及放置/移动的面未跑定位与边界/owner 回读不得标已投放，堵「跳过核验即无分流触发」绕过）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch37 | raw 删除 | 曾为计分批（十维全过）；c60-P2 修复（预读确知比预期窄也不径直放入——先修边界或换容器按 blocked，不做先放进去再修）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch38 | raw 删除 | 曾为计分批（十维全过）；c61 challenge P1 修复（含「选点自评、未经独立复核」面的只得报限定式已同步，复核确认前不得去掉限定词）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（且新限定词条款被 new 臂三跑引出）；同上按 convergence-by-deletion 处置 |
| batch39 | raw 删除 | 曾为计分批（十维全过）；c63-r1 P1 修复（放后分流补「owner 读不到/无法核验以致排除不了非预期」一档同入待安全处置，closeout 触发枚举两处同步）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch40 | raw 删除 | 曾为计分批（十维全过）；c64 challenge P1 修复（限定词摘除的独立复核要件——须由投放者本人以外的有权 owner/读者确认，兼任者不得自审）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（独立性要件被 new 臂引出）；同上按 convergence-by-deletion 处置 |
| batch41 | raw 删除 | 曾为计分批（十维全过）；c65-r1 P1 修复（「或其所属的授权主体」的归属/授权关系本身也须独立记录或权威侧记录载明，投放者不得自行认定，认定不了按 owner 非预期/无法核验分流）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch42 | raw 删除 | 曾为计分批（十维全过）；c66-r1 P1 修复（放后分流安全优先——「确知更窄」档以 owner 与其余安全项符合预期为前提，同面多档命中时待安全处置吸收，不得以 blocked 绕开转出）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致；同上按 convergence-by-deletion 处置 |
| batch43 | raw 删除 | 曾为计分批（十维全过）；c67-r1 P1 修复（转出问题按命中类型对应权威——owner 归属问题归 owner 治理权威，边界权威仅当兼持 owner 治理权才可一并裁，两类命中各自结案）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（权威对型条款被 new 臂引出）；同上按 convergence-by-deletion 处置 |
| batch44 | raw 删除 | 曾为计分批（十维全过）；c68-r1 P1 修复（无基线裁决记录两半分权——边界半归边界权威、owner 半须由持 owner 治理权一方作出/确认，无治理权的边界权威单方指定 owner 不构成基线）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（两半分权被 new 臂 H/I 引出）；同上按 convergence-by-deletion 处置 |
| batch45 | raw 删除 | 曾为计分批（十维全过）；c69-r1 P1 修复（放后转出与 closeout 第 4 条的结案方同带治理权对型——owner 失配/无法核验类的结案者须实际持有 owner 治理权）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（结案者治理权对型被 new 臂 F 引出）；同上按 convergence-by-deletion 处置 |
| batch46 | raw 删除 | 曾为计分批（十维全过）；c70 challenge P1 修复（授权不投放须载明理由与可回读的授权来源——自写理由不构成授权，无可回读授权的面按实际状态标 blocked 或对应分流）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（授权来源要件被 new 臂引出）；同上按 convergence-by-deletion 处置 |
| batch47 | raw 删除 | 曾为计分批（十维全过）；c71-r1 P1 修复（「owner 治理权」歧义消解——定义为内容归属治理权（任务/需求/密级体系一侧），目标容器现任控制方不因控制容器而得此权、自署记录属自证不构成基线；四处同步）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（排除条款被 new 臂 F 引出）；同上按 convergence-by-deletion 处置 |
| batch48 | raw 删除 | 曾为计分批（十维全过）；c72-P2 修复（受限路径段省略只限面向无权读者的交付信息，完整路径须保留于核验记录并交付给对结构有权的复核方）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（全径交付复核方条款被 new 臂 G 引出）；同上按 convergence-by-deletion 处置 |
| batch49 | raw 删除 | 曾为计分批（十维全过）；c73-r1 P1 修复（裁决后预期受众/边界与预期 owner 记录整体随裁决更新——裁定过的 owner 不再被放后回读判成失配）改动 reference 文本使臂过期，对称重跑为下一计分批；其十差分维结果与后继批一致（整体基线更新被 new 臂 I 引出）；同上按 convergence-by-deletion 处置 |
| batch50 | raw 删除 | 曾为计分批（十维全过）；c75 challenge P1 修复（摘限定词的确认须由有内容归置判断权的确认方作出、且只认确认方侧可回读的确认记录——结构可见权限不构成复核资格、投放者自述已确认不算）改动 reference 文本使臂过期，对称重跑；同上按 convergence-by-deletion 处置 |
| **batch51（ctl-invalid，省答跑保留自证）** | new-run1 保留于 runs/archived-new-ctlinvalid-b51-run1.txt，其余 raw 删除 | 修复后首跑 new-run1 的 C 段省答内容标志回读（C-ctl new 2/3，未达冻结的 3/3 有效线）——整批无效，按冻结纪律重采为批 52；省答跑保留自证，其余 5 跑不承载判定角色移出 |
| batch52 | raw 删除 | 曾为计分批（v9 十维全过）；仪器 v10 增 J 问与 D-verifyonly 维（c77-r1 假绿发现的修复，判据冻结先于批 53）使 prompt 过期，对称重跑为批 53（臂文本未变、prompt 变更）；其十个既有维结果与批 53 对应维一致；同上按 convergence-by-deletion 处置 |
| batch53 | raw 删除 | 曾为计分批（v10 十一维全过，D-verifyonly old 0/3）；c78 challenge P1 修复（限定式已同步显式定性为已投放态上的注记+未结复核项清单，非第五态）改动 reference 文本使臂过期，对称重跑为批 54；其十一维通过线结果与批 54 一致（批 54 的 D-verifyonly old 读数为 1/3——跨批漂移如实记录）；同上按 convergence-by-deletion 处置 |
| batch54 | raw 删除 | 曾为计分批（十一维过线；D-verifyonly old 读数 1/3——run1 经「不授权删除」类推达成两半，如实计入）；c79b-P1a 修复（含待复核面的收尾报法不得出现「已同步」字样，改报「已投放 N 面 + 待复核清单」）改动 reference 文本使臂过期，对称重跑为批 55；其通过线结果与批 55 一致；**其 new-run2 的 C4 曾把「窄于预期」误表述为通过（条文实际要求确知更窄按 blocked）——该保真偏差如实留痕（见下方计分保真标注政策），维定义未涉、不构成失分**；同上按 convergence-by-deletion 处置 |
| batch55 | raw 删除 | 曾为计分批（十一维全过）；c83 challenge P1 修复（权威身份以承接面/组织既有权威名册或治理记录独立锚定，投放者不得自行指认，名册核不到按无法核验处理并经既有升级通道问明）改动 reference 文本使臂过期，对称重跑为批 56；其通过线结果与批 56 一致（其 E/F 段 owner 失配并入边界权威的引出偏差已按保真政策留痕）；同上按 convergence-by-deletion 处置 |
| batch56 | raw 删除 | 曾为计分批（十一维全过、无保真偏差）；c85 challenge P1 修复（授权不投放的授权主体是否有权作此排除，同按 ①b 权威身份锚定规则核验——名册核到排除决定权才算，配合出具记录的无权主体不构成授权方）改动 reference 文本使臂过期，对称重跑为批 57；其通过线结果与批 57 一致；同上按 convergence-by-deletion 处置 |
| **batch23（计分失败，raw 保留自证）** | raw 保留于 runs/archived-formfail-* | c38-r1 修复后 v6 形态首跑：**D-acl-pre new 臂 1/3 未过通过线**（new-run1/2 全答仅预设预期受众、未产出记录义务本身——义务句在臂文本中原样存在，属六问形态下 A/E 两问间省答，与 v2 先例同形态）；old 臂七维 0/3、C-ctl 双 3/3（对照有效）。处置=仪器 v7 形态修复（A 问加列全指令，维度定义与通过线逐字不变，冻结于批 24 之前）后对称重跑。失败判定（D-acl-pre new 1/3）落在 new 臂——其自证所需的 3 份 new raw 全量保留（archived-formfail-new-*）；同批 old 臂 raw 不承载该失败判定的任何角色（old 各维照常 0/3），按 convergence-by-deletion 移出，使评审包回到完整候选 diff（该移出为 c56-ch 有界包发现的终态解） |
| ctl-invalid 两组 | 各组保留**省答那一跑**于 runs/archived-new-ctlinvalid-*（v1prompt 组=run1、acl 组=run3） | 其「整批无效」判定（C-ctl 2/3 未达 3/3 有效线）由省答跑自证；各组另两跑对照维命中、不承载判定角色，按 convergence-by-deletion 移出（c56-ch 后包体积治理的同则延伸） |
