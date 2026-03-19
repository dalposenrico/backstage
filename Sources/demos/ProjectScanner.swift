import Foundation

enum ProjectScanner {
    static let audioExtensions: Set<String> = [
        "mp3", "wav", "aiff", "aif", "m4a", "flac", "ogg", "caf", "opus", "alac", "aac"
    ]

    private static let trackKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .contentModificationDateKey, .creationDateKey
    ]

    static func scan(root: URL) async -> [FolderNode] {
        await Task.detached(priority: .userInitiated) {
            buildTree(at: root, depth: 0)?.children ?? []
        }.value
    }

    // Recursively builds a FolderNode tree.
    // Folders with a .als file → Ableton project leaf (even if no audio exports yet).
    // Folders without .als    → organizational node; recurse into subdirs.
    private static func buildTree(at folder: URL, depth: Int) -> FolderNode? {
        guard depth < 8 else { return nil }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(trackKeys) + [.tagNamesKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let alsFiles = contents.filter { $0.pathExtension.lowercased() == "als" }
        if !alsFiles.isEmpty {
            // This is an Ableton project folder
            let tracks   = audioFilesIn(contents)
            let versions = alsVersionsIn(alsFiles)
            let attrs    = try? folder.resourceValues(forKeys: [.creationDateKey, .tagNamesKey])

            let project = Project(
                name: cleanName(folder.lastPathComponent),
                folderURL: folder,
                tracks: tracks,
                versions: versions,
                creationDate: attrs?.creationDate,
                tags: attrs?.tagNames ?? []
            )
            return FolderNode(url: folder, name: project.name, project: project, children: [])
        }

        // Organizational folder — recurse into subdirectories
        var children: [FolderNode] = []
        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir, let child = buildTree(at: item, depth: depth + 1) {
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

    // Only direct audio children — Samples/, Backup/ etc. are never recursed into.
    private static func audioFilesIn(_ contents: [URL]) -> [Track] {
        contents.compactMap { url in
            let res = try? url.resourceValues(forKeys: trackKeys)
            guard !(res?.isDirectory ?? true),
                  audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return Track(url: url,
                         modificationDate: res?.contentModificationDate,
                         creationDate: res?.creationDate)
        }
        .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
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
}
