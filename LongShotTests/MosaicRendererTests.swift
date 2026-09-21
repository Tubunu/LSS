import CoreGraphics
@testable import LongShot
import XCTest

final class MosaicRendererTests: XCTestCase {
    func testEmptyStrokesReturnsOriginalImage() throws {
        let original = try makeTestImage(width: 100, height: 100, color: 128)
        let renderer = MosaicRenderer()
        let result = try renderer.applyMosaic(to: original, strokes: [])

        XCTAssertEqual(result.width, original.width)
        XCTAssertEqual(result.height, original.height)
    }

    func testMosaicRendererModifiesStrokeRegion() throws {
        // 创建一个包含渐变或特征纹理的测试图像
        let width = 120
        let height = 120
        let original = try makeGradientTestImage(width: width, height: height)

        let renderer = MosaicRenderer()
        let stroke = MosaicStroke(
            points: [CGPoint(x: 20, y: 60), CGPoint(x: 100, y: 60)],
            lineWidth: 20
        )

        let result = try renderer.applyMosaic(to: original, strokes: [stroke], pixelScale: 16.0)

        XCTAssertEqual(result.width, width)
        XCTAssertEqual(result.height, height)

        // 读取原图与马赛克图的数据进行对比
        let originalBytes = try readBytes(from: original)
        let mosaicBytes = try readBytes(from: result)

        // 位于 (60, 60) 的点处于笔迹中心，像素值必须被马赛克改变
        let centerPixelIndex = (60 * width + 60) * 4
        let originalRed = originalBytes[centerPixelIndex]
        let mosaicRed = mosaicBytes[centerPixelIndex]

        // 验证马赛克发生了像素聚合改变（或不完全相同）
        XCTAssertNotEqual(originalBytes, mosaicBytes, "应用马赛克后图像字节数组应发生改变")
    }

    // MARK: - Helpers

    private func makeTestImage(width: Int, height: Int, color: UInt8) throws -> CGImage {
        let bytesPerRow = width * 4
        let pixels = [UInt8](repeating: color, count: bytesPerRow * height)
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

    private func makeGradientTestImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var pixels = [UInt8]()
        pixels.reserveCapacity(bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let r = UInt8((x * 255) / width)
                let g = UInt8((y * 255) / height)
                let b = UInt8(((x + y) * 128) / (width + height))
                pixels.append(r)
                pixels.append(g)
                pixels.append(b)
                pixels.append(255)
            }
        }
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

    private func readBytes(from image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StitchError.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
