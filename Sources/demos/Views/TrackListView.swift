import SwiftUI
import AppKit

// MARK: - Track list (right panel)

struct TrackListView: View {
    let project: Project
    var allowsExpandedWorkspace = true
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var artworkStore: ProjectArtworkStore
    @EnvironmentObject var collectionColors: CollectionColorStore
    @Environment(\.openWindow) private var openWindow
    @State private var section: ProjectInspectorSection = .overview
    @State private var arrangement: AbletonArrangement?
    @State private var isLoadingArrangement = false
    @AppStorage("projectWorkspaceExpanded") private var workspaceExpanded = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Project header ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {

                        // Project identity. Secondary actions live in one menu so the
                        // two actions that resume work remain visually dominant.
                        HStack(spacing: 10) {
                            Text(project.name)
                                .font(.system(size: 23, weight: .bold))
                                .foregroundColor(.primaryText)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            projectActionsMenu
                        }

                        // Finder color tags
                        if !project.tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(project.tags, id: \.self) { tag in
                                    if let color = Color.finderTagColor(tag) {
                                        HStack(spacing: 4) {
                                            Circle().fill(color).frame(width: 8, height: 8)
                                            Text(tag)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(color.opacity(0.9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(color.opacity(0.12))
                                        .cornerRadius(10)
                                    } else {
                                        Text(tag)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondaryText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }

                        // Metadata row — larger, higher contrast
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(project.hasExports
                                     ? "\(project.tracks.count) \(project.tracks.count == 1 ? "export" : "exports")"
                                     : "No exports yet")
                                if project.latestModification != .distantPast {
                                    Text("·").foregroundColor(.tertiaryText)
                                    Text("Edited \(project.latestModification.relativeFull)")
                                }
                            }
                            if let created = project.creationDate {
                                Text("Added \(created.fullDateTime)")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)

                        ProjectInsights(project: project)

                        HStack(spacing: 8) {
                            if let version = project.newestAbletonVersion {
                                Button { store.openInAbleton(project, version: version) } label: {
                                    Label("Open in Ableton", systemImage: "arrow.up.forward.app.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .foregroundColor(.white)
                                        .background(Color.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }

                            if project.hasExports {
                                Button {
                                    if let first = project.sortedTracks.first { store.playTrack(first) }
                                } label: {
                                    Label("Play Latest", systemImage: "play.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .foregroundColor(.primaryText)
                                        .background(Color.elevatedBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)

            Divider().background(Color.white.opacity(0.18))

            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(ProjectInspectorSection.allCases) { item in
                        let isSelected = section == item
                        Button {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                section = item
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .accent : Color(white: 0.65))
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(isSelected ? .white : Color(white: 0.72))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background {
                                if isSelected {
                                    DawTabFill(cornerRadius: 5, bottomExtension: 2.0)
                                        .fill(Color.appBg)
                                }
                            }
                            .overlay {
                                if isSelected {
                                    DawTabOutline(cornerRadius: 5, strokeWidth: 2.0, bottomExtension: 2.0)
                                        .stroke(Color.accent, lineWidth: 2.0)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 36)
            .background(Color.sidebarBg.opacity(0.45))

            // ── Content ──────────────────────────────────────────────────────
            Group {
                switch section {
                case .overview, .workflow, .files:
                    HStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                switch section {
                                case .overview:
                                    ProjectProgressSection(project: project)
                                    ProjectTodoSection(project: project)
                                    ProjectNotesSection(project: project)
                                    StreamingReferencesSection(project: project)
                                        .padding(.vertical, 8)

                                case .workflow:
                                    ProductionChecklistView(project: project)

                                case .files:
                                    PluginsUsedSection(plugins: project.plugins)
                                    if !project.tracks.isEmpty {
                                        ListSectionHeader(title: "Exports", count: project.tracks.count)

                                        ForEach(project.exportGroups) { group in
                                            if !group.folder.isEmpty {
                                                ExportFolderHeader(path: group.folder, count: group.tracks.count)
                                            }
                                            ForEach(group.tracks) { track in
                                                TrackRow(track: track, project: project)
                                                    .padding(.leading, group.folder.isEmpty ? 0 : 14)
                                                    .onTapGesture {
                                                        player.currentTrack?.id == track.id
                                                            ? player.togglePlayPause()
                                                            : store.playTrack(track)
                                                    }
                                            }
                                        }
                                    } else {
                                        HStack(spacing: 10) {
                                            Image(systemName: "square.dashed")
                                                .font(.system(size: 13))
                                                .foregroundColor(.tertiaryText)
                                            Text("No audio exports found in this project folder")
                                                .font(.system(size: 13))
                                                .foregroundColor(.tertiaryText)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 20)
                                    }

                                    if !project.versions.isEmpty {
                                        ListSectionHeader(title: "Project Files", count: project.versions.count)
                                            .padding(.top, project.tracks.isEmpty ? 4 : 0)

                                        ForEach(project.versions) { version in
                                            AbletonVersionRow(version: version)
                                        }
                                    }

                                default:
                                    EmptyView()
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                        }

                        if allowsExpandedWorkspace && workspaceExpanded {
                            Divider().background(Color.divider)
                            ProjectDetailsPanel(project: project)
                                .frame(width: 320)
                        }
                    }

                case .arrangement:
                    if let arrangement {
                        ArrangementTimelineView(arrangement: arrangement, projectName: project.name)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if isLoadingArrangement {
                        VStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Parsing arrangement tracks & clips from .als...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "rectangle.split.3x1")
                                .font(.system(size: 26))
                                .foregroundColor(.tertiaryText)
                            Text("No Ableton Live set (.als) available to inspect")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .midi:
                    if let arrangement {
                        MidiClipVaultView(arrangement: arrangement, projectName: project.name)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "pianokeys")
                                .font(.system(size: 26))
                                .foregroundColor(.tertiaryText)
                            Text("No MIDI clips found")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .samples:
                    if let arrangement {
                        SampleHealthAuditorView(arrangement: arrangement, project: project)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundColor(.tertiaryText)
                            Text("No samples found")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
                .overlay(alignment: .bottomTrailing) {
                    if allowsExpandedWorkspace {
                        ExpandWindowButton()
                            .padding(10)
                    }
                }
        }
        .background(Color.appBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: project.id) {
            isLoadingArrangement = true
            if let alsURL = project.newestAbletonVersion?.url ?? project.versions.first?.url {
                arrangement = await Task.detached(priority: .userInitiated) {
                    AbletonArrangementParser.parse(from: alsURL, projectFolderURL: project.folderURL)
                }.value
            } else {
                arrangement = nil
            }
            isLoadingArrangement = false
        }
    }

    private var projectActionsMenu: some View {
        Menu {
            Button { NSWorkspace.shared.open(project.folderURL) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button { store.toggleFavourite(project) } label: {
                Label(
                    store.favourites.contains(project.folderURL) ? "Remove from Favourites" : "Add to Favourites",
                    systemImage: store.favourites.contains(project.folderURL) ? "star.slash" : "star"
                )
            }
            Divider()
            Button { openWindow(id: "ab-compare") } label: {
                Label("Open Versions", systemImage: "rectangle.split.2x1")
            }
            Button { openWindow(id: "project-artwork") } label: {
                Label("Choose Artwork", systemImage: "photo")
            }
            Divider()
            Button { Task { await store.refreshProject(project) } } label: {
                Label("Refresh Project", systemImage: "arrow.clockwise")
            }
            .disabled(store.refreshingProjects.contains(project.folderURL))
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondaryText)
                .frame(width: 30, height: 28)
                .background(Color.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("More project actions")
    }
}

private enum ProjectInspectorSection: String, CaseIterable, Identifiable {
    case arrangement, midi, samples, overview, workflow, files

    var id: String { rawValue }
    var title: String {
        switch self {
        case .arrangement: return "Arrangement"
        case .midi: return "MIDI"
        case .samples: return "Samples"
        case .overview: return "Overview"
        case .workflow: return "Workflow"
        case .files: return "Files"
        }
    }
    var icon: String {
        switch self {
        case .arrangement: return "rectangle.split.3x1"
        case .midi: return "pianokeys"
        case .samples: return "waveform.badge.magnifyingglass"
        case .overview: return "scope"
        case .workflow: return "checklist"
        case .files: return "folder"
        }
    }
}

private struct ExportFolderHeader: View {
    let path: String
    let count: Int
    @EnvironmentObject private var collectionColors: CollectionColorStore
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundColor(
                    store.selectedProject.flatMap { collectionColors.resolvedColor(for: $0.folderURL)?.color }
                    ?? .secondaryText
                )
            Text(path)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }
}

private struct ProjectInsights: View {
    let project: Project

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], alignment: .leading, spacing: 8) {
            if let bpm = project.bpmLabel {
                insight(icon: "metronome", value: bpm, label: "BPM")
            }
            if project.activity.backupCount > 0 {
                insight(
                    icon: "clock.arrow.circlepath",
                    value: project.activity.estimatedWorkTime.estimatedWorkLabel,
                    label: "estimated work"
                )
                insight(
                    icon: "square.stack.3d.up",
                    value: "\(project.activity.backupCount)",
                    label: project.activity.backupCount == 1 ? "backup" : "backups"
                )
                insight(
                    icon: "calendar.badge.clock",
                    value: "\(project.activity.sessionCount)",
                    label: project.activity.sessionCount == 1 ? "session" : "sessions"
                )
            }
        }
        .padding(.top, 2)
        .help("Work time is estimated from Ableton save and backup timestamps. Gaps over two hours start a new session.")
    }

    private func insight(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accent)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Section header

struct ListSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.tertiaryText)
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.tertiaryText.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Audio track row

struct TrackRow: View {
    let track: Track
    let project: Project
    @State private var isHovered = false
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var untitledSync: UntitledSyncStore

    var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                // State icon
                ZStack {
                    if isCurrent {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accent)
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                                          isActive: player.isPlaying)
                    } else {
                        Image(systemName: isHovered ? "play.fill" : "music.note")
                            .font(.system(size: isHovered ? 11 : 10))
                            .foregroundColor(isHovered ? .primaryText : .secondaryText)
                    }
                }
                .frame(width: 18, alignment: .center)

                Text(track.displayName)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .accent : .primaryText)
                    .lineLimit(1)
                    .help(track.displayName)

                // Format badge
                Text(track.fileExtension)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(4)

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 28)
                if isCurrent {
                    PlaybackTimeLabel(timeline: player.timeline)
                } else if let date = track.modificationDate {
                    Text("Edited \(date.relativeShort)")
                }
                Spacer()
                UntitledSyncButton(track: track, project: project)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isCurrent
                      ? Color.accent.opacity(0.07)
                      : (isHovered ? Color.hoverBg : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

private struct UntitledSyncButton: View {
    let track: Track
    let project: Project
    @EnvironmentObject var sync: UntitledSyncStore
    @Environment(\.openWindow) private var openWindow

    private var status: UntitledSyncStatus { sync.status(for: track) }

    var body: some View {
        Menu {
            if status != .synced {
                Button(status == .updateAvailable ? "Send New Version" : "Send to [untitled]") {
                    sync.prepare(track, project: project)
                    openWindow(id: "untitled-automation")
                    WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: false)
                }
            }
            if status == .sending {
                Button("Mark as On [untitled]") { sync.markSynced(track) }
            }
            if status != .notSynced {
                Divider()
                Button("Reset Sync Status") { sync.reset(track) }
            }
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(helpText)
    }

    private var label: String {
        switch status {
        case .notSynced: return "Not synced"
        case .sending: return "Sending"
        case .synced: return "On [untitled]"
        case .updateAvailable: return "New version"
        }
    }

    private var icon: String {
        switch status {
        case .notSynced: return "icloud.slash"
        case .sending: return "icloud.and.arrow.up"
        case .synced: return "icloud.fill"
        case .updateAvailable: return "arrow.triangle.2.circlepath.icloud"
        }
    }

    private var color: Color {
        switch status {
        case .synced: return .accent
        case .sending, .updateAvailable: return .orange
        case .notSynced: return .tertiaryText
        }
    }

    private var helpText: String {
        switch status {
        case .notSynced: return "Send this export to [untitled]"
        case .sending: return "Waiting for confirmation from [untitled]"
        case .synced: return "This exact export is marked as on [untitled]"
        case .updateAvailable: return "This file changed after it was synced"
        }
    }
}

// MARK: - Ableton version row (.als file)

struct AbletonVersionRow: View {
    let version: AbletonVersion
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                // Document icon — visually distinct from the music note
                Image(systemName: "doc.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText.opacity(0.6))
                    .frame(width: 18, alignment: .center)

                Text(version.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                    .help(version.displayName)

                // .als badge
                Text("als")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accent.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accent.opacity(0.10))
                    .cornerRadius(4)

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Spacer().frame(width: 28)
                if let date = version.modificationDate {
                    Text("Edited \(date.relativeShort)")
                }
                Spacer()
                if let created = version.creationDate {
                    Text("Added \(created.formatted(.dateTime.month(.abbreviated).day().year()))")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isHovered ? Color.hoverBg : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Expand window button

struct ExpandWindowButton: View {
    @AppStorage("projectWorkspaceExpanded") private var isExpanded = false
    @State private var isHovered    = false

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Image(systemName: isExpanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11))
                .foregroundColor(isHovered ? .secondaryText : .tertiaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? Color.hoverBg : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "Return to project library" : "Expand project workspace")
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Plug-ins used

private struct PluginsUsedSection: View {
    let plugins: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                Text("PLUGINS USED")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.tertiaryText)
                    .tracking(0.8)
                Text("\(plugins.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.tertiaryText)
                Spacer()
            }

            if plugins.isEmpty {
                Text("No third-party plug-ins found in the newest Ableton set.")
                    .font(.system(size: 12))
                    .foregroundColor(.tertiaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(plugins, id: \.self) { plugin in
                        Text(plugin)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.elevatedBg)
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(Color.subtleBorder, lineWidth: 1) }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1) }
        .padding(.vertical, 10)
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 600
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}
