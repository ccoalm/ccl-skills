# 内联 SVG 自包含判据的可复算证据

## 三条命令与期望

| 命令 | 期望退出码 | 期望关键行 |
| --- | --- | --- |
| `bash skills/tighten-doc/scripts/test_figure_and_doc_lint.sh` | 0 | `OK: figure-lint / doc-lint 逐谓词差分与契约五态全部符合预期` |
| `bash skills/tighten-doc/scripts/mutation_probe.sh` | 0 | `differential_sensitivity=38/38`、`mutation_probe_ok`，无 `DERIVATION-GAP` |
| `CCL_SKILL_BASE_REF=origin/main make test` | 0 | `alias_audit_ok`、`r0_status=private-ok` |
| `bash skills/skill-extraction-workflow/scripts/test_check_ccl_regressions.sh --heavy-only` | 0 | 无 `suite(s) failed` |

前两条完全由包内文件决定、可自行复算；第三条依赖维护者私有 alias，
**如实标为不可从包内独立复核**。

## 五条 fixture（差分表要求报告文件集与期望集全对应）

| fixture | 期望 | 测的是 |
| --- | --- | --- |
| `unsafe-script.svg` | `SVG-NOT-SELF-CONTAINED` | `<script>` 进入宿主 DOM，是注入面 |
| `unsafe-external-ref.svg` | `SVG-NOT-SELF-CONTAINED` | `image` 的外部 `href` |
| `unsafe-noxmlns.svg` | `SVG-NOT-SELF-CONTAINED` | **无默认 `xmlns` 的裸标签**（review lane 指出） |
| `unsafe-css-url.svg` | `SVG-NOT-SELF-CONTAINED` | `<style>` 里 `@font-face` 的外链（challenge lane 指出） |
| `unsafe-css-import.svg` | `SVG-NOT-SELF-CONTAINED` | `@import "https://…"`——**不走 url() 语法**的绕过口 |
| `unsafe-event-handler.svg` | `SVG-NOT-SELF-CONTAINED` | `onload=` 事件处理器，与 `<script>` 同一注入面 |
| `foreign-ns-title.svg` | `C4-TITLE` | `<dc:title>`（RDF 元数据）不得冒充图标题 |
| `self-contained-ok.svg` | **0 ERROR** | 边界组：内联 `<style>` + `<a>` + `use` fragment + `data:` 全在一张图里 |

最后一条是 challenge lane 要求的**反方向断言**：没有它，未来收紧 `href` 分类会在
全部测试仍绿的情况下打坏这些合法输入。

## dual-track 两条 lane 各指出一条真实漏报面

1. **review**：只匹配带命名空间的 QName，则无 `xmlns` 的内联 SVG（在 HTML 里完全合法，
   HTML 解析器会补命名空间、ElementTree 不会）持续假绿。
   **顺着查发现这是全文件的假设**——`C4-TITLE` 与 `GROUPING` 反方向误报「缺标题」「零分组」。
   已把全部 9 处标签比较改走 `lname()` / `iter_local()`。
2. **challenge**：外部资源不只从 `href` 进来——`fill="url(https://…)"`、`filter=`、
   `<style>` 里的 `@font-face src` 同样在渲染时拉取。已改为扫描所有属性值与 `<style>` 文本里的
   `url(...)`，只放行 `url(#id)` 与 `data:`。

## 语料实测（0 命中的诚实读法）

跨作者真实语料 55 张 SVG：`SVG-NOT-SELF-CONTAINED` 命中 **0**。
读法是「**没测到误报，也没测到真阳性**——这批语料不触发这个类」，不是「谓词有效」。

local-name 修正在本语料上是**零回归**：`C4-TITLE` 55→55、`GROUPING` 20→20
（那 55 张都带 `xmlns`，所以修正对它们不改变判定）。

## 刻意不做的两件事

- **不禁 `<style>`**：邻近的 `artifact-diagramming` 禁它，但那是它那条 lane 的前提
  （页面已有 CSS 层）。本仓的图正当地用内联 `<style>` 定义字号与语义色。
- **不禁 `<a>`**：超链接不在渲染时拉取任何东西，与自包含无关。

外部包借理论不借实现——**照抄邻居的约束会把它的前提一起引进来**。

## 第二轮 dual-track：四条发现，其中两条是我上一轮修正的**过度修正**

1. **`lname()` 无条件丢命名空间**（两条 lane 从相反方向指出）。为支持无 `xmlns` 而丢掉全部
   命名空间，代价是 Inkscape/Illustrator 导出里极常见的 `<dc:title>`（RDF 元数据）会冒充图标题
   让缺标题的图假绿，而 `<ext:script>` 会被误判成脚本错误阻断。
   **支持无 xmlns 不要求接受任意外来命名空间**——现在只接受 SVG 命名空间或无命名空间。
2. **整图标题被放宽成任意层级**：原代码用 `root.find` 只认直接子元素，我改成 `iter` 后，
   嵌套在 `<g>` 里、本是某个子元素提示的 `<title>` 也能满足 C4。已改回只认直接子元素。
3. **`@import` 绕过**：合法 CSS 且不走 `url()` 语法，只认 `url()` 就漏。已单列正则。
4. **事件处理器与 `javascript:` URL**：谓词声称管注入面，却只查 `<script>`——
   **又一次声明与实现相反**。已覆盖任意 `on*` 属性与 `javascript:` URL。

附带修了 `parse_css` 不认 at-rule：`@import`/`@media` 会污染紧随其后的真规则，
让文字取不到样式、退回默认值，冒出一串与本缺陷无关的契约报错。

## 语料零回归（改动前后对照）

| 谓词 | 改前 | 改后 |
| --- | --- | --- |
| `SVG-NOT-SELF-CONTAINED` | 0 | 0 |
| `C4-TITLE` | 55 | 55 |
| `GROUPING` | 20 | 20 |
| `CONTRACT-FONT-SCALE` | 0 | 0 |
