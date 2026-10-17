import SwiftUI

/// Minimal, connected DAW tab outline shape (open at bottom).
struct DawTabOutline: Shape {
    var cornerRadius: CGFloat = 5
    var strokeWidth: CGFloat = 1.2
    var bottomExtension: CGFloat = 1.0

    func path(in rect: CGRect) -> Path {
        let half = strokeWidth / 2.0
        let leftX = rect.minX + half
        let rightX = rect.maxX - half
        let topY = rect.minY + half
        let bottomY = rect.maxY + bottomExtension

        var path = Path()
        path.move(to: CGPoint(x: leftX, y: bottomY))
        path.addLine(to: CGPoint(x: leftX, y: topY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: leftX + cornerRadius, y: topY),
            control: CGPoint(x: leftX, y: topY)
        )
        path.addLine(to: CGPoint(x: rightX - cornerRadius, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: rightX, y: topY + cornerRadius),
            control: CGPoint(x: rightX, y: topY)
        )
        path.addLine(to: CGPoint(x: rightX, y: bottomY))
        return path
    }
}

/// Solid tab background fill (extends 1px down to seamlessly cover baseline divider).
struct DawTabFill: Shape {
    var cornerRadius: CGFloat = 5
    var bottomExtension: CGFloat = 1.0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottomY = rect.maxY + bottomExtension
        path.move(to: CGPoint(x: rect.minX, y: bottomY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: bottomY))
        path.closeSubpath()
        return path
    }
}

/// Top studio navigation bar inspired by DAWbro and modern DAWs.
/// Tabs have connected outlines that merge directly into the workspace below.
struct DawTopNavBar: View {
    @Binding var selection: WorkspaceSection
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @Environment(\.openSettings) private var openSettings
    @State private var hoveredSection: WorkspaceSection?

    private var activeTabBackground: Color {
        switch selection {
        case .library:
            return Color.sidebarBg
        case .project, .home, .releases, .tools:
            return Color.appBg
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Horizontal baseline across the entire navbar width
            Rectangle()
                .fill(Color.divider)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                // App Branding (vertically centered)
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
                .frame(maxHeight: .infinity, alignment: .center)

                // Studio Tabs (DAWbro style, connected directly to page below)
                HStack(alignment: .bottom, spacing: 4) {
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
                .frame(maxHeight: .infinity, alignment: .bottom)

                Spacer()

                // Quick Hotkey HUD Button + Settings (vertically centered)
                HStack(spacing: 8) {
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
                            } else if let result = globalHotkey.lastResult, result.contains("Untitled") {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text("Save Track First")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.orange)
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
                                .fill(
                                    globalHotkey.isRunningExport
                                        ? Color.accent.opacity(0.15)
                                        : (globalHotkey.lastResult?.contains("Untitled") == true
                                            ? Color.orange.opacity(0.12)
                                            : Color.sidebarBg.opacity(0.7))
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    globalHotkey.isRunningExport
                                        ? Color.accent
                                        : (globalHotkey.lastResult?.contains("Untitled") == true
                                            ? Color.orange.opacity(0.5)
                                            : Color.white.opacity(0.14)),
                                    lineWidth: 1
                                )
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
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .padding(.horizontal, 14)
        }
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
                    .foregroundColor(isSelected ? .accent : (isHovered ? .white : .secondaryText))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : (isHovered ? .white : .secondaryText))
            }
            .padding(.horizontal, 13)
            .frame(height: 35)
            .background {
                if isSelected {
                    DawTabFill(cornerRadius: 5)
                        .fill(activeTabBackground)
                } else if isHovered {
                    DawTabFill(cornerRadius: 5, bottomExtension: 0)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .overlay {
                if isSelected {
                    DawTabOutline(cornerRadius: 5, strokeWidth: 1.2)
                        .stroke(Color.accent, lineWidth: 1.2)
                } else if isHovered {
                    DawTabFill(cornerRadius: 5, bottomExtension: 0)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.0)
                }
            }
            .contentShape(Rectangle())
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
                        .foregroundColor(isSelected ? .accent : (isHovered ? .white : .secondaryText))
                    Text(project.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : (isHovered ? .white : .secondaryText))
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .frame(height: 35)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.closeProjectTab()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : Color.secondaryText)
                    .frame(width: 18, height: 18)
                    .background(isHovered ? Color.white.opacity(0.08) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Close project tab")
        }
        .frame(height: 35)
        .background {
            if isSelected {
                DawTabFill(cornerRadius: 5)
                    .fill(Color.appBg)
            } else if isHovered {
                DawTabFill(cornerRadius: 5, bottomExtension: 0)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .overlay {
            if isSelected {
                DawTabOutline(cornerRadius: 5, strokeWidth: 1.2)
                    .stroke(Color.accent, lineWidth: 1.2)
            } else if isHovered {
                DawTabFill(cornerRadius: 5, bottomExtension: 0)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.0)
            }
        }
        .contentShape(Rectangle())
        .onHover { isOver in
            if isOver {
                hoveredSection = .project
            } else if hoveredSection == .project {
                hoveredSection = nil
            }
        }
    }
}
