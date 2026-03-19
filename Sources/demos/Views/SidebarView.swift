import SwiftUI

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Button { openSettings() } label: {
                        Text("[demos]")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")

                    Spacer()

                    // Collapse / expand all folders
                    if !store.folderTree.isEmpty && store.searchQuery.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.collapseAll()
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.tertiaryText)
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Collapse all folders")

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.expandAll()
                            }
                        } label: {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.tertiaryText)
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Expand all folders")
                    }

                    // Sort menu
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                store.sortOrder = order
                            } label: {
                                Label(order.rawValue,
                                      systemImage: store.sortOrder == order ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(store.sortOrder == .recentlyEdited ? .tertiaryText : .accent)
                            .frame(width: 22, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Sort projects")

                    if store.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Button { Task { await store.scan() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.tertiaryText)
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh")
                    }
                }

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                    TextField("Search projects", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
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
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)

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
            if store.folderTree.isEmpty && !store.isScanning {
                VStack(spacing: 8) {
                    Text(store.rootFolderURL == nil ? "No folder selected" : "No projects found")
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if store.searchQuery.isEmpty {
                            // ── Tree browser ──────────────────────────
                            ForEach(store.folderTree) { node in
                                FolderTreeItem(node: node, depth: 0)
                            }
                        } else {
                            // ── Flat filtered list during search ──────
                            ForEach(store.filteredProjects) { project in
                                ProjectRow(
                                    project: project,
                                    isSelected: store.selectedProject?.id == project.id
                                )
                                .onTapGesture { store.selectedProject = project }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
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
                    Text(project.hasExports
                         ? "\(project.tracks.count) \(project.tracks.count == 1 ? "export" : "exports")"
                         : "no exports")
                        .font(.system(size: 12))
                        .foregroundColor(project.hasExports ? .tertiaryText : .tertiaryText.opacity(0.5))
                        .italic(!project.hasExports)
                    if !dateLabel.isEmpty && project.hasExports {
                        Text(" · \(dateLabel)")
                            .font(.system(size: 12))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }

            Spacer()

            // Reveal in Finder on hover
            if isHovered {
                Button { NSWorkspace.shared.open(project.folderURL) } label: {
                    Image(systemName: "folder.badge.arrow.up")
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
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
