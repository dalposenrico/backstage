import SwiftUI

/// Minimal, connected DAW tab outline shape (open at bottom).
struct DawTabOutline: Shape {
    var cornerRadius: CGFloat = 5
    var strokeWidth: CGFloat = 2.0
    var bottomExtension: CGFloat = 2.0

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

/// Solid tab background fill (extends down to seamlessly cover baseline divider).
struct DawTabFill: Shape {
    var cornerRadius: CGFloat = 5
    var bottomExtension: CGFloat = 2.0

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
    @State private var hoveredProjectID: Project.ID?

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
            // Horizontal baseline across the entire navbar width forming the top outline of the selected page
            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(height: 2)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
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

                // Studio & Project Tabs (Chrome-style tabs connected directly to page below)
                HStack(alignment: .bottom, spacing: 4) {
                    tabButton(
                        title: "Project library",
                        icon: "line.3.horizontal",
                        section: .library
                    )

                    ForEach(store.openProjects) { project in
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

                // Top Bar Live Capsule Pill & Settings
                HStack(spacing: 8) {
                    topBarLivePill

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

    // MARK: - Top Bar Live Capsule Pill (Morph target for floating mini HUD)

    private var topBarLivePill: some View {
        let isOpening = store.openingAbletonProject?.phase == .opening
        let isLiveActive = store.currentOpenProject != nil

        let activeProj = store.currentOpenProject ?? store.selectedProject ?? store.recentProjects.first

        let projectName: String = {
            if isOpening {
                return store.openingAbletonProject?.projectName ?? "Ableton Live"
            }
            if let active = store.currentOpenProject {
                return active.name
            }
            return activeProj?.name ?? "goodvibrations HQ"
        }()

        let subtitle: String = {
            if isOpening {
                return "Opening in Live…"
            }
            if let ver = store.currentOpenProject?.newestAbletonVersion?.displayName {
                return "\(ver) • Ableton Live"
            }
            if isLiveActive {
                return "Active in Live"
            }
            if let sel = store.selectedProject {
                return "\(sel.name) • Ready"
            }
            return "goodvibrations HQ"
        }()

        return HStack(spacing: 7) {
            // Clickable info area: collapses back to mini floating HUD
            Button {
                WindowPresenter.collapseMainWindowToPill()
            } label: {
                HStack(spacing: 7) {
                    // Status indicator dot
                    if isOpening {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else if isLiveActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                            .shadow(color: Color.green.opacity(0.6), radius: 3)
                    } else {
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(projectName)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(hex: "F3F4F6"))
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color(hex: "9CA3AF"))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 160, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to collapse back into floating mini HUD")

            // Open in Ableton Live Button
            Button {
                if let project = store.currentOpenProject ?? activeProj {
                    store.openInAbleton(project)
                } else {
                    _ = AbletonSessionDetector.activateAbleton()
                }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(hex: "E5E7EB"))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open in Ableton Live")

            // Auto-Export Button ("E")
            Button {
                if globalHotkey.isRunningExport {
                    globalHotkey.cancelExport()
                } else if let project = activeProj {
                    store.openAndExport(project)
                } else {
                    globalHotkey.triggerExport()
                }
            } label: {
                if globalHotkey.isRunningExport {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                } else {
                    Text("E")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(isLiveActive ? Color.accentColor : Color(hex: "E5E7EB"))
                        .frame(width: 20, height: 20)
                        .background(isLiveActive ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.10), in: Circle())
                }
            }
            .buttonStyle(.plain)
            .help(globalHotkey.isRunningExport ? "Export running — click to cancel" : "Auto-Export project (F1 / ⇧⌘E)")

            // Collapse Icon Button
            Button {
                WindowPresenter.collapseMainWindowToPill()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color(hex: "9CA3AF"))
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Collapse to floating mini HUD")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(hex: "16191E"))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func tabButton(title: String, icon: String, section: WorkspaceSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selection = section
            }
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
                    DawTabFill(cornerRadius: 5, bottomExtension: 2.0)
                        .fill(activeTabBackground)
                } else if isHovered {
                    DawTabFill(cornerRadius: 5, bottomExtension: 0)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .overlay {
                if isSelected {
                    DawTabOutline(cornerRadius: 5, strokeWidth: 2.0, bottomExtension: 2.0)
                        .stroke(Color.accent, lineWidth: 2.0)
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
        let isSelected = selection == .project && store.selectedProject?.id == project.id
        let isHovered = hoveredProjectID == project.id

        return HStack(spacing: 0) {
            Button {
                store.selectedProject = project
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selection = .project
                }
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
                store.closeProjectTab(project)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? Color.white.opacity(0.8) : Color.secondaryText)
                    .frame(width: 18, height: 18)
                    .background(isHovered ? Color.white.opacity(0.08) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Close tab (\(project.name))")
        }
        .frame(height: 35)
        .background {
            if isSelected {
                DawTabFill(cornerRadius: 5, bottomExtension: 2.0)
                    .fill(Color.appBg)
            } else if isHovered {
                DawTabFill(cornerRadius: 5, bottomExtension: 0)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .overlay {
            if isSelected {
                DawTabOutline(cornerRadius: 5, strokeWidth: 2.0, bottomExtension: 2.0)
                    .stroke(Color.accent, lineWidth: 2.0)
            } else if isHovered {
                DawTabFill(cornerRadius: 5, bottomExtension: 0)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.0)
            }
        }
        .contentShape(Rectangle())
        .onHover { isOver in
            hoveredProjectID = isOver ? project.id : nil
        }
        .contextMenu {
            Button("Close Tab") {
                store.closeProjectTab(project)
            }
            Button("Close Other Tabs") {
                store.closeOtherProjectTabs(keeping: project)
            }
            Divider()
            Button("Open in Ableton Live") {
                store.openInAbleton(project)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.folderURL])
            }
        }
    }
}
