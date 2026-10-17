import SwiftUI

public enum AbletonTrackType: String, Sendable, Codable {
    case midi = "MIDI"
    case audio = "Audio"
    case group = "Group"
    case returnMaster = "Master/Return"

    public var systemIcon: String {
        switch self {
        case .midi: return "pianokeys"
        case .audio: return "waveform"
        case .group: return "folder"
        case .returnMaster: return "slider.vertical.3"
        }
    }
}

public struct AbletonNote: Sendable, Identifiable, Equatable, Hashable {
    public var id: String { "\(pitch)-\(startBeat)-\(durationBeats)" }
    public let pitch: Int // 0 - 127 (e.g. 60 = Middle C / C3)
    public let startBeat: Double
    public let durationBeats: Double
    public let velocity: Double // 0 - 127

    public init(pitch: Int, startBeat: Double, durationBeats: Double, velocity: Double = 100) {
        self.pitch = pitch
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.velocity = velocity
    }

    public var noteName: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (pitch / 12) - 2 // Ableton standard: MIDI 60 is C3
        let name = noteNames[pitch % 12]
        return "\(name)\(octave)"
    }
}

public struct AbletonSampleRef: Sendable, Identifiable, Equatable {
    public var id: String { absolutePath ?? relativePath ?? fileName }
    public let fileName: String
    public let relativePath: String?
    public let absolutePath: String?
    public let isMissing: Bool

    public init(fileName: String, relativePath: String? = nil, absolutePath: String? = nil, isMissing: Bool = false) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.isMissing = isMissing
    }
}

public struct AbletonClip: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let startTimeBeats: Double
    public let durationBeats: Double
    public let colorIndex: Int
    public let isMidi: Bool
    public let notes: [AbletonNote]
    public let sampleRef: AbletonSampleRef?

    public init(
        id: String = UUID().uuidString,
        name: String,
        startTimeBeats: Double,
        durationBeats: Double,
        colorIndex: Int = 12,
        isMidi: Bool = true,
        notes: [AbletonNote] = [],
        sampleRef: AbletonSampleRef? = nil
    ) {
        self.id = id
        self.name = name
        self.startTimeBeats = startTimeBeats
        self.durationBeats = durationBeats
        self.colorIndex = colorIndex
        self.isMidi = isMidi
        self.notes = notes
        self.sampleRef = sampleRef
    }

    public var endBeat: Double {
        startTimeBeats + durationBeats
    }

    public var color: Color {
        AbletonColorPalette.color(for: colorIndex)
    }

    public var pitchRange: ClosedRange<Int>? {
        guard !notes.isEmpty else { return nil }
        let pitches = notes.map(\.pitch)
        guard let minP = pitches.min(), let maxP = pitches.max() else { return nil }
        return minP...maxP
    }
}

public enum AbletonDeviceType: String, Sendable, Codable {
    case native = "Native"
    case au = "AU"
    case vst2 = "VST2"
    case vst3 = "VST3"
    case maxForLive = "M4L"

    public var badgeColor: Color {
        switch self {
        case .native: return Color.accent
        case .au: return Color.orange
        case .vst2: return Color.cyan
        case .vst3: return Color.blue
        case .maxForLive: return Color.purple
        }
    }
}

public struct AbletonDevice: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let vendor: String?
    public let type: AbletonDeviceType
    public let isEnabled: Bool
    public let slotIndex: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        vendor: String? = nil,
        type: AbletonDeviceType = .native,
        isEnabled: Bool = true,
        slotIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.type = type
        self.isEnabled = isEnabled
        self.slotIndex = slotIndex
    }
}

public struct AbletonTrack: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: AbletonTrackType
    public let colorIndex: Int
    public let clips: [AbletonClip]
    public let devices: [AbletonDevice]

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: AbletonTrackType,
        colorIndex: Int = 12,
        clips: [AbletonClip] = [],
        devices: [AbletonDevice] = []
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.colorIndex = colorIndex
        self.clips = clips
        self.devices = devices
    }

    public var color: Color {
        AbletonColorPalette.color(for: colorIndex)
    }

    public var totalClipsCount: Int {
        clips.count
    }
}

public struct AbletonArrangement: Sendable, Equatable {
    public let tempo: Double
    public let timeSignatureNumerator: Int
    public let timeSignatureDenominator: Int
    public let tracks: [AbletonTrack]
    public let totalLengthBeats: Double
    public let masterTrack: AbletonTrack?
    public let returnTracks: [AbletonTrack]

    public init(
        tempo: Double = 120.0,
        timeSignatureNumerator: Int = 4,
        timeSignatureDenominator: Int = 4,
        tracks: [AbletonTrack] = [],
        totalLengthBeats: Double = 128.0,
        masterTrack: AbletonTrack? = nil,
        returnTracks: [AbletonTrack] = []
    ) {
        self.tempo = tempo
        self.timeSignatureNumerator = timeSignatureNumerator
        self.timeSignatureDenominator = timeSignatureDenominator
        self.tracks = tracks
        self.totalLengthBeats = totalLengthBeats
        self.masterTrack = masterTrack
        self.returnTracks = returnTracks
    }

    public var allConsoleTracks: [AbletonTrack] {
        var list = tracks
        list.append(contentsOf: returnTracks)
        if let master = masterTrack {
            list.append(master)
        }
        return list
    }

    public var midiClips: [AbletonClip] {
        tracks.flatMap { $0.clips.filter(\.isMidi) }
    }

    public var sampleRefs: [AbletonSampleRef] {
        tracks.flatMap { $0.clips.compactMap(\.sampleRef) }
    }
}

/// Official Ableton Live color palette mapping (colors 0 to 69).
public enum AbletonColorPalette {
    private static let hexPalette: [UInt32] = [
        0xFF9577, 0xED7F59, 0xD4663B, 0xB64C20, 0x9B380D,
        0xFFB570, 0xF59F48, 0xDE842B, 0xBE6712, 0xA25000,
        0xFFDC73, 0xF8CD4E, 0xE0B431, 0xC39917, 0xA67E00,
        0xF0FA65, 0xD7E646, 0xB9CA2E, 0x98A917, 0x7E8E05,
        0xB2FA65, 0x98E446, 0x7CC52C, 0x61A416, 0x4B8704,
        0x6EFB6E, 0x51E251, 0x36C436, 0x1EA11E, 0x0C830C,
        0x67F9A9, 0x4BE08F, 0x32C376, 0x1AA25B, 0x088444,
        0x65FAD7, 0x49E2BE, 0x30C3A0, 0x19A282, 0x078467,
        0x62FAFA, 0x46E2E2, 0x2DC4C4, 0x17A2A2, 0x068484,
        0x65D7FA, 0x49BEE2, 0x30A0C3, 0x1982A2, 0x076784,
        0x6AA9FA, 0x4E8FE2, 0x3572C3, 0x1E57A2, 0x0B3F84,
        0x8383FA, 0x6767E2, 0x4D4DC3, 0x3333A2, 0x1E1E84,
        0xB26AFA, 0x984EE2, 0x7C35C3, 0x611EA2, 0x4B0B84,
        0xFA6DF4, 0xE251DC, 0xC436BD, 0xA21FA0, 0x840C82
    ]

    public static func color(for index: Int) -> Color {
        guard index >= 0 else { return Color.accent }
        let idx = index % hexPalette.count
        let hex = hexPalette[idx]
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
