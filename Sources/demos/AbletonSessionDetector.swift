import AppKit
import CoreGraphics
import Foundation

struct AbletonSessionSnapshot: Equatable {
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
            if let exact = runningApplications.first(where: {
                $0.bundleURL?.standardizedFileURL.path == preferredPath
            }) {
                return exact
            }
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
            let matching = runningApplications.filter {
                $0.bundleURL?.standardizedFileURL.path == preferredPath
            }
            if !matching.isEmpty {
                abletonApplications = matching
            } else {
                abletonApplications = runningApplications.filter { application in
                    application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                        || application.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
                }
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
            } else if FileManager.default.fileExists(atPath: preferred.path) {
                // Preferred Live is not running; launch it
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: preferred, configuration: config, completionHandler: nil)
                return true
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

    static func loadedDocuments(in logText: String, since launchDate: Date) -> [URL] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = .current
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        let marker = ": info: Loading document \""

        return logText.split(separator: "\n", omittingEmptySubsequences: true).reversed().compactMap { rawLine in
            let line = String(rawLine)
            guard let markerRange = line.range(of: marker),
                  let timestamp = isoFormatter.date(from: String(line[..<markerRange.lowerBound]))
                    ?? localFormatter.date(from: String(line[..<markerRange.lowerBound])),
                  timestamp >= launchDate else { return nil }
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
        }), let handle = try? FileHandle(forReadingFrom: newestLog) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let effectiveLaunchDate = launchDate == .distantPast ? .distantPast : launchDate.addingTimeInterval(-60)

        // Live logs can grow large when running for many hours. Inspect progressively larger chunks
        // from the end of Log.txt (1 MB -> 4 MB -> 16 MB -> full file) until loaded documents are found.
        let chunkSizes: [UInt64] = [1_048_576, 4_194_304, 16_777_216, fileSize]
        for chunkSize in chunkSizes {
            let bytesToRead = min(fileSize, chunkSize)
            try? handle.seek(toOffset: fileSize - bytesToRead)
            guard let data = try? handle.readToEnd() else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let docs = loadedDocuments(in: text, since: effectiveLaunchDate)
            if !docs.isEmpty {
                return docs
            }
            if bytesToRead >= fileSize {
                break
            }
        }
        return []
    }
}
