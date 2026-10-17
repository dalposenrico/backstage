import SwiftUI

struct ExportCheckpointView: View {
    let project: Project
    @EnvironmentObject private var notes: ProjectNotesStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @Environment(\.dismiss) private var dismiss

    private var progress: ProjectProgress { progressStore.progress(for: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPORT CHECKPOINT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(.secondary)
                    Text(project.name)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Text("Capture where the track is while the export runs.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                checkpointLabel("PRODUCTION STAGE")
                Picker("Production stage", selection: Binding(
                    get: { progress.stage },
                    set: { progressStore.setStage($0, for: project) }
                )) {
                    ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                        Text(stage.title).tag(stage)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                checkpointLabel("SPARK")
                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { rating in
                        Button {
                            progressStore.setSparkRating(rating, for: project)
                        } label: {
                            Image(systemName: rating <= progress.sparkRating ? "sparkle" : "diamond")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(rating <= progress.sparkRating ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(progress.sparkRating == 0 ? "How excited are you to return?" : "\(progress.sparkRating)/5")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                checkpointLabel("NEXT ACTION")
                TextField("The smallest concrete thing to do next…", text: progressStore.nextMoveBinding(for: project))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                checkpointLabel("EXPORT NOTE")
                TextEditor(text: notes.binding(for: project))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 105)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func checkpointLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundColor(.secondary)
    }
}
