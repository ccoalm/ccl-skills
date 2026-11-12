# `product-rd-workflow` 入口瘦身的零丢失核对

对照基线是 `origin/main` 上的 `skills/product-rd-workflow/SKILL.md`（233 行，75,615 字节）。瘦身后入口 26,887 字节，移出的文字在三个新参考文件里：`references/stage-classify-and-route.md`、`references/stage-plan-and-design.md`、`references/stage-quality-and-landing.md`。

核对方法：基线入口的每个非空行，把连续空白归一成一个空格后，在新入口和三个参考文件里做整行子串查找。202 行里 189 行找到，其中 188 行是整行相等，1 行是被并进一个更长的行；13 行没找到，逐行列在第二张表。

这个方法证明的是文字都还在，不证明每条规则的上下文没变。上下文另查了两项：

- **缩进。** 原入口里挂在编号步骤下的条目（缩进 3 格，子条目 5 格）搬到参考文件后改挂在同名小节标题下（0 格，子条目 2 格）。每一行都少 3 格，父子关系没有变。
- **顺序。** 搬进同一个参考文件的行保持原来的先后，只有一处例外：`stage-classify-and-route.md` 里「External Skill Augmentation」一节排在「Existing Project Assessment」和「Feature Deprecation」之后，原入口里它在前。三节各有自己的标题，互不引用先后。

## 逐字保留的行

| 原入口行号 | 逐字保留在 |
| --- | --- |
| 2–6 | 入口 |
| 8 | `stage-classify-and-route.md` |
| 10–12 | 入口 |
| 14–24 | `stage-classify-and-route.md` |
| 26 | 入口、`stage-classify-and-route.md` |
| 28–31 | `stage-classify-and-route.md` |
| 34–57 | `stage-classify-and-route.md` |
| 59 | 入口、`stage-classify-and-route.md` |
| 61–63 | 入口 |
| 64 | 入口、`stage-classify-and-route.md` |
| 65–66、68–77、80–89、91–100 | `stage-classify-and-route.md` |
| 79 | 入口 |
| 103–108、110–112、114–131、133–135 | `stage-plan-and-design.md` |
| 137 | 入口 |
| 138、140–144、147–161、163–177、180、182–186、201 | `stage-quality-and-landing.md` |
| 179 | 入口 |
| 188–199 | 入口（Pre-Final Continuation Gate 全文没有动） |
| 203、207、217 | 入口 |
| 205、209–215、219 | `stage-classify-and-route.md` |
| 221 | 入口、`stage-classify-and-route.md` |
| 223–233 | `stage-classify-and-route.md` |

入口里对应这些行的是压缩后的摘要。被脚本、登记行锚点、契约锚点或同步指针钉住的短语都原样留在入口。

## 不是逐字的 13 行

| 原行号 | 差别 | 处置 |
| --- | --- | --- |
| 32 | 「Architecture routing: decide when architecture work is needed before implementation.」 | 第一版有意改成「a backend design must load `software-architecture` before drafting」，见方案 11.2 |
| 33 | Development routing 行里去掉了「`software-architecture` for architecture」 | 同上，这次提及并进了上一行 |
| 67 | 「through the owning skills below」「owned by the Existing Project Assessment section」 | 文字移到参考文件后，把指向改成参考文件内的节名，其余逐字 |
| 90 | 「see the Feature Deprecation section below」 | 改成指向入口的 Feature Deprecation 一节，其余逐字 |
| 102 | 「3. Produce only useful artifacts.」 | 入口里这一步改名为「Plan and design」，参考文件的节标题是原名 |
| 109 | 「separate from the section-4 visible UI delivery record」 | 改成指向 `stage-quality-and-landing.md`，其余逐字 |
| 113 | 「per the High-risk resilience gating scope above」 | 改成指向 `stage-classify-and-route.md` §Scope，其余逐字 |
| 132 | 「the blocking-gate labels below」 | 改成指向 `stage-quality-and-landing.md`，其余逐字 |
| 139 | 「the Workflow step 3 standards checklist result」 | 加了所在文件名，其余逐字 |
| 145 | 「the Scope text-artifact-quality rule」 | 加了所在文件和节名，其余逐字 |
| 146 | 「per the entry-gate name→invoke rule above」 | 改成指向入口，其余逐字 |
| 162 | 「the step-3 test-layer decision table」 | 加了所在文件名，其余逐字 |
| 181 | 「run the Pre-Final Continuation Gate below」 | 改成指向入口，其余逐字 |

第 32、33 行是行为改动，有对照证据。其余 11 行只改了指向，因为原文里的「上文」「下文」在搬家后不再成立。

## 入口新增的文字

入口新增四处，都只规定何时加载哪个参考文件，没有改任何阶段规则的内容：

- 开头的一段说明和触发点表。
- 第 3 步的一条「You must load `references/stage-plan-and-design.md` …」。
- 第 4 步的一条「You must load `references/stage-quality-and-landing.md` …」。
- Scope 一节开头的一句，说明全文在 `stage-classify-and-route.md`。
