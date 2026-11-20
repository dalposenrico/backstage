import SwiftUI
import AppKit

struct ProjectOffloadModalView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppStore.shared ?? AppStore()
    @ObservedObject private var offloadStore = ProjectOffloadStore.shared
    @ObservedObject private var dropbox = DropboxManager.shared

    @State private var sizeBreakdown: OffloadSizeBreakdown?
    @State private var isLoadingSize = true
    @State private var isOffloading = false
    @State private var errorMessage: String?
    @State private var showBounceAlert = false

    private var exportReadiness: ExportReadiness {
        offloadStore.checkExportReadiness(for: project)
    }

    private var archiveDestinationURL: URL {
        dropbox.archiveDirectoryURL().appendingPathComponent("\(project.name).zip")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // Storage impact card
                    storageImpactCard

                    // Export readiness check
                    exportStatusCard

                    // Destination card
                    destinationCard

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            footerView
        }
        .frame(width: 520, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            isLoadingSize = true
            sizeBreakdown = await offloadStore.calculateSize(for: project.folderURL)
            isLoadingSize = false
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Offload to Cloud")
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(project.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Storage Impact Card
    private var storageImpactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Disk Space Analysis", systemImage: "internaldrive")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isLoadingSize {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let size = sizeBreakdown {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Size")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(size.formattedTotal)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.primary)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.secondary.opacity(0.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Space to Free")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Text(size.formattedEstimatedSavings)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Breakdown list
                VStack(spacing: 6) {
                    breakdownRow(label: "Samples & Audio Recordings", size: size.formattedSamples, icon: "waveform")
                    breakdownRow(label: "Ableton Backups", size: size.formattedBackups, icon: "clock.arrow.circlepath")
                    breakdownRow(label: "Live Sets (.als)", size: size.formattedAls, icon: "doc")
                    breakdownRow(label: "Offline Demo Export (Kept Local)", size: size.formattedExports, icon: "speaker.wave.2", highlightGreen: true)
                }
            } else {
                Text("Analyzing project files…")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func breakdownRow(label: String, size: String, icon: String, highlightGreen: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(highlightGreen ? Color.green : Color.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
            Spacer()
            Text(size)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(highlightGreen ? Color.green : Color.secondary)
        }
    }

    // MARK: - Export Readiness Card
    private var exportStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Offline Auditioning Check", systemImage: "music.note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)

            switch exportReadiness {
            case .ready(let primaryTrack, let isOutdated):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("Export found: ")
                            .font(.system(size: 12, weight: .medium))
                        + Text(primaryTrack.displayName + "." + primaryTrack.fileExtension)
                            .font(.system(size: 12, weight: .semibold))
                    }

                    Text("This demo export will remain on your Mac so you can preview, loop, and listen to the song instantly in goodvibrations HQ.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)

                    if isOutdated {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(Color.orange)
                            Text("The export is older than your latest Ableton save.")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .missing:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("No Audio Export Found!")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }

                    Text("If you offload now, you will NOT be able to audition or listen to this project offline until you restore it. We recommend exporting an audio bounce from Ableton first.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)

                    Button {
                        dismiss()
                        store.openInAbleton(project)
                    } label: {
                        Label("Open in Ableton to Export First", systemImage: "arrow.up.forward.app")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Destination Card
    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cloud Archive Destination", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)

            HStack {
                Image(systemName: dropbox.isDropboxAvailable ? "checkmark.icloud.fill" : "folder.fill")
                    .foregroundStyle(dropbox.isDropboxAvailable ? Color.blue : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dropbox.isDropboxAvailable ? "Dropbox Archive Folder" : "Local Archive Vault")
                        .font(.system(size: 12, weight: .medium))
                    Text(archiveDestinationURL.path)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(dropbox.isDropboxAvailable
                 ? "Dropbox will automatically sync this compressed archive to your cloud storage."
                 : "Archive will be stored safely in Application Support until cloud sync is configured.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(Color.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(Color.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if isOffloading {
                ProgressView()
                    .controlSize(.small)
                Text("Archiving & freeing space…")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            } else {
                Button {
                    if case .missing = exportReadiness {
                        showBounceAlert = true
                    } else {
                        performOffload()
                    }
                } label: {
                    let savingsText = sizeBreakdown?.formattedEstimatedSavings ?? ""
                    Label(
                        savingsText.isEmpty ? "Offload to Cloud" : "Offload & Free \(savingsText)",
                        systemImage: "icloud.and.arrow.up"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingSize)
            }
        }
        .padding(20)
        .alert("Offload Without Audio Export?", isPresented: $showBounceAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Offload Anyway", role: .destructive) {
                performOffload()
            }
        } message: {
            Text("This project does not have an audio bounce. You will not be able to listen to it in goodvibrations HQ until you restore the project. Are you sure you want to proceed?")
        }
    }

    private func performOffload() {
        isOffloading = true
        errorMessage = nil

        Task {
            do {
                _ = try await offloadStore.offloadProject(
                    project: project,
                    customArchiveDestination: archiveDestinationURL,
                    keepAudioExport: true
                )
                // Refresh project in store
                await store.refreshProject(project)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isOffloading = false
            }
        }
    }
}
