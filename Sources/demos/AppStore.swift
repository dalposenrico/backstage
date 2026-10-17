import Foundation
import AppKit
import WidgetKit

enum SortOrder: String, CaseIterable {
    case recentlyEdited = "Recently Edited"
    case name = "Name"
    case dateAdded = "Date Added"
    case activity = "Activity"
    case bpm = "BPM"
    case work = "Estimated Work"
}

enum LibraryLoadPresentation: Equatable {
    case chooseFolder
    case unavailable(folderName: String)
    case loading(folderName: String)
    case updating(folderName: String)
    case noProjects(folderName: String)
    case ready

    static func resolve(
        rootFolderURL: URL?,
        unavailableFolderPath: String?,
        isScanning: Bool,
        hasCompletedScan: Bool,
        projectCount: Int
    ) -> LibraryLoadPresentation {
        if let unavailableFolderPath, rootFolderURL == nil {
            return .unavailable(folderName: URL(fileURLWithPath: unavailableFolderPath).lastPathComponent)
        }
        guard let rootFolderURL else { return .chooseFolder }
        let name = rootFolderURL.lastPathComponent
        if isScanning { return projectCount > 0 ? .updating(folderName: name) : .loading(folderName: name) }
        if projectCount > 0 { return .ready }
        return hasCompletedScan ? .noProjects(folderName: name) : .loading(folderName: name)
    }
}

@MainActor
class AppStore: ObservableObject {
    @Published var rootFolderURL: URL?
    @Published var folderTree: [FolderNode] = []
    @Published var expandedFolders: Set<URL> = []
    @Published var expandedCollections: Set<URL> = []
    @Published var favourites: Set<URL> = []
    @Published var hiddenProjects: Set<URL> = []
    @Published var hiddenFolders: Set<URL> = []
    @Published var showHidden = false
    @Published var exportCheckpointProject: Project?
    @Published var checkpointError: String?
    @Published private(set) var currentOpenProjectURL: URL?
    private var pendingCheckpointPath: String?
    private var abletonSessionTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastAbletonLaunchRequest: Date?
    private let inspectionCache = ProjectInspectionCache()
    private var libraryWatcher: ProjectLibraryWatcher?
    private var libraryFallbackTimer: Timer?
    private var pendingLibraryChanges = Set<URL>()
    private var libraryChangeTask: Task<Void, Never>?
    private var libraryScanID = UUID()

