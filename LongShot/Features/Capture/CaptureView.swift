import SwiftUI

struct CaptureView: View {
    @ObservedObject var manager: ScreenCaptureManager
    @State private var showsGuide = false
    @State private var showsProcessing = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(manager.state.title, systemImage: stateIcon)
                        .font(.title3.bold())
                        .foregroundStyle(stateColor)
                    Text(statusDetail)
                        .foregroundStyle(.secondary)

                    if manager.state == .capturing {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("已成功开启录制！请直接上滑切换到目标 App 缓慢滚动。")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 8)
            }

            Section("捕获状态") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("已用时", value: elapsed(at: context.date))
                }
                LabeledContent("已选关键帧", value: "\(manager.diagnostics.selectedFrames)")
                LabeledContent("有效帧", value: "\(manager.diagnostics.validFrames)")
                LabeledContent("后台帧增长", value: "\(manager.diagnostics.backgroundFrameDelta)")
            }

            Section("录制设置") {
                Toggle("切回 LongShot 自动结束录制", isOn: $manager.autoStopOnForeground)
                Text("默认关闭（建议手动点击「停止捕获」）。开启后，在外部 App 滚动至少 2 秒后切回 LongShot 将自动停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("操作提示") {
                Text("1. 点击「开始捕获」并在弹窗中选择「共享整个屏幕」。\n2. 关闭弹窗后，直接上滑切换到需要长截图的 App 缓慢向下滚动。\n3. 截屏完毕切回 LongShot 点击「停止捕获」，或点击顶部红点停止。")
                    .font(.footnote)
                Label("屏幕内容仅在设备本地处理", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("滚动截图")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("帮助", systemImage: "questionmark.circle") {
                    showsGuide = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $showsGuide) {
            CaptureGuideView()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if manager.state.canStart {
                Button("开始捕获") {
                    manager.startCaptureSelection()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("beginCapture")
            }
            if manager.state.canStop {
                Button("停止捕获", role: .destructive) {
                    manager.stopCapture()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("stopCapture")
            }
            if manager.state == .completed {
                if manager.sessionDirectory != nil {
                    Button("生成长截图") {
                        showsProcessing = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("重置") {
                    manager.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
        .sheet(isPresented: $showsProcessing) {
            if let dir = manager.sessionDirectory {
                ProcessingView(sessionURL: dir)
            }
        }
    }

    private var stateIcon: String {
        switch manager.state {
        case .idle: "record.circle"
        case .selectingContent, .starting: "ellipsis.circle"
        case .capturing: "record.circle.fill"
        case .stopping: "stop.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch manager.state {
        case .capturing: .red
        case .completed: .green
        case .failed: .orange
        default: .primary
        }
    }

    private var statusDetail: String {
        switch manager.state {
        case .idle: "点击下方按钮，在弹出的系统面板中选择整个屏幕。"
        case .selectingContent: "系统选择器已唤起：请选择「共享整个屏幕」并确认。若未开始请重试。"
        case .starting: "正在建立本地屏幕捕获流与帧采集管线..."
        case .capturing: "正在录制！请切换到目标 App 缓慢向下滚动。录制完成后返回点击「停止捕获」。"
        case .stopping: "正在安全停止屏幕流并保存关键帧..."
        case .completed: "关键帧采集完成，可点击下方按钮生成长截图。"
        case .failed: "捕获未成功，你可以检查授权后重试。"
        }
    }

    private func elapsed(at date: Date) -> String {
        guard let startedAt = manager.captureStartedAt else { return "00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CaptureGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Label("选择整个屏幕", systemImage: "1.circle.fill")
                Label("切换到需要截图的 App", systemImage: "2.circle.fill")
                Label("缓慢向下滚动，可以短暂停顿", systemImage: "3.circle.fill")
                Label("返回 LongShot 并停止", systemImage: "4.circle.fill")
            }
            .navigationTitle("如何捕获")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        CaptureView(manager: ScreenCaptureManager())
    }
}
