import Foundation
import AppKit
import ServiceManagement

/// 一个颜色条目：稳定 id（用于 SwiftUI 列表身份）+ 颜色 hex
struct ColorEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var hex: String
}

/// 菜单栏块的持久化快照。运行时状态（菜单栏深浅等）不写在这里。
struct BlockSnapshot: Codable, Equatable {
    var id: UUID
    var autosaveName: String
    var text: String
    var prefix: String
    var suffix: String
    var trackHistory: Bool
    var maxWidth: Double
    var fontSize: Double
    var bold: Bool
    var fontFamily: String?
    var colorEntries: [ColorEntry]
    var adaptiveColors: Bool
    var lightBarColorEntries: [ColorEntry]
    var darkBarColorEntries: [ColorEntry]
    var history: [String]
    var rotationEnabled: Bool
    var rotationPaused: Bool
    var rotationInterval: RotationInterval
    var rotationOrder: RotationOrder
    var rotationItems: [RotationItem]

    /// 新增块的默认值：只显示文字本身，样式与主块保持一致的基础值。
    static func makeDefault(autosaveName: String, text: String) -> BlockSnapshot {
        BlockSnapshot(
            id: UUID(),
            autosaveName: autosaveName,
            text: text,
            prefix: "",
            suffix: "",
            trackHistory: true,
            maxWidth: 200,
            fontSize: 13,
            bold: true,
            fontFamily: nil,
            colorEntries: [ColorEntry(hex: "#FFFFFF")],
            adaptiveColors: false,
            lightBarColorEntries: [ColorEntry(hex: "#000000")],
            darkBarColorEntries: [ColorEntry(hex: "#FFFFFF")],
            history: [],
            rotationEnabled: false,
            rotationPaused: false,
            rotationInterval: .oneMinute,
            rotationOrder: .sequential,
            rotationItems: [])
    }
}

/// 单个菜单栏块：文字、样式、颜色、轮播与历史都相互独立。
@MainActor
final class BlockSettings: ObservableObject, Identifiable {
    enum Change {
        case display    // 需要刷新菜单栏标题
        case rotation   // 需要重排轮播定时器
        case persist    // 只需落盘（例如历史列表变化）
    }

    let id: UUID
    let autosaveName: String

    var onChange: ((Change) -> Void)?

    @Published var text: String {
        didSet {
            // 当前值永远不留在历史里。实时编辑（suppressHistory）也要执行这一步，
            // 只是不把被替换掉的旧值新增进历史。
            history.removeAll { $0 == text }
            if !suppressHistory {
                // 被替换掉的旧值进入历史（“切换”语义）
                if trackHistory, !oldValue.isEmpty, oldValue != text {
                    history.removeAll { $0 == oldValue }
                    history.insert(oldValue, at: 0)
                    if history.count > 10 { history = Array(history.prefix(10)) }
                }
            }
            onChange?(.display)
        }
    }
    @Published var prefix: String { didSet { onChange?(.display) } }
    @Published var suffix: String { didSet { onChange?(.display) } }
    @Published var trackHistory: Bool { didSet { onChange?(.persist) } }
    @Published var maxWidth: Double { didSet { onChange?(.display) } }
    @Published var fontSize: Double { didSet { onChange?(.display) } }
    @Published var bold: Bool { didSet { onChange?(.display) } }
    /// 自定义字体族；nil = 系统默认
    @Published var fontFamily: String? { didSet { onChange?(.display) } }
    /// 每个字符一个颜色，不足时循环使用
    @Published var colorEntries: [ColorEntry] { didSet { onChange?(.display) } }
    /// 自适应菜单栏：开启后按菜单栏深浅自动切换两套颜色
    @Published var adaptiveColors: Bool { didSet { onChange?(.display) } }
    /// 浅色菜单栏（深色壁纸）下使用的颜色
    @Published var lightBarColorEntries: [ColorEntry] { didSet { onChange?(.display) } }
    /// 深色菜单栏（浅色壁纸）下使用的颜色
    @Published var darkBarColorEntries: [ColorEntry] { didSet { onChange?(.display) } }
    @Published var history: [String] { didSet { onChange?(.persist) } }

