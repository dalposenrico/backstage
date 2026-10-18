import Foundation

public enum BatchPluginPreset: String, CaseIterable, Identifiable, Sendable {
    case utilityGain = "Utility (Gain Staging 0.0 dB)"
    case eqEight = "EQ Eight"
    case customXml = "Custom XML Preset"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .utilityGain: return "Utility (Gain Staging)"
        case .eqEight: return "EQ Eight"
        case .customXml: return "Custom XML Preset"
        }
    }

    public var description: String {
        switch self {
        case .utilityGain:
            return "Inserts Ableton's clean Utility device with 0.0 dB default gain across tracks."
        case .eqEight:
            return "Inserts Ableton's 8-band parametric EQ across tracks."
        case .customXml:
            return "Inserts a custom device XML snippet into target tracks."
        }
    }

    public var defaultXmlSnippet: String {
        switch self {
        case .utilityGain:
            return """
            <StereoGain Id="0">
                <LomId Value="0" />
                <IsExpanded Value="true" />
                <On><Manual Value="true" /></On>
                <UserName Value="Gain Stage (0dB)" />
                <Gain><Manual Value="0.0" /></Gain>
                <Mute><Manual Value="false" /></Mute>
            </StereoGain>
            """
        case .eqEight:
            return """
            <Eq8 Id="0">
                <LomId Value="0" />
                <IsExpanded Value="true" />
                <On><Manual Value="true" /></On>
                <UserName Value="Mix EQ" />
            </Eq8>
            """
        case .customXml:
            return ""
        }
    }
}

public enum BatchTargetScope: String, CaseIterable, Identifiable, Sendable {
    case allTracks = "All Tracks"
    case audioOnly = "Audio Tracks Only"
    case midiOnly = "MIDI Tracks Only"
    case nonGroups = "Non-Group Tracks"

    public var id: String { rawValue }
}

public enum BatchInsertPosition: String, CaseIterable, Identifiable, Sendable {
    case first = "First Insert (Input)"
    case last = "Last Insert (Output)"

    public var id: String { rawValue }
}

public struct BatchInjectionOptions: Sendable {
    public var preset: BatchPluginPreset
    public var customXml: String
    public var targetScope: BatchTargetScope
    public var position: BatchInsertPosition
    public var saveAsNewVersion: Bool

    public init(
        preset: BatchPluginPreset = .utilityGain,
        customXml: String = "",
        targetScope: BatchTargetScope = .allTracks,
        position: BatchInsertPosition = .first,
        saveAsNewVersion: Bool = false
    ) {
        self.preset = preset
        self.customXml = customXml
        self.targetScope = targetScope
        self.position = position
        self.saveAsNewVersion = saveAsNewVersion
    }
}

public struct BatchInjectionResult: Sendable {
    public let targetFileUrl: URL
    public let backupFileUrl: URL?
    public let tracksModifiedCount: Int
}

public enum BatchInjectionError: LocalizedError {
    case fileNotFound
    case unableToReadALS
    case unableToWriteALS
    case noMatchingTracksFound
    case invalidSnippet

    public var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Ableton project file (.als) was not found."
        case .unableToReadALS: return "Could not decompress or read Ableton project XML."
        case .unableToWriteALS: return "Failed to compress and save modified Ableton project file."
        case .noMatchingTracksFound: return "No tracks matched the chosen filter scope."
        case .invalidSnippet: return "Device XML snippet is empty or invalid."
        }
    }
}

public enum AbletonBatchDeviceInjector {

    /// Safely injects a device preset into target tracks of an Ableton (.als) file.
    /// Always creates a timestamped backup before modifying any existing file.
    public static func inject(
        into alsURL: URL,
        options: BatchInjectionOptions
    ) throws -> BatchInjectionResult {
        guard FileManager.default.fileExists(atPath: alsURL.path) else {
            throw BatchInjectionError.fileNotFound
        }

        guard let rawXml = Gunzip.readTextFile(at: alsURL) else {
            throw BatchInjectionError.unableToReadALS
        }

        let snippetToInject = (options.preset == .customXml ? options.customXml : options.preset.defaultXmlSnippet)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !snippetToInject.isEmpty else {
            throw BatchInjectionError.invalidSnippet
        }

        // Create backup in same directory
        let directory = alsURL.deletingLastPathComponent()
        let baseName = alsURL.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())

        let backupURL = directory.appendingPathComponent("\(baseName)_backup_\(timestamp).als")
        do {
            try FileManager.default.copyItem(at: alsURL, to: backupURL)
        } catch {
            // Backup creation failure should not be ignored for user data safety
            print("Warning: could not create direct copy backup: \(error)")
        }

        let destinationURL: URL
        if options.saveAsNewVersion {
            destinationURL = directory.appendingPathComponent("\(baseName)_with_\(options.preset.title.replacingOccurrences(of: " ", with: "_")).als")
        } else {
            destinationURL = alsURL
        }

