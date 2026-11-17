import Foundation
import AppKit
import ServiceManagement

/// 一个颜色条目：稳定 id（用于 SwiftUI 列表身份）+ 颜色 hex
struct ColorEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var hex: String
}

extension ColorEntry {
    /// 缺失 id/hex 时使用默认值，避免旧/新备份因单个字段导致整组颜色丢失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        hex = (try? c.decode(String.self, forKey: .hex)) ?? "#FFFFFF"
    }
}

/// 一条历史记录：文字 + 当时的前缀/后缀，可收藏置顶。
struct HistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var prefix: String = ""
    var suffix: String = ""
    var isPinned: Bool = false

    var displayValue: String { prefix + text + suffix }
}

extension HistoryEntry {
    /// 缺失字段时使用默认值，避免单条历史数据损坏影响整个块。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        prefix = (try? c.decode(String.self, forKey: .prefix)) ?? ""
        suffix = (try? c.decode(String.self, forKey: .suffix)) ?? ""
        isPinned = (try? c.decode(Bool.self, forKey: .isPinned)) ?? false
    }
}

/// 字重：字族支持多少档就选最近的可用字面。
enum FontWeight: String, CaseIterable, Identifiable, Codable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    var id: String { rawValue }

    /// NSFontManager 的 weight 参数范围 0...15
    var managerWeight: Int {
        switch self {
        case .ultraLight: return 0
        case .thin:       return 1
        case .light:      return 2
        case .regular:    return 5
        case .medium:     return 6
        case .semibold:   return 7
        case .bold:       return 9
        case .heavy:      return 11
        case .black:      return 15
        }
    }

    var nsWeight: NSFont.Weight {
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

    /// 旧版本只有 bold 布尔值：导出时用它保持旧版本可读。
    var isBoldLike: Bool {
        switch self {
        case .semibold, .bold, .heavy, .black: return true
        default: return false
        }
    }

    func label(_ isChinese: Bool) -> String {
        switch self {
        case .ultraLight: return isChinese ? "超细" : "Ultra Light"
        case .thin:       return isChinese ? "纤细" : "Thin"
        case .light:      return isChinese ? "细体" : "Light"
        case .regular:    return isChinese ? "常规" : "Regular"
        case .medium:     return isChinese ? "中等" : "Medium"
        case .semibold:   return isChinese ? "半粗" : "Semibold"
        case .bold:       return isChinese ? "粗体" : "Bold"
        case .heavy:      return isChinese ? "特粗" : "Heavy"
        case .black:      return isChinese ? "极粗" : "Black"
        }
    }
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
    var fontWeight: FontWeight
    var tracking: Double
    var fontFamily: String?
    var colorEntries: [ColorEntry]
    var adaptiveColors: Bool
    var lightBarColorEntries: [ColorEntry]
    var darkBarColorEntries: [ColorEntry]
    var history: [HistoryEntry]
    var historyLimit: Int
    var rotationEnabled: Bool
    var rotationPaused: Bool
    var rotationInterval: RotationInterval
    var rotationOrder: RotationOrder
    var rotationItems: [RotationItem]
    /// 动态日期时间：菜单栏按 datePattern 显示当前日期/时间
    var dateEnabled: Bool
    /// Unicode TR35 日期格式（例如 MM-dd[EEE]HH:mm）
    var datePattern: String
    /// 左键点击该块时打开系统日历
    var calendarOnLeftClick: Bool

    static let defaultDatePattern = "MM-dd[EEE]HH:mm"

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
            fontWeight: .bold,
            tracking: 0,
            fontFamily: nil,
            colorEntries: [ColorEntry(hex: "#FFFFFF")],
            adaptiveColors: false,
            lightBarColorEntries: [ColorEntry(hex: "#000000")],
            darkBarColorEntries: [ColorEntry(hex: "#FFFFFF")],
            history: [],
            historyLimit: 10,
            rotationEnabled: false,
            rotationPaused: false,
            rotationInterval: .oneMinute,
            rotationOrder: .sequential,
            rotationItems: [],
            dateEnabled: false,
            datePattern: defaultDatePattern,
            calendarOnLeftClick: false)
    }
}

