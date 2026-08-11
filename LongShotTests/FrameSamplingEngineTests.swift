@testable import LongShot
import XCTest

final class FrameSamplingEngineTests: XCTestCase {
    func testStaticPageForTenSecondsKeepsOnlyInitialFrame() {
        var engine = makeEngine()
        let frame = fixture(offset: 0)
        var selected = 0

        for step in 0 ... 100 {
            selected += evaluateAndAccept(&engine, frame: frame, timestamp: Double(step) / 10)
        }

        XCTAssertEqual(selected, 1)
    }

    func testLightScrollWaitsForMinimumDisplacement() {
        var engine = makeEngine()

        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 0), timestamp: 0), 1)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 1), timestamp: 0.2), 0)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 2), timestamp: 0.4), 0)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 3), timestamp: 0.6), 0)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 4), timestamp: 0.8), 1)
    }

    func testNormalScrollSelectsOverlappingFrames() {
        var engine = makeEngine()
        let offsets = [0, 6, 12, 18]
        let decisions = offsets.enumerated().map { index, offset -> FrameSamplingDecision in
            let frame = fixture(offset: offset)
            let decision = engine.evaluate(signature: frame, timestamp: Double(index) * 0.25)
            if decision.shouldSelect {
                engine.accept(signature: frame, timestamp: Double(index) * 0.25)
            }
            return decision
        }

        XCTAssertTrue(decisions.allSatisfy(\.shouldSelect))
        XCTAssertEqual(decisions.dropFirst().map(\.reason), [.movement, .movement, .movement])
    }

    func testFastScrollUsesFastMovementReason() {
        var engine = makeEngine()
        let initial = fixture(offset: 0)
        _ = engine.evaluate(signature: initial, timestamp: 0)
        engine.accept(signature: initial, timestamp: 0)

        let fast = fixture(offset: 18)
        let decision = engine.evaluate(signature: fast, timestamp: 0.25)

        XCTAssertTrue(decision.shouldSelect)
        XCTAssertEqual(decision.reason, .fastMovement)
        XCTAssertGreaterThanOrEqual(decision.score, 0.75)
    }

    func testSmallRollbackIsIgnoredThenDownwardProgressResumes() {
        var engine = makeEngine()
        let initial = fixture(offset: 0)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: initial, timestamp: 0), 1)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 8), timestamp: 0.25), 1)

        let rollback = engine.evaluate(signature: fixture(offset: 5), timestamp: 0.5)
        XCTAssertFalse(rollback.shouldSelect)
        XCTAssertEqual(rollback.reason, .smallRollback)

        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 12), timestamp: 0.75), 1)
    }

    func testSmallAnimationRegionDoesNotCreateRepeatedFrames() {
        var engine = makeEngine()
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 0), timestamp: 0), 1)

        for second in 1 ... 10 {
            let frame = fixture(offset: 0, animatedSeed: second, animatedSize: 4)
            XCTAssertEqual(evaluateAndAccept(&engine, frame: frame, timestamp: Double(second)), 0)
        }

        XCTAssertEqual(engine.selectedFrameCount, 1)
    }

    func testMaximumGapProtectsChangingContentWithoutDetectedMotion() {
        var engine = makeEngine()
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 0), timestamp: 0), 1)

        let changed = fixture(offset: 0, animatedSeed: 7, animatedSize: 10)
        let decision = engine.evaluate(signature: changed, timestamp: 1.3)

        XCTAssertTrue(decision.shouldSelect)
        XCTAssertEqual(decision.reason, .maximumGap)
    }

    func testCapacityIsEnforced() {
        var thresholds = testThresholds()
        thresholds.maximumPersistedFrames = 2
        var engine = FrameSamplingEngine(thresholds: thresholds)

        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 0), timestamp: 0), 1)
        XCTAssertEqual(evaluateAndAccept(&engine, frame: fixture(offset: 8), timestamp: 0.25), 1)

        let decision = engine.evaluate(signature: fixture(offset: 16), timestamp: 0.5)
        XCTAssertFalse(decision.shouldSelect)
        XCTAssertEqual(decision.reason, .capacityReached)
    }

    private func makeEngine() -> FrameSamplingEngine {
        FrameSamplingEngine(thresholds: testThresholds())
    }

    private func testThresholds() -> FrameSamplingThresholds {
        var thresholds = FrameSamplingThresholds()
        thresholds.analysisInterval = 0.05
        thresholds.minimumSelectionInterval = 0.15
        thresholds.maximumSelectionGap = 1.25
        thresholds.minimumDisplacementRatio = 0.08
        thresholds.fastDisplacementRatio = 0.28
        thresholds.maximumIgnoredRollbackRatio = 0.14
        return thresholds
    }

    private func evaluateAndAccept(
        _ engine: inout FrameSamplingEngine,
        frame: FrameSignature,
        timestamp: Double
    ) -> Int {
        let decision = engine.evaluate(signature: frame, timestamp: timestamp)
        guard decision.shouldSelect else { return 0 }
        engine.accept(signature: frame, timestamp: timestamp)
        return 1
    }

    private func fixture(
        offset: Int,
        animatedSeed: Int? = nil,
        animatedSize: Int = 0
    ) -> FrameSignature {
        let width = 24
        let height = 48
        var values = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let documentY = y + offset
                let value = (documentY * 73 + x * 41 + documentY * x * 17 + (documentY % 7) * 29) % 256
                values[y * width + x] = UInt8(value)
            }
        }

        if let animatedSeed {
            for y in 16 ..< min(16 + animatedSize, height) {
                for x in 8 ..< min(8 + animatedSize, width) {
                    values[y * width + x] = UInt8((animatedSeed * 53 + y * 11 + x * 7) % 256)
                }
            }
        }

        return FrameSignature(width: width, height: height, luminance: values)
    }
}
