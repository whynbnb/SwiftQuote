import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese, english
    var id: String { rawValue }
}

/// 界面多语言文案（中文 / English）
struct L {
    let isChinese: Bool

    private func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    // MARK: 菜单栏菜单
    var menuInput: String   { t("输入…", "Input…") }
    var menuDateFormat: String { t("日期格式…", "Date Format…") }
    var menuSettings: String { t("设置…", "Settings…") }
    var menuQuit: String    { t("退出", "Quit") }
    var trackHistory: String { t("跟踪历史", "Track History") }
    var historyHeader: String { t("历史", "History") }
    var clearHistory: String { t("清除历史", "Clear History") }
    var statusItemToolTip: String {
        t("SwiftQuote：左键打开菜单，右键编辑文字",
          "SwiftQuote — left-click for menu, right-click to edit")
    }

    // MARK: 输入面板
    var inputPlaceholder: String { t("输入内容，回车确认", "Type and press Return") }

    // MARK: 设置窗口 Tab
    var tabGeneral: String { t("通用", "General") }
    var tabBlocks: String { t("菜单栏块", "Blocks") }
    var tabText: String { t("文字", "Text") }
    var tabColors: String  { t("颜色", "Colors") }
    var tabHistory: String { t("历史记录", "History") }

    // MARK: 菜单栏块
    var block: String       { t("块", "Block") }
    var addBlock: String    { t("添加块", "Add Block") }
    var deleteBlock: String { t("删除块", "Delete Block") }
    var newBlockText: String { t("新块", "New") }
    var blocksHint: String {
        t("每个块在菜单栏独立显示，文字、样式、颜色、轮播和历史互不影响。",
          "Each block is an independent menu bar item with its own text, style, colors, rotation, and history.")
    }
    var blocksPositionHint: String {
        t("按住 ⌘ 拖动菜单栏块可调整位置，位置会随块保存。",
          "⌘-drag a menu bar block to reorder it; its position is saved with the block.")
    }

    // MARK: 通用设置
    var groupText: String   { t("文字", "Text") }
    var content: String     { t("内容", "Content") }
    var prefix: String      { t("前缀", "Prefix") }
    var suffix: String      { t("后缀", "Suffix") }
    var bold: String        { t("加粗", "Bold") }
    var fontFamily: String  { t("字体", "Font") }
    var systemDefault: String { t("系统默认", "System Default") }
    var fontSize: String    { t("文字大小", "Font Size") }
    var maxWidth: String    { t("最大宽度", "Max Width") }

