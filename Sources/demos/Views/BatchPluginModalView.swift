import SwiftUI

struct BatchPluginModalView: View {
    let project: Project
    var targetAlsURL: URL? = nil
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preset: BatchPluginPreset = .utilityGain
    @State private var targetScope: BatchTargetScope = .allTracks
    @State private var position: BatchInsertPosition = .first
    @State private var saveAsNewVersion: Bool = false
    @State private var customXml: String = ""
    @State private var isExecuting: Bool = false
    @State private var resultMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var selectedAlsUrl: URL? = nil

    private var projectAlsUrl: URL? {
        selectedAlsUrl ?? targetAlsURL ?? project.newestAbletonVersion?.url ?? project.versions.first?.url
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accent)
                    Text("Batch Insert Plugins")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(Color.hoverBg, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.sidebarBg.opacity(0.8))

            Divider().background(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Safety notice
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 15))
                            .foregroundColor(.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safe Non-Destructive Injections")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primaryText)
                            Text("An automatic timestamped backup of your Ableton file is created before any changes are written.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondaryText)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accent.opacity(0.08))
                    .cornerRadius(8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accent.opacity(0.25), lineWidth: 1)
                    }

                    if project.versions.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TARGET LIVE SET")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.tertiaryText)

                            Picker("Live Set", selection: Binding(
                                get: { projectAlsUrl ?? project.versions.first?.url },
                                set: { selectedAlsUrl = $0 }
                            )) {
                                ForEach(project.versions) { version in
                                    Text(version.displayName + ".als").tag(Optional(version.url))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Choose Plugin Preset
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DEVICE PRESET")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.tertiaryText)

                        Picker("Preset", selection: $preset) {
                            ForEach(BatchPluginPreset.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(preset.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondaryText)
                            .padding(.top, 2)

                        if preset == .customXml {
                            TextEditor(text: $customXml)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 70)
                                .padding(6)
                                .background(Color.surfaceBg)
                                .cornerRadius(6)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.subtleBorder, lineWidth: 1)
                                }
                        }
                    }

                    // Target Tracks
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET TRACKS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.tertiaryText)

                        Picker("Tracks", selection: $targetScope) {
                            ForEach(BatchTargetScope.allCases) { scope in
                                Text(scope.rawValue).tag(scope)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                    }

                    // Insert Position
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INSERT POSITION IN CHAIN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.tertiaryText)

                        Picker("Position", selection: $position) {
                            ForEach(BatchInsertPosition.allCases) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(position == .first ? "Inserts before all existing plugins — ideal for input gain staging." : "Inserts at the very end of the channel strip.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondaryText)
                    }

                    // Output Option
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $saveAsNewVersion) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save as separate new version")
                                    .font(.system(size: 11.5, weight: .medium))
                                Text("Creates a new .als file instead of updating the current project set.")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondaryText)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }

                    // Status Message
                    if let resultMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(resultMessage)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primaryText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(6)
                    }

                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                    }
                }
                .padding(20)
            }

            Divider().background(Color.divider)

            // Bottom Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
                .font(.system(size: 12))

                Spacer()

                Button {
                    executeBatchInjection()
                } label: {
                    HStack(spacing: 6) {
                        if isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isExecuting ? "Injecting..." : "Inject into Channels")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isExecuting || projectAlsUrl == nil)
            }
            .padding(16)
            .background(Color.sidebarBg.opacity(0.8))
        }
        .frame(width: 480, height: 530)
        .background(Color.appBg)
    }

    private func executeBatchInjection() {
        guard let url = projectAlsUrl else {
            errorMessage = "No Ableton (.als) project file found."
            return
        }

        isExecuting = true
        errorMessage = nil
        resultMessage = nil

        let options = BatchInjectionOptions(
            preset: preset,
            customXml: customXml,
            targetScope: targetScope,
            position: position,
            saveAsNewVersion: saveAsNewVersion
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try AbletonBatchDeviceInjector.inject(into: url, options: options)
                DispatchQueue.main.async {
                    self.isExecuting = false
                    self.resultMessage = "Successfully injected into \(result.tracksModifiedCount) channels!\nBackup: \(result.backupFileUrl?.lastPathComponent ?? "saved")"
                    self.onComplete()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExecuting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
