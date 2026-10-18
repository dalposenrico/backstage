import XCTest
@testable import demos

final class AbletonBatchDeviceInjectorTests: XCTestCase {

    func testBatchInjectorInjectsUtilityIntoAllTracks() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12049" SchemaChangeCount="3" Creator="Ableton Live 12.0">
            <LiveSet>
                <Tracks>
                    <AudioTrack Id="1">
                        <Name><EffectiveName Value="Vocal" /></Name>
                        <DeviceChain>
                            <Devices>
                                <Eq8 Id="10"><On><Manual Value="true" /></On></Eq8>
                            </Devices>
                        </DeviceChain>
                    </AudioTrack>
                    <MidiTrack Id="2">
                        <Name><EffectiveName Value="Pluck" /></Name>
                        <DeviceChain>
                            <Devices />
                        </DeviceChain>
                    </MidiTrack>
                </Tracks>
            </LiveSet>
        </Ableton>
        """

        let (modified, count) = AbletonBatchDeviceInjector.injectDeviceXml(
            into: sampleXML,
            snippet: BatchPluginPreset.utilityGain.defaultXmlSnippet,
            scope: .allTracks,
            position: .first
        )

        XCTAssertEqual(count, 2)
        XCTAssertTrue(modified.contains("<StereoGain"))
        XCTAssertTrue(modified.contains("Gain Stage"))

        // Re-parse with arrangement parser to verify structure
        let arrangement = AbletonArrangementParser.parse(xml: modified)
        XCTAssertEqual(arrangement.tracks.count, 2)

        let audioTrack = arrangement.tracks.first { $0.type == .audio }
        XCTAssertNotNil(audioTrack)
        // First slot should now be StereoGain / Utility!
        XCTAssertEqual(audioTrack?.devices.first?.type, .native)
        XCTAssertTrue(audioTrack?.devices.first?.name.contains("Gain Stage") == true)
        // Second slot should still be EQ Eight
        XCTAssertEqual(audioTrack?.devices[1].name, "EQ Eight")
    }

    func testBatchInjectorFiltersByScope() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12049" SchemaChangeCount="3" Creator="Ableton Live 12.0">
            <LiveSet>
                <Tracks>
                    <AudioTrack Id="1">
                        <DeviceChain><Devices /></DeviceChain>
                    </AudioTrack>
                    <MidiTrack Id="2">
                        <DeviceChain><Devices /></DeviceChain>
                    </MidiTrack>
                    <GroupTrack Id="3">
                        <DeviceChain><Devices /></DeviceChain>
                    </GroupTrack>
                </Tracks>
            </LiveSet>
        </Ableton>
        """

        // Test audioOnly
        let (_, audioCount) = AbletonBatchDeviceInjector.injectDeviceXml(
            into: sampleXML,
            snippet: BatchPluginPreset.utilityGain.defaultXmlSnippet,
            scope: .audioOnly,
            position: .first
        )
        XCTAssertEqual(audioCount, 1)

        // Test nonGroups
        let (_, nonGroupCount) = AbletonBatchDeviceInjector.injectDeviceXml(
            into: sampleXML,
            snippet: BatchPluginPreset.utilityGain.defaultXmlSnippet,
            scope: .nonGroups,
            position: .first
        )
        XCTAssertEqual(nonGroupCount, 2)
    }
}
