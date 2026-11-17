import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// 通用页：主题 / 语言 / 开机自启（默认 Tab）
struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        Form {
            Section(s.groupAppearance) {
                Picker("", selection: $settings.appearance) {
                    Text(s.appearanceSystem).tag(AppAppearance.system)
                    Text(s.appearanceLight).tag(AppAppearance.light)
                    Text(s.appearanceDark).tag(AppAppearance.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Section(s.groupLanguage) {
                Picker("", selection: $settings.language) {
                    Text(s.languageSystem).tag(AppLanguage.system)
                    Text("中文").tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Section(s.groupStartup) {
                Toggle(s.launchAtLogin, isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }))
                    .disabled(!settings.loginItemAvailable)

                if !settings.loginItemAvailable {
                    Text(s.launchAtLoginUnavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = settings.loginItemError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if settings.loginItemStatus == .requiresApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.loginItemRequiresApproval)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(s.openLoginItems) {
                            settings.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                } else if settings.loginItemStatus == .notFound {
                    Text(s.loginItemNotFound)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(s.groupBackup) {
                HStack(spacing: 8) {
                    Button(s.exportSettings) {
                        exportSettings()
                    }
                    Button(s.importSettings) {
                        importSettings()
                    }
                    Spacer()
                }
                Button(role: .destructive) {
                    resetSettings()
                } label: {
                    Text(s.resetSettings)
                }
                Text(s.dataVersion(AppSettings.dataVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(s.backupHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 12)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 从系统设置批准/拒绝登录项后返回，重新读取真实状态
            settings.refreshLoginItemState()
        }
    }

    // MARK: - 备份与恢复

    private func exportSettings() {
        let s = settings.strings
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.backupFileName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try settings.exportBackupData()
            try data.write(to: url, options: .atomic)
            showAlert(title: s.exportDoneTitle,
                      message: s.exportDoneMessage(url.lastPathComponent))
        } catch {
            showAlert(title: s.exportFailedTitle,
                      message: error.localizedDescription,
                      style: .warning)
        }
    }

    private func importSettings() {
        let s = settings.strings
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showAlert(title: s.importFailedTitle,
                      message: s.importInvalidFile,
                      style: .warning)
            return
        }

        do {
            let preview = try settings.decodeBackup(data)
            var notes: [String] = []
            if preview.droppedBlocks > 0 {
                notes.append(s.importDropped(preview.droppedBlocks))
            }
            if preview.schemaVersion > AppSettings.dataVersion {
                notes.append(s.importFutureVersion(preview.schemaVersion, AppSettings.dataVersion))
            }
            let message = ([s.importConfirmMessage(
                preview.blocks.count,
                preview.schemaVersion == 0 ? s.legacyDataVersion : "\(preview.schemaVersion)")] + notes)
                .joined(separator: "\n")
            guard confirm(title: s.importConfirmTitle,
                          message: message,
                          confirmTitle: s.importSettings) else { return }

            let result = settings.applyBackup(preview)
            let done = settings.strings
            var doneNotes: [String] = []
            if result.droppedBlocks > 0 {
                doneNotes.append(done.importDropped(result.droppedBlocks))
            }
            if result.schemaVersion > AppSettings.dataVersion {
                doneNotes.append(done.importFutureVersion(result.schemaVersion, AppSettings.dataVersion))
            }
            showAlert(title: done.importDoneTitle,
                      message: ([done.importDoneMessage(result.importedBlocks)] + doneNotes)
                        .joined(separator: "\n"))
        } catch {
            showAlert(title: s.importFailedTitle,
                      message: s.importInvalidFile,
                      style: .warning)
        }
    }

    private func resetSettings() {
        let s = settings.strings
        guard confirm(title: s.resetConfirmTitle,
                      message: s.resetConfirmMessage,
                      confirmTitle: s.resetConfirmButton) else { return }
        settings.resetToDefaults()
        let done = settings.strings
        showAlert(title: done.resetDoneTitle, message: done.resetDoneMessage)
    }

    private func showAlert(title: String, message: String,
                           style: NSAlert.Style = .informational) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: settings.strings.ok)
        alert.runModal()
    }

    private func confirm(title: String, message: String,
                         confirmTitle: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: settings.strings.cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "SwiftQuote-Settings-\(formatter.string(from: Date())).json"
    }
}

/// 菜单栏块页：添加 / 删除 / 选择当前编辑的块。
struct BlocksSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s.blocksHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(s.addBlock) {
                    settings.addBlock()
                }
            }

            List(selection: Binding(
                get: { Optional(settings.selectedBlockID) },
                set: { newValue in
                    if let newValue { settings.selectedBlockID = newValue }
                })) {
                ForEach(settings.blocks) { block in
                    BlockRow(block: block)
                        .tag(block.id)
                }
            }
            .listStyle(.inset)

            Text(s.blocksPositionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// 观察单个块，保证块列表里的文字随编辑/轮播实时更新。
private struct BlockRow: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var block: BlockSettings

    var body: some View {
        let s = settings.strings
        HStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.secondary)
            Text(block.label(settings.isChinese))
                .lineLimit(1)
            Spacer()
            Button {
                settings.removeBlock(block)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(settings.blocks.count <= 1)
            .help(s.deleteBlock)
        }
    }
}

/// 观察单个块，保证块选择器里的名称随编辑/轮播实时更新。
private struct BlockLabel: View {
    @ObservedObject var block: BlockSettings
    let isChinese: Bool

    var body: some View {
        Text(block.label(isChinese))
    }
}

/// 每块页面顶部的块选择器。
private struct BlockPickerRow: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let s = settings.strings
        HStack {
            Text(s.block)
                .frame(width: 60, alignment: .trailing)
            Picker("", selection: $settings.selectedBlockID) {
                ForEach(settings.blocks) { block in
                    BlockLabel(block: block, isChinese: settings.isChinese)
                        .tag(block.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 文字页：内容/前后缀/样式/预设/历史开关（作用于当前块）
struct TextSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let block = settings.selectedBlock {
            BlockTextSettingsView(block: block)
                .id(block.id)
        }
    }
}

private struct BlockTextSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var block: BlockSettings

    var body: some View {
        let s = settings.strings
        let isChinese = settings.isChinese
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BlockPickerRow()

                GroupBox(s.groupText) {
                    VStack(alignment: .leading, spacing: 8) {
                        // 实时编辑：更新菜单栏但不逐字写历史（切换时才把旧值记入历史）
                        labeledField(s.content, text: Binding(
                            get: { block.text },
                            set: { block.setTextLive($0) }),
                            onBeginEditing: { block.beginTextEditing() },
                            onEndEditing: { block.endTextEditing() })
                        labeledField(s.prefix, text: $block.prefix)
                        labeledField(s.suffix, text: $block.suffix)
                        HStack {
                            Text(s.fontFamily)
                                .frame(width: 60, alignment: .trailing)
                            Picker("", selection: $block.fontFamily) {
                                Text(s.systemDefault).tag(String?.none)
                                ForEach(AppSettings.availableFontFamilies, id: \.self) { family in
                                    Text(family).tag(Optional(family))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Text(s.fontWeight)
                                .frame(width: 60, alignment: .trailing)
                            Picker("", selection: $block.fontWeight) {
                                ForEach(FontWeight.allCases) { weight in
                                    Text(weight.label(isChinese)).tag(weight)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Text(s.fontSize)
                            Slider(value: $block.fontSize, in: 9...21, step: 0.5)
                            Text("\(block.fontSize, specifier: "%.1f")")
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                        HStack {
                            Text(s.tracking)
                            Slider(value: $block.tracking, in: -2...5, step: 0.1)
                            Text("\(block.tracking, specifier: "%.1f")")
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                        HStack {
                            Text(s.maxWidth)
                            Slider(value: $block.maxWidth, in: 40...400, step: 5)
                            Text("\(Int(block.maxWidth))")
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                        HStack {
                            Text(s.preview)
                                .frame(width: 60, alignment: .trailing)
                            if block.dateEnabled {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(block.displayText(at: context.date))
                                        .font(block.swiftUIFont(size: 13))
                                        .tracking(block.tracking)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(block.displayText.isEmpty ? "—" : block.displayText)
                                    .font(block.swiftUIFont(size: 13))
                                    .tracking(block.tracking)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(8)
                }

                GroupBox(s.groupDateTime) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(s.dynamicDateTime, isOn: $block.dateEnabled)

                        HStack {
                            Text(s.dateFormat)
                                .frame(width: 60, alignment: .trailing)
                            NoAutofillTextFieldView(
                                placeholder: s.dateFormatPlaceholder,
                                text: $block.datePattern,
                                font: .monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                           weight: .regular))
                                .frame(maxWidth: .infinity)
                        }

                        Text(s.dateFormatHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), alignment: .leading)],
                                  alignment: .leading,
                                  spacing: 6) {
                            ForEach(Self.datePatterns, id: \.self) { pattern in
                                Button(pattern) {
                                    block.datePattern = pattern
                                    block.dateEnabled = true
                                }
                                .controlSize(.small)
                            }
                            Button(s.dateScreenshotPreset) {
                                block.datePattern = "MM-dd[EEE]HH:mm"
                                block.prefix = ""
                                block.suffix = " "
                                block.dateEnabled = true
                            }
                            .controlSize(.small)
                        }

                        HStack {
                            Text(s.preview)
                                .frame(width: 60, alignment: .trailing)
                            if block.dateEnabled {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Text(block.displayText(at: context.date))
                                        .font(block.swiftUIFont(size: 13))
                                        .tracking(block.tracking)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(block.displayText)
                                    .font(block.swiftUIFont(size: 13))
                                    .tracking(block.tracking)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }

                        if block.dateEnabled {
                            Text(s.dateContentIgnoredHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Toggle(s.calendarOnLeftClick, isOn: $block.calendarOnLeftClick)
                        Text(s.calendarClickHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }

                GroupBox(s.groupPresets) {
                    VStack(spacing: 4) {
                        ForEach(Preset.all) { preset in
                            HStack {
                                Text(preset.name(isChinese))
                                Spacer()
                                Text(preset.prefix + preset.text(isChinese) + preset.suffix)
                                    .font(block.swiftUIFont(size: 13))
                                    .tracking(block.tracking)
                                    .foregroundStyle(.secondary)
                                Button(s.apply) {
                                    block.dateEnabled = false
                                    let value = preset.text(isChinese)
                                    // 先切文字：旧值会以旧前后缀进入历史；再套用新前后缀
                                    if !value.isEmpty {
                                        block.text = value
                                    }
                                    block.prefix = preset.prefix
                                    block.suffix = preset.suffix
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox(s.tabHistory) {
                    HStack {
                        Toggle(s.trackHistory, isOn: $block.trackHistory)
                    }
                    .padding(8)
                }
            }
            .padding()
        }
    }

    private static let datePatterns = [
        "MM-dd[EEE]HH:mm",
        "HH:mm",
        "HH:mm:ss",
        "yyyy-MM-dd",
        "yyyy-MM-dd EEE",
        "M月d日 EEE",
    ]

    private func labeledField(_ label: String, text: Binding<String>,
                              onBeginEditing: (() -> Void)? = nil,
                              onEndEditing: (() -> Void)? = nil) -> some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .trailing)
            NoAutofillTextFieldView(
                placeholder: label,
                text: text,
                font: block.resolvedFont(size: NSFont.systemFontSize),
                onBeginEditing: onBeginEditing,
                onEndEditing: onEndEditing)
                .frame(maxWidth: .infinity)
        }
    }
}

/// 颜色页：依次循环应用到每个字符，可单独修改、拖动排序、删除（作用于当前块）
/// 开启「自适应菜单栏」后维护两套颜色，随菜单栏深浅自动切换
struct ColorsSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let block = settings.selectedBlock {
            BlockColorsSettingsView(block: block)
                .id(block.id)
        }
    }
}

private struct BlockColorsSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var block: BlockSettings

    var body: some View {
        let s = settings.strings
        VStack(alignment: .leading, spacing: 12) {
            BlockPickerRow()

            HStack {
                Toggle(s.adaptiveColors, isOn: $block.adaptiveColors)
                Spacer()
                Button(s.resetColors) {
                    block.resetColorsToDefault()
                }
            }

            if block.adaptiveColors {
                colorList(title: s.lightBarColors,
                          entries: $block.lightBarColorEntries)
                colorList(title: s.darkBarColors,
                          entries: $block.darkBarColorEntries)
            } else {
                colorList(title: nil, entries: $block.colorEntries)
            }

            Text(s.colorsHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            preview
        }
        .padding()
    }

    /// 一组颜色的编辑列表（添加 / 修改 / 排序 / 删除）
    private func colorList(title: String?, entries: Binding<[ColorEntry]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            ColorListEditor(entries: entries)
        }
    }

    private var preview: some View {
        // 逐字符颜色需要独立 Text；用 HStack 间距模拟字距（单个字符的 .tracking 不生效）。
        HStack(spacing: CGFloat(block.tracking)) {
            let colors = block.effectiveNSColors
            let full = block.displayText
            ForEach(Array(full.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(block.swiftUIFont(size: block.fontSize))
                    .foregroundStyle(colors.isEmpty ? Color.white : Color(nsColor: colors[i % colors.count]))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// 可复用的颜色列表编辑器：添加 / 修改 / 拖动排序 / 删除
private struct ColorListEditor: View {
    @Binding var entries: [ColorEntry]
    @State private var newColor = Color.white

    var body: some View {
        HStack {
            ColorPicker("", selection: $newColor, supportsOpacity: false)
                .labelsHidden()
            Button(AppSettings.shared.strings.add) {
                entries.append(ColorEntry(hex: NSColor(newColor).hexString))
            }
            Spacer()
        }

        List {
            ForEach(entries) { entry in
                HStack {
                    ColorPicker("", selection: colorBinding(entry.id), supportsOpacity: false)
                        .labelsHidden()
                    Spacer()
                    Button {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(entries.count <= 1)
                }
            }
            .onMove { offsets, destination in
                entries.move(fromOffsets: offsets, toOffset: destination)
            }
        }
        .frame(minHeight: 120)
    }

    private func colorBinding(_ id: UUID) -> Binding<Color> {
        Binding(
            get: {
                guard let i = entries.firstIndex(where: { $0.id == id }) else { return .white }
                return Color(nsColor: NSColor(hex: entries[i].hex) ?? .white)
            },
            set: { newValue in
                guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
                entries[i].hex = NSColor(newValue).hexString
            }
        )
    }
}

/// 轮播页：当前块的一组文字按间隔顺序/随机切换
struct RotationSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let block = settings.selectedBlock {
            BlockRotationSettingsView(block: block)
                .id(block.id)
        }
    }
}

private struct BlockRotationSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var block: BlockSettings

    var body: some View {
        let s = settings.strings
        VStack(alignment: .leading, spacing: 12) {
            BlockPickerRow()

            Group {
                Toggle(s.rotationEnabled, isOn: $block.rotationEnabled)

                HStack {
                    Text(s.rotationInterval)
                        .frame(width: 60, alignment: .trailing)
                    Picker("", selection: $block.rotationInterval) {
                        ForEach(RotationInterval.allCases) { interval in
                            Text(interval.label(settings.isChinese)).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text(s.rotationOrder)
                        .frame(width: 60, alignment: .trailing)
                    Picker("", selection: $block.rotationOrder) {
                        Text(s.rotationSequential).tag(RotationOrder.sequential)
                        Text(s.rotationRandom).tag(RotationOrder.random)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 8) {
                    Button(s.rotationAddCurrent) {
                        block.addCurrentTextToRotation()
                    }
                    .disabled(block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || block.rotationItems.contains { $0.text == block.text })

                    Button(s.rotationAddItem) {
                        block.rotationItems.append(RotationItem(text: ""))
                    }

                    Spacer()

                    Button(s.menuNextItem) {
                        RotationController.shared.nextManually(block: block)
                    }
                    .disabled(!block.rotationEnabled || block.activeRotationItems.count < 2)

                    Button(block.rotationPaused ? s.menuResumeRotation : s.menuPauseRotation) {
                        RotationController.shared.togglePause(block: block)
                    }
                    .disabled(!block.rotationEnabled)
                }
                .controlSize(.small)

                if block.rotationItems.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(s.rotationEmpty)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    Spacer()
                } else {
                    List {
                        ForEach($block.rotationItems) { $item in
                            HStack(spacing: 8) {
                                TextField(s.rotationItemPlaceholder, text: $item.text)
                                    .textFieldStyle(.roundedBorder)
                                    .font(block.swiftUIFont(size: 13))
                                    .tracking(block.tracking)
                                if item.text == block.text && !item.text.isEmpty {
                                    Text(s.current)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    block.rotationItems.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onMove { block.rotationItems.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { block.rotationItems.remove(atOffsets: $0) }
                    }
                    .listStyle(.inset)
                }

                if !block.rotationItems.isEmpty && block.activeRotationItems.count < 2 {
                    Text(s.rotationNeedsTwo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(block.dateEnabled)

            if block.dateEnabled {
                Text(s.rotationDisabledByDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// 历史记录页：查看、应用、删除单条、清空（作用于当前块）
struct HistorySettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let block = settings.selectedBlock {
            BlockHistorySettingsView(block: block)
                .id(block.id)
        }
    }
}

private struct BlockHistorySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var block: BlockSettings
    @State private var query = ""

    var body: some View {
        let s = settings.strings
        let items = filteredHistory
        VStack(alignment: .leading, spacing: 12) {
            BlockPickerRow()

            if block.dateEnabled {
                Text(s.dateHistoryHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Toggle(s.trackHistory, isOn: $block.trackHistory)
                Spacer()
                if !block.history.isEmpty {
                    Button(role: .destructive) {
                        block.history = []
                    } label: {
                        Label(s.clearAll, systemImage: "trash")
                    }
                }
            }

            HStack(spacing: 8) {
                NoAutofillTextFieldView(placeholder: s.searchHistory, text: $query)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(s.clearSearch)
                }
            }

            HStack {
                Text(s.historyLimit)
                    .frame(width: 60, alignment: .trailing)
                Stepper(value: $block.historyLimit, in: 1...100) {
                    Text("\(block.historyLimit)")
                        .monospacedDigit()
                }
                Spacer()
            }

            Text(s.historyHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            // 当前值单独显示（不混在历史列表里）
            if !block.text.isEmpty {
                GroupBox(s.current) {
                    HStack {
                        Text(block.prefix + block.text + block.suffix)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(6)
                }
            }

            if items.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text(query.isEmpty ? s.noHistory : s.noSearchResults)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                List {
                    ForEach(items) { entry in
                        HStack(spacing: 8) {
                            Button {
                                block.togglePinned(entry)
                            } label: {
                                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                                    .foregroundStyle(entry.isPinned ? Color.orange : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(entry.isPinned ? s.unpin : s.pin)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .lineLimit(1)
                                if entry.displayValue != entry.text {
                                    Text(entry.displayValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Button(s.apply) {
                                block.applyHistory(entry)
                            }
                            .controlSize(.small)
                            .disabled(block.dateEnabled)

                            Button {
                                block.removeHistory(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(s.deleteHistoryItem)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { block.removeHistory(items[index]) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }

    /// 搜索文字、前缀或后缀；收藏项天然排在历史数组最前。
    private var filteredHistory: [HistoryEntry] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = block.displayHistory
        guard !value.isEmpty else { return items }
        return items.filter {
            $0.text.localizedCaseInsensitiveContains(value)
                || $0.prefix.localizedCaseInsensitiveContains(value)
                || $0.suffix.localizedCaseInsensitiveContains(value)
        }
    }
}

private extension BlockSettings {
    /// SwiftUI 侧的字体：系统默认走 .system，自定义字体族用其 PostScript 名。
    func swiftUIFont(size: CGFloat) -> Font {
        if fontFamily != nil {
            return .custom(resolvedFont(size: size).fontName, size: size)
        }
        return .system(size: size, weight: fontWeight.swiftUIWeight)
    }
}

private extension FontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        }
    }
}
