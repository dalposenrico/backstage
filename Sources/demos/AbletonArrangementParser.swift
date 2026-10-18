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
        let nsXml = xml as NSString
        let returnStart = nsXml.range(of: "<ReturnTracks>")
        if returnStart.location != NSNotFound {
            let returnEnd = nsXml.range(of: "</ReturnTracks>", options: [], range: NSRange(location: returnStart.location, length: nsXml.length - returnStart.location))
            if returnEnd.location != NSNotFound {
                let returnSlice = nsXml.substring(with: NSRange(location: returnStart.location, length: (returnEnd.location + returnEnd.length) - returnStart.location))
                returnTracks = extractTracks(regex: returnTrackRegex, in: returnSlice, type: .returnMaster, projectFolderURL: projectFolderURL).map(\.track)
            } else {
                returnTracks = []
            }
        } else {
            returnTracks = []
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
        let ns = xml as NSString
        let openRange = ns.range(of: "<MasterTrack")
        guard openRange.location != NSNotFound else { return nil }
        let closeRange = ns.range(of: "</MasterTrack>", options: [], range: NSRange(location: openRange.location, length: ns.length - openRange.location))
        guard closeRange.location != NSNotFound else { return nil }

        let masterSlice = ns.substring(with: NSRange(location: openRange.location, length: (closeRange.location + closeRange.length) - openRange.location))
        let idMatch = masterTrackRegex.firstMatch(in: masterSlice, range: NSRange(location: 0, length: (masterSlice as NSString).length))
        let id = (idMatch != nil && idMatch!.range(at: 1).location != NSNotFound)
            ? (masterSlice as NSString).substring(with: idMatch!.range(at: 1))
            : "master"
        let name = extractTrackName(from: masterSlice) ?? "Master"
        let colorIndex = extractColor(from: masterSlice) ?? 0
        let devices = extractDevices(from: masterSlice)

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
        let ns = trackXml as NSString
        let chainRange = ns.range(of: "<DeviceChain>")
        guard chainRange.location != NSNotFound else { return [] }

        let afterChainLoc = chainRange.location + chainRange.length
        let afterChainLen = ns.length - afterChainLoc
        let devOpenRange = ns.range(of: "<Devices>", options: [], range: NSRange(location: afterChainLoc, length: afterChainLen))
        guard devOpenRange.location != NSNotFound else { return [] }

        var searchLoc = devOpenRange.location + devOpenRange.length
        var nestedCount = 0
        var devCloseLoc: Int?

        while searchLoc < ns.length {
            let remainRange = NSRange(location: searchLoc, length: ns.length - searchLoc)
            let nextClose = ns.range(of: "</Devices>", options: [], range: remainRange)
            guard nextClose.location != NSNotFound else { break }

            let betweenRange = NSRange(location: searchLoc, length: nextClose.location - searchLoc)
            let nextOpen = ns.range(of: "<Devices>", options: [], range: betweenRange)

            if nextOpen.location != NSNotFound {
                nestedCount += 1
                searchLoc = nextOpen.location + nextOpen.length
            } else {
                if nestedCount == 0 {
                    devCloseLoc = nextClose.location
                    break
                } else {
                    nestedCount -= 1
                    searchLoc = nextClose.location + nextClose.length
                }
            }
        }

        guard let closeLoc = devCloseLoc else { return [] }
        let devicesContent = ns.substring(with: NSRange(location: devOpenRange.location + devOpenRange.length, length: closeLoc - (devOpenRange.location + devOpenRange.length)))
        return parseDeviceElements(devicesContent)
    }

    private static func parseDeviceElements(_ devicesXml: String) -> [AbletonDevice] {
        let ns = devicesXml as NSString
        var devices: [AbletonDevice] = []
        var loc = 0
        var slotIndex = 0

        while loc < ns.length {
            let openBracket = ns.range(of: "<", options: [], range: NSRange(location: loc, length: ns.length - loc))
            guard openBracket.location != NSNotFound else { break }

            let afterOpen = openBracket.location + 1
            guard afterOpen < ns.length else { break }

            let firstChar = ns.character(at: afterOpen)
            // Skip comments (<!), closing tags (</), directives (<?)
            if firstChar == 47 /* / */ || firstChar == 33 /* ! */ || firstChar == 63 /* ? */ {
                let closeBracket = ns.range(of: ">", options: [], range: NSRange(location: afterOpen, length: ns.length - afterOpen))
                guard closeBracket.location != NSNotFound else { break }
                loc = closeBracket.location + 1
                continue
            }

            // Find end of tag name
            var nameEnd = afterOpen
            while nameEnd < ns.length {
                let c = ns.character(at: nameEnd)
                if c == 32 || c == 9 || c == 10 || c == 13 || c == 62 || c == 47 {
                    break
                }
                nameEnd += 1
            }

            let tagName = ns.substring(with: NSRange(location: afterOpen, length: nameEnd - afterOpen))
            guard !tagName.isEmpty else {
                loc = afterOpen + 1
                continue
            }

            // Find end of the opening tag '>'
            let openTagEnd = ns.range(of: ">", options: [], range: NSRange(location: nameEnd, length: ns.length - nameEnd))
            guard openTagEnd.location != NSNotFound else { break }

            // Check if self-closing: e.g. <Tag /> or <Tag/>
            let isSelfClosing = (openTagEnd.location > openBracket.location && ns.character(at: openTagEnd.location - 1) == 47 /* / */)

            if isSelfClosing {
                let tagXml = ns.substring(with: NSRange(location: openBracket.location, length: openTagEnd.location + 1 - openBracket.location))
                let dev = parseSingleDevice(tag: tagName, xml: tagXml, slotIndex: slotIndex)
                devices.append(dev)
                slotIndex += 1
                loc = openTagEnd.location + 1
                continue
            }

            // Search for matching closing tag </tagName>
            let closePattern = "</\(tagName)>"
            let openPattern = "<\(tagName)"
            var depth = 1
            var scanLoc = openTagEnd.location + 1
            var foundEndLoc: Int?

            while scanLoc < ns.length {
                let remainRange = NSRange(location: scanLoc, length: ns.length - scanLoc)
                let nextClose = ns.range(of: closePattern, options: [], range: remainRange)
                guard nextClose.location != NSNotFound else { break }

                // Check for any nested opening tags between scanLoc and nextClose.location
                var subScan = scanLoc
                while subScan < nextClose.location {
                    let betweenRange = NSRange(location: subScan, length: nextClose.location - subScan)
                    let nextOpen = ns.range(of: openPattern, options: [], range: betweenRange)
                    guard nextOpen.location != NSNotFound else { break }

                    let charAfter = nextOpen.location + openPattern.count
                    if charAfter < ns.length {
                        let c = ns.character(at: charAfter)
                        if c == 32 || c == 9 || c == 10 || c == 13 || c == 62 || c == 47 {
                            // Find tag close to check if self-closing
                            let subTagClose = ns.range(of: ">", options: [], range: NSRange(location: charAfter, length: nextClose.location - charAfter))
                            if subTagClose.location != NSNotFound {
                                let prevC = ns.character(at: subTagClose.location - 1)
                                if prevC != 47 {
                                    depth += 1
                                }
                                subScan = subTagClose.location + 1
                                continue
                            }
                        }
                    }
                    subScan = nextOpen.location + openPattern.count
                }

                depth -= 1
                if depth == 0 {
                    foundEndLoc = nextClose.location + nextClose.length
                    break
                } else {
                    scanLoc = nextClose.location + nextClose.length
                }
            }

            guard let endLoc = foundEndLoc else {
                loc = openTagEnd.location + 1
                continue
            }

            let fullDeviceXml = ns.substring(with: NSRange(location: openBracket.location, length: endLoc - openBracket.location))
            let dev = parseSingleDevice(tag: tagName, xml: fullDeviceXml, slotIndex: slotIndex)
            devices.append(dev)
            slotIndex += 1
            loc = endLoc
        }

        return devices
    }

    private static func parseSingleDevice(tag: String, xml: String, slotIndex: Int) -> AbletonDevice {
        // Optimize search range to first 32KB of device xml (names/state are always near the top, avoiding megabytes of preset blobs)
        let searchXml: String
        if xml.count > 32768 {
            searchXml = String(xml.prefix(32768))
        } else {
            searchXml = xml
        }

        let isEnabled: Bool
        if let onMatch = isOnRegex.firstMatch(in: searchXml, range: NSRange(location: 0, length: (searchXml as NSString).length)) {
            let val = (searchXml as NSString).substring(with: onMatch.range(at: 1)).lowercased()
            isEnabled = (val != "false" && val != "0")
        } else {
            isEnabled = true
        }

        let customName = extractFirstRegex(regex: userNameRegex, in: searchXml)

        if tag == "AuPluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: searchXml) ?? "Audio Unit"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: searchXml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .au,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag == "Vst3PluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: searchXml) ?? "VST3 Plugin"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: searchXml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .vst3,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag == "VstPluginDevice" {
            let name = extractFirstRegex(regex: pluginNameRegex, in: searchXml) ?? "VST Plugin"
            let vendor = extractFirstRegex(regex: pluginVendorRegex, in: searchXml)
            return AbletonDevice(
                name: customName ?? name,
                vendor: vendor,
                type: .vst2,
                isEnabled: isEnabled,
                slotIndex: slotIndex
            )
        } else if tag.starts(with: "MxDevice") {
            let name = customName ?? extractFirstRegex(regex: pluginNameRegex, in: searchXml) ?? "Max for Live"
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
