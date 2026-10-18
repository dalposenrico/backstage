import Foundation

struct AbletonLocator: Equatable, Sendable {
    let timeInBeats: Double
    let name: String
    let annotation: String
}

enum AbletonProjectInspector {
    struct Result {
        let bpm: Double?
        let plugins: [String]
        let activity: ProjectActivity
        let key: String?
        let timeSignature: String?
        let liveVersion: String?
        let tracksCount: Int?
        let samplesCount: Int?

        init(
            bpm: Double?,
            plugins: [String],
            activity: ProjectActivity,
            key: String? = nil,
            timeSignature: String? = nil,
            liveVersion: String? = nil,
            tracksCount: Int? = nil,
            samplesCount: Int? = nil
        ) {
            self.bpm = bpm
            self.plugins = plugins
            self.activity = activity
            self.key = key
            self.timeSignature = timeSignature
            self.liveVersion = liveVersion
            self.tracksCount = tracksCount
            self.samplesCount = samplesCount
        }
    }

    /// Identifies the exact set of `.als` files an inspection was derived from.
    /// Any change to a set file or backup changes the fingerprint, so a cached
    /// result is never reused for a project that has been edited since.
    static func fingerprint(projectFiles: [URL], backupFiles: [URL]) -> String? {
        guard !projectFiles.isEmpty else { return nil }
        var parts: [String] = projectFiles
            .sorted { $0.path < $1.path }
            .map { "p|\($0.path)|\(stamp($0))" }
        parts.append("n|\(backupFiles.count)")
        parts.append(contentsOf: backupFiles
            .sorted { $0.path < $1.path }
            .map { "b|\($0.path)|\(stamp($0))" })
        return parts.joined(separator: ";")
    }

