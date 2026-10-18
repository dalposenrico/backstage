import AppKit
import CoreGraphics
import Foundation

struct AbletonSessionSnapshot: Equatable {
    let isRunning: Bool
    let windowTitles: [String]
    let loadedDocumentURLs: [URL]
}

enum AbletonSessionDetector {
    static func snapshot() -> AbletonSessionSnapshot {
        let runningApplications = NSWorkspace.shared.runningApplications
        let abletonApplications = runningApplications.filter { application in
            application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                || application.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
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
        let loadedDocuments = recentlyLoadedDocuments(since: launchDate)
        return AbletonSessionSnapshot(
            isRunning: true,
            windowTitles: titles,
            loadedDocumentURLs: loadedDocuments
        )
    }

    /// Brings the running Ableton Live application to the front and gives it focus,
    /// without reopening or reloading any set documents.
    @discardableResult
    static func activateAbleton() -> Bool {
        let runningApplications = NSWorkspace.shared.runningApplications
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

    private static func recentlyLoadedDocuments(since launchDate: Date) -> [URL] {
        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton", isDirectory: true)
        guard let versionFolders = try? FileManager.default.contentsOfDirectory(
            at: preferencesURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let logURLs = versionFolders.compactMap { folder -> URL? in
            guard folder.lastPathComponent.hasPrefix("Live ") else { return nil }
            let logURL = folder.appendingPathComponent("Log.txt")
            return FileManager.default.fileExists(atPath: logURL.path) ? logURL : nil
        }
        guard let newestLog = logURLs.max(by: {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }), let handle = try? FileHandle(forReadingFrom: newestLog) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let bytesToRead: UInt64 = min(fileSize, 1_048_576)
        try? handle.seek(toOffset: fileSize - bytesToRead)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }
        return loadedDocuments(in: text, since: launchDate)
    }
}