extension BlockSnapshot {
    /// 兼容旧/新版本的块数据：
    /// - 缺失字段使用默认值（旧版本备份）
    /// - 未知字段自动忽略（新版本备份）
    /// - 类型异常只影响对应字段，不会让整个备份失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        autosaveName = (try? c.decode(String.self, forKey: .autosaveName)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        let decodedPrefix = (try? c.decode(String.self, forKey: .prefix)) ?? ""
        let decodedSuffix = (try? c.decode(String.self, forKey: .suffix)) ?? ""
        prefix = decodedPrefix
        suffix = decodedSuffix
        trackHistory = (try? c.decode(Bool.self, forKey: .trackHistory)) ?? true
        maxWidth = (try? c.decode(Double.self, forKey: .maxWidth)) ?? 200
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? 13
        let legacyBold = (try? c.decode(Bool.self, forKey: .bold)) ?? true
        bold = legacyBold
        fontWeight = (try? c.decode(FontWeight.self, forKey: .fontWeight))
            ?? (legacyBold ? .bold : .regular)
        tracking = (try? c.decode(Double.self, forKey: .tracking)) ?? 0
        fontFamily = try? c.decode(String.self, forKey: .fontFamily)
        colorEntries = (try? c.decode([ColorEntry].self, forKey: .colorEntries))
            ?? [ColorEntry(hex: "#FFFFFF")]
        adaptiveColors = (try? c.decode(Bool.self, forKey: .adaptiveColors)) ?? false
        lightBarColorEntries = (try? c.decode([ColorEntry].self, forKey: .lightBarColorEntries))
            ?? [ColorEntry(hex: "#000000")]
        darkBarColorEntries = (try? c.decode([ColorEntry].self, forKey: .darkBarColorEntries))
            ?? [ColorEntry(hex: "#FFFFFF")]
        // 旧版本历史是 [String]；新版本是 [HistoryEntry]（含前缀/后缀/收藏状态）。
        if let legacyHistory = try? c.decode([String].self, forKey: .history) {
            history = legacyHistory.map {
                HistoryEntry(text: $0, prefix: decodedPrefix, suffix: decodedSuffix)
            }
        } else {
            history = (try? c.decode([HistoryEntry].self, forKey: .history)) ?? []
        }
        historyLimit = (try? c.decode(Int.self, forKey: .historyLimit)) ?? 10
        rotationEnabled = (try? c.decode(Bool.self, forKey: .rotationEnabled)) ?? false
        rotationPaused = (try? c.decode(Bool.self, forKey: .rotationPaused)) ?? false
        rotationInterval = (try? c.decode(RotationInterval.self, forKey: .rotationInterval))
            ?? .oneMinute
        rotationOrder = (try? c.decode(RotationOrder.self, forKey: .rotationOrder)) ?? .sequential
        rotationItems = (try? c.decode([RotationItem].self, forKey: .rotationItems)) ?? []
        dateEnabled = (try? c.decode(Bool.self, forKey: .dateEnabled)) ?? false
        datePattern = (try? c.decode(String.self, forKey: .datePattern))
            ?? BlockSnapshot.defaultDatePattern
        calendarOnLeftClick = (try? c.decode(Bool.self, forKey: .calendarOnLeftClick)) ?? false
    }
}

/// 单个菜单栏块：文字、样式、颜色、轮播与历史都相互独立。
@MainActor
final class BlockSettings: ObservableObject, Identifiable {
    enum Change {
        case display    // 需要刷新菜单栏标题
        case rotation   // 需要重排轮播定时器
        case date       // 动态日期时间开关变化（启停时钟定时器）
        case persist    // 只需落盘（例如历史列表变化）
    }

    let id: UUID
    let autosaveName: String

    var onChange: ((Change) -> Void)?

