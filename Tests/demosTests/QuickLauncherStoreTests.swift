import XCTest
@testable import demos

@MainActor
final class QuickLauncherStoreTests: XCTestCase {
    func testStoreInitializesWithNineDefaultItems() {
        let store = QuickLauncherStore()
        XCTAssertEqual(store.items.count, 9)
        XCTAssertEqual(store.items.first?.key, "1")
        XCTAssertEqual(store.items.first?.title, "SSL 4000 E")
        XCTAssertEqual(store.items.last?.key, "9")
        XCTAssertEqual(store.items.last?.title, "Utility")
    }

    func testKeyCodeMappingForNumbersAndLetters() {
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "1"), 18)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "2"), 19)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "3"), 20)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "4"), 21)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "5"), 23)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "6"), 22)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "7"), 26)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "8"), 28)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "9"), 25)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "0"), 29)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "f1"), 122)
        XCTAssertEqual(KeyCodeHelper.keyCode(for: "space"), 49)
    }

    func testAddAndRemoveItem() {
        let store = QuickLauncherStore()
        let initialCount = store.items.count
        store.addItem(title: "Custom Synth", key: "0", category: "INST")
        XCTAssertEqual(store.items.count, initialCount + 1)
        XCTAssertEqual(store.items.last?.title, "Custom Synth")

        if let lastId = store.items.last?.id {
            store.removeItem(id: lastId)
            XCTAssertEqual(store.items.count, initialCount)
        }
    }

    func testUpdateItem() {
        let store = QuickLauncherStore()
        guard var first = store.items.first else {
            XCTFail("Missing first item")
            return
        }
        first.title = "Custom EQ"
        store.updateItem(first)
        XCTAssertEqual(store.items.first?.title, "Custom EQ")

        store.resetToDefaults()
        XCTAssertEqual(store.items.first?.title, "SSL 4000 E")
    }

    func testTrayHeightCalculation() {
        let store = QuickLauncherStore()
        XCTAssertGreaterThan(store.trayHeight, 100)
    }
}
