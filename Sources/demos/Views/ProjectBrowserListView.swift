import SwiftUI
import AppKit

enum ProjectDateFilter: String, CaseIterable, Identifiable {
    case anytime = "Any time"
    case week = "Past week"
    case month = "Past month"
    case quarter = "Past 3 months"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        guard self != .anytime else { return true }
        guard date != .distantPast else { return false }
        let days: Double
        switch self {
        case .anytime: return true
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        }
        return date.timeIntervalSinceNow >= -days * 86_400
    }
}

private struct ProjectFilterBar: View {
    @Binding var stage: ProjectStage?
    @Binding var priority: ProjectPriority?
    @Binding var rating: ProjectRating?
    @Binding var date: ProjectDateFilter
    @Binding var rediscoverEnabled: Bool
    let clear: () -> Void

    private var hasFilters: Bool {
        stage != nil || priority != nil || rating != nil || date != .anytime || rediscoverEnabled
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Menu {
                    Button("Any stage") { stage = nil }
                    Divider()
                    ForEach(ProjectStage.allCases, id: \.rawValue) { item in
                        Button(item.title) { stage = item }
                    }
                } label: { filterLabel(stage?.title ?? "Stage", icon: "flag", active: stage != nil) }

                Menu {
                    Button("Any priority") { priority = nil }
                    Divider()
                    ForEach(ProjectPriority.allCases) { item in
                        Button {
                            priority = item
                        } label: {
                            Label(item.title, systemImage: priority == item ? "checkmark" : "exclamationmark")
                        }
                    }
                } label: { filterLabel(priority.map { "Priority · \($0.title)" } ?? "Priority", icon: "exclamationmark", active: priority != nil) }

                Menu {
                    Button("Any rating") { rating = nil }
                    Divider()
                    ForEach(ProjectRating.allCases) { item in
                        Button {
                            rating = item
                        } label: {
                            Label(item.rawValue, systemImage: rating == item ? "checkmark" : "medal")
                        }
                    }
                } label: { filterLabel(rating.map { "Rating · \($0.rawValue)" } ?? "Rating", icon: "medal", active: rating != nil) }

                Menu {
                    ForEach(ProjectDateFilter.allCases) { item in Button(item.rawValue) { date = item } }
                } label: { filterLabel(date == .anytime ? "Modified" : date.rawValue, icon: "calendar", active: date != .anytime) }

                Button { rediscoverEnabled.toggle() } label: {
                    filterLabel("Rediscover", icon: "shuffle", active: rediscoverEnabled)
                }
                .buttonStyle(.plain)

                if hasFilters {
                    Button("Clear", action: clear)
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondaryText)
                        .padding(.leading, 3)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 42)
        .background(Color.sidebarBg.opacity(0.28))
    }

    private func filterLabel(_ title: String, icon: String, active: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(active ? .accent : .secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(active ? Color.accent.opacity(0.10) : Color.elevatedBg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(active ? Color.accent.opacity(0.45) : Color.subtleBorder) }
    }
}

private struct ProjectShortcutBar: View {
    var body: some View {
        HStack(spacing: 14) {
            shortcut("↑ ↓", "navigate")
            shortcut("↩", "open")
            shortcut("Space", "play")
            shortcut("Esc", "back")
            shortcut("P", "details")
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.sidebarBg.opacity(0.58))
        .overlay(alignment: .top) { Divider().background(Color.divider) }
    }

    private func shortcut(_ key: String, _ action: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(action).font(.system(size: 9)).foregroundColor(.tertiaryText)
        }
    }
}

struct ProjectBrowserListView: View {
    @Binding var showProjectInspector: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var collectionColors: CollectionColorStore
    @EnvironmentObject var progressStore: ProjectProgressStore
    @EnvironmentObject var metadataStore: ProjectMetadataStore
    @AppStorage("projectBrowserViewStyle") private var viewStyle = "list"
    @State private var stageFilter: ProjectStage?
    @State private var priorityFilter: ProjectPriority?
    @State private var ratingFilter: ProjectRating?
    @State private var dateFilter: ProjectDateFilter = .anytime
    @State private var rediscoverEnabled = false

