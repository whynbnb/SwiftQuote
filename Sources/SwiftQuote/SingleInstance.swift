import Foundation
import Darwin

/// 单实例保护：避免重复启动出现两个菜单栏项，并同时读写同一份 UserDefaults。
///
/// 做法：按「Bundle ID（打包 App）/ 可执行文件路径（SwiftPM 裸跑）」生成一个稳定的
/// 锁文件名，用 `flock` 加非阻塞独占锁。进程存活期间一直持有 fd，退出时由系统自动释放；
/// 第二个实例会短暂等待（兼容「先起新进程、再退旧进程」的重启流程），仍拿不到锁则退出。
enum SingleInstance {
    static func acquire() -> Bool {
        #if DEBUG
        // 开发时用可执行文件路径区分，避免 Xcode Debug 版被已安装的 Release 版挡住
        let identity = Bundle.main.executableURL?.path ?? "SwiftQuote-debug"
        #else
        let identity = Bundle.main.bundleIdentifier
            ?? Bundle.main.executableURL?.path
            ?? "SwiftQuote"
        #endif
        let fileName = "\(stableHash(identity)).lock"

        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("SwiftQuote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(fileName).path

        // O_CLOEXEC：重启流程由旧进程拉起新进程，锁 fd 不能被新进程继承，
        // 否则新进程会“替旧进程”继续持有锁，导致自己拿不到锁而退出。
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return true }   // 锁文件不可用时不要阻止正常启动

        // 「重启」菜单会先拉起新进程、再退出旧进程，因此这里短暂重试，
        // 等旧实例释放锁（通常 < 0.3s）；普通重复启动会在约 1s 后退出。
        for _ in 0..<10 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                // 故意不 close(fd)：锁要一直持有到进程退出。
                return true
            }
            usleep(100_000)
        }
        close(fd)
        return false
    }

    /// 稳定的 FNV-1a 哈希。不能用 `hashValue`（每次进程启动随机种子不同）。
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16)
    }
}
