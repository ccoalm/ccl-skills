# 客户端开发手册（内置 owner 与其它端路由）

> 域专题：四个内置客户端 owner 怎么用、其它渲染端怎么查 owner，以及各端与 UI/UX 设计怎么分工、如何提供渲染证据。
>
> **何时找它**：要写 Web / App / 小程序 / 终端 / 桌面 / TV 等界面、定渲染证据、和 UI/UX 分工、局部重构某组件或页面。

## 四个内置技能与其它端

| 技能 | 范围 |
|---|---|
| [`web-react-dev`](../skills/web-react-dev/SKILL.md) | React Web：组件、路由、状态、API/数据、表单、浏览器行为、可用性、构建/部署、浏览器验收 |
| [`app-cross-platform-dev`](../skills/app-cross-platform-dev/SKILL.md) | Flutter / React Native / 原生 Android / iOS：导航、状态、离线/缓存、平台能力、构建/发布、设备验收 |
| [`miniapp-product-dev`](../skills/miniapp-product-dev/SKILL.md) | 微信/支付宝/抖音/百度小程序（默认 Taro）：页面路由、登录、支付、分享、订阅、平台能力、审核、发布、开发者工具/真机验收 |
| [`terminal-cli-dev`](../skills/terminal-cli-dev/SKILL.md) | 命令行/TUI/PTY/ANSI：布局、输入、颜色、换行、选择、scrollback、可用性、真实终端验收 |

Vue、Svelte、static/vendor Web，Electron、桌面、TV shell 和其它客户端不因上表没有专用技能而消失：先用项目已安装 owner；没有明确映射时，按 [`delivery-contract.md`](../skills/product-ui-ux-design/references/delivery-contract.md) 查 README/CONTRIBUTING、就近 AGENTS/CLAUDE 及 client/style/design 文档。查不到或材料不可访问就记 `owner-lookup-unavailable` 并阻断完成声明，不能把它写成 `not-applicable`。复合宿主的内容层与 shell 层分别建 owner、record 和 binding member。

## 和 UI/UX 设计的分工

- **设计还没定**（页面怎么设计、交互、状态、视觉、看着别扭）→ 先 [`product-ui-ux-design`](../skills/product-ui-ux-design/SKILL.md)，见 [UI/UX 设计手册](uiux-design-handbook.md)。
- **设计已定，问代码机制**（Tailwind 怎么写、Flutter 动画、小程序接 API、终端 ANSI 渲染）→ 对应客户端技能。

> **动第一笔可见 UI 代码前，先消费适用的完整 brief 或低风险纯文案轻量记录，以及测试 Phase 0。** 每个受影响客户端和内容层/宿主层先按 [`delivery-contract.md`](../skills/product-ui-ux-design/references/delivery-contract.md) 写 `client_entry`：本地规则 quote/ID 与实现决定、目标 runtime、计划实跑/采集命令、必须保持的行为。实跑后回传完整 canonical client member，包括受影响文件/组件、保持行为、不可变候选 binding、运行目标、artifact、criterion 观察、覆盖边界、缺口和实际使用的 backend/config/prompt/model producer member/version。测试 Phase 1 聚合集合判充分性，再由设计 owner 给 verdict。WebView、mini-program `web-view`、Electron 等复合宿主不能用单一端记录闭环；窄到直接找客户端技能、没进 product-rd-workflow 也照做。

## 渲染证据要求（硬线）

可见 UI 改动在声明 `complete` 或设计 `accepted` 前必须有对应目标的**渲染证据**。若分支/commit/草稿 MR 先交接而运行环境尚不可用，记录实际尝试、观察到的失败、残余风险、不可变候选绑定、缺失层、owner、命令和下一步，状态只能是 `pre-runtime-test-ready` 或 `blocked`，不能写成 MR-ready、merge-ready 或完成：

| 端 | 证据 |
|---|---|
| Web | 绑定候选、路由与尺寸的浏览器截图/trace/检查结果 |
| App | 绑定候选、构建目标与设备/模拟器的运行证据 |
| 小程序 | 绑定候选与目标 host 的开发者工具 / 预览构建 / 真机证据 |
| 终端 | 按风险分两档（见下）|
| 其它 Web、桌面、TV 或其它客户端 | 由实际 owner 记录绑定候选、目标 runtime、关键状态与该平台可复查的渲染/交互证据；无 owner 映射时先阻断并完成 fail-closed lookup |

终端证据按风险分两档：

- **纯输出**（只往 stdout 打文本）：PTY transcript 或 cell-buffer 快照即可。
- **交互 / 控制态**（raw mode、alt screen、光标、焦点、鼠标、粘贴、选择、scrollback、resize、颜色）：字符串快照证明不了，要 **PTY 生命周期断言 + 清理断言 + 真实终端 smoke**。

自动化测试只证明它实际执行的 oracle；build、DOM 存在或组件快照不能替代视觉/层级/密度判断。可见变化要有目标运行面的渲染证据，并由设计 owner 对绑定候选给 verdict。

## 关键纪律

- **非渲染改动**（请求 plumbing、header、telemetry、storage adapter、service client，且不改变 rendered experience 或 user decision flow：布局、文案、状态、交互、导航、组件语义、无障碍/焦点/键盘或用户反馈/错误均不变）→ 显式记 `visible surface: no` + 原因；任一维变化就走可见 UI 交付契约。
- **运行时依赖的改动**（平台 API、生命周期、流式传输、权限、导航语义、存储/会话恢复、渲染状态）→ host smoke 是 blocking。
- **局部重构**（重构这个组件/页面/widget/终端命令）走对应客户端技能；多阶段交付走 `product-rd-workflow`。
- 嵌入式终端（浏览器/原生/小程序内）：host 栈技能管嵌入/权限/生命周期/打包/发布，`terminal-cli-dev` 管终端渲染/输入/PTY/ANSI/scrollback/选择/清理。

## 延伸阅读

- 四个技能 SKILL.md（见上）+ [UI/UX 设计手册](uiux-design-handbook.md)
- [写测试与测试用例手册](testing-handbook.md) · [做需求/加功能/重构手册](feature-delivery-handbook.md)
