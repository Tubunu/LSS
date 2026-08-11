@testable import LongShot
import XCTest

final class CaptureStateTests: XCTestCase {
    func testIdleAndTerminalStatesCanStart() {
        XCTAssertTrue(CaptureState.idle.canStart)
        XCTAssertTrue(CaptureState.completed.canStart)
        XCTAssertTrue(CaptureState.failed(message: "error").canStart)
    }

    func testBusyStatesRejectDuplicateStart() {
        XCTAssertFalse(CaptureState.selectingContent.canStart)
        XCTAssertFalse(CaptureState.starting.canStart)
        XCTAssertFalse(CaptureState.capturing.canStart)
        XCTAssertFalse(CaptureState.stopping.canStart)
    }

    func testOnlyStartingAndCapturingCanStop() {
        XCTAssertTrue(CaptureState.starting.canStop)
        XCTAssertTrue(CaptureState.capturing.canStop)
        XCTAssertFalse(CaptureState.idle.canStop)
        XCTAssertFalse(CaptureState.stopping.canStop)
        XCTAssertFalse(CaptureState.completed.canStop)
    }

    func testFailedStatesCompareTheirMessages() {
        XCTAssertEqual(CaptureState.failed(message: "A"), .failed(message: "A"))
        XCTAssertNotEqual(CaptureState.failed(message: "A"), .failed(message: "B"))
    }
}
