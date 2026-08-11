@preconcurrency import AVFoundation
@preconcurrency import CoreImage
@preconcurrency import ImageIO
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum Phase0CaptureState: String, Sendable {
    case idle = "尚未开始"
    case selecting = "等待选择整个屏幕"
    case starting = "正在启动"
    case capturing = "正在捕获"
    case stopping = "正在停止"
    case failed = "捕获失败"
}

struct Phase0Snapshot: Sendable {
    let receivedFrames: Int
    let validFrames: Int
    let invalidFrames: Int
    let savedFrames: Int
    let width: Int
    let height: Int
    let lastTimestamp: Double?
}

final class Phase0CaptureManager: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var state: Phase0CaptureState = .idle
    @Published private(set) var snapshot = Phase0Snapshot(
        receivedFrames: 0,
        validFrames: 0,
        invalidFrames: 0,
        savedFrames: 0,
        width: 0,
        height: 0,
        lastTimestamp: nil
    )
    @Published private(set) var backgroundFrameDelta = 0
    @Published private(set) var backgroundDuration: TimeInterval = 0
    @Published private(set) var sessionDirectory: URL?
    @Published var errorMessage: String?

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(label: "com.example.LongShot.phase0.samples", qos: .userInitiated)
    private let counters = Phase0Counters()
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var stream: SCStream?
    private var backgroundStartFrameCount: Int?
    private var backgroundStartedAt: Date?
    private var captureStartedAt: Date?
    private var captureDuration: TimeInterval = 0
    private var sessionID = UUID()

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

    var canStart: Bool {
        stream == nil && state != .selecting && state != .starting && state != .stopping
    }

    var canStop: Bool {
        stream != nil && (state == .capturing || state == .starting)
    }

    func startSelection() {
        guard canStart else { return }
        errorMessage = nil
        backgroundFrameDelta = 0
        backgroundDuration = 0
        backgroundStartFrameCount = nil
        backgroundStartedAt = nil
        captureStartedAt = nil
        captureDuration = 0
        sessionID = UUID()
        counters.reset()
        publish(counters.snapshot())
        state = .selecting

        guard picker.isAvailable else {
            fail(message: "当前设备不允许屏幕捕获。")
            return
        }

        picker.present(using: .display)
    }

    func stopCapture() {
        guard let stream, state != .stopping else { return }
        state = .stopping

        Task { @MainActor [self, stream] in
            do {
                try await stream.stopCapture()
                if let captureStartedAt {
                    captureDuration = Date().timeIntervalSince(captureStartedAt)
                }
                self.stream = nil
                state = .idle
                writeDiagnostics()
            } catch {
                self.stream = nil
                fail(message: "停止失败：\(error.localizedDescription)")
            }
        }
    }

    func appDidEnterBackground() {
        backgroundStartFrameCount = counters.snapshot().validFrames
        backgroundStartedAt = Date()
    }

    func appDidBecomeActive() {
        guard let backgroundStartFrameCount, let backgroundStartedAt else { return }
        backgroundFrameDelta = max(0, counters.snapshot().validFrames - backgroundStartFrameCount)
        backgroundDuration = Date().timeIntervalSince(backgroundStartedAt)
        self.backgroundStartFrameCount = nil
        self.backgroundStartedAt = nil
        writeDiagnostics()
    }

    private func beginCapture(filter: SCContentFilter) {
        guard stream == nil else { return }
        state = .starting

        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        configuration.width = max(Int(filter.contentRect.width * scale), 1)
        configuration.height = max(Int(filter.contentRect.height * scale), 1)
        configuration.capturesAudio = false

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)

        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            stream = newStream
        } catch {
            fail(message: "添加屏幕帧输出失败：\(error.localizedDescription)")
            return
        }

        do {
            let directory = try Phase0FileStore.makeSessionDirectory(id: sessionID)
            sessionDirectory = directory
        } catch {
            errorMessage = "诊断目录创建失败：\(error.localizedDescription)"
        }

        Task { @MainActor [self, newStream] in
            do {
                try await newStream.startCapture()
                guard stream === newStream else { return }
                captureStartedAt = Date()
                state = .capturing
                writeDiagnostics()
            } catch {
                stream = nil
                fail(message: "启动屏幕捕获失败：\(error.localizedDescription)")
            }
        }
    }

    private func receive(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard type == .screen else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            counters.recordInvalidFrame()
            publishIfNeeded(force: true)
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let decision = counters.recordValidFrame(width: width, height: height, timestamp: timestamp)

        if decision.shouldSave,
           let directory = sessionDirectory,
           save(pixelBuffer: pixelBuffer, index: decision.saveIndex, to: directory)
        {
            counters.recordSavedFrame()
        }

        publishIfNeeded(force: decision.shouldPublish)
    }

    private func publishIfNeeded(force: Bool = false) {
        guard force else { return }
        let value = counters.snapshot()
        DispatchQueue.main.async { [weak self] in
            self?.publish(value)
        }
    }

    private func publish(_ value: Phase0Snapshot) {
        snapshot = value
    }

    private func save(pixelBuffer: CVPixelBuffer, index: Int, to directory: URL) -> Bool {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return false }
        let url = directory.appendingPathComponent(String(format: "frame-%02d.png", index))
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }
        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func writeDiagnostics() {
        guard let sessionDirectory else { return }
        let value = counters.snapshot()
        let payload: [String: Any] = [
            "sessionID": sessionID.uuidString,
            "state": state.rawValue,
            "receivedFrames": value.receivedFrames,
            "validFrames": value.validFrames,
            "invalidFrames": value.invalidFrames,
            "savedFrames": value.savedFrames,
            "lastFrameWidth": value.width,
            "lastFrameHeight": value.height,
            "lastTimestamp": value.lastTimestamp as Any,
            "backgroundFrameDelta": backgroundFrameDelta,
            "backgroundDurationSeconds": backgroundDuration,
            "captureDurationSeconds": captureDuration,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: sessionDirectory.appendingPathComponent("diagnostics.json"), options: .atomic)
        } catch {
            errorMessage = "写入诊断信息失败：\(error.localizedDescription)"
        }
    }

    private func fail(message: String) {
        state = .failed
        errorMessage = message
        writeDiagnostics()
    }
}

