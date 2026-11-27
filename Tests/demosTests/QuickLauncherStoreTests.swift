import XCTest
@testable import demos

@MainActor
final class QuickLauncherStoreTests: XCTestCase {
    private func makeIsolatedStore() -> (QuickLauncherStore, String) {
        let suiteName = "QuickLauncherStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (QuickLauncherStore(defaults: defaults), suiteName)
    }

    func testStoreInitializesWithUpdatedDefaultItems() {
        let (store, suiteName) = makeIsolatedStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.items.map(\.key), ["1", "2", "3", "4", "5", "6", "8", "9", "(", ")"])
        XCTAssertEqual(store.items.map(\.title), [
            "SSL 4000 E",
            "Saturn 2",
            "Spectre",
            "Utility",
            "Pro-Q 4",
            "StandardCLIP",
            "ValhallaRoom",
            "SideKick",
            "Utility",
            "Life"
        ])
    }

    func testLegacyStoredDefaultsAreMigratedOnceToNewPreset() throws {
        let suiteName = "QuickLauncherStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = [QuickLauncherItem(title: "Pro-Q 3", key: "3", category: "EQ")]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "quickLauncherActions")

        let migrated = QuickLauncherStore(defaults: defaults)
        XCTAssertEqual(migrated.items.count, 10)
        XCTAssertEqual(migrated.items[4].title, "Pro-Q 4")

        // Subsequent user customizations after v2 migration are preserved
        migrated.addItem(title: "Custom Synth", key: "0", category: "INST")
        let reloaded = QuickLauncherStore(defaults: defaults)
        XCTAssertEqual(reloaded.items.count, 11)
        XCTAssertEqual(reloaded.items.last?.title, "Custom Synth")
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
        let (store, suiteName) = makeIsolatedStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

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
        let (store, suiteName) = makeIsolatedStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

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
        let (store, suiteName) = makeIsolatedStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        XCTAssertGreaterThan(store.trayHeight, 100)
    }

    func testKeyStrokeMappingSupportsParentheses() {
        let openParen = KeyCodeHelper.keyStroke(for: "(")
        let closeParen = KeyCodeHelper.keyStroke(for: ")")
        XCTAssertNotNil(openParen)
        XCTAssertNotNil(closeParen)
        XCTAssertTrue(openParen?.flags.contains(.maskShift) == true)
        XCTAssertTrue(closeParen?.flags.contains(.maskShift) == true)
    }

    func testShouldPresentFloatingPanelOnlyWhenCollapsed() {
        let suiteName = "QuickLauncherStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "isFloatingWidgetCollapsed")
        let expandedStore = QuickLauncherStore(defaults: defaults)
        XCTAssertFalse(expandedStore.shouldPresentFloatingPanel)

        defaults.set(true, forKey: "isFloatingWidgetCollapsed")
        let collapsedStore = QuickLauncherStore(defaults: defaults)
        XCTAssertTrue(collapsedStore.shouldPresentFloatingPanel)
    }
}
