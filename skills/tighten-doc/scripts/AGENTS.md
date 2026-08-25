# skills/tighten-doc/scripts Agent Contract

这里的脚本对交付文档的**图与表**做起草期确定性检查：`figure-lint.py` 查 SVG，
`doc-lint.py` 查 Markdown 的表格与结构。判据与其依据档位定义在
`../references/figure-and-table-craft.md`。

Rules:

- **每条谓词必须标依据档位**，并与 `figure-and-table-craft.md` §1 的分档一致：
  `[外]` 有权威一手源、`[工]` 工程约定（不得声称行业最佳实践）、`[禁]` 查证后确认无来源。
  新增谓词若属 `[工]`，其阈值必须在代码注释里明说是拍的下界，不得写成像有依据的样子。
- **不引入"可读性阈值"类的无据数字**。加粗密度、图表密度、行宽字数、句长这几类已核实无可靠来源
  （见 `figure-and-table-craft.md` §1 的 `[禁]` 档），不得以任何形式重新引入。
- **一致性判为契约符合性，不判魔数**：偏离已声明的 `figure-contract.json` 才报，
  "几档算多"不是判据；契约缺失单独报 `CONTRACT-MISSING`。
- **对比度检查必须解析文本实际压着的底色**，不得假定白底——假定白底会把压在色块上的白字误报。
- 谓词钉在**结构与实体**上，不钉在文件名或标题词表上。
- 两个 linter 的退出码语义一致（含 `--json` 模式）：有 ERROR 返回 1、仅 WARN 返回 2、干净返回 0。
  改其中一个必须同步另一个，否则调用方会把正常结果当执行失败。

Validation（缺一不可）:

- `bash skills/tighten-doc/scripts/test_figure_and_doc_lint.sh` —— 逐谓词差分 + 契约三态正负例。
  **改判据必须同步改 fixture**：本目录踩过"修完误报后 fixture 当场失效却仍通过"。
- **新增或修改谓词后必须做突变实测**：跑 `bash skills/tighten-doc/scripts/mutation_probe.sh`——
  它逐谓词把 code 字面量替换掉使其在结果中消失，确认套件转红；任一谓词仍绿即无覆盖，脚本退出非 0。
  该脚本是可重跑的证据，不是一次性命令：评审方可自行执行核对。两条已踩过的坑——① 突变要作用在 oracle 实际观测的维度上
  （改 severity 而断言比 code 集合 = 无效突变，会全绿假通过）；② 突变判据要看**退出码**，
  只看有无 `FAIL` 行会把脚本崩溃读成绿。
- **新增谓词前先在真实语料上量命中率**：fixture 只证明谓词**能**报，不证明它报得**对**——
  fixture 是作者造的，天然符合作者的假设。判据是否成立要看它在**没有为它准备的**真实文档上的分布。
  本目录实测：四条阈值型谓词在 392 份正常文档上产生 318 条 ERROR、命中 38% 的文件，
  抽样中无一条是其声称的缺陷，已全部删除。**一条真正的缺陷判据不会在正常仓库里命中 38% 的文件。**
  参考命令：`python3 doc-lint.py $(find docs skills -name '*.md' -not -path '*/tests/*') --json`。
- **已删除的谓词勿再加回**：标题过长、单元格塞整段、段落内并列枚举、列表项多句——
  理由与实测代价见 `../references/figure-and-table-craft.md` §9。
- 断言不得写成 OR（三选一命中即过）——那会让其余维度永久失去覆盖。
- **期望表必须全量对应**：报告里出现而期望表未列的文件、或期望表列了而报告里没有的文件，都判红。
  只断言点名的 fixture 会让意外文件（通配到非目标文件、新增 fixture 忘记登记）的发现无人过问。
- **改函数签名必须同步改调用点**：曾把参数加进签名却漏改调用点，第一条期望被当成参数吃掉，
  控制组变脏仍全绿。参数个数不足现在会直接判红。
- 该测试已注册进 `Makefile` 的 `test-repo-gates`；新增 `test_*.sh` 同样要注册，
  本目录**不在** `skill-extraction-workflow` 那道注册闸的覆盖范围内，不注册就静默不跑。
- shell 脚本里凡在字符串中插值一律用 `${var}`：CJK 标点紧跟 `$var` 会被 bash 吞进变量名
  （本目录踩过两次）。
- `bash skills/skill-extraction-workflow/scripts/check-ccl-skills.sh .`
