import SwiftUI
import AppKit

struct ProjectNotesSection: View {
    let project: Project
    @EnvironmentObject var notes: ProjectNotesStore
    @Environment(\.openWindow) private var openWindow
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Project Notes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primaryText)
                        Text("Ideas, decisions, and useful timestamps")
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                    }
                }
                Spacer()
                Button {
                    openWindow(id: "project-notes")
                    WindowPresenter.showProjectNotes()
                } label: {
                    Label("Pop Out", systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Open notes in a floating window")
            }

            TextEditor(text: notes.binding(for: project))
                .font(.system(size: 13.5))
                .foregroundColor(.primaryText)
                .scrollContentBackground(.hidden)
                .lineSpacing(3)
                .padding(10)
                .frame(minHeight: 130, maxHeight: 200)
                .background(Color.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .focused($isEditing)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isEditing ? Color.accent.opacity(0.8) : Color.subtleBorder,
                                lineWidth: isEditing ? 1.5 : 1)
                }
                .overlay {
                    if notes.note(for: project).isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Start a note…")
                                .font(.system(size: 13, weight: .medium))
                            Text("Try a mix decision, lyric idea, or timestamp.")
                                .font(.system(size: 11))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.tertiaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(16)
                        .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                Text("Saved automatically on this Mac")
            }
            .font(.system(size: 10))
            .foregroundColor(.tertiaryText)
        }
        .padding(14)
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.subtleBorder, lineWidth: 1)
        }
        .padding(.vertical, 10)
    }
}

struct ProjectNotesWindow: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var notes: ProjectNotesStore
    @State private var pinned = false

    var body: some View {
        Group {
            if let project = store.selectedProject {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text("Project notes")
                                .font(.system(size: 11))
                                .foregroundColor(.secondaryText)
                        }
                        Spacer()
                        Button {
                            pinned.toggle()
                            NSApp.keyWindow?.level = pinned ? .floating : .normal
                        } label: {
                            Image(systemName: pinned ? "pin.fill" : "pin")
                                .foregroundColor(pinned ? .accent : .secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(pinned ? "Unpin window" : "Keep above other apps")
                    }
                    .padding(14)

                    Divider().background(Color.divider)

                    TextEditor(text: notes.binding(for: project))
                        .font(.system(size: 14))
                        .foregroundColor(.primaryText)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                }
            } else {
                Text("Select a project to write notes")
                    .foregroundColor(.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.appBg)
    }
}
