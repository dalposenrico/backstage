import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var projectNotes: ProjectNotesStore
    @EnvironmentObject var projectProgress: ProjectProgressStore
    @EnvironmentObject var projectTodos: ProjectTodoStore
    @EnvironmentObject var dailyFocus: DailyFocusStore
    @EnvironmentObject var focusCalendar: FocusCalendarStore
    @EnvironmentObject var globalHotkey: GlobalHotkeyManager
    @Environment(\.openWindow) private var openWindow
    @AppStorage("compactWorkspaceNavigation") private var compactWorkspaceNavigation = false
    @State private var showProjectInspector = false
    @State private var projectWorkspaceExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Top studio navigation bar (DAWbro style)
            DawTopNavBar(selection: $store.activeWorkspaceSection)

            ZStack {
                LibraryWorkspace(
                    showProjectInspector: $showProjectInspector,
                    projectWorkspaceExpanded: $projectWorkspaceExpanded
                )
                .opacity(store.activeWorkspaceSection == .library ? 1 : 0)
                .allowsHitTesting(store.activeWorkspaceSection == .library)

                if store.activeWorkspaceSection == .project, let project = store.selectedProject {
                    ProjectFullWorkspaceView(project: project) {
                        store.closeProjectTab()
                    }
                    .background(Color.appBg)
                }

                if store.activeWorkspaceSection == .home {
                    HomeDashboardView { project in
                        store.openProjectTab(project)
                    }
                    .background(Color.appBg)
                }

                if store.activeWorkspaceSection == .releases {
                    ReleasesHubView {
                        store.activeWorkspaceSection = .library
                        showProjectInspector = true
                    }
                    .background(Color.appBg)
                }

                if store.activeWorkspaceSection == .tools {
                    ToolsHubView()
                        .background(Color.appBg)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.divider)
            PlayerBarView()
        }
        .background(Color.appBg)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let opening = store.openingAbletonProject {
                    AbletonOpeningBanner(opening: opening) {
                        store.dismissAbletonOpeningAlert()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if globalHotkey.isRunningExport {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(globalHotkey.lastResult ?? "⚡ Running Ableton auto-export...")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.elevatedBg, in: Capsule())
                    .overlay(Capsule().stroke(Color.accent.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 14)
        }
        .animation(.easeInOut(duration: 0.25), value: store.openingAbletonProject)
        .animation(.easeInOut(duration: 0.2), value: globalHotkey.isRunningExport)
        .animation(.easeInOut(duration: 0.2), value: store.currentOpenProjectURL)
        .onChange(of: showProjectInspector) { _, isShowing in
            if !isShowing { projectWorkspaceExpanded = false }
        }
        .onChange(of: focusCalendar.dueEvent) { _, event in
            if let event { presentScheduledFocus(event) }
        }
        .task {
            await focusCalendar.refresh()
            focusCalendar.checkForDueEvent()
            if let event = focusCalendar.dueEvent { presentScheduledFocus(event) }
        }
        .onAppear {
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow, window.firstResponder is NSTextView || window.firstResponder is NSTextField {
                    window.makeFirstResponder(nil)
                }
                if settings.isFloatingWidgetActive {
                    openWindow(id: "floating-widget")
                    WindowPresenter.showFloatingWidget(pinned: settings.isFloatingWidgetPinned, collapsed: settings.isFloatingWidgetCollapsed)
                }
                WindowPresenter.showMainWindow()
            }
        }
        .preferredColorScheme(settings.appearanceMode.colorSchemeOverride)
        .frame(minWidth: 940, minHeight: 560)
        .onOpenURL { url in
            if let projectPath = FocusCalendarEventContent.projectPath(from: url) {
                presentScheduledFocus(
                    projectPath: projectPath,
                    durationMinutes: FocusCalendarEventContent.durationMinutes(from: url) ?? dailyFocus.focusMinutes
                )
            } else if url.scheme == "goodvibrations", url.host == "open-project" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let path = components.queryItems?.first(where: { $0.name == "path" })?.value,
                   !path.isEmpty {
                    let folderURL = URL(fileURLWithPath: path)
                    store.openProjectWhenAvailable(folderURL: folderURL)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                store.openExportCheckpoint(from: url)
            }
        }
        .sheet(item: $store.exportCheckpointProject) { project in
            ExportCheckpointView(project: project)
                .environmentObject(projectNotes)
                .environmentObject(projectProgress)
        }
        .alert("Export Checkpoint", isPresented: Binding(
            get: { store.checkpointError != nil },
            set: { if !$0 { store.checkpointError = nil } }
        )) {
            Button("OK", role: .cancel) { store.checkpointError = nil }
        } message: {
            Text(store.checkpointError ?? "")
        }
    }

    private func presentScheduledFocus(_ event: ScheduledFocusEvent) {
        presentScheduledFocus(projectPath: event.projectPath, durationMinutes: event.durationMinutes)
        focusCalendar.acknowledgeDueEvent()
    }

    private func presentScheduledFocus(projectPath: String, durationMinutes: Int) {
        guard let project = store.projects.first(where: { $0.folderURL.path == projectPath }) else {
            focusCalendar.acknowledgeDueEvent()
            return
        }
        let tasks = projectTodos.openTodos(for: project).map(\.title)
        dailyFocus.prepareScheduledFocus(
            project: project,
            taskTitles: tasks,
            durationMinutes: durationMinutes
        )
        store.selectedProject = project
        openWindow(id: "focus-timer")
        WindowPresenter.showFocusTimer(pinned: dailyFocus.keepsTimerOnTop)
    }
}

