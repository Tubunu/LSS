import Foundation

struct FixedRegionDetector: Sendable {
    private let thresholds: StitchThresholds

    init(thresholds: StitchThresholds = .init()) {
        self.thresholds = thresholds
    }

    func detect(frames: [AnalyzedFrame]) throws -> [FixedRegion] {
        guard frames.count >= thresholds.fixedRegionMinimumFrames else { return [] }
        guard let first = frames.first,
              frames.allSatisfy({
                  $0.sourceWidth == first.sourceWidth
                      && $0.sourceHeight == first.sourceHeight
                      && $0.analysisWidth == first.analysisWidth
                      && $0.analysisHeight == first.analysisHeight
                      && $0.luminance.count == first.luminance.count
              })
        else {
            throw StitchError.incompatibleFrames
        }

        let blockSize = max(2, thresholds.fixedRegionBlockSize)
        let columns = Int(ceil(Double(first.analysisWidth) / Double(blockSize)))
        let rows = Int(ceil(Double(first.analysisHeight) / Double(blockSize)))
        var active = [Bool](repeating: false, count: columns * rows)
        var scores = [Double](repeating: 0, count: columns * rows)

        for blockY in 0 ..< rows {
            for blockX in 0 ..< columns {
                let minX = blockX * blockSize
                let maxX = min(minX + blockSize, first.analysisWidth)
                let minY = blockY * blockSize
                let maxY = min(minY + blockSize, first.analysisHeight)
                var stableEdges = 0
                var pixels = 0

                for y in minY ..< maxY {
                    for x in minX ..< maxX {
                        pixels += 1
                        guard isStableEdge(x: x, y: y, frames: frames) else { continue }
                        stableEdges += 1
                    }
                }

                let ratio = pixels > 0 ? Double(stableEdges) / Double(pixels) : 0
                let index = blockY * columns + blockX
                scores[index] = ratio
                active[index] = ratio >= thresholds.fixedMinimumStableEdgeRatio
            }
        }

        var consumed = [Bool](repeating: false, count: active.count)
        var analysisRegions = [AnalysisRegion]()
        let bandRows = (0 ..< rows).map { blockY in
            let count = (0 ..< columns).filter { active[blockY * columns + $0] }.count
            return Double(count) / Double(columns) >= thresholds.fixedMinimumBandCoverageRatio
        }
        for range in contiguousRanges(values: bandRows) {
            guard range.count >= 2 else { continue }
            let indices = range.flatMap { blockY in
                (0 ..< columns).compactMap { blockX -> Int? in
                    let index = blockY * columns + blockX
                    guard active[index] else { return nil }
                    consumed[index] = true
                    return index
                }
            }
            guard !indices.isEmpty else { continue }
            analysisRegions.append(
                makeBand(
                    rowRange: range,
                    indices: indices,
                    scores: scores,
                    frame: first,
                    blockSize: blockSize
                )
            )
        }

        let hasTopAnchor = analysisRegions.contains { $0.kind == .topBar }
        let hasBottomAnchor = analysisRegions.contains { $0.kind == .bottomBar }
        guard hasTopAnchor, hasBottomAnchor else {
            return []
        }

        for start in active.indices where active[start] && !consumed[start] {
            var queue = [start]
            var component = [Int]()
            consumed[start] = true
            while let current = queue.popLast() {
                component.append(current)
                let x = current % columns
                let y = current / columns
                for deltaY in -1 ... 1 {
                    for deltaX in -1 ... 1 where deltaX != 0 || deltaY != 0 {
                        let nextX = x + deltaX
                        let nextY = y + deltaY
                        guard nextX >= 0, nextX < columns, nextY >= 0, nextY < rows else { continue }
                        let next = nextY * columns + nextX
                        guard active[next], !consumed[next] else { continue }
                        consumed[next] = true
                        queue.append(next)
                    }
                }
            }

            guard component.count >= thresholds.fixedMinimumComponentBlocks else { continue }
            let blockXs = component.map { $0 % columns }
            let blockYs = component.map { $0 / columns }
            analysisRegions.append(
                AnalysisRegion(
                    kind: .floating,
                    minX: max(0, (blockXs.min() ?? 0) * blockSize - thresholds.fixedRegionPadding),
                    minY: max(0, (blockYs.min() ?? 0) * blockSize - thresholds.fixedRegionPadding),
                    maxX: min(
                        first.analysisWidth,
                        ((blockXs.max() ?? 0) + 1) * blockSize + thresholds.fixedRegionPadding
                    ),
                    maxY: min(
                        first.analysisHeight,
                        ((blockYs.max() ?? 0) + 1) * blockSize + thresholds.fixedRegionPadding
                    ),
                    confidence: confidence(indices: component, scores: scores)
                )
            )
        }

        return analysisRegions
            .filter { $0.maxX > $0.minX && $0.maxY > $0.minY }
            .map { scale(region: $0, frame: first) }
            .sorted { lhs, rhs in
                lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
            }
    }

