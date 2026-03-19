import Foundation
import AppKit

enum SortOrder: String, CaseIterable {
    case recentlyEdited = "Recently Edited"
    case name = "Name"
    case dateAdded = "Date Added"
}

@MainActor
class AppStore: ObservableObject {
    @Published var rootFolderURL: URL?
    @Published var folderTree: [FolderNode] = []
    @Published var expandedFolders: Set<URL> = []
    @Published var selectedProject: Project? {
        didSet { saveSelectedProject() }
    }
    @Published var isScanning = false
    @Published var searchQuery = ""
    @Published var sortOrder: SortOrder = .recentlyEdited {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }

    let audioPlayer = AudioPlayer()

    // Flat list of all projects, derived from tree
    var projects: [Project] {
        folderTree.flatMap { $0.allProjects() }
    }

    // Filtered + sorted flat list (used during search and for playback ordering)
    var filteredProjects: [Project] {
        let base = searchQuery.isEmpty ? projects : projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery)
        }
        switch sortOrder {
        case .recentlyEdited:
            return base.sorted { $0.latestModification > $1.latestModification }
        case .name:
            return base.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .dateAdded:
            return base.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
    }

    init() {
        // Restore sort order
        if let raw = UserDefaults.standard.string(forKey: "sortOrder"),
           let saved = SortOrder(rawValue: raw) {
            sortOrder = saved
        }

        if let path = UserDefaults.standard.string(forKey: "rootFolderPath") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                rootFolderURL = url
                Task { await scan() }
            }
        }
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
                self?.rootFolderURL = url
                UserDefaults.standard.set(url.path, forKey: "rootFolderPath")
                await self?.scan()
            }
        }
    }

    func scan() async {
        guard let root = rootFolderURL else { return }
        isScanning = true
        let tree = await ProjectScanner.scan(root: root)
        folderTree = tree
        isScanning = false

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
    }

    func toggleExpansion(_ url: URL) {
        if expandedFolders.contains(url) {
            expandedFolders.remove(url)
        } else {
            expandedFolders.insert(url)
        }
        saveExpandedFolders()
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

    private func saveExpandedFolders() {
        UserDefaults.standard.set(expandedFolders.map(\.path), forKey: "expandedFolderPaths")
    }

    private func saveSelectedProject() {
        UserDefaults.standard.set(selectedProject?.folderURL.path, forKey: "selectedProjectPath")
    }

    func playTrack(_ track: Track) {
        audioPlayer.play(track)
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
