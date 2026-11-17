import Foundation

/// 轮播控制器：按设置的间隔在文字组中切换。
/// 自动切换走 `setTextLive`，不会把轮播内容写进历史。
@MainActor
final class RotationController {
    static let shared = RotationController()

    private let settings = AppSettings.shared
    private var timer: Timer?
    /// 输入面板打开等场景下临时挂起定时器
    private var isSuspended = false

    private init() {
        settings.onRotationSettingsChange = { [weak self] in self?.schedule() }
    }

    /// App 启动时调用，按已保存的配置开始计时。
    func start() {
        schedule()
    }

    /// 手动切到下一条（菜单「下一条」/ 设置页按钮），并重新计时。
    func nextManually() {
        advance()
        schedule()
    }

    /// 暂停 / 继续。
    func togglePause() {
        guard settings.rotationEnabled else { return }
        settings.rotationPaused.toggle()
    }

    /// 输入面板打开期间暂停自动切换，避免覆盖用户正在编辑的内容。
    func suspend() {
        isSuspended = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        isSuspended = false
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard !isSuspended,
              settings.rotationEnabled,
              !settings.rotationPaused,
              settings.activeRotationItems.count > 1 else { return }

        let timer = Timer(timeInterval: settings.rotationInterval.seconds,
                          target: self,
                          selector: #selector(tick),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        // 用户正在设置页编辑正文时跳过本次，避免打断输入
        guard !settings.isEditingText else { return }
        advance()
    }

    private func advance() {
        let items = settings.activeRotationItems
        guard items.count > 1 else { return }

        let nextIndex: Int
        switch settings.rotationOrder {
        case .sequential:
            if let current = items.firstIndex(where: { $0.text == settings.text }) {
                nextIndex = (current + 1) % items.count
            } else {
                nextIndex = 0
            }
        case .random:
            let candidates = items.indices.filter { items[$0].text != settings.text }
            nextIndex = candidates.randomElement() ?? items.indices.randomElement()!
        }

        settings.setTextLive(items[nextIndex].text)
    }
}
