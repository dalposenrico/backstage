import SwiftUI

@main
struct demosApp: App {
    @StateObject private var store         = AppStore()
    @StateObject private var settings      = SettingsStore()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {

        // MARK: - Main window
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.audioPlayer)
                .environmentObject(settings)
                .environmentObject(updateChecker)
        }
        .defaultSize(width: 960, height: 620)
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

            CommandGroup(after: .windowArrangement) {
                Button("Open Music Folder…") { store.selectFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Refresh Library")    { Task { await store.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Toggle Appearance") { settings.appearanceMode = settings.appearanceMode.next }
            }
        }

        // MARK: - Settings (⌘,)
        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}
