import SwiftUI

struct MosaicCanvasView: View {
    let imageSize: CGSize
    @Binding var strokes: [MosaicStroke]
    let isPainting: Bool
    @State private var currentStroke: [CGPoint] = []

    init(
        imageSize: CGSize,
        strokes: Binding<[MosaicStroke]>,
        isPainting: Bool = true
    ) {
        self.imageSize = imageSize
        self._strokes = strokes
        self.isPainting = isPainting
    }

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let scaleX = imageSize.width > 0 ? imageSize.width / viewSize.width : 1
            let scaleY = imageSize.height > 0 ? imageSize.height / viewSize.height : 1

            Canvas { context, size in
                // 绘制已有笔迹预览（半透明马赛克网格提示风格）
                for stroke in strokes {
                    var path = Path()
                    guard stroke.points.count > 1 else { continue }
                    // 将图像像素坐标转换为当前 View 坐标
                    let first = CGPoint(x: stroke.points[0].x / scaleX, y: stroke.points[0].y / scaleY)
                    path.move(to: first)
                    for pt in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: pt.x / scaleX, y: pt.y / scaleY))
                    }
                    context.stroke(
                        path,
                        with: .color(.blue.opacity(0.35)),
                        style: StrokeStyle(lineWidth: stroke.lineWidth / scaleX, lineCap: .round, lineJoin: .round)
                    )
                }

                // 绘制正在拖拽中的笔迹
                if currentStroke.count > 1 {
                    var path = Path()
                    path.move(to: currentStroke[0])
                    for pt in currentStroke.dropFirst() {
                        path.addLine(to: pt)
                    }
                    context.stroke(
                        path,
                        with: .color(.blue.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isPainting else { return }
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        guard isPainting, !currentStroke.isEmpty else { return }
                        // 将 View 坐标转换为原始图像绝对像素坐标
                        let pixelPoints = currentStroke.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
                        let stroke = MosaicStroke(points: pixelPoints, lineWidth: 28 * scaleX)
                        strokes.append(stroke)
                        currentStroke = []
                    }
            )
        }
    }
}
