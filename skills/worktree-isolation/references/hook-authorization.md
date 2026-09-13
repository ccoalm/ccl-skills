# Hook 合并授权

以下执行额度规则受 [合并执行协议](../SKILL.md) 的目标授权、验证和安全边界约束。`hooks/merge-authorization-prompt.sh` 从用户指令生成额度，`hooks/guard-merge-authorization.sh` 在平台合并命令放行时消费额度。

## 指令与有效期

支持原有单独“合并/merge”和“批量合并 N”，另支持完整单行“完成并合并 PR #123 / MR !123”（英文 `finish and merge PR #123`）。原有单次/计数额度仍被任何新消息清除。

新形式只绑定当前 `origin` 仓库和指定编号，原始 60 分钟内消费一次；单独“继续/继续吧/进度/状态/continue/status/progress”保留原额度和到期时间，“停止/停一下/不要合并/撤销合并授权/stop/pause/cancel merge”撤销，其他消息暂停机械额度，之后“继续”不能恢复。

## 执行命令

新形式的执行命令必须是单条直接 `gh pr merge` 或 `glab mr merge`，显式编号；gh 使用 `--repo host/owner/repo` 并指定策略，glab 使用 `--repo https://host/namespace/repo` 并指定 `--auto-merge=false --yes`，可附完整 head SHA，其他参数和 API 形式保持未核验。
