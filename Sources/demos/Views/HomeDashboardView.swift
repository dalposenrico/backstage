import SwiftUI

struct HomeDashboardView: View {
    let openProject: (Project) -> Void
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    private var projects: [Project] {
        Array(store.visibleProjects.sorted { $0.latestModification > $1.latestModification }.prefix(15))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Welcome back")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primaryText)
                    Text("Pick up a project with the context you need to make the next decision.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondaryText)
                }

                if projects.isEmpty {
                    HomeLibraryStatusView(state: store.libraryLoadPresentation)
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    if case .updating(let folderName) = store.libraryLoadPresentation {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Updating \(folderName)…")
                                .font(.system(size: 11, weight: .medium))
                            Text("Your current projects remain available while the library refreshes.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Pick up where you left off")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primaryText)
                        Spacer()
                        Text("Your most recently edited projects")
                            .font(.system(size: 11))
                            .foregroundColor(.tertiaryText)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                            HomeProjectCard(
                                project: project,
                                progress: progressStore.progress(for: project),
                                todos: Array(todoStore.openTodos(for: project).prefix(2)),
                                metadata: metadataStore.metadata(for: project),
                                artworkStyle: HomeCardArtworkStyle.style(at: index),
                                open: { openProject(project) },
                                play: {
                                    guard let track = project.sortedTracks.first else { return }
                                    store.playTrack(track)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.appBg)
    }
}

private struct HomeMasonryLayout: Layout {
    let minimumColumnWidth: CGFloat
    let maximumColumns: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        let metrics = measurements(for: subviews, width: width)
        return CGSize(width: width, height: metrics.columnHeights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = measurements(for: subviews, width: bounds.width)
        var columnHeights = Array(repeating: CGFloat.zero, count: metrics.columnCount)

        for subview in subviews {
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: metrics.columnWidth, height: nil))
            let x = bounds.minX + CGFloat(column) * (metrics.columnWidth + spacing)
            let y = bounds.minY + columnHeights[column]
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: metrics.columnWidth, height: size.height)
            )
            columnHeights[column] += size.height + spacing
        }
    }

    private func measurements(for subviews: Subviews, width: CGFloat) -> Metrics {
        let possibleColumns = Int((width + spacing) / (minimumColumnWidth + spacing))
        let columnCount = max(1, min(maximumColumns, possibleColumns))
        let columnWidth = (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for subview in subviews {
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[column] += size.height + spacing
        }

        if !subviews.isEmpty {
            columnHeights = columnHeights.map { max(0, $0 - spacing) }
        }
        return Metrics(columnCount: columnCount, columnWidth: columnWidth, columnHeights: columnHeights)
    }

    private struct Metrics {
        let columnCount: Int
        let columnWidth: CGFloat
        let columnHeights: [CGFloat]
    }
}

private enum HomeCardArtworkStyle {
    case compact
    case landscape(CGFloat)

    static func style(at index: Int) -> HomeCardArtworkStyle {
        switch index % 7 {
        case 1: return .landscape(132)
        case 2: return .landscape(174)
        case 5: return .landscape(150)
        default: return .compact
        }
    }
}

private struct HomeLibraryStatusView: View {
    @EnvironmentObject private var store: AppStore
    let state: LibraryLoadPresentation

