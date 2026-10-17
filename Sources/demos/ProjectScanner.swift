import Foundation

struct ProjectScanProgress: Equatable, Sendable {
    let currentFolder: String
    let foldersScanned: Int
    let projectsFound: Int
    let totalFolders: Int?

    init(
        currentFolder: String,
        foldersScanned: Int,
        projectsFound: Int,
        totalFolders: Int? = nil
    ) {
        self.currentFolder = currentFolder
        self.foldersScanned = foldersScanned
        self.projectsFound = projectsFound
        self.totalFolders = totalFolders
    }

    var fractionComplete: Double? {
        guard let totalFolders, totalFolders > 0 else { return nil }
        return min(max(Double(foldersScanned) / Double(totalFolders), 0), 1)
    }
}

enum ProjectScanner {
    static let audioExtensions: Set<String> = [
        "mp3", "wav", "aiff", "aif", "m4a", "flac", "ogg", "caf", "opus", "alac", "aac"
    ]

    private static let trackKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .contentModificationDateKey, .creationDateKey
    ]

    private static let exportFolderNames: Set<String> = [
        "version", "versions", "export", "exports", "bounce", "bounces",
        "mix", "mixes", "master", "masters", "render", "renders", "demo", "demos"
    ]

    private static let ignoredAudioFolderNames: Set<String> = [
        "samples", "recorded", "processed", "freeze", "backup", "ableton project info"
    ]

    static func scan(
        root: URL,
        cache: ProjectInspectionCache? = nil,
        progress: @escaping @Sendable (ProjectScanProgress) -> Void = { _ in }
    ) async -> [FolderNode] {
        await Task.detached(priority: .userInitiated) {
            progress(ProjectScanProgress(
                currentFolder: "Measuring \(root.lastPathComponent)…",
                foldersScanned: 0,
                projectsFound: 0
            ))
            let totalFolders = countScannableFolders(at: root, depth: 0)
            var reporter = ScanReporter(root: root, totalFolders: totalFolders, progress: progress)
            return buildTree(at: root, depth: 0, reporter: &reporter, cache: cache)?.children ?? []
        }.value
    }

    static func scanProject(at folder: URL, cache: ProjectInspectionCache? = nil) async -> Project? {
        await Task.detached(priority: .userInitiated) {
            var reporter = ScanReporter(root: folder, totalFolders: 1, progress: { _ in })
            return buildTree(at: folder, depth: 0, reporter: &reporter, cache: cache)?.project
        }.value
    }

    /// A lightweight first pass gives the UI a truthful denominator without
    /// walking inside Ableton projects, samples, backups, or export folders.
    private static func countScannableFolders(at folder: URL, depth: Int) -> Int {
        guard depth < 8 else { return 0 }
        guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
              ) else { return 1 }

        if contents.contains(where: { $0.pathExtension.lowercased() == "als" }) {
            return 1
        }
        return 1 + contents.reduce(into: 0) { count, item in
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                count += countScannableFolders(at: item, depth: depth + 1)
            }
        }
    }

    // Recursively builds a FolderNode tree.
    // Folders with a .als file → Ableton project leaf (even if no audio exports yet).
    // Folders without .als    → organizational node; recurse into subdirs.
    private static func buildTree(
        at folder: URL,
        depth: Int,
        reporter: inout ScanReporter,
        cache: ProjectInspectionCache?
    ) -> FolderNode? {
        guard depth < 8 else { return nil }
        reporter.entering(folder)

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(trackKeys) + [.tagNamesKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let alsFiles = contents.filter { $0.pathExtension.lowercased() == "als" }
        if !alsFiles.isEmpty {
            // This is an Ableton project folder
            let tracks   = audioFilesInProject(folder, rootContents: contents)
            let versions = alsVersionsIn(alsFiles)
            let attrs    = try? folder.resourceValues(forKeys: [.creationDateKey, .tagNamesKey])
            let backupFiles = abletonBackups(in: folder)
            let inspection = inspection(
                projectFiles: alsFiles,
                backupFiles: backupFiles,
                cache: cache
            )

            let project = Project(
                name: cleanName(folder.lastPathComponent),
                folderURL: folder,
                tracks: tracks,
                versions: versions,
                creationDate: attrs?.creationDate,
                tags: attrs?.tagNames ?? [],
                bpm: inspection.bpm,
                plugins: inspection.plugins,
                activity: inspection.activity
            )
            reporter.foundProject(in: folder)
            return FolderNode(url: folder, name: project.name, project: project, children: [])
        }

        // Organizational folder — recurse into subdirectories
        var children: [FolderNode] = []
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir, let child = buildTree(at: item, depth: depth + 1, reporter: &reporter, cache: cache) {
                children.append(child)
            }
        }
        guard !children.isEmpty else { return nil }

        let sorted = children.sorted {
            if $0.isProject != $1.isProject { return !$0.isProject }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
        return FolderNode(url: folder, name: folder.lastPathComponent, project: nil, children: sorted)
    }

    /// Reads the project's XML once, then serves the result from the cache for as
    /// long as the `.als` files keep the same paths, sizes, and dates.
    private static func inspection(
        projectFiles: [URL],
        backupFiles: [URL],
        cache: ProjectInspectionCache?
    ) -> AbletonProjectInspector.Result {
        let resume = { (cached: CachedInspection) in
            AbletonProjectInspector.Result(
                bpm: cached.bpm,
                plugins: cached.plugins,
                activity: cached.activity
            )
        }
        guard let cache,
              let fingerprint = AbletonProjectInspector.fingerprint(
                projectFiles: projectFiles,
                backupFiles: backupFiles
              ) else {
            return AbletonProjectInspector.inspect(
                projectFiles: projectFiles,
                backupFiles: backupFiles
            )
        }

        if let cached = cache.cached(for: fingerprint) {
            return resume(cached)
        }

        let inspected = AbletonProjectInspector.inspect(
            projectFiles: projectFiles,
            backupFiles: backupFiles
        )
        cache.store(
            CachedInspection(
                bpm: inspected.bpm,
                plugins: inspected.plugins,
                activity: inspected.activity
            ),
            for: fingerprint
        )
        return inspected
    }

    private static func abletonBackups(in projectFolder: URL) -> [URL] {
        let backupFolder = projectFolder.appendingPathComponent("Backup", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupFolder,
            includingPropertiesForKeys: Array(trackKeys),
            options: .skipsHiddenFiles
        ) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "als" }
    }

    // Root audio is always an export candidate. Nested audio is scanned only inside
    // clearly export-oriented folders, never Ableton's Samples/Recorded/Processed tree.
    private static func audioFilesInProject(_ projectFolder: URL, rootContents: [URL]) -> [Track] {
        var tracks = tracks(in: rootContents, relativeFolder: "")
        for url in rootContents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true,
                  exportFolderNames.contains(url.lastPathComponent.lowercased()) else { continue }
            tracks += audioFilesRecursively(at: url, relativeTo: projectFolder, depth: 0)
        }
        return tracks.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    private static func audioFilesRecursively(at folder: URL, relativeTo projectFolder: URL, depth: Int) -> [Track] {
        guard depth < 5,
              !ignoredAudioFolderNames.contains(folder.lastPathComponent.lowercased()),
              let contents = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(trackKeys),
                options: .skipsHiddenFiles
              ) else { return [] }

        let relative = String(folder.path.dropFirst(projectFolder.path.count + 1))
        var found = tracks(in: contents, relativeFolder: relative)
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                found += audioFilesRecursively(at: url, relativeTo: projectFolder, depth: depth + 1)
            }
        }
        return found
    }

    private static func tracks(in contents: [URL], relativeFolder: String) -> [Track] {
        contents.compactMap { url in
            let res = try? url.resourceValues(forKeys: trackKeys)
            guard !(res?.isDirectory ?? true),
                  audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return Track(url: url,
                         modificationDate: res?.contentModificationDate,
                         creationDate: res?.creationDate,
                         relativeFolder: relativeFolder)
        }
    }

    // .als files in the project root (the Backup/ subdir is never recursed, so only
    // the current + any manually-saved .als variants appear here).
    private static func alsVersionsIn(_ urls: [URL]) -> [AbletonVersion] {
        urls.compactMap { url in
            let res = try? url.resourceValues(forKeys: trackKeys)
            return AbletonVersion(url: url,
                                  modificationDate: res?.contentModificationDate,
                                  creationDate: res?.creationDate)
        }
        .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
    }

    private static func cleanName(_ folderName: String) -> String {
        folderName.hasSuffix(" Project")
            ? String(folderName.dropLast(" Project".count))
            : folderName
    }

    private struct ScanReporter {
        let root: URL
        let totalFolders: Int
        let progress: @Sendable (ProjectScanProgress) -> Void
        var foldersScanned = 0
        var projectsFound = 0

        mutating func entering(_ folder: URL) {
            foldersScanned += 1
            emit(folder)
        }

        mutating func foundProject(in folder: URL) {
            projectsFound += 1
            emit(folder)
        }

        private func emit(_ folder: URL) {
            let rootComponents = root.standardizedFileURL.pathComponents
            let folderComponents = folder.standardizedFileURL.pathComponents
            let relativeComponents = Array(folderComponents.dropFirst(rootComponents.count))
            let displayPath = relativeComponents.isEmpty
                ? root.lastPathComponent
                : relativeComponents.joined(separator: " / ")
            progress(ProjectScanProgress(
                currentFolder: displayPath,
                foldersScanned: foldersScanned,
                projectsFound: projectsFound,
                totalFolders: totalFolders
            ))
        }
    }
}
