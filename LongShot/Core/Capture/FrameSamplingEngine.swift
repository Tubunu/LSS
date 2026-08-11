import Foundation

struct FrameSamplingEngine: Sendable {
    private(set) var selectedFrameCount = 0

    private let thresholds: FrameSamplingThresholds
    private var lastAnalyzedTimestamp: Double?
    private var lastSelectedTimestamp: Double?
    private var lastSelectedSignature: FrameSignature?

    init(thresholds: FrameSamplingThresholds = .init()) {
        self.thresholds = thresholds
    }

    var canSelectMoreFrames: Bool {
        selectedFrameCount < thresholds.maximumPersistedFrames
    }

    mutating func evaluate(signature: FrameSignature, timestamp: Double) -> FrameSamplingDecision {
        guard canSelectMoreFrames else {
            return rejected(reason: .capacityReached)
        }

        if let lastAnalyzedTimestamp,
           timestamp - lastAnalyzedTimestamp < thresholds.analysisInterval
        {
            return rejected(reason: .analysisInterval)
        }
        lastAnalyzedTimestamp = timestamp

        guard let previous = lastSelectedSignature,
              let lastSelectedTimestamp
        else {
            return FrameSamplingDecision(
                shouldSelect: true,
                reason: .initial,
                score: 1,
                elapsedSinceSelection: 0,
                comparison: nil
            )
        }

        let elapsed = max(0, timestamp - lastSelectedTimestamp)
        let comparison = compare(previous: previous, current: signature)
        let isDuplicate = comparison.hashDistance <= thresholds.duplicateHashDistance
            && comparison.changedPixelRatio <= thresholds.duplicateChangedPixelRatio
        guard !isDuplicate else {
            return rejected(reason: .duplicate, elapsed: elapsed, comparison: comparison)
        }

        guard elapsed >= thresholds.minimumSelectionInterval else {
            return rejected(reason: .selectionInterval, elapsed: elapsed, comparison: comparison)
        }

        let absoluteDisplacement = abs(comparison.verticalDisplacement)
        let minimumDisplacement = max(
            1,
            Int((Double(signature.height) * thresholds.minimumDisplacementRatio).rounded(.up))
        )
        let fastDisplacement = max(
            minimumDisplacement + 1,
            Int((Double(signature.height) * thresholds.fastDisplacementRatio).rounded(.up))
        )
        let ignoredRollback = max(
            minimumDisplacement,
            Int((Double(signature.height) * thresholds.maximumIgnoredRollbackRatio).rounded(.up))
        )
        let matchIsUsable = comparison.matchError <= thresholds.acceptableMatchError
        let score = selectionScore(comparison: comparison, elapsed: elapsed, height: signature.height)

        if comparison.verticalDisplacement < 0, absoluteDisplacement <= ignoredRollback {
            return rejected(reason: .smallRollback, elapsed: elapsed, comparison: comparison, score: score)
        }

        if absoluteDisplacement >= fastDisplacement
            || (!matchIsUsable && comparison.changedPixelRatio >= thresholds.fastChangedPixelRatio)
        {
            return selected(
                reason: .fastMovement,
                score: max(score, 0.75),
                elapsed: elapsed,
                comparison: comparison
            )
        }

        if comparison.verticalDisplacement >= minimumDisplacement, matchIsUsable {
            return selected(reason: .movement, score: score, elapsed: elapsed, comparison: comparison)
        }

        if elapsed >= thresholds.maximumSelectionGap,
           comparison.changedPixelRatio >= thresholds.minimumChangedPixelRatio
        {
            return selected(reason: .maximumGap, score: score, elapsed: elapsed, comparison: comparison)
        }

        return rejected(reason: .insufficientChange, elapsed: elapsed, comparison: comparison, score: score)
    }

    mutating func accept(signature: FrameSignature, timestamp: Double) {
        lastSelectedSignature = signature
        lastSelectedTimestamp = timestamp
        selectedFrameCount += 1
    }

