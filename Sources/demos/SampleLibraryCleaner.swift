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
    let packFolder: String // First 1 or 2 directory components
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

// MARK: - Sample Pack Folder
struct SamplePackFolder: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let totalCount: Int
    let totalBytes: Int64
    let unusedCount: Int
    let unusedBytes: Int64
    let collectedCount: Int
    let activeDependencyCount: Int

    var formattedTotalBytes: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    var formattedUnusedBytes: String { ByteCountFormatter.string(fromByteCount: unusedBytes, countStyle: .file) }
}

// MARK: - Cleaner View Mode
enum CleanerPresentationMode: String, CaseIterable, Identifiable {
    case folderBrowser = "Folder Browser"
    case tinderSwipe = "Tinder Swiper"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .folderBrowser: return "folder.fill"
        case .tinderSwipe: return "flame.fill"
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

    // Navigation & View Modes
    @Published var viewMode: CleanerPresentationMode = .folderBrowser
    @Published var selectedPackPath: String? = nil // nil = All Folders
    @Published var folderSearchText: String = ""

    // Scan State
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var auditItems: [SampleAuditItem] = []
    @Published var packFolders: [SamplePackFolder] = []

    // Filter & Search
    @Published var selectedItemIds: Set<String> = []
    @Published var filterMode: SampleCleanerFilter = .all
    @Published var searchText: String = ""

    // Tinder Swipe Mode State
    @Published var swipeDeck: [SampleAuditItem] = []
    @Published var currentSwipeIndex: Int = 0
    @Published var markedForTrashIds: Set<String> = []
    @Published var markedToKeepIds: Set<String> = []
    @Published var swipeHistory: [(item: SampleAuditItem, isTrash: Bool)] = []

    // Actions & Deletions
    @Published var isCollecting = false
    @Published var isDeleting = false
    @Published var errorMessage: String? = nil
    @Published var lastDeletedCount: Int = 0
    @Published var lastDeletedBytes: Int64 = 0
    @Published var showDeleteConfirmation = false
    @Published var deleteConfirmationSource: DeleteSource = .selectedItems

    enum DeleteSource {
        case selectedItems
        case swipedTrashItems
    }

