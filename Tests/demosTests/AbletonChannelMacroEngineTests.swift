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

    func testMacroEngineTrackSelectionAndFilters() {
        let engine = AbletonChannelMacroEngine()
        engine.createDefaultTracks(count: 6)
        XCTAssertEqual(engine.tracks.count, 6)
        XCTAssertEqual(engine.selectedCount, 6)

        engine.deselectAllTracks()
        XCTAssertEqual(engine.selectedCount, 0)

        engine.selectAudioTracksOnly()
        XCTAssertTrue(engine.selectedTracks.allSatisfy { $0.type == .audio })

        engine.selectMidiTracksOnly()
        XCTAssertTrue(engine.selectedTracks.allSatisfy { $0.type == .midi })

        engine.selectAllTracks()
        XCTAssertEqual(engine.selectedCount, 6)

        if let first = engine.tracks.first {
            engine.toggleTrack(id: first.id)
            XCTAssertEqual(engine.selectedCount, 5)
        }
    }

    func testLoadTracksFromArrangement() {
        let engine = AbletonChannelMacroEngine()
        let arrangement = AbletonArrangement(
            tracks: [
                AbletonTrack(name: "Kick", type: .audio, devices: [AbletonDevice(name: "Utility")]),
                AbletonTrack(name: "Bass", type: .midi, devices: [AbletonDevice(name: "EQ Eight")]),
                AbletonTrack(name: "Drum Bus", type: .group, devices: [])
            ]
        )

        engine.loadTracks(from: arrangement, projectName: "Summer Vibes")
        XCTAssertEqual(engine.loadedProjectName, "Summer Vibes")
        XCTAssertEqual(engine.tracks.count, 3)
        XCTAssertEqual(engine.tracks[0].name, "Kick")
        XCTAssertEqual(engine.tracks[0].devices, ["Utility"])
        // Groups default to unselected
        XCTAssertTrue(engine.tracks[0].isSelected)
        XCTAssertTrue(engine.tracks[1].isSelected)
        XCTAssertFalse(engine.tracks[2].isSelected)
        XCTAssertEqual(engine.selectedCount, 2)
    }

    func testMacroEngineInitialStateAndStop() {
        let engine = AbletonChannelMacroEngine()
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(engine.countdownRemaining)
        XCTAssertEqual(engine.statusMessage, "Ready")

        // Stopping an idle engine shouldn't crash
        engine.stopMacro()
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.statusMessage, "Macro stopped.")
    }
}
