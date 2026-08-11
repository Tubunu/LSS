@testable import LongShot
import XCTest

final class TemporaryFrameStoreTests: XCTestCase {
    func testCreatesUniqueSessionDirectoryAndRemovesIt() throws {
        let store = try TemporaryFrameStore()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.path))
        XCTAssertTrue(store.frameURL(index: 7).lastPathComponent.hasSuffix("00007.png"))

        try store.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }
}
