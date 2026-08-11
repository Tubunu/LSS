@testable import LongShot
import XCTest

final class FixedRegionDetectorTests: XCTestCase {
    func testDetectsTopBottomAndFloatingStableRegions() throws {
        let frames = [0, 12, 24].enumerated().map { index, offset in
            makeFrame(index: index, documentOffset: offset)
        }

        let regions = try FixedRegionDetector().detect(frames: frames)

        XCTAssertTrue(regions.contains { $0.kind == .topBar && $0.y == 0 })
        XCTAssertTrue(regions.contains { region in
            region.kind == .bottomBar && region.y + region.height == 64
        })
        XCTAssertTrue(regions.contains { region in
            region.kind == .floating
                && region.x <= 27 && region.x + region.width > 27
                && region.y <= 39 && region.y + region.height > 39
                && region.width < 32
        })
    }

    func testFixedRegionsAreExcludedFromOverlapAndSeam() throws {
        let frames = [0, 12, 24].enumerated().map { index, offset in
            makeFrame(index: index, documentOffset: offset)
        }

        let plan = try StitchEngine().makePlan(frames: frames)

        XCTAssertTrue(plan.isRenderable)
        XCTAssertEqual(plan.segments.map(\.offset), [12, 12])
        XCTAssertEqual(plan.outputHeight, 88)
        XCTAssertTrue(plan.segments.allSatisfy { !$0.fixedRegions.isEmpty })
        for segment in plan.segments {
            XCTAssertFalse(segment.fixedRegions.contains { region in
                region.x == 0
                    && segment.seam >= region.y
                    && segment.seam < region.y + region.height
            })
        }
    }

    func testMinorRollbackFrameIsSkippedAndProgressContinues() throws {
        let offsets = [0, 16, 12, 28]
        let frames = offsets.enumerated().map { index, offset in
            makeFrame(index: index, documentOffset: offset)
        }

        let plan = try StitchEngine().makePlan(frames: frames)

        XCTAssertTrue(plan.isRenderable)
        XCTAssertEqual(plan.skippedFrameIndices, [2])
        XCTAssertEqual(plan.placements.map(\.frameIndex), [0, 1, 3])
        XCTAssertEqual(plan.segments.map(\.offset), [16, 12])
        XCTAssertEqual(plan.outputHeight, 92)
        XCTAssertEqual(plan.warnings.map(\.kind), [.rollbackRecovered])
    }

    func testRendererUsesOriginalIndicesAfterRollbackRecovery() throws {
        let offsets = [0, 16, 12, 28]
        let frames = offsets.enumerated().map { index, offset in
            makeFrame(index: index, documentOffset: offset)
        }
        let plan = try StitchEngine().makePlan(frames: frames)
        let images = try frames.map(makeImage)

        let rendered = try StitchRenderer().render(plan: plan, images: images)

        XCTAssertEqual(rendered.width, 32)
        XCTAssertEqual(rendered.height, 92)
    }

    private func makeFrame(index: Int, documentOffset: Int) -> AnalyzedFrame {
        let width = 32
        let height = 64
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let value: UInt8
                if y < 8 {
                    value = (x / 2 + y / 2).isMultiple(of: 2) ? 28 : 226
                } else if y >= 56 {
                    value = (x / 3 + y / 2).isMultiple(of: 2) ? 42 : 214
                } else {
                    let documentY = documentOffset + y - 8
                    value = UInt8(
                        (x * 67 + documentY * 43 + x * documentY * 19 + (documentY % 11) * 31) % 256
                    )
                }
                values[y * width + x] = value
            }
        }

        for y in 36 ..< 44 {
            for x in 24 ..< 30 {
                values[y * width + x] = (x + y).isMultiple(of: 2) ? 20 : 235
            }
        }

        return AnalyzedFrame(
            index: index,
            sourceWidth: width,
            sourceHeight: height,
            analysisWidth: width,
            analysisHeight: height,
            luminance: values
        )
    }

    private func makeImage(frame: AnalyzedFrame) throws -> CGImage {
        let rows = (0 ..< frame.sourceHeight).reversed().flatMap { row in
            Array(
                frame.luminance[
                    (row * frame.sourceWidth) ..< ((row + 1) * frame.sourceWidth)
                ]
            )
        }
        guard let provider = CGDataProvider(data: Data(rows) as CFData),
              let image = CGImage(
                  width: frame.sourceWidth,
                  height: frame.sourceHeight,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8,
                  bytesPerRow: frame.sourceWidth,
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
