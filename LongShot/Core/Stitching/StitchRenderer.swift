import CoreGraphics
import Foundation

struct StitchRenderer: Sendable {
    private let thresholds: StitchThresholds

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
    }

    func render(plan: StitchPlan, images: [CGImage]) throws -> CGImage {
        let referencedIndices = plan.placements.map(\.frameIndex)
            + plan.segments.flatMap { [$0.upperFrameIndex, $0.lowerFrameIndex] }
        guard !referencedIndices.isEmpty,
              referencedIndices.allSatisfy(images.indices.contains),
              referencedIndices.allSatisfy({
                  images[$0].width == plan.sourceWidth && images[$0].height == plan.sourceHeight
              })
        else {
            throw StitchError.incompatibleFrames
        }
        guard plan.isRenderable else { throw StitchError.lowConfidence }
        guard plan.sourceWidth <= thresholds.maximumRenderDimension,
              plan.outputHeight <= thresholds.maximumRenderDimension
        else {
            throw StitchError.renderDimensionExceeded
        }

        let decoded = try images.map(decodeRGBA)
        let bytesPerRow = plan.sourceWidth * 4
        var output = [UInt8](repeating: 0, count: bytesPerRow * plan.outputHeight)
        let firstFrameIndex = plan.placements[0].frameIndex
        copyRows(
            from: decoded[firstFrameIndex],
            sourceStartY: 0,
            sourceHeight: plan.sourceHeight,
            to: &output,
            destinationStartY: 0,
            bytesPerRow: bytesPerRow
        )

        for segmentIndex in plan.segments.indices {
            let segment = plan.segments[segmentIndex]
            let sourceStartY = min(max(segment.seam, 0), plan.sourceHeight - 1)
            let placement = plan.placements[segmentIndex + 1]
            copyRows(
                from: decoded[segment.lowerFrameIndex],
                sourceStartY: sourceStartY,
                sourceHeight: plan.sourceHeight - sourceStartY,
                to: &output,
                destinationStartY: placement.offsetY + sourceStartY,
                bytesPerRow: bytesPerRow
            )
        }

        return try makeImage(topDownRGBA: output, width: plan.sourceWidth, height: plan.outputHeight)
    }

    private func decodeRGBA(_ image: CGImage) throws -> [UInt8] {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StitchError.contextCreationFailed
        }
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private func copyRows(
        from source: [UInt8],
        sourceStartY: Int,
        sourceHeight: Int,
        to destination: inout [UInt8],
        destinationStartY: Int,
        bytesPerRow: Int
    ) {
        for row in 0 ..< sourceHeight {
            let sourceStart = (sourceStartY + row) * bytesPerRow
            let destinationStart = (destinationStartY + row) * bytesPerRow
            destination.replaceSubrange(
                destinationStart ..< destinationStart + bytesPerRow,
                with: source[sourceStart ..< sourceStart + bytesPerRow]
            )
        }
    }

    private func makeImage(topDownRGBA: [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
        var quartzRows = [UInt8]()
        quartzRows.reserveCapacity(topDownRGBA.count)
        for row in (0 ..< height).reversed() {
            let start = row * bytesPerRow
            quartzRows.append(contentsOf: topDownRGBA[start ..< start + bytesPerRow])
        }

        guard let provider = CGDataProvider(data: Data(quartzRows) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                  ),
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
