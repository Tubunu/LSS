@preconcurrency import CoreImage
@preconcurrency import CoreVideo
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

final class FrameSampler: @unchecked Sendable {
    struct Configuration: Sendable {
        var minimumPersistenceInterval: TimeInterval = 3
        var maximumPersistedFrames = 60
    }

    private let configuration: Configuration
    private let store: TemporaryFrameStore
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var lastPersistedTimestamp: Double?
    private var persistedFrameCount = 0

    init(store: TemporaryFrameStore, configuration: Configuration = .init()) {
        self.store = store
        self.configuration = configuration
    }

    func consider(pixelBuffer: CVPixelBuffer, timestamp: Double) -> Bool {
        guard persistedFrameCount < configuration.maximumPersistedFrames else { return false }
        guard lastPersistedTimestamp.map({ timestamp - $0 >= configuration.minimumPersistenceInterval }) ?? true else {
            return false
        }

        let nextIndex = persistedFrameCount + 1
        guard persist(pixelBuffer: pixelBuffer, to: store.frameURL(index: nextIndex)) else { return false }
        persistedFrameCount = nextIndex
        lastPersistedTimestamp = timestamp
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
}
