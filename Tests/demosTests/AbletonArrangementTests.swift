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
}
