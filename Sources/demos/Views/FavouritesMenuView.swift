import AppKit
import SwiftUI

private enum QuickAccessTab: String, CaseIterable {
    case songs = "Songs"
    case tools = "Tools"
}

struct FavouritesMenuView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var toolLaunchers: ToolLauncherStore
    @EnvironmentObject private var untitledSync: UntitledSyncStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @EnvironmentObject private var dailyFocus: DailyFocusStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTab: QuickAccessTab = .songs
    @State private var searchText = ""
    @State private var isAddingMacro = false
    @State private var macroName = ""
    @FocusState private var isMacroNameFocused: Bool

    private var projects: [Project] {
        let matches = searchText.isEmpty ? store.projects : store.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return matches.sorted { $0.latestModification > $1.latestModification }
    }

    private var tools: [ToolLauncher] {
        searchText.isEmpty ? toolLaunchers.tools : toolLaunchers.tools.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var showsAbletonExport: Bool {
        searchText.isEmpty
            || "Ableton Auto-Export".localizedCaseInsensitiveContains(searchText)
            || "Export".localizedCaseInsensitiveContains(searchText)
            || "F1".localizedCaseInsensitiveContains(searchText)
    }

    private var showsABCompare: Bool {
        searchText.isEmpty
            || "Versions".localizedCaseInsensitiveContains(searchText)
            || "A/B Compare".localizedCaseInsensitiveContains(searchText)
    }

    private var showsProjectNotes: Bool {
        searchText.isEmpty
            || "Project Notes".localizedCaseInsensitiveContains(searchText)
            || "Notes".localizedCaseInsensitiveContains(searchText)
    }

    private var showsUntitledSync: Bool {
        searchText.isEmpty
            || "untitled".localizedCaseInsensitiveContains(searchText)
            || "Automation".localizedCaseInsensitiveContains(searchText)
    }

    private var showsFocusStudio: Bool {
        searchText.isEmpty
            || "Focus".localizedCaseInsensitiveContains(searchText)
            || "Timer".localizedCaseInsensitiveContains(searchText)
            || "Planner".localizedCaseInsensitiveContains(searchText)
    }

    private var showsCrashAnalyzer: Bool {
        searchText.isEmpty || "Ableton Crash Analyzer".localizedCaseInsensitiveContains(searchText)
    }

    private var showsNameWorlds: Bool {
        searchText.isEmpty
            || "Name Worlds".localizedCaseInsensitiveContains(searchText)
            || "Name Generator".localizedCaseInsensitiveContains(searchText)
    }

    private var visibleToolCount: Int {
        tools.count
            + (showsAbletonExport ? 1 : 0)
            + (showsABCompare ? 1 : 0)
            + (showsProjectNotes ? 1 : 0)
            + (showsUntitledSync ? 1 : 0)
            + (showsFocusStudio ? 1 : 0)
            + (showsNameWorlds ? 1 : 0)
            + (showsCrashAnalyzer ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            if store.audioPlayer.currentTrack != nil { nowPlaying }
            footer
        }
        .frame(width: 420, height: 520)
        .background(.regularMaterial)
        .task {
            while !Task.isCancelled {
                await store.scan()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("GV")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                Text("goodvibrations HQ").font(.caption).foregroundStyle(.secondary)
                Spacer()

                // Toggle Floating HUD
                Button {
                    settings.isFloatingWidgetActive.toggle()
                    if settings.isFloatingWidgetActive {
                        openWindow(id: "floating-widget")
                        WindowPresenter.showFloatingWidget(pinned: settings.isFloatingWidgetPinned, collapsed: settings.isFloatingWidgetCollapsed)
                    } else {
                        WindowPresenter.hideFloatingWidget()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: settings.isFloatingWidgetActive ? "macwindow.on.rectangle" : "macwindow")
                            .font(.system(size: 9.5))
                        Text(settings.isFloatingWidgetActive ? "HUD Active" : "HUD")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(settings.isFloatingWidgetActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(settings.isFloatingWidgetActive ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(settings.isFloatingWidgetActive ? "Deactivate Floating HUD" : "Activate Floating HUD")

                if selectedTab == .tools {
                    addToolMenu
                }
            }
            Picker("Section", selection: $selectedTab) {
                ForEach(QuickAccessTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(selectedTab == .songs ? "Search songs…" : "Search tools…", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .onChange(of: selectedTab) { searchText = "" }
    }

    @ViewBuilder private var content: some View {
        if selectedTab == .songs {
            if projects.isEmpty {
                emptyState(title: store.rootFolderURL == nil ? "Choose a music folder in goodvibrations HQ" : "No songs found",
                           symbol: "music.note.list")
            } else {
                VStack(spacing: 0) {
                    if searchText.isEmpty {
                        quickOpenInDawBanner
                    }
                    ScrollView { LazyVStack(spacing: 0) { ForEach(projects) { songRow($0) } } }
                }
            }
        } else {
            VStack(spacing: 0) {
                if isAddingMacro {
                    macroEditor
                    Divider()
                }
                if visibleToolCount == 0 {
                    emptyState(title: "Add your first tool", symbol: "hammer")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            floatingHudRow
                            if showsAbletonExport { abletonExportRow }
                            if showsABCompare { abCompareRow }
                            if showsProjectNotes { projectNotesRow }
                            if showsUntitledSync { untitledAutomationRow }
                            if showsFocusStudio { focusStudioRow }
                            if showsNameWorlds { nameWorldsRow }
                            if showsCrashAnalyzer { crashAnalyzerRow }
                            ForEach(tools) { toolRow($0) }
                        }
                    }
                }
            }
        }
    }

    private var floatingHudRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Floating Studio HUD")
                    Text("⇧⌘W")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Always-on-top resizable companion widget for Live")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { settings.isFloatingWidgetActive },
                set: { active in
                    settings.isFloatingWidgetActive = active
                    if active {
                        openWindow(id: "floating-widget")
                        WindowPresenter.showFloatingWidget(pinned: settings.isFloatingWidgetPinned, collapsed: settings.isFloatingWidgetCollapsed)
                    } else {
                        WindowPresenter.hideFloatingWidget()
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var abletonExportRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ableton Auto-Export")
                    Text("F1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                }
                Text(globalHotkey.isRunningExport ? "Exporting from active Live session…" : (globalHotkey.lastResult ?? "Auto-versions & exports current Live set"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(globalHotkey.isRunningExport ? "Running…" : "Run F1") {
                globalHotkey.triggerExport()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(globalHotkey.isRunningExport)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if !globalHotkey.isRunningExport {
                globalHotkey.triggerExport()
            }
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var abCompareRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.2.square")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Versions")
                    Text("⇧⌘V")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("A/B version compare & mix evolution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Launch") {
                openWindow(id: "ab-compare")
                WindowPresenter.showABCompare()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            openWindow(id: "ab-compare")
            WindowPresenter.showABCompare()
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var projectNotesRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 18))
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Project Notes")
                    Text("⇧⌘N")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Floating scratchpad synced to selected project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                openWindow(id: "project-notes")
                WindowPresenter.showProjectNotes()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            openWindow(id: "project-notes")
            WindowPresenter.showProjectNotes()
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var untitledAutomationRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("[untitled] Automation")
                    Text("⇧⌘U")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Auto-upload exported mixes to [untitled]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                openWindow(id: "untitled-automation")
                WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: true)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            openWindow(id: "untitled-automation")
            WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: true)
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var focusStudioRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 18))
                .foregroundStyle(.mint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus Timer & Planner")
                Text("Daily sprint timer and session goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                openWindow(id: "focus-timer")
                WindowPresenter.showFocusTimer(pinned: dailyFocus.keepsTimerOnTop)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            openWindow(id: "focus-timer")
            WindowPresenter.showFocusTimer(pinned: dailyFocus.keepsTimerOnTop)
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private var nameWorldsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Name Worlds")
                Text("Project names from vibes and tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Launch", action: openNameWorlds)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(perform: openNameWorlds)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private func openNameWorlds() {
        openWindow(id: "name-generator")
        WindowPresenter.showNameGenerator(dismissingMenuBarPanel: true)
    }

    private var crashAnalyzerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(.purple)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ableton Crash Analyzer")
                Text("Crash history and plug-in diagnosis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Launch") { toolLaunchers.launchAbletonCrashAnalyzer() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { toolLaunchers.launchAbletonCrashAnalyzer() }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    @ViewBuilder private var quickOpenInDawBanner: some View {
        if let project = store.currentOpenProject ?? store.recentProjects.first,
           project.newestAbletonVersion != nil {
            let isCurrentSession = store.currentOpenProject?.id == project.id
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isCurrentSession ? Color.green : Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text(isCurrentSession ? "CURRENT LIVE SESSION" : "RECENT PROJECT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(isCurrentSession ? .green : .accentColor)
                    }
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    store.openInAbleton(project)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("DAW")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help(isCurrentSession ? "Switch to current session in Ableton Live" : "Open directly in DAW without opening goodvibrations HQ")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.10))
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }

    private func songRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Button {
                if let track = project.sortedTracks.first { store.playTrack(track) }
                else { NSWorkspace.shared.open(project.folderURL) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.favourites.contains(project.folderURL) ? "star.fill" : "music.note")
                        .font(.system(size: 11))
                        .frame(width: 16)
                        .foregroundStyle(store.favourites.contains(project.folderURL) ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(project.latestSavedItem?.name ?? "Show in Finder")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let saved = project.latestSavedItem?.date {
                                Text("·").font(.system(size: 9)).foregroundStyle(.tertiary)
                                Text(saved.menuSavedDate)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Open in DAW directly without opening goodvibrations HQ
            if project.newestAbletonVersion != nil {
                Button {
                    store.openInAbleton(project)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 9))
                        Text("DAW")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.8)
                    )
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(store.isCurrentOpenProject(project) ? "Switch to current session in Ableton Live" : "Open directly in DAW without opening goodvibrations HQ")
            }

            Button { store.openInMainWindow(project) } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("View project in goodvibrations HQ")

            if let latestExport = project.sortedTracks.first {
                untitledMenu(track: latestExport, project: project)
            }

            Button { NSWorkspace.shared.open(project.folderURL) } label: {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Open in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .contextMenu {
            if project.newestAbletonVersion != nil {
                Button {
                    store.openInAbleton(project)
                } label: {
                    Label("Open in Ableton Live (DAW)", systemImage: "arrow.up.forward.app.fill")
                }
                Divider()
            }
            Button(store.favourites.contains(project.folderURL) ? "Remove from Favourites" : "Add to Favourites") {
                store.toggleFavourite(project)
            }
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 36) }
    }

    private func untitledMenu(track: Track, project: Project) -> some View {
        let status = untitledSync.status(for: track)
        return Menu {
            if status != .synced {
                Button(status == .updateAvailable ? "Send New Version" : "Send to [untitled]") {
                    untitledSync.prepare(track, project: project)
                    openWindow(id: "untitled-automation")
                    WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: true)
                }
            }
            if status == .sending {
                Button("Mark as On [untitled]") { untitledSync.markSynced(track) }
            }
            if status != .notSynced {
                Divider()
                Button("Reset Sync Status") { untitledSync.reset(track) }
            }
        } label: {
            Image(systemName: untitledIcon(for: status))
                .foregroundStyle(untitledColor(for: status))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(untitledHelp(for: status))
    }

    private func untitledIcon(for status: UntitledSyncStatus) -> String {
        switch status {
        case .notSynced: return "icloud.slash"
        case .sending: return "icloud.and.arrow.up"
        case .synced: return "icloud.fill"
        case .updateAvailable: return "arrow.triangle.2.circlepath.icloud"
        }
    }

    private func untitledColor(for status: UntitledSyncStatus) -> Color {
        switch status {
        case .synced: return .accentColor
        case .sending, .updateAvailable: return .orange
        case .notSynced: return .secondary
        }
    }

    private func untitledHelp(for status: UntitledSyncStatus) -> String {
        switch status {
        case .notSynced: return "Send latest export to [untitled]"
        case .sending: return "Waiting for [untitled] confirmation"
        case .synced: return "Latest export is marked as on [untitled]"
        case .updateAvailable: return "A newer version is ready for [untitled]"
        }
    }

    private func toolRow(_ tool: ToolLauncher) -> some View {
        HStack(spacing: 10) {
            if tool.isKeyboardMaestroMacro {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tool.path))
                    .resizable().scaledToFit().frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name).lineLimit(1)
                Text(tool.isKeyboardMaestroMacro
                     ? "Keyboard Maestro macro"
                     : tool.url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Launch") { toolLaunchers.launch(tool) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { toolLaunchers.launch(tool) }
        .contextMenu {
            if !tool.isKeyboardMaestroMacro {
                Button("Show in Finder") { toolLaunchers.reveal(tool) }
                Divider()
            }
            Button("Remove", role: .destructive) { toolLaunchers.remove(tool) }
        }
        .overlay(alignment: .bottom) { Divider().padding(.leading, 48) }
    }

    private func emptyState(title: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            if selectedTab == .tools { addToolMenu }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addToolMenu: some View {
        Menu {
            Button("Keyboard Maestro Macro…") {
                isAddingMacro = true
                DispatchQueue.main.async { isMacroNameFocused = true }
            }
            Button("App, File, or Folder…", action: toolLaunchers.addTools)
        } label: {
            Label("Add Tool", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add a producer tool")
    }

    private var macroEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keyboard Maestro Macro")
                .font(.system(size: 13, weight: .semibold))
            TextField("Exact macro name or UID", text: $macroName)
                .textFieldStyle(.roundedBorder)
                .focused($isMacroNameFocused)
                .onSubmit(addMacro)
            Text("Use the UID if more than one macro has the same name.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") {
                    macroName = ""
                    isAddingMacro = false
                }
                Button("Add", action: addMacro)
                    .buttonStyle(.borderedProminent)
                    .disabled(macroName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    private func addMacro() {
        guard !macroName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        toolLaunchers.addKeyboardMaestroMacro(named: macroName)
        macroName = ""
        isAddingMacro = false
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Button(action: store.audioPlayer.togglePlayPause) {
                Image(systemName: store.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.audioPlayer.currentTrack?.displayName ?? "").font(.caption).lineLimit(1)
                PlaybackProgressView(timeline: store.audioPlayer.timeline)
            }
        }
        .padding(10)
    }

    private struct PlaybackProgressView: View {
        @ObservedObject var timeline: PlaybackTimeline

        var body: some View {
            ProgressView(value: timeline.progress).controlSize(.small)
        }
    }

    private var footer: some View {
        HStack {
            Text(selectedTab == .songs ? "\(projects.count) songs" : "\(visibleToolCount) tools")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Open goodvibrations HQ") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            .controlSize(.small)
        }
        .padding(10)
    }
}
