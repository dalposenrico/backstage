import XCTest
@testable import demos

final class ProjectDockSizingTests: XCTestCase {
    func testCollapsedDockUsesOnlyTheHeaderHeight() {
        XCTAssertEqual(
            ProjectDockSizing.presentedHeight(420, isExpanded: false, availableHeight: 700),
            ProjectDockSizing.collapsedHeight
        )
    }

    func testExpandedDockRestoresItsClampedSavedHeight() {
        XCTAssertEqual(
            ProjectDockSizing.presentedHeight(420, isExpanded: true, availableHeight: 700),
            420
        )
    }

    func testExpandedDockLeavesRoomForTheBrowser() {
        XCTAssertEqual(
            ProjectDockSizing.presentedHeight(560, isExpanded: true, availableHeight: 500),
            350
        )
    }
}
