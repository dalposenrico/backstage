import SwiftUI

private enum LegacyDefaultsMigration {
    private static let legacyDomain = "com.enricodalpos.demos"
    private static let migrationKey = "didMigrateLegacyDemosDefaults"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        let currentDomain = Bundle.main.bundleIdentifier ?? "com.enricodalpos.goodvibrationshq"
        let currentValues = defaults.persistentDomain(forName: currentDomain) ?? [:]
        let legacyValues = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        for (key, value) in legacyValues where currentValues[key] == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: migrationKey)
    }
}

@main
struct demosApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDiagnostics.self) private var lifecycleDiagnostics
    @StateObject private var store = {
        LegacyDefaultsMigration.run()
        return AppStore()
    }()
    @StateObject private var settings      = SettingsStore()
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var toolLaunchers = ToolLauncherStore()
    @StateObject private var untitledSync = UntitledSyncStore()
    @StateObject private var projectNotes = ProjectNotesStore()
    @StateObject private var references = ReferenceStore()
    @StateObject private var projectProgress = ProjectProgressStore()
    @StateObject private var projectArtwork = ProjectArtworkStore()
    @StateObject private var studioWorkflow = StudioWorkflowStore()
    @StateObject private var collectionColors = CollectionColorStore()
    @StateObject private var projectTodos = ProjectTodoStore()
    @StateObject private var projectMetadata = ProjectMetadataStore()
    @StateObject private var comparisonMarkers = ComparisonMarkerStore()
    @StateObject private var dailyFocus = DailyFocusStore()
    @StateObject private var focusCalendar = FocusCalendarStore()
    @StateObject private var globalHotkey = GlobalHotkeyManager()
    @StateObject private var dragScroll = AbletonDragScrollManager()
    @Environment(\.openWindow) private var openWindow
    @AppStorage(ProjectDockSizing.storageKey) private var projectDockHeight = ProjectDockSizing.defaultHeight

    var body: some Scene {

        // MARK: - Main window
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.audioPlayer)
                .environmentObject(settings)
                .environmentObject(updateChecker)
                .environmentObject(untitledSync)
                .environmentObject(projectNotes)
                .environmentObject(references)
                .environmentObject(projectProgress)
                .environmentObject(projectArtwork)
                .environmentObject(studioWorkflow)
                .environmentObject(collectionColors)
                .environmentObject(projectTodos)
                .environmentObject(projectMetadata)
                .environmentObject(comparisonMarkers)
                .environmentObject(toolLaunchers)
                .environmentObject(dailyFocus)
                .environmentObject(focusCalendar)
                .environmentObject(globalHotkey)
                .environmentObject(dragScroll)
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Playback") {
                Button("Play / Pause")    { store.audioPlayer.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Next Track")      { store.playNext() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Track")  { store.playPrevious() }
                    .keyboardShortcut(.leftArrow,  modifiers: .command)
            }

            CommandMenu("Tools") {
                Button("Ableton Auto-Export") {
                    globalHotkey.triggerExport()
                }
                .keyboardShortcut(.f1, modifiers: [])

                Button("Ableton Auto-Export (Alternative)") {
                    globalHotkey.triggerExport()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Versions (A/B Compare)…") {
                    openWindow(id: "ab-compare")
                    WindowPresenter.showABCompare()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Project Notes…") {
                    openWindow(id: "project-notes")
                    WindowPresenter.showProjectNotes()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("[untitled] Automation…") {
                    openWindow(id: "untitled-automation")
                    WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: false)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Button("Name Generator…") {
                    openWindow(id: "name-generator")
                    WindowPresenter.showNameGenerator(dismissingMenuBarPanel: false)
                }

                Button("Workflow Editor…") {
                    openWindow(id: "studio-companion")
                    WindowPresenter.showWorkflowEditor()
                }

                Divider()

                Button("Focus Timer…") {
                    openWindow(id: "focus-timer")
                    WindowPresenter.showFocusTimer(pinned: dailyFocus.keepsTimerOnTop)
                }

                Button("Focus Planner…") {
                    openWindow(id: "focus-planner")
                    WindowPresenter.showFocusPlanner()
                }

                Divider()

                Button("Ableton Crash Analyzer…") {
                    toolLaunchers.launchAbletonCrashAnalyzer()
                }
            }

            CommandMenu("Project Panel") {
                Button("Increase Project Panel Size") {
                    projectDockHeight = ProjectDockSizing.adjusted(
                        projectDockHeight,
                        by: ProjectDockSizing.keyboardStep
                    )
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Project Panel Size") {
                    projectDockHeight = ProjectDockSizing.adjusted(
                        projectDockHeight,
                        by: -ProjectDockSizing.keyboardStep
                    )
                }
                .keyboardShortcut("-", modifiers: .command)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Open Music Folder…") { store.selectFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Refresh Library")    { Task { await store.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Toggle Appearance") { settings.appearanceMode = settings.appearanceMode.next }
            }
        }

        Window("[untitled] Automation", id: "untitled-automation") {
            UntitledAutomationView()
                .environmentObject(untitledSync)
        }
        .defaultSize(width: 520, height: 500)
        .windowResizability(.contentSize)

        Window("Project Notes", id: "project-notes") {
            ProjectNotesWindow()
                .environmentObject(store)
                .environmentObject(projectNotes)
        }
        .defaultSize(width: 390, height: 430)

        Window("Versions", id: "ab-compare") {
            ABComparisonView()
                .environmentObject(store)
                .environmentObject(store.audioPlayer)
                .environmentObject(references)
                .environmentObject(projectProgress)
                .environmentObject(comparisonMarkers)
        }
        .defaultSize(width: 1120, height: 720)

        Window("Project Artwork", id: "project-artwork") {
            if let project = store.selectedProject {
                ArtworkPickerView(project: project)
                    .environmentObject(projectArtwork)
            }
        }
        .defaultSize(width: 760, height: 620)

        Window("Workflow Editor", id: "studio-companion") {
            WorkflowEditorWindow()
                .environmentObject(studioWorkflow)
        }
        .defaultSize(width: 720, height: 720)

        Window("Name Generator", id: "name-generator") {
            ProjectNameGeneratorView()
        }
        .defaultSize(width: 680, height: 650)

        Window("Focus Timer", id: "focus-timer") {
            FloatingFocusTimerView()
                .environmentObject(store)
                .environmentObject(dailyFocus)
        }
        .defaultSize(width: 292, height: 500)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Focus Planner", id: "focus-planner") {
            FocusPlannerView()
                .environmentObject(store)
                .environmentObject(dailyFocus)
                .environmentObject(focusCalendar)
                .environmentObject(projectTodos)
        }
        .defaultSize(width: 1180, height: 700)

        // MARK: - Settings (⌘,)
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(globalHotkey)
                .environmentObject(dragScroll)
        }

        // MARK: - Menu bar extra
        MenuBarExtra {
            FavouritesMenuView()
                .environmentObject(store)
                .environmentObject(toolLaunchers)
                .environmentObject(untitledSync)
                .environmentObject(projectNotes)
                .environmentObject(references)
                .environmentObject(studioWorkflow)
                .environmentObject(globalHotkey)
                .environmentObject(dailyFocus)
        } label: {
            Image(systemName: "music.note")
        }
        .menuBarExtraStyle(.window)

    }
}
