import XCTest
@testable import demos

@MainActor
final class AbletonDragScrollManagerTests: XCTestCase {
    func testManagerInitializesAndDefaultsToEnabled() {
        let manager = AbletonDragScrollManager()
        XCTAssertTrue(manager.isEnabled)
    }

    func testManagerCanBeToggled() {
        let manager = AbletonDragScrollManager()
        manager.isEnabled = false
        XCTAssertFalse(manager.isEnabled)
        manager.isEnabled = true
        XCTAssertTrue(manager.isEnabled)
    }
}
