import SwiftUI

/// Top studio navigation bar inspired by DAWbro and modern DAWs.
struct DawTopNavBar: View {
    @Binding var selection: WorkspaceSection
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @Environment(\.openSettings) private var openSettings
    @State private var hoveredSection: WorkspaceSection?

    var body: some View {
        HStack(spacing: 14) {
            // App Branding
            Button { openSettings() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accent)
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)

                    HStack(spacing: 4) {
                        Text("goodvibrations")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primaryText)
                        Text("HQ")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .buttonStyle(.plain)
            .help("goodvibrations HQ Settings (⌘,)")

            // Studio Tabs (DAWbro style, clearly outlined, full-width clickable target)
            HStack(spacing: 6) {
                tabButton(
                    title: "Project library",
                    icon: "line.3.horizontal",
                    section: .library
                )

                if let project = store.selectedProject {
                    projectTabButton(project: project)
                }

                tabButton(
                    title: "Focus studio",
                    icon: "sparkles",
                    section: .home
                )

                tabButton(
                    title: "Releases",
                    icon: "shippingbox",
                    section: .releases
                )

                tabButton(
                    title: "Tools",
                    icon: "wrench.and.screwdriver",
                    section: .tools
                )
            }

            Spacer()

            // Quick Hotkey HUD Button (Clickable & shows live exporting state)
            Button {
                globalHotkey.triggerExport()
            } label: {
                HStack(spacing: 6) {
                    if globalHotkey.isRunningExport {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                        Text("Exporting…")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accent)
                    } else {
                        Text("F1")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        Text("Auto-Export")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondaryText)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(globalHotkey.isRunningExport ? Color.accent.opacity(0.15) : Color.sidebarBg.opacity(0.7))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(globalHotkey.isRunningExport ? Color.accent : Color.white.opacity(0.14), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help(globalHotkey.lastResult ?? "Click or press F1 / ⇧⌘E anywhere to trigger Ableton auto-export")

            // Settings button
            Button { openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Color.hoverBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(red: 0.08, green: 0.085, blue: 0.095))
    }

    private func tabButton(title: String, icon: String, section: WorkspaceSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            selection = section
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : (isHovered ? Color(white: 0.95) : Color.secondaryText))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color(red: 0.17, green: 0.18, blue: 0.22)
                            : (isHovered ? Color(red: 0.13, green: 0.14, blue: 0.16) : Color(red: 0.10, green: 0.105, blue: 0.12))
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected
                            ? Color.accent
                            : (isHovered ? Color.white.opacity(0.32) : Color.white.opacity(0.14)),
                        lineWidth: isSelected ? 1.2 : 1.0
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            hoveredSection = isOver ? section : nil
        }
    }

    private func projectTabButton(project: Project) -> some View {
        let isSelected = selection == .project
        let isHovered = hoveredSection == .project

        return HStack(spacing: 0) {
            Button {
                selection = .project
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .accent : .secondaryText)
                    Text(project.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                }
                .foregroundColor(isSelected ? .white : (isHovered ? Color(white: 0.95) : Color.secondaryText))
                .padding(.leading, 11)
                .padding(.trailing, 6)
                .frame(height: 30)
            }
            .buttonStyle(.plain)

            Button {
                store.closeProjectTab()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : Color.secondaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Close project tab")
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected
                        ? Color(red: 0.17, green: 0.18, blue: 0.22)
                        : (isHovered ? Color(red: 0.13, green: 0.14, blue: 0.16) : Color(red: 0.10, green: 0.105, blue: 0.12))
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected
                        ? Color.accent
                        : (isHovered ? Color.white.opacity(0.32) : Color.white.opacity(0.14)),
                    lineWidth: isSelected ? 1.2 : 1.0
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered in
            if isHovered {
                hoveredSection = .project
            } else if hoveredSection == .project {
                hoveredSection = nil
            }
        }
    }
}
