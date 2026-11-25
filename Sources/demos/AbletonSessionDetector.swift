import AppKit
import CoreGraphics
import Foundation

struct AbletonSessionSnapshot: Equatable, Sendable {
    let isRunning: Bool
    let windowTitles: [String]
    let loadedDocumentURLs: [URL]
}

enum AbletonSessionDetector {
    /// Returns the active or preferred running Ableton Live application, if any.
    static func runningAbletonApp(preferredAppURL: URL? = AbletonAppDetector.selectedAppURL()) -> NSRunningApplication? {
        let runningApplications = NSWorkspace.shared.runningApplications
        if let preferred = preferredAppURL {
            let preferredPath = preferred.standardizedFileURL.path
            return runningApplications.first(where: {
                $0.bundleURL?.standardizedFileURL.path == preferredPath
            })
        }
        return runningApplications.first { application in
            application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                || application.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
                || (application.localizedName?.localizedCaseInsensitiveContains("Live") == true && application.bundleIdentifier?.lowercased().contains("ableton") == true)
        }
    }

    static func snapshot(preferredAppURL: URL? = AbletonAppDetector.selectedAppURL()) -> AbletonSessionSnapshot {
        let runningApplications = NSWorkspace.shared.runningApplications
        let abletonApplications: [NSRunningApplication]

        if let preferred = preferredAppURL {
            let preferredPath = preferred.standardizedFileURL.path
            abletonApplications = runningApplications.filter {
                $0.bundleURL?.standardizedFileURL.path == preferredPath
            }
        } else {
            abletonApplications = runningApplications.filter { application in
                application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                    || application.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
            }
        }

        guard !abletonApplications.isEmpty else {
            return AbletonSessionSnapshot(isRunning: false, windowTitles: [], loadedDocumentURLs: [])
        }

        let processIDs = Set(abletonApplications.map(\.processIdentifier))
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[CFString: Any]] ?? []
        let titles = windowInfo.compactMap { window -> String? in
            guard let processID = window[kCGWindowOwnerPID] as? Int,
                  processIDs.contains(pid_t(processID)),
                  let title = window[kCGWindowName] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return title
        }
        let launchDate = abletonApplications.compactMap(\.launchDate).max() ?? .distantPast
        // Plug-in windows can have readable titles while Live's main set window is
        // hidden by macOS privacy protections. Always keep the local log fallback.
        let loadedDocuments = recentlyLoadedDocuments(since: launchDate, preferredAppURL: preferredAppURL)
        return AbletonSessionSnapshot(
            isRunning: true,
            windowTitles: titles,
            loadedDocumentURLs: loadedDocuments
        )
    }

    /// Brings the running Ableton Live application to the front and gives it focus,
    /// or launches the preferred Ableton Live application if configured and not yet open.
    @discardableResult
    static func activateAbleton(preferredAppURL: URL? = AbletonAppDetector.selectedAppURL()) -> Bool {
        let runningApplications = NSWorkspace.shared.runningApplications

        if let preferred = preferredAppURL {
            let preferredPath = preferred.standardizedFileURL.path
            if let runningPreferred = runningApplications.first(where: {
                $0.bundleURL?.standardizedFileURL.path == preferredPath
            }) {
                if let bundleURL = runningPreferred.bundleURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
                }
                if #available(macOS 14.0, *) {
                    return runningPreferred.activate()
                } else {
                    return runningPreferred.activate(options: [.activateIgnoringOtherApps])
                }
            } else {
                // Preferred Live is not running; cannot activate it
                return false
            }
        }

        guard let ableton = runningApplications.first(where: { application in
            application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                || application.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
        }) else {
            return false
        }

        if let bundleURL = ableton.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
        }

        if #available(macOS 14.0, *) {
            return ableton.activate()
        } else {
            return ableton.activate(options: [.activateIgnoringOtherApps])
        }
    }

    static func matchingProject(in projects: [Project], loadedDocumentURLs: [URL]) -> Project? {
        guard let documentURL = loadedDocumentURLs.first else { return nil }
        let documentPath = documentURL.standardizedFileURL.path
        if let exact = projects.first(where: { project in
            project.versions.contains { $0.url.standardizedFileURL.path == documentPath }
        }) {
            return exact
        }
        if let containing = projects
            .filter({ documentPath.hasPrefix($0.folderURL.standardizedFileURL.path + "/") })
            .max(by: { $0.folderURL.path.count < $1.folderURL.path.count }) {
            return containing
        }

        // Live may reopen a recovered or Save As set from its private BaseFiles
        // directory. The copied filename still contains the real version name,
        // commonly with a recovery suffix such as "-1".
        if documentPath.localizedCaseInsensitiveContains("/Library/Preferences/Ableton/")
            && documentPath.localizedCaseInsensitiveContains("/BaseFiles/") {
            return matchingProject(
                in: projects,
                windowTitles: [documentURL.deletingPathExtension().lastPathComponent]
            )
        }

        // Match by containing project folder name (handles parent directory renames/moves)
        let parentFolder = documentURL.deletingLastPathComponent().lastPathComponent
        if !parentFolder.isEmpty, let matchByFolder = projects.first(where: {
            $0.folderURL.lastPathComponent.localizedCaseInsensitiveCompare(parentFolder) == .orderedSame
        }) {
            return matchByFolder
        }

        // Match by exact .als version filename
        let alsFilename = documentURL.lastPathComponent
        if !alsFilename.isEmpty, let matchByVersion = projects.first(where: { project in
            project.versions.contains { $0.url.lastPathComponent.localizedCaseInsensitiveCompare(alsFilename) == .orderedSame }
        }) {
            return matchByVersion
        }

        // Title/fuzzy match by document base name
        let baseName = documentURL.deletingPathExtension().lastPathComponent
        if !baseName.isEmpty, let matchByName = matchingProject(in: projects, windowTitles: [baseName]) {
            return matchByName
        }

        return nil
    }

    static func matchingProject(in projects: [Project], windowTitles: [String]) -> Project? {
        let normalizedTitles = windowTitles.map(normalize).filter { !$0.isEmpty }
        guard !normalizedTitles.isEmpty else { return nil }

        var matches: [(project: Project, score: Int)] = []
        for project in projects {
            var bestScore = 0
            let versionNames = project.versions.map { normalize($0.displayName) }
            for title in normalizedTitles {
                for versionName in versionNames where versionName.count >= 4 && containsPhrase(title, versionName) {
                    bestScore = max(bestScore, 1_000 + versionName.count)
                }

                let projectName = normalize(project.name)
                if projectName.count >= 6 && containsPhrase(title, projectName) {
                    bestScore = max(bestScore, 100 + projectName.count)
                }
            }
            if bestScore > 0 { matches.append((project, bestScore)) }
        }

        guard let highestScore = matches.map(\.score).max() else { return nil }
        let strongest = matches.filter { $0.score == highestScore }
        guard strongest.count == 1 else { return nil }
        return strongest[0].project
    }

    static func projectFolder(forDocumentURL documentURL: URL) -> URL? {
        let standardized = documentURL.standardizedFileURL
        var folder = standardized.deletingLastPathComponent()
        let folderName = folder.lastPathComponent.lowercased()
        if folderName == "backup" || folderName == "backups" {
            folder = folder.deletingLastPathComponent()
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
            return folder
        }
        return nil
    }

    static func activeProject(
        in projects: [Project],
        windowTitles: [String],
        loadedDocumentURLs: [URL]
    ) -> Project? {
        matchingProject(in: projects, windowTitles: windowTitles)
            ?? matchingProject(in: projects, loadedDocumentURLs: loadedDocumentURLs)
    }

    private static func containsPhrase(_ text: String, _ phrase: String) -> Bool {
        text == phrase || text.hasPrefix(phrase + " ") || text.hasSuffix(" " + phrase)
            || text.contains(" " + phrase + " ")
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let formatterLock = NSLock()
    private static let sharedISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let sharedLocalFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return f
    }()

    private static let logCacheLock = NSLock()
    private static var cachedLogKey: LogCacheKey?
    private static var cachedLogDocuments: [URL] = []

    private struct LogCacheKey: Equatable {
        let path: String
        let fileSize: UInt64
        let modificationTime: TimeInterval
        let launchTime: TimeInterval
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return sharedLocalFormatter.date(from: value) ?? sharedISOFormatter.date(from: value)
    }

    /// Zero-allocation UTF-8 pre-filter: skips lines that cannot possibly reference a quoted `.als` path.
    private static func lineMightContainQuotedALS(_ utf8: Substring.UTF8View) -> Bool {
        guard utf8.count >= 6 else { return false }
        var state = 0 // 0=none, 1='.', 2='a', 3='l', 4='s'
        for byte in utf8 {
            switch state {
            case 0:
                if byte == 0x2E { state = 1 } // '.'
            case 1:
                if byte == 0x61 || byte == 0x41 { state = 2 } // 'a'/'A'
                else if byte == 0x2E { state = 1 }
                else { state = 0 }
            case 2:
                if byte == 0x6C || byte == 0x4C { state = 3 } // 'l'/'L'
                else if byte == 0x2E { state = 1 }
                else { state = 0 }
            case 3:
                if byte == 0x73 || byte == 0x53 { state = 4 } // 's'/'S'
                else if byte == 0x2E { state = 1 }
                else { state = 0 }
            case 4:
                if byte == 0x22 { return true } // '"'
                if byte == 0x2E { state = 1 }
                else { state = 0 }
            default:
                state = 0
            }
        }
        return false
    }

    private static func earliestTimestamp(in logText: String) -> Date? {
        var inspected = 0
        for rawLine in logText.split(separator: "\n", omittingEmptySubsequences: true) {
            inspected += 1
            if inspected > 25 { break }
            let trimmed = rawLine.drop(while: { $0 == " " || $0 == "\t" })
            guard !trimmed.isEmpty else { continue }
            let candidate: String
            if let colonSpace = trimmed.range(of: ": ") {
                candidate = String(trimmed[..<colonSpace.lowerBound])
            } else if let space = trimmed.firstIndex(of: " ") {
                candidate = String(trimmed[..<space])
            } else {
                continue
            }
            if let parsed = parseTimestamp(candidate) {
                return parsed
            }
        }
        return nil
    }

    static func loadedDocuments(in logText: String, since launchDate: Date) -> [URL] {
        let markers = [
            ": info: Loading document \"",
            ": info: Saving document \"",
            ": info: Document \"",
            "Loading document \"",
            "Saving document \"",
            "Loaded document: \"",
            "LoadDocument: \"",
            "Document: \""
        ]

        return logText.split(separator: "\n", omittingEmptySubsequences: true).reversed().compactMap { rawLine in
            guard lineMightContainQuotedALS(rawLine.utf8) else { return nil }
            let line = String(rawLine)
            var matchedMarkerRange: Range<String.Index>?
            for marker in markers {
                if let range = line.range(of: marker) {
                    matchedMarkerRange = range
                    break
                }
            }
            guard let markerRange = matchedMarkerRange else { return nil }
            let prefix = String(line[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let datePart = prefix.components(separatedBy: ": ").first?.trimmingCharacters(in: .whitespaces) ?? prefix
            let timestamp = parseTimestamp(datePart) ?? parseTimestamp(prefix)
            if let timestamp, timestamp < launchDate { return nil }
            let pathStart = markerRange.upperBound
            guard let closingQuote = line[pathStart...].firstIndex(of: "\"") else { return nil }
            let path = String(line[pathStart..<closingQuote])
            let normalizedPath = path.lowercased()
            guard normalizedPath.hasSuffix(".als"),
                  !normalizedPath.contains("/user library/defaults/creating tracks/") else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    private static func recentlyLoadedDocuments(since launchDate: Date, preferredAppURL: URL? = AbletonAppDetector.selectedAppURL()) -> [URL] {
        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton", isDirectory: true)
        guard let versionFolders = try? FileManager.default.contentsOfDirectory(
            at: preferencesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var logURLs = versionFolders.compactMap { folder -> URL? in
            guard folder.lastPathComponent.hasPrefix("Live ") else { return nil }
            let logURL = folder.appendingPathComponent("Log.txt")
            return FileManager.default.fileExists(atPath: logURL.path) ? logURL : nil
        }
        guard !logURLs.isEmpty else { return [] }

        // If a preferred Live app is configured, prioritize log files from its matching version folder
        if let preferred = preferredAppURL, let appInfo = AbletonAppDetector.appInfo(for: preferred) {
            if let prefix = appInfo.majorVersionPrefix {
                let matching = logURLs.filter { $0.deletingLastPathComponent().lastPathComponent.hasPrefix(prefix) }
                if !matching.isEmpty {
                    logURLs = matching
                }
            }
        }

        guard let newestLog = logURLs.max(by: {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }) else { return [] }

        let effectiveLaunchDate = launchDate == .distantPast ? .distantPast : launchDate.addingTimeInterval(-60)
        let values = try? newestLog.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = UInt64(max(0, values?.fileSize ?? 0))
        let modTime = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let cacheKey = LogCacheKey(
            path: newestLog.path,
            fileSize: fileSize,
            modificationTime: modTime,
            launchTime: effectiveLaunchDate.timeIntervalSinceReferenceDate
        )

        logCacheLock.lock()
        if cachedLogKey == cacheKey {
            let cached = cachedLogDocuments
            logCacheLock.unlock()
            return cached
        }
        logCacheLock.unlock()

        guard let handle = try? FileHandle(forReadingFrom: newestLog) else { return [] }
        defer { try? handle.close() }

        let actualFileSize = (try? handle.seekToEnd()) ?? fileSize

        // Live logs can grow large when running for many hours. Inspect progressively larger chunks
        // from the end of Log.txt (1 MB -> 4 MB -> 16 MB -> full file) until loaded documents are found
        // or the chunk already reaches entries written before Ableton launched.
        let chunkSizes: [UInt64] = [1_048_576, 4_194_304, 16_777_216, actualFileSize]
        var resolvedDocs: [URL] = []
        for chunkSize in chunkSizes {
            let bytesToRead = min(actualFileSize, chunkSize)
            try? handle.seek(toOffset: actualFileSize - bytesToRead)
            guard let data = try? handle.readToEnd() else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let docs = loadedDocuments(in: text, since: effectiveLaunchDate)
            if !docs.isEmpty {
                resolvedDocs = docs
                break
            }
            if bytesToRead >= actualFileSize {
                break
            }
            if effectiveLaunchDate != .distantPast,
               let earliest = earliestTimestamp(in: text),
               earliest < effectiveLaunchDate {
                break
            }
        }

        logCacheLock.lock()
        cachedLogKey = cacheKey
        cachedLogDocuments = resolvedDocs
        logCacheLock.unlock()

        return resolvedDocs
    }
}
