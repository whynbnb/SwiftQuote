> Vibe-coded with DeepSeek V4.1 Flash / OpenCode

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

<p align="center"><a href="README.zh-CN.md">中文</a></p>

<p align="center">A lightweight macOS menu bar app that displays custom text in the menu bar — slogans, reminders, or anything you like.</p>

## Screenshots

<p align="center">
  <img src="docs/preview-main.png" width="220" alt="Custom text in the menu bar">
</p>

<p align="center">
  <img src="docs/preview-left.png" width="210" alt="Left-click menu">
  &nbsp;&nbsp;
  <img src="docs/preview-right.png" width="400" alt="Right-click edit panel">
</p>

<p align="center">
  <img src="docs/preview-setting.png" width="420" alt="Settings window">
</p>

## Features

- **Multiple menu bar blocks** — add any number of independent blocks; each has its own text, style, colors, rotation, and history
- **Custom text in the menu bar** — left-click for the menu, right-click to edit the clicked block
- **Rich styling per block** — prefix/suffix, font size, bold, per-character colors (multiple colors cycle through characters), max width limit
- **Custom font** — choose any installed font family, or keep the system default
- **Dynamic date & time** — per block, live-updating date/time using Unicode TR35 patterns (e.g. `MM-dd[EEE]HH:mm`), with quick patterns and a screenshot-style preset
- **Open Calendar on click** — optional per block: left-click opens Calendar; right-click then opens the app menu
- **Adaptive colors** — maintain separate palettes for light/dark menu bars; colors switch automatically as the menu bar appearance changes (with a reset-to-default button)
- **Text presets** — one-click templates like "Aloha!", "Do not disturb", "Coffee"
- **Text rotation** — group multiple texts and rotate through them every 30s / 1m / 5m / 1h, sequentially or randomly; pause, resume, or skip to the next item from the menu
- **History** — keeps the last 10 entries, quick-apply from the menu or settings; the current text is kept out of the list and each entry can be deleted individually
- **Appearance** — System / Light / Dark mode
- **Localization** — System / 中文 / English UI
- **Launch at login** — built with SMAppService (requires running as a bundled app)
- **Lightweight** — ~13 MB baseline memory; windows release their view trees on close, and a built-in **Restart** menu item reclaims memory from long sessions

## Requirements

- macOS 15+
- Swift 6.0+ / Xcode 16+ (for building)

## Build & Run

With SwiftPM:

```sh
swift build
.build/debug/SwiftQuote
```

Or open `SwiftQuote.xcodeproj` in Xcode and run (the project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`).

## Usage

- **Right-click** a menu bar block to edit it in place (`⏎` to apply, `Esc` to cancel); that block's recent history is shown below the field — click an entry to apply it, or use the × button to delete it
- **⌘-drag** menu bar blocks to rearrange them; positions are saved per block
- **Dynamic date/time** is configured per block in the **Text** tab. The pattern follows [Unicode TR35](https://unicode.org/reports/tr35/tr35-dates.html#Date_Format_Patterns) and uses the system language/time zone. For example `MM-dd[EEE]HH:mm` with suffix ` ` gives the clock-style item; quick-pattern buttons set common formats
- **Left-click Opens Calendar** can be enabled per block (also available from the menu). When enabled, left-click opens Calendar and right-click opens the app menu; turn it off to restore left-click menu / right-click edit
- **Left-click** for the menu: Input…, Settings…, track history toggle, launch-at-login toggle, recent history (up to 5), rotation controls when enabled (Next / Pause), About (with version), Restart, Quit
- Settings has six tabs: **General** (theme, language & startup), **Blocks** (add/delete/select menu bar blocks), **Text** (content, prefix/suffix, font family, size, bold, dynamic date/time, presets for the current block), **Colors** (per-character colors, adaptive menu bar palettes), **Rotation** (group texts, interval/order, enable, pause/next; disabled in date/time mode), **History** (current text shown separately; delete entries individually)

## License

This project is licensed under the terms of the [MIT License](LICENSE).
