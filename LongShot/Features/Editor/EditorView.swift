import SwiftUI

public struct EditorView: View {
    public let baseImage: CGImage
    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [MosaicStroke] = []
    @State private var isPaintingMode: Bool = true
    @State private var toastMessage: String?
    @State private var isSaved: Bool = false
    @State private var isCopied: Bool = false
    @State private var isProcessing: Bool = false

    private let renderer = MosaicRenderer()

    public init(baseImage: CGImage) {
        self.baseImage = baseImage
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 编辑区域
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: baseImage, scale: 1.0)
                            .resizable()
                            .scaledToFit()

                        MosaicCanvasView(
                            imageSize: CGSize(width: baseImage.width, height: baseImage.height),
                            strokes: $strokes,
                            isPainting: isPaintingMode
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                // 底部工具条
                editorToolbar
            }
            .navigationTitle("编辑与打码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation {
                                toastMessage = nil
                            }
                        }
                }
            }
        }
    }

    private var editorToolbar: some View {
        VStack(spacing: 12) {
            // 工具选项行：画笔/浏览切换与撤销
            HStack(spacing: 16) {
                Button {
                    isPaintingMode.toggle()
                } label: {
                    Label(
                        isPaintingMode ? "涂抹中" : "浏览长图",
                        systemImage: isPaintingMode ? "paintbrush.pointed.fill" : "hand.draw"
                    )
                    .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
                .tint(isPaintingMode ? .blue : .secondary)

                Button {
                    if !strokes.isEmpty {
                        strokes.removeLast()
                    }
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(strokes.isEmpty)

                if !strokes.isEmpty {
                    Button("清空", role: .destructive) {
                        strokes.removeAll()
                    }
                    .font(.subheadline)
                }

                Spacer()

                Text("已打码 \(strokes.count) 处")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Divider()

            // 导出动作行
            HStack(spacing: 12) {
                Button {
                    exportToClipboard()
                } label: {
                    Label(isCopied ? "已复制" : "复制到剪贴板", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(isCopied ? .green : .blue)

                Button {
                    Task { await exportToPhotos() }
                } label: {
                    Label(isSaved ? "已保存" : "保存到相册", systemImage: isSaved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSaved ? .green : .blue)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
    }

    private func getFinalImage() -> CGImage {
        guard !strokes.isEmpty else { return baseImage }
        return (try? renderer.applyMosaic(to: baseImage, strokes: strokes)) ?? baseImage
    }

    private func exportToClipboard() {
        let finalImg = getFinalImage()
        QuickExporter.copyToClipboard(image: finalImg)
        isCopied = true
        toastMessage = "已复制带马赛克的长图，可直接去微信粘贴"
    }

    private func exportToPhotos() async {
        let finalImg = getFinalImage()
        do {
            try await QuickExporter.saveToPhotos(image: finalImg)
            isSaved = true
            toastMessage = "带马赛克的长图已存入系统相册"
        } catch {
            toastMessage = error.localizedDescription
        }
    }
}
