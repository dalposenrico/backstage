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

extension FolderNode {
    func replacingProject(_ project: Project) -> FolderNode {
        if url == project.folderURL {
            return FolderNode(url: url, name: project.name, project: project, children: [])
        }
        return FolderNode(
            url: url,
            name: name,
            project: self.project,
            children: children.map { $0.replacingProject(project) }
        )
    }
}

extension Array where Element == FolderNode {
    func findNode(at url: URL) -> FolderNode? {
        for node in self {
            if node.url == url { return node }
            if let match = node.children.findNode(at: url) { return match }
        }
        return nil
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
    let bpm: Double?
    let plugins: [String]
    let activity: ProjectActivity
    let latestModification: Date

    init(
        name: String,
        folderURL: URL,
        tracks: [Track],
        versions: [AbletonVersion],
        creationDate: Date?,
        tags: [String],
        bpm: Double?,
        plugins: [String],
        activity: ProjectActivity,
        latestModification: Date? = nil
    ) {
        self.name = name
        self.folderURL = folderURL
        self.tracks = tracks
        self.versions = versions
        self.creationDate = creationDate
        self.tags = tags
        self.bpm = bpm
        self.plugins = plugins
        self.activity = activity
        self.latestModification = latestModification ?? ((tracks.compactMap(\.modificationDate) + versions.compactMap(\.modificationDate)).max() ?? .distantPast)
    }

    var hasExports: Bool { !tracks.isEmpty }

    var bpmLabel: String? {
        guard let bpm else { return nil }
        return bpm.rounded() == bpm ? String(Int(bpm)) : String(format: "%.1f", bpm)
    }

    var latestSavedItem: (name: String, date: Date)? {
        let audioItems = tracks.compactMap { track in
            track.modificationDate.map { (track.displayName, $0) }
        }
        let abletonItems = versions.compactMap { version in
            version.modificationDate.map { (version.displayName, $0) }
        }
        return (audioItems + abletonItems).max { $0.1 < $1.1 }
    }

    var sortedTracks: [Track] {
        tracks.sorted {
            ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
        }
    }

    var exportGroups: [ExportGroup] {
        let grouped = Dictionary(grouping: sortedTracks) { $0.relativeFolder }
        return grouped.map { ExportGroup(folder: $0.key, tracks: $0.value) }
            .sorted {
                if $0.folder.isEmpty != $1.folder.isEmpty { return $0.folder.isEmpty }
                return $0.folder.localizedCompare($1.folder) == .orderedAscending
            }
    }

    var newestAbletonVersion: AbletonVersion? {
        versions.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
    }
}

struct ExportGroup: Identifiable {
    var id: String { folder }
    let folder: String
    let tracks: [Track]
}

struct ProjectActivity: Codable, Hashable {
    let backupCount: Int
    let sessionCount: Int
    let estimatedWorkTime: TimeInterval
    let firstSave: Date?
    let latestSave: Date?

    /// A deliberately simple activity scale, not a claim about song completion.
    /// Thirty Ableton backups fills the meter; deeply worked projects can exceed 100%.
    var activityPercent: Int {
        Int((Double(backupCount) / 30.0 * 100).rounded())
    }

    init(
        backupCount: Int = 0,
        sessionCount: Int = 0,
        estimatedWorkTime: TimeInterval = 0,
        firstSave: Date? = nil,
        latestSave: Date? = nil
    ) {
        self.backupCount = backupCount
        self.sessionCount = sessionCount
        self.estimatedWorkTime = estimatedWorkTime
        self.firstSave = firstSave
        self.latestSave = latestSave
    }
}

// MARK: - Track (audio export)
struct Track: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let modificationDate: Date?
    let creationDate: Date?
    let relativeFolder: String

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

// MARK: - Navigation & Sidebar Models

enum SidebarSection: Equatable {
    case all
    case recents
    case favorites
    case folder(URL)
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case library, project, home, releases, tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .project: return "Project"
        case .home: return "Focus studio"
        case .releases: return "Releases"
        case .tools: return "Tools"
        }
    }

    var icon: String {
        switch self {
        case .library: return "line.3.horizontal"
        case .project: return "waveform"
        case .home: return "sparkles"
        case .releases: return "shippingbox"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