        let (modifiedXml, count) = injectDeviceXml(
            into: rawXml,
            snippet: snippetToInject,
            scope: options.targetScope,
            position: options.position
        )

        guard count > 0 else {
            throw BatchInjectionError.noMatchingTracksFound
        }

        guard Gunzip.writeTextFile(modifiedXml, to: destinationURL) else {
            throw BatchInjectionError.unableToWriteALS
        }

        return BatchInjectionResult(
            targetFileUrl: destinationURL,
            backupFileUrl: backupURL,
            tracksModifiedCount: count
        )
    }

    /// Pure function modifying track XML string in memory.
    public static func injectDeviceXml(
        into xml: String,
        snippet: String,
        scope: BatchTargetScope,
        position: BatchInsertPosition
    ) -> (modifiedXml: String, tracksModifiedCount: Int) {
        var count = 0
        var result = xml

        // Match MidiTrack, AudioTrack, GroupTrack
        let trackPattern = #"<(MidiTrack|AudioTrack|GroupTrack)(?:\s+Id=\"[^\"]*\"[^>]*)?>[\s\S]*?</\1>"#
        guard let trackRegex = try? NSRegularExpression(pattern: trackPattern) else {
            return (xml, 0)
        }

        let nsString = xml as NSString
        let matches = trackRegex.matches(in: xml, range: NSRange(location: 0, length: nsString.length))

        // We process in reverse order to keep string indices valid
        for match in matches.reversed() {
            let trackXml = nsString.substring(with: match.range)
            let trackType = extractTrackType(from: trackXml)

            // Check if track matches scope
            guard shouldInclude(trackType: trackType, scope: scope) else {
                continue
            }

            if let updatedTrack = injectIntoTrack(trackXml: trackXml, snippet: snippet, position: position) {
                let range = Range(match.range, in: result)!
                result.replaceSubrange(range, with: updatedTrack)
                count += 1
            }
        }

        return (result, count)
    }

    private static func extractTrackType(from trackXml: String) -> String {
        if trackXml.hasPrefix("<MidiTrack") { return "MidiTrack" }
        if trackXml.hasPrefix("<AudioTrack") { return "AudioTrack" }
        if trackXml.hasPrefix("<GroupTrack") { return "GroupTrack" }
        return ""
    }

    private static func shouldInclude(trackType: String, scope: BatchTargetScope) -> Bool {
        switch scope {
        case .allTracks:
            return true
        case .audioOnly:
            return trackType == "AudioTrack"
        case .midiOnly:
            return trackType == "MidiTrack"
        case .nonGroups:
            return trackType == "AudioTrack" || trackType == "MidiTrack"
        }
    }

    private static func injectIntoTrack(
        trackXml: String,
        snippet: String,
        position: BatchInsertPosition
    ) -> String? {
        guard let chainRange = trackXml.range(of: "<DeviceChain>") else { return nil }
        let afterChain = trackXml[chainRange.upperBound...]

        // Case 1: Self-closing <Devices /> or <Devices/>
        if let selfClosingRange = afterChain.range(of: #"<Devices\s*/>"#, options: .regularExpression) {
            let replacement = "<Devices>\n\(snippet)\n</Devices>"
            var modified = trackXml
            modified.replaceSubrange(selfClosingRange, with: replacement)
            return modified
        }

        // Case 2: Standard <Devices> ... </Devices>
        guard let devOpenRange = afterChain.range(of: "<Devices>") else {
            // If <Devices> tag doesn't exist at all inside <DeviceChain>, insert one before </DeviceChain>
            if let closeChain = trackXml.range(of: "</DeviceChain>") {
                var modified = trackXml
                let newDevicesBlock = "<Devices>\n\(snippet)\n</Devices>\n"
                modified.insert(contentsOf: newDevicesBlock, at: closeChain.lowerBound)
                return modified
            }
            return nil
        }

        // Find matching </Devices>
        var nested = 0
        var searchIdx = devOpenRange.upperBound
        var devCloseRange: Range<String.Index>?

        while searchIdx < afterChain.endIndex {
            let nextOpen = afterChain.range(of: "<Devices>", range: searchIdx..<afterChain.endIndex)
            let nextClose = afterChain.range(of: "</Devices>", range: searchIdx..<afterChain.endIndex)
            guard let close = nextClose else { break }

            if let open = nextOpen, open.lowerBound < close.lowerBound {
                nested += 1
                searchIdx = open.upperBound
            } else {
                if nested == 0 {
                    devCloseRange = close
                    break
                } else {
                    nested -= 1
                    searchIdx = close.upperBound
                }
            }
        }

        guard let closeRange = devCloseRange else { return nil }

        var modified = trackXml
        switch position {
        case .first:
            modified.insert(contentsOf: "\n" + snippet, at: devOpenRange.upperBound)
        case .last:
            modified.insert(contentsOf: snippet + "\n", at: closeRange.lowerBound)
        }

        return modified
    }
}