    private func compare(previous: FrameSignature, current: FrameSignature) -> FrameComparison {
        guard previous.width == current.width, previous.height == current.height else {
            return FrameComparison(
                hashDistance: (previous.perceptualHash ^ current.perceptualHash).nonzeroBitCount,
                changedPixelRatio: 1,
                verticalDisplacement: 0,
                matchError: 1,
                zeroDisplacementError: 1,
                motionConfidence: 0
            )
        }

        let changedCount = zip(previous.luminance, current.luminance).reduce(into: 0) { count, pair in
            let difference = abs(Int(pair.0) - Int(pair.1))
            if difference >= Int(thresholds.pixelDifferenceThreshold) {
                count += 1
            }
        }
        let changedRatio = Double(changedCount) / Double(current.luminance.count)
        let maximumShift = max(
            1,
            Int((Double(current.height) * thresholds.maximumSearchDisplacementRatio).rounded(.down))
        )
        let zeroError = meanAbsoluteError(previous: previous, current: current, shift: 0)
        var bestShift = 0
        var bestError = zeroError

        for magnitude in 1 ... maximumShift {
            for shift in [magnitude, -magnitude] {
                let error = meanAbsoluteError(previous: previous, current: current, shift: shift)
                if error < bestError - 0.000_001 {
                    bestError = error
                    bestShift = shift
                }
            }
        }

        let confidence: Double
        if zeroError <= 0.000_001 {
            confidence = 0
        } else {
            confidence = max(0, min(1, (zeroError - bestError) / zeroError))
        }

        return FrameComparison(
            hashDistance: (previous.perceptualHash ^ current.perceptualHash).nonzeroBitCount,
            changedPixelRatio: changedRatio,
            verticalDisplacement: bestShift,
            matchError: bestError,
            zeroDisplacementError: zeroError,
            motionConfidence: confidence
        )
    }

    private func meanAbsoluteError(
        previous: FrameSignature,
        current: FrameSignature,
        shift: Int
    ) -> Double {
        let margin = max(1, current.height / 10)
        let startY = max(margin, -shift)
        let endY = min(current.height - margin, current.height - shift)
        guard endY > startY else { return 1 }

        var totalDifference = 0
        var sampleCount = 0
        for y in startY ..< endY {
            let previousY = y + shift
            for x in 0 ..< current.width {
                let currentValue = current.luminance[y * current.width + x]
                let previousValue = previous.luminance[previousY * previous.width + x]
                totalDifference += abs(Int(currentValue) - Int(previousValue))
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return 1 }
        return Double(totalDifference) / Double(sampleCount * 255)
    }

    private func selectionScore(
        comparison: FrameComparison,
        elapsed: TimeInterval,
        height: Int
    ) -> Double {
        let change = min(1, comparison.changedPixelRatio / max(thresholds.fastChangedPixelRatio, 0.01))
        let motion = min(1, Double(abs(comparison.verticalDisplacement)) / max(Double(height), 1))
        let time = min(1, elapsed / max(thresholds.maximumSelectionGap, 0.01))
        return min(1, change * 0.35 + motion * 0.45 + time * 0.20)
    }

    private func selected(
        reason: FrameSamplingReason,
        score: Double,
        elapsed: TimeInterval,
        comparison: FrameComparison
    ) -> FrameSamplingDecision {
        FrameSamplingDecision(
            shouldSelect: true,
            reason: reason,
            score: score,
            elapsedSinceSelection: elapsed,
            comparison: comparison
        )
    }

    private func rejected(
        reason: FrameSamplingReason,
        elapsed: TimeInterval = 0,
        comparison: FrameComparison? = nil,
        score: Double = 0
    ) -> FrameSamplingDecision {
        FrameSamplingDecision(
            shouldSelect: false,
            reason: reason,
            score: score,
            elapsedSinceSelection: elapsed,
            comparison: comparison
        )
    }
}
