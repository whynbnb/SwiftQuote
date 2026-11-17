import AppKit

/// 一个历史菜单项携带：属于哪个块 + 要应用的历史记录。
private struct HistoryMenuPayload {
    let blockID: UUID
    let entry: HistoryEntry
}

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()

    /// 每个块对应一个菜单栏状态项。
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var appearanceObservations: [UUID: NSKeyValueObservation] = [:]
    /// 每个块上一次真正写入的标题/宽度，避免重复赋值导致状态项消失。
    private var lastRendered: [UUID: (title: NSAttributedString, width: CGFloat)] = [:]

    private var inputPanel: InputPanel?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    private let settings = AppSettings.shared

    /// 状态项的最小长度：即使文字、前缀、后缀全部为空，也保留一个可点击的入口，
    /// 避免用户把内容清空后菜单栏项消失、再也打不开设置。
    private static let minimumStatusItemWidth: CGFloat = 22

    func setup() {
        // 设置变化时刷新对应菜单栏块（直接回调，比 Combine/UserDefaults 通知可靠）
        settings.onDisplayChange = { [weak self] block in self?.refreshTitle(block) }
        settings.onStructureChange = { [weak self] in
            self?.syncStatusItems()
            RotationController.shared.scheduleAll()
            DateTextController.shared.schedule()
        }
        settings.onAppearanceChange = { [weak self] in self?.applyAppearanceToWindows() }

        syncStatusItems()
    }

    /// 让状态项与 `settings.blocks` 保持一致（新增/删除块时调用）。
    private func syncStatusItems() {
        let valid = Set(settings.blocks.map(\.id))
        let stale = statusItems.keys.filter { !valid.contains($0) }
        for id in stale {
            appearanceObservations[id]?.invalidate()
            appearanceObservations[id] = nil
            if let item = statusItems[id] {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItems[id] = nil
            lastRendered[id] = nil
        }

        for block in settings.blocks where statusItems[block.id] == nil {
            createStatusItem(for: block)
        }
        for block in settings.blocks {
            refreshTitle(block)
        }

        if !settings.blocks.contains(where: { $0.id == settings.selectedBlockID }),
           let first = settings.blocks.first {
            settings.selectedBlockID = first.id
        }
    }

    private func createStatusItem(for block: BlockSettings) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // 记住用户 Cmd+拖动后的位置，重启后保持在菜单栏同一位置
        item.autosaveName = block.autosaveName
        guard let button = item.button else { return }
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

        // 监听该块菜单栏深浅变化（壁纸/系统外观改变时系统会自动调整）
        let initialDark = Self.isDarkAppearance(button.effectiveAppearance)
        if block.menuBarIsDark != initialDark {
            block.menuBarIsDark = initialDark
        }
        appearanceObservations[block.id] = button.observe(\.effectiveAppearance, options: [.new]) {
            [weak self, weak block] button, _ in
            // KVO 回调在主线程触发；Swift 6 下需显式声明主actor隔离
            MainActor.assumeIsolated {
                guard let self, let block else { return }
                let dark = Self.isDarkAppearance(button.effectiveAppearance)
                if dark != block.menuBarIsDark {
                    block.menuBarIsDark = dark
                    if block.adaptiveColors { self.refreshTitle(block) }
                }
            }
        }

        statusItems[block.id] = item
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        // 菜单栏实际外观是 VibrantLight/VibrantDark，不是 Aqua/DarkAqua
        appearance.name == .vibrantDark || appearance.bestMatch(from: [.vibrantDark, .aqua]) == .vibrantDark
    }

    private func refreshTitle(_ block: BlockSettings) {
        guard let item = statusItems[block.id], let button = item.button else { return }
        // 刷新前同步菜单栏当前深浅状态（开关切换时确保用对颜色）。
        // 先判等再写，避免 @Published 在每次标题刷新时都触发设置页重绘。
        let isDark = Self.isDarkAppearance(button.effectiveAppearance)
        if block.menuBarIsDark != isDark {
            block.menuBarIsDark = isDark
        }
        let str = NSMutableAttributedString()
        let colors = block.effectiveNSColors
        let full = block.displayText
        let font = block.font
        for (i, ch) in full.enumerated() {
            let color = colors.isEmpty ? .white : colors[i % colors.count]
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            if block.tracking != 0 {
                attributes[.kern] = NSNumber(value: block.tracking)
            }
            str.append(NSAttributedString(string: String(ch), attributes: attributes))
        }
        // 紧凑布局：长度 = 文字实际宽度（cell 内部零补白；剩余间距是系统项间距）。
        // 同时保证一个最小宽度：内容全部清空时仍保留可点击区域，不会把入口弄丢。
        let textWidth = ceil(str.size().width)
        let maxWidth = max(CGFloat(block.maxWidth), Self.minimumStatusItemWidth)
        let width = max(min(textWidth, maxWidth), Self.minimumStatusItemWidth)

        // 内容为空时用提示文案兜底，方便用户悬停/读屏时知道这里可以点。
        let accessibleText = full.isEmpty ? "SwiftQuote" : full
        button.toolTip = full.isEmpty ? settings.strings.statusItemToolTip : full
        button.setAccessibilityLabel(accessibleText)

        // 避免重复写入相同的 attributedTitle：macOS 上反复赋值（尤其是相同值）
        // 会让状态项整个消失。内容/宽度没变就直接跳过。
        if let last = lastRendered[block.id],
           last.title.isEqual(to: str),
           last.width == width {
            return
        }
        lastRendered[block.id] = (str, width)
        button.attributedTitle = str
        item.length = width
    }

    private func block(for button: NSStatusBarButton) -> BlockSettings? {
        settings.blocks.first { statusItems[$0.id]?.button === button }
    }

    private func block(id: UUID?) -> BlockSettings? {
        guard let id else { return nil }
        return settings.blocks.first { $0.id == id }
    }

    /// 打开系统日历（Calendar.app）。找不到时静默忽略。
    private func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: configuration,
                                           completionHandler: nil)
    }

    @objc private func onClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent, let block = block(for: sender) else { return }
        // 右键，或 Ctrl+单击（macOS 上等价于右键）→ 编辑该块；其余 → 菜单
        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.type == .leftMouseUp
            && event.modifierFlags.contains(.control)
        if isRightClick || isControlClick {
            // 开启「左键打开日历」后，右键改为打开菜单，保证设置入口仍然可用
            if block.calendarOnLeftClick {
                showMenu(for: block)
            } else {
                showInputPanel(block)
            }
        } else if block.calendarOnLeftClick {
            openCalendar()
        } else {
            showMenu(for: block)
        }
    }

    // MARK: - 左键菜单
    private func showMenu(for block: BlockSettings) {
        guard let item = statusItems[block.id], let button = item.button else { return }
        let menu = NSMenu()
        let s = settings.strings

        // 多块时在菜单顶部标出当前操作的是哪一块
        if settings.blocks.count > 1 {
            let header = NSMenuItem(title: block.label(settings.isChinese), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        let input = NSMenuItem(title: block.dateEnabled ? s.menuDateFormat : s.menuInput,
                               action: #selector(onInput(_:)),
                               keyEquivalent: "")
        input.target = self
        input.representedObject = block.id
        menu.addItem(input)

        let settingsItem = NSMenuItem(title: s.menuSettings, action: #selector(onSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !block.dateEnabled {
            let historyToggle = NSMenuItem(title: s.trackHistory,
                                           action: #selector(onToggleHistory(_:)),
                                           keyEquivalent: "")
            historyToggle.target = self
            historyToggle.representedObject = block.id
            historyToggle.state = block.trackHistory ? .on : .off
            menu.addItem(historyToggle)
        }

        let calendarToggle = NSMenuItem(title: s.calendarOnLeftClick,
                                        action: #selector(onToggleCalendar(_:)),
                                        keyEquivalent: "")
        calendarToggle.target = self
        calendarToggle.representedObject = block.id
        calendarToggle.state = block.calendarOnLeftClick ? .on : .off
        menu.addItem(calendarToggle)

        let loginToggle = NSMenuItem(title: s.launchAtLogin,
                                     action: #selector(onToggleLogin),
                                     keyEquivalent: "")
        loginToggle.target = self
        loginToggle.state = settings.launchAtLogin ? .on : .off
        loginToggle.isEnabled = settings.loginItemAvailable   // SPM 裸跑时禁用
        menu.addItem(loginToggle)

        // 历史里永远排除当前值（实时编辑后当前值也可能短暂留在底层 history 中）
        let displayHistory = block.displayHistory
        if !block.dateEnabled && block.trackHistory && !displayHistory.isEmpty {
            menu.addItem(.separator())
            historyHeaderMenu(menu, block: block, items: Array(displayHistory.prefix(5)))
        }

        if !block.dateEnabled && block.rotationEnabled && block.activeRotationItems.count > 1 {
            menu.addItem(.separator())
            rotationMenu(menu, block: block)
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

        // 打开设置时默认选中刚才点击的块
        settings.selectedBlockID = block.id
        item.menu = menu
        button.performClick(nil)   // 由系统弹出，定位最精确
        item.menu = nil
    }

    private func historyHeaderMenu(_ menu: NSMenu, block: BlockSettings, items: [HistoryEntry]) {
        let header = NSMenuItem(title: settings.strings.historyHeader, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in items {
            let title = entry.isPinned ? "★ \(entry.displayValue)" : entry.displayValue
            let mi = NSMenuItem(title: title, action: #selector(onHistoryItem(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = HistoryMenuPayload(blockID: block.id, entry: entry)
            menu.addItem(mi)
        }
        let clear = NSMenuItem(title: settings.strings.clearHistory,
                               action: #selector(onClearHistory(_:)),
                               keyEquivalent: "")
        clear.target = self
        clear.representedObject = block.id
        menu.addItem(clear)
    }

    private func rotationMenu(_ menu: NSMenu, block: BlockSettings) {
        let s = settings.strings
        let next = NSMenuItem(title: s.menuNextItem,
                              action: #selector(onNextRotationItem(_:)),
                              keyEquivalent: "")
        next.target = self
        next.representedObject = block.id
        next.isEnabled = block.activeRotationItems.count > 1
        menu.addItem(next)

        let pause = NSMenuItem(title: block.rotationPaused ? s.menuResumeRotation : s.menuPauseRotation,
                               action: #selector(onToggleRotationPause(_:)),
                               keyEquivalent: "")
        pause.target = self
        pause.representedObject = block.id
        menu.addItem(pause)
    }

    @objc private func onNextRotationItem(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        RotationController.shared.nextManually(block: block)
    }

    @objc private func onToggleRotationPause(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        RotationController.shared.togglePause(block: block)
    }

    @objc private func onHistoryItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? HistoryMenuPayload,
              let block = block(id: payload.blockID) else { return }
        block.applyHistory(payload.entry)
    }

    @objc private func onClearHistory(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        block.history = []
    }

    @objc private func onToggleHistory(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        block.trackHistory.toggle()
    }

    @objc private func onToggleCalendar(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        block.calendarOnLeftClick.toggle()
    }

    @objc private func onToggleLogin() {
        settings.launchAtLogin.toggle()
    }

    @objc private func onInput(_ sender: NSMenuItem) {
        guard let block = block(id: sender.representedObject as? UUID) else { return }
        showInputPanel(block)
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
    private func showInputPanel(_ block: BlockSettings) {
        if inputPanel == nil {
            let panel = InputPanel()
            // 关闭后释放面板（连同 NSTextField），回收视图树、保持轻量。
            panel.onDismiss = { [weak self] in self?.inputPanel = nil }
            inputPanel = panel
        }
        inputPanel?.appearance = settings.appAppearance
        inputPanel?.show(block: block, near: statusItems[block.id]?.button)
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