    // MARK: - 轮播

    @Published var rotationEnabled: Bool {
        didSet {
            if rotationPaused {
                rotationPaused = false   // 切换启用状态时清除暂停
            }
            onChange?(.rotation)
        }
    }
    @Published var rotationPaused: Bool { didSet { onChange?(.rotation) } }
    @Published var rotationInterval: RotationInterval { didSet { onChange?(.rotation) } }
    @Published var rotationOrder: RotationOrder { didSet { onChange?(.rotation) } }
    @Published var rotationItems: [RotationItem] { didSet { onChange?(.rotation) } }

    /// 当前块所在的菜单栏是否为深色（每个状态项可能在不同显示器上）。
    /// 仅影响自适应配色与标题刷新，不落盘。
    @Published var menuBarIsDark = false

    /// 设置页输入框实时编辑时置位：更新当前文字但不写历史，避免逐字污染历史。
    private var suppressHistory = false

    /// 设置页「内容」输入框开始编辑时记录基线。
    private var textEditBaseline: String?

    /// 设置页正文输入框是否正在编辑：轮播定时器据此跳过，避免打断输入。
    private(set) var isEditingText = false

    init(snapshot: BlockSnapshot) {
        id = snapshot.id
        autosaveName = snapshot.autosaveName
        text = snapshot.text
        prefix = snapshot.prefix
        suffix = snapshot.suffix
        trackHistory = snapshot.trackHistory
        maxWidth = snapshot.maxWidth
        // 菜单栏高度约 24pt，字号上限压到 21，避免上下被裁切；同时兜底旧数据中的越界值。
        fontSize = min(max(snapshot.fontSize, 9), 21)
        bold = snapshot.bold
        // 字体族：只接受当前系统仍可用的字体，否则回退系统默认
        fontFamily = snapshot.fontFamily.flatMap {
            AppSettings.availableFontFamilies.contains($0) ? $0 : nil
        }
        colorEntries = snapshot.colorEntries.isEmpty
            ? [ColorEntry(hex: "#FFFFFF")]
            : snapshot.colorEntries
        adaptiveColors = snapshot.adaptiveColors
        lightBarColorEntries = snapshot.lightBarColorEntries.isEmpty
            ? [ColorEntry(hex: "#000000")]
            : snapshot.lightBarColorEntries
        darkBarColorEntries = snapshot.darkBarColorEntries.isEmpty
            ? [ColorEntry(hex: "#FFFFFF")]
            : snapshot.darkBarColorEntries
        // 历史：过滤当前值/空值，去重并截断到 10 条
        var cleanedHistory: [String] = []
        for item in snapshot.history where item != snapshot.text && !item.isEmpty {
            if !cleanedHistory.contains(item) { cleanedHistory.append(item) }
        }
        history = Array(cleanedHistory.prefix(10))
        rotationEnabled = snapshot.rotationEnabled
        rotationPaused = snapshot.rotationPaused
        rotationInterval = snapshot.rotationInterval
        rotationOrder = snapshot.rotationOrder
        rotationItems = snapshot.rotationItems
    }

    var snapshot: BlockSnapshot {
        BlockSnapshot(
            id: id,
            autosaveName: autosaveName,
            text: text,
            prefix: prefix,
            suffix: suffix,
            trackHistory: trackHistory,
            maxWidth: maxWidth,
            fontSize: fontSize,
            bold: bold,
            fontFamily: fontFamily,
            colorEntries: colorEntries,
            adaptiveColors: adaptiveColors,
            lightBarColorEntries: lightBarColorEntries,
            darkBarColorEntries: darkBarColorEntries,
            history: history,
            rotationEnabled: rotationEnabled,
            rotationPaused: rotationPaused,
            rotationInterval: rotationInterval,
            rotationOrder: rotationOrder,
            rotationItems: rotationItems)
    }

    // MARK: - 编辑 / 历史

    /// 实时编辑当前文字（不记入历史）。用于设置页输入框逐字输入。
    func setTextLive(_ value: String) {
        suppressHistory = true
        text = value
        suppressHistory = false
    }