    private func isStableEdge(x: Int, y: Int, frames: [AnalyzedFrame]) -> Bool {
        guard let first = frames.first else { return false }
        let index = y * first.analysisWidth + x
        var minimum = UInt8.max
        var maximum = UInt8.min
        for frame in frames {
            let value = frame.luminance[index]
            minimum = min(minimum, value)
            maximum = max(maximum, value)
        }
        guard Int(maximum) - Int(minimum) <= Int(thresholds.fixedPixelTolerance) else { return false }

        let left = first.luminance[y * first.analysisWidth + max(0, x - 1)]
        let right = first.luminance[y * first.analysisWidth + min(first.analysisWidth - 1, x + 1)]
        let above = first.luminance[max(0, y - 1) * first.analysisWidth + x]
        let below = first.luminance[min(first.analysisHeight - 1, y + 1) * first.analysisWidth + x]
        let edge = max(abs(Int(left) - Int(right)), abs(Int(above) - Int(below)))
        return edge >= Int(thresholds.fixedMinimumEdge)
    }

    private func contiguousRanges(values: [Bool]) -> [ClosedRange<Int>] {
        var ranges = [ClosedRange<Int>]()
        var start: Int?
        for index in values.indices {
            if values[index], start == nil {
                start = index
            }
            if !values[index], let currentStart = start {
                ranges.append(currentStart ... index - 1)
                start = nil
            }
        }
        if let start {
            ranges.append(start ... values.count - 1)
        }
        return ranges
    }

    private func makeBand(
        rowRange: ClosedRange<Int>,
        indices: [Int],
        scores: [Double],
        frame: AnalyzedFrame,
        blockSize: Int
    ) -> AnalysisRegion {
        var minY = max(0, rowRange.lowerBound * blockSize - thresholds.fixedRegionPadding)
        var maxY = min(
            frame.analysisHeight,
            (rowRange.upperBound + 1) * blockSize + thresholds.fixedRegionPadding
        )
        let edgeTolerance = blockSize * 2
        let maximumBandHeight = Int(
            (Double(frame.analysisHeight) * thresholds.maximumFixedBandRatio).rounded(.up)
        )
        let kind: FixedRegionKind
        if minY <= edgeTolerance, maxY <= maximumBandHeight {
            minY = 0
            kind = .topBar
        } else if maxY >= frame.analysisHeight - edgeTolerance,
                  minY >= frame.analysisHeight - maximumBandHeight
        {
            maxY = frame.analysisHeight
            kind = .bottomBar
        } else {
            kind = .floating
        }
        return AnalysisRegion(
            kind: kind,
            minX: 0,
            minY: minY,
            maxX: frame.analysisWidth,
            maxY: maxY,
            confidence: confidence(indices: indices, scores: scores)
        )
    }

    private func confidence(indices: [Int], scores: [Double]) -> Double {
        let average = indices.reduce(0) { $0 + scores[$1] } / Double(max(indices.count, 1))
        return min(
            1,
            0.60 + average / max(thresholds.fixedMinimumStableEdgeRatio, 0.01) * 0.20
        )
    }

    private func scale(region: AnalysisRegion, frame: AnalyzedFrame) -> FixedRegion {
        let scaleX = Double(frame.sourceWidth) / Double(frame.analysisWidth)
        let scaleY = Double(frame.sourceHeight) / Double(frame.analysisHeight)
        let x = Int((Double(region.minX) * scaleX).rounded(.down))
        let y = Int((Double(region.minY) * scaleY).rounded(.down))
        let endX = Int((Double(region.maxX) * scaleX).rounded(.up))
        let endY = Int((Double(region.maxY) * scaleY).rounded(.up))
        return FixedRegion(
            kind: region.kind,
            x: x,
            y: y,
            width: min(frame.sourceWidth, endX) - x,
            height: min(frame.sourceHeight, endY) - y,
            confidence: region.confidence
        )
    }
}

private struct AnalysisRegion {
    var kind: FixedRegionKind
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int
    var confidence: Double
}

struct FixedRegionMask: Sendable {
    let width: Int
    let height: Int
    private let excluded: [Bool]

    init(frame: AnalyzedFrame, regions: [FixedRegion]) {
        width = frame.analysisWidth
        height = frame.analysisHeight
        var values = [Bool](repeating: false, count: width * height)
        let scaleX = Double(width) / Double(frame.sourceWidth)
        let scaleY = Double(height) / Double(frame.sourceHeight)

        for region in regions {
            let minX = max(0, Int((Double(region.x) * scaleX).rounded(.down)))
            let minY = max(0, Int((Double(region.y) * scaleY).rounded(.down)))
            let maxX = min(width, Int((Double(region.x + region.width) * scaleX).rounded(.up)))
            let maxY = min(height, Int((Double(region.y + region.height) * scaleY).rounded(.up)))
            guard maxX > minX, maxY > minY else { continue }
            for y in minY ..< maxY {
                for x in minX ..< maxX {
                    values[y * width + x] = true
                }
            }
        }
        excluded = values
    }

    func contains(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return true }
        return excluded[y * width + x]
    }
}
