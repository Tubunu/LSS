import CoreGraphics
@testable import LongShot
import XCTest

final class TileRendererTests: XCTestCase {
    func testTileRendererRendersSingleImage() throws {
        let fixture = try loadFixture(name: "simple_article")
        let frames = makeFrames(fixture: fixture)
        let plan = try StitchEngine().makePlan(frames: frames)
        let images = try frames.map {
            try makeImage(values: $0.luminance, width: $0.sourceWidth, height: $0.sourceHeight)
        }

        let renderer = TileRenderer()
        let result = try renderer.render(plan: plan, images: images)

        XCTAssertEqual(result.width, plan.sourceWidth)
        XCTAssertEqual(result.height, plan.outputHeight)
    }

    func testTileRendererDownsamplesCorrectly() throws {
        let fixture = try loadFixture(name: "simple_article")
        let frames = makeFrames(fixture: fixture)
        let plan = try StitchEngine().makePlan(frames: frames)
        let images = try frames.map {
            try makeImage(values: $0.luminance, width: $0.sourceWidth, height: $0.sourceHeight)
        }

        let renderer = TileRenderer()
        let scale: CGFloat = 0.5
        let result = try renderer.render(plan: plan, images: images, scale: scale)

        XCTAssertEqual(result.width, Int(CGFloat(plan.sourceWidth) * scale))
        XCTAssertEqual(result.height, Int(CGFloat(plan.outputHeight) * scale))
    }

    func testTileRendererSlicesOnOversize() throws {
        let fixture = try loadFixture(name: "simple_article")
        let frames = makeFrames(fixture: fixture)
        let plan = try StitchEngine().makePlan(frames: frames)
        let images = try frames.map {
            try makeImage(values: $0.luminance, width: $0.sourceWidth, height: $0.sourceHeight)
        }

        let renderer = TileRenderer()
        // 设置较小的 maxSliceHeight 以触发切片
        let maxSliceHeight = 50
        let slices = try renderer.renderSlices(plan: plan, images: images, maxSliceHeight: maxSliceHeight)

        XCTAssertGreaterThan(slices.count, 1)
        for (i, slice) in slices.enumerated() {
            XCTAssertEqual(slice.index, i + 1)
            XCTAssertEqual(slice.total, slices.count)
            XCTAssertEqual(slice.image.width, plan.sourceWidth)
            XCTAssertGreaterThan(slice.image.height, 0)
        }

        // 所有切片高度总和必须完全等于完整长图高度
        let totalSliceHeight = slices.reduce(0) { $0 + $1.image.height }
        XCTAssertEqual(totalSliceHeight, plan.outputHeight)
    }

    func testTileRendererRejectsLowConfidencePlan() throws {
        let fixture = try loadFixture(name: "edge_cases")
        let first = makeFrame(fixture: fixture, index: 0, offset: 0, seed: 3)
        let second = makeFrame(fixture: fixture, index: 1, offset: 20, seed: 97)
        let plan = try StitchEngine().makePlan(frames: [first, second])
        let images = try [
            makeImage(values: first.luminance, width: first.sourceWidth, height: first.sourceHeight),
            makeImage(values: second.luminance, width: second.sourceWidth, height: second.sourceHeight),
        ]

        let renderer = TileRenderer()
        XCTAssertThrowsError(try renderer.render(plan: plan, images: images)) { error in
            XCTAssertEqual(error as? StitchError, .lowConfidence)
        }
    }

    // MARK: - Helpers

    private func loadFixture(name: String) throws -> StitchFixture {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/\(name)"
        ) ?? bundle.bundleURL.appendingPathComponent("Fixtures/\(name)/\(name).json")

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StitchFixture.self, from: data)
    }

    private func makeFrames(fixture: StitchFixture) -> [AnalyzedFrame] {
        fixture.offsets.enumerated().map { index, offset in
            makeFrame(fixture: fixture, index: index, offset: offset, seed: 11)
        }
    }

    private func makeFrame(fixture: StitchFixture, index: Int, offset: Int, seed: Int) -> AnalyzedFrame {
        var luminance = [UInt8]()
        luminance.reserveCapacity(fixture.width * fixture.height)
        for y in 0 ..< fixture.height {
            for x in 0 ..< fixture.width {
                luminance.append(pixel(fixture: fixture, x: x, y: y, offset: offset, seed: seed))
            }
        }
        return AnalyzedFrame(
            index: index,
            sourceWidth: fixture.width,
            sourceHeight: fixture.height,
            analysisWidth: fixture.width,
            analysisHeight: fixture.height,
            luminance: luminance
        )
    }

    private func pixel(fixture: StitchFixture, x: Int, y: Int, offset: Int, seed: Int) -> UInt8 {
        let documentY = y + offset
        switch fixture.style {
        case "simple_article":
            if y < 8 { return 240 }
            if y >= fixture.height - 6 { return 230 }
            let line = documentY / 6
            let isTextRow = (documentY % 6) < 3
            if isTextRow {
                let textEnd = (line * 17 + seed * 19) % (fixture.width - 8) + 4
                return x < textEnd ? 20 : 255
            }
            return 255
        default:
            return UInt8((x * 13 + documentY * 37 + seed) % 256)
        }
    }

    private func makeImage(values: [UInt8], width: Int, height: Int) throws -> CGImage {
        let quartzRows = (0 ..< height).reversed().flatMap { row in
            Array(values[(row * width) ..< ((row + 1) * width)])
        }
        guard let provider = CGDataProvider(data: Data(quartzRows) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: width,
                  space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            throw StitchError.contextCreationFailed
        }
        return image
    }
}

private struct StitchFixture: Decodable {
    var name: String
    var style: String
    var width: Int
    var height: Int
    var offsets: [Int]
    var expectedFinalHeight: Int
}
