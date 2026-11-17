import Foundation
import AppKit
import ServiceManagement

/// 一个颜色条目：稳定 id（用于 SwiftUI 列表身份）+ 颜色 hex
struct ColorEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var hex: String
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var text: String {
        didSet {
            UserDefaults.standard.set(text, forKey: "text")
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
            onDisplayChange?()
        }
    }
    @Published var prefix: String {
        didSet { UserDefaults.standard.set(prefix, forKey: "prefix"); onDisplayChange?() }
    }
    @Published var suffix: String {
        didSet { UserDefaults.standard.set(suffix, forKey: "suffix"); onDisplayChange?() }
    }
    @Published var trackHistory: Bool {
        didSet { UserDefaults.standard.set(trackHistory, forKey: "trackHistory") }
    }
    @Published var maxWidth: Double {
        didSet { UserDefaults.standard.set(maxWidth, forKey: "maxWidth"); onDisplayChange?() }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize"); onDisplayChange?() }
    }
    @Published var bold: Bool {
        didSet { UserDefaults.standard.set(bold, forKey: "bold"); onDisplayChange?() }
    }
    /// 自定义字体族；nil = 系统默认
    @Published var fontFamily: String? {
        didSet {
            if let fontFamily {
                UserDefaults.standard.set(fontFamily, forKey: "fontFamily")
            } else {
                UserDefaults.standard.removeObject(forKey: "fontFamily")
            }
            onDisplayChange?()
        }
    }
    /// 每个字符一个颜色，不足时循环使用
    @Published var colorEntries: [ColorEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(colorEntries) {
                UserDefaults.standard.set(data, forKey: "colorEntries")
            }
            onDisplayChange?()
        }
    }
    /// 自适应菜单栏：开启后按菜单栏深浅自动切换两套颜色
    @Published var adaptiveColors: Bool {
        didSet { UserDefaults.standard.set(adaptiveColors, forKey: "adaptiveColors"); onDisplayChange?() }
    }
    /// 浅色菜单栏（深色壁纸）下使用的颜色
    @Published var lightBarColorEntries: [ColorEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(lightBarColorEntries) {
                UserDefaults.standard.set(data, forKey: "lightBarColorEntries")
            }
            onDisplayChange?()
        }
    }
    /// 深色菜单栏（浅色壁纸）下使用的颜色
    @Published var darkBarColorEntries: [ColorEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(darkBarColorEntries) {
                UserDefaults.standard.set(data, forKey: "darkBarColorEntries")
            }
            onDisplayChange?()
        }
    }
    @Published var history: [String] {
        didSet { UserDefaults.standard.set(history, forKey: "history") }
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

    // MARK: - 轮播

    @Published var rotationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rotationEnabled, forKey: "rotationEnabled")
            if rotationPaused {
                rotationPaused = false   // 切换启用状态时清除暂停
            }
            onRotationSettingsChange?()
        }
    }
    @Published var rotationPaused: Bool {
        didSet {
            UserDefaults.standard.set(rotationPaused, forKey: "rotationPaused")
            onRotationSettingsChange?()
        }
    }
    @Published var rotationInterval: RotationInterval {
        didSet {
            UserDefaults.standard.set(rotationInterval.rawValue, forKey: "rotationInterval")
            onRotationSettingsChange?()
        }
    }
    @Published var rotationOrder: RotationOrder {
        didSet {
            UserDefaults.standard.set(rotationOrder.rawValue, forKey: "rotationOrder")
            onRotationSettingsChange?()
        }
    }
    @Published var rotationItems: [RotationItem] {
        didSet {
            if let data = try? JSONEncoder().encode(rotationItems) {
                UserDefaults.standard.set(data, forKey: "rotationItems")
            }
            onRotationSettingsChange?()
        }
    }

    /// 设置页输入框实时编辑时置位：更新当前文字但不写历史，避免逐字污染历史。
    private var suppressHistory = false

    /// 实时编辑当前文字（不记入历史）。用于设置页输入框逐字输入。
    func setTextLive(_ value: String) {
        suppressHistory = true
        text = value
        suppressHistory = false
    }

    /// 设置页「内容」输入框开始编辑时记录基线。
    private var textEditBaseline: String?

    /// 设置页正文输入框是否正在编辑：轮播定时器据此跳过，避免打断输入。
    private(set) var isEditingText = false

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

    /// 删除某一条历史。
    func removeHistory(_ value: String) {
        history.removeAll { $0 == value }
    }

    private init() {
        let d = UserDefaults.standard
        let currentText = d.string(forKey: "text") ?? "Aloha!"
        text = currentText
        prefix = d.string(forKey: "prefix") ?? "["
        suffix = d.string(forKey: "suffix") ?? "]"
        trackHistory = d.object(forKey: "trackHistory") as? Bool ?? true
        maxWidth = d.object(forKey: "maxWidth") as? Double ?? 200
        // 菜单栏高度约 24pt，字号上限压到 21，避免上下被裁切；同时兜底旧数据中的越界值。
        fontSize = min(max(d.object(forKey: "fontSize") as? Double ?? 13, 9), 21)
        bold = d.object(forKey: "bold") as? Bool ?? true
        // 字体族：只接受当前系统仍可用的字体，否则回退系统默认
        let storedFamily = d.string(forKey: "fontFamily")
        fontFamily = storedFamily.flatMap { Self.availableFontFamilies.contains($0) ? $0 : nil }
        if let data = d.data(forKey: "colorEntries"),
           let decoded = try? JSONDecoder().decode([ColorEntry].self, from: data),
           !decoded.isEmpty {
            colorEntries = decoded
        } else {
            // 兼容旧版本存的 [String]
            let legacy = d.stringArray(forKey: "colors") ?? ["#FFFFFF"]
            colorEntries = legacy.map { ColorEntry(hex: $0) }
        }
        // 历史：过滤当前值/空值，去重并截断到 10 条，避免旧数据产生重复 ID 或超长列表
        var cleanedHistory: [String] = []
        for item in d.stringArray(forKey: "history") ?? []
        where item != currentText && !item.isEmpty {
            if !cleanedHistory.contains(item) { cleanedHistory.append(item) }
        }
        history = Array(cleanedHistory.prefix(10))
        adaptiveColors = d.object(forKey: "adaptiveColors") as? Bool ?? false
        func loadEntries(_ key: String, fallback: [ColorEntry]) -> [ColorEntry] {
            guard let data = d.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ColorEntry].self, from: data),
                  !decoded.isEmpty else { return fallback }
            return decoded
        }
        lightBarColorEntries = loadEntries("lightBarColorEntries", fallback: [ColorEntry(hex: "#000000")])
        darkBarColorEntries = loadEntries("darkBarColorEntries", fallback: [ColorEntry(hex: "#FFFFFF")])
        appearance = AppAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: d.string(forKey: "appLanguage") ?? "") ?? .system

        rotationEnabled = d.object(forKey: "rotationEnabled") as? Bool ?? false
        rotationPaused = d.object(forKey: "rotationPaused") as? Bool ?? false
        rotationInterval = RotationInterval(rawValue: d.string(forKey: "rotationInterval") ?? "") ?? .oneMinute
        rotationOrder = RotationOrder(rawValue: d.string(forKey: "rotationOrder") ?? "") ?? .sequential
        if let data = d.data(forKey: "rotationItems"),
           let decoded = try? JSONDecoder().decode([RotationItem].self, from: data) {
            rotationItems = decoded
        } else {
            rotationItems = []
        }
    }

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

    /// 主题外观变化时的回调（由 StatusBarController 设置，用于更新已打开的窗口）
    var onAppearanceChange: (() -> Void)?

    /// 轮播配置变化时的回调（由 RotationController 设置）
    var onRotationSettingsChange: (() -> Void)?

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

    var displayText: String { prefix + text + suffix }

    /// 所有可选字体族（去掉隐藏字体/“System Font”；系统默认单独作为 nil 选项）
    static let availableFontFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") && $0 != "System Font" }
        .sorted()

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

    var nsColors: [NSColor] {
        colorEntries.compactMap { NSColor(hex: $0.hex) }
    }

    /// 菜单栏当前是否为深色（浅色壁纸下系统会把菜单栏压暗）。
    /// 用 @Published 让设置页的颜色预览能随菜单栏深浅变化实时刷新；
    /// 赋值处需先判等，避免每次刷新标题都触发无意义的 SwiftUI 重绘。
    @Published var menuBarIsDark = false

    /// 显示内容变化时的回调（由 StatusBarController 设置）
    var onDisplayChange: (() -> Void)?

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

enum RotationInterval: String, CaseIterable, Identifiable {
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

enum RotationOrder: String, CaseIterable, Identifiable {
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
