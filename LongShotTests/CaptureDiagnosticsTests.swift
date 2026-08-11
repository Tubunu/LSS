@testable import LongShot
import XCTest

final class CaptureDiagnosticsTests: XCTestCase {
    func testRecordsFrameAndBackgroundMetrics() {
        let diagnostics = CaptureDiagnostics()

        XCTAssertTrue(diagnostics.recordValidFrame(width: 1206, height: 2622, timestamp: 10))
        diagnostics.recordInvalidFrame()
        diagnostics.recordSelectedFrame()
        diagnostics.recordBackgroundResult(frameDelta: 42, duration: 31.5)

        let snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.receivedFrames, 2)
        XCTAssertEqual(snapshot.validFrames, 1)
        XCTAssertEqual(snapshot.invalidFrames, 1)
        XCTAssertEqual(snapshot.selectedFrames, 1)
        XCTAssertEqual(snapshot.width, 1206)
        XCTAssertEqual(snapshot.height, 2622)
        XCTAssertEqual(snapshot.backgroundFrameDelta, 42)
        XCTAssertEqual(snapshot.backgroundDuration, 31.5)
    }

    func testThrottlesSnapshotPublication() {
        let diagnostics = CaptureDiagnostics()

        XCTAssertTrue(diagnostics.recordValidFrame(width: 1, height: 1, timestamp: 1))
        XCTAssertFalse(diagnostics.recordValidFrame(width: 1, height: 1, timestamp: 1.1))
        XCTAssertTrue(diagnostics.recordValidFrame(width: 1, height: 1, timestamp: 1.3))
    }

    func testResetClearsAllMetrics() {
        let diagnostics = CaptureDiagnostics()
        _ = diagnostics.recordValidFrame(width: 100, height: 200, timestamp: 5)
        diagnostics.recordSelectedFrame()

        diagnostics.reset()

        XCTAssertEqual(diagnostics.snapshot(), CaptureDiagnosticsSnapshot())
    }
}
