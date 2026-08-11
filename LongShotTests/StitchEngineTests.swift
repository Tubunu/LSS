import CoreGraphics
@testable import LongShot
import XCTest

final class StitchEngineTests: XCTestCase {
    func testFixtureOffsetsAndApproximateHeights() throws {
        for name in ["simple_article", "settings_list", "chat_style", "image_feed"] {
            let fixture = try loadFixture(name: name)
            let frames = makeFrames(fixture: fixture)
            let plan = try StitchEngine().makePlan(frames: frames)

            XCTAssertTrue(plan.isRenderable, name)
            XCTAssertEqual(plan.warnings, [], name)
            XCTAssertEqual(
                plan.segments.map(\.offset),
                zip(fixture.offsets, fixture.offsets.dropFirst()).map { $1 - $0 },
                name
            )
            XCTAssertEqual(plan.outputHeight, fixture.expectedFinalHeight, name)
            XCTAssertTrue(plan.segments.allSatisfy { $0.confidence >= 0.60 }, name)
            XCTAssertTrue(plan.segments.allSatisfy { $0.overlap + $0.offset == fixture.height }, name)
        }
    }

    func testUnrelatedFramesProduceWarningAndRendererRefuses() throws {
        let fixture = try loadFixture(name: "edge_cases")
        let first = makeFrame(fixture: fixture, index: 0, offset: 0, seed: 3)
        let second = makeFrame(fixture: fixture, index: 1, offset: 20, seed: 97)
        let plan = try StitchEngine().makePlan(frames: [first, second])

        XCTAssertFalse(plan.isRenderable)
        XCTAssertEqual(plan.warnings.count, 1)
        XCTAssertEqual(plan.warnings.first?.kind, .lowConfidence)

        let images = try [
            makeImage(values: first.luminance, width: first.sourceWidth, height: first.sourceHeight),
            makeImage(values: second.luminance, width: second.sourceWidth, height: second.sourceHeight),
        ]
        XCTAssertThrowsError(try StitchRenderer().render(plan: plan, images: images)) { error in
            XCTAssertEqual(error as? StitchError, .lowConfidence)
        }
    }

    func testFrameAnalyzerPlanAndRendererEndToEnd() throws {
        let fixture = try loadFixture(name: "simple_article")
        let sourceFrames = makeFrames(fixture: fixture)
        let images = try sourceFrames.map {
            try makeImage(values: $0.luminance, width: $0.sourceWidth, height: $0.sourceHeight)
        }
        let analyzer = FrameAnalyzer()
        let analyzed = try images.enumerated().map { index, image in
            try analyzer.analyze(image: image, index: index)
        }
        if let mismatch = zip(analyzed[0].luminance, sourceFrames[0].luminance).enumerated().first(where: {
            $0.element.0 != $0.element.1
        }) {
            XCTFail(
                "analyzer mismatch at x=\(mismatch.offset % fixture.width), "
                    + "y=\(mismatch.offset / fixture.width): analyzed=\(mismatch.element.0), "
                    + "expected=\(mismatch.element.1)"
            )
            return
        }
        let plan = try StitchEngine().makePlan(frames: analyzed)
        let rendered = try StitchRenderer().render(plan: plan, images: images)

        XCTAssertEqual(rendered.width, fixture.width)
        XCTAssertEqual(rendered.height, fixture.expectedFinalHeight)
        XCTAssertTrue(plan.segments.allSatisfy { !$0.debugCandidates.isEmpty })

        let renderedValues = try readLuminance(image: rendered)
        let expectedValues = (0 ..< fixture.expectedFinalHeight).flatMap { documentY in
            (0 ..< fixture.width).map { x in
                fixtureValue(style: fixture.style, x: x, documentY: documentY, seed: 11)
            }
        }
        let firstMismatch = zip(renderedValues, expectedValues).enumerated().first {
            $0.element.0 != $0.element.1
        }
        XCTAssertNil(
            firstMismatch,
            firstMismatch.map {
                "first mismatch at x=\($0.offset % fixture.width), y=\($0.offset / fixture.width): "
                    + "rendered=\($0.element.0), expected=\($0.element.1)"
            } ?? ""
        )
    }

    func testPlanRoundTripsThroughDebugJSON() throws {
        let fixture = try loadFixture(name: "chat_style")
        let plan = try StitchEngine().makePlan(frames: makeFrames(fixture: fixture))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        try StitchDebugWriter().write(plan: plan, to: url)
        let decoded = try JSONDecoder().decode(StitchPlan.self, from: Data(contentsOf: url))

        XCTAssertEqual(decoded, plan)
    }

    func testRejectsIncompatibleFrameSizes() throws {
        let fixture = try loadFixture(name: "simple_article")
        var frames = makeFrames(fixture: fixture)
        frames[1].sourceWidth += 1

        XCTAssertThrowsError(try StitchEngine().makePlan(frames: frames)) { error in
            XCTAssertEqual(error as? StitchError, .incompatibleFrames)
        }
    }

    private func loadFixture(name: String) throws -> StitchFixture {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture \(name)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(StitchFixture.self, from: Data(contentsOf: url))
    }

    private func makeFrames(fixture: StitchFixture) -> [AnalyzedFrame] {
        fixture.offsets.enumerated().map { index, offset in
            makeFrame(fixture: fixture, index: index, offset: offset, seed: 11)
        }
    }

    private func makeFrame(
        fixture: StitchFixture,
        index: Int,
        offset: Int,
        seed: Int
    ) -> AnalyzedFrame {
        var values = [UInt8](repeating: 0, count: fixture.width * fixture.height)
        for y in 0 ..< fixture.height {
            for x in 0 ..< fixture.width {
                values[y * fixture.width + x] = fixtureValue(
                    style: fixture.style,
                    x: x,
                    documentY: y + offset,
                    seed: seed
                )
            }
        }
        return AnalyzedFrame(
            index: index,
            sourceWidth: fixture.width,
            sourceHeight: fixture.height,
            analysisWidth: fixture.width,
            analysisHeight: fixture.height,
            luminance: values
        )
    }

    private func fixtureValue(style: String, x: Int, documentY: Int, seed: Int) -> UInt8 {
        switch style {
        case "article":
            let line = documentY / 3
            let textWidth = 8 + (line * 13 + seed) % 21
            return documentY % 3 == 1 && x < textWidth ? UInt8(35 + (x * 7 + line) % 50) : 242
        case "settings":
            if documentY % 9 == 8 {
                return 188
            }
            if x < 5, documentY % 9 >= 2, documentY % 9 <= 6 {
                return UInt8(45 + (documentY / 9 * 31 + seed) % 130)
            }
            let row = documentY / 9
            let textEnd = 11 + (row * 7 + seed) % 17
            return x >= 8 && x < textEnd && documentY % 9 == 4 ? 55 : 247
        case "chat":
            let block = documentY / 11
            let rightAligned = block.isMultiple(of: 2)
            let start = rightAligned ? 12 : 2
            let end = rightAligned ? 30 : 21
            if documentY % 11 == 10 {
                return 238
            }
            return x >= start && x < end ? UInt8(120 + (block * 23 + seed) % 90) : 247
        default:
            let panel = documentY / 16
            let noise = (x * 43 + documentY * 71 + x * documentY * 13 + panel * 29 + seed * 47) % 256
            return UInt8(noise)
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

    private func readLuminance(image: CGImage) throws -> [UInt8] {
        var values = [UInt8](repeating: 0, count: image.width * image.height)
        guard let context = CGContext(
            data: &values,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw StitchError.contextCreationFailed
        }
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return values
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
