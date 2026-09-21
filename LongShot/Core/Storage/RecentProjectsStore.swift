import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

public struct RecentProject: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let width: Int
    public let height: Int
    public let sliceCount: Int
    public let thumbnailFileName: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        width: Int,
        height: Int,
        sliceCount: Int = 1,
        thumbnailFileName: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.sliceCount = sliceCount
        self.thumbnailFileName = thumbnailFileName
    }
}

@MainActor
public final class RecentProjectsStore: ObservableObject {
    public static let shared = RecentProjectsStore()

    @Published public private(set) var projects: [RecentProject] = []

    private let maxCount = 10
    private let fileManager = FileManager.default
    private let rootDirectory: URL

    private init() {
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        rootDirectory = appSupport.appendingPathComponent("LongShotProjects", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        load()
    }

    /// 记录新生成的长截图（最多保留最近 10 条，并生成轻量缩略图）
    public func record(image: CGImage, sliceCount: Int = 1) {
        let id = UUID()
        let thumbName = "\(id.uuidString).jpg"
        let thumbURL = rootDirectory.appendingPathComponent(thumbName)

        // 生成缩略图并写入磁盘
        if let thumbData = createThumbnailJPEG(from: image) {
            try? thumbData.write(to: thumbURL, options: .atomic)
        }

        let project = RecentProject(
            id: id,
            createdAt: Date(),
            width: image.width,
            height: image.height,
            sliceCount: sliceCount,
            thumbnailFileName: thumbName
        )

        projects.insert(project, at: 0)

        // 淘汰超期记录与缩略图文件
        while projects.count > maxCount {
            let removed = projects.removeLast()
            let oldURL = rootDirectory.appendingPathComponent(removed.thumbnailFileName)
            try? fileManager.removeItem(at: oldURL)
        }

        save()
    }

    public func delete(id: UUID) {
        if let index = projects.firstIndex(where: { $0.id == id }) {
            let removed = projects.remove(at: index)
            let oldURL = rootDirectory.appendingPathComponent(removed.thumbnailFileName)
            try? fileManager.removeItem(at: oldURL)
            save()
        }
    }

    public func clearAll() {
        for p in projects {
            let url = rootDirectory.appendingPathComponent(p.thumbnailFileName)
            try? fileManager.removeItem(at: url)
        }
        projects.removeAll()
        save()
    }

    public func thumbnailURL(for project: RecentProject) -> URL {
        rootDirectory.appendingPathComponent(project.thumbnailFileName)
    }

    private func load() {
        let metaURL = rootDirectory.appendingPathComponent("recents.json")
        guard let data = try? Data(contentsOf: metaURL),
              let list = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return
        }
        self.projects = list
    }

    private func save() {
        let metaURL = rootDirectory.appendingPathComponent("recents.json")
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    private func createThumbnailJPEG(from image: CGImage) -> Data? {
        let thumbHeight = 360
        let scale = CGFloat(thumbHeight) / CGFloat(image.height)
        let thumbWidth = max(1, Int(CGFloat(image.width) * scale))

        guard let context = CGContext(
            data: nil,
            width: thumbWidth,
            height: thumbHeight,
            bitsPerComponent: 8,
            bytesPerRow: thumbWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.translateBy(x: 0, y: CGFloat(thumbHeight))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(image, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        guard let thumbImage = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.72
        ]
        CGImageDestinationAddImage(destination, thumbImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }
}