    /// Reads uncached metadata on purpose: `URL.resourceValues` remembers what it
    /// fetched for a URL instance, which would make a fingerprint miss a save that
    /// happened after an earlier read in the same process.
    private static func stamp(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "0:0"
        }
        let date = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return String(format: "%.3f:%d", date, size)
    }

    static func inspect(projectFiles: [URL], backupFiles: [URL]) -> Result {
        let current = projectFiles.max { modificationDate($0) < modificationDate($1) }
        let xml = current.flatMap { Gunzip.readTextFile(at: $0) }
        let bpm = xml.flatMap(readTempo)
        let plugins = xml.map(readPlugins) ?? []
        let key = xml.flatMap(readScale)
        let timeSig = xml.flatMap(readTimeSignature)
        let version = xml.flatMap(readLiveVersion)
        let tracksCount = xml.map(countTracks)
        let samplesCount = xml.map(countSamples)
        let dates = (projectFiles + backupFiles)
            .compactMap(modificationDate)
            .sorted()

        return Result(
            bpm: bpm,
            plugins: plugins,
            activity: estimateActivity(from: dates, backupCount: backupFiles.count),
            key: key,
            timeSignature: timeSig,
            liveVersion: version,
            tracksCount: tracksCount,
            samplesCount: samplesCount
        )
    }

    private static func estimateActivity(from dates: [Date], backupCount: Int) -> ProjectActivity {
        guard !dates.isEmpty else { return ProjectActivity(backupCount: backupCount) }

        let sessionGap: TimeInterval = 2 * 60 * 60
        let minimumSession: TimeInterval = 15 * 60
        var sessionCount = 1
        var estimated = minimumSession

        for (previous, next) in zip(dates, dates.dropFirst()) {
            let gap = next.timeIntervalSince(previous)
            if gap > 0, gap <= sessionGap {
                estimated += gap
            } else if gap > sessionGap {
                sessionCount += 1
                estimated += minimumSession
            }
        }

        return ProjectActivity(
            backupCount: backupCount,
            sessionCount: sessionCount,
            estimatedWorkTime: estimated,
            firstSave: dates.first,
            latestSave: dates.last
        )
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private static func readTempo(in xml: String) -> Double? {
        let patterns = [
            #"<Tempo[\s\S]*?<Manual\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#,
            #"<CurrentSongTempo\s+Value=\"([0-9]+(?:\.[0-9]+)?)\""#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
                  let range = Range(match.range(at: 1), in: xml),
                  let value = Double(xml[range]), value > 0 else { continue }
            return value
        }
        return nil
    }

    static func readLocators(from url: URL) -> [AbletonLocator] {
        guard let xml = Gunzip.readTextFile(at: url) else { return [] }
        return parseLocators(in: xml)
    }

    static func parseLocators(in xml: String) -> [AbletonLocator] {
        guard let blockRegex = try? NSRegularExpression(
            pattern: #"<Locator(?:\s+[^>]*)?>[\s\S]*?</Locator>"#
        ) else { return [] }

        return blockRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            guard let range = Range(match.range, in: xml) else { return nil }
            let block = String(xml[range])
            guard let timeText = attribute(named: "Time", in: block),
                  let time = Double(timeText), time >= 0 else { return nil }
            let rawName = attribute(named: "Name", in: block) ?? ""
            let name = decodeXMLEntities(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
            let annotation = decodeXMLEntities(attribute(named: "Annotation", in: block) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return AbletonLocator(
                timeInBeats: time,
                name: name.isEmpty ? "Ableton marker" : name,
                annotation: annotation
            )
        }
        .sorted { $0.timeInBeats < $1.timeInBeats }
    }

    private static func attribute(named element: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<"# + NSRegularExpression.escapedPattern(for: element) + #"\s+Value=\"([^\"]*)\""#
        ),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Reads third-party plug-in display names from Ableton's gzipped XML.
    /// Native Ableton devices are deliberately excluded: this section is meant to
    /// answer "which external plug-ins did I use?" at a glance.
    private static func readPlugins(in xml: String) -> [String] {
        let blockPatterns = [
            #"<VstPluginInfo[\s\S]*?</VstPluginInfo>"#,
            #"<Vst3PluginInfo[\s\S]*?</Vst3PluginInfo>"#,
            #"<AuPluginInfo[\s\S]*?</AuPluginInfo>"#
        ]
        let namePatterns = [
            #"<PlugName\s+Value=\"([^\"]+)\""#,
            #"<Name\s+Value=\"([^\"]+)\""#,
            #"<ProductName\s+Value=\"([^\"]+)\""#
        ]
        var names = Set<String>()

        for blockPattern in blockPatterns {
            guard let blockRegex = try? NSRegularExpression(pattern: blockPattern) else { continue }
            let matches = blockRegex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                guard let blockRange = Range(match.range, in: xml) else { continue }
                let block = String(xml[blockRange])
                for namePattern in namePatterns {
                    guard let nameRegex = try? NSRegularExpression(pattern: namePattern),
                          let nameMatch = nameRegex.firstMatch(
                            in: block,
                            range: NSRange(block.startIndex..., in: block)
                          ),
                          let nameRange = Range(nameMatch.range(at: 1), in: block) else { continue }
                    let name = decodeXMLEntities(String(block[nameRange])).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { names.insert(name) }
                    break
                }
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func readLiveVersion(in xml: String) -> String? {
        if let match = xml.range(of: #"Creator=\"Ableton Live\s+([0-9\.]+)\""#, options: .regularExpression) {
            let matchedStr = String(xml[match])
            if let numMatch = matchedStr.range(of: #"([0-9\.]+)"#, options: .regularExpression) {
                return String(matchedStr[numMatch])
            }
        }
        if let match = xml.range(of: #"MinorVersion=\"([0-9]+)\."#, options: .regularExpression) {
            let matchedStr = String(xml[match])
            if let num = matchedStr.range(of: #"[0-9]+"#, options: .regularExpression) {
                return "\(matchedStr[num]).0"
            }
        }
        return nil
    }

    private static func readTimeSignature(in xml: String) -> String? {
        let numPattern = #"<TimeSignature>[\s\S]*?<Numerator\s+Value=\"([0-9]+)\""#
        let denomPattern = #"<TimeSignature>[\s\S]*?<Denominator\s+Value=\"([0-9]+)\""#
        var num = 4
        var denom = 4
        if let match = xml.range(of: numPattern, options: .regularExpression) {
            let slice = String(xml[match])
            if let val = slice.components(separatedBy: "Value=\"").last?.components(separatedBy: "\"").first, let n = Int(val) {
                num = n
            }
        }
        if let match = xml.range(of: denomPattern, options: .regularExpression) {
            let slice = String(xml[match])
            if let val = slice.components(separatedBy: "Value=\"").last?.components(separatedBy: "\"").first, let d = Int(val) {
                denom = d
            }
        }
        return "\(num)/\(denom)"
    }

    private static func readScale(in xml: String) -> String? {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        if let scaleRange = xml.range(of: "<ScaleInformation>") ?? xml.range(of: "<Scale>") {
            let endIdx = xml.index(scaleRange.lowerBound, offsetBy: min(600, xml.distance(from: scaleRange.lowerBound, to: xml.endIndex)))
            let slice = String(xml[scaleRange.lowerBound..<endIdx])

            var rootIdx: Int? = nil
            if let rootMatch = slice.range(of: #"RootNote\s+Value=\"([0-9]+)\""#, options: .regularExpression) {
                let str = String(slice[rootMatch])
                if let val = str.components(separatedBy: "Value=\"").last?.components(separatedBy: "\"").first, let idx = Int(val), idx >= 0 && idx < 12 {
                    rootIdx = idx
                }
            }

            var scaleName = "Major"
            if let nameMatch = slice.range(of: #"Name\s+Value=\"([^\"]+)\""#, options: .regularExpression) {
                let str = String(slice[nameMatch])
                if let val = str.components(separatedBy: "Value=\"").last?.components(separatedBy: "\"").first {
                    scaleName = val
                }
            }

            if let r = rootIdx {
                let isMinor = scaleName.lowercased().contains("minor")
                let note = noteNames[r]
                let mode = isMinor ? "minor" : "major"
                let isDefault = (r == 0 && !isMinor)
                return isDefault ? "\(note) \(mode) *" : "\(note) \(mode)"
            }
        }
        return "C major *"
    }

    private static func countOccurrences(of substring: String, in string: String) -> Int {
        var count = 0
        var searchRange = string.startIndex..<string.endIndex
        while let range = string.range(of: substring, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<string.endIndex
        }
        return count
    }

    private static func countTracks(in xml: String) -> Int {
        let midi = countOccurrences(of: "<MidiTrack ", in: xml)
        let audio = countOccurrences(of: "<AudioTrack ", in: xml)
        let group = countOccurrences(of: "<GroupTrack ", in: xml)
        return midi + audio + group
    }

    private static func countSamples(in xml: String) -> Int {
        return countOccurrences(of: "<SampleRef>", in: xml)
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

enum Gunzip {
    private typealias GZFile = UnsafeMutableRawPointer

    @_silgen_name("gzopen") private static func gzopen(
        _ path: UnsafePointer<CChar>, _ mode: UnsafePointer<CChar>
    ) -> GZFile?
    @_silgen_name("gzread") private static func gzread(
        _ file: GZFile, _ buffer: UnsafeMutableRawPointer, _ length: UInt32
    ) -> Int32
    @_silgen_name("gzwrite") private static func gzwrite(
        _ file: GZFile, _ buffer: UnsafeRawPointer, _ length: UInt32
    ) -> Int32
    @_silgen_name("gzclose") private static func gzclose(_ file: GZFile) -> Int32

    static func readTextFile(at url: URL) -> String? {
        let file = url.path.withCString { path in
            "rb".withCString { mode in gzopen(path, mode) }
        }
        guard let file else { return nil }
        defer { _ = gzclose(file) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                gzread(file, bytes.baseAddress!, UInt32(bytes.count))
            }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: Int(count))
        }
        return String(data: data, encoding: .utf8)
    }

    static func writeTextFile(_ text: String, to url: URL) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        let file = url.path.withCString { path in
            "wb".withCString { mode in gzopen(path, mode) }
        }
        guard let file else { return false }
        defer { _ = gzclose(file) }

        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return true }
            let bytesWritten = gzwrite(file, base, UInt32(rawBuffer.count))
            return bytesWritten == Int32(rawBuffer.count)
        }
    }
}
