import Foundation

/// 轮播控制器：每个菜单栏块各自维护一个定时器，按设置的间隔在文字组中切换。
/// 自动切换走 `setTextLive`，不会把轮播内容写进历史。
@MainActor
final class RotationController {
    static let shared = RotationController()

    private let settings = AppSettings.shared
    private var timers: [UUID: Timer] = [:]
    /// 输入面板打开等场景下临时挂起对应块的定时器
    private var suspended: Set<UUID> = []

    private init() {
        settings.onRotationChange = { [weak self] block in self?.schedule(block) }
    }

    /// App 启动时调用，按已保存的配置开始计时。
    func start() {
        scheduleAll()
    }

    /// 手动切到下一条（菜单「下一条」/ 设置页按钮），并重新计时。
    func nextManually(block: BlockSettings) {
        advance(block)
        schedule(block)
    }

    /// 暂停 / 继续。
    func togglePause(block: BlockSettings) {
        guard block.rotationEnabled else { return }
        block.rotationPaused.toggle()
    }

    /// 输入面板打开期间暂停该块的自动切换，避免覆盖用户正在编辑的内容。
    func suspend(block: BlockSettings) {
        suspended.insert(block.id)
        cancel(block.id)
    }

    func resume(block: BlockSettings) {
        suspended.remove(block.id)
        schedule(block)
    }

    func resume(blockID: UUID) {
        suspended.remove(blockID)
        if let block = settings.blocks.first(where: { $0.id == blockID }) {
            schedule(block)
        }
    }

    /// 块增删或启动时调用：清理失效定时器并重排所有块。
    func scheduleAll() {
        let valid = Set(settings.blocks.map(\.id))
        for id in Array(timers.keys) where !valid.contains(id) {
            cancel(id)
        }
        for block in settings.blocks {
            schedule(block)
        }
    }

    private func schedule(_ block: BlockSettings) {
        cancel(block.id)
        guard !suspended.contains(block.id),
              block.rotationEnabled,
              !block.rotationPaused,
              block.activeRotationItems.count > 1 else { return }

        let timer = Timer(timeInterval: block.rotationInterval.seconds,
                          target: self,
                          selector: #selector(tick(_:)),
                          userInfo: block.id,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        timers[block.id] = timer
    }

    private func cancel(_ id: UUID) {
        timers[id]?.invalidate()
        timers[id] = nil
    }

    @objc private func tick(_ timer: Timer) {
        guard let id = timer.userInfo as? UUID,
              let block = settings.blocks.first(where: { $0.id == id }) else { return }
        // 用户正在设置页编辑正文时跳过本次，避免打断输入
        guard !block.isEditingText else { return }
        advance(block)
    }

    private func advance(_ block: BlockSettings) {
        let items = block.activeRotationItems
        guard items.count > 1 else { return }

        let nextIndex: Int
        switch block.rotationOrder {
        case .sequential:
            if let current = items.firstIndex(where: { $0.text == block.text }) {
                nextIndex = (current + 1) % items.count
            } else {
                nextIndex = 0
            }
        case .random:
            let candidates = items.indices.filter { items[$0].text != block.text }
            nextIndex = candidates.randomElement() ?? items.indices.randomElement()!
        }

        block.setTextLive(items[nextIndex].text)
    }
}
