import AppKit

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem!
    private var inputPanel: InputPanel?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private let settings = AppSettings.shared
    private var appearanceObservation: NSKeyValueObservation?

    /// 上一次真正写入按钮的标题，用于避免重复赋值（见 refreshTitle）。
    private var lastRenderedTitle: NSAttributedString?
    private var lastRenderedLength: CGFloat = 0

    /// 状态项的最小长度：即使文字、前缀、后缀全部为空，也保留一个可点击的入口，
    /// 避免用户把内容清空后菜单栏项消失、再也打不开设置。
    private static let minimumStatusItemWidth: CGFloat = 22

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 记住用户 Cmd+拖动后的位置，重启后保持在菜单栏同一位置
        statusItem.autosaveName = "SwiftQuoteStatusItem"
        guard let button = statusItem.button else { return }
        button.action = #selector(onClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // macOS 15 在多显示器 / 通用控制下会把「非活动显示器」的菜单栏整体压暗。
        // 只有带 image 的状态项才会走系统的 inactive-display 渲染；纯 attributedTitle
        // 的项不会随之变暗，浅色文字在灰色菜单栏上就会像「消失」了一样。
        // 这里挂一个空图片（不占布局），只为让状态项进入 image-backed 渲染路径。
        // 参考：exelban/stats#2131（macOS 15.0 上的同一问题）。
        button.image = NSImage()
        button.imagePosition = .imageLeading

        // 监听菜单栏深浅变化（壁纸/系统外观改变时系统会自动调整菜单栏外观）
        let initialDark = Self.isDarkAppearance(button.effectiveAppearance)
        if settings.menuBarIsDark != initialDark {
            settings.menuBarIsDark = initialDark
        }
        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            // KVO 回调在主线程触发；Swift 6 下需显式声明主actor隔离
            MainActor.assumeIsolated {
                guard let self else { return }
                let dark = Self.isDarkAppearance(button.effectiveAppearance)
                if dark != self.settings.menuBarIsDark {
                    self.settings.menuBarIsDark = dark
                    if self.settings.adaptiveColors { self.refreshTitle() }
                }
            }
        }

        // 设置变化时刷新菜单栏（直接回调，比 Combine/UserDefaults 通知可靠）
        settings.onDisplayChange = { [weak self] in self?.refreshTitle() }
        settings.onAppearanceChange = { [weak self] in self?.applyAppearanceToWindows() }

        refreshTitle()
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        // 菜单栏实际外观是 VibrantLight/VibrantDark，不是 Aqua/DarkAqua
        appearance.name == .vibrantDark || appearance.bestMatch(from: [.vibrantDark, .aqua]) == .vibrantDark
    }

    @objc private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        // 刷新前同步菜单栏当前深浅状态（开关切换时确保用对颜色）。
        // 先判等再写，避免 @Published 在每次标题刷新时都触发设置页重绘。
        let isDark = Self.isDarkAppearance(button.effectiveAppearance)
        if settings.menuBarIsDark != isDark {
            settings.menuBarIsDark = isDark
        }
        let str = NSMutableAttributedString()
        let colors = settings.effectiveNSColors
        let full = settings.displayText
        let font = settings.font
        for (i, ch) in full.enumerated() {
            let color = colors.isEmpty ? .white : colors[i % colors.count]
            str.append(NSAttributedString(
                string: String(ch),
                attributes: [.font: font, .foregroundColor: color]))
        }
        // 紧凑布局：长度 = 文字实际宽度（cell 内部零补白；剩余间距是系统项间距）。
        // 同时保证一个最小宽度：内容全部清空时仍保留可点击区域，不会把入口弄丢。
        let textWidth = ceil(str.size().width)
        let maxWidth = max(CGFloat(settings.maxWidth), Self.minimumStatusItemWidth)
        let width = max(min(textWidth, maxWidth), Self.minimumStatusItemWidth)

        // 内容为空时用提示文案兜底，方便用户悬停/读屏时知道这里可以点。
        let accessibleText = full.isEmpty ? "SwiftQuote" : full
        button.toolTip = full.isEmpty ? settings.strings.statusItemToolTip : full
        button.setAccessibilityLabel(accessibleText)

        // 避免重复写入相同的 attributedTitle：macOS 上反复赋值（尤其是相同值）
        // 会让状态项整个消失。内容/宽度没变就直接跳过。
        if let lastRenderedTitle,
           lastRenderedTitle.isEqual(to: str),
           lastRenderedLength == width {
            return
        }
        lastRenderedTitle = str
        lastRenderedLength = width
        button.attributedTitle = str
        statusItem.length = width
    }

    @objc private func onClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        // 右键，或 Ctrl+单击（macOS 上等价于右键）→ 编辑面板；其余 → 菜单
        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.type == .leftMouseUp
            && event.modifierFlags.contains(.control)
        if isRightClick || isControlClick {
            showInputPanel()
        } else {
            showMenu()
        }
    }

    // MARK: - 左键菜单
    private func showMenu() {
        let menu = NSMenu()

        let s = settings.strings
        let input = NSMenuItem(title: s.menuInput, action: #selector(onInput), keyEquivalent: "")
        input.target = self
        menu.addItem(input)

        let settingsItem = NSMenuItem(title: s.menuSettings, action: #selector(onSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let historyToggle = NSMenuItem(title: s.trackHistory, action: #selector(onToggleHistory), keyEquivalent: "")
        historyToggle.target = self
        historyToggle.state = settings.trackHistory ? .on : .off
        menu.addItem(historyToggle)

        let loginToggle = NSMenuItem(title: s.launchAtLogin, action: #selector(onToggleLogin), keyEquivalent: "")
        loginToggle.target = self
        loginToggle.state = settings.launchAtLogin ? .on : .off
        loginToggle.isEnabled = settings.loginItemAvailable   // SPM 裸跑时禁用
        menu.addItem(loginToggle)

        // 历史里永远排除当前值（实时编辑后当前值也可能短暂留在底层 history 中）
        let displayHistory = settings.displayHistory
        if settings.trackHistory && !displayHistory.isEmpty {
            menu.addItem(.separator())
            historyHeaderMenu(menu, items: Array(displayHistory.prefix(5)))
        }

        if settings.rotationEnabled && settings.activeRotationItems.count > 1 {
            menu.addItem(.separator())
            rotationMenu(menu)
        }

        menu.addItem(.separator())
        // 关于（打包 App 时附上版本号）
        let aboutTitle: String
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            aboutTitle = "\(s.menuAbout) \(v)"
        } else {
            aboutTitle = s.menuAbout
        }
        let about = NSMenuItem(title: aboutTitle, action: #selector(onAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let restart = NSMenuItem(title: s.menuRestart, action: #selector(onRestart), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        let quit = NSMenuItem(title: s.menuQuit, action: #selector(onQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)   // 由系统弹出，定位最精确
        statusItem.menu = nil
    }

    private func historyHeaderMenu(_ menu: NSMenu, items: [String]) {
        let header = NSMenuItem(title: settings.strings.historyHeader, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for item in items {
            let mi = NSMenuItem(title: item, action: #selector(onHistoryItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = item
            menu.addItem(mi)
        }
        let clear = NSMenuItem(title: settings.strings.clearHistory, action: #selector(onClearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    private func rotationMenu(_ menu: NSMenu) {
        let s = settings.strings
        let next = NSMenuItem(title: s.menuNextItem,
                              action: #selector(onNextRotationItem),
                              keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let pause = NSMenuItem(title: settings.rotationPaused ? s.menuResumeRotation : s.menuPauseRotation,
                               action: #selector(onToggleRotationPause),
                               keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
    }

    @objc private func onNextRotationItem() {
        RotationController.shared.nextManually()
    }

    @objc private func onToggleRotationPause() {
        RotationController.shared.togglePause()
    }

    @objc private func onHistoryItem(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.text = value
    }

    @objc private func onClearHistory() {
        settings.history = []
    }

    @objc private func onToggleHistory() {
        settings.trackHistory.toggle()
    }

    @objc private func onToggleLogin() {
        settings.launchAtLogin.toggle()
    }

    @objc private func onInput() {
        showInputPanel()
    }

    @objc private func onAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }
        aboutWindowController?.window?.appearance = settings.appAppearance
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        aboutWindowController?.window?.orderFrontRegardless()
    }

    @objc private func onSettings() {
        showSettings()
    }

    @objc private func onQuit() {
        NSApp.terminate(nil)
    }

    /// 重启应用：先拉起新进程，再退出当前实例（缓解长期运行/开窗后的内存残留）
    @objc private func onRestart() {
        let url = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let proc = Process()
        proc.executableURL = url
        proc.standardOutput = nil
        proc.standardError = nil
        try? proc.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 输入面板
    private func showInputPanel() {
        if inputPanel == nil {
            let panel = InputPanel()
            // 关闭后释放面板（连同 NSTextField），回收视图树、保持轻量。
            panel.onDismiss = { [weak self] in self?.inputPanel = nil }
            inputPanel = panel
        }
        inputPanel?.appearance = settings.appAppearance
        inputPanel?.show(near: statusItem.button)
    }

    // MARK: - 设置窗口
    func settingsWindowDidClose(_ controller: SettingsWindowController) {
        // 只有当前仍由该控制器持有时才释放，避免旧窗口的延迟回调清掉新窗口
        if settingsWindowController === controller {
            settingsWindowController = nil   // 释放窗口与视图树
        }
    }

    func aboutWindowDidClose(_ controller: AboutWindowController) {
        if aboutWindowController === controller {
            aboutWindowController = nil
        }
    }

    /// 把主题外观应用到本 App 自己的窗口。
    /// 不设置 `NSApp.appearance`：macOS 会把前台 App 的外观套到整条菜单栏上，
    /// 选「浅色」时会让整个菜单栏变灰，状态项文字也可能因此看不清。
    private func applyAppearanceToWindows() {
        let appearance = settings.appAppearance
        settingsWindowController?.window?.appearance = appearance
        aboutWindowController?.window?.appearance = appearance
        inputPanel?.appearance = appearance
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.window?.appearance = settings.appAppearance
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
        // orderFrontRegardless 保证窗口提到最前（普通 accessory 应用 showWindow 可能落在其他窗口下）
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.window?.orderFrontRegardless()
    }
}
