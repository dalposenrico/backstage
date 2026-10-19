import XCTest
@testable import demos

final class PetPuckNotificationTests: XCTestCase {
    func testPetPuckSizeCapsuleDimensions() {
        for size in PetPuckSize.allCases {
            XCTAssertGreaterThan(size.capsuleWidth, 100)
            XCTAssertGreaterThan(size.capsuleHeight, 30)
            XCTAssertGreaterThan(size.capsuleTitleFontSize, 10)
            XCTAssertGreaterThan(size.capsuleSubtitleFontSize, 8)
            XCTAssertLessThan(size.capsuleSubtitleFontSize, size.capsuleTitleFontSize)

            // When app icon is disabled (standalone floating pill):
            XCTAssertEqual(size.totalCollapsedWidth(hasIcon: false), size.capsuleWidth)
            XCTAssertEqual(size.totalCollapsedHeight(hasIcon: false), size.capsuleHeight)

            // When app icon is enabled:
            XCTAssertEqual(size.totalCollapsedWidth(hasIcon: true), size.dimension + size.capsuleWidth + 8)
            XCTAssertEqual(size.totalCollapsedHeight(hasIcon: true), size.dimension)
        }
    }

    func testPetPuckSizeOrdering() {
        XCTAssertLessThan(PetPuckSize.small.dimension, PetPuckSize.medium.dimension)
        XCTAssertLessThan(PetPuckSize.medium.dimension, PetPuckSize.large.dimension)
        XCTAssertLessThan(PetPuckSize.large.dimension, PetPuckSize.extraLarge.dimension)

        XCTAssertLessThan(PetPuckSize.small.capsuleWidth, PetPuckSize.medium.capsuleWidth)
        XCTAssertLessThan(PetPuckSize.medium.capsuleWidth, PetPuckSize.large.capsuleWidth)
        XCTAssertLessThan(PetPuckSize.large.capsuleWidth, PetPuckSize.extraLarge.capsuleWidth)
    }

    func testSettingsStoreDefaultsForPuckNotification() {
        let settings = SettingsStore()
        XCTAssertFalse(settings.showAppIconOnPuck) // Default: icon removed as requested
        XCTAssertTrue(settings.isFloatingWidgetPinned) // Default: always pinned on top
        XCTAssertTrue(settings.showPetPuckProjectCapsule)
        XCTAssertTrue(settings.notifyOnAbletonReady)
    }
}
