import Foundation

// MARK: - Folder tree node
// Each node is either an organizational folder (children non-empty, project == nil)
// or an Ableton project leaf (project non-nil, children empty).
struct FolderNode: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let project: Project?
    let children: [FolderNode]

    var isProject: Bool { project != nil }

    var projectCount: Int {
        project != nil ? 1 : children.reduce(0) { $0 + $1.projectCount }
    }

    func allProjects() -> [Project] {
        if let p = project { return [p] }
        return children.flatMap { $0.allProjects() }
    }
}

// MARK: - Project
struct Project: Identifiable, Hashable {
    var id: URL { folderURL }
    let name: String
    let folderURL: URL
    let tracks: [Track]          // audio exports (wav, mp3, etc.)
    let versions: [AbletonVersion] // .als project files
    let creationDate: Date?
    let tags: [String]

    var hasExports: Bool { !tracks.isEmpty }

    var latestModification: Date {
        tracks.compactMap(\.modificationDate).max() ?? .distantPast
    }

    var sortedTracks: [Track] {
        tracks.sorted {
            ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
        }
    }
}

// MARK: - Track (audio export)
struct Track: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let modificationDate: Date?
    let creationDate: Date?

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }
}

// MARK: - AbletonVersion (.als project file)
struct AbletonVersion: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let modificationDate: Date?
    let creationDate: Date?

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Track group (name-based versioning, kept for potential future use)
struct TrackGroup: Identifiable {
    let id = UUID()
    let baseName: String
    let tracks: [Track]

    var isSingle: Bool { tracks.count == 1 }
}