    @Published var text: String {
        didSet {
            // 当前值永远不出现在历史列表里；收藏项保留在底层（当前值时由 displayHistory 隐藏）。
            // 实时编辑（suppressHistory）也要执行这一步，只是不把被替换掉的旧值新增进历史。
            history.removeAll { !$0.isPinned && $0.text == text }
            if !suppressHistory {
                // 被替换掉的旧值进入历史（“切换”语义），同时保存当时的前缀/后缀
                if trackHistory, !oldValue.isEmpty, oldValue != text {
                    addHistoryEntry(text: oldValue, prefix: prefix, suffix: suffix)
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
    /// 字重（9 档）；旧版本 bold 布尔值会迁移到这里。
    @Published var fontWeight: FontWeight { didSet { onChange?(.display) } }
    /// 字距（points），应用到菜单栏和预览。
    @Published var tracking: Double { didSet { onChange?(.display) } }
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
    @Published var history: [HistoryEntry] { didSet { onChange?(.persist) } }
    /// 历史保留条数（只统计非收藏记录）；收藏项不会被自动清理。
    @Published var historyLimit: Int {
        didSet {
            let clamped = min(max(historyLimit, 1), 100)
            if clamped != historyLimit {
                historyLimit = clamped
                return
            }
            trimHistory()
            onChange?(.persist)
        }
    }

    // MARK: - 动态日期时间

    /// 开启后菜单栏显示按 `datePattern` 格式化的当前日期/时间。
    @Published var dateEnabled: Bool {
        didSet {
            rebuildDateFormatter()
            onChange?(.date)
        }
    }
    /// Unicode TR35 日期格式，例如 MM-dd[EEE]HH:mm；空值使用默认格式。
    @Published var datePattern: String {
        didSet {
            rebuildDateFormatter()
            onChange?(.display)
        }
    }
    /// 左键点击该块时打开系统日历（右键改为打开应用菜单，保证菜单入口仍在）。
    @Published var calendarOnLeftClick: Bool { didSet { onChange?(.persist) } }

    /// DateFormatter 的创建成本较高，按块缓存；pattern 变化时重建。
    private var dateFormatter: DateFormatter?

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

    /// 设置页「内容」输入框开始编辑时记录基线（连同时的前后缀）。
    private var textEditBaseline: HistoryEntry?

    /// 设置页正文输入框是否正在编辑：轮播定时器据此跳过，避免打断输入。
    private(set) var isEditingText = false

    init(snapshot: BlockSnapshot) {
        id = snapshot.id
        autosaveName = snapshot.autosaveName.isEmpty
            ? "SwiftQuoteStatusItem-\(snapshot.id.uuidString)"
            : snapshot.autosaveName
        text = snapshot.text
        prefix = snapshot.prefix
        suffix = snapshot.suffix
        trackHistory = snapshot.trackHistory
        maxWidth = snapshot.maxWidth.isFinite
            ? min(max(snapshot.maxWidth, 40), 400)
            : 200
        // 菜单栏高度约 24pt，字号上限压到 21，避免上下被裁切；同时兜底旧数据中的越界值。
        fontSize = snapshot.fontSize.isFinite
            ? min(max(snapshot.fontSize, 9), 21)
            : 13
        fontWeight = snapshot.fontWeight
        tracking = snapshot.tracking.isFinite
            ? min(max(snapshot.tracking, -2), 5)
            : 0
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
        historyLimit = min(max(snapshot.historyLimit, 1), 100)
        // 历史：过滤空值/当前值（收藏项除外），同文字去重（收藏优先）
        var cleanedHistory: [HistoryEntry] = []
        var seenHistoryIDs = Set<UUID>()
        for var entry in snapshot.history where !entry.text.isEmpty {
            if seenHistoryIDs.contains(entry.id) { entry.id = UUID() }
            seenHistoryIDs.insert(entry.id)
            if entry.text == snapshot.text && !entry.isPinned { continue }
            if let index = cleanedHistory.firstIndex(where: { $0.text == entry.text }) {
                if entry.isPinned && !cleanedHistory[index].isPinned {
                    cleanedHistory[index] = entry
                }
            } else {
                cleanedHistory.append(entry)
            }
        }
        history = cleanedHistory
        rotationEnabled = snapshot.rotationEnabled
        rotationPaused = snapshot.rotationPaused
        rotationInterval = snapshot.rotationInterval
        rotationOrder = snapshot.rotationOrder
        rotationItems = snapshot.rotationItems
        dateEnabled = snapshot.dateEnabled
        datePattern = snapshot.datePattern
        calendarOnLeftClick = snapshot.calendarOnLeftClick
        trimHistory()
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
            bold: fontWeight.isBoldLike,
            fontWeight: fontWeight,
            tracking: tracking,
            fontFamily: fontFamily,
            colorEntries: colorEntries,
            adaptiveColors: adaptiveColors,
            lightBarColorEntries: lightBarColorEntries,
            darkBarColorEntries: darkBarColorEntries,
            history: history,
            historyLimit: historyLimit,
            rotationEnabled: rotationEnabled,
            rotationPaused: rotationPaused,
            rotationInterval: rotationInterval,
            rotationOrder: rotationOrder,
            rotationItems: rotationItems,
            dateEnabled: dateEnabled,
            datePattern: datePattern,
            calendarOnLeftClick: calendarOnLeftClick)
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
        textEditBaseline = HistoryEntry(text: text, prefix: prefix, suffix: suffix)
    }

    /// 输入框失焦 / 设置窗口关闭时，把“开始编辑前的当前值”补记一次历史。
    /// 逐字输入期间仍不写历史，避免半截输入污染列表。
    func endTextEditing() {
        isEditingText = false
        guard let baseline = textEditBaseline else { return }
        textEditBaseline = nil
        guard !suppressHistory, trackHistory,
              !baseline.text.isEmpty, baseline.text != text else { return }
        addHistoryEntry(text: baseline.text, prefix: baseline.prefix, suffix: baseline.suffix)
    }

    /// 用于展示的历史列表：始终排除当前值（收藏项也会暂时隐藏）。
    var displayHistory: [HistoryEntry] { history.filter { $0.text != text } }

    /// 删除某一条历史。
    func removeHistory(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
    }

    /// 应用一条历史：恢复文字、前缀和后缀。
    func applyHistory(_ entry: HistoryEntry) {
        guard entry.text != text || entry.prefix != prefix || entry.suffix != suffix else { return }

        let oldText = text
        let oldPrefix = prefix
        let oldSuffix = suffix

        // 一次性切换，避免旧值被重复记入历史
        suppressHistory = true
        prefix = entry.prefix
        suffix = entry.suffix
        text = entry.text
        suppressHistory = false

        // 应用后该条成为当前值：未收藏的同文字条目已由 text didSet 移除；收藏项保留但从列表隐藏。
        if trackHistory, !oldText.isEmpty, oldText != entry.text {
            addHistoryEntry(text: oldText, prefix: oldPrefix, suffix: oldSuffix)
        }
        trimHistory()
    }

    /// 收藏 / 取消收藏。收藏项固定在列表最前，且不会被自动清理。
    func togglePinned(_ entry: HistoryEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = history[index]
        updated.isPinned.toggle()
        history.remove(at: index)
        if updated.isPinned {
            history.insert(updated, at: 0)
        } else {
            let insertIndex = history.firstIndex(where: { !$0.isPinned }) ?? history.count
            history.insert(updated, at: insertIndex)
        }
        trimHistory()
    }

    /// 插入一条历史（自动去重：收藏项优先保留）。
    private func addHistoryEntry(text: String, prefix: String, suffix: String) {
        guard !text.isEmpty, text != self.text else { return }
        // 已有同文字的收藏项时保留收藏项（连同其保存的前后缀）
        if history.contains(where: { $0.isPinned && $0.text == text }) { return }
        history.removeAll { !$0.isPinned && $0.text == text }
        let entry = HistoryEntry(text: text, prefix: prefix, suffix: suffix)
        // 收藏项永远在最前，新记录插到第一条非收藏记录之前
        let insertIndex = history.firstIndex(where: { !$0.isPinned }) ?? history.count
        history.insert(entry, at: insertIndex)
        trimHistory()
    }

    /// 按条数上限清理：收藏项全保留且不占名额，非收藏项保留最新的若干条。
    private func trimHistory() {
        let pinned = history.filter(\.isPinned)
        let unpinned = history.filter { !$0.isPinned }
        let kept = pinned + unpinned.prefix(historyLimit)
        if kept != history { history = kept }
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

    /// 按 DateFormatter（Unicode TR35）格式化当前时间。
    func dateText(at date: Date) -> String {
        let formatter: DateFormatter
        if let cached = dateFormatter,
           cached.locale == Locale.current,
           cached.timeZone == TimeZone.current,
           cached.calendar == Calendar.current {
            formatter = cached
        } else {
            // 系统时区/语言可能在运行中变化；直接重建，避免 Locale 变更重置 dateFormat。
            rebuildDateFormatter()
            formatter = dateFormatter ?? DateFormatter()
        }
        return formatter.string(from: date)
    }

    var dateText: String { dateText(at: Date()) }

    func displayText(at date: Date) -> String {
        prefix + (dateEnabled ? dateText(at: date) : text) + suffix
    }

    var displayText: String { displayText(at: Date()) }

    /// 用于设置页块列表/菜单标题的简短标签。
    func label(_ isChinese: Bool) -> String {
        if dateEnabled {
            let pattern = datePattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return pattern.isEmpty ? (isChinese ? "日期时间" : "Date & Time") : pattern
        }
        let value = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (isChinese ? "空块" : "Empty Block") : value
    }

    private func rebuildDateFormatter() {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = .current
        formatter.timeZone = .current
        let pattern = datePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        formatter.dateFormat = pattern.isEmpty ? BlockSnapshot.defaultDatePattern : datePattern
        dateFormatter = formatter
    }

    /// 按当前字体族/字重/字号解析实际字体；字体不可用时回退系统字体。
    func resolvedFont(size: CGFloat) -> NSFont {
        if let fontFamily {
            if let custom = NSFontManager.shared.font(withFamily: fontFamily,
                                                      traits: [],
                                                      weight: fontWeight.managerWeight,
                                                      size: size) {
                return custom
            }
            // 该字族没有请求的字重时，退回同族常规字重
            if let regular = NSFontManager.shared.font(withFamily: fontFamily,
                                                       traits: [],
                                                       weight: 5,
                                                       size: size) {
                return regular
            }
        }
        return .systemFont(ofSize: size, weight: fontWeight.nsWeight)
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

/// 解析后的备份预览：确认后再应用到 AppSettings。
struct BackupPreview {
    let blocks: [BlockSnapshot]
    let appearance: AppAppearance?
    let language: AppLanguage?
    let launchAtLogin: Bool?
    let selectedBlockID: UUID?
    let schemaVersion: Int
    let droppedBlocks: Int
}

/// 导入结果（用于 UI 反馈）。
struct BackupImportResult {
    let importedBlocks: Int
    let droppedBlocks: Int
    let schemaVersion: Int
}

enum BackupError: Error {
    /// JSON 结构无法识别
    case invalidFile
    /// 文件里没有任何可用的块
    case noValidBlocks
}

/// 导出文档。字段只增不减；读取端对缺失/未知字段都做了兼容。
private struct BackupExportDocument: Encodable {
    let format = "SwiftQuoteSettings"
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String
    let exportedAt: String
    let settings: Payload

    struct Payload: Encodable {
        let appearance: String
        let language: String
        let launchAtLogin: Bool?
        let selectedBlockID: String?
        let blocks: [BlockSnapshot]
    }
}

/// 全局设置 + 所有菜单栏块。每个块在菜单栏有独立的 NSStatusItem。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// 设置/备份数据结构版本。修改备份结构时递增，并在 decodeBackup 中做迁移。
    /// v2: history 从 [String] 升级为 [HistoryEntry]（文字 + 前后缀 + 收藏），新增 historyLimit。
    /// v3: 新增 fontWeight（9 档）与 tracking（字距），bold 保留用于旧版本兼容。
    static let dataVersion = 3

    /// 恢复默认时需要清理的 UserDefaults 键。
    private static let managedDefaultsKeys = [
        "blocks", "selectedBlockID", "settingsDataVersion",
        "appearance", "appLanguage",
        "text", "prefix", "suffix", "trackHistory", "maxWidth", "fontSize", "bold",
        "fontFamily", "colorEntries", "colors", "history",
        "adaptiveColors", "lightBarColorEntries", "darkBarColorEntries",
        "rotationEnabled", "rotationPaused", "rotationInterval", "rotationOrder",
        "rotationItems",
    ]

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
        case .date:
            // 日期模式切换会同时影响标题、时钟定时器和轮播（日期模式下不轮播）
            onDisplayChange?(block)
            onDateChange?(block)
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
            return sanitize(decoded)
        }
        return [legacySnapshot(d)]
    }

    /// 兜底损坏/重复数据：ID 与 autosaveName 都必须唯一。
    private static func sanitize(_ snapshots: [BlockSnapshot]) -> [BlockSnapshot] {
        var seenIDs = Set<UUID>()
        var seenNames = Set<String>()
        return snapshots.map { snapshot in
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

        var cleanedHistory: [HistoryEntry] = []
        let legacyPrefix = d.string(forKey: "prefix") ?? "["
        let legacySuffix = d.string(forKey: "suffix") ?? "]"
        for item in d.stringArray(forKey: "history") ?? []
        where item != currentText && !item.isEmpty {
            if !cleanedHistory.contains(where: { $0.text == item }) {
                cleanedHistory.append(HistoryEntry(text: item,
                                                   prefix: legacyPrefix,
                                                   suffix: legacySuffix))
            }
        }

        let rotationItems: [RotationItem]
        if let data = d.data(forKey: "rotationItems"),
           let decoded = try? JSONDecoder().decode([RotationItem].self, from: data) {
            rotationItems = decoded
        } else {
            rotationItems = []
        }

        let legacyBold = d.object(forKey: "bold") as? Bool ?? true

        return BlockSnapshot(
            id: UUID(),
            autosaveName: "SwiftQuoteStatusItem",   // 保留旧版菜单栏位置
            text: currentText,
            prefix: legacyPrefix,
            suffix: legacySuffix,
            trackHistory: d.object(forKey: "trackHistory") as? Bool ?? true,
            maxWidth: d.object(forKey: "maxWidth") as? Double ?? 200,
            fontSize: d.object(forKey: "fontSize") as? Double ?? 13,
            bold: legacyBold,
            fontWeight: legacyBold ? .bold : .regular,
            tracking: 0,
            fontFamily: family,
            colorEntries: colors,
            adaptiveColors: d.object(forKey: "adaptiveColors") as? Bool ?? false,
            lightBarColorEntries: loadEntries("lightBarColorEntries",
                                              fallback: [ColorEntry(hex: "#000000")]),
            darkBarColorEntries: loadEntries("darkBarColorEntries",
                                             fallback: [ColorEntry(hex: "#FFFFFF")]),
            history: Array(cleanedHistory.prefix(10)),
            historyLimit: 10,
            rotationEnabled: d.object(forKey: "rotationEnabled") as? Bool ?? false,
            rotationPaused: d.object(forKey: "rotationPaused") as? Bool ?? false,
            rotationInterval: RotationInterval(rawValue: d.string(forKey: "rotationInterval") ?? "")
                ?? .oneMinute,
            rotationOrder: RotationOrder(rawValue: d.string(forKey: "rotationOrder") ?? "")
                ?? .sequential,
            rotationItems: rotationItems,
            dateEnabled: false,
            datePattern: BlockSnapshot.defaultDatePattern,
            calendarOnLeftClick: false)
    }

    private func persistBlocks() {
        if let data = try? JSONEncoder().encode(blocks.map(\.snapshot)) {
            UserDefaults.standard.set(data, forKey: "blocks")
        }
        UserDefaults.standard.set(selectedBlockID.uuidString, forKey: "selectedBlockID")
        UserDefaults.standard.set(Self.dataVersion, forKey: "settingsDataVersion")
    }

    /// 补记所有块可能仍在编辑中的正文（endTextEditing 幂等）。
    func endTextEditing() {
        for block in blocks { block.endTextEditing() }
    }

    // MARK: - 备份与恢复

    /// 导出当前所有设置（JSON）。未知字段可由未来版本忽略，缺失字段由读取端补默认值。
    func exportBackupData() throws -> Data {
        let document = BackupExportDocument(
            schemaVersion: Self.dataVersion,
            appVersion: versionString,
            appBuild: buildString,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            settings: .init(
                appearance: appearance.rawValue,
                language: language.rawValue,
                launchAtLogin: loginItemAvailable ? launchAtLogin : nil,
                selectedBlockID: selectedBlockID.uuidString,
                blocks: blocks.map(\.snapshot)))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// 解析备份但不应用；UI 可先展示块数量、数据版本和丢弃数量供用户确认。
    func decodeBackup(_ data: Data) throws -> BackupPreview {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw BackupError.invalidFile
        }

        var schemaVersion = 0
        var payload: [String: Any]?
        var blockItems: [Any]?

        if let dict = root as? [String: Any] {
            if let format = dict["format"] as? String,
               !format.isEmpty,
               format != "SwiftQuoteSettings" {
                throw BackupError.invalidFile
            }
            schemaVersion = Self.intValue(dict["schemaVersion"]) ?? 0
            if let settingsDict = dict["settings"] as? [String: Any] {
                payload = settingsDict
            } else if dict["blocks"] is [Any] {
                payload = dict
            }
            blockItems = dict["blocks"] as? [Any]
        } else if let array = root as? [Any] {
            // 兼容直接导出的 blocks 数组
            blockItems = array
        }

        // v1 -> v2：历史项由字符串升级为对象；BlockSnapshot 同时接受两种格式。
        // v2 -> v3：新增 fontWeight/tracking；缺失时由旧 bold 推导，tracking 默认 0。
        // 未来新增字段时，在此按 schemaVersion 做必要迁移。
        // BlockSnapshot 对缺失字段使用默认值、对未知字段自动忽略，因此大多数升级无需额外迁移。

        if let payload {
            if blockItems == nil {
                blockItems = payload["blocks"] as? [Any]
            }
            if schemaVersion == 0 {
                schemaVersion = Self.intValue(payload["schemaVersion"]) ?? 0
            }
        }

        guard let blockItems, !blockItems.isEmpty else { throw BackupError.noValidBlocks }

        var blocks: [BlockSnapshot] = []
        var droppedBlocks = 0
        for item in blockItems {
            // 只接受至少包含一个已知内容字段的对象；未来完全改版、无法识别的块直接丢弃，
            // 避免生成一堆空白块。
            guard let dict = item as? [String: Any],
                  Self.hasRecognizedBlockContent(dict),
                  JSONSerialization.isValidJSONObject(item),
                  let itemData = try? JSONSerialization.data(withJSONObject: item),
                  let snapshot = try? JSONDecoder().decode(BlockSnapshot.self, from: itemData) else {
                droppedBlocks += 1
                continue
            }
            blocks.append(snapshot)
        }
        guard !blocks.isEmpty else { throw BackupError.noValidBlocks }

        let meta = payload ?? (root as? [String: Any])
        let appearanceValue = meta?["appearance"] as? String
        let languageValue = meta?["language"] as? String
        let launchValue = meta?["launchAtLogin"] as? Bool
        let selectedValue = meta?["selectedBlockID"] as? String

        return BackupPreview(
            blocks: Self.sanitize(blocks),
            appearance: appearanceValue.flatMap(AppAppearance.init(rawValue:)),
            language: languageValue.flatMap(AppLanguage.init(rawValue:)),
            launchAtLogin: launchValue,
            selectedBlockID: selectedValue.flatMap(UUID.init(uuidString:)),
            schemaVersion: schemaVersion,
            droppedBlocks: droppedBlocks)
    }

    /// 应用已解析的备份，替换全部块和（存在时）外观/语言设置。
    @discardableResult
    func applyBackup(_ preview: BackupPreview) -> BackupImportResult {
        endTextEditing()

        let newBlocks = preview.blocks.map { snapshot -> BlockSettings in
            let block = BlockSettings(snapshot: snapshot)
            block.onChange = { [weak self, weak block] change in
                guard let self, let block else { return }
                self.blockChanged(block, change)
            }
            return block
        }
        guard !newBlocks.isEmpty else {
            return BackupImportResult(importedBlocks: 0,
                                      droppedBlocks: preview.droppedBlocks,
                                      schemaVersion: preview.schemaVersion)
        }

        blocks = newBlocks
        if let selected = preview.selectedBlockID,
           newBlocks.contains(where: { $0.id == selected }) {
            selectedBlockID = selected
        } else {
            selectedBlockID = newBlocks[0].id
        }

        // 只覆盖备份中明确提供的全局设置；直接导入 blocks 数组时保留当前外观/语言
        if let appearance = preview.appearance { self.appearance = appearance }
        if let language = preview.language { self.language = language }
        // 登录项是系统状态：仅在可用且备份明确提供时尝试恢复，失败会显示在通用页
        if loginItemAvailable,
           let launchAtLogin = preview.launchAtLogin,
           self.launchAtLogin != launchAtLogin {
            self.launchAtLogin = launchAtLogin
        }

        persistBlocks()
        onStructureChange?()
        onAppearanceChange?()

        return BackupImportResult(importedBlocks: newBlocks.count,
                                  droppedBlocks: preview.droppedBlocks,
                                  schemaVersion: preview.schemaVersion)
    }

    /// 一键恢复默认：清空本 App 管理的键，并生成一个默认块。
    /// 不修改系统「开机自启」状态。
    func resetToDefaults() {
        endTextEditing()

        let defaults = UserDefaults.standard
        for key in Self.managedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }

        var snapshot = BlockSnapshot.makeDefault(autosaveName: "SwiftQuoteStatusItem",
                                                 text: "Aloha!")
        snapshot.prefix = "["
        snapshot.suffix = "]"
        let block = BlockSettings(snapshot: snapshot)
        block.onChange = { [weak self, weak block] change in
            guard let self, let block else { return }
            self.blockChanged(block, change)
        }

        blocks = [block]
        selectedBlockID = block.id
        appearance = .system
        language = .system
        loginItemError = nil

        persistBlocks()
        onStructureChange?()
        onAppearanceChange?()
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    /// 判断一个块对象是否包含至少一个已知内容字段。
    private static func hasRecognizedBlockContent(_ dict: [String: Any]) -> Bool {
        let keys = [
            "text", "prefix", "suffix", "fontFamily", "fontWeight", "fontSize",
            "tracking", "colorEntries", "history", "rotationItems", "datePattern",
        ]
        return keys.contains { key in
            guard let value = dict[key] else { return false }
            return !(value is NSNull)
        }
    }

    // MARK: - 回调（由状态栏 / 轮播控制器设置）

    /// 某个块的显示内容变化
    var onDisplayChange: ((BlockSettings) -> Void)?
    /// 某个块的轮播配置变化
    var onRotationChange: ((BlockSettings) -> Void)?
    /// 某个块的动态日期时间开关变化
    var onDateChange: ((BlockSettings) -> Void)?
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

extension RotationItem {
    /// 缺失字段时使用默认值，避免单条轮播数据损坏影响整块导入。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }
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
