import SwiftUI

public struct RecentProjectPreviewSheet: View {
    public let project: RecentProject
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RecentProjectsStore.shared
    @State private var toastMessage: String?
    @State private var isCopied = false
    @State private var isSaved = false

    public init(project: RecentProject) {
        self.project = project
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 缩略图展示
                let thumbURL = store.thumbnailURL(for: project)
                if let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.separator), lineWidth: 1)
                            )
                            .padding(.horizontal)
                    }
                } else {
                    ContentUnavailableView("预览图已失效", systemImage: "photo")
                }

                // 项目元数据
                VStack(spacing: 6) {
                    Text("\(project.width) × \(project.height) px")
                        .font(.headline)
                    Text("生成时间：\(formattedDate(project.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if project.sliceCount > 1 {
                        Text("包含 \(project.sliceCount) 张智能切片")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        store.delete(id: project.id)
                        dismiss()
                    } label: {
                        Label("删除", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        copyThumbnail()
                    } label: {
                        Label(isCopied ? "已复制" : "复制", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(isCopied ? .green : .blue)

                    Button {
                        Task { await saveThumbnail() }
                    } label: {
                        Label(isSaved ? "已保存" : "存相册", systemImage: isSaved ? "checkmark" : "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSaved ? .green : .blue)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("项目详情")
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

    private func copyThumbnail() {
        let thumbURL = store.thumbnailURL(for: project)
        if let uiImg = UIImage(contentsOfFile: thumbURL.path) {
            UIPasteboard.general.image = uiImg
            isCopied = true
            toastMessage = "长截图已复制到剪贴板"
        }
    }

    private func saveThumbnail() async {
        let thumbURL = store.thumbnailURL(for: project)
        if let uiImg = UIImage(contentsOfFile: thumbURL.path), let cgImg = uiImg.cgImage {
            do {
                try await QuickExporter.saveToPhotos(image: cgImg)
                isSaved = true
                toastMessage = "已保存到系统相册"
            } catch {
                toastMessage = error.localizedDescription
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
