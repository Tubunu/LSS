import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

@MainActor
final class ProcessingCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingFrames
        case analyzing
        case planning
        case awaitingOversizeDecision(height: Int)
        case rendering
        case completed
        case failed(String)

        var title: String {
            switch self {
            case .idle: "准备中"
            case .loadingFrames: "正在加载关键帧..."
            case .analyzing: "正在分析图像特征..."
            case .planning: "正在规划接缝与对齐..."
            case .awaitingOversizeDecision: "长图尺寸超限，等待处理方式..."
            case .rendering: "正在渲染长截图..."
            case .completed: "长截图已生成！"
            case let .failed(msg): "处理失败：\(msg)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var resultImage: CGImage?
    @Published private(set) var resultSlices: [TileRenderer.SlicedImage] = []
    @Published var showsOversizeSheet: Bool = false
    @Published var oversizeHeight: Int = 0
    @Published var toastMessage: String?
    @Published var isSavedToPhotos: Bool = false
    @Published var isCopiedToClipboard: Bool = false

    private var loadedImages: [CGImage] = []
    private var stitchPlan: StitchPlan?
    private var sessionURL: URL?
    private let engine = StitchEngine()
    private let tileRenderer = TileRenderer()

    init() {}

    func process(sessionURL: URL) async {
        self.sessionURL = sessionURL
        self.phase = .loadingFrames
        self.progress = 0.1

        do {
            // 1. 加载关键帧 PNG
            let urls = try fetchFrameURLs(from: sessionURL)
            guard urls.count >= 2 else {
                self.phase = .failed("有效关键帧不足（少于 2 帧），无法拼接")
                return
            }

            var images = [CGImage]()
            for url in urls {
                if let image = loadImage(from: url) {
                    images.append(image)
                }
            }
            guard images.count >= 2 else {
                self.phase = .failed("关键帧图像加载失败")
                return
            }
            self.loadedImages = images
            self.progress = 0.3

            // 2. 灰度特征分析
            self.phase = .analyzing
            let analyzer = FrameAnalyzer()
            var analyzedFrames = [AnalyzedFrame]()
            for (idx, img) in images.enumerated() {
                let analyzed = try analyzer.analyze(image: img, index: idx)
                analyzedFrames.append(analyzed)
            }
            self.progress = 0.5

            // 3. 规划接缝与固定区剔除
            self.phase = .planning
            let plan = try engine.makePlan(frames: analyzedFrames)
            self.stitchPlan = plan
            self.progress = 0.7

            // 4. 检查是否超过 25,000px 阈值
            if plan.outputHeight > TileRenderer.maxSafeDimension {
                self.oversizeHeight = plan.outputHeight
                self.phase = .awaitingOversizeDecision(height: plan.outputHeight)
                self.showsOversizeSheet = true
                return
            }

            // 正常尺寸：直接渲染
            await executeRender(strategy: .downsample(scale: 1.0))
        } catch {
            self.phase = .failed(error.localizedDescription)
        }
    }

    /// 用户选择策略后继续执行渲染
    func applyOversizeStrategy(_ strategy: TileRenderer.OversizeStrategy) async {
        showsOversizeSheet = false
        await executeRender(strategy: strategy)
    }

    private func executeRender(strategy: TileRenderer.OversizeStrategy) async {
        guard let plan = stitchPlan else { return }
        self.phase = .rendering
        self.progress = 0.85

        do {
            switch strategy {
            case let .downsample(scale):
                let rendered = try tileRenderer.render(plan: plan, images: loadedImages, scale: scale)
                self.resultImage = rendered
                self.resultSlices = []
            case let .slice(maxSliceHeight):
                let slices = try tileRenderer.renderSlices(plan: plan, images: loadedImages, maxSliceHeight: maxSliceHeight)
                self.resultSlices = slices
                self.resultImage = slices.first?.image
            }

            self.progress = 1.0
            self.phase = .completed

            if plan.warnings.contains(where: { $0.kind == .lowConfidence }) {
                self.toastMessage = "长截图已生成！个别接缝若有轻微错位可使用接缝微调。"
            }

            // 记录到最近项目（仅保留轻量缩略图）
            if let img = self.resultImage {
                RecentProjectsStore.shared.record(image: img, sliceCount: self.resultSlices.isEmpty ? 1 : self.resultSlices.count)
            }

            // 5. 渲染成功后，即用即抛清理原始关键帧 PNG
            if let sessionURL = sessionURL {
                SessionGarbageCollector.purgeKeyframes(in: sessionURL)
            }
        } catch {
            self.phase = .failed("渲染拼接长图失败：\(error.localizedDescription)")
        }
    }

    /// 一键复制到剪贴板
    func copyToClipboard() {
        guard let image = resultImage else { return }
        QuickExporter.copyToClipboard(image: image)
        self.isCopiedToClipboard = true
        self.toastMessage = "已复制到剪贴板，可直接去微信粘贴"
    }

    /// 一键存入系统相册
    func saveToPhotos() async {
        do {
            if !resultSlices.isEmpty {
                let slices = resultSlices.map(\.image)
                try await QuickExporter.saveSlicesToPhotos(slices: slices)
                self.isSavedToPhotos = true
                self.toastMessage = "共 \(slices.count) 张切片长图已存入系统相册"
            } else if let image = resultImage {
                try await QuickExporter.saveToPhotos(image: image)
                self.isSavedToPhotos = true
                self.toastMessage = "长截图已存入系统相册"
            }
        } catch {
            self.toastMessage = error.localizedDescription
        }
    }

    private func fetchFrameURLs(from sessionURL: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: sessionURL,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension.lowercased() == "png" && $0.lastPathComponent.hasPrefix("frame-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return image
    }
}
