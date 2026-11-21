import Foundation
import SwiftUI
import AppKit

// MARK: - Sample Usage Status
enum SampleUsageStatus: Sendable, Equatable, Hashable {
    case unused
    case collectedInProject(projectNames: [String])
    case activeDependency(projectNames: [String])

    var isDeletable: Bool {
        switch self {
        case .unused, .collectedInProject:
            return true
        case .activeDependency:
            return false
        }
    }
}

// MARK: - Sample Audit Item
struct SampleAuditItem: Identifiable, Sendable, Equatable {
    let id: String // Absolute path
    let fileURL: URL
    let fileName: String
    let relativePath: String
    let fileSize: Int64
    let formattedSize: String
    let modificationDate: Date?
    var status: SampleUsageStatus

    var referencingProjects: [String] {
        switch status {
        case .unused: return []
        case .collectedInProject(let names): return names
        case .activeDependency(let names): return names
        }
    }
}

// MARK: - Cleaner Filter Mode
enum SampleCleanerFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unused = "Unused"
    case collected = "Collected in Projects"
    case active = "Active Dependencies"

    var id: String { rawValue }
}

// MARK: - Sample Library Cleaner Store
@MainActor
final class SampleLibraryCleanerStore: ObservableObject {
    static let shared = SampleLibraryCleanerStore()

    private static let libraryPathKey = "sampleLibraryCleanerPath"

