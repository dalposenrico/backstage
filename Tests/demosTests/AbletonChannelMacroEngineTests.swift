import XCTest
@testable import demos

@MainActor
final class AbletonChannelMacroEngineTests: XCTestCase {

    func testMacroDirectionKeyCodes() {
        XCTAssertEqual(ChannelMacroDirection.arrangementDown.keyCode, 125, "Arrangement view down arrow should be key code 125")
        XCTAssertEqual(ChannelMacroDirection.sessionRight.keyCode, 124, "Session view right arrow should be key code 124")
    }

    func testMacroPacingDelays() {
        XCTAssertEqual(ChannelMacroPacing.relaxed.stepDelaySeconds, 0.25)
        XCTAssertEqual(ChannelMacroPacing.normal.stepDelaySeconds, 0.15)
        XCTAssertEqual(ChannelMacroPacing.fast.stepDelaySeconds, 0.08)
    }

    func testMacroModeSubtitles() {
        XCTAssertFalse(ChannelMacroMode.pasteClipboard.subtitle.isEmpty)
        XCTAssertFalse(ChannelMacroMode.searchAndInsert.subtitle.isEmpty)
    }

    func testDeviceTooltipDescription() {
        let deviceWithVendor = AbletonDevice(
            name: "Pro-Q 3",
            vendor: "FabFilter",
            type: .vst3,
            isEnabled: true
        )
        XCTAssertEqual(deviceWithVendor.tooltipDescription, "Pro-Q 3 (FabFilter) · VST3")
        XCTAssertTrue(deviceWithVendor.isOn)

        let nativeDevice = AbletonDevice(
            name: "Utility",
            vendor: nil,
            type: .native,
            isEnabled: false
        )
        XCTAssertEqual(nativeDevice.tooltipDescription, "Utility · Native")
        XCTAssertFalse(nativeDevice.isOn)
    }

    func testMacroEngineInitialStateAndStop() {
        let engine = AbletonChannelMacroEngine()
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.countdownRemaining)
        XCTAssertEqual(engine.currentChannel, 0)
        XCTAssertEqual(engine.statusMessage, "Ready")

        // Stopping an idle engine shouldn't crash
        engine.stopMacro()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.statusMessage, "Macro stopped.")
    }
}
