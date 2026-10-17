import SwiftUI

struct ProjectDetailsPanel: View {
    let project: Project
    @EnvironmentObject private var metadataStore: ProjectMetadataStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @EnvironmentObject private var notesStore: ProjectNotesStore
    @EnvironmentObject private var references: ReferenceStore
    @State private var metadataExpanded = true
    @State private var tasksExpanded = true
    @State private var versionsExpanded = false
    @State private var exportsExpanded = false
    @State private var pluginsExpanded = false
    @State private var notesExpanded = false
    @State private var referencesExpanded = false

    private var metadata: ProjectMetadata { metadataStore.metadata(for: project) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Project Details")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("LOCAL")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
            }
            .padding(16)

            Divider().background(Color.divider)

            ScrollView {
                VStack(spacing: 0) {
                    detailGroup("Metadata", icon: "music.note", isExpanded: $metadataExpanded) {
                        VStack(alignment: .leading, spacing: 14) {
                            metric("BPM", project.bpmLabel ?? "—")

                            VStack(alignment: .leading, spacing: 5) {
                                Text(metadata.musicalKey.map { "KEY · \($0.uppercased())" } ?? "KEY · NOT SET").detailLabel()
                                ProjectMusicalKeyPicker(project: project)
                            }
                            .frame(maxWidth: .infinity)

                            Text("RATING · \(metadata.rating?.rawValue ?? "NOT SET")").detailLabel()
                            HStack(spacing: 5) {
                                ForEach(ProjectRating.allCases) { rating in
                                    choiceButton(rating.rawValue, selected: metadata.rating == rating) {
                                        metadataStore.setRating(metadata.rating == rating ? nil : rating, for: project)
                                    }
                                }
                            }

                            Text("PRIORITY · \(metadata.priority?.title ?? "NOT SET")").detailLabel()
                            HStack(spacing: 5) {
                                ForEach(ProjectPriority.allCases) { priority in
                                    choiceButton(priority.title, selected: metadata.priority == priority) {
                                        metadataStore.setPriority(metadata.priority == priority ? nil : priority, for: project)
                                    }
                                }
                            }

                            HStack {
                                Text("Production stage")
                                Spacer()
                                Text(progressStore.progress(for: project).stage.title)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondaryText)
                        }
                    }

                    detailGroup("Tasks", count: todoStore.openTodos(for: project).count, icon: "checkmark.square", isExpanded: $tasksExpanded) {
                        previewRows(todoStore.openTodos(for: project).map(\.title), empty: "No open tasks")
                    }
                    detailGroup("Versions", count: project.versions.count, icon: "clock.arrow.circlepath", isExpanded: $versionsExpanded) {
                        previewRows(project.versions.prefix(5).map(\.displayName), empty: "No Ableton versions")
                    }
                    detailGroup("Exports", count: project.tracks.count, icon: "waveform", isExpanded: $exportsExpanded) {
                        previewRows(project.sortedTracks.prefix(5).map(\.displayName), empty: "No exports")
                    }
                    detailGroup("Plugins", count: project.plugins.count, icon: "puzzlepiece.extension", isExpanded: $pluginsExpanded) {
                        previewRows(Array(project.plugins.prefix(8)), empty: "No third-party plugins found")
                    }
                    detailGroup("References", count: references.streamingReferences(for: project).count, icon: "scope", isExpanded: $referencesExpanded) {
                        previewRows(references.streamingReferences(for: project).map(\.title), empty: "No vibe references")
                    }
                    detailGroup("Notes", icon: "note.text", isExpanded: $notesExpanded) {
                        Text(notesStore.note(for: project).isEmpty ? "No project notes" : notesStore.note(for: project))
                            .font(.system(size: 11))
                            .foregroundColor(notesStore.note(for: project).isEmpty ? .tertiaryText : .secondaryText)
                            .lineLimit(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .background(Color.sidebarBg.opacity(0.72))
    }

    private func detailGroup<Content: View>(
        _ title: String, count: Int? = nil, icon: String, isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content().padding(.horizontal, 16).padding(.bottom, 14)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 16).foregroundColor(.secondaryText)
                Text(title).font(.system(size: 12, weight: .semibold))
                if let count { Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundColor(.tertiaryText) }
            }
            .padding(.vertical, 13)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Divider().background(Color.divider) }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).detailLabel()
            Text(value).font(.system(size: 12, weight: .semibold)).frame(height: 22)
        }
        .frame(width: 70, alignment: .leading)
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(selected ? .white : .secondaryText)
            .frame(minWidth: 28, minHeight: 25)
            .background(selected ? Color.accent : Color.elevatedBg)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accent : Color.subtleBorder) }
    }

    private func previewRows(_ rows: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if rows.isEmpty {
                Text(empty).foregroundColor(.tertiaryText)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row).lineLimit(1)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Text {
    func detailLabel() -> some View {
        self.font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundColor(Color.tertiaryText)
    }
}