    @Published var libraryURL: URL? {
        didSet {
            if let path = libraryURL?.path {
                UserDefaults.standard.set(path, forKey: Self.libraryPathKey)
            }
        }
    }

    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var auditItems: [SampleAuditItem] = []
    @Published var selectedItemIds: Set<String> = []
    @Published var filterMode: SampleCleanerFilter = .all
    @Published var searchText: String = ""
    @Published var isCollecting = false
    @Published var isDeleting = false
    @Published var errorMessage: String? = nil
    @Published var lastDeletedCount: Int = 0
    @Published var lastDeletedBytes: Int64 = 0
    @Published var showDeleteConfirmation = false

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: Self.libraryPathKey),
           FileManager.default.fileExists(atPath: savedPath) {
            self.libraryURL = URL(fileURLWithPath: savedPath)
        }
    }

    // MARK: - Filtered Items
    var displayedItems: [SampleAuditItem] {
        auditItems.filter { item in
            // Filter by category
            switch filterMode {
            case .all:
                break
            case .unused:
                if item.status != .unused { return false }
            case .collected:
                if case .collectedInProject = item.status { break } else { return false }
            case .active:
                if case .activeDependency = item.status { break } else { return false }
            }

            // Filter by search query
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let nameMatches = item.fileName.lowercased().contains(query)
                let pathMatches = item.relativePath.lowercased().contains(query)
                let projectMatches = item.referencingProjects.contains { $0.lowercased().contains(query) }
                return nameMatches || pathMatches || projectMatches
            }

            return true
        }
    }

    // MARK: - Counts & Size Metrics
    var totalCount: Int { auditItems.count }
    var totalBytes: Int64 { auditItems.reduce(0) { $0 + $1.fileSize } }
    var formattedTotalBytes: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }

    var unusedItems: [SampleAuditItem] {
        auditItems.filter { $0.status == .unused }
    }
    var unusedCount: Int { unusedItems.count }
    var unusedBytes: Int64 { unusedItems.reduce(0) { $0 + $1.fileSize } }
    var formattedUnusedBytes: String { ByteCountFormatter.string(fromByteCount: unusedBytes, countStyle: .file) }

    var collectedItems: [SampleAuditItem] {
        auditItems.filter {
            if case .collectedInProject = $0.status { return true }
            return false
        }
    }
    var collectedCount: Int { collectedItems.count }
    var collectedBytes: Int64 { collectedItems.reduce(0) { $0 + $1.fileSize } }
    var formattedCollectedBytes: String { ByteCountFormatter.string(fromByteCount: collectedBytes, countStyle: .file) }

    var activeDependencyItems: [SampleAuditItem] {
        auditItems.filter {
            if case .activeDependency = $0.status { return true }
            return false
        }
    }
    var activeDependencyCount: Int { activeDependencyItems.count }
    var activeDependencyBytes: Int64 { activeDependencyItems.reduce(0) { $0 + $1.fileSize } }
    var formattedActiveDependencyBytes: String { ByteCountFormatter.string(fromByteCount: activeDependencyBytes, countStyle: .file) }

    var selectedItems: [SampleAuditItem] {
        auditItems.filter { selectedItemIds.contains($0.id) }
    }
    var selectedCount: Int { selectedItems.count }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.fileSize } }
    var formattedSelectedBytes: String { ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file) }

    // MARK: - Selection Management
    func selectAllUnused() {
        let unusedIds = unusedItems.map(\.id)
        selectedItemIds.formUnion(unusedIds)
    }

    func selectAllCollected() {
        let collectedIds = collectedItems.map(\.id)
        selectedItemIds.formUnion(collectedIds)
    }

    func deselectAll() {
        selectedItemIds.removeAll()
    }

    func toggleSelection(for id: String) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            // Guard: don't allow selecting active dependencies
            if let item = auditItems.first(where: { $0.id == id }), item.status.isDeletable {
                selectedItemIds.insert(id)
            }
        }
    }

    // MARK: - Choose Folder
    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Sample Library"
        panel.message = "Choose the root folder of your sample library to scan."

        if let current = libraryURL {
            panel.directoryURL = current
        }

        if panel.runModal() == .OK, let selected = panel.url {
            self.libraryURL = selected
        }
    }

    // MARK: - Start Audit
    func startAudit(with projects: [Project]) {
        guard let libraryURL = self.libraryURL else {
            self.errorMessage = "Please choose a sample library folder first."
            return
        }

        isScanning = true
        scanProgress = 0.0
        statusMessage = "Preparing to scan Ableton projects…"
        auditItems = []
        selectedItemIds.removeAll()
        errorMessage = nil

        let targetLibrary = libraryURL

        Task.detached(priority: .userInitiated) {
            do {
                let items = try await Self.runAudit(projects: projects, libraryURL: targetLibrary) { progress, message in
                    Task { @MainActor in
                        self.scanProgress = progress
                        self.statusMessage = message
                    }
                }

                await MainActor.run {
                    self.auditItems = items
                    self.isScanning = false
                    self.statusMessage = "Scan complete. Found \(items.count) samples."
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.errorMessage = "Audit failed: \(error.localizedDescription)"
                    self.statusMessage = "Scan error."
                }
            }
        }
    }

    // MARK: - Collect into Project Action
    func collectSampleIntoProject(item: SampleAuditItem, targetProject: Project) async {
        isCollecting = true
        defer { isCollecting = false }

        let fm = FileManager.default
        let importedFolder = targetProject.folderURL.appendingPathComponent("Samples/Imported", isDirectory: true)

        do {
            try fm.createDirectory(at: importedFolder, withIntermediateDirectories: true)
            let destinationURL = importedFolder.appendingPathComponent(item.fileName)

            if !fm.fileExists(atPath: destinationURL.path) {
                try fm.copyItem(at: item.fileURL, to: destinationURL)
            }

            // Update item in audit list: it is now safely collected!
            if let index = auditItems.firstIndex(where: { $0.id == item.id }) {
                auditItems[index].status = .collectedInProject(projectNames: [targetProject.name])
            }
        } catch {
            errorMessage = "Failed to collect sample into \(targetProject.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Move Selected to Trash
    func moveSelectedToTrash() async {
        guard !selectedItemIds.isEmpty else { return }

        isDeleting = true
        defer { isDeleting = false }

        let fm = FileManager.default
        let itemsToDelete = auditItems.filter { selectedItemIds.contains($0.id) && $0.status.isDeletable }

        var deletedCount = 0
        var deletedBytes: Int64 = 0
        var deletedIds: Set<String> = []

        for item in itemsToDelete {
            do {
                try fm.trashItem(at: item.fileURL, resultingItemURL: nil)
                deletedCount += 1
                deletedBytes += item.fileSize
                deletedIds.insert(item.id)
            } catch {
                print("Failed to trash \(item.fileName): \(error.localizedDescription)")
            }
        }

        // Update UI
        self.lastDeletedCount = deletedCount
        self.lastDeletedBytes = deletedBytes
        self.auditItems.removeAll { deletedIds.contains($0.id) }
        self.selectedItemIds.subtract(deletedIds)
    }

    // MARK: - Background Analysis Engine
    private static func runAudit(
        projects: [Project],
        libraryURL: URL,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [SampleAuditItem] {
        let fm = FileManager.default

        // Step 1: Extract sample references from all projects
        onProgress(0.05, "Scanning Ableton projects for sample dependencies…")

        // Map: standardized lowercased file path -> Set of project names
        var externalReferencedPaths: [String: Set<String>] = [:]
        // Map: lowercased filename -> Set of project names
        var externalReferencedNames: [String: Set<String>] = [:]
        // Map: lowercased filename -> List of (projectName, fileSize) for collected project copies
        var projectCollectedFiles: [String: [(projectName: String, fileSize: Int64)]] = [:]

        let totalProjects = max(1, projects.count)

        for (index, project) in projects.enumerated() {
            let pct = 0.05 + (Double(index) / Double(totalProjects)) * 0.45
            onProgress(pct, "Inspecting project \(index + 1) of \(totalProjects): \(project.name)…")

            // Ensure offline .als is available even if offloaded
            var alsURLs: [URL] = []
            if project.isOffloaded {
                alsURLs = ProjectOffloadStore.shared.ensureAlsAvailableLocally(for: project.folderURL)
            }
            if alsURLs.isEmpty {
                alsURLs = project.versions.map(\.url).filter { fm.fileExists(atPath: $0.path) }
            }
            if alsURLs.isEmpty {
                // Check folder directly
                let folderContents = (try? fm.contentsOfDirectory(at: project.folderURL, includingPropertiesForKeys: nil)) ?? []
                alsURLs = folderContents.filter { $0.pathExtension.lowercased() == "als" }
            }

            // 1a. Parse .als XML files
            for alsURL in alsURLs {
                guard let xml = Gunzip.readTextFile(at: alsURL) else { continue }
                let refs = extractSampleRefs(from: xml, projectFolderURL: project.folderURL)

                for ref in refs {
                    if ref.isCollected {
                        // Collected inside this project
                        if let name = ref.fileName?.lowercased() {
                            projectCollectedFiles[name, default: []].append((project.name, ref.fileSize ?? 0))
                        }
                    } else {
                        // External reference!
                        if let path = ref.standardizedPath {
                            externalReferencedPaths[path, default: []].insert(project.name)
                        }
                        if let name = ref.fileName?.lowercased() {
                            externalReferencedNames[name, default: []].insert(project.name)
                        }
                    }
                }
            }

            // 1b. Also scan the physical project's Samples/ folder on disk for collected samples
            let samplesDir = project.folderURL.appendingPathComponent("Samples")
            if fm.fileExists(atPath: samplesDir.path),
               let enumerator = fm.enumerator(
                at: samplesDir,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
               ) {
                while let fileURL = enumerator.nextObject() as? URL {
                    guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                          vals.isDirectory == false,
                          let size = vals.fileSize else { continue }

                    let name = fileURL.lastPathComponent.lowercased()
                    projectCollectedFiles[name, default: []].append((project.name, Int64(size)))
                }
            }
        }

        // Step 2: Enumerate sample library files
        onProgress(0.55, "Scanning sample library files on disk…")

        let libraryStandardPath = libraryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let audioExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "flac", "m4a", "ogg"]

        guard let libraryEnumerator = fm.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var scannedFiles: [(url: URL, relative: String, size: Int64, modDate: Date?)] = []

        while let fileURL = libraryEnumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            guard !fileURL.lastPathComponent.hasPrefix("._") else { continue }

            guard let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]),
                  vals.isDirectory == false,
                  let size = vals.fileSize else { continue }

            let path = fileURL.standardizedFileURL.path
            var rel = String(path.dropFirst(libraryStandardPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }

            scannedFiles.append((fileURL, rel, Int64(size), vals.contentModificationDate))
        }

        // Step 3: Cross-reference samples against project references
        onProgress(0.80, "Cross-referencing \(scannedFiles.count) samples with project dependencies…")

        var auditItems: [SampleAuditItem] = []
        auditItems.reserveCapacity(scannedFiles.count)

        for item in scannedFiles {
            let standardPath = item.url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
            let lowerName = item.url.lastPathComponent.lowercased()

            let status: SampleUsageStatus

            // Check A: Active external dependency
            if let projects = externalReferencedPaths[standardPath], !projects.isEmpty {
                status = .activeDependency(projectNames: Array(projects).sorted())
            } else if let projects = externalReferencedNames[lowerName], !projects.isEmpty {
                // If the name matched and file is referenced externally
                status = .activeDependency(projectNames: Array(projects).sorted())
            }
            // Check B: Collected inside project(s)
            else if let collectedProjects = projectCollectedFiles[lowerName], !collectedProjects.isEmpty {
                // Check if size matches (or within tolerance)
                let matching = collectedProjects.filter { entry in
                    entry.fileSize == 0 || entry.fileSize == item.size
                }
                if !matching.isEmpty {
                    let uniqueNames = Array(Set(matching.map(\.projectName))).sorted()
                    status = .collectedInProject(projectNames: uniqueNames)
                } else {
                    status = .unused
                }
            }
            // Check C: Completely unused
            else {
                status = .unused
            }

            auditItems.append(SampleAuditItem(
                id: item.url.path,
                fileURL: item.url,
                fileName: item.url.lastPathComponent,
                relativePath: item.relative,
                fileSize: item.size,
                formattedSize: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                modificationDate: item.modDate,
                status: status
            ))
        }

        onProgress(1.0, "Analysis complete.")

        // Default sort: Unused first, then largest size first
        return auditItems.sorted { a, b in
            if a.status == .unused && b.status != .unused { return true }
            if a.status != .unused && b.status == .unused { return false }
            return a.fileSize > b.fileSize
        }
    }

    // MARK: - Sample Reference Extraction from Ableton XML
    private struct ExtractedRef {
        let fileName: String?
        let standardizedPath: String?
        let relativePath: String?
        let isCollected: Bool
        let fileSize: Int64?
    }

    private static let sampleRefRegex = try! NSRegularExpression(
        pattern: #"<SampleRef>[\s\S]*?</SampleRef>"#
    )
    private static let pathRegex = try! NSRegularExpression(
        pattern: #"<Path\s+Value=\"([^\"]*)\""#
    )
    private static let relPathRegex = try! NSRegularExpression(
        pattern: #"<RelativePath\s+Value=\"([^\"]*)\""#
    )
    private static let nameRegex = try! NSRegularExpression(
        pattern: #"<Name\s+Value=\"([^\"]*)\""#
    )

    private static func extractSampleRefs(from xml: String, projectFolderURL: URL) -> [ExtractedRef] {
        let ns = xml as NSString
        let matches = sampleRefRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))

        var results: [ExtractedRef] = []
        results.reserveCapacity(matches.count)

        let projectStandardPath = projectFolderURL.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()

        for match in matches {
            let snippet = ns.substring(with: match.range)
            let snippetNS = snippet as NSString
            let snippetRange = NSRange(location: 0, length: snippetNS.length)

            let rawPath: String? = {
                guard let m = pathRegex.firstMatch(in: snippet, range: snippetRange), m.range(at: 1).location != NSNotFound else { return nil }
                return snippetNS.substring(with: m.range(at: 1))
            }()

            let rawRel: String? = {
                guard let m = relPathRegex.firstMatch(in: snippet, range: snippetRange), m.range(at: 1).location != NSNotFound else { return nil }
                return snippetNS.substring(with: m.range(at: 1))
            }()

            let rawName: String? = {
                guard let m = nameRegex.firstMatch(in: snippet, range: snippetRange), m.range(at: 1).location != NSNotFound else { return nil }
                return snippetNS.substring(with: m.range(at: 1))
            }()

            let standardizedPath: String? = {
                guard let p = rawPath, !p.isEmpty else { return nil }
                return URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
            }()

            let isCollected: Bool = {
                if let rel = rawRel?.lowercased(), rel.contains("samples/") {
                    return true
                }
                if let std = standardizedPath, std.contains(projectStandardPath) && std.contains("/samples/") {
                    return true
                }
                return false
            }()

            results.append(ExtractedRef(
                fileName: rawName,
                standardizedPath: standardizedPath,
                relativePath: rawRel,
                isCollected: isCollected,
                fileSize: nil
            ))
        }

        return results
    }
}
