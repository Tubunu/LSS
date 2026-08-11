import Foundation

struct OverlapDetector: Sendable {
    private let thresholds: StitchThresholds

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
    }

    func detect(upper: AnalyzedFrame, lower: AnalyzedFrame) throws -> OverlapMatch {
        guard upper.sourceWidth == lower.sourceWidth,
              upper.sourceHeight == lower.sourceHeight,
              upper.analysisWidth == lower.analysisWidth,
              upper.analysisHeight == lower.analysisHeight,
              upper.luminance.count == lower.luminance.count
        else {
            throw StitchError.incompatibleFrames
        }

        let height = upper.analysisHeight
        let minimumDisplacement = max(
            1,
            Int((Double(height) * thresholds.minimumDisplacementRatio).rounded(.up))
        )
        let maximumDisplacement = max(
            minimumDisplacement,
            height - Int((Double(height) * thresholds.minimumOverlapRatio).rounded(.up))
        )
        var candidates = [OverlapCandidate]()
        candidates.reserveCapacity(maximumDisplacement - minimumDisplacement + 1)

        for displacement in minimumDisplacement ... maximumDisplacement {
            candidates.append(
                OverlapCandidate(
                    displacement: displacement,
                    normalizedError: error(
                        upper: upper,
                        lower: lower,
                        displacement: displacement
                    )
                )
            )
        }

        let sorted = candidates.sorted {
            if abs($0.normalizedError - $1.normalizedError) < 0.000_001 {
                return $0.displacement < $1.displacement
            }
            return $0.normalizedError < $1.normalizedError
        }
        guard let best = sorted.first else { throw StitchError.incompatibleFrames }
        let separated = sorted.first {
            abs($0.displacement - best.displacement) >= thresholds.candidateSeparation
        }
        let secondError = separated?.normalizedError ?? 1
        let uniqueness = max(0, min(1, (secondError - best.normalizedError) / max(secondError, 0.000_001)))
        let texture = textureScore(upper: upper, lower: lower, displacement: best.displacement)
        let matchQuality = max(
            0,
            min(1, 1 - best.normalizedError / max(thresholds.acceptableMatchError, 0.000_001))
        )
        let overlapRatio = Double(height - best.displacement) / Double(height)
        let confidence = min(
            1,
            matchQuality * 0.65 + uniqueness * 0.15 + overlapRatio * 0.10 + texture * 0.10
        )
        let sourceScale = Double(upper.sourceHeight) / Double(height)
        let sourceOffset = Int((Double(best.displacement) * sourceScale).rounded())
        let sourceOverlap = upper.sourceHeight - sourceOffset
        let analysisSeam = selectSeam(
            upper: upper,
            lower: lower,
            displacement: best.displacement
        )
        let sourceSeam = min(
            sourceOverlap,
            max(0, Int((Double(analysisSeam) * sourceScale).rounded()))
        )

        return OverlapMatch(
            offset: sourceOffset,
            overlap: sourceOverlap,
            confidence: confidence,
            seam: sourceSeam,
            normalizedError: best.normalizedError,
            uniqueness: uniqueness,
            texture: texture,
            candidates: Array(sorted.prefix(5)).map {
                OverlapCandidate(
                    displacement: Int((Double($0.displacement) * sourceScale).rounded()),
                    normalizedError: $0.normalizedError
                )
            }
        )
    }

    private func error(
        upper: AnalyzedFrame,
        lower: AnalyzedFrame,
        displacement: Int
    ) -> Double {
        let overlap = upper.analysisHeight - displacement
        guard overlap > 0 else { return 1 }
        let horizontalMargin = max(1, upper.analysisWidth / 16)
        var total = 0
        var count = 0

        for lowerY in 0 ..< overlap {
            let upperY = lowerY + displacement
            for x in horizontalMargin ..< (upper.analysisWidth - horizontalMargin) {
                let upperValue = upper.luminance[upperY * upper.analysisWidth + x]
                let lowerValue = lower.luminance[lowerY * lower.analysisWidth + x]
                total += abs(Int(upperValue) - Int(lowerValue))
                count += 1
            }
        }

        guard count > 0 else { return 1 }
        return Double(total) / Double(count * 255)
    }

    private func textureScore(
        upper: AnalyzedFrame,
        lower: AnalyzedFrame,
        displacement: Int
    ) -> Double {
        let overlap = upper.analysisHeight - displacement
        guard overlap > 0 else { return 0 }
        var values = [Double]()
        values.reserveCapacity(overlap * upper.analysisWidth * 2)

        for y in 0 ..< overlap {
            let upperY = y + displacement
            for x in 0 ..< upper.analysisWidth {
                values.append(Double(upper.luminance[upperY * upper.analysisWidth + x]))
                values.append(Double(lower.luminance[y * lower.analysisWidth + x]))
            }
        }

        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Double(values.count)
        return min(1, sqrt(variance) / 64)
    }

    private func selectSeam(
        upper: AnalyzedFrame,
        lower: AnalyzedFrame,
        displacement: Int
    ) -> Int {
        let overlap = upper.analysisHeight - displacement
        let lowerBound = max(
            0,
            Int((Double(overlap) * thresholds.seamSearchLowerBoundRatio).rounded())
        )
        let upperBound = min(
            overlap - 1,
            Int((Double(overlap) * thresholds.seamSearchUpperBoundRatio).rounded())
        )
        let midpoint = overlap / 2
        var bestRow = midpoint
        var bestError = Double.greatestFiniteMagnitude

        guard upperBound >= lowerBound else { return max(0, midpoint) }
        for lowerY in lowerBound ... upperBound {
            let upperY = lowerY + displacement
            var rowTotal = 0
            for x in 0 ..< upper.analysisWidth {
                let upperValue = upper.luminance[upperY * upper.analysisWidth + x]
                let lowerValue = lower.luminance[lowerY * lower.analysisWidth + x]
                rowTotal += abs(Int(upperValue) - Int(lowerValue))
            }
            let rowError = Double(rowTotal) / Double(upper.analysisWidth * 255)
            if rowError < bestError - 0.000_001
                || (abs(rowError - bestError) < 0.000_001
                    && abs(lowerY - midpoint) < abs(bestRow - midpoint))
            {
                bestError = rowError
                bestRow = lowerY
            }
        }

        return bestRow
    }
}
