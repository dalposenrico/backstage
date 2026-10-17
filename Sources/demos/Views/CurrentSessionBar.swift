import SwiftUI

struct CurrentSessionBar: View {
    let project: Project
    var eyebrow = "CURRENT SESSION"
    @Binding var isExpanded: Bool
    let openDetails: () -> Void
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore
    @Environment(\.openWindow) private var openWindow
    @State private var isKeyPickerPresented = false

    private var progress: ProjectProgress { progressStore.progress(for: project) }
    private var metadata: ProjectMetadata { metadataStore.metadata(for: project) }
    private var openTodos: [ProjectTodo] { todoStore.openTodos(for: project) }
    private var isPlayingProject: Bool {
        guard let track = player.currentTrack else { return false }
        return project.tracks.contains { $0.id == track.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(eyebrow, systemImage: eyebrow == "CURRENT SESSION" ? "waveform" : "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.accent)
                Text(project.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                stageMenu
                if !isExpanded {
                    Text(compactSummary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "Collapse" : "Show project", systemImage: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: ProjectDockSizing.collapsedHeight)

            if isExpanded {
                Divider().background(Color.accent.opacity(0.22))
                HStack(alignment: .top, spacing: 16) {
                    identity
                        .frame(minWidth: 240, maxWidth: 310, alignment: .leading)

                    Divider().background(Color.accent.opacity(0.18))

                    direction
                        .frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)

                    Divider().background(Color.accent.opacity(0.18))

                    todoPreview
                        .frame(minWidth: 210, maxWidth: 300, alignment: .leading)

                    actions
                        .frame(width: 118)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.accent.opacity(0.16), Color.surfaceBg, Color.accent.opacity(0.055)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accent.opacity(0.72)).frame(height: 2)
        }
        .accessibilityElement(children: .contain)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            ProjectArtworkImage(project: project)
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.55), lineWidth: 1.5))
                .shadow(color: Color.accent.opacity(0.18), radius: 10)

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                if let version = project.newestAbletonVersion {
                    Label(version.displayName, systemImage: "doc.badge.gearshape")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accent)
                        .lineLimit(1)
                }
                if let export = project.sortedTracks.first {
                    Label("Latest export · \(export.displayName)", systemImage: "waveform")
                        .font(.system(size: 9))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                    if let date = export.modificationDate ?? export.creationDate {
                        Text("Exported \(date.menuSavedDate)")
                            .font(.system(size: 9))
                            .foregroundColor(.tertiaryText)
                    }
                } else {
                    Text("No audio export yet")
                        .font(.system(size: 9))
                        .foregroundColor(.tertiaryText)
                }
            }
        }
    }

    private var direction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                stageMenu
                if let bpm = project.bpmLabel { sessionBadge("\(bpm) BPM", icon: "metronome") }
                excitementMenu
            }
            HStack(spacing: 7) {
                priorityMenu
                ratingMenu
                musicalKeyMenu
            }
            Text("NEXT MOVE")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundColor(.tertiaryText)
            Text(progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Add a concrete next move in project details"
                 : progress.nextMove)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(progress.nextMove.isEmpty ? .tertiaryText : .primaryText)
                .lineLimit(2)
            Text("\(project.activity.backupCount) backups · \(project.activity.estimatedWorkTime.estimatedWorkLabel) estimated work")
                .font(.system(size: 9))
                .foregroundColor(.secondaryText)
        }
    }

    private var todoPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("NEXT UP", systemImage: "checklist")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.accent)
                Spacer()
                Text("\(openTodos.count) open")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.tertiaryText)
            }
            if openTodos.isEmpty {
                Text("No open tasks — add one in project details.")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
            } else {
                ForEach(openTodos.prefix(3)) { todo in
                    Button { todoStore.toggle(todo, for: project) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "circle")
                                .font(.system(size: 10))
                                .foregroundColor(.accent)
                            Text(todo.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Mark complete")
                }
                if openTodos.count > 3 {
                    Text("+\(openTodos.count - 3) more")
                        .font(.system(size: 9))
                        .foregroundColor(.tertiaryText)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 7) {
            Button {
                if isPlayingProject {
                    player.togglePlayPause()
                } else if let export = project.sortedTracks.first {
                    store.playTrack(export)
                }
            } label: {
                Label(isPlayingProject && player.isPlaying ? "Pause" : "Play latest", systemImage: isPlayingProject && player.isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!project.hasExports)

            Button(action: openDetails) {
                Label("Open project", systemImage: "arrow.up.left.and.arrow.down.right")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

            Button {
                store.selectedProject = project
                openWindow(id: "ab-compare")
            } label: {
                Label("Versions", systemImage: "waveform.path")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.accent)
        }
    }

    private func sessionBadge(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.accent.opacity(0.09), in: Capsule())
    }

    private var stageMenu: some View {
        Menu {
            ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                Button {
                    progressStore.setStage(stage, for: project)
                } label: {
                    Label(stage.title, systemImage: progress.stage == stage ? "checkmark" : "flag")
                }
            }
        } label: {
            editableSessionBadge(progress.stage.title, icon: "flag.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change project stage")
    }

    private var excitementMenu: some View {
        Menu {
            ForEach(Array(0...5), id: \.self) { rating in
                Button {
                    progressStore.setSparkRating(rating, for: project)
                } label: {
                    Label(
                        rating == 0 ? "Not rated" : "\(rating)/5",
                        systemImage: progress.sparkRating == rating ? "checkmark" : "sparkles"
                    )
                }
            }
        } label: {
            editableSessionBadge(
                progress.sparkRating == 0 ? "Excitement" : "\(progress.sparkRating)/5",
                icon: "sparkles"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change excitement rating")
    }

    private var priorityMenu: some View {
        Menu {
            Button("No priority") { metadataStore.setPriority(nil, for: project) }
            Divider()
            ForEach(ProjectPriority.allCases) { priority in
                Button {
                    metadataStore.setPriority(priority, for: project)
                } label: {
                    Label(priority.title, systemImage: metadata.priority == priority ? "checkmark" : "exclamationmark")
                }
            }
        } label: {
            editableSessionBadge(
                metadata.priority.map { "Priority \($0.title)" } ?? "Priority",
                icon: "exclamationmark"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change priority")
    }

    private var ratingMenu: some View {
        Menu {
            Button("No rating") { metadataStore.setRating(nil, for: project) }
            Divider()
            ForEach(ProjectRating.allCases) { rating in
                Button {
                    metadataStore.setRating(rating, for: project)
                } label: {
                    Label(rating.rawValue, systemImage: metadata.rating == rating ? "checkmark" : "medal")
                }
            }
        } label: {
            editableSessionBadge(
                metadata.rating.map { "Rating \($0.rawValue)" } ?? "Rating",
                icon: "medal"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change rating")
    }

    private var musicalKeyMenu: some View {
        Button {
            isKeyPickerPresented.toggle()
        } label: {
            editableSessionBadge(metadata.musicalKey ?? "Key", icon: "music.note")
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isKeyPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Musical key")
                    .font(.system(size: 12, weight: .semibold))
                ProjectMusicalKeyPicker(project: project)
            }
            .padding(12)
        }
        .help("Change musical key")
    }

    private func editableSessionBadge(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.tertiaryText)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.secondaryText)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.accent.opacity(0.09), in: Capsule())
        .contentShape(Capsule())
    }

    private var compactSummary: String {
        let tasks = openTodos.isEmpty ? "No open tasks" : "\(openTodos.count) open tasks"
        return "\(project.newestAbletonVersion?.displayName ?? "No Ableton set") · \(tasks)"
    }
}