private struct LibraryWorkspace: View {
    @Binding var showProjectInspector: Bool
    @Binding var projectWorkspaceExpanded: Bool
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settings: SettingsStore
    @AppStorage(ProjectDockSizing.storageKey) private var projectDockHeight = ProjectDockSizing.defaultHeight
    @AppStorage(ProjectDockSizing.expansionStorageKey) private var isProjectDockExpanded = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if showProjectInspector,
                   projectWorkspaceExpanded,
                   let project = store.selectedProject {
                    ProjectWorkspaceDock(
                        project: project,
                        collapse: { projectWorkspaceExpanded = false },
                        close: {
                            projectWorkspaceExpanded = false
                            showProjectInspector = false
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            SidebarView()
                                .frame(width: settings.sidebarWidth)

                            ResizableDivider(width: $settings.sidebarWidth)

                            ProjectBrowserListView(showProjectInspector: $showProjectInspector)
                                .frame(minWidth: 300, maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)

                        if let project = dockProject {
                            if isProjectDockExpanded {
                                ProjectDockResizeHandle(
                                    height: $projectDockHeight,
                                    availableHeight: proxy.size.height
                                )
                            }

                            CurrentSessionBar(
                                project: project,
                                eyebrow: store.currentOpenProject?.id == project.id
                                    ? "CURRENT SESSION"
                                    : "SELECTED PROJECT",
                                isExpanded: $isProjectDockExpanded
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    store.selectedProject = project
                                    showProjectInspector = true
                                    projectWorkspaceExpanded = true
                                }
                            }
                            .frame(height: ProjectDockSizing.presentedHeight(
                                projectDockHeight,
                                isExpanded: isProjectDockExpanded,
                                availableHeight: proxy.size.height
                            ), alignment: .top)
                            .clipped()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: projectWorkspaceExpanded)
            .animation(.easeInOut(duration: 0.18), value: showProjectInspector)
        }
    }

    private var dockProject: Project? {
        if showProjectInspector, let selectedProject = store.selectedProject {
            return selectedProject
        }
        return store.currentOpenProject
    }
}

enum ProjectDockSizing {
    static let storageKey = "projectDockHeight"
    static let expansionStorageKey = "currentSessionBarExpanded"
    static let defaultHeight = 190.0
    static let expandedDefaultHeight = 360.0
    static let collapsedHeight: CGFloat = 36.0
    static let minimumHeight = 126.0
    static let maximumHeight = 560.0
    static let minimumBrowserHeight = 150.0
    static let keyboardStep = 32.0

    static func clamped(_ height: Double, availableHeight: CGFloat? = nil) -> CGFloat {
        let availableMaximum = availableHeight.map {
            max(minimumHeight, Double($0) - minimumBrowserHeight)
        } ?? maximumHeight
        return CGFloat(min(min(maximumHeight, availableMaximum), max(minimumHeight, height)))
    }

