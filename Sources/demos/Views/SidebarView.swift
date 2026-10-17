import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @EnvironmentObject var collectionColors: CollectionColorStore
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isSearchFocused: Bool
    @State private var showingFolderSearch = false
    @State private var folderSearchQuery = ""
    @AppStorage("librarySidebarMode") private var sidebarMode = "library"

    var body: some View {
        librarySidebar
            .onAppear {
                isSearchFocused = false
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
                        .focused($isSearchFocused)
                        .textContentType(nil)
                        .autocorrectionDisabled(true)

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
                        sidebarSectionButton(
                            title: "ALL PROJECTS",
                            icon: "house.fill",
                            count: store.visibleProjects.count,
                            isSelected: store.selectedSidebarSection == .all,
                            action: {
                                store.selectedSidebarSection = .all
                                store.selectedCollectionURL = nil
                            }
                        )

                        // 2. RECENT (Clickable to show in middle list)
                        if !store.recentProjects.isEmpty {
                            sidebarSectionButton(
                                title: "RECENT",
                                icon: "clock.fill",
                                count: store.recentProjects.count,
                                isSelected: store.selectedSidebarSection == .recents,
                                action: {
                                    store.selectedSidebarSection = .recents
                                    store.selectedCollectionURL = nil
                                }
                            )

                            ForEach(store.recentProjects) { project in
                                SidebarProjectItem(project: project, depth: 0)
                            }
                        }

                        // 3. FAVORITES (Clickable to show in middle list)
                        sidebarSectionButton(
                            title: "FAVORITES",
                            icon: "star.fill",
                            count: store.favouriteProjects.isEmpty ? nil : store.favouriteProjects.count,
                            isSelected: store.selectedSidebarSection == .favorites,
                            action: {
                                store.selectedSidebarSection = .favorites
                                store.selectedCollectionURL = nil
                            }
                        )

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
                        DawFolderIcon(isOpen: false, color: .secondaryText)
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

    private func sidebarSectionButton(
        title: String,
        icon: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? .accent : .secondaryText)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(isSelected ? .white : .primaryText)

                Spacer()

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                isSelected
                    ? Color(red: 0.18, green: 0.19, blue: 0.22)
                    : Color.clear
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(Color.accent).frame(width: 2.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func matchesFolderSearch(_ node: FolderNode, query: String) -> Bool {
        guard !node.isProject else { return false }
        guard !query.isEmpty else { return true }
        return node.name.localizedCaseInsensitiveContains(query)
            || node.children.contains { matchesFolderSearch($0, query: query) }
    }
}

/// Tree guide lines connecting nested folders and projects, inspired by DAWbro.
private struct TreeIndentGuides: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { _ in
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)
                }
                .frame(width: 14)
            }
        }
    }
}

private struct CollectionTreeItem: View {
    let node: FolderNode
    let depth: Int
    let folderSearchQuery: String
    @EnvironmentObject var store: AppStore

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
                depth: depth,
                expandable: !childCollections.isEmpty || !childProjects.isEmpty,
                expanded: expanded,
                hidden: store.isFolderHidden(node.url),
                collectionURL: node.url,
                toggleExpansion: {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        store.toggleCollectionExpansion(node.url)
                    }
                },
                toggleHidden: { store.toggleFolderHidden(node.url) }
            ) {
                store.selectedSidebarSection = .folder(node.url)
                store.selectedCollectionURL = node.url
                if let first = node.allProjects().first { store.selectedProject = first }
            }

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

/// Minimal, high-contrast DAW folder icon inspired by DAWbro.
/// Renders a sharp, flat outline when closed, and an unmistakable 3D open
/// pocket with an angled front flap and interior sheet when open.
struct DawFolderIcon: View {
    let isOpen: Bool
    var color: Color = Color(white: 0.88)

