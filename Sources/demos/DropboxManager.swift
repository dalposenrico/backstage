import AppKit
import Foundation

@MainActor
final class DropboxManager: ObservableObject {
    static let shared = DropboxManager()

    @Published private(set) var dropboxRootURL: URL?
    @Published private(set) var isDropboxAvailable: Bool = false

    static let defaultClientWorkFolderName = "MIXING - MASTERING WORK"
    static let defaultMusicProjectsFolderName = "MUSIC PROJECTS"

    init() {
        refreshDropboxStatus()
    }

    /// Refresh detection of local Dropbox folder
    func refreshDropboxStatus() {
        if let detected = Self.findDropboxRoot() {
            dropboxRootURL = detected
            isDropboxAvailable = FileManager.default.fileExists(atPath: detected.path)
        } else {
            dropboxRootURL = nil
            isDropboxAvailable = false
        }
    }

    /// Detects Dropbox root directory using ~/.dropbox/info.json, CloudStorage, or home fallback.
    static func findDropboxRoot() -> URL? {
        // 1. Try ~/.dropbox/info.json
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let infoJSONURL = homeDir.appendingPathComponent(".dropbox/info.json")
        if let data = try? Data(contentsOf: infoJSONURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Can be under "personal" or "business"
            if let personal = json["personal"] as? [String: Any],
               let pathStr = personal["path"] as? String {
                let url = URL(fileURLWithPath: pathStr)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
            if let business = json["business"] as? [String: Any],
               let pathStr = business["path"] as? String {
                let url = URL(fileURLWithPath: pathStr)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        // 2. Try macOS CloudStorage path
        let cloudStoragePath = homeDir.appendingPathComponent("Library/CloudStorage/Dropbox")
        if FileManager.default.fileExists(atPath: cloudStoragePath.path) {
            return cloudStoragePath
        }

        // 3. Try standard ~/Dropbox
        let standardPath = homeDir.appendingPathComponent("Dropbox")
        if FileManager.default.fileExists(atPath: standardPath.path) {
            return standardPath
        }

        return nil
    }

    /// Resolves the recommended Dropbox destination folder for a given project configuration.
    func recommendedFolderURL(
        clientName: String?,
        projectName: String,
        isClientProject: Bool
    ) -> URL? {
        guard let root = dropboxRootURL else { return nil }
        let trimmedProject = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeProject = trimmedProject.isEmpty ? "Untitled Project" : trimmedProject

        if isClientProject {
            let client = clientName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeClient = (client?.isEmpty ?? true) ? "Unassigned Client" : client!
            return root
                .appendingPathComponent(Self.defaultClientWorkFolderName, isDirectory: true)
                .appendingPathComponent(safeClient, isDirectory: true)
                .appendingPathComponent(safeProject, isDirectory: true)
        } else {
            return root
                .appendingPathComponent(Self.defaultMusicProjectsFolderName, isDirectory: true)
                .appendingPathComponent(safeProject, isDirectory: true)
        }
    }

    /// Checks if a folder already exists on disk.
    func folderExists(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Creates the Dropbox project folder and optional standard studio subfolders atomically.
    @discardableResult
    func createProjectFolder(
        at folderURL: URL,
        createStudioSubfolders: Bool = true
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        if createStudioSubfolders {
            let subfolders = ["01 Stems", "02 Mix Bounces", "03 Deliverables", "04 References"]
            for sub in subfolders {
                let subURL = folderURL.appendingPathComponent(sub, isDirectory: true)
                try fm.createDirectory(at: subURL, withIntermediateDirectories: true)
            }
        }

        return folderURL
    }

    /// Reveals the folder in Finder.
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Computes the direct Dropbox Web URL for a local Dropbox folder path.
    func dropboxWebURL(for localURL: URL) -> URL? {
        guard let root = dropboxRootURL else { return nil }
        let rootPath = root.path
        let localPath = localURL.path

        guard localPath.hasPrefix(rootPath) else { return nil }

        let relativePath = String(localPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        let webURLString = "https://www.dropbox.com/home/\(encodedPath)"
        return URL(string: webURLString)
    }

    /// Opens the folder on Dropbox Web in the default browser.
    func openInDropboxWeb(localURL: URL) {
        if let webURL = dropboxWebURL(for: localURL) {
            NSWorkspace.shared.open(webURL)
        }
    }
}
