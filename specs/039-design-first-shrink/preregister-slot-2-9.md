# 槽位 2/9 双臂预注册清单（先于任何一次运行落盘）

| 项 | 值（冻结） |
| --- | --- |
| 被测规则 | `skill-extraction-workflow` description 中的同形词消歧子句「核查全局安装点（~/.config/opencode 等）旧快照是否遮蔽本仓技能」 |
| 观察点 | `eval-routing-bank.rb`，任务 #78（expect `skill-extraction-workflow`） |
| 每臂运行次数 | **5** |
| 判定函数（唯一，写死） | 该臂 5 次运行中，任务 #78 被路由到 `skill-extraction-workflow` 的次数（`pass_count ∈ 0..5`） |
| 效应判据 | `pass_count(控制) - pass_count(目标突变) >= 3` 方可认定该子句承重 |
| 安慰剂臂 | 在**同一注入点**（同一 description 字段）删除一段等长、与同形词消歧无关的文字 |
| 假阳上限 | 安慰剂臂与控制臂的差 `>= 3` 即判本探针失效（oracle 对无关改动敏感），该槽位判 `证据不足` |
| 模型 | 由 `eval-routing-bank.rb` 默认（本机为 claude-haiku-4-5） |
