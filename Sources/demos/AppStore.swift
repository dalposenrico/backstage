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
    @Published var folderTree: [FolderNode] = [] {
        didSet { invalidateProjectsCache() }
    }
    @Published var expandedFolders: Set<URL> = []
    @Published var expandedCollections: Set<URL> = []
    @Published var favourites: Set<URL> = [] {
        didSet { invalidateFavouritesCache() }
    }
    @Published var hiddenProjects: Set<URL> = [] {
        didSet { invalidateVisibleProjectsCache() }
    }
    @Published var hiddenFolders: Set<URL> = [] {
        didSet { invalidateVisibleProjectsCache() }
    }
    @Published var showHidden = false {
        didSet { invalidateVisibleProjectsCache() }
    }
    @Published var exportCheckpointProject: Project?
    @Published var checkpointError: String?
    @Published private(set) var currentOpenProjectURL: URL?
    @Published private(set) var openingAbletonProject: AbletonOpeningState?
    private var openingDismissTask: Task<Void, Never>?
    private var pendingCheckpointPath: String?
    private var abletonSessionTimer: Timer?
    private var isSnappyAbletonPolling = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastAbletonLaunchRequest: Date?
    private let inspectionCache = ProjectInspectionCache()
    private var libraryWatcher: ProjectLibraryWatcher?
    private var libraryFallbackTimer: Timer?
    private var pendingLibraryChanges = Set<URL>()
    private var libraryChangeTask: Task<Void, Never>?
    private var widgetSnapshotTask: Task<Void, Never>?
    private var libraryScanID = UUID()

    nonisolated static let favoritesFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Backstage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("favorites.json")
    }()
    @Published var openProjects: [Project] = []
    @Published var selectedProject: Project? {
        didSet {
            if let project = selectedProject {
                if !openProjects.contains(where: { $0.id == project.id }) {
                    openProjects.append(project)
                }
            }
            saveSelectedProject()
            updateWidgetSnapshot()
        }
    }
    @Published var pendingProjectURLToOpen: URL?
    @Published var isScanning = false
    @Published private(set) var hasCompletedLibraryScan = false
    @Published private(set) var unavailableFolderPath: String?
    @Published private(set) var scanProgress: ProjectScanProgress?
    @Published var refreshingProjects: Set<URL> = []
    @Published var searchQuery = "" {
        didSet { invalidateFilteredProjectsCache() }
    }
    @Published var selectedCollectionURL: URL? {
        didSet {
            if let selectedCollectionURL {
                selectedSidebarSection = .folder(selectedCollectionURL)
            } else if case .folder = selectedSidebarSection {
                selectedSidebarSection = .all
            }
        }
    }
    @Published var selectedSidebarSection: SidebarSection = .all {
        didSet { invalidateFilteredProjectsCache() }
    }
    @Published var activeWorkspaceSection: WorkspaceSection = .library
    @Published var sortOrder: SortOrder = .recentlyEdited {
        didSet {
            UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder")
            invalidateFilteredProjectsCache()
        }
    }
    @Published var sortAscending = false {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: "sortAscending")
            invalidateFilteredProjectsCache()
        }
    }

    let audioPlayer = AudioPlayer()
    let comparisonAudioPlayer = ComparisonAudioPlayer()

    @Published var initialProjectInspectorSection: String? = nil
    @Published var isVersionsTabActive = false

    // MARK: - Tab Navigation Helpers

    func selectProjectTab(_ project: Project) {
        if !openProjects.contains(where: { $0.id == project.id }) {
            openProjects.append(project)
        }
        if selectedProject?.id != project.id || activeWorkspaceSection != .project {
            selectedProject = project
            activeWorkspaceSection = .project
        }
    }

    func openProjectTab(_ project: Project) {
        if !openProjects.contains(where: { $0.id == project.id }) {
            openProjects.append(project)
        }
        selectedProject = project
        activeWorkspaceSection = .project
    }

    func openProjectMixer(_ project: Project) {
        openProjectTab(project)
    }

    func closeProjectTab(_ project: Project? = nil) {
        let toClose = project ?? selectedProject
        guard let toClose else {
            activeWorkspaceSection = .library
            selectedProject = nil
            return
        }
        if let idx = openProjects.firstIndex(where: { $0.id == toClose.id }) {
            openProjects.remove(at: idx)
        }
        if selectedProject?.id == toClose.id {
            if let next = openProjects.last {
                selectedProject = next
                activeWorkspaceSection = .project
            } else {
                selectedProject = nil
                activeWorkspaceSection = .library
            }
        }
    }

    func closeOtherProjectTabs(keeping project: Project) {
        openProjects = [project]
        selectedProject = project
        activeWorkspaceSection = .project
    }

    // MARK: - Memoized Project Lists
    private var _cachedProjects: [Project]?
    private var _cachedVisibleProjects: [Project]?
    private var _cachedRecentProjects: [Project]?
    private var _cachedRecentDashboardProjects: [Project]?
    private var _cachedFavouriteProjects: [Project]?
    private var _cachedFilteredProjects: [Project]?

    func invalidateProjectsCache() {
        _cachedProjects = nil
        invalidateVisibleProjectsCache()
    }

    func invalidateVisibleProjectsCache() {
        _cachedVisibleProjects = nil
        _cachedRecentProjects = nil
        _cachedRecentDashboardProjects = nil
        _cachedFavouriteProjects = nil
        invalidateFilteredProjectsCache()
    }

    func invalidateFavouritesCache() {
        _cachedFavouriteProjects = nil
        invalidateFilteredProjectsCache()
    }

    func invalidateFilteredProjectsCache() {
        _cachedFilteredProjects = nil
    }

    // Flat list of all projects, derived from tree (memoized)
    var projects: [Project] {
        if let cached = _cachedProjects { return cached }
        let list = folderTree.flatMap { $0.allProjects() }
        _cachedProjects = list
        return list
    }

    var visibleProjects: [Project] {
        if let cached = _cachedVisibleProjects { return cached }
        let all = projects
        let list = showHidden ? all : all.filter { !isProjectHidden($0) }
        _cachedVisibleProjects = list
        return list
    }

    var recentProjects: [Project] {
        if let cached = _cachedRecentProjects { return cached }
        let list = visibleProjects
            .filter { $0.latestModification != .distantPast }
            .sorted { $0.latestModification > $1.latestModification }
            .prefix(5)
            .map { $0 }
        _cachedRecentProjects = list
        return list
    }

    var recentDashboardProjects: [Project] {
        if let cached = _cachedRecentDashboardProjects { return cached }
        let list = visibleProjects
            .filter { $0.latestModification != .distantPast }
            .sorted { $0.latestModification > $1.latestModification }
            .prefix(15)
            .map { $0 }
        _cachedRecentDashboardProjects = list
        return list
    }

    var favouriteProjects: [Project] {
        if let cached = _cachedFavouriteProjects { return cached }
        let list = visibleProjects.filter { favourites.contains($0.folderURL) }
        _cachedFavouriteProjects = list
        return list
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

    // Filtered + sorted flat list (used during search and for playback ordering, memoized)
    var filteredProjects: [Project] {
        if let cached = _cachedFilteredProjects { return cached }
        let baseList: [Project]
        switch selectedSidebarSection {
        case .all:
            baseList = visibleProjects
        case .recents:
            baseList = visibleProjects
                .filter { $0.latestModification != .distantPast }
                .sorted { $0.latestModification > $1.latestModification }
        case .favorites:
            baseList = favouriteProjects
        case .folder(let collectionURL):
            baseList = folderTree.findNode(at: collectionURL)?.allProjects() ?? visibleProjects
        }

        let visibleCollectionProjects = showHidden
            ? baseList
            : baseList.filter { !isProjectHidden($0) }
        let base = searchQuery.isEmpty ? visibleCollectionProjects : visibleCollectionProjects.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
        let result: [Project]
        switch sortOrder {
        case .recentlyEdited:
            result = sorted(base, value: { $0.latestModification })
        case .name:
            result = base.sorted {
                let r = $0.name.localizedCompare($1.name)
                return sortAscending ? r == .orderedAscending : r == .orderedDescending
            }
        case .dateAdded:
            result = sortedOptional(base, value: { $0.creationDate })
        case .activity:
            result = sortedOptional(base, value: { $0.activity.backupCount > 0 ? $0.activity.activityPercent : nil })
        case .bpm:
            result = sortedOptional(base, value: { $0.bpm })
        case .work:
            result = sortedOptional(base, value: { $0.activity.estimatedWorkTime > 0 ? $0.activity.estimatedWorkTime : nil })
        }
        _cachedFilteredProjects = result
        return result
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
        openProjects = openProjects.compactMap { op in
            all.first { $0.folderURL == op.folderURL }
        }

        // Detect running Ableton session now that projects are available
        refreshAbletonSession()

        if let pending = pendingProjectURLToOpen, let match = all.first(where: { $0.folderURL == pending }) {
            openInMainWindow(match)
            pendingProjectURLToOpen = nil
        } else if let activeSession = currentOpenProject {
            // Live already has a session open! Prioritize the active DAW session
            selectedProject = activeSession
            if audioPlayer.currentTrack == nil, let track = activeSession.primaryTrack {
                audioPlayer.prepare(track, autoPlay: false)
            }
        } else {
            let savedPath = UserDefaults.standard.string(forKey: "selectedProjectPath")
            if let path = savedPath, let match = all.first(where: { $0.folderURL.path == path }) {
                selectedProject = match
            } else if selectedProject == nil || !all.contains(where: { $0.id == selectedProject?.id }) {
                selectedProject = all.first
            }
            if audioPlayer.currentTrack == nil, let track = selectedProject?.primaryTrack {
                audioPlayer.prepare(track, autoPlay: false)
            }
        }

        resolvePendingExportCheckpoint(reportFailure: true)
        updateWidgetSnapshot()

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

    func dismissAbletonOpeningAlert() {
        openingDismissTask?.cancel()
        openingDismissTask = nil
        openingAbletonProject = nil
        startAbletonPolling(snappy: false)
    }

    func openAndExport(_ project: Project, version: AbletonVersion? = nil) {
        let targetVersion = version ?? project.newestAbletonVersion
        let isSameOrLatestVersion = version == nil || version?.url == project.newestAbletonVersion?.url

        // If this project is ALREADY the current open session in Ableton Live:
        let isAlreadyActive: Bool = {
            if isSameOrLatestVersion && isCurrentOpenProject(project) {
                return true
            }
            if isSameOrLatestVersion {
                let snapshot = AbletonSessionDetector.snapshot()
                if snapshot.isRunning,
                   let match = AbletonSessionDetector.activeProject(
                       in: [project],
                       windowTitles: snapshot.windowTitles,
                       loadedDocumentURLs: snapshot.loadedDocumentURLs
                   ), match.folderURL == project.folderURL {
                    setCurrentOpenProject(project.folderURL)
                    return true
                }
            }
            return false
        }()

        if isAlreadyActive {
            _ = AbletonSessionDetector.activateAbleton()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                GlobalHotkeyManager.shared?.triggerExport()
            }
            return
        }

        // If not already active, launch project with autoExportOnReady
        openInAbleton(project, version: targetVersion, autoExportOnReady: true)
    }

    func openInAbleton(_ project: Project, version: AbletonVersion? = nil, autoExportOnReady: Bool = false) {
        let targetVersion = version ?? project.newestAbletonVersion

        // If this project is ALREADY the current open session in Ableton Live,
        // do not reopen the set file (which triggers Ableton to reload/re-ask to save);
        // simply bring Ableton Live to the foreground.
        let isSameOrLatestVersion = version == nil || version?.url == project.newestAbletonVersion?.url
        if isSameOrLatestVersion && isCurrentOpenProject(project) {
            if AbletonSessionDetector.activateAbleton() {
                if autoExportOnReady {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        GlobalHotkeyManager.shared?.triggerExport()
                    }
                }
                return
            }
        } else if isSameOrLatestVersion {
            // Live snapshot check in case periodic poll has not updated currentOpenProjectURL yet
            let snapshot = AbletonSessionDetector.snapshot()
            if snapshot.isRunning,
               let match = AbletonSessionDetector.activeProject(
                   in: [project],
                   windowTitles: snapshot.windowTitles,
                   loadedDocumentURLs: snapshot.loadedDocumentURLs
               ),
               match.folderURL == project.folderURL {
                setCurrentOpenProject(project.folderURL)
                if AbletonSessionDetector.activateAbleton() {
                    if autoExportOnReady {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            GlobalHotkeyManager.shared?.triggerExport()
                        }
                    }
                    return
                }
            }
        }

        guard let targetVersion else { return }

        // If this exact project is already opening, bring Ableton to front and avoid duplicate launch
        if let opening = openingAbletonProject,
           opening.phase == .opening,
           opening.matchesLoadedProject(folderURL: project.folderURL) {
            if autoExportOnReady && !opening.autoExportOnReady {
                openingAbletonProject?.autoExportOnReady = true
            }
            _ = AbletonSessionDetector.activateAbleton()
            return
        }

        openingDismissTask?.cancel()
        openingDismissTask = nil

        let now = Date()
        openingAbletonProject = AbletonOpeningState(
            projectID: project.id,
            folderURL: project.folderURL,
            projectName: project.name,
            targetVersionURL: targetVersion.url,
            startedAt: now,
            phase: .opening,
            autoExportOnReady: autoExportOnReady
        )
        lastAbletonLaunchRequest = now

        startAbletonPolling(snappy: true)
        AbletonAppDetector.openALS(at: targetVersion.url)
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

    private func startAbletonPolling(snappy: Bool = false) {
        if abletonSessionTimer != nil && isSnappyAbletonPolling == snappy { return }
        stopAbletonPolling()
        isSnappyAbletonPolling = snappy
        let interval: TimeInterval = snappy ? 0.75 : 2.5
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAbletonSession() }
        }
        RunLoop.main.add(timer, forMode: .common)
        abletonSessionTimer = timer
    }

    private func stopAbletonPolling() {
        abletonSessionTimer?.invalidate()
        abletonSessionTimer = nil
        isSnappyAbletonPolling = false
    }

    private func setCurrentOpenProject(_ url: URL?) {
        guard currentOpenProjectURL != url else { return }
        currentOpenProjectURL = url
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = url != nil ? "●" : nil
        }
    }

    private func refreshAbletonSession() {
        let snapshot = AbletonSessionDetector.snapshot()
        let now = Date()

        if let opening = openingAbletonProject, opening.phase == .opening {
            var isLoaded = false
            if snapshot.isRunning {
                if let match = AbletonSessionDetector.activeProject(
                    in: projects,
                    windowTitles: snapshot.windowTitles,
                    loadedDocumentURLs: snapshot.loadedDocumentURLs
                ), opening.matchesLoadedProject(folderURL: match.folderURL) {
                    isLoaded = true
                    setCurrentOpenProject(match.folderURL)
                }
            }

            if isLoaded {
                let shouldAutoExport = opening.autoExportOnReady
                openingAbletonProject?.phase = .loaded
                let projectName = opening.projectName
                if UserDefaults.standard.object(forKey: "notifyOnAbletonReady") as? Bool ?? true {
                    SystemNotifier.post(
                        title: "goodvibrations HQ",
                        message: shouldAutoExport
                            ? "\"\(projectName)\" loaded — starting version export…"
                            : "\"\(projectName)\" is ready in Ableton Live."
                    )
                }
                openingDismissTask?.cancel()
                openingDismissTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(1400))
                    guard !Task.isCancelled else { return }
                    self?.openingAbletonProject = nil
                    self?.startAbletonPolling(snappy: false)
                }

                if shouldAutoExport {
                    Task { @MainActor in
                        // Brief settle window so Ableton finishes updating UI and release document lock
                        try? await Task.sleep(for: .milliseconds(1200))
                        _ = AbletonSessionDetector.activateAbleton()
                        try? await Task.sleep(for: .milliseconds(350))
                        GlobalHotkeyManager.shared?.triggerExport()
                    }
                }
            } else if opening.hasTimedOut(at: now, timeoutInterval: 60) {
                openingAbletonProject = nil
            }
        }

        guard snapshot.isRunning else {
            if openingAbletonProject == nil {
                stopAbletonPolling()
            }
            if lastAbletonLaunchRequest.map({ now.timeIntervalSince($0) >= 12 }) ?? true {
                setCurrentOpenProject(nil)
            }
            return
        }

        startAbletonPolling(snappy: openingAbletonProject?.phase == .opening)

        // Don't attempt project resolution if projects have not been scanned yet
        guard !projects.isEmpty else { return }

        if let match = AbletonSessionDetector.activeProject(
            in: projects,
            windowTitles: snapshot.windowTitles,
            loadedDocumentURLs: snapshot.loadedDocumentURLs
        ) {
            let isNewSession = currentOpenProjectURL != match.folderURL
            setCurrentOpenProject(match.folderURL)
            if isNewSession {
                // If a new session became active and the player is not actively playing something else,
                // keep the app focused on the active DAW project and prepare its latest export
                if audioPlayer.currentTrack == nil || !audioPlayer.isPlaying {
                    selectedProject = match
                    if let track = match.primaryTrack {
                        audioPlayer.prepare(track, autoPlay: false)
                    }
                }
            }
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
        if let idx = openProjects.firstIndex(where: { $0.folderURL == refreshed.folderURL }) {
            openProjects[idx] = refreshed
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

    private var saveCollectionsTask: Task<Void, Never>?

    func toggleCollectionExpansion(_ url: URL) {
        if expandedCollections.contains(url) { expandedCollections.remove(url) }
        else { expandedCollections.insert(url) }
        saveCollectionsTask?.cancel()
        saveCollectionsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.saveExpandedCollections()
        }
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
        if showHidden || hiddenProjects.isEmpty {
            return node.projectCount
        }
        return node.cachedProjects.filter { !isProjectHidden($0) }.count
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
        updateWidgetSnapshot()
    }

    func playTrack(_ track: Track) {
        audioPlayer.play(track)
    }

    func openProjectWhenAvailable(folderURL: URL) {
        if let project = projects.first(where: { $0.folderURL == folderURL }) {
            openInMainWindow(project)
        } else {
            pendingProjectURLToOpen = folderURL
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func updateWidgetSnapshot() {
        widgetSnapshotTask?.cancel()
        let recents = recentProjects
        let active = selectedProject ?? recents.first
        let favs = favouriteProjects
        let allProjectsCount = projects.count
        let favURLs = favourites

        widgetSnapshotTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let activeSummary: WidgetProjectSummary? = active.map { project in
                WidgetProjectSummary(
                    name: project.name,
                    path: project.folderURL.path,
                    alsPath: project.newestAbletonVersion?.url.path,
                    lastModified: project.latestModification,
                    bpm: project.bpm,
                    musicalKey: project.key,
                    trackName: project.sortedTracks.first?.displayName,
                    isFavorite: favURLs.contains(project.folderURL)
                )
            }

            let recentSummaries = recents.prefix(5).map { project in
                WidgetProjectSummary(
                    name: project.name,
                    path: project.folderURL.path,
                    alsPath: project.newestAbletonVersion?.url.path,
                    lastModified: project.latestModification,
                    bpm: project.bpm,
                    musicalKey: project.key,
                    trackName: project.sortedTracks.first?.displayName,
                    isFavorite: favURLs.contains(project.folderURL)
                )
            }

            let favoriteSummaries = favs.prefix(5).map { project in
                WidgetProjectSummary(
                    name: project.name,
                    path: project.folderURL.path,
                    alsPath: project.newestAbletonVersion?.url.path,
                    lastModified: project.latestModification,
                    bpm: project.bpm,
                    musicalKey: project.key,
                    trackName: project.sortedTracks.first?.displayName,
                    isFavorite: true
                )
            }

            let snapshot = WidgetSnapshotData(
                updatedAt: Date(),
                lastActiveProject: activeSummary,
                recentProjects: Array(recentSummaries),
                favoriteProjects: Array(favoriteSummaries),
                totalProjectsCount: allProjectsCount
            )

            WidgetDataStorage.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "BackstageWidget")
        }
    }

    func openInMainWindow(_ project: Project) {
        let target = projects.first(where: { $0.folderURL == project.folderURL }) ?? project
        openProjectTab(target)
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