    var body: some View {
        Canvas { context, _ in
            let w: CGFloat = 16.0
            let h: CGFloat = 13.0
            let strokeW: CGFloat = 1.15

            if isOpen {
                // ── 3D OPEN FOLDER ──
                // 1. Back wall & tab standing upright
                var back = Path()
                back.move(to: CGPoint(x: 1.5, y: 3.2))
                back.addLine(to: CGPoint(x: 1.5, y: 1.2))
                back.addQuadCurve(to: CGPoint(x: 2.5, y: 0.5), control: CGPoint(x: 1.5, y: 0.5))
                back.addLine(to: CGPoint(x: 6.5, y: 0.5))
                back.addQuadCurve(to: CGPoint(x: 7.8, y: 3.2), control: CGPoint(x: 7.2, y: 1.5))
                back.addLine(to: CGPoint(x: w - 2.0, y: 3.2))
                back.addQuadCurve(to: CGPoint(x: w - 1.2, y: 4.0), control: CGPoint(x: w - 1.2, y: 3.2))
                back.addLine(to: CGPoint(x: w - 1.2, y: h - 1.5))
                back.addLine(to: CGPoint(x: 1.5, y: h - 1.5))
                back.closeSubpath()

                // Dark interior cavity shadow
                context.fill(back, with: .color(color.opacity(0.35)))
                context.stroke(back, with: .color(color.opacity(0.6)), lineWidth: 1.0)

                // 2. Crisp project paper sheet sticking up out of the open folder
                let paperRect = CGRect(x: 3.5, y: 1.6, width: w - 7.0, height: 5.2)
                context.fill(Path(roundedRect: paperRect, cornerRadius: 1.0), with: .color(Color.white.opacity(0.92)))
                context.stroke(Path(roundedRect: paperRect, cornerRadius: 1.0), with: .color(Color.black.opacity(0.5)), lineWidth: 0.7)

                // Mini header line on the paper
                var paperLine = Path()
                paperLine.move(to: CGPoint(x: 5.5, y: 3.4))
                paperLine.addLine(to: CGPoint(x: w - 5.5, y: 3.4))
                context.stroke(paperLine, with: .color(Color.black.opacity(0.25)), lineWidth: 0.75)

                // 3. Front flap (swung forward in 3D perspective towards viewer)
                var frontFlap = Path()
                frontFlap.move(to: CGPoint(x: 0.5, y: 5.8))
                frontFlap.addLine(to: CGPoint(x: w - 0.5, y: 5.8))
                frontFlap.addLine(to: CGPoint(x: w - 2.0, y: h - 0.5))
                frontFlap.addLine(to: CGPoint(x: 2.0, y: h - 0.5))
                frontFlap.closeSubpath()

                // Solid bright front flap
                context.fill(frontFlap, with: .color(color))
                context.stroke(frontFlap, with: .color(Color.black.opacity(0.4)), lineWidth: 0.8)

                // Crisp top rim highlight on the open flap
                var flapRim = Path()
                flapRim.move(to: CGPoint(x: 0.5, y: 5.8))
                flapRim.addLine(to: CGPoint(x: w - 0.5, y: 5.8))
                context.stroke(flapRim, with: .color(Color.white.opacity(0.95)), lineWidth: 1.1)

            } else {
                // ── CLEAN CLOSED FOLDER ──
                // Tab at top left
                var tab = Path()
                tab.move(to: CGPoint(x: 1.5, y: 3.4))
                tab.addLine(to: CGPoint(x: 1.5, y: 1.2))
                tab.addQuadCurve(to: CGPoint(x: 2.5, y: 0.5), control: CGPoint(x: 1.5, y: 0.5))
                tab.addLine(to: CGPoint(x: 6.5, y: 0.5))
                tab.addQuadCurve(to: CGPoint(x: 7.8, y: 3.4), control: CGPoint(x: 7.2, y: 1.5))
                context.stroke(tab, with: .color(color.opacity(0.8)), lineWidth: strokeW)

                // Main closed folder body
                let bodyRect = CGRect(x: 1.2, y: 3.4, width: w - 2.4, height: h - 4.2)
                let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 1.8)

                // Translucent fill
                context.fill(bodyPath, with: .color(color.opacity(0.18)))
                // Sharp outline
                context.stroke(bodyPath, with: .color(color), lineWidth: strokeW)

                // Front flap seam line across the closed face
                var slit = Path()
                slit.move(to: CGPoint(x: 2.2, y: 4.8))
                slit.addLine(to: CGPoint(x: w - 2.2, y: 4.8))
                context.stroke(slit, with: .color(color.opacity(0.7)), lineWidth: strokeW * 0.8)
            }
        }
        .frame(width: 16, height: 13)
    }
}

