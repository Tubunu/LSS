import Foundation

struct StitchEngine: Sendable {
    private let thresholds: StitchThresholds
    private let overlapDetector: OverlapDetector
    private let fixedRegionDetector: FixedRegionDetector

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
        overlapDetector = OverlapDetector(thresholds: thresholds)
        fixedRegionDetector = FixedRegionDetector(thresholds: thresholds)
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

        let fixedRegions = try fixedRegionDetector.detect(frames: frames)
        var placements = [FramePlacement(frameIndex: first.index, offsetY: 0)]
        var segments = [StitchSegment]()
        var skippedFrameIndices = [Int]()
        var warnings = [StitchWarning]()
        var outputOffset = 0
        var upper = first

        for candidateIndex in 1 ..< frames.count {
            let lower = frames[candidateIndex]
            let match = try overlapDetector.detect(
                upper: upper,
                lower: lower,
                excluding: fixedRegions
            )
            if match.confidence < thresholds.minimumConfidence {
                let reverse = try overlapDetector.detect(
                    upper: lower,
                    lower: upper,
                    excluding: fixedRegions
                )
                let rollbackLimit = Int(
                    (Double(first.sourceHeight) * thresholds.maximumMinorRollbackRatio).rounded(.up)
                )
                if reverse.confidence >= thresholds.minimumConfidence,
                   reverse.offset <= rollbackLimit
                {
                    skippedFrameIndices.append(lower.index)
                    warnings.append(
                        StitchWarning(
                            kind: .rollbackRecovered,
                            pairIndex: candidateIndex - 1,
                            message: "第 \(candidateIndex + 1) 张截图为小幅回滚帧，已跳过"
                        )
                    )
                    continue
                }
            }

            let warning: StitchWarning?
            if match.confidence < thresholds.minimumConfidence {
                let issue = StitchWarning(
                    kind: .lowConfidence,
                    pairIndex: candidateIndex - 1,
                    message: "第 \(upper.index + 1) 与第 \(lower.index + 1) 张截图重叠置信度不足"
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
                    fixedRegions: fixedRegions,
                    warning: warning,
                    debugCandidates: match.candidates
                )
            )
            upper = lower
        }

        return StitchPlan(
            sourceWidth: first.sourceWidth,
            sourceHeight: first.sourceHeight,
            outputHeight: first.sourceHeight + outputOffset,
            placements: placements,
            segments: segments,
            skippedFrameIndices: skippedFrameIndices,
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
