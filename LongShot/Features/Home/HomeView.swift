import SwiftUI

struct HomeView: View {
    @ObservedObject var captureManager: ScreenCaptureManager
    @State private var isShowingProcessing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("把滚动页面")
                        Text("变成一张完整截图。")
                    }
                    .font(.largeTitle.bold())
                    .accessibilityElement(children: .combine)

                    if captureManager.state == .completed, let dir = captureManager.sessionDirectory {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("捕获已完成，可生成长图", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Button {
                                isShowingProcessing = true
                            } label: {
                                Label("立即生成长截图", systemImage: "rectangle.compress.vertical")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        NavigationLink {
                            CaptureView(manager: captureManager)
                        } label: {
                            Label("开始滚动截图", systemImage: "rectangle.inset.filled.and.person.filled")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("startScrollingCapture")
                    }

                    Button {} label: {
                        Label("导入截图拼接", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .accessibilityHint("将在后续阶段开放")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近项目")
                            .font(.title2.bold())
                        ContentUnavailableView(
                            "还没有长截图",
                            systemImage: "rectangle.stack",
                            description: Text("完成捕获后，项目会显示在这里。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(24)
            }
            .navigationTitle("LongShot")
            .sheet(isPresented: $isShowingProcessing) {
                if let dir = captureManager.sessionDirectory {
                    ProcessingView(sessionURL: dir)
                }
            }
        }
    }
}

#Preview {
    HomeView(captureManager: ScreenCaptureManager())
}
