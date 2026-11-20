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
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var dropbox = DropboxManager.shared
    @State private var isHovered = false
    @State private var isRestoring = false
    @State private var showRestoreConfirm = false

    var body: some View {
        Button {
            if project.isOffloaded {
                showRestoreConfirm = true
            } else {
                store.offloadModalProject = project
            }
        } label: {
            HStack(spacing: 3.5) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Restoring…")
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
                    Text(isHovered ? "Offload" : "Dropbox")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                } else {
                    Image(systemName: isHovered ? "icloud.and.arrow.up" : "internaldrive")
                        .font(.system(size: 8))
                    Text(isHovered ? "Offload" : "Local")
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
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .alert("Restore '\(project.name)' from Cloud?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore Project\(project.savedSpaceFormatted.map { " (\($0))" } ?? "")") {
                isRestoring = true
                Task {
                    try? await store.restoreOffloadedProject(project)
                    isRestoring = false
                }
            }
        } message: {
            Text("This will unpack all samples, audio recordings, and Ableton sets back to your local drive.")
        }
        .help(tooltipText)
    }

    private var foregroundColor: Color {
        if isHovered {
            return Color.white
        }
        if project.isOffloaded {
            return Color(hex: "60A5FA")
        } else if dropbox.isUnderDropbox(url: project.folderURL) {
            return Color(hex: "93C5FD")
        } else {
            return Color.tertiaryText
        }
    }

    private var backgroundColor: Color {
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
        if project.isOffloaded {
            let freed = project.savedSpaceFormatted.map { " (\($0) freed)" } ?? ""
            return "Offloaded to cloud archive\(freed). Click to restore project."
        } else if dropbox.isUnderDropbox(url: project.folderURL) {
            return "Stored in Dropbox folder. Click to offload heavy assets to cloud."
        } else {
            return "Stored locally on Mac. Click to offload to cloud archive."
        }
    }
}