extension Phase0CaptureManager: SCContentSharingPickerObserver {
    func contentSharingPicker(
        _: SCContentSharingPicker,
        didCancelFor _: SCStream?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard self?.stream == nil else { return }
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
            self?.fail(message: "系统选择器启动失败：\(error.localizedDescription)")
        }
    }
}

extension Phase0CaptureManager: SCStreamOutput {
    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        receive(sampleBuffer, type: type)
    }
}

extension Phase0CaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            guard self?.stream === stream else { return }
            self?.stream = nil
            self?.fail(message: "屏幕捕获已停止：\(error.localizedDescription)")
        }
    }
}

private final class Phase0Counters: @unchecked Sendable {
    struct RecordDecision {
        let shouldSave: Bool
        let saveIndex: Int
        let shouldPublish: Bool
    }

    private let lock = NSLock()
    private var receivedFrames = 0
    private var validFrames = 0
    private var invalidFrames = 0
    private var savedFrames = 0
    private var width = 0
    private var height = 0
    private var lastTimestamp: Double?
    private var lastSavedTimestamp: Double?
    private var lastPublishedTimestamp = 0.0

    func reset() {
        lock.withLock {
            receivedFrames = 0
            validFrames = 0
            invalidFrames = 0
            savedFrames = 0
            width = 0
            height = 0
            lastTimestamp = nil
            lastSavedTimestamp = nil
            lastPublishedTimestamp = 0
        }
    }

    func recordInvalidFrame() {
        lock.withLock {
            receivedFrames += 1
            invalidFrames += 1
        }
    }

    func recordValidFrame(width: Int, height: Int, timestamp: Double) -> RecordDecision {
        lock.withLock {
            receivedFrames += 1
            validFrames += 1
            self.width = width
            self.height = height
            lastTimestamp = timestamp

            let maySave = savedFrames < 8
            let saveIntervalPassed = lastSavedTimestamp.map { timestamp - $0 >= 5 } ?? true
            let shouldSave = maySave && saveIntervalPassed
            if shouldSave {
                lastSavedTimestamp = timestamp
            }
            let shouldPublish = timestamp - lastPublishedTimestamp >= 0.25
            if shouldPublish {
                lastPublishedTimestamp = timestamp
            }

            return RecordDecision(
                shouldSave: shouldSave,
                saveIndex: savedFrames + 1,
                shouldPublish: shouldPublish
            )
        }
    }

    func recordSavedFrame() {
        lock.withLock {
            savedFrames += 1
        }
    }

    func snapshot() -> Phase0Snapshot {
        lock.withLock { makeSnapshot() }
    }

    private func makeSnapshot() -> Phase0Snapshot {
        Phase0Snapshot(
            receivedFrames: receivedFrames,
            validFrames: validFrames,
            invalidFrames: invalidFrames,
            savedFrames: savedFrames,
            width: width,
            height: height,
            lastTimestamp: lastTimestamp
        )
    }
}

private enum Phase0FileStore {
    static func makeSessionDirectory(id: UUID) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("Phase0Frames", isDirectory: true)
        let session = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        return session
    }
}
