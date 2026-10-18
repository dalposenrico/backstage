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
    private static let returnTrackRegex = try! NSRegularExpression(
        pattern: #"<ReturnTrack(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</ReturnTrack>"#
    )
    private static let masterTrackRegex = try! NSRegularExpression(
        pattern: #"<MasterTrack(?:\s+Id=\"([^\"]*)\"[^>]*)?>([\s\S]*?)</MasterTrack>"#
    )
    private static let midiClipRegex = try! NSRegularExpression(
        pattern: #"<MidiClip(?:\s+[^>]*)?Time=\"([0-9]+(?:\.[0-9]+)?)\"[\s\S]*?>([\s\S]*?)</MidiClip>"#
    )
    private static let audioClipRegex = try! NSRegularExpression(
        pattern: #"<AudioClip(?:\s+[^>]*)?Time=\"([0-9]+(?:\.[0-9]+)?)\"[\s\S]*?>([\s\S]*?)</AudioClip>"#
    )
    private static let pluginNameRegex = try! NSRegularExpression(
        pattern: #"<(?:PlugName|Name|ProductName)\s+Value=\"([^\"]+)\""#
    )
    private static let pluginVendorRegex = try! NSRegularExpression(
        pattern: #"<Manufacturer\s+Value=\"([^\"]+)\""#
    )
    private static let userNameRegex = try! NSRegularExpression(
        pattern: #"<UserName\s+Value=\"([^\"]+)\""#
    )
    private static let isOnRegex = try! NSRegularExpression(
        pattern: #"<(?:On|IsOn)>[\s\S]*?<Manual\s+Value=\"([^\"]+)\""#
    )
    private static let trackNamePatterns = [
        try! NSRegularExpression(pattern: #"<UserName\s+Value=\"([^\"]+)\""#),
        try! NSRegularExpression(pattern: #"<EffectiveName\s+Value=\"([^\"]+)\""#),
        try! NSRegularExpression(pattern: #"<Name>\s*<EffectiveName\s+Value=\"([^\"]+)\""#)
    ]
    private static let colorRegex = try! NSRegularExpression(pattern: #"<Color\s+Value=\"([0-9]+)\""#)
    private static let trackGroupIdRegex = try! NSRegularExpression(pattern: #"<TrackGroupId\s+Value=\"([^\"]+)\""#)
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
    public static func parse(
        from fileURL: URL,
        projectFolderURL: URL? = nil,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) -> AbletonArrangement? {
        let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        cacheLock.lock()
        if let cached = cache[fileURL], cached.modificationDate == modDate {
            cacheLock.unlock()
            onProgress?(1.0, "Arrangement ready")
            return cached.arrangement
        }
        cacheLock.unlock()

        onProgress?(0.12, "Decompressing Ableton project set…")
        guard let xml = Gunzip.readTextFile(at: fileURL) else { return nil }

        let arrangement = parse(
            xml: xml,
            projectFolderURL: projectFolderURL ?? fileURL.deletingLastPathComponent(),
            onProgress: onProgress
        )

        cacheLock.lock()
        cache[fileURL] = (modDate, arrangement)
        cacheLock.unlock()

        return arrangement
    }

    /// Parses arrangement data from unzipped Ableton XML string.
    public static func parse(
        xml: String,
        projectFolderURL: URL? = nil,
        onProgress: (@Sendable (Double, String) -> Void)? = nil
    ) -> AbletonArrangement {
        onProgress?(0.25, "Reading tempo & song structure…")
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

        var rawTrackMatches: [(location: Int, track: AbletonTrack)] = []

        onProgress?(0.35, "Scanning MIDI tracks…")
        let midiTracks = extractTracks(regex: midiTrackRegex, in: tracksSlice, type: .midi, projectFolderURL: projectFolderURL) { current, total, name in
            let pct = 0.35 + (Double(current) / Double(max(1, total))) * 0.25
            onProgress?(pct, "MIDI track \(current)/\(total): \(name)")
        }
        rawTrackMatches.append(contentsOf: midiTracks)

        onProgress?(0.60, "Scanning audio tracks & waveforms…")
        let audioTracks = extractTracks(regex: audioTrackRegex, in: tracksSlice, type: .audio, projectFolderURL: projectFolderURL) { current, total, name in
            let pct = 0.60 + (Double(current) / Double(max(1, total))) * 0.22
            onProgress?(pct, "Audio track \(current)/\(total): \(name)")
        }
        rawTrackMatches.append(contentsOf: audioTracks)

        onProgress?(0.82, "Scanning group & return tracks…")
        let groupTracks = extractTracks(regex: groupTrackRegex, in: tracksSlice, type: .group, projectFolderURL: projectFolderURL) { current, total, name in
            let pct = 0.82 + (Double(current) / Double(max(1, total))) * 0.08
            onProgress?(pct, "Group track \(current)/\(total): \(name)")
        }
        rawTrackMatches.append(contentsOf: groupTracks)

        // Sort tracks by their exact document order in <Tracks>
        let tracks = rawTrackMatches.sorted { $0.location < $1.location }.map(\.track)

        // Extract MasterTrack
        onProgress?(0.90, "Resolving master track & sample paths…")
        let masterTrack = extractMasterTrack(in: xml)

        // Extract ReturnTracks
        let returnTracks: [AbletonTrack]
        if let returnStart = xml.range(of: "<ReturnTracks>"),
           let returnEnd = xml.range(of: "</ReturnTracks>", range: returnStart.upperBound..<xml.endIndex) {
            let returnSlice = String(xml[returnStart.lowerBound..<returnEnd.upperBound])
            returnTracks = extractTracks(regex: returnTrackRegex, in: returnSlice, type: .returnMaster, projectFolderURL: projectFolderURL).map(\.track)
        } else {
            returnTracks = extractTracks(regex: returnTrackRegex, in: xml, type: .returnMaster, projectFolderURL: projectFolderURL).map(\.track)
        }

        // Calculate total arrangement length in beats
        onProgress?(0.96, "Calculating timeline boundaries…")
        let allClips = tracks.flatMap(\.clips)
        let maxClipEnd = allClips.map(\.endBeat).max() ?? 64.0
        let totalLength = max(64.0, ceil(maxClipEnd / 16.0) * 16.0)

        onProgress?(1.0, "Arrangement ready")

        return AbletonArrangement(
            tempo: tempo,
            timeSignatureNumerator: num,
            timeSignatureDenominator: denom,
            tracks: tracks,
            totalLengthBeats: totalLength,
            masterTrack: masterTrack,
            returnTracks: returnTracks
        )
    }

    // MARK: - Track Extraction

    private static func extractTracks(
        regex: NSRegularExpression,
        in xml: String,
        type: AbletonTrackType,
        projectFolderURL: URL?,
        onTrackProgress: ((Int, Int, String) -> Void)? = nil
    ) -> [(location: Int, track: AbletonTrack)] {
        let nsString = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))
        let total = matches.count

        return matches.enumerated().compactMap { index, match in
            let id = match.range(at: 1).location != NSNotFound
                ? nsString.substring(with: match.range(at: 1))
                : UUID().uuidString
            let body = nsString.substring(with: match.range(at: 2))

            let name = extractTrackName(from: body) ?? "\(type.rawValue) Track"
            onTrackProgress?(index + 1, total, name)
            let colorIndex = extractColor(from: body) ?? 12
            let rawGroupId = extractAttribute(regex: trackGroupIdRegex, in: body)
            let trackGroupId = (rawGroupId != nil && rawGroupId != "-1") ? rawGroupId : nil
            let clips = extractClips(from: body, type: type, projectFolderURL: projectFolderURL)
            let devices = extractDevices(from: body)

            let track = AbletonTrack(
                id: id,
                name: name,
                type: type,
                colorIndex: colorIndex,
                trackGroupId: trackGroupId,
                clips: clips,
                devices: devices
            )
            return (location: match.range.location, track: track)
        }
    }

    private static func extractMasterTrack(in xml: String) -> AbletonTrack? {
        let nsString = xml as NSString
        guard let match = masterTrackRegex.firstMatch(in: xml, range: NSRange(location: 0, length: nsString.length)) else {
            return nil
        }
        let id = match.range(at: 1).location != NSNotFound
            ? nsString.substring(with: match.range(at: 1))
            : "master"
        let body = nsString.substring(with: match.range(at: 2))
        let name = extractTrackName(from: body) ?? "Master"
        let colorIndex = extractColor(from: body) ?? 0
        let devices = extractDevices(from: body)

        return AbletonTrack(
            id: id,
            name: name,
            type: .returnMaster,
            colorIndex: colorIndex,
            clips: [],
            devices: devices
        )
    }

    // MARK: - Known Native Devices
    private static let knownNativeDevices: [String: String] = [
        "Eq8": "EQ Eight",
        "ChannelEq": "Channel EQ",
        "Compressor2": "Compressor",
        "GlueCompressor": "Glue Compressor",
        "Limiter": "Limiter",
        "Saturator": "Saturator",
        "UtilityDevice": "Utility",
        "StereoGain": "Utility",
        "Delay": "Delay",
        "Reverb": "Reverb",
        "Echo": "Echo",
        "AutoFilter": "Auto Filter",
        "DrumBuss": "Drum Buss",
        "Overdrive": "Overdrive",
        "Pedal": "Pedal",
        "Chorus2": "Chorus-Ensemble",
        "Chorus": "Chorus",
        "PhaserNew": "Phaser-Flanger",
        "Phaser": "Phaser",
        "Redux2": "Redux",
        "Redux": "Redux",
        "Amp": "Amp",
        "Cabinet": "Cabinet",
        "Corpus": "Corpus",
        "MultibandDynamics": "Multiband Dynamics",
        "Gate": "Gate",
        "Vocoder": "Vocoder",
        "Tuner": "Tuner",
        "Spectrum": "Spectrum",
        "AudioEffectGroupDevice": "Audio Effect Rack",
        "MidiEffectGroupDevice": "MIDI Effect Rack",
        "InstrumentGroupDevice": "Instrument Rack",
        "OriginalSimpler": "Simpler",
        "MultiSampler": "Sampler",
        "UltraAnalog": "Analog",
        "Operator": "Operator",
        "Wavetable": "Wavetable",
        "Drift": "Drift",
        "Roar": "Roar",
        "SpectralResonator": "Spectral Resonator",
        "SpectralTime": "Spectral Time",
        "Hybrid": "Hybrid Reverb",
        "Shifter": "Shifter",
        "MidiArpeggiator": "Arpeggiator",
        "MidiChord": "Chord",
        "MidiPitcher": "Pitch",
        "MidiRandom": "Random",
        "MidiScale": "Scale",
        "MidiVelocitySlider": "Velocity",
        "MidiNoteLength": "Note Length"
    ]

    // MARK: - Device Extraction

    private static func extractDevices(from trackXml: String) -> [AbletonDevice] {
        guard let chainRange = trackXml.range(of: "<DeviceChain>") else { return [] }
        let afterChain = trackXml[chainRange.upperBound...]
        guard let devOpenRange = afterChain.range(of: "<Devices>") else { return [] }
        let contentStart = devOpenRange.upperBound

        // Match the closing </Devices> corresponding to this opening <Devices>
        var nestedCount = 0
        var searchIndex = contentStart
        var devCloseRange: Range<String.Index>?

        while searchIndex < afterChain.endIndex {
            let nextOpen = afterChain.range(of: "<Devices>", range: searchIndex..<afterChain.endIndex)
            let nextClose = afterChain.range(of: "</Devices>", range: searchIndex..<afterChain.endIndex)

            guard let close = nextClose else { break }

            if let open = nextOpen, open.lowerBound < close.lowerBound {
                nestedCount += 1
                searchIndex = open.upperBound
            } else {
                if nestedCount == 0 {
                    devCloseRange = close
                    break
                } else {
                    nestedCount -= 1
                    searchIndex = close.upperBound
                }
            }
        }

        guard let closeRange = devCloseRange else { return [] }
        let devicesString = String(afterChain[contentStart..<closeRange.lowerBound])
        return parseDeviceElements(devicesString)
    }

    private static func parseDeviceElements(_ devicesXml: String) -> [AbletonDevice] {
        var devices: [AbletonDevice] = []
        var currentIndex = devicesXml.startIndex
        var slotIndex = 0

        while currentIndex < devicesXml.endIndex {
            guard let openBracket = devicesXml.range(of: "<", range: currentIndex..<devicesXml.endIndex) else {
                break
            }
            let afterOpen = openBracket.upperBound
            if afterOpen >= devicesXml.endIndex { break }

            if devicesXml[afterOpen] == "/" || devicesXml[afterOpen] == "!" || devicesXml[afterOpen] == "?" {
                guard let closeBracket = devicesXml.range(of: ">", range: afterOpen..<devicesXml.endIndex) else { break }
                currentIndex = closeBracket.upperBound
                continue
            }

            var tagEnd = afterOpen
            while tagEnd < devicesXml.endIndex,
                  devicesXml[tagEnd] != " " && devicesXml[tagEnd] != "\t" &&
                  devicesXml[tagEnd] != "\n" && devicesXml[tagEnd] != "\r" &&
                  devicesXml[tagEnd] != ">" && devicesXml[tagEnd] != "/" {
                tagEnd = devicesXml.index(after: tagEnd)
            }
            let tagName = String(devicesXml[afterOpen..<tagEnd])
            guard !tagName.isEmpty else {
                currentIndex = devicesXml.index(after: afterOpen)
                continue
            }

            guard let openTagEnd = devicesXml.range(of: ">", range: tagEnd..<devicesXml.endIndex) else {
                break
            }

            let tagHeader = devicesXml[openBracket.lowerBound..<openTagEnd.upperBound]
            if tagHeader.hasSuffix("/>") {
                let dev = parseSingleDevice(tag: tagName, xml: String(tagHeader), slotIndex: slotIndex)
                devices.append(dev)
                slotIndex += 1
                currentIndex = openTagEnd.upperBound
                continue
            }

            let closingPattern = "</\(tagName)>"
            let openingPrefix = "<\(tagName)"
            var depth = 1
            var scanIdx = openTagEnd.upperBound
            var foundEnd: Range<String.Index>?

            while scanIdx < devicesXml.endIndex {
                let nextClose = devicesXml.range(of: closingPattern, range: scanIdx..<devicesXml.endIndex)
                guard let close = nextClose else { break }

                let nextOpen = devicesXml.range(of: openingPrefix, range: scanIdx..<close.lowerBound)
                if let open = nextOpen {
                    let afterOpenIdx = open.upperBound
                    if afterOpenIdx < devicesXml.endIndex {
                        let c = devicesXml[afterOpenIdx]
                        if c == " " || c == ">" || c == "/" {
                            if let tagClose = devicesXml.range(of: ">", range: afterOpenIdx..<close.lowerBound) {
                                let subTag = devicesXml[open.lowerBound..<tagClose.upperBound]
                                if !subTag.hasSuffix("/>") {
                                    depth += 1
                                }
                                scanIdx = tagClose.upperBound
                                continue
                            }
                        }
                    }
                }

                depth -= 1
                if depth == 0 {
                    foundEnd = close
                    break
                } else {
                    scanIdx = close.upperBound
                }
            }

            guard let endMatch = foundEnd else {
                currentIndex = openTagEnd.upperBound
                continue
            }

            let fullDeviceXml = String(devicesXml[openBracket.lowerBound..<endMatch.upperBound])
            let dev = parseSingleDevice(tag: tagName, xml: fullDeviceXml, slotIndex: slotIndex)
            devices.append(dev)
            slotIndex += 1
            currentIndex = endMatch.upperBound
        }

        return devices
    }

    private static func parseSingleDevice(tag: String, xml: String, slotIndex: Int) -> AbletonDevice {
        let isEnabled: Bool
        if let onMatch = isOnRegex.firstMatch(in: xml, range: NSRange(location: 0, length: (xml as NSString).length)) {
            let val = (xml as NSString).substring(with: onMatch.range(at: 1)).lowercased()
            isEnabled = (val != "false" && val != "0")
        } else {
            isEnabled = true
        }

        let customName = extractFirstRegex(regex: userNameRegex, in: xml)

        if tag == "AuPluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: xml) ?? "Audio Unit"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: xml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .au,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag == "Vst3PluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: xml) ?? "VST3 Plugin"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: xml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .vst3,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag == "VstPluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: xml) ?? "VST Plugin"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: xml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .vst2,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag.starts(with: "MxDevice") {
            let name = customName ?? extractFirstRegex(regex: pluginNameRegex, in: xml) ?? "Max for Live"
            return AbletonDevice(
                name: name,
                vendor: "Cycling '74",
                type: .maxForLive,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else {
            let standardName = knownNativeDevices[tag] ?? tag
            let displayName = customName != nil ? "\(customName!) (\(standardName))" : standardName
            return AbletonDevice(
                name: displayName,
                vendor: "Ableton",
                type: .native,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        }
    }

    private static func extractFirstRegex(regex: NSRegularExpression, in text: String) -> String? {
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        let raw = nsText.substring(with: match.range(at: 1))
        let decoded = decodeXMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func extractTrackName(from text: String) -> String? {
        let searchSlice: String
        if let nameStart = text.range(of: "<Name>"),
           let nameEnd = text.range(of: "</Name>", range: nameStart.upperBound..<text.endIndex) {
            searchSlice = String(text[nameStart.lowerBound..<nameEnd.upperBound])
        } else {
            searchSlice = text
        }

        let nsText = searchSlice as NSString
        let range = NSRange(location: 0, length: nsText.length)

        for regex in trackNamePatterns {
            if let match = regex.firstMatch(in: searchSlice, range: range),
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
