@preconcurrency import ScreenCaptureKit
import SwiftUI
import UIKit

final class ScreenCaptureManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = ScreenCaptureManager()

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var diagnostics = CaptureDiagnosticsSnapshot()
    @Published private(set) var sessionDirectory: URL?
    @Published private(set) var captureStartedAt: Date?
    var autoStopOnForeground: Bool = false

    private let picker = SCContentSharingPicker.shared
    private let captureDiagnostics = CaptureDiagnostics()
    private var session: ScreenCaptureSession?
    private var backgroundStartedAt: Date?
    private var backgroundStartFrameCount: Int?
    private var isIntentionalStop = false
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        picker.add(self)
        picker.isActive = true

        let configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
    }

    private static let pickerStyleSelector = Selector(("presentPickerUsingContentStyle:"))
    private static let pickerBasicSelector = Selector(("present"))

    deinit {
        picker.remove(self)
        picker.isActive = false
    }

    func startCaptureSelection() {
        guard state.canStart, session == nil else { return }
        guard picker.isAvailable else {
            state = .failed(message: "当前设备不允许屏幕捕获")
            return
        }

        captureDiagnostics.reset()
        diagnostics = .init()
        captureStartedAt = nil
        sessionDirectory = nil
        backgroundStartedAt = nil
        backgroundStartFrameCount = nil
        isIntentionalStop = false
        state = .selectingContent

        // 确保激活 Picker
        picker.isActive = true

        // 动态安全探测 Selector，优先官方样式选择器，降级无参选择器，杜绝未捕获异常闪退
        if picker.responds(to: Self.pickerStyleSelector) {
            picker.present(using: .display)
        } else if picker.responds(to: Self.pickerBasicSelector) {
            picker.present()
        } else {
            state = .failed(message: "当前系统的屏幕捕获选择器不可用")
        }
    }

    func stopCapture() {
        guard state.canStop, let session else { return }
        session.setSamplingActive(false)
        state = .stopping
        isIntentionalStop = true
        endBackgroundTaskIfNeeded()

        Task { @MainActor [self, session] in
            do {
                try await session.stop()
                self.session = nil
                state = .completed
                diagnostics = captureDiagnostics.snapshot()
                writeDiagnostics(state: state)
            } catch {
                self.session = nil
                state = .failed(message: "停止失败：\(error.localizedDescription)")
                writeDiagnostics(state: state)
            }
        }
    }

    func reset() {
        guard !state.isBusy else { return }
        session?.setSamplingActive(false)
        endBackgroundTaskIfNeeded()
        state = .idle
        diagnostics = .init()
        captureStartedAt = nil
        sessionDirectory = nil
    }

    func appDidEnterBackground() {
        guard state == .capturing else { return }
        backgroundStartedAt = Date()
        backgroundStartFrameCount = captureDiagnostics.snapshot().validFrames

        // 切入后台（进入目标 App），激活关键帧采样
        session?.setSamplingActive(true)

        // 申请系统后台执行时间片，双重保障在切出 LongShot 期间进程不被系统挂起
        if backgroundTaskIdentifier == .invalid {
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "LongShot.ScreenCapture") { [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    func appDidBecomeActive() {
        endBackgroundTaskIfNeeded()
        // 切回 LongShot 前台，立即暂停关键帧采样，避免 LongShot 界面与多任务动画污染帧序列
        session?.setSamplingActive(false)

        guard let backgroundStartedAt, let backgroundStartFrameCount else {
            // 如果从未切入过后台（如刚在 App 内完成选择器确认并关闭浮层），绝对不能触发停止
            return
        }

        let duration = Date().timeIntervalSince(backgroundStartedAt)
        let snapshot = captureDiagnostics.snapshot()
        let frameDelta = snapshot.validFrames - backgroundStartFrameCount
        captureDiagnostics.recordBackgroundResult(
            frameDelta: frameDelta,
            duration: duration
        )
        diagnostics = captureDiagnostics.snapshot()
        self.backgroundStartedAt = nil
        self.backgroundStartFrameCount = nil
        writeDiagnostics(state: state)

        // 仅当开启自动停止，且确实经历过有效后台录制（时长 >= 2.0s 且有后台帧增量 >= 2）时才自动停止
        if autoStopOnForeground && state == .capturing && duration >= 2.0 && frameDelta >= 2 {
            stopCapture()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }

    private func beginCapture(filter: SCContentFilter) {
        guard session == nil else { return }
        state = .starting

        do {
            let store = try TemporaryFrameStore()
            let newSession = try ScreenCaptureSession(
                filter: filter,
                frameStore: store,
                diagnostics: captureDiagnostics,
                snapshotHandler: { [weak self] snapshot in
                    DispatchQueue.main.async {
                        self?.diagnostics = snapshot
                    }
                },
                unexpectedStopHandler: { [weak self] error in
                    DispatchQueue.main.async {
                        self?.handleUnexpectedStop(error)
                    }
                }
            )
            session = newSession
            sessionDirectory = store.directory

            Task { @MainActor [self, newSession] in
                do {
                    try await newSession.start()
                    guard session === newSession else { return }
                    captureStartedAt = Date()
                    state = .capturing
                    // 在 LongShot 前台等待期间保持静默，切出到目标 App 后再激活采样
                    newSession.setSamplingActive(false)
                    writeDiagnostics(state: state)
                } catch {
                    session = nil
                    state = .failed(message: "启动失败：\(error.localizedDescription)")
                    writeDiagnostics(state: state)
                }
            }
        } catch {
            state = .failed(message: "创建捕获会话失败：\(error.localizedDescription)")
        }
    }

    private func handleUnexpectedStop(_ error: Error) {
        guard !isIntentionalStop else { return }
        session = nil
        endBackgroundTaskIfNeeded()
        let snapshot = captureDiagnostics.snapshot()
        let nsError = error as NSError
        let errorDetail = "\(error.localizedDescription) (代码: \(nsError.code))"
        if snapshot.selectedFrames >= 2 {
            state = .completed
        } else {
            state = .failed(message: "屏幕捕获已中断：\(errorDetail)")
        }
        writeDiagnostics(state: state)
    }

    private func writeDiagnostics(state: CaptureState) {
        guard let sessionDirectory else { return }
        let value = captureDiagnostics.snapshot()
        let payload: [String: Any] = [
            "state": state.title,
            "receivedFrames": value.receivedFrames,
            "validFrames": value.validFrames,
            "invalidFrames": value.invalidFrames,
            "selectedFrames": value.selectedFrames,
            "width": value.width,
            "height": value.height,
            "lastTimestamp": value.lastTimestamp as Any,
            "backgroundFrameDelta": value.backgroundFrameDelta,
            "backgroundDurationSeconds": value.backgroundDuration,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: sessionDirectory.appendingPathComponent("diagnostics.json"), options: .atomic)
        } catch {
            assertionFailure("Failed to persist capture diagnostics: \(error)")
        }
    }
}

extension ScreenCaptureManager: SCContentSharingPickerObserver {
    func contentSharingPicker(
        _: SCContentSharingPicker,
        didCancelFor _: SCStream?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard self?.session == nil else { return }
            self?.state = .idle
        }
    }

    func contentSharingPicker(
        _: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for _: SCStream?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.beginCapture(filter: filter)
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        DispatchQueue.main.async { [weak self] in
            self?.state = .failed(message: "系统选择器启动失败：\(error.localizedDescription)")
        }
    }
}
