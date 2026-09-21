import SwiftUI

struct HomeView: View {
    @ObservedObject var captureManager: ScreenCaptureManager
    @ObservedObject private var recentStore = RecentProjectsStore.shared

    @State private var isShowingProcessing = false
    @State private var customProcessingURL: URL?
    @State private var recoverableSession: RecoverableSession?
    @State private var selectedRecentProject: RecentProject?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // 异常会话恢复横幅
                    if let recoverable = recoverableSession {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.orange)
                                Text("发现未完成的截图任务")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(recoverable.frameCount) 张关键帧")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("上次捕获可能因切换或异常中断，关键帧已完好保存在本机，是否恢复拼接？")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                Button("恢复拼接") {
                                    customProcessingURL = recoverable.directory
                                    isShowingProcessing = true
                                    recoverableSession = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)

                                Button("放弃") {
                                    SessionRecovery.discard(session: recoverable)
                                    recoverableSession = nil
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("把滚动页面")
                        Text("变成一张完整截图。")
                    }
                    .font(.largeTitle.bold())
                    .accessibilityElement(children: .combine)

                    if captureManager.state == .completed, captureManager.sessionDirectory != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("捕获已完成，可生成长图", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Button {
                                customProcessingURL = nil
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

                    NavigationLink {
                        ImportView()
                    } label: {
                        Label("导入截图拼接", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)

                    // 最近项目流
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("最近项目")
                                .font(.title2.bold())
                            Spacer()
                            if !recentStore.projects.isEmpty {
                                Text("\(recentStore.projects.count) 项")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if recentStore.projects.isEmpty {
                            ContentUnavailableView(
                                "还没有长截图",
                                systemImage: "rectangle.stack",
                                description: Text("完成捕获后，项目会显示在这里。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(recentStore.projects) { project in
                                        let thumbURL = recentStore.thumbnailURL(for: project)
                                        VStack(alignment: .leading, spacing: 6) {
                                            if let uiImg = UIImage(contentsOfFile: thumbURL.path) {
                                                Image(uiImage: uiImg)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 110, height: 180)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(Color(.separator), lineWidth: 1)
                                                    )
                                            } else {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(Color(.secondarySystemGroupedBackground))
                                                    .frame(width: 110, height: 180)
                                            }

                                            Text("\(project.width)×\(project.height)")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.primary)

                                            if project.sliceCount > 1 {
                                                Text("\(project.sliceCount) 张切片")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        .onTapGesture {
                                            selectedRecentProject = project
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("LongShot")
            .onAppear {
                recoverableSession = SessionRecovery.findRecoverableSession()
            }
            .sheet(isPresented: $isShowingProcessing) {
                if let url = customProcessingURL ?? captureManager.sessionDirectory {
                    ProcessingView(sessionURL: url)
                }
            }
            .sheet(item: $selectedRecentProject) { project in
                RecentProjectPreviewSheet(project: project)
            }
        }
    }
}

#Preview {
    HomeView(captureManager: ScreenCaptureManager())
}
