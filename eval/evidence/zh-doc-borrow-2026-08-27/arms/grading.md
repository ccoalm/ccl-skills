# 逐跑判分记录（每行绑定 runs/ 下的原始输出文件；哈希见 SHA256SUMS）

臂文本 = 本目录 armA/armB 四文件（armA-old/armB-old 取自本轮 base，armA-new/armB-new 与最终候选逐字节一致，diff 校验）。逐字 prompt 由 `build_prompts.sh <臂>` 确定性重建；运行设置：`claude -p --model claude-sonnet-5`，cwd=空白临时目录（隔离项目 CLAUDE.md 与 auto-memory），跑后对全部输出 grep 污染标记与 org 标识，零命中。

## 仪器 A（n=3/臂）

| 输出文件 | 臂 | D1 句②代词 | C1 句③空话 | 句④哨兵 |
|---|---|---|---|---|
| runs/A-old-run1.txt | old | miss（判 BLUF） | hit | 被既有「主动语态」条命中 |
| runs/A-old-run2.txt | old | miss（判 BLUF） | hit | 无命中 |
| runs/A-old-run3.txt | old | miss（判 BLUF+空泛） | hit | 被既有「主动语态」条命中（自注「相对轻微」） |
| runs/A-new-run1.txt | new | hit（引新条文） | hit | 被既有「主动语态」条命中（非新增条文，不计 D1） |
| runs/A-new-run2.txt | new | hit（引新条文） | hit | 无命中 |
| runs/A-new-run3.txt | new | hit（引新条文） | hit | 无命中 |

汇总：D1 old 0/3 → new 3/3；C1 两臂 3/3；句④哨兵：old 2/3、new 1/3 被**既有**主动语态条命中（new 臂输出为「后接名词」措辞定稿后的最终重跑，哨兵命中落在 run1）——两臂皆现、与新增条文无涉，说明该噪声源自既有规则对无主语句的既有行为（初版判分把 old 两跑误记为无命中，经外部评审比对 raw 纠正）。弱动词维（撤回依据）：A-old 三跑均以既有「删冗词的定式」类推命中句①（可在上表 old 输出中核对）→ 该子句撤回未落。

## 仪器 A2（先行词代词分支补测，c13 评审要求；n=3/臂，判据冻结于运行前）

样本句①植入「它」距先行词远且中间插入另一名词（依赖清单…缓存目录…它）；D1b 命中 = 引先行词分支（距离远/插入名词即重复名词）指出指代不明。prompt 由 `build_prompts.sh A2-old|A2-new` 重建。

| 输出文件 | 臂 | D1b 先行词代词 | C1 空话 | 哨兵句③ |
|---|---|---|---|---|
| runs/A2-old-run1.txt | old | miss（明写「不属于清单内规则覆盖范围，不作为违规列出」——天然对照） | hit | 被既有「主动语态」条命中 |
| runs/A2-old-run2.txt | old | miss | hit | 无命中 |
| runs/A2-old-run3.txt | old | miss | hit | 无命中 |
| runs/A2-new-run1.txt | new | hit（引「插入另一名词」重复名词） | hit | 无命中 |
| runs/A2-new-run2.txt | new | hit（引歧义代词消歧） | hit | 被既有「主动语态」条命中 |
| runs/A2-new-run3.txt | new | hit（引「离得远或插入另一名词就直接重复名词」） | hit | 无命中 |

汇总：D1b old 0/3 → new 3/3；C1 两臂 3/3；哨兵句③ old 1/3、new 1/3 被既有主动语态条命中（两臂对称噪声，与新增条文无涉）。与仪器 A 合并后，代词规则的两支（指示词、先行词）均有 applied differential 覆盖。

## 仪器 B2

old 臂文本在全程未变（armB-old=base），故 old 臂两批共 6 跑全部有效；new 臂只有末批与最终候选一致，前批（收缩前臂文本）降级为 supplementary、不计入最终候选主张。

| 输出文件 | 臂 | 有效性 | 终答 | 引用 |
|---|---|---|---|---|
| runs/B2-supplementary-prefinal-new-run1..3.txt | new(收缩前臂) | supplementary | 需要 ×3 | 均逐字引「校验绿只是人读性的代理」 |
| （sample1 old 三跑） | old | verdict-recorded, raw-lost | 清单未规定 ×3 | 无代理条文可引 |
| runs/B2-old-sample2-run1.txt | old | 有效 | 清单未规定 | — |
| runs/B2-old-sample2-run2.txt | old | 有效 | 需要 | 借③条硬引（漂移） |
| runs/B2-old-sample2-run3.txt | old | 有效 | 清单未规定（首词「需要。」但通篇论证后以加粗「**清单未规定**」收束，按终答计） | — |
| runs/B2-final-new-run1..3.txt | new(最终臂) | 有效 | 需要 ×3 | 均逐字引代理条文 |

| runs/B2-sample3-old-run1.txt | old | 有效 | 需要（据①③条推证，无代理条文可引——严格 hit 不成立） | 非代理条文 |
| runs/B2-sample3-old-run2.txt | old | 有效 | 清单未规定 | — |
| runs/B2-sample3-old-run3.txt | old | 有效 | 清单未规定 | — |
| runs/B2-sample3-new-run1..3.txt | new(最终臂) | 有效 | 需要 ×3 | 均引「校验绿只是人读性的代理」 |

**计分规则（predeclared）**：输出以**终答**计——该规则自 sample1 判分起即适用（sample1-old-run3 同型：首词「需要」、终答「清单未规定」，当时即按终答计），sample2-run3 初版误按首词计，经外部评审比对 raw 纠正，本表已按同一规则统一。
**如实记的过程缺陷**：①sample1 的 old 臂三份原始输出被 sample2 重跑覆盖丢失（作者脚本复用同名输出文件所致）；其逐跑判定（清单未规定 ×3）当场记录于作者 scratch 判分日志，raw 不可恢复，故标 `verdict-recorded, raw-lost`、不计入可审计集合；②初版判分含两处真错（A-old 句④两跑、B2-run3 终答），均由外部评审对 raw 复核揪出后修正——判分表的可信度依赖本目录 raw 与任何评审方的复核，不依赖作者单方断言。
**修正后汇总（仅计可归因于最终臂快照且 raw 在包内的跑；两侧指标为预冻结的非对称设计——old 臂计终答「需要」数、new 臂计严格 hit=需要+引代理条文）**：可审计集 = 样本 2+3，共 old 6 跑 / new(最终臂) 6 跑。old：终答「需要」2/6（sample2-run2 借③条、sample3-run1 据①③推证，均无代理条文可引，严格 hit 0/6）；new：严格 hit 6/6。逐样本冻结门槛（old「需要」≤1/3、new hit≥2/3）两样本均满足 → clean pass（沿革：run3 首词误判与混臂 1/6 vs 6/6 口径均经外部评审指出后修正/撤回，第三样本按评审要求补测且 raw 全留）。sample1-old（raw-lost）与 supplementary-prefinal-new 两组不进任何汇总主张，仅存档。包级 RED 底线由仪器 A/A2 与本仪器共同承担。