    static func adjusted(_ height: Double, by delta: Double) -> Double {
        min(maximumHeight, max(minimumHeight, height + delta))
    }

    static func presentedHeight(
        _ expandedHeight: Double,
        isExpanded: Bool,
        availableHeight: CGFloat? = nil
    ) -> CGFloat {
        isExpanded ? clamped(expandedHeight, availableHeight: availableHeight) : collapsedHeight
    }
}

private struct ProjectDockResizeHandle: View {
    @Binding var height: Double
    let availableHeight: CGFloat
    @State private var startingHeight = 0.0
    @State private var isDragging = false
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.accent.opacity(isHovered || isDragging ? 0.72 : 0.34))
                .frame(width: 42, height: 3)
        }
        .frame(height: 9)
        .contentShape(Rectangle())
        .onHover { hovered in
            isHovered = hovered
            if hovered { NSCursor.resizeUpDown.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startingHeight = height
                    }
                    let proposedHeight = startingHeight - Double(value.translation.height)
                    height = Double(ProjectDockSizing.clamped(
                        proposedHeight,
                        availableHeight: availableHeight
                    ))
                }
                .onEnded { _ in isDragging = false }
        )
        .background(Color.sidebarBg.opacity(0.82))
        .help("Drag to resize the project panel · ⌘− / ⌘+")
        .accessibilityLabel("Resize project panel")
        .accessibilityValue("\(Int(height)) points high")
    }
}

private struct ProjectWorkspaceDock: View {
    let project: Project
    let collapse: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("PROJECT WORKSPACE", systemImage: "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.accent)
                Text(project.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                Spacer()
                Button(action: collapse) {
                    Label("Back to Library", systemImage: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
                Button {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
                .help("Toggle macOS full screen")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(Color.hoverBg, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close project workspace")
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Color.sidebarBg.opacity(0.78))

            Divider().background(Color.accent.opacity(0.24))

            TrackListView(project: project, allowsExpandedWorkspace: false)
        }
        .background(Color.appBg)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accent.opacity(0.72)).frame(height: 2)
        }
        .onExitCommand(perform: collapse)
    }
}

struct ProjectFullWorkspaceView: View {
    let project: Project
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TrackListView(project: project, allowsExpandedWorkspace: false)
        }
        .background(Color.appBg)
    }
}

private struct WorkspaceSidebar: View {
    @Binding var selection: WorkspaceSection
    @Binding var isCompact: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if !isCompact {
                    Button { openSettings() } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.accent)
                                Image(systemName: "waveform")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 26, height: 26)
                            Text("goodvibrations")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")
                }

                Spacer(minLength: 0)

                Button { isCompact.toggle() } label: {
                    Image(systemName: isCompact ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondaryText)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .help(isCompact ? "Expand workspace navigation" : "Collapse workspace navigation to icons")
            }
            .padding(.horizontal, isCompact ? 16 : 10)
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 4) {
                ForEach(WorkspaceSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: section.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 17)
                            if !isCompact {
                                Text(section.title)
                                    .font(.system(size: 12, weight: selection == section ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                        }
                        .foregroundColor(selection == section ? .primaryText : .secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == section ? Color.selectedBg : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(section.title)
                }
            }
            .padding(.horizontal, 7)

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                if !isCompact {
                    Text("Local only")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                }
            }
            .padding(isCompact ? 24 : 12)
        }
        .background(Color.sidebarBg)
    }
}

// MARK: - Resizable divider handle

struct ResizableDivider: View {
    @Binding var width: CGFloat
    @State private var isDragging  = false
    @State private var startWidth: CGFloat = 0
    @State private var isHovered   = false

    var body: some View {
        ZStack {
            Color.divider.frame(width: 1)
            // Extra-wide invisible hit area makes it easy to grab
            Color.clear.frame(width: 10)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .onHover { hovered in
            isHovered = hovered
            if hovered { NSCursor.resizeLeftRight.push() }
            else        { NSCursor.pop() }
        }
        .overlay(
            // Subtle highlight while hovering
            Color.accent.opacity(isHovered || isDragging ? 0.35 : 0)
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startWidth = width
                    }
                    width = max(190, min(440, startWidth + value.translation.width))
                }
                .onEnded { _ in isDragging = false }
        )
    }
}
