import CoreGraphics
@testable import LongShot
import XCTest

@MainActor
final class RecentProjectsStoreTests: XCTestCase {
    func testRecordAndLimitTenProjects() throws {
        let store = RecentProjectsStore.shared
        store.clearAll()

        let testImage = try makeSampleImage()

        // 插入 12 次记录
        for _ in 1...12 {
            store.record(image: testImage, sliceCount: 1)
        }

        // 必须严格封顶 10 条
        XCTAssertEqual(store.projects.count, 10)

        // 测试删除单条
        if let first = store.projects.first {
            store.delete(id: first.id)
            XCTAssertEqual(store.projects.count, 9)
        }

        store.clearAll()
        XCTAssertEqual(store.projects.count, 0)
    }

    private func makeSampleImage() throws -> CGImage {
        let width = 60
        let height = 100
        let bytesPerRow = width * 4
        let pixels = [UInt8](repeating: 200, count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw StitchError.contextCreationFailed
        }
        return image
    }
}
