import Foundation

/// Lightweight, zero-dependency Standard MIDI File (SMF 1.0) binary generator.
/// Encodes Ableton clip notes into standard .mid format for drag-and-drop into Ableton Live or Finder.
public enum StandardMidiWriter {

    private static let ticksPerQuarter: UInt16 = 480

    private struct MidiEvent {
        let tick: UInt32
        let bytes: [UInt8]
    }

    /// Generates raw Standard MIDI File (Format 0) bytes from an array of notes.
    public static func generateMidiData(
        notes: [AbletonNote],
        tempo: Double = 120.0,
        trackName: String = "Exported Clip"
    ) -> Data {
        var events: [MidiEvent] = []

        // 1. Tempo meta event: 500,000 µs = 120 BPM
        let safeTempo = max(20.0, min(999.0, tempo))
        let microsecondsPerQuarter = UInt32(60_000_000.0 / safeTempo)
        events.append(MidiEvent(tick: 0, bytes: [
            0xFF, 0x51, 0x03,
            UInt8((microsecondsPerQuarter >> 16) & 0xFF),
            UInt8((microsecondsPerQuarter >> 8) & 0xFF),
            UInt8(microsecondsPerQuarter & 0xFF)
        ]))

        // 2. Track Name meta event
        if !trackName.isEmpty {
            let nameBytes = Array(trackName.utf8)
            var nameEventBytes: [UInt8] = [0xFF, 0x03]
            nameEventBytes.append(contentsOf: encodeVLQ(UInt32(nameBytes.count)))
            nameEventBytes.append(contentsOf: nameBytes)
            events.append(MidiEvent(tick: 0, bytes: nameEventBytes))
        }

        // 3. Time Signature: 4/4 default
        events.append(MidiEvent(tick: 0, bytes: [
            0xFF, 0x58, 0x04,
            0x04, // numerator
            0x02, // denominator power of 2 (2^2 = 4)
            0x18, // MIDI clocks per metronome click (24)
            0x08  // 32nd notes per 24 MIDI clocks (8)
        ]))

        // 4. Note On & Note Off events
        for note in notes {
            let onTick = UInt32(max(0, note.startBeat * Double(ticksPerQuarter)))
            let offTick = UInt32(max(Double(onTick + 1), (note.startBeat + max(0.05, note.durationBeats)) * Double(ticksPerQuarter)))
            let pitch = UInt8(max(0, min(127, note.pitch)))
            let vel = UInt8(max(1, min(127, Int(note.velocity))))

            // Note On (Channel 1 = 0x90)
            events.append(MidiEvent(tick: onTick, bytes: [0x90, pitch, vel]))
            // Note Off (Channel 1 = 0x80)
            events.append(MidiEvent(tick: offTick, bytes: [0x80, pitch, 0x40]))
        }

        // Sort events chronologically. For identical ticks, sort Note Off before Note On.
        events.sort { a, b in
            if a.tick != b.tick { return a.tick < b.tick }
            let aIsOff = a.bytes.first == 0x80
            let bIsOff = b.bytes.first == 0x80
            if aIsOff != bIsOff { return aIsOff }
            return false
        }

        // 5. Build MTrk chunk payload with delta-times
        var trackData = Data()
        var lastTick: UInt32 = 0

        for event in events {
            let delta = event.tick >= lastTick ? event.tick - lastTick : 0
            lastTick = event.tick
            trackData.append(contentsOf: encodeVLQ(delta))
            trackData.append(contentsOf: event.bytes)
        }

        // End of Track meta event
        trackData.append(contentsOf: encodeVLQ(0))
        trackData.append(contentsOf: [0xFF, 0x2F, 0x00])

        // 6. Assemble Full SMF File (MThd + MTrk)
        var fileData = Data()

        // MThd Header: Format 0, 1 Track, ticksPerQuarter
        fileData.append(contentsOf: [0x4D, 0x54, 0x68, 0x64]) // "MThd"
        fileData.append(contentsOf: [0x00, 0x00, 0x00, 0x06]) // Length = 6
        fileData.append(contentsOf: [0x00, 0x00])             // Format 0
        fileData.append(contentsOf: [0x00, 0x01])             // 1 Track
        fileData.append(contentsOf: [
            UInt8((ticksPerQuarter >> 8) & 0xFF),
            UInt8(ticksPerQuarter & 0xFF)
        ])

        // MTrk Track Chunk:
        fileData.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B]) // "MTrk"
        let trackLength = UInt32(trackData.count)
        fileData.append(contentsOf: [
            UInt8((trackLength >> 24) & 0xFF),
            UInt8((trackLength >> 16) & 0xFF),
            UInt8((trackLength >> 8) & 0xFF),
            UInt8(trackLength & 0xFF)
        ])
        fileData.append(trackData)

        return fileData
    }

    /// Writes clip notes directly to a temporary or permanent .mid file URL.
    @discardableResult
    public static func writeMidi(
        notes: [AbletonNote],
        tempo: Double = 120.0,
        trackName: String = "Clip",
        to url: URL
    ) throws -> URL {
        let data = generateMidiData(notes: notes, tempo: tempo, trackName: trackName)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Encodes a 32-bit unsigned integer into MIDI Variable-Length Quantity (VLQ).
    private static func encodeVLQ(_ value: UInt32) -> [UInt8] {
        var buffer: [UInt8] = []
        var val = value
        buffer.append(UInt8(val & 0x7F))
        val >>= 7

        while val > 0 {
            buffer.insert(UInt8((val & 0x7F) | 0x80), at: 0)
            val >>= 7
        }
        return buffer
    }
}
