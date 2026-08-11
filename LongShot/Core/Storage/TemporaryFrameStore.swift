import Foundation

struct TemporaryFrameStore: Sendable {
    let sessionID: UUID
    let directory: URL

    init(sessionID: UUID = UUID(), fileManager: FileManager = .default) throws {
        self.sessionID = sessionID
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = caches
            .appendingPathComponent("LongShot", isDirectory: true)
            .appendingPathComponent("CaptureSessions", isDirectory: true)
        directory = root.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
    }

    func frameURL(index: Int) -> URL {
        directory.appendingPathComponent(String(format: "frame-%05d.png", index))
    }

    func diagnosticsURL() -> URL {
        directory.appendingPathComponent("diagnostics.json")
    }

    func frameMetadataURL() -> URL {
        directory.appendingPathComponent("frames.json")
    }

    func remove(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}
