import Foundation

actor SessionGarbageCollector {
    /// 拼接成功后立即清理原始关键帧 PNG，释放数百 MB 存储
    static func purgeKeyframes(in sessionDirectory: URL) {
        Task.detached(priority: .background) {
            let fileManager = FileManager.default
            guard let files = try? fileManager.contentsOfDirectory(
                at: sessionDirectory,
                includingPropertiesForKeys: nil
            ) else { return }

            for file in files where file.pathExtension.lowercased() == "png" {
                // 仅删除原始关键帧 PNG，保留 metadata.json 或 diagnostics.json 便于审计
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// 启动时清理超过 24 小时的孤儿临时目录
    static func cleanupStaleSessions() {
        Task.detached(priority: .background) {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LongShot")
            let cutoff = Date().addingTimeInterval(-86400)
            guard let sessions = try? FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey]
            ) else { return }

            for dir in sessions {
                if let date = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
                   date < cutoff {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        }
    }
}