    func beginTextEditing() {
        isEditingText = true
        guard textEditBaseline == nil else { return }
        textEditBaseline = text
    }

    /// 输入框失焦 / 设置窗口关闭时，把“开始编辑前的当前值”补记一次历史。
    /// 逐字输入期间仍不写历史，避免半截输入污染列表。
    func endTextEditing() {
        isEditingText = false
        guard let baseline = textEditBaseline else { return }
        textEditBaseline = nil
        guard !suppressHistory, trackHistory, !baseline.isEmpty, baseline != text else { return }
        history.removeAll { $0 == baseline || $0 == text }
        history.insert(baseline, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }
    }

    /// 用于展示的历史列表：始终排除当前值。
    var displayHistory: [String] { history.filter { $0 != text } }

    /// 删除某一条历史。
    func removeHistory(_ value: String) {
        history.removeAll { $0 == value }
    }

    // MARK: - 轮播

    /// 轮播实际参与切换的条目：过滤空白项，并按文字去重。
    var activeRotationItems: [RotationItem] {
        var seen = Set<String>()
        return rotationItems.filter { item in
            let value = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return false }
            return seen.insert(item.text).inserted
        }
    }

    /// 把当前文字加入轮播组（已存在或为空则忽略）。
    func addCurrentTextToRotation() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !rotationItems.contains(where: { $0.text == text }) else { return }
        rotationItems.append(RotationItem(text: text))
    }

    // MARK: - 显示

    var displayText: String { prefix + text + suffix }

    /// 用于设置页块列表/菜单标题的简短标签。
    func label(_ isChinese: Bool) -> String {
        let value = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (isChinese ? "空块" : "Empty Block") : value
    }

    /// 按当前字体族/粗体/字号解析实际字体；字体不可用时回退系统字体。
    func resolvedFont(size: CGFloat) -> NSFont {
        if let fontFamily {
            let traits: NSFontTraitMask = bold ? [.boldFontMask] : []
            if let custom = NSFontManager.shared.font(withFamily: fontFamily,
                                                      traits: traits,
                                                      weight: 5,
                                                      size: size) {
                return custom
            }
            // 字体族没有独立粗体时，退回同族常规字重并尝试合成粗体
            if bold,
               let regular = NSFontManager.shared.font(withFamily: fontFamily,
                                                       traits: [],
                                                       weight: 5,
                                                       size: size) {
                return NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
            }
        }
        return bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    }

    var font: NSFont { resolvedFont(size: fontSize) }

    /// 当前实际生效的颜色（自适应开启时按菜单栏深浅选一套）
    var effectiveColorEntries: [ColorEntry] {
        guard adaptiveColors else { return colorEntries }
        return menuBarIsDark ? darkBarColorEntries : lightBarColorEntries
    }

    var effectiveNSColors: [NSColor] {
        effectiveColorEntries.compactMap { NSColor(hex: $0.hex) }
    }

    /// 恢复默认颜色（当前模式下正在编辑的那套/两套）
    func resetColorsToDefault() {
        if adaptiveColors {
            lightBarColorEntries = [ColorEntry(hex: "#000000")]
            darkBarColorEntries = [ColorEntry(hex: "#FFFFFF")]
        } else {
            colorEntries = [ColorEntry(hex: "#FFFFFF")]
        }
    }
}

