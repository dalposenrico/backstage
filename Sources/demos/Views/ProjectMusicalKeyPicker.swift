import SwiftUI

struct ProjectMusicalKeyPicker: View {
    let project: Project
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    private var selection: ProjectMusicalKeySelection? {
        ProjectMusicalKeys.selection(from: metadataStore.metadata(for: project).musicalKey)
    }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button("No key") { metadataStore.setMusicalKey(nil, for: project) }
                Divider()
                ForEach(ProjectMusicalKeys.notes, id: \.self) { note in
                    Button {
                        save(note: note)
                    } label: {
                        Label(note, systemImage: selection?.note == note ? "checkmark" : "music.note")
                    }
                }
            } label: {
                keyPart(selection?.note ?? "Note", width: 56, active: selection != nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            separator

            HStack(spacing: 2) {
                ForEach(ProjectKeyAccidental.allCases) { accidental in
                    Button {
                        save(accidental: accidental)
                    } label: {
                        Text(accidental.pickerTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 23, height: 22)
                            .foregroundColor(selection?.accidental == accidental ? .white : .secondaryText)
                            .background(selection?.accidental == accidental ? Color.accent : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)
                    .help(accidental.spokenTitle)
                }
            }
            .padding(.horizontal, 3)

            separator

            Menu {
                ForEach(ProjectKeyMode.allCases) { mode in
                    Button {
                        save(mode: mode)
                    } label: {
                        Label(mode.title, systemImage: selection?.mode == mode ? "checkmark" : "music.note")
                    }
                }
            } label: {
                keyPart(selection?.mode.compactTitle ?? "Mode", width: 116, active: selection != nil)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(selection == nil)

            if selection != nil {
                separator
                Button {
                    metadataStore.setMusicalKey(nil, for: project)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.tertiaryText)
                        .frame(width: 25, height: 28)
                }
                .buttonStyle(.plain)
                .help("Clear key")
            }
        }
        .frame(height: 30)
        .background(Color.elevatedBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(selection == nil ? Color.subtleBorder : Color.accent.opacity(0.45)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Musical key")
        .help(selection?.displayName ?? "Choose a root note, accidental, and key type")
    }

    private var separator: some View {
        Rectangle().fill(Color.subtleBorder).frame(width: 1, height: 18)
    }

    private func keyPart(_ title: String, width: CGFloat, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(active ? .primaryText : .secondaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.tertiaryText)
        }
        .frame(width: width, height: 28)
        .contentShape(Rectangle())
    }

    private func save(note: String? = nil, accidental: ProjectKeyAccidental? = nil, mode: ProjectKeyMode? = nil) {
        var updated = selection ?? ProjectMusicalKeySelection(note: "C", accidental: .natural, mode: .major)
        if let note { updated.note = note }
        if let accidental { updated.accidental = accidental }
        if let mode { updated.mode = mode }
        metadataStore.setMusicalKey(updated.displayName, for: project)
    }
}
