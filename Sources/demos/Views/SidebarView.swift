import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var collectionColors: CollectionColorStore
    @Environment(\.openSettings) private var openSettings
    @State private var showingFolderSearch = false
    @State private var folderSearchQuery = ""
    @AppStorage("librarySidebarMode") private var sidebarMode = "library"

    var body: some View {
        librarySidebar
            .onAppear {
                if sidebarMode != "library" { sidebarMode = "library" }
            }
    }

    private var librarySidebar: some View {
        VStack(spacing: 0) {

            // ── Search bar (DAWbro style) ───────────────────────────────────
            HStack(spacing: 6) {
                if !store.searchQuery.isEmpty || store.selectedProject != nil {
                    Button {
                        store.searchQuery = ""
                        store.selectedProject = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Back / Clear Search")
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.tertiaryText)

                    TextField("Search projects", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primaryText)

                    if !store.searchQuery.isEmpty {
                        Button { store.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }

                Menu {
                    Button { store.showHidden.toggle() } label: {
                        Label(store.showHidden ? "Hide Archived Items" : "Show Archived Items", systemImage: store.showHidden ? "eye.slash" : "eye")
                    }
                    Button { Task { await store.scan() } } label: {
                        Label("Refresh Library", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isScanning)
                } label: {
                    if store.isScanning {
                        ProgressView().controlSize(.small).frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Library options")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().background(Color.divider)

            // ── Update banner (only shown when a new release is available) ────
            if let ver = updateChecker.availableVersion,
               let url = updateChecker.releasePageURL,
               !updateChecker.isDismissed {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                    Text("v\(ver) available")
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)
                    Spacer()
                    Button("Download") { NSWorkspace.shared.open(url) }
                        .font(.system(size: 12))
                        .foregroundColor(.accent)
                        .buttonStyle(.plain)
                    Button { withAnimation { updateChecker.dismiss() } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accent.opacity(0.07))
                .transition(.move(edge: .top).combined(with: .opacity))

                Divider().background(Color.divider)
            }

            // ── Project / folder list ────────────────────────────────────────
            if store.folderTree.isEmpty && store.isScanning {
                VStack(spacing: 10) {
                    Group {
                        if let fraction = store.scanProgress?.fractionComplete {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                        }
                    }
                    .progressViewStyle(.linear)
                    .tint(.accent)
                    .frame(width: 120)
                    Text("Loading library…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondaryText)
                    if let progress = store.scanProgress {
                        Text(progress.currentFolder)
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 145)
                        Text(progress.totalFolders.map {
                            "\(progress.foldersScanned)/\($0) checked · \(progress.projectsFound) found"
                        } ?? "Counting folders…")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.folderTree.isEmpty {
                VStack(spacing: 8) {
                    Text(store.rootFolderURL == nil ? "Choose a music folder" : "No Ableton projects found")
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                    if store.rootFolderURL == nil {
                        Button("Choose Folder…", action: store.selectFolder)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // 1. ALL PROJECTS
                        Button {
                            store.selectedCollectionURL = nil
                            store.selectedProject = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(store.selectedCollectionURL == nil && store.selectedProject == nil ? .accent : .secondaryText)
                                    .frame(width: 14)

                                Text("ALL PROJECTS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundColor(store.selectedCollectionURL == nil && store.selectedProject == nil ? .white : .primaryText)

                                Spacer()

                                Text("\(store.visibleProjects.count)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.tertiaryText)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(
                                store.selectedCollectionURL == nil && store.selectedProject == nil
                                    ? Color(red: 0.18, green: 0.19, blue: 0.22)
                                    : Color.clear
                            )
                            .overlay(alignment: .leading) {
                                if store.selectedCollectionURL == nil && store.selectedProject == nil {
                                    Rectangle().fill(Color.accent).frame(width: 2.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        // 2. RECENT
                        if !store.recentProjects.isEmpty {
                            SidebarSectionHeader(title: "RECENT", icon: "clock.fill", count: store.recentProjects.count)

                            ForEach(store.recentProjects) { project in
                                SidebarProjectItem(project: project, depth: 0)
                            }
                        }

                        // 3. FAVORITES
                        SidebarSectionHeader(title: "FAVORITES", icon: "star.fill", count: store.favouriteProjects.isEmpty ? nil : store.favouriteProjects.count)

                        if store.favouriteProjects.isEmpty {
                            Text("Click the star next to a project to keep it here.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.tertiaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(store.favouriteProjects) { project in
                                SidebarProjectItem(project: project, depth: 0)
                            }
                        }

                        // 4. IMPORTED FOLDERS
                        SidebarSectionHeader(
                            title: "IMPORTED FOLDERS",
                            icon: "folder.fill",
                            count: store.visibleProjects.count
                        )

                        ForEach(store.folderTree) { node in
                            CollectionTreeItem(node: node, depth: 0, folderSearchQuery: "")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider().background(Color.divider)

            // ── Footer: folder selector + appearance toggle ──────────────────
            HStack(spacing: 0) {
                Button(action: store.selectFolder) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundColor(.secondaryText)
                        Text(store.rootFolderURL.map { $0.lastPathComponent } ?? "Open Folder…")
                            .font(.system(size: 12))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                        if store.rootFolderURL != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.tertiaryText)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Appearance toggle — compact, in footer
                HStack(spacing: 1) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button { settings.appearanceMode = mode } label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10,
                                              weight: settings.appearanceMode == mode ? .bold : .regular))
                                .foregroundColor(settings.appearanceMode == mode ? .accent : .tertiaryText)
                                .frame(width: 20, height: 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(settings.appearanceMode == mode
                                              ? Color.accent.opacity(0.12)
                                              : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(mode.rawValue)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.03))
                .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color.sidebarBg)
        .frame(maxHeight: .infinity)
    }

    private func matchesFolderSearch(_ node: FolderNode, query: String) -> Bool {
        guard !node.isProject else { return false }
        guard !query.isEmpty else { return true }
        return node.name.localizedCaseInsensitiveContains(query)
            || node.children.contains { matchesFolderSearch($0, query: query) }
    }
}

private struct CollectionTreeItem: View {
    let node: FolderNode
    let depth: Int
    let folderSearchQuery: String
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var collectionColors: CollectionColorStore

    private var childCollections: [FolderNode] {
        node.children.filter {
            !$0.isProject
                && (store.showHidden || !store.isFolderHidden($0.url))
                && matchesFolderSearch($0)
        }
    }

    private var childProjects: [FolderNode] {
        node.children.filter {
            $0.isProject
                && (store.showHidden || ($0.project != nil && !store.isProjectHidden($0.project!)))
        }
    }

    private var expanded: Bool { !folderSearchQuery.isEmpty || store.expandedCollections.contains(node.url) }

    var body: some View {
        if !node.isProject && (store.showHidden || !store.isFolderHidden(node.url)) {
            CollectionRow(
                name: node.name,
                count: store.visibleProjectCount(in: node),
                selected: store.selectedCollectionURL == node.url,
                icon: expanded ? "folder.fill" : "folder",
                depth: depth,
                expandable: !childCollections.isEmpty || !childProjects.isEmpty,
                expanded: expanded,
                hidden: store.isFolderHidden(node.url),
                collectionURL: node.url,
                toggleExpansion: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        store.toggleCollectionExpansion(node.url)
                    }
                },
                toggleHidden: { store.toggleFolderHidden(node.url) }
            ) {
                store.selectedCollectionURL = node.url
                if let first = node.allProjects().first { store.selectedProject = first }
            }
            .padding(.leading, CGFloat(depth) * 10)

            if expanded {
                ForEach(childCollections) { child in
                    CollectionTreeItem(node: child, depth: depth + 1, folderSearchQuery: folderSearchQuery)
                }
                ForEach(childProjects) { child in
                    if let project = child.project {
                        SidebarProjectItem(project: project, depth: depth + 1)
                    }
                }
            }
        }
    }

    private func matchesFolderSearch(_ candidate: FolderNode) -> Bool {
        guard folderSearchQuery.isEmpty == false else { return true }
        return candidate.name.localizedCaseInsensitiveContains(folderSearchQuery)
            || candidate.children.contains { !$0.isProject && matchesFolderSearch($0) }
    }
}

private struct CollectionRow: View {
    let name: String
    let count: Int
    let selected: Bool
    let icon: String
    var depth: Int = 0
    var expandable = false
    var expanded = false
    var hidden = false
    var collectionURL: URL?
    var toggleExpansion: () -> Void = {}
    var toggleHidden: () -> Void = {}
    let action: () -> Void
    @State private var hovered = false
    @State private var showColorPalette = false
    @EnvironmentObject private var collectionColors: CollectionColorStore

    private var categoryColor: CollectionColor? {
        collectionURL.flatMap { collectionColors.resolvedColor(for: $0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if expandable {
                Button(action: toggleExpansion) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.tertiaryText)
                        .frame(width: 12, height: 20)
                }
                .buttonStyle(.plain)
            } else if collectionURL != nil {
                Color.clear.frame(width: 12)
            }
            if let collectionURL {
                Button { showColorPalette = true } label: {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(categoryColor?.color.opacity(selected ? 0.82 : 0.48) ?? (selected ? .accent : .secondaryText))
                        .frame(width: 14, height: 20)
                }
                .buttonStyle(.plain)
                .help("Choose a color for \(name)")
                .popover(isPresented: $showColorPalette, arrowEdge: .leading) {
                    CollectionColorPalette(name: name, url: collectionURL)
                }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(selected ? .accent : .secondaryText)
                    .frame(width: 14)
            }
            Text(name)
                .font(.system(size: 13, weight: selected || depth == 0 ? .semibold : .regular))
                .foregroundColor(selected ? .primaryText : .secondaryText)
                .lineLimit(1)
            if let emoji = collectionURL.flatMap({ collectionColors.resolvedEmoji(for: $0) }) {
                Text(emoji).font(.system(size: 13))
            }
            Spacer()
            if hidden {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7).fill(
                selected
                    ? Color.selectedBg
                    : (hovered ? Color.hoverBg : .clear)
            )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
        .opacity(hidden ? 0.55 : 1)
        .contextMenu {
            if icon != "square.grid.2x2" {
                Button(hidden ? "Unhide Folder" : "Hide Folder") { toggleHidden() }
            }
            if let collectionURL {
                Divider()
                Menu("Color") {
                    Button {
                        collectionColors.setColor(nil, for: collectionURL)
                    } label: {
                        Label("None", systemImage: collectionColors.exactColor(for: collectionURL) == nil ? "checkmark.circle.fill" : "circle")
                    }
                    Divider()
                    ForEach(CollectionColor.allCases) { option in
                        Button {
                            collectionColors.setColor(option, for: collectionURL)
                        } label: {
                            Label(option.title, systemImage: collectionColors.exactColor(for: collectionURL) == option ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                }
            }
        }
        .help(expandable ? "Select this folder, or use the chevron to show nested folders" : "Show projects in this folder")
    }
}

private struct CollectionColorPalette: View {
    let name: String
    let url: URL
    @EnvironmentObject private var collectionColors: CollectionColorStore
    @Environment(\.dismiss) private var dismiss

    private var selected: CollectionColor? { collectionColors.exactColor(for: url) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 52, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(selected?.color ?? .secondaryText)
                .frame(height: 58)

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)
                .lineLimit(1)

            HStack {
                Text("COLLECTION EMOJI")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                Spacer()
                TextField("🎵", text: Binding(
                    get: { collectionColors.exactEmoji(for: url) ?? "" },
                    set: { collectionColors.setEmoji($0, for: url) }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: 54)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("FOLDER COLOR")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        paletteButton(nil)
                        ForEach(CollectionColor.allCases) { color in
                            paletteButton(color)
                        }
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("SUBTLE BACKGROUND")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                HStack {
                    Button("Choose Photo…") { chooseBackground() }
                    if collectionColors.resolvedBackgroundURL(for: url) != nil {
                        Button("Remove", role: .destructive) {
                            collectionColors.setBackgroundURL(nil, for: url)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("PRODUCTION STAGES")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundColor(.tertiaryText)
                    Spacer()
                    if collectionColors.exactAllowedStages(for: url) != nil {
                        Button("Use inherited") { collectionColors.resetStages(for: url) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9))
                            .foregroundColor(.accent)
                    }
                }

                Text("Choose the stages that make sense for projects in this folder. Nested folders inherit this setting.")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                    ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                        let isEnabled = collectionColors.allowedStages(for: url).contains(stage)
                        Button {
                            collectionColors.setStage(stage, enabled: !isEnabled, for: url)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                Text(stage.title).lineLimit(1)
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(isEnabled ? .primaryText : .tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7)
                            .frame(height: 28)
                            .background(isEnabled ? Color.accent.opacity(0.09) : Color.elevatedBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 390)
    }

    private func paletteButton(_ option: CollectionColor?) -> some View {
        Button {
            collectionColors.setColor(option, for: url)
        } label: {
            ZStack {
                Circle()
                    .fill(option?.color ?? Color.secondaryText.opacity(0.12))
                    .frame(width: 25, height: 25)
                if option == nil {
                    Image(systemName: "slash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondaryText)
                }
                if selected == option {
                    Circle()
                        .stroke(Color.primaryText.opacity(0.8), lineWidth: 2)
                        .frame(width: 31, height: 31)
                }
            }
            .frame(width: 31, height: 31)
        }
        .buttonStyle(.plain)
        .help(option?.title ?? "No color")
    }

    private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a subtle background for \(name)"
        panel.begin { response in
            guard response == .OK, let imageURL = panel.url else { return }
            Task { @MainActor in collectionColors.setBackgroundURL(imageURL, for: url) }
        }
    }
}

// MARK: - Recursive tree item

struct FolderTreeItem: View {
    let node: FolderNode
    let depth: Int
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer

    var isExpanded: Bool { store.expandedFolders.contains(node.url) }

    var body: some View {
        if node.isProject, let project = node.project {
            ProjectRow(
                project: project,
                isSelected: store.selectedProject?.id == project.id
            )
            .padding(.leading, max(0, CGFloat(depth - 1) * 14 + (depth > 0 ? 8 : 0)))
            .onTapGesture { store.selectedProject = project }
        } else {
            VStack(spacing: 2) {
                FolderRow(node: node, isExpanded: isExpanded)
                    .padding(.leading, CGFloat(depth) * 14)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            store.toggleExpansion(node.url)
                        }
                    }

                if isExpanded {
                    ForEach(node.children) { child in
                        FolderTreeItem(node: child, depth: depth + 1)
                    }
                }
            }
        }
    }
}

// MARK: - Folder row (organizational folder, not a project)

struct FolderRow: View {
    let node: FolderNode
    let isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.tertiaryText)
                .frame(width: 10)

            Image(systemName: isExpanded ? "folder.open.fill" : "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(isHovered ? .accent.opacity(0.8) : .secondaryText)

            Text(node.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .primaryText : .secondaryText)
                .lineLimit(1)

            Spacer()

            Text("\(node.projectCount)")
                .font(.system(size: 11))
                .foregroundColor(.tertiaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.hoverBg : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Project row

struct ProjectRow: View {
    let project: Project
    let isSelected: Bool
    @State private var isHovered = false
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var store: AppStore

    var isCurrentlyPlaying: Bool {
        guard let current = player.currentTrack else { return false }
        return project.tracks.contains { $0.id == current.id }
    }

    // Date label adapts to active sort order
    var dateLabel: String {
        let date: Date?
        switch store.sortOrder {
        case .dateAdded: date = project.creationDate
        default:
            let m = project.latestModification
            date = m == .distantPast ? nil : m
        }
        return date?.relativeShort ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            // Playing indicator
            Circle()
                .fill(isCurrentlyPlaying ? Color.accent : Color.clear)
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(
                            !project.hasExports
                                ? .tertiaryText
                                : (isSelected || isHovered ? .primaryText : Color(hex: "999999"))
                        )
                        .lineLimit(1)

                    // Finder color tags
                    ForEach(project.tags.prefix(3), id: \.self) { tag in
                        if let color = Color.finderTagColor(tag) {
                            Circle().fill(color).frame(width: 7, height: 7)
                        }
                    }
                }

                HStack(spacing: 0) {
                    if let bpm = project.bpmLabel {
                        Text("\(bpm) BPM")
                            .fontWeight(.medium)
                    } else {
                        Text(project.hasExports
                             ? "\(project.tracks.count) \(project.tracks.count == 1 ? "export" : "exports")"
                             : "no exports")
                            .italic(!project.hasExports)
                    }
                    if project.activity.backupCount > 0 {
                        Text(" · \(project.activity.estimatedWorkTime.estimatedWorkLabel)")
                    }
                    if !dateLabel.isEmpty && project.hasExports {
                        Text(" · \(dateLabel)")
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(project.hasExports ? .tertiaryText : .tertiaryText.opacity(0.5))
            }

            Spacer()

            // Persistent star indicator when not hovering
            if store.favourites.contains(project.folderURL) && !isHovered {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.accent.opacity(0.6))
            }

            // Action buttons on hover
            if isHovered {
                HStack(spacing: 4) {
                    Button { store.toggleFavourite(project) } label: {
                        Image(systemName: store.favourites.contains(project.folderURL) ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundColor(store.favourites.contains(project.folderURL) ? .accent : .secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(store.favourites.contains(project.folderURL) ? "Remove from widget" : "Add to widget")

                    Button { NSWorkspace.shared.open(project.folderURL) } label: {
                        Image(systemName: "folder.badge.arrow.up")
                            .font(.system(size: 13))
                            .foregroundColor(.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.selectedBg : (isHovered ? Color.hoverBg : Color.clear))
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    let icon: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondaryText)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(.secondaryText)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.tertiaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

struct SidebarProjectItem: View {
    let project: Project
    var depth: Int = 0
    @EnvironmentObject var store: AppStore

    private var isSelected: Bool {
        store.selectedProject?.id == project.id
    }

    var body: some View {
        Button {
            store.selectedProject = project
        } label: {
            HStack(spacing: 7) {
                AbletonBadgeView()

                Text(project.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.leading, CGFloat(depth) * 12 + 12)
            .padding(.trailing, 10)
            .frame(height: 25)
            .background(
                isSelected
                    ? Color(red: 0.22, green: 0.16, blue: 0.10)
                    : Color.clear
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(Color.accent)
                        .frame(width: 2.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
