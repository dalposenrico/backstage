import XCTest
@testable import demos

final class AbletonArrangementTests: XCTestCase {

    func testStandardMidiWriterGeneratesValidSMFHeader() {
        let notes = [
            AbletonNote(pitch: 60, startBeat: 0.0, durationBeats: 1.0, velocity: 100),
            AbletonNote(pitch: 64, startBeat: 1.0, durationBeats: 1.0, velocity: 90),
            AbletonNote(pitch: 67, startBeat: 2.0, durationBeats: 2.0, velocity: 110)
        ]

        let data = StandardMidiWriter.generateMidiData(notes: notes, tempo: 128.0, trackName: "Test Melody")

        // SMF files must start with "MThd"
        XCTAssertGreaterThan(data.count, 22)
        let headerPrefix = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(headerPrefix, "MThd")

        // Track chunk starts with "MTrk" at byte 14
        let trackPrefix = String(data: data.subdata(in: 14..<18), encoding: .ascii)
        XCTAssertEqual(trackPrefix, "MTrk")
    }

    func testAbletonArrangementParserExtractsTracksAndNotes() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12049" SchemaChangeCount="3" Creator="Ableton Live 12.0">
            <LiveSet>
                <MasterTrack>
                    <DeviceChain>
                        <Mixer>
                            <Tempo>
                                <Manual Value="134.0"/>
                            </Tempo>
                            <TimeSignature>
                                <TimeSignatures>
                                    <RemoteableTimeSignature>
                                        <Numerator Value="4"/>
                                        <Denominator Value="4"/>
                                    </RemoteableTimeSignature>
                                </TimeSignatures>
                            </TimeSignature>
                        </Mixer>
                    </DeviceChain>
                </MasterTrack>
                <Tracks>
                    <MidiTrack Id="10">
                        <Name>
                            <EffectiveName Value="plucks"/>
                        </Name>
                        <Color Value="15"/>
                        <DeviceChain>
                            <MainSequencer>
                                <ClipTimeable>
                                    <ArrangerAutomation>
                                        <Events>
                                            <MidiClip Id="101" Time="48.0">
                                                <CurrentStart Value="0.0"/>
                                                <CurrentEnd Value="16.0"/>
                                                <Name Value="Lead Hook"/>
                                                <Color Value="22"/>
                                                <Notes>
                                                    <KeyTracks>
                                                        <KeyTrack>
                                                            <MidiKey Value="60"/>
                                                            <Notes>
                                                                <MidiNote Time="0.0" Duration="1.0" Velocity="100.0"/>
                                                                <MidiNote Time="2.0" Duration="0.5" Velocity="95.0"/>
                                                            </Notes>
                                                        </KeyTrack>
                                                    </KeyTracks>
                                                </Notes>
                                            </MidiClip>
                                        </Events>
                                    </ArrangerAutomation>
                                </ClipTimeable>
                            </MainSequencer>
                        </DeviceChain>
                    </MidiTrack>
                    <AudioTrack Id="20">
                        <Name>
                            <EffectiveName Value="Vocal Hook"/>
                        </Name>
                        <Color Value="35"/>
                        <DeviceChain>
                            <MainSequencer>
                                <ClipTimeable>
                                    <ArrangerAutomation>
                                        <Events>
                                            <AudioClip Id="201" Time="64.0">
                                                <CurrentStart Value="0.0"/>
                                                <CurrentEnd Value="32.0"/>
                                                <Name Value="Vocal_Wet_134.wav"/>
                                                <Color Value="35"/>
                                                <SampleRef>
                                                    <FileRef>
                                                        <RelativePath Value="Samples/Recorded/Vocal_Wet_134.wav"/>
                                                        <Path Value="/Users/producer/Music/Samples/Recorded/Vocal_Wet_134.wav"/>
                                                    </FileRef>
                                                </SampleRef>
                                            </AudioClip>
                                        </Events>
                                    </ArrangerAutomation>
                                </ClipTimeable>
                            </MainSequencer>
                        </DeviceChain>
                    </AudioTrack>
                </Tracks>
            </LiveSet>
        </Ableton>
        """

        let arrangement = AbletonArrangementParser.parse(xml: sampleXML)

        XCTAssertEqual(arrangement.tempo, 134.0)
        XCTAssertEqual(arrangement.timeSignatureNumerator, 4)
        XCTAssertEqual(arrangement.tracks.count, 2)

        let midiTrack = arrangement.tracks.first { $0.type == .midi }
        XCTAssertNotNil(midiTrack)
        XCTAssertEqual(midiTrack?.name, "plucks")
        XCTAssertEqual(midiTrack?.clips.count, 1)

        let clip = midiTrack?.clips.first
        XCTAssertEqual(clip?.name, "Lead Hook")
        XCTAssertEqual(clip?.startTimeBeats, 48.0)
        XCTAssertEqual(clip?.durationBeats, 16.0)
        XCTAssertEqual(clip?.notes.count, 2)
        XCTAssertEqual(clip?.notes.first?.pitch, 60)
        XCTAssertEqual(clip?.notes.first?.durationBeats, 1.0)

        let audioTrack = arrangement.tracks.first { $0.type == .audio }
        XCTAssertNotNil(audioTrack)
        XCTAssertEqual(audioTrack?.name, "Vocal Hook")
        XCTAssertEqual(audioTrack?.clips.first?.sampleRef?.fileName, "Vocal_Wet_134.wav")
    }

    func testAbletonArrangementParserExtractsTrackDevicesAndBypassState() {
        let sampleXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton MajorVersion="5" MinorVersion="12.0_12049" SchemaChangeCount="3" Creator="Ableton Live 12.0">
            <LiveSet>
                <Tracks>
                    <AudioTrack Id="50">
                        <Name>
                            <EffectiveName Value="Lead Vocal"/>
                        </Name>
                        <Color Value="14"/>
                        <DeviceChain>
                            <Devices>
                                <StereoGain Id="1">
                                    <UserName Value="Pre-Gain"/>
                                    <On><Manual Value="true"/></On>
                                </StereoGain>
                                <Vst3PluginDevice Id="2">
                                    <PluginDesc>
                                        <Vst3PluginInfo>
                                            <Name Value="FabFilter Pro-Q 3"/>
                                            <Manufacturer Value="FabFilter"/>
                                        </Vst3PluginInfo>
                                    </PluginDesc>
                                    <On><Manual Value="true"/></On>
                                </Vst3PluginDevice>
                                <AuPluginDevice Id="3">
                                    <PluginDesc>
                                        <AuPluginInfo>
                                            <Name Value="Decapitator"/>
                                            <Manufacturer Value="Soundtoys"/>
                                        </AuPluginInfo>
                                    </PluginDesc>
                                    <On><Manual Value="false"/></On>
                                </AuPluginDevice>
                                <Eq8 Id="4">
                                    <On><Manual Value="true"/></On>
                                </Eq8>
                            </Devices>
                        </DeviceChain>
                    </AudioTrack>
                </Tracks>
            </LiveSet>
        </Ableton>
        """