    var body: some View {
        VStack(spacing: 15) {
            statusIcon
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isActivelyScanning {
                scanActivity
            }
            actions
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.subtleBorder))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .loading:
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium)).foregroundColor(.accent)
        case .chooseFolder:
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34)).foregroundColor(.accent)
        case .unavailable:
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34)).foregroundColor(.orange)
        case .noProjects:
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 34)).foregroundColor(.secondaryText)
        case .updating:
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium)).foregroundColor(.accent)
        case .ready:
            EmptyView()
        }
    }

    private var isActivelyScanning: Bool {
        if case .loading = state { return true }
        if case .updating = state { return true }
        return false
    }

    private var scanActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let fraction = store.scanProgress?.fractionComplete {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(.accent)
            .frame(maxWidth: 420)
            .accessibilityLabel("Library scan in progress")

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundColor(.accent)
                Text(store.scanProgress.map { "Scanning \($0.currentFolder)" } ?? "Preparing library scan…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 10)
                if let progress = store.scanProgress {
                    Text(progressSummary(progress))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                        .fixedSize()
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private func progressSummary(_ progress: ProjectScanProgress) -> String {
        let folders = progress.totalFolders.map {
            "\(progress.foldersScanned) of \($0) folders checked"
        } ?? "Counting folders"
        return "\(folders) · \(progress.projectsFound) projects found"
    }

    private var title: String {
        switch state {
        case .chooseFolder: return "Choose your music folder"
        case .unavailable: return "Music folder unavailable"
        case .loading: return "Loading your library…"
        case .updating: return "Updating your library…"
        case .noProjects: return "No Ableton projects found"
        case .ready: return "Library ready"
        }
    }

    private var message: String {
        switch state {
        case .chooseFolder:
            return "goodvibrations HQ is waiting for the folder that contains your Ableton projects."
        case .unavailable(let folderName):
            return "The saved folder “\(folderName)” can’t be reached. It may have moved or be on a disconnected drive."
        case .loading(let folderName):
            return "Scanning “\(folderName)” for Ableton sets and audio exports. This can take a moment after an update."
        case .updating(let folderName):
            return "Refreshing “\(folderName)”."
        case .noProjects(let folderName):
            return "Finished scanning “\(folderName)”, but no folders containing Ableton .als files were found."
        case .ready:
            return "Your projects are ready."
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .chooseFolder, .unavailable:
            Button("Choose Music Folder…", action: store.selectFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .noProjects:
            HStack {
                Button("Choose Different Folder…", action: store.selectFolder)
                    .buttonStyle(.borderedProminent)
                Button("Scan Again") { Task { await store.scan() } }
                    .buttonStyle(.bordered)
            }
        case .loading, .updating:
            Text("You can leave this screen open; projects will appear automatically.")
                .font(.system(size: 10))
                .foregroundColor(.tertiaryText)
        case .ready:
            EmptyView()
        }
    }
}

private struct HomeProjectCard: View {
    let project: Project
    let progress: ProjectProgress
    let todos: [ProjectTodo]
    let metadata: ProjectMetadata
    let artworkStyle: HomeCardArtworkStyle
    let open: () -> Void
    let play: () -> Void

    private var nextMove: String {
        let value = progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Add a concrete next move" : value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            projectHeader

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("PRODUCTION STAGE")
                    Spacer()
                    Text(progress.stage.title)
                        .foregroundColor(.secondaryText)
                }
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                HStack(spacing: 4) {
                    ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                        Capsule()
                            .fill(stage.workflowIndex <= progress.stage.workflowIndex ? Color.accent : Color.divider)
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 5)
                Text("NEXT MOVE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                Text(nextMove)
                    .font(.system(size: 13, weight: progress.nextMove.isEmpty ? .regular : .medium))
                    .foregroundColor(progress.nextMove.isEmpty ? .tertiaryText : .primaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(Color.elevatedBg)
            .clipShape(RoundedRectangle(cornerRadius: 9))

            if !todos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TO-DO")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .foregroundColor(.tertiaryText)
                    ForEach(todos) { todo in
                        Label(todo.title, systemImage: "circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.sortedTracks.first.map { "Latest export · \($0.displayName)" } ?? "No audio export yet")
                        .lineLimit(1)
                    if project.latestModification != .distantPast {
                        Text("Edited \(project.latestModification.compactAge)")
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(.tertiaryText)

                Spacer()

                if project.hasExports {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondaryText)
                    .help("Play latest export")
                }

                Button("Continue", action: open)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.subtleBorder, lineWidth: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    @ViewBuilder
    private var projectHeader: some View {
        switch artworkStyle {
        case .compact:
            HStack(alignment: .top, spacing: 14) {
                ProjectArtworkImage(project: project)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                projectIdentity
                Spacer(minLength: 0)
            }
        case .landscape(let height):
            VStack(alignment: .leading, spacing: 12) {
                ProjectArtworkImage(project: project)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                projectIdentity
            }
        }
    }

    private var projectIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primaryText)
                .lineLimit(2)
            Text(project.folderURL.deletingLastPathComponent().lastPathComponent)
                .font(.system(size: 11))
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
            HStack(spacing: 10) {
                Label(progress.stage.title, systemImage: "flag")
                if let bpm = project.bpmLabel {
                    Label("\(bpm) BPM", systemImage: "metronome")
                }
                if progress.sparkRating > 0 {
                    Label("\(progress.sparkRating)/5", systemImage: "sparkles")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondaryText)
            HStack(spacing: 5) {
                if let priority = metadata.priority {
                    Text(priority.title).homeMetadataBadge(color: .orange)
                }
                if let rating = metadata.rating {
                    Text(rating.rawValue).homeMetadataBadge(color: .accent)
                }
                if let key = metadata.musicalKey {
                    Text(key).homeMetadataBadge(color: .secondaryText)
                }
            }
        }
    }
}

private extension Text {
    func homeMetadataBadge(color: Color) -> some View {
        self.font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