/// 全局设置 + 所有菜单栏块。每个块在菜单栏有独立的 NSStatusItem。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// 所有菜单栏块（至少一个）。结构变化通过 onStructureChange 通知状态栏同步。
    @Published private(set) var blocks: [BlockSettings]

    /// 设置页当前编辑的块。
    @Published var selectedBlockID: UUID {
        didSet {
            UserDefaults.standard.set(selectedBlockID.uuidString, forKey: "selectedBlockID")
            // 切换块时结束所有可能仍在编辑的输入框，补记基线历史；
            // 否则旧块会一直停留在 isEditingText，轮播被永久跳过。
            for block in blocks { block.endTextEditing() }
        }
    }

    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            onAppearanceChange?()
        }
    }
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    var selectedBlock: BlockSettings? {
        blocks.first { $0.id == selectedBlockID } ?? blocks.first
    }

    private init() {
        let d = UserDefaults.standard
        let loaded = Self.loadBlocks(d)
        let initialBlocks = loaded.map { BlockSettings(snapshot: $0) }
        blocks = initialBlocks

        appearance = AppAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: d.string(forKey: "appLanguage") ?? "") ?? .system

        let savedSelection = d.string(forKey: "selectedBlockID").flatMap(UUID.init(uuidString:))
        selectedBlockID = initialBlocks.first { $0.id == savedSelection }?.id ?? initialBlocks[0].id

        for block in initialBlocks {
            block.onChange = { [weak self, weak block] change in
                guard let self, let block else { return }
                self.blockChanged(block, change)
            }
        }

        // 首次从旧版本迁移时立即落盘，避免每次启动重新生成块 ID。
        persistBlocks()
    }

    private func blockChanged(_ block: BlockSettings, _ change: BlockSettings.Change) {
        persistBlocks()
        switch change {
        case .display:
            onDisplayChange?(block)
        case .rotation:
            onRotationChange?(block)
        case .persist:
            break
        }
    }

    // MARK: - 块管理

    @discardableResult
    func addBlock() -> BlockSettings {
        let snapshot = BlockSnapshot.makeDefault(
            autosaveName: "SwiftQuoteStatusItem-\(UUID().uuidString)",
            text: strings.newBlockText)
        let block = BlockSettings(snapshot: snapshot)
        block.onChange = { [weak self, weak block] change in
            guard let self, let block else { return }
            self.blockChanged(block, change)
        }
        let index = blocks.firstIndex { $0.id == selectedBlockID }.map { $0 + 1 } ?? blocks.count
        blocks.insert(block, at: min(index, blocks.count))
        selectedBlockID = block.id
        persistBlocks()
        onStructureChange?()
        return block
    }

    func removeBlock(_ block: BlockSettings) {
        guard blocks.count > 1,
              let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks.remove(at: index)
        if selectedBlockID == block.id {
            selectedBlockID = blocks[min(index, blocks.count - 1)].id
        }
        persistBlocks()
        onStructureChange?()
    }

    private static func loadBlocks(_ d: UserDefaults) -> [BlockSnapshot] {
        if let data = d.data(forKey: "blocks"),
           let decoded = try? JSONDecoder().decode([BlockSnapshot].self, from: data),
           !decoded.isEmpty {
            // 兜底损坏/重复数据：ID 与 autosaveName 都必须唯一
            var seenIDs = Set<UUID>()
            var seenNames = Set<String>()
            return decoded.map { snapshot in
                var snapshot = snapshot
                if seenIDs.contains(snapshot.id) { snapshot.id = UUID() }
                seenIDs.insert(snapshot.id)
                if snapshot.autosaveName.isEmpty || seenNames.contains(snapshot.autosaveName) {
                    snapshot.autosaveName = "SwiftQuoteStatusItem-\(UUID().uuidString)"
                }
                seenNames.insert(snapshot.autosaveName)
                return snapshot
            }
        }
        return [legacySnapshot(d)]
    }

    /// 从旧版本的单块键迁移出第一个块。
    private static func legacySnapshot(_ d: UserDefaults) -> BlockSnapshot {
        let currentText = d.string(forKey: "text") ?? "Aloha!"
        let storedFamily = d.string(forKey: "fontFamily")
        let family = storedFamily.flatMap { availableFontFamilies.contains($0) ? $0 : nil }

        let colors: [ColorEntry]
        if let data = d.data(forKey: "colorEntries"),
           let decoded = try? JSONDecoder().decode([ColorEntry].self, from: data),
           !decoded.isEmpty {
            colors = decoded
        } else {
            // 兼容更早版本存的 [String]
            let legacy = d.stringArray(forKey: "colors") ?? ["#FFFFFF"]
            colors = legacy.map { ColorEntry(hex: $0) }
        }

        func loadEntries(_ key: String, fallback: [ColorEntry]) -> [ColorEntry] {
            guard let data = d.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ColorEntry].self, from: data),
                  !decoded.isEmpty else { return fallback }
            return decoded
        }

        var cleanedHistory: [String] = []
        for item in d.stringArray(forKey: "history") ?? []
        where item != currentText && !item.isEmpty {
            if !cleanedHistory.contains(item) { cleanedHistory.append(item) }
        }

        let rotationItems: [RotationItem]
        if let data = d.data(forKey: "rotationItems"),
           let decoded = try? JSONDecoder().decode([RotationItem].self, from: data) {
            rotationItems = decoded
        } else {
            rotationItems = []
        }

        return BlockSnapshot(
            id: UUID(),
            autosaveName: "SwiftQuoteStatusItem",   // 保留旧版菜单栏位置
            text: currentText,
            prefix: d.string(forKey: "prefix") ?? "[",
            suffix: d.string(forKey: "suffix") ?? "]",
            trackHistory: d.object(forKey: "trackHistory") as? Bool ?? true,
            maxWidth: d.object(forKey: "maxWidth") as? Double ?? 200,
            fontSize: d.object(forKey: "fontSize") as? Double ?? 13,
            bold: d.object(forKey: "bold") as? Bool ?? true,
            fontFamily: family,
            colorEntries: colors,
            adaptiveColors: d.object(forKey: "adaptiveColors") as? Bool ?? false,
            lightBarColorEntries: loadEntries("lightBarColorEntries",
                                              fallback: [ColorEntry(hex: "#000000")]),
            darkBarColorEntries: loadEntries("darkBarColorEntries",
                                             fallback: [ColorEntry(hex: "#FFFFFF")]),
            history: Array(cleanedHistory.prefix(10)),
            rotationEnabled: d.object(forKey: "rotationEnabled") as? Bool ?? false,
            rotationPaused: d.object(forKey: "rotationPaused") as? Bool ?? false,
            rotationInterval: RotationInterval(rawValue: d.string(forKey: "rotationInterval") ?? "")
                ?? .oneMinute,
            rotationOrder: RotationOrder(rawValue: d.string(forKey: "rotationOrder") ?? "")
                ?? .sequential,
            rotationItems: rotationItems)
    }

    private func persistBlocks() {
        if let data = try? JSONEncoder().encode(blocks.map(\.snapshot)) {
            UserDefaults.standard.set(data, forKey: "blocks")
        }
        UserDefaults.standard.set(selectedBlockID.uuidString, forKey: "selectedBlockID")
    }

    /// 补记所有块可能仍在编辑中的正文（endTextEditing 幂等）。
    func endTextEditing() {
        for block in blocks { block.endTextEditing() }
    }

    // MARK: - 回调（由状态栏 / 轮播控制器设置）

    /// 某个块的显示内容变化
    var onDisplayChange: ((BlockSettings) -> Void)?
    /// 某个块的轮播配置变化
    var onRotationChange: ((BlockSettings) -> Void)?
    /// 块的增删
    var onStructureChange: (() -> Void)?
    /// 主题外观变化（用于更新已打开的窗口）
    var onAppearanceChange: (() -> Void)?

    // MARK: - 开机自启（SMAppService；裸跑 SwiftPM 可执行文件时不可用）

    /// 无 Bundle ID（非打包 App）时无法注册登录项
    var loginItemAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    /// 登录项实时状态：enabled / requiresApproval / notFound / notRegistered
    var loginItemStatus: SMAppService.Status? {
        loginItemAvailable ? SMAppService.mainApp.status : nil
    }

    /// 最近一次切换登录项失败的原因（nil 表示没有错误）
    @Published var loginItemError: String?

    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled }
        set {
            guard loginItemAvailable else { return }
            loginItemError = nil
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                loginItemError = error.localizedDescription
                NSLog("登录项切换失败: \(error.localizedDescription)")
            }
            // register() 后可能进入 .requiresApproval；launchAtLogin 是计算属性，
            // 需要手动通知 SwiftUI 重新读取状态与错误信息。
            objectWillChange.send()
        }
    }

    /// 打开系统设置的「登录项」页面（用于需要用户批准时引导）
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// 重新读取登录项状态：从系统设置批准/拒绝后返回 App 时刷新 UI。
    func refreshLoginItemState() {
        if loginItemStatus == .enabled || loginItemStatus == .requiresApproval,
           loginItemError != nil {
            loginItemError = nil   // @Published 会自动通知 SwiftUI
        } else {
            objectWillChange.send()
        }
    }

    // MARK: - 版本信息（SPM 裸跑无 Info.plist 时回退到开发版本 1.0）

    var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }

    /// 主题对应的窗口外观；只应用到本 App 自己的窗口。
    /// 不要赋给 `NSApp.appearance`：macOS 会把前台 App 的外观套到整条菜单栏上，
    /// 选「浅色」时整个菜单栏会变灰，状态项文字也可能因此看不见。
    var appAppearance: NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    var isChinese: Bool {
        switch language {
        case .chinese: return true
        case .english: return false
        case .system:
            return (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
        }
    }

    /// 当前语言下的文案
    var strings: L { L(isChinese: isChinese) }

    /// 所有可选字体族（去掉隐藏字体/“System Font”；系统默认单独作为 nil 选项）
    static let availableFontFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") && $0 != "System Font" }
        .sorted()
}

