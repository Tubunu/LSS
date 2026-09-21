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

            Section("操作提示") {
                Text("授权后切换到需要截图的 App，缓慢向下滚动。完成后返回 LongShot 并停止。")
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
                if let dir = manager.sessionDirectory {
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
        case .idle: "点击开始后，在系统面板中选择整个屏幕。"
        case .selectingContent: "等待你在系统屏幕共享面板中确认。"
        case .starting: "正在建立本地屏幕帧管线。"
        case .capturing: "可以切换到其他 App 开始滚动。"
        case .stopping: "正在安全释放屏幕捕获流。"
        case .completed: "关键帧已保存，后续阶段将进入拼接。"
        case .failed: "你可以修正问题后重试。"
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
