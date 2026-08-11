import CoreGraphics
import Foundation

final class FrameAnalyzer: @unchecked Sendable {
    private let thresholds: StitchThresholds

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
    }

    func analyze(image: CGImage, index: Int) throws -> AnalyzedFrame {
        let width = min(image.width, thresholds.analysisWidth)
        let aspectHeight = Int(
            (Double(image.height) / Double(image.width) * Double(width)).rounded()
        )
        let height = min(max(aspectHeight, 1), thresholds.maximumAnalysisHeight, image.height)
        var luminance = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &luminance,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw StitchError.contextCreationFailed
        }

        context.interpolationQuality = .low
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return AnalyzedFrame(
            index: index,
            sourceWidth: image.width,
            sourceHeight: image.height,
            analysisWidth: width,
            analysisHeight: height,
            luminance: luminance
        )
    }
}
