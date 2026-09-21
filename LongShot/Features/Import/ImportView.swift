import CoreGraphics
import PhotosUI
import SwiftUI

struct ImportedScreenshot: Identifiable {
    let id = UUID()
    let image: CGImage
    let uiImage: UIImage
}

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var importedScreenshots: [ImportedScreenshot] = []
    @State private var isLoadingPhotos: Bool = false
    @State private var processingSessionURL: URL?
    @State private var isShowingProcessing: Bool = false
    @State private var errorMessage: String?

    init() {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if importedScreenshots.isEmpty {
                    emptyStateView
                } else {
                    screenshotListView
                }
            }
            .navigationTitle("导入截图拼接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }

                if !importedScreenshots.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        PhotosPicker(
                            selection: $selectedPickerItems,
                            maxSelectionCount: 30,
                            matching: .screenshots
                        ) {
                            Text("加图")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !importedScreenshots.isEmpty {
                    bottomActionBar
                }
            }
            .onChange(of: selectedPickerItems) { _, items in
                Task {
                    await loadSelectedPhotos(items)
                }
            }
            .sheet(isPresented: $isShowingProcessing) {
                if let url = processingSessionURL {
                    ProcessingView(sessionURL: url)
                }
            }
            .overlay {
                if isLoadingPhotos {
                    ProgressView("正在读取相册截图...")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("从系统相册导入截图")
                    .font(.title3.bold())
                Text("按滚动顺序选取 2~30 张截图，系统将自动识别重叠区并拼接为完整长图。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            PhotosPicker(
                selection: $selectedPickerItems,
                maxSelectionCount: 30,
                matching: .screenshots
            ) {
                Label("从相册选择截图", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var screenshotListView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("已选 \(importedScreenshots.count) 张截图")
                    .font(.headline)
                Spacer()
                Text("可点击左右箭头微调顺序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(importedScreenshots.enumerated()), id: \.element.id) { index, item in
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: item.uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color(.separator), lineWidth: 1)
                                    )

                                // 序号徽章
                                Text("\(index + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.blue, in: Circle())
                                    .offset(x: -6, y: 6)
                            }

                            // 顺序微调与删除
                            HStack(spacing: 8) {
                                Button {
                                    moveItem(from: index, to: index - 1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.caption2)
                                }
                                .disabled(index == 0)

                                Button(role: .destructive) {
                                    importedScreenshots.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }

                                Button {
                                    moveItem(from: index, to: index + 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .disabled(index == importedScreenshots.count - 1)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 240)

            Spacer()
        }
        .padding(.top)
    }

    private var bottomActionBar: some View {
        VStack(spacing: 8) {
            Button {
                startStitching()
            } label: {
                Label("开始拼接长图", systemImage: "rectangle.compress.vertical")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(importedScreenshots.count < 2)
        }
        .padding()
        .background(.bar)
    }

    private func moveItem(from: Int, to: Int) {
        guard to >= 0, to < importedScreenshots.count else { return }
        importedScreenshots.swapAt(from, to)
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        var loaded = [ImportedScreenshot]()

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImg = UIImage(data: data),
               let cgImg = uiImg.cgImage {
                loaded.append(ImportedScreenshot(image: cgImg, uiImage: uiImg))
            }
        }

        self.importedScreenshots.append(contentsOf: loaded)
        self.selectedPickerItems = []
        self.isLoadingPhotos = false
    }

    private func startStitching() {
        guard importedScreenshots.count >= 2 else { return }
        do {
            let store = try TemporaryFrameStore()
            // 写入关键帧 PNG 到 session 目录，对接标准拼接管线
            for (idx, item) in importedScreenshots.enumerated() {
                let url = store.frameURL(index: idx)
                if let data = item.uiImage.pngData() {
                    try data.write(to: url, options: .atomic)
                }
            }
            self.processingSessionURL = store.directory
            self.isShowingProcessing = true
        } catch {
            self.errorMessage = "创建拼接会话失败：\(error.localizedDescription)"
        }
    }
}