private struct CollectionRow: View {
    let name: String
    let count: Int
    let selected: Bool
    var depth: Int = 0
    var expandable = false
    var expanded = false
    var hidden = false
    var collectionURL: URL?
    var toggleExpansion: () -> Void = {}
    var toggleHidden: () -> Void = {}
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 5) {
            // Indent guide lines for nested subfolders
            if depth > 0 {
                TreeIndentGuides(depth: depth)
            }

            // Disclosure chevron + DAW minimal folder icon (click either to expand/collapse)
            Button(action: {
                if expandable { toggleExpansion() }
                else { action() }
            }) {
                HStack(spacing: 4) {
                    if expandable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(hovered ? .white : Color(white: 0.55))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 10, height: 20)
                    } else {
                        Color.clear.frame(width: 10)
                    }

                    DawFolderIcon(isOpen: expanded, color: selected ? .white : Color(white: 0.88))
                }
            }
            .buttonStyle(.plain)

            // Folder name & track count (click to select and open folder)
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 12, weight: selected || depth == 0 ? .semibold : .medium))
                        .foregroundColor(selected ? .white : Color(white: 0.92))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if hidden {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 8.5))
                            .foregroundColor(.orange)
                    }

                    Text("\(count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, depth == 0 ? 10 : 4)
        .padding(.trailing, 10)
        .frame(height: 26)
        .background(
            selected
                ? Color(red: 0.22, green: 0.16, blue: 0.10)
                : (hovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 2.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            if let collectionURL {
                Button(hidden ? "Unhide Folder" : "Hide Folder") { toggleHidden() }
                Button("Show in Finder") { NSWorkspace.shared.open(collectionURL) }
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

            DawFolderIcon(
                isOpen: isExpanded,
                color: isHovered ? .accent : Color(white: 0.72)
            )

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
        .onTapGesture {
            store.openProjectTab(project)
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

struct SidebarSectionHeader: View {
    let title: String
    let icon: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 7) {
            if icon == "folder.fill" {
                DawFolderIcon(isOpen: true, color: .secondaryText)
                    .frame(width: 14)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondaryText)
                    .frame(width: 14)
            }

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
    @State private var hovered = false

    private var isSelected: Bool {
        store.selectedProject?.id == project.id
    }

    private var isFavourite: Bool {
        store.favourites.contains(project.folderURL)
    }

    var body: some View {
        Button {
            store.selectedProject = project
        } label: {
            HStack(spacing: 6) {
                // Indent guide lines for nested subfolder hierarchy
                if depth > 0 {
                    TreeIndentGuides(depth: depth)
                }

                // Meaningful Version / Stage badge
                ProjectBadgeView(project: project)

                // High-contrast project title
                Text(project.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : Color(white: 0.90))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Favorite star button (matches DAWbro Image 2)
                if hovered || isFavourite {
                    Button {
                        store.toggleFavourite(project)
                    } label: {
                        Image(systemName: isFavourite ? "star.fill" : "star")
                            .font(.system(size: 9.5))
                            .foregroundColor(isFavourite ? .accent : Color(white: 0.55))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isFavourite ? "Remove from favorites" : "Add to favorites")
                }
            }
            .padding(.leading, depth == 0 ? 12 : 4)
            .padding(.trailing, 10)
            .frame(height: 25)
            .background(
                isSelected
                    ? Color(red: 0.22, green: 0.16, blue: 0.10)
                    : (hovered ? Color.white.opacity(0.04) : Color.clear)
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
        .onHover { hovered = $0 }
    }
}
