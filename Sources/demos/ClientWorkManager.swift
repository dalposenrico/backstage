import AppKit
import Foundation
import SwiftUI

@MainActor
final class ClientWorkManager: ObservableObject {
    static let shared = ClientWorkManager()

    static let defaultFolderName = "MIXING - MASTERING WORK"

    @Published var clientWorkFolderName: String {
        didSet {
            UserDefaults.standard.set(clientWorkFolderName, forKey: "clientWorkFolderName")
            refreshDiscoveredClients()
        }
    }

    @Published var customClientWorkFolderPath: String? {
        didSet {
            UserDefaults.standard.set(customClientWorkFolderPath, forKey: "customClientWorkFolderPath")
            refreshDiscoveredClients()
        }
    }

    @Published private(set) var discoveredClientNames: [String] = []

    init() {
        let savedName = UserDefaults.standard.string(forKey: "clientWorkFolderName")
        clientWorkFolderName = (savedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ? Self.defaultFolderName
            : savedName!

        customClientWorkFolderPath = UserDefaults.standard.string(forKey: "customClientWorkFolderPath")
        refreshDiscoveredClients()
    }

    /// Resolves the effective base URL where all client folders live.
    var clientWorkBaseURL: URL {
        if let custom = customClientWorkFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }

        // 1. Check if ~/Music/<clientWorkFolderName> exists
        let musicDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        let musicClientURL = musicDir.appendingPathComponent(clientWorkFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: musicClientURL.path) {
            return musicClientURL
        }

        // 2. Check if Dropbox has this folder (only if the folder actually exists on disk in Dropbox)
        if let dropbox = DropboxManager.shared.dropboxRootURL {
            let dropboxClientURL = dropbox.appendingPathComponent(clientWorkFolderName, isDirectory: true)
            if FileManager.default.fileExists(atPath: dropboxClientURL.path) {
                return dropboxClientURL
            }
        }

        // 3. Default to ~/Music/<clientWorkFolderName>
        return musicClientURL
    }

    /// Checks if the client work base directory exists on disk.
    var baseFolderExistsOnDisk: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: clientWorkBaseURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Ensures the client work base directory exists on disk.
    @discardableResult
    func ensureBaseFolderExists() throws -> URL {
        let url = clientWorkBaseURL
        if !baseFolderExistsOnDisk {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Scans the client work base folder for subdirectories (each subdirectory is a client).
    func refreshDiscoveredClients() {
        let base = clientWorkBaseURL
        guard FileManager.default.fileExists(atPath: base.path) else {
            discoveredClientNames = []
            return
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            discoveredClientNames = []
            return
        }

        var names: [String] = []
        for item in contents {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let name = item.lastPathComponent
                if !name.hasPrefix(".") {
                    names.append(name)
                }
            }
        }

        discoveredClientNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Creates a folder on disk for a new client inside the client work base directory.
    @discardableResult
    func createClientFolder(named rawName: String) throws -> URL {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClientWorkError.invalidClientName
        }

        // Sanitize path component
        let sanitized = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        try ensureBaseFolderExists()

        let clientFolderURL = clientWorkBaseURL.appendingPathComponent(sanitized, isDirectory: true)
        if !FileManager.default.fileExists(atPath: clientFolderURL.path) {
            try FileManager.default.createDirectory(at: clientFolderURL, withIntermediateDirectories: true)
        }

        refreshDiscoveredClients()
        return clientFolderURL
    }

    /// Renames the client work folder name (e.g. from "MIXING - MASTERING WORK" to another name).
    func renameClientWorkFolder(to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClientWorkError.invalidFolderName
        }

        if customClientWorkFolderPath == nil {
            // Default location: rename on disk if it currently exists
            let currentURL = clientWorkBaseURL
            let parentURL = currentURL.deletingLastPathComponent()
            let newURL = parentURL.appendingPathComponent(trimmed, isDirectory: true)

            if FileManager.default.fileExists(atPath: currentURL.path) && currentURL != newURL {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    throw ClientWorkError.destinationAlreadyExists(newURL.path)
                }
                try FileManager.default.moveItem(at: currentURL, to: newURL)
            }
        }

        clientWorkFolderName = trimmed
        refreshDiscoveredClients()
    }

    /// Opens an NSOpenPanel to let the user select a custom base folder for client work.
    func chooseCustomBaseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Client Work Base Folder"
        panel.prompt = "Choose Folder"
        panel.message = "Select the folder that contains your client subfolders (e.g. Mixing/Mastering Work)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = clientWorkBaseURL

        if panel.runModal() == .OK, let url = panel.url {
            customClientWorkFolderPath = url.path
            refreshDiscoveredClients()
        }
    }

    /// Resets the base folder to automatic detection (Dropbox / Music).
    func resetToDefaultBaseFolder() {
        customClientWorkFolderPath = nil
        refreshDiscoveredClients()
    }

    /// Moves a project folder on disk into a client's folder, migrating all metadata, to-dos, and progress.
    @discardableResult
    func moveProject(
        _ project: Project,
        toClient clientName: String,
        metadataStore: ProjectMetadataStore,
        todoStore: ProjectTodoStore,
        progressStore: ProjectProgressStore
    ) throws -> URL {
        let trimmedClient = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClient.isEmpty else {
            throw ClientWorkError.invalidClientName
        }

        let clientFolderURL = try createClientFolder(named: trimmedClient)
        let sourceURL = project.folderURL
        let destinationURL = clientFolderURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            throw ClientWorkError.alreadyInDestination
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            throw ClientWorkError.destinationAlreadyExists(destinationURL.path)
        }

        // Perform the disk move
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)

        // Migrate local store mappings from old path to new path
        let oldPath = sourceURL.path
        let newPath = destinationURL.path

        metadataStore.migratePath(from: oldPath, to: newPath)
        todoStore.migratePath(from: oldPath, to: newPath)
        progressStore.migratePath(from: oldPath, to: newPath)

        // Explicitly set project kind to Client and record client name
        metadataStore.setProjectKind(.client, forPath: newPath)
        metadataStore.setClientName(trimmedClient, forPath: newPath)

        refreshDiscoveredClients()
        return destinationURL
    }

    /// Reveals a folder in Finder.
    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum ClientWorkError: LocalizedError {
    case invalidClientName
    case invalidFolderName
    case alreadyInDestination
    case destinationAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidClientName:
            return "Please provide a valid client name."
        case .invalidFolderName:
            return "Please provide a valid folder name."
        case .alreadyInDestination:
            return "This project is already inside this client's folder."
        case .destinationAlreadyExists(let path):
            return "A folder already exists at: \(path)"
        }
    }
}
