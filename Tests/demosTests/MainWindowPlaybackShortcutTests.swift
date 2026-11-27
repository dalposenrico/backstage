import AppKit
import XCTest
@testable import demos

final class MainWindowPlaybackShortcutTests: XCTestCase {
    func testAllowsSpacebarInMainWindowWhenNotEditingText() {
        XCTAssertTrue(
            MainWindowPlaybackShortcut.shouldHandleSpacebar(
                windowTitle: "goodvibrations HQ",
                canBecomeMain: true,
                hasAttachedSheet: false,
                isEditingText: false,
                keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                modifierFlags: [],
                isRepeat: false
            )
        )
    }

    func testRejectsSpacebarWhenFloatingHUDOrUtilityWindowIsKey() {
        for title in ["goodvibrations HUD", "Quick Launcher Panel", "Focus Timer", "Versions", "Project Notes", "Settings"] {
            XCTAssertFalse(
                MainWindowPlaybackShortcut.shouldHandleSpacebar(
                    windowTitle: title,
                    canBecomeMain: true,
                    hasAttachedSheet: false,
                    isEditingText: false,
                    keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                    modifierFlags: [],
                    isRepeat: false
                ),
                "Expected spacebar to be ignored for window '\(title)'"
            )
        }
    }

    func testRejectsSpacebarWhenEditingTextSheetModifiersOrRepeat() {
        XCTAssertFalse(
            MainWindowPlaybackShortcut.shouldHandleSpacebar(
                windowTitle: "goodvibrations HQ",
                canBecomeMain: true,
                hasAttachedSheet: false,
                isEditingText: true,
                keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                modifierFlags: [],
                isRepeat: false
            )
        )
        XCTAssertFalse(
            MainWindowPlaybackShortcut.shouldHandleSpacebar(
                windowTitle: "goodvibrations HQ",
                canBecomeMain: true,
                hasAttachedSheet: true,
                isEditingText: false,
                keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                modifierFlags: [],
                isRepeat: false
            )
        )
        XCTAssertFalse(
            MainWindowPlaybackShortcut.shouldHandleSpacebar(
                windowTitle: "goodvibrations HQ",
                canBecomeMain: true,
                hasAttachedSheet: false,
                isEditingText: false,
                keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                modifierFlags: [.command],
                isRepeat: false
            )
        )
        XCTAssertFalse(
            MainWindowPlaybackShortcut.shouldHandleSpacebar(
                windowTitle: "goodvibrations HQ",
                canBecomeMain: true,
                hasAttachedSheet: false,
                isEditingText: false,
                keyCode: MainWindowPlaybackShortcut.spaceKeyCode,
                modifierFlags: [],
                isRepeat: true
            )
        )
    }
}