    private var scanTask: Task<Void, Never>?

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: Self.libraryPathKey),
           FileManager.default.fileExists(atPath: savedPath) {
            self.libraryURL = URL(fileURLWithPath: savedPath)
        }
    }

    // MARK: - Filtered Items for Browser
    var displayedItems: [SampleAuditItem] {
        auditItems.filter { item in
            // Filter by selected pack
            if let pack = selectedPackPath, item.packFolder != pack {
                return false
            }

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

    var displayedPackFolders: [SamplePackFolder] {
        if folderSearchText.isEmpty {
            return packFolders
        }
        let q = folderSearchText.lowercased()
        return packFolders.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
    }

    // MARK: - Metrics
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

    // Tinder Swipe Metrics
    var swipedTrashItems: [SampleAuditItem] {
        auditItems.filter { markedForTrashIds.contains($0.id) }
    }
    var swipedTrashBytes: Int64 {
        swipedTrashItems.reduce(0) { $0 + $1.fileSize }
    }
    var formattedSwipedTrashBytes: String {
        ByteCountFormatter.string(fromByteCount: swipedTrashBytes, countStyle: .file)
    }

    // MARK: - Tinder Deck Management
    func prepareSwipeDeck() {
        // As requested: ONLY samples that DO NOT have dependencies (safe to choose without fear!)
        let eligible = auditItems.filter { item in
            guard item.status.isDeletable else { return false }
            if let pack = selectedPackPath {
                return item.packFolder == pack
            }
            return true
        }

        // Exclude already marked ones
        self.swipeDeck = eligible.filter { !markedForTrashIds.contains($0.id) && !markedToKeepIds.contains($0.id) }
        self.currentSwipeIndex = 0

        // Auto-play the first sample if available
        if let first = swipeDeck.first {
            SampleAudioPlayer.shared.play(sampleId: first.id, url: first.fileURL)
        }
    }

    var currentSwipeCard: SampleAuditItem? {
        guard currentSwipeIndex < swipeDeck.count else { return nil }
        return swipeDeck[currentSwipeIndex]
    }

    var nextSwipeCard: SampleAuditItem? {
        let nextIndex = currentSwipeIndex + 1
        guard nextIndex < swipeDeck.count else { return nil }
        return swipeDeck[nextIndex]
    }

    func swipeLeftTrash() {
        guard let card = currentSwipeCard else { return }
        markedForTrashIds.insert(card.id)
        swipeHistory.append((item: card, isTrash: true))
        advanceSwipe()
    }

    func swipeRightKeep() {
        guard let card = currentSwipeCard else { return }
        markedToKeepIds.insert(card.id)
        swipeHistory.append((item: card, isTrash: false))
        advanceSwipe()
    }

    func undoLastSwipe() {
        guard let last = swipeHistory.popLast() else { return }
        if last.isTrash {
            markedForTrashIds.remove(last.item.id)
        } else {
            markedToKeepIds.remove(last.item.id)
        }
        if currentSwipeIndex > 0 {
            currentSwipeIndex -= 1
        }
        if let current = currentSwipeCard {
            SampleAudioPlayer.shared.play(sampleId: current.id, url: current.fileURL)
        }
    }

    private func advanceSwipe() {
        currentSwipeIndex += 1
        if let next = currentSwipeCard {
            SampleAudioPlayer.shared.play(sampleId: next.id, url: next.fileURL)
        } else {
            SampleAudioPlayer.shared.stop()
        }
    }

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

    // MARK: - Cancel Scan
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        statusMessage = "Scan cancelled."
    }

    // MARK: - Start Audit (Lightweight, Background QoS)
    func startAudit(with projects: [Project]) {
        guard let libraryURL = self.libraryURL else {
            self.errorMessage = "Please choose a sample library folder first."
            return
        }

        scanTask?.cancel()

        isScanning = true
        scanProgress = 0.0
        statusMessage = "Preparing background scanner…"
        auditItems = []
        packFolders = []
        selectedItemIds.removeAll()
        markedForTrashIds.removeAll()
        markedToKeepIds.removeAll()
        swipeHistory.removeAll()
        errorMessage = nil

        let targetLibrary = libraryURL

        scanTask = Task.detached(priority: .utility) {
            do {
                final class ProgressThrottle: @unchecked Sendable {
                    private var lastUpdate = Date.distantPast
                    private let lock = NSLock()
                    func shouldUpdate(now: Date) -> Bool {
                        lock.lock()
                        defer { lock.unlock() }
                        if now.timeIntervalSince(lastUpdate) >= 0.12 {
                            lastUpdate = now
                            return true
                        }
                        return false
                    }
                }
                let throttle = ProgressThrottle()

                let (items, folders) = try await Self.runAudit(projects: projects, libraryURL: targetLibrary) { progress, message in
                    // Throttle UI dispatches to max 8 times per second so the Mac stays cool and responsive
                    let now = Date()
                    if throttle.shouldUpdate(now: now) || progress >= 1.0 {
                        Task { @MainActor in
                            self.scanProgress = progress
                            self.statusMessage = message
                        }
                    }
                }

                if Task.isCancelled { return }

                await MainActor.run {
                    self.auditItems = items
                    self.packFolders = folders
                    self.isScanning = false
                    self.statusMessage = "Scan complete. Cataloged \(items.count) samples in \(folders.count) packs."
                    self.prepareSwipeDeck()
                }
            } catch {
                if Task.isCancelled { return }
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
            // Also update swipe deck if present
            if let deckIdx = swipeDeck.firstIndex(where: { $0.id == item.id }) {
                swipeDeck[deckIdx].status = .collectedInProject(projectNames: [targetProject.name])
            }
        } catch {
            errorMessage = "Failed to collect sample into \(targetProject.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Move Selected to Trash
    func moveItemsToTrash(ids: Set<String>) async {
        guard !ids.isEmpty else { return }

        isDeleting = true
        defer { isDeleting = false }

        let fm = FileManager.default
        let itemsToDelete = auditItems.filter { ids.contains($0.id) && $0.status.isDeletable }

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
        self.markedForTrashIds.subtract(deletedIds)
        self.swipeDeck.removeAll { deletedIds.contains($0.id) }
        self.packFolders = Self.computePackFolders(from: self.auditItems)
    }

    // MARK: - Ultra-Fast Background Analysis Engine
    private static func runAudit(
        projects: [Project],
        libraryURL: URL,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ([SampleAuditItem], [SamplePackFolder]) {
        let fm = FileManager.default

        // Step 1: Scan projects
        onProgress(0.05, "Scanning Ableton projects for sample dependencies…")

        var externalReferencedPaths: [String: Set<String>] = [:]
        var externalReferencedNames: [String: Set<String>] = [:]
        var projectCollectedFiles: [String: [(projectName: String, fileSize: Int64)]] = [:]

        let totalProjects = max(1, projects.count)

        for (index, project) in projects.enumerated() {
            if Task.isCancelled { break }

            let pct = 0.05 + (Double(index) / Double(totalProjects)) * 0.40
            onProgress(pct, "Project \(index + 1) of \(totalProjects): \(project.name)…")

            // Micro-yield so background scanning never blocks UI or other tasks
            await Task.yield()

            // Find primary .als file (check newest version first to avoid scanning 10 backup iterations)
            var alsURLs: [URL] = []
            if project.isOffloaded {
                alsURLs = ProjectOffloadStore.shared.ensureAlsAvailableLocally(for: project.folderURL)
            }
            if alsURLs.isEmpty, let newest = project.newestAbletonVersion?.url, fm.fileExists(atPath: newest.path) {
                alsURLs = [newest]
            }
            if alsURLs.isEmpty {
                let folderContents = (try? fm.contentsOfDirectory(at: project.folderURL, includingPropertiesForKeys: nil)) ?? []
                alsURLs = folderContents.filter { $0.pathExtension.lowercased() == "als" }
            }

            // Parse .als XML using fast substring scanner (skips massive envelopes)
            for alsURL in alsURLs {
                guard let xml = Gunzip.readTextFile(at: alsURL) else { continue }
                let refs = extractSampleRefsFast(from: xml, projectFolderURL: project.folderURL)

                for ref in refs {
                    if ref.isCollected {
                        if let name = ref.fileName?.lowercased() {
                            projectCollectedFiles[name, default: []].append((project.name, 0))
                        }
                    } else {
                        if let path = ref.standardizedPath {
                            externalReferencedPaths[path, default: []].insert(project.name)
                        }
                        if let name = ref.fileName?.lowercased() {
                            externalReferencedNames[name, default: []].insert(project.name)
                        }
                    }
                }
            }

            // Scan local Samples/ folder on disk for collected samples
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

            // Small breathing room every 5 projects
            if index % 5 == 0 {
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            }
        }

        if Task.isCancelled { return ([], []) }

        // Step 2: Enumerate sample library files
        onProgress(0.50, "Crawling sample library folders…")

        let libraryStandardPath = libraryURL.resolvingSymlinksInPath().standardizedFileURL.path
        let audioExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "flac", "m4a", "ogg"]

        guard let libraryEnumerator = fm.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [])
        }

        var scannedFiles: [(url: URL, relative: String, pack: String, size: Int64, modDate: Date?)] = []

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

            // Determine pack folder (top 1-2 components)
            let comps = rel.split(separator: "/")
            let packName: String
            if comps.count > 2 {
                packName = "\(comps[0])/\(comps[1])"
            } else if comps.count == 2 {
                packName = String(comps[0])
            } else {
                packName = "Root"
            }

            scannedFiles.append((fileURL, rel, packName, Int64(size), vals.contentModificationDate))
        }

        if Task.isCancelled { return ([], []) }

        // Step 3: Cross-reference
        onProgress(0.80, "Cross-referencing \(scannedFiles.count) samples against projects…")

        var auditItems: [SampleAuditItem] = []
        auditItems.reserveCapacity(scannedFiles.count)

        for (idx, item) in scannedFiles.enumerated() {
            if idx % 1000 == 0 {
                await Task.yield()
            }

            let standardPath = item.url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
            let lowerName = item.url.lastPathComponent.lowercased()

            let status: SampleUsageStatus

            if let projects = externalReferencedPaths[standardPath], !projects.isEmpty {
                status = .activeDependency(projectNames: Array(projects).sorted())
            } else if let projects = externalReferencedNames[lowerName], !projects.isEmpty {
                status = .activeDependency(projectNames: Array(projects).sorted())
            } else if let collectedProjects = projectCollectedFiles[lowerName], !collectedProjects.isEmpty {
                let matching = collectedProjects.filter { entry in
                    entry.fileSize == 0 || entry.fileSize == item.size
                }
                if !matching.isEmpty {
                    let uniqueNames = Array(Set(matching.map(\.projectName))).sorted()
                    status = .collectedInProject(projectNames: uniqueNames)
                } else {
                    status = .unused
                }
            } else {
                status = .unused
            }

            auditItems.append(SampleAuditItem(
                id: item.url.path,
                fileURL: item.url,
                fileName: item.url.lastPathComponent,
                relativePath: item.relative,
                packFolder: item.pack,
                fileSize: item.size,
                formattedSize: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                modificationDate: item.modDate,
                status: status
            ))
        }

        onProgress(1.0, "Analysis complete.")

        // Compute pack folder aggregates
        let folders = computePackFolders(from: auditItems)

        let sortedItems = auditItems.sorted { a, b in
            if a.status == .unused && b.status != .unused { return true }
            if a.status != .unused && b.status == .unused { return false }
            return a.fileSize > b.fileSize
        }

        return (sortedItems, folders)
    }

    private static func computePackFolders(from items: [SampleAuditItem]) -> [SamplePackFolder] {
        var grouped: [String: [SampleAuditItem]] = [:]
        for item in items {
            grouped[item.packFolder, default: []].append(item)
        }

        return grouped.map { path, packItems in
            let totalBytes = packItems.reduce(0) { $0 + $1.fileSize }
            let unused = packItems.filter { $0.status == .unused }
            let unusedBytes = unused.reduce(0) { $0 + $1.fileSize }
            let collectedCount = packItems.filter { if case .collectedInProject = $0.status { return true }; return false }.count
            let activeCount = packItems.filter { if case .activeDependency = $0.status { return true }; return false }.count
            let folderName = path.split(separator: "/").last.map(String.init) ?? path

            return SamplePackFolder(
                path: path,
                name: folderName,
                totalCount: packItems.count,
                totalBytes: totalBytes,
                unusedCount: unused.count,
                unusedBytes: unusedBytes,
                collectedCount: collectedCount,
                activeDependencyCount: activeCount
            )
        }.sorted { $0.unusedBytes > $1.unusedBytes }
    }

    // MARK: - Fast Substring XML Extractor (Skips 95% of Unneeded Envelopes)
    private struct ExtractedRef {
        let fileName: String?
        let standardizedPath: String?
        let relativePath: String?
        let isCollected: Bool
    }

    private static func extractSampleRefsFast(from xml: String, projectFolderURL: URL) -> [ExtractedRef] {
        // Find <Tracks> ... </Tracks> slice
        let trackSlice: Substring
        if let start = xml.range(of: "<Tracks>"),
           let end = xml.range(of: "</Tracks>", range: start.upperBound..<xml.endIndex) {
            trackSlice = xml[start.lowerBound..<end.upperBound]
        } else {
            trackSlice = xml[...]
        }

        let projectStandardPath = projectFolderURL.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()

        var results: [ExtractedRef] = []
        var searchRange = trackSlice.startIndex..<trackSlice.endIndex

        while let open = trackSlice.range(of: "<SampleRef>", range: searchRange) {
            guard let close = trackSlice.range(of: "</SampleRef>", range: open.upperBound..<trackSlice.endIndex) else {
                break
            }

            let snippet = trackSlice[open.upperBound..<close.lowerBound]

            let rawPath = extractAttributeFast("Path", in: snippet)
            let rawRel = extractAttributeFast("RelativePath", in: snippet)
            let rawName = extractAttributeFast("Name", in: snippet)

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
                isCollected: isCollected
            ))

            searchRange = close.upperBound..<trackSlice.endIndex
        }

        return results
    }

    private static func extractAttributeFast(_ attrName: String, in snippet: Substring) -> String? {
        guard let tagRange = snippet.range(of: "<\(attrName)") else { return nil }
        guard let valRange = snippet.range(of: "Value=\"", range: tagRange.upperBound..<snippet.endIndex) else { return nil }
        guard let quoteEnd = snippet.range(of: "\"", range: valRange.upperBound..<snippet.endIndex) else { return nil }
        return String(snippet[valRange.upperBound..<quoteEnd.lowerBound])
    }
}
