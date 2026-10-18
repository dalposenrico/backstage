import Foundation

public struct WidgetSnapshotData: Codable, Sendable {
    public let updatedAt: Date
    public let lastActiveProject: WidgetProjectSummary?
    public let recentProjects: [WidgetProjectSummary]
    public let favoriteProjects: [WidgetProjectSummary]
    public let totalProjectsCount: Int

    public init(
        updatedAt: Date = Date(),
        lastActiveProject: WidgetProjectSummary? = nil,
        recentProjects: [WidgetProjectSummary] = [],
        favoriteProjects: [WidgetProjectSummary] = [],
        totalProjectsCount: Int = 0
    ) {
        self.updatedAt = updatedAt
        self.lastActiveProject = lastActiveProject
        self.recentProjects = recentProjects
        self.favoriteProjects = favoriteProjects
        self.totalProjectsCount = totalProjectsCount
    }
}

public struct WidgetProjectSummary: Codable, Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let alsPath: String?
    public let lastModified: Date
    public let bpm: Double?
    public let musicalKey: String?
    public let trackName: String?
    public let isFavorite: Bool

    public init(
        name: String,
        path: String,
        alsPath: String?,
        lastModified: Date,
        bpm: Double? = nil,
        musicalKey: String? = nil,
        trackName: String? = nil,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.path = path
        self.alsPath = alsPath
        self.lastModified = lastModified
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.trackName = trackName
        self.isFavorite = isFavorite
    }
}

public enum WidgetDataStorage {
    public static let sharedContainerURL: URL = {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.enricodalpos.goodvibrationshq") {
            return groupURL
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let groupDir = home.appendingPathComponent("Library/Group Containers/group.com.enricodalpos.goodvibrationshq")
        try? FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)
        return groupDir
    }()

    public static var fileURL: URL {
        let dir = sharedContainerURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("widget_data.json")
    }

    public static func load() -> WidgetSnapshotData? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshotData.self, from: data) else {
            return nil
        }
        return snapshot
    }

    public static func save(_ snapshot: WidgetSnapshotData) {
        let url = fileURL
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url)
        }
    }
}
