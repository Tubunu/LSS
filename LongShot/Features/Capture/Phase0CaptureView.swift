import SwiftUI

struct Phase0CaptureView: View {
    @ObservedObject var manager: Phase0CaptureManager

    var body: some View {
        NavigationStack {
            List {
                Section("Phase 0 真机验证") {
                    LabeledContent("状态", value: manager.state.rawValue)
                    LabeledContent("收到帧", value: "\(manager.snapshot.receivedFrames)")
                    LabeledContent("有效帧", value: "\(manager.snapshot.validFrames)")
                    LabeledContent("无效 / 丢弃", value: "\(manager.snapshot.invalidFrames)")
                    LabeledContent("诊断帧", value: "\(manager.snapshot.savedFrames) / 8")
                    LabeledContent("当前尺寸", value: frameSize)
                    LabeledContent("后台帧增长", value: "\(manager.backgroundFrameDelta)")
                    LabeledContent("后台持续时间", value: backgroundDuration)
                    LabeledContent("最后时间戳", value: lastTimestamp)

                    if manager.backgroundDuration > 0 {
                        Label(
                            gatePassed ? "30 秒后台捕获已通过" : "后台捕获尚未达到 30 秒",
                            systemImage: gatePassed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(gatePassed ? .green : .orange)
                        .accessibilityIdentifier("phase0GateResult")
                    }
                }

                Section("30 秒验收步骤") {
                    Text("1. 点击开始，在系统面板选择整个屏幕。")
                    Text("2. 切换到 Safari 或设置，持续滚动至少 30 秒。")
                    Text("3. 返回 LongShot，确认“后台帧增长”大于 0。")
                    Text("4. 点击停止，再检查落盘的诊断帧。")
                    Text("屏幕内容仅在设备本地处理。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let directory = manager.sessionDirectory {
                    Section("诊断位置") {
                        Text(directory.lastPathComponent)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if let errorMessage = manager.errorMessage {
                    Section("错误") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("LongShot")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("开始 Full Display") {
                        manager.startSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.canStart)

                    Button("停止") {
                        manager.stopCapture()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.canStop)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
    }

    private var frameSize: String {
        guard manager.snapshot.width > 0, manager.snapshot.height > 0 else { return "—" }
        return "\(manager.snapshot.width) × \(manager.snapshot.height)"
    }

    private var lastTimestamp: String {
        guard let value = manager.snapshot.lastTimestamp else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private var backgroundDuration: String {
        manager.backgroundDuration.formatted(.number.precision(.fractionLength(1))) + " 秒"
    }

    private var gatePassed: Bool {
        manager.backgroundDuration >= 30 && manager.backgroundFrameDelta > 0
    }
}

#Preview {
    Phase0CaptureView(manager: Phase0CaptureManager())
}
