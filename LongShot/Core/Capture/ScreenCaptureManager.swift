@preconcurrency import ScreenCaptureKit
import SwiftUI

final class ScreenCaptureManager: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = ScreenCaptureManager()

    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var diagnostics = CaptureDiagnosticsSnapshot()
    @Published private(set) var sessionDirectory: URL?
    @Published private(set) var captureStartedAt: Date?
    var autoStopOnForeground: Bool = true

    private let picker = SCContentSharingPicker.shared
    private let captureDiagnostics = CaptureDiagnostics()
    private var session: ScreenCaptureSession?
    private var backgroundStartedAt: Date?
    private var backgroundStartFrameCount: Int?
    private var isIntentionalStop = false

    override init() {
        super.init()
        picker.add(self)
        picker.isActive = true

        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
    }

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
        picker.present(using: .display)
    }

    func stopCapture() {
        guard state.canStop, let session else { return }
        state = .stopping
        isIntentionalStop = true

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
        state = .idle
        diagnostics = .init()
        captureStartedAt = nil
        sessionDirectory = nil
    }

    func appDidEnterBackground() {
        guard state == .capturing else { return }
        backgroundStartedAt = Date()
        backgroundStartFrameCount = captureDiagnostics.snapshot().validFrames
    }

    func appDidBecomeActive() {
        if let backgroundStartedAt, let backgroundStartFrameCount {
            let snapshot = captureDiagnostics.snapshot()
            captureDiagnostics.recordBackgroundResult(
                frameDelta: snapshot.validFrames - backgroundStartFrameCount,
                duration: Date().timeIntervalSince(backgroundStartedAt)
            )
            diagnostics = captureDiagnostics.snapshot()
            self.backgroundStartedAt = nil
            self.backgroundStartFrameCount = nil
            writeDiagnostics(state: state)
        }

        if autoStopOnForeground && state == .capturing && diagnostics.selectedFrames >= 2 {
            stopCapture()
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
        let snapshot = captureDiagnostics.snapshot()
        if snapshot.selectedFrames >= 2 {
            state = .completed
        } else {
            state = .failed(message: "屏幕捕获已中断：\(error.localizedDescription)")
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
