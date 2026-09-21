import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

struct MosaicStroke: Sendable, Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var lineWidth: CGFloat

    init(points: [CGPoint] = [], lineWidth: CGFloat = 28) {
        self.points = points
        self.lineWidth = lineWidth
    }
}

struct MosaicRenderer: @unchecked Sendable {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    init() {}

    /// 将马赛克笔迹通过 CoreImage GPU 加速合成到原图中
    func applyMosaic(
        to image: CGImage,
        strokes: [MosaicStroke],
        pixelScale: Float = 24.0
    ) throws -> CGImage {
        guard !strokes.isEmpty else { return image }

        let width = image.width
        let height = image.height
        let ciImage = CIImage(cgImage: image)

        // 1. 生成马赛克底图 (CIPixellate)
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = ciImage
        pixellate.scale = pixelScale
        pixellate.center = CGPoint(x: width / 2, y: height / 2)
        guard let pixellatedImage = pixellate.outputImage else {
            return image
        }

        // 2. 生成黑白遮罩图（笔迹为纯白，其余为纯黑）
        guard let maskCGImage = createMaskImage(
            width: width,
            height: height,
            strokes: strokes
        ) else {
            return image
        }
        let maskCIImage = CIImage(cgImage: maskCGImage)

        // 3. 使用遮罩混合原图与马赛克图 (CIBlendWithMask)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = pixellatedImage
        blend.backgroundImage = ciImage
        blend.maskImage = maskCIImage

        guard let outputCI = blend.outputImage,
              let finalCGImage = context.createCGImage(outputCI, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return image
        }

        return finalCGImage
    }

    private func createMaskImage(
        width: Int,
        height: Int,
        strokes: [MosaicStroke]
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // 填充纯黑色底
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 翻转坐标系，使 (0, 0) 与 SwiftUI / UIKit 保持一致（原点在左上角）
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        // 纯白画笔绘制笔迹
        context.setStrokeColor(gray: 1.0, alpha: 1.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            guard stroke.points.count > 1 else { continue }
            context.setLineWidth(stroke.lineWidth)
            context.beginPath()
            context.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() {
                context.addLine(to: pt)
            }
            context.strokePath()
        }

        return context.makeImage()
    }
}
