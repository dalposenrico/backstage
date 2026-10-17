import Foundation

/// Parses arrangement tracks, clips, notes, and sample references from an Ableton Live (.als) project file.
public enum AbletonArrangementParser {

    /// Parses an arrangement from an .als file on disk.
    public static func parse(from fileURL: URL, projectFolderURL: URL? = nil) -> AbletonArrangement? {
        guard let xml = Gunzip.readTextFile(at: fileURL) else { return nil }
        return parse(xml: xml, projectFolderURL: projectFolderURL ?? fileURL.deletingLastPathComponent())
    }

    /// Parses arrangement data from unzipped Ableton XML string.
    public static func parse(xml: String, projectFolderURL: URL? = nil) -> AbletonArrangement {
        let tempo = extractTempo(from: xml) ?? 120.0
        let (num, denom) = extractTimeSignature(from: xml)

        var tracks: [AbletonTrack] = []

        // Extract MidiTracks
        let midiTracks = extractTracks(ofKind: "MidiTrack", in: xml, type: .midi, projectFolderURL: projectFolderURL)
        tracks.append(contentsOf: midiTracks)

        // Extract AudioTracks
        let audioTracks = extractTracks(ofKind: "AudioTrack", in: xml, type: .audio, projectFolderURL: projectFolderURL)
        tracks.append(contentsOf: audioTracks)

        // Extract GroupTracks
        let groupTracks = extractTracks(ofKind: "GroupTrack", in: xml, type: .group, projectFolderURL: projectFolderURL)
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
        ofKind tag: String,
        in xml: String,
        type: AbletonTrackType,
        projectFolderURL: URL?
    ) -> [AbletonTrack] {
        guard let trackRegex = try? NSRegularExpression(
            pattern: #"<"# + tag + #"(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</"# + tag + #">"#
        ) else { return [] }

        let nsString = xml as NSString
        let matches = trackRegex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))

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
        let patterns = [
            #"<UserName\s+Value=\"([^\"]+)\""#,
            #"<EffectiveName\s+Value=\"([^\"]+)\""#,
            #"<Name>\s*<EffectiveName\s+Value=\"([^\"]+)\""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
               match.range(at: 1).location != NSNotFound {
                let raw = (text as NSString).substring(with: match.range(at: 1))
                let decoded = decodeXMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    private static func extractColor(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"<Color\s+Value=\"([0-9]+)\""#),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        return Int((text as NSString).substring(with: match.range(at: 1)))
    }

    // MARK: - Clip Extraction

    private static func extractClips(
        from trackBody: String,
        type: AbletonTrackType,
        projectFolderURL: URL?
    ) -> [AbletonClip] {
        let clipTag = type == .midi ? "MidiClip" : "AudioClip"
        guard let clipRegex = try? NSRegularExpression(
            pattern: #"<"# + clipTag + #"(?:\s+[^>]*)?Time=\"([0-9]+(?:\.[0-9]+)?)\"[\s\S]*?>([\s\S]*?)</"# + clipTag + #">"#
        ) else { return [] }

        let nsString = trackBody as NSString
        let matches = clipRegex.matches(in: trackBody, range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.range(at: 1).location != NSNotFound,
                  let startTime = Double(nsString.substring(with: match.range(at: 1))) else {
                return nil
            }
            let clipBody = nsString.substring(with: match.range(at: 2))

            let name = extractAttribute(named: "Name", in: clipBody) ?? "Clip"
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
        guard let startStr = extractAttribute(named: "CurrentStart", in: clipBody),
              let endStr = extractAttribute(named: "CurrentEnd", in: clipBody),
              let start = Double(startStr),
              let end = Double(endStr),
              end > start else {
            return nil
        }
        return end - start
    }

    // MARK: - Note Extraction (Ableton 10/11/12)

    private static func extractMidiNotes(from clipBody: String) -> [AbletonNote] {
        var notes: [AbletonNote] = []

        // Format 1 (Live 10/11): <KeyTrack><MidiKey Value="60"/><Notes><MidiNote Time="0" Duration="1" Velocity="100".../>
        if let keyTrackRegex = try? NSRegularExpression(pattern: #"<KeyTrack>[\s\S]*?<MidiKey\s+Value=\"([0-9]+)\"[\s\S]*?<Notes>([\s\S]*?)</Notes>"#) {
            let nsBody = clipBody as NSString
            let ktMatches = keyTrackRegex.matches(in: clipBody, range: NSRange(location: 0, length: nsBody.length))

            for ktMatch in ktMatches {
                guard ktMatch.range(at: 1).location != NSNotFound,
                      let pitch = Int(nsBody.substring(with: ktMatch.range(at: 1))) else { continue }
                let notesBlock = nsBody.substring(with: ktMatch.range(at: 2))

                if let noteRegex = try? NSRegularExpression(
                    pattern: #"<MidiNote\s+Time=\"([0-9\.]+)\"\s+Duration=\"([0-9\.]+)\"\s+Velocity=\"([0-9\.]+)\""#
                ) {
                    let nsNotes = notesBlock as NSString
                    let noteMatches = noteRegex.matches(in: notesBlock, range: NSRange(location: 0, length: nsNotes.length))

                    for nm in noteMatches {
                        guard let time = Double(nsNotes.substring(with: nm.range(at: 1))),
                              let dur = Double(nsNotes.substring(with: nm.range(at: 2))),
                              let vel = Double(nsNotes.substring(with: nm.range(at: 3))) else { continue }
                        notes.append(AbletonNote(pitch: pitch, startBeat: time, durationBeats: dur, velocity: vel))
                    }
                }
            }
        }

        // Format 2 (Live 12 simplified): <MidiNote MidiKey="60" Time="0" Duration="1" Velocity="100".../>
        if notes.isEmpty {
            if let noteRegex = try? NSRegularExpression(
                pattern: #"<MidiNote\s+[^>]*?MidiKey=\"([0-9]+)\"[^>]*?Time=\"([0-9\.]+)\"[^>]*?Duration=\"([0-9\.]+)\"[^>]*?Velocity=\"([0-9\.]+)\""#
            ) {
                let nsBody = clipBody as NSString
                let matches = noteRegex.matches(in: clipBody, range: NSRange(location: 0, length: nsBody.length))

                for m in matches {
                    guard let pitch = Int(nsBody.substring(with: m.range(at: 1))),
                          let time = Double(nsBody.substring(with: m.range(at: 2))),
                          let dur = Double(nsBody.substring(with: m.range(at: 3))),
                          let vel = Double(nsBody.substring(with: m.range(at: 4))) else { continue }
                    notes.append(AbletonNote(pitch: pitch, startBeat: time, durationBeats: dur, velocity: vel))
                }
            }
        }

        return notes.sorted { $0.startBeat < $1.startBeat }
    }

    // MARK: - Sample Reference Extraction

    private static func extractSampleRef(from clipBody: String, projectFolderURL: URL?) -> AbletonSampleRef? {
        guard clipBody.contains("<SampleRef>") else { return nil }

        let name = extractAttribute(named: "Name", in: clipBody) ?? "Audio"
        let path = extractAttribute(named: "Path", in: clipBody)
        let relativePath = extractAttribute(named: "RelativePath", in: clipBody)

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
        let patterns = [
            #"<Tempo[\s\S]*?<Manual\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#,
            #"<CurrentSongTempo\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)),
                  let val = Double((xml as NSString).substring(with: match.range(at: 1))), val > 0 else { continue }
            return val
        }
        return nil
    }

    private static func extractTimeSignature(from xml: String) -> (Int, Int) {
        guard let numRegex = try? NSRegularExpression(pattern: #"<TimeSignature>[\s\S]*?<Numerator\s+Value=\"([0-9]+)\""#),
              let numMatch = numRegex.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)),
              let num = Int((xml as NSString).substring(with: numMatch.range(at: 1))) else {
            return (4, 4)
        }
        let denomRegex = try? NSRegularExpression(pattern: #"<TimeSignature>[\s\S]*?<Denominator\s+Value=\"([0-9]+)\""#)
        let denomMatch = denomRegex?.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length))
        let denom = denomMatch != nil ? Int((xml as NSString).substring(with: denomMatch!.range(at: 1))) ?? 4 : 4
        return (num, denom)
    }

    private static func extractAttribute(named name: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<"# + NSRegularExpression.escapedPattern(for: name) + #"\s+Value=\"([^\"]*)\""#
        ),
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
        match.range(at: 1).location != NSNotFound else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
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
