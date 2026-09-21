import Foundation
@testable import LongShot
import XCTest

final class SessionRecoveryTests: XCTestCase {
    func testRecoverableSessionDetectionAndDiscard() throws {
        // 创建一个包含 2 张 PNG 关键帧的临时测试目录
        let store = try TemporaryFrameStore()
        let frame0 = store.frameURL(index: 0)
        let frame1 = store.frameURL(index: 1)

        try Data([1, 2, 3]).write(to: frame0)
        try Data([4, 5, 6]).write(to: frame1)

        let session = SessionRecovery.findRecoverableSession()
        XCTAssertNotNil(session, "拥有 2 张以上未清理关键帧的会话应当被识别为可恢复会话")

        if let s = session {
            XCTAssertGreaterThanOrEqual(s.frameCount, 2)
            SessionRecovery.discard(session: s)
        }

        // 清理自身
        try? store.remove()
    }
}
