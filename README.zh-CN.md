> Vibe Coding而成（DeepSeek V4.1 Flash / OpenCode）

<p align="center">
  <img src="docs/logo.png" width="112" alt="SwiftQuote logo">
</p>

<h1 align="center">SwiftQuote</h1>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-blue" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6.0%2B-orange" alt="Swift 6.0+">
  <img src="https://img.shields.io/badge/UI-AppKit-8A2BE2" alt="AppKit">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
</p>

<p align="center"><a href="README.md">English</a></p>

<p align="center">一款轻量 macOS 菜单栏应用，在菜单栏显示自定义文字——格言、提醒、或任何你想展示的内容。</p>

## 截图

<p align="center">
  <img src="docs/preview-main.png" width="220" alt="菜单栏自定义文字">
</p>

<p align="center">
  <img src="docs/preview-left.png" width="210" alt="左键菜单">
  &nbsp;&nbsp;
  <img src="docs/preview-right.png" width="400" alt="右键编辑面板">
</p>

<p align="center">
  <img src="docs/preview-setting.png" width="420" alt="设置窗口">
</p>

## 功能

- **菜单栏多块** — 可添加任意数量的独立菜单栏块，每块拥有自己的文字、样式、颜色、轮播和历史
- **菜单栏自定义文字** — 左键打开菜单，右键编辑所点击的块
- **每块独立样式** — 前后缀、字号、9 档字重、字距、逐字符颜色（多颜色循环）、最大宽度限制
- **自定义字体** — 可选择任意已安装字体族、9 档字重和字距，或使用系统默认
- **动态日期时间** — 每个块可独立开启，按 Unicode TR35 格式实时更新（例如 `MM-dd[EEE]HH:mm`），附常用格式与截图同款预设
- **左键打开日历** — 每个块可独立开启：左键点击该块打开系统日历，右键则打开应用菜单
- **自适应颜色** — 浅色/深色菜单栏各一套配色，随菜单栏外观变化自动切换（附恢复默认按钮）
- **文字预设** — 一键套用模板（Aloha!、请勿打扰、Coffee 等）
- **文字轮播** — 把多条文字组成一组，按 30 秒 / 1 分钟 / 5 分钟 / 1 小时顺序或随机切换；可在菜单中暂停、继续或切到下一条
- **历史记录** — 可配置保留条数（1–100）、收藏置顶、搜索，应用时一并恢复前缀/后缀；当前文字不混在列表里，每条均可单独删除
- **外观** — 跟随系统 / 浅色 / 深色
- **备份与恢复** — 把所有块和全局设置（含可用的开机自启状态）导出为带数据版本号的 JSON；导入兼容新旧格式，无法识别的块会被单独丢弃，解析失败不会改动当前设置；支持一键恢复默认
- **多语言** — 跟随系统 / 中文 / English 界面
- **开机自启** — 基于 SMAppService（需以打包 App 形式运行）
- **轻量** — 常驻内存约 13 MB；窗口关闭即释放视图树，内置「重启」菜单项可回收长期运行残留内存

## 环境要求

- macOS 15+
- Swift 6.0+ / Xcode 16+（自行构建时）

## 构建与运行

使用 SwiftPM：

```sh
swift build
.build/debug/SwiftQuote
```

或在 Xcode 中打开 `SwiftQuote.xcodeproj` 运行（工程由 `project.yml` 通过 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成：`xcodegen generate`）。

## 使用说明

- **右键** 点击某个菜单栏块即可原地编辑（`⏎` 确认，`Esc` 取消）；输入框下方显示该块的最近历史，点击某条即可应用，点 × 可单独删除
- **⌘ 拖动** 菜单栏块可调整位置，位置会随块保存
- **动态日期时间** 在 **文字** 页按块配置，格式遵循 [Unicode TR35](https://unicode.org/reports/tr35/tr35-dates.html#Date_Format_Patterns)，按系统语言和时区显示。例如格式 `MM-dd[EEE]HH:mm` 配合后缀 ` ` 即为截图中的时钟样式；常用格式可一键套用
- **左键打开日历** 可按块开启（菜单中也可切换）。开启后左键点击该块打开系统日历，右键打开应用菜单；关闭后恢复左键菜单、右键编辑
- **备份与恢复** 位于 **通用** 页。导出的 JSON 带数据版本号和全部块；导入会替换当前设置。缺失字段使用默认值，未知字段自动忽略，无法识别的块按块丢弃。导入时会在可用的情况下恢复开机自启；恢复默认不会修改系统「开机自启」状态
- **左键** 打开菜单：输入…、设置…、跟踪历史开关、开机自启开关、最近历史（最多 5 条）、启用轮播后的「下一条 / 暂停或继续」、关于（含版本号）、重启、退出
- 设置分为六个标签页：**通用**（主题、语言、启动、备份与恢复）、**菜单栏块**（添加/删除/选择块）、**文字**（当前块的内容、前后缀、字体、字重、字号、字距、动态日期时间、预设）、**颜色**（逐字符颜色、自适应菜单栏配色）、**轮播**（文字组、间隔、顺序、暂停/下一条；日期时间模式下不可用）、**历史**（保留条数、搜索、收藏置顶、应用时恢复前后缀；当前文字单独展示）

## 开源许可

本项目基于 [MIT 许可证](LICENSE) 开源。
