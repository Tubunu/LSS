import Foundation

struct StitchEngine: Sendable {
    private let thresholds: StitchThresholds
    private let overlapDetector: OverlapDetector

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
        overlapDetector = OverlapDetector(thresholds: thresholds)
    }

    func makePlan(frames: [AnalyzedFrame]) throws -> StitchPlan {
        guard frames.count >= 2 else { throw StitchError.insufficientFrames }
        guard let first = frames.first,
              frames.allSatisfy({
                  $0.sourceWidth == first.sourceWidth
                      && $0.sourceHeight == first.sourceHeight
                      && $0.analysisWidth == first.analysisWidth
                      && $0.analysisHeight == first.analysisHeight
              })
        else {
            throw StitchError.incompatibleFrames
        }

        var placements = [FramePlacement(frameIndex: first.index, offsetY: 0)]
        var segments = [StitchSegment]()
        var warnings = [StitchWarning]()
        var outputOffset = 0

        for pairIndex in 0 ..< frames.count - 1 {
            let upper = frames[pairIndex]
            let lower = frames[pairIndex + 1]
            let match = try overlapDetector.detect(upper: upper, lower: lower)
            let warning: StitchWarning?
            if match.confidence < thresholds.minimumConfidence {
                let issue = StitchWarning(
                    kind: .lowConfidence,
                    pairIndex: pairIndex,
                    message: "第 \(pairIndex + 1) 与第 \(pairIndex + 2) 张截图重叠置信度不足"
                )
                warning = issue
                warnings.append(issue)
            } else {
                warning = nil
            }

            outputOffset += match.offset
            placements.append(FramePlacement(frameIndex: lower.index, offsetY: outputOffset))
            segments.append(
                StitchSegment(
                    upperFrameIndex: upper.index,
                    lowerFrameIndex: lower.index,
                    offset: match.offset,
                    overlap: match.overlap,
                    confidence: match.confidence,
                    seam: match.seam,
                    fixedRegions: [],
                    warning: warning,
                    debugCandidates: match.candidates
                )
            )
        }

        return StitchPlan(
            sourceWidth: first.sourceWidth,
            sourceHeight: first.sourceHeight,
            outputHeight: first.sourceHeight + outputOffset,
            placements: placements,
            segments: segments,
            warnings: warnings
        )
    }
}

struct StitchDebugWriter: Sendable {
    func write(plan: StitchPlan, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan).write(to: url, options: .atomic)
    }
}
