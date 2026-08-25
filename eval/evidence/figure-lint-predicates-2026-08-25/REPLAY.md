# figure-lint / doc-lint 谓词覆盖证据（可复算）

**这份文件的意义在于能被独立重跑，不在于我说它跑过了。**
冻结评审包只含 diff，所以「本地跑绿了」这句话在包里不可复核；下面三条命令与其
预期输出都在包内的 tracked 文件里，评审方可自行复算。

| 命令 | 期望退出码 | 期望关键行 |
| --- | --- | --- |
| `bash skills/tighten-doc/scripts/test_figure_and_doc_lint.sh` | 0 | `OK: figure-lint / doc-lint 逐谓词差分与契约五态全部符合预期` |
| `bash skills/tighten-doc/scripts/mutation_probe.sh` | 0 | `differential_sensitivity=37/37` 与 `mutation_probe_ok`，且无 `DERIVATION-GAP` 行 |
| `make test-repo-gates` | 0 | `alias_audit_ok`、`r0_status=private-ok` |

前两条**完全由包内文件决定**（脚本、fixture、被测检查器都在 diff 里），
第三条依赖维护者的私有 alias 配置，本地实测通过、包内不可复算——**如实标为
不可从包内独立复核**，而不是当成已验证。

## 本次实测（供对照，非替代复算）

- `test_figure_and_doc_lint.sh` exit=0 — OK: figure-lint / doc-lint 逐谓词差分与契约五态全部符合预期
- `mutation_probe.sh` exit=0 — differential_sensitivity=37/37

派生谓词清单（由 `mutation_probe.sh` 从检查器源码正则派生，非手写）：

```
C4-EDGE-DIRECTION C4-EDGE-LABEL C4-EDGE-VAGUE C4-LEGEND C4-TITLE C4-VIEWBOX 
CARRIER-IMBALANCE CONTRACT-COLOR-TOKEN CONTRACT-FONT-SCALE CONTRACT-INVALID 
CONTRACT-MISSING CONTRACT-RATIO CONTRAST-UNSUPPORTED CVD-DISTANCE FIG-ORPHAN 
FIG-REF-DANGLING FIGURE-A11Y-STRUCTURE FIGURE-IS-A-LIST FLOW-DIRECTION-MIXED GEOMETRY 
GRAPH-CROSSINGS GROUPING ICD203-9-SHOULD-BE-CHART PARSE READ SVG-OVERFLOW TABLE-NO-UNIT 
TABLE-UNFILLED TABLE-WIDE THEME-CONTRAST THEME-PURE-BLACK THEME-UNASSESSED 
VALUE-SHOULD-BE-TOKEN WCAG-131-FAKE-HEADING WCAG-131-TABLE WCAG-143 
```

## 分母曾两次静默变小（都是本探针自己的缺陷）

1. 提取正则只认 `add(...)` 与错误元组，漏掉走 `findings.append({'code': ...})` 的
   `CONTRACT-MISSING` / `CONTRACT-INVALID`；
2. 档位只枚举了 `ERROR|WARN`，于是把一条谓词改成 `INFO` 就让它**退出分母**——
   总数看着没变，覆盖少了一条。现在档位用 `[A-Z]+` 匹配，不枚举。

**教训**：覆盖率的分母如果由被测代码的某个属性决定，改那个属性就能无声地让分数变好看。
