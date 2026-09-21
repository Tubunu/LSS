import Foundation

struct StitchThresholds: Sendable {
    var analysisWidth = 48
    var maximumAnalysisHeight = 112
    var minimumDisplacementRatio = 0.04
    var minimumOverlapRatio = 0.25
    var acceptableMatchError = 0.16
    var minimumConfidence = 0.60
    var candidateSeparation = 3
    var seamSearchLowerBoundRatio = 0.20
    var seamSearchUpperBoundRatio = 0.80
    var seamEdgePenaltyWeight = 0.20
    var fixedRegionBlockSize = 4
    var fixedPixelTolerance: UInt8 = 10
    var fixedMinimumEdge: UInt8 = 14
    var fixedMinimumStableEdgeRatio = 0.06
    var fixedMinimumBandCoverageRatio = 0.30
    var fixedMinimumComponentBlocks = 2
    var fixedRegionPadding = 2
    var fixedRegionMinimumFrames = 3
    var maximumFixedBandRatio = 0.30
    var maximumMinorRollbackRatio = 0.16
    var maximumRenderDimension = 32000
}

struct AnalyzedFrame: Equatable, Sendable {
    var index: Int
    var sourceWidth: Int
    var sourceHeight: Int
    var analysisWidth: Int
    var analysisHeight: Int
    var luminance: [UInt8]
}

struct OverlapCandidate: Codable, Equatable, Sendable {
    var displacement: Int
    var normalizedError: Double
}

struct OverlapMatch: Codable, Equatable, Sendable {
    var offset: Int
    var overlap: Int
    var confidence: Double
    var seam: Int
    var normalizedError: Double
    var uniqueness: Double
    var texture: Double
    var candidates: [OverlapCandidate]
}

enum FixedRegionKind: String, Codable, Sendable {
    case topBar
    case bottomBar
    case floating
}

struct FixedRegion: Codable, Equatable, Sendable {
    var kind: FixedRegionKind
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var confidence: Double
}

enum StitchWarningKind: String, Codable, Sendable {
    case lowConfidence
    case incompatibleFrames
    case rollbackRecovered

    var isBlocking: Bool {
        self == .incompatibleFrames
    }
}

struct StitchWarning: Codable, Equatable, Sendable {
    var kind: StitchWarningKind
    var pairIndex: Int
    var message: String
}

struct StitchSegment: Codable, Equatable, Sendable {
    var upperFrameIndex: Int
    var lowerFrameIndex: Int
    var offset: Int
    var overlap: Int
    var confidence: Double
    var seam: Int
    var fixedRegions: [FixedRegion]
    var warning: StitchWarning?
    var debugCandidates: [OverlapCandidate]
}

struct FramePlacement: Codable, Equatable, Sendable {
    var frameIndex: Int
    var offsetY: Int
}

struct StitchPlan: Codable, Equatable, Sendable {
    var sourceWidth: Int
    var sourceHeight: Int
    var outputHeight: Int
    var placements: [FramePlacement]
    var segments: [StitchSegment]
    var skippedFrameIndices: [Int]
    var warnings: [StitchWarning]

    var isRenderable: Bool {
        guard !segments.isEmpty else { return false }
        if warnings.contains(where: { $0.kind == .incompatibleFrames }) {
            return false
        }
        // 若全部接缝均严重低置信度（如两张完全无关图），判定为不可渲染
        let hasUsableSegment = segments.contains { $0.confidence >= 0.50 }
        return hasUsableSegment
    }
}

enum StitchError: LocalizedError, Equatable {
    case insufficientFrames
    case incompatibleFrames
    case lowConfidence
    case renderDimensionExceeded
    case contextCreationFailed
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .insufficientFrames:
            "至少需要两张截图"
        case .incompatibleFrames:
            "截图尺寸或分析数据不兼容"
        case .lowConfidence:
            "部分截图无法可靠匹配，请检查问题接缝"
        case .renderDimensionExceeded:
            "拼接结果超过当前基础渲染器尺寸限制"
        case .contextCreationFailed:
            "无法创建拼接画布"
        case .cropFailed:
            "无法裁剪待拼接截图"
        }
    }
}