struct Preset: Identifiable {
    let id = UUID()
    let nameZh: String
    let nameEn: String
    let textZh: String
    let textEn: String
    let prefix: String
    let suffix: String

    func name(_ isChinese: Bool) -> String { isChinese ? nameZh : nameEn }
    func text(_ isChinese: Bool) -> String { isChinese ? textZh : textEn }

    static let all: [Preset] = [
        .init(nameZh: "Aloha!",
              nameEn: "Aloha!",
              textZh: "Aloha!",
              textEn: "Aloha!",
              prefix: "[", suffix: "]"),
        .init(nameZh: "Ciallo～(∠・ω< )⌒★",
              nameEn: "Ciallo～(∠・ω< )⌒★",
              textZh: "Ciallo～(∠・ω< )⌒★",
              textEn: "Ciallo～(∠・ω< )⌒★",
              prefix: "", suffix: ""),
        .init(nameZh: "时间占位",
              nameEn: "Time Placeholder",
              textZh: "♥",
              textEn: "♥",
              prefix: "", suffix: ""),
        .init(nameZh: "工作中…",
              nameEn: "Working…",
              textZh: "工作中…",
              textEn: "Working…",
              prefix: "⦿ ", suffix: ""),
        .init(nameZh: "免打扰",
              nameEn: "Do Not Disturb",
              textZh: "请勿打扰",
              textEn: "Do Not Disturb",
              prefix: "🔕 ", suffix: ""),
        .init(nameZh: "Coffee",
              nameEn: "Coffee",
              textZh: "Coffee",
              textEn: "Coffee",
              prefix: "☕️ ", suffix: ""),
        .init(nameZh: "日期",
              nameEn: "Date",
              textZh: "",
              textEn: "",
              prefix: "「", suffix: "」"),
    ]
}

// MARK: - 轮播模型

enum RotationInterval: String, CaseIterable, Identifiable, Codable {
    case thirtySeconds, oneMinute, fiveMinutes, oneHour

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .thirtySeconds: return 30
        case .oneMinute:     return 60
        case .fiveMinutes:   return 300
        case .oneHour:       return 3600
        }
    }

    func label(_ isChinese: Bool) -> String {
        switch self {
        case .thirtySeconds: return isChinese ? "30 秒" : "30s"
        case .oneMinute:     return isChinese ? "1 分钟" : "1m"
        case .fiveMinutes:   return isChinese ? "5 分钟" : "5m"
        case .oneHour:       return isChinese ? "1 小时" : "1h"
        }
    }
}

enum RotationOrder: String, CaseIterable, Identifiable, Codable {
    case sequential, random

    var id: String { rawValue }
}

struct RotationItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
