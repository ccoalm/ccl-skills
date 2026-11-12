# 入口摘要与阶段参考文件的括注对照

做法：在三个阶段参考文件里找出含 treat、count、including、even、also、any、or 的括注，取其中的实词，到入口里查；一半以上的实词在入口里找不到就列出来人工判断。判断标准：入口摘要有没有因为缺了这条括注而**放宽**规则，也就是让本该触发的情况看起来不触发。缺了只会让入口更严的（收窄了豁免），或者括注只是举例的，不算。

| 参考文件 | 括注 | 判断 |
| --- | --- | --- |
| `stage-plan-and-design.md` | treat two or more accountable teams, deployable clients, or contract/API consumers as triggering | **放宽**：只出设计的会话不读这个文件，入口摘要缺这条就看不出两个团队也算触发。已补回入口 |
| `stage-plan-and-design.md` | one bug fix, implementation-only, or visible-UI-only change | 豁免条件；入口没写豁免，按入口执行只会更严 |
| `stage-plan-and-design.md` | a CI/merge gate, pre-commit hook, schema/signature/checksum validator, evidence or attestation apparatus, migration guard | 举例；入口写的是总称 new mechanical enforcement or verification machinery |
| `stage-plan-and-design.md` | restating, freezing, or quoting | 举例 |
| `stage-plan-and-design.md` | or separate clone | 隔离方式的替代项；入口要求 worktree，更严 |
| `stage-classify-and-route.md` | `local status`, `MR-ready`, `landed`, `release-ready`, or `shared-status-ready` | 状态词表，在多仓交付账本的引用文件里；入口指向该文件 |
| `stage-classify-and-route.md` | → `skill-extraction-workflow` first — only a resulting lifecycle-routing or gate policy change comes back here | 回流条件；入口已把复盘和技能修改直接路由到 `skill-extraction-workflow` |
| `stage-classify-and-route.md` | including a listed entry skill's own self-invocation mandate | 举例；入口写的是可选包的技能不替代本入口 |
| `stage-classify-and-route.md` | immediately after any genuine host-mandated preflight | 入口写的是 only a host-authored preflight runs first，同义 |
| `stage-classify-and-route.md` | Feishu/Bitable writeback, shared/public docs, MR/issue body or review comment, external trackers | 外发面举例，规则本身在引用文件里 |
| `stage-quality-and-landing.md` | output-only changes may use a PTY transcript or cell-buffer snapshot … | 终端证据的细则，在实现和验收阶段加载 |
| `stage-quality-and-landing.md` | code ready for named runtime/device handoff but not merge-ready, release-ready, or complete | 状态措辞细则，在完成声明之前加载 |
| `stage-quality-and-landing.md` | workspace verifier, conformance script, contract-coverage gate … | 举例 |

后两个参考文件在第一处实现改动和任何完成声明之前加载（入口触发点表，以及 `hooks/skill-loading.py` 的首次改源码检查点），所以它们的细则在需要时够得着。`stage-plan-and-design.md` 的技术设计闸会在只出设计的会话里触发，而这类会话不读该文件，所以只有这一处需要在入口补全。

这个扫描按关键词取候选，不保证穷尽：不含这些词的括注、不在括号里的限定都没有覆盖到。
