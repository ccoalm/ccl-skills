# 最严任务在最终文本上的重测

任务：隐式 Go 预约（`arch-design-booking-implicit-go`）。候选提交的技能文本与本分支最终提交逐字节相同（`product-rd-workflow` 入口 26,994 字节）。基线中位数 100,135 字节（方案 10.4）。字节按方案 11.6 的口径：会话里加载或读取过的插件 Markdown 文件，按整文件大小求和。

| 运行 | 有效 | 加载的文件 | 字节 | 成本，美元 |
| --- | --- | --- | --- | --- |
| 1 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 0.99 |
| 2 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 0.92 |
| 3 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 1.01 |
| 4 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 0.97 |
| 5 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 0.92 |
| 6 | 是 | `product-rd-workflow/SKILL.md`、`software-architecture/SKILL.md`、`tighten-doc/SKILL.md` | 100,008 | 1.00 |

判分（基线校准，没有评分项因校准被排除）：

| 评分项 | 做到 |
| --- | --- |
| `inv_no_overlap` | 6/6 |
| `inv_booking_transitions` | 6/6 |
| `inv_pending_expiry` | 6/6 |
| `inv_room_disabled` | 6/6 |
| `stack_go_deadline` | 6/6 |
| `stack_go_dal_boundary` | 6/6 |
| `dep_direction` | 6/6 |
