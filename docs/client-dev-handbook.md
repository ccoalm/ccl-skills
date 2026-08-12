# 客户端开发手册（Web / App / 小程序 / 终端）

> 域专题：四类客户端各用哪个技能、和 UI/UX 设计怎么分工、渲染证据要求。
>
> **何时找它**：要写 Web / App / 小程序 / 终端 界面、定渲染证据、和 UI/UX 分工、局部重构某组件或页面。

## 四个技能

| 技能 | 范围 |
|---|---|
| [`web-react-dev`](../skills/web-react-dev/SKILL.md) | React Web：组件、路由、状态、API/数据、表单、浏览器行为、可用性、构建/部署、浏览器验收 |
| [`app-cross-platform-dev`](../skills/app-cross-platform-dev/SKILL.md) | Flutter / React Native / 原生 Android / iOS：导航、状态、离线/缓存、平台能力、构建/发布、设备验收 |
| [`miniapp-product-dev`](../skills/miniapp-product-dev/SKILL.md) | 微信/支付宝/抖音/百度小程序（默认 Taro）：页面路由、登录、支付、分享、订阅、平台能力、审核、发布、开发者工具/真机验收 |
| [`terminal-cli-dev`](../skills/terminal-cli-dev/SKILL.md) | 命令行/TUI/PTY/ANSI：布局、输入、颜色、换行、选择、scrollback、可用性、真实终端验收 |

## 和 UI/UX 设计的分工

- **设计还没定**（页面怎么设计、交互、状态、视觉、看着别扭）→ 先 [`product-ui-ux-design`](../skills/product-ui-ux-design/SKILL.md)，见 [UI/UX 设计手册](uiux-design-handbook.md)。
- **设计已定，问代码机制**（Tailwind 怎么写、Flutter 动画、小程序接 API、终端 ANSI 渲染）→ 对应客户端技能。

> **动第一笔可见 UI 代码前，先记实现 owner checkpoint。** 窄到直接找客户端技能、没进 product-rd-workflow 也照做。字段、轻量路径和漏记后的补救见 [UI/UX 设计手册](uiux-design-handbook.md) 的「实现 owner checkpoint」节。

## 渲染证据要求（硬线）

可见 UI 改动 commit/MR 前必须有对应目标的**渲染证据**：

| 端 | 证据 |
|---|---|
| Web | 浏览器截图或浏览器检查 |
| App | 设备/模拟器/预览 |
| 小程序 | 开发者工具 / 预览构建 / 真机 |
| 终端 | 按风险分两档（见下）|

终端证据按风险分两档：

- **纯输出**（只往 stdout 打文本）：PTY transcript 或 cell-buffer 快照即可。
- **交互 / 控制态**（raw mode、alt screen、光标、焦点、鼠标、粘贴、选择、scrollback、resize、颜色）：字符串快照证明不了，要 **PTY 生命周期断言 + 清理断言 + 真实终端 smoke**。

自动化测试证明行为，**证明不了视觉/层级/密度**——必须渲染走查。

## 关键纪律

- **非渲染改动**（请求 plumbing、header、telemetry、storage adapter、service client，不改可见布局/文案/状态/导航/错误）→ 显式记 `visible surface: no` + 原因，不必走设计检查点。
- **运行时依赖的改动**（平台 API、生命周期、流式传输、权限、导航语义、存储/会话恢复、渲染状态）→ host smoke 是 blocking。
- **局部重构**（重构这个组件/页面/widget/终端命令）走对应客户端技能；多阶段交付走 `product-rd-workflow`。
- 嵌入式终端（浏览器/原生/小程序内）：host 栈技能管嵌入/权限/生命周期/打包/发布，`terminal-cli-dev` 管终端渲染/输入/PTY/ANSI/scrollback/选择/清理。

## 延伸阅读

- 四个技能 SKILL.md（见上）+ [UI/UX 设计手册](uiux-design-handbook.md)
- [写测试与测试用例手册](testing-handbook.md) · [做需求/加功能/重构手册](feature-delivery-handbook.md)
