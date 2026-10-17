import Foundation

/// Parses arrangement tracks, clips, notes, and sample references from an Ableton Live (.als) project file.
public enum AbletonArrangementParser {

    // MARK: - In-Memory Cache
    private static var cache: [URL: (modificationDate: Date, arrangement: AbletonArrangement)] = [:]
    private static let cacheLock = NSLock()

    // MARK: - Pre-compiled Regular Expressions
    private static let midiTrackRegex = try! NSRegularExpression(
        pattern: #"<MidiTrack(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</MidiTrack>"#
    )
    private static let audioTrackRegex = try! NSRegularExpression(
        pattern: #"<AudioTrack(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</AudioTrack>"#
    )
    private static let groupTrackRegex = try! NSRegularExpression(
        pattern: #"<GroupTrack(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</GroupTrack>"#
    )
    private static let midiClipRegex = try! NSRegularExpression(
        pattern: #"<MidiClip(?:\s+[^>]*)?Time=\"([0-9]+(?:\.[0-9]+)?)\"[\s\S]*?>([\s\S]*?)</MidiClip>"#
    )
    private static let audioClipRegex = try! NSRegularExpression(
        pattern: #"<AudioClip(?:\s+[^>]*)?Time=\"([0-9]+(?:\.[0-9]+)?)\"[\s\S]*?>([\s\S]*?)</AudioClip>"#
    )
    private static let trackNamePatterns = [
        try! NSRegularExpression(pattern: #"<UserName\s+Value=\"([^\"]+)\""#),
        try! NSRegularExpression(pattern: #"<EffectiveName\s+Value=\"([^\"]+)\""#),
        try! NSRegularExpression(pattern: #"<Name>\s*<EffectiveName\s+Value=\"([^\"]+)\""#)
    ]
    private static let colorRegex = try! NSRegularExpression(pattern: #"<Color\s+Value=\"([0-9]+)\""#)
    private static let keyTrackRegex = try! NSRegularExpression(
        pattern: #"<KeyTrack>[\s\S]*?<MidiKey\s+Value=\"([0-9]+)\"[\s\S]*?<Notes>([\s\S]*?)</Notes>"#
    )
    private static let midiNoteRegex = try! NSRegularExpression(
        pattern: #"<MidiNote\s+Time=\"([0-9\.]+)\"\s+Duration=\"([0-9\.]+)\"\s+Velocity=\"([0-9\.]+)\""#
    )
    private static let live12NoteRegex = try! NSRegularExpression(
        pattern: #"<MidiNote\s+[^>]*?MidiKey=\"([0-9]+)\"[^>]*?Time=\"([0-9\.]+)\"[^>]*?Duration=\"([0-9\.]+)\"[^>]*?Velocity=\"([0-9\.]+)\""#
    )
    private static let currentStartRegex = try! NSRegularExpression(pattern: #"<CurrentStart\s+Value=\"([^\"]*)\""#)
    private static let currentEndRegex = try! NSRegularExpression(pattern: #"<CurrentEnd\s+Value=\"([^\"]*)\""#)
    private static let nameAttrRegex = try! NSRegularExpression(pattern: #"<Name\s+Value=\"([^\"]*)\""#)
    private static let pathAttrRegex = try! NSRegularExpression(pattern: #"<Path\s+Value=\"([^\"]*)\""#)
    private static let relativePathAttrRegex = try! NSRegularExpression(pattern: #"<RelativePath\s+Value=\"([^\"]*)\""#)
    private static let tempoPatterns = [
        try! NSRegularExpression(pattern: #"<Tempo[\s\S]*?<Manual\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#),
        try! NSRegularExpression(pattern: #"<CurrentSongTempo\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#)
    ]
    private static let timeSigNumeratorRegex = try! NSRegularExpression(pattern: #"<TimeSignature>[\s\S]*?<Numerator\s+Value=\"([0-9]+)\""#)
    private static let timeSigDenominatorRegex = try! NSRegularExpression(pattern: #"<TimeSignature>[\s\S]*?<Denominator\s+Value=\"([0-9]+)\""#)

    /// Parses an arrangement from an .als file on disk with thread-safe memory caching.
    public static func parse(from fileURL: URL, projectFolderURL: URL? = nil) -> AbletonArrangement? {
        let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        cacheLock.lock()
        if let cached = cache[fileURL], cached.modificationDate == modDate {
            cacheLock.unlock()
            return cached.arrangement
        }
        cacheLock.unlock()

        guard let xml = Gunzip.readTextFile(at: fileURL) else { return nil }
        let arrangement = parse(xml: xml, projectFolderURL: projectFolderURL ?? fileURL.deletingLastPathComponent())

        cacheLock.lock()
        cache[fileURL] = (modDate, arrangement)
        cacheLock.unlock()

        return arrangement
    }

    /// Parses arrangement data from unzipped Ableton XML string.
    public static func parse(xml: String, projectFolderURL: URL? = nil) -> AbletonArrangement {
        let tempo = extractTempo(from: xml) ?? 120.0
        let (num, denom) = extractTimeSignature(from: xml)

        // Slicing <Tracks> ... </Tracks> reduces string scan area by up to 98%,
        // bypassing tens of megabytes of preset and automation envelope data.
        let tracksSlice: String
        if let start = xml.range(of: "<Tracks>"),
           let end = xml.range(of: "</Tracks>", range: start.upperBound..<xml.endIndex) {
            tracksSlice = String(xml[start.lowerBound..<end.upperBound])
        } else {
            tracksSlice = xml
        }

        var tracks: [AbletonTrack] = []

        // Extract MidiTracks
        let midiTracks = extractTracks(regex: midiTrackRegex, in: tracksSlice, type: .midi, projectFolderURL: projectFolderURL)
        tracks.append(contentsOf: midiTracks)

        // Extract AudioTracks
        let audioTracks = extractTracks(regex: audioTrackRegex, in: tracksSlice, type: .audio, projectFolderURL: projectFolderURL)
        tracks.append(contentsOf: audioTracks)

        // Extract GroupTracks
        let groupTracks = extractTracks(regex: groupTrackRegex, in: tracksSlice, type: .group, projectFolderURL: projectFolderURL)
        tracks.append(contentsOf: groupTracks)

        // Calculate total arrangement length in beats
        let allClips = tracks.flatMap(\.clips)
        let maxClipEnd = allClips.map(\.endBeat).max() ?? 64.0
        let totalLength = max(64.0, ceil(maxClipEnd / 16.0) * 16.0)

        return AbletonArrangement(
            tempo: tempo,
            timeSignatureNumerator: num,
            timeSignatureDenominator: denom,
            tracks: tracks,
            totalLengthBeats: totalLength
        )
    }

    // MARK: - Track Extraction

    private static func extractTracks(
        regex: NSRegularExpression,
        in xml: String,
        type: AbletonTrackType,
        projectFolderURL: URL?
    ) -> [AbletonTrack] {
        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            let id = match.range(at: 1).location != NSNotFound
                ? nsString.substring(with: match.range(at: 1))
                : UUID().uuidString
            let body = nsString.substring(with: match.range(at: 2))

            let name = extractTrackName(from: body) ?? "\(type.rawValue) Track"
            let colorIndex = extractColor(from: body) ?? 12
            let clips = extractClips(from: body, type: type, projectFolderURL: projectFolderURL)

            return AbletonTrack(
                id: id,
                name: name,
                type: type,
                colorIndex: colorIndex,
                clips: clips
            )
        }
    }

    private static func extractTrackName(from text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        for regex in trackNamePatterns {
            if let match = regex.firstMatch(in: text, range: range),
               match.range(at: 1).location != NSNotFound {
                let raw = nsText.substring(with: match.range(at: 1))
                let decoded = decodeXMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    private static func extractColor(from text: String) -> Int? {
        let nsText = text as NSString
        guard let match = colorRegex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        return Int(nsText.substring(with: match.range(at: 1)))
    }

    // MARK: - Clip Extraction

    private static func extractClips(
        from trackBody: String,
        type: AbletonTrackType,
        projectFolderURL: URL?
    ) -> [AbletonClip] {
        let clipRegex = type == .midi ? midiClipRegex : audioClipRegex
        let nsString = trackBody as NSString
        let matches = clipRegex.matches(in: trackBody, range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound,
                  let startTime = Double(nsString.substring(with: match.range(at: 1))) else {
                return nil
            }
            let clipBody = nsString.substring(with: match.range(at: 2))

            let name = extractAttribute(regex: nameAttrRegex, in: clipBody) ?? "Clip"
            let duration = extractClipDuration(from: clipBody) ?? 16.0
            let colorIndex = extractColor(from: clipBody) ?? 12

            var notes: [AbletonNote] = []
            var sampleRef: AbletonSampleRef? = nil

            if type == .midi {
                notes = extractMidiNotes(from: clipBody)
            } else if type == .audio {
                sampleRef = extractSampleRef(from: clipBody, projectFolderURL: projectFolderURL)
            }

            return AbletonClip(
                name: decodeXMLEntities(name),
                startTimeBeats: startTime,
                durationBeats: max(0.25, duration),
                colorIndex: colorIndex,
                isMidi: type == .midi,
                notes: notes,
                sampleRef: sampleRef
            )
        }
    }

    private static func extractClipDuration(from clipBody: String) -> Double? {
        guard let startStr = extractAttribute(regex: currentStartRegex, in: clipBody),
              let endStr = extractAttribute(regex: currentEndEndRegexFallback(in: clipBody) ?? currentEndRegex, in: clipBody),
              let start = Double(startStr),
              let end = Double(endStr),
              end > start else {
            return nil
        }
        return end - start
    }

    private static func currentEndEndRegexFallback(in text: String) -> NSRegularExpression? {
        return currentEndRegex
    }

    // MARK: - Note Extraction (Ableton 10/11/12)

    private static func extractMidiNotes(from clipBody: String) -> [AbletonNote] {
        var notes: [AbletonNote] = []

        // Format 1 (Live 10/11): <KeyTrack><MidiKey Value="60"/><Notes><MidiNote Time="0" Duration="1" Velocity="100".../>
        let nsBody = clipBody as NSString
        let ktMatches = keyTrackRegex.matches(in: clipBody, range: NSRange(location: 0, length: nsBody.length))

        for ktMatch in ktMatches {
            guard ktMatch.range(at: 1).location != NSNotFound,
                  let pitch = Int(nsBody.substring(with: ktMatch.range(at: 1))) else { continue }
            let notesBlock = nsBody.substring(with: ktMatch.range(at: 2))

            let nsNotes = notesBlock as NSString
            let noteMatches = midiNoteRegex.matches(in: notesBlock, range: NSRange(location: 0, length: nsNotes.length))

            for nm in noteMatches {
                guard let time = Double(nsNotes.substring(with: nm.range(at: 1))),
                      let dur = Double(nsNotes.substring(with: nm.range(at: 2))),
                      let vel = Double(nsNotes.substring(with: nm.range(at: 3))) else { continue }
                notes.append(AbletonNote(pitch: pitch, startBeat: time, durationBeats: dur, velocity: vel))
            }
        }

        // Format 2 (Live 12 simplified): <MidiNote MidiKey="60" Time="0" Duration="1" Velocity="100".../>
        if notes.isEmpty {
            let matches = live12NoteRegex.matches(in: clipBody, range: NSRange(location: 0, length: nsBody.length))

            for m in matches {
                guard let pitch = Int(nsBody.substring(with: m.range(at: 1))),
                      let time = Double(nsBody.substring(with: m.range(at: 2))),
                      let dur = Double(nsBody.substring(with: m.range(at: 3))),
                      let vel = Double(nsBody.substring(with: m.range(at: 4))) else { continue }
                notes.append(AbletonNote(pitch: pitch, startBeat: time, durationBeats: dur, velocity: vel))
            }
        }

        return notes.sorted { $0.startBeat < $1.startBeat }
    }

    // MARK: - Sample Reference Extraction

    private static func extractSampleRef(from clipBody: String, projectFolderURL: URL?) -> AbletonSampleRef? {
        guard clipBody.contains("<SampleRef>") else { return nil }

        let name = extractAttribute(regex: nameAttrRegex, in: clipBody) ?? "Audio"
        let path = extractAttribute(regex: pathAttrRegex, in: clipBody)
        let relativePath = extractAttribute(regex: relativePathAttrRegex, in: clipBody)

        var exists = false
        if let path, !path.isEmpty {
            exists = FileManager.default.fileExists(atPath: path)
        }
        if !exists, let relativePath, let projectFolderURL {
            let resolved = projectFolderURL.appendingPathComponent(relativePath).path
            exists = FileManager.default.fileExists(atPath: resolved)
        }

        return AbletonSampleRef(
            fileName: decodeXMLEntities(name),
            relativePath: relativePath,
            absolutePath: path,
            isMissing: !exists
        )
    }

    // MARK: - Helpers

    private static func extractTempo(from xml: String) -> Double? {
        let nsXml = xml as NSString
        let range = NSRange(location: 0, length: nsXml.length)

        for regex in tempoPatterns {
            guard let match = regex.firstMatch(in: xml, range: range),
                  let val = Double(nsXml.substring(with: match.range(at: 1))), val > 0 else { continue }
            return val
        }
        return nil
    }

    private static func extractTimeSignature(from xml: String) -> (Int, Int) {
        let nsXml = xml as NSString
        let range = NSRange(location: 0, length: nsXml.length)

        guard let numMatch = timeSigNumeratorRegex.firstMatch(in: xml, range: range),
              let num = Int(nsXml.substring(with: numMatch.range(at: 1))) else {
            return (4, 4)
        }
        let denomMatch = timeSigDenominatorRegex.firstMatch(in: xml, range: range)
        let denom = denomMatch != nil ? Int(nsXml.substring(with: denomMatch!.range(at: 1))) ?? 4 : 4
        return (num, denom)
    }

    private static func extractAttribute(regex: NSRegularExpression, in text: String) -> String? {
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func decodeXMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
