@preconcurrency import CoreImage
@preconcurrency import CoreVideo

final class FrameSignatureBuilder: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let thresholds: FrameSamplingThresholds

    init(thresholds: FrameSamplingThresholds = .init()) {
        self.thresholds = thresholds
    }

    func makeSignature(pixelBuffer: CVPixelBuffer) -> FrameSignature? {
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let width = min(thresholds.thumbnailWidth, sourceWidth)
        let aspectHeight = Int(
            (Double(sourceHeight) / Double(sourceWidth) * Double(width)).rounded()
        )
        let height = min(max(aspectHeight, 1), thresholds.maximumThumbnailHeight, sourceHeight)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = CGFloat(width) / image.extent.width
        let scaleY = CGFloat(height) / image.extent.height
        let thumbnail = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var luminance = [UInt8](repeating: 0, count: width * height)

        luminance.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            context.render(
                thumbnail,
                toBitmap: address,
                rowBytes: width,
                bounds: bounds,
                format: .L8,
                colorSpace: nil
            )
        }

        return FrameSignature(width: width, height: height, luminance: luminance)
    }
}