    private var displayedProjects: [Project] {
        let filtered = store.filteredProjects.filter { project in
            let progress = progressStore.progress(for: project)
            let metadata = metadataStore.metadata(for: project)
            return (stageFilter == nil || progress.stage == stageFilter)
                && (priorityFilter == nil || metadata.priority == priorityFilter)
                && (ratingFilter == nil || metadata.rating == ratingFilter)
                && dateFilter.includes(project.latestModification)
        }
        let ordered = rediscoverEnabled
            ? filtered.sorted { rediscoveryScore($0) > rediscoveryScore($1) }
            : filtered
        return ordered
    }

    private var collectionLegendItems: [CollectionLegendItem] {
        collectionColors.legendItems(for: displayedProjects.map(\.folderURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu {
                    Button {
                        selectAllProjects()
                    } label: {
                        Label("All Projects", systemImage: store.selectedCollectionURL == nil ? "checkmark" : "square.grid.2x2")
                    }
                    if !collectionChoices.isEmpty { Divider() }
                    ForEach(collectionChoices) { choice in
                        Button {
                            selectCollection(choice.url)
                        } label: {
                            Label(
                                choice.title,
                                systemImage: store.selectedCollectionURL == choice.url ? "checkmark" : "folder"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if let color = selectedCategoryColor {
                            Circle().fill(color.color).frame(width: 8, height: 8)
                        }
                        if let emoji = selectedCollectionEmoji {
                            Text(emoji).font(.system(size: 14))
                        }
                        Text(collectionTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Current collection — click to switch folders")

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondaryText)
                    TextField("Search projects in \(collectionTitle)", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    if !store.searchQuery.isEmpty {
                        Button { store.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 440)
                .frame(height: 34)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))

                Spacer(minLength: 10)
                Text("\(displayedProjects.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.tertiaryText)
                Menu {
                    Section("Layout") {
                        Button { viewStyle = "list" } label: {
                            Label("List", systemImage: viewStyle == "list" ? "checkmark" : "list.bullet")
                        }
                        Button { viewStyle = "gallery" } label: {
                            Label("Gallery", systemImage: viewStyle == "gallery" ? "checkmark" : "square.grid.2x2")
                        }
                    }
                    Divider()
                    Button { showProjectInspector.toggle() } label: {
                        Label(showProjectInspector ? "Close Project Details" : "Open Project Details", systemImage: "rectangle.center.inset.filled")
                    }
                    .disabled(store.selectedProject == nil)
                } label: {
                    Label(viewStyle == "list" ? "List" : "Gallery", systemImage: viewStyle == "list" ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change layout and visible panels")
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(selectedCategoryColor?.color.opacity(0.055) ?? Color.clear)

            Divider().background(Color.divider)

            ProjectFilterBar(
                stage: $stageFilter,
                priority: $priorityFilter,
                rating: $ratingFilter,
                date: $dateFilter,
                rediscoverEnabled: $rediscoverEnabled,
                clear: clearFilters
            )

            Divider().background(Color.divider)

            if !collectionLegendItems.isEmpty {
                CollectionLegendBar(items: collectionLegendItems)
            }

            if viewStyle == "list" {
                GeometryReader { proxy in
                    // The workspace rail and project inspector leave less room for the
                    // browser than the full window size suggests. Switch earlier so the
                    // flexible project-name column never gets squeezed behind actions.
                    let compact = proxy.size.width < 820
                    VStack(spacing: 0) {
                        ProjectListHeader(compact: compact)
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(displayedProjects) { project in
                                    BrowserProjectRow(project: project, compact: compact)
                                        .onTapGesture { toggleProjectInspector(for: project) }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            } else {
                ProjectGalleryView(
                    projects: displayedProjects,
                    showProjectInspector: $showProjectInspector
                )
            }

            ProjectShortcutBar()
        }
        .background {
            ZStack {
                Color.appBg
                if let backgroundURL = selectedCollectionBackgroundURL {
                    CollectionBackgroundImage(url: backgroundURL)
                        .opacity(0.11)
                    Color.appBg.opacity(0.72)
                }
                selectedCategoryColor?.color.opacity(0.018) ?? Color.clear
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.return) {
            guard store.selectedProject != nil else { return .ignored }
            showProjectInspector = true
            return .handled
        }
        .onKeyPress(.escape) {
            if showProjectInspector { showProjectInspector = false }
            else { store.selectedProject = nil }
            return .handled
        }
        .onKeyPress("p") { showProjectInspector.toggle(); return .handled }
    }

    private func moveSelection(by offset: Int) {
        guard !displayedProjects.isEmpty else { return }
        let current = store.selectedProject.flatMap { selected in
            displayedProjects.firstIndex(where: { $0.id == selected.id })
        } ?? (offset > 0 ? -1 : displayedProjects.count)
        store.selectedProject = displayedProjects[max(0, min(displayedProjects.count - 1, current + offset))]
        showProjectInspector = true
    }

    private func rediscoveryScore(_ project: Project) -> Double {
        let age = project.latestModification == .distantPast ? 365 : max(0, -project.latestModification.timeIntervalSinceNow / 86_400)
        let progress = progressStore.progress(for: project)
        return age + Double(progress.sparkRating) * 18 + (progress.stage == .done ? -100 : 25)
    }

    private func clearFilters() {
        stageFilter = nil
        priorityFilter = nil
        ratingFilter = nil
        dateFilter = .anytime
        rediscoverEnabled = false
    }

    private var collectionTitle: String {
        guard let url = store.selectedCollectionURL else { return "All Projects" }
        return store.folderTree.findNode(at: url)?.name ?? "Projects"
    }

    private var selectedCategoryColor: CollectionColor? {
        store.selectedCollectionURL.flatMap { collectionColors.resolvedColor(for: $0) }
    }

    private var selectedCollectionEmoji: String? {
        store.selectedCollectionURL.flatMap { collectionColors.resolvedEmoji(for: $0) }
    }

    private var selectedCollectionBackgroundURL: URL? {
        store.selectedCollectionURL.flatMap { collectionColors.resolvedBackgroundURL(for: $0) }
    }

    private var collectionChoices: [CollectionChoice] {
        flattenCollections(store.folderTree, parents: [])
    }

    private func flattenCollections(_ nodes: [FolderNode], parents: [String]) -> [CollectionChoice] {
        nodes.flatMap { node -> [CollectionChoice] in
            guard !node.isProject, store.showHidden || !store.isFolderHidden(node.url) else { return [] }
            let path = parents + [node.name]
            let choice = CollectionChoice(url: node.url, title: path.joined(separator: " / "))
            return [choice] + flattenCollections(node.children, parents: path)
        }
    }

    private func selectAllProjects() {
        store.selectedCollectionURL = nil
    }

    private func selectCollection(_ url: URL) {
        store.selectedCollectionURL = url
        if let first = store.folderTree.findNode(at: url)?.allProjects().first {
            store.selectedProject = first
        }
    }

    private func toggleProjectInspector(for project: Project) {
        store.selectedProject = project
        showProjectInspector = true
    }
}

@MainActor
private enum CollectionBackgroundCache {
    static let images = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }
}

private struct CollectionBackgroundImage: View {
    let url: URL

    var body: some View {
        Group {
            if let image = CollectionBackgroundCache.image(at: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
    }
}

private struct PickupStrip: View {
    let projects: [Project]
    let select: (Project) -> Void
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var progressStore: ProjectProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("PICK UP WHERE YOU LEFT OFF")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("Recent projects")
                    .font(.system(size: 9))
                    .foregroundColor(.tertiaryText)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(projects) { project in
                        PickupProjectCard(
                            project: project,
                            progress: progressStore.progress(for: project),
                            select: { select(project) },
                            play: {
                                guard let export = project.sortedTracks.first else { return }
                                store.playTrack(export)
                            }
                        )
                        .frame(width: 235)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.sidebarBg.opacity(0.3))
    }
}

private struct PickupProjectCard: View {
    let project: Project
    let progress: ProjectProgress
    let select: () -> Void
    let play: () -> Void

    private var supportingText: String {
        let nextMove = progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nextMove.isEmpty { return "Next · \(nextMove)" }
        if let export = project.sortedTracks.first { return "Latest · \(export.displayName)" }
        return "Add a next move"
    }

    var body: some View {
        HStack(spacing: 9) {
            Button(action: select) {
                HStack(spacing: 9) {
                    ProjectArtworkImage(project: project)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                        Text(supportingText)
                            .font(.system(size: 9))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                        Text(progress.stage.title)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(progress.stage.companionColor)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(project.hasExports ? .primaryText : .tertiaryText)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!project.hasExports)
                .help(project.hasExports ? "Play latest export" : "No audio exports")
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.divider))
    }
}

private struct CollectionChoice: Identifiable {
    var id: URL { url }
    let url: URL
    let title: String
}

private struct ProjectGalleryView: View {
    let projects: [Project]
    @Binding var showProjectInspector: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var artworkStore: ProjectArtworkStore
    @EnvironmentObject var metadataStore: ProjectMetadataStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205, maximum: 285), spacing: 26)], spacing: 34) {
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    ProjectArtworkImage(project: project)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: .black.opacity(0.13), radius: 12, y: 7)
                            if store.selectedProject?.id == project.id {
                                LinearGradient(
                                    colors: [
                                        Color.accent.opacity(0.42),
                                        Color.accent.opacity(0.12),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .allowsHitTesting(false)
                            }
                            if project.hasExports {
                                Button { if let track = project.sortedTracks.first { store.playTrack(track) } } label: {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 58, height: 58)
                                        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 17))
                                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 9, y: 9)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleProjectInspector(for: project) }
                        .contextMenu {
                            Button("Choose Artwork…") {
                                store.selectedProject = project
                                openWindow(id: "project-artwork")
                            }
                            Button("Open in Finder") { NSWorkspace.shared.open(project.folderURL) }
                        }

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(project.folderURL.deletingLastPathComponent().lastPathComponent)
                                    .font(.system(size: 11)).foregroundColor(.secondaryText).lineLimit(1)
                            }
                            Spacer()
                            Menu {
                                Button("Choose Artwork…") {
                                    store.selectedProject = project
                                    openWindow(id: "project-artwork")
                                }
                                if artworkStore.imageURL(for: project) != nil {
                                    Button("Remove Artwork") { artworkStore.remove(for: project) }
                                }
                                Divider()
                                Button("Open Project Folder") { NSWorkspace.shared.open(project.folderURL) }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 24, height: 20)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .help("Project options")
                        }

                        if let metadata = artworkStore.metadata(for: project), let creator = metadata.creator {
                            Button("Photo by \(creator)") {
                                if let source = metadata.sourceURL { NSWorkspace.shared.open(source) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundColor(.tertiaryText)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func toggleProjectInspector(for project: Project) {
        store.selectedProject = project
        showProjectInspector = true
    }
}

private struct ProjectListHeader: View {
    let compact: Bool
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            sortHeader("ACTIVITY", order: .activity, width: compact ? 48 : 66, alignment: .leading)
            Color.clear.frame(width: compact ? 28 : 36)
            sortHeader("PROJECT", order: .name, alignment: .leading)
            sortHeader("BPM", order: .bpm, width: compact ? 36 : 48, alignment: .trailing)
            if !compact { sortHeader("WORK", order: .work, width: 72, alignment: .trailing) }
            sortHeader("MODIFIED", order: .recentlyEdited, width: compact ? 72 : 100, alignment: .trailing)
            Color.clear.frame(width: compact ? 104 : 132)
        }
        .font(.system(size: 9, weight: .semibold))
        .tracking(0.6)
        .foregroundColor(.tertiaryText)
        .padding(.horizontal, 17)
        .frame(height: 30)
        .background(Color.sidebarBg.opacity(0.5))
        .overlay(alignment: .bottom) { Divider().background(Color.divider) }
    }

    private func sortHeader(
        _ title: String,
        order: SortOrder,
        width: CGFloat? = nil,
        alignment: Alignment
    ) -> some View {
        Button { store.toggleSort(order) } label: {
            HStack(spacing: 3) {
                Text(title)
                if store.sortOrder == order {
                    Image(systemName: store.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundColor(store.sortOrder == order ? .accent : .tertiaryText)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: alignment)
        .help("Sort by \(title.lowercased())\(store.sortOrder == order ? "; click again to reverse" : "")")
    }
}

private struct CollectionLegendBar: View {
    let items: [CollectionLegendItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Text("COLLECTION DOTS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)

                ForEach(items) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(item.color.color.opacity(0.58))
                            .frame(width: 7, height: 7)
                        Text(item.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.title) collection")
                    .help("This dot marks projects in \(item.title)")
                }
            }
            .padding(.horizontal, 17)
        }
        .frame(height: 28)
        .background(Color.sidebarBg.opacity(0.28))
        .overlay(alignment: .bottom) {
            Divider().background(Color.divider)
        }
    }
}

private struct BrowserProjectRow: View {
    let project: Project
    let compact: Bool
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var notes: ProjectNotesStore
    @EnvironmentObject var progressStore: ProjectProgressStore
    @EnvironmentObject var collectionColors: CollectionColorStore
    @EnvironmentObject var artworkStore: ProjectArtworkStore
    @EnvironmentObject var metadataStore: ProjectMetadataStore
    @Environment(\.openWindow) private var openWindow
    @State private var hovered = false

    private var selected: Bool { store.selectedProject?.id == project.id }
    private var isCurrentOpenProject: Bool { store.isCurrentOpenProject(project) }
    private var playing: Bool {
        guard let current = player.currentTrack else { return false }
        return project.tracks.contains { $0.id == current.id }
    }
    private var progress: ProjectProgress { progressStore.progress(for: project) }
    private var collectionColorHelp: String {
        guard let sourceURL = collectionColors.resolvedColorSourceURL(for: project.folderURL) else {
            return "Collection color"
        }
        return "Collection: \(sourceURL.lastPathComponent)"
    }
    var body: some View {
        HStack(spacing: isCurrentOpenProject ? 12 : 9) {
            ActivityMeter(
                percent: project.activity.activityPercent,
                backupCount: project.activity.backupCount,
                color: playing ? .accent : effortColor
            )
            .frame(width: compact ? 48 : 66)
            ProjectArtworkImage(project: project)
                .frame(
                    width: isCurrentOpenProject ? (compact ? 42 : 52) : (compact ? 28 : 36),
                    height: isCurrentOpenProject ? (compact ? 42 : 52) : (compact ? 28 : 36)
                )
                .clipShape(RoundedRectangle(cornerRadius: isCurrentOpenProject ? 11 : (compact ? 6 : 7)))
                .overlay {
                    RoundedRectangle(cornerRadius: isCurrentOpenProject ? 11 : (compact ? 6 : 7))
                        .stroke(
                            isCurrentOpenProject ? Color.accent.opacity(0.72) : Color.primary.opacity(selected ? 0.18 : 0.07),
                            lineWidth: isCurrentOpenProject ? 1.5 : 1
                        )
                }
                .shadow(color: isCurrentOpenProject ? Color.accent.opacity(0.22) : .clear, radius: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let category = collectionColors.resolvedColor(for: project.folderURL) {
                        Circle()
                            .fill(category.color.opacity(0.58))
                            .frame(width: 6, height: 6)
                            .help(collectionColorHelp)
                    }
                    Text(project.name)
                        .font(.system(size: isCurrentOpenProject ? 15 : 13, weight: selected || isCurrentOpenProject ? .semibold : .regular))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                    if isCurrentOpenProject {
                        Label("CURRENT OPEN PROJECT", systemImage: "waveform")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accent.opacity(0.14), in: Capsule())
                            .overlay { Capsule().stroke(Color.accent.opacity(0.48)) }
                            .lineLimit(1)
                    }
                    if let priority = metadataStore.metadata(for: project).priority {
                        Text("PRIORITY \(priority.title)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    if let rating = metadataStore.metadata(for: project).rating {
                        Text("RATING \(rating.rawValue)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.accent)
                    }
                    if let key = metadataStore.metadata(for: project).musicalKey {
                        Text(key.uppercased())
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondaryText)
                    }
                }
                Text(project.folderURL.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: isCurrentOpenProject ? 12 : 11))
                    .foregroundColor(.tertiaryText)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    CompactRunway(progress: progress)
                    if !compact && !progress.nextMove.isEmpty {
                        Text("·")
                            .foregroundColor(.tertiaryText)
                        Text(progress.nextMove)
                            .font(.system(size: 9))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Text(project.bpmLabel ?? "—")
                .frame(width: compact ? 36 : 48, alignment: .trailing)
            if !compact {
                Text(project.activity.backupCount > 0
                     ? project.activity.estimatedWorkTime.estimatedWorkLabel
                     : "—")
                    .frame(width: 72, alignment: .trailing)
            }
            Group {
                if project.latestModification == .distantPast {
                    Text("—")
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(project.latestModification.compactAge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondaryText)
                        Text(project.latestModification.compactCalendarDate)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
            .frame(width: compact ? 72 : 100, alignment: .trailing)
            
            HStack(spacing: compact ? 5 : 8) {
                Button {
                    if playing {
                        player.togglePlayPause()
                    } else if let newestExport = project.sortedTracks.first {
                        store.playTrack(newestExport)
                    }
                } label: {
                    Image(systemName: playing && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(project.hasExports ? (playing ? .accent : .primaryText) : .tertiaryText)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(project.hasExports ? Color.white.opacity(0.07) : Color.clear))
                }
                .buttonStyle(.plain)
                .disabled(!project.hasExports)
                .help(project.hasExports ? (playing ? "Play or pause this project" : "Play newest export") : "No audio exports")

                Button {
                    store.openInAbleton(project)
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(project.newestAbletonVersion == nil ? .tertiaryText : .accent)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(project.newestAbletonVersion == nil)
                .help(project.newestAbletonVersion.map { "Open \($0.displayName) in Ableton" } ?? "No Ableton project file")

                Button { NSWorkspace.shared.open(project.folderURL) } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                        .frame(width: compact ? 16 : nil, height: 20)
                }
                .buttonStyle(.plain)
                .help("Open project folder in Finder")

                Button {
                    store.selectedProject = project
                    openWindow(id: "project-notes")
                    WindowPresenter.showProjectNotes()
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 11))
                        .foregroundColor(notes.note(for: project).isEmpty ? .secondaryText : .accent)
                        .frame(width: compact ? 16 : nil, height: 20)
                }
                .buttonStyle(.plain)
                .help(notes.note(for: project).isEmpty ? "Add project note" : "Open project note")

                if store.favourites.contains(project.folderURL) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.accent)
                        .frame(width: 9)
                } else {
                    Color.clear.frame(width: 9)
                }
            }
            .frame(width: compact ? 104 : 132, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, isCurrentOpenProject ? 15 : 8)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(isCurrentOpenProject
                      ? Color.accent.opacity(0.13)
                      : (selected ? Color.primary.opacity(0.045) : (hovered ? Color.hoverBg : .clear)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isCurrentOpenProject ? Color.accent.opacity(0.62) : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .opacity(store.isProjectHidden(project) ? 0.5 : 1)
        .contextMenu {
            if let version = project.newestAbletonVersion {
                Button("Open in Ableton") { store.openInAbleton(project, version: version) }
            }
            Button(notes.note(for: project).isEmpty ? "Add Project Note" : "Open Project Note") {
                store.selectedProject = project
                openWindow(id: "project-notes")
                WindowPresenter.showProjectNotes()
            }
            Button(store.isProjectHidden(project) ? "Unhide Project" : "Hide Project") {
                store.toggleProjectHidden(project)
            }
            Divider()
            Button(store.favourites.contains(project.folderURL) ? "Remove Favourite" : "Favourite") {
                store.toggleFavourite(project)
            }
            Button("Reveal in Finder") { NSWorkspace.shared.open(project.folderURL) }
        }
    }

    private var effortColor: Color {
        switch project.activity.activityPercent {
        case 75...: return Color(hex: "35D06F")
        case 45..<75: return Color(hex: "A7E84B")
        case 20..<45: return Color(hex: "F4C542")
        case 1..<20: return Color(hex: "F29B38")
        default: return Color.divider
        }
    }
}

private struct ActivityMeter: View {
    let percent: Int
    let backupCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.divider)
                    if percent > 100 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: rainbowColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: rainbowColors.last?.opacity(glowOpacity) ?? .clear, radius: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: proxy.size.width * CGFloat(percent) / 100)
                    }
                }
            }
            .frame(width: 32, height: 8)

            ZStack(alignment: .trailing) {
                Text("\(percent)")
                    .font(.system(size: 9, weight: percent > 100 ? .bold : .regular, design: .monospaced))
                    .foregroundColor(percent > 100 ? rainbowColors.last : .tertiaryText)
                if percent > 100 {
                    Image(systemName: "sparkles")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(rainbowColors.last)
                        .offset(x: 5, y: -7)
                }
            }
            .frame(width: 27, alignment: .trailing)
        }
        .help(helpText)
    }

    private var rainbowColors: [Color] {
        switch percent {
        case 200...:
            return [.pink, .purple, .blue, .cyan, .green, .yellow, .orange, .pink]
        case 150..<200:
            return [.purple, .blue, .cyan, .green, .yellow, .orange]
        case 120..<150:
            return [.blue, .cyan, .green, .yellow]
        default:
            return [.green, .cyan, .blue]
        }
    }

    private var glowOpacity: Double {
        min(0.7, 0.25 + Double(max(0, percent - 100)) / 200)
    }

    private var helpText: String {
        let count = "\(backupCount) \(backupCount == 1 ? "backup" : "backups") · \(percent)% activity"
        if percent >= 200 { return "\(count) · Certified studio obsession ✨🌈" }
        if percent >= 150 { return "\(count) · This one has lived in the studio 🌈" }
        if percent > 100 { return "\(count) · Extra love detected ✨" }
        return "\(count) · 30 backups = 100%"
    }
}
