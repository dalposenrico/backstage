import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case ableton = "Ableton Live"
    case shortcuts = "Shortcuts"
    case accounts = "Accounts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .ableton: return "pianokeys"
        case .shortcuts: return "keyboard"
        case .accounts: return "person.crop.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var globalHotkey: GlobalHotkeyManager
    @EnvironmentObject var dragScroll: AbletonDragScrollManager
    @EnvironmentObject var launcherStore: QuickLauncherStore
    @EnvironmentObject var pluginCloser: PluginCloserManager

    @ObservedObject private var clientManager = ClientWorkManager.shared
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    @State private var selectedTab: SettingsTab = .general
    @State private var showingRenameFolderAlert = false
    @State private var renameFolderNameDraft = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)

            abletonTab
                .tabItem { Label("Ableton Live", systemImage: "pianokeys") }
                .tag(SettingsTab.ableton)

            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
        }
        .frame(width: 520)
        .preferredColorScheme(settings.appearanceMode.colorSchemeOverride)
        .alert("Rename Client Work Folder", isPresented: $showingRenameFolderAlert) {
            TextField("Folder Name", text: $renameFolderNameDraft)
            Button("Cancel", role: .cancel) { renameFolderNameDraft = "" }
            Button("Rename") {
                let trimmed = renameFolderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? clientManager.renameClientWorkFolder(to: trimmed)
                }
                renameFolderNameDraft = ""
            }
        } message: {
            Text("Enter a new folder name for your client work. If it exists in the default directory, it will be renamed on disk safely.")
        }
        .onAppear {
            launchAtLogin.refresh()
            settings.refreshAvailableAbletonApps()
            clientManager.refreshDiscoveredClients()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            // Music Library
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Music Folder")
                            .font(.system(size: 13, weight: .semibold))
                        Text(store.rootFolderURL?.path ?? "Not selected")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") {
                        store.selectFolder()
                    }
                    .controlSize(.small)
                }

                HStack {
                    Text("Default project sort")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("", selection: $store.sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            } header: {
                Label("Music Library", systemImage: "folder")
                    .font(.headline)
            }

            // Client Work Directory
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Client Work Folder")
                                    .font(.system(size: 13, weight: .semibold))
                                if clientManager.customClientWorkFolderPath != nil {
                                    Text("CUSTOM")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.accent)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Text("DEFAULT")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                                }
                            }

                            Text(clientManager.clientWorkBaseURL.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Choose Folder…") {
                            clientManager.chooseCustomBaseFolder()
                        }
                        .controlSize(.small)
                    }

                    Text("Where client folders (e.g. Mixing & Mastering work) and their Ableton sets live on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Reveal in Finder") {
                            clientManager.revealInFinder(url: clientManager.clientWorkBaseURL)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.accent)

                        Text("·")
                            .foregroundColor(.secondary)

                        Button("Rename Folder Name…") {
                            renameFolderNameDraft = clientManager.clientWorkFolderName
                            showingRenameFolderAlert = true
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if clientManager.customClientWorkFolderPath != nil {
                            Text("·")
                                .foregroundColor(.secondary)

                            Button("Reset to Default") {
                                clientManager.resetToDefaultBaseFolder()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            } header: {
                Label("Client Work & Mixing/Mastering", systemImage: "person.2")
                    .font(.headline)
            }

            // Cloud Storage & Auto-Offload
            Section {
                Toggle("Auto-offload inactive projects", isOn: $settings.isAutoOffloadEnabled)

                if settings.isAutoOffloadEnabled {
                    HStack {
                        Text("Offload when older than")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $settings.autoOffloadThreshold) {
                            ForEach(AutoOffloadAge.allCases) { age in
                                Text(age.rawValue).tag(age)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatically archives local Ableton project assets (samples, backups, sets) to your Dropbox archive when projects haven't been modified in over \(settings.autoOffloadThreshold.rawValue).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Only projects with at least one audio bounce export are auto-offloaded so you can always audition them offline.")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                let eligibleCount = ProjectOffloadStore.shared.eligibleProjectsForAutoOffload(
                    in: store.projects,
                    threshold: settings.autoOffloadThreshold
                ).count

                HStack {
                    if eligibleCount > 0 {
                        Text("\(eligibleCount) project\(eligibleCount == 1 ? "" : "s") ready to offload")
                            .font(.caption)
                            .foregroundColor(.accent)
                    } else {
                        Text("No projects currently meet the threshold")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Run Auto-Offload Now") {
                        ProjectOffloadStore.shared.performAutoOffload(
                            projects: store.projects,
                            threshold: settings.autoOffloadThreshold
                        )
                    }
                    .controlSize(.small)
                    .disabled(eligibleCount == 0)
                }
            } header: {
                Label("Cloud Storage & Auto-Offload", systemImage: "icloud.and.arrow.up")
                    .font(.headline)
            }

            // Startup
            Section {
                Toggle("Launch goodvibrations HQ at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(launchAtLogin.isChanging)

                if let message = launchAtLogin.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Keeps Quick Access available in the menu bar after you restart your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Startup", systemImage: "power")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Project List Display", selection: $settings.showInlineWaveforms) {
                    Label("Inline Waveforms", systemImage: "waveform").tag(true)
                    Label("Icons & Artwork", systemImage: "photo").tag(false)
                }
                .pickerStyle(.segmented)

                Text("Show inline audio waveforms with quick-play buttons for bounced tracks, like DAWbro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Theme & Project Display", systemImage: "paintbrush")
                    .font(.headline)
            }

            Section {
                HStack {
                    Text("Sidebar width")
                    Spacer()
                    Slider(value: $settings.sidebarWidth, in: 190...440, step: 1)
                        .frame(width: 160)
                    Text("\(Int(settings.sidebarWidth)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            } header: {
                Label("Sidebar Layout", systemImage: "sidebar.left")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    // MARK: - Ableton Live Tab

    private var abletonTab: some View {
        Form {
            Section {
                Picker("Live Application", selection: $settings.selectedAbletonAppPath) {
                    Text("Auto-detect / System Default").tag("")
                    ForEach(settings.availableAbletonApps) { app in
                        Text(app.pickerLabel).tag(app.path)
                    }
                    if !settings.selectedAbletonAppPath.isEmpty && !settings.availableAbletonApps.contains(where: { $0.path == settings.selectedAbletonAppPath }) {
                        Text(settings.currentSelectedAbletonApp?.pickerLabel ?? settings.selectedAbletonAppPath)
                            .tag(settings.selectedAbletonAppPath)
                    }
                }

                HStack {
                    if let app = settings.currentSelectedAbletonApp {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(app.displayName)
                                    .font(.caption.bold())
                                if app.isBeta {
                                    Text("BETA")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundStyle(Color.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                            Text(app.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("Automatic: uses whichever Live app is open or macOS default for .als sets.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Browse…") {
                        settings.browseForAbletonApp()
                    }
                    .controlSize(.small)
                }

                Text("goodvibrations HQ opens project sets, runs export shortcuts, and monitors session status using this version of Ableton Live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Application Selection", systemImage: "pianokeys")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            // Ableton Export Hotkey
            Section {
                Toggle("Enable F1 global hotkey", isOn: $globalHotkey.isEnabled)

                Text("While goodvibrations HQ is running, press **F1** or **⇧⌘E** anywhere (including inside Ableton Live) to auto-version and export the active project.\n\nTip: On keyboards where F1 adjusts display brightness, use **Fn+F1** or **⇧⌘E**.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = globalHotkey.lastResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: result.contains("success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.contains("success") ? .green : .orange)
                            .font(.caption)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            } header: {
                Label("Ableton Export Hotkey", systemImage: "keyboard")
                    .font(.headline)
            }

            // Close Plugin Windows
            Section {
                Toggle("Enable Close Plugin Windows shortcut", isOn: $pluginCloser.isEnabled)

                HStack(spacing: 8) {
                    Text("Shortcut")
                    Spacer()

                    Toggle("⌘ Cmd", isOn: $pluginCloser.useCommand)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    Toggle("⌥ Opt", isOn: $pluginCloser.useOption)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    Toggle("⇧ Shift", isOn: $pluginCloser.useShift)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    Toggle("⌃ Ctrl", isOn: $pluginCloser.useControl)
                        .toggleStyle(.button)
                        .controlSize(.small)

                    TextField("Key", text: $pluginCloser.key)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 34)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Only trigger when Ableton Live is frontmost", isOn: $pluginCloser.onlyWhenAbletonActive)

                Text("Press **\(pluginCloser.shortcutDisplayString)** to close all open floating VST / AU plugin windows in Ableton Live at once. Never closes your Ableton Live set or triggers save dialogs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Close Plugin Windows Now") {
                        pluginCloser.closePluginWindows()
                    }
                    .controlSize(.small)

                    Button("Reset (⌥⌘W)") {
                        pluginCloser.resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if let status = pluginCloser.lastStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Close Plugin Windows", systemImage: "xmark.rectangle.stack")
                    .font(.headline)
            }

            // Drag Navigation
            Section {
                Toggle("Drag-scroll tracks with W and S", isOn: $dragScroll.isEnabled)

                Text("While dragging a track, clip, or sample in Ableton Live (mouse held down), press **W** to scroll up (Page Up) and **S** to scroll down (Page Down). Normal typing in Ableton search and other apps is never interrupted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Ableton Drag Navigation", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.headline)
            }

            // Quick Plugin Launcher
            Section {
                Text("Tap buttons in the floating dock's pop-out tray to trigger your plugin macros or keystrokes directly in Ableton Live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($launcherStore.items) { $item in
                    HStack(spacing: 8) {
                        TextField("Key", text: $item.key)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(width: 34)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.roundedBorder)

                        TextField("Plugin / Action name", text: $item.title)
                            .font(.system(size: 12))
                            .textFieldStyle(.roundedBorder)

                        TextField("Tag", text: Binding(
                            get: { item.category ?? "" },
                            set: { item.category = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)

                        Button {
                            launcherStore.trigger(item)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Test trigger in Ableton")

                        Button {
                            launcherStore.removeItem(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Remove item")
                    }
                }

                HStack {
                    Button("+ Add Action") {
                        let nextNum = String(launcherStore.items.count + 1)
                        launcherStore.addItem(title: "New Action", key: nextNum)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("Reset to Defaults") {
                        launcherStore.resetToDefaults()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } header: {
                Label("Quick Plugin Launcher", systemImage: "bolt.fill")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }

    // MARK: - Accounts Tab

    private var accountsTab: some View {
        Form {
            Section {
                ForEach(StreamingService.allCases, id: \.self) { service in
                    HStack {
                        Label(service.title, systemImage: service.icon)
                        Spacer()
                        Text("Uses provider app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open") { NSWorkspace.shared.open(service.homeURL) }
                            .controlSize(.small)
                    }
                }

                Text("Sign in and out in the official music app. HQ does not claim or store account connection state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Music Streaming Accounts", systemImage: "person.crop.circle")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 6)
    }
}

extension StreamingService: Identifiable {
    var id: String { rawValue }

    var homeURL: URL {
        switch self {
        case .spotify: return URL(string: "https://open.spotify.com")!
        case .appleMusic: return URL(string: "https://music.apple.com")!
        }
    }
}
