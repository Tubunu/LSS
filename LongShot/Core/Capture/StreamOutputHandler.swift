@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit

final class StreamOutputHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    typealias SnapshotHandler = @Sendable (CaptureDiagnosticsSnapshot) -> Void

    private let diagnostics: CaptureDiagnostics
    private let sampler: FrameSampler
    private let snapshotHandler: SnapshotHandler

    init(
        diagnostics: CaptureDiagnostics,
        sampler: FrameSampler,
        snapshotHandler: @escaping SnapshotHandler
    ) {
        self.diagnostics = diagnostics
        self.sampler = sampler
        self.snapshotHandler = snapshotHandler
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            diagnostics.recordInvalidFrame()
            snapshotHandler(diagnostics.snapshot())
            return
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let shouldPublish = diagnostics.recordValidFrame(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            timestamp: timestamp
        )
        if sampler.consider(pixelBuffer: pixelBuffer, timestamp: timestamp) {
            diagnostics.recordSelectedFrame()
        }
        if shouldPublish {
            snapshotHandler(diagnostics.snapshot())
        }
    }
}
