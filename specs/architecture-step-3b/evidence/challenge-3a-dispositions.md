# `challenge-3a.json` 的处置

这次挑战的评审包按 `origin/main` 的最新一端取差异。评审开始前 PR #218 已合入 `main`，分支当时还没变基，所以 #218 新增的内容在包里显示成被本分支删掉。前两条发现由此而来。

| 发现 | 处置 | 依据 |
| --- | --- | --- |
| P1 `product-ui-ux-design/references/delivery-contract.md`：视觉来源字段和对照判据被删 | 不是本分支的改动 | 本分支没有改这个文件；变基到 #218 之后，`git diff origin/main...HEAD` 不含它 |
| P2 `source-register.md`：新增两行替换了三行视觉一致性登记 | 不是本分支的改动 | 变基时两边追加的行都保留，#218 的三行在前，本分支的两行在后 |
| P2 `product-rd-workflow/SKILL.md`：技术设计闸摘要丢了「两个及以上负责团队」的触发限定 | 已修 | 只出设计的会话不读 `stage-plan-and-design.md`，限定在设计时够不着；补回入口（方案 11.12 末尾）。另把三个阶段参考文件里会放宽触发条件的括注逐条对了入口摘要，只有这一处是放宽 |
| P2 `hooks/skill-loading.py`：包里缺少分派、状态和异常处理的上下文，无法判断仅改配置或文档、只用 Bash 写代码等路径 | 记为限度，不改 hook | 读源码确认：检查点只拦 Edit、Write、MultiEdit、NotebookEdit、apply_patch 对源码扩展名文件的改动，只用 Bash 写代码的会话碰不到它。这是检查点原有的范围，不是本分支引入的；方案 11.10 和 11.12 的限度里已写明 |
