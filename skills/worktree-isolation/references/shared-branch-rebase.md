# 已共享分支的安全 rebase

动作、停止条件和推送命令以 `worktree-isolation/SKILL.md`「把落后分支更新到最新目标」的共享分支条目为准；默认 merge / 平台 update 及方向报告以同文件「收尾」节的「合并方向必须可读」为准。本页只解释这些硬规则为何不可放松。

## 为什么只信本分支的这次 fetch

目标必须先按入口上文刷新。随后只 fetch 本分支一次并立即保存 `FETCH_HEAD`；单分支 fetch 在 refspec 不匹配时可能不更新 remote-tracking ref，因此它不能替代入口保存的字面 OID。之后可 fetch 其它 ref，但必须继续使用已保存的 `remote_oid`；再次 fetch 本分支并换钉值，会把观察后的并发推进错当成新基线。

## 为什么 lease 必须显式绑定

远端在观察后发生变化时，显式 OID lease 会拒绝推送。裸 `--force-with-lease` 使用本地 tracking ref；后台 fetch、IDE 自动 fetch 或同仓其它命令都可能推进它，使租约从“与我审阅的 OID 比较”退化为“与远端现状比较”，从而覆盖别人刚推的提交。

## 为什么重写后证据全部失效

重写会改变 commit hash 和行内评论锚点；旧评审线程、approval、mergeable 与 CI 状态不再证明当前提交。工具若把重写和发布合成一步，无法在两者之间验证，只能在返回后逐层重验，并在全部通过前保持 PR 不合并。
