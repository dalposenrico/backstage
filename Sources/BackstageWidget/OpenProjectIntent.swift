import AppIntents
import AppKit

struct OpenProjectInAbletonIntent: AppIntent {
    static var title: LocalizedStringResource = "Open in Ableton Live"
    static var description = IntentDescription("Opens the latest Ableton Live project file (.als).")

    @Parameter(title: "ALS Path")
    var alsPath: String

    @Parameter(title: "Folder Path")
    var folderPath: String

    init() {
        self.alsPath = ""
        self.folderPath = ""
    }

    init(alsPath: String?, folderPath: String) {
        self.alsPath = alsPath ?? ""
        self.folderPath = folderPath
    }

    func perform() async throws -> some IntentResult {
        if !alsPath.isEmpty, FileManager.default.fileExists(atPath: alsPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: alsPath))
            return .result()
        }
        if !folderPath.isEmpty, FileManager.default.fileExists(atPath: folderPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: folderPath))
        }
        return .result()
    }
}

struct OpenProjectInFinderIntent: AppIntent {
    static var title: LocalizedStringResource = "Open in Finder"
    static var description = IntentDescription("Opens the project folder in Finder.")

    @Parameter(title: "Path")
    var path: String

    init() { self.path = "" }
    init(path: String) { self.path = path }

    func perform() async throws -> some IntentResult {
        guard !path.isEmpty else { return .result() }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        return .result()
    }
}

struct OpenProjectInHQIntent: AppIntent {
    static var title: LocalizedStringResource = "Open in goodvibrations HQ"
    static var description = IntentDescription("Focuses the project in goodvibrations HQ.")

    @Parameter(title: "Path")
    var path: String

    init() { self.path = "" }
    init(path: String) { self.path = path }

    func perform() async throws -> some IntentResult {
        if path.isEmpty {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.enricodalpos.goodvibrationshq") {
                _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            } else if let fallback = URL(string: "goodvibrations://open-project") {
                NSWorkspace.shared.open(fallback)
            }
        } else if let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "goodvibrations://open-project?path=\(encoded)") {
            NSWorkspace.shared.open(url)
        }
        return .result()
    }
}

struct OpenLastProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Last Active Project"
    static var description = IntentDescription("Opens the most recently active project in Ableton Live.")

    init() {}

    func perform() async throws -> some IntentResult {
        if let snapshot = WidgetDataStorage.load(), let project = snapshot.lastActiveProject {
            if let als = project.alsPath, !als.isEmpty, FileManager.default.fileExists(atPath: als) {
                NSWorkspace.shared.open(URL(fileURLWithPath: als))
            } else if !project.path.isEmpty {
                NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
            }
        }
        return .result()
    }
}

struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project in Finder"

    @Parameter(title: "Path")
    var path: String

    init() { self.path = "" }
    init(path: String) { self.path = path }

    func perform() async throws -> some IntentResult {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        return .result()
    }
}
