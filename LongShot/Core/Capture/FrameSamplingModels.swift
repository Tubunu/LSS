import Foundation

struct FrameSamplingThresholds: Sendable {
    var analysisInterval: TimeInterval = 0.10
    var minimumSelectionInterval: TimeInterval = 0.18
    var maximumSelectionGap: TimeInterval = 1.25
    var maximumPersistedFrames = 240
    var thumbnailWidth = 32
    var maximumThumbnailHeight = 72
    var duplicateHashDistance = 2
    var duplicateChangedPixelRatio = 0.012
    var minimumChangedPixelRatio = 0.035
    var fastChangedPixelRatio = 0.35
    var pixelDifferenceThreshold: UInt8 = 14
    var minimumDisplacementRatio = 0.08
    var fastDisplacementRatio = 0.28
    var maximumSearchDisplacementRatio = 0.48
    var maximumIgnoredRollbackRatio = 0.14
    var acceptableMatchError = 0.16
}

struct FrameSignature: Equatable, Sendable {
    let width: Int
    let height: Int
    let luminance: [UInt8]
    let perceptualHash: UInt64

    init(width: Int, height: Int, luminance: [UInt8]) {
        precondition(width > 0 && height > 0)
        precondition(luminance.count == width * height)
        self.width = width
        self.height = height
        self.luminance = luminance
        perceptualHash = Self.makeAverageHash(width: width, height: height, luminance: luminance)
    }

    private static func makeAverageHash(width: Int, height: Int, luminance: [UInt8]) -> UInt64 {
        var samples = [UInt8]()
        samples.reserveCapacity(64)

        for row in 0 ..< 8 {
            let y = min((row * height + height / 2) / 8, height - 1)
            for column in 0 ..< 8 {
                let x = min((column * width + width / 2) / 8, width - 1)
                samples.append(luminance[y * width + x])
            }
        }

        let average = samples.reduce(0) { $0 + Int($1) } / samples.count
        return samples.enumerated().reduce(into: UInt64(0)) { hash, element in
            if Int(element.element) >= average {
                hash |= UInt64(1) << UInt64(element.offset)
            }
        }
    }
}

struct FrameComparison: Equatable, Sendable {
    var hashDistance: Int
    var changedPixelRatio: Double
    var verticalDisplacement: Int
    var matchError: Double
    var zeroDisplacementError: Double
    var motionConfidence: Double
}

enum FrameSamplingReason: String, Codable, Sendable {
    case initial
    case movement
    case fastMovement
    case maximumGap
    case duplicate
    case insufficientChange
    case analysisInterval
    case selectionInterval
    case smallRollback
    case capacityReached
}

struct FrameSamplingDecision: Equatable, Sendable {
    var shouldSelect: Bool
    var reason: FrameSamplingReason
    var score: Double
    var elapsedSinceSelection: TimeInterval
    var comparison: FrameComparison?
}

struct FrameMetadata: Codable, Equatable, Sendable {
    var index: Int
    var timestamp: Double
    var sourceWidth: Int
    var sourceHeight: Int
    var thumbnailWidth: Int
    var thumbnailHeight: Int
    var perceptualHash: String
    var reason: FrameSamplingReason
    var score: Double
    var elapsedSinceSelection: TimeInterval
    var verticalDisplacement: Int
    var changedPixelRatio: Double
    var hashDistance: Int
    var matchError: Double
    var motionConfidence: Double
}