        let arrangement = AbletonArrangementParser.parse(xml: sampleXML)
        XCTAssertEqual(arrangement.tracks.count, 1)

        let track = arrangement.tracks[0]
        XCTAssertEqual(track.name, "Lead Vocal")
        XCTAssertEqual(track.devices.count, 4)

        // Slot 0: StereoGain / Utility
        let d0 = track.devices[0]
        XCTAssertEqual(d0.slotIndex, 0)
        XCTAssertTrue(d0.name.contains("Pre-Gain"))
        XCTAssertEqual(d0.type, .native)
        XCTAssertTrue(d0.isEnabled)

        // Slot 1: VST3 Pro-Q 3
        let d1 = track.devices[1]
        XCTAssertEqual(d1.slotIndex, 1)
        XCTAssertEqual(d1.name, "FabFilter Pro-Q 3")
        XCTAssertEqual(d1.vendor, "FabFilter")
        XCTAssertEqual(d1.type, .vst3)
        XCTAssertTrue(d1.isEnabled)

        // Slot 2: AU Decapitator (bypassed)
        let d2 = track.devices[2]
        XCTAssertEqual(d2.slotIndex, 2)
        XCTAssertEqual(d2.name, "Decapitator")
        XCTAssertEqual(d2.vendor, "Soundtoys")
        XCTAssertEqual(d2.type, .au)
        XCTAssertFalse(d2.isEnabled) // Bypassed!

        // Slot 3: Native EQ Eight
        let d3 = track.devices[3]
        XCTAssertEqual(d3.slotIndex, 3)
        XCTAssertEqual(d3.name, "EQ Eight")
        XCTAssertEqual(d3.type, .native)
        XCTAssertTrue(d3.isEnabled)
    }
}
