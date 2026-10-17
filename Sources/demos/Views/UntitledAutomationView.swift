import SwiftUI

struct UntitledAutomationView: View {
    @EnvironmentObject private var sync: UntitledSyncStore
    @Environment(\.dismiss) private var dismiss
    @State private var newDestinationName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let draft = sync.draft {
                destinationList(draft)
                Divider()
                footer(draft)
            } else {
                ContentUnavailableView(
                    "No Export Selected",
                    systemImage: "icloud.and.arrow.up",
                    description: Text("Choose Send to [untitled] from a track or the menu bar.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 500)
        .background(Color.appBg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("[untitled] Automation")
                .font(.system(size: 22, weight: .bold))
            if let draft = sync.draft {
                Text(draft.track.displayName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(20)
    }

    private func destinationList(_ draft: UntitledSendDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("SEND TO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                ForEach(draft.destinations) { destination in
                    HStack(spacing: 12) {
                        Button { sync.toggleDestination(destination) } label: {
                            Image(systemName: draft.selectedDestinationIDs.contains(destination.id)
                                  ? "checkmark.square.fill" : "square")
                                .font(.system(size: 17))
                        }
                        .buttonStyle(.plain)
                        .disabled(destination.isSongProject)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(destination.name)
                            Text(destination.mode == .newVersion ? "Create project if needed · then add a new version" : "Add as a new track")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if destination.isSongProject {
                            Text("DEFAULT")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Button { sync.removeDestination(destination) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove destination")
                        }
                    }
                    .padding(12)
                    .background(Color.hoverBg, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    TextField("Add another [untitled] project…", text: $newDestinationName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDestination)
                    Button("Add", action: addDestination)
                        .disabled(newDestinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 6)
            }
            .padding(20)
        }
    }

    private func footer(_ draft: UntitledSendDraft) -> some View {
        HStack {
            Text("\(draft.selectedDestinationIDs.count) destination\(draft.selectedDestinationIDs.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Start Uploads") {
                sync.sendDraft()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.selectedDestinationIDs.isEmpty)
        }
        .padding(16)
    }

    private func addDestination() {
        sync.addDestination(named: newDestinationName)
        newDestinationName = ""
    }
}
