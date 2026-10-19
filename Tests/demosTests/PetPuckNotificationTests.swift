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

            // When no capsule is active, total width equals dimension
            XCTAssertEqual(size.totalCollapsedWidth(hasCapsule: false), size.dimension)

            // When capsule is active, total width accommodates icon, spacing, and capsule
            XCTAssertEqual(size.totalCollapsedWidth(hasCapsule: true), size.dimension + size.capsuleWidth + 8)
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
        XCTAssertTrue(settings.showPetPuckProjectCapsule)
        XCTAssertTrue(settings.notifyOnAbletonReady)
    }
}
