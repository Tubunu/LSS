@preconcurrency import ScreenCaptureKit

final class ScreenCaptureSession: NSObject, SCStreamDelegate, @unchecked Sendable {
    typealias StopHandler = @Sendable (Error) -> Void

    let frameStore: TemporaryFrameStore
    private var stream: SCStream!
    private let outputHandler: StreamOutputHandler
    private let sampleQueue = DispatchQueue(label: "com.example.LongShot.capture.samples", qos: .userInitiated)
    private let unexpectedStopHandler: StopHandler

    init(
        filter: SCContentFilter,
        frameStore: TemporaryFrameStore,
        diagnostics: CaptureDiagnostics,
        snapshotHandler: @escaping StreamOutputHandler.SnapshotHandler,
        unexpectedStopHandler: @escaping StopHandler
    ) throws {
        self.frameStore = frameStore
        self.unexpectedStopHandler = unexpectedStopHandler
        outputHandler = StreamOutputHandler(
            diagnostics: diagnostics,
            sampler: FrameSampler(store: frameStore),
            snapshotHandler: snapshotHandler
        )

        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        configuration.width = max(Int(filter.contentRect.width * scale), 1)
        configuration.height = max(Int(filter.contentRect.height * scale), 1)
        configuration.capturesAudio = false

        super.init()
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(outputHandler, type: .screen, sampleHandlerQueue: sampleQueue)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    func stop() async throws {
        try await stream.stopCapture()
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        unexpectedStopHandler(error)
    }
}