    // MARK: 动态日期时间
    var groupDateTime: String { t("动态日期时间", "Dynamic Date & Time") }
    var dynamicDateTime: String { t("启用动态日期时间", "Enable Dynamic Date & Time") }
    var dateFormat: String { t("格式", "Format") }
    var dateFormatPlaceholder: String { "MM-dd[EEE]HH:mm" }
    var dateFormatHint: String {
        t("使用 Unicode TR35 日期格式，例如 MM-dd[EEE]HH:mm；按系统语言和时区显示，字面字母可用单引号转义。",
          "Uses Unicode TR35 date patterns (e.g. MM-dd[EEE]HH:mm). Dates follow the system language and time zone; quote literal letters with single quotes.")
    }
    var dateScreenshotPreset: String { t("截图格式 ", "Screenshot Format ") }
    var preview: String { t("预览", "Preview") }
    var dateContentIgnoredHint: String {
        t("日期时间模式下，菜单栏显示格式结果；内容文字不参与显示，前缀和后缀仍然生效。",
          "In date/time mode the menu bar shows the formatted result; the content text is hidden, while prefix and suffix still apply.")
    }
    var calendarOnLeftClick: String { t("左键打开系统日历", "Left-click Opens Calendar") }
    var calendarClickHint: String {
        t("开启后：左键点击该块打开系统日历，右键打开应用菜单；关闭后恢复左键菜单、右键编辑。",
          "When on: left-click opens Calendar and right-click opens the app menu. When off: left-click opens the menu and right-click edits.")
    }
    var rotationDisabledByDate: String {
        t("动态日期时间开启时轮播不生效，可先关闭日期时间。",
          "Rotation is disabled while dynamic date/time is on. Turn it off to use rotation.")
    }
    var dateHistoryHint: String {
        t("日期时间模式下不记录历史；关闭日期时间后继续使用原有历史。",
          "History is not recorded in date/time mode; the existing history is kept for when you turn it off.")
    }
    var groupAppearance: String { t("主题", "Appearance") }
    var appearanceSystem: String { t("跟随系统", "System") }
    var appearanceLight: String  { t("浅色", "Light") }
    var appearanceDark: String   { t("深色", "Dark") }
    var groupLanguage: String { t("语言", "Language") }
    var languageSystem: String  { t("跟随系统", "System") }
    var groupStartup: String  { t("启动", "Startup") }
    var launchAtLogin: String { t("开机自启", "Launch at Login") }
    var launchAtLoginUnavailable: String { t("需以打包的 App 形式运行才可用", "Requires running as a bundled app") }
    var loginItemRequiresApproval: String {
        t("需要在系统设置的「登录项」中允许", "Allow it in System Settings > Login Items")
    }
    var loginItemNotFound: String {
        t("未找到登录项，请重新安装 App", "Login item not found; reinstall the app")
    }
    var openLoginItems: String {
        t("打开登录项设置", "Open Login Items Settings")
    }
    var menuAbout: String     { t("关于", "About") }
    var menuRestart: String   { t("重启", "Restart") }
    var aboutTitle: String    { t("关于 SwiftQuote", "About SwiftQuote") }
    var aboutDescription: String { t("轻量级 macOS 菜单栏自定义文字应用", "A lightweight macOS menu bar custom text app") }
    func aboutVersion(_ v: String, _ b: String) -> String {
        t("版本 \(v) (\(b))", "Version \(v) (\(b))")
    }
    let repositoryURL = "https://github.com/whynbnb/SwiftQuote"
    var groupPresets: String { t("预设", "Presets") }
    var apply: String       { t("应用", "Apply") }

    // MARK: 颜色设置
    var add: String         { t("添加", "Add") }
    var adaptiveColors: String { t("自适应菜单栏（浅色/深色两套颜色）", "Adapt to menu bar (light/dark palettes)") }
    var lightBarColors: String { t("浅色菜单栏（用深色文字）", "Light Menu Bar (dark text)") }
    var darkBarColors: String  { t("深色菜单栏（用浅色文字）", "Dark Menu Bar (light text)") }
    var resetColors: String { t("恢复默认", "Reset to Default") }
    var colorsHint: String {
        t("颜色依次循环应用到每个字符；拖动可排序", "Colors cycle through characters; drag to reorder")
    }

    // MARK: 历史记录
    var clearAll: String  { t("清空全部", "Clear All") }
    var noHistory: String { t("暂无历史记录", "No history yet") }
    var current: String   { t("当前", "Current") }
    var deleteHistoryItem: String { t("删除该记录", "Delete") }

    // MARK: 轮播
    var tabRotation: String { t("轮播", "Rotation") }
    var rotationEnabled: String { t("启用轮播", "Enable Rotation") }
    var rotationInterval: String { t("切换间隔", "Interval") }
    var rotationOrder: String { t("顺序", "Order") }
    var rotationSequential: String { t("顺序", "Sequential") }
    var rotationRandom: String { t("随机", "Random") }
    var rotationAddCurrent: String { t("添加当前", "Add Current") }
    var rotationAddItem: String { t("添加条目", "Add Item") }
    var rotationItemPlaceholder: String { t("文字", "Text") }
    var rotationEmpty: String {
        t("暂无条目，添加两条以上即可开始轮播",
          "No items yet. Add at least two to start rotating.")
    }
    var rotationNeedsTwo: String {
        t("至少需要 2 条非空文字才会开始轮播",
          "Add at least two non-empty items to start rotating.")
    }
    var menuNextItem: String { t("下一条", "Next") }
    var menuPauseRotation: String { t("暂停轮播", "Pause Rotation") }
    var menuResumeRotation: String { t("继续轮播", "Resume Rotation") }
}
