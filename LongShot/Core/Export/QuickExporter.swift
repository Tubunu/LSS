import CoreGraphics
import Foundation
import Photos
import UIKit

@MainActor
struct QuickExporter {
    enum ExportError: LocalizedError {
        case notAuthorized
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "未获得系统相册写入权限，请在系统设置中开启"
            case let .saveFailed(msg):
                "保存失败：\(msg)"
            }
        }
    }

    /// 一键复制到系统剪贴板（日常高频：微信直接粘贴）
    static func copyToClipboard(image: CGImage) {
        let uiImage = UIImage(cgImage: image)
        UIPasteboard.general.image = uiImage
    }

    /// 保存单张长图到系统相册
    static func saveToPhotos(image: CGImage) async throws {
        let uiImage = UIImage(cgImage: image)
        try await performPhotoSave(images: [uiImage])
    }

    /// 批量保存切片多图到系统相册
    static func saveSlicesToPhotos(slices: [CGImage]) async throws {
        let uiImages = slices.map { UIImage(cgImage: $0) }
        try await performPhotoSave(images: uiImages)
    }

    private static func performPhotoSave(images: [UIImage]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.notAuthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            for img in images {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            }
        }
    }
}
