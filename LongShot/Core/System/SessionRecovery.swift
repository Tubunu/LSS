import Foundation

struct RecoverableSession: Identifiable, Sendable {
    let id: UUID
    let directory: URL
    let frameCount: Int
    let createdAt: Date

    init(id: UUID, directory: URL, frameCount: Int, createdAt: Date) {
        self.id = id
        self.directory = directory
        self.frameCount = frameCount
        self.createdAt = createdAt
    }
}

struct SessionRecovery: Sendable {
    /// 检查是否存在未完成但保留了关键帧的会话（例如异常退出或崩溃）
    static func findRecoverableSession() -> RecoverableSession? {
        let fileManager = FileManager.default
        guard let caches = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        let root = caches
            .appendingPathComponent("LongShot", isDirectory: true)
            .appendingPathComponent("CaptureSessions", isDirectory: true)

        guard let sessions = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return nil }

        // 寻找 24 小时内有 2 张以上未清理 png 关键帧的最近会话
        let cutoff = Date().addingTimeInterval(-86400)
        var bestSession: RecoverableSession?

        for sessionDir in sessions where sessionDir.hasDirectoryPath {
            guard let files = try? fileManager.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil) else {
                continue
            }
            let pngCount = files.filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("frame-") }.count
            guard pngCount >= 2 else { continue }

            let date = (try? sessionDir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if date > cutoff {
                if bestSession == nil || date > (bestSession?.createdAt ?? .distantPast) {
                    if let uuid = UUID(uuidString: sessionDir.lastPathComponent) {
                        bestSession = RecoverableSession(id: uuid, directory: sessionDir, frameCount: pngCount, createdAt: date)
                    }
                }
            }
        }

        return bestSession
    }

    /// 用户选择放弃未完成会话，物理清除临时目录
    static func discard(session: RecoverableSession) {
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: session.directory)
        }
    }
}
