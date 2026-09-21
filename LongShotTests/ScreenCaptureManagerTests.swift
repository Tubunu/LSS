@testable import LongShot
import ScreenCaptureKit
import XCTest

final class ScreenCaptureManagerTests: XCTestCase {
    func testScreenCaptureManagerInitialState() {
        let manager = ScreenCaptureManager()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.sessionDirectory)
        XCTAssertNil(manager.captureStartedAt)
        XCTAssertFalse(manager.autoStopOnForeground, "默认应为手动模式，避免误判停止")
        XCTAssertEqual(manager.diagnostics.validFrames, 0)
    }

    func testStartCaptureSelectionDoesNotCrash() {
        let manager = ScreenCaptureManager()
        // 验证调用 startCaptureSelection() 能够安全通过 selector 探测，绝不抛出 unrecognized selector 致命异常
        manager.startCaptureSelection()

        // 状态应安全迁移为 selectingContent 或在无权限时迁移为 failed
        switch manager.state {
        case .selectingContent:
            XCTAssertTrue(true)
        case .failed(let msg):
            XCTAssertFalse(msg.isEmpty)
        default:
            XCTFail("Unexpected state after startCaptureSelection: \(manager.state)")
        }
    }

    func testResetRestoresIdle() {
        let manager = ScreenCaptureManager()
        manager.reset()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(manager.diagnostics.selectedFrames, 0)
    }

    func testPickerDismissalDoesNotTriggerPrematureStop() {
        let manager = ScreenCaptureManager()
        // 模拟用户刚在 App 内完成选择器，但从未切出到后台
        // 浮层关闭使得 App 变为活跃状态
        manager.appDidBecomeActive()
        XCTAssertEqual(manager.state, .idle)
    }

    func testNonCapturingBackgroundLifecycleHandling() {
        let manager = ScreenCaptureManager()
        // 在非 capturing 状态下切后台切前台不应破坏状态
        manager.appDidEnterBackground()
        manager.appDidBecomeActive()
        XCTAssertEqual(manager.state, .idle)
    }

    func testResetCleansUpResources() {
        let manager = ScreenCaptureManager()
        manager.appDidEnterBackground()
        manager.reset()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.sessionDirectory)
    }
}