    nonisolated static let favoritesFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Backstage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }()
    @Published var selectedProject: Project? {
        didSet { saveSelectedProject() }
    }
    @Published var isScanning = false
    @Published private(set) var hasCompletedLibraryScan = false
    @Published private(set) var unavailableFolderPath: String?
    @Published private(set) var scanProgress: ProjectScanProgress?
    @Published var refreshingProjects: Set<URL> = []
    @Published var searchQuery = ""
    @Published var selectedCollectionURL: URL?
    @Published var sortOrder: SortOrder = .recentlyEdited {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }
    @Published var sortAscending = false {
        didSet { UserDefaults.standard.set(sortAscending, forKey: "sortAscending") }
    }

    let audioPlayer = AudioPlayer()

    // Flat list of all projects, derived from tree
    var projects: [Project] {
        folderTree.flatMap { $0.allProjects() }
    }

    var visibleProjects: [Project] {
        showHidden ? projects : projects.filter { !isProjectHidden($0) }
    }

    var recentProjects: [Project] {
        visibleProjects
            .filter { $0.latestModification != .distantPast }
            .sorted { $0.latestModification > $1.latestModification }
            .prefix(5)
            .map { $0 }
    }

    var favouriteProjects: [Project] {
        visibleProjects.filter { favourites.contains($0.folderURL) }
    }

    var libraryLoadPresentation: LibraryLoadPresentation {
        .resolve(
            rootFolderURL: rootFolderURL,
            unavailableFolderPath: unavailableFolderPath,
            isScanning: isScanning,
            hasCompletedScan: hasCompletedLibraryScan,
            projectCount: projects.count
        )
    }

    // Filtered + sorted flat list (used during search and for playback ordering)
    var filteredProjects: [Project] {
        let collectionProjects = selectedCollectionURL.flatMap { collectionURL in
            folderTree.findNode(at: collectionURL)?.allProjects()
        } ?? visibleProjects
        let visibleCollectionProjects = showHidden
            ? collectionProjects
            : collectionProjects.filter { !isProjectHidden($0) }
        let base = searchQuery.isEmpty ? visibleCollectionProjects : visibleCollectionProjects.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
        switch sortOrder {
        case .recentlyEdited:
            return sorted(base, value: { $0.latestModification })
        case .name:
            return base.sorted {
                let result = $0.name.localizedCompare($1.name)
                return sortAscending ? result == .orderedAscending : result == .orderedDescending
            }
        case .dateAdded:
            return sortedOptional(base, value: { $0.creationDate })
        case .activity:
            return sortedOptional(base, value: { $0.activity.backupCount > 0 ? $0.activity.activityPercent : nil })
        case .bpm:
            return sortedOptional(base, value: { $0.bpm })
        case .work:
            return sortedOptional(base, value: { $0.activity.estimatedWorkTime > 0 ? $0.activity.estimatedWorkTime : nil })
        }
    }

    private func sorted<T: Comparable>(_ projects: [Project], value: (Project) -> T) -> [Project] {
        projects
            .map { (project: $0, value: value($0)) }
            .sorted { sortAscending ? $0.value < $1.value : $0.value > $1.value }
            .map(\.project)
    }

    private func sortedOptional<T: Comparable>(_ projects: [Project], value: (Project) -> T?) -> [Project] {
        projects
            .map { (project: $0, value: value($0)) }
            .sorted { lhs, rhs in
            switch (lhs.value, rhs.value) {
            case let (left?, right?): return sortAscending ? left < right : left > right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.project.name.localizedCompare(rhs.project.name) == .orderedAscending
            }
            }
            .map(\.project)
    }

    init() {
        // Restore sort order
        if let raw = UserDefaults.standard.string(forKey: "sortOrder"),
           let saved = SortOrder(rawValue: raw) {
            sortOrder = saved
        }
        if UserDefaults.standard.object(forKey: "sortAscending") != nil {
            sortAscending = UserDefaults.standard.bool(forKey: "sortAscending")
        } else {
            sortAscending = sortOrder == .name
        }

        loadFavourites()
        hiddenProjects = loadURLSet(key: "hiddenProjectPaths")
        hiddenFolders = loadURLSet(key: "hiddenFolderPaths")
        if let paths = UserDefaults.standard.stringArray(forKey: "expandedCollectionPaths") {
            expandedCollections = Set(paths.map { URL(fileURLWithPath: $0) })
        }

        if let path = UserDefaults.standard.string(forKey: "rootFolderPath") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                rootFolderURL = url
                startLibraryUpdates(for: url)
                let requestID = UUID()
                libraryScanID = requestID
                isScanning = true
                scanProgress = ProjectScanProgress(currentFolder: url.lastPathComponent, foldersScanned: 0, projectsFound: 0)
                Task { await performScan(root: url, requestID: requestID) }
            } else {
                unavailableFolderPath = path
            }
        }

        refreshAbletonSession()
        observeAbletonLifecycle()

        // The library watcher already reports changes; this is only a slow safety
        // net for the cases FSEvents cannot see.
        let fallbackTimer = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.scan() }
        }
        RunLoop.main.add(fallbackTimer, forMode: .common)
        libraryFallbackTimer = fallbackTimer
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your music projects folder"
        panel.prompt = "Open"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.unavailableFolderPath = nil
                self?.rootFolderURL = url
                self?.hasCompletedLibraryScan = false
                UserDefaults.standard.set(url.path, forKey: "rootFolderPath")
                self?.startLibraryUpdates(for: url)
                await self?.scan(forceRestart: true)
            }
        }
    }

    func scan(forceRestart: Bool = false) async {
        guard let root = rootFolderURL else { return }
        guard !isScanning || forceRestart else { return }
        let requestID = UUID()
        libraryScanID = requestID
        isScanning = true
        scanProgress = ProjectScanProgress(currentFolder: root.lastPathComponent, foldersScanned: 0, projectsFound: 0)
        await performScan(root: root, requestID: requestID)
    }

    private func performScan(root: URL, requestID: UUID) async {
        inspectionCache.beginScan()
        let tree = await ProjectScanner.scan(root: root, cache: inspectionCache) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self,
                      self.libraryScanID == requestID,
                      self.isScanning else { return }
                self.scanProgress = progress
            }
        }
        guard libraryScanID == requestID, rootFolderURL == root else { return }
        folderTree = tree
        isScanning = false
        scanProgress = nil
        hasCompletedLibraryScan = true

        // Restore expanded folders, fall back to auto-expanding top-level on first launch
        if let savedPaths = UserDefaults.standard.stringArray(forKey: "expandedFolderPaths") {
            expandedFolders = Set(savedPaths.map { URL(fileURLWithPath: $0) })
        } else {
            expandedFolders = Set(tree.filter { !$0.isProject }.map { $0.url })
        }

        // Restore selected project by saved path, fall back to first project
        let all = tree.flatMap { $0.allProjects() }
        let savedPath = UserDefaults.standard.string(forKey: "selectedProjectPath")
        if let path = savedPath, let match = all.first(where: { $0.folderURL.path == path }) {
            selectedProject = match
        } else if selectedProject == nil || !all.contains(where: { $0.id == selectedProject?.id }) {
            selectedProject = all.first
        }

        resolvePendingExportCheckpoint(reportFailure: true)
        refreshAbletonSession()

        let cache = inspectionCache
        Task.detached(priority: .utility) { cache.persistIfNeeded() }
    }

    private func startLibraryUpdates(for rootURL: URL) {
        libraryChangeTask?.cancel()
        pendingLibraryChanges.removeAll()
        let watcher = ProjectLibraryWatcher()
        watcher.start(watching: rootURL) { [weak self] changedURLs in
            Task { @MainActor [weak self] in self?.scheduleLibraryRefresh(for: changedURLs) }
        }
        libraryWatcher?.stop()
        libraryWatcher = watcher
    }

    private func scheduleLibraryRefresh(for changedURLs: [URL]) {
        pendingLibraryChanges.formUnion(changedURLs)
        libraryChangeTask?.cancel()
        libraryChangeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.applyPendingLibraryChanges()
        }
    }

    private func applyPendingLibraryChanges() async {
        guard let rootFolderURL else { return }
        let changedURLs = Array(pendingLibraryChanges)
        pendingLibraryChanges.removeAll()
        guard let projectFolders = ProjectLibraryChangeRouter.projectFoldersToRefresh(
            changedURLs: changedURLs,
            projectFolderURLs: projects.map(\.folderURL),
            rootURL: rootFolderURL
        ) else {
            await scan()
            return
        }

        for projectFolder in projectFolders {
            guard let project = projects.first(where: { $0.folderURL == projectFolder }) else { continue }
            await refreshProject(project)
        }
    }

    var currentOpenProject: Project? {
        guard let currentOpenProjectURL else { return nil }
        return projects.first { $0.folderURL == currentOpenProjectURL }
    }

    func isCurrentOpenProject(_ project: Project) -> Bool {
        currentOpenProjectURL == project.folderURL
    }

    func openInAbleton(_ project: Project, version: AbletonVersion? = nil) {
        guard let version = version ?? project.newestAbletonVersion else { return }
        setCurrentOpenProject(project.folderURL)
        lastAbletonLaunchRequest = Date()
        NSWorkspace.shared.open(version.url)
    }

    /// Watching Live's windows costs a window-server round trip, so it is only
    /// worth doing while Live is actually open. Launching or quitting Live starts
    /// and stops the poll instead of leaving it running for the whole session.
    private func observeAbletonLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAbletonSession() }
            })
        }
    }

    private func startAbletonPolling() {
        guard abletonSessionTimer == nil else { return }
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAbletonSession() }
        }
        RunLoop.main.add(timer, forMode: .common)
        abletonSessionTimer = timer
    }

    private func stopAbletonPolling() {
        abletonSessionTimer?.invalidate()
        abletonSessionTimer = nil
    }

    private func setCurrentOpenProject(_ url: URL?) {
        guard currentOpenProjectURL != url else { return }
        currentOpenProjectURL = url
    }

    private func refreshAbletonSession() {
        let snapshot = AbletonSessionDetector.snapshot()
        guard snapshot.isRunning else {
            stopAbletonPolling()
            if lastAbletonLaunchRequest.map({ Date().timeIntervalSince($0) >= 12 }) ?? true {
                setCurrentOpenProject(nil)
            }
            return
        }
        startAbletonPolling()
        if let match = AbletonSessionDetector.activeProject(
            in: projects,
            windowTitles: snapshot.windowTitles,
            loadedDocumentURLs: snapshot.loadedDocumentURLs
        ) {
            setCurrentOpenProject(match.folderURL)
        } else if !snapshot.windowTitles.isEmpty || !snapshot.loadedDocumentURLs.isEmpty {
            setCurrentOpenProject(nil)
        }
    }

    func openExportCheckpoint(from url: URL) {
        guard url.scheme?.lowercased() == "goodvibrations",
              url.host?.lowercased() == "checkpoint",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else {
            checkpointError = "The export checkpoint link did not include a project path."
            return
        }

        pendingCheckpointPath = URL(fileURLWithPath: path).standardizedFileURL.path
        NSApp.activate(ignoringOtherApps: true)
        resolvePendingExportCheckpoint(
            reportFailure: !isScanning && (rootFolderURL == nil || !projects.isEmpty)
        )
    }

    private func resolvePendingExportCheckpoint(reportFailure: Bool) {
        guard let targetPath = pendingCheckpointPath else { return }
        let candidates = projects.filter { project in
            let folderPath = project.folderURL.standardizedFileURL.path
            return targetPath == folderPath || targetPath.hasPrefix(folderPath + "/")
        }

        if let project = candidates.max(by: { $0.folderURL.path.count < $1.folderURL.path.count }) {
            pendingCheckpointPath = nil
            selectedProject = project
            exportCheckpointProject = project
        } else if reportFailure {
            pendingCheckpointPath = nil
            checkpointError = "No scanned project contains \(URL(fileURLWithPath: targetPath).lastPathComponent). Refresh the library or check the path sent by Keyboard Maestro."
        }
    }

    func refreshProject(_ project: Project) async {
        guard !refreshingProjects.contains(project.folderURL) else { return }
        refreshingProjects.insert(project.folderURL)
        defer { refreshingProjects.remove(project.folderURL) }

        guard let refreshed = await ProjectScanner.scanProject(
            at: project.folderURL,
            cache: inspectionCache
        ) else { return }
        folderTree = folderTree.map { $0.replacingProject(refreshed) }
        if selectedProject?.folderURL == refreshed.folderURL {
            selectedProject = refreshed
        }

        let cache = inspectionCache
        Task.detached(priority: .utility) { cache.persistIfNeeded() }
    }

    func toggleExpansion(_ url: URL) {
        if expandedFolders.contains(url) {
            expandedFolders.remove(url)
        } else {
            expandedFolders.insert(url)
        }
        saveExpandedFolders()
    }

    func toggleCollectionExpansion(_ url: URL) {
        if expandedCollections.contains(url) { expandedCollections.remove(url) }
        else { expandedCollections.insert(url) }
        saveExpandedCollections()
    }

    func collapseAllCollections() {
        expandedCollections = []
        saveExpandedCollections()
    }

    func expandAllCollections() {
        var urls = Set<URL>()
        func collect(_ nodes: [FolderNode]) {
            for node in nodes where !node.isProject {
                if node.children.contains(where: { !$0.isProject }) { urls.insert(node.url) }
                collect(node.children)
            }
        }
        collect(folderTree)
        expandedCollections = urls
        saveExpandedCollections()
    }

    private func saveExpandedCollections() {
        UserDefaults.standard.set(expandedCollections.map(\.path), forKey: "expandedCollectionPaths")
    }

    func collapseAll() {
        expandedFolders = []
        saveExpandedFolders()
    }

    func expandAll() {
        var allURLs = Set<URL>()
        func collect(_ nodes: [FolderNode]) {
            for node in nodes where !node.isProject {
                allURLs.insert(node.url)
                collect(node.children)
            }
        }
        collect(folderTree)
        expandedFolders = allURLs
        saveExpandedFolders()
    }

    func toggleSort(_ order: SortOrder) {
        if sortOrder == order {
            sortAscending.toggle()
        } else {
            sortOrder = order
            sortAscending = order == .name
        }
    }

    private func saveExpandedFolders() {
        UserDefaults.standard.set(expandedFolders.map(\.path), forKey: "expandedFolderPaths")
    }

    private func saveSelectedProject() {
        UserDefaults.standard.set(selectedProject?.folderURL.path, forKey: "selectedProjectPath")
    }

    func toggleFavourite(_ project: Project) {
        if favourites.contains(project.folderURL) {
            favourites.remove(project.folderURL)
        } else {
            favourites.insert(project.folderURL)
        }
        saveFavourites()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func isFolderHidden(_ url: URL) -> Bool {
        hiddenFolders.contains(url)
    }

    func isProjectHidden(_ project: Project) -> Bool {
        hiddenProjects.contains(project.folderURL) || hiddenFolders.contains { folder in
            project.folderURL.path == folder.path || project.folderURL.path.hasPrefix(folder.path + "/")
        }
    }

    func toggleProjectHidden(_ project: Project) {
        if isProjectHidden(project) {
            hiddenProjects.remove(project.folderURL)
            hiddenFolders = hiddenFolders.filter { folder in
                !(project.folderURL.path == folder.path || project.folderURL.path.hasPrefix(folder.path + "/"))
            }
            saveURLSet(hiddenFolders, key: "hiddenFolderPaths")
        } else {
            hiddenProjects.insert(project.folderURL)
        }
        saveURLSet(hiddenProjects, key: "hiddenProjectPaths")
    }

    func toggleFolderHidden(_ url: URL) {
        if hiddenFolders.contains(url) { hiddenFolders.remove(url) }
        else { hiddenFolders.insert(url) }
        saveURLSet(hiddenFolders, key: "hiddenFolderPaths")
    }

    func visibleProjectCount(in node: FolderNode) -> Int {
        showHidden ? node.projectCount : node.allProjects().filter { !isProjectHidden($0) }.count
    }

    private func loadURLSet(key: String) -> Set<URL> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) })
    }

    private func saveURLSet(_ urls: Set<URL>, key: String) {
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
    }

    private func loadFavourites() {
        guard let data = try? Data(contentsOf: Self.favoritesFileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return }
        favourites = Set(paths.map { URL(fileURLWithPath: $0) })
    }

    private func saveFavourites() {
        let paths = favourites.map(\.path)
        if let data = try? JSONEncoder().encode(paths) {
            try? data.write(to: Self.favoritesFileURL)
        }
    }

    func playTrack(_ track: Track) {
        audioPlayer.play(track)
    }

    func openInMainWindow(_ project: Project) {
        selectedProject = projects.first(where: { $0.folderURL == project.folderURL }) ?? project
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: { $0.canBecomeMain && !($0 is NSPanel) })?
            .makeKeyAndOrderFront(nil)
    }

    func playNext() {
        guard let current = audioPlayer.currentTrack else { return }
        let all = filteredProjects.flatMap(\.sortedTracks)
        if let idx = all.firstIndex(where: { $0.id == current.id }), idx + 1 < all.count {
            let next = all[idx + 1]
            audioPlayer.play(next)
            selectedProject = projects.first { $0.tracks.contains { $0.id == next.id } }
        }
    }

    func playPrevious() {
        guard let current = audioPlayer.currentTrack else { return }
        if audioPlayer.currentTime > 3 { audioPlayer.seek(to: 0); return }
        let all = filteredProjects.flatMap(\.sortedTracks)
        if let idx = all.firstIndex(where: { $0.id == current.id }), idx > 0 {
            let prev = all[idx - 1]
            audioPlayer.play(prev)
            selectedProject = projects.first { $0.tracks.contains { $0.id == prev.id } }
        }
    }
}
