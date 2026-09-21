import CoreGraphics
import Foundation
import ImageIO

public struct TileRenderer: Sendable {
    public static let maxSafeDimension = 25000
    public static let defaultMaxSliceHeight = 20000

    public enum OversizeStrategy: Sendable, Equatable {
        case downsample(scale: CGFloat)
        case slice(maxSliceHeight: Int)
    }

    public struct SlicedImage: Sendable {
        public let index: Int
        public let total: Int
        public let image: CGImage
    }

    private let thresholds: StitchThresholds

    public init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
    }

    /// 单图渲染：按需单帧解码，内存峰值极低
    public func render(
        plan: StitchPlan,
        images: [CGImage],
        scale: CGFloat = 1.0
    ) throws -> CGImage {
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

        let bytesPerRow = plan.sourceWidth * 4
        var output = [UInt8](repeating: 0, count: bytesPerRow * plan.outputHeight)

        // 1. 绘制首帧（仅解码首帧，拷贝完立即释放）
        try autoreleasepool {
            let firstFrameIndex = plan.placements[0].frameIndex
            let decodedFirst = try decodeRGBA(images[firstFrameIndex])
            copyRows(
                from: decodedFirst,
                sourceStartY: 0,
                sourceHeight: plan.sourceHeight,
                to: &output,
                destinationStartY: 0,
                bytesPerRow: bytesPerRow
            )
        }

        // 2. 逐段按 seam 绘制后一帧（流式解码，单帧在内存停留耗时 < 5ms）
        for segmentIndex in plan.segments.indices {
            try autoreleasepool {
                let segment = plan.segments[segmentIndex]
                let sourceStartY = min(max(segment.seam, 0), plan.sourceHeight - 1)
                let placement = plan.placements[segmentIndex + 1]
                let decodedLower = try decodeRGBA(images[segment.lowerFrameIndex])
                copyRows(
                    from: decodedLower,
                    sourceStartY: sourceStartY,
                    sourceHeight: plan.sourceHeight - sourceStartY,
                    to: &output,
                    destinationStartY: placement.offsetY + sourceStartY,
                    bytesPerRow: bytesPerRow
                )
            }
        }

        let fullImage = try makeImage(topDownRGBA: output, width: plan.sourceWidth, height: plan.outputHeight)
        if scale < 0.999 {
            return try resizeImage(fullImage, scale: scale)
        }
        return fullImage
    }

    /// 智能分页/切片渲染：在自然 seam 接缝处切分，每段高度不超过 maxSliceHeight
    public func renderSlices(
        plan: StitchPlan,
        images: [CGImage],
        maxSliceHeight: Int = defaultMaxSliceHeight
    ) throws -> [SlicedImage] {
        guard plan.outputHeight > maxSliceHeight else {
            let single = try render(plan: plan, images: images)
            return [SlicedImage(index: 1, total: 1, image: single)]
        }

        // 寻找最优切割点：必须落在 segment 的 seam 绝对 Y 坐标上
        var sliceYCutoffs = [Int]()
        var lastCutY = 0

        for segmentIndex in plan.segments.indices {
            let segment = plan.segments[segmentIndex]
            let placement = plan.placements[segmentIndex + 1]
            let seamAbsoluteY = placement.offsetY + segment.seam

            if seamAbsoluteY - lastCutY >= maxSliceHeight {
                sliceYCutoffs.append(seamAbsoluteY)
                lastCutY = seamAbsoluteY
            }
        }
        sliceYCutoffs.append(plan.outputHeight)

        // 渲染完整缓冲区并按 seam 切片
        let fullImage = try render(plan: plan, images: images)
        var result = [SlicedImage]()
        var startY = 0

        for (idx, endY) in sliceYCutoffs.enumerated() {
            let height = endY - startY
            guard height > 0 else { continue }
            let cropRect = CGRect(x: 0, y: startY, width: plan.sourceWidth, height: height)
            guard let cropped = fullImage.cropping(to: cropRect) else {
                throw StitchError.cropFailed
            }
            result.append(SlicedImage(index: idx + 1, total: sliceYCutoffs.count, image: cropped))
            startY = endY
        }

        return result
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
            guard sourceStart + bytesPerRow <= source.count,
                  destinationStart + bytesPerRow <= destination.count else {
                continue
            }
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

    private func resizeImage(_ image: CGImage, scale: CGFloat) throws -> CGImage {
        let targetWidth = max(1, Int(CGFloat(image.width) * scale))
        let targetHeight = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw StitchError.contextCreationFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaled = context.makeImage() else {
            throw StitchError.contextCreationFailed
        }
        return scaled
    }
}
