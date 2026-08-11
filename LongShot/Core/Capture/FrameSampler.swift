@preconcurrency import CoreImage
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

final class FrameSampler: @unchecked Sendable {
    struct Configuration: Sendable {
        var thresholds = FrameSamplingThresholds()
    }

    private let configuration: Configuration
    private let store: TemporaryFrameStore
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let signatureBuilder: FrameSignatureBuilder
    private var engine: FrameSamplingEngine
    private var metadata = [FrameMetadata]()
    private var lastSignatureTimestamp: Double?

    init(store: TemporaryFrameStore, configuration: Configuration = .init()) {
        self.store = store
        self.configuration = configuration
        signatureBuilder = FrameSignatureBuilder(thresholds: configuration.thresholds)
        engine = FrameSamplingEngine(thresholds: configuration.thresholds)
    }

    func consider(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        guard engine.canSelectMoreFrames else { return false }
        guard lastSignatureTimestamp.map({
            timestamp - $0 >= configuration.thresholds.analysisInterval
        }) ?? true else { return false }
        lastSignatureTimestamp = timestamp

        guard let signature = signatureBuilder.makeSignature(pixelBuffer: pixelBuffer)
        else { return false }

        let decision = engine.evaluate(signature: signature, timestamp: timestamp)
        guard decision.shouldSelect else { return false }

        let nextIndex = engine.selectedFrameCount + 1
        let frameURL = store.frameURL(index: nextIndex)
        guard persist(pixelBuffer: pixelBuffer, to: frameURL) else { return false }

        let comparison = decision.comparison
        let value = FrameMetadata(
            index: nextIndex,
            timestamp: timestamp,
            sourceWidth: CVPixelBufferGetWidth(pixelBuffer),
            sourceHeight: CVPixelBufferGetHeight(pixelBuffer),
            thumbnailWidth: signature.width,
            thumbnailHeight: signature.height,
            perceptualHash: String(format: "%016llx", signature.perceptualHash),
            reason: decision.reason,
            score: decision.score,
            elapsedSinceSelection: decision.elapsedSinceSelection,
            verticalDisplacement: comparison?.verticalDisplacement ?? 0,
            changedPixelRatio: comparison?.changedPixelRatio ?? 0,
            hashDistance: comparison?.hashDistance ?? 0,
            matchError: comparison?.matchError ?? 0,
            motionConfidence: comparison?.motionConfidence ?? 1
        )
        metadata.append(value)
        guard persistMetadata() else {
            metadata.removeLast()
            try? FileManager.default.removeItem(at: frameURL)
            return false
        }

        engine.accept(signature: signature, timestamp: timestamp)
        return true
    }

    private func persist(pixelBuffer: CVPixelBuffer, to url: URL) -> Bool {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else { return false }

        CGImageDestinationAddImage(destination, cgImage, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func persistMetadata() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(metadata)
            try data.write(to: store.frameMetadataURL(), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
