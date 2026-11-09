import XCTest
@testable import demos

@MainActor
final class PluginCloserManagerTests: XCTestCase {
    func testManagerInitializesWithSensibleDefaults() {
        let manager = PluginCloserManager()
        manager.resetToDefaults()

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.key, "w")
        XCTAssertTrue(manager.useCommand)
        XCTAssertTrue(manager.useOption)
        XCTAssertFalse(manager.useShift)
        XCTAssertFalse(manager.useControl)
        XCTAssertTrue(manager.onlyWhenAbletonActive)
        XCTAssertEqual(manager.shortcutDisplayString, "⌥⌘W")
    }

    func testShortcutDisplayStringReflectsModifiers() {
        let manager = PluginCloserManager()
        manager.useCommand = true
        manager.useOption = true
        manager.useShift = true
        manager.useControl = true
        manager.key = "e"
        XCTAssertEqual(manager.shortcutDisplayString, "⌃⌥⇧⌘E")

        manager.useControl = false
        manager.useShift = false
        manager.key = "w"
        XCTAssertEqual(manager.shortcutDisplayString, "⌥⌘W")
    }

    func testResetToDefaultsRestoresStandardShortcut() {
        let manager = PluginCloserManager()
        manager.key = "x"
        manager.useOption = false
        manager.resetToDefaults()

        XCTAssertEqual(manager.key, "w")
        XCTAssertTrue(manager.useOption)
        XCTAssertTrue(manager.useCommand)
        XCTAssertEqual(manager.shortcutDisplayString, "⌥⌘W")
    }

    func testPluginCloseResultMessages() {
        XCTAssertEqual(PluginCloseResult.closed.userMessage, "Closed all plugin windows")
        XCTAssertEqual(PluginCloseResult.alreadyClosed.userMessage, "Plugin windows are already closed")
        XCTAssertEqual(PluginCloseResult.notRunning.userMessage, "Ableton Live is not running")
        XCTAssertEqual(PluginCloseResult.menuNotFound.userMessage, "Ableton plugin window menu not found")
        XCTAssertEqual(PluginCloseResult.failed.userMessage, "Could not close plugin windows")
    }
}
