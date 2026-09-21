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
        var skippedFrameIndices = [Int]()
        var warnings = [StitchWarning]()

        // 1. 前导无关帧智能寻优：
        // 若首帧与第 1 帧完全不匹配，但第 1 帧与第 2 帧匹配良好，说明第 0 帧为无关前导过渡帧，自动跳过
        var startIndex = 0
        if frames.count >= 3 {
            let maxLeadInCheck = min(2, frames.count - 2)
            while startIndex < maxLeadInCheck {
                let testMatch = try overlapDetector.detect(
                    upper: frames[startIndex],
                    lower: frames[startIndex + 1],
                    excluding: fixedRegions
                )
                if testMatch.confidence >= thresholds.minimumConfidence {
                    break // 首对匹配良好，无需跳帧
                }

                // 检查下一对是否匹配良好
                let nextPairMatch = try overlapDetector.detect(
                    upper: frames[startIndex + 1],
                    lower: frames[startIndex + 2],
                    excluding: fixedRegions
                )
                if nextPairMatch.confidence >= thresholds.minimumConfidence {
                    skippedFrameIndices.append(frames[startIndex].index)
                    warnings.append(
                        StitchWarning(
                            kind: .rollbackRecovered,
                            pairIndex: startIndex,
                            message: "第 \(startIndex + 1) 张截图为过渡前导帧，已自动跳过"
                        )
                    )
                    startIndex += 1
                } else {
                    break
                }
            }
        }

        let effectiveFirst = frames[startIndex]
        var placements = [FramePlacement(frameIndex: effectiveFirst.index, offsetY: 0)]
        var segments = [StitchSegment]()
        var outputOffset = 0
        var upper = effectiveFirst

        var candidateIndex = startIndex + 1
        while candidateIndex < frames.count {
            let lower = frames[candidateIndex]
            let match = try overlapDetector.detect(
                upper: upper,
                lower: lower,
                excluding: fixedRegions
            )

            if match.confidence < thresholds.minimumConfidence {
                // A. 尝试反向回滚检测
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
                    candidateIndex += 1
                    continue
                }

                // B. 前瞻单帧跳跃探测 (Lookahead 1)
                if candidateIndex + 1 < frames.count {
                    let nextLower = frames[candidateIndex + 1]
                    let lookaheadMatch = try overlapDetector.detect(
                        upper: upper,
                        lower: nextLower,
                        excluding: fixedRegions
                    )
                    if lookaheadMatch.confidence >= thresholds.minimumConfidence {
                        skippedFrameIndices.append(lower.index)
                        warnings.append(
                            StitchWarning(
                                kind: .rollbackRecovered,
                                pairIndex: candidateIndex - 1,
                                message: "第 \(candidateIndex + 1) 张截图为瞬态跳帧，已跳过"
                            )
                        )
                        outputOffset += lookaheadMatch.offset
                        placements.append(FramePlacement(frameIndex: nextLower.index, offsetY: outputOffset))
                        segments.append(
                            StitchSegment(
                                upperFrameIndex: upper.index,
                                lowerFrameIndex: nextLower.index,
                                offset: lookaheadMatch.offset,
                                overlap: lookaheadMatch.overlap,
                                confidence: lookaheadMatch.confidence,
                                seam: lookaheadMatch.seam,
                                fixedRegions: fixedRegions,
                                warning: nil,
                                debugCandidates: lookaheadMatch.candidates
                            )
                        )
                        upper = nextLower
                        candidateIndex += 2
                        continue
                    }
                }

                // C. 尾部孤立无关帧修剪：若已有有效段且当前已是最后一帧，直接忽略尾部垃圾帧
                if candidateIndex == frames.count - 1, !segments.isEmpty {
                    skippedFrameIndices.append(lower.index)
                    warnings.append(
                        StitchWarning(
                            kind: .rollbackRecovered,
                            pairIndex: candidateIndex - 1,
                            message: "尾部第 \(candidateIndex + 1) 张截图为切换过渡帧，已自动修剪"
                        )
                    )
                    break
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
            candidateIndex += 1
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
