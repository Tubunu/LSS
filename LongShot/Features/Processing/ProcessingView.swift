import SwiftUI

struct ProcessingView: View {
    let sessionURL: URL
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = ProcessingCoordinator()
    @State private var isShowingEditor: Bool = false

    init(sessionURL: URL) {
        self.sessionURL = sessionURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 顶部状态提示
                VStack(spacing: 8) {
                    Text(coordinator.phase.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ProgressView(value: coordinator.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .padding(.horizontal)
                }
                .padding(.top)

                // 预览展示区域
                if let image = coordinator.resultImage {
                    VStack(alignment: .leading, spacing: 8) {
                        if !coordinator.resultSlices.isEmpty {
                            Text("已按接缝切分为 \(coordinator.resultSlices.count) 段高清长图")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }

                        ScrollView {
                            Image(decorative: image, scale: 1.0)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                                .padding(.horizontal)
                        }
                    }
                } else if case let .failed(msg) = coordinator.phase {
                    ContentUnavailableView(
                        "生成长截图失败",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(msg)
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }

                Spacer()
            }
            .navigationTitle("生成结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if coordinator.phase == .completed {
                    actionBar
                }
            }
            .sheet(isPresented: $coordinator.showsOversizeSheet) {
                OversizeDecisionSheet(rawHeight: coordinator.oversizeHeight) { strategy in
                    Task {
                        await coordinator.applyOversizeStrategy(strategy)
                    }
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                if let img = coordinator.resultImage {
                    EditorView(baseImage: img)
                }
            }
            .overlay(alignment: .top) {
                if let toast = coordinator.toastMessage {
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
                                coordinator.toastMessage = nil
                            }
                        }
                }
            }
            .task {
                await coordinator.process(sessionURL: sessionURL)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                isShowingEditor = true
            } label: {
                Label("打码", systemImage: "paintbrush.pointed")
                    .frame(minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button {
                coordinator.copyToClipboard()
            } label: {
                Label(
                    coordinator.isCopiedToClipboard ? "已复制" : "复制",
                    systemImage: coordinator.isCopiedToClipboard ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .tint(coordinator.isCopiedToClipboard ? .green : .blue)

            Button {
                Task {
                    await coordinator.saveToPhotos()
                }
            } label: {
                Label(
                    coordinator.isSavedToPhotos ? "已存相册" : "存相册",
                    systemImage: coordinator.isSavedToPhotos ? "checkmark" : "square.and.arrow.down"
                )
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(coordinator.isSavedToPhotos ? .green : .blue)
        }
        .padding()
        .background(.bar)
    }
}
