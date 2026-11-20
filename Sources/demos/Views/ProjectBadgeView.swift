import SwiftUI

/// Meaningful project badge replacing the redundant [AL] badge.
/// Displays production stage (MIX, MST, DONE, IDEA), version iteration (v2, v8, 3v),
/// or demo status (DEMO) with crisp DAW-style color coding.
struct ProjectBadgeView: View {
    let project: Project
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    private var badgeData: (text: String, bg: Color, textCol: Color, border: Color) {
        let meta = metadataStore.metadata(for: project)
        if let phase = meta.productionPhase {
            let isClient = meta.projectKind == .client
            let color = isClient ? Color(hex: "FB923C") : Color(hex: "4ADE80")
            return (phase.shortTitle.uppercased(), color.opacity(0.18), color, color.opacity(0.40))
        }

        let progress = progressStore.progress(for: project)

        // 1. Production Stage if progressed past initial idea
        switch progress.stage {
        case .done:
            return ("DONE", Color(red: 0.10, green: 0.26, blue: 0.16), Color(red: 0.40, green: 0.90, blue: 0.55), Color.green.opacity(0.4))
        case .master:
            return ("MST", Color(red: 0.24, green: 0.14, blue: 0.32), Color(red: 0.85, green: 0.65, blue: 1.0), Color.purple.opacity(0.4))
        case .mix:
            return ("MIX", Color(red: 0.10, green: 0.22, blue: 0.32), Color(red: 0.45, green: 0.80, blue: 1.0), Color.blue.opacity(0.4))
        case .fullTrack:
            return ("ARRG", Color(red: 0.24, green: 0.20, blue: 0.12), Color(red: 0.95, green: 0.80, blue: 0.45), Color.orange.opacity(0.4))
        case .structure:
            return ("STRUC", Color(red: 0.22, green: 0.18, blue: 0.14), Color(red: 0.90, green: 0.70, blue: 0.50), Color.orange.opacity(0.35))
        case .spark:
            break
        }

        // 2. Version Iteration extracted from filename / project name (e.g. "v3", "v8", "v2.1")
        if let extracted = project.extractedVersionNumber {
            return (extracted, Color(red: 0.18, green: 0.19, blue: 0.22), Color.white, Color.white.opacity(0.18))
        }

        // 3. Multi-version count (e.g. "3v", "5v")
        if project.versions.count > 1 {
            return ("\(project.versions.count)v", Color(red: 0.18, green: 0.19, blue: 0.22), Color.white, Color.white.opacity(0.18))
        }

        // 4. Has Audio Demo / Export
        if project.hasExports {
            return ("DEMO", Color(red: 0.26, green: 0.18, blue: 0.10), Color.accent, Color.accent.opacity(0.4))
        }

        // 5. Default initial version
        return ("v1", Color(red: 0.18, green: 0.19, blue: 0.22), Color.secondaryText, Color.white.opacity(0.14))
    }

    var body: some View {
        let info = badgeData
        Text(info.text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundColor(info.textCol)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(info.bg)
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
            .overlay {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(info.border, lineWidth: 0.6)
            }
    }
}

/// Dedicated badge for Cloud / Storage status (separate column).
struct ProjectStorageBadgeView: View {
    let project: Project
    @ObservedObject private var offloadStore = ProjectOffloadStore.shared
    @ObservedObject private var dropbox = DropboxManager.shared
    @State private var isHovered = false

    private var activeState: OffloadOperationState? {
        offloadStore.activeOperations[project.folderURL.standardizedFileURL.path]
    }

    private var localFormattedSize: String? {
        offloadStore.cachedFormattedSize(for: project.folderURL)
    }

    var body: some View {
        Button {
            handleClick()
        } label: {
            HStack(spacing: 3.5) {
                if let state = activeState {
                    ProgressView()
                        .controlSize(.mini)
                    Text(state == .offloading ? "Offload…" : "Restore…")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                } else if project.isOffloaded {
                    Image(systemName: isHovered ? "icloud.and.arrow.down.fill" : "icloud.and.arrow.up.fill")
                        .font(.system(size: 8))
                    Text(isHovered ? "Restore" : (project.savedSpaceFormatted ?? "Cloud"))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                } else if dropbox.isUnderDropbox(url: project.folderURL) {
                    Image(systemName: isHovered ? "icloud.and.arrow.up" : "cloud.fill")
                        .font(.system(size: 8))
                    let label = isHovered ? "Offload" : (localFormattedSize ?? "Dropbox")
                    Text(label)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                } else {
                    Image(systemName: isHovered ? "icloud.and.arrow.up" : "internaldrive")
                        .font(.system(size: 8))
                    let label = isHovered ? "Offload" : (localFormattedSize ?? "Local")
                    Text(label)
                        .font(.system(size: 8.5, weight: isHovered ? .bold : .medium, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
            .overlay {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(borderColor, lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onAppear {
            if !project.isOffloaded {
                offloadStore.requestSize(for: project.folderURL)
            }
        }
        .help(tooltipText)
    }

    private func handleClick() {
        guard activeState == nil else { return }
        if project.isOffloaded {
            offloadStore.queueRestore(project: project)
        } else {
            offloadStore.queueOffload(project: project)
        }
    }

    private var foregroundColor: Color {
        if activeState != nil {
            return Color.white
        }
        if isHovered {
            return Color.white
        }
        if project.isOffloaded {
            return Color(hex: "60A5FA")
        } else if dropbox.isUnderDropbox(url: project.folderURL) {
            return Color(hex: "93C5FD")
        } else if localFormattedSize != nil {
            return Color.primaryText.opacity(0.85)
        } else {
            return Color.tertiaryText
        }
    }

    private var backgroundColor: Color {
        if activeState != nil {
            return Color.blue.opacity(0.40)
        }
        if isHovered {
            return project.isOffloaded ? Color.blue.opacity(0.35) : Color.accent.opacity(0.30)
        }
        if project.isOffloaded {
            return Color.blue.opacity(0.18)
        } else if dropbox.isUnderDropbox(url: project.folderURL) {
            return Color.blue.opacity(0.08)
        } else {
            return Color.white.opacity(0.03)
        }
    }

    private var borderColor: Color {
        if activeState != nil {
            return Color.blue.opacity(0.60)
        }
        if isHovered {
            return project.isOffloaded ? Color.blue.opacity(0.60) : Color.accent.opacity(0.50)
        }
        if project.isOffloaded {
            return Color.blue.opacity(0.40)
        } else if dropbox.isUnderDropbox(url: project.folderURL) {
            return Color.blue.opacity(0.20)
        } else {
            return Color.white.opacity(0.06)
        }
    }

    private var tooltipText: String {
        if let state = activeState {
            return state == .offloading ? "Offloading project in background…" : "Restoring project in background…"
        }
        if project.isOffloaded {
            let freed = project.savedSpaceFormatted.map { " (\($0) freed)" } ?? ""
            return "Offloaded to cloud archive\(freed). Click to restore immediately."
        } else {
            let sizeInfo = localFormattedSize.map { " (\($0) on disk)" } ?? ""
            return "Local project\(sizeInfo). Click to offload to cloud and free space."
        }
    }
}
